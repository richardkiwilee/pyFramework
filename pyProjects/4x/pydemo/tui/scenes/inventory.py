"""仓库场景（键 I）：装备按 def_id 库存行 + 效果/归属详情 + 卖出/卸下（ADR-0009）。

左右两窗口:
- 左侧(W1):阵营仓库内全部装备定义,每定义一行(取代 ADR-0007 的逐件实例列表)。
    每行显示:定义名  库存数 + 已装备数 + 归属列表(哪些部队·单位装备了该定义)。
  焦点在左侧某装备上时:
    · S 卖出(按 def_id 卖 1 件库存,固定 +10 金币,走 Game.action_sell_artifact)
    · X 卸下(按 def_id 找一件已装备该定义的单位,卸其对应槽位;不在己方据点则提示)
- 右侧(W2):当前焦点装备的效果描述 + 归属列表。

装/卸均要求单位所在部队在己方据点内(待命单位可编辑);野外部队不可穿戴/卸下。
注意:本场景用独立按键处理(直接读 CHAR 动作的 char 字段)。S/X 仅在左侧窗口焦点时生效。
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
    if et == "skill_grant":
        return f"赋予技能 {p.get('skill')}"
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
    def _all_defs(self) -> list[str]:
        """仓库内全部装备 def_id(按 id 排序稳定展示)。ADR-0009。"""
        g = ctrl_mod.ctrl.g
        # 列出所有已定义装备定义(含库存 0 的也显示,便于查看效果)
        return sorted(g.artifact_defs.keys())

    def _safe_focus(self) -> list[str]:
        defs = self._all_defs()
        if not defs:
            self.focus = 0
            return defs
        if self.focus >= len(defs):
            self.focus = len(defs) - 1
        return defs

    def _selected_def(self) -> str | None:
        defs = self._safe_focus()
        if not defs:
            return None
        return defs[self.focus]

    def _equipped_owners(self, def_id: str) -> list:
        """装备了该 def_id 的本阵营单位列表:[(army_txt, unit)]。ADR-0009 反查。"""
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        out = []
        for u in g.unit_index.values():
            if g._unit_owner(u) != player.id:
                continue
            if def_id in u.artifacts:
                army = g.armies.get(u.army_id) if u.army_id else None
                if army:
                    if army.is_garrison:
                        sh = g.map.strongholds.get(army.node_id)
                        army_txt = f"{sh.name if sh else army.node_id}驻军"
                    else:
                        army_txt = army.name
                else:
                    army_txt = "待命"
                out.append((army_txt, u))
        return out

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        defs = self._safe_focus()
        if a == actions.BACK:
            return POP()
        if a in (actions.UP, actions.DOWN):
            self._move_vertical(a, defs)
            return NONE()
        # S 卖出 / X 卸下 —— 直接读字符,仅左侧列表焦点时生效。
        if a == actions.CHAR and event.char:
            ch = event.char.lower()
            if ch == "s":
                self._do_sell()
                return NONE()
            if ch == "x":
                self._do_unequip()
                return NONE()
        return NONE()

    def _move_vertical(self, a: str, defs: list) -> None:
        if not defs:
            return
        delta = -1 if a == actions.UP else 1
        self.focus = (self.focus + delta) % len(defs)
        visible = W1[3] - 2
        if self.focus < self.list_scroll:
            self.list_scroll = self.focus
        elif self.focus >= self.list_scroll + visible:
            self.list_scroll = self.focus - visible + 1

    def _do_sell(self) -> None:
        def_id = self._selected_def()
        if def_id is None:
            return
        g = ctrl_mod.ctrl.g
        msg = g.action_sell_artifact(g.player_id, def_id)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)
        self._safe_focus()

    def _do_unequip(self) -> None:
        def_id = self._selected_def()
        if def_id is None:
            return
        g = ctrl_mod.ctrl.g
        # 找一件已装备该定义的单位,卸其对应槽位
        owners = self._equipped_owners(def_id)
        if not owners:
            log.push("该装备无被装备件,无需卸下", warn=True)
            return
        _army_txt, u = owners[0]
        slot = u.artifacts.index(def_id)
        msg = g.action_unequip(g.player_id, u.id, slot)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        defs = self._safe_focus()
        draw_box(buf, 0, 0, w, h, title="仓库")
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        stock_total = sum(player.inventory.values())
        buf.put_text(2, 1, f"装备定义 {len(defs)} 种 · 库存 {stock_total} 件",
                     theme.HEADING, theme.BG)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        self._render_w1(buf, defs)
        self._render_w2(buf)
        log.render_log_bar(buf, 0, h - 2, w)

    def _render_w1(self, buf, defs: list) -> None:
        x, y, ww, hh = W1
        border = theme.ACCENT
        draw_box(buf, x, y, ww, hh, title="装备列表(按定义)", fg=border)
        if not defs:
            buf.put_text(x + 1, y + 1, "（无装备定义）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        visible = hh - 2
        start = self.list_scroll
        end = min(len(defs), start + visible)
        for i in range(start, end):
            ry = y + 1 + (i - start)
            if ry >= y + hh - 1:
                break
            def_id = defs[i]
            art = g.artifact_def_of(def_id)
            name = art.name if art else def_id
            stock = player.inventory.get(def_id, 0)
            equipped = g.equipped_count(player.id, def_id)
            avail = max(0, stock - equipped)
            # 行:名字 + 在库/已装备
            label = f"{name}  库{avail}/装{equipped}"
            fg = theme.ACCENT2 if equipped > 0 else theme.FG
            self._draw_row(buf, x, ry, ww, label, fg, i, self.focus, truncate=True)
        if len(defs) > visible:
            buf.put_text(x + ww - 9, y, f"({self.focus + 1}/{len(defs)})",
                         theme.DIM, theme.BG)

    def _render_w2(self, buf) -> None:
        x, y, ww, hh = W2
        draw_box(buf, x, y, ww, hh, title="装备详情", fg=theme.BORDER)
        def_id = self._selected_def()
        if def_id is None:
            buf.put_text(x + 1, y + 1, "（请选择左侧装备）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        art = g.artifact_def_of(def_id)
        ry = y + 1
        # 名称
        buf.put_text(x + 1, ry, f"名称: {art.name if art else def_id}",
                     theme.HEADING, theme.BG); ry += 1
        # 库存/已装备
        stock = player.inventory.get(def_id, 0)
        equipped = g.equipped_count(player.id, def_id)
        avail = max(0, stock - equipped)
        buf.put_text(x + 1, ry, f"库存: {stock}  在库可用: {avail}  已装备: {equipped}",
                     theme.FG, theme.BG); ry += 1
        # 归属列表
        owners = self._equipped_owners(def_id)
        if owners:
            buf.put_text(x + 1, ry, "归属:", theme.ACCENT, theme.BG); ry += 1
            for army_txt, u in owners:
                if ry >= y + hh - 4:
                    break
                put_truncated(buf, x + 2, ry, f"· {army_txt} · {u.name}",
                              ww - 4, theme.ACCENT2, theme.BG)
                ry += 1
        else:
            buf.put_text(x + 1, ry, "归属:（无被装备件）", theme.DIM, theme.BG); ry += 1
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
        ops = []
        if avail > 0:
            ops.append("S 卖出(+10金币)")
        if equipped > 0:
            ops.append("X 卸下")
        if not ops:
            ops.append("无库存,不可操作")
        fg = theme.DIM if not (avail or equipped) else theme.ACCENT2
        buf.put_text(x + 1, ry, "  ".join(ops), fg, theme.BG)

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
