"""
Game:核心编排。

把所有子系统串成可跑的一局:日历、地图、阵营、部队、单位、修正收集、
移动、战斗、占领、招募、建造、事件、胜负。

逻辑与交互分离:本类只暴露动作接口与查询;CLI/AI 调用之。
"""
from __future__ import annotations
import os
import random
from dataclasses import dataclass, field
from typing import Any

from .data_loader import load_definitions
from .time_system import Calendar
from .economy import (Resources, Belief, RESOURCE_TYPES, RESOURCE_CN, BELIEF_DIMS,
                      BELIEF_CN, SOURCE_BUILD, SOURCE_MAINT, SOURCE_RECRUIT,
                      SOURCE_TRAIN, SOURCE_SUPPLY, SOURCE_INIT)
from .map_system import GameMap, Stronghold, MinorLocation, Building
from .unit import (Unit, UnitType, Artifact, load_unit_types, load_artifacts,
                   ATTR_BOUNDS, ATTR_CN, TAG_CN, MAJOR_TAGS,
                   WILL_SURVIVAL_ENABLED, WILL_BASE, WILL_GROWTH_NORMAL, WILL_GROWTH_HERO)
from .hero import (HeroDef, load_hero_defs, make_hero_unit, meets_belief_req,
                   describe_req, RecruitmentPool)
from .army import Army, empty_army, row_of, col_of, ROWS, ROW_CN, GRID_SIZE
from .synergy import load_synergies, collect_synergy_mods
from .modifier import (Modifier, ModifierCollection, compute_attribute, ModifierSource)
from .effects import (Effect, build_skill_effects, collect_passive_modifiers,
                      skill_kind, SKILL_PERK)
from .formation import UnitStrategy, build_default_formation, choose_target_with_slots
from .battle import BattleSide, BattleResult, run_battle, effective_attrs
from .events import GameEvent, load_events, apply_option, random_event
from .faction import Faction


def cn_building(bdef: dict) -> str:
    return bdef.get("name", bdef.get("id", "?"))


def _load_list_defs(path: str) -> dict[str, dict]:
    """加载 techs/cultures 等 [{id, ...}] 列表为 {id: record}。失败返回 {}。"""
    import json
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}
    out: dict[str, dict] = {}
    if isinstance(data, list):
        for rec in data:
            if isinstance(rec, dict) and "id" in rec:
                out[str(rec["id"])] = rec
    return out


# 标志性建筑防御 buff:据点守方 p_def 百分比加成(按 landmark tier)
LANDMARK_DEFENSE_BUFF: dict[str, float] = {"weak": 0.0, "medium": 0.10, "strong": 0.20}

# 锻造屋回合产出(B10):每回合有此概率随机产出一件装备。
FORGE_DROP_CHANCE: float = 0.05
# 装备稀有度抽取权重(common/uncommon/rare)。
RARITY_WEIGHTS: dict[str, int] = {"common": 60, "uncommon": 30, "rare": 10}


def _weighted_random_artifact(rng, artifact_defs: dict) -> str | None:
    """按 RARITY_WEIGHTS 选稀有度,再在该稀有度装备定义中随机选一个 def_id。
    无该稀有度定义则回退 common。无任何装备定义返回 None。
    """
    if not artifact_defs:
        return None
    # 按稀有度分桶
    buckets: dict[str, list[str]] = {"common": [], "uncommon": [], "rare": []}
    for aid, a in artifact_defs.items():
        r = getattr(a, "rarity", "common")
        buckets.setdefault(r, []).append(aid)
    # 按权重选稀有度
    weighted = [(r, RARITY_WEIGHTS.get(r, 0)) for r in buckets if buckets[r]]
    if not weighted:
        return None
    total = sum(w for _, w in weighted)
    if total <= 0:
        return None
    roll = rng.random() * total
    acc = 0.0
    chosen_rarity = "common"
    for r, w in weighted:
        acc += w
        if roll < acc:
            chosen_rarity = r
            break
    pool = buckets.get(chosen_rarity) or buckets.get("common") or []
    if not pool:
        return None
    return rng.choice(pool)


def _forge_drop_handler(game: "Game", faction: "Faction", stronghold, building) -> None:
    """锻造屋 on_turn handler:5% 概率随机产出一件装备入阵营库存。
    装备按稀有度加权抽取(Forge drop);产出后入 faction.inventory(def_id 计数)。
    """
    rng = random.Random()  # 锻造屋用独立 rng;命中后随机选装备
    if rng.random() < FORGE_DROP_CHANCE:
        def_id = _weighted_random_artifact(rng, game.artifact_defs)
        if def_id:
            game.add_artifact_stock(def_id, faction.id, count=1)
            adef = game.artifact_defs.get(def_id)
            name = adef.name if adef else def_id
            game.log_msg(f"{stronghold.name} 锻造屋产出 {name}")


# 注册建筑回合事件 handler(B10):forge_drop → 锻造屋产出装备。
# 类属性在类体执行时建立,handler 引用 Game/Faction(运行时类型,见上注解)。



