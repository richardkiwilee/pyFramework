class_name HexMap
extends RefCounted
## =============================================================================
## 地图数据与生成 —— 确定性岛屿大陆 + 河流网络(纯逻辑,无渲染)
## =============================================================================
## · 地图为半径 RADIUS 的六边形区域,城市固定在中心 (0,0);
## · 海拔 0..3:平地 / 缓坡 / 丘陵 / 山脉 —— 丘陵 +3 防御、山脉不可通行,
##   这正是相对《文明 6》新增的"高度"维度:高度决定地貌与通行/战斗价值;
## · 河流沿地块边界流动:发源于高地、顺地势流向海洋,并在两岸切削出河谷;
## · 大陆外圈是海洋(便于建造港口),城市 3 格内保证有海湾 / 山脉 / 丘陵 / 河流,
##   让每一种区域类型都有展示舞台。
## =============================================================================

enum Terrain { OCEAN, GRASS, PLAINS, DESERT }


## 单个地块的数据(纯数据,由 HexMap 持有)
class HexTile extends RefCounted:
	var q: int = 0
	var r: int = 0
	var elevation: int = 0            # 0 平地 / 1 缓坡 / 2 丘陵 / 3 山脉
	var terrain: Terrain = Terrain.OCEAN
	var has_woods: bool = false       # 森林(圣地:每 2 格 +1)
	var has_fish: bool = false        # 鱼群(港口:每 2 格 +1)
	var is_city_center: bool = false
	var district: int = -1            # DistrictSystem.DistrictType 之一,-1 表示无


## 地块顶面高度(水面低于 0 层)
static func top_y(t: HexTile) -> float:
	if t.terrain == Terrain.OCEAN:
		return HexCore.WATER_Y
	return float(t.elevation) * HexCore.ELEV_H


static func terrain_name(t: HexTile) -> String:
	match t.terrain:
		Terrain.OCEAN:
			return "海洋"
		Terrain.GRASS:
			return "草原"
		Terrain.PLAINS:
			return "平原"
		Terrain.DESERT:
			return "沙漠"
	return "?"


static func elevation_name(e: int) -> String:
	match e:
		0:
			return "平地"
		1:
			return "缓坡"
		2:
			return "丘陵"
		3:
			return "山脉"
	return "?"


## 防御加成:丘陵 +3(文明 6 经典规则)
static func defense_bonus(t: HexTile) -> int:
	return 3 if t.elevation == HexCore.HILL else 0


## 移动消耗:山脉不可通行,丘陵 2,其余 1
static func move_cost(t: HexTile) -> int:
	if t.elevation >= HexCore.MOUNTAIN:
		return 99
	return 2 if t.elevation == HexCore.HILL else 1


var tiles: Dictionary[Vector2i, HexTile] = {}
var river_edges: Dictionary[String, bool] = {}     # 河流边集合,key = 排序后的 "q,r|q,r"
var city_coord := Vector2i.ZERO
var water_dist: Dictionary[Vector2i, int] = {}     # 每格到最近水域的步数(河流路由用)
var _rng := RandomNumberGenerator.new()


func generate(seed_value: int) -> void:
	_rng.seed = seed_value
	tiles.clear()
	river_edges.clear()
	_gen_base_tiles()
	_set_city_center()
	_carve_bay()
	_compute_water_dist()
	_gen_rivers(3)
	_route_city_river()
	_carve_river_valleys()
	_ensure_mountain_near_city()
	_ensure_hill_near_city()
	_gen_fish(4)
	_compute_water_dist()


## 海陆 / 海拔 / 气候 / 森林:全部由确定性值噪声驱动
func _gen_base_tiles() -> void:
	for q in range(-HexCore.RADIUS, HexCore.RADIUS + 1):
		for r in range(-HexCore.RADIUS, HexCore.RADIUS + 1):
			var coord := Vector2i(q, r)
			if HexCore.hex_distance(Vector2i.ZERO, coord) > HexCore.RADIUS:
				continue
			var td := HexTile.new()
			td.q = q
			td.r = r
			var d := HexCore.hex_distance(Vector2i.ZERO, coord)
			var coast := _noise2(q, r, 7)
			if float(d) > 4.4 + coast * 0.9:
				td.terrain = Terrain.OCEAN
				td.elevation = 0
			else:
				var h := _noise2(q, r, 13)
				if h > 0.45:
					td.elevation = 3
				elif h > 0.05:
					td.elevation = 2
				elif h > -0.35:
					td.elevation = 1
				else:
					td.elevation = 0
				var cl := _noise2(q, r, 29)
				if cl < -0.25:
					td.terrain = Terrain.DESERT
				elif cl < 0.3:
					td.terrain = Terrain.PLAINS
				else:
					td.terrain = Terrain.GRASS
				if td.elevation <= 1 and td.terrain != Terrain.DESERT and _noise2(q, r, 41) > 0.55:
					td.has_woods = true
			tiles[coord] = td


