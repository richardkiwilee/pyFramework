class_name MapView
extends Node3D
## =============================================================================
## 地图视图 —— 把 HexMap 数据渲染成 3D 场景
## =============================================================================
## · 地形:每格一个六棱柱网格(顶点色,共享材质),高度 = 海拔 × ELEV_H,
##   陆地统一带 -0.35 的基座裙边,水面下沉到 -0.1、侧面直插海底;
## · 河流:沿共享边的蓝色飘带,贴在高的一侧地块顶面上方;
## · 城市:石地基 + 六边形城墙环(带垛口)+ 六座角楼 + 王宫 + 城名牌;
## · 区域:色块底座 + 各具特色的建筑群 + 悬空的加成标签(Label3D);
## · 高亮:悬停白圈 / 可建造绿圈 / 不可建造红圈 / 选中金圈 + 预览标签。
## =============================================================================

enum RingState { NONE, HOVER, VALID, INVALID }

var map: HexMap
var sys: DistrictSystem

var _terrain_mat: StandardMaterial3D
var _stone_vc_mat: StandardMaterial3D
var _river_mat: StandardMaterial3D
var _mat_hover: StandardMaterial3D
var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D
var _mat_selected: StandardMaterial3D
var _mat_stone: StandardMaterial3D
var _mat_white: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_roof_red: StandardMaterial3D
var _mat_roof_dark: StandardMaterial3D
var _mat_blue: StandardMaterial3D
var _mat_gold: StandardMaterial3D
var _mat_brick: StandardMaterial3D
var _mat_cream: StandardMaterial3D
var _mat_tree_green: StandardMaterial3D
var _mat_trunk: StandardMaterial3D
var _pad_mats: Dictionary[int, StandardMaterial3D] = {}

var _font: SystemFont
var _hover_ring: MeshInstance3D
var _sel_ring: MeshInstance3D
var _preview_label: Label3D

var _district_nodes: Dictionary[Vector2i, Node3D] = {}
var _bonus_labels: Dictionary[Vector2i, Label3D] = {}


func init(m: HexMap, s: DistrictSystem) -> void:
	map = m
	sys = s
	_make_materials()
	_build_terrain()
	_build_rivers()
	_build_city()
	_build_fish_and_trees()
	_build_highlight_rings()
	_build_preview_label()


## ----------------------------------------------------------------------------
## 材质与字体
## ----------------------------------------------------------------------------

func _make_materials() -> void:
	# 地形用无光照材质:顶点色即最终颜色,不受光照/色调映射洗色影响,
	# 明暗层次靠顶面色与侧壁色的差异(伪 AO)表达,风格类似文明 6 棋盘
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# 城墙/城市地基用受光照的顶点色材质,保留立体感
	_stone_vc_mat = StandardMaterial3D.new()
	_stone_vc_mat.vertex_color_use_as_albedo = true
	_stone_vc_mat.roughness = 0.9

	_river_mat = StandardMaterial3D.new()
	_river_mat.albedo_color = Color("3f9de0")
	_river_mat.emission_enabled = true
	_river_mat.emission = Color("2a7fc0")
	_river_mat.emission_energy_multiplier = 0.5
	_river_mat.roughness = 0.2
	_river_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_hover = _ring_mat(Color(0.95, 0.98, 1.0))
	_mat_valid = _ring_mat(Color(0.45, 0.9, 0.5))
	_mat_invalid = _ring_mat(Color(0.92, 0.38, 0.35))
	_mat_selected = _ring_mat(Color(1.0, 0.84, 0.35))
	_mat_stone = _solid_mat(Color("a8a49a"))
	_mat_white = _solid_mat(Color("f0ecdf"))
	_mat_dark = _solid_mat(Color("3c4250"))
	_mat_wood = _solid_mat(Color("8a6a4a"))
	_mat_roof_red = _solid_mat(Color("a03b2f"))
	_mat_roof_dark = _solid_mat(Color("4a3c34"))
	_mat_blue = _solid_mat(Color("3f6fb8"))
	_mat_gold = _solid_mat(Color("c9a23f"))
	_mat_brick = _solid_mat(Color("7a4a33"))
	_mat_cream = _solid_mat(Color("e8dcc0"))
	_mat_tree_green = _solid_mat(Color("3e6e34"))
	_mat_trunk = _solid_mat(Color("6b4c30"))

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])


