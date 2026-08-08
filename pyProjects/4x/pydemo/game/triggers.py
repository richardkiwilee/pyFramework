"""战斗触发时点、状态、策略条件枚举(ADR-0010/0011)。

批次2 的枚举唯一来源。批次1 在 ADR 中写了值集合但未落代码常量,本模块补齐:
  - TriggerPoint:被动触发时点(10 个,固定集可扩展,ADR-0011)
  - StatusType / StatusConsume:单位状态类型与消费方式(ADR-0010)
  - ConditionType:策略表条件(必要/优先两型,ADR-0011)
  - STATUS_META:状态默认层数与消费方式

状态采用「消费模型」(无 tick 计时):状态按消费方式耗层,层数归 0 即解除,
battle_end 清场(状态不跨场,与 HP 跨场不同)。详见 ADR-0010 与批次2 计划。
条件编码为结构化 dict(如 {"type":"self_hp_le","threshold":50}),不写字符串 DSL。
"""
from __future__ import annotations
from enum import Enum
from typing import Any


class TriggerPoint(str, Enum):
    """被动触发时点(ADR-0011,固定集可扩展)。"""
    BATTLE_START = "battle_start"             # 战斗开始一次性
    BATTLE_END = "battle_end"                 # 战斗结束一次性
    SELF_ATTACK_START = "self_attack_start"   # 攻击者出手前
    SELF_ATTACK_END = "self_attack_end"       # 攻击者出手后
    ALLY_ATTACKED_START = "ally_attacked_start"  # 被攻击方响应前(被攻击单位同侧)
    ALLY_ATTACKED_END = "ally_attacked_end"      # 被攻击方响应后
    ON_BLOCK = "on_block"                      # 格挡成功时
    ON_EVA = "on_eva"                          # 闪避成功时
    AFTER_PHYS = "after_phys"                  # 受物理攻击后
    AFTER_MAGIC = "after_magic"                # 受魔法攻击后


TRIGGER_POINTS = tuple(TriggerPoint)   # 用于校验


class StatusType(str, Enum):
    """单位状态类型(ADR-0010,可随技能需要扩展)。"""
    FROZEN = "frozen"   # 冰封:轮到自身行动时跳过出手并消耗 1 层;受击也消耗 1 层
    DEBUFF = "debuff"   # 减益:分类标签,供「优先处于减益状态的敌方」匹配


STATUS_CN = {StatusType.FROZEN: "冰封", StatusType.DEBUFF: "减益"}


class StatusConsume(str, Enum):
    """状态消费方式(无 tick 计时,按消费耗层)。

    - BATTLE_LONG:整场持续到 battle_end 清除,不消耗层数
    - ON_SELF_ATTACK:轮到该单位行动、执行一次攻击后层数 −1(冻结采用此)
    - ON_SELF_HIT:该单位被攻击命中后层数 −1
    """
    BATTLE_LONG = "battle_long"
    ON_SELF_ATTACK = "on_self_attack"
    ON_SELF_HIT = "on_self_hit"


# 状态元数据:type -> (默认层数, 消费方式)
STATUS_META: dict[StatusType, tuple[int, StatusConsume]] = {
    StatusType.FROZEN: (1, StatusConsume.ON_SELF_ATTACK),
    StatusType.DEBUFF: (2, StatusConsume.BATTLE_LONG),
}


class ConditionType(str, Enum):
    """策略表条件类型(ADR-0011)。必要=全满足才释放并筛合法目标;优先=满足则偏好目标。"""
    # 必要(全满足才允许释放并筛选目标)
    SELF_HP_LE = "self_hp_le"                 # 自身 HP ≤ threshold%
    ALLY_AVG_HP_LE = "ally_avg_hp_le"        # 同侧平均 HP ≤ threshold%
    ROW_COUNT_GE = "row_count_ge"            # 某排存活单位数 ≥ n
    ENEMY_HAS_FROZEN = "enemy_has_frozen"     # 仅筛处于冻结状态的目标
    TARGET_PREF_LOW_HP = "target_pref_low_hp"  # 必要版:筛存活目标(按 low_hp 语义,作为合法性筛选)
    TARGET_PREF_FRONT = "target_pref_front"    # 必要版:筛前排目标
    TARGET_PREF_RANDOM = "target_pref_random"  # 必要版:合法(占位,等同不筛)
    # 优先(满足则偏好该目标,不影响是否释放)
    PREF_ENEMY_FROZEN = "pref_enemy_frozen"
    PREF_ENEMY_DEBUFFED = "pref_enemy_debuffed"
    PREF_LOW_HP = "pref_low_hp"
    PREF_FRONT = "pref_front"
    PREF_RANDOM = "pref_random"


