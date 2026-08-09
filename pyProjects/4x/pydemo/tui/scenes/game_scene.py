"""游戏主场景（枢纽）：地图作主场景 + 顶栏 + 操作提示栏 + 底部日志栏。

按 操作逻辑.md（新布局）：
- 主画面是地图拓扑（据点/小地点 + 驻军数），不再有"绑定键面板"网格。
- 顶部三行：
    y=0  当前场景可用按键操作（动态：随子场景返回或选单而变，默认列出 K/W/H/J/C/A/Z/M/T）
         ——由框架 hints_row="top" 原生绘制（render_hints 重写：键名 ACCENT + 说明 DIM）
    y=1  第 N 天 · 时段 · 月相(魔力恢复 +X)
    y=2  阵营 + 全局资源数值 + 信念
- 底部一行（y=h-1）：日志信息栏（最近若干条，WARN/DIM 区分）——场景自绘。
- 绑定键直接打开子场景；ESC 打开选单；按住 Tab 帝国总览 overlay。
- 省略"↑↓ 移动""回车 确认"提示（已无焦点网格可移动）。

返回值通道：子场景 POP(return_value) 携带的值由框架直接交付本场景 on_return()。
on_return 可返回 SceneResult 触发后续栈转换，故无需待决标志：esc_menu 回传
"to_menu" → 直接 POP 自身回主菜单；"end_turn" → 执行回合后若游戏结束推送
胜者消息框。返回主菜单在同一帧内完成，无需再按一次键中转。
"""
from __future__ import annotations

from typing import Any

from pyconsole.core import actions
from pyconsole.core.scene import Scene, SceneResult, PUSH, POP, NONE
from pyconsole.io.buffer import FrameBuffer
from pyconsole.io import theme
from pyconsole.io.widgets import draw_box, fill_rect, put_truncated
from pyconsole.io.width import text_width

from .. import controller as ctrl_mod
from .. import log
from .. import actions as g_actions
from pydemo.game.economy import RESOURCE_TYPES, RESOURCE_CN, BELIEF_CN
from .map_scene import render_topology, _render_legend, C_OWN, C_ENEMY, C_NEUTRAL, C_MINOR

# §2 资源净变动配色:增量 >0 绿、≤0 红(原型复用归属色)
C_GAIN = C_OWN    # 41 绿
C_LOSS = C_ENEMY  # 196 红

# 默认操作提示：游戏主场景下可用的绑定键（省略 ↑↓/回车 提示）。
DEFAULT_HINTS: list[tuple[str, str]] = [
    ("K", "科技"), ("W", "文化"), ("H", "百科"),
    ("C", "据点"), ("A", "部队"), ("Z", "招募"), ("X", "单位"),
    ("V", "据点总览"), ("I", "仓库"),
    ("M", "地图"), ("T", "下一回合"), ("ESC", "选单"), ("Tab", "总览"),
]


