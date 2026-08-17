extends SceneTree
## =============================================================================
## 纯逻辑自测:六边形几何、地图生成约束、区域放置规则与邻接加成
## 运行: godot --headless --path . --script res://tests/test_logic.gd
## =============================================================================

var _fails: Array[String] = []


func _check(name: String, ok: bool) -> void:
	if ok:
		print("[ ok ] %s" % name)
	else:
		_fails.append(name)
		print("[FAIL] %s" % name)


func _init() -> void:
	print("== 六边形几何 ==")
	_check("hex_distance 轴距 2", HexCore.hex_distance(Vector2i(0, 0), Vector2i(2, -1)) == 2)
	_check("hex_distance 对角 4", HexCore.hex_distance(Vector2i(1, -2), Vector2i(-1, 2)) == 4)
	var coords: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(2, -1), Vector2i(-3, 1), Vector2i(4, -4), Vector2i(-5, 5),
	]
	for c in coords:
		_check("轴向取整 (%d,%d)" % [c.x, c.y], HexCore.axial_round(HexCore.center(c.x, c.y)) == c)

	print("== 地图生成 ==")
	var m := HexMap.new()
	m.generate(20260817)
	_check("91 格地图", m.tiles.size() == 91)
	_check("城市为陆地且海拔 0",
			m.tiles[m.city_coord].terrain != HexMap.Terrain.OCEAN and m.tiles[m.city_coord].elevation == 0)
	_check("城市临河", m.adjacent_river_count(m.city_coord) > 0)
	_check("城市 3 格内有可建港口的水域", _has_placeable_harbor(m))
	_check("城市 3 格内有山脉", _has_elev(m, 3, 3))
	_check("城市 3 格内有丘陵", _has_elev(m, 3, 2))
	_check("有鱼群资源", _count_fish(m) > 0)
	var m2 := HexMap.new()
	m2.generate(20260817)
	_check("同种子确定性", m.river_edges.size() == m2.river_edges.size() and _same_terrain(m, m2))

	print("== 区域系统 ==")
	var sys := DistrictSystem.new()
	# 水渠:城市邻居中临河的地块必然可建
	var aqueduct_spot := Vector2i(99999, 99999)
	for d in HexCore.DIRS:
		var n := m.city_coord + d
		if m.tiles.has(n) and m.adjacent_river_count(n) > 0 \
				and m.tiles[n].terrain != HexMap.Terrain.OCEAN:
			aqueduct_spot = n
			break
	_check("找到水渠位置(邻城+临河)", aqueduct_spot.x < 99990)
	_check("水渠可放置", sys.can_place(m, DistrictSystem.DistrictType.AQUEDUCT, aqueduct_spot).ok)
	_check("水渠超出 3 格被拒", not sys.can_place(m, DistrictSystem.DistrictType.AQUEDUCT, Vector2i(3, 3)).ok)
	_check("港口在陆地被拒", not sys.can_place(m, DistrictSystem.DistrictType.HARBOR, m.city_coord).ok)
	# 商业中心:找一块临河陆地,加成 ≥ 基础 + 2×河岸数
	var river_land := _find_valid(m, sys, DistrictSystem.DistrictType.COMMERCIAL_HUB)
	_check("存在临河陆地建商业中心", river_land.x < 99990)
	var adj := sys.adjacency(m, DistrictSystem.DistrictType.COMMERCIAL_HUB, river_land)
	_check("商业中心临河 +2 每边", adj.total >= 1 + 2 * m.adjacent_river_count(river_land))
	# 学院:加成 ≥ 基础 + 相邻山脉数
	var campus_spot := _find_valid(m, sys, DistrictSystem.DistrictType.CAMPUS)
	_check("存在学院地块", campus_spot.x < 99990)
	var cadj := sys.adjacency(m, DistrictSystem.DistrictType.CAMPUS, campus_spot)
	var expect := 1
	for d in HexCore.DIRS:
		var nb := campus_spot + d
		if m.tiles.has(nb) and m.tiles[nb].elevation >= HexCore.MOUNTAIN:
			expect += 1
	_check("学院邻山加成", cadj.total >= expect)
	# 每类限建一个
	var c1 := _find_valid(m, sys, DistrictSystem.DistrictType.CAMPUS)
	if c1.x < 99990:
		sys.place(m, DistrictSystem.DistrictType.CAMPUS, c1)
	var c2 := _find_valid(m, sys, DistrictSystem.DistrictType.CAMPUS)
	_check("同类型限建一个", c2.x >= 99990)

	print("== 结果 ==")
	if _fails.is_empty():
		print("全部通过")
		quit(0)
	else:
		print("失败 %d 项: %s" % [_fails.size(), ", ".join(_fails)])
		quit(1)


func _has_elev(m: HexMap, radius: int, elev: int) -> bool:
	for coord in m.tiles:
		if HexCore.hex_distance(m.city_coord, coord) <= radius \
				and m.tiles[coord].elevation == elev \
				and m.tiles[coord].terrain != HexMap.Terrain.OCEAN:
			return true
	return false


func _has_placeable_harbor(m: HexMap) -> bool:
	for coord in m.tiles:
		if HexCore.hex_distance(m.city_coord, coord) > 3:
			continue
		if m.tiles[coord].terrain == HexMap.Terrain.OCEAN and m.has_land_neighbor(coord):
			return true
	return false


func _count_fish(m: HexMap) -> int:
	var n := 0
	for coord in m.tiles:
		if m.tiles[coord].has_fish:
			n += 1
	return n


func _same_terrain(a: HexMap, b: HexMap) -> bool:
	for coord in a.tiles:
		var ta := a.tiles[coord]
		var tb := b.tiles[coord]
		if ta.elevation != tb.elevation or ta.terrain != tb.terrain or ta.has_woods != tb.has_woods:
			return false
	return true


func _find_valid(m: HexMap, sys: DistrictSystem, def_id: int) -> Vector2i:
	for coord in m.tiles:
		if sys.can_place(m, def_id, coord).ok:
			return coord
	return Vector2i(99999, 99999)