class ConditionKind(str, Enum):
    NECESSARY = "necessary"   # 硬筛
    PRIORITY = "priority"     # 软排


# 必要条件集合(用于判断一条 condition 走筛还是排)
NECESSARY_TYPES = {
    ConditionType.SELF_HP_LE, ConditionType.ALLY_AVG_HP_LE, ConditionType.ROW_COUNT_GE,
    ConditionType.ENEMY_HAS_FROZEN,
    ConditionType.TARGET_PREF_LOW_HP, ConditionType.TARGET_PREF_FRONT, ConditionType.TARGET_PREF_RANDOM,
}
PRIORITY_TYPES = {
    ConditionType.PREF_ENEMY_FROZEN, ConditionType.PREF_ENEMY_DEBUFFED,
    ConditionType.PREF_LOW_HP, ConditionType.PREF_FRONT, ConditionType.PREF_RANDOM,
}


def is_necessary(cond: dict) -> bool:
    """该条件是否为必要型(走筛)。"""
    return cond.get("type") in {t.value for t in NECESSARY_TYPES}


def is_priority(cond: dict) -> bool:
    """该条件是否为优先型(走排)。"""
    return cond.get("type") in {t.value for t in PRIORITY_TYPES}


# ---------------------------------------------------------------------------
# 状态读写(无 tick 计时,消费模型)
# ---------------------------------------------------------------------------

def status_layers(u: Any, status: StatusType | str) -> int:
    """单位当前某状态的剩余层数(0 = 无)。"""
    key = status.value if isinstance(status, StatusType) else status
    return int(u.statuses.get(key, 0))


def has_status(u: Any, status: StatusType | str) -> bool:
    return status_layers(u, status) > 0


def apply_status(u: Any, status: StatusType | str, layers: int | None = None) -> str:
    """施加状态:重施加取 max(当前, 新层),不叠加(ADR-0010 消费模型)。

    layers 缺省取 STATUS_META 的默认层数。返回施加的状态名。
    """
    st = status if isinstance(status, StatusType) else StatusType(status)
    if layers is None:
        layers = STATUS_META.get(st, (1, StatusConsume.BATTLE_LONG))[0]
    key = st.value
    cur = int(u.statuses.get(key, 0))
    u.statuses[key] = max(cur, int(layers))
    return key


def consume_on_self_attack(u: Any) -> list[str]:
    """轮到该单位行动出手后:消费方式 == ON_SELF_ATTACK 的状态层 −1,归 0 移除。
    返回本次被消费/移除的状态名列表(供日志)。
    """
    removed: list[str] = []
    for st, (default, consume) in STATUS_META.items():
        if consume != StatusConsume.ON_SELF_ATTACK:
            continue
        key = st.value
        if key not in u.statuses or u.statuses[key] <= 0:
            continue
        u.statuses[key] -= 1
        if u.statuses[key] <= 0:
            u.statuses.pop(key, None)
            removed.append(key)
    return removed


def consume_on_self_hit(u: Any) -> list[str]:
    """该单位被攻击命中后:消费方式 == ON_SELF_HIT 的状态层 −1,归 0 移除。"""
    removed: list[str] = []
    for st, (default, consume) in STATUS_META.items():
        if consume != StatusConsume.ON_SELF_HIT:
            continue
        key = st.value
        if key not in u.statuses or u.statuses[key] <= 0:
            continue
        u.statuses[key] -= 1
        if u.statuses[key] <= 0:
            u.statuses.pop(key, None)
            removed.append(key)
    return removed


def clear_statuses(u: Any) -> None:
    """battle_end 清场:状态不跨场(与 HP 跨场不同,ADR-0010)。"""
    u.statuses.clear()


def is_frozen(u: Any) -> bool:
    """单位是否处于冻结(轮到自身行动时跳过出手)。"""
    return has_status(u, StatusType.FROZEN)


# ---------------------------------------------------------------------------
# 条件求值
# ---------------------------------------------------------------------------

def _pct_cur_hp(u: Any) -> float:
    """单位当前 HP 占有效上限百分比(0..100)。无上限信息时按当前血量>0 处理。"""
    eff_max = u.base.get("hp", 1) or 1
    return 100.0 * float(u.cur_hp) / float(eff_max)