class GameScene(Scene):
    allow_status_overlay = True
    hints_row = "top"  # 框架在第 0 行原生绘制键提示栏（render_hints 重写）
    def __init__(self) -> None:
        super().__init__()
        self._hints: list[tuple[str, str]] = list(DEFAULT_HINTS)

    def on_enter(self, params: Any = None) -> None:
        self.params = params

    def on_return(self, value: Any) -> SceneResult:
        """子场景 POP 回传值。esc_menu 用 'end_turn'/'to_menu' 传指令。

        框架支持 on_return 返回 SceneResult 触发后续栈转换，故无需待决标志：
        'to_menu' / 游戏结束 直接 POP 自身回主菜单。'end_turn' 执行回合后若游戏
        结束则推送胜者消息框（消息框 POP 后会再回到本钩子，此时已是 None，走忽略分支）。
        """
        # 子场景返回后，操作提示恢复为主场景默认
        self._hints = list(DEFAULT_HINTS)
        if value == "end_turn":
            self._do_end_turn()
            if ctrl_mod.ctrl.g.is_over():
                from pyconsole.scenes.message import MessageScene
                w = ctrl_mod.ctrl.g.winner
                if w and w in ctrl_mod.ctrl.g.factions:
                    msg = f"游戏结束！\n\n胜者：{ctrl_mod.ctrl.g.factions[w].name}"
                else:
                    msg = "游戏结束（无胜者）"
                return PUSH(MessageScene(msg))
            return NONE()
        if value == "to_menu":
            return POP()
        # 其它返回值（MessageScene 的 None、各子场景的 None）忽略
        return NONE()

    # ---- 输入 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action

        # 1. 结束回合
        if a == g_actions.END_TURN:
            return self._end_turn_result()

        # 2. 绑定键直接打开子场景
        if a == g_actions.OPEN_TECH:
            from .tech_tree import TechTreeScene
            return PUSH(TechTreeScene())
        if a == g_actions.OPEN_CULTURE:
            from .culture_tree import CultureTreeScene
            return PUSH(CultureTreeScene())
        if a == actions.OPEN_WIKI:
            from .wiki import GameWikiScene
            return PUSH(GameWikiScene())
        if a == g_actions.OPEN_STRONGHOLD:
            from .stronghold import StrongholdScene
            return PUSH(StrongholdScene())
        if a == g_actions.OPEN_ARMY:
            from .army import ArmyScene
            return PUSH(ArmyScene())
        if a == g_actions.OPEN_UNIT:
            from .unit import UnitScene
            return PUSH(UnitScene())
        if a == g_actions.OPEN_INVENTORY:
            from .inventory import InventoryScene
            return PUSH(InventoryScene())
        if a == g_actions.OPEN_STRONGHOLD_OVERVIEW:
            from .stronghold_overview import StrongholdOverviewScene
            return PUSH(StrongholdOverviewScene())
        if a == g_actions.OPEN_RECRUIT:
            from .recruit import RecruitScene
            return PUSH(RecruitScene())
        if a == g_actions.OPEN_RECRUIT_UNIT:
            from .recruit_unit import RecruitUnitScene
            return PUSH(RecruitUnitScene())
        if a == g_actions.OPEN_MAP:
            from .map_scene import MapScene
            return PUSH(MapScene())

        # 3. 选单
        if a == actions.BACK:
            from .esc_menu import EscMenuScene
            return PUSH(EscMenuScene())

        return NONE()

    def _end_turn_result(self) -> SceneResult:
        """执行结束回合：AI 行动 + 时间推进。若游戏结束则推送胜者消息框。"""
        self._do_end_turn()
        if ctrl_mod.ctrl.g.is_over():
            from pyconsole.scenes.message import MessageScene
            w = ctrl_mod.ctrl.g.winner
            if w and w in ctrl_mod.ctrl.g.factions:
                msg = f"游戏结束！\n\n胜者：{ctrl_mod.ctrl.g.factions[w].name}"
            else:
                msg = "游戏结束（无胜者）"
            return PUSH(MessageScene(msg))
        return NONE()

    # ---- 回合 ----
    def _do_end_turn(self) -> None:
        ctrl_mod.ctrl.run_ai_and_advance()

    # ---- 渲染 ----
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()

        # 顶部：y=0 由框架绘制键提示栏（hints_row="top"）；y=1 日历；y=2 资源+信念
        self._render_calendar_line(buf, w, 1, g)
        self._render_resource_line(buf, w, 2, g, player)

        # 主画面：地图拓扑（夹在顶栏与底部日志栏之间）
        map_rect = (0, 3, w, h - 4)
        render_topology(buf, map_rect, g)
        # 地图图例放在主画面底部
        _render_legend(buf, 2, h - 2, w)

        # 底部日志栏（最底行，场景自绘）
        self._render_log(buf, w, h)

    def render_hints(self, buf: FrameBuffer, y: int, w: int) -> None:
        """y=0：当前场景可用按键操作（横排，键名 ACCENT + 说明 DIM）。

        覆盖框架默认的 draw_hints，以分色显示键名与说明。内容随 self._hints 动态变化。
        """
        buf.fill_rect(0, y, w, 1, " ", theme.BG, theme.BG)
        x = 1
        for i, (key, desc) in enumerate(self._hints):
            if i > 0:
                x = buf.put_text(x, y, "  ", theme.DIM, theme.BG)
            x = buf.put_text(x, y, key, theme.ACCENT, theme.BG)
            x = buf.put_text(x, y, f" {desc}", theme.DIM, theme.BG)
            if x >= w - 1:
                break

    def _render_calendar_line(self, buf: FrameBuffer, w: int, y: int, g) -> None:
        """y=1：第 N 天 · 时段 · 月相(魔力恢复 +X)。"""
        buf.fill_rect(0, y, w, 1, " ", theme.HEADING, theme.BG)
        cal_desc = g.calendar.describe()
        buf.put_text(1, y, cal_desc, theme.HEADING, theme.BG)

    def _render_resource_line(self, buf: FrameBuffer, w: int, y: int, g, player) -> None:
        """y=2：阵营 + 资源(§2:现存(净变动) 形式)+ 信念。

        净变动用 display_net(操作逻辑.md §2.1)= 本回合已结算净变动 + 下回合投影
        (建造/拆除后立刻刷新)。>0 绿色、≤0 红色(§2);无变动则只显示现存值。
        """
        buf.fill_rect(0, y, w, 1, " ", theme.DIM, theme.BG)
        x = buf.put_text(1, y, player.name, theme.HEADING, theme.BG)
        x = buf.put_text(x, y, "  ", theme.DIM, theme.BG)
        res = player.resources
        for k in RESOURCE_TYPES:
            v = res.get(k)
            if v == 0:
                continue
            net = res.resource(k).display_net()
            if net != 0:
                # §2:20(+1) 形式,净变动 >0 绿、≤0 红
                sign = "+" if net > 0 else ""
                delta_txt = f"({sign}{net})"
                txt = f"{RESOURCE_CN[k]}:{v}{delta_txt} "
                delta_fg = C_GAIN if net > 0 else C_LOSS
            else:
                txt = f"{RESOURCE_CN[k]}:{v} "
                delta_fg = None
            base_fg = theme.GOLD if k == "gold" else (
                theme.ACCENT if k in ("tech", "culture", "faith") else theme.FG)
            if x + text_width(txt) > w - 1:
                if w - 1 - x > 4:
                    buf.put_text(x, y, "…", theme.DIM, theme.BG)
                break
            # 先画存量部分(不带 delta_txt 的前缀)
            if net != 0:
                prefix = f"{RESOURCE_CN[k]}:{v}"
                x = buf.put_text(x, y, prefix, base_fg, theme.BG)
                x = buf.put_text(x, y, delta_txt, delta_fg, theme.BG)
                x = buf.put_text(x, y, " ", theme.DIM, theme.BG)
            else:
                x = buf.put_text(x, y, txt, base_fg, theme.BG)
        # 信念挤在右侧
        belief_txt = "  ".join(f"{BELIEF_CN[dim]}:{val:+d}" for dim, val in player.belief.values.items())
        bt_w = text_width(belief_txt)
        if bt_w < w - 1 and x + 2 + bt_w < w - 1:
            buf.put_text(w - 1 - bt_w, y, belief_txt, theme.ACCENT2, theme.BG)

    def _render_log(self, buf: FrameBuffer, w: int, h: int) -> None:
        """y=h-1：日志信息栏（最近若干条）。§6 委托共享渲染。"""
        log.render_log_bar(buf, 0, h - 1, w)

    # ---- Tab overlay：自定义帝国总览 ----
    def render_overlay(self, buf: FrameBuffer, w: int, h: int) -> bool:
        g = ctrl_mod.ctrl.g
        player = ctrl_mod.ctrl.player()
        pw, ph = 60, 16
        px = (w - pw) // 2
        py = (h - ph) // 2
        fill_rect(buf, px - 1, py - 1, pw + 2, ph + 2, " ", theme.FG, theme.OVERLAY_BG)
        draw_box(buf, px, py, pw, ph, title="帝国总览 (按住 Tab)",
                 fg=theme.OVERLAY_BORDER, bg=theme.OVERLAY_BG)

        cy = py + 2
        buf.put_text(px + 2, cy, f"阵营  {player.name}", theme.HEADING, theme.OVERLAY_BG)
        cy += 1
        buf.put_text(px + 2, cy, g.calendar.describe(), theme.ACCENT, theme.OVERLAY_BG)
        cy += 1
        buf.put_text(px + 2, cy,
                     f"据点 {len(player.stronghold_ids)}  部队 {len(player.army_ids)}  英雄 {len(player.hero_ids)}",
                     theme.FG, theme.OVERLAY_BG)
        cy += 1
        for dim, val in player.belief.values.items():
            buf.put_text(px + 2, cy, f"{BELIEF_CN[dim]}:{val:+d}", theme.ACCENT2, theme.OVERLAY_BG)
            cy += 1
        cy += 1
        buf.put_text(px + 2, cy, "资源", theme.HEADING, theme.OVERLAY_BG)
        cy += 1
        res = player.resources
        half = (len(RESOURCE_TYPES) + 1) // 2
        for i, k in enumerate(RESOURCE_TYPES):
            txt = f"{RESOURCE_CN[k]}:{res.get(k)}"
            if i < half:
                buf.put_text(px + 2, cy + i, txt, theme.FG, theme.OVERLAY_BG)
            else:
                buf.put_text(px + 30, cy + (i - half), txt, theme.FG, theme.OVERLAY_BG)
        if g.is_over():
            w_name = g.factions[g.winner].name if g.winner and g.winner in g.factions else "无"
            buf.put_text(px + 2, py + ph - 2, f"游戏结束 · 胜者 {w_name}", theme.WARN, theme.OVERLAY_BG)
        return True

    def get_hints(self) -> list[str]:
        # hints_row="top" 时框架调用 render_hints() 自绘分色提示栏，此处不用于渲染。
        return []
