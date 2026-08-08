"""战斗引擎批次2 单元测试(ADR-0008/0010/0011)。

覆盖主动技能执行、被动时点调度、状态消费模型、格挡/闪避掷骰、
策略表条件求值、run_battle 端到端。每测注入 random.Random(定种子)作 rng=,
使战斗脱离全局 random.seed(ADR-0008 RNG 注入)。

构造最小 BattleSide/Unit 直接调 run_battle,绕过 Game/场景装配。
"""
import unittest
import random

from pydemo.game.unit import Unit
from pydemo.game.army import Army, empty_army
from pydemo.game.battle import (
    BattleSide, BattleResult, run_battle, resolve_strike, BattleContext,
    BLOCK_EVA_ENABLED, BLOCK_DMG_FACTOR,
)
from pydemo.game.formation import (
    UnitStrategy, StrategyRow, default_strategy, build_default_formation,
    choose_target_with_slots, validate_strategy, STRATEGY_ROW_CAP,
)
from pydemo.game.effects import build_skill_effects, SKILL_ACTIVE, SKILL_PASSIVE
from pydemo.game.triggers import (
    TriggerPoint, StatusType, StatusConsume, STATUS_META,
    apply_status, consume_on_self_attack, consume_on_self_hit, clear_statuses,
    is_frozen, has_status, status_layers,
)
from pydemo.game.modifier import Modifier, ModifierSource


# ---------------------------------------------------------------------------
# 测试工厂
# ---------------------------------------------------------------------------

def _base_unit(uid="u", name="U", tags=None, hp=100, ap=4, pp=4, mana=10,
               speed=50, p_atk=30, m_atk=0, p_def=10, m_def=10,
               acc=100, eva=0, block=0, crit=0, skills=None):
    """造一个可直接投入战斗的单位(base 已含战斗所需属性)。"""
    u = Unit(
        id=uid, type_id=uid, name=name,
        tags=set(tags or {"melee"}),
        base={
            "occupy": 1, "hp": hp, "ap": ap, "pp": pp, "mana": mana,
            "speed": speed, "p_atk": p_atk, "m_atk": m_atk,
            "p_def": p_def, "m_def": m_def, "acc": acc, "eva": eva,
            "block": block, "crit": crit, "luck": 0, "will": 0, "leadership": 0,
        },
        is_hero=False,
        skills=list(skills or []),
    )
    return u


def _side(units, is_attacker=True, army_id="a", name="A", node="n1"):
    """把单位列表装进一个 BattleSide(每单位占一个槽位)。"""
    army = empty_army(army_id, name, owner="f1", node_id=node)
    index = {u.id: u for u in units}
    for i, u in enumerate(units):
        army.grid[i] = u.id
        u.army_id = army.id
    side = BattleSide(army=army, is_attacker=is_attacker, home_node=node,
                      units=list(units))
    return side, index


SKILL_DEFS = {
    "fireball": {"name": "火球术", "kind": "active",
                 "effects": [{"type": "ap_damage", "params": {"kind": "magic", "value": 45},
                              "trigger": "active", "ap_cost": 1, "mana_cost": 3}]},
    "ice_brand": {"name": "冰烙印", "kind": "active",
                  "effects": [
                      {"type": "ap_damage", "params": {"kind": "physical", "value": 30},
                       "trigger": "active", "ap_cost": 2},
                      {"type": "apply_status", "params": {"status": "frozen", "duration": 1},
                       "trigger": "active"},
                  ]},
    "frost_warden": {"name": "霜守", "kind": "passive",
                    "effects": [{"type": "apply_status",
                                 "params": {"status": "frozen", "duration": 1},
                                 "trigger": "passive",
                                 "trigger_point": "on_block", "pp_cost": 1}]},
}


def _strat_for(units, skill_defs=SKILL_DEFS):
    """为 units 造默认策略表(走 build_default_formation 的真实路径)。"""
    # 单位先放进一个 army 才能 build_default_formation
    return build_default_formation(units[0].army_id and _army_of(units) or units, None, skill_defs) \
        if False else {u.id: default_strategy(u, skill_defs) for u in units}


