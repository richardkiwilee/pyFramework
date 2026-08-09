## Game：核心编排（对应 pydemo/game/game.py）。
## 串起一局：日历、地图、阵营、部队、单位、修正收集、移动、战斗、占领、
## 招募、建造、事件、胜负、存档。只暴露动作接口与查询，逻辑与交互分离。
class_name Game
extends RefCounted

const LANDMARK_DEFENSE_BUFF: Dictionary = {"weak": 0.0, "medium": 0.10, "strong": 0.20}
const FORGE_DROP_CHANCE := 0.05
const RARITY_WEIGHTS: Dictionary = {"common": 60, "uncommon": 30, "rare": 10}
const STANDBY_COOLDOWN := 5
const EVENT_TRIGGER_CHANCE := 0.40

var defs: Dictionary = {}
var unit_type_defs: Dictionary = {}
var hero_defs: Dictionary = {}
var artifact_defs: Dictionary = {}
var synergy_defs: Dictionary = {}
var event_defs: Array = []
var building_defs: Dictionary = {}
var resource_defs: Dictionary = {}
var terrain_defs: Dictionary = {}
var tech_defs: Dictionary = {}
var culture_defs: Dictionary = {}

var calendar: Calendar
var map: MapSystem.GameMap
var factions: Dictionary = {}     # id -> Faction.Faction_
var armies: Dictionary = {}       # id -> Armies.Army
var unit_index: Dictionary = {}   # id -> Units.Unit
var log: Array = []
var winner: String = ""
var player_id: String = ""
var pending_event: Variant = null   # GameEvents.GameEvent
var rng: RandomNumberGenerator
var _army_counter := 0
var _unit_counter := 0

func _init(defs_: Dictionary = {}, seed: int = 0) -> void:
	if defs_.is_empty():
		defs = DataLoader.load_definitions()
	else:
		defs = defs_
	rng = RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(Time.get_ticks_usec())
	unit_type_defs = Units.load_unit_types(defs.get("unit_types", {}))
	hero_defs = Heroes.load_hero_defs(defs.get("heroes", {}))
	artifact_defs = Units.load_artifacts(defs.get("artifacts", {}))
	synergy_defs = Synergies.load_synergies(defs.get("synergies", {}))
	event_defs = GameEvents.load_events(defs.get("events", {}))
	building_defs = defs.get("buildings", {})
	resource_defs = defs.get("resources", {})
	terrain_defs = defs.get("terrain", {})
	tech_defs = DataLoader.load_list_defs("res://data/techs.json")
	culture_defs = DataLoader.load_list_defs("res://data/cultures.json")
	calendar = Calendar.new(1)
	map = MapSystem.GameMap.new()

# ---------- 工具 ----------
func log_msg(msg: String) -> void:
	log.append(msg)

func new_id(prefix: String) -> String:
	_unit_counter += 1
	return "%s_%d" % [prefix, _unit_counter]

func new_army_id() -> String:
	_army_counter += 1
	return "army_%d" % _army_counter

# ---------- 装备库存（def_id 计数模型） ----------
func add_artifact_stock(def_id: String, owner: String, count: int = 1) -> void:
	if not factions.has(owner) or not artifact_defs.has(def_id):
		return
	var f: Faction.Faction_ = factions[owner]
	f.inventory[def_id] = int(f.inventory.get(def_id, 0)) + maxi(0, count)

func artifact_def_of(def_id: String) -> Variant:
	return artifact_defs.get(def_id)

## 某 def_id 在本阵营各单位已装备总数（反查）。
func equipped_count(faction_id: String, def_id: String) -> int:
	var n := 0
	for uid in unit_index:
		var u: Units.Unit = unit_index[uid]
		if _unit_owner(u) != faction_id:
			continue
		n += u.artifacts.count(def_id)
	return n

## 在库可装数 = 库存 - 已装备（>=0）。
func available_count(faction_id: String, def_id: String) -> int:
	if not factions.has(faction_id):
		return 0
	var f: Faction.Faction_ = factions[faction_id]
	var stock := int(f.inventory.get(def_id, 0))
	return maxi(0, stock - equipped_count(faction_id, def_id))

# ---------- 阵营/单位/部队 ----------
func add_faction(fid: String, name: String, is_ai: bool = false) -> Faction.Faction_:
	var f := Faction.Faction_.new(fid, name, is_ai)
	factions[fid] = f
	if not is_ai and player_id == "":
		player_id = fid
	return f

func make_unit(type_id: String) -> Units.Unit:
	var ut: Units.UnitType = unit_type_defs[type_id]
	var base := ut.base.duplicate()
	var growth := ut.growth.duplicate()
	base["will"] = Units.WILL_BASE
	growth["will"] = Units.WILL_GROWTH_NORMAL
	var u := Units.Unit.new(new_id("u"), type_id, ut.name, ut.tags.duplicate(),
		base, [], false, [], [], 0.0, "", 0.0, 0.0, 0.0, 0.0, true, {}, "", 1, 0, growth)
	u.grant_tags_from_artifacts(artifact_defs)
	unit_index[u.id] = u
	return u

func make_hero(hero_def_id: String) -> Units.Unit:
	var hdef: Heroes.HeroDef = hero_defs[hero_def_id]
	var u := Heroes.make_hero_unit(hdef)
	u.id = new_id("u")
	u.base["will"] = Units.WILL_BASE
	u.growth["will"] = Units.WILL_GROWTH_HERO
	u.grant_tags_from_artifacts(artifact_defs)
	unit_index[u.id] = u
	return u

func create_army(owner: String, node_id: String, name: String) -> Armies.Army:
	var aid := new_army_id()
	var army := Armies.empty_army(aid, name, owner, node_id)
	armies[aid] = army
	var f: Faction.Faction_ = factions[owner]
	f.army_ids.append(aid)
	return army

func set_captain(army: Armies.Army, hero_unit: Units.Unit) -> bool:
	if not hero_unit.is_hero:
		return false
	# 若该英雄已是别的部队队长，先离队
	if hero_unit.army_id != "" and hero_unit.army_id != army.id:
		var old: Variant = armies.get(hero_unit.army_id)
		if old != null:
			old.remove(hero_unit.id)
			old.captain_id = ""
			_try_fill_captain(old)
	var f: Variant = factions.get(army.owner)
	var in_standby: bool = f != null and f.standby.has(hero_unit.id)
	army.captain_id = hero_unit.id
	if hero_unit.army_id != army.id:
		if not army.can_add(hero_unit, unit_index):
			army.captain_id = ""   # 回滚
			return false
		if in_standby:
			_pull_from_standby(f, hero_unit)
		army.add(hero_unit, unit_index)
		hero_unit.node_id = army.node_id
	elif in_standby:
		_pull_from_standby(f, hero_unit)
	return true

## 队长继任：从待命·可用英雄指派（leadership 高的优先）；无则解散。
func _try_fill_captain(army: Armies.Army) -> bool:
	if army.captain_id != "" and unit_index.has(army.captain_id):
		return true
	var f: Variant = factions.get(army.owner)
	if f == null:
		disband_army(army)
		return false
	var cands: Array = []
	for uid in f.standby_available_ids():
		if unit_index.has(uid):
			var u: Units.Unit = unit_index[uid]
			if u.is_hero and u.alive:
				cands.append(u)
	cands.sort_custom(func(a, b): return a.leadership() > b.leadership())
	for u in cands:
		if set_captain(army, u):
			return true
	disband_army(army)
	return false

