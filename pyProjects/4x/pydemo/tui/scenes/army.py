"""部队场景：3 窗口 + 九宫格编辑（§5）+ N 新建 + 移动/攻击。

按 操作逻辑.md（部队界面）+ 修正稿1.md §5：
- 3 个左右排列窗口。W1=部队名称列表（数字 1/2/4 筛选 我方/敌方/全部，3=驻军），
  W2=部队操作 / 单元格操作，W3=部队规模 + 九宫格单位。
- 方向键右逐层进入：W1→W2→W3；方向键左回退。非本方/驻军部队 W2 不可操作。
- §5：在第三个窗口（W3 九宫格），上下左右控制选择九宫格的位置（含空格），
  空格进入该格的详细操作（W1 变为该格单位详情，W2 列出可用操作）：
    · 单位格 → [移动, 下场, 编辑装备]
      移动：再在九宫格选目标格，回车确认；目标为空=移过去，目标为单位=换位。
      下场 → action_discharge（部队在己方据点内则冷却 0、否则 5 回合；队长下场可能解散部队）。
      编辑装备 → PUSH(UnitScene(), {"unit_id":...}) 委托给单位场景。
    · 空格 → [上场]
      上场 → 列待命·可用单位，回车 action_deploy（部队须在己方据点）。
- 部队级操作（W2 非单元格模式）：移动（整支部队在地图邻接地点移动/攻击）、
  编辑（进入 W3 九宫格编辑阵型）、解散。
  操作逻辑.md §7.3：焦点在 W2（非单元格模式）时方向键右不再进入 W3，
  必须选中"编辑"并按回车才进入右侧九宫格焦点。
- N 新建部队：仅 W1 且本方据点英雄可用；阵营级待命·可用英雄任队长（ADR-0005）。

注意：可由 StrongholdScene 通过 PUSH(ArmyScene(), {"army_id":...}) 委托进入，
聚焦到指定部队。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, PUSH, POP, NONE
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
        self.w2_focus = 0        # W2 操作焦点
        self.grid_cursor = 0     # W3 九宫格光标 0..8（含空格）
        self.cell_mode = False   # True=W1 显示该格详情、W2 显示该格操作（§5 空格进入）
        self.in_move = False     # 部队级地图移动子模式（整支部队移动/攻击）
        self._move_focus = 0
        self.in_cell_move = False  # §5 单位格"移动"子模式：选目标格（空=移动/占=换位）
        self._cell_move_target = 0
        self.in_deploy = False   # §5 空格"上场"子模式：列待命·可用单位
        self._deploy_focus = 0
        self._deploy_scroll = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.cell_mode = False
        self.grid_cursor = 0
        self.in_move = False
        self.in_cell_move = False
        self.in_deploy = False
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

    def _cell_ops(self) -> list[str]:
        """单元格操作：单位格→[移动,下场,编辑装备]；空格→[上场]（§5）。"""
        army = self._selected_army()
        if army is None:
            return []
        uid = army.grid[self.grid_cursor]
        if uid and uid in ctrl_mod.ctrl.g.unit_index and ctrl_mod.ctrl.g.unit_index[uid].alive:
            return ["移动", "下场", "编辑装备"]
        return ["上场"]

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        # 筛选（任意层可用）：重置所有子模式与单元格模式
        if a == g_actions.FILTER_1:
            return self._set_filter(0)
        if a == g_actions.FILTER_2:
            return self._set_filter(1)
        if a == g_actions.FILTER_3:
            return self._set_filter(2)
        if a == g_actions.FILTER_4:
            return self._set_filter(3)

        # N 新建：仅 W1（level 0、非单元格模式）
        if a == g_actions.NEW_ARMY and self.level == 0 and not self.cell_mode:
            return self._new_army()

        # 子模式优先消费方向/确认/返回
        if self.in_move:
            return self._handle_move_mode(a)
        if self.in_cell_move:
            return self._handle_cell_move_mode(a)
        if self.in_deploy:
            return self._handle_deploy_mode(a)

        # §5：W3 九宫格浏览（level 2、非单元格模式）——上下左右移光标，空格进详情
        if self.level == 2 and not self.cell_mode:
            if a in (actions.UP, actions.DOWN, actions.LEFT, actions.RIGHT):
                self._move_grid_cursor(a)
                return NONE()
            if a in (actions.SELECT, actions.CONFIRM):
                self._enter_cell_mode()
                return NONE()
            if a == actions.RIGHT:
                self._enter_cell_mode()
                return NONE()
            if a == actions.BACK:
                self.level = 1
                self.cell_mode = False
                return NONE()
            return NONE()

        if a == actions.BACK:
            return self._back()
        if a == actions.LEFT:
            return self._left()
        if a == actions.RIGHT:
            return self._go_right()
        if a in (actions.UP, actions.DOWN):
            self._move_vertical(a)
            return NONE()
        if a == actions.CONFIRM:
            return self._activate()
        if a == actions.SELECT:
            # 单元格模式时空格无特殊含义；其余层忽略（进入由 → 负责）
            return NONE()
        return NONE()

    def _set_filter(self, idx: int) -> SceneResult:
        self.filter = idx
        self.focus = 0
        self.cell_mode = False
        self.grid_cursor = 0
        self.in_move = False
        self.in_cell_move = False
        self.in_deploy = False
        return NONE()

    def _back(self) -> SceneResult:
        if self.cell_mode:
            self.cell_mode = False
            self.level = 2
            return NONE()
        if self.level > 0:
            self.level -= 1
            if self.level == 0:
                self.cell_mode = False
            return NONE()
        return POP()

    def _left(self) -> SceneResult:
        # LEFT 与 BACK 同样回退；但不 POP（level 0 时无动作）
        if self.cell_mode:
            self.cell_mode = False
            self.level = 2
            return NONE()
        if self.level > 0:
            self.level -= 1
            if self.level == 0:
                self.cell_mode = False
        return NONE()

    def _go_right(self) -> SceneResult:
        if self.level == 0:
            self.level = 1
            self.w2_focus = 0
            self.cell_mode = False
            return NONE()
        if self.level == 1:
            if self.cell_mode:
                # 单元格模式 → 退回九宫格浏览
                self.cell_mode = False
                self.level = 2
            # 操作逻辑.md §7.3:部队级模式(W2 非单元格)方向键右不再进入 W3。
            # 必须在 W2 选中"编辑"并按回车(_w2_activate)才进入 W3 九宫格焦点。
            return NONE()
        # level 2：进入单元格详情
        self._enter_cell_mode()
        return NONE()

    def _move_vertical(self, a: str) -> None:
        delta = -1 if a == actions.UP else 1
        if self.level == 0:
            n = len(self._filtered_armies())
            if n:
                self.focus = (self.focus + delta) % n
            return
        if self.level == 1:
            ops = self._cell_ops() if self.cell_mode else self._army_ops()
            if ops:
                self.w2_focus = (self.w2_focus + delta) % len(ops)
            return

    def _move_grid_cursor(self, a: str) -> None:
        row = self.grid_cursor // 3
        col = self.grid_cursor % 3
        if a == actions.UP:
            row = (row - 1) % 3
        elif a == actions.DOWN:
            row = (row + 1) % 3
        elif a == actions.LEFT:
            col = (col - 1) % 3
        elif a == actions.RIGHT:
            col = (col + 1) % 3
        self.grid_cursor = row * 3 + col

    def _enter_cell_mode(self) -> None:
        army = self._selected_army()
        if army is None:
            return
        self.cell_mode = True
        self.level = 1
        self.w2_focus = 0

    def _activate(self) -> SceneResult:
        """回车：W1→W2；W2 执行操作；W3 九宫格→进单元格详情。"""
        if self.level == 0:
            self.level = 1
            self.w2_focus = 0
            self.cell_mode = False
            return NONE()
        if self.level == 1:
            return self._w2_activate()
        # level 2：进入单元格详情
        self._enter_cell_mode()
        return NONE()

    def _w2_activate(self) -> SceneResult:
        army = self._selected_army()
        if army is None:
            return NONE()
        if self.cell_mode:
            return self._activate_cell_op(army)
        # 部队级操作
        if not self._is_ours(army):
            log.push("非本方/驻军部队，不可操作", warn=True)
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
            # 操作逻辑.md §7.4:部队级"编辑"按回车 → 进入 W3 九宫格焦点(level 2,非单元格),
            # 供玩家上下左右浏览九宫格、空格进单元格操作。
            self.level = 2
            self.cell_mode = False
            self.grid_cursor = 0
            return NONE()
        if op == "解散":
            return self._disband(army)
        return NONE()

    def _activate_cell_op(self, army) -> SceneResult:
        """单元格操作（§5）：移动/下场/编辑装备（单位格）；上场（空格）。"""
        if not self._is_ours(army):
            log.push("非本方/驻军部队，不可编辑", warn=True)
            return NONE()
        ops = self._cell_ops()
        if not ops:
            return NONE()
        op = ops[self.w2_focus % len(ops)]
        uid = army.grid[self.grid_cursor]
        g = ctrl_mod.ctrl.g
        if op == "移动":            # 单位格
            self.in_cell_move = True
            self._cell_move_target = self.grid_cursor
            self.level = 2
            return NONE()
        if op == "下场":
            msg = g.action_discharge(g.player_id, army.id, uid)
            ok = not msg.startswith("失败")
            log.push(msg, warn=not ok)
            if army.id not in g.armies:
                # 队长下场且无接任 → 部队已解散
                armies = self._filtered_armies()
                if armies and self.focus >= len(armies):
                    self.focus = max(0, len(armies) - 1)
                self.level = 0
                self.cell_mode = False
            else:
                self.cell_mode = False
                self.level = 2
            return NONE()
        if op == "编辑装备":
            from .unit import UnitScene
            return PUSH(UnitScene(), {"unit_id": uid})
        if op == "上场":            # 空格
            player = ctrl_mod.ctrl.player()
            if army.node_id not in player.stronghold_ids:
                log.push("部队不在己方据点，无法上场", warn=True)
                return NONE()
            avail = player.standby_available_ids()
            if not avail:
                log.push("无待命·可用单位可上场", warn=True)
                return NONE()
            self.in_deploy = True
            self._deploy_focus = 0
            self._deploy_scroll = 0
            self.level = 2
            return NONE()
        return NONE()

    # ---- 部队级地图移动子模式 ----
    def _handle_move_mode(self, a: str) -> SceneResult:
        if a == actions.BACK:
            self.in_move = False
            return NONE()
        if a in (actions.UP, actions.DOWN):
            nbrs = self._neighbors_of_current()
            if nbrs:
                delta = -1 if a == actions.UP else 1
                self._move_focus = (self._move_focus + delta) % len(nbrs)
            return NONE()
        if a == actions.CONFIRM:
            return self._confirm_move()
        return NONE()

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
        idx = self._move_focus % len(nbrs)
        nid, _is_attack = nbrs[idx]
        msg = g.action_move_attack(army.owner, army.id, nid)
        log.push(msg)
        self.in_move = False
        if army.id not in g.armies:
            armies = self._filtered_armies()
            if armies and self.focus >= len(armies):
                self.focus = max(0, len(armies) - 1)
            self.level = 0
            self.cell_mode = False
        return NONE()

    # ---- §5 单位格"移动"子模式（移到空格 / 与单位换位）----
    def _handle_cell_move_mode(self, a: str) -> SceneResult:
        if a == actions.BACK:
            self.in_cell_move = False
            self.level = 1
            return NONE()
        if a in (actions.UP, actions.DOWN, actions.LEFT, actions.RIGHT):
            row = self._cell_move_target // 3
            col = self._cell_move_target % 3
            if a == actions.UP:
                row = (row - 1) % 3
            elif a == actions.DOWN:
                row = (row + 1) % 3
            elif a == actions.LEFT:
                col = (col - 1) % 3
            else:
                col = (col + 1) % 3
            self._cell_move_target = row * 3 + col
            return NONE()
        if a == actions.CONFIRM:
            return self._confirm_cell_move()
        return NONE()

    def _confirm_cell_move(self) -> SceneResult:
        army = self._selected_army()
        if army is None:
            self.in_cell_move = False
            return NONE()
        src = self.grid_cursor
        tgt = self._cell_move_target
        self.in_cell_move = False
        self.level = 1
        if tgt == src:
            log.push("未移动（目标与原位相同）")
            return NONE()
        s_uid = army.grid[src]
        t_uid = army.grid[tgt]
        if s_uid is None:
            log.push("原位无单位", warn=True)
            return NONE()
        if t_uid is None:
            army.grid[tgt] = s_uid
            army.grid[src] = None
            log.push(f"已移动至 {ROW_CN[row_of(tgt)]}排{col_of(tgt)+1}列")
        else:
            army.grid[src], army.grid[tgt] = army.grid[tgt], army.grid[src]
            log.push(f"已与 {ROW_CN[row_of(tgt)]}排{col_of(tgt)+1}列换位")
        self.grid_cursor = tgt
        return NONE()

    # ---- §5 空格"上场"子模式（列待命·可用，回车 action_deploy）----
    def _handle_deploy_mode(self, a: str) -> SceneResult:
        if a == actions.BACK:
            self.in_deploy = False
            self.level = 1
            return NONE()
        if a in (actions.UP, actions.DOWN):
            player = ctrl_mod.ctrl.player()
            avail = player.standby_available_ids()
            if not avail:
                return NONE()
            delta = -1 if a == actions.UP else 1
            self._deploy_focus = (self._deploy_focus + delta) % len(avail)
            visible = W3[3] - 6
            if self._deploy_focus < self._deploy_scroll:
                self._deploy_scroll = self._deploy_focus
            elif self._deploy_focus >= self._deploy_scroll + visible:
                self._deploy_scroll = self._deploy_focus - visible + 1
            return NONE()
        if a == actions.CONFIRM:
            return self._confirm_deploy()
        return NONE()

    def _confirm_deploy(self) -> SceneResult:
        g = ctrl_mod.ctrl.g
        army = self._selected_army()
        if army is None:
            self.in_deploy = False
            return NONE()
        player = ctrl_mod.ctrl.player()
        avail = player.standby_available_ids()
        if not avail:
            self.in_deploy = False
            self.level = 1
            return NONE()
        uid = avail[self._deploy_focus % len(avail)]
        msg = g.action_deploy(g.player_id, army.id, uid, slot=self.grid_cursor)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)
        self.in_deploy = False
        self.level = 1
        return NONE()

    # ---- 解散 / 新建 ----
    def _disband(self, army) -> SceneResult:
        g = ctrl_mod.ctrl.g
        name = army.name
        g.disband_army(army)
        log.push(f"已解散 {name}")
        armies = self._filtered_armies()
        if armies and self.focus >= len(armies):
            self.focus = max(0, len(armies) - 1)
        self.level = 0
        self.cell_mode = False
        return NONE()

    def _new_army(self) -> SceneResult:
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        army = self._selected_army()
        node_id = army.node_id if army else None
        if node_id is None:
            node_id = player.capital_id
        if node_id is None:
            log.push("无可用的建队据点", warn=True)
            return NONE()
        # 队长候选:阵营级待命·可用英雄(ADR-0005)
        hero = None
        for uid in player.standby_available_ids():
            u = g.unit_index.get(uid)
            if u and u.is_hero and u.alive:
                hero = u
                break
        if hero is None:
            log.push("无待命·可用英雄任队长", warn=True)
            return NONE()
        new_army = g.create_army(g.player_id, node_id, f"{hero.name}的部队")
        ok = g.set_captain(new_army, hero)
        if not ok:
            g.disband_army(new_army)
            log.push(f"建队失败：{hero.name} 无法任队长", warn=True)
            return NONE()
        log.push(f"新建部队 {new_army.name}（队长 {hero.name}）驻于 {g.map.node_name(node_id)}")
        self.filter = 0
        armies = self._filtered_armies()
        for i, a in enumerate(armies):
            if a.id == new_army.id:
                self.focus = i
                break
        return NONE()

    def _focus_to_army(self, army_id: str) -> None:
        self.filter = 3
        for i, a in enumerate(self._filtered_armies()):
            if a.id == army_id:
                self.focus = i
                return
        self.filter = 0
        for i, a in enumerate(self._filtered_armies()):
            if a.id == army_id:
                self.focus = i
                return

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="部队一栏")
        self._render_filter_row(buf, w)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        self._render_w1(buf)
        self._render_w2(buf)
        self._render_w3(buf)
        # §6 底部日志栏 y=h-2（键提示由框架在 h-1 绘制）
        log.render_log_bar(buf, 0, h - 2, w)

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
        active = self.level == 0 and not self.cell_mode
        border = theme.ACCENT if active else theme.BORDER
        title = "单位详情" if self.cell_mode else "部队列表"
        draw_box(buf, x, y, ww, hh, title=title, fg=border)
        if self.cell_mode:
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
        if army is None:
            buf.put_text(x + 1, y + 1, "（无单位）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        uid = army.grid[self.grid_cursor]
        ry = y + 1
        if not uid or uid not in g.unit_index or not g.unit_index[uid].alive:
            # 空格详情：可上场提示
            buf.put_text(x + 1, ry, "（空位）", theme.HEADING, theme.BG); ry += 1
            avail = ctrl_mod.ctrl.player().standby_available_ids()
            buf.put_text(x + 1, ry, f"可上场：待命·可用 {len(avail)} 名", theme.DIM, theme.BG); ry += 1
            if self._is_ours(army):
                if army.node_id in ctrl_mod.ctrl.player().stronghold_ids:
                    buf.put_text(x + 1, ry, "回车→上场（W2）", theme.ACCENT, theme.BG)
                else:
                    buf.put_text(x + 1, ry, "部队不在己方据点", theme.WARN, theme.BG)
            else:
                buf.put_text(x + 1, ry, "非本方/驻军，不可编辑", theme.WARN, theme.BG)
            return
        u = g.unit_index[uid]
        buf.put_text(x + 1, ry, u.name, theme.HEADING, theme.BG); ry += 1
        tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(u.tags))
        buf.put_text(x + 1, ry, f"词条 {tagstr}", theme.DIM, theme.BG); ry += 1
        buf.put_text(x + 1, ry, f"英雄 {'是' if u.is_hero else '否'}", theme.DIM, theme.BG); ry += 1
        buf.put_text(x + 1, ry, f"等级 Lv{u.level}  经验 {u.xp}", theme.ACCENT, theme.BG); ry += 1
        ry += 1
        buf.put_text(x + 1, ry, "属性", theme.ACCENT, theme.BG); ry += 1
        attrs = ["hp", "p_atk", "m_atk", "p_def", "m_def", "speed", "acc", "eva", "block", "crit", "will", "occupy", "leadership"]
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
        title = "单位操作" if self.cell_mode else "部队操作"
        draw_box(buf, x, y, ww, hh, title=title, fg=border)
        if self.level == 0 and not self.cell_mode:
            buf.put_text(x + 1, y + 1, "（选中部队按 →）", theme.DIM, theme.BG)
            return
        army = self._selected_army()
        if army is None:
            return
        ops = self._cell_ops() if self.cell_mode else self._army_ops()
        for i, op in enumerate(ops):
            ry = y + 1 + i
            if ry >= y + hh - 1:
                break
            self._draw_row(buf, x, ry, ww, op, theme.FG, i, self.w2_focus, active)
        if not self._is_ours(army) and self.level >= 1:
            buf.put_text(x + 1, y + hh - 2, "（非本方/驻军，仅可查看）", theme.WARN, theme.BG)

    def _render_w3(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W3
        active = self.level == 2 and not self.cell_mode and not self.in_cell_move and not self.in_deploy
        border = theme.ACCENT if active else theme.BORDER
        title = "阵型"
        if self.in_move:
            title = "移动·选择目的地"
        elif self.in_cell_move:
            title = "移动·选择目标格"
        elif self.in_deploy:
            title = "上场·选择单位"
        draw_box(buf, x, y, ww, hh, title=title, fg=border)
        army = self._selected_army()
        if army is None:
            buf.put_text(x + 1, y + 1, "（无部队）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        # 头部：占用/补给/位置
        occ = army.occupy_total(g.unit_index)
        mx = army.max_leadership(g.unit_index)
        buf.put_text(x + 1, y + 1, f"占用 {occ}/{mx}", theme.HEADING, theme.BG)
        buf.put_text(x + 14, y + 1, f"补给 {army.supply}/{army.supply_max}", theme.DIM, theme.BG)
        buf.put_text(x + 1, y + 2, f"位置 {g.map.node_name(army.node_id)}", theme.DIM, theme.BG)
        if army.has_acted_this_turn:
            buf.put_text(x + 18, y + 2, "(已行动)", theme.WARN, theme.BG)
        if not self._is_ours(army):
            buf.put_text(x + 1, y + 3, "（非本方/驻军，仅可查看）", theme.WARN, theme.BG)

        if self.in_move:
            self._render_move_targets(buf, x, y, ww, hh, army)
            return
        if self.in_deploy:
            self._render_deploy_targets(buf, x, y, ww, hh, army)
            return
        # 九宫格（浏览 / 单元格模式 / 单位格移动子模式）
        self._render_grid(buf, x, y, ww, hh, army)

    def _render_grid(self, buf: FrameBuffer, x: int, y: int, ww: int, hh: int, army) -> None:
        g = ctrl_mod.ctrl.g
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
                # 决定高亮
                hl = False
                fg = theme.FG
                bg = theme.BG
                if self.in_cell_move:
                    if slot == self._cell_move_target:
                        hl, fg, bg = True, theme.SELECTED_FG, theme.SELECTED_BG
                    elif slot == self.grid_cursor:
                        hl, fg, bg = True, theme.SELECTED_FG, theme.ACCENT2
                elif self.level == 2 and not self.cell_mode:
                    if slot == self.grid_cursor:
                        hl, fg, bg = True, theme.SELECTED_FG, theme.SELECTED_BG
                elif self.cell_mode:
                    if slot == self.grid_cursor:
                        hl, fg, bg = True, theme.SELECTED_FG, theme.ACCENT2
                if uid and uid in g.unit_index and g.unit_index[uid].alive:
                    u = g.unit_index[uid]
                    name = u.name[:3]
                    if hl:
                        buf.fill_rect(cx - 1, cy, 7, 1, " ", fg, bg)
                        buf.put_text(cx, cy, name, fg, bg)
                    else:
                        buf.put_text(cx, cy, name, theme.FG, theme.BG)
                else:
                    marker = "·"
                    if hl:
                        buf.fill_rect(cx - 1, cy, 7, 1, " ", fg, bg)
                        buf.put_text(cx, cy, marker, fg, bg)
                    else:
                        buf.put_text(cx, cy, marker, theme.DIM, theme.BG)

    def _render_move_targets(self, buf: FrameBuffer, x: int, y: int, ww: int, hh: int, army) -> None:
        nbrs = self._neighbors_of_current()
        if not nbrs:
            buf.put_text(x + 1, y + 4, "（无可移动的邻接地点）", theme.WARN, theme.BG)
            return
        idx = self._move_focus % len(nbrs)
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

    def _render_deploy_targets(self, buf: FrameBuffer, x: int, y: int, ww: int, hh: int, army) -> None:
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        avail = player.standby_available_ids()
        if not self._is_ours(army):
            buf.put_text(x + 1, y + 4, "（非本方/驻军，不可上场）", theme.WARN, theme.BG)
            return
        if army.node_id not in player.stronghold_ids:
            buf.put_text(x + 1, y + 4, "部队不在己方据点，无法上场", theme.WARN, theme.BG)
            return
        if not avail:
            buf.put_text(x + 1, y + 4, "无待命·可用单位", theme.WARN, theme.BG)
            return
        idx = self._deploy_focus % len(avail)
        start = self._deploy_scroll
        visible = hh - 6
        for i in range(start, min(len(avail), start + visible)):
            ry = y + 4 + (i - start)
            if ry >= y + hh - 1:
                break
            u = g.unit_index[avail[i]]
            tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(u.tags))
            label = f"{u.name}  {tagstr}"
            self._draw_row(buf, x, ry, ww, label, theme.FG, i, idx, True)
        if len(avail) > visible:
            buf.put_text(x + ww - 8, y, f"({self._deploy_focus+1}/{len(avail)})", theme.DIM, theme.BG)

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
        if self.in_move:
            return ["↑↓ 选目的地", "回车 移动/攻击", "ESC 取消"]
        if self.in_cell_move:
            return ["↑↓←→ 选目标格", "回车 确认", "ESC 取消"]
        if self.in_deploy:
            return ["↑↓ 选单位", "回车 上场", "ESC 取消"]
        if self.level == 2 and not self.cell_mode:
            return ["↑↓←→ 选格", "空格 进详情操作", "ESC 返回"]
        if self.cell_mode:
            return ["↑↓ 选操作", "回车 确认", "←/ESC 回九宫格"]
        hints = ["1-4 筛选", "↑↓ 切换", "→ 进入W2", "回车 确认/编辑", "← 回退"]
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
