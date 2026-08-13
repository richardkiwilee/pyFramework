extends Node3D
## =============================================================================
## 分屏双视角 —— 同一个 3D 世界同时渲染两个视角
## =============================================================================
## 屏幕左右各一个 SubViewport（共享同一个 World3D，场景只建一份）：
##   左：第三人称跟随视角（镜头始终跟在玩家身后）；
##   右：俯视战略视角（固定高空正交相机，全局态势）。
## WASD 移动玩家方块，两个视角同步看到它的移动。
## =============================================================================

const GridShader = preload("res://features/split_screen/grid.gdshader")

var _player: MeshInstance3D

@onready var follow_cam: Camera3D = $LeftView/SubViewportContainer/SubViewport/FollowCam
@onready var top_cam: Camera3D = $RightView/SubViewportContainer/SubViewport/TopCam


func _ready() -> void:
	_build_world()
	_player = _make_player()


func _build_world() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = GridShader
	ground.material_override = gm
	add_child(ground)

	for pos in [Vector3(-5, 0, -3), Vector3(6, 0, 5), Vector3(-2, 0, 7), Vector3(7, 0, -6)]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0, 2.4, 2.0)
		b.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.5, 0.3)
		b.material_override = mat
		add_child(b)
		b.position = pos + Vector3(0, 1.2, 0)


func _make_player() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.1, 1.1, 1.1)
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.9)
	mat.emission_energy_multiplier = 1.2
	m.material_override = mat
	add_child(m)
	m.position = Vector3(0, 0.55, 0)
	return m


func _process(delta: float) -> void:
	# WASD 移动玩家
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.z -= 1
	if Input.is_key_pressed(KEY_S):
		dir.z += 1
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if dir.length() > 0:
		_player.position += dir.normalized() * 6.0 * delta
		_player.position.x = clampf(_player.position.x, -14, 14)
		_player.position.z = clampf(_player.position.z, -14, 14)

	# 左屏：跟随视角（保持在玩家侧后方，始终看着玩家）
	var back := -dir.normalized() if dir.length() > 0 else Vector3(0, 0, 1)
	follow_cam.position = _player.position + back * 6.5 + Vector3(0, 3.4, 0)
	follow_cam.look_at(_player.position + Vector3(0, 0.6, 0))