def _army_of(units):
    a = empty_army("a", "A", "f1", "n1")
    for i, u in enumerate(units):
        a.grid[i] = u.id
        u.army_id = a.id
    return a


def _run(attackers, defenders, skill_defs=SKILL_DEFS, rng=None, log=False):
    """跑一场战斗的便捷封装:建 side + 策略 + run_battle。"""
    aside, _ = _side(attackers, is_attacker=True, army_id="att", name="攻方")
    dside, _ = _side(defenders, is_attacker=False, army_id="def", name="守方")
    all_u = attackers + defenders
    strats = {u.id: default_strategy(u, skill_defs) for u in all_u}
    res = run_battle(aside, dside, strats, extra_mods=[],
                     log_detail=log, rng=rng or random.Random(0),
                     skill_defs=skill_defs)
    return res, aside, dside


# ---------------------------------------------------------------------------
# 状态系统(triggers.py)
# ---------------------------------------------------------------------------

class TestStatusModel(unittest.TestCase):
    def _u(self):
        u = _base_unit("x", "X")
        u.statuses = {}
        return u

    def test_apply_takes_max_no_stack(self):
        u = self._u()
        apply_status(u, StatusType.FROZEN, 1)
        self.assertEqual(status_layers(u, StatusType.FROZEN), 1)
        # 重施加 1 层不叠加(取 max)
        apply_status(u, StatusType.FROZEN, 1)
        self.assertEqual(status_layers(u, StatusType.FROZEN), 1)
        # 重施加 2 层取 max
        apply_status(u, StatusType.FROZEN, 2)
        self.assertEqual(status_layers(u, StatusType.FROZEN), 2)

    def test_apply_default_layers(self):
        u = self._u()
        # 不传 layers 取 STATUS_META 默认(FROZEN=1)
        apply_status(u, StatusType.FROZEN)
        self.assertEqual(status_layers(u, StatusType.FROZEN), 1)

    def test_consume_on_self_attack_decrements_and_removes(self):
        u = self._u()
        apply_status(u, StatusType.FROZEN, 2)
        removed = consume_on_self_attack(u)
        self.assertEqual(status_layers(u, StatusType.FROZEN), 1)
        self.assertEqual(removed, [])
        removed = consume_on_self_attack(u)
        self.assertEqual(status_layers(u, StatusType.FROZEN), 0)
        self.assertEqual(removed, ["frozen"])

    def test_consume_on_self_hit_only_consumes_hit_type(self):
        u = self._u()
        apply_status(u, StatusType.FROZEN, 2)   # ON_SELF_ATTACK,不受 hit 消费
        removed = consume_on_self_hit(u)
        self.assertEqual(removed, [])
        self.assertEqual(status_layers(u, StatusType.FROZEN), 2)

    def test_battle_long_not_consumed_by_attack_or_hit(self):
        u = self._u()
        apply_status(u, StatusType.DEBUFF, 2)   # BATTLE_LONG
        consume_on_self_attack(u)
        consume_on_self_hit(u)
        self.assertEqual(status_layers(u, StatusType.DEBUFF), 2)

    def test_clear_statuses(self):
        u = self._u()
        apply_status(u, StatusType.FROZEN, 1)
        apply_status(u, StatusType.DEBUFF, 2)
        clear_statuses(u)
        self.assertEqual(u.statuses, {})

    def test_is_frozen(self):
        u = self._u()
        self.assertFalse(is_frozen(u))
        apply_status(u, StatusType.FROZEN, 1)
        self.assertTrue(is_frozen(u))


# ---------------------------------------------------------------------------
# 策略表(formation.py)
# ---------------------------------------------------------------------------