func _set_city_center() -> void:
	var t := tiles[city_coord]
	t.terrain = Terrain.GRASS
	t.elevation = 0
	t.has_woods = false
	t.is_city_center = true


## 若最近水域距城市超过 3 格,沿海湾方向开凿一条水道,保证港口可建
func _carve_bay() -> void:
	var nearest := Vector2i.ZERO
	var nd := 9999
	for coord in tiles:
		if tiles[coord].terrain != Terrain.OCEAN:
			continue
		var d := HexCore.hex_distance(city_coord, coord)
		if d < nd:
			nearest = coord
			nd = d
	if nd <= 3:
		return
	var cur := nearest
	var guard := 0
	while HexCore.hex_distance(city_coord, cur) > 2 and guard < 40:
		guard += 1
		_set_water(cur)
		var best_n := cur
		var best_d := 9999
		for d in HexCore.DIRS:
			var n := cur + d
			if not tiles.has(n):
				continue
			var dn := HexCore.hex_distance(city_coord, n)
			if dn < best_d:
				best_n = n
				best_d = dn
		if best_n == cur:
			break
		cur = best_n


func _set_water(coord: Vector2i) -> void:
	var t := tiles[coord]
	t.terrain = Terrain.OCEAN
	t.elevation = 0
	t.has_woods = false
	t.has_fish = false


## 多源 BFS:每格到最近水域的步数
func _compute_water_dist() -> void:
	water_dist.clear()
	var queue: Array[Vector2i] = []
	for coord in tiles:
		if tiles[coord].terrain == Terrain.OCEAN:
			water_dist[coord] = 0
			queue.append(coord)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d in HexCore.DIRS:
			var n := cur + d
			if not tiles.has(n) or water_dist.has(n):
				continue
			water_dist[n] = water_dist[cur] + 1
			queue.append(n)


## 自然河流:从高地发源(count 条),沿低处流向海洋
## 源头按"距海步数 + 海拔"排序,优先最深内陆的高地,保证河流足够长
func _gen_rivers(count: int) -> void:
	var sources: Array[Vector2i] = []
	for coord in tiles:
		var t := tiles[coord]
		if t.terrain == Terrain.OCEAN:
			continue
		if t.elevation < HexCore.HILL:
			continue
		if HexCore.hex_distance(city_coord, coord) < 3:
			continue
		sources.append(coord)
	sources.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var sa: int = int(water_dist.get(a, 0)) + tiles[a].elevation
		var sb: int = int(water_dist.get(b, 0)) + tiles[b].elevation
		return sa > sb)
	for i in mini(count, sources.size()):
		_route_to_water(sources[i])


## 保证城市临河(水渠的建造前提)
func _route_city_river() -> void:
	if adjacent_river_count(city_coord) > 0:
		return
	_route_to_water(city_coord)


## 贪心路由:每一步选"海拔最低、离海最近"的未访问邻居,直到入海
func _route_to_water(start: Vector2i) -> void:
	var cur := start
	var visited: Array[Vector2i] = [start]
	var steps := 0
	while steps < 60 and tiles[cur].terrain != Terrain.OCEAN:
		steps += 1
		var best := cur
		var best_score := 1e30
		var found := false
		for d in HexCore.DIRS:
			var n := cur + d
			if not tiles.has(n) or n in visited:
				continue
			var score := float(tiles[n].elevation * 4 + water_dist.get(n, 99))
			if score < best_score:
				best_score = score
				best = n
				found = true
		if not found:
			break
		_add_river_edge(cur, best)
		cur = best
		visited.append(cur)


## 河流边(端点排序后作 key,保证无向边唯一)
func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var x := a
	var y := b
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		x = b
		y = a
	return "%d,%d|%d,%d" % [x.x, x.y, y.x, y.y]


func _add_river_edge(a: Vector2i, b: Vector2i) -> void:
	river_edges[_edge_key(a, b)] = true


func is_river_edge(a: Vector2i, b: Vector2i) -> bool:
	return river_edges.has(_edge_key(a, b))


