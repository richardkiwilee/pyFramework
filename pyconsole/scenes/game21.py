"""21 点人机对战场景。

规则（grilling 确认）：
- 一副 52 张牌（无大小王），双方轮流操作。
- 每位玩家面前**固定 5 个卡槽**。打出一张牌时必须**手动选择打到哪个卡槽**：
  - 选中的卡槽是空的 → 牌放上、本动作完成。
  - 选中的卡槽已被占用 → 放置失败，停留在卡槽选择界面继续重选。
- 抽牌回合约束：**一旦本回合选择了抽牌，必须打出一张牌到桌上才算回合结束**。
  - 即可连续"抽牌→藏牌→抽牌→…"，但只要抽过牌，就不能再用 pass / 从袖子打出
    来结束本回合；唯一结束方式是打出一张牌到桌面的空卡槽。
  - 没抽过牌的回合：可 pass 停牌，或"从袖子打出"（直接进入卡槽选择）。
- 袖子最多 2 张；**袖子已满再藏时，不再自动弃牌，改为手动选择丢弃哪一张**（藏入新牌前
  先丢弃选中的旧牌）。若 5 槽已满则无处可放，须 pass。
- 爆牌（>21）上桌即判、当场结算。A=1/11 取最优，JQK=10。
- 结算：一方爆→对方胜；双爆比小；双方停→比点数（高胜、等平）。
- 随机先后手；AI 启发式概率决策；AI 动作用 tick 钩子 + 时间队列做延迟动画。

阶段（phase）：
  menu          玩家回合主菜单（抽牌 / 从袖子打出 / pass）
  holding       刚抽到一张牌，待决定打出或藏入袖子
  discard       藏入已满袖子时，选一张丢弃（再藏入新牌）
  sleeve_select 从袖子里选一张打出
  slot_select   选目标卡槽放牌（左右切换，回车确认）
  ai_turn       AI 行动中（忽略玩家输入，Esc 可放弃对局返回）
  settled       已结算，任意键返回主菜单

按住 Tab：显示当前完整牌堆（含桌面/袖子/手牌的归属），并在 overlay 左上角
绘制抽牌堆顶牌的隐写卡背（信息藏在统一纹理里，正面看似普通背面）。
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any, Callable

from ..core import actions
from ..core.scene import Scene, SceneResult, POP, NONE
from ..game.cards import Card, hand_score, new_deck, rank_label, suit_color, shuffle
from ..game.card_back import draw_card_back_buf
from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.widgets import draw_box, fill_rect, put_centered
from ..io.width import text_width

MAX_SLOTS = 5        # 每位玩家面前固定 5 个卡槽
MAX_SLEEVE = 2       # 袖子最多 2 张
AI_STEP_DELAY = 0.7  # AI 每个可见动作的间隔（秒）
CARD_W = 6           # ASCII 牌宽（含边框）
CARD_H = 4           # ASCII 牌高
CARD_GAP = 1         # 牌间距
TOKEN_W = 5          # 袖子牌 token 宽度

# Tab 牌堆总览：隐写卡背尺寸（与 stealth_marked_card_back 默认一致）
BACK_W = 19
BACK_H = 11
# 牌堆总览中每张牌的网格宽度（含 1 格间距）
GRID_CELL = 4


@dataclass
class Side:
    """一方（玩家或 AI）。桌面是固定 5 卡槽（None=空），袖子最多 2 张。"""
    slots: list[Card | None] = field(default_factory=lambda: [None] * MAX_SLOTS)
    sleeve: list[Card] = field(default_factory=list)
    passed: bool = False
    busted: bool = False

    @property
    def table(self) -> list[Card]:
        """桌面上的牌（只读视图，按卡槽顺序）。保留兼容旧代码 / 点数计算。"""
        return [c for c in self.slots if c is not None]

    def first_free_slot(self) -> int | None:
        for i, c in enumerate(self.slots):
            if c is None:
                return i
        return None

    def score(self) -> tuple[int, bool]:
        return hand_score(self.table)


class Game21Scene(Scene):
    allow_status_overlay = True  # 按住 Tab 显示完整牌堆 + 抽牌堆顶隐写卡背

    def __init__(self, rng: random.Random | None = None) -> None:
        super().__init__()
        self._rng = rng if rng is not None else random.Random()
        self.deck: list[Card] = []
        self.player = Side()
        self.ai = Side()
        self.turn: str = "player"            # "player" | "ai"
        self.phase: str = "menu"
        self.held_card: Card | None = None   # 待放置的牌（打出上桌用）
        self._slot_focus: int = 0            # slot_select 阶段焦点卡槽
        # 放牌来源：抽牌后藏失败转打出？此处记录 slot_select 是在放哪张牌
        self._placing_source: str = "held"   # "held"(刚抽/持有) | "sleeve"(从袖子打出)
        self._sleeve_play_idx: int = 0       # 若 source=sleeve，要打出的袖子牌索引
        self.menu_focus: int = 0
        self.sleeve_focus: int = 0
        self._holding_focus: int = 0         # holding 阶段两选项焦点（0=打出,1=藏入袖子）
        self.discard_focus: int = 0          # discard 阶段焦点（袖子内）
        self._drawn_this_turn: bool = False  # 本回合是否已抽牌（决定能否 pass / 出袖子）
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

    def _can_pass(self) -> bool:
        """抽过牌的回合不能 pass（必须打出一张牌才算回合结束）。"""
        return not self._drawn_this_turn

    def _can_play_sleeve(self) -> bool:
        """抽过牌的回合不能从袖子打出（必须把刚抽/持有的牌打到桌面）。"""
        return not self._drawn_this_turn

    # ---- 输入分发 ----
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if self.phase == "settled":
            return POP()
        # 子选择阶段的 Esc：返回玩家菜单（不放弃对局）
        if self.phase in ("sleeve_select", "slot_select", "discard") and a == actions.BACK:
            if self.phase == "slot_select" and self._placing_source == "held":
                # 抽牌持有态进入卡槽选择，Esc 退回 holding 二选一
                self.phase = "holding"
                return NONE()
            if self.phase == "discard":
                # 藏牌已满：Esc 取消藏牌，退回 holding
                self.phase = "holding"
                return NONE()
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
        if self.phase == "discard":
            return self._handle_discard(event)
        if self.phase == "sleeve_select":
            return self._handle_sleeve_select(event)
        if self.phase == "slot_select":
            return self._handle_slot_select(event)
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
            self._drawn_this_turn = True
            self.log.append(f"你抽到 {self.held_card}。")
            self.phase = "holding"
            self._holding_focus = 0
            return NONE()
        if choice == "从袖子打出":
            if not self._can_play_sleeve():
                self.log.append("本回合已抽牌，必须打出一张牌到桌面。")
                return NONE()
            if len(self.player.sleeve) > 1:
                self.phase = "sleeve_select"
                self.sleeve_focus = 0
            else:
                # 只有一张袖子牌：直接进入卡槽选择放牌
                self._begin_place(source="sleeve", sleeve_idx=0)
            return NONE()
        if choice == "Pass 停牌":
            if not self._can_pass():
                self.log.append("本回合已抽牌，必须打出一张牌到桌面。")
                return NONE()
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
        if choice == 0:
            # 打出上桌：进入卡槽选择
            self._begin_place(source="held")
        else:
            # 藏入袖子：满了则先丢弃
            if len(self.player.sleeve) >= MAX_SLEEVE:
                self.phase = "discard"
                self.discard_focus = 0
                self.log.append("袖子已满，选择一张丢弃以藏入新牌。")
            else:
                self._stash_to_sleeve(self.player, self.held_card, "player")
                self.held_card = None
                # 藏牌不结束回合（本回合仍须打出一张牌）：回菜单继续抽/打
                self.phase = "menu"
                self.menu_focus = 0
        return NONE()

    def _handle_discard(self, event) -> SceneResult:
        """袖子已满藏牌时：选一张丢弃，再藏入新牌。"""
        a = event.action
        n = len(self.player.sleeve)
        if a == actions.LEFT:
            self.discard_focus = (self.discard_focus - 1) % n
            return NONE()
        if a == actions.RIGHT:
            self.discard_focus = (self.discard_focus + 1) % n
            return NONE()
        if a in (actions.UP, actions.DOWN):
            self.discard_focus = (self.discard_focus + 1) % n
            return NONE()
        if a == actions.CONFIRM:
            assert self.held_card is not None
            dropped = self.player.sleeve.pop(self.discard_focus)
            self.log.append(f"你丢弃了袖子里的 {dropped}。")
            self._stash_to_sleeve(self.player, self.held_card, "player")
            self.held_card = None
            self.phase = "menu"
            self.menu_focus = 0
            return NONE()
        if a == actions.CHAR and event.char.isdigit():
            idx = int(event.char) - 1
            if 0 <= idx < n:
                self.discard_focus = idx
        return NONE()

    def _handle_sleeve_select(self, event) -> SceneResult:
        a = event.action
        n = len(self.player.sleeve)
        if a == actions.LEFT:
            self.sleeve_focus = (self.sleeve_focus - 1) % n
            return NONE()
        if a == actions.RIGHT:
            self.sleeve_focus = (self.sleeve_focus + 1) % n
            return NONE()
        if a in (actions.UP, actions.DOWN):
            self.sleeve_focus = (self.sleeve_focus + 1) % n
            return NONE()
        if a == actions.CONFIRM:
            idx = self.sleeve_focus
            self._begin_place(source="sleeve", sleeve_idx=idx)
            return NONE()
        return NONE()

    def _begin_place(self, source: str, sleeve_idx: int = 0) -> None:
        """进入卡槽选择：source='held'(刚抽/持有) 或 'sleeve'(从袖子打出)。"""
        self._placing_source = source
        self._sleeve_play_idx = sleeve_idx
        # 焦点默认落在第一个空槽（若无空槽则停在 0，放置会失败提示）
        free = self.player.first_free_slot()
        self._slot_focus = free if free is not None else 0
        self.phase = "slot_select"

    def _handle_slot_select(self, event) -> SceneResult:
        a = event.action
        if a == actions.LEFT:
            self._slot_focus = (self._slot_focus - 1) % MAX_SLOTS
            return NONE()
        if a == actions.RIGHT:
            self._slot_focus = (self._slot_focus + 1) % MAX_SLOTS
            return NONE()
        if a in (actions.UP, actions.DOWN):
            self._slot_focus = (self._slot_focus + 1) % MAX_SLOTS
            return NONE()
        if a == actions.CONFIRM:
            return self._try_place(self._slot_focus)
        if a == actions.CHAR and event.char.isdigit():
            idx = int(event.char) - 1
            if 0 <= idx < MAX_SLOTS:
                self._slot_focus = idx
                return self._try_place(idx)
        return NONE()

    def _current_placing_card(self) -> Card | None:
        if self._placing_source == "held":
            return self.held_card
        if 0 <= self._sleeve_play_idx < len(self.player.sleeve):
            return self.player.sleeve[self._sleeve_play_idx]
        return None

    def _try_place(self, slot: int) -> SceneResult:
        """尝试把牌放到指定卡槽；占用则失败、停留重选。"""
        card = self._current_placing_card()
        if card is None:
            self.phase = "menu"
            return NONE()
        if self.player.slots[slot] is not None:
            # 放置失败：占用，继续重选
            self.log.append(f"卡槽 {slot + 1} 已被占用，放置失败，请重选。")
            return NONE()
        # 真正放牌
        if self._placing_source == "held":
            self.held_card = None
        else:
            self.player.sleeve.pop(self._sleeve_play_idx)
        self._place_to_slot(self.player, slot, card, "player")
        # 打出一张牌 → 本回合结束（满足"抽牌必须打出"约束）
        self._after_play("player")
        return NONE()

    # ---- 出牌/藏牌核心 ----
    def _place_to_slot(self, side: Side, slot: int, card: Card, owner: str) -> None:
        side.slots[slot] = card
        who = "你" if owner == "player" else "AI"
        self.log.append(f"{who}把 {card} 放到卡槽 {slot + 1}。")
        score, busted = side.score()
        if busted:
            side.busted = True
            self.log.append(f"{who}爆牌！")
        elif side.first_free_slot() is None:
            side.passed = True
            self.log.append(f"{who}5 个卡槽已满，自动停牌。")

    def _stash_to_sleeve(self, side: Side, card: Card, owner: str) -> None:
        who = "你" if owner == "player" else "AI"
        side.sleeve.append(card)
        self.log.append(f"{who}把 {card} 藏入袖子。")

    def _after_play(self, owner: str) -> None:
        """打出一张牌后检查结算或切换回合。"""
        self._drawn_this_turn = False  # 回合结束，重置抽牌标志
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
            self._begin_player_turn()

    def _begin_player_turn(self) -> None:
        self.phase = "menu"
        self.menu_focus = 0
        self._drawn_this_turn = False
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
        """AI 启发式决策：pass / 抽牌 / 出袖子。

        新规则下 AI 遵循玩家同样的约束：抽牌后必须打出一张牌。AI 状态机为：
        pass → 结束；抽牌 → resolve；从袖子打出（仅当本回合未抽牌）→ resolve。
        本回合已抽牌时，不能 pass / 不能出袖子，唯一出路是继续抽（抽到不爆的牌即打出）。
        终局保护：桌满无处放 → 强制 pass。
        """
        if self.phase != "ai_turn":
            return
        if self.ai.passed or self.ai.busted:
            self._ai_end_turn()
            return
        score, _ = self.ai.score()
        ps, _ = self.player.score()
        # 桌面已满无处放牌 → 必须 pass
        if self.ai.first_free_slot() is None:
            self.ai.passed = True
            self.log.append("AI 桌面已满，选择停牌。")
            self._ai_end_turn()
            return
        # 本回合已抽牌：必须打出一张牌，不能 pass / 不能出袖子 → 继续抽
        if self._drawn_this_turn:
            self._ai_draw()
            return
        # 点数足够高 → 大概率停牌
        if score >= 17 and self._rng.random() < 0.85:
            self.ai.passed = True
            self.log.append("AI 选择停牌。")
            self._ai_end_turn()
            return
        if score <= 11:
            self._ai_draw()
            return
        must = self.player.passed and ps > score  # 玩家已停且点数更高，AI 被迫追
        if must or self._rng.random() < 0.6:
            self._ai_draw()
            return
        # 偶尔从袖子出牌（若有、打出不爆）
        if self.ai.sleeve and self._rng.random() < 0.3:
            for i, c in enumerate(self.ai.sleeve):
                _, b2 = hand_score(self.ai.table + [c])
                if not b2:
                    self._ai_play_from_sleeve(i)
                    return
        self.ai.passed = True
        self.log.append("AI 选择停牌。")
        self._ai_end_turn()

    def _ai_draw(self) -> None:
        card = self._draw_from_deck()
        self.held_card = card
        self._drawn_this_turn = True
        self.log.append("AI 抽了一张牌。")
        self.schedule(AI_STEP_DELAY, self._ai_resolve_held)

    def _ai_resolve_held(self) -> None:
        if self.held_card is None:
            self._ai_end_turn()
            return
        card = self.held_card
        self.held_card = None
        _, busted = hand_score(self.ai.table + [card])
        if not busted:
            # 多数直接打出；小概率藏（袖子有空位且未满）
            if len(self.ai.sleeve) < MAX_SLEEVE and self._rng.random() < 0.15:
                self._stash_to_sleeve(self.ai, card, "ai")
                # 藏牌不结束回合：AI 仍须打出一张牌（_drawn_this_turn 仍 True → 继续抽）
                self.schedule(AI_STEP_DELAY, self._ai_act)
                return
            # 打到第一个空槽
            self._ai_place_held(card)
        else:
            # 会爆：优先藏入袖子（有空位），否则被迫丢弃一张再藏（与玩家手动选择对等：
            # AI 弃掉袖子里最小点数的牌）。藏入后仍须打出一张牌（继续抽）。
            if len(self.ai.sleeve) < MAX_SLEEVE:
                self._stash_to_sleeve(self.ai, card, "ai")
                self.schedule(AI_STEP_DELAY, self._ai_act)
            else:
                drop_idx = min(range(len(self.ai.sleeve)),
                               key=lambda i: _card_value(self.ai.sleeve[i]))
                dropped = self.ai.sleeve.pop(drop_idx)
                self.log.append(f"AI 丢弃了袖子里的 {dropped}。")
                self._stash_to_sleeve(self.ai, card, "ai")
                self.schedule(AI_STEP_DELAY, self._ai_act)

    def _ai_place_held(self, card: Card) -> None:
        """AI 把持有的牌放到第一个空槽（AI 不手动选槽，自动挑空位）。"""
        slot = self.ai.first_free_slot()
        if slot is None:
            # 无处可放：强制 pass
            self.ai.passed = True
            self.log.append("AI 桌面已满，选择停牌。")
            self._ai_end_turn()
            return
        self._place_to_slot(self.ai, slot, card, "ai")
        self._after_play("ai")

    def _ai_play_from_sleeve(self, idx: int) -> None:
        if idx < 0 or idx >= len(self.ai.sleeve):
            self._ai_end_turn()
            return
        slot = self.ai.first_free_slot()
        if slot is None:
            self.ai.passed = True
            self.log.append("AI 桌面已满，选择停牌。")
            self._ai_end_turn()
            return
        card = self.ai.sleeve.pop(idx)
        self._place_to_slot(self.ai, slot, card, "ai")
        self._after_play("ai")

    def _ai_end_turn(self) -> None:
        self._drawn_this_turn = False
        self.end_turn("ai")

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
        self._render_slots(buf, 2, self.ai, owner="ai")
        buf.put_text(2, 6, "AI 袖子:", theme.DIM, theme.BG)
        self._render_sleeve_tokens(buf, 11, 6, self.ai.sleeve, face_up=False)

        self._hline(buf, 1, 7, w - 1)

        # ---- 状态 / 握牌区 ----
        put_centered(buf, 8, self._status_text(), w, self._status_color(), theme.BG)
        if self.phase == "holding" and self.held_card is not None:
            x = (w - CARD_W) // 2
            self._draw_card(buf, x, 9, self.held_card, face_up=True, hl=True)
        elif self.phase in ("slot_select", "discard", "sleeve_select") and self._current_placing_card() is not None:
            # 选卡槽 / 选丢弃 / 选袖子牌时，也显示当前持有的牌
            x = (w - CARD_W) // 2
            self._draw_card(buf, x, 9, self._current_placing_card(), face_up=True, hl=True)

        self._hline(buf, 1, 13, w - 1)

        # ---- 玩家区 ----
        self._render_slots(buf, 14, self.player, owner="player")
        buf.put_text(2, 18, "你的袖子:", theme.DIM, theme.BG)
        self._render_sleeve_tokens(buf, 12, 18, self.player.sleeve, face_up=True,
                                   selectable=(self.phase == "sleeve_select" or self.phase == "discard"))
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
        if self.phase == "slot_select":
            card = self._current_placing_card()
            return f"选择卡槽放置 {card}（←→ 切换 · 回车确认）"
        if self.phase == "discard":
            return f"袖子已满，选一张丢弃以藏入 {self.held_card}"
        if self.phase == "sleeve_select":
            return "选择袖子里的牌打出"
        if self.player.passed:
            return "你已停牌，等待 AI…"
        if self._drawn_this_turn:
            return "你已抽牌，必须打出一张牌到桌面"
        return "你的回合"

    def _status_color(self) -> int:
        if self.phase == "settled":
            return {"win": theme.GOLD, "lose": theme.WARN, "draw": theme.DIM}.get(self.result or "", theme.FG)
        if self.phase == "ai_turn":
            return theme.ACCENT2
        if self.phase in ("holding", "slot_select", "discard", "sleeve_select"):
            return theme.ACCENT
        return theme.HEADING

    def _render_slots(self, buf: FrameBuffer, y: int, side: Side, owner: str) -> None:
        """绘制固定 5 个卡槽。玩家在 slot_select 时高亮焦点（空槽金色 / 占用红色）。"""
        w = buf.w
        total = MAX_SLOTS * CARD_W + max(0, MAX_SLOTS - 1) * CARD_GAP
        x0 = max(2, (w - total) // 2)
        slot_select = (self.phase == "slot_select" and owner == "player")
        for i in range(MAX_SLOTS):
            x = x0 + i * (CARD_W + CARD_GAP)
            card = side.slots[i]
            focused = slot_select and i == self._slot_focus
            if card is not None:
                # 占用槽：焦点时红色边框警示（放置会失败），否则正常画牌
                self._draw_card(buf, x, y, card, face_up=True, hl=False,
                                slot_hl=focused, slot_free=False)
            else:
                # 空槽：画空卡槽框；焦点时金色高亮（可放置）
                self._draw_empty_slot(buf, x, y, focused=focused)
            # 卡槽编号（小标）
            buf.put_text(x + 1, y + CARD_H, f"[{i + 1}]", theme.DIM, theme.BG)

    def _draw_empty_slot(self, buf: FrameBuffer, x: int, y: int, focused: bool = False) -> None:
        """画一个空卡槽（虚线框）。focused 时金色高亮。"""
        border = theme.GOLD if focused else theme.BORDER
        bg = theme.SELECTED_BG if focused else theme.BG
        x2 = x + CARD_W - 1
        y2 = y + CARD_H - 1
        buf.set_char(x, y, "┌", border, bg)
        buf.set_char(x2, y, "┐", border, bg)
        buf.set_char(x, y2, "└", border, bg)
        buf.set_char(x2, y2, "┘", border, bg)
        for cx in range(x + 1, x2):
            buf.set_char(cx, y, "┄", border, bg)
            buf.set_char(cx, y2, "┄", border, bg)
        for ry in range(y + 1, y2):
            buf.set_char(x, ry, "┆", border, bg)
            buf.set_char(x2, ry, "┆", border, bg)
        if focused:
            buf.put_text(x + 1, y + 1, " 空槽 ", theme.GOLD, bg)
            buf.set_char(x + (CARD_W // 2), y + 2, "▼", theme.GOLD, bg)

    def _render_sleeve_tokens(self, buf: FrameBuffer, x: int, y: int, sleeve: list[Card],
                              face_up: bool, selectable: bool = False) -> None:
        if not sleeve:
            buf.put_text(x, y, "(空)", theme.DIM, theme.BG)
            return
        cx = x
        for i, c in enumerate(sleeve):
            hl = selectable and (
                (self.phase == "sleeve_select" and i == self.sleeve_focus) or
                (self.phase == "discard" and i == self.discard_focus)
            )
            bg = theme.SELECTED_BG if hl else theme.BG
            border = theme.WARN if (hl and self.phase == "discard") else (theme.ACCENT if hl else theme.DIM)
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
                   face_up: bool = True, hl: bool = False,
                   slot_hl: bool = False, slot_free: bool = True) -> None:
        """画一张 4 行 ASCII 牌。slot_hl=True 时按卡槽状态着色边框（占用红/空槽金）。"""
        fg = suit_color(card.suit)
        if slot_hl:
            bg = theme.SELECTED_BG
            border = theme.GOLD if slot_free else theme.WARN
        elif hl:
            bg = theme.SELECTED_BG
            border = theme.ACCENT
        else:
            bg = theme.BG
            border = theme.BORDER
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
            if self._drawn_this_turn:
                buf.put_text(10, y0, "（本回合已抽牌，须打出一张牌才能结束）",
                             theme.WARN, theme.BG)
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
            opts = ["1. 打出上桌（选卡槽）", "2. 藏入袖子"]
            if len(self.player.sleeve) >= MAX_SLEEVE:
                opts[1] += "（袖子已满，将选一张丢弃）"
            for i, label in enumerate(opts):
                ry = y0 + 1 + i
                marker = "▶" if i == self._holding_focus else " "
                if i == self._holding_focus:
                    buf.fill_rect(2, ry, w - 4, 1, " ", theme.SELECTED_FG, theme.SELECTED_BG)
                    buf.put_text(2, ry, f"{marker} {label}", theme.SELECTED_FG, theme.SELECTED_BG)
                else:
                    buf.put_text(2, ry, f"{marker} {label}", theme.FG, theme.BG)
        elif self.phase == "slot_select":
            buf.put_text(2, y0, "选择卡槽放牌:", theme.ACCENT, theme.BG)
            buf.put_text(2, y0 + 1, "←→ 切换卡槽 · 回车 放置 · 数字 1-5 直选 · Esc 返回",
                         theme.DIM, theme.BG)
            buf.put_text(2, y0 + 2, "（金色=空槽可放 · 红色=已占用，放置会失败）",
                         theme.DIM, theme.BG)
        elif self.phase == "discard":
            buf.put_text(2, y0, "袖子已满：选一张丢弃以藏入新牌", theme.WARN, theme.BG)
            buf.put_text(2, y0 + 1, "←→ 切换 · 回车 丢弃 · Esc 取消藏牌", theme.DIM, theme.BG)
        elif self.phase == "sleeve_select":
            buf.put_text(2, y0, "选择袖子里的牌打出:", theme.ACCENT, theme.BG)
            buf.put_text(2, y0 + 1, "←→ 切换 · 回车 选择 · Esc 返回菜单", theme.DIM, theme.BG)
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
            return ["Esc 放弃对局", "Tab 牌堆"]
        if self.phase == "holding":
            return ["↑↓ 选择", "回车/1 打出", "2 藏入袖子", "Tab 牌堆", "Esc 放弃对局"]
        if self.phase == "slot_select":
            return ["←→ 切换卡槽", "回车 放置", "1-5 直选", "Tab 牌堆", "Esc 返回"]
        if self.phase == "discard":
            return ["←→ 选丢弃", "回车 丢弃", "Tab 牌堆", "Esc 取消"]
        if self.phase == "sleeve_select":
            return ["←→ 选袖子牌", "回车 选择", "Tab 牌堆", "Esc 返回菜单"]
        return ["↑↓ 选择", "回车 确认", "1-3 快捷", "Tab 牌堆", "Esc 放弃对局"]

    # ==================== Tab 牌堆总览 ====================
    def _full_deck(self) -> list[Card]:
        """本局完整牌堆（原始 52 张顺序，无大小王）。"""
        return new_deck()

    def _card_location(self, card: Card) -> str:
        """牌当前所在位置：'抽牌堆' / '你-桌面' / '你-袖子' / 'AI-桌面' / 'AI-袖子' / '已出'。

        '已出' 表示该牌已不在场上任何可见位置（理论上 21 点不弃牌，留作兜底）。
        """
        if card in self.player.table:
            return "你-桌面"
        if card in self.player.sleeve:
            return "你-袖子"
        if card in self.ai.table:
            return "AI-桌面"
        if card in self.ai.sleeve:
            return "AI-袖子"
        if card in self.deck:
            return "抽牌堆"
        return "已出"

    def _card_loc_color(self, loc: str) -> int:
        return {
            "抽牌堆": theme.DIM,
            "你-桌面": theme.HEADING,
            "你-袖子": theme.ACCENT,
            "AI-桌面": theme.ACCENT2,
            "AI-袖子": theme.ACCENT2,
            "已出": theme.DIM,
        }.get(loc, theme.DIM)

    def render_overlay(self, buf: FrameBuffer, w: int, h: int) -> bool:
        """按住 Tab：完整牌堆网格 + 左上角抽牌堆顶牌的隐写卡背。"""
        # 面板：顶部留 BACK_H+3 给左上角卡背 + 右侧说明；下方 13 行牌堆网格
        grid_rows = 4
        grid_top_pad = 2
        pw = w - 4
        ph = BACK_H + 3 + grid_top_pad + grid_rows + 2
        px = (w - pw) // 2
        py = max(1, (h - ph) // 2)

        fill_rect(buf, px - 1, py - 1, pw + 2, ph + 2, " ", theme.FG, theme.OVERLAY_BG)
        draw_box(buf, px, py, pw, ph, title="牌堆总览 (按住 Tab)",
                 fg=theme.OVERLAY_BORDER, bg=theme.OVERLAY_BG)

        # ---- 左上角：抽牌堆顶牌的隐写卡背 ----
        back_x = px + 2
        back_y = py + 2
        if self.deck:
            top_card = self.deck[-1]
            draw_card_back_buf(buf, back_x, back_y, top_card,
                               width=BACK_W, height=BACK_H,
                               border_fg=theme.OVERLAY_BORDER, tex_fg=theme.DIM,
                               bg=theme.OVERLAY_BG)
            cap = "抽牌堆顶（隐写）"
        else:
            buf.put_text(back_x, back_y, "(牌堆已空)", theme.DIM, theme.OVERLAY_BG)
            cap = "抽牌堆顶"
        buf.put_text(back_x, back_y + BACK_H + 1, cap, theme.DIM, theme.OVERLAY_BG)
        buf.put_text(back_x, back_y + BACK_H + 2, f"牌堆剩余 {len(self.deck)} 张",
                     theme.DIM, theme.OVERLAY_BG)

        # ---- 右上角：说明 ----
        info_x = back_x + BACK_W + 3
        info_lines = [
            ("花色编码", theme.HEADING),
            ("┆ 在左上/右上/左下/右下", theme.DIM),
            ("  → ♠ ♥ ♣ ♦", theme.DIM),
            ("", theme.DIM),
            ("点数编码", theme.HEADING),
            ("顶边 ┈ 的槽位 = 点数", theme.DIM),
            ("  (A 2..10 J Q K)", theme.DIM),
            ("", theme.DIM),
            ("图例", theme.HEADING),
            ("抽牌堆", self._card_loc_color("抽牌堆")),
            ("你-桌面", self._card_loc_color("你-桌面")),
            ("你-袖子", self._card_loc_color("你-袖子")),
            ("AI-桌面", self._card_loc_color("AI-桌面")),
            ("AI-袖子", self._card_loc_color("AI-袖子")),
        ]
        for i, (text, color) in enumerate(info_lines):
            if text:
                buf.put_text(info_x, back_y + i, text, color, theme.OVERLAY_BG)

        # ---- 下方：完整牌堆网格（按花色×点数） ----
        grid_y = py + BACK_H + 3 + grid_top_pad
        buf.put_text(px + 2, grid_y - 1, "完整牌堆（4 花色 × 13 点数）",
                     theme.HEADING, theme.OVERLAY_BG)

        suits_order = ("♠", "♥", "♣", "♦")
        # 每列宽 4：可容纳 "10♠"(3) + 1 间距，普通牌 "7♠"(2) + 2 间距
        col_w = 4
        for col, r in enumerate(range(1, 14)):
            cx = px + 3 + col * col_w
            buf.put_text(cx, grid_y, rank_label(r), theme.DIM, theme.OVERLAY_BG)

        for row, suit in enumerate(suits_order):
            gy = grid_y + 1 + row
            buf.put_text(px + 2, gy, suit, theme.FG, theme.OVERLAY_BG)
            buf.set_char(px + 3, gy, ":", theme.DIM, theme.OVERLAY_BG)
            for col, r in enumerate(range(1, 14)):
                card = Card(r, suit)
                loc = self._card_location(card)
                color = self._card_loc_color(loc)
                cx = px + 3 + col * col_w
                label = rank_label(r) + suit  # 如 "10♠"
                buf.put_text(cx, gy, label, color, theme.OVERLAY_BG)

        # 底部提示
        put_centered(buf, py + ph - 1, "松开 Tab 关闭", theme.DIM, theme.OVERLAY_BG)
        return True


# ---- 模块级辅助 ----
def _card_value(card: Card) -> int:
    """AI 弃牌策略用：牌的"数值"（A=1, JQK=10，便于挑最小弃）。"""
    if card.rank == 1:
        return 1
    if card.rank >= 11:
        return 10
    return card.rank