func _solid_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _ring_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## ----------------------------------------------------------------------------
## 地形
## ----------------------------------------------------------------------------

func _tile_top_color(t: HexMap.HexTile) -> Color:
	var top := Color("8fbf5a")           # 草原:鲜绿
	if t.terrain == HexMap.Terrain.OCEAN:
		top = Color("3d83c9")            # 海洋
	elif t.elevation >= HexCore.MOUNTAIN:
		top = Color("d9dde2")            # 雪山
	elif t.terrain == HexMap.Terrain.PLAINS:
		top = Color("c2b25c")            # 平原:黄绿
	elif t.terrain == HexMap.Terrain.DESERT:
		top = Color("e0c576")            # 沙漠:暖黄
	if t.elevation == 1:
		top = top.darkened(0.06)
	elif t.elevation == HexCore.HILL:
		top = top.darkened(0.12)
	return top


func _build_terrain() -> void:
	for coord in map.tiles:
		var t := map.tiles[coord]
		var top_y := HexMap.top_y(t)
		var bottom_y := HexCore.SEA_FLOOR_Y if t.terrain == HexMap.Terrain.OCEAN else -0.35
		var top_col := _tile_top_color(t)
		var side_col := top_col.darkened(0.42)
		if t.elevation >= HexCore.MOUNTAIN:
			side_col = Color("7c7f86")
		var mi := MeshInstance3D.new()
		mi.mesh = MeshBuilder.prism(HexCore.HEX_R, top_y, bottom_y, top_col, side_col)
		mi.material_override = _terrain_mat
		mi.position = _tile_pos(t)
		add_child(mi)
	# 海底平面(整图垫底,让大陆像浮在海面上的岛屿)
	var floor_disc := MeshInstance3D.new()
	floor_disc.mesh = MeshBuilder.disc(HexCore.HEX_R * 8.6, Color("16325e"))
	floor_disc.material_override = _terrain_mat
	floor_disc.position = Vector3(0.0, HexCore.SEA_FLOOR_Y - 0.02, 0.0)
	add_child(floor_disc)


func _tile_pos(t: HexMap.HexTile) -> Vector3:
	var c := HexCore.center(t.q, t.r)
	return Vector3(c.x, 0.0, c.y)


## ----------------------------------------------------------------------------
## 河流:沿两格共享边的蓝色飘带
## ----------------------------------------------------------------------------

func _build_rivers() -> void:
	var root := Node3D.new()
	root.name = "Rivers"
	add_child(root)
	for key: String in map.river_edges:
		var parts: PackedStringArray = key.split("|")
		var a := _parse_coord(parts[0])
		var b := _parse_coord(parts[1])
		var ca := HexCore.center(a.x, a.y)
		var cb := HexCore.center(b.x, b.y)
		var mid := (ca + cb) * 0.5
		var edge_dir := (cb - ca).orthogonal().normalized()   # 垂直中心连线 = 沿边方向
		var half := HexCore.HEX_R * 0.5
		var p1 := mid - edge_dir * half
		var p2 := mid + edge_dir * half
		var y := maxf(HexMap.top_y(map.tiles[a]), HexMap.top_y(map.tiles[b])) + 0.045
		var mi := MeshInstance3D.new()
		mi.mesh = MeshBuilder.ribbon(p1, p2, y, 0.16, Color.WHITE)
		mi.material_override = _river_mat
		root.add_child(mi)


func _parse_coord(s: String) -> Vector2i:
	var p: PackedStringArray = s.split(",")
	return Vector2i(int(p[0]), int(p[1]))


## ----------------------------------------------------------------------------
## 城市:城墙环绕的首都
## ----------------------------------------------------------------------------

