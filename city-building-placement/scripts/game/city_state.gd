extends Node
class_name CityCore
## 城市状态（autoload：CityState）
## 地块归属、建筑实例、四资源、回合结算、相邻加成计算。无 UI 依赖。

signal changed

const TerrainData := preload("res://scripts/data/terrain_data.gd")
const BuildingData := preload("res://scripts/data/building_data.gd")
const HexGeo := preload("res://scripts/hex/hex_geometry.gd")

const CENTER: Vector2i = Vector2i.ZERO

## Vector2i -> true
var owned: Dictionary = {}
## Vector2i -> {"id": String, "level": int}
var buildings: Dictionary = {}
## Res -> int
var resources: Dictionary = {}
var turn_count: int = 0


func _ready() -> void:
	_apply_initial_state()


func _apply_initial_state() -> void:
	owned.clear()
	buildings.clear()
	resources = {
		BuildingData.Res.GOLD: 200,
		BuildingData.Res.WOOD: 150,
		BuildingData.Res.FOOD: 150,
		BuildingData.Res.STONE: 100,
	}
	turn_count = 0
	# 开局拥有 1 环（6+1）
	for cell: Vector2i in TerrainData.LAYOUT.keys():
		if HexGeo.axial_distance(cell, CENTER) <= 1:
			owned[cell] = true
	buildings[CENTER] = {"id": BuildingData.CITY_CENTER_ID, "level": 1}


# ── 查询 ──

func has_cell(cell: Vector2i) -> bool:
	return TerrainData.LAYOUT.has(cell)


func is_owned(cell: Vector2i) -> bool:
	return owned.has(cell)


func is_built(cell: Vector2i) -> bool:
	return buildings.has(cell)


func building_at(cell: Vector2i) -> Dictionary:
	return buildings.get(cell, {})


func terrain_of(cell: Vector2i) -> int:
	return TerrainData.terrain_at(cell)


func terrain_top(cell: Vector2i) -> float:
	return float(TerrainData.TOP_HEIGHT.get(terrain_of(cell), 0.0))


func ring_of(cell: Vector2i) -> int:
	return HexGeo.axial_distance(cell, CENTER)


func has_owned_neighbor(cell: Vector2i) -> bool:
	for n: Vector2i in HexGeo.neighbors(cell):
		if owned.has(n):
			return true
	return false


func count_adjacent_terrain(cell: Vector2i, terrains: Array) -> int:
	var count: int = 0
	for n: Vector2i in HexGeo.neighbors(cell):
		if not has_cell(n):
			continue
		if terrains.has(terrain_of(n)):
			count += 1
	return count


func can_afford(cost: Dictionary) -> bool:
	for res: int in cost.keys():
		if int(resources.get(res, 0)) < int(cost[res]):
			return false
	return true


# ── 开拓 ──

func can_expand(cell: Vector2i) -> bool:
	return has_cell(cell) and not owned.has(cell) and has_owned_neighbor(cell)


func expand_cost(cell: Vector2i) -> Dictionary:
	var ring: int = ring_of(cell)
	var base: Dictionary = {}
	if ring == 2:
		base = {BuildingData.Res.GOLD: 30, BuildingData.Res.WOOD: 20}
	else:
		base = {BuildingData.Res.GOLD: 80, BuildingData.Res.WOOD: 50, BuildingData.Res.STONE: 20}
	var mult: float = 1.0 + owned.size() * 0.05
	var cost: Dictionary = {}
	for res: int in base.keys():
		cost[res] = int(roundf(float(base[res]) * mult))
	return cost


func expand(cell: Vector2i) -> bool:
	if not can_expand(cell):
		return false
	var cost: Dictionary = expand_cost(cell)
	if not can_afford(cost):
		return false
	_deduct(cost)
	owned[cell] = true
	changed.emit()
	return true


# ── 建造 ──

func build_cost(id: String, level: int = 1) -> Dictionary:
	var data: Dictionary = BuildingData.get_building(id)
	var base: Dictionary = data.get("cost", {})
	var mult: int = 1
	if level > 1:
		mult = 1 << (level - 1)
	var cost: Dictionary = {}
	for res: int in base.keys():
		cost[res] = int(base[res]) * mult
	return cost


## 无法建造的原因；空串 = 可以建造
func build_block_reason(cell: Vector2i, id: String) -> String:
	var data: Dictionary = BuildingData.get_building(id)
	if data.is_empty():
		return "未知建筑"
	var terr: int = terrain_of(cell)
	var req: Array = data.get("terrain_req", [])
	if not req.has(terr):
		return "地形不符（需要：" + terrain_list_name(req) + "）"
	var adj_req: Array = data.get("adj_req", [])
	for entry: Dictionary in adj_req:
		var tlist: Array = entry.get("terrains", [])
		if count_adjacent_terrain(cell, tlist) == 0:
			return "相邻要求不满足（需要相邻" + terrain_list_name(tlist) + "）"
	if not can_afford(build_cost(id)):
		return "资源不足"
	return ""


