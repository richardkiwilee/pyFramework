"""单位场景（键 X）：己方所有单位一览 + 单体详情 + 训练/装备按钮。

按 修正稿1.md §3：
- 左右两窗口。左侧列己方所有单位（场上部队成员 + 待命 + 己方据点驻军）；
  右侧展示单位详情：所有属性、所属部队、当前位置、等级与经验、训练所需资源、装备栏。
- 空格在左窗口时把焦点切进右侧详情；右侧有 4 个可交互"按钮"：训练 + 3 装备栏。
- 训练：消费资源直接获 +5 XP（走 Game.action_train）；可训练位见 is_trainable
  （在己方据点且该据点无敌方部队，或待命·可用）。不可训练/已训练/资源不足时按钮
  置灰，回车在日志栏提示原因。
- 装备栏：展示已装备神器（最多 3，u.artifacts）。回车进入神器选择子模式，列出所有
  已定义神器（原型不维护库存），回车装备到该槽位（走 Game.action_equip）。装备不
  受位置限制。可由 ArmyScene 通过 PUSH(UnitScene(), {"unit_id":...}) 委托进入并
  预选到指定单位。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, put_truncated
from pyconsole.io.width import text_width, char_width

from .. import controller as ctrl_mod
from .. import log
from pydemo.game.unit import ATTR_CN, TAG_CN, xp_to_next
from pydemo.game.economy import RESOURCE_CN

# 左右两窗口（x, y, w, h）。外框 (0,0,100,30)，y=3..27 给窗口，y=28 日志栏。
W1 = (1, 3, 33, 25)
W2 = (34, 3, 65, 25)

# 详情属性 3 列布局的起始 x（W2 内部）
_ATTR_COLS = (35, 56, 77)
# 16 个属性按 3 列分组（最后一行 1 个）
_ATTR_ROWS = [
    ["hp", "ap", "mana"],
    ["speed", "p_atk", "m_atk"],
    ["p_def", "m_def", "acc"],
    ["eva", "block", "crit"],
    ["luck", "will", "occupy"],
    ["leadership"],
]


class UnitScene(Scene):
    allow_status_overlay = True

    def __init__(self) -> None:
        super().__init__()
        self.focus = 0           # 左侧单位列表焦点
        self.list_scroll = 0
        self.in_detail = False   # False=左列表有焦点, True=右侧按钮有焦点
        self.btn_focus = 0       # 0=训练 1/2/3=装备栏
        # 装备子模式:正在为哪个槽位(0..2)选神器;None=不在子模式
        self.in_equip: int | None = None
        self.equip_scroll = 0
        self.equip_focus = 0

    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.in_detail = False
        self.btn_focus = 0
        self.in_equip = None
        # 委托进入:预选到指定单位并直接进详情(供 ArmyScene 编辑装备委托)
        if isinstance(params, dict) and params.get("unit_id"):
            entries = self._all_player_units()
            for i, (u, _) in enumerate(entries):
                if u.id == params["unit_id"]:
                    self.focus = i
                    self.in_detail = True
                    break
        self._safe_focus()

    # ---- 数据 ----
    def _all_player_units(self) -> list:
        """己方所有单位：(Unit, 显示标签)。顺序：部队成员 → 待命 → 驻军。"""
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        entries: list = []
        # 1. 场上部队成员
        for aid in player.army_ids:
            a = g.armies.get(aid)
            if not a:
                continue
            for uid in a.grid:
                if uid and uid in g.unit_index:
                    u = g.unit_index[uid]
                    if u.alive:
                        entries.append((u, f"{u.name} · {a.name}"))
        # 2. 待命（含可用/不可用）
        for uid, cd in player.standby.items():
            u = g.unit_index.get(uid)
            if u and u.alive:
                if cd <= 0:
                    lbl = f"{u.name} · 待命·可用"
                else:
                    lbl = f"{u.name} · 待命·不可用{cd}"
                entries.append((u, lbl))
        # 3. 己方据点驻军
        for sid in player.stronghold_ids:
            sh = g.map.strongholds.get(sid)
            if not sh:
                continue
            for a in g.armies.values():
                if a.is_garrison and a.node_id == sid and a.owner == player.id:
                    for uid in a.grid:
                        if uid and uid in g.unit_index:
                            u = g.unit_index[uid]
                            if u.alive:
                                entries.append((u, f"{u.name} · {sh.name}驻军"))
        return entries

    def _safe_focus(self) -> list:
        """夹住焦点到合法范围，返回当前单位列表。"""
        entries = self._all_player_units()
        if not entries:
            self.focus = 0
            self.in_detail = False
            return entries
        if self.focus >= len(entries):
            self.focus = len(entries) - 1
        return entries

    def _selected_unit(self):
        entries = self._safe_focus()
        if not entries:
            return None
        return entries[self.focus][0]

    def _train_status(self, u) -> str:
        # 返回 "" 表示可训练；否则返回不可原因（用于按钮置灰与日志提示）。
        g = ctrl_mod.ctrl.g
        if getattr(u, "_trained_this_turn", False):
            return "本回合已训练"
        ok, why = g.is_trainable(u)
        if not ok:
            return f"不可训练:{why}"
        if not ctrl_mod.ctrl.player().resources.can_afford(g._train_cost(u)):
            return "资源不足"
        return ""

    def _artifact_defs(self) -> list:
        """所有已定义神器 (id, Artifact)，按 id 排序，便于稳定展示。"""
        g = ctrl_mod.ctrl.g
        return sorted(g.artifact_defs.items(), key=lambda kv: kv[0])

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        # 装备子模式优先处理
        if self.in_equip is not None:
            return self._handle_equip(a)
        entries = self._safe_focus()
        if not entries:
            if a == actions.BACK:
                return POP()
            return NONE()

        if a == actions.BACK:
            if self.in_detail:
                self.in_detail = False
                return NONE()
            return POP()
        if a == actions.LEFT:
            if self.in_detail:
                self.in_detail = False
            return NONE()
        if a == actions.SELECT:   # 空格：左右焦点切换
            self.in_detail = not self.in_detail
            if self.in_detail:
                self.btn_focus = 0
            return NONE()
        if a in (actions.UP, actions.DOWN):
            self._move_vertical(a, entries)
            return NONE()
        if a == actions.CONFIRM:
            if self.in_detail:
                self._activate_button(self._selected_unit())
            else:
                self.in_detail = True
                self.btn_focus = 0
            return NONE()
        return NONE()

    def _move_vertical(self, a: str, entries: list) -> None:
        delta = -1 if a == actions.UP else 1
        if self.in_detail:
            self.btn_focus = (self.btn_focus + delta) % 4
            return
        self.focus = (self.focus + delta) % len(entries)
        self._clamp_scroll()

    def _clamp_scroll(self) -> None:
        visible = W1[3] - 2
        if self.focus < self.list_scroll:
            self.list_scroll = self.focus
        elif self.focus >= self.list_scroll + visible:
            self.list_scroll = self.focus - visible + 1

    def _activate_button(self, u) -> None:
        if u is None:
            return
        if self.btn_focus == 0:
            self._do_train(u)
        else:
            # 装备栏：进入神器选择子模式
            self.in_equip = self.btn_focus - 1
            self.equip_focus = 0
            self.equip_scroll = 0

    def _handle_equip(self, a) -> SceneResult:
        arts = self._artifact_defs()
        if a == actions.BACK:
            self.in_equip = None
            return NONE()
        if a in (actions.UP, actions.DOWN):
            if not arts:
                return NONE()
            delta = -1 if a == actions.UP else 1
            self.equip_focus = (self.equip_focus + delta) % len(arts)
            # 滚动夹住
            visible = 8
            if self.equip_focus < self.equip_scroll:
                self.equip_scroll = self.equip_focus
            elif self.equip_focus >= self.equip_scroll + visible:
                self.equip_scroll = self.equip_focus - visible + 1
            return NONE()
        if a == actions.CONFIRM:
            if not arts:
                self.in_equip = None
                return NONE()
            u = self._selected_unit()
            if u is None:
                self.in_equip = None
                return NONE()
            aid = arts[self.equip_focus][0]
            msg = ctrl_mod.ctrl.g.action_equip(ctrl_mod.ctrl.g.player_id, u.id, aid, self.in_equip)
            ok = not msg.startswith("失败")
            log.push(msg, warn=not ok)
            self.in_equip = None
            return NONE()
        return NONE()

    def _do_train(self, u) -> None:
        g = ctrl_mod.ctrl.g
        msg = g.action_train(g.player_id, u.id)
        ok = not msg.startswith("失败")
        log.push(msg, warn=not ok)

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        entries = self._safe_focus()
        draw_box(buf, 0, 0, w, h, title="单位一览")
        buf.put_text(2, 1, f"己方单位 {len(entries)} 名", theme.HEADING, theme.BG)
        for cx in range(1, w - 1):
            buf.set_char(cx, 2, "─", theme.BORDER, theme.BG)
        self._render_w1(buf, entries)
        self._render_w2(buf)
        # §6 底部日志栏 y=h-2（键提示由框架在 h-1 绘制）
        log.render_log_bar(buf, 0, h - 2, w)

    def _render_w1(self, buf, entries: list) -> None:
        x, y, ww, hh = W1
        active = not self.in_detail
        border = theme.ACCENT if active else theme.BORDER
        draw_box(buf, x, y, ww, hh, title="单位列表", fg=border)
        if not entries:
            buf.put_text(x + 1, y + 1, "（无单位）", theme.DIM, theme.BG)
            return
        self._clamp_scroll()
        player = ctrl_mod.ctrl.player()
        start = self.list_scroll
        end = min(len(entries), start + hh - 2)
        for i in range(start, end):
            ry = y + 1 + (i - start)
            if ry >= y + hh - 1:
                break
            u, label = entries[i]
            if u.is_hero:
                fg = theme.ACCENT2
            elif u.id in player.standby:
                fg = theme.DIM
            else:
                fg = theme.FG
            self._draw_row(buf, x, ry, ww, label, fg, i, self.focus, active)
        if len(entries) > hh - 2:
            buf.put_text(x + ww - 9, y, f"({self.focus + 1}/{len(entries)})",
                         theme.DIM, theme.BG)

    def _draw_row(self, buf, x, y, ww, label, fg, idx, focus_idx, active,
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

    def _render_w2(self, buf) -> None:
        x, y, ww, hh = W2
        active = self.in_detail
        border = theme.ACCENT if active else theme.BORDER
        draw_box(buf, x, y, ww, hh, title="单位详情", fg=border)
        u = self._selected_unit()
        if u is None:
            buf.put_text(x + 1, y + 1, "（请选择左侧单位）", theme.DIM, theme.BG)
            return
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()

        ry = y + 1
        # 名称
        buf.put_text(x + 1, ry, f"名称: {u.name}", theme.HEADING, theme.BG); ry += 1
        # 词条 | 英雄
        tagstr = "/".join(TAG_CN.get(t, t) for t in sorted(u.tags))
        buf.put_text(x + 1, ry, f"词条: {tagstr}", theme.DIM, theme.BG)
        buf.put_text(x + 30, ry, f"英雄: {'是' if u.is_hero else '否'}", theme.DIM, theme.BG); ry += 1
        # 所属部队 | 位置
        if u.army_id and u.army_id in g.armies:
            a = g.armies[u.army_id]
            if a.is_garrison:
                sh = g.map.strongholds.get(a.node_id)
                army_txt = f"{sh.name if sh else a.node_id}驻军"
            else:
                army_txt = a.name
        elif u.id in player.standby:
            cd = player.standby[u.id]
            army_txt = f"待命·{'可用' if cd <= 0 else '不可用' + str(cd)}"
        else:
            army_txt = "无"
        buf.put_text(x + 1, ry, f"所属部队: {army_txt}", theme.FG, theme.BG)
        node_txt = g.map.node_name(u.node_id) if u.node_id else "无"
        buf.put_text(x + 32, ry, f"位置: {node_txt}", theme.FG, theme.BG); ry += 1
        # 等级/经验 | 生命
        buf.put_text(x + 1, ry, f"等级: Lv{u.level}  经验: {u.xp}/{xp_to_next(u.level)}",
                     theme.ACCENT, theme.BG)
        buf.put_text(x + 32, ry, f"生命: {int(u.cur_hp)}/{int(u.base.get('hp', 1))}",
                     theme.DIM, theme.BG); ry += 1
        # 分隔
        self._hline(buf, x, ry, ww); ry += 1
        # 属性
        buf.put_text(x + 1, ry, "属性", theme.ACCENT, theme.BG); ry += 1
        for row_attrs in _ATTR_ROWS:
            for c, attr in enumerate(row_attrs):
                if c >= len(_ATTR_COLS):
                    break
                cx = _ATTR_COLS[c]
                name = ATTR_CN.get(attr, attr)
                if attr == "hp":
                    cell = f"{name}: {int(u.cur_hp)}/{int(u.base.get('hp', 1))}"
                else:
                    cell = f"{name}: {int(u.base.get(attr, 0))}"
                put_truncated(buf, cx, ry, cell, 19, theme.FG, theme.BG)
            ry += 1
        # 分隔
        self._hline(buf, x, ry, ww); ry += 1
        # 维护费
        maint_txt = self._cost_text(g._maintenance_cost(u))
        buf.put_text(x + 1, ry, f"维护费: {maint_txt}", theme.DIM, theme.BG); ry += 1
        # 训练消耗 / 不可训练原因
        status = self._train_status(u)
        if status == "":
            cost_txt = self._cost_text(g._train_cost(u))
            buf.put_text(x + 1, ry, f"训练消耗: {cost_txt}", theme.GOLD, theme.BG)
        else:
            buf.put_text(x + 1, ry, f"训练: {status}", theme.WARN, theme.BG)
        # 按钮行动条（底部）
        self._render_buttons(buf, u)
        # 装备子模式覆盖层（在按钮上方区域列神器）
        if self.in_equip is not None:
            self._render_equip_picker(buf, u)

    def _render_equip_picker(self, buf, u) -> None:
        x, y, ww, hh = W2
        # 在按钮行上方画一个候选框:y+hh-8 .. y+hh-3(5 行可视)
        top = y + hh - 9
        bx = x + 1
        bw = ww - 2
        draw_box(buf, bx, top, bw, 7, title=f"装备栏{self.in_equip + 1} · 选神器(ESC 取消)",
                 fg=theme.ACCENT)
        arts = self._artifact_defs()
        if not arts:
            buf.put_text(bx + 1, top + 1, "（无神器定义）", theme.WARN, theme.BG)
            return
        visible = 5
        start = self.equip_scroll
        end = min(len(arts), start + visible)
        for i in range(start, end):
            row = i - start
            ry = top + 1 + row
            aid, art = arts[i]
            # 当前槽位已装的神器标 "(已装)"
            cur = u.artifacts[self.in_equip] if self.in_equip < len(u.artifacts) else None
            tag = " (已装)" if cur == aid else ""
            label = f"{art.name}{tag}"
            self._draw_row(buf, bx, ry, bw, label, theme.FG, i, self.equip_focus,
                           True, truncate=True)
        if len(arts) > visible:
            buf.put_text(bx + bw - 8, top, f"({self.equip_focus + 1}/{len(arts)})",
                         theme.DIM, theme.BG)

    def _render_buttons(self, buf, u) -> None:
        x, y, ww, hh = W2
        yb = y + hh - 2           # 按钮行
        self._hline(buf, x, yb - 1, ww)
        rects = self._button_rects(yb)
        labels = self._button_labels(u)
        status = self._train_status(u) if u is not None else "无单位"
        for i, (bx, _, bw) in enumerate(rects):
            focused = self.in_detail and self.btn_focus == i
            if i == 0:
                disabled = bool(status)
                fg = theme.DIM if disabled else theme.ACCENT
            else:
                slot = i - 1
                has = u is not None and slot < len(u.artifacts) and u.artifacts[slot]
                fg = theme.FG if has else theme.DIM
            self._render_button(buf, bx, yb, bw, labels[i], focused, fg)

    def _button_rects(self, yb: int) -> list:
        x, _, ww, _ = W2
        widths = [14, 15, 15, 15]
        cx = x + 1
        rects = []
        for wdt in widths:
            rects.append((cx, yb, wdt))
            cx += wdt + 1
        return rects

    def _button_labels(self, u) -> list:
        g = ctrl_mod.ctrl.g
        labels = ["训练"]
        for slot in range(3):
            if u is not None and slot < len(u.artifacts) and u.artifacts[slot]:
                aid = u.artifacts[slot]
                art = g.artifact_defs.get(aid)
                name = art.name if art else aid
            else:
                name = "空"
            labels.append(f"装备{slot + 1}:{name}")
        return labels

    def _render_button(self, buf, x, y, w, label, focused, fg) -> None:
        bg = theme.SELECTED_BG if focused else theme.BG
        tf = theme.SELECTED_FG if focused else fg
        buf.fill_rect(x, y, w, 1, " ", tf, bg)
        avail = w - 1
        lw = text_width(label)
        if lw > avail:
            put_truncated(buf, x + 1, y, label, avail, tf, bg)
        else:
            buf.put_text(x + max(1, (w - lw) // 2), y, label, tf, bg)

    def _hline(self, buf, x, y, ww) -> None:
        for cx in range(x + 1, x + ww - 1):
            buf.set_char(cx, y, "─", theme.BORDER, theme.BG)

    @staticmethod
    def _cost_text(cost: dict) -> str:
        if not cost:
            return "免费"
        return "  ".join(f"{RESOURCE_CN.get(k, k)}:{v}" for k, v in cost.items())

    def get_hints(self) -> list[str]:
        if self.in_equip is not None:
            return ["↑↓ 选神器", "回车 装备", "ESC 取消"]
        if self.in_detail:
            return ["↑↓ 切换按钮", "回车 确认", "空格/← 回列表", "ESC 返回"]
        return ["↑↓ 选单位", "空格/回车 进详情", "ESC 返回"]


def _truncate(text: str, max_w: int) -> str:
    """按显示宽度截断并加省略号。"""
    if text_width(text) <= max_w:
        return text
    out = ""
    w = 0
    for ch in text:
        cw = char_width(ch)
        if w + cw > max_w - 1:
            break
        out += ch
        w += cw
    return out + "…"

