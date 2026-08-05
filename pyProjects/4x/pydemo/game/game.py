"""
Game:核心编排。

把所有子系统串成可跑的一局:日历、地图、阵营、部队、单位、修正收集、
移动、战斗、占领、招募、建造、事件、胜负。

逻辑与交互分离:本类只暴露动作接口与查询;CLI/AI 调用之。
"""
from __future__ import annotations
import random
from dataclasses import dataclass, field
from typing import Any

from .data_loader import load_definitions
from .time_system import Calendar
from .economy import Resources, Belief, RESOURCE_TYPES, RESOURCE_CN, BELIEF_DIMS, BELIEF_CN
from .map_system import GameMap, Stronghold, MinorLocation, Building, SIZE_SLOTS
from .unit import (Unit, UnitType, Artifact, load_unit_types, load_artifacts,
                   ATTR_BOUNDS, ATTR_CN, TAG_CN, MAJOR_TAGS)
from .hero import (HeroDef, load_hero_defs, make_hero_unit, meets_belief_req,
                   describe_req, RecruitmentPool)
from .army import Army, empty_army, row_of, col_of, ROWS, ROW_CN, GRID_SIZE
from .synergy import load_synergies, collect_synergy_mods
from .modifier import (Modifier, ModifierCollection, compute_attribute, ModifierSource)
from .effects import (Effect, build_skill_effects, collect_passive_modifiers)
from .formation import UnitStrategy, build_default_formation, choose_target_with_slots
from .battle import BattleSide, BattleResult, run_battle, effective_attrs
from .events import GameEvent, load_events, apply_option, random_event
from .faction import Faction