## 解散部队：清九宫格，单位 army_id=None（直接丢弃，不进待命池）。
func disband_army(army: Armies.Army) -> void:
	for uid in army.grid:
		if uid != null and unit_index.has(uid):
			unit_index[uid].army_id = ""
	army.grid = []
	for i in range(Armies.GRID_SIZE):
		army.grid.append(null)
	army.captain_id = ""
	if armies.has(army.id):
		for fid in factions:
			var f: Faction.Faction_ = factions[fid]
			if f.army_ids.has(army.id):
				f.army_ids.erase(army.id)
		armies.erase(army.id)

# ---------- 待命池 ----------
func _to_standby(faction: Faction.Faction_, unit: Units.Unit, cooldown: int) -> void:
	unit.army_id = ""
	unit.node_id = ""
	faction.standby[unit.id] = cooldown

func _pull_from_standby(faction: Faction.Faction_, unit: Units.Unit) -> void:
	faction.standby.erase(unit.id)

func _tick_standby(faction: Faction.Faction_) -> void:
	for uid in faction.standby.keys():
		if int(faction.standby[uid]) > 0:
			faction.standby[uid] = int(faction.standby[uid]) - 1

## 上场：待命·可用单位派进己方据点内部队。
func action_deploy(faction_id: String, army_id: String, unit_id: String, slot: int = -1) -> String:
	var f: Variant = factions.get(faction_id)
	if f == null:
		return "失败:无此阵营"
	var u: Variant = unit_index.get(unit_id)
	if u == null:
		return "失败:无此单位"
	if not f.standby.has(unit_id):
		return "失败:单位不在待命池"
	if int(f.standby[unit_id]) > 0:
		return "失败:单位待命·不可用"
	var army: Variant = armies.get(army_id)
	if army == null or army.owner != faction_id:
		return "失败:无此部队"
	if not f.stronghold_ids.has(army.node_id):
		return "失败:部队不在己方据点"
	if not army.can_add(u, unit_index):
		return "失败:部队已满或领导力不足"
	var ok: bool
	if slot >= 0:
		if slot >= Armies.GRID_SIZE:
			return "失败:槽位越界"
		if army.grid[slot] != null:
			return "失败:该槽位已占用"
		ok = army.add(u, unit_index, slot)
	else:
		ok = army.add(u, unit_index)
	if not ok:
		return "失败:加入失败"
	_pull_from_standby(f, u)
	u.node_id = army.node_id
	return "%s 已上场至 %s" % [u.name, army.name]

## 下场：撤入待命。部队在己方据点 → 冷却 0；否则 5 回合。队长下场触发继任。
func action_discharge(faction_id: String, army_id: String, unit_id: String) -> String:
	var f: Variant = factions.get(faction_id)
	if f == null:
		return "失败:无此阵营"
	var army: Variant = armies.get(army_id)
	if army == null or army.owner != faction_id:
		return "失败:无此部队"
	var u: Variant = unit_index.get(unit_id)
	if u == null or u.army_id != army_id:
		return "失败:单位不在此部队"
	if not army.grid.has(unit_id):
		return "失败:单位不在此部队"
	army.remove(unit_id)
	var in_stronghold: bool = f.stronghold_ids.has(army.node_id)
	var msg: String
	if in_stronghold:
		_to_standby(f, u, 0)
		msg = "%s 下场,进入待命·可用(部队在己方据点)" % u.name
	else:
		_to_standby(f, u, STANDBY_COOLDOWN)
		msg = "%s 下场,进入待命·不可用(%d回合)" % [u.name, STANDBY_COOLDOWN]
	if army.captain_id == unit_id:
		army.captain_id = ""
		if not _try_fill_captain(army):
			msg += ";无可用英雄接任,%s 已解散" % army.name
	return msg

# ---------- 装备 ----------
## 装备：库存计数模型；单位须在己方据点（待命单位可）。槽满先卸旧。
func action_equip(faction_id: String, unit_id: String, def_id: String, slot: int) -> String:
	var f: Variant = factions.get(faction_id)
	if f == null:
		return "失败:无此阵营"
	var u: Variant = unit_index.get(unit_id)
	if u == null:
		return "失败:无此单位"
	if _unit_owner(u) != faction_id:
		return "失败:单位不归你"
	if slot < 0 or slot >= Units.ARTIFACT_SLOTS:
		return "失败:槽位越界"
	if not _unit_in_own_stronghold(f, u):
		return "失败:单位不在己方据点(野外不可穿戴/卸下)"
	if not artifact_defs.has(def_id):
		return "失败:未知装备定义"
	if available_count(faction_id, def_id) <= 0:
		return "失败:仓库无此装备在库可用"
	var art: Units.Artifact = artifact_defs[def_id]
	while u.artifacts.size() <= slot:
		u.artifacts.append(null)
	if u.artifacts[slot] != null:
		_unequip_into_inventory(u, slot)
	u.artifacts[slot] = def_id
	_recompute_unit_tags(u)
	_recompute_granted_skills(u)
	return "%s 装备了 %s" % [u.name, art.name]

## 卸下：回库。位置限制同装备。
func action_unequip(faction_id: String, unit_id: String, slot: int) -> String:
	var f: Variant = factions.get(faction_id)
	if f == null:
		return "失败:无此阵营"
	var u: Variant = unit_index.get(unit_id)
	if u == null:
		return "失败:无此单位"
	if _unit_owner(u) != faction_id:
		return "失败:单位不归你"
	if slot < 0 or slot >= Units.ARTIFACT_SLOTS:
		return "失败:槽位越界"
	if not _unit_in_own_stronghold(f, u):
		return "失败:单位不在己方据点(野外不可穿戴/卸下)"
	if slot >= u.artifacts.size() or u.artifacts[slot] == null:
		return "失败:该槽位无装备"
	var name := _unequip_into_inventory(u, slot)
	_recompute_unit_tags(u)
	_recompute_granted_skills(u)
	return "%s 卸下了 %s(回库·可用)" % [u.name, name]

func _unequip_into_inventory(u: Units.Unit, slot: int) -> String:
	var def_id: String = u.artifacts[slot]
	var art: Variant = artifact_defs.get(def_id) if def_id != null else null
	var name: String = art.name if art != null else (def_id if def_id != null else "?")
	u.artifacts[slot] = null
	return name

## 单位所在部队是否在己方据点内（待命单位无部队、视为安全）。
func _unit_in_own_stronghold(f: Faction.Faction_, u: Units.Unit) -> bool:
	if u.army_id == "":
		return true
	var army: Variant = armies.get(u.army_id)
	if army == null:
		return false
	return f.stronghold_ids.has(army.node_id)

