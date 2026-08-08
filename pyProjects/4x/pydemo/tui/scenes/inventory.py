"""仓库场景（键 I）：装备实例一览 + 效果/归属详情 + 卖出/卸下（操作逻辑.md §13）。

左右两窗口:
- 左侧(W1):阵营仓库内全部装备实例(最多 200,ADR-0007)。每件一行,按状态显示:
    · 已装备 → 名字前加 "E"(equiped);行尾标所属部队·单位
    · 在库可用 → 普通显示
    · 在库不可用(卸下冷却中) → 名字后标 "(不可用N)"
  焦点在左侧某装备上时:
    · S 卖出(仅未装备且可用,固定 +10 金币,走 Game.action_sell_artifact)
    · X 卸下(仅正在被装备,走 Game.action_unequip;装备单位不在己方据点则
      进不可用 5 回合,见操作逻辑.md §13)
- 右侧(W2):当前焦点装备的效果描述 + 归属(若已装备:哪个部队的哪个单位)。

注意:本场景用独立按键处理(直接读 CHAR 动作的 char 字段),因 S/X 在主场景
键绑定里未绑定到游戏动作(主场景 X 绑定 OPEN_UNIT,但本场景拦截后自行处理,不
冒泡到主场景)。S/X 仅在左侧窗口焦点时生效。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, put_truncated
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from pydemo.game.unit import ATTR_CN, TAG_CN

# 左右两窗口(x, y, w, h)。外框 (0,0,100,30),y=3..27 给窗口,y=28 日志栏。
W1 = (1, 3, 48, 25)
W2 = (49, 3, 50, 25)


def _describe_effect(eff: dict) -> str:
    """把一条 effect 原始 dict 转成中文描述(仓库右侧效果展示用)。"""
    et = eff.get("type")
    p = eff.get("params", {})
    if et == "flat_attr":
        return f"{ATTR_CN.get(p.get('attr'), p.get('attr'))} +{p.get('value', 0)}"
    if et == "pct_attr":
        return f"{ATTR_CN.get(p.get('attr'), p.get('attr'))} +{p.get('value', 0)}%"
    if et == "tag_grant":
        return f"赋予词条 {TAG_CN.get(p.get('tag'), p.get('tag'))}"
    if et == "tag_bonus":
        return (f"有 {TAG_CN.get(p.get('tag'), p.get('tag'))} 时 "
                f"{ATTR_CN.get(p.get('attr'), p.get('attr'))} +{p.get('value', 0)}")
    if et == "aura_flat":
        return f"光环 {ATTR_CN.get(p.get('attr'), p.get('attr'))} +{p.get('value', 0)}"
    return f"{et} {p}"


class InventoryScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.focus = 0          # 左侧装备列表焦点
        self.list_scroll = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.focus = 0
        self.list_scroll = 0

    # ---- 数据 ----
    def _all_instances(self) -> list:
        """仓库内全部装备实例(已装备 + 在库),按 def_id 再按 id 排序稳定展示。"""
        player = ctrl_mod.ctrl.player()
        return sorted(player.inventory, key=lambda a: (a.def_id, a.id))

    def _safe_focus(self) -> list:
        insts = self._all_instances()
        if not insts:
            self.focus = 0
            return insts
        if self.focus >= len(insts):
            self.focus = len(insts) - 1
        return insts

    def _selected_inst(self):
        insts = self._safe_focus()
        if not insts:
            return None
        return insts[self.focus]

    def _equip_owner_text(self, inst) -> str:
        """若实例已装备,返回 "部队名·单位名";否则返回空串。"""
        if not inst.is_equipped():
            return ""
        g = ctrl_mod.ctrl.g
        u = g.unit_index.get(inst.equipped_by)
        if not u:
            return "(装备单位缺失)"
        army = g.armies.get(u.army_id) if u.army_id else None
        if army:
            if army.is_garrison:
                sh = g.map.strongholds.get(army.node_id)
                army_txt = f"{sh.name if sh else army.node_id}驻军"
            else:
                army_txt = army.name
        else:
            army_txt = "待命"
        return f"{army_txt} · {u.name}"

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        insts = self._safe_focus()
        if a == actions.BACK:
            return POP()
        if a in (actions.UP, actions.DOWN):
            self._move_vertical(a, insts)
            return NONE()
        # 操作逻辑.md §13:S 卖出 / X 卸下 —— 直接读字符,仅左侧列表焦点时生效。
        if a == actions.CHAR and event.char:
            ch = event.char.lower()
            if ch == "s":
                self._do_sell()
                return NONE()
            if ch == "x":
                self._do_unequip()
                return NONE()
        return NONE()

    def _move_vertical(self, a: str, insts: list) -> None:
        if not insts:
            return
        delta = -1 if a == actions.UP else 1
        self.focus = (self.focus + delta) % len(insts)
        visible = W1[3] - 2
        if self.focus < self.list_scroll:
            self.list_scroll = self.focus
        elif self.focus >= self.list_scroll + visible:
            self.list_scroll = self.focus - visible + 1

    def _do_sell(self) -> None:
        inst = self._selected_inst()
        if inst is None:
            return
        g = ctrl_mod.ctrl.g
        msg = g.action_sell_artifact(g.player_id, inst.id)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)
        # 卖出后列表缩短,夹住焦点
        self._safe_focus()

    def _do_unequip(self) -> None:
        inst = self._selected_inst()
        if inst is None:
            return
        if not inst.is_equipped():
            log.push("该装备未被装备,无法卸下", warn=True)
            return
        g = ctrl_mod.ctrl.g
        u = g.unit_index.get(inst.equipped_by)
        if u is None:
            log.push("装备单位缺失", warn=True)
            return
        # 找到槽位(实例在单位 artifacts 中的位置)
        slot = None
        for i, iid in enumerate(u.artifacts):
            if iid == inst.id:
                slot = i
                break
        if slot is None:
            log.push("未找到装备槽位", warn=True)
            return
        msg = g.action_unequip(g.player_id, u.id, slot)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        insts = self._safe_focus()
        draw_box(buf, 0, 0, w, h, title="仓库")
        buf.put_text(2, 1, f"装备 {len(insts)}/200", theme.HEADING, theme.BG)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        self._render_w1(buf, insts)
        self._render_w2(buf)
        log.render_log_bar(buf, 0, h - 2, w)

    def _render_w1(self, buf, insts: list) -> None:
        x, y, ww, hh = W1
        border = theme.ACCENT
        draw_box(buf, x, y, ww, hh, title="装备列表", fg=border)
        if not insts:
            buf.put_text(x + 1, y + 1, "（仓库无装备）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        visible = hh - 2
        start = self.list_scroll
        end = min(len(insts), start + visible)
        for i in range(start, end):
            ry = y + 1 + (i - start)
            if ry >= y + hh - 1:
                break
            inst = insts[i]
            art = g.artifact_def_of(inst.id)
            name = art.name if art else inst.def_id
            # 操作逻辑.md §13:已装备名字前加 E
            prefix = "E " if inst.is_equipped() else "  "
            # 状态后缀
            if inst.is_equipped():
                owner = self._equip_owner_text(inst)
                suffix = f"  → {owner}"
                fg = theme.ACCENT2
            elif inst.is_unavailable():
                suffix = f"  (不可用{inst.cooldown})"
                fg = theme.WARN
            else:
                suffix = ""
                fg = theme.FG
            label = f"{prefix}{name}{suffix}"
            self._draw_row(buf, x, ry, ww, label, fg, i, self.focus, truncate=True)
        if len(insts) > visible:
            buf.put_text(x + ww - 9, y, f"({self.focus + 1}/{len(insts)})",
                         theme.DIM, theme.BG)

    def _render_w2(self, buf) -> None:
        x, y, ww, hh = W2
        draw_box(buf, x, y, ww, hh, title="装备详情", fg=theme.BORDER)
        inst = self._selected_inst()
        if inst is None:
            buf.put_text(x + 1, y + 1, "（请选择左侧装备）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        art = g.artifact_def_of(inst.id)
        ry = y + 1
        # 名称
        buf.put_text(x + 1, ry, f"名称: {art.name if art else inst.def_id}",
                     theme.HEADING, theme.BG); ry += 1
        # 状态
        if inst.is_equipped():
            state_txt = "已装备"
            sfg = theme.ACCENT2
        elif inst.is_unavailable():
            state_txt = f"不可用(冷却 {inst.cooldown} 回合)"
            sfg = theme.WARN
        else:
            state_txt = "在库·可用"
            sfg = theme.FG
        buf.put_text(x + 1, ry, f"状态: {state_txt}", sfg, theme.BG); ry += 1
        # 归属(若已装备)
        if inst.is_equipped():
            owner = self._equip_owner_text(inst)
            buf.put_text(x + 1, ry, f"装备于: {owner}", theme.ACCENT, theme.BG)
        ry += 1
        # 分隔
        self._hline(buf, x, ry, ww); ry += 1
        # 效果
        buf.put_text(x + 1, ry, "效果", theme.ACCENT, theme.BG); ry += 1
        if art and art.effects:
            for eff in art.effects:
                if ry >= y + hh - 1:
                    break
                txt = "· " + _describe_effect(eff)
                put_truncated(buf, x + 2, ry, txt, ww - 4, theme.FG, theme.BG)
                ry += 1
        else:
            buf.put_text(x + 2, ry, "（无效果）", theme.DIM, theme.BG); ry += 1
        # 可用操作提示(底部)
        ry = y + hh - 2
        self._hline(buf, x, ry, ww); ry += 1
        if inst.is_equipped():
            buf.put_text(x + 1, ry, "X 卸下(不在据点则进不可用5回合)", theme.ACCENT2, theme.BG)
        elif inst.is_available():
            buf.put_text(x + 1, ry, "S 卖出(+10 金币)", theme.GOLD, theme.BG)
        else:
            buf.put_text(x + 1, ry, "冷却中,不可操作", theme.DIM, theme.BG)

    def _draw_row(self, buf, x, y, ww, label, fg, idx, focus_idx,
                  truncate: bool = False) -> None:
        inner_w = ww - 2
        if idx == focus_idx:
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

    def _hline(self, buf, x, y, ww) -> None:
        for cx in range(x + 1, x + ww - 1):
            buf.set_char(cx, y, "─", theme.BORDER, theme.BG)

    def get_hints(self) -> list[str]:
        return ["↑↓ 选装备", "S 卖出", "X 卸下", "ESC 返回"]


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
