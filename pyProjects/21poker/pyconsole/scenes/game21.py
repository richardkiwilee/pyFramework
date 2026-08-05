"""21 点人机对战场景（阶段 7：经济 + 多轮 + 套牌/卡牌效果 + 卡槽栈 + 软 pass）。

规则要点（详见 DESIGN.md §14/§15/§16/§17）：
- 共享牌组：开局从全部套牌抽 = 玩家数 的若干套合并洗牌；所有玩家共用。
- 每位玩家面前固定 5 个卡槽（升级为栈模型，见 effects.slot_can_place）。
- 多轮经济：每轮起手收底注 = 轮数×2（不足全交）；金币进公共池；轮末按 21 决胜链分池。
- 软上限 20：轮末结算后丢弃超额金币；轮内可超。
- 游戏结束条件 = 任一玩家金币归 0（仅轮末第 6 步检查）；终局最多金币者胜。
- 软 pass：pass 后冻结，若他人效果在回合外改变了我的总点数 → 自动取消 pass；全员 pass 才结算。
- 爆牌不立即结算（可抽负点数牌自救）；放牌时序见 §16.4（付费→卡槽效果→打出效果→点数→激活询问→结束turn）。
- 洗牌规则：抽牌堆空 → 弃牌堆洗为新抽牌堆（袖子不洗、不进弃牌堆）。

阶段（phase）：
  menu          玩家回合主菜单（抽牌 / 从袖子打出 / Pass）
  holding       刚抽到一张牌，待决定打出或藏入袖子
  discard       藏入已满袖子时，选一张丢弃（再藏入新牌）
  sleeve_select 从袖子里选一张打出
  slot_select   选目标卡槽放牌（左右切换，回车确认）
  activate_prompt 放牌后问是否激活 on_activate（强制牌跳过）
  ai_turn       AI 行动中（忽略玩家输入，Esc 可放弃对局返回）
  round_settled 轮结算面板，任意键继续
  game_over     游戏结束面板，任意键返回主菜单

按住 Tab：显示当前完整牌组构成 + 左上角抽牌堆顶牌的隐写卡背。
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any, Callable

from ..core import actions
from ..core.scene import Scene, SceneResult, POP, NONE
from ..game.cards import (
    Card, hand_score, rank_label, suit_color, shuffle,
)
from ..game.card_back import draw_card_back_buf
from ..game.effects import (
    Effect, SlotEffect, EXPLOIT, BROKEN, SHELL,
    register, run_effect,
    is_forced_activate, is_shell_card, slot_can_place, slot_is_open, slot_is_occupied,
)
from ..game.deck_defs import DECK_DEF
from ..io.buffer import FrameBuffer
from ..io import theme
from ..io.widgets import draw_box, fill_rect, put_centered
from ..io.width import text_width

MAX_SLOTS = 5        # 每位玩家面前固定 5 个卡槽
MAX_SLEEVE = 2       # 袖子最多 2 张
AI_STEP_DELAY = 0.7  # AI 每个可见动作的间隔（秒）
CARD_W = 8           # ASCII 牌宽（含边框）——加宽以容纳多值标签 "1|11"
CARD_H = 4           # ASCII 牌高
CARD_GAP = 1         # 牌间距
TOKEN_W = 5          # 袖子牌 token 宽度
START_GOLD = 20      # 初始金币（软上限）
GOLD_CAP = 20        # 轮末丢弃超额到此值
HIDE_COST = 2        # 藏牌费用

# Tab 牌堆总览：隐写卡背尺寸（与 stealth_marked_card_back 默认一致）
BACK_W = 19
BACK_H = 11


# =====================================================================
# 状态结构
# =====================================================================
@dataclass
class Slot:
    """卡槽（栈模型）：cards 有序栈（末尾=栈顶）+ 可选卡槽效果。"""
    cards: list[Card] = field(default_factory=list)
    slot_effect: SlotEffect | None = None

    @property
    def top(self) -> Card | None:
        return self.cards[-1] if self.cards else None


@dataclass
class Side:
    """一方（玩家或 AI）。

    - slots：5 个卡槽（栈）；table 视图派生为扁平所有牌（点数计算/决胜用）。
    - sleeve：≤2，跨轮保留。
    - gold：金币（软上限 20）。
    - passed / pass_score：软 pass 冻结态与记录的总点数。
    """
    slots: list[Slot] = field(default_factory=lambda: [Slot() for _ in range(MAX_SLOTS)])
    sleeve: list[Card] = field(default_factory=list)
    gold: int = START_GOLD
    passed: bool = False
    pass_score: int | None = None

    @property
    def table(self) -> list[Card]:
        """桌面所有牌（所有卡槽所有牌的扁平视图）。"""
        return [c for s in self.slots for c in s.cards]

    def score(self) -> tuple[int, bool]:
        return hand_score(self.table)

    def first_playable_slot(self) -> int | None:
        """第一个可放牌的卡槽（取代旧 first_free_slot）。

        可放判定 = slot_is_open：空槽 / 空壳效果槽 / 栈顶空壳牌。
        """
        for i, s in enumerate(self.slots):
            if slot_is_open(s):
                return i
        return None

    def is_table_full(self) -> bool:
        """5 个卡槽是否全部被占据（栈顶非空壳牌 → 无处可放须 pass）。"""
        return all(slot_is_occupied(s) for s in self.slots)


class Game21Scene(Scene):
    allow_status_overlay = True  # 按住 Tab 显示牌组构成 + 抽牌堆顶隐写卡背

    def __init__(self, rng: random.Random | None = None) -> None:
        super().__init__()
        self._rng = rng if rng is not None else random.Random()
        # 注册本场景依赖的执行器（幂等：register 直接覆盖）
        _register_known_effects()
        self.players: list[Side] = [Side(), Side()]   # [human, ai]
        self.pool: int = 0
        self.round_num: int = 0
        self.current: int = 0                          # 当前行动玩家索引
        self.deck: list[Card] = []
        self.discard: list[Card] = []
        self.phase: str = "menu"
        self.held_card: Card | None = None             # 待放置的牌（打出上桌用）
        self._slot_focus: int = 0                       # slot_select 阶段焦点卡槽
        self._placing_source: str = "held"              # "held" | "sleeve"
        self._sleeve_play_idx: int = 0
        # _pending_activate：放牌后待激活询问的牌所在（玩家索引, 卡槽索引, 牌）
        self._pending_activate: tuple[int, int, Card] | None = None
        self.menu_focus: int = 0
        self.sleeve_focus: int = 0
        self._holding_focus: int = 0
        self.discard_focus: int = 0
        self._drawn_this_turn: bool = False            # 本回合是否已抽牌（决定能否 pass）
        self.log: list[str] = []
        self.result: str | None = None                 # 本轮胜负文案缓存
        self.winners: list[int] = []                  # 本轮胜者索引
        self.game_over_winners: list[int] = []         # 游戏结束时的最终赢家
        self._tasks: list[tuple[float, Callable[[], None]]] = []
        self._last_now: float = 0.0
        self._ai_turn_pending: bool = False
        # 结算阶段细分（供 render 与任意键继续逻辑用）
        self._settled_kind: str = "round"               # "round" | "game"

    # ---- 索引别名（测试/渲染可读性）----
    @property
    def player(self) -> Side:
        return self.players[0]

    @property
    def ai(self) -> Side:
        return self.players[1]

    # ==================================================================
    # 生命周期
    # ==================================================================
    def on_enter(self, params: Any = None) -> None:
        self.params = params
        self.log.append("新对局开始。每位玩家初始 20 金币。")
        self._begin_game()

    def _begin_game(self) -> None:
        """开局：建共享牌组、随机分第4/5槽卡槽效果、收第1轮底注、随机先手。"""
        self.deck = DECK_DEF.sample_for(len(self.players), self._rng)
        self.discard = []
        self.pool = 0
        self.round_num = 0
        for p in self.players:
            p.gold = START_GOLD
            p.sleeve = []
            p.passed = False
            p.pass_score = None
            for s in p.slots:
                s.cards = []
                s.slot_effect = None
        # 第4、5卡槽随机分配卡槽效果（v1 暂无卡槽效果表 → 分配 None 占位）
        # 留接口：未来 _random_slot_effect(rng) 从效果表抽；当前为 None。
        for p in self.players:
            for i in (3, 4):
                p.slots[i].slot_effect = self._random_slot_effect()
        self._begin_round()

    def _random_slot_effect(self) -> SlotEffect | None:
        """从卡槽效果表随机抽一个。v1 无效果表 → 返回 None（空槽无费用）。

        未来扩充：从 SlotEffect 表抽样，可能含空壳/付费等。
        """
        return None

    def _begin_round(self) -> None:
        """新一轮：清 pass 状态、收底注、重置共享牌组（首轮）/沿用弃牌堆。"""
        self.round_num += 1
        for p in self.players:
            p.passed = False
            p.pass_score = None
        # 收底注 = 轮数×2
        ante = self.round_num * 2
        self.log.append(f"—— 第 {self.round_num} 轮开始，每人底注 {ante} 金币 ——")
        for i, p in enumerate(self.players):
            paid = self._pay(i, ante)
            if paid < ante:
                self.log.append(f"{'你' if i == 0 else 'AI'} 金币不足，仅付 {paid}。")
        # 随机先手
        self.current = 0 if self._rng.random() < 0.5 else 1
        self.log.append(f"{'你' if self.current == 0 else 'AI'} 先手。")
        self._begin_player_or_ai_turn()

    # ==================================================================
    # 经济方法
    # ==================================================================
    def _pay(self, who: int, amt: int) -> int:
        """who 支付 amt 进公共池，不足全交。返回实付额。"""
        if amt <= 0:
            return 0
        side = self.players[who]
        paid = min(side.gold, amt)
        side.gold -= paid
        self.pool += paid
        return paid

    def _settle_pool(self, winners: list[int]) -> None:
        """分池：唯一胜者独得整池；多胜者平分（向下取整，余数丢弃）。"""
        if not winners:
            # 无人胜（理论上不会发生，兜底）：池内金币丢弃
            self.pool = 0
            return
        share = self.pool // len(winners)
        for w in winners:
            self.players[w].gold += share
        self.pool = 0

    def _clamp_gold(self) -> None:
        """轮末丢弃超额金币到 ≤ GOLD_CAP。"""
        for p in self.players:
            if p.gold > GOLD_CAP:
                p.gold = GOLD_CAP

    # ==================================================================
    # 抽牌 / 弃牌
    # ==================================================================
    def _draw_from_deck(self) -> Card:
        """抽牌：抽牌堆空 → 弃牌堆洗为新抽牌堆（袖子不洗、不进弃牌堆）。"""
        if not self.deck:
            if self.discard:
                self.deck = self.discard
                self.discard = []
                shuffle(self.deck, self._rng)
                self.log.append("抽牌堆耗尽，弃牌堆洗为新抽牌堆。")
            else:
                # R2 兜底：抽牌堆与弃牌堆双空。理论上极罕见；建一副新标准牌堆兜底，
                # 保证游戏不卡死（与玩家约定的未定义行为，留待实测后再定规则）。
                self.deck = DECK_DEF.sample_for(len(self.players), self._rng)
                self.log.append("（极端态）抽牌堆与弃牌堆皆空，重建共享牌组兜底。")
        return self.deck.pop()

    # ==================================================================
    # 玩家回合主菜单
    # ==================================================================
    def _menu_items(self, who: int) -> list[str]:
        items = ["抽牌"]
        if self.players[who].sleeve:
            items.append("从袖子打出")
        items.append("Pass 停牌")
        return items

    def _can_pass(self) -> bool:
        """抽过牌的回合不能 pass（必须打出一张牌）。"""
        return not self._drawn_this_turn

    def _can_play_sleeve(self) -> bool:
        """抽过牌的回合不能从袖子打出。"""
        return not self._drawn_this_turn

    def _check_auto_pass(self, who: int) -> bool:
        """双重检查：无可用槽且非 pass → 自动 pass。返回是否触发了自动 pass。"""
        side = self.players[who]
        if side.passed:
            return False
        if side.first_playable_slot() is None:
            side.passed = True
            who_name = "你" if who == 0 else "AI"
            self.log.append(f"{who_name} 无可用卡槽，自动停牌。")
            return True
        return False

    # ==================================================================
    # 输入分发
    # ==================================================================
    def handle_action(self, event) -> SceneResult:
        a = event.action
        if self.phase in ("round_settled", "game_over"):
            # 任意键：轮结算 → 下一轮/游戏结束检查；游戏结束 → 返回主菜单
            if a in (actions.CONFIRM, actions.BACK, actions.SELECT) or \
               (a == actions.CHAR and event.char):
                if self.phase == "game_over":
                    return POP()
                # round_settled：进入下一轮或判游戏结束
                self._after_round_settled()
            return NONE()
        # 子选择阶段的 Esc：返回玩家菜单
        if self.phase in ("sleeve_select", "slot_select", "discard", "activate_prompt") \
                and a == actions.BACK:
            if self.phase == "slot_select" and self._placing_source == "held":
                self.phase = "holding"
                return NONE()
            if self.phase == "discard":
                self.phase = "holding"
                return NONE()
            if self.phase == "activate_prompt":
                # 激活询问 Esc 视为 N（不激活）——非强制牌才到这里
                self._resolve_activate(False)
                return NONE()
            self.phase = "menu"
            self.menu_focus = 0
            return NONE()
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
        if self.phase == "activate_prompt":
            return self._handle_activate(event)
        # ai_turn：忽略其余输入
        return NONE()

    def _handle_menu(self, event) -> SceneResult:
        a = event.action
        items = self._menu_items(self.current)
        if a in (actions.UP, actions.DOWN):
            self.menu_focus = (self.menu_focus + (1 if a == actions.DOWN else -1)) % len(items)
            return NONE()
        if a == actions.SELECT:
            return NONE()
        if a == actions.CONFIRM:
            return self._activate_menu(self.menu_focus)
        if a == actions.CHAR and event.char.isdigit():
            idx = int(event.char) - 1
            if 0 <= idx < len(items):
                return self._activate_menu(idx)
        return NONE()

    def _activate_menu(self, idx: int) -> SceneResult:
        who = self.current
        items = self._menu_items(who)
        if idx < 0 or idx >= len(items):
            return NONE()
        side = self.players[who]
        choice = items[idx]
        if choice == "抽牌":
            # 双重检查预检：无可用槽 → 自动 pass（不应抽牌）
            if self._check_auto_pass(who):
                self._end_turn(who)
                return NONE()
            self.held_card = self._draw_from_deck()
            self._drawn_this_turn = True
            who_name = "你" if who == 0 else "AI"
            self.log.append(f"{who_name} 抽到 {self.held_card}。")
            self.phase = "holding"
            self._holding_focus = 0
            return NONE()
        if choice == "从袖子打出":
            if not self._can_play_sleeve():
                self.log.append("本回合已抽牌，必须打出一张牌到桌面。")
                return NONE()
            if len(side.sleeve) > 1:
                self.phase = "sleeve_select"
                self.sleeve_focus = 0
            else:
                self._begin_place(who, source="sleeve", sleeve_idx=0)
            return NONE()
        if choice == "Pass 停牌":
            if not self._can_pass():
                self.log.append("本回合已抽牌，必须打出一张牌到桌面。")
                return NONE()
            side.passed = True
            side.pass_score = side.score()[0]
            who_name = "你" if who == 0 else "AI"
            self.log.append(f"{who_name} 选择停牌（{side.pass_score} 点）。")
            self._end_turn(who)
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
        who = self.current
        side = self.players[who]
        assert self.held_card is not None
        if choice == 0:
            self._begin_place(who, source="held")
        else:
            # 藏入袖子：付费 2 金（不足则拒绝）
            if side.gold < HIDE_COST:
                self.log.append("金币不足 2，无法藏牌。")
                return NONE()
            if len(side.sleeve) >= MAX_SLEEVE:
                self.phase = "discard"
                self.discard_focus = 0
                self.log.append("袖子已满，选择一张丢弃以藏入新牌。")
            else:
                self._stash_to_sleeve(who, self.held_card)
                self.held_card = None
                self.phase = "menu"
                self.menu_focus = 0
        return NONE()

    def _handle_discard(self, event) -> SceneResult:
        """袖子已满藏牌时：选一张丢弃，再藏入新牌。"""
        a = event.action
        who = self.current
        side = self.players[who]
        n = len(side.sleeve)
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
            dropped = side.sleeve.pop(self.discard_focus)
            who_name = "你" if who == 0 else "AI"
            self.log.append(f"{who_name} 丢弃了袖子里的 {dropped}。")
            self._stash_to_sleeve(who, self.held_card)
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
        who = self.current
        side = self.players[who]
        n = len(side.sleeve)
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
            self._begin_place(who, source="sleeve", sleeve_idx=self.sleeve_focus)
            return NONE()
        return NONE()

    def _begin_place(self, who: int, source: str, sleeve_idx: int = 0) -> None:
        """进入卡槽选择（玩家）；AI 走 _ai_place 选槽。"""
        self._placing_source = source
        self._sleeve_play_idx = sleeve_idx
        free = self.players[who].first_playable_slot()
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
            return self._try_place(self.current, self._slot_focus)
        if a == actions.CHAR and event.char.isdigit():
            idx = int(event.char) - 1
            if 0 <= idx < MAX_SLOTS:
                self._slot_focus = idx
                return self._try_place(self.current, idx)
        return NONE()

    def _current_placing_card(self, who: int) -> Card | None:
        side = self.players[who]
        if self._placing_source == "held":
            return self.held_card
        if 0 <= self._sleeve_play_idx < len(side.sleeve):
            return side.sleeve[self._sleeve_play_idx]
        return None

    # ==================================================================
    # 放牌时序核心（§16.4）
    # ==================================================================
    def _try_place(self, who: int, slot_idx: int) -> SceneResult:
        """尝试放牌到指定卡槽；失败则停留重选。"""
        side = self.players[who]
        slot = side.slots[slot_idx]
        card = self._current_placing_card(who)
        if card is None:
            self.phase = "menu"
            return NONE()
        # 1. 校验可放（栈顶空壳/空槽/空壳效果槽）
        if not slot_can_place(slot, card):
            who_name = "你" if who == 0 else "AI"
            self.log.append(f"{who_name} 卡槽 {slot_idx + 1} 无法放置（栈顶非空壳），请重选。")
            return NONE()
        # 2. 付卡槽费用（若 slot_effect.cost>0）：不够 → 拒绝重选
        se = slot.slot_effect
        cost = se.cost if se is not None else 0
        if cost > 0 and side.gold < cost:
            who_name = "你" if who == 0 else "AI"
            self.log.append(f"{who_name} 金币不足支付卡槽 {slot_idx + 1} 费用 {cost}，请重选。")
            return NONE()
        if cost > 0:
            self._pay(who, cost)
        # 3. 消耗来源牌
        if self._placing_source == "held":
            self.held_card = None
        else:
            side.sleeve.pop(self._sleeve_play_idx)
        # 4. 放牌入栈
        slot.cards.append(card)
        who_name = "你" if who == 0 else "AI"
        self.log.append(f"{who_name} 把 {card} 放到卡槽 {slot_idx + 1}。")
        # 5. 卡槽效果（on-place）
        if se is not None:
            self._run_slot_effect(who, slot_idx, card, se)
        # 6. 打出效果（on_play）
        if card.on_play is not None:
            run_effect(card.on_play.kind, self, who, slot_idx, card, card.on_play)
            # 效果可能改变了他人点数 → 软 pass 取消
            self._after_effect_cancel_pass()
        # 7. 重算点数（不立即结算）
        score, busted = side.score()
        if busted:
            self.log.append(f"{who_name} 当前 {score} 点，已爆牌！")
        # 8. 激活效果询问
        if card.on_activate is not None and not busted:
            if is_forced_activate(card):
                # 强制：直接激活
                run_effect(card.on_activate.kind, self, who, slot_idx, card, card.on_activate)
                self._after_effect_cancel_pass()
                self._after_play(who)
            else:
                # 进激活询问阶段（玩家：Y/N；AI：走 _ai_act 的激活分支）
                self._pending_activate = (who, slot_idx, card)
                if who == 0:
                    self.phase = "activate_prompt"
                else:
                    # AI 激活决策后结束回合
                    self._ai_resolve_activate()
                    self._after_play(who)
        else:
            # 无激活效果或已爆牌：直接结束 turn
            self._after_play(who)
        return NONE()

    def _handle_activate(self, event) -> SceneResult:
        """玩家激活询问：Y=激活, N=不激活。"""
        a = event.action
        if a == actions.CHAR and event.char.lower() in ("y", "n"):
            self._resolve_activate(event.char.lower() == "y")
            return NONE()
        if a == actions.CONFIRM:
            self._resolve_activate(True)
            return NONE()
        if a in (actions.LEFT, actions.RIGHT, actions.UP, actions.DOWN):
            # 在 Y/N 间切换并不改变结果（回车=是），仅占位
            return NONE()
        return NONE()

    def _resolve_activate(self, do_activate: bool) -> None:
        who, slot_idx, card = self._pending_activate  # type: ignore[misc]
        if do_activate and card.on_activate is not None:
            run_effect(card.on_activate.kind, self, who, slot_idx, card, card.on_activate)
            self._after_effect_cancel_pass()
        self._pending_activate = None
        self._after_play(who)

    # ==================================================================
    # 卡槽效果 / 袖子
    # ==================================================================
    def _run_slot_effect(self, who: int, slot_idx: int, card: Card, se: SlotEffect) -> None:
        """触发卡槽 on-place 效果。v1 无已知卡槽效果执行器，按 kind 走 registry。"""
        run_effect(se.kind, self, who, slot_idx, card, Effect(kind=se.kind, params=se.params))

    def _stash_to_sleeve(self, who: int, card: Card) -> None:
        side = self.players[who]
        self._pay(who, HIDE_COST)   # 藏牌 2 金
        side.sleeve.append(card)
        who_name = "你" if who == 0 else "AI"
        self.log.append(f"{who_name} 把 {card} 藏入袖子（-2 金）。")

    # ==================================================================
    # 软 pass 取消
    # ==================================================================
    def _after_effect_cancel_pass(self) -> None:
        """效果结算后：扫描所有 passed 玩家，总点数 != pass_score → 取消 pass。"""
        for p in self.players:
            if p.passed and p.pass_score is not None:
                cur = p.score()[0]
                if cur != p.pass_score:
                    p.passed = False
                    p.pass_score = None

    def _after_play(self, who: int) -> None:
        """打出一张牌后：重置抽牌标志，结束回合。"""
        self._drawn_this_turn = False
        self._end_turn(who)

    # ==================================================================
    # 回合推进
    # ==================================================================
    def _end_turn(self, who: int) -> None:
        """回合结束：检查全员 pass → 结算；否则推进到下一位非 pass 玩家。"""
        # 仅 pass 动作后检查结算触发
        if all(p.passed for p in self.players):
            self._round_end()
            return
        # 推进到下一位未 pass 玩家
        nxt = self._next_active(who)
        self.current = nxt
        self._begin_player_or_ai_turn()

    def _next_active(self, who: int) -> int:
        """从 who 的下一位起，找第一个未 pass 的玩家（环形）。"""
        n = len(self.players)
        for k in range(1, n + 1):
            idx = (who + k) % n
            if not self.players[idx].passed:
                return idx
        return who  # 全 pass（理论上前面已结算）

    def _begin_player_or_ai_turn(self) -> None:
        if self.current == 0:
            self._begin_player_turn()
        else:
            self._start_ai_turn()

    def _begin_player_turn(self) -> None:
        self.phase = "menu"
        self.menu_focus = 0
        self._drawn_this_turn = False
        # 双重检查预检：无可用槽 → 自动 pass（推进到下一位）
        if self._check_auto_pass(0):
            self._end_turn(0)
            return
        items = self._menu_items(0)
        if self.menu_focus >= len(items):
            self.menu_focus = 0

    # ==================================================================
    # 轮末事件顺序（§14.3，不可变）
    # ==================================================================
    def _round_end(self) -> None:
        """轮末事件顺序：
        1. 21 结算（定胜者，决胜链）
        2. 终局效果（按卡槽号横向触发，损坏移除）
        3. 分池
        4. 桌面牌 → 弃牌堆（损坏牌已移除，不进）
        5. 丢弃超额金币
        6. 0 检查（游戏结束 / 下一轮）
        """
        # 1. 21 结算
        self.winners = self._resolve_winners()
        # 2. 终局效果（横向：slot 0..4 × players × slot.cards 顺序触发 on_end）
        removed = self._trigger_on_end()
        # 3. 分池
        self._settle_pool(self.winners)
        # 4. 桌面牌 → 弃牌堆（损坏牌已收集到 removed，跳过）
        for p in self.players:
            for s in p.slots:
                for c in s.cards:
                    if c not in removed:
                        self.discard.append(c)
                s.cards = []
            p.passed = False
            p.pass_score = None
        # 5. 丢弃超额金币
        self._clamp_gold()
        # 6. 0 检查
        self._settled_kind = "round"
        if any(p.gold <= 0 for p in self.players):
            self._begin_game_over()
        else:
            self.phase = "round_settled"
            self.result = self._round_result_text()

    def _trigger_on_end(self) -> list[Card]:
        """终局横向触发：slot 0..4 × players × slot.cards 顺序触发 on_end。

        损坏牌收集到返回列表（统一从牌池移除，不进弃牌堆）。
        """
        removed: list[Card] = []
        for slot_idx in range(MAX_SLOTS):
            for who, p in enumerate(self.players):
                slot = p.slots[slot_idx]
                for card in slot.cards:
                    if card.on_end is not None:
                        run_effect(card.on_end.kind, self, who, slot_idx, card, card.on_end)
                        # 损坏执行器会登记移除；这里按 kind 统一收集
                        if card.on_end.kind == BROKEN:
                            removed.append(card)
        return removed

    def _resolve_winners(self) -> list[int]:
        """21 决胜链（§14.5）：定胜者索引列表。"""
        n = len(self.players)
        scores = [p.score()[0] for p in self.players]
        busted = [p.score()[1] for p in self.players]
        # 爆牌者剔除出竞争；未爆者中点数最高者胜
        active = [i for i in range(n) if not busted[i]]
        if not active:
            # 全员爆牌 → 点数最小者胜
            mn = min(scores)
            return [i for i in range(n) if scores[i] == mn]
        mx = max(scores[i] for i in active)
        top = [i for i in active if scores[i] == mx]
        if len(top) == 1:
            return top
        # 并列最高分
        if mx != 21:
            # 非 21 并列 → 平分池
            return top
        # 正好 21 并列 → 组成 21 的桌面牌张数少者胜（不含袖子）
        counts = [len(self.players[i].table) for i in top]
        fewest = min(counts)
        few = [i for i in top if counts[i] == fewest]
        if len(few) == 1:
            return few
        # 仍并列 → 单张最大点数大者胜（按结算时采用的多值选中值）
        maxpt = [self._max_single_point(self.players[i]) for i in few]
        biggest = max(maxpt)
        best = [i for i in few if self._max_single_point(self.players[i]) == biggest]
        if len(best) == 1:
            return best
        # 仍并列 → 平分池
        return best

    @staticmethod
    def _max_single_point(side: Side) -> int:
        """该方桌面牌中单张最大点数（按结算时采用的值，即多值选中的最优组合里
        各牌取值）。简化：取每张牌 points 里的最大候选值（A 算 11），用于决胜。"""
        best = 0
        for c in side.table:
            if c.points:
                best = max(best, max(c.points))
        return best

    def _round_result_text(self) -> str:
        if len(self.winners) == 1:
            w = self.winners[0]
            return "你赢了本轮！" if w == 0 else "AI 赢了本轮。"
        return "本轮平局，平分公共池。"

    def _after_round_settled(self) -> None:
        """轮结算面板按任意键后：进入下一轮。"""
        self._begin_round()

    # ==================================================================
    # 游戏结束
    # ==================================================================
    def _begin_game_over(self) -> None:
        mx = max(p.gold for p in self.players)
        self.game_over_winners = [i for i, p in enumerate(self.players) if p.gold == mx]
        self.phase = "game_over"
        self._tasks.clear()
        self._ai_turn_pending = False

    # ==================================================================
    # 定时任务 / tick
    # ==================================================================
    def schedule(self, delay: float, fn: Callable[[], None]) -> None:
        self._tasks.append((self._last_now + delay, fn))

    def on_tick(self, now: float) -> None:
        self._last_now = now
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

    # ==================================================================
    # AI
    # ==================================================================
    def _start_ai_turn(self) -> None:
        self.phase = "ai_turn"
        self._ai_turn_pending = True

    def _ai_act(self) -> None:
        """AI 启发式决策（遵循与玩家相同的约束）。

        决策层：点数层(≥17倾向pass/≤11抽/12-16概率) + 经济层(付费槽能否承担、藏牌gold<2不藏)
        + 软pass重决策 + 激活选择 + 多轮意识(无望pass省金)。
        状态机：已 pass/busted → 结束；桌满无处放 → 强制 pass；本回合已抽牌 → 必须打出。
        """
        if self.phase != "ai_turn":
            return
        who = self.current
        side = self.players[who]
        if side.passed:
            self._ai_end_turn()
            return
        score, busted = side.score()
        ps, _ = self.players[0].score()
        # 双重检查预检：无可用槽 → 自动 pass
        if self._check_auto_pass(who):
            self._ai_end_turn()
            return
        # 本回合已抽牌：必须打出一张牌（不能 pass / 不能出袖子）→ 继续抽
        if self._drawn_this_turn:
            self._ai_draw()
            return
        # 无望局面（金币极少且点数低）：pass 认输省金
        hopeless = side.gold <= 2 and score < 12
        # 点数足够高 → 大概率 pass
        if score >= 17 and not hopeless and self._rng.random() < 0.85:
            side.passed = True
            side.pass_score = score
            self.log.append("AI 选择停牌。")
            self._ai_end_turn()
            return
        if hopeless:
            side.passed = True
            side.pass_score = score
            self.log.append("AI 金币紧张，选择停牌认输。")
            self._ai_end_turn()
            return
        if score <= 11:
            self._ai_draw()
            return
        must = self.players[0].passed and ps > score  # 玩家已停且点数更高，AI 被迫追
        if must or self._rng.random() < 0.6:
            self._ai_draw()
            return
        # 偶尔从袖子出牌（若有、本回合未抽牌）
        if side.sleeve and self._rng.random() < 0.3:
            for i, c in enumerate(side.sleeve):
                _, b2 = hand_score(side.table + [c])
                if not b2:
                    self._ai_play_from_sleeve(i)
                    return
        side.passed = True
        side.pass_score = score
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
        who = self.current
        side = self.players[who]
        _, busted = hand_score(side.table + [card])
        if not busted:
            # 多数直接打出；gold≥2 且袖子未满时小概率藏
            if side.gold >= HIDE_COST and len(side.sleeve) < MAX_SLEEVE and self._rng.random() < 0.15:
                self._stash_to_sleeve(who, card)
                # 藏牌不结束回合：仍须打出一张牌 → 继续抽
                self.schedule(AI_STEP_DELAY, self._ai_act)
                return
            self._ai_place_held(card)
        else:
            # 会爆：优先藏入袖子（gold≥2 且有空位），否则被迫丢弃一张再藏
            if side.gold >= HIDE_COST and len(side.sleeve) < MAX_SLEEVE:
                self._stash_to_sleeve(who, card)
                self.schedule(AI_STEP_DELAY, self._ai_act)
            elif side.gold >= HIDE_COST and len(side.sleeve) >= MAX_SLEEVE:
                drop_idx = min(range(len(side.sleeve)),
                               key=lambda i: _card_value(side.sleeve[i]))
                dropped = side.sleeve.pop(drop_idx)
                self.log.append(f"AI 丢弃了袖子里的 {dropped}。")
                self._stash_to_sleeve(who, card)
                self.schedule(AI_STEP_DELAY, self._ai_act)
            else:
                # 金币不足藏牌：被迫打出（可能爆牌，但爆牌不立即结算）
                self._ai_place_held(card)

    def _ai_place_held(self, card: Card) -> None:
        """AI 把持有的牌放到一个可放卡槽（自动挑空槽/空壳槽）。"""
        who = self.current
        side = self.players[who]
        slot = side.first_playable_slot()
        if slot is None:
            side.passed = True
            side.pass_score = side.score()[0]
            self.log.append("AI 无可用卡槽，选择停牌。")
            self._ai_end_turn()
            return
        # 复用放牌时序（付卡槽费用 → 卡槽效果 → on_play → 激活）
        self._placing_source = "held"
        self._sleeve_play_idx = 0
        self._slot_focus = slot
        # 直接走 _try_place 的核心（不进 slot_select 阶段）
        self._ai_try_place(who, slot, card)

    def _ai_play_from_sleeve(self, idx: int) -> None:
        who = self.current
        side = self.players[who]
        if idx < 0 or idx >= len(side.sleeve):
            self._ai_end_turn()
            return
        slot = side.first_playable_slot()
        if slot is None:
            side.passed = True
            side.pass_score = side.score()[0]
            self.log.append("AI 无可用卡槽，选择停牌。")
            self._ai_end_turn()
            return
        self._placing_source = "sleeve"
        self._sleeve_play_idx = idx
        self._slot_focus = slot
        card = side.sleeve[idx]
        self._ai_try_place(who, slot, card)

    def _ai_try_place(self, who: int, slot_idx: int, card: Card) -> None:
        """AI 放牌时序（与玩家 _try_place 一致，但不进 slot_select / activate_prompt）。

        会处理卡槽费用、卡槽效果、on_play、激活询问（AI 决策）。
        """
        side = self.players[who]
        slot = side.slots[slot_idx]
        se = slot.slot_effect
        cost = se.cost if se is not None else 0
        if cost > 0 and side.gold < cost:
            # AI 选的槽付不起 → 换下一个可放且付得起的槽；都没有则 pass
            alt = self._ai_find_affordable_slot(who, card)
            if alt is None:
                side.passed = True
                side.pass_score = side.score()[0]
                self.log.append("AI 无法支付卡槽费用，选择停牌。")
                self._ai_end_turn()
                return
            slot_idx = alt
            slot = side.slots[slot_idx]
            se = slot.slot_effect
            cost = se.cost if se is not None else 0
        if cost > 0:
            self._pay(who, cost)
        # 消耗来源牌
        if self._placing_source == "held":
            self.held_card = None
        else:
            side.sleeve.pop(self._sleeve_play_idx)
        # 放牌入栈
        slot.cards.append(card)
        who_name = "AI"
        self.log.append(f"{who_name} 把 {card} 放到卡槽 {slot_idx + 1}。")
        if se is not None:
            self._run_slot_effect(who, slot_idx, card, se)
        if card.on_play is not None:
            run_effect(card.on_play.kind, self, who, slot_idx, card, card.on_play)
            self._after_effect_cancel_pass()
        score, busted = side.score()
        if busted:
            self.log.append(f"{who_name} 当前 {score} 点，已爆牌！")
        # 激活：AI 启发式
        if card.on_activate is not None and not busted:
            if is_forced_activate(card):
                run_effect(card.on_activate.kind, self, who, slot_idx, card, card.on_activate)
                self._after_effect_cancel_pass()
            else:
                self._pending_activate = (who, slot_idx, card)
                self._ai_resolve_activate()
        self._after_play(who)

    def _ai_find_affordable_slot(self, who: int, card: Card) -> int | None:
        """找一个可放且付得起费用的卡槽。"""
        side = self.players[who]
        for i, s in enumerate(side.slots):
            if not slot_can_place(s, card):
                continue
            cost = s.slot_effect.cost if s.slot_effect is not None else 0
            if side.gold >= cost:
                return i
        return None

    def _ai_resolve_activate(self) -> None:
        """AI 激活决策：on_activate 对自己有利则激活，否则不激活。

        v1 已知 on_activate 执行器尚未定义具体效果；默认不激活（保守）。
        未来按 kind 硬编码：对自己加金币/减点数等利己效果 → 激活。
        """
        if self._pending_activate is None:
            return
        who, slot_idx, card = self._pending_activate
        # 强制牌已在 _try_place / _ai_try_place 中直接激活，不会到这里
        # 默认不激活（保守）；留接口
        activate = False
        if activate and card.on_activate is not None:
            run_effect(card.on_activate.kind, self, who, slot_idx, card, card.on_activate)
            self._after_effect_cancel_pass()
        self._pending_activate = None

    def _ai_end_turn(self) -> None:
        self._drawn_this_turn = False
        self._end_turn(self.current)

    # ==================== 渲染 ====================
    def render(self, buf: FrameBuffer) -> None:
        w, h = buf.w, buf.h
        draw_box(buf, 0, 0, w, h, title=f"21点 · 第{self.round_num}轮 · 人机对战")

        # ---- AI 区 ----
        ai = self.players[1]
        as_score, as_busted = ai.score()
        ai_label = f"【AI 对手】 点数:{as_score}  金币:{ai.gold}" + ("  爆牌!" if as_busted else "")
        buf.put_text(2, 1, ai_label, theme.WARN if as_busted else theme.ACCENT2, theme.BG)
        if ai.passed:
            buf.put_text(2 + text_width(ai_label) + 2, 1, "[停牌]", theme.DIM, theme.BG)
        deck_txt = f"牌堆:{len(self.deck)} 弃:{len(self.discard)} 池:{self.pool}"
        buf.put_text(w - 2 - text_width(deck_txt), 1, deck_txt, theme.DIM, theme.BG)
        self._render_slots(buf, 2, owner=1)
        buf.put_text(2, 6, "AI 袖子:", theme.DIM, theme.BG)
        self._render_sleeve_tokens(buf, 11, 6, ai.sleeve, face_up=False)

        self._hline(buf, 1, 7, w - 1)

        # ---- 状态 / 握牌区 ----
        put_centered(buf, 8, self._status_text(), w, self._status_color(), theme.BG)
        if self.phase == "holding" and self.held_card is not None:
            x = (w - CARD_W) // 2
            self._draw_card(buf, x, 9, self.held_card, face_up=True, hl=True)
        elif self.phase in ("slot_select", "discard", "sleeve_select") \
                and self._current_placing_card(self.current) is not None:
            x = (w - CARD_W) // 2
            self._draw_card(buf, x, 9, self._current_placing_card(self.current),
                            face_up=True, hl=True)
        elif self.phase == "activate_prompt" and self._pending_activate is not None:
            x = (w - CARD_W) // 2
            self._draw_card(buf, x, 9, self._pending_activate[2], face_up=True, hl=True)

        self._hline(buf, 1, 13, w - 1)

        # ---- 玩家区 ----
        player = self.players[0]
        self._render_slots(buf, 14, owner=0)
        buf.put_text(2, 18, "你的袖子:", theme.DIM, theme.BG)
        self._render_sleeve_tokens(buf, 12, 18, player.sleeve, face_up=True,
                                   selectable=(self.phase in ("sleeve_select", "discard")))
        ps_score, ps_busted = player.score()
        p_label = f"【你】 点数:{ps_score}  金币:{player.gold}" + ("  爆牌!" if ps_busted else "")
        put_centered(buf, 19, p_label, w, theme.WARN if ps_busted else theme.HEADING, theme.BG)
        if player.passed:
            buf.put_text(2, 19, "[你已停牌]", theme.DIM, theme.BG)

        self._hline(buf, 1, 20, w - 1)

        # ---- 操作面板 / 日志 ----
        self._render_panel(buf, w)
        self._render_log(buf, w)

        if self.phase == "round_settled":
            self._render_round_settlement(buf, w, h)
        elif self.phase == "game_over":
            self._render_game_over(buf, w, h)

    # ---- 渲染辅助 ----
    def _status_text(self) -> str:
        if self.phase == "round_settled":
            return self.result or "本轮结束"
        if self.phase == "game_over":
            return "游戏结束"
        if self.phase == "ai_turn":
            return "AI 思考中…"
        if self.phase == "holding":
            return f"你抽到 {self.held_card} —— 打出 还是 藏入袖子(2金)？"
        if self.phase == "slot_select":
            card = self._current_placing_card(self.current)
            return f"选择卡槽放置 {card}（←→ 切换 · 回车确认 · 金色可放 · 红色不可放）"
        if self.phase == "discard":
            return f"袖子已满，选一张丢弃以藏入 {self.held_card}"
        if self.phase == "sleeve_select":
            return "选择袖子里的牌打出"
        if self.phase == "activate_prompt":
            card = self._pending_activate[2] if self._pending_activate else None
            return f"{card} 有激活效果，是否发动？(Y 激活 / N 不激活)"
        if self.players[0].passed:
            return "你已停牌，等待 AI…"
        if self._drawn_this_turn:
            return "你已抽牌，必须打出一张牌到桌面"
        return "你的回合"

    def _status_color(self) -> int:
        if self.phase == "round_settled":
            return theme.GOLD
        if self.phase == "game_over":
            return theme.GOLD
        if self.phase == "ai_turn":
            return theme.ACCENT2
        if self.phase in ("holding", "slot_select", "discard", "sleeve_select", "activate_prompt"):
            return theme.ACCENT
        return theme.HEADING

    def _render_slots(self, buf: FrameBuffer, y: int, owner: int) -> None:
        """绘制固定 5 个卡槽（栈模型）。玩家在 slot_select 时高亮焦点。"""
        w = buf.w
        side = self.players[owner]
        total = MAX_SLOTS * CARD_W + max(0, MAX_SLOTS - 1) * CARD_GAP
        x0 = max(2, (w - total) // 2)
        slot_select = (self.phase == "slot_select" and owner == 0)
        for i in range(MAX_SLOTS):
            x = x0 + i * (CARD_W + CARD_GAP)
            slot = side.slots[i]
            focused = slot_select and i == self._slot_focus
            if slot.cards:
                top = slot.cards[-1]
                stack_n = len(slot.cards)
                # 占据判定：栈顶非空壳 → 红色（放置会失败）；空壳顶 → 金色（可叠）
                free_top = is_shell_card(top)
                self._draw_card(buf, x, y, top, face_up=True, hl=False,
                                slot_hl=focused, slot_free=free_top)
                if stack_n > 1:
                    # 叠放计数
                    buf.put_text(x + CARD_W - 3, y + 1, f"×{stack_n}", theme.GOLD, theme.BG)
            else:
                self._draw_empty_slot(buf, x, y, focused=focused)
            # 卡槽编号 + 卡槽效果标注
            se = slot.slot_effect
            if se is not None:
                se_label = f"[{i+1}{_slot_effect_tag(se)}]"
            else:
                se_label = f"[{i+1}]"
            buf.put_text(x + 1, y + CARD_H, se_label, theme.GOLD if se else theme.DIM, theme.BG)

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
                label = c.tag
                if text_width(label) <= 1:
                    buf.put_text(cx + 1, y, label + " ", fg, bg)
                else:
                    buf.put_text(cx + 1, y, label[:2], fg, bg)
                buf.set_char(cx + 3, y, c.suit, fg, bg)
            else:
                for dx in (1, 2, 3):
                    buf.set_char(cx + dx, y, "▓", theme.DIM, bg)
            cx += TOKEN_W + CARD_GAP

    def _draw_card(self, buf: FrameBuffer, x: int, y: int, card: Card,
                   face_up: bool = True, hl: bool = False,
                   slot_hl: bool = False, slot_free: bool = True) -> None:
        """画一张 4 行 ASCII 牌。tag 显示在左上角（多值如 1|11）。"""
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
            label = card.tag
            lw = text_width(label)
            # 左上：tag（截断到 CARD_W-3）
            buf.put_text(x + 1, y + 1, label[:max(1, CARD_W - 3)], fg, bg)
            if lw < CARD_W - 3:
                buf.set_char(x + 1 + lw, y + 1, card.suit, fg, bg)
            # 中央花色
            buf.set_char(x + (CARD_W // 2), y + 2, card.suit, theme.HEADING, bg)
            # 右下：tag
            buf.put_text(max(x + 1, x2 - lw), y2 - 1, label[:max(1, CARD_W - 3)], fg, bg)
        else:
            for ry in range(y + 1, y2):
                for cx in range(x + 1, x2):
                    buf.set_char(cx, ry, "░", theme.DIM, bg)

    def _render_panel(self, buf: FrameBuffer, w: int) -> None:
        y0 = 21
        if self.phase == "menu":
            items = self._menu_items(self.current)
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
            buf.put_text(2, y0, "刚抽到的牌如何处置？（藏牌 -2 金）", theme.ACCENT, theme.BG)
            opts = ["1. 打出上桌（选卡槽）", "2. 藏入袖子（2金）"]
            if len(self.players[self.current].sleeve) >= MAX_SLEEVE:
                opts[1] += "（袖子已满，将选一张丢弃）"
            if self.players[self.current].gold < HIDE_COST:
                opts[1] += "（金币不足）"
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
            buf.put_text(2, y0 + 2, "（金色=可放 · 红色=已占用不可放 · 卡槽效果标在 [n] 处）",
                         theme.DIM, theme.BG)
        elif self.phase == "discard":
            buf.put_text(2, y0, "袖子已满：选一张丢弃以藏入新牌", theme.WARN, theme.BG)
            buf.put_text(2, y0 + 1, "←→ 切换 · 回车 丢弃 · Esc 取消藏牌", theme.DIM, theme.BG)
        elif self.phase == "sleeve_select":
            buf.put_text(2, y0, "选择袖子里的牌打出:", theme.ACCENT, theme.BG)
            buf.put_text(2, y0 + 1, "←→ 切换 · 回车 选择 · Esc 返回菜单", theme.DIM, theme.BG)
        elif self.phase == "activate_prompt":
            buf.put_text(2, y0, "是否发动激活效果？", theme.ACCENT, theme.BG)
            buf.put_text(2, y0 + 1, "Y 激活（免费）· N 不激活 · 回车=激活 · Esc=不激活",
                         theme.DIM, theme.BG)
        elif self.phase == "ai_turn":
            buf.put_text(2, y0, "AI 回合，请稍候…", theme.DIM, theme.BG)
            buf.put_text(2, y0 + 1, "（按 Esc 放弃对局返回主菜单）", theme.DIM, theme.BG)
        elif self.phase == "round_settled":
            buf.put_text(2, y0, "本轮结算完成，按任意键进入下一轮。", theme.GOLD, theme.BG)
        elif self.phase == "game_over":
            buf.put_text(2, y0, "游戏结束，按任意键返回主菜单。", theme.GOLD, theme.BG)

    def _render_log(self, buf: FrameBuffer, w: int) -> None:
        recent = self.log[-2:]
        if not recent:
            return
        buf.put_text(2, 27, "日志:", theme.DIM, theme.BG)
        buf.put_text(8, 27, recent[-1][:w - 10], theme.DIM, theme.BG)
        if len(recent) == 2:
            buf.put_text(2, 28, recent[-2][:w - 4], theme.DIM, theme.BG)

    def _render_round_settlement(self, buf: FrameBuffer, w: int, h: int) -> None:
        scores = [p.score()[0] for p in self.players]
        title = "本轮结算"
        lines = [
            f"第 {self.round_num} 轮结束",
            f"你的点数: {scores[0]}   金币: {self.players[0].gold}",
            f"AI 的点数: {scores[1]}   金币: {self.players[1].gold}",
            f"公共池已分: {self.result or ''}",
        ]
        box_h = len(lines) + 5
        box_w = max(max(text_width(l) for l in lines), text_width(title), 20) + 8
        bx = (w - box_w) // 2
        by = (h - box_h) // 2
        buf.fill_rect(bx - 1, by - 1, box_w + 2, box_h + 2, " ", theme.FG, theme.OVERLAY_BG)
        draw_box(buf, bx, by, box_w, box_h, title=title, fg=theme.OVERLAY_BORDER, bg=theme.OVERLAY_BG)
        for i, line in enumerate(lines):
            buf.put_text(bx + 2, by + 2 + i, line, theme.FG, theme.OVERLAY_BG)
        put_centered(buf, by + box_h - 1, "按任意键继续", theme.DIM, theme.OVERLAY_BG)

    def _render_game_over(self, buf: FrameBuffer, w: int, h: int) -> None:
        winners = self.game_over_winners
        if len(winners) == 1:
            title = "你赢了！" if winners[0] == 0 else "你输了。"
            color = theme.GOLD if winners[0] == 0 else theme.WARN
        else:
            title = "平局（并列最多金币）"
            color = theme.DIM
        lines = [
            f"游戏结束（第 {self.round_num} 轮）",
            f"你的金币: {self.players[0].gold}",
            f"AI 的金币: {self.players[1].gold}",
        ]
        box_h = len(lines) + 5
        box_w = max(max(text_width(l) for l in lines), text_width(title), 20) + 8
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
        if self.phase in ("round_settled", "game_over"):
            return ["任意键 继续"]
        if self.phase == "ai_turn":
            return ["Esc 放弃对局", "Tab 牌堆"]
        if self.phase == "holding":
            return ["↑↓ 选择", "回车/1 打出", "2 藏入袖子(2金)", "Tab 牌堆", "Esc 放弃对局"]
        if self.phase == "slot_select":
            return ["←→ 切换卡槽", "回车 放置", "1-5 直选", "Tab 牌堆", "Esc 返回"]
        if self.phase == "discard":
            return ["←→ 选丢弃", "回车 丢弃", "Tab 牌堆", "Esc 取消"]
        if self.phase == "sleeve_select":
            return ["←→ 选袖子牌", "回车 选择", "Tab 牌堆", "Esc 返回菜单"]
        if self.phase == "activate_prompt":
            return ["Y 激活", "N 不激活", "回车=激活", "Esc=不激活"]
        return ["↑↓ 选择", "回车 确认", "1-3 快捷", "Tab 牌堆", "Esc 放弃对局"]

    # ==================== Tab 牌堆总览 ====================
    def _full_deck(self) -> list[Card]:
        """本局完整牌组构成（按套牌展开，用于 overlay 网格遍历）。"""
        cards: list[Card] = []
        for s in DECK_DEF.suits:
            cards.extend(s.cards)
        return cards

    def _card_location(self, card: Card) -> str:
        """牌当前所在位置：'抽牌堆' / '你-桌面' / '你-袖子' / 'AI-桌面' / 'AI-袖子' / '弃牌堆' / '已出'。"""
        if card in self.players[0].table:
            return "你-桌面"
        if card in self.players[0].sleeve:
            return "你-袖子"
        if card in self.players[1].table:
            return "AI-桌面"
        if card in self.players[1].sleeve:
            return "AI-袖子"
        if card in self.deck:
            return "抽牌堆"
        if card in self.discard:
            return "弃牌堆"
        return "已出"

    def _card_loc_color(self, loc: str) -> int:
        return {
            "抽牌堆": theme.DIM,
            "弃牌堆": theme.DIM,
            "你-桌面": theme.HEADING,
            "你-袖子": theme.ACCENT,
            "AI-桌面": theme.ACCENT2,
            "AI-袖子": theme.ACCENT2,
            "已出": theme.DIM,
        }.get(loc, theme.DIM)

    def render_overlay(self, buf: FrameBuffer, w: int, h: int) -> bool:
        """按住 Tab：本局牌组构成网格 + 左上角抽牌堆顶牌的隐写卡背。"""
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
        buf.put_text(back_x, back_y + BACK_H + 2,
                     f"抽牌堆 {len(self.deck)} · 弃牌堆 {len(self.discard)}",
                     theme.DIM, theme.OVERLAY_BG)

        # ---- 右上角：说明 ----
        info_x = back_x + BACK_W + 3
        info_lines = [
            ("花色编码", theme.HEADING),
            ("┆ 在四角 → ♠♥♦♣", theme.DIM),
            ("", theme.DIM),
            ("点数编码", theme.HEADING),
            ("顶边 ┈ 的槽位 = 点数", theme.DIM),
            ("", theme.DIM),
            ("图例", theme.HEADING),
            ("抽牌堆", self._card_loc_color("抽牌堆")),
            ("弃牌堆", self._card_loc_color("弃牌堆")),
            ("你-桌面", self._card_loc_color("你-桌面")),
            ("你-袖子", self._card_loc_color("你-袖子")),
            ("AI-桌面", self._card_loc_color("AI-桌面")),
            ("AI-袖子", self._card_loc_color("AI-袖子")),
        ]
        for i, (text, color) in enumerate(info_lines):
            if text:
                buf.put_text(info_x, back_y + i, text, color, theme.OVERLAY_BG)

        # ---- 下方：本局牌组构成网格（按套牌×rank） ----
        grid_y = py + BACK_H + 3 + grid_top_pad
        buf.put_text(px + 2, grid_y - 1, "本局牌组构成（套牌 × 点数）",
                     theme.HEADING, theme.OVERLAY_BG)

        # 按 DECK_DEF.suits 的顺序排成行
        col_w = 5
        # 表头：rank 列
        for col, r in enumerate(range(1, 14)):
            cx = px + 4 + col * col_w
            buf.put_text(cx, grid_y, rank_label(r), theme.DIM, theme.OVERLAY_BG)
        for row, suit_def in enumerate(DECK_DEF.suits):
            gy = grid_y + 1 + row
            buf.put_text(px + 2, gy, suit_def.symbol, suit_color(suit_def.symbol), theme.OVERLAY_BG)
            buf.put_text(px + 3, gy, ":", theme.DIM, theme.OVERLAY_BG)
            # 该套牌的牌（按 rank 排列）
            by_rank = {c.rank: c for c in suit_def.cards if c.rank is not None}
            for col, r in enumerate(range(1, 14)):
                cx = px + 4 + col * col_w
                card = by_rank.get(r)
                if card is None:
                    buf.put_text(cx, gy, "  ·  ", theme.DIM, theme.OVERLAY_BG)
                    continue
                loc = self._card_location(card)
                color = self._card_loc_color(loc)
                label = rank_label(r) + suit_def.symbol
                buf.put_text(cx, gy, label, color, theme.OVERLAY_BG)

        put_centered(buf, py + ph - 1, "松开 Tab 关闭", theme.DIM, theme.OVERLAY_BG)
        return True


# =====================================================================
# 模块级辅助 + 执行器注册
# =====================================================================
def _card_value(card: Card) -> int:
    """AI 弃牌策略用：牌的"数值"（A=1, JQK=10，便于挑最小弃）。"""
    if card.rank == 1:
        return 1
    if card.rank is not None and card.rank >= 11:
        return 10
    if card.rank is not None:
        return card.rank
    # 怪套：取 points 的最小值
    return min(card.points) if card.points else 0


def _slot_effect_tag(se: SlotEffect) -> str:
    """卡槽效果在卡槽编号旁的缩写标注。"""
    cost = f"·{se.cost}金" if se.cost > 0 else ""
    return f"{se.kind}{cost}"


# 已知效果执行器（幂等注册，供 Game21Scene 构造时调用）
def _register_known_effects() -> None:
    @register(EXPLOIT)
    def _exec_exploit(scene: "Game21Scene", actor_idx: int, slot_idx: int,
                     card: Card, effect: Effect) -> None:
        """剥削（on_play）：打出时所有其他玩家各付 level 进公共池。"""
        amt = effect.level if effect.level > 0 else 1
        who_name = "你" if actor_idx == 0 else "AI"
        for i, p in enumerate(scene.players):
            if i == actor_idx:
                continue
            paid = scene._pay(i, amt)
            other_name = "你" if i == 0 else "AI"
            scene.log.append(f"{other_name} 被剥削，支付 {paid} 金（{who_name} 的 {card}）。")

    @register(BROKEN)
    def _exec_broken(scene: "Game21Scene", actor_idx: int, slot_idx: int,
                     card: Card, effect: Effect) -> None:
        """损坏（on_end）：从活跃牌池移除。执行器仅记日志；实际移除由 _trigger_on_end 收集。"""
        who_name = "你" if actor_idx == 0 else "AI"
        scene.log.append(f"{who_name} 的 {card} 损坏，从牌池移除。")

    @register(SHELL)
    def _exec_shell(scene: "Game21Scene", actor_idx: int, slot_idx: int,
                    card: Card, effect: Effect) -> None:
        """空壳：被动效果，无执行逻辑（参与 slot_can_place 判定）。"""
        return None