func terrain_list_name(list: Array) -> String:
	var parts: Array[String] = []
	for t: int in list:
		parts.append(TerrainData.terrain_name(t))
	return "、".join(parts)


func can_build(cell: Vector2i, id: String) -> bool:
	if not owned.has(cell) or buildings.has(cell):
		return false
	return build_block_reason(cell, id).is_empty()


func build(cell: Vector2i, id: String) -> bool:
	if not can_build(cell, id):
		return false
	_deduct(build_cost(id))
	buildings[cell] = {"id": id, "level": 1}
	changed.emit()
	return true


# ── 升级 / 拆除 ──

func upgrade_cost(cell: Vector2i) -> Dictionary:
	var b: Dictionary = building_at(cell)
	if b.is_empty():
		return {}
	var id: String = str(b.get("id", ""))
	var level: int = int(b.get("level", 1))
	return build_cost(id, level + 1)


func can_upgrade(cell: Vector2i) -> bool:
	var b: Dictionary = building_at(cell)
	if b.is_empty():
		return false
	var id: String = str(b.get("id", ""))
	var data: Dictionary = BuildingData.get_building(id)
	var max_level: int = int(data.get("max_level", 1))
	var level: int = int(b.get("level", 1))
	return level < max_level and can_afford(upgrade_cost(cell))


func upgrade(cell: Vector2i) -> bool:
	if not can_upgrade(cell):
		return false
	_deduct(upgrade_cost(cell))
	var b: Dictionary = buildings[cell]
	b["level"] = int(b.get("level", 1)) + 1
	buildings[cell] = b
	changed.emit()
	return true


func can_demolish(cell: Vector2i) -> bool:
	if not buildings.has(cell):
		return false
	return str(buildings[cell].get("id", "")) != BuildingData.CITY_CENTER_ID


func demolish(cell: Vector2i) -> void:
	if not can_demolish(cell):
		return
	buildings.erase(cell)
	changed.emit()


# ── 产出与回合 ──

## 某格建筑每回合产出（含等级放大、相邻建筑/水域/匹配地形加成）
func building_yield(cell: Vector2i) -> Dictionary:
	var b: Dictionary = building_at(cell)
	if b.is_empty():
		return {}
	var id: String = str(b.get("id", ""))
	var level: int = int(b.get("level", 1))
	var data: Dictionary = BuildingData.get_building(id)
	var out: Dictionary = {}
	var base: Dictionary = data.get("yields", {})
	for res: int in base.keys():
		var amt: float = float(base[res]) * pow(1.5, level - 1)
		out[res] = int(ceili(amt))
	# 相邻建筑加成（市中心不参与任何加成）
	for entry: Dictionary in data.get("adjacency", []):
		var add: int = int(entry.get("amt", 0)) + level - 1
		var res: int = int(entry.get("res", 0))
		var ids: Array = entry.get("ids", [])
		var cats: Array = entry.get("cats", [])
		for n: Vector2i in HexGeo.neighbors(cell):
			if not buildings.has(n):
				continue
			var nid: String = str(buildings[n].get("id", ""))
			var ndata: Dictionary = BuildingData.get_building(nid)
			var ncat: String = str(ndata.get("category", ""))
			if ids.has(nid) or cats.has(ncat):
				out[res] = int(out.get(res, 0)) + add
	# 相邻水域加成（每格水域单独计）
	var wb: Dictionary = data.get("water_bonus", {})
	if not wb.is_empty():
		var wcount: int = count_adjacent_terrain(cell, [TerrainData.Terrain.WATER])
		if wcount > 0:
			for res: int in wb.keys():
				out[res] = int(out.get(res, 0)) + (int(wb[res]) + level - 1) * wcount
	# 匹配地形加成
	var mb: Dictionary = data.get("match_bonus", {})
	if mb.has(terrain_of(cell)):
		var mres: Dictionary = mb[terrain_of(cell)]
		for res: int in mres.keys():
			out[res] = int(out.get(res, 0)) + int(mres[res]) + level - 1
	return out


func net_income() -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in buildings.keys():
		var y: Dictionary = building_yield(cell)
		for res: int in y.keys():
			out[res] = int(out.get(res, 0)) + int(y[res])
	return out


func end_turn() -> void:
	var income: Dictionary = net_income()
	for res: int in income.keys():
		resources[res] = int(resources.get(res, 0)) + int(income[res])
	turn_count += 1
	changed.emit()


func add_resources_debug(amount: int = 100) -> void:
	for res: int in BuildingData.Res.values():
		resources[res] = int(resources.get(res, 0)) + amount
	changed.emit()


func _deduct(cost: Dictionary) -> void:
	for res: int in cost.keys():
		resources[res] = int(resources.get(res, 0)) - int(cost[res])