def eval_necessary(cond: dict, ctx: Any, actor: Any | None,
                   target: Any | None = None, eff_map: dict | None = None) -> bool:
    """必要条件求值(全满足才允许释放并筛选目标)。

    部分 necessary 条件作用于「是否释放」(self_hp_le/ally_avg_hp_le/row_count_ge,
    不需 target,在 _can_fire_active / dispatch 中 gate 释放);部分作用于「目标合法性」
    (target_pref_*/enemy_has_frozen,需 target,在 choose_target_with_slots 中过滤)。
    两者在此统一求值,由调用方决定传不传 target。
    """
    t = cond.get("type")
    if t == ConditionType.SELF_HP_LE.value:
        return _pct_cur_hp(actor) <= float(cond.get("threshold", 0))
    if t == ConditionType.ALLY_AVG_HP_LE.value:
        allies = _side_allies_of(ctx, actor)
        if not allies:
            return True   # 无同侧单位视为满足(避免空集卡死)
        avg = sum(_pct_cur_hp(a) for a in allies) / len(allies)
        return avg <= float(cond.get("threshold", 0))
    if t == ConditionType.ROW_COUNT_GE.value:
        row = cond.get("row", "front")
        n = int(cond.get("n", 0))
        return _row_alive_count(ctx, actor, row) >= n
    if t == ConditionType.ENEMY_HAS_FROZEN.value:
        # 作用于目标合法性:目标需处于冻结
        if target is None:
            return True   # 无目标上下文时不卡释放(由 choose_target 过滤)
        return has_status(target, StatusType.FROZEN)
    if t == ConditionType.TARGET_PREF_LOW_HP.value:
        # 必要版筛存活目标:不筛血量(避免与 low_hp 优先版语义混淆),仅作「合法」占位
        return target is None or target.alive
    if t == ConditionType.TARGET_PREF_FRONT.value:
        # 必要版:目标须在前排(需 slot 上下文;无 slot 时不卡)
        slot = cond.get("_target_slot") if cond else None
        if slot is None or target is None:
            return True
        from .army import row_of
        return row_of(slot) == "front"
    if t == ConditionType.TARGET_PREF_RANDOM.value:
        return True   # 随机=不筛
    return False   # 未知条件不满足(保守)


def priority_key(cond: dict, ctx: Any, target: Any, target_slot: int | None = None) -> tuple:
    """优先条件求值:返回排序键(越小越优先)。多个优先条件由调用方组合(稳定排序)。"""
    t = cond.get("type")
    if t == ConditionType.PREF_ENEMY_FROZEN.value:
        return (0 if has_status(target, StatusType.FROZEN) else 1)
    if t == ConditionType.PREF_ENEMY_DEBUFFED.value:
        return (0 if has_status(target, StatusType.DEBUFF) else 1)
    if t == ConditionType.PREF_LOW_HP.value:
        return (float(target.cur_hp),)
    if t == ConditionType.PREF_FRONT.value:
        if target_slot is None:
            return (1,)
        from .army import row_of
        return (0 if row_of(target_slot) == "front" else 1, 0)
    if t == ConditionType.PREF_RANDOM.value:
        return (0,)   # 随机=不影响排序,由调用方在末尾加随机扰动
    return (1,)


# ---------------------------------------------------------------------------
# 辅助:从 ctx 取同侧单位 / 某排存活数
# ---------------------------------------------------------------------------

def _unit_side(ctx: Any, u: Any) -> Any:
    """返回 u 所在的 BattleSide。"""
    if u in ctx.attacker_side.units:
        return ctx.attacker_side
    return ctx.defender_side


def _side_allies_of(ctx: Any, u: Any) -> list[Any]:
    """u 同侧存活单位(含 u 自身,用于 ally_avg_hp_le)。"""
    side = _unit_side(ctx, u)
    return [x for x in side.units if x.alive]


def _row_alive_count(ctx: Any, u: Any, row: str) -> int:
    """u 同侧某排存活单位数。"""
    side = _unit_side(ctx, u)
    from .army import row_of
    count = 0
    for i, uid in enumerate(side.army.grid):
        if uid is None:
            continue
        if row_of(i) != row:
            continue
        x = next((v for v in side.units if v.id == uid), None)
        if x and x.alive:
            count += 1
    return count
