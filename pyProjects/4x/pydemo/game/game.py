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
from .economy import (Resources, Belief, RESOURCE_TYPES, RESOURCE_CN, BELIEF_DIMS,
                      BELIEF_CN, SOURCE_BUILD, SOURCE_MAINT, SOURCE_RECRUIT,
                      SOURCE_TRAIN, SOURCE_SUPPLY, SOURCE_INIT)
from .map_system import GameMap, Stronghold, MinorLocation, Building
from .unit import (Unit, UnitType, Artifact, load_unit_types, load_artifacts,
                   ArtifactInstance, ARTIFACT_AVAILABLE, ARTIFACT_UNAVAILABLE,
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
        self._artifact_counter = 0   # 装备实例 id 计数(ADR-0007)
        # 装备实例索引:instance_id -> ArtifactInstance(便于 O(1) 查询单位装备)
        self._artifact_index: dict[str, ArtifactInstance] = {}

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

    def new_artifact_id(self) -> str:
        """装备实例唯一 id(ADR-0007)。"""
        self._artifact_counter += 1
        return f"art_{self._artifact_counter}"

    def make_artifact_instance(self, def_id: str, owner: str,
                               state: str = ARTIFACT_AVAILABLE,
                               cooldown: int = 0) -> ArtifactInstance:
        """创建一件装备实例,登记进 owner 阵营仓库 + 全局索引(ADR-0007)。

        用于场景初始化与(后续可能的)装备获取动作。仓库上限 200,超则不建(返回 None)。
        """
        f = self.factions.get(owner)
        if f is None:
            return None  # type: ignore[return-value]
        if len(f.inventory) >= 200:
            return None  # type: ignore[return-value]
        if def_id not in self.artifact_defs:
            return None  # type: ignore[return-value]
        inst = ArtifactInstance(id=self.new_artifact_id(), def_id=def_id,
                                owner=owner, state=state, cooldown=cooldown)
        f.inventory.append(inst)
        self._artifact_index[inst.id] = inst
        return inst

    def artifact_def_of(self, instance_id: str) -> Artifact | None:
        """装备实例 -> 其 Artifact 定义(None 若无)。"""
        inst = self._artifact_index.get(instance_id)
        if not inst:
            return None
        return self.artifact_defs.get(inst.def_id)

    def artifact_instance(self, instance_id: str) -> ArtifactInstance | None:
        return self._artifact_index.get(instance_id)

    def _instance_in_faction_inventory(self, inst: ArtifactInstance,
                                       faction: Faction) -> bool:
        return inst in faction.inventory

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
            growth=dict(ut.growth),
        )
        u.grant_tags_from_artifacts(self._artifact_index, self.artifact_defs)
        self.unit_index[u.id] = u
        return u

    def make_hero(self, hero_def_id: str) -> Unit:
        hdef = self.hero_defs[hero_def_id]
        u = make_hero_unit(hdef)
        u.id = self.new_id("u")
        u.grant_tags_from_artifacts(self._artifact_index, self.artifact_defs)
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

    def _tick_inventory(self, faction: Faction) -> None:
        """回合开始:仓库内不可用装备冷却 -1,到 0 转可用(ADR-0007)。"""
        for inst in faction.inventory:
            if inst.is_unavailable() and inst.cooldown > 0:
                inst.cooldown -= 1
                if inst.cooldown <= 0:
                    inst.state = ARTIFACT_AVAILABLE
                    inst.cooldown = 0

    def action_deploy(self, faction_id: str, army_id: str, unit_id: str,
                      slot: int | None = None) -> str:
        """上场:把待命·可用单位派进己方据点内的一支部队(§5)。

        约束:单位必须在待命池且冷却已归零(可用);目标部队必须为本阵营非驻军部队,
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
        if not army or army.owner != faction_id or army.is_garrison:
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
        if not army or army.owner != faction_id or army.is_garrison:
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
                     instance_id: str, slot: int) -> str:
        """装备一件仓库内可用装备到指定槽位 0..2(§3 装备栏,ADR-0007)。

        装备改为实例模型:instance_id 必须为本阵营仓库内、在库且可用(未装备、
        冷却已归零)的实例。目标单位可为本阵营任意单位,不要求其在据点内(玩家可将
        可用装备装备给任意单位)。装备到已占用槽位会先把旧装备卸下(旧装备若其单位
        不在己方据点则进不可用冷却,见 action_unequip 规则)。槽位越界/实例不可用则失败。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        u = self.unit_index.get(unit_id)
        if not u:
            return "失败:无此单位"
        if self._unit_owner(u) != faction_id:
            return "失败:单位不归你"
        if not (0 <= slot < 3):
            return "失败:槽位越界"
        inst = self._artifact_index.get(instance_id)
        if not inst or not self._instance_in_faction_inventory(inst, f):
            return "失败:无此装备实例"
        if not inst.is_available():
            if inst.is_equipped():
                return "失败:装备已被装备"
            return "失败:装备不可用(冷却中)"
        art = self.artifact_defs.get(inst.def_id)
        if not art:
            return "失败:未知装备定义"
        # 槽位已占用:先把旧实例卸下(走 unequip 规则)
        while len(u.artifacts) <= slot:
            u.artifacts.append(None)  # type: ignore[arg-type]
        old_iid = u.artifacts[slot]
        if old_iid is not None:
            old_msg = self._unequip_instance(f, u, slot, suppress_log=True)
            if old_msg.startswith("失败"):
                return old_msg   # 理论上不会失败,防御
        # 装上新实例
        u.artifacts[slot] = instance_id
        inst.equipped_by = u.id
        inst.state = ARTIFACT_AVAILABLE
        inst.cooldown = 0
        self._recompute_unit_tags(u)
        return f"{u.name} 装备了 {art.name}"

    def action_unequip(self, faction_id: str, unit_id: str, slot: int) -> str:
        """卸下单位指定槽位 0..2 的装备(ADR-0007)。

        可在单位界面(满槽按回车)或仓库界面(X 键)调用。卸下规则:装备的单位当前
        在己方据点内则实例回到仓库·可用(冷却 0);不在己方据点则进不可用,5 回合后
        恢复可用(与单位下场冷却同理,ADR-0005)。槽位空则失败。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        u = self.unit_index.get(unit_id)
        if not u:
            return "失败:无此单位"
        if self._unit_owner(u) != faction_id:
            return "失败:单位不归你"
        if not (0 <= slot < 3):
            return "失败:槽位越界"
        if slot >= len(u.artifacts) or u.artifacts[slot] is None:
            return "失败:该槽位无装备"
        return self._unequip_instance(f, u, slot)

    def _unequip_instance(self, f: Faction, u: Unit, slot: int,
                         suppress_log: bool = False) -> str:
        """从单位槽位卸下一件装备实例,按单位是否在己方据点决定冷却。

        suppress_log=True 时不写 log(equip 替换旧装备时由调用方统一报消息)。
        """
        iid = u.artifacts[slot]
        inst = self._artifact_index.get(iid) if iid is not None else None
        if inst is None:
            return "失败:该槽位无装备"
        art = self.artifact_defs.get(inst.def_id)
        name = art.name if art else iid
        u.artifacts[slot] = None
        inst.equipped_by = None
        # 装备的单位当前所在部队
        army = self.armies.get(u.army_id) if u.army_id else None
        in_stronghold = (army is not None and not army.is_garrison
                         and army.node_id in f.stronghold_ids)
        if in_stronghold:
            inst.state = ARTIFACT_AVAILABLE
            inst.cooldown = 0
            msg = f"{u.name} 卸下了 {name}(回库·可用)"
        else:
            inst.state = ARTIFACT_UNAVAILABLE
            inst.cooldown = self.STANDBY_COOLDOWN
            msg = (f"{u.name} 卸下了 {name}(单位不在己方据点,进不可用"
                   f"{self.STANDBY_COOLDOWN}回合)")
        self._recompute_unit_tags(u)
        if not suppress_log:
            self.log_msg(msg)
        return msg

    def action_sell_artifact(self, faction_id: str, instance_id: str) -> str:
        """卖出仓库内一件在库·可用装备,固定 +10 金币(ADR-0007)。

        只能卖出未装备且 state=available 的实例。不可用(冷却中)或已装备的不可卖。
        """
        f = self.factions.get(faction_id)
        if not f:
            return "失败:无此阵营"
        inst = self._artifact_index.get(instance_id)
        if not inst or not self._instance_in_faction_inventory(inst, f):
            return "失败:无此装备实例"
        if not inst.is_available():
            if inst.is_equipped():
                return "失败:装备已被装备,先卸下"
            return "失败:装备不可用(冷却中)"
        art = self.artifact_defs.get(inst.def_id)
        name = art.name if art else instance_id
        # 从仓库与索引移除
        f.inventory.remove(inst)
        self._artifact_index.pop(inst.id, None)
        f.resources.add("gold", 10, source=SOURCE_INIT,
                        building=name)
        return f"卖出 {name},+10 金币"

    def _release_artifacts(self, f: Faction, u: Unit) -> None:
        """单位死亡/解散时回收其装备:全部回库·可用(死亡无位置惩罚)。"""
        for slot in range(len(u.artifacts)):
            iid = u.artifacts[slot]
            inst = self._artifact_index.get(iid) if iid is not None else None
            if inst is None:
                continue
            inst.equipped_by = None
            inst.state = ARTIFACT_AVAILABLE
            inst.cooldown = 0
        u.artifacts = []

    def _recompute_unit_tags(self, u: Unit) -> None:
        """重算单位 tags = 本体 tag ∪ 当前装备赋予的 tag(ADR-0007)。

        兵种本体 tag 不可由装备移除,故每次装备/卸下后重算。装备改实例模型,经
        _artifact_index 映射到 def_id 再取 effects。
        """
        granted: set[str] = set()
        for iid in u.artifacts:
            inst = self._artifact_index.get(iid)
            if not inst:
                continue
            art = self.artifact_defs.get(inst.def_id)
            if not art:
                continue
            for e in art.effects:
                if e.get("type") == "tag_grant":
                    granted.add(e["params"]["tag"])
        body_tags = self._body_tags(u)
        u.tags = body_tags | granted

    def _body_tags(self, u: Unit) -> set[str]:
        """单位本体词条(不含神器赋予的 tag)。取兵种/英雄定义的原始 tags。"""
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
        # 5. 装备(神器):经实例索引解析到 def(ADR-0007)
        for iid in unit.artifacts:
            inst = self._artifact_index.get(iid)
            if not inst:
                continue
            art = self.artifact_defs.get(inst.def_id)
            if not art:
                continue
            effs = build_skill_effects({"effects": art.effects})
            army_tags_count = self._army_tags_count(army) if army else {}
            mods.extend(collect_passive_modifiers(effs, unit.id, unit.tags,
                                                  army_tags_count,
                                                  ModifierSource.ARTIFACT, iid))
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
        # 驻军设一个虚拟队长(取前排第一个单位,提其 leadership 以容纳全队)
        for uid in army.grid:
            if uid:
                army.captain_id = uid
                self.unit_index[uid].base["leadership"] = 999
                break
        self.armies[aid] = army
        return army

    # ---------- 回合驱动 ----------
    def start_turn(self, faction: Faction) -> None:
        """每阵营回合开始(规范入口):待命冷却推进 → 经济结算(含维护费/回血) →
        招募池刷新检查。

        AI 阵营与玩家阵营都走此入口。CLI/TUI 的回合编排应调用 start_turn,
        不再直接调 tick_economy(后者仅为经济结算子步,供 start_turn 内部调用)。
        回血前必须先扣维护费并打好断粮标记(断粮单位本回合不回血,见 §1)。
        """
        # 待命冷却推进(ADR-0005):不可用单位 -1,到 0 转可用
        self._tick_standby(faction)
        # 装备冷却推进(ADR-0007):仓库内不可用装备 -1,到 0 转可用
        self._tick_inventory(faction)
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

    def end_turn_advance(self) -> None:
        """回合结束推进时间。"""
        self.calendar.advance()

    # ---------- 经济 ----------
    def tick_economy(self, faction: Faction) -> None:
        """经济结算(由 start_turn 调用,也可单独调用以重算)。时序(见 §1 Maintenance):
        建筑产出 → 扣维护费(打断粮标记) → 补给补充 → 补给消耗/野外回血(5%)
        → 据点内回血(10%) → 驻军回血(10%)。

        所有回血阶段均跳过本回合断粮(_starved_this_turn)的单位(不掉血,仅跳过)。
        驻军免维护费故不会断粮,其回血跳过检查仅为守一致口径。
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
            if not army or army.is_garrison:
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
            if not army or army.is_garrison:
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
        # 5. 据点内回血(ADR-0004):非驻军部队在己方据点内每回合回血 10%;断粮单位跳过
        for aid in list(faction.army_ids):
            army = self.armies.get(aid)
            if not army or army.is_garrison:
                continue
            if army.node_id not in faction.stronghold_ids:
                continue
            for u in army.alive_units(self.unit_index):
                if getattr(u, "_starved_this_turn", False):
                    continue
                u.cur_hp = min(u.base.get("hp", 1),
                               u.cur_hp + u.base.get("hp", 1) * 0.1)
        # 6. 驻军回血补兵(未全灭):驻军免维护费不会断粮,此处仍守一致口径跳过断粮
        for sid in list(faction.stronghold_ids):
            sh = self.map.strongholds.get(sid)
            if not sh:
                continue
            for a in self.armies.values():
                if a.is_garrison and a.node_id == sid and a.owner == faction.id:
                    if not a.is_wiped(self.unit_index):
                        for u in a.alive_units(self.unit_index):
                            if getattr(u, "_starved_this_turn", False):
                                continue
                            u.cur_hp = min(u.base.get("hp", 1),
                                           u.cur_hp + u.base.get("hp", 1) * 0.1)
                        # 补兵:原型简化为不补新单位,仅回血

    # ---------- 维护费(§1) ----------
    def _deduct_maintenance(self, faction: Faction) -> None:
        """扣各单位维护费(§1)。单位级判定:逐资源尝试扣(允许部分扣),但只要任一
        资源没扣足,即标记该单位本回合断粮(不回血)。标志性建筑驻军免维护费。

        待命中的单位需不需要维护费?——需要。待命不是免维护状态(只免去上场冷却);
        静养不进食说不通,且会让待命池成为躲避维护费的漏洞。故待命单位照常扣维护费,
        断粮同样打标(待命单位本就不回血,标记在此只记录口径,无副作用)。

        数据来源:UnitType.maintenance / HeroDef.maintenance(数据驱动)。
        原型默认:普通人类兵种 {food:1},魔法兵种追加魔石,英雄约为普通 4 倍。
        """
        # 先把阵营所有非驻军单位打上未断粮默认(含上回合已断粮的,每回合重判);
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
            if army and army.is_garrison:
                continue   # 驻军免维护费
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
            if army.is_garrison:
                return False, "驻军不可训练"
            if army.node_id not in f.stronghold_ids:
                return False, "部队不在己方据点"
            # 该据点是否有任何敌方部队(非驻军)
            for a in self.armies.values():
                if (a.node_id == army.node_id and a.owner not in (None, owner)
                        and not a.is_garrison and not a.is_wiped(self.unit_index)):
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
            if a.is_wiped(self.unit_index) and not a.is_garrison:
                # 玩家部队全灭:解散(装备回库·可用)
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