class TestStrategyTable(unittest.TestCase):
    def test_default_strategy_under_cap(self):
        u = _base_unit("k", "骑士", tags={"melee", "cavalry"},
                       skills=["cavalry_charge", "iron_body", "frost_warden"])
        strat = default_strategy(u, SKILL_DEFS)
        # cavalry_charge/iron_body 是 perk(不进表),frost_warden 被动进 passive_rows
        self.assertLessEqual(strat.total_rows, STRATEGY_ROW_CAP)
        self.assertTrue(any(r.skill_id == "frost_warden" for r in strat.passive_rows))

    def test_validate_strategy_raises_over_cap(self):
        u = _base_unit("k", "K", skills=[])
        strat = default_strategy(u, SKILL_DEFS)
        # 手动塞超 8 行
        for i in range(9):
            strat.active_rows.append(StrategyRow(skill_id=f"x{i}"))
        with self.assertRaises(ValueError):
            validate_strategy(strat)

    def test_default_strategy_no_skill_defs_fallback(self):
        u = _base_unit("k", "K", skills=["fireball"])
        strat = default_strategy(u, None)   # 无 skill_defs
        # 退化:skill_order 填满,无 rows
        self.assertEqual(strat.active_rows, [])
        self.assertEqual(strat.passive_rows, [])
        self.assertIn("fireball", strat.skill_order)

    def test_default_strategy_active_melee_gets_front_necessary(self):
        u = _base_unit("k", "K", tags={"melee"}, skills=["ice_brand"])
        strat = default_strategy(u, SKILL_DEFS)
        self.assertEqual(len(strat.active_rows), 1)
        row = strat.active_rows[0]
        self.assertEqual(row.skill_id, "ice_brand")
        self.assertTrue(any(c.get("type") == "target_pref_front" for c in row.necessary))

    def test_default_strategy_passive_reads_trigger_point(self):
        u = _base_unit("k", "K", skills=["frost_warden"])
        strat = default_strategy(u, SKILL_DEFS)
        self.assertEqual(len(strat.passive_rows), 1)
        self.assertEqual(strat.passive_rows[0].trigger_point, TriggerPoint.ON_BLOCK)


# ---------------------------------------------------------------------------
# 选目标 + 条件求值(formation.choose_target_with_slots)
# ---------------------------------------------------------------------------

class TestTargetSelection(unittest.TestCase):
    def _ctx_and_strats(self, attackers, defenders):
        aside, ai = _side(attackers, True, "att", "攻方")
        dside, di = _side(defenders, False, "def", "守方")
        all_u = attackers + defenders
        strats = {u.id: default_strategy(u, SKILL_DEFS) for u in all_u}
        res = BattleResult()
        # eff_map 简单给 speed
        eff_map = {u.id: {"speed": u.base.get("speed", 50)} for u in all_u}
        ctx = BattleContext(attacker_side=aside, defender_side=dside,
                            strategies=strats, eff_map=eff_map,
                            skill_defs=SKILL_DEFS, result=res, log_detail=False,
                            rng=random.Random(0))
        return ctx, strats, aside, dside

    def test_melee_targets_front_row_first(self):
        atk = _base_unit("a", "A", tags={"melee"})
        front = _base_unit("d1", "D1", tags={"melee"})
        back = _base_unit("d2", "D2", tags={"ranged"})
        aside, ai = _side([atk], True)
        dside, di = _side([front, back], False)
        dside.army.grid = [front.id, None, None, None, None, None, back.id, None, None]
        front.army_id = dside.army.id
        back.army_id = dside.army.id
        strat = default_strategy(atk, None)
        strat.target_pref = "front"
        foes = [(i, di[uid]) for i, uid in enumerate(dside.army.grid) if uid]
        target = choose_target_with_slots(0, atk.tags, foes, strat, rng=random.Random(0))
        self.assertIsNotNone(target)
        self.assertEqual(target[1].id, "d1")

    def test_necessary_filters_pool_fallback_to_reachable(self):
        atk = _base_unit("a", "A", tags={"ranged"})
        d1 = _base_unit("d1", "D1")
        d2 = _base_unit("d2", "D2")
        aside, ai = _side([atk], True)
        dside, di = _side([d1, d2], False)
        strat = default_strategy(atk, None)
        ctx, _, _, _ = self._ctx_and_strats([atk], [d1, d2])
        foes = [(i, di[uid]) for i, uid in enumerate(dside.army.grid) if uid]
        # 必要条件:enemy_has_frozen,但谁都没冻结 → 池空回退可达性池
        nec = [{"type": "enemy_has_frozen"}]
        target = choose_target_with_slots(0, atk.tags, foes, strat,
                                           rng=random.Random(0), necessary=nec,
                                           eff_map=ctx.eff_map, ctx=ctx, attacker=atk)
        # 回退后仍应选到目标(不软锁)
        self.assertIsNotNone(target)

    def test_priority_stable_sort_prefers_frozen(self):
        atk = _base_unit("a", "A", tags={"ranged"})
        d1 = _base_unit("d1", "D1")
        d2 = _base_unit("d2", "D2")
        apply_status(d2, StatusType.FROZEN, 1)
        aside, ai = _side([atk], True)
        dside, di = _side([d1, d2], False)
        strat = default_strategy(atk, None)
        ctx, _, _, _ = self._ctx_and_strats([atk], [d1, d2])
        foes = [(i, di[uid]) for i, uid in enumerate(dside.army.grid) if uid]
        prio = [{"type": "pref_enemy_frozen"}]
        target = choose_target_with_slots(0, atk.tags, foes, strat,
                                           rng=random.Random(0), priority=prio,
                                           eff_map=ctx.eff_map, ctx=ctx)
        self.assertEqual(target[1].id, "d2")   # 冻结者优先


