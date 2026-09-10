extends RefCounted
## 程序化网格工厂：地形棱柱、六边形圆盘、六边形环、共享材质。

const TerrainData := preload("res://scripts/data/terrain_data.gd")

static var _top_mats: Dictionary = {}
static var _side_mats: Dictionary = {}
static var _hover_mats: Dictionary = {}
static var _disc_meshes: Dictionary = {}
static var _ring_mesh: ArrayMesh = null


## flat-top 六边形顶点（从上方看为顺时针 = Godot 正面绕序），XZ 平面
static func hex_corners(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a: float = i * PI / 3.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts


static func terrain_top_material(t: int) -> StandardMaterial3D:
	if not _top_mats.has(t):
		_top_mats[t] = unshaded_material(TerrainData.TOP_COLOR.get(t, Color.WHITE))
	return _top_mats[t]


static func terrain_side_material(t: int) -> StandardMaterial3D:
	if not _side_mats.has(t):
		_side_mats[t] = unshaded_material(TerrainData.SIDE_COLOR.get(t, Color.GRAY))
	return _side_mats[t]


static func unshaded_material(color: Color, alpha: float = 1.0, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func hover_material(color: Color, alpha: float, priority: int = 0) -> StandardMaterial3D:
	var key: String = "%s_%s_%d" % [color.to_html(), alpha, priority]
	if not _hover_mats.has(key):
		var m: StandardMaterial3D = unshaded_material(color, alpha, true)
		# 标记物永远画在最上层，避免与顶面 0.02~0.03 深度差被深度缓冲吃掉
		m.no_depth_test = true
		m.render_priority = priority
		_hover_mats[key] = m
	return _hover_mats[key]


## 六边形圆盘（高亮用）
static func disc_mesh(radius: float) -> ArrayMesh:
	var key: String = "disc_%.2f" % radius
	if _disc_meshes.has(key):
		return _disc_meshes[key]
	var pts := hex_corners(radius)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	for p in pts:
		verts.append(Vector3(p.x, 0.0, p.y))
		normals.append(Vector3.UP)
	var idx := PackedInt32Array()
	for i in 6:
		idx.append(0)
		idx.append(i + 1)
		idx.append((i + 1) % 6 + 1)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(verts, normals, idx))
	_disc_meshes[key] = mesh
	return mesh


## 六边形环（领土标记用）
static func ring_mesh(outer: float, inner: float) -> ArrayMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var op := hex_corners(outer)
	var ip := hex_corners(inner)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in 6:
		verts.append(Vector3(op[i].x, 0.0, op[i].y))
		normals.append(Vector3.UP)
	for i in 6:
		verts.append(Vector3(ip[i].x, 0.0, ip[i].y))
		normals.append(Vector3.UP)
	var idx := PackedInt32Array()
	for i in 6:
		var j: int = (i + 1) % 6
		idx.append(i)
		idx.append(6 + i)
		idx.append(6 + j)
		idx.append(i)
		idx.append(6 + j)
		idx.append(j)
	_ring_mesh = ArrayMesh.new()
	_ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(verts, normals, idx))
	return _ring_mesh


static func _arrays(verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays
