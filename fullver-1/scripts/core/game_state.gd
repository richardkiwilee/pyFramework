class_name GameState
extends RefCounted
## =============================================================================
## GameState — 完整游戏运行态（序列化根）
## =============================================================================
## 领域术语见 CONTEXT.md：GameState 持有所有领域对象，
## 是存读档（to_dict/from_dict）与跨场景数据桥的唯一载体。
## 由 GameManager autoload 持有（autoload 不做业务数据，只做编排）。
##
## 职责：
##   - 对象注册表与 O(1) 查询（get_faction/get_city/get_army）
##   - ID 生成（新军团/新单位）
##   - 事件日志（event_log：消息面板与游戏事件的数据源）
##   - 整体序列化（Team 自包含单位数据，存档无跨表引用）
##
## 类比 Python：
##   相当于游戏的核心 dataclass 容器 + 工厂方法，
##   类似 SQLAlchemy session 持有的对象图，但没有数据库。
## =============================================================================

## 存档格式版本号。改动存档结构时 +1；读档版本不符拒绝加载。
const SAVE_VERSION := 1

## 当前回合数（从 1 开始）
var turn: int = 1

## 势力列表（含玩家与 AI）
var factions: Array[Faction] = []

## 城市列表（大地图全部据点）
var cities: Array[City] = []

## 军团列表（全部势力）
var armies: Array[Army] = []

## 双边关系列表。A 对 B 与 B 对 A 各有一条（不对称），
## 由 DiplomacySystem.ensure_relation() 惰性创建。
var relations: Array[Relation] = []

## 事件日志：[{turn: int, kind: String, data: Dictionary}, ...]
## kind 对应 data/i18n 的 "event.*" 文案 key；UI 消息面板订阅渲染。
var event_log: Array = []

## ID 计数器（新对象生成时自增，保证存档内唯一）
var _next_army_id: int = 1
var _next_unit_id: int = 1


# ==================================================================
#  对象注册与查询
# ==================================================================

func get_faction(faction_id: String) -> Faction:
	for f in factions:
		if f.id == faction_id:
			return f
	return null


func get_city(city_id: String) -> City:
	for c in cities:
		if c.id == city_id:
			return c
	return null


func get_army(army_id: String) -> Army:
	for a in armies:
		if a.id == army_id:
			return a
	return null


## 某势力的全部军团
func armies_of(faction_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a in armies:
		if a.owner_faction_id == faction_id:
			result.append(a)
	return result


## 某势力的全部城市
func cities_of(faction_id: String) -> Array[City]:
	var result: Array[City] = []
	for c in cities:
		if c.owner_faction_id == faction_id:
			result.append(c)
	return result


## 查询双边关系（A 对 B）。不存在返回 null（DiplomacySystem 负责创建）
func get_relation(faction_a: String, faction_b: String) -> Relation:
	for r in relations:
		if r.faction_a == faction_a and r.faction_b == faction_b:
			return r
	return null


## 玩家势力对象
func player_faction() -> Faction:
	for f in factions:
		if f.is_player:
			return f
	return null


## 全部 AI 势力（is_player=false 且存活）
func ai_factions() -> Array[Faction]:
	var result: Array[Faction] = []
	for f in factions:
		if not f.is_player and f.alive:
			result.append(f)
	return result


# ==================================================================
#  工厂方法（ID 生成集中在此，保证唯一）
# ==================================================================

## 新建军团（空编队），挂在指定城市作为驻军
func new_army(faction_id: String, city_id: String) -> Army:
	var a := Army.new()
	a.id = "army_%d" % _next_army_id
	_next_army_id += 1
	a.owner_faction_id = faction_id
	a.current_city_id = city_id
	# 移动力上限读 factions.json 配置（数据驱动）
	var faction_data: Dictionary = DataManager.get_faction(faction_id)
	a.max_move_points = int(faction_data.get("army_move_points", 2))
	a.move_points = a.max_move_points
	armies.append(a)
	var city := get_city(city_id)
	if city != null:
		city.garrison_army_id = a.id
	return a


## 新建单位（由调用方用 Team.set_unit 放进编队）
func new_unit(character_id: String, level: int = 1) -> Unit:
	var u := Unit.new()
	u.id = "unit_%d" % _next_unit_id
	_next_unit_id += 1
	u.character_id = character_id
	u.level = level
	return u


## 移除军团（编队解散/被消灭时）
func remove_army(army: Army) -> void:
	if army == null:
		return
	# 城市驻军引用置空
	var city := get_city(army.current_city_id)
	if city != null and city.garrison_army_id == army.id:
		city.garrison_army_id = ""
	armies.erase(army)


# ==================================================================
#  事件日志
# ==================================================================

## 追加一条事件（kind 对应 i18n 的 "event." + kind 文案 key）
func add_event(kind: String, data: Dictionary = {}) -> void:
	event_log.append({"turn": turn, "kind": kind, "data": data})


## 最近 N 条事件（消息面板用）。slice 返回副本，防止外部改坏日志。
func recent_events(count: int) -> Array:
	var end: int = event_log.size()
	# ⚠️ max() 是全局函数，返回 Variant——用 := 推断会触发
	# INFERRED_DECLARATION 警告（本环境警告视为错误），必须显式标类型
	var begin: int = max(0, end - count)
	return event_log.slice(begin, end)


# ==================================================================
#  整体序列化（存档）
# ==================================================================

func to_dict() -> Dictionary:
	var faction_dicts: Array = []
	for f in factions:
		faction_dicts.append(f.to_dict())
	var city_dicts: Array = []
	for c in cities:
		city_dicts.append(c.to_dict())
	var army_dicts: Array = []
	for a in armies:
		army_dicts.append(a.to_dict())
	var relation_dicts: Array = []
	for r in relations:
		relation_dicts.append(r.to_dict())
	return {
		"save_version": SAVE_VERSION,
		"turn": turn,
		"next_army_id": _next_army_id,
		"next_unit_id": _next_unit_id,
		"factions": faction_dicts,
		"cities": city_dicts,
		"armies": army_dicts,
		"relations": relation_dicts,
		"event_log": event_log,
	}


## 从字典重建完整对象图。版本不符返回 null（调用方提示玩家）。
static func from_dict(d: Dictionary) -> GameState:
	if int(d.get("save_version", -1)) != SAVE_VERSION:
		return null
	var gs := GameState.new()
	gs.turn = int(d.get("turn", 1))
	gs._next_army_id = int(d.get("next_army_id", 1))
	gs._next_unit_id = int(d.get("next_unit_id", 1))
	for f in d.get("factions", []):
		gs.factions.append(Faction.from_dict(f))
	for c in d.get("cities", []):
		gs.cities.append(City.from_dict(c))
	# 军团自带编队与单位数据（自包含），直接重建
	for a in d.get("armies", []):
		gs.armies.append(Army.from_dict(a))
	for r in d.get("relations", []):
		gs.relations.append(Relation.from_dict(r))
	for ev in d.get("event_log", []):
		gs.event_log.append(ev)
	return gs
