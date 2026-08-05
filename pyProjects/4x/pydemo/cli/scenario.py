"""
场景装配:3-4 据点双路径小地图 + 2 阵营(玩家+AI)初始状态。

拓扑(两首都夹中立据点,双路径):
  P_capital -- m1 -- N1 -- m2 -- A_capital        (主路径)
                    N1 -- m3 -- N2 -- m4 -- A_capital   (中立据点间分支)
  简化为:P_capital - m1 - N1 - m2 - A_capital,另 N1 - m3 - N2 - m4 - A_capital 两条路径
  实际连边:
    P - m1 - N1 - m2 - A          (上路)
    N1 - m3 - N2 - m4 - A         (下路汇回 A)
  即 N1 到 A 有两条路(m2 直达 / m3-N2-m4)。
"""
from __future__ import annotations
from ..game.game import Game
from ..game.map_system import Stronghold, MinorLocation, Building
from ..game.economy import Resources
from ..game.hero import RecruitmentPool


def build_scenario() -> Game:
    game = Game(seed=20260804)

    # 据点
    p_cap = Stronghold(id="p_cap", name="玩家首都", size="medium",
                       landmark_type="medium", owner="player", is_capital=True, x=0, y=0)
    a_cap = Stronghold(id="a_cap", name="AI首都", size="medium",
                       landmark_type="medium", owner="ai", is_capital=True, x=8, y=0)
    n1 = Stronghold(id="n1", name="中央堡", size="small",
                    landmark_type="weak", owner=None, x=4, y=0)
    n2 = Stronghold(id="n2", name="南境堡", size="small",
                    landmark_type="weak", owner=None, x=6, y=2)
    for s in (p_cap, a_cap, n1, n2):
        game.map.add_stronghold(s)

    # 小地点
    minors = [
        ("m1", "路口", "plains", 2, 0),
        ("m2", "隘口", "mountain", 6, 0),
        ("m3", "林道", "forest", 5, 1),
        ("m4", "南道", "plains", 7, 2),
    ]
    for mid, name, ter, x, y in minors:
        game.map.add_minor(MinorLocation(id=mid, name=name, terrain=ter, x=x, y=y))

    # 连边(双路径)
    edges = [("p_cap", "m1"), ("m1", "n1"), ("n1", "m2"), ("m2", "a_cap"),
             ("n1", "m3"), ("m3", "n2"), ("n2", "m4"), ("m4", "a_cap")]
    for a, b in edges:
        game.map.connect(a, b)

    # 阵营
    player = game.add_faction("player", "玩家", is_ai=False)
    ai = game.add_faction("ai", "敌方AI", is_ai=True)
    player.capital_id = "p_cap"
    ai.capital_id = "a_cap"
    player.stronghold_ids = ["p_cap"]
    ai.stronghold_ids = ["a_cap"]

    # 初始信念:给阵营初始信念取向,使对应英雄可达招募门槛
    # 玩家偏道德(骑士王 需 道德>=20),AI 偏功利(大法师 需 功利>=20)
    player.belief.values = {"morality": 20, "utility": 0, "liberty": 0}
    ai.belief.values = {"morality": 0, "utility": 20, "liberty": 0}

    # 初始资源
    for fid in ("player", "ai"):
        f = game.factions[fid]
        f.resources = Resources(amounts={
            "gold": 80, "food": 30, "wood": 30, "stone": 10, "iron": 10,
            "mana_stone": 15, "tech": 0, "culture": 5, "faith": 0,
            "luxury": 0, "decree": 0,
        })

    # 初始产出建筑(首都各一个农场)
    for cap_id in ("p_cap", "a_cap"):
        cap = game.map.strongholds[cap_id]
        cap.add_building(Building(id="b_farm_start", type_id="farm", name="农场",
                                  produces={"food": 5}, build_turns_left=0))

    # 据点驻军(含中立据点)
    for sid, sh in game.map.strongholds.items():
        game.make_garrison(sh)

    # 玩家初始英雄+部队
    hero = game.make_hero("knight")
    hero.node_id = "p_cap"
    player.hero_ids.append(hero.id)
    army = game.create_army("player", "p_cap", "先锋军")
    game.set_captain(army, hero)
    # 加 2 步兵
    for _ in range(2):
        u = game.make_unit("infantry")
        u.node_id = "p_cap"
        army.add(u, game.unit_index)

    # AI 初始英雄+部队
    ai_hero = game.make_hero("archmage")
    ai_hero.node_id = "a_cap"
    ai.hero_ids.append(ai_hero.id)
    ai_army = game.create_army("ai", "a_cap", "AI守备军")
    game.set_captain(ai_army, ai_hero)
    for _ in range(2):
        u = game.make_unit("archer")
        u.node_id = "a_cap"
        ai_army.add(u, game.unit_index)

    # 招募池初始化
    for fid, f in game.factions.items():
        for sid in f.stronghold_ids:
            pool = RecruitmentPool(stronghold_id=sid)
            pool.refresh(list(game.hero_defs.keys()), game.calendar.day)
            f.recruitment_pools[sid] = pool

    game.log_msg("场景就绪:玩家首都 vs AI首都,中央堡/南境堡为中立据点")
    return game
