## 地图系统：结点（据点/小地点）+ 连线 + 建筑（对应 pydemo/game/map_system.py）。
## 据点 size 为整数槽位 1~5；标志性建筑走独立专用槽；建造即时无"建造中"。
class_name MapSystem
extends RefCounted

class Building:
	var id: String
	var type_id: String
	var name: String
	var produces: Dictionary = {}   # 资源 -> 数量
	var tier: String = ""           # landmark 档位 weak/medium/strong

	func _init(id_: String, type_id_: String, name_: String,
			produces_: Dictionary = {}, tier_: String = "") -> void:
		id = id_
		type_id = type_id_
		name = name_
		produces = produces_
		tier = tier_

class Stronghold:
	var id: String
	var name: String
	var size: int                    # 普通建筑槽数 1~5
	var owner: String = ""           # 阵营 id，"" 表示中立
	var is_capital: bool = false
	var landmark: Building = null    # 标志性建筑（独立专用槽）
	var buildings: Array = []        # [Building]
	var stationed_army_id: String = ""
	var x: int = 0
	var y: int = 0

	func _init(id_: String, name_: String, size_: int, owner_: String = "",
			is_capital_: bool = false, landmark_: Building = null,
			x_: int = 0, y_: int = 0) -> void:
		id = id_
		name = name_
		size = size_
		owner = owner_
		is_capital = is_capital_
		landmark = landmark_
		x = x_
		y = y_

	func slots() -> int:
		return size

	func free_slots() -> int:
		return size - buildings.size()

	func add_building(b: Building) -> bool:
		if free_slots() <= 0:
			return false
		buildings.append(b)
		return true

	## 本回合所有已建成建筑的产出汇总。
	func tick_produce() -> Dictionary:
		var gained: Dictionary = {}
		for b in buildings:
			for k in b.produces:
				gained[k] = int(gained.get(k, 0)) + int(b.produces[k])
		return gained

class MinorLocation:
	var id: String
	var name: String
	var terrain: String
	var x: int = 0
	var y: int = 0

	func _init(id_: String, name_: String, terrain_: String,
			x_: int = 0, y_: int = 0) -> void:
		id = id_
		name = name_
		terrain = terrain_
		x = x_
		y = y_

class Road:
	var a: String            # 端点节点 id（无向，存储时 a < b）
	var b: String
	var curve: float         # 曲线凸起：0=直线；正负=垂直于连线方向的凸起比例

	func _init(a_: String, b_: String, curve_: float = 0.0) -> void:
		a = a_
		b = b_
		curve = curve_

class GameMap:
	var strongholds: Dictionary = {}  # id -> Stronghold
	var minors: Dictionary = {}       # id -> MinorLocation
	var adj: Dictionary = {}          # id -> [邻居 id]（无向）
	var roads: Array = []             # [Road]（道路：坐标对 + 曲线信息，渲染用）

	func add_stronghold(s: Stronghold) -> void:
		strongholds[s.id] = s

	func add_minor(m: MinorLocation) -> void:
		minors[m.id] = m

	func add_edge(a: String, b: String) -> void:
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		if not adj[a].has(b):
			adj[a].append(b)
		if not adj[b].has(a):
			adj[b].append(a)

	## 道路与边不同：道路携带曲线信息用于地图虚线绘制（无向，规范存 a<b）。
	func add_road(a: String, b: String, curve: float = 0.0) -> void:
		var key_a := a
		var key_b := b
		if key_a > key_b:
			var t := key_a
			key_a = key_b
			key_b = t
		for r in roads:
			if r.a == key_a and r.b == key_b:
				r.curve = curve
				return
		roads.append(Road.new(key_a, key_b, curve))

	## 查询道路曲线值（无道路返回 0）。
	func road_curve(a: String, b: String) -> float:
		var key_a := a
		var key_b := b
		if key_a > key_b:
			var t := key_a
			key_a = key_b
			key_b = t
		for r in roads:
			if r.a == key_a and r.b == key_b:
				return r.curve
		return 0.0

	func node_name(nid: String) -> String:
		if strongholds.has(nid):
			return strongholds[nid].name
		return minors[nid].name

	func is_stronghold(nid: String) -> bool:
		return strongholds.has(nid)

	func neighbors(nid: String) -> Array:
		return adj.get(nid, [])

	func all_nodes() -> Array:
		var out: Array = []
		for k in strongholds:
			out.append(k)
		for k in minors:
			out.append(k)
		return out

	## 小地点地形（用于修正收集）；据点返回空串。
	func terrain_of(nid: String) -> String:
		if minors.has(nid):
			return minors[nid].terrain
		return ""