func _build_city() -> void:
	var t := map.tiles[map.city_coord]
	var root := Node3D.new()
	root.name = "City"
	root.position = _tile_pos(t) + Vector3(0.0, HexMap.top_y(t), 0.0)
	add_child(root)
	# 石质地基
	var pad := MeshInstance3D.new()
	pad.mesh = MeshBuilder.prism(HexCore.HEX_R * 0.86, 0.05, 0.0, Color("b9b3a5"), Color("8f8a7d"))
	pad.material_override = _stone_vc_mat
	root.add_child(pad)
	# 六边形城墙(环壁)
	var wall := MeshInstance3D.new()
	wall.mesh = MeshBuilder.wall_ring(HexCore.HEX_R * 0.8, HexCore.HEX_R * 0.62, 0.42,
			Color("b3afa2"), Color("817d71"))
	wall.material_override = _stone_vc_mat
	root.add_child(wall)
	# 垛口:沿墙 18 座小方墩
	for i in 18:
		var a := float(i) / 18.0 * TAU + TAU / 36.0
		var rmid := HexCore.HEX_R * 0.71
		_prim(root, _mat_stone, _box(Vector3(0.075, 0.09, 0.075)),
				Vector3(cos(a) * rmid, 0.47, sin(a) * rmid))
	# 六座角楼(圆柱 + 红锥顶)
	for i in 6:
		var a := PI / 6.0 + float(i) * PI / 3.0
		var px := cos(a) * HexCore.HEX_R * 0.71
		var pz := sin(a) * HexCore.HEX_R * 0.71
		_prim(root, _mat_stone, _cyl(0.1, 0.13, 0.58, 8), Vector3(px, 0.33, pz))
		_prim(root, _mat_roof_red, _cyl(0.01, 0.18, 0.22, 8), Vector3(px, 0.7, pz))
	# 王宫
	_prim(root, _mat_white, _box(Vector3(0.42, 0.3, 0.36)), Vector3(0.0, 0.2, 0.0))
	_prim(root, _mat_roof_red, _cyl(0.01, 0.3, 0.24, 4), Vector3(0.0, 0.47, 0.0))
	# 城名牌
	var lbl := _make_label("首都 · 城墙", 34)
	lbl.position = Vector3(0.0, 1.25, 0.0)
	root.add_child(lbl)


## ----------------------------------------------------------------------------
## 区域建筑与加成标签
## ----------------------------------------------------------------------------

## 重建所有区域视觉(建造后调用)
func rebuild_all_districts() -> void:
	for coord in _district_nodes:
		_district_nodes[coord].queue_free()
	_district_nodes.clear()
	_bonus_labels.clear()
	for coord in map.tiles:
		var t := map.tiles[coord]
		if t.district != DistrictSystem.DistrictType.NONE:
			place_district_visual(t)
	rebuild_labels()


func place_district_visual(t: HexMap.HexTile) -> void:
	var def := sys.get_def(t.district)
	var coord := Vector2i(t.q, t.r)
	var node := Node3D.new()
	node.position = _tile_pos(t) + Vector3(0.0, HexMap.top_y(t), 0.0)
	node.rotation.y = float(posmod(t.q * 7 + t.r * 13, 6)) * PI / 3.0
	add_child(node)
	_district_nodes[coord] = node
	# 色块底座
	var pad := MeshInstance3D.new()
	pad.mesh = MeshBuilder.prism(HexCore.HEX_R * 0.52, 0.05, 0.0, def.color, def.color.darkened(0.35))
	pad.material_override = _pad_mat(int(def.id))
	node.add_child(pad)
	_build_district_buildings(node, t, def)
	# 加成标签
	var lbl := _make_label("", 26)
	lbl.position = Vector3(0.0, 0.9, 0.0)
	node.add_child(lbl)
	_bonus_labels[coord] = lbl


func _pad_mat(id: int) -> StandardMaterial3D:
	if _pad_mats.has(id):
		return _pad_mats[id]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	_pad_mats[id] = m
	return m


func _build_district_buildings(node: Node3D, t: HexMap.HexTile, def: DistrictSystem.DistrictDef) -> void:
	match def.id:
		DistrictSystem.DistrictType.CAMPUS:
			_prim(node, _mat_white, _box(Vector3(0.34, 0.26, 0.28)), Vector3(0.0, 0.18, 0.0))
			_prim(node, _mat_blue, _box(Vector3(0.42, 0.07, 0.36)), Vector3(0.0, 0.34, 0.0))
			_prim(node, _mat_dark, _box(Vector3(0.14, 0.2, 0.14)), Vector3(0.3, 0.15, 0.12))
		DistrictSystem.DistrictType.HOLY_SITE:
			_prim(node, _mat_white, _box(Vector3(0.3, 0.24, 0.3)), Vector3(0.0, 0.17, 0.0))
			_prim(node, _mat_roof_red, _cyl(0.02, 0.26, 0.22, 4), Vector3(0.0, 0.4, 0.0))
			_prim(node, _mat_gold, _box(Vector3(0.08, 0.3, 0.08)), Vector3(0.0, 0.55, 0.0))
		DistrictSystem.DistrictType.COMMERCIAL_HUB:
			for i in 3:
				var a := float(i) / 3.0 * TAU
				var px := cos(a) * 0.22
				var pz := sin(a) * 0.22
				_prim(node, _mat_wood, _box(Vector3(0.2, 0.14, 0.18)), Vector3(px, 0.12, pz))
				var awning: StandardMaterial3D = _mat_roof_red
				if i == 1:
					awning = _mat_blue
				elif i == 2:
					awning = _mat_gold
				_prim(node, awning, _box(Vector3(0.27, 0.05, 0.2)), Vector3(px, 0.22, pz))
		DistrictSystem.DistrictType.INDUSTRIAL_ZONE:
			_prim(node, _mat_brick, _box(Vector3(0.36, 0.22, 0.3)), Vector3(0.0, 0.16, 0.0))
			_prim(node, _mat_roof_dark, _box(Vector3(0.42, 0.05, 0.36)), Vector3(0.0, 0.3, 0.0))
			_prim(node, _mat_stone, _cyl(0.05, 0.06, 0.42, 8), Vector3(0.14, 0.33, -0.08))
		DistrictSystem.DistrictType.THEATER_SQUARE:
			_prim(node, _mat_cream, _cyl(0.34, 0.3, 0.18, 16), Vector3(0.0, 0.12, 0.0))
			_prim(node, _mat_wood, _box(Vector3(0.14, 0.24, 0.1)), Vector3(0.0, 0.26, 0.16))
		DistrictSystem.DistrictType.AQUEDUCT:
			var dir := _river_dir(t)
			node.rotation.y = atan2(dir.x, dir.y)
			for k in 3:
				var z := 0.42 + float(k) * 0.26
				_prim(node, _mat_stone, _box(Vector3(0.52, 0.1, 0.1)), Vector3(0.0, 0.2, z))
				_prim(node, _mat_stone, _cyl(0.05, 0.05, 0.16, 8), Vector3(-0.21, 0.1, z))
				_prim(node, _mat_stone, _cyl(0.05, 0.05, 0.16, 8), Vector3(0.21, 0.1, z))
		DistrictSystem.DistrictType.HARBOR:
			_prim(node, _mat_wood, _box(Vector3(0.5, 0.06, 0.72)), Vector3(0.0, 0.08, 0.0))
			_prim(node, _mat_wood, _box(Vector3(0.5, 0.05, 0.72)), Vector3(0.12, 0.14, 0.1))
			_prim(node, _mat_white, _cyl(0.08, 0.1, 0.5, 10), Vector3(-0.28, 0.3, -0.2))
			_prim(node, _mat_roof_red, _cyl(0.01, 0.17, 0.16, 10), Vector3(-0.28, 0.6, -0.2))