## 该地块相邻的河流边数量
func adjacent_river_count(coord: Vector2i) -> int:
	var n := 0
	for d in HexCore.DIRS:
		var nb := coord + d
		if tiles.has(nb) and is_river_edge(coord, nb):
			n += 1
	return n


## 河谷下切:临河的非山地块海拔 -1(山体不受侵蚀)
func _carve_river_valleys() -> void:
	for key: String in river_edges:
		var parts: PackedStringArray = key.split("|")
		_carve_one(_parse_coord(parts[0]))
		_carve_one(_parse_coord(parts[1]))


func _parse_coord(s: String) -> Vector2i:
	var p: PackedStringArray = s.split(",")
	return Vector2i(int(p[0]), int(p[1]))


func _carve_one(coord: Vector2i) -> void:
	var t := tiles[coord]
	if t.terrain != Terrain.OCEAN and t.elevation > 0 and t.elevation < HexCore.MOUNTAIN:
		t.elevation -= 1


## 城市 3 格内保证至少一座山脉(学院/圣地加成演示)
func _ensure_mountain_near_city() -> void:
	if _has_elev_near(city_coord, 3, HexCore.MOUNTAIN):
		return
	var cands: Array[Vector2i] = []
	for coord in tiles:
		var t := tiles[coord]
		if t.terrain != Terrain.OCEAN and t.elevation < HexCore.MOUNTAIN \
				and HexCore.hex_distance(city_coord, coord) == 3 and not t.is_city_center:
			cands.append(coord)
	if cands.is_empty():
		return
	tiles[cands[_rng.randi_range(0, cands.size() - 1)]].elevation = HexCore.MOUNTAIN


## 城市 3 格内保证至少一座丘陵(工业区加成演示)
func _ensure_hill_near_city() -> void:
	if _has_elev_near(city_coord, 3, HexCore.HILL):
		return
	var cands: Array[Vector2i] = []
	for coord in tiles:
		var t := tiles[coord]
		if t.terrain != Terrain.OCEAN and t.elevation < HexCore.HILL \
				and HexCore.hex_distance(city_coord, coord) <= 3 and not t.is_city_center:
			cands.append(coord)
	if cands.is_empty():
		return
	tiles[cands[_rng.randi_range(0, cands.size() - 1)]].elevation = HexCore.HILL


func _has_elev_near(center: Vector2i, radius: int, elev: int) -> bool:
	for coord in tiles:
		if HexCore.hex_distance(center, coord) <= radius \
				and tiles[coord].elevation == elev and tiles[coord].terrain != Terrain.OCEAN:
			return true
	return false


## 鱼群(海洋资源):优先沿海、离城 4 格内,供港口加成
func _gen_fish(count: int) -> void:
	var cands: Array[Vector2i] = []
	for coord in tiles:
		var t := tiles[coord]
		if t.terrain != Terrain.OCEAN or not has_land_neighbor(coord):
			continue
		cands.append(coord)
	var near: Array[Vector2i] = []
	for c in cands:
		if HexCore.hex_distance(city_coord, c) <= 4:
			near.append(c)
	if not near.is_empty():
		cands = near
	for i in mini(count, cands.size()):
		var pick := _rng.randi_range(0, cands.size() - 1)
		tiles[cands[pick]].has_fish = true
		cands.remove_at(pick)


## 是否有相邻陆地(港口建造前提)
func has_land_neighbor(coord: Vector2i) -> bool:
	for d in HexCore.DIRS:
		var n := coord + d
		if tiles.has(n) and tiles[n].terrain != Terrain.OCEAN:
			return true
	return false


## 整数格点 hash → [-1, 1)
func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 974634571) & 0x7fffffff
	return float(h) / 2147483647.0 * 2.0 - 1.0


## 值噪声:格点 hash 双线性插值,尺度 0.5(约两格一个起伏)
func _noise2(q: int, r: int, salt: int) -> float:
	var q0 := floori(float(q) * 0.5)
	var r0 := floori(float(r) * 0.5)
	var fq := float(q) * 0.5 - float(q0)
	var fr := float(r) * 0.5 - float(r0)
	var v00 := _hash01(q0, r0, salt)
	var v10 := _hash01(q0 + 1, r0, salt)
	var v01 := _hash01(q0, r0 + 1, salt)
	var v11 := _hash01(q0 + 1, r0 + 1, salt)
	return lerpf(lerpf(v00, v10, fq), lerpf(v01, v11, fq), fr)
