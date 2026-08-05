"""部队场景：3 窗口 + 单体详情模式 + N 新建 + 移动/攻击/换位（M7 完整实现）。

按 操作逻辑.md（部队界面）：
- 3 个左右排列窗口。W1=部队名称列表（数字 1/2/4 筛选 我方/敌方/全部，3=驻军），
  W2=部队操作（移动/编辑/解散），W3=部队规模 + 九宫格单位。
- 方向键右逐层进入：W1→W2→W3；方向键左回退。非本方部队 W2 不可操作。
- 焦点在 W3 单位上时：W1 变为单位详情，W2 变为单位操作（换位/上场/下场/编辑装备）。
- 移动：W2 移动 → W3 列出距离 1 的邻接地点，若该地点有敌方非驻军部队则标"攻击"，
  回车确认 → action_move_attack。
- 换位：W2 换位 → W3 标记空/占位，回车交换（直接 grid 交换，业务层无接口）。
- N 新建部队：仅在 W1 且焦点在最左侧窗口时；找该据点无部队英雄 → 建队+任队长。
- 上场/下场/编辑装备：业务层暂无支持 → 占位警告（计划中标注缺口）。

注意：可由 StrongholdScene 通过 PUSH(ArmyScene(), {"army_id":...}) 委托进入，
聚焦到指定部队。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, fill_rect
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from .. import actions as g_actions
from pydemo.game.army import ROWS, ROW_CN, row_of, col_of, GRID_SIZE
from pydemo.game.unit import ATTR_CN, TAG_CN

# 3 个窗口矩形（x, y, w, h）。外框 (0,0,100,30)，y=3..27。
W1 = (1, 3, 33, 25)
W2 = (34, 3, 32, 25)
W3 = (66, 3, 33, 25)

FILTER_LABELS = ["我方", "敌方", "驻军", "全部"]


class ArmyScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.filter = 0          # 0=我方 1=敌方 2=驻军 3=全部
        self.focus = 0           # W1 当前列表焦点
        self.list_scroll = 0
        self.level = 0           # 0=W1 1=W2 2=W3
        self.w2_focus = 0        # W2 操作焦点（army 模式：0移动1编辑2解散；unit 模式：换位/上场/下场/装备）
        self.unit_slot = None   # W3 单位槽位（int 0..8）或 None
        self.in_move = False    # 移动模式：W3 列邻接
        self.in_swap = False     # 换位模式：W3 标空位
        self._w2_rect = W2
        self._w3_rect = W3
        self._w1_rect = W1

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        if isinstance(params, dict) and params.get("army_id"):
            self._focus_to_army(params["army_id"])

    def on_return(self, value: Any) -> None:
        # 移动/战斗后部队可能消失，夹住焦点
        armies = self._filtered_armies()
        if armies and self.focus >= len(armies):
            self.focus = max(0, len(armies) - 1)
        if self.in_move:
            self.in_move = False

    # ---- 数据查询 ----
    def _all_armies(self):
        return list(ctrl_mod.ctrl.g.armies.values())

    def _filtered_armies(self):
        g = ctrl_mod.ctrl.g
        pid = g.player_id
        if self.filter == 0:    # 我方
            return [a for a in self._all_armies() if a.owner == pid and not a.is_garrison]
        if self.filter == 1:    # 敌方
            return [a for a in self._all_armies() if a.owner != pid and not a.is_garrison and a.owner is not None]
        if self.filter == 2:    # 驻军
            return [a for a in self._all_armies() if a.is_garrison]
        return [a for a in self._all_armies()]

    def _selected_army(self):
        armies = self._filtered_armies()
        return armies[self.focus % len(armies)] if armies else None

    def _is_ours(self, army) -> bool:
        return army is not None and army.owner == ctrl_mod.ctrl.g.player_id and not army.is_garrison

    def _army_ops(self) -> list[str]:
        return ["移动", "编辑", "解散"]

    def _unit_ops(self) -> list[str]:
        return ["换位", "上场", "下场", "编辑装备"]

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        # 筛选（任意层可用）
        if a == g_actions.FILTER_1:
            self.filter = 0; self.focus = 0; self.in_move = False; self.in_swap = False
            self.unit_slot = None; return NONE()
        if a == g_actions.FILTER_2:
            self.filter = 1; self.focus = 0; self.in_move = False; self.in_swap = False
            self.unit_slot = None; return NONE()
        if a == g_actions.FILTER_3:
            self.filter = 2; self.focus = 0; self.in_move = False; self.in_swap = False
            self.unit_slot = None; return NONE()
        if a == g_actions.FILTER_4:
            self.filter = 3; self.focus = 0; self.in_move = False; self.in_swap = False
            self.unit_slot = None; return NONE()

        # N 新建：仅 W1 且本方据点英雄可用
        if a == g_actions.NEW_ARMY and self.level == 0:
            return self._new_army()

        if a == actions.BACK:
            if self.in_move or self.in_swap:
                self.in_move = False; self.in_swap = False
                return NONE()
            if self.unit_slot is not None:
                self.unit_slot = None
                return NONE()
            if self.level > 0:
                self.level -= 1
                if self.level == 0:
                    self.unit_slot = None
                return NONE()
            return POP()

        if a == actions.LEFT:
            if self.in_move or self.in_swap:
                self.in_move = False; self.in_swap = False
                return NONE()
            if self.unit_slot is not None:
                self.unit_slot = None
                return NONE()
            if self.level > 0:
                self.level -= 1
                if self.level == 0:
                    self.unit_slot = None
            return NONE()

        if a == actions.RIGHT:
            return self._go_right()

        if a in (actions.UP, actions.DOWN):
            self._move_vertical(a)
            return NONE()

        if a == actions.CONFIRM:
            return self._activate()
        return NONE()

    def _move_vertical(self, a: str) -> None:
        delta = -1 if a == actions.UP else 1
        if self.in_move:
            nbrs = self._neighbors_of_current()
            if nbrs:
                self._move_focus = (getattr(self, "_move_focus", 0) + delta) % len(nbrs)
            return
        if self.in_swap:
            empties = self._empty_slots_of_current()
            if empties:
                self._swap_focus = (getattr(self, "_swap_focus", 0) + delta) % len(empties)
            return
        if self.level == 0:
            n = len(self._filtered_armies())
            if n:
                self.focus = (self.focus + delta) % n
            return
        if self.level == 1:
            # W2：army 模式 3 项 / unit 模式 4 项
            ops = self._unit_ops() if self.unit_slot is not None else self._army_ops()
            if ops:
                self.w2_focus = (self.w2_focus + delta) % len(ops)
            return
        if self.level == 2:
            # W3：在占位槽位间移动焦点，进入 unit 模式
            army = self._selected_army()
            if army is None:
                return
            g = ctrl_mod.ctrl.g
            occ = [i for i, uid in enumerate(army.grid) if uid and g.unit_index[uid].alive]
            if not occ:
                return
            cur = self.unit_slot if self.unit_slot is not None else occ[0]
            try:
                idx = occ.index(cur)
            except ValueError:
                idx = 0
            idx = (idx + delta) % len(occ)
            self.unit_slot = occ[idx]
            return

    def _go_right(self) -> SceneResult:
        if self.level == 0:
            self.level = 1
            self.w2_focus = 0
            self.in_move = False
            self.in_swap = False
            return NONE()
        if self.level == 1:
            # → 在 W2 上把焦点移到 W3 阵型；执行操作请用回车（_activate/_w2_activate）
            self.level = 2
            return NONE()
        if self.level == 2:
            # W3 单位上按 → 进入 unit 模式（设 unit_slot 已由上下选中）
            if self.unit_slot is None:
                self._move_vertical(actions.DOWN)
            # 切到 W2 unit 模式
            self.level = 1
            self.w2_focus = 0
            return NONE()
        return NONE()

    def _w2_activate(self) -> SceneResult:
        army = self._selected_army()
        if army is None:
            return NONE()
        if self.unit_slot is not None:
            # unit 模式
            ops = self._unit_ops()
            op = ops[self.w2_focus % len(ops)]
            if op == "换位":
                self.in_swap = True
                self._swap_focus = 0
                self.level = 2
                return NONE()
            if op == "上场":
                log.push("上场：业务层暂无离场概念（占位）", warn=True)
                return NONE()
            if op == "下场":
                log.push("下场：业务层暂无离场概念（占位）", warn=True)
                return NONE()
            if op == "编辑装备":
                log.push("编辑装备：业务层暂未开放（占位）", warn=True)
                return NONE()
            return NONE()
        # army 模式
        if not self._is_ours(army):
            log.push("非本方部队，不可操作", warn=True)
            return NONE()
        ops = self._army_ops()
        op = ops[self.w2_focus % len(ops)]
        if op == "移动":
            if army.has_acted_this_turn:
                log.push("本部队本回合已行动", warn=True)
                return NONE()
            self.in_move = True
            self._move_focus = 0
            self.level = 2
            return NONE()
        if op == "编辑":
            log.push("部队编辑：业务层暂未开放（占位）", warn=True)
            return NONE()
        if op == "解散":
            return self._disband(army)
        return NONE()

    def _activate(self) -> SceneResult:
        """回车：W1/W2 进入下一层或执行；W3 单位→进 unit 模式 / 移动换位确认。"""
        if self.in_move:
            return self._confirm_move()
        if self.in_swap:
            return self._confirm_swap()
        if self.level == 0:
            self.level = 1
            self.w2_focus = 0
            return NONE()
        if self.level == 1:
            return self._w2_activate()
        if self.level == 2:
            # 选中单位进 unit 模式
            army = self._selected_army()
            if army is None:
                return NONE()
            if self.unit_slot is None:
                self._move_vertical(actions.DOWN)
            self.level = 1
            self.w2_focus = 0
            return NONE()
        return NONE()

    # ---- 移动 ----
    def _neighbors_of_current(self):
        g = ctrl_mod.ctrl.g
        army = self._selected_army()
        if army is None:
            return []
        nbrs = g.map.neighbors(army.node_id)
        out = []
        for nid in nbrs:
            has_enemy = any(a.node_id == nid and a.owner not in (None, army.owner)
                            and not a.is_garrison and not a.is_wiped(g.unit_index)
                            for a in g.armies.values())
            target_sh = g.map.strongholds.get(nid)
            is_siege = target_sh and target_sh.owner not in (None, army.owner)
            out.append((nid, has_enemy or is_siege))
        return out

    def _confirm_move(self) -> SceneResult:
        g = ctrl_mod.ctrl.g
        army = self._selected_army()
        if army is None:
            self.in_move = False
            return NONE()
        nbrs = self._neighbors_of_current()
        if not nbrs:
            self.in_move = False
            return NONE()
        idx = getattr(self, "_move_focus", 0) % len(nbrs)
        nid, _is_attack = nbrs[idx]
        msg = g.action_move_attack(army.owner, army.id, nid)
        log.push(msg)
        self.in_move = False
        # 移动后若该部队全灭（攻方全灭被清理），夹住焦点
        if army.id not in g.armies:
            armies = self._filtered_armies()
            if armies and self.focus >= len(armies):
                self.focus = max(0, len(armies) - 1)
            self.level = 0
        return NONE()

    # ---- 换位 ----
    def _empty_slots_of_current(self):
        army = self._selected_army()
        if army is None:
            return []
        return [i for i, uid in enumerate(army.grid) if uid is None]

    def _confirm_swap(self) -> SceneResult:
        army = self._selected_army()
        if army is None or self.unit_slot is None:
            self.in_swap = False
            return NONE()
        empties = self._empty_slots_of_current()
        if not empties:
            log.push("部队已无空位", warn=True)
            self.in_swap = False
            return NONE()
        idx = getattr(self, "_swap_focus", 0) % len(empties)
        target = empties[idx]
        # 直接交换 grid 槽位
        army.grid[self.unit_slot], army.grid[target] = army.grid[target], army.grid[self.unit_slot]
        self.unit_slot = target
        log.push(f"已换位至 {ROW_CN[row_of(target)]}排{col_of(target)+1}列")
        self.in_swap = False
        return NONE()

    def _disband(self, army) -> SceneResult:
        g = ctrl_mod.ctrl.g
        name = army.name
        g.disband_army(army)
        log.push(f"已解散 {name}")
        armies = self._filtered_armies()
        if armies and self.focus >= len(armies):
            self.focus = max(0, len(armies) - 1)
        self.level = 0
        self.unit_slot = None
        return NONE()

    def _new_army(self) -> SceneResult:
        g = ctrl_mod.ctrl.g
        army = self._selected_army()
        node_id = army.node_id if army else None
        # 若没选中部队，默认用玩家首都
        if node_id is None:
            player = ctrl_mod.ctrl.player()
            node_id = player.capital_id
        if node_id is None:
            log.push("无可用的建队据点", warn=True)
            return NONE()
        # 找该据点无部队的英雄
        hero = None
        for uid in ctrl_mod.ctrl.player().hero_ids:
            u = g.unit_index.get(uid)
            if u and u.is_hero and u.alive and u.node_id == node_id and u.army_id is None:
                hero = u
                break
        if hero is None:
            log.push(f"{g.map.node_name(node_id)} 无可用英雄任队长", warn=True)
            return NONE()
        new_army = g.create_army(g.player_id, node_id, f"{hero.name}的部队")
        ok = g.set_captain(new_army, hero)
        if not ok:
            g.disband_army(new_army)
            log.push(f"建队失败：{hero.name} 无法任队长", warn=True)
            return NONE()
        log.push(f"新建部队 {new_army.name}（队长 {hero.name}）驻于 {g.map.node_name(node_id)}")
        # 切到该部队
        self.filter = 0
        armies = self._filtered_armies()
        for i, a in enumerate(armies):
            if a.id == new_army.id:
                self.focus = i
                break
        return NONE()

    def _focus_to_army(self, army_id: str) -> None:
        # 先在"全部"里找，再尝试切到合适 filter
        self.filter = 3
        for i, a in enumerate(self._filtered_armies()):
            if a.id == army_id:
                self.focus = i
                return
        # 退回我方
        self.filter = 0
        for i, a in enumerate(self._filtered_armies()):
            if a.id == army_id:
                self.focus = i
                return

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="部队一栏")
        # 筛选行 y=1
        self._render_filter_row(buf, w)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        self._render_w1(buf)
        self._render_w2(buf)
        self._render_w3(buf)
        # 图例 y=28
        buf.put_text(2, 28, "1我方 2敌方 3驻军 4全部  N新建(仅W1)  →进入 ←回退  回车确认",
                     theme.DIM, theme.BG)

    def _render_filter_row(self, buf: FrameBuffer, w: int) -> None:
        x = 2
        for i, label in enumerate(FILTER_LABELS):
            tag = f"{i+1} {label}"
            fg = theme.ACCENT if i == self.filter else theme.DIM
            if i > 0:
                x = buf.put_text(x, 1, "   ", theme.DIM, theme.BG)
            x = buf.put_text(x, 1, tag, fg, theme.BG)

    def _render_w1(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W1
        active = self.level == 0 and self.unit_slot is None
        border = theme.ACCENT if active else theme.BORDER
        title = "部队列表"
        # unit 模式：W1 显示单位详情标题
        if self.unit_slot is not None:
            title = "单位详情"
        draw_box(buf, x, y, ww, hh, title=title, fg=border)
        if self.unit_slot is not None:
            self._render_unit_detail(buf, x, y, ww, hh)
            return
        armies = self._filtered_armies()
        if not armies:
            buf.put_text(x + 1, y + 1, "（无部队）", theme.DIM, theme.BG)
            return
        start = self.list_scroll
        end = min(len(armies), start + hh - 2)
        for i in range(start, end):
            ry = y + 1 + (i - start)
            if ry >= y + hh - 1:
                break
            a = armies[i]
            ours = a.owner == ctrl_mod.ctrl.g.player_id
            fg = theme.ACCENT2 if ours else (theme.WARN if a.owner and a.owner != ctrl_mod.ctrl.g.player_id else theme.DIM)
            label = a.name
            if a.is_garrison:
                label += "(驻军)"
            if a.is_wiped(ctrl_mod.ctrl.g.unit_index):
                label += "(全灭)"
            self._draw_row(buf, x, ry, ww, label, fg, i, self.focus, active)
        if len(armies) > hh - 2:
            buf.put_text(x + ww - 8, y, f"({self.focus+1}/{len(armies)})", theme.DIM, theme.BG)

    def _render_unit_detail(self, buf: FrameBuffer, x: int, y: int, ww: int, hh: int) -> None:
        army = self._selected_army()
        if army is None or self.unit_slot is None:
            buf.put_text(x + 1, y + 1, "（无单位）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        uid = army.grid[self.unit_slot]
        u = g.unit_index.get(uid) if uid else None
        if u is None:
            buf.put_text(x + 1, y + 1, "（空位）", theme.DIM, theme.BG)
            return
        ry = y + 1
        buf.put_text(x + 1, ry, u.name, theme.HEADING, theme.BG); ry += 1
        tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(u.tags))
        buf.put_text(x + 1, ry, f"词条 {tagstr}", theme.DIM, theme.BG); ry += 1
        buf.put_text(x + 1, ry, f"英雄 {'是' if u.is_hero else '否'}", theme.DIM, theme.BG); ry += 1
        ry += 1
        buf.put_text(x + 1, ry, "属性", theme.ACCENT, theme.BG); ry += 1
        attrs = ["hp", "p_atk", "m_atk", "p_def", "m_def", "speed", "acc", "eva", "block", "crit", "will"]
        for attr in attrs:
            if ry >= y + hh - 1:
                break
            val = u.base.get(attr, 0)
            buf.put_text(x + 1, ry, f"{ATTR_CN.get(attr, attr)}: {int(val)}", theme.FG, theme.BG)
            if attr == "hp":
                buf.put_text(x + 18, ry, f"({int(u.cur_hp)}/{int(u.base.get('hp',1))})", theme.DIM, theme.BG)
            ry += 1

    def _render_w2(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W2
        active = self.level == 1
        border = theme.ACCENT if active else theme.BORDER
        title = "单位操作" if self.unit_slot is not None else "部队操作"
        draw_box(buf, x, y, ww, hh, title=title, fg=border)
        if self.level == 0 and self.unit_slot is None:
            buf.put_text(x + 1, y + 1, "（选中部队按 →）", theme.DIM, theme.BG)
            return
        army = self._selected_army()
        if army is None:
            return
        if self.unit_slot is not None:
            ops = self._unit_ops()
        else:
            ops = self._army_ops()
        for i, op in enumerate(ops):
            ry = y + 1 + i
            if ry >= y + hh - 1:
                break
            self._draw_row(buf, x, ry, ww, op, theme.FG, i, self.w2_focus, active)
        # 非本方提示
        if self.unit_slot is None and not self._is_ours(army) and self.level >= 1:
            buf.put_text(x + 1, y + hh - 2, "（非本方部队，仅可查看）", theme.WARN, theme.BG)

    def _render_w3(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W3
        active = self.level == 2
        border = theme.ACCENT if active else theme.BORDER
        title = "阵型"
        if self.in_move:
            title = "移动·选择目的地"
        elif self.in_swap:
            title = "换位·选择空位"
        draw_box(buf, x, y, ww, hh, title=title, fg=border)
        army = self._selected_army()
        if army is None:
            buf.put_text(x + 1, y + 1, "（无部队）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        # 头部：规模/补给/位置
        size = army.size(g.unit_index)
        mx = army.max_size(g.unit_index)
        buf.put_text(x + 1, y + 1, f"规模 {size}/{mx}", theme.HEADING, theme.BG)
        buf.put_text(x + 14, y + 1, f"补给 {army.supply}/{army.supply_max}", theme.DIM, theme.BG)
        buf.put_text(x + 1, y + 2, f"位置 {g.map.node_name(army.node_id)}", theme.DIM, theme.BG)
        if army.has_acted_this_turn:
            buf.put_text(x + 18, y + 2, "(已行动)", theme.WARN, theme.BG)

        if self.in_move:
            self._render_move_targets(buf, x, y, ww, hh, army)
            return
        if self.in_swap:
            self._render_swap_targets(buf, x, y, ww, hh, army)
            return

        # 九宫格
        gx = x + 4
        gy = y + 5
        # 列头
        for c in range(3):
            buf.put_text(gx + c * 8, gy - 1, f"{c+1}列", theme.DIM, theme.BG)
        for r in range(3):
            buf.put_text(gx - 3, gy + r * 2, ROW_CN[ROWS[r]] + "排", theme.DIM, theme.BG)
            for c in range(3):
                slot = r * 3 + c
                cx = gx + c * 8
                cy = gy + r * 2
                uid = army.grid[slot]
                if uid and uid in g.unit_index:
                    u = g.unit_index[uid]
                    name = u.name[:3]
                    is_focus = (self.level == 2 and self.unit_slot == slot)
                    if is_focus:
                        buf.fill_rect(cx - 1, cy, 7, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                        buf.put_text(cx, cy, name, theme.SELECTED_FG, theme.SELECTED_BG)
                    else:
                        buf.put_text(cx, cy, name, theme.FG, theme.BG)
                else:
                    buf.put_text(cx, cy, "·", theme.DIM, theme.BG)

    def _render_move_targets(self, buf: FrameBuffer, x: int, y: int, ww: int, hh: int, army) -> None:
        nbrs = self._neighbors_of_current()
        if not nbrs:
            buf.put_text(x + 1, y + 4, "（无可移动的邻接地点）", theme.WARN, theme.BG)
            return
        idx = getattr(self, "_move_focus", 0) % len(nbrs)
        g = ctrl_mod.ctrl.g
        for i, (nid, is_attack) in enumerate(nbrs):
            ry = y + 4 + i
            if ry >= y + hh - 1:
                break
            name = g.map.node_name(nid)
            marker = " [攻击]" if is_attack else ""
            label = f"→ {name}{marker}"
            fg = theme.WARN if is_attack else theme.ACCENT2
            self._draw_row(buf, x, ry, ww, label, fg, i, idx, True)

    def _render_swap_targets(self, buf: FrameBuffer, x: int, y: int, ww: int, hh: int, army) -> None:
        empties = self._empty_slots_of_current()
        if not empties:
            buf.put_text(x + 1, y + 4, "（部队已无空位）", theme.WARN, theme.BG)
            return
        idx = getattr(self, "_swap_focus", 0) % len(empties)
        for i, slot in enumerate(empties):
            ry = y + 4 + i
            if ry >= y + hh - 1:
                break
            label = f"{ROW_CN[row_of(slot)]}排{col_of(slot)+1}列 (空位)"
            self._draw_row(buf, x, ry, ww, label, theme.ACCENT2, i, idx, True)

    def _draw_row(self, buf: FrameBuffer, x: int, y: int, ww: int, label: str,
                  fg: int, idx: int, focus_idx: int, active: bool) -> None:
        inner_w = ww - 2
        if idx == focus_idx and active:
            buf.fill_rect(x + 1, y, inner_w, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
            buf.put_text(x + 1, y, "▶", theme.ACCENT2, theme.SELECTED_BG)
            text = label
            if text_width(text) > inner_w - 2:
                text = _truncate(text, inner_w - 3)
            buf.put_text(x + 3, y, text, theme.SELECTED_FG, theme.SELECTED_BG)
        else:
            buf.put_text(x + 1, y, "  ", theme.DIM, theme.BG)
            text = label
            if text_width(text) > inner_w - 2:
                text = _truncate(text, inner_w - 3)
            buf.put_text(x + 3, y, text, fg, theme.BG)

    def get_hints(self) -> list[str]:
        hints = ["1-4 筛选", "↑↓ 切换", "→ 进入", "← 回退", "回车 确认"]
        if self.level == 0:
            hints.append("N 新建")
        hints.append("ESC 返回")
        return hints


def _truncate(text: str, max_w: int) -> str:
    if text_width(text) <= max_w:
        return text
    out = ""; w = 0
    for ch in text:
        from pyconsole.io.width import char_width
        cw = char_width(ch)
        if w + cw > max_w - 1:
            break
        out += ch; w += cw
    return out + "…"