## 指向相邻河流中心的方向(水渠铺设方向)
func _river_dir(t: HexMap.HexTile) -> Vector2:
	var sum := Vector2.ZERO
	var self_coord := Vector2i(t.q, t.r)
	for d in HexCore.DIRS:
		var n := self_coord + d
		if map.tiles.has(n) and map.is_river_edge(self_coord, n):
			sum += HexCore.center(n.x, n.y) - HexCore.center(t.q, t.r)
	if sum == Vector2.ZERO:
		return Vector2(0.0, 1.0)
	return sum.normalized()


## 刷新所有区域加成标签
func rebuild_labels() -> void:
	for coord in _bonus_labels:
		var t := map.tiles[coord]
		var def := sys.get_def(t.district)
		var adj := sys.adjacency(map, t.district, coord)
		var lbl := _bonus_labels[coord]
		lbl.text = "%s\n+%d %s" % [def.name, adj.total, def.yield_name]
		lbl.modulate = def.color.lightened(0.35)


## ----------------------------------------------------------------------------
## 鱼群与森林
## ----------------------------------------------------------------------------

func _build_fish_and_trees() -> void:
	for coord in map.tiles:
		var t := map.tiles[coord]
		var c := HexCore.center(t.q, t.r)
		var y := HexMap.top_y(t)
		if t.has_fish:
			for i in 3:
				var ox := (float(i) - 1.0) * 0.14
				var oz := float(posmod(t.q * 5 + t.r * 11 + i * 3, 5) - 2) * 0.07
				var mi := MeshInstance3D.new()
				mi.mesh = _box(Vector3(0.1, 0.03, 0.05))
				mi.material_override = _mat_white
				mi.position = Vector3(c.x + ox, y + 0.05, c.y + oz)
				add_child(mi)
		elif t.has_woods:
			var count := 2 + posmod(t.q + t.r, 2)
			for i in count:
				var a := float(posmod(t.q * 17 + t.r * 23 + i * 41, 360)) * PI / 180.0
				var rr := 0.14 + float(posmod(t.q * 7 + i * 13, 10)) * 0.02
				_tree(c.x + cos(a) * rr, c.y + sin(a) * rr, y)


func _tree(x: float, z: float, y: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, y, z)
	add_child(root)
	_prim(root, _mat_trunk, _cyl(0.03, 0.05, 0.16, 6), Vector3(0.0, 0.08, 0.0))
	_prim(root, _mat_tree_green, _cyl(0.01, 0.11, 0.24, 8), Vector3(0.0, 0.26, 0.0))


## ----------------------------------------------------------------------------
## 高亮环与预览标签
## ----------------------------------------------------------------------------

func _build_highlight_rings() -> void:
	_hover_ring = _make_ring(_mat_hover)
	_sel_ring = _make_ring(_mat_selected)


func _make_ring(mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.ring(HexCore.HEX_R * 1.0, HexCore.HEX_R * 0.9, Color.WHITE)
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi


func set_hover(coord: Vector2i, state: int) -> void:
	if state == RingState.NONE or not map.tiles.has(coord):
		_hover_ring.visible = false
		return
	var t := map.tiles[coord]
	var m: StandardMaterial3D = _mat_hover
	match state:
		RingState.VALID:
			m = _mat_valid
		RingState.INVALID:
			m = _mat_invalid
	_hover_ring.material_override = m
	_hover_ring.visible = true
	var c := HexCore.center(t.q, t.r)
	_hover_ring.position = Vector3(c.x, HexMap.top_y(t) + 0.04, c.y)


func set_selected(td: HexMap.HexTile) -> void:
	if td == null:
		_sel_ring.visible = false
		return
	var c := HexCore.center(td.q, td.r)
	_sel_ring.visible = true
	_sel_ring.position = Vector3(c.x, HexMap.top_y(td) + 0.04, c.y)


func _build_preview_label() -> void:
	_preview_label = _make_label("", 30)
	_preview_label.visible = false
	add_child(_preview_label)


func set_preview(td: HexMap.HexTile, text: String, color: Color) -> void:
	if td == null or text == "":
		_preview_label.visible = false
		return
	var c := HexCore.center(td.q, td.r)
	_preview_label.visible = true
	_preview_label.text = text
	_preview_label.modulate = color
	_preview_label.position = Vector3(c.x, HexMap.top_y(td) + 1.15, c.y)


## ----------------------------------------------------------------------------
## 拾取:射线与各格顶面求交 + 六边形内判定
## ----------------------------------------------------------------------------

func pick_tile(cam: Camera3D, screen_pos: Vector2) -> HexMap.HexTile:
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.y) < 0.0001:
		return null
	var best: HexMap.HexTile = null
	var best_t := 1e30
	for coord in map.tiles:
		var t := map.tiles[coord]
		var y := HexMap.top_y(t)
		var tt := (y - o.y) / d.y
		if tt <= 0.0 or tt >= best_t:
			continue
		var hit := o + d * tt
		if HexCore.axial_round(Vector2(hit.x, hit.z)) == coord:
			best = t
			best_t = tt
	return best