## 卖出仓库内 1 件某定义装备，固定 +10 金币。
func action_sell_artifact(faction_id: String, def_id: String) -> String:
	var f: Variant = factions.get(faction_id)
	if f == null:
		return "失败:无此阵营"
	if not artifact_defs.has(def_id):
		return "失败:未知装备定义"
	if available_count(faction_id, def_id) <= 0:
		return "失败:无在库可用件(已装备须先卸下)"
	var art: Units.Artifact = artifact_defs[def_id]
	f.inventory[def_id] = int(f.inventory[def_id]) - 1
	if int(f.inventory[def_id]) <= 0:
		f.inventory.erase(def_id)
	f.resources.add("gold", 10, Economy.SOURCE_INIT, "", art.name)
	return "卖出 %s,+10 金币" % art.name

## 单位死亡/解散时回收其装备：清槽位（库存计数不变，已装备由反查体现）。
func _release_artifacts(f: Faction.Faction_, u: Units.Unit) -> void:
	u.artifacts = []
	u.granted_skills = []

## 重算单位 tags = 本体词条 ∪ 装备 tag_grant 赋予。
func _recompute_unit_tags(u: Units.Unit) -> void:
	var granted: Array = []
	for def_id in u.artifacts:
		if def_id == null:
			continue
		var art: Variant = artifact_defs.get(def_id)
		if art == null:
			continue
		for e in art.effects:
			if e.get("type") == "tag_grant":
				granted.append(e["params"]["tag"])
	var body := _body_tags(u)
	var merged: Array = []
	for t in body:
		if not merged.has(t):
			merged.append(t)
	for t in granted:
		if not merged.has(t):
			merged.append(t)
	u.tags = merged

## 重算装备赋予技能（装上加入、卸下移除——全量重算）。
func _recompute_granted_skills(u: Units.Unit) -> void:
	var granted: Array = []
	for def_id in u.artifacts:
		if def_id == null:
			continue
		var art: Variant = artifact_defs.get(def_id)
		if art == null:
			continue
		for e in art.effects:
			if e.get("type") == "skill_grant":
				var sid: String = e["params"].get("skill", "")
				if sid != "" and not granted.has(sid):
					granted.append(sid)
	u.granted_skills = granted

## 单位本体词条（不含装备赋予）。
func _body_tags(u: Units.Unit) -> Array:
	if u.is_hero:
		var hdef: Variant = hero_defs.get(u.type_id)
		return hdef.tags.duplicate() if hdef != null else u.tags.duplicate()
	var ut: Variant = unit_type_defs.get(u.type_id)
	return ut.tags.duplicate() if ut != null else u.tags.duplicate()

# ---------- 修正收集 ----------
func collect_unit_mods(unit: Units.Unit, army: Variant,
		calendar_: Calendar, terrain: String = "") -> Array:
	var mods: Array = []
	# 1. 月相：魔力恢复
	mods.append(Modifier.Mod_.new(Modifier.Source.MOON, "moon", unit.id,
		"mana_regen", float(calendar_.mana_regen()), "flat"))
	# 2. 昼夜
	var tod := calendar_.time_of_day_index()
	var tod_bonus: Dictionary = {
		0: {"melee": ["p_atk", 0.05]},
		1: {"ranged": ["p_atk", 0.05]},
		2: {"melee": ["p_atk", 0.05]},
		3: {"magic": ["m_atk", 0.10]},
		4: {"magic": ["m_atk", 0.15]},
	}
	var bonus: Variant = tod_bonus.get(tod, {})
	for tag in bonus:
		if unit.tags.has(tag):
			mods.append(Modifier.Mod_.new(Modifier.Source.DAY_NIGHT, "tod", unit.id,
				bonus[tag][0], float(bonus[tag][1]), "pct"))
	# 3. 技能/被动（perk 走修正管道）
	for sid in unit.effective_skills():
		var skill_data: Dictionary = defs.get("skills", {}).get(sid, {})
		if skill_data.is_empty():
			continue
		if Effects.skill_kind(skill_data) != Effects.SKILL_PERK:
			continue
		var effs := Effects.build_skill_effects(skill_data)
		var counts := _army_tags_count(army) if army != null else {}
		mods.append_array(Effects.collect_passive_modifiers(effs, unit.id, unit.tags,
			counts, Modifier.Source.SKILL, sid))
	# 4. 装备
	for def_id in unit.artifacts:
		if def_id == null:
			continue
		var art: Variant = artifact_defs.get(def_id)
		if art == null:
			continue
		var effs := Effects.build_skill_effects({"effects": art.effects})
		var counts := _army_tags_count(army) if army != null else {}
		mods.append_array(Effects.collect_passive_modifiers(effs, unit.id, unit.tags,
			counts, Modifier.Source.ARTIFACT, def_id))
	# 5. 地形（小地点）
	if terrain != "" and terrain_defs.has(terrain):
		var tdef: Dictionary = terrain_defs[terrain]
		for attr in tdef.get("mods", {}):
			mods.append(Modifier.Mod_.new(Modifier.Source.TERRAIN, terrain, unit.id,
				attr, float(tdef["mods"][attr]), "flat"))
	return mods

func _army_tags_count(army: Variant) -> Dictionary:
	if army == null:
		return {}
	var counts: Dictionary = {}
	for uid in army.grid:
		if uid != null and unit_index.has(uid):
			for t in unit_index[uid].tags:
				counts[t] = int(counts.get(t, 0)) + 1
	return counts

## 收集整支部队所有单位的修正 + 羁绊。
func collect_army_mods(army: Armies.Army, calendar_: Calendar,
		terrain: String = "") -> Array:
	var all_mods: Array = []
	var units := army.alive_units(unit_index)
	var tags_count := _army_tags_count(army)
	all_mods.append_array(Synergies.collect_synergy_mods(tags_count, units, synergy_defs))
	for u in units:
		all_mods.append_array(collect_unit_mods(u, army, calendar_, terrain))
	return all_mods

# ---------- 回合驱动 ----------
func start_turn(faction: Faction.Faction_) -> void:
	_tick_standby(faction)
	faction.resources.reset_turn()
	tick_economy(faction)
	# 招募池刷新（每 14 天）
	for sid in faction.stronghold_ids:
		var pool: Variant = faction.recruitment_pools.get(sid)
		if pool == null:
			pool = Heroes.RecruitmentPool.new(sid)
			faction.recruitment_pools[sid] = pool
			pool.refresh(hero_defs.keys(), calendar.day, 14, rng)
		elif calendar.day >= pool.refresh_day:
			pool.refresh(hero_defs.keys(), calendar.day, 14, rng)
	_dispatch_building_turn_events(faction)

## 建筑回合事件 dispatch（B10）：forge_drop → 锻造屋产出装备。
func _forge_drop_handler(faction: Faction.Faction_, stronghold, building) -> void:
	if rng.randf() < FORGE_DROP_CHANCE:
		var def_id := _weighted_random_artifact()
		if def_id != "":
			add_artifact_stock(def_id, faction.id, 1)
			var adef: Variant = artifact_defs.get(def_id)
			var name: String = adef.name if adef != null else def_id
			log_msg("%s 锻造屋产出 %s" % [stronghold.name, name])