class Game:
    def __init__(self, defs: dict | None = None, seed: int | None = None) -> None:
        if seed is not None:
            random.seed(seed)
        self.defs = defs if defs is not None else load_definitions()
        # 定义
        self.unit_type_defs = load_unit_types(self.defs.get("unit_types", {}))
        self.hero_defs = load_hero_defs(self.defs.get("heroes", {}))
        self.artifact_defs = load_artifacts(self.defs.get("artifacts", {}))
        self.synergy_defs = load_synergies(self.defs.get("synergies", {}))
        self.event_defs = load_events(self.defs.get("events", {}))
        self.building_defs = self.defs.get("buildings", {})
        self.resource_defs = self.defs.get("resources", {})
        self.terrain_defs = self.defs.get("terrain", {})
        # 科技/文化定义(B7):data_loader 不在 DEFINITION_FILES 中,这里直接从 data/ 读。
        # 业务层建造门控(action_build requires)与 AI 学习逻辑查询之;TUI 树场景沿用 load_tree。
        from .data_loader import BASE_DATA_DIR
        self.tech_defs = _load_list_defs(os.path.join(BASE_DATA_DIR, "techs.json"))
        self.culture_defs = _load_list_defs(os.path.join(BASE_DATA_DIR, "cultures.json"))

        # 状态
        self.calendar = Calendar(day=1)
        self.map = GameMap()
        self.factions: dict[str, Faction] = {}
        self.armies: dict[str, Army] = {}
        self.unit_index: dict[str, Unit] = {}
        self.log: list[str] = []
        self.winner: str | None = None
        # 玩家阵营 id(顺序回合制:玩家先)
        self.player_id: str | None = None
        # 当前回合的事件(供玩家选择)
        self.pending_event: GameEvent | None = None
        self._army_counter = 0
        self._unit_counter = 0

    # ---------- 工具 ----------
    def log_msg(self, msg: str) -> None:
        self.log.append(msg)

    def new_id(self, prefix: str) -> str:
        self._army_counter if prefix == "army" else None
        self._unit_counter += 1
        return f"{prefix}_{self._unit_counter}"

    def new_army_id(self) -> str:
        self._army_counter += 1
        return f"army_{self._army_counter}"

    # ---------- 装备库存(def_id 计数模型,ADR-0009) ----------
    def add_artifact_stock(self, def_id: str, owner: str, count: int = 1) -> None:
        """给阵营仓库增加 count 件某定义装备(入库存计数)。"""
        f = self.factions.get(owner)
        if f is None or def_id not in self.artifact_defs:
            return
        f.inventory[def_id] = f.inventory.get(def_id, 0) + max(0, count)

    def artifact_def_of(self, def_id: str) -> Artifact | None:
        """按 def_id 取装备定义(ADR-0009)。"""
        return self.artifact_defs.get(def_id)

    def equipped_count(self, faction_id: str, def_id: str) -> int:
        """某 def_id 装备在本阵营各单位已装备的总数(反查所有己方单位 artifacts)。"""
        n = 0
        for uid, u in self.unit_index.items():
            if self._unit_owner(u) != faction_id:
                continue
            n += u.artifacts.count(def_id)
        return n

    def available_count(self, faction_id: str, def_id: str) -> int:
        """某 def_id 装备的"在库可装数" = 库存数 - 已装备数(≥0)。"""
        f = self.factions.get(faction_id)
        if not f:
            return 0
        stock = f.inventory.get(def_id, 0)
        return max(0, stock - self.equipped_count(faction_id, def_id))

    # ---------- 装配 ----------
    def add_faction(self, fid: str, name: str, is_ai: bool = False) -> Faction:
        f = Faction(id=fid, name=name, is_ai=is_ai)
        self.factions[fid] = f
        if not is_ai and self.player_id is None:
            self.player_id = fid
        return f

    def make_unit(self, type_id: str) -> Unit:
        ut = self.unit_type_defs[type_id]
        base = dict(ut.base)
        growth = dict(ut.growth)
        # 意志生还(B3):普通兵覆盖 will 基准=5、增长率=0.1(数据层默认 0/0.3)
        base["will"] = WILL_BASE
        growth["will"] = WILL_GROWTH_NORMAL
        u = Unit(
            id=self.new_id("u"),
            type_id=type_id, name=ut.name, tags=set(ut.tags),
            base=base,
            growth=growth,
        )
        u.grant_tags_from_artifacts(self.artifact_defs)
        self.unit_index[u.id] = u
        return u

    def make_hero(self, hero_def_id: str) -> Unit:
        hdef = self.hero_defs[hero_def_id]
        u = make_hero_unit(hdef)
        u.id = self.new_id("u")
        # 意志生还(B3):英雄覆盖 will 基准=5、增长率=0.2(数据层默认 0/0.3)
        u.base["will"] = WILL_BASE
        u.growth["will"] = WILL_GROWTH_HERO
        u.grant_tags_from_artifacts(self.artifact_defs)
        self.unit_index[u.id] = u
        return u

    def create_army(self, owner: str, node_id: str, name: str) -> Army:
        aid = self.new_army_id()
        army = empty_army(aid, name, owner, node_id)
        self.armies[aid] = army
        self.factions[owner].army_ids.append(aid)
        return army

    def set_captain(self, army: Army, hero_unit: Unit) -> bool:
        if not hero_unit.is_hero:
            return False
        # 若该英雄已是别的部队队长,先离队
        if hero_unit.army_id and hero_unit.army_id != army.id:
            old = self.armies.get(hero_unit.army_id)
            if old:
                old.remove(hero_unit.id)
                old.captain_id = None
                self._try_fill_captain(old)
        # 记录是否在待命池;出池推迟到 can_add 通过之后,避免"加入失败却已出池"
        # 导致单位既不在待命也不在部队(孤儿)。
        f = self.factions.get(army.owner)
        in_standby = f is not None and hero_unit.id in f.standby
        # 先设队长,使 max_leadership 计入该英雄的领导力(队长领导力即部队上限)
        army.captain_id = hero_unit.id
        if hero_unit.army_id != army.id:
            # 加入部队(若有空位且不超领导力)
            if not army.can_add(hero_unit, self.unit_index):
                army.captain_id = None   # 回滚:加入失败,复原队长空缺
                return False
            if in_standby:
                self._pull_from_standby(f, hero_unit)   # can_add 已通过,安全出池
            army.add(hero_unit, self.unit_index)
            # 单位位置随部队(部队所在据点)
            hero_unit.node_id = army.node_id
        elif in_standby:
            # 英雄已在部队但仍在待命池(理论上不会发生):一并出池
            self._pull_from_standby(f, hero_unit)
        return True

    def _try_fill_captain(self, army: Army) -> bool:
        """队长空缺时,从待命·可用英雄指派接任;无则解散。

        待命为阵营级、无位置(ADR-0005):候选来自 owner 阵营的 standby 池中
        冷却已归零的英雄,不再限"同据点无部队英雄"。
        """
        if army.captain_id and army.captain_id in self.unit_index:
            return True
        f = self.factions.get(army.owner)
        if not f:
            self.disband_army(army)
            return False
        # 阵营级待命·可用英雄(优先取 leadership 高的,便于承接大部队)
        cands = [self.unit_index[uid] for uid in f.standby_available_ids()
                 if uid in self.unit_index and self.unit_index[uid].is_hero
                 and self.unit_index[uid].alive]
        cands.sort(key=lambda u: u.leadership(), reverse=True)
        for u in cands:
            if self.set_captain(army, u):   # set_captain 内部在 can_add 通过后出池
                return True
        # 无可用英雄:解散
        self.disband_army(army)
        return False

    def disband_army(self, army: Army) -> None:
        for uid in list(army.grid):
            if uid:
                u = self.unit_index.get(uid)
                if u:
                    u.army_id = None
        army.grid = [None] * GRID_SIZE
        army.captain_id = None
        if army.id in self.armies:
            for f in self.factions.values():
                if army.id in f.army_ids:
                    f.army_ids.remove(army.id)
            del self.armies[army.id]

    # ---------- 待命池(ADR-0005) ----------
    STANDBY_COOLDOWN = 5

    def _to_standby(self, faction: Faction, unit: Unit, cooldown: int) -> None:
        """单位进待命池:清 army_id、node_id,记冷却。"""
        unit.army_id = None
        unit.node_id = None
        faction.standby[unit.id] = cooldown

    def _pull_from_standby(self, faction: Faction, unit: Unit) -> None:
        """单位出待命池:从池中移除(node_id 由调用方按部队所在据点补设)。"""
        faction.standby.pop(unit.id, None)

    def _tick_standby(self, faction: Faction) -> None:
        """回合开始:所有不可用待命单位冷却 -1,到 0 转为可用。"""
        for uid in list(faction.standby.keys()):
            if faction.standby[uid] > 0:
                faction.standby[uid] -= 1

    # def_id 库存模型无卸下冷却,故无 _tick_inventory(ADR-0009 取代 ADR-0007)。

    def action_deploy(self, faction_id: str, army_id: str, unit_id: str,
                      slot: int | None = None) -> str:
        """上场:把待命·可用单位派进己方据点内的一支部队(§5)。

        约束:单位必须在待命池且冷却已归零(可用);目标部队必须为本阵营部队,
        且当前停在己方据点内(ADR-0005:部队必须回到己方据点才能补充人员)。
        槽位由调用方指定(空格选中的位置);不指定则按兵种角色自动落位。
        资源不做扣减(上场本身免费,招募时已付)。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        u = self.unit_index.get(unit_id)
        if not u:
            return "失败:无此单位"
        if unit_id not in f.standby:
            return "失败:单位不在待命池"
        if f.standby[unit_id] > 0:
            return "失败:单位待命·不可用"
        army = self.armies.get(army_id)
        if not army or army.owner != faction_id:
            return "失败:无此部队"
        if army.node_id not in f.stronghold_ids:
            return "失败:部队不在己方据点"
        if not army.can_add(u, self.unit_index):
            return "失败:部队已满或领导力不足"
        if slot is not None:
            if not (0 <= slot < GRID_SIZE):
                return "失败:槽位越界"
            if army.grid[slot] is not None:
                return "失败:该槽位已占用"
            ok = army.add(u, self.unit_index, slot=slot)
        else:
            ok = army.add(u, self.unit_index)
        if not ok:
            return "失败:加入失败"
        self._pull_from_standby(f, u)
        u.node_id = army.node_id
        return f"{u.name} 已上场至 {army.name}"

    def action_discharge(self, faction_id: str, army_id: str,
                         unit_id: str) -> str:
        """下场:把部队中的单位撤入待命(§7.7 + ADR-0005,操作逻辑.md §7.7)。

        冷却规则:单位所属部队当前停在己方据点内,则下场后立刻进入待命·可用
        (冷却 0);不在己方据点(野外/敌境)则进待命·不可用,5 回合后转可用。
        队长下场后由 _try_fill_captain 接任;无可用英雄接任则部队解散。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        army = self.armies.get(army_id)
        if not army or army.owner != faction_id:
            return "失败:无此部队"
        u = self.unit_index.get(unit_id)
        if not u or u.army_id != army_id:
            return "失败:单位不在此部队"
        if unit_id not in army.grid:
            return "失败:单位不在此部队"
        # 从九宫格移除
        army.remove(unit_id)
        # 冷却:部队在己方据点 → 立即可用;否则 5 回合不可用(操作逻辑.md §7.7)
        in_stronghold = army.node_id in f.stronghold_ids
        if in_stronghold:
            self._to_standby(f, u, cooldown=0)
            msg = f"{u.name} 下场,进入待命·可用(部队在己方据点)"
        else:
            self._to_standby(f, u, cooldown=self.STANDBY_COOLDOWN)
            msg = f"{u.name} 下场,进入待命·不可用({self.STANDBY_COOLDOWN}回合)"
        # 若是队长,尝试接任;无可用英雄则解散(并提示)
        if army.captain_id == unit_id:
            army.captain_id = None
            if not self._try_fill_captain(army):
                msg += f";无可用英雄接任,{army.name} 已解散"
        return msg

    def action_equip(self, faction_id: str, unit_id: str,
                     def_id: str, slot: int) -> str:
        """装备一件仓库内在库可用装备到指定槽位 0..3(ADR-0009)。

        装备按 def_id 以库存计数存储:取该 def_id 一件在库可装数装备到 slot。
        位置限制:目标单位所在部队必须位于己方据点内才允许(待命单位无部队、
        视为安全,可编辑);野外部队无法穿戴。槽位已占用时先把旧装备卸下(回库)。
        库存不足/槽位越界/位置不符则失败。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        u = self.unit_index.get(unit_id)
        if not u:
            return "失败:无此单位"
        if self._unit_owner(u) != faction_id:
            return "失败:单位不归你"
        if not (0 <= slot < u.ARTIFACT_SLOTS):
            return "失败:槽位越界"
        if not self._unit_in_own_stronghold(f, u):
            return "失败:单位不在己方据点(野外不可穿戴/卸下)"
        if def_id not in self.artifact_defs:
            return "失败:未知装备定义"
        if self.available_count(faction_id, def_id) <= 0:
            return "失败:仓库无此装备在库可用"
        art = self.artifact_defs[def_id]
        # 槽位已占用:先把旧装备卸下(回库)
        while len(u.artifacts) <= slot:
            u.artifacts.append(None)  # type: ignore[arg-type]
        if u.artifacts[slot] is not None:
            self._unequip_into_inventory(u, slot)
        # 装上新装备(记 def_id 到槽位;库存计数不变,已装备由反查体现)
        u.artifacts[slot] = def_id
        self._recompute_unit_tags(u)
        self._recompute_granted_skills(u)
        return f"{u.name} 装备了 {art.name}"

    def action_unequip(self, faction_id: str, unit_id: str, slot: int) -> str:
        """卸下单位指定槽位 0..3 的装备,回库(ADR-0009)。

        位置限制同装备:单位所在部队须在己方据点内;待命单位可编辑。
        无冷却——卸下即回库可用。槽位空则失败。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        u = self.unit_index.get(unit_id)
        if not u:
            return "失败:无此单位"
        if self._unit_owner(u) != faction_id:
            return "失败:单位不归你"
        if not (0 <= slot < u.ARTIFACT_SLOTS):
            return "失败:槽位越界"
        if not self._unit_in_own_stronghold(f, u):
            return "失败:单位不在己方据点(野外不可穿戴/卸下)"
        if slot >= len(u.artifacts) or u.artifacts[slot] is None:
            return "失败:该槽位无装备"
        name = self._unequip_into_inventory(u, slot)
        self._recompute_unit_tags(u)
        self._recompute_granted_skills(u)
        return f"{u.name} 卸下了 {name}(回库·可用)"

    def _unequip_into_inventory(self, u: Unit, slot: int) -> str:
        """把单位 slot 槽位的装备卸下回库(库存计数不变,槽位置 None)。返回装备名。"""
        def_id = u.artifacts[slot]
        art = self.artifact_defs.get(def_id) if def_id else None
        name = art.name if art else (def_id or "?")
        u.artifacts[slot] = None
        return name

    def _unit_in_own_stronghold(self, f: Faction, u: Unit) -> bool:
        """单位所在部队是否在己方据点内(待命单位无部队、视为安全,可编辑)。ADR-0009。"""
        if not u.army_id:
            return True   # 待命单位
        army = self.armies.get(u.army_id)
        if not army:
            return False
        return army.node_id in f.stronghold_ids

    def action_sell_artifact(self, faction_id: str, def_id: str) -> str:
        """卖出仓库内 1 件某定义装备,固定 +10 金币(ADR-0009)。

        按定义卖:从库存扣 1(只能在库可用数内,已装备数不可卖)。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        if def_id not in self.artifact_defs:
            return "失败:未知装备定义"
        if self.available_count(faction_id, def_id) <= 0:
            return "失败:无在库可用件(已装备须先卸下)"
        art = self.artifact_defs[def_id]
        f.inventory[def_id] -= 1
        if f.inventory[def_id] <= 0:
            f.inventory.pop(def_id, None)
        f.resources.add("gold", 10, source=SOURCE_INIT, building=art.name)
        return f"卖出 {art.name},+10 金币"

    def _release_artifacts(self, f: Faction, u: Unit) -> None:
        """单位死亡/解散时回收其装备:全部回库(死亡无位置惩罚)。ADR-0009。

        def_id 库存计数不变(库存含已装备),单位槽位置空即可——已装备数由反查体现,
        单位没了就不再占用库存。故本函数只需清槽位。
        """
        u.artifacts = []
        u.granted_skills = []

    def _recompute_unit_tags(self, u: Unit) -> None:
        """重算单位 tags = 本体 tag ∪ 当前装备赋予的 tag(ADR-0009)。

        兵种本体 tag 不可由装备移除,故每次装备/卸下后重算。按 def_id 直接查 artifact_defs。
        """
        granted: set[str] = set()
        for def_id in u.artifacts:
            art = self.artifact_defs.get(def_id)
            if not art:
                continue
            for e in art.effects:
                if e.get("type") == "tag_grant":
                    granted.add(e["params"]["tag"])
        body_tags = self._body_tags(u)
        u.tags = body_tags | granted

    def _recompute_granted_skills(self, u: Unit) -> None:
        """重算装备赋予技能(ADR-0008):遍历单位装备,收集 skill_grant 的技能 id。

        装上时加入、卸下时移除——整体重算即可(装/卸后调用)。与 _recompute_unit_tags
        同样的"全量重算"口径。
        """
        granted: list[str] = []
        for def_id in u.artifacts:
            art = self.artifact_defs.get(def_id)
            if not art:
                continue
            for e in art.effects:
                if e.get("type") == "skill_grant":
                    sid = e["params"].get("skill")
                    if sid and sid not in granted:
                        granted.append(sid)
        u.granted_skills = granted

    def _body_tags(self, u: Unit) -> set[str]:
        """单位本体词条(不含装备赋予的 tag)。取兵种/英雄定义的原始 tags。"""
        if u.is_hero:
            hdef = self.hero_defs.get(u.type_id)
            return set(hdef.tags) if hdef else set(u.tags)
        ut = self.unit_type_defs.get(u.type_id)
        return set(ut.tags) if ut else set(u.tags)

    # ---------- 修正收集 ----------
    def collect_unit_mods(self, unit: Unit, army: Army | None,
                          calendar: Calendar, terrain: str | None = None) -> list[Modifier]:
        """收集作用于某单位的所有修正。"""
        mods: list[Modifier] = []
        # 1. 月相:魔力恢复
        mods.append(Modifier(ModifierSource.MOON, "moon", unit.id, "mana_regen",
                             float(calendar.mana_regen()), op="flat"))
        # 2. 昼夜:简化按兵种给修正(白天近战+物攻,夜晚魔法+魔攻,等)
        tod = calendar.time_of_day_index()
        tod_bonus = {
            0: {"melee": ("p_atk", 0.05)},   # 清晨 近战+5%
            1: {"ranged": ("p_atk", 0.05)},    # 白天 远程+5%
            2: {"melee": ("p_atk", 0.05)},    # 黄昏 近战+5%
            3: {"magic": ("m_atk", 0.10)},    # 夜晚 魔法+10%
            4: {"magic": ("m_atk", 0.15)},    # 深夜 魔法+15%
        }.get(tod, {})
        for tag, (attr, val) in tod_bonus.items():
            if tag in unit.tags:
                mods.append(Modifier(ModifierSource.DAY_NIGHT, "tod", unit.id, attr, val, op="pct"))
        # 3. 兵种词条加成:原型通过技能 tag_bonus 体现,无全局词条修正
        # 4. 技能/被动:遍历单位有效技能(习得 + 装备赋予),kind=perk 走修正管道
        for sid in unit.effective_skills():
            skill_data = self._skill_def(sid)
            if not skill_data:
                continue
            # 仅 perk(kind=perk 或缺省)走修正管道;active/passive 由战斗引擎处理
            if skill_kind(skill_data) != SKILL_PERK:
                continue
            effs = build_skill_effects(skill_data)
            army_tags_count = self._army_tags_count(army) if army else {}
            mods.extend(collect_passive_modifiers(effs, unit.id, unit.tags,
                                                  army_tags_count,
                                                  ModifierSource.SKILL, sid))
        # 5. 装备:按 def_id 直接查 defs(ADR-0009)
        for def_id in unit.artifacts:
            art = self.artifact_defs.get(def_id)
            if not art:
                continue
            effs = build_skill_effects({"effects": art.effects})
            army_tags_count = self._army_tags_count(army) if army else {}
            mods.extend(collect_passive_modifiers(effs, unit.id, unit.tags,
                                                  army_tags_count,
                                                  ModifierSource.ARTIFACT, def_id))
        # 6. 地形(小地点):原型给小修正
        if terrain and terrain in self.terrain_defs:
            tdef = self.terrain_defs[terrain]
            for attr, val in tdef.get("mods", {}).items():
                mods.append(Modifier(ModifierSource.TERRAIN, terrain, unit.id, attr,
                                     float(val), op="flat"))
        return mods

    def _skill_def(self, sid: str) -> dict | None:
        """技能定义查找:原型技能挂在 hero_defs 的 skills 里(列表 of id),
        实际效果数据存于 data/skills.json。"""
        return self.defs.get("skills", {}).get(sid)

    def _army_tags_count(self, army: Army | None) -> dict[str, int]:
        if not army:
            return {}
        counts: dict[str, int] = {}
        for uid in army.grid:
            if uid and uid in self.unit_index:
                for t in self.unit_index[uid].tags:
                    counts[t] = counts.get(t, 0) + 1
        return counts

    def collect_army_mods(self, army: Army, calendar: Calendar,
                          terrain: str | None = None) -> list[Modifier]:
        """收集整支部队所有单位的修正 + 羁绊。"""
        all_mods: list[Modifier] = []
        units = army.alive_units(self.unit_index)
        tags_count = self._army_tags_count(army)
        # 羁绊
        all_mods.extend(collect_synergy_mods(tags_count, units, self.synergy_defs))
        # 每单位
        for u in units:
            all_mods.extend(self.collect_unit_mods(u, army, calendar, terrain))
        return all_mods

    # ---------- 回合驱动 ----------
    def start_turn(self, faction: Faction) -> None:
        """每阵营回合开始(规范入口):待命冷却推进 → 经济结算(含维护费/回血) →
        招募池刷新检查 → 建筑回合事件 dispatch。

        AI 阵营与玩家阵营都走此入口。CLI/TUI 的回合编排应调用 start_turn,
        不再直接调 tick_economy(后者仅为经济结算子步,供 start_turn 内部调用)。
        回血前必须先扣维护费并打好断粮标记(断粮单位本回合不回血,见 §1)。
        建筑回合事件在 tick_economy 之后、招募池刷新之后 dispatch(产出已结算,
        事件可能产出装备入库存)。
        """
        # 待命冷却推进(ADR-0005):不可用单位 -1,到 0 转可用
        self._tick_standby(faction)
        # 装备冷却已移除(def_id 库存模型,ADR-0009),无 _tick_inventory
        # 经济结算:产出 → 扣维护费(打断粮标记)→ 补给 → 各类回血(均跳过断粮单位)
        # §2:回合开始先清空各资源 delta(存量保留),供本回合重新累计净变动
        faction.resources.reset_turn()
        self.tick_economy(faction)
        # 招募池刷新(每 14 天)
        for sid in list(faction.stronghold_ids):
            pool = faction.recruitment_pools.get(sid)
            if not pool:
                pool = RecruitmentPool(stronghold_id=sid)
                faction.recruitment_pools[sid] = pool
                pool.refresh(list(self.hero_defs.keys()), self.calendar.day)
            elif self.calendar.day >= pool.refresh_day:
                pool.refresh(list(self.hero_defs.keys()), self.calendar.day)
        # 建筑回合事件 dispatch(B10):遍历己方据点建筑,触发 on_turn handler。
        self._dispatch_building_turn_events(faction)

    # ---------- 建筑回合事件(B10) ----------
    # 建筑定义的 on_turn 字段指向注册表中的 handler 名;start_turn 在 tick_economy 后 dispatch。
    # 扩展点:新事件在 BUILDING_TURN_EVENTS 注册 handler 即可,不改 start_turn。
    BUILDING_TURN_EVENTS: dict = {"forge_drop": _forge_drop_handler}  # event_name -> handler(game, faction, stronghold, building)

    def _dispatch_building_turn_events(self, faction: Faction) -> None:
        for sid in list(faction.stronghold_ids):
            sh = self.map.strongholds.get(sid)
            if not sh:
                continue
            for b in list(sh.buildings):
                bdef = self.building_defs.get(b.type_id, {})
                event = bdef.get("on_turn")
                if not event:
                    continue
                handler = self.BUILDING_TURN_EVENTS.get(event)
                if handler:
                    handler(self, faction, sh, b)

    def end_turn_advance(self) -> None:
        """回合结束推进时间。"""
        self.calendar.advance()

    # ---------- 经济 ----------
    def tick_economy(self, faction: Faction) -> None:
        """经济结算(由 start_turn 调用,也可单独调用以重算)。时序(见 §1 Maintenance):
        建筑产出 → 扣维护费(打断粮标记) → 补给补充 → 补给消耗/野外回血(5%)
        → 据点内回血(10%)。

        所有回血阶段均跳过本回合断粮(_starved_this_turn)的单位(不掉血,仅跳过)。
        """
        # 1. 建筑产出(§2 delta:来源 build + 据点+建筑名)
        for sid in list(faction.stronghold_ids):
            sh = self.map.strongholds.get(sid)
            if not sh:
                continue
            gained = sh.tick_produce()
            for k, v in gained.items():
                # 该据点所有产出建筑贡献同一资源,记成一条 delta(溯源到据点 + 建筑名串)
                bld_names = "、".join(b.name for b in sh.buildings
                                      if k in b.produces) or None
                faction.resources.add(k, v, source=SOURCE_BUILD,
                                      stronghold=sid, building=bld_names)
        # 2. 扣维护费(单独函数,便于调整平衡;§1):在回血之前打断粮标记
        self._deduct_maintenance(faction)
        # 3. 补给补充:在己方据点的部队(§2 delta:来源 supply)
        for aid in list(faction.army_ids):
            army = self.armies.get(aid)
            if not army:
                continue
            if army.node_id in faction.stronghold_ids:
                need = army.supply_max - army.supply
                if need > 0 and faction.resources.get("food") >= need:
                    faction.resources.add("food", -need, source=SOURCE_SUPPLY)
                    army.supply = army.supply_max
                elif need > 0:
                    give = min(need, faction.resources.get("food"))
                    faction.resources.add("food", -give, source=SOURCE_SUPPLY)
                    army.supply += give
        # 4. 补给消耗 + 野外回血(ADR-0004):在小地点的部队
        for aid in list(faction.army_ids):
            army = self.armies.get(aid)
            if not army:
                continue
            if army.node_id in self.map.minors:
                army.supply -= 1
                if army.supply <= 0:
                    army.supply = 0
                    for u in army.alive_units(self.unit_index):
                        u.cur_hp = max(0, u.cur_hp - u.base.get("hp", 1) * 0.05)
                else:
                    # 野外(小地点)有补给时每回合回血 5%;断粮单位跳过
                    for u in army.alive_units(self.unit_index):
                        if getattr(u, "_starved_this_turn", False):
                            continue
                        u.cur_hp = min(u.base.get("hp", 1),
                                       u.cur_hp + u.base.get("hp", 1) * 0.05)
        # 5. 据点内回血(ADR-0004):在己方据点内每回合回血 10%;断粮单位跳过
        for aid in list(faction.army_ids):
            army = self.armies.get(aid)
            if not army:
                continue
            if army.node_id not in faction.stronghold_ids:
                continue
            for u in army.alive_units(self.unit_index):
                if getattr(u, "_starved_this_turn", False):
                    continue
                u.cur_hp = min(u.base.get("hp", 1),
                               u.cur_hp + u.base.get("hp", 1) * 0.1)

    # ---------- 维护费(§1) ----------
    def _deduct_maintenance(self, faction: Faction) -> None:
        """扣各单位维护费(§1)。单位级判定:逐资源尝试扣(允许部分扣),但只要任一
        资源没扣足,即标记该单位本回合断粮(不回血)。

        待命中的单位需不需要维护费?——需要。待命不是免维护状态(只免去上场冷却);
        静养不进食说不通,且会让待命池成为躲避维护费的漏洞。故待命单位照常扣维护费,
        断粮同样打标(待命单位本就不回血,标记在此只记录口径,无副作用)。

        数据来源:UnitType.maintenance / HeroDef.maintenance(数据驱动)。
        原型默认:普通人类兵种 {food:1},魔法兵种追加魔石,英雄约为普通 4 倍。
        """
        # 先把阵营所有单位打上未断粮默认(含上回合已断粮的,每回合重判);
        # 同时复位训练标记(§3:每回合每单位最多训练 1 次)
        for uid, u in self.unit_index.items():
            if u.alive and self._unit_owner(u) == faction.id:
                u._starved_this_turn = False
                u._trained_this_turn = False
        # 逐单位扣维护费
        for uid, u in self.unit_index.items():
            if not u.alive:
                continue
            army = self.armies.get(u.army_id) if u.army_id else None
            # 只管该阵营的单位(队长/成员归属由 army.owner 决定;待命单位也属本阵营)
            owner = self._unit_owner(u)
            if owner != faction.id:
                continue
            cost = self._maintenance_cost(u)
            if not cost:
                continue
            # 逐资源尝试扣,允许部分扣(§2 delta:来源 maint)
            starved = False
            for k, v in cost.items():
                have = faction.resources.get(k)
                pay_v = min(v, have)
                if pay_v > 0:
                    faction.resources.add(k, -pay_v, source=SOURCE_MAINT)
                if pay_v < v:
                    starved = True   # 该资源没扣足
            if starved:
                u._starved_this_turn = True
            # else 分支:已在开头重置为 False

    def _unit_owner(self, u: Unit) -> str | None:
        """单位归属阵营:部队成员看 army.owner,待命单位遍历阵营 standby。"""
        if u.army_id and u.army_id in self.armies:
            return self.armies[u.army_id].owner
        for fid, f in self.factions.items():
            if u.id in f.standby:
                return fid
        return None

    def _maintenance_cost(self, u: Unit) -> dict[str, int]:
        """单位的维护费(数据驱动)。原型默认规则见 CONTEXT.md Maintenance。"""
        # 优先读定义里的 maintenance 字段;无则按原型默认推算
        if u.is_hero:
            hdef = self.hero_defs.get(u.type_id)
            if hdef and getattr(hdef, "maintenance", None):
                return dict(hdef.maintenance)
        else:
            ut = self.unit_type_defs.get(u.type_id)
            if ut and getattr(ut, "maintenance", None):
                return dict(ut.maintenance)
        # 默认:普通人类兵种 {food:1},魔法兵种追加魔石,英雄 4 倍
        cost: dict[str, int] = {"food": 4 if u.is_hero else 1}
        if "magic" in u.tags:
            cost["mana_stone"] = 4 if u.is_hero else 1
        return cost

    def _train_cost(self, u: Unit) -> dict[str, int]:
        """训练消耗(数据驱动)。原型默认:gold = 招募价/2 + 5 食物;魔法系兵种额外消耗魔石;
        英雄按其定义。见 CONTEXT.md Training 训练消耗。"""
        if u.is_hero:
            hdef = self.hero_defs.get(u.type_id)
            if hdef and getattr(hdef, "train_cost", None):
                return dict(hdef.train_cost)
        else:
            ut = self.unit_type_defs.get(u.type_id)
            if ut and getattr(ut, "train_cost", None):
                return dict(ut.train_cost)
        # 默认:gold = 招募价/2(向下取整) + 5 食物;魔法系追加 1 魔石
        recruit = {}
        if u.is_hero:
            hdef = self.hero_defs.get(u.type_id)
            recruit = hdef.recruit_cost if hdef else {}
        else:
            ut = self.unit_type_defs.get(u.type_id)
            recruit = ut.recruit_cost if ut else {}
        gold_half = recruit.get("gold", 0) // 2
        cost: dict[str, int] = {"gold": gold_half + 5, "food": 5}
        if "magic" in u.tags:
            cost["mana_stone"] = 1
        return cost

    def is_trainable(self, u: Unit) -> tuple[bool, str]:
        """单位是否可训练(§3)。返回(可否, 不可原因)。

        可训练位:
        - 在己方据点内的部队中,且该据点无任何敌方部队;或
        - 待命·可用(无位置,默认安全)。
        其余条件(本回合尚未训练、资源负担得起)在 action_train 中实时判定。
        """
        owner = self._unit_owner(u)
        if owner is None:
            return False, "无主单位"
        if not u.alive:
            return False, "单位已亡"
        # 待命·可用:无位置,默认安全可训练
        f = self.factions.get(owner)
        if f and u.id in f.standby:
            if f.standby[u.id] > 0:
                return False, "待命·不可用"
            return True, ""
        # 在部队中:检查部队是否在己方据点且该据点无敌方部队
        if u.army_id and u.army_id in self.armies:
            army = self.armies[u.army_id]
            if army.node_id not in f.stronghold_ids:
                return False, "部队不在己方据点"
            # 该据点是否有任何敌方部队
            for a in self.armies.values():
                if (a.node_id == army.node_id and a.owner not in (None, owner)
                        and not a.is_wiped(self.unit_index)):
                    return False, "据点有敌方部队"
            return True, ""
        return False, "单位不在部队也不在待命"

    def action_train(self, faction_id: str, unit_id: str) -> str:
        """训练:消耗资源获 +5 XP(§3)。每回合每单位最多 1 次。

        可训练位见 is_trainable;升级时 HP 按比例保留(见 Unit.gain_xp)。
        训练本身不回血。
        """
        u = self.unit_index.get(unit_id)
        if not u:
            return "失败:无此单位"
        if self._unit_owner(u) != faction_id:
            return "失败:单位不归你"
        if getattr(u, "_trained_this_turn", False):
            return "失败:本回合已训练"
        ok, why = self.is_trainable(u)
        if not ok:
            return f"失败:不可训练({why})"
        cost = self._train_cost(u)
        f = self.factions[faction_id]
        if not f.resources.can_afford(cost):
            return "失败:资源不足"
        f.resources.pay(cost, source=SOURCE_TRAIN)
        levels = u.gain_xp(5)
        u._trained_this_turn = True
        msg = f"{u.name} 训练:+5XP"
        if levels > 0:
            msg += f",升到 Lv{u.level}"
        return msg

    # ---------- 动作 ----------
    def action_build(self, faction_id: str, stronghold_id: str, building_id: str) -> str:
        """建造:支付足额资源即立即建成(ADR-0006,无建造回合)。

        操作逻辑.md §2.1:建造后立刻刷新"下回合变化"——把新建筑的下回合产出
        写入资源投影(add_projected),使面板净变动立刻体现(如农场 +5 食物:
        27(-3) 立刻变 27(+2))。投影由 reset_turn 清空,下回合真实产出由
        tick_economy 记 delta,不会重复计数。
        """
        f = self.factions[faction_id]
        sh = self.map.strongholds.get(stronghold_id)
        if not sh or sh.owner != faction_id:
            return "失败:据点不归你所有"
        if sh.free_slots() <= 0:
            return "失败:据点无空槽"
        bdef = self.building_defs.get(building_id)
        if not bdef:
            return "失败:未知建筑"
        # 建造门控(B7):recruit/special 类建筑需 requires 中列出的科技/文化已学。
        # 产出建筑(produce)免门控——保「独特建筑→独特兵种→战略位置」设计意图。
        requires = bdef.get("requires", [])
        if requires:
            missing = self._unmet_requires(faction_id, requires)
            if missing:
                return f"失败:需先研究 {'、'.join(missing)}"
        cost = bdef.get("cost", {})
        if not f.resources.can_afford(cost):
            return "失败:资源不足"
        f.resources.pay(cost, source=SOURCE_BUILD, stronghold=stronghold_id,
                        building=cn_building(bdef))
        b = Building(id=f"b{random.randint(1000,9999)}", type_id=building_id,
                     name=cn_building(bdef),
                     produces=bdef.get("produces", {}) if bdef.get("kind") == "produce" else {})
        sh.add_building(b)
        # point 4:新建筑下回合产出写入投影,面板立刻刷新
        for k, v in b.produces.items():
            f.resources.resource(k).add_projected(v)
        return f"已在 {sh.name} 建造 {b.name}(即时建成)"

    def action_demolish(self, faction_id: str, stronghold_id: str, building_id: str) -> str:
        """拆除据点内一座建筑(按 Building.id 实例 id)。

        即时拆除、不退资源(原型)。操作逻辑.md §5.4:拆除后立刻刷新"下回合变化"——
        该建筑的下回合产出从投影中扣除(add_projected(-v)),面板净变动立刻体现。
        """
        f = self.factions[faction_id]
        sh = self.map.strongholds.get(stronghold_id)
        if not sh or sh.owner != faction_id:
            return "失败:据点不归你所有"
        target = None
        for b in sh.buildings:
            if b.id == building_id:
                target = b
                break
        if target is None:
            return "失败:据点内无此建筑"
        sh.buildings.remove(target)
        # point 4:拆除建筑下回合产出从投影扣除,面板立刻刷新
        for k, v in target.produces.items():
            f.resources.resource(k).add_projected(-v)
        return f"已在 {sh.name} 拆除 {target.name}"

    def action_recruit_hero(self, faction_id: str, stronghold_id: str, hero_id: str) -> str:
        f = self.factions[faction_id]
        sh = self.map.strongholds.get(stronghold_id)
        if not sh or sh.owner != faction_id:
            return "失败:据点不归你所有"
        pool = f.recruitment_pools.get(stronghold_id)
        if not pool or hero_id not in pool.offerings:
            return "失败:该英雄不在招募池"
        hdef = self.hero_defs.get(hero_id)
        if not hdef:
            return "失败:未知英雄"
        if not meets_belief_req(f.belief, hdef.belief_req):
            return "失败:信念不足(" + describe_req(hdef.belief_req) + ")"
        if not f.resources.can_afford(hdef.recruit_cost):
            return "失败:资源不足"
        f.resources.pay(hdef.recruit_cost, source=SOURCE_RECRUIT, stronghold=stronghold_id,
                        building=hdef.name)
        u = self.make_hero(hero_id)
        f.hero_ids.append(u.id)
        # 招募后该槽位置 None（不压缩），其余英雄原位保留，与三窗口一一对应
        pool.offerings[pool.offerings.index(hero_id)] = None
        # 招募的单位立即进入待命·可用(ADR-0005):阵营级、无位置,不自动编入部队。
        # 玩家可后续派遣到己方据点内的部队,或新建部队时任队长。
        self._to_standby(f, u, cooldown=0)
        return f"招募了 {u.name}，进入待命·可用"

    def _unmet_requires(self, faction_id: str, requires: list[str]) -> list[str]:
        """建筑 requires 列表中尚未满足的科技/文化名(返回中文名便于提示)。"""
        f = self.factions[faction_id]
        learned = f.tech_learned | f.culture_learned
        out: list[str] = []
        for rid in requires:
            if rid in learned:
                continue
            tdef = self.tech_defs.get(rid) or self.culture_defs.get(rid)
            out.append(tdef.get("name", rid) if tdef else rid)
        return out

    def action_learn_tech(self, faction_id: str, tech_id: str) -> str:
        """学习科技:校验前置已学 + 资源够 → 扣资源 → 加入 tech_learned。
        学习只扣资源,无即时战斗/经济效果(通过建造门控间接生效)。
        """
        return self._learn_tree(faction_id, tech_id, "tech")

    def action_learn_culture(self, faction_id: str, culture_id: str) -> str:
        """学习文化:同 action_learn_tech,记录到 culture_learned。"""
        return self._learn_tree(faction_id, culture_id, "culture")

    def _learn_tree(self, faction_id: str, item_id: str, kind: str) -> str:
        f = self.factions[faction_id]
        defs = self.tech_defs if kind == "tech" else self.culture_defs
        learned = f.tech_learned if kind == "tech" else f.culture_learned
        label = "科技" if kind == "tech" else "文化"
        idef = defs.get(item_id)
        if not idef:
            return f"失败:未知{label}"
        if item_id in learned:
            return f"已学习过:{idef.get('name', item_id)}"
        prereqs = idef.get("prereqs", [])
        all_learned = f.tech_learned | f.culture_learned
        missing = [p for p in prereqs if p not in all_learned]
        if missing:
            names = []
            for p in missing:
                pdef = self.tech_defs.get(p) or self.culture_defs.get(p)
                names.append(pdef.get("name", p) if pdef else p)
            return f"失败:前置未满足({', '.join(names)})"
        cost = idef.get("cost", {})
        if not f.resources.can_afford(cost):
            return f"失败:资源不足,无法学习 {idef.get('name', item_id)}"
        f.resources.pay(cost, source=SOURCE_BUILD, building=idef.get("name", item_id))
        learned.add(item_id)
        return f"学习了 {idef.get('name', item_id)}"

    def action_recruit_unit(self, faction_id: str, unit_type_id: str) -> str:
        """招募普通兵(B1):全局存在性 + 资源 → make_unit → 待命池(cooldown=0)。

        全局存在性:任一己方据点 sh.buildings 含该兵种对应的 recruit 建筑
        (building def 的 recruits 含 unit_type_id);不必在招募据点建造。
        校验 unit_types 的 recruit_cost,资源够 → pay → make_unit → _to_standby。
        招募建筑本身是否可建由科技/文化门控(action_build requires)把关,此处只查存在。
        """
        f = self.factions[faction_id]
        # 1. 找到 recruits 含 unit_type_id 的建筑 def(及其 id)
        recruiting_bid = None
        recruiting_bdef = None
        for bid, bdef in self.building_defs.items():
            if unit_type_id in bdef.get("recruits", []):
                recruiting_bid = bid
                recruiting_bdef = bdef
                break
        if recruiting_bdef is None:
            return f"失败:无招募 {unit_type_id} 的建筑定义"
        # 2. 全局存在性:任一己方据点含该建筑 type_id
        has_building = any(
            any(b.type_id == recruiting_bid for b in sh.buildings)
            for sid in f.stronghold_ids
            for sh in [self.map.strongholds.get(sid)] if sh
        )
        if not has_building:
            return f"失败:需先建造 {recruiting_bdef.get('name', '招募建筑')}"
        # 3. 兵种定义与招募成本
        ut = self.unit_type_defs.get(unit_type_id)
        if ut is None:
            return f"失败:未知兵种 {unit_type_id}"
        cost = ut.recruit_cost
        if not f.resources.can_afford(cost):
            return f"失败:资源不足,无法招募 {ut.name}"
        f.resources.pay(cost, source=SOURCE_RECRUIT, building=ut.name)
        u = self.make_unit(unit_type_id)
        # 招后进待命·可用(cooldown=0),阵营级无位置(ADR-0005)。
        self._to_standby(f, u, cooldown=0)
        return f"招募了 {u.name},进入待命·可用"

    def action_move(self, faction_id: str, army_id: str, to_node: str) -> str:
        f = self.factions[faction_id]
        army = self.armies.get(army_id)
        if not army or army.owner != faction_id:
            return "失败:无此部队"
        if army.node_id == to_node:
            return "失败:已在目标结点"
        if to_node not in self.map.neighbors(army.node_id):
            return "失败:目标结点不相邻"
        army.node_id = to_node
        for uid in army.grid:
            if uid and uid in self.unit_index:
                self.unit_index[uid].node_id = to_node
        return f"{army.name} 移动到 {self.map.node_name(to_node)}"

    def action_move_attack(self, faction_id: str, army_id: str, to_node: str) -> str:
        """移动到邻接结点;若该结点有敌方部队则触发战斗。

        占领机制(驻军系统已废除):据点无己方部队驻守时,进攻方进入即易主(无战斗);
        有敌方部队驻守时,进攻方须先击败守方(守方获标志性建筑防御 buff),胜则据点易主。
        """
        f = self.factions[faction_id]
        army = self.armies.get(army_id)
        if not army or army.owner != faction_id:
            return "失败:无此部队"
        if army.has_acted_this_turn:
            return "失败:本部队本回合已行动"
        if to_node not in self.map.neighbors(army.node_id):
            return "失败:目标结点不相邻"
        # 移动过去
        from_node = army.node_id
        army.node_id = to_node
        for uid in army.grid:
            if uid and uid in self.unit_index:
                self.unit_index[uid].node_id = to_node
        # 检查目标结点是否有敌方部队
        target_sh = self.map.strongholds.get(to_node)
        defender_army: Army | None = None
        is_siege = False
        if target_sh and target_sh.owner not in (None, faction_id):
            is_siege = True
            # 找该据点的敌方部队
            for a in self.armies.values():
                if (a.node_id == to_node and a.owner == target_sh.owner
                        and not a.is_wiped(self.unit_index)):
                    defender_army = a
                    break
        # 野外小地点:遇敌方部队
        if not defender_army and to_node in self.map.minors:
            for a in self.armies.values():
                if (a.node_id == to_node and a.owner not in (None, faction_id)
                        and not a.is_wiped(self.unit_index)):
                    defender_army = a
                    break

        if defender_army is None:
            # 无防守部队:据点直接易主(驻军系统已废除,无守则直接占)
            if is_siege and target_sh:
                self._capture_stronghold(target_sh, faction_id)
                army.has_acted_this_turn = True
                cap_msg = ""
                if target_sh.is_capital:
                    self._on_capital_fallen(target_sh)
                return f"{army.name} 占领了 {target_sh.name}!"
            army.has_acted_this_turn = True
            return f"{army.name} 移动到 {self.map.node_name(to_node)}"

        # 开战
        result = self._do_battle(army, defender_army, from_node, is_siege,
                                  target_sh if is_siege else None)
        army.has_acted_this_turn = True
        return result

    def _do_battle(self, attacker: Army, defender: Army, from_node: str,
                  is_siege: bool, target_sh: Stronghold | None) -> str:
        # 收集修正
        a_terrain = self.map.minors[attacker.node_id].terrain if attacker.node_id in self.map.minors else None
        d_terrain = self.map.minors[defender.node_id].terrain if defender.node_id in self.map.minors else None
        cal = self.calendar
        a_mods = self.collect_army_mods(attacker, cal, a_terrain)
        d_mods = self.collect_army_mods(defender, cal, d_terrain)
        # 攻城 buff:据点守方获标志性建筑防御加成(弱 0%/中 10%/强 20% p_def)
        landmark = getattr(target_sh, "landmark", None) if (is_siege and target_sh) else None
        if landmark is not None:
            tier = getattr(landmark, "tier", "weak")
            buff_val = LANDMARK_DEFENSE_BUFF.get(tier, 0.0)
            if buff_val > 0:
                for u in defender.alive_units(self.unit_index):
                    d_mods.append(Modifier(ModifierSource.LANDMARK, landmark.name,
                                           u.id, "p_def", buff_val, op="pct"))
        all_mods = a_mods + d_mods
        # 策略
        skill_defs = self.defs.get("skills", {})
        strats: dict[str, UnitStrategy] = {}
        for u in attacker.alive_units(self.unit_index):
            strats[u.id] = build_default_formation(attacker, self.unit_index, skill_defs)[u.id]
        for u in defender.alive_units(self.unit_index):
            strats[u.id] = build_default_formation(defender, self.unit_index, skill_defs)[u.id]
        # 跑战斗
        aside = BattleSide(army=attacker, is_attacker=True, home_node=from_node,
                            units=attacker.alive_units(self.unit_index))
        dside = BattleSide(army=defender, is_attacker=False,
                           home_node=defender.node_id,
                           units=defender.alive_units(self.unit_index))
        result = run_battle(aside, dside, strats, all_mods, log_detail=False,
                            rng=random.Random(), skill_defs=skill_defs,
                            player_faction_id=self.player_id)
        # 处理结局
        msgs: list[str] = []
        if result.attacker_wiped:
            msgs.append(f"{attacker.name} 进攻失败,部队全灭")
        if result.defender_wiped:
            msgs.append(f"{defender.name} 被全灭")
        # 死亡经验:每个阵亡单位,把其等级数值作为 XP 发给击杀方所有存活单位
        self._award_death_xp(result, attacker, defender)
        if result.occupier_side == "attacker":
            # 进攻方占据结点
            if is_siege and target_sh:
                # 占领据点
                self._capture_stronghold(target_sh, attacker.owner)
                msgs.append(f"{attacker.name} 占领了 {target_sh.name}!")
                # 首都判定
                if target_sh.is_capital:
                    self._on_capital_fallen(target_sh)
            else:
                msgs.append(f"{attacker.name} 控制了 {self.map.node_name(attacker.node_id)}")
        elif result.occupier_side == "defender":
            msgs.append(f"{defender.name} 击退来犯之敌")
        else:
            # 200 tick 未分胜负:进攻方退回出发结点
            attacker.node_id = from_node
            for uid in attacker.grid:
                if uid and uid in self.unit_index:
                    self.unit_index[uid].node_id = from_node
            msgs.append(f"战斗未分胜负,{attacker.name} 退回 {self.map.node_name(from_node)}")
        # 清理全灭部队
        self._cleanup_wiped()
        return "、".join(msgs)

    def _capture_stronghold(self, sh: Stronghold, new_owner: str) -> None:
        old_owner = sh.owner
        sh.owner = new_owner
        # 转移据点归属列表(标志建筑随据点归属,原型不换类型)
        if old_owner and old_owner in self.factions:
            if sh.id in self.factions[old_owner].stronghold_ids:
                self.factions[old_owner].stronghold_ids.remove(sh.id)
        self.factions[new_owner].stronghold_ids.append(sh.id)
        self.log_msg(f"{sh.name} 由 {old_owner} 转归 {new_owner}")

    def _on_capital_fallen(self, capital: Stronghold) -> None:
        old_owner = None
        for fid, f in self.factions.items():
            if f.capital_id == capital.id:
                old_owner = fid
                break
        if not old_owner:
            return
        f = self.factions[old_owner]
        f.alive = False
        # 解散所有部队与英雄(装备回库·可用)
        for aid in list(f.army_ids):
            a = self.armies.get(aid)
            if a:
                for uid in a.grid:
                    if uid:
                        u = self.unit_index.get(uid)
                        if u:
                            self._release_artifacts(f, u)
                        self.unit_index.pop(uid, None)
                if aid in self.armies:
                    del self.armies[aid]
        # 清待命池(阵营灭亡,待命单位随之消亡)
        for uid in list(f.standby.keys()):
            u = self.unit_index.get(uid)
            if u:
                self._release_artifacts(f, u)
            self.unit_index.pop(uid, None)
        f.standby.clear()
        f.army_ids.clear()
        f.hero_ids.clear()
        self.log_msg(f"{f.name} 首都陷落,出局!所有部队解散。")
        # 胜负判定
        alive = [fid for fid, ff in self.factions.items() if ff.alive]
        if len(alive) == 1:
            self.winner = alive[0]
        elif self.player_id and self.factions[self.player_id].alive:
            # 玩家仍存活且只剩玩家+0或1个敌人
            enemies_alive = [fid for fid in alive if fid != self.player_id]
            if len(enemies_alive) == 0:
                self.winner = self.player_id

    def _cleanup_wiped(self) -> None:
        for a in list(self.armies.values()):
            if a.is_wiped(self.unit_index):
                # 部队全灭:解散(装备回库·可用)
                owner_f = self.factions.get(a.owner)
                for uid in list(a.grid):
                    if uid:
                        u = self.unit_index.get(uid)
                        if u and owner_f is not None:
                            self._release_artifacts(owner_f, u)
                        self.unit_index.pop(uid, None)
                if a.id in self.armies:
                    for f in self.factions.values():
                        if a.id in f.army_ids:
                            f.army_ids.remove(a.id)
                    del self.armies[a.id]

    def _award_death_xp(self, result, attacker: Army, defender: Army) -> None:
        """死亡经验:每个阵亡单位,击杀方所有存活单位各获得等同其等级数值的 XP。

        判定击杀方:阵亡单位属于哪一边,另一边的存活单位拿经验。
        (若双方都有阵亡,各自按对方阵亡单位的等级获得。)
        """
        att_ids = {u.id for u in attacker.alive_units(self.unit_index)}
        def_ids = {u.id for u in defender.alive_units(self.unit_index)}
        for uid in result.casualties:
            dead = self.unit_index.get(uid)
            if not dead:
                continue
            xp = getattr(dead, "level", 1)
            if xp <= 0:
                continue
            # 阵亡方是防守方 -> 进攻方存活单位得经验;反之亦然
            if uid in def_ids or (uid in {x.id for x in defender.units(self.unit_index)}):
                gainers = [u for u in attacker.alive_units(self.unit_index)]
            else:
                gainers = [u for u in defender.alive_units(self.unit_index)]
            for g in gainers:
                levels = g.gain_xp(xp)
                if levels > 0:
                    self.log_msg(f"{g.name} 获 {xp} 经验,升到 Lv{g.level}")

    # ---------- 玩家事件 ----------
    def maybe_trigger_event(self, faction: Faction) -> None:
        """回合开始有概率触发事件(玩家阵营)。"""
        if faction.is_ai:
            return
        if random.random() < 0.4 and self.event_defs:
            self.pending_event = random_event(self.event_defs)

    def resolve_event(self, option_index: int) -> str:
        ev = self.pending_event
        if not ev or option_index >= len(ev.options):
            return "无事件"
        opt = ev.options[option_index]
        f = self.factions[self.player_id]
        result = apply_option(opt, f.resources, f.belief)
        self.pending_event = None
        return f"事件【{ev.title}】选择:{opt.label} -> {result}"

    # ---------- 胜负 ----------
    def check_winner(self) -> None:
        if self.winner:
            return
        alive = [fid for fid, f in self.factions.items() if f.alive]
        if len(alive) <= 1 and alive:
            self.winner = alive[0]

    def is_over(self) -> bool:
        return self.winner is not None

    # ---------- 存档读档(B5) ----------
    # 完整 JSON 序列化:所有跨对象链接均为字符串 id,可直接序列化;
    # set(tags/tech_learned/culture_learned/statuses keys)→list,还原时转回 set。
    # 存档始终写 pydemo/saves/save001.dat(单存档);Game() 重载定义后重建对象图。

    def snapshot(self) -> dict:
        """全状态 JSON 化为可序列化 dict。"""
        return {
            "version": 1,
            "day": self.calendar.day,
            "player_id": self.player_id,
            "winner": self.winner,
            "log": list(self.log),
            "counters": {"army": self._army_counter, "unit": self._unit_counter},
            "pending_event_id": self.pending_event.id if self.pending_event else None,
            "map": {
                "strongholds": {sid: self._stronghold_to_dict(s)
                                for sid, s in self.map.strongholds.items()},
                "minors": {mid: {"id": m.id, "name": m.name, "terrain": m.terrain,
                                 "x": m.x, "y": m.y}
                           for mid, m in self.map.minors.items()},
                "adj": {a: list(b) for a, b in self.map.adj.items()},
            },
            "factions": {fid: self._faction_to_dict(f)
                         for fid, f in self.factions.items()},
            "armies": {aid: self._army_to_dict(a)
                       for aid, a in self.armies.items()},
            "units": {uid: self._unit_to_dict(u)
                      for uid, u in self.unit_index.items()},
        }

    @staticmethod
    def _building_to_dict(b: Building) -> dict:
        return {"id": b.id, "type_id": b.type_id, "name": b.name,
                "produces": dict(b.produces), "tier": b.tier}

    @staticmethod
    def _building_from_dict(d: dict) -> Building:
        return Building(id=d["id"], type_id=d["type_id"], name=d["name"],
                        produces=dict(d.get("produces", {})),
                        tier=d.get("tier", ""))

    def _stronghold_to_dict(self, sh: Stronghold) -> dict:
        return {
            "id": sh.id, "name": sh.name, "size": sh.size, "owner": sh.owner,
            "is_capital": sh.is_capital,
            "landmark": self._building_to_dict(sh.landmark) if sh.landmark else None,
            "buildings": [self._building_to_dict(b) for b in sh.buildings],
            "stationed_army_id": sh.stationed_army_id,
            "x": sh.x, "y": sh.y,
        }

    def _faction_to_dict(self, f: Faction) -> dict:
        return {
            "id": f.id, "name": f.name, "is_ai": f.is_ai,
            "resources": dict(f.resources.amounts),
            "belief": dict(f.belief.values),
            "capital_id": f.capital_id,
            "army_ids": list(f.army_ids),
            "hero_ids": list(f.hero_ids),
            "stronghold_ids": list(f.stronghold_ids),
            "standby": dict(f.standby),
            "inventory": dict(f.inventory),
            "recruitment_pools": {
                sid: {"stronghold_id": p.stronghold_id,
                      "offerings": list(p.offerings), "refresh_day": p.refresh_day}
                for sid, p in f.recruitment_pools.items()},
            "tech_learned": list(f.tech_learned),
            "culture_learned": list(f.culture_learned),
            "alive": f.alive,
        }

    @staticmethod
    def _army_to_dict(a: Army) -> dict:
        return {"id": a.id, "name": a.name, "captain_id": a.captain_id,
                "grid": list(a.grid), "owner": a.owner, "node_id": a.node_id,
                "has_acted_this_turn": a.has_acted_this_turn,
                "supply": a.supply, "supply_max": a.supply_max}

    @staticmethod
    def _unit_to_dict(u: Unit) -> dict:
        return {
            "id": u.id, "type_id": u.type_id, "name": u.name,
            "tags": list(u.tags), "base": dict(u.base),
            "artifacts": list(u.artifacts), "is_hero": u.is_hero,
            "skills": list(u.skills), "granted_skills": list(u.granted_skills),
            "cur_hp": u.cur_hp, "army_id": u.army_id,
            "cur_ap": u.cur_ap, "cur_pp": u.cur_pp, "cur_mana": u.cur_mana,
            "atb": u.atb, "alive": u.alive,
            "statuses": dict(u.statuses), "node_id": u.node_id,
            "level": u.level, "xp": u.xp, "growth": dict(u.growth),
        }

    @classmethod
    def restore(cls, data: dict) -> "Game":
        """从 snapshot() 产生的 dict 反序列化重建 Game 对象图。
        重新加载定义(definitions),按 id 重建引用;list→set 还原 tags/学习记录。
        """
        g = cls()  # 重新加载定义;seed=None 不重置全局 random
        g.calendar = Calendar(day=data["day"])
        g.player_id = data.get("player_id")
        g.winner = data.get("winner")
        g.log = list(data.get("log", []))
        counters = data.get("counters", {})
        g._army_counter = counters.get("army", 0)
        g._unit_counter = counters.get("unit", 0)
        g.pending_event = None
        # 地图
        m = data["map"]
        for sid, sd in m["strongholds"].items():
            sh = Stronghold(
                id=sd["id"], name=sd["name"], size=sd["size"],
                owner=sd["owner"], is_capital=sd["is_capital"],
                landmark=cls._building_from_dict(sd["landmark"]) if sd.get("landmark") else None,
                buildings=[cls._building_from_dict(b) for b in sd.get("buildings", [])],
                stationed_army_id=sd.get("stationed_army_id"),
                x=sd.get("x", 0), y=sd.get("y", 0))
            g.map.add_stronghold(sh)
        for mid, md in m["minors"].items():
            g.map.add_minor(MinorLocation(
                id=md["id"], name=md["name"], terrain=md["terrain"],
                x=md.get("x", 0), y=md.get("y", 0)))
        for a, nbrs in m.get("adj", {}).items():
            g.map.adj[a] = list(nbrs)   # 直接还原邻接表(保留顺序,connect 会重排)
        # 单位先建(army/faction 引用 unit id)
        for uid, ud in data["units"].items():
            # __post_init__ 会在 cur_hp<=0 时重置为 base.hp,故先用占位 cur_hp 再覆盖
            u = Unit(
                id=ud["id"], type_id=ud["type_id"], name=ud["name"],
                tags=set(ud["tags"]), base=dict(ud["base"]),
                artifacts=list(ud["artifacts"]), is_hero=ud["is_hero"],
                skills=list(ud["skills"]),
                granted_skills=list(ud.get("granted_skills", [])),
                cur_hp=1.0, army_id=ud.get("army_id"),
                cur_ap=ud.get("cur_ap", 0), cur_pp=ud.get("cur_pp", 0),
                cur_mana=ud.get("cur_mana", 0), atb=ud.get("atb", 0),
                alive=ud.get("alive", True),
                statuses=dict(ud.get("statuses", {})),
                node_id=ud.get("node_id"),
                level=ud.get("level", 1), xp=ud.get("xp", 0),
                growth=dict(ud.get("growth", {})),
            )
            u.cur_hp = ud["cur_hp"]   # 覆盖占位,保留真实(可能 <=0 的)血量
            g.unit_index[u.id] = u
        # 阵营
        for fid, fd in data["factions"].items():
            f = Faction(id=fd["id"], name=fd["name"], is_ai=fd["is_ai"])
            f.resources = Resources(amounts=dict(fd["resources"]))
            f.belief = Belief(values=dict(fd["belief"]))
            f.capital_id = fd.get("capital_id")
            f.army_ids = list(fd["army_ids"])
            f.hero_ids = list(fd["hero_ids"])
            f.stronghold_ids = list(fd["stronghold_ids"])
            f.standby = dict(fd["standby"])
            f.inventory = dict(fd["inventory"])
            for sid, pd in fd.get("recruitment_pools", {}).items():
                pool = RecruitmentPool(stronghold_id=pd["stronghold_id"])
                pool.offerings = list(pd["offerings"])
                pool.refresh_day = pd["refresh_day"]
                f.recruitment_pools[sid] = pool
            f.tech_learned = set(fd.get("tech_learned", []))
            f.culture_learned = set(fd.get("culture_learned", []))
            f.alive = fd.get("alive", True)
            g.factions[fid] = f
        # 部队
        for aid, ad in data["armies"].items():
            a = Army(id=ad["id"], name=ad["name"],
                     captain_id=ad.get("captain_id"),
                     grid=list(ad["grid"]), owner=ad.get("owner"),
                     node_id=ad.get("node_id"),
                     has_acted_this_turn=ad.get("has_acted_this_turn", False),
                     supply=ad.get("supply", 10),
                     supply_max=ad.get("supply_max", 10))
            g.armies[aid] = a
        # 待处理事件(按 id 从定义重建)
        pid = data.get("pending_event_id")
        if pid:
            g.pending_event = next((e for e in g.event_defs if e.id == pid), None)
        return g