## ----------------------------------------------------------------------------
## 小工具
## ----------------------------------------------------------------------------

func _make_label(text: String, size: int) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font = _font
	lbl.font_size = size
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0.05, 0.05, 0.08)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


func _prim(parent: Node3D, mat: StandardMaterial3D, mesh: Mesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl(top_r: float, bottom_r: float, h: float, radial: int) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = radial
	return m


## ----------------------------------------------------------------------------
## 网格构建器:手写顶点数组(顶点色 + 平面法线),绕序自校正
## ----------------------------------------------------------------------------

class MeshBuilder extends RefCounted:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()


	## 四边形 a(顶1) b(顶2) c(底1) d(底2),法线 n;绕序按 n 自动校正
	## 顶点色入线性:引擎把 COLOR 数组当线性值、输出时做 sRGB 编码,
	## 预先 srgb_to_linear 后往返正好还原指定的 sRGB 颜色
	func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
			col_top: Color, col_bottom: Color) -> void:
		var base := verts.size()
		verts.append(a)
		verts.append(b)
		verts.append(c)
		verts.append(d)
		for i in 4:
			norms.append(n)
		var lt := col_top.srgb_to_linear()
		var lb := col_bottom.srgb_to_linear()
		cols.append(lt)
		cols.append(lt)
		cols.append(lb)
		cols.append(lb)
		if (b - a).cross(c - a).dot(n) >= 0.0:
			idx.append(base + 0)
			idx.append(base + 1)
			idx.append(base + 2)
			idx.append(base + 1)
			idx.append(base + 3)
			idx.append(base + 2)
		else:
			idx.append(base + 0)
			idx.append(base + 2)
			idx.append(base + 1)
			idx.append(base + 1)
			idx.append(base + 2)
			idx.append(base + 3)


	## 六边形顶面扇形(pts 逆时针,法线向上)
	## Godot 前向面为逆时针绕序:三角形取 (c, p_i, p_j),从上方看为逆时针,
	## 否则顶面会被背面剔除(只剩侧壁)。
	func add_top_hex(pts: PackedVector2Array, y: float, color: Color) -> void:
		var base := verts.size()
		verts.append(Vector3(0.0, y, 0.0))
		norms.append(Vector3.UP)
		var lc := color.srgb_to_linear()
		cols.append(lc)
		for p in pts:
			verts.append(Vector3(p.x, y, p.y))
			norms.append(Vector3.UP)
			cols.append(lc)
		for i in pts.size():
			var j := (i + 1) % pts.size()
			idx.append(base)
			idx.append(base + 1 + i)
			idx.append(base + 1 + j)


	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


	## 六棱柱(顶面 + 侧面,侧面内缩 0.004 避免邻格共面闪烁)
	static func prism(radius: float, top_y: float, bottom_y: float,
			top_color: Color, side_color: Color) -> ArrayMesh:
		var mb := MeshBuilder.new()
		var pts := HexCore.corners(0, 0, radius)
		mb.add_top_hex(pts, top_y, top_color)
		if top_y > bottom_y + 0.001:
			for i in 6:
				var p1 := pts[i]
				var p2 := pts[(i + 1) % 6]
				var mid := (p1 + p2).normalized()
				var n3 := Vector3(mid.x, 0.0, mid.y)
				var inset := mid * 0.004
				mb.add_quad(
					Vector3(p1.x + inset.x, top_y, p1.y + inset.y),
					Vector3(p2.x + inset.x, top_y, p2.y + inset.y),
					Vector3(p1.x + inset.x, bottom_y, p1.y + inset.y),
					Vector3(p2.x + inset.x, bottom_y, p2.y + inset.y),
					n3, side_color, side_color.darkened(0.18))
		return mb.commit()


	## 平坦六边形片
	static func disc(radius: float, color: Color) -> ArrayMesh:
		var mb := MeshBuilder.new()
		mb.add_top_hex(HexCore.corners(0, 0, radius), 0.0, color)
		return mb.commit()


	## 高亮环(外圈 - 内圈)
	static func ring(outer: float, inner: float, color: Color) -> ArrayMesh:
		var mb := MeshBuilder.new()
		var op := HexCore.corners(0, 0, outer)
		var ip := HexCore.corners(0, 0, inner)
		for i in 6:
			var j := (i + 1) % 6
			mb.add_quad(
				Vector3(op[i].x, 0.0, op[i].y), Vector3(op[j].x, 0.0, op[j].y),
				Vector3(ip[i].x, 0.0, ip[i].y), Vector3(ip[j].x, 0.0, ip[j].y),
				Vector3.UP, color, color)
		return mb.commit()


	## 河流飘带:沿 p1-p2、横向宽 width 的水平条
	static func ribbon(p1: Vector2, p2: Vector2, y: float, width: float, color: Color) -> ArrayMesh:
		var mb := MeshBuilder.new()
		var dir := (p2 - p1).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var a := p1 + perp * width * 0.5
		var b := p1 - perp * width * 0.5
		var c := p2 + perp * width * 0.5
		var d := p2 - perp * width * 0.5
		mb.add_quad(
			Vector3(a.x, y, a.y), Vector3(b.x, y, b.y),
			Vector3(c.x, y, c.y), Vector3(d.x, y, d.y),
			Vector3.UP, color, color)
		return mb.commit()


	## 城墙:顶面环 + 外壁 + 内壁
	static func wall_ring(outer: float, inner: float, height: float,
			top_color: Color, side_color: Color) -> ArrayMesh:
		var mb := MeshBuilder.new()
		var op := HexCore.corners(0, 0, outer)
		var ip := HexCore.corners(0, 0, inner)
		for i in 6:
			var j := (i + 1) % 6
			mb.add_quad(
				Vector3(op[i].x, height, op[i].y), Vector3(op[j].x, height, op[j].y),
				Vector3(ip[i].x, height, ip[i].y), Vector3(ip[j].x, height, ip[j].y),
				Vector3.UP, top_color, top_color)
		for i in 6:
			var j := (i + 1) % 6
			var mid := (op[i] + op[j]).normalized()
			var n3 := Vector3(mid.x, 0.0, mid.y)
			mb.add_quad(
				Vector3(op[i].x, height, op[i].y), Vector3(op[j].x, height, op[j].y),
				Vector3(op[i].x, 0.0, op[i].y), Vector3(op[j].x, 0.0, op[j].y),
				n3, side_color, side_color.darkened(0.15))
		for i in 6:
			var j := (i + 1) % 6
			var mid := (ip[i] + ip[j]).normalized()
			var n3 := Vector3(-mid.x, 0.0, -mid.y)
			mb.add_quad(
				Vector3(ip[i].x, height, ip[i].y), Vector3(ip[j].x, height, ip[j].y),
				Vector3(ip[i].x, 0.0, ip[i].y), Vector3(ip[j].x, 0.0, ip[j].y),
				n3, side_color, side_color.darkened(0.15))
		return mb.commit()
