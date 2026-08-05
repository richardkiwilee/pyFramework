"""卡牌效果 / 卡槽效果 / 执行器注册表（阶段 7）。

- Effect：卡牌效果（on_play/on_activate/on_end 三类）。
- SlotEffect：卡槽效果（on-place 一次性，绑槽不绑牌）。
- SHELL / FORCED：词缀常量。空壳（被动参与可放牌判定）；强制（有 on_activate 必须激活）。
- slot_can_place / slot_is_occupied：栈模型判定（空壳牌/空壳效果槽）。
- EFFECT_REGISTRY：kind → executor(scene, actor_idx, slot_idx, card, effect)。
  新增效果 = 加一条注册，不改 Card/Suit 结构。

已知执行器（首版）：
- 剥削（on_play）：打出时所有其他玩家各付 level 进公共池。
- 损坏（on_end）：轮末从活跃牌池移除该牌（不进弃牌堆、本局剩余轮永久缺席）。
- 空壳（被动）：无执行器，参与 slot_can_place 判定。

执行器签名：executor(scene, actor_idx, slot_idx, card, effect) -> None
  - scene：Game21Scene 实例（访问 _pay/players/pool）。
  - actor_idx：触发该效果的玩家索引。
  - slot_idx：牌所在卡槽索引（-1 表示不在槽上，如袖子牌触发，目前不会发生）。
  - card：触发效果的牌。
  - effect：Effect 实例（含 level/params）。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, TYPE_CHECKING

if TYPE_CHECKING:
    from .cards import Card

# ---- 词缀常量 ----
SHELL = "空壳"      # 空壳牌/空壳卡槽效果：允许在其上继续叠牌
FORCED = "强制"      # 强制词条：有 on_activate 则必须激活
EXPLOIT = "剥削"
BROKEN = "损坏"

# 卡牌是否带「强制」词条：on_activate 存在且其 effect.params.get("forced")，或单独的 FORCED 效果。
# 简化约定：on_activate 的 Effect.params["forced"]=True 表示强制激活。


@dataclass(frozen=True)
class Effect:
    """卡牌效果。kind=词缀名，level=参数（剥削1 的 1），params=额外参数。"""
    kind: str
    level: int = 0
    params: dict = field(default_factory=dict)


@dataclass(frozen=True)
class SlotEffect:
    """卡槽效果（on-place 一次性）。cost=放牌费用（0=免费槽）。"""
    kind: str
    cost: int = 0
    params: dict = field(default_factory=dict)


def is_shell_card(card: Card) -> bool:
    """该牌是否为空壳牌（任意 on_* 效果 kind==SHELL）。前向兼容：v1 无此类牌。"""
    for eff in (card.on_play, card.on_activate, card.on_end):
        if eff is not None and eff.kind == SHELL:
            return True
    return False


def is_forced_activate(card: Card) -> bool:
    """该牌的 on_activate 是否为强制激活。"""
    eff = card.on_activate
    return eff is not None and bool(eff.params.get("forced", False))


def slot_can_place(slot, card: Card) -> bool:
    """卡槽是否可放牌：空槽 / 空壳效果槽 / 栈顶是空壳牌。

    slot：含 .cards 与 .slot_effect 的对象（Side.slots[i]）。
    """
    # 空壳效果槽：永远可放
    se = getattr(slot, "slot_effect", None)
    if se is not None and se.kind == SHELL:
        return True
    cards = getattr(slot, "cards", [])
    if not cards:
        return True
    # 栈顶是空壳牌 → 可放
    return is_shell_card(cards[-1])


def slot_is_occupied(slot) -> bool:
    """卡槽是否被占据：栈顶是非空壳牌（用于「5槽满须 pass」判定）。"""
    cards = getattr(slot, "cards", [])
    if not cards:
        return False
    return not is_shell_card(cards[-1])


def slot_is_open(slot) -> bool:
    """卡槽是否对任意牌开放（与具体牌无关）：空槽 / 空壳效果槽 / 栈顶空壳牌。

    与 :func:`slot_can_place` 的区别：后者接收具体 card（当前实现未用到 card，
    二者等价），本函数语义上表达「该槽还能不能继续放牌」，供自动 pass 双重检查
    与 AI 选槽使用。
    """
    se = getattr(slot, "slot_effect", None)
    if se is not None and se.kind == SHELL:
        return True
    cards = getattr(slot, "cards", [])
    if not cards:
        return True
    return is_shell_card(cards[-1])


# ---- 执行器注册表 ----
# executor(scene, actor_idx, slot_idx, card, effect) -> None
EFFECT_REGISTRY: dict[str, Callable[[Any, int, int, Card, Effect], None]] = {}


def register(kind: str):
    """装饰器：注册一个效果执行器。"""
    def deco(fn: Callable[..., None]) -> Callable[..., None]:
        EFFECT_REGISTRY[kind] = fn
        return fn
    return deco


def run_effect(kind: str, scene, actor_idx: int, slot_idx: int, card, effect: Effect) -> None:
    """按 kind 查找并执行效果。未注册的 kind 静默跳过（前向兼容未定效果）。"""
    fn = EFFECT_REGISTRY.get(kind)
    if fn is not None:
        fn(scene, actor_idx, slot_idx, card, effect)


# ---- 已知执行器（延迟注册，避免循环导入）----
# 剥削 / 损坏执行器需要访问场景经济方法，在 game21 模块加载后由 _register_known_effects() 注册。
# 这里只留注册入口，具体执行器定义在 scenes/game21.py 末尾调用 register() 装饰。

def _ensure_known_effects_registered() -> None:
    """触发执行器注册（首次调用时从 scenes.game21 导入注册函数）。

    为避免 game -> scenes 反向依赖，注册函数由 scenes.game21 主动调用。
    本函数保留作为测试钩子；若 scenes.game21 尚未导入（如纯逻辑测试），
    视为「未注册任何效果执行器」，调用方应保证不依赖该执行器存在。
    """
    try:
        from ..scenes import game21  # noqa: F401
    except Exception:
        pass


def _reset_registry_for_tests() -> None:
    """测试钩子：清理所有「测试效果_」前缀的临时执行器。"""
    for k in [k for k in EFFECT_REGISTRY if k.startswith("测试效果_")]:
        del EFFECT_REGISTRY[k]
