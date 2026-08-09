"""B3 意志生还单元测试。

覆盖:
- 命中(will% rng<阈值)→ 单位 HP 保留 1(不死)。
- 每单位每场最多 1 次(第二次致死真死)。
- 非玩家单位不触发(player_faction_id 不匹配)。
- HP==1 时不触发(必须 >1)。
- HP>1 但伤害不致死时不触发(new_hp>0)。
- will=0 时不触发。
- 全局开关 WILL_SURVIVAL_ENABLED=False 时不触发。
"""
import unittest
import random

from pydemo.game import battle as battle_mod
from pydemo.game.unit import Unit
from pydemo.game.army import empty_army
from pydemo.game.battle import (
    BattleSide, BattleResult, run_battle, resolve_strike, BattleContext,
)
from pydemo.game.formation import default_strategy
from pydemo.game import unit as unit_mod


def _base_unit(uid="u", name="U", tags=None, hp=100, ap=4, pp=4, mana=0,
               speed=50, p_atk=30, m_atk=0, p_def=0, m_def=0,
               acc=100, eva=0, block=0, crit=0, will=0, owner="f1"):
    u = Unit(
        id=uid, type_id=uid, name=name,
        tags=set(tags or {"melee"}),
        base={
            "occupy": 1, "hp": hp, "ap": ap, "pp": pp, "mana": mana,
            "speed": speed, "p_atk": p_atk, "m_atk": m_atk,
            "p_def": p_def, "m_def": m_def, "acc": acc, "eva": eva,
            "block": block, "crit": crit, "luck": 0, "will": will,
            "leadership": 0,
        },
        is_hero=False,
        skills=[],
    )
    return u


def _side(units, is_attacker=True, army_id="a", name="A", node="n1", owner="f1"):
    army = empty_army(army_id, name, owner=owner, node_id=node)
    for i, u in enumerate(units):
        army.grid[i] = u.id
        u.army_id = army.id
    side = BattleSide(army=army, is_attacker=is_attacker, home_node=node,
                     units=list(units))
    return side


def _ctx(atk, tgt, rng=None, player_faction_id="f1", block_eva=False):
    """造一个 BattleContext,直接调 resolve_strike 测意志生还。
    block_eva 关掉使命中恒成立(避免闪避干扰)。eff_map 的 will 取自单位 base.will。
    """
    aside = _side([atk], True, "att", "A", owner="f1")
    dside = _side([tgt], False, "def", "D", owner="f2")
    res = BattleResult()
    eff_map = {
        atk.id: {"speed": 50, "p_atk": atk.base["p_atk"], "m_atk": atk.base.get("m_atk", 0),
                 "acc": 100, "crit": atk.base.get("crit", 0), "eva": 0, "block": 0,
                 "will": atk.base.get("will", 0)},
        tgt.id: {"speed": 50, "p_def": tgt.base["p_def"], "m_def": tgt.base["m_def"],
                 "acc": 100, "crit": 0, "eva": 0, "block": 0,
                 "will": tgt.base.get("will", 0)},
    }
    strats = {u.id: default_strategy(u, {}) for u in (atk, tgt)}
    ctx = BattleContext(attacker_side=aside, defender_side=dside,
                        strategies=strats, eff_map=eff_map,
                        skill_defs={}, result=res, log_detail=False,
                        rng=rng or random.Random(0), block_eva_enabled=block_eva,
                        player_faction_id=player_faction_id)
    ctx.resolve_strike = resolve_strike
    return ctx