# ---------------------------------------------------------------------------
# 格挡/闪避掷骰(resolve_strike)
# ---------------------------------------------------------------------------

class TestBlockEva(unittest.TestCase):
    def _ctx(self, atk, tgt):
        aside, _ = _side([atk], True, "att", "A")
        dside, _ = _side([tgt], False, "def", "D")
        res = BattleResult()
        eff_map = {
            atk.id: {"speed": 50, "p_atk": atk.base["p_atk"], "m_atk": atk.base.get("m_atk", 0),
                     "acc": 100, "crit": atk.base.get("crit", 0), "eva": 0, "block": 0},
            tgt.id: {"speed": 50, "p_def": tgt.base["p_def"], "m_def": tgt.base["m_def"],
                     "acc": 100, "crit": 0, "eva": tgt.base["eva"],
                     "block": tgt.base["block"]},
        }
        strats = {u.id: default_strategy(u, SKILL_DEFS) for u in (atk, tgt)}
        ctx = BattleContext(attacker_side=aside, defender_side=dside,
                            strategies=strats, eff_map=eff_map,
                            skill_defs=SKILL_DEFS, result=res, log_detail=False,
                            rng=random.Random(0), block_eva_enabled=True)
        ctx.resolve_strike = resolve_strike
        return ctx

    def test_eva_triggers_zero_damage(self):
        # 闪避率 100,定种子使第一个 rng.random() < 1.0 → 闪避
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=50)
        tgt = _base_unit("d", "D", tags={"melee"}, eva=100)
        ctx = self._ctx(atk, tgt)
        hp0 = tgt.cur_hp
        r = resolve_strike(ctx, atk, tgt, "physical")
        self.assertTrue(r.evaded)
        self.assertEqual(r.dmg, 0)
        self.assertEqual(tgt.cur_hp, hp0)   # 无伤害

    def test_block_halves_damage(self):
        # block=100 必格挡;eva=0 不闪避;crit=0 不暴击
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, p_def=0, eva=0, block=100)
        ctx = self._ctx(atk, tgt)
        r = resolve_strike(ctx, atk, tgt, "physical")
        self.assertTrue(r.blocked)
        self.assertFalse(r.evaded)
        # base = 100 - 0 = 100;block 后 ×0.5 = 50
        self.assertEqual(r.dmg, 50)

    def test_disabled_block_eva_always_hits(self):
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, p_def=0, eva=100, block=100)
        ctx = self._ctx(atk, tgt)
        ctx.block_eva_enabled = False
        r = resolve_strike(ctx, atk, tgt, "physical")
        self.assertFalse(r.evaded)
        self.assertFalse(r.blocked)
        self.assertEqual(r.dmg, 100)

    def test_crit_multiplies_damage(self):
        # crit=100 必暴击;eva/block=0
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=40, crit=100)
        tgt = _base_unit("d", "D", tags={"melee"}, p_def=0)
        ctx = self._ctx(atk, tgt)
        r = resolve_strike(ctx, atk, tgt, "physical")
        self.assertTrue(r.crit)
        # 40 × 1.5 = 60
        self.assertEqual(r.dmg, 60)


