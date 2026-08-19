class_name EconomySystem
extends RefCounted
## =============================================================================
## EconomySystem — 经济系统（纯逻辑）
## =============================================================================
## 职责（docs/00-design.md §12）：
##   - 每回合结算：城市产出（等级 × 每级产出）− 军团军费 → 势力资源
##   - 城市升级 / 征募军团的费用校验与执行
##   参数全部来自 data/resources.json（资源定义 + economy 段）。
##
## 类比 Python：service 层，纯计算 + 状态变更，无引擎依赖。
## =============================================================================

## 游戏状态（构造时注入）
var state: GameState

## 资源定义（data/resources.json 的 resources 数组）
var resource_defs: Array = []

## 经济参数（data/resources.json 的 economy 段）
var config: Dictionary


func _init(gs: GameState) -> void:
	state = gs
	resource_defs = DataManager.get_resource_defs()
	config = DataManager.get_economy_config()


# ==================================================================
#  回合结算
# ==================================================================

## ---------------------------------------------------------------------------
## settle_turn() — 每回合结束时的经济结算
## ---------------------------------------------------------------------------
## 每个存活势力：
##   收入 = Σ 城市等级 × 该资源每级产出
##   支出 = Σ 军团 × 每军团军费
##   净值入账（不足扣到 0——框架阶段不引入负债/破产机制）
## 返回明细（供测试与未来 UI 展示）：
##   [{faction_id, income: {}, upkeep: {}, net: {}}]
## ---------------------------------------------------------------------------
func settle_turn() -> Array:
	var detail: Array = []
	var upkeep_cfg: Dictionary = config.get("army_upkeep", {})
	for faction in state.factions:
		if not faction.alive:
			continue
		var income := _total_income(faction)
		var upkeep := _total_upkeep(faction, upkeep_cfg)
		# 净入账：income - upkeep，逐资源 clamp 到 0
		var net: Dictionary = {}
		for res_id in income:
			var n: int = int(income.get(res_id, 0)) - int(upkeep.get(res_id, 0))
			net[res_id] = max(0, n + int(faction.resources.get(res_id, 0)))
			faction.resources[res_id] = net[res_id]
		detail.append({"faction_id": faction.id, "income": income, "upkeep": upkeep, "net": net})
	return detail


## 某势力每回合总收入（Σ 城市产出）
func _total_income(faction: Faction) -> Dictionary:
	var total: Dictionary = {}
	for city in state.cities_of(faction.id):
		var production: Dictionary = get_city_production(city)
		for res_id in production:
			total[res_id] = int(total.get(res_id, 0)) + int(production[res_id])
	return total


## 某势力每回合总军费（Σ 军团维护费）
func _total_upkeep(faction: Faction, upkeep_cfg: Dictionary) -> Dictionary:
	var total: Dictionary = {}
	var army_count: int = state.armies_of(faction.id).size()
	for res_id in upkeep_cfg:
		total[res_id] = int(upkeep_cfg[res_id]) * army_count
	return total


## 城市每回合产出：等级 × 每级产出（数据驱动）
func get_city_production(city: City) -> Dictionary:
	var result: Dictionary = {}
	for res_def in resource_defs:
		var res_id: String = res_def.get("id", "")
		var per_level: int = int(res_def.get("production_per_city_level", 0))
		result[res_id] = per_level * city.level
	return result


# ==================================================================
#  城市升级
# ==================================================================

## 升级费用（数据驱动）
func get_upgrade_cost(_city: City) -> Dictionary:
	return config.get("city_upgrade_cost", {})


## 升级城市：费用校验 + 等级上限校验
func upgrade_city(faction: Faction, city: City) -> Dictionary:
	if city.owner_faction_id != faction.id:
		return {"ok": false, "reason": "not_owner"}
	var max_level: int = int(config.get("max_city_level", 5))
	if city.level >= max_level:
		return {"ok": false, "reason": "max_level"}
	var cost := get_upgrade_cost(city)
	if not faction.pay(cost):
		return {"ok": false, "reason": "insufficient"}
	city.level += 1
	return {"ok": true, "level": city.level}


# ==================================================================
#  征募军团
# ==================================================================

## 征募费用（数据驱动）
func get_recruit_cost() -> Dictionary:
	return config.get("recruit_cost", {})


## ---------------------------------------------------------------------------
## recruit_army() — 在指定城市征募一个满编军团
## ---------------------------------------------------------------------------
## 校验：城市归属、资源足额。成功 → 建军团（随机 team_size 单位 + 随机配装）。
## 编队站位：前排（slot 6/7/8）优先，再中排（3/4/5）——前排有人的战斗好习惯。
## free=true 跳过费用（开局初始军团用，GameManager.new_game 复用本方法）。
## ---------------------------------------------------------------------------
func recruit_army(faction: Faction, city: City, team_size: int = -1, free: bool = false) -> Dictionary:
	if city.owner_faction_id != faction.id:
		return {"ok": false, "reason": "not_owner"}
	if not free:
		var cost := get_recruit_cost()
		if not faction.pay(cost):
			return {"ok": false, "reason": "insufficient"}
	if team_size < 0:
		team_size = int(DataManager.get_factions_config().get("army_team_size", 6))
	# 城市已有驻军 → 拒绝（一城一军，框架阶段最简）
	for a in state.armies:
		if a.current_city_id == city.id and a.owner_faction_id == faction.id:
			return {"ok": false, "reason": "garrison_exists"}

	var army: Army = state.new_army(faction.id, city.id)
	var char_ids: Array = DataManager.get_random_characters(team_size)
	var slots: Array[int] = [6, 7, 8, 3, 4, 5, 0, 1, 2]
	for i in range(min(char_ids.size(), 9)):
		var unit: Unit = state.new_unit(char_ids[i], 1)
		_assign_random_equipment(unit)
		army.team.set_unit(slots[i], unit)
	state.add_event("army_recruited", {
		"faction": faction.name_zh,
		"city_name": city.name_zh,
	})
	return {"ok": true, "army_id": army.id}


## 按角色职业随机配一件武器（失败静默跳过——无合适装备也合法）
func _assign_random_equipment(unit: Unit) -> void:
	var char_data: Dictionary = DataManager.get_character(unit.character_id)
	if char_data.is_empty():
		return
	var class_id := DataManager.get_class_id_by_character(char_data)
	if class_id == "":
		return
	var subtypes: Array = DataManager.get_class_weapon_subtypes(class_id)
	if subtypes.is_empty():
		return
	var eq_ids: Array = DataManager.get_random_equipment_for_slot(subtypes[0], 1)
	if not eq_ids.is_empty():
		unit.equip("weapon", eq_ids[0])


## ---------------------------------------------------------------------------
## AI 指令处理器（"recruit"）
## ---------------------------------------------------------------------------
func ai_recruit_command(params: Dictionary, ctx: AIContext) -> Dictionary:
	var city: City = state.get_city(params.get("city_id", ""))
	if city == null:
		return {"ok": false, "reason": "bad_city"}
	return recruit_army(ctx.faction, city)