func _weighted_random_artifact() -> String:
	if artifact_defs.is_empty():
		return ""
	var buckets: Dictionary = {"common": [], "uncommon": [], "rare": []}
	for aid in artifact_defs:
		var a: Units.Artifact = artifact_defs[aid]
		var r: String = a.rarity
		if not buckets.has(r):
			buckets[r] = []
		buckets[r].append(aid)
	var weighted: Array = []
	var total := 0
	for r in buckets:
		if not buckets[r].is_empty():
			weighted.append([r, int(RARITY_WEIGHTS.get(r, 0))])
			total += int(RARITY_WEIGHTS.get(r, 0))
	if weighted.is_empty() or total <= 0:
		return ""
	var roll := rng.randf() * total
	var acc := 0.0
	var chosen := "common"
	for pair in weighted:
		acc += pair[1]
		if roll < acc:
			chosen = pair[0]
			break
	var pool: Array = buckets.get(chosen, buckets.get("common", []))
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]

func _dispatch_building_turn_events(faction: Faction.Faction_) -> void:
	for sid in faction.stronghold_ids:
		var sh: Variant = map.strongholds.get(sid)
		if sh == null:
			continue
		for b in sh.buildings:
			var bdef: Dictionary = building_defs.get(b.type_id, {})
			var event: String = bdef.get("on_turn", "")
			if event == "":
				continue
			if event == "forge_drop":
				_forge_drop_handler(faction, sh, b)

func end_turn_advance() -> void:
	calendar.advance()

# ---------- 经济 ----------
func tick_economy(faction: Faction.Faction_) -> void:
	# 1. 建筑产出
	for sid in faction.stronghold_ids:
		var sh: Variant = map.strongholds.get(sid)
		if sh == null:
			continue
		var gained: Dictionary = sh.tick_produce()
		for k in gained:
			var bld_names: Array[String] = []
			for b in sh.buildings:
				if b.produces.has(k):
					bld_names.append(b.name)
			faction.resources.add(k, int(gained[k]), Economy.SOURCE_BUILD, sid,
				"、".join(bld_names) if not bld_names.is_empty() else "")
	# 2. 扣维护费
	_deduct_maintenance(faction)
	# 3. 补给补充（己方据点）
	for aid in faction.army_ids:
		var army: Variant = armies.get(aid)
		if army == null:
			continue
		if faction.stronghold_ids.has(army.node_id):
			var need: int = army.supply_max - army.supply
			if need > 0:
				var give := mini(need, faction.resources.get_amount("food"))
				if give > 0:
					faction.resources.add("food", -give, Economy.SOURCE_SUPPLY)
					army.supply += give
	# 4. 补给消耗 + 野外回血（小地点）
	for aid in faction.army_ids:
		var army: Variant = armies.get(aid)
		if army == null:
			continue
		if map.minors.has(army.node_id):
			army.supply -= 1
			if army.supply <= 0:
				army.supply = 0
				for u in army.alive_units(unit_index):
					u.cur_hp = maxf(0.0, float(u.cur_hp) - float(u.base.get("hp", 1)) * 0.05)
			else:
				for u in army.alive_units(unit_index):
					if u._starved_this_turn:
						continue
					u.cur_hp = minf(float(u.base.get("hp", 1)),
						float(u.cur_hp) + float(u.base.get("hp", 1)) * 0.05)
	# 5. 据点内回血 10%（跳过断粮）
	for aid in faction.army_ids:
		var army: Variant = armies.get(aid)
		if army == null:
			continue
		if not faction.stronghold_ids.has(army.node_id):
			continue
		for u in army.alive_units(unit_index):
			if u._starved_this_turn:
				continue
			u.cur_hp = minf(float(u.base.get("hp", 1)),
				float(u.cur_hp) + float(u.base.get("hp", 1)) * 0.1)

## 扣各单位维护费：逐资源尝试扣（允许部分扣），任一没扣足标记断粮（本回合不回血）。
func _deduct_maintenance(faction: Faction.Faction_) -> void:
	for uid in unit_index:
		var u: Units.Unit = unit_index[uid]
		if u.alive and _unit_owner(u) == faction.id:
			u._starved_this_turn = false
			u._trained_this_turn = false
	for uid in unit_index:
		var u: Units.Unit = unit_index[uid]
		if not u.alive:
			continue
		if _unit_owner(u) != faction.id:
			continue
		var cost := _maintenance_cost(u)
		if cost.is_empty():
			continue
		var starved := false
		for k in cost:
			var have := faction.resources.get_amount(k)
			var pay_v := mini(int(cost[k]), have)
			if pay_v > 0:
				faction.resources.add(k, -pay_v, Economy.SOURCE_MAINT)
			if pay_v < int(cost[k]):
				starved = true
		if starved:
			u._starved_this_turn = true

## 单位归属阵营：部队成员看 army.owner；待命单位遍历阵营 standby。
func _unit_owner(u: Units.Unit) -> String:
	if u.army_id != "" and armies.has(u.army_id):
		return armies[u.army_id].owner
	for fid in factions:
		var f: Faction.Faction_ = factions[fid]
		if f.standby.has(u.id):
			return fid
	return ""

## 维护费：优先读定义；缺省普通人类 {food:1}、魔法追加魔石、英雄 4 倍。
func _maintenance_cost(u: Units.Unit) -> Dictionary:
	if u.is_hero:
		var hdef: Variant = hero_defs.get(u.type_id)
		if hdef != null and not hdef.maintenance.is_empty():
			return hdef.maintenance.duplicate()
	else:
		var ut: Variant = unit_type_defs.get(u.type_id)
		if ut != null and not ut.maintenance.is_empty():
			return ut.maintenance.duplicate()
	var cost: Dictionary = {"food": 4 if u.is_hero else 1}
	if u.tags.has("magic"):
		cost["mana_stone"] = 4 if u.is_hero else 1
	return cost

## 训练消耗：优先读定义；缺省 gold = 招募价/2 + 5 食物，魔法系追加 1 魔石。
func _train_cost(u: Units.Unit) -> Dictionary:
	if u.is_hero:
		var hdef: Variant = hero_defs.get(u.type_id)
		if hdef != null and not hdef.train_cost.is_empty():
			return hdef.train_cost.duplicate()
	else:
		var ut: Variant = unit_type_defs.get(u.type_id)
		if ut != null and not ut.train_cost.is_empty():
			return ut.train_cost.duplicate()
	var recruit: Dictionary = {}
	if u.is_hero:
		var hdef: Variant = hero_defs.get(u.type_id)
		if hdef != null:
			recruit = hdef.recruit_cost
	else:
		var ut: Variant = unit_type_defs.get(u.type_id)
		if ut != null:
			recruit = ut.recruit_cost
	var gold_half := int(recruit.get("gold", 0)) / 2
	var cost: Dictionary = {"gold": gold_half + 5, "food": 5}
	if u.tags.has("magic"):
		cost["mana_stone"] = 1
	return cost

## 是否可训练：己方据点内部队且该据点无敌方部队，或待命·可用。返回 [可否, 原因]。
func is_trainable(u: Units.Unit) -> Array:
	var owner := _unit_owner(u)
	if owner == "":
		return [false, "无主单位"]
	if not u.alive:
		return [false, "单位已亡"]
	var f: Faction.Faction_ = factions.get(owner)
	if f.standby.has(u.id):
		if int(f.standby[u.id]) > 0:
			return [false, "待命·不可用"]
		return [true, ""]
	if u.army_id != "" and armies.has(u.army_id):
		var army: Armies.Army = armies[u.army_id]
		if not f.stronghold_ids.has(army.node_id):
			return [false, "部队不在己方据点"]
		for a in armies.values():
			if (a.node_id == army.node_id and a.owner != owner and a.owner != ""
					and not a.is_wiped(unit_index)):
				return [false, "据点有敌方部队"]
		return [true, ""]
	return [false, "单位不在部队也不在待命"]

