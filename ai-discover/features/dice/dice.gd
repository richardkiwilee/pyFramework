extends Node3D
## =============================================================================
## 骰子 —— 程序化点数贴图 + 真实物理投掷 + 顶面自动读数
## =============================================================================
## · 六面点数贴图用代码生成（Image 画点 → ImageTexture），
##   对侧面之和 = 7（+Y=1 / -Y=6 / +X=5 / -X=2 / +Z=4 / -Z=3）；
## · 【掷骰子】给 RigidBody3D 随机力矩 + 上抛冲量，真实翻滚；
## · 骰子静止（sleeping）后按全局朝向判定顶面 → 读出点数，
##   记录最近 10 次历史。
## =============================================================================

const FACE_NORMALS: Array[Vector3] = [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK,
]
## BoxMesh 面的顺序：+X -X +Y -Y +Z -Z 对应的点数
const FACE_VALUES: Array[int] = [5, 2, 1, 6, 4, 3]

var _rolling := false
var _wait_time := 0.0
var _history: Array[int] = []

@onready var dice: RigidBody3D = $Dice
@onready var dice_mesh: MeshInstance3D = $Dice/Mesh
@onready var result_label: Label = $CanvasLayer/Bar/ResultLabel
@onready var history_label: Label = $CanvasLayer/Bar/HistoryLabel
@onready var roll_btn: Button = $CanvasLayer/Bar/RollBtn


func _ready() -> void:
	_apply_pips()
	roll_btn.pressed.connect(_roll)


## 生成六面点数贴图（对侧面之和 7）
## Godot 4 的 BoxMesh 只有 1 个 surface，无法逐面贴材质——
## 因此手工构建 6 个独立 surface 的 ArrayMesh，每面各挂一张点数贴图。
func _apply_pips() -> void:
	dice_mesh.mesh = _build_cube_mesh()
	for i in FACE_VALUES.size():
		var tex := _make_pip_texture(FACE_VALUES[i])
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 0.55
		dice_mesh.set_surface_override_material(i, mat)


## 六个面的 ArrayMesh（法线向外，每个面一个 surface）
func _build_cube_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()
	for n in FACE_NORMALS:
		# 面内两个正交方向（u × v = n，保证绕序对外）
		var u: Vector3 = Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
		var v: Vector3 = n.cross(u)
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		for corner in [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]]:
			verts.append(n * 0.5 + u * corner[0] + v * corner[1])
			uvs.append(Vector2(corner[0] + 0.5, 1.0 - (corner[1] + 0.5)))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _make_pip_texture(count: int) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.96, 0.94, 0.88))
	var dots: Dictionary = {
		1: [Vector2i(32, 32)],
		2: [Vector2i(16, 16), Vector2i(48, 48)],
		3: [Vector2i(16, 16), Vector2i(32, 32), Vector2i(48, 48)],
		4: [Vector2i(16, 16), Vector2i(48, 16), Vector2i(16, 48), Vector2i(48, 48)],
		5: [Vector2i(16, 16), Vector2i(48, 16), Vector2i(32, 32), Vector2i(16, 48), Vector2i(48, 48)],
		6: [Vector2i(16, 16), Vector2i(48, 16), Vector2i(16, 32), Vector2i(48, 32), Vector2i(16, 48), Vector2i(48, 48)],
	}
	for p in dots[count]:
		img.fill_rect(Rect2i(p - Vector2i(7, 7), Vector2i(14, 14)), Color(0.10, 0.10, 0.14))
	return ImageTexture.create_from_image(img)


func _roll() -> void:
	if _rolling:
		return
	_rolling = true
	_wait_time = 0.0
	roll_btn.disabled = true
	result_label.text = "🎲 骰子翻滚中…"
	# 上抛 + 随机旋转冲量
	dice.linear_velocity = Vector3.ZERO
	dice.angular_velocity = Vector3.ZERO
	dice.global_position = Vector3(0, 3.0, 0)
	dice.apply_central_impulse(Vector3(randf_range(-2.0, 2.0), randf_range(5.5, 7.5), randf_range(-2.0, 2.0)))
	dice.apply_torque_impulse(Vector3(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0), randf_range(-7.0, 7.0)))


func _process(delta: float) -> void:
	if not _rolling:
		return
	_wait_time += delta
	if dice.sleeping or _wait_time > 12.0:
		_finish_roll()


func _finish_roll() -> void:
	_rolling = false
	roll_btn.disabled = false
	var value := _top_face_value()
	_history.push_front(value)
	if _history.size() > 10:
		_history.pop_back()
	result_label.text = "🎲 掷出 %d 点！" % value
	var parts: Array[String] = []
	for v in _history:
		parts.append(str(v))
	history_label.text = "历史：" + "  ".join(parts)


## 按全局朝向找朝上的面 → 点数
func _top_face_value() -> int:
	var b := dice.global_transform.basis
	var best := 0
	var best_dot := -2.0
	for i in FACE_NORMALS.size():
		var d: float = (b * FACE_NORMALS[i]).dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best = i
	return FACE_VALUES[best]