class TestWillSurvival(unittest.TestCase):
    def test_will_survives_keeps_1_hp(self):
        # 守方 HP=10,will=100(必触发),受致死伤害 → 保留 1 HP
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0, will=100)
        # player_faction_id=f1 守方属 f2 → 不触发;需守方属玩家方
        # 让守方属 f1(玩家方)
        ctx = _ctx(atk, tgt, rng=random.Random(0), player_faction_id="f1")
        # 守方 army owner 是 f2,改 dside owner 为 f1
        ctx.defender_side.army.owner = "f1"
        r = resolve_strike(ctx, atk, tgt, "physical")
        # dmg=100-0=100 > 10 → 致死;will=100 rng<1.0 必触发 → 保留 1 HP
        self.assertEqual(tgt.cur_hp, 1, f"应保留 1 HP,实际 {tgt.cur_hp}")
        self.assertIn(tgt.id, ctx.survived_this_battle)
        self.assertTrue(any("意志生还" in m for m in ctx.result.log))

    def test_will_once_per_battle(self):
        # 第一次致死生还(保留 1 HP);第二次致死真死(HD 已 1,但 new_hp<=0 触发条件 cur_hp>1 不满足)
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0, will=100)
        ctx = _ctx(atk, tgt, rng=random.Random(0), player_faction_id="f1")
        ctx.defender_side.army.owner = "f1"
        resolve_strike(ctx, atk, tgt, "physical")
        self.assertEqual(tgt.cur_hp, 1)
        # 第二次:cur_hp=1,条件 cur_hp>1 不满足 → 不触发,正常扣血致死
        resolve_strike(ctx, atk, tgt, "physical")
        self.assertLessEqual(tgt.cur_hp, 0)

    def test_non_player_unit_no_trigger(self):
        # 守方属非玩家方 f2,player_faction_id=f1 → 不触发
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0, will=100)
        ctx = _ctx(atk, tgt, rng=random.Random(0), player_faction_id="f1")
        # 守方 owner 保持 f2(非玩家)
        resolve_strike(ctx, atk, tgt, "physical")
        self.assertLessEqual(tgt.cur_hp, 0, "非玩家单位应正常死亡")
        self.assertEqual(len(ctx.survived_this_battle), 0)

    def test_hp_eq_1_no_trigger(self):
        # 守方 HP=1(不 >1)→ 不触发
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=1, p_def=0, will=100)
        ctx = _ctx(atk, tgt, rng=random.Random(0), player_faction_id="f1")
        ctx.defender_side.army.owner = "f1"
        resolve_strike(ctx, atk, tgt, "physical")
        self.assertLessEqual(tgt.cur_hp, 0)
        self.assertEqual(len(ctx.survived_this_battle), 0)

    def test_non_lethal_no_trigger(self):
        # 伤害不致死(new_hp>0)→ 不触发
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=5)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0, will=100)
        ctx = _ctx(atk, tgt, rng=random.Random(0), player_faction_id="f1")
        ctx.defender_side.army.owner = "f1"
        r = resolve_strike(ctx, atk, tgt, "physical")
        # dmg=5-0=5 → new_hp=5>0 不致死
        self.assertEqual(tgt.cur_hp, 5)
        self.assertEqual(len(ctx.survived_this_battle), 0)

    def test_will_zero_no_trigger(self):
        # will=0 → 概率 0 不触发
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0, will=0)
        ctx = _ctx(atk, tgt, rng=random.Random(0), player_faction_id="f1")
        ctx.defender_side.army.owner = "f1"
        resolve_strike(ctx, atk, tgt, "physical")
        self.assertLessEqual(tgt.cur_hp, 0)
        self.assertEqual(len(ctx.survived_this_battle), 0)

    def test_disabled_flag_no_trigger(self):
        # WILL_SURVIVAL_ENABLED=False → 不触发
        atk = _base_unit("a", "A", tags={"melee"}, p_atk=100)
        tgt = _base_unit("d", "D", tags={"melee"}, hp=10, p_def=0, will=100)
        ctx = _ctx(atk, tgt, rng=random.Random(0), player_faction_id="f1")
        ctx.defender_side.army.owner = "f1"
        orig = unit_mod.WILL_SURVIVAL_ENABLED
        unit_mod.WILL_SURVIVAL_ENABLED = False
        battle_mod.WILL_SURVIVAL_ENABLED = False
        try:
            resolve_strike(ctx, atk, tgt, "physical")
        finally:
            unit_mod.WILL_SURVIVAL_ENABLED = orig
            battle_mod.WILL_SURVIVAL_ENABLED = orig
        self.assertLessEqual(tgt.cur_hp, 0)
        self.assertEqual(len(ctx.survived_this_battle), 0)

    def test_make_unit_will_base(self):
        # make_unit 出来的单位 will base=5、growth=0.1
        from pydemo.cli.scenario import build_scenario
        g = build_scenario()
        u = g.make_unit("infantry")
        self.assertEqual(u.base["will"], 5.0)
        self.assertEqual(u.growth["will"], 0.1)

    def test_make_hero_will_growth(self):
        # make_hero 出来的英雄 will base=5、growth=0.2
        from pydemo.cli.scenario import build_scenario
        g = build_scenario()
        h = g.make_hero("knight")
        self.assertEqual(h.base["will"], 5.0)
        self.assertEqual(h.growth["will"], 0.2)

    def test_will_partial_chance_survives(self):
        # will=50,大样本统计:致死时约 50% 生还
        survived = 0
        n = 400
        for i in range(n):
            atk = _base_unit(f"a{i}", "A", tags={"melee"}, p_atk=1000)
            tgt = _base_unit(f"d{i}", "D", tags={"melee"}, hp=10, p_def=0, will=50)
            ctx = _ctx(atk, tgt, rng=random.Random(i), player_faction_id="f1")
            ctx.defender_side.army.owner = "f1"
            resolve_strike(ctx, atk, tgt, "physical")
            if tgt.cur_hp >= 1:
                survived += 1
        # 期望 ~50%,容差 ±10%
        self.assertAlmostEqual(survived / n, 0.5, delta=0.10)


if __name__ == "__main__":
    unittest.main()
