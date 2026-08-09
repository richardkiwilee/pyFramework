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
from ..game.game import Game, cn_building
from ..game.map_system import Stronghold, MinorLocation, Building
from ..game.economy import Resources
from ..game.hero import RecruitmentPool


def build_scenario() -> Game:
    game = Game(seed=20260804)

    # 据点(size 为整数槽位 1~5,ADR-0006;landmark 为标志性建筑实例,提供守方防御 buff)
    # landmark 走独立专用槽(不在 buildings 列表、不计 size);首都 medium、中立 weak。
    # 首都 size=4:容纳 农场 + 信念英雄招募所需矿 + 2 个产出建筑,避免开局造满市场后
    # 再无槽位造英雄招募所需矿(玩家缺铁、AI 缺魔石)导致起始英雄战死后无法再招、
    # 陷入双方 0 部队死局(平衡修正:首都扩到 4 槽 + 各送初始矿)。
    def _landmark(type_id: str) -> Building:
        bdef = game.building_defs.get(type_id, {})
        return Building(id=f"lm_{type_id}", type_id=type_id,
                        name=cn_building(bdef), tier=bdef.get("tier", "weak"))

    p_cap = Stronghold(id="p_cap", name="玩家首都", size=4,
                       landmark=_landmark("lm_medium"), owner="player", is_capital=True, x=0, y=0)
    a_cap = Stronghold(id="a_cap", name="AI首都", size=4,
                       landmark=_landmark("lm_medium"), owner="ai", is_capital=True, x=8, y=0)
    n1 = Stronghold(id="n1", name="中央堡", size=1,
                    landmark=_landmark("lm_weak"), owner=None, x=4, y=0)
    n2 = Stronghold(id="n2", name="南境堡", size=1,
                    landmark=_landmark("lm_weak"), owner=None, x=6, y=2)
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

    # 初始产出建筑(建造即时,无 build_turns_left,ADR-0006):
    # 首都各一个农场(食物);并各送一个"初始矿"——玩家送铁矿井(骑士王 需 铁矿),
    # AI 送魔石矿(大法师 需 魔石),保证信念英雄招募所需资源流不断(平衡修正)。
    for cap_id in ("p_cap", "a_cap"):
        cap = game.map.strongholds[cap_id]
        cap.add_building(Building(id="b_farm_start", type_id="farm", name="农场",
                                  produces={"food": 5}))
    game.map.strongholds["p_cap"].add_building(
        Building(id="b_iron_start", type_id="iron_mine", name="铁矿井",
                 produces={"iron": 5}))
    game.map.strongholds["a_cap"].add_building(
        Building(id="b_mana_start", type_id="mana_mine", name="魔石矿",
                 produces={"mana_stone": 3}))

    # 初始仓库装备(ADR-0009):玩家开局每种装备定义各 3 件,全部入库存计数。
    # 装备按 def_id 以库存计数存储——inventory[def_id] += 3。无件级实例、无 200 件上限。
    # AI 原型阶段不使用装备,故不发放(AI 单位无装备,死亡回收为空操作)。
    for def_id in game.artifact_defs:
        game.add_artifact_stock(def_id, "player", count=3)
    game.log_msg(f"玩家仓库初始装备:{sum(1 for _ in game.artifact_defs) * 3} 件")

    # 据点驻军系统已废除(将来不存在玩家不能控制的部队):据点不再生成自动防御驻军,
    # 防御靠标志性建筑给驻守部队提供 buff;中立据点开局无守军,进攻方进入即易主。

    # 玩家初始英雄+部队
    hero = game.make_hero("knight")
    player.hero_ids.append(hero.id)
    # 初始英雄直接编入部队(不经待命池),作为开局已有部队
    army = game.create_army("player", "p_cap", "先锋军")
    game.set_captain(army, hero)
    # 加 2 步兵
    for _ in range(2):
        u = game.make_unit("infantry")
        u.node_id = "p_cap"
        army.add(u, game.unit_index)

    # AI 初始英雄+部队
    ai_hero = game.make_hero("archmage")
    ai.hero_ids.append(ai_hero.id)
    ai_army = game.create_army("ai", "a_cap", "AI守备军")
    game.set_captain(ai_army, ai_hero)
    for _ in range(2):
        u = game.make_unit("archer")
        u.node_id = "a_cap"
        ai_army.add(u, game.unit_index)

    # 预备兵兜底已移除(B1 招募普通兵动作已落地):
    # 起始部队战死后可通过建造招募建筑(兵营/马厩/靶场/法师塔/寺院)+ 招兵动作
    # 重建战力,不再需要开局硬塞预备兵。

    # 招募池初始化
    for fid, f in game.factions.items():
        for sid in f.stronghold_ids:
            pool = RecruitmentPool(stronghold_id=sid)
            pool.refresh(list(game.hero_defs.keys()), game.calendar.day)
            f.recruitment_pools[sid] = pool

    game.log_msg("场景就绪:玩家首都 vs AI首都,中央堡/南境堡为中立据点")
    return game