## 训练：+5 XP，每回合每单位 1 次。升级时 HP 按比例保留。
func action_train(faction_id: String, unit_id: String) -> String:
	var u: Variant = unit_index.get(unit_id)
	if u == null:
		return "失败:无此单位"
	if _unit_owner(u) != faction_id:
		return "失败:单位不归你"
	if u._trained_this_turn:
		return "失败:本回合已训练"
	var trainable := is_trainable(u)
	if not trainable[0]:
		return "失败:不可训练(%s)" % trainable[1]
	var cost := _train_cost(u)
	var f: Faction.Faction_ = factions[faction_id]
	if not f.resources.can_afford(cost):
		return "失败:资源不足"
	f.resources.pay(cost, Economy.SOURCE_TRAIN)
	var levels: int = u.gain_xp(5)
	u._trained_this_turn = true
	var msg := "%s 训练:+5XP" % u.name
	if levels > 0:
		msg += ",升到 Lv%d" % u.level
	return msg

# ---------- 建造/拆除 ----------
## 建造：支付足额资源即立即建成；recruit/special 需 requires 已学；刷新产出投影。
func action_build(faction_id: String, stronghold_id: String, building_id: String) -> String:
	var f: Faction.Faction_ = factions[faction_id]
	var sh: Variant = map.strongholds.get(stronghold_id)
	if sh == null or sh.owner != faction_id:
		return "失败:据点不归你所有"
	if sh.free_slots() <= 0:
		return "失败:据点无空槽"
	var bdef: Dictionary = building_defs.get(building_id, {})
	if bdef.is_empty():
		return "失败:未知建筑"
	var requires: Array = bdef.get("requires", [])
	if not requires.is_empty():
		var missing := _unmet_requires(faction_id, requires)
		if not missing.is_empty():
			return "失败:需先研究 %s" % "、".join(missing)
	var cost: Dictionary = bdef.get("cost", {})
	if not f.resources.can_afford(cost):
		return "失败:资源不足"
	f.resources.pay(cost, Economy.SOURCE_BUILD, stronghold_id, cn_building(bdef))
	var b := MapSystem.Building.new(
		"b%d" % rng.randi_range(1000, 9999), building_id, cn_building(bdef),
		bdef.get("produces", {}) if bdef.get("kind") == "produce" else {})
	sh.add_building(b)
	# 新建筑下回合产出写入投影，面板立刻刷新
	for k in b.produces:
		f.resources.resource(k).add_projected(int(b.produces[k]))
	return "已在 %s 建造 %s(即时建成)" % [sh.name, b.name]

## 拆除：即时、不退资源；刷新投影。
func action_demolish(faction_id: String, stronghold_id: String, building_id: String) -> String:
	var f: Faction.Faction_ = factions[faction_id]
	var sh: Variant = map.strongholds.get(stronghold_id)
	if sh == null or sh.owner != faction_id:
		return "失败:据点不归你所有"
	var target: Variant = null
	for b in sh.buildings:
		if b.id == building_id:
			target = b
			break
	if target == null:
		return "失败:据点内无此建筑"
	sh.buildings.erase(target)
	for k in target.produces:
		f.resources.resource(k).add_projected(-int(target.produces[k]))
	return "已在 %s 拆除 %s" % [sh.name, target.name]

# ---------- 招募 ----------
## 英雄招募：信念门槛 + 资源 → 待命·可用；招募后该槽位置 None 不压缩。
func action_recruit_hero(faction_id: String, stronghold_id: String, hero_id: String) -> String:
	var f: Faction.Faction_ = factions[faction_id]
	var sh: Variant = map.strongholds.get(stronghold_id)
	if sh == null or sh.owner != faction_id:
		return "失败:据点不归你所有"
	var pool: Variant = f.recruitment_pools.get(stronghold_id)
	if pool == null or not pool.offerings.has(hero_id):
		return "失败:该英雄不在招募池"
	var hdef: Variant = hero_defs.get(hero_id)
	if hdef == null:
		return "失败:未知英雄"
	if not Heroes.meets_belief_req(f.belief, hdef.belief_req):
		return "失败:信念不足(%s)" % Heroes.describe_req(hdef.belief_req)
	if not f.resources.can_afford(hdef.recruit_cost):
		return "失败:资源不足"
	f.resources.pay(hdef.recruit_cost, Economy.SOURCE_RECRUIT, stronghold_id, hdef.name)
	var u := make_hero(hero_id)
	f.hero_ids.append(u.id)
	pool.offerings[pool.offerings.find(hero_id)] = null
	_to_standby(f, u, 0)
	return "招募了 %s，进入待命·可用" % u.name

func _unmet_requires(faction_id: String, requires: Array) -> Array:
	var f: Faction.Faction_ = factions[faction_id]
	var learned: Array = []
	learned.append_array(f.tech_learned)
	learned.append_array(f.culture_learned)
	var out: Array = []
	for rid in requires:
		if learned.has(rid):
			continue
		var tdef: Variant = tech_defs.get(rid, culture_defs.get(rid))
		out.append(tdef.get("name", rid) if tdef != null else rid)
	return out

func action_learn_tech(faction_id: String, tech_id: String) -> String:
	return _learn_tree(faction_id, tech_id, "tech")

func action_learn_culture(faction_id: String, culture_id: String) -> String:
	return _learn_tree(faction_id, culture_id, "culture")

func _learn_tree(faction_id: String, item_id: String, kind: String) -> String:
	var f: Faction.Faction_ = factions[faction_id]
	var defs_: Dictionary = tech_defs if kind == "tech" else culture_defs
	var learned: Array = f.tech_learned if kind == "tech" else f.culture_learned
	var label := "科技" if kind == "tech" else "文化"
	var idef: Variant = defs_.get(item_id)
	if idef == null:
		return "失败:未知%s" % label
	if learned.has(item_id):
		return "已学习过:%s" % idef.get("name", item_id)
	var prereqs: Array = idef.get("prereqs", [])
	var all_learned: Array = []
	all_learned.append_array(f.tech_learned)
	all_learned.append_array(f.culture_learned)
	var missing: Array = []
	for p in prereqs:
		if not all_learned.has(p):
			missing.append(p)
	if not missing.is_empty():
		var names: Array[String] = []
		for p in missing:
			var pdef: Variant = tech_defs.get(p, culture_defs.get(p))
			names.append(pdef.get("name", p) if pdef != null else p)
		return "失败:前置未满足(%s)" % ", ".join(names)
	var cost: Dictionary = idef.get("cost", {})
	if not f.resources.can_afford(cost):
		return "失败:资源不足,无法学习 %s" % idef.get("name", item_id)
	f.resources.pay(cost, Economy.SOURCE_BUILD, "", idef.get("name", item_id))
	learned.append(item_id)
	return "学习了 %s" % idef.get("name", item_id)