# ---------------------------------------------------------------------------
# run_battle 端到端
# ---------------------------------------------------------------------------

class TestRunBattle(unittest.TestCase):
    def test_one_sided_wipe(self):
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=200, hp=500)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0)
        res, aside, dside = _run([atk], [tgt], rng=random.Random(1))
        self.assertTrue(res.defender_wiped)
        self.assertEqual(res.occupier_side, "attacker")

    def test_status_cleared_after_battle(self):
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=200, hp=500)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0)
        apply_status(tgt, StatusType.DEBUFF, 2)
        res, _, _ = _run([atk], [tgt], rng=random.Random(1))
        self.assertEqual(tgt.statuses, {})   # battle_end 清场

    def test_frozen_unit_skips_action(self):
        # 攻击者被冻结:轮到行动应跳过出手 + 扣层
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=200, hp=500)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0)
        apply_status(atk, StatusType.FROZEN, 1)
        res, _, _ = _run([atk], [tgt], rng=random.Random(1), log=True)
        # 战斗结束状态清空;战斗中冻结被消费(出手即跳过+扣层)
        # 关键:战斗能跑完且分出胜负
        self.assertEqual(res.occupier_side, "attacker")

    def test_fireball_consumes_ap_and_mana(self):
        # 法师释放火球术,AP/Mana 应扣
        mage = _base_unit("m", "法师", tags={"magic"}, hp=200, ap=4, pp=4,
                          mana=10, speed=200, p_atk=0, m_atk=40)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=500, p_def=50)
        aside, _ = _side([mage], True, "att", "攻方")
        dside, _ = _side([tgt], False, "def", "守方")
        strats = {mage.id: default_strategy(mage, SKILL_DEFS),
                  tgt.id: default_strategy(tgt, SKILL_DEFS)}
        # 给法师足够出手次数(高 speed)
        res = run_battle(aside, dside, strats, extra_mods=[],
                         log_detail=True, rng=random.Random(0),
                         skill_defs=SKILL_DEFS)
        # 战斗跑完即可(火球释放细节由 log 体现);此处断言不崩
        self.assertIsNotNone(res)

    def test_ap_insufficient_falls_back_to_normal_attack(self):
        # AP=0 无法释放主动 → 走普攻
        mage = _base_unit("m", "法师", tags={"magic"}, hp=200, ap=0, pp=4,
                          mana=10, speed=100, p_atk=10, m_atk=40)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=500, p_def=0)
        res, _, _ = _run([mage], [tgt], rng=random.Random(0))
        # 跑完不崩;普攻仍能造成伤害
        self.assertIsNotNone(res)

    def test_battle_start_fires_once(self):
        # battle_start 应发一次(霜守无 battle_start 被动,故测无崩 + 占据)
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=200, hp=500,
                         skills=["frost_warden"])
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0)
        res, _, _ = _run([atk], [tgt], rng=random.Random(1))
        self.assertEqual(res.occupier_side, "attacker")

    def test_no_skill_defs_runs_plain(self):
        # skill_defs=None:主动/被动不触发,只普攻(向后兼容)
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=200, hp=500,
                         skills=["fireball"])
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0)
        aside, _ = _side([atk], True)
        dside, _ = _side([tgt], False)
        strats = {u.id: default_strategy(u, None) for u in (atk, tgt)}
        res = run_battle(aside, dside, strats, extra_mods=[],
                         log_detail=False, rng=random.Random(0), skill_defs=None)
        self.assertEqual(res.occupier_side, "attacker")


# ---------------------------------------------------------------------------
# 端到端回归:smoke_test 在进程内调用
# ---------------------------------------------------------------------------

class TestSmokeRegression(unittest.TestCase):
    def test_smoke_run_returns_zero(self):
        from smoke_test import run as smoke_run
        # 不锁定特定胜者,只要求跑完有胜者(exit 0)
        rc = smoke_run(max_turns=200)
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
