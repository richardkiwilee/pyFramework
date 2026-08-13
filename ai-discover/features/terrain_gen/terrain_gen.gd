extends Node3D
## =============================================================================
## 程序化地形 —— fbm 噪声高度图 → 彩色网格地形 + 水面
## =============================================================================
## · 60×60 顶点网格，高度由 4 层 value noise 叠加（fbm）生成；
## · 顶点色按高度分带：沙滩 → 草地 → 岩石 → 雪顶；
## · 法线用高度图中心差分计算，光照自然；
## · 【🎲 重新生成】换随机种子；左键拖拽旋转视角、滚轮缩放。
## =============================================================================

const GRID := 60          # 顶点网格 60×60
const SPACING := 1.6      # 顶点间距
const WATER_LEVEL := 2.6

var _terrain: MeshInstance3D
var _water: MeshInstance3D
var _seed := 0
var _yaw := 0.6
var _pitch := 0.5
var _dist := 34.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	$CanvasLayer/Bar/RegenBtn.pressed.connect(_regenerate)
	_generate(0)
	_update_camera()


func _regenerate() -> void:
	_seed += 1
	_generate(_seed)


# ============================================================
#  噪声
# ============================================================
func _hash2(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n & 0x7fffffff) % 1000) / 1000.0


func _vnoise(x: float, y: float) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - xi
	var yf := y - yi
	xf = xf * xf * (3.0 - 2.0 * xf)
	yf = yf * yf * (3.0 - 2.0 * yf)
	return lerp(
		lerp(_hash2(xi, yi), _hash2(xi + 1, yi), xf),
		lerp(_hash2(xi, yi + 1), _hash2(xi + 1, yi + 1), xf),
		yf)


func _height_at(x: float, y: float) -> float:
	var v := 0.0
	var amp := 3.2
	var freq := 0.055
	for i in 4:
		v += amp * _vnoise(x * freq + _seed * 13.7, y * freq + _seed * 7.3)
		amp *= 0.5
		freq *= 2.1
	return v


## 高度 → 顶点色（沙滩/草地/岩石/雪顶）
func _color_for_height(h: float) -> Color:
	if h < WATER_LEVEL + 0.5:
		return Color(0.72, 0.66, 0.45)      # 沙滩
	if h < 5.0:
		return Color(0.32, 0.55, 0.25)      # 草地
	if h < 7.0:
		return Color(0.5, 0.46, 0.42)       # 岩石
	return Color(0.92, 0.92, 0.95)          # 雪顶


func _generate(seed: int) -> void:
	_seed = seed
	if _terrain != null:
		_terrain.queue_free()
	if _water != null:
		_water.queue_free()

	# 高度场
	var heights := PackedFloat32Array()
	heights.resize((GRID + 1) * (GRID + 1))
	for z in GRID + 1:
		for x in GRID + 1:
			heights[z * (GRID + 1) + x] = _height_at(x, z)

	# 构建网格（顶点色 + 中心差分法线）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in GRID:
		for x in GRID:
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var gx: int = x + corner.x
				var gz: int = z + corner.y
				var h: float = heights[gz * (GRID + 1) + gx]
				st.set_color(_color_for_height(h))
				st.set_normal(_normal_at(gx, gz, heights))
				st.add_vertex(Vector3(gx * SPACING, h, gz * SPACING))
	_terrain = MeshInstance3D.new()
	_terrain.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	_terrain.material_override = mat
	add_child(_terrain)
	# 偏移到网格中心
	_terrain.position = Vector3(-GRID * SPACING / 2.0, 0, -GRID * SPACING / 2.0)

	# 水面（半透明蓝色平面）
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GRID * SPACING * 1.2, GRID * SPACING * 1.2)
	_water.mesh = plane
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.15, 0.45, 0.75, 0.65)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.2
	_water.material_override = wmat
	_water.position = Vector3(0, WATER_LEVEL, 0)
	add_child(_water)


## 法线 = 高度图中心差分
func _normal_at(x: int, z: int, heights: PackedFloat32Array) -> Vector3:
	var hl := heights[z * (GRID + 1) + maxi(0, x - 1)]
	var hr := heights[z * (GRID + 1) + mini(GRID, x + 1)]
	var hd := heights[maxi(0, z - 1) * (GRID + 1) + x]
	var hu := heights[mini(GRID, z + 1) * (GRID + 1) + x]
	return Vector3(hl - hr, 2.0 * SPACING, hd - hu).normalized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(18.0, _dist - 1.5)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(60.0, _dist + 1.5)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.005, 0.2, 0.85)
		_update_camera()


func _update_camera() -> void:
	var target := Vector3(0, 4.0, 0)
	camera.position = target + Vector3(
		cos(_yaw) * cos(_pitch),
		sin(_pitch),
		sin(_yaw) * cos(_pitch)
	) * _dist
	camera.look_at(target)
