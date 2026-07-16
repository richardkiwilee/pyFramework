"""21 点人机对战场景。

规则（grilling 确认）：
- 一副 52 张牌（无大小王），双方轮流操作（每次一个动作后交给对方，除非对方已停牌）。
- 三选一：①从牌堆抽牌（抽到后可选打出上桌或藏入袖子）；②从袖子选一张打出；③pass 停止抽牌。
- 袖子最多 2 张；已满再藏则丢弃最左边（最旧）那张。
- 牌桌每方最多 5 张，到 5 张自动 pass。
- 爆牌（>21）上桌即判、当场结算。A=1/11 取最优，JQK=10。
- 结算：一方爆→对方胜；双爆比小；双方停→比点数（高胜、等平）。
- 随机先后手；AI 启发式概率决策；AI 动作用 tick 钩子 + 时间队列做延迟动画。

阶段（phase）：
  menu          玩家回合主菜单（抽牌/打出袖子牌/pass）
  holding       刚抽到一张牌，待决定打出或藏入袖子
  sleeve_select 从袖子里选一张打出
  ai_turn       AI 行动中（忽略玩家输入，Esc 可放弃对局返回）
  settled       已结算，任意键返回主菜单
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any, Callable

from ..core import actions
from ..core.scene import Scene, SceneResult, POP, NONE
from ..game.cards import Card, hand_score, new_deck, rank_label, suit_color, shuffle
from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.widgets import draw_box, put_centered
from ..io.width import text_width

MAX_TABLE = 5          # 桌面最多 5 张
MAX_SLEEVE = 2         # 袖子最多 2 张
AI_STEP_DELAY = 0.7    # AI 每个可见动作的间隔（秒）
CARD_W = 6             # ASCII 牌宽（含边框）
CARD_H = 4             # ASCII 牌高
CARD_GAP = 1           # 牌间距
TOKEN_W = 5            # 袖子牌 token 宽度


@dataclass
class Side:
    """一方（玩家或 AI）的牌。"""
    table: list[Card] = field(default_factory=list)
    sleeve: list[Card] = field(default_factory=list)
    passed: bool = False
    busted: bool = False

    def score(self) -> tuple[int, bool]:
        return hand_score(self.table)


class Game21Scene(Scene):
    allow_status_overlay = False

    def __init__(self, rng: random.Random | None = None) -> None:
        super().__init__()
        self._rng = rng if rng is not None else random.Random()
        self.deck: list[Card] = []
        self.player = Side()
        self.ai = Side()
        self.turn: str = "player"            # "player" | "ai"
        self.phase: str = "menu"
        self.held_card: Card | None = None   # 刚抽到、待决定的牌
        self.menu_focus: int = 0
        self.sleeve_focus: int = 0
        self._holding_focus: int = 0         # holding 阶段两选项焦点（0=打出,1=藏入袖子）
        self.log: list[str] = []
        self.result: str | None = None       # "win" | "lose" | "draw"
        self._tasks: list[tuple[float, Callable[[], None]]] = []
        self._last_now: float = 0.0
        self._ai_turn_pending: bool = False  # 待 on_tick 启动 AI 回合（保证延迟从真实时间起算）

    # ---- 生命周期 ----
    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.deck = new_deck()
        shuffle(self.deck, self._rng)
        self.turn = "player" if self._rng.random() < 0.5 else "ai"
        self.log.append("新对局开始。")
        self.log.append(f"{'你' if self.turn == 'player' else 'AI'} 先手。")
        if self.turn == "ai":
            self._start_ai_turn()
        else:
            self.phase = "menu"

    # ---- 定时任务 ----
    def schedule(self, delay: float, fn: Callable[[], None]) -> None:
        self._tasks.append((self._last_now + delay, fn))

    def on_tick(self, now: float) -> None:
        self._last_now = now
        # 启动挂起的 AI 回合（延迟从真实 now 起算，而非 on_enter 时的 0.0）
        if self._ai_turn_pending and self.phase == "ai_turn":
            self._ai_turn_pending = False
            self.schedule(AI_STEP_DELAY, self._ai_act)
        if not self._tasks:
            return
        ready = [t for t in self._tasks if t[0] <= now]
        if not ready:
            return
        self._tasks = [t for t in self._tasks if t[0] > now]
        ready.sort(key=lambda t: t[0])
        for _, fn in ready:
            try:
                fn()
            except Exception:  # noqa: BLE001 - 定时任务不应让场景崩
                self.log.append("(内部错误)")

    # ---- 抽牌 ----
    def _draw_from_deck(self) -> Card:
        if not self.deck:
            self.deck = new_deck()
            shuffle(self.deck, self._rng)
            self.log.append("牌堆耗尽，重新洗牌。")
        return self.deck.pop()

    # ---- 玩家回合主菜单选项（动态）----
    def _menu_items(self) -> list[str]:
        items = ["抽牌"]
        if self.player.sleeve:
            items.append("从袖子打出")
        items.append("Pass 停牌")
        return items

    # ---- 输入分发 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if self.phase == "settled":
            return POP()
        # sleeve_select：Esc 取消选择回菜单（不放弃对局）
        if self.phase == "sleeve_select" and a == actions.BACK:
            self.phase = "menu"
            self.menu_focus = 0
            return NONE()
        # 其余阶段：Esc 放弃对局返回主菜单
        if a == actions.BACK:
            return POP()

        if self.phase == "menu":
            return self._handle_menu(event)
        if self.phase == "holding":
            return self._handle_holding(event)
        if self.phase == "sleeve_select":
            return self._handle_sleeve_select(event)
        # ai_turn：忽略其余输入
        return NONE()

    def _handle_menu(self, event) -> SceneResult:
        a = event.action
        items = self._menu_items()
        if a in (actions.UP, actions.DOWN):
            self.menu_focus = (self.menu_focus + (1 if a == actions.DOWN else -1)) % len(items)
            return NONE()
        if a == actions.SELECT:
            return NONE()  # 空格无效（沿用主菜单约定）
        if a == actions.CONFIRM:
            return self._activate_menu(self.menu_focus)
        if a == actions.CHAR and event.char.isdigit():
            idx = int(event.char) - 1
            if 0 <= idx < len(items):
                return self._activate_menu(idx)
        return NONE()

    def _activate_menu(self, idx: int) -> SceneResult:
        items = self._menu_items()
        if idx < 0 or idx >= len(items):
            return NONE()
        choice = items[idx]
        if choice == "抽牌":
            self.held_card = self._draw_from_deck()
            self.log.append(f"你抽到 {self.held_card}。")
            self.phase = "holding"
            self._holding_focus = 0
            return NONE()
        if choice == "从袖子打出":
            if len(self.player.sleeve) > 1:
                self.phase = "sleeve_select"
                self.sleeve_focus = 0
            else:
                self._play_from_sleeve(0, "player")
                self._after_play("player")
            return NONE()
        if choice == "Pass 停牌":
            self.player.passed = True
            self.log.append("你选择停牌。")
            self.end_turn("player")
            return NONE()
        return NONE()

    def _handle_holding(self, event) -> SceneResult:
        a = event.action
        if a in (actions.UP, actions.DOWN, actions.LEFT, actions.RIGHT):
            self._holding_focus = 1 - self._holding_focus
            return NONE()
        if a == actions.CONFIRM:
            return self._resolve_holding(self._holding_focus)
        if a == actions.SELECT:
            return NONE()
        if a == actions.CHAR:
            if event.char == "1":
                return self._resolve_holding(0)
            if event.char == "2":
                return self._resolve_holding(1)
        return NONE()

    def _resolve_holding(self, choice: int) -> SceneResult:
        """choice 0=打出上桌, 1=藏入袖子。"""
        assert self.held_card is not None
        card = self.held_card
        self.held_card = None
        if choice == 0:
            self._play_to_table(self.player, card, "player")
        else:
            self._stash_to_sleeve(self.player, card, "player")
        self._after_play("player")
        return NONE()

    def _handle_sleeve_select(self, event) -> SceneResult:
        a = event.action
        n = len(self.player.sleeve)
        if a == actions.UP:
            self.sleeve_focus = (self.sleeve_focus - 1) % n
            return NONE()
        if a == actions.DOWN:
            self.sleeve_focus = (self.sleeve_focus + 1) % n
            return NONE()
        if a == actions.CONFIRM:
            idx = self.sleeve_focus
            self._play_from_sleeve(idx, "player")
            self._after_play("player")
            return NONE()
        return NONE()

    # ---- 出牌/藏牌核心 ----
    def _play_to_table(self, side: Side, card: Card, owner: str) -> None:
        side.table.append(card)
        who = "你" if owner == "player" else "AI"
        self.log.append(f"{who}打出 {card}。")
        score, busted = side.score()
        if busted:
            side.busted = True
            self.log.append(f"{who}爆牌！")
        elif len(side.table) >= MAX_TABLE:
            side.passed = True
            self.log.append(f"{who}桌面已满 {MAX_TABLE} 张，自动停牌。")

    def _stash_to_sleeve(self, side: Side, card: Card, owner: str) -> None:
        who = "你" if owner == "player" else "AI"
        if len(side.sleeve) >= MAX_SLEEVE:
            dropped = side.sleeve.pop(0)  # 丢弃最左边（最旧）
            self.log.append(f"{who}袖子已满，弃掉 {dropped}。")
        side.sleeve.append(card)
        self.log.append(f"{who}把 {card} 藏入袖子。")

    def _play_from_sleeve(self, idx: int, owner: str) -> None:
        side = self.player if owner == "player" else self.ai
        if idx < 0 or idx >= len(side.sleeve):
            return
        card = side.sleeve.pop(idx)
        self._play_to_table(side, card, owner)

    def _after_play(self, owner: str) -> None:
        """打牌/藏牌后检查结算或切换回合。"""
        self.end_turn(owner)

    # ---- 回合切换 / 结算 ----
    def end_turn(self, side_name: str) -> None:
        if self.player.busted or self.ai.busted:
            self.settle()
            return
        if self.player.passed and self.ai.passed:
            self.settle()
            return
        cur = self.player if side_name == "player" else self.ai
        other_name = "ai" if side_name == "player" else "player"
        other = self.ai if side_name == "player" else self.player
        if cur.passed or cur.busted:
            # 当前方已停：交给对方（对方也停则结算，上面已处理）
            self.turn = other_name
        else:
            # 当前方还能继续：对方未停则交给对方，否则本方继续
            self.turn = side_name if (other.passed or other.busted) else other_name
        if self.turn == "ai":
            self._start_ai_turn()
        else:
            self.phase = "menu"
            self.menu_focus = 0
            # 聚焦可能因袖子变化越界，夹一下
            items = self._menu_items()
            if self.menu_focus >= len(items):
                self.menu_focus = 0

    def settle(self) -> None:
        ps, pb = self.player.score()
        as_, ab = self.ai.score()
        if pb and ab:
            self.result = "win" if ps < as_ else ("lose" if ps > as_ else "draw")
        elif pb:
            self.result = "lose"
        elif ab:
            self.result = "win"
        else:
            self.result = "win" if ps > as_ else ("lose" if ps < as_ else "draw")
        self.phase = "settled"
        self._tasks.clear()
        self._ai_turn_pending = False
        self.log.append("对局结束。")

    # ---- AI ----
    def _start_ai_turn(self) -> None:
        self.phase = "ai_turn"
        self._ai_turn_pending = True

    def _ai_act(self) -> None:
        """AI 启发式决策：pass / 抽牌 / 出袖子。"""
        if self.phase != "ai_turn":
            return
        if self.ai.passed or self.ai.busted:
            self.end_turn("ai")
            return
        score, _ = self.ai.score()
        ps, _ = self.player.score()
        # 点数足够高 → 大概率停牌
        if score >= 17 and self._rng.random() < 0.85:
            self.ai.passed = True
            self.log.append("AI 选择停牌。")
            self.schedule(AI_STEP_DELAY, lambda: self.end_turn("ai"))
            return
        if score <= 11:
            self._ai_draw()
            return
        must = self.player.passed and ps > score  # 玩家已停且点数更高，AI 被迫追
        if must or self._rng.random() < 0.6:
            self._ai_draw()
            return
        # 偶尔从袖子出牌（若有且打出不爆）
        if self.ai.sleeve and self._rng.random() < 0.3:
            for i, c in enumerate(self.ai.sleeve):
                _, b2 = hand_score(self.ai.table + [c])
                if not b2:
                    self._play_from_sleeve(i, "ai")
                    self.schedule(AI_STEP_DELAY, lambda: self.end_turn("ai"))
                    return
        self.ai.passed = True
        self.log.append("AI 选择停牌。")
        self.schedule(AI_STEP_DELAY, lambda: self.end_turn("ai"))

    def _ai_draw(self) -> None:
        card = self._draw_from_deck()
        self.held_card = card
        self.log.append("AI 抽了一张牌。")
        self.schedule(AI_STEP_DELAY, self._ai_resolve_held)

    def _ai_resolve_held(self) -> None:
        if self.held_card is None:
            return
        card = self.held_card
        self.held_card = None
        _, busted = hand_score(self.ai.table + [card])
        if not busted:
            # 多数直接打出；小概率藏（袖子有空位）
            if len(self.ai.sleeve) < MAX_SLEEVE and self._rng.random() < 0.15:
                self._stash_to_sleeve(self.ai, card, "ai")
            else:
                self._play_to_table(self.ai, card, "ai")
        else:
            # 会爆：优先藏入袖子（有空位），否则被迫打出爆牌
            if len(self.ai.sleeve) < MAX_SLEEVE:
                self._stash_to_sleeve(self.ai, card, "ai")
            else:
                self._play_to_table(self.ai, card, "ai")
        self.schedule(AI_STEP_DELAY, lambda: self.end_turn("ai"))

    # ==================== 渲染 ====================
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title="21点 · 人机对战")

        # ---- AI 区 ----
        as_score, as_busted = self.ai.score()
        ai_label = f"【AI 对手】 点数:{as_score}" + ("  爆牌!" if as_busted else "")
        buf.put_text(2, 1, ai_label, theme.WARN if as_busted else theme.ACCENT2, theme.BG)
        deck_txt = f"牌堆剩余:{len(self.deck)}"
        buf.put_text(w - 2 - text_width(deck_txt), 1, deck_txt, theme.DIM, theme.BG)
        self._render_table(buf, 2, self.ai.table)
        buf.put_text(2, 6, "AI 袖子:", theme.DIM, theme.BG)
        self._render_sleeve_tokens(buf, 11, 6, self.ai.sleeve, face_up=False)

        self._hline(buf, 1, 7, w - 1)

        # ---- 状态 / 握牌区 ----
        put_centered(buf, 8, self._status_text(), w, self._status_color(), theme.BG)
        if self.phase == "holding" and self.held_card is not None:
            x = (w - CARD_W) // 2
            self._draw_card(buf, x, 9, self.held_card, face_up=True, hl=True)

        self._hline(buf, 1, 13, w - 1)

        # ---- 玩家区 ----
        self._render_table(buf, 14, self.player.table)
        buf.put_text(2, 18, "你的袖子:", theme.DIM, theme.BG)
        self._render_sleeve_tokens(buf, 12, 18, self.player.sleeve, face_up=True,
                                   selectable=(self.phase == "sleeve_select"))
        ps_score, ps_busted = self.player.score()
        p_label = f"【你】 点数:{ps_score}" + ("  爆牌!" if ps_busted else "")
        put_centered(buf, 19, p_label, w, theme.WARN if ps_busted else theme.HEADING, theme.BG)

        self._hline(buf, 1, 20, w - 1)

        # ---- 操作面板 / 日志 ----
        self._render_panel(buf, w)
        self._render_log(buf, w)

        if self.phase == "settled":
            self._render_settlement(buf, w, h)

    # ---- 渲染辅助 ----
    def _status_text(self) -> str:
        if self.phase == "settled":
            return {"win": "你赢了！", "lose": "你输了。", "draw": "平局。"}.get(self.result or "", "对局结束")
        if self.phase == "ai_turn":
            return "AI 思考中…"
        if self.phase == "holding":
            return f"你抽到 {self.held_card} —— 打出 还是 藏入袖子？"
        if self.phase == "sleeve_select":
            return "选择袖子里的牌打出"
        if self.player.passed:
            return "你已停牌，等待 AI…"
        return "你的回合"

    def _status_color(self) -> int:
        if self.phase == "settled":
            return {"win": theme.GOLD, "lose": theme.WARN, "draw": theme.DIM}.get(self.result or "", theme.FG)
        if self.phase == "ai_turn":
            return theme.ACCENT2
        if self.phase == "holding":
            return theme.ACCENT
        return theme.HEADING

    def _render_table(self, buf: FrameBuffer, y: int, table: list[Card]) -> None:
        if not table:
            buf.put_text(2, y, "(无牌)", theme.DIM, theme.BG)
            return
        w = buf.w
        total = len(table) * CARD_W + max(0, len(table) - 1) * CARD_GAP
        x = max(2, (w - total) // 2)
        for c in table:
            self._draw_card(buf, x, y, c, face_up=True, hl=False)
            x += CARD_W + CARD_GAP

    def _render_sleeve_tokens(self, buf: FrameBuffer, x: int, y: int, sleeve: list[Card],
                              face_up: bool, selectable: bool = False) -> None:
        if not sleeve:
            buf.put_text(x, y, "(空)", theme.DIM, theme.BG)
            return
        cx = x
        for i, c in enumerate(sleeve):
            hl = selectable and i == self.sleeve_focus
            bg = theme.SELECTED_BG if hl else theme.BG
            border = theme.ACCENT if hl else theme.DIM
            buf.set_char(cx, y, "[", border, bg)
            buf.set_char(cx + TOKEN_W - 1, y, "]", border, bg)
            if face_up:
                fg = suit_color(c.suit)
                label = rank_label(c.rank)
                if len(label) == 1:
                    buf.put_text(cx + 1, y, label + " ", fg, bg)
                else:  # "10"
                    buf.put_text(cx + 1, y, label, fg, bg)
                buf.set_char(cx + 3, y, c.suit, fg, bg)
            else:
                for dx in (1, 2, 3):
                    buf.set_char(cx + dx, y, "▓", theme.DIM, bg)
            cx += TOKEN_W + CARD_GAP

    def _draw_card(self, buf: FrameBuffer, x: int, y: int, card: Card,
                   face_up: bool = True, hl: bool = False) -> None:
        """画一张 4 行 ASCII 牌。"""
        fg = suit_color(card.suit)
        bg = theme.SELECTED_BG if hl else theme.BG
        border = theme.ACCENT if hl else theme.BORDER
        x2 = x + CARD_W - 1
        y2 = y + CARD_H - 1
        buf.set_char(x, y, "┌", border, bg)
        buf.set_char(x2, y, "┐", border, bg)
        buf.set_char(x, y2, "└", border, bg)
        buf.set_char(x2, y2, "┘", border, bg)
        for cx in range(x + 1, x2):
            buf.set_char(cx, y, "─", border, bg)
            buf.set_char(cx, y2, "─", border, bg)
        for ry in range(y + 1, y2):
            buf.set_char(x, ry, "│", border, bg)
            buf.set_char(x2, ry, "│", border, bg)
        if face_up:
            label = rank_label(card.rank)
            lw = text_width(label)
            buf.put_text(x + 1, y + 1, label, fg, bg)          # 左上
            buf.set_char(x + 1 + lw, y + 1, card.suit, fg, bg)
            buf.set_char(x + (CARD_W // 2), y + 2, card.suit, theme.HEADING, bg)  # 中央
            buf.put_text(x2 - lw, y2 - 1, label, fg, bg)       # 右下
        else:
            for ry in range(y + 1, y2):
                for cx in range(x + 1, x2):
                    buf.set_char(cx, ry, "░", theme.DIM, bg)

    def _render_panel(self, buf: FrameBuffer, w: int) -> None:
        y0 = 21
        if self.phase == "menu":
            items = self._menu_items()
            focus = min(self.menu_focus, len(items) - 1)
            buf.put_text(2, y0, "操作:", theme.ACCENT, theme.BG)
            for i, label in enumerate(items):
                ry = y0 + 1 + i
                marker = "▶" if i == focus else " "
                text = f"{marker} {i + 1}. {label}"
                if i == focus:
                    buf.fill_rect(2, ry, w - 4, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                    buf.put_text(2, ry, text, theme.SELECTED_FG, theme.SELECTED_BG)
                else:
                    buf.put_text(2, ry, text, theme.FG, theme.BG)
        elif self.phase == "holding":
            buf.put_text(2, y0, "刚抽到的牌如何处置？", theme.ACCENT, theme.BG)
            full = "（袖子已满，藏入将弃最旧）" if len(self.player.sleeve) >= MAX_SLEEVE else ""
            opts = ["1. 打出上桌", f"2. 藏入袖子{full}"]
            for i, label in enumerate(opts):
                ry = y0 + 1 + i
                marker = "▶" if i == self._holding_focus else " "
                if i == self._holding_focus:
                    buf.fill_rect(2, ry, w - 4, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                    buf.put_text(2, ry, f"{marker} {label}", theme.SELECTED_FG, theme.SELECTED_BG)
                else:
                    buf.put_text(2, ry, f"{marker} {label}", theme.FG, theme.BG)
        elif self.phase == "sleeve_select":
            buf.put_text(2, y0, "选择袖子里的牌打出:", theme.ACCENT, theme.BG)
            buf.put_text(2, y0 + 1, "↑↓ 切换 · 回车 打出 · Esc 返回菜单", theme.DIM, theme.BG)
        elif self.phase == "ai_turn":
            buf.put_text(2, y0, "AI 回合，请稍候…", theme.DIM, theme.BG)
            buf.put_text(2, y0 + 1, "（按 Esc 放弃对局返回主菜单）", theme.DIM, theme.BG)
        elif self.phase == "settled":
            buf.put_text(2, y0, "对局已结束，按任意键返回主菜单。", theme.GOLD, theme.BG)

    def _render_log(self, buf: FrameBuffer, w: int) -> None:
        # 行 27-28 给日志；行 29 由 App 画 hints，勿占用
        recent = self.log[-2:]
        if not recent:
            return
        buf.put_text(2, 27, "日志:", theme.DIM, theme.BG)
        buf.put_text(8, 27, recent[-1][:w - 10], theme.DIM, theme.BG)
        if len(recent) == 2:
            buf.put_text(2, 28, recent[-2][:w - 4], theme.DIM, theme.BG)

    def _render_settlement(self, buf: FrameBuffer, w: int, h: int) -> None:
        ps, _ = self.player.score()
        as_, _ = self.ai.score()
        title = {"win": "胜利！", "lose": "失败", "draw": "平局"}.get(self.result or "", "结束")
        color = {"win": theme.GOLD, "lose": theme.WARN, "draw": theme.DIM}.get(self.result or "", theme.FG)
        ai_sleeve = ", ".join(str(c) for c in self.ai.sleeve) if self.ai.sleeve else "空"
        lines = [
            f"你的点数: {ps}",
            f"AI 的点数: {as_}",
            "",
            f"AI 袖子揭晓: {ai_sleeve}",
        ]
        box_h = len(lines) + 5
        box_w = max(max(text_width(l) for l in lines), text_width(title), 18) + 8
        bx = (w - box_w) // 2
        by = (h - box_h) // 2
        buf.fill_rect(bx - 1, by - 1, box_w + 2, box_h + 2, " ", theme.FG, theme.OVERLAY_BG)
        draw_box(buf, bx, by, box_w, box_h, title=title, fg=theme.OVERLAY_BORDER, bg=theme.OVERLAY_BG)
        buf.put_text(bx + 2, by + 2, f"结果: {title}", color, theme.OVERLAY_BG)
        for i, line in enumerate(lines):
            buf.put_text(bx + 2, by + 3 + i, line, theme.FG, theme.OVERLAY_BG)
        put_centered(buf, by + box_h - 1, "按任意键返回主菜单", theme.DIM, theme.OVERLAY_BG)

    @staticmethod
    def _hline(buf: FrameBuffer, x0: int, y: int, x1: int) -> None:
        for cx in range(x0, x1):
            buf.set_char(cx, y, "─", theme.BORDER, theme.BG)

    def get_hints(self) -> list[str]:
        if self.phase == "settled":
            return ["任意键 返回主菜单"]
        if self.phase == "ai_turn":
            return ["Esc 放弃对局"]
        if self.phase == "holding":
            return ["↑↓ 选择", "回车/1 打出", "2 藏入袖子", "Esc 放弃对局"]
        if self.phase == "sleeve_select":
            return ["↑↓ 选袖子牌", "回车 打出", "Esc 返回菜单"]
        return ["↑↓ 选择", "回车 确认", "1-3 快捷", "Esc 放弃对局"]