## 招普通兵：全局存在性（任一己方据点有对应招募建筑）+ 资源 → 待命·可用。
func action_recruit_unit(faction_id: String, unit_type_id: String) -> String:
	var f: Faction.Faction_ = factions[faction_id]
	var recruiting_bid := ""
	var recruiting_bdef: Dictionary = {}
	for bid in building_defs:
		var bdef: Dictionary = building_defs[bid]
		if bdef.get("recruits", []).has(unit_type_id):
			recruiting_bid = bid
			recruiting_bdef = bdef
			break
	if recruiting_bdef.is_empty():
		return "失败:无招募 %s 的建筑定义" % unit_type_id
	var has_building := false
	for sid in f.stronghold_ids:
		var sh: Variant = map.strongholds.get(sid)
		if sh == null:
			continue
		for b in sh.buildings:
			if b.type_id == recruiting_bid:
				has_building = true
				break
		if has_building:
			break
	if not has_building:
		return "失败:需先建造 %s" % recruiting_bdef.get("name", "招募建筑")
	var ut: Variant = unit_type_defs.get(unit_type_id)
	if ut == null:
		return "失败:未知兵种 %s" % unit_type_id
	var cost: Dictionary = ut.recruit_cost
	if not f.resources.can_afford(cost):
		return "失败:资源不足,无法招募 %s" % ut.name
	f.resources.pay(cost, Economy.SOURCE_RECRUIT, "", ut.name)
	var u := make_unit(unit_type_id)
	_to_standby(f, u, 0)
	return "招募了 %s,进入待命·可用" % u.name

# ---------- 移动与战斗 ----------
func action_move(faction_id: String, army_id: String, to_node: String) -> String:
	var f: Faction.Faction_ = factions[faction_id]
	var army: Variant = armies.get(army_id)
	if army == null or army.owner != faction_id:
		return "失败:无此部队"
	if army.node_id == to_node:
		return "失败:已在目标结点"
	if not map.neighbors(army.node_id).has(to_node):
		return "失败:目标结点不相邻"
	army.node_id = to_node
	for uid in army.grid:
		if uid != null and unit_index.has(uid):
			unit_index[uid].node_id = to_node
	return "%s 移动到 %s" % [army.name, map.node_name(to_node)]

## 移动 + 进攻：无守方 → 直接占领；有守方 → _do_battle。
func action_move_attack(faction_id: String, army_id: String, to_node: String) -> String:
	var f: Faction.Faction_ = factions[faction_id]
	var army: Variant = armies.get(army_id)
	if army == null or army.owner != faction_id:
		return "失败:无此部队"
	if army.has_acted_this_turn:
		return "失败:本部队本回合已行动"
	if not map.neighbors(army.node_id).has(to_node):
		return "失败:目标结点不相邻"
	var from_node: String = army.node_id
	army.node_id = to_node
	for uid in army.grid:
		if uid != null and unit_index.has(uid):
			unit_index[uid].node_id = to_node
	# 找防守部队
	var target_sh: Variant = map.strongholds.get(to_node)
	var defender_army: Variant = null
	var is_siege := false
	if target_sh != null and target_sh.owner != "" and target_sh.owner != faction_id:
		is_siege = true
		for a in armies.values():
			if (a.node_id == to_node and a.owner == target_sh.owner
					and not a.is_wiped(unit_index)):
				defender_army = a
				break
	if defender_army == null and map.minors.has(to_node):
		for a in armies.values():
			if (a.node_id == to_node and a.owner != "" and a.owner != faction_id
					and not a.is_wiped(unit_index)):
				defender_army = a
				break
	if defender_army == null:
		# 无防守部队：据点直接易主
		if is_siege and target_sh != null:
			_capture_stronghold(target_sh, faction_id)
			army.has_acted_this_turn = true
			if target_sh.is_capital:
				_on_capital_fallen(target_sh)
			return "%s 占领了 %s!" % [army.name, target_sh.name]
		army.has_acted_this_turn = true
		return "%s 移动到 %s" % [army.name, map.node_name(to_node)]
	# 开战
	var result := _do_battle(army, defender_army, from_node, is_siege,
		target_sh if is_siege else null)
	army.has_acted_this_turn = true
	return result

func _do_battle(attacker: Armies.Army, defender: Armies.Army, from_node: String,
		is_siege: bool, target_sh: Variant) -> String:
	var a_terrain := map.terrain_of(attacker.node_id)
	var d_terrain := map.terrain_of(defender.node_id)
	var a_mods := collect_army_mods(attacker, calendar, a_terrain)
	var d_mods := collect_army_mods(defender, calendar, d_terrain)
	# 攻城 buff：据点守方获 landmark p_def 百分比加成
	var landmark: Variant = target_sh.landmark if (is_siege and target_sh != null) else null
	if landmark != null:
		var tier: String = landmark.tier if landmark.tier != "" else "weak"
		var buff_val := float(LANDMARK_DEFENSE_BUFF.get(tier, 0.0))
		if buff_val > 0:
			for u in defender.alive_units(unit_index):
				d_mods.append(Modifier.Mod_.new(Modifier.Source.LANDMARK, landmark.name,
					u.id, "p_def", buff_val, "pct"))
	var all_mods: Array = []
	all_mods.append_array(a_mods)
	all_mods.append_array(d_mods)
	# 策略
	var skill_defs: Dictionary = defs.get("skills", {})
	var strats: Dictionary = {}
	for u in attacker.alive_units(unit_index):
		strats[u.id] = Formation.default_strategy(u, skill_defs)
	for u in defender.alive_units(unit_index):
		strats[u.id] = Formation.default_strategy(u, skill_defs)
	# 跑战斗
	var aside := Battle.BattleSide.new(attacker, true, from_node, attacker.alive_units(unit_index))
	var dside := Battle.BattleSide.new(defender, false, defender.node_id, defender.alive_units(unit_index))
	var result := Battle.run_battle(aside, dside, strats, all_mods, false,
		rng, skill_defs, player_id)
	# 结局处理
	var msgs: Array[String] = []
	if result.attacker_wiped:
		msgs.append("%s 进攻失败,部队全灭" % attacker.name)
	if result.defender_wiped:
		msgs.append("%s 被全灭" % defender.name)
	_award_death_xp(result, attacker, defender)
	if result.occupier_side == "attacker":
		if is_siege and target_sh != null:
			_capture_stronghold(target_sh, attacker.owner)
			msgs.append("%s 占领了 %s!" % [attacker.name, target_sh.name])
			if target_sh.is_capital:
				_on_capital_fallen(target_sh)
		else:
			msgs.append("%s 控制了 %s" % [attacker.name, map.node_name(attacker.node_id)])
	elif result.occupier_side == "defender":
		msgs.append("%s 击退来犯之敌" % defender.name)
	else:
		# 200 tick 未分胜负：进攻方退回
		attacker.node_id = from_node
		for uid in attacker.grid:
			if uid != null and unit_index.has(uid):
				unit_index[uid].node_id = from_node
		msgs.append("战斗未分胜负,%s 退回 %s" % [attacker.name, map.node_name(from_node)])
	_cleanup_wiped()
	return "、".join(msgs)