def cn_building(bdef: dict) -> str:
    return bdef.get("name", bdef.get("id", "?"))


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

    # ---------- 装配 ----------
    def add_faction(self, fid: str, name: str, is_ai: bool = False) -> Faction:
        f = Faction(id=fid, name=name, is_ai=is_ai)
        self.factions[fid] = f
        if not is_ai and self.player_id is None:
            self.player_id = fid
        return f

    def make_unit(self, type_id: str) -> Unit:
        ut = self.unit_type_defs[type_id]
        u = Unit(
            id=self.new_id("u"),
            type_id=type_id, name=ut.name, tags=set(ut.tags),
            base=dict(ut.base),
        )
        u.grant_tags_from_artifacts(self.artifact_defs)
        self.unit_index[u.id] = u
        return u

    def make_hero(self, hero_def_id: str) -> Unit:
        hdef = self.hero_defs[hero_def_id]
        u = make_hero_unit(hdef)
        u.id = self.new_id("u")
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
        army.captain_id = hero_unit.id
        if hero_unit.army_id != army.id:
            # 加入部队(若有空位)
            if not army.can_add(hero_unit, self.unit_index):
                # 强制放第一个空位即使超规模?不,放不下则失败
                return False
            army.add(hero_unit, self.unit_index)
        return True

    def _try_fill_captain(self, army: Army) -> bool:
        """队长空缺时,从同据点英雄指派接任;无则解散。"""
        if army.captain_id and army.captain_id in self.unit_index:
            return True
        # 同据点的无部队英雄
        for u in self.unit_index.values():
            if u.is_hero and u.alive and u.node_id == army.node_id and u.army_id is None:
                if self.set_captain(army, u):
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
        # 4. 技能/被动
        for sid in unit.skills:
            sdef = None
            # 技能定义来自 building/hero 数据中的 skills;原型在 hero_defs 里
            skill_data = self._skill_def(sid)
            if not skill_data:
                continue
            effs = build_skill_effects(skill_data)
            army_tags_count = self._army_tags_count(army) if army else {}
            mods.extend(collect_passive_modifiers(effs, unit.id, unit.tags,
                                                  army_tags_count,
                                                  ModifierSource.SKILL, sid))
        # 5. 装备(神器)
        for aid in unit.artifacts:
            art = self.artifact_defs.get(aid)
            if not art:
                continue
            effs = build_skill_effects({"effects": art.effects})
            army_tags_count = self._army_tags_count(army) if army else {}
            mods.extend(collect_passive_modifiers(effs, unit.id, unit.tags,
                                                  army_tags_count,
                                                  ModifierSource.ARTIFACT, aid))
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

    # ---------- 据点驻军 ----------
    def make_garrison(self, stronghold: Stronghold) -> Army:
        """根据标志建筑类型生成据点驻军(由建筑决定编队,玩家不可编辑)。"""
        gtype = stronghold.landmark_type   # weak/medium/strong
        # 驻军编队:弱=2 步兵;中=3 步兵+1 弓兵;强=4 步兵+2 弓兵+1 骑兵
        comps = {
            "weak": [("infantry", 2)],
            "medium": [("infantry", 3), ("archer", 1)],
            "strong": [("infantry", 4), ("archer", 2), ("cavalry", 1)],
        }.get(gtype, [("infantry", 2)])
        aid = self.new_army_id()
        army = Army(id=aid, name=f"{stronghold.name}驻军", owner=stronghold.owner,
                    node_id=stronghold.id, is_garrison=True)
        # 按角色自动落位(近战前排、远程后排),不做规模检查
        for type_id, count in comps:
            for _ in range(count):
                u = self.make_unit(type_id)
                army.place_for_garrison(u, self.unit_index)
        # 驻军设一个虚拟队长(取前排第一个单位,提其 will 以容纳全队)
        for uid in army.grid:
            if uid:
                army.captain_id = uid
                self.unit_index[uid].base["will"] = 99
                break
        self.armies[aid] = army
        return army

    # ---------- 回合驱动 ----------
    def start_turn(self, faction: Faction) -> None:
        """回合开始:事件触发(玩家阵营)、刷新招募池检查、驻军回血。"""
        # 驻军回血补兵(未全灭)
        for sid in list(faction.stronghold_ids):
            sh = self.map.strongholds.get(sid)
            if not sh:
                continue
            # 找该据点的驻军
            for a in self.armies.values():
                if a.is_garrison and a.node_id == sid and a.owner == faction.id:
                    if not a.is_wiped(self.unit_index):
                        for u in a.alive_units(self.unit_index):
                            u.cur_hp = min(u.base.get("hp", 1),
                                           u.cur_hp + u.base.get("hp", 1) * 0.1)
                        # 补兵:原型简化为不补新单位,仅回血
        # 招募池刷新(每 14 天)
        for sid in list(faction.stronghold_ids):
            pool = faction.recruitment_pools.get(sid)
            if not pool:
                pool = RecruitmentPool(stronghold_id=sid)
                faction.recruitment_pools[sid] = pool
                pool.refresh(list(self.hero_defs.keys()), self.calendar.day)
            elif self.calendar.day >= pool.refresh_day:
                pool.refresh(list(self.hero_defs.keys()), self.calendar.day)

    def end_turn_advance(self) -> None:
        """回合结束推进时间。"""
        self.calendar.advance()

    # ---------- 经济 ----------
    def tick_economy(self, faction: Faction) -> None:
        """产出建筑产出资源 + 建造推进。"""
        for sid in list(faction.stronghold_ids):
            sh = self.map.strongholds.get(sid)
            if not sh:
                continue
            gained = sh.tick_builds()
            for k, v in gained.items():
                faction.resources.add(k, v)
        # 补给补充:在己方据点的部队
        for aid in list(faction.army_ids):
            army = self.armies.get(aid)
            if not army or army.is_garrison:
                continue
            if army.node_id in faction.stronghold_ids:
                need = army.supply_max - army.supply
                if need > 0 and faction.resources.get("food") >= need:
                    faction.resources.add("food", -need)
                    army.supply = army.supply_max
                elif need > 0:
                    give = min(need, faction.resources.get("food"))
                    faction.resources.add("food", -give)
                    army.supply += give
        # 补给消耗:在小地点的部队
        for aid in list(faction.army_ids):
            army = self.armies.get(aid)
            if not army or army.is_garrison:
                continue
            if army.node_id in self.map.minors:
                army.supply -= 1
                if army.supply <= 0:
                    army.supply = 0
                    for u in army.alive_units(self.unit_index):
                        u.cur_hp = max(0, u.cur_hp - u.base.get("hp", 1) * 0.05)

    # ---------- 动作 ----------
    def action_build(self, faction_id: str, stronghold_id: str, building_id: str) -> str:
        f = self.factions[faction_id]
        sh = self.map.strongholds.get(stronghold_id)
        if not sh or sh.owner != faction_id:
            return "失败:据点不归你所有"
        if sh.free_slots() <= 0:
            return "失败:据点无空槽"
        bdef = self.building_defs.get(building_id)
        if not bdef:
            return "失败:未知建筑"
        cost = bdef.get("cost", {})
        if not f.resources.can_afford(cost):
            return "失败:资源不足"
        f.resources.pay(cost)
        turns = bdef.get("build_turns", 1)
        # 领主加速
        lord = f.lords.get(stronghold_id)
        if lord:
            turns = max(1, turns - 1)
        b = Building(id=f"b{random.randint(1000,9999)}", type_id=building_id,
                     name=cn_building(bdef),
                     produces=bdef.get("produces", {}) if bdef.get("kind") == "produce" else {},
                     build_turns_left=turns)
        sh.add_building(b)
        return f"已在 {sh.name} 建造 {b.name}(需{turns}回合)"

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
        f.resources.pay(hdef.recruit_cost)
        u = self.make_hero(hero_id)
        u.node_id = stronghold_id
        f.hero_ids.append(u.id)
        # 招募后该槽位置 None（不压缩），其余英雄原位保留，与三窗口一一对应
        pool.offerings[pool.offerings.index(hero_id)] = None
        # 英雄进入聚贤庄（hall_of_worthies）待命，不自动编入部队。
        # 玩家可后续将其指派为据点领主，或新建部队时任队长。
        # 保留 u.node_id=stronghold_id 使其暂留于招募据点，供指派/建队流程按
        # 「该据点的无部队英雄」检索（据点界面 _candidates_for、部队界面 _new_army）。
        f.hall_of_worthies[u.id] = 0
        return f"招募了 {u.name}，进入聚贤庄待命（可指派至据点）"

    def action_move(self, faction_id: str, army_id: str, to_node: str) -> str:
        f = self.factions[faction_id]
        army = self.armies.get(army_id)
        if not army or army.owner != faction_id or army.is_garrison:
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
        """移动到邻接结点;若该结点有敌方部队则触发战斗。"""
        f = self.factions[faction_id]
        army = self.armies.get(army_id)
        if not army or army.owner != faction_id or army.is_garrison:
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
        # 检查目标结点是否有敌方/中立据点或敌方部队
        target_sh = self.map.strongholds.get(to_node)
        defender_army: Army | None = None
        is_siege = False
        # 1. 若是据点且有玩家驻军(敌方),先打玩家驻军
        if target_sh and target_sh.owner not in (None, faction_id):
            is_siege = True
            # 找该据点的敌方非驻军部队
            for a in self.armies.values():
                if (a.node_id == to_node and a.owner == target_sh.owner
                        and not a.is_garrison and not a.is_wiped(self.unit_index)):
                    defender_army = a
                    break
        # 2. 若是据点无玩家驻军,或玩家驻军已全灭,打据点驻军
        # 3. 野外小地点:遇敌方部队
        if not defender_army and to_node in self.map.minors:
            for a in self.armies.values():
                if (a.node_id == to_node and a.owner not in (None, faction_id)
                        and not a.is_garrison and not a.is_wiped(self.unit_index)):
                    defender_army = a
                    break

        if defender_army is None and is_siege:
            # 据点无玩家驻军:打据点驻军
            garrison = self._find_garrison(to_node)
            if garrison:
                defender_army = garrison

        if defender_army is None:
            army.has_acted_this_turn = True
            return f"{army.name} 移动到 {self.map.node_name(to_node)}"

        # 开战
        result = self._do_battle(army, defender_army, from_node, is_siege,
                                  target_sh if is_siege else None)
        army.has_acted_this_turn = True
        return result

    def _find_garrison(self, stronghold_id: str) -> Army | None:
        for a in self.armies.values():
            if a.is_garrison and a.node_id == stronghold_id and not a.is_wiped(self.unit_index):
                return a
        return None

    def _do_battle(self, attacker: Army, defender: Army, from_node: str,
                  is_siege: bool, target_sh: Stronghold | None) -> str:
        # 收集修正
        a_terrain = self.map.minors[attacker.node_id].terrain if attacker.node_id in self.map.minors else None
        d_terrain = self.map.minors[defender.node_id].terrain if defender.node_id in self.map.minors else None
        cal = self.calendar
        a_mods = self.collect_army_mods(attacker, cal, a_terrain)
        d_mods = self.collect_army_mods(defender, cal, d_terrain)
        # 攻城 buff:据点有玩家驻军时,防守方(玩家驻军)获小幅 buff
        if is_siege and target_sh:
            buff_val = {"weak": 0.05, "medium": 0.10, "strong": 0.15}.get(target_sh.landmark_type, 0.05)
            for u in defender.alive_units(self.unit_index):
                d_mods.append(Modifier(ModifierSource.LANDMARK, target_sh.landmark_type,
                                       u.id, "p_def", buff_val, op="pct"))
        all_mods = a_mods + d_mods
        # 策略
        strats: dict[str, UnitStrategy] = {}
        for u in attacker.alive_units(self.unit_index):
            strats[u.id] = build_default_formation(attacker, self.unit_index)[u.id]
        for u in defender.alive_units(self.unit_index):
            strats[u.id] = build_default_formation(defender, self.unit_index)[u.id]
        # 跑战斗
        aside = BattleSide(army=attacker, is_attacker=True, home_node=from_node,
                            units=attacker.alive_units(self.unit_index))
        dside = BattleSide(army=defender, is_attacker=False,
                           units=defender.alive_units(self.unit_index))
        result = run_battle(aside, dside, strats, all_mods, log_detail=False)
        # 处理结局
        msgs: list[str] = []
        if result.attacker_wiped:
            msgs.append(f"{attacker.name} 进攻失败,部队全灭")
        if result.defender_wiped:
            msgs.append(f"{defender.name} 被全灭")
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
        # 转移标志建筑为进攻方版本(同档位,原型不换类型)
        # 转移据点归属列表
        if old_owner and old_owner in self.factions:
            if sh.id in self.factions[old_owner].stronghold_ids:
                self.factions[old_owner].stronghold_ids.remove(sh.id)
        self.factions[new_owner].stronghold_ids.append(sh.id)
        # 清除旧驻军,生成新驻军
        for a in list(self.armies.values()):
            if a.is_garrison and a.node_id == sh.id:
                # 解放旧驻军单位
                for uid in a.grid:
                    if uid:
                        self.unit_index.pop(uid, None)
                del self.armies[a.id]
        self.make_garrison(sh)
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
        # 解散所有部队与英雄
        for aid in list(f.army_ids):
            a = self.armies.get(aid)
            if a:
                for uid in a.grid:
                    if uid:
                        self.unit_index.pop(uid, None)
                if aid in self.armies:
                    del self.armies[aid]
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
            if a.is_wiped(self.unit_index) and not a.is_garrison:
                # 玩家部队全灭:解散
                for uid in list(a.grid):
                    if uid:
                        self.unit_index.pop(uid, None)
                if a.id in self.armies:
                    for f in self.factions.values():
                        if a.id in f.army_ids:
                            f.army_ids.remove(a.id)
                    del self.armies[a.id]

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
