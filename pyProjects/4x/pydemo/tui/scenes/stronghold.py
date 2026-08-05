"""据点场景：4 层嵌套窗口（M6 完整实现）。

按 操作逻辑.md（据点界面）：
- 4 个左右排列的窗口，焦点用方向键右逐层进入、方向键左回退。
  W1 所有据点（绿=我方/红=敌方/白=中立）→ W2 单据点（槽位+部队）→
  W3 槽位操作（建造/拆除/指派）→ W4 候选（建筑/英雄）。
- 非己方据点可查看 W2，但不能继续向右操作。
- 槽位操作：建造/指派用 → 进入 W4 选具体目标后回车确认；拆除直接回车确认。
- 焦点在部队上按 → 进入部队操作（委托给 ArmyScene，等同部队一览）。
- 不在最左侧窗口时，← 回退一层；ESC 也回退一层，在 W1 时 ESC 退出本场景。

业务层无据点"拆除/指派领主"接口，故拆除用直接 buildings 列表删除、
指派用直接 player.lords[sh.id]=hero 写入（计划中标注的业务层缺口）。
建造走 Game.action_build（有资源/槽位校验）。
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
from pydemo.game.economy import RESOURCE_CN
from pydemo.game.map_system import SIZE_CN

# 归属颜色
C_OWN = 41       # 绿
C_ENEMY = 196    # 红
C_NEUTRAL = 254  # 白

# 4 个窗口矩形（x, y, w, h）。外框 (0,0,100,30)，y=3..27 给窗口。
W1 = (1, 3, 26, 25)
W2 = (27, 3, 24, 25)
W3 = (51, 3, 24, 25)
W4 = (75, 3, 24, 25)


def _owner_color(sh, player_id: str) -> int:
    if sh.owner == player_id:
        return C_OWN
    if sh.owner is None:
        return C_NEUTRAL
    return C_ENEMY


class StrongholdScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.level = 0                 # 0..3 当前焦点所在窗口
        self.focus = [0, 0, 0, 0]      # 各层焦点下标
        self._slot_index = 0           # W2 中进入 W3 时记录的槽位下标
        self._mode = "build"           # W4 模式：build / assign

    def on_enter(self, params: Any = None) -> None:
        self.params = params

    def on_return(self, value: Any) -> None:
        """从 ArmyScene（部队操作委托）弹回时，W2 部队列表可能变化，夹住焦点。"""
        sh = self._selected_sh()
        rows = self._w2_rows_for(sh)
        if rows and self.focus[1] >= len(rows):
            self.focus[1] = max(0, len(rows) - 1)

    # ---- 数据查询（每帧/每次动作都重新算，避免状态过期）----
    def _selected_sh(self):
        g = ctrl_mod.ctrl.g
        shs = list(g.map.strongholds.values())
        return shs[self.focus[0] % len(shs)] if shs else None

    def _w2_rows_for(self, sh) -> list[tuple[str, Any]]:
        """W2 行：槽位 + 该据点上的部队（含驻军）。"""
        g = ctrl_mod.ctrl.g
        rows: list[tuple[str, Any]] = []
        if sh is None:
            return rows
        for i in range(sh.slots()):
            rows.append(("slot", i))
        for a in g.armies.values():
            if a.node_id == sh.id and not a.is_wiped(g.unit_index):
                rows.append(("army", a.id))
        return rows

    def _ops_for(self, sh, slot_idx: int) -> list[str]:
        """W3 槽位操作：空槽→建造；有建筑→拆除；指派恒有。"""
        if sh is None:
            return []
        occupied = slot_idx < len(sh.buildings)
        return (["拆除", "指派"] if occupied else ["建造", "指派"])

    def _candidates_for(self, sh, mode: str) -> list[tuple[str, str, str, bool]]:
        """W4 候选：(id, 显示名, 副信息, 可用)。"""
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        out: list[tuple[str, str, str, bool]] = []
        if sh is None:
            return out
        if mode == "build":
            for bid, bdef in g.building_defs.items():
                name = bdef.get("name", bid)
                cost = bdef.get("cost", {})
                cost_str = "  ".join(f"{RESOURCE_CN.get(k, k)}:{v}" for k, v in cost.items()) or "免费"
                ok = player.resources.can_afford(cost)
                out.append((bid, name, cost_str, ok))
        else:  # assign 领主
            lord_ids = set(player.lords.values())
            captain_ids = {a.captain_id for a in g.armies.values() if a.captain_id}
            for u in g.unit_index.values():
                if (u.is_hero and u.alive and u.node_id == sh.id
                        and u.id not in lord_ids and u.id not in captain_ids):
                    out.append((u.id, u.name, "可指派", True))
        return out

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if a == actions.BACK:
            if self.level > 0:
                self.level -= 1
                return NONE()
            return POP()
        if a == actions.LEFT:
            if self.level > 0:
                self.level -= 1
            return NONE()
        if a == actions.RIGHT:
            return self._go_right()
        if a in (actions.UP, actions.DOWN):
            self._move_vertical(a)
            return NONE()
        if a == actions.CONFIRM:
            return self._activate()
        if a == actions.SELECT:
            # 空格在某层也可作"进入"（与回车一致），方便无方向键时操作
            return self._activate()
        return NONE()

    def _move_vertical(self, a: str) -> None:
        lv = self.level
        delta = -1 if a == actions.UP else 1
        if lv == 0:
            n = len(ctrl_mod.ctrl.g.map.strongholds)
        elif lv == 1:
            n = len(self._w2_rows_for(self._selected_sh()))
        elif lv == 2:
            n = len(self._ops_for(self._selected_sh(), self._slot_index))
        else:
            n = len(self._candidates_for(self._selected_sh(), self._mode))
        if n > 0:
            self.focus[lv] = (self.focus[lv] + delta) % n

    def _go_right(self) -> SceneResult:
        if self.level == 0:
            self.focus[1] = 0
            self.level = 1
            return NONE()
        if self.level == 1:
            return self._enter_from_w2()
        if self.level == 2:
            sh = self._selected_sh()
            ops = self._ops_for(sh, self._slot_index)
            if not ops:
                return NONE()
            op = ops[self.focus[2] % len(ops)]
            if op == "拆除":
                log.push("拆除请按回车确认", warn=True)
                return NONE()
            self._mode = "build" if op == "建造" else "assign"
            self.focus[3] = 0
            self.level = 3
            return NONE()
        return NONE()  # W4 已是最深

    def _enter_from_w2(self) -> SceneResult:
        g = ctrl_mod.ctrl.g
        sh = self._selected_sh()
        rows = self._w2_rows_for(sh)
        if not rows:
            return NONE()
        kind, key = rows[self.focus[1] % len(rows)]
        if kind == "army":
            if sh.owner != g.player_id:
                log.push("非己方据点，不可操作", warn=True)
                return NONE()
            army = g.armies[key]
            if army.is_garrison:
                log.push("驻军不可编辑", warn=True)
                return NONE()
            from .army import ArmyScene
            return PUSH(ArmyScene(), {"army_id": key})
        # 槽位
        if sh.owner != g.player_id:
            log.push("非己方据点，不可操作", warn=True)
            return NONE()
        self._slot_index = key
        self.focus[2] = 0
        self.level = 2
        return NONE()

    def _activate(self) -> SceneResult:
        """回车：在 W1/W2 同 →（进入下层）；W2→W3、W3 执行或进 W4、W4 确认执行。"""
        if self.level in (0, 1):
            return self._go_right()
        if self.level == 2:
            sh = self._selected_sh()
            ops = self._ops_for(sh, self._slot_index)
            if not ops:
                return NONE()
            op = ops[self.focus[2] % len(ops)]
            if op == "拆除":
                self._do_demolish(sh)
                self.level = 1
                return NONE()
            self._mode = "build" if op == "建造" else "assign"
            self.focus[3] = 0
            self.level = 3
            return NONE()
        if self.level == 3:
            self._do_candidate_confirm()
            self.level = 1
            return NONE()
        return NONE()

    def _do_demolish(self, sh) -> None:
        i = self._slot_index
        if i < len(sh.buildings):
            b = sh.buildings[i]
            sh.buildings.pop(i)
            log.push(f"拆除了 {sh.name} 的 {b.name}")

    def _do_candidate_confirm(self) -> None:
        g = ctrl_mod.ctrl.g
        sh = self._selected_sh()
        cands = self._candidates_for(sh, self._mode)
        if not cands or sh is None:
            return
        cid, name, _sub, _ok = cands[self.focus[3] % len(cands)]
        if self._mode == "build":
            msg = g.action_build(g.player_id, sh.id, cid)
            log.push(msg)
        else:
            ctrl_mod.ctrl.player().lords[sh.id] = cid
            log.push(f"指派 {name} 为 {sh.name} 的领主")

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="据点一览")
        # 面包屑 y=1
        buf.put_text(2, 1, self._breadcrumb(), theme.ACCENT, theme.BG)
        # 分隔线 y=2
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        self._render_w1(buf)
        self._render_w2(buf)
        self._render_w3(buf)
        self._render_w4(buf)
        # 图例 y=28
        legend = "◆首都  绿=我方  红=敌方  白=中立  ·  槽位=建筑/空槽  ·  →进入 ←回退 回车确认"
        buf.put_text(2, 28, legend, theme.DIM, theme.BG)

    def _breadcrumb(self) -> str:
        sh = self._selected_sh()
        if sh is None:
            return "（无据点）"
        parts = [f"据点: {sh.name}"]
        if self.level >= 1:
            rows = self._w2_rows_for(sh)
            if rows:
                kind, key = rows[self.focus[1] % len(rows)]
                if kind == "slot":
                    label = sh.buildings[key].name if key < len(sh.buildings) else "空槽"
                    parts.append(f"槽{key}: {label}")
                else:
                    parts.append(f"部队: {ctrl_mod.ctrl.g.armies[key].name}")
        if self.level >= 2:
            ops = self._ops_for(sh, self._slot_index)
            if ops:
                parts.append(f"操作: {ops[self.focus[2] % len(ops)]}")
        if self.level >= 3:
            cands = self._candidates_for(sh, self._mode)
            if cands:
                parts.append(f"候选: {cands[self.focus[3] % len(cands)][1]}")
        return " > ".join(parts)

    def _render_w1(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W1
        active = self.level == 0
        border = theme.ACCENT if active else theme.BORDER
        draw_box(buf, x, y, ww, hh, title="据点", fg=border)
        shs = list(ctrl_mod.ctrl.g.map.strongholds.values())
        for i, sh in enumerate(shs):
            ry = y + 1 + i
            if ry >= y + hh - 1:
                break
            fg = _owner_color(sh, ctrl_mod.ctrl.g.player_id)
            label = f"◆{sh.name}" + ("(都)" if sh.is_capital else "")
            self._draw_row(buf, x, ry, ww, label, fg, i, self.focus[0], active)

    def _render_w2(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W2
        active = self.level == 1
        border = theme.ACCENT if active else theme.BORDER
        sh = self._selected_sh()
        draw_box(buf, x, y, ww, hh, title="据点详情", fg=border)
        if sh is None:
            return
        # 头部两行
        buf.put_text(x + 1, y + 1, sh.name, theme.HEADING, theme.BG)
        owner_txt = "我方" if sh.owner == ctrl_mod.ctrl.g.player_id else (
            "中立" if sh.owner is None else "敌方")
        buf.put_text(x + 1, y + 2,
                     f"规模{SIZE_CN.get(sh.size, '?')} 槽{len(sh.buildings)}/{sh.slots()} {owner_txt}",
                     theme.DIM, theme.BG)
        rows = self._w2_rows_for(sh)
        if not rows:
            buf.put_text(x + 1, y + 4, "（无槽位/部队）", theme.DIM, theme.BG)
            return
        for idx, (kind, key) in enumerate(rows):
            ry = y + 3 + idx
            if ry >= y + hh - 1:
                break
            if kind == "slot":
                if key < len(sh.buildings):
                    b = sh.buildings[key]
                    label = b.name + ("(建造中)" if not b.is_ready() else "")
                    fg = theme.FG
                else:
                    label = "空槽"
                    fg = theme.DIM
            else:
                a = ctrl_mod.ctrl.g.armies[key]
                label = a.name + ("(驻军)" if a.is_garrison else "")
                fg = theme.DIM if a.is_garrison else theme.ACCENT2
            self._draw_row(buf, x, ry, ww, label, fg, idx, self.focus[1], active)

    def _render_w3(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W3
        active = self.level == 2
        border = theme.ACCENT if active else theme.BORDER
        sh = self._selected_sh()
        draw_box(buf, x, y, ww, hh, title="槽位操作", fg=border)
        if self.level < 2 or sh is None:
            buf.put_text(x + 1, y + 1, "（在 W2 槽位上按 →）", theme.DIM, theme.BG)
            return
        ops = self._ops_for(sh, self._slot_index)
        slot_label = (sh.buildings[self._slot_index].name
                      if self._slot_index < len(sh.buildings) else "空槽")
        buf.put_text(x + 1, y + 1, f"槽{self._slot_index}: {slot_label}", theme.HEADING, theme.BG)
        for i, op in enumerate(ops):
            ry = y + 2 + i
            if ry >= y + hh - 1:
                break
            self._draw_row(buf, x, ry, ww, op, theme.FG, i, self.focus[2], active)

    def _render_w4(self, buf: FrameBuffer) -> None:
        x, y, ww, hh = W4
        active = self.level == 3
        border = theme.ACCENT if active else theme.BORDER
        sh = self._selected_sh()
        title = "候选·建造" if self._mode == "build" else "候选·指派"
        draw_box(buf, x, y, ww, hh, title=title, fg=border)
        if self.level < 3 or sh is None:
            buf.put_text(x + 1, y + 1, "（在 W3 操作上按 →）", theme.DIM, theme.BG)
            return
        cands = self._candidates_for(sh, self._mode)
        if not cands:
            buf.put_text(x + 1, y + 1,
                         "无可指派英雄" if self._mode == "assign" else "（无候选）",
                         theme.WARN, theme.BG)
            return
        for i, (cid, name, sub, ok) in enumerate(cands):
            ry = y + 1 + i
            if ry >= y + hh - 1:
                break
            if self._mode == "build":
                label = f"{name} {sub}"
                fg = theme.GOLD if ok else theme.WARN
            else:
                label = name
                fg = theme.FG
            self._draw_row(buf, x, ry, ww, label, fg, i, self.focus[3], active,
                           truncate=True)

    def _draw_row(self, buf: FrameBuffer, x: int, y: int, ww: int, label: str,
                  fg: int, idx: int, focus_idx: int, active: bool,
                  truncate: bool = False) -> None:
        inner_w = ww - 2
        if idx == focus_idx and active:
            buf.fill_rect(x + 1, y, inner_w, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
            buf.put_text(x + 1, y, "▶", theme.ACCENT2, theme.SELECTED_BG)
            text = label
            if truncate and text_width(text) > inner_w - 2:
                text = _truncate(text, inner_w - 3)
            buf.put_text(x + 3, y, text, theme.SELECTED_FG, theme.SELECTED_BG)
        else:
            buf.put_text(x + 1, y, "  ", theme.DIM, theme.BG)
            text = label
            if truncate and text_width(text) > inner_w - 2:
                text = _truncate(text, inner_w - 3)
            buf.put_text(x + 3, y, text, fg, theme.BG)

    def get_hints(self) -> list[str]:
        return ["↑↓ 切换", "→ 进入", "← 回退", "回车 确认", "ESC 返回"]


def _truncate(text: str, max_w: int) -> str:
    """按显示宽度截断并加省略号。"""
    if text_width(text) <= max_w:
        return text
    out = ""
    w = 0
    for ch in text:
        from pyconsole.io.width import char_width
        cw = char_width(ch)
        if w + cw > max_w - 1:
            break
        out += ch
        w += cw
    return out + "…"