## 据点易主：转 landmark + 归属。
func _capture_stronghold(sh: MapSystem.Stronghold, new_owner: String) -> void:
	var old_owner: String = sh.owner
	sh.owner = new_owner
	if old_owner != "" and factions.has(old_owner):
		if factions[old_owner].stronghold_ids.has(sh.id):
			factions[old_owner].stronghold_ids.erase(sh.id)
	factions[new_owner].stronghold_ids.append(sh.id)
	log_msg("%s 由 %s 转归 %s" % [sh.name, old_owner, new_owner])

## 首都陷落：阵营出局，释放单位/装备，解散军队，判定胜负。
func _on_capital_fallen(capital: MapSystem.Stronghold) -> void:
	var old_owner := ""
	for fid in factions:
		var f: Faction.Faction_ = factions[fid]
		if f.capital_id == capital.id:
			old_owner = fid
			break
	if old_owner == "":
		return
	var f: Faction.Faction_ = factions[old_owner]
	f.alive = false
	for aid in f.army_ids:
		var a: Variant = armies.get(aid)
		if a != null:
			for uid in a.grid:
				if uid != null:
					var u: Variant = unit_index.get(uid)
					if u != null:
						_release_artifacts(f, u)
					unit_index.erase(uid)
			if armies.has(aid):
				armies.erase(aid)
	for uid in f.standby.keys():
		var u: Variant = unit_index.get(uid)
		if u != null:
			_release_artifacts(f, u)
		unit_index.erase(uid)
	f.standby.clear()
	f.army_ids.clear()
	f.hero_ids.clear()
	log_msg("%s 首都陷落,出局!所有部队解散。" % f.name)
	var alive: Array = []
	for fid in factions:
		if factions[fid].alive:
			alive.append(fid)
	if alive.size() == 1:
		winner = alive[0]
	elif player_id != "" and factions[player_id].alive:
		var enemies: Array = []
		for fid in alive:
			if fid != player_id:
				enemies.append(fid)
		if enemies.is_empty():
			winner = player_id

## 清理全灭部队（装备回库）。
func _cleanup_wiped() -> void:
	for aid in armies.keys():
		var a: Armies.Army = armies[aid]
		if a.is_wiped(unit_index):
			var owner_f: Variant = factions.get(a.owner)
			for uid in a.grid:
				if uid != null:
					var u: Variant = unit_index.get(uid)
					if u != null and owner_f != null:
						_release_artifacts(owner_f, u)
					unit_index.erase(uid)
			if armies.has(aid):
				for fid in factions:
					var f: Faction.Faction_ = factions[fid]
					if f.army_ids.has(aid):
						f.army_ids.erase(aid)
				armies.erase(aid)

## 死亡经验：每个阵亡单位，其等级数值作为 XP 发给击杀方所有存活单位。
func _award_death_xp(result, attacker: Armies.Army, defender: Armies.Army) -> void:
	var att_ids: Dictionary = {}
	for u in attacker.alive_units(unit_index):
		att_ids[u.id] = true
	var def_ids: Dictionary = {}
	for u in defender.alive_units(unit_index):
		def_ids[u.id] = true
	for uid in result.casualties:
		var dead: Variant = unit_index.get(uid)
		if dead == null:
			continue
		var xp: int = dead.level
		if xp <= 0:
			continue
		var gainers: Array = []
		if def_ids.has(uid):
			gainers = attacker.alive_units(unit_index)
		else:
			gainers = defender.alive_units(unit_index)
		for g in gainers:
			var levels: int = g.gain_xp(xp)
			if levels > 0:
				log_msg("%s 获 %d 经验,升到 Lv%d" % [g.name, xp, g.level])

# ---------- 玩家事件 ----------
func maybe_trigger_event(faction: Faction.Faction_) -> void:
	if faction.is_ai:
		return
	if rng.randf() < EVENT_TRIGGER_CHANCE and not event_defs.is_empty():
		pending_event = GameEvents.random_event(event_defs, rng)

func resolve_event(option_index: int) -> String:
	var ev: Variant = pending_event
	if ev == null or option_index >= ev.options.size():
		return "无事件"
	var opt = ev.options[option_index]
	var f: Faction.Faction_ = factions[player_id]
	var result := GameEvents.apply_option(opt, f.resources, f.belief)
	pending_event = null
	return "事件【%s】选择:%s -> %s" % [ev.title, opt.label, result]

# ---------- 胜负 ----------
func check_winner() -> void:
	if winner != "":
		return
	var alive: Array = []
	for fid in factions:
		if factions[fid].alive:
			alive.append(fid)
	if alive.size() <= 1 and not alive.is_empty():
		winner = alive[0]

func is_over() -> bool:
	return winner != ""

# ---------- 存档（snapshot / restore） ----------
func snapshot() -> Dictionary:
	var data: Dictionary = {
		"version": 1,
		"day": calendar.day,
		"player_id": player_id,
		"winner": winner,
		"log": log.duplicate(),
		"counters": {"army": _army_counter, "unit": _unit_counter},
		"pending_event_id": pending_event.id if pending_event != null else null,
		"map": {
			"strongholds": {},
			"minors": {},
			"adj": {},
			"roads": [],
		},
		"factions": {},
		"armies": {},
		"units": {},
	}
	for sid in map.strongholds:
		data["map"]["strongholds"][sid] = _stronghold_to_dict(map.strongholds[sid])
	for mid in map.minors:
		var m: MapSystem.MinorLocation = map.minors[mid]
		data["map"]["minors"][mid] = {"id": m.id, "name": m.name, "terrain": m.terrain,
			"x": m.x, "y": m.y}
	for a in map.adj:
		data["map"]["adj"][a] = map.adj[a].duplicate()
	var roads_out: Array = []
	for r in map.roads:
		roads_out.append({"a": r.a, "b": r.b, "curve": r.curve})
	data["map"]["roads"] = roads_out
	for fid in factions:
		data["factions"][fid] = _faction_to_dict(factions[fid])
	for aid in armies:
		data["armies"][aid] = _army_to_dict(armies[aid])
	for uid in unit_index:
		data["units"][uid] = _unit_to_dict(unit_index[uid])
	return data

static func _building_to_dict(b: MapSystem.Building) -> Dictionary:
	return {"id": b.id, "type_id": b.type_id, "name": b.name,
		"produces": b.produces.duplicate(), "tier": b.tier}

static func _building_from_dict(d: Dictionary) -> MapSystem.Building:
	return MapSystem.Building.new(d["id"], d["type_id"], d["name"],
		d.get("produces", {}).duplicate(), d.get("tier", ""))

func _stronghold_to_dict(sh: MapSystem.Stronghold) -> Dictionary:
	var blds: Array = []
	for b in sh.buildings:
		blds.append(_building_to_dict(b))
	return {
		"id": sh.id, "name": sh.name, "size": sh.size, "owner": sh.owner,
		"is_capital": sh.is_capital,
		"landmark": _building_to_dict(sh.landmark) if sh.landmark != null else null,
		"buildings": blds,
		"stationed_army_id": sh.stationed_army_id,
		"x": sh.x, "y": sh.y,
	}

func _faction_to_dict(f: Faction.Faction_) -> Dictionary:
	var pools: Dictionary = {}
	for sid in f.recruitment_pools:
		var p: Heroes.RecruitmentPool = f.recruitment_pools[sid]
		pools[sid] = {"stronghold_id": p.stronghold_id,
			"offerings": p.offerings.duplicate(), "refresh_day": p.refresh_day}
	return {
		"id": f.id, "name": f.name, "is_ai": f.is_ai,
		"resources": f.resources.amounts.duplicate(),
		"belief": f.belief.values.duplicate(),
		"capital_id": f.capital_id,
		"army_ids": f.army_ids.duplicate(),
		"hero_ids": f.hero_ids.duplicate(),
		"stronghold_ids": f.stronghold_ids.duplicate(),
		"standby": f.standby.duplicate(),
		"inventory": f.inventory.duplicate(),
		"recruitment_pools": pools,
		"tech_learned": f.tech_learned.duplicate(),
		"culture_learned": f.culture_learned.duplicate(),
		"alive": f.alive,
	}

static func _army_to_dict(a: Armies.Army) -> Dictionary:
	return {"id": a.id, "name": a.name, "captain_id": a.captain_id,
		"grid": a.grid.duplicate(), "owner": a.owner, "node_id": a.node_id,
		"has_acted_this_turn": a.has_acted_this_turn,
		"supply": a.supply, "supply_max": a.supply_max}

static func _unit_to_dict(u: Units.Unit) -> Dictionary:
	return {
		"id": u.id, "type_id": u.type_id, "name": u.name,
		"tags": u.tags.duplicate(), "base": u.base.duplicate(),
		"artifacts": u.artifacts.duplicate(), "is_hero": u.is_hero,
		"skills": u.skills.duplicate(), "granted_skills": u.granted_skills.duplicate(),
		"cur_hp": u.cur_hp, "army_id": u.army_id,
		"cur_ap": u.cur_ap, "cur_pp": u.cur_pp, "cur_mana": u.cur_mana,
		"atb": u.atb, "alive": u.alive,
		"statuses": u.statuses.duplicate(), "node_id": u.node_id,
		"level": u.level, "xp": u.xp, "growth": u.growth.duplicate(),
	}

## 从 snapshot() dict 反序列化重建 Game 对象图。
static func restore(data: Dictionary) -> Game:
	var g := Game.new()
	g.calendar = Calendar.new(int(data["day"]))
	g.player_id = data.get("player_id", "")
	g.winner = data.get("winner", "")
	g.log = data.get("log", []).duplicate()
	var counters: Dictionary = data.get("counters", {})
	g._army_counter = int(counters.get("army", 0))
	g._unit_counter = int(counters.get("unit", 0))
	g.pending_event = null
	# 地图
	var m: Dictionary = data["map"]
	for sid in m["strongholds"]:
		var sd: Dictionary = m["strongholds"][sid]
		var landmark: Variant = _building_from_dict(sd["landmark"]) if sd.get("landmark") != null else null
		var blds: Array = []
		for b in sd.get("buildings", []):
			blds.append(_building_from_dict(b))
		g.map.add_stronghold(MapSystem.Stronghold.new(sd["id"], sd["name"], int(sd["size"]),
			sd.get("owner", ""), sd.get("is_capital", false), landmark,
			int(sd.get("x", 0)), int(sd.get("y", 0))))
		g.map.strongholds[sd["id"]].buildings = blds
	for mid in m["minors"]:
		var md: Dictionary = m["minors"][mid]
		g.map.add_minor(MapSystem.MinorLocation.new(md["id"], md["name"], md["terrain"],
			int(md.get("x", 0)), int(md.get("y", 0))))
	for a in m.get("adj", {}):
		g.map.adj[a] = m["adj"][a].duplicate()
	# 道路：存档有则还原；旧存档无道路则从连边补默认直线（兼容）
	var roads_in: Array = m.get("roads", [])
	if roads_in.is_empty():
		var seen: Dictionary = {}
		for a in g.map.adj:
			for b in g.map.adj[a]:
				var k := [a, b]
				k.sort()
				var key := str(k)
				if seen.has(key):
					continue
				seen[key] = true
				g.map.add_road(a, b, 0.0)
	else:
		for r in roads_in:
			g.map.add_road(r.get("a", ""), r.get("b", ""), float(r.get("curve", 0.0)))
	# 单位先建（army/faction 引用 unit id）
	for uid in data["units"]:
		var ud: Dictionary = data["units"][uid]
		# __post_init__ 等价逻辑在 Unit._init：cur_hp<=0 会重置，故用占位再覆盖
		var u := Units.Unit.new(ud["id"], ud["type_id"], ud["name"],
			ud.get("tags", []), ud.get("base", {}), ud.get("artifacts", []),
			ud.get("is_hero", false), ud.get("skills", []),
			ud.get("granted_skills", []), 1.0, ud.get("army_id", ""),
			float(ud.get("cur_ap", 0)), float(ud.get("cur_pp", 0)),
			float(ud.get("cur_mana", 0)), float(ud.get("atb", 0)),
			ud.get("alive", true), ud.get("statuses", {}), ud.get("node_id", ""),
			int(ud.get("level", 1)), int(ud.get("xp", 0)), ud.get("growth", {}))
		u.cur_hp = float(ud["cur_hp"])   # 覆盖占位，保留真实（可能 <=0）血量
		g.unit_index[u.id] = u
	# 阵营
	for fid in data["factions"]:
		var fd: Dictionary = data["factions"][fid]
		var f := Faction.Faction_.new(fd["id"], fd["name"], fd.get("is_ai", false))
		f.resources = Economy.Resources.new(fd.get("resources", {}))
		f.belief = Economy.Belief.new(fd.get("belief", {}))
		f.capital_id = fd.get("capital_id", "")
		f.army_ids = fd.get("army_ids", []).duplicate()
		f.hero_ids = fd.get("hero_ids", []).duplicate()
		f.stronghold_ids = fd.get("stronghold_ids", []).duplicate()
		f.standby = fd.get("standby", {}).duplicate()
		f.inventory = fd.get("inventory", {}).duplicate()
		for sid in fd.get("recruitment_pools", {}):
			var pd: Dictionary = fd["recruitment_pools"][sid]
			var pool := Heroes.RecruitmentPool.new(pd["stronghold_id"])
			pool.offerings = pd.get("offerings", []).duplicate()
			pool.refresh_day = int(pd.get("refresh_day", 1))
			f.recruitment_pools[sid] = pool
		f.tech_learned = fd.get("tech_learned", []).duplicate()
		f.culture_learned = fd.get("culture_learned", []).duplicate()
		f.alive = fd.get("alive", true)
		g.factions[fid] = f
	# 部队
	for aid in data["armies"]:
		var ad: Dictionary = data["armies"][aid]
		g.armies[aid] = Armies.Army.new(ad["id"], ad["name"],
			ad.get("captain_id", ""), ad.get("grid", []), ad.get("owner", ""),
			ad.get("node_id", ""), ad.get("has_acted_this_turn", false),
			int(ad.get("supply", 10)), int(ad.get("supply_max", 10)))
	# 待处理事件（按 id 从定义重建）
	var pid: Variant = data.get("pending_event_id")
	if pid != null:
		for ev in g.event_defs:
			if ev.id == pid:
				g.pending_event = ev
				break
	return g

## 建筑定义显示名。
static func cn_building(bdef: Dictionary) -> String:
	return bdef.get("name", bdef.get("id", "?"))
