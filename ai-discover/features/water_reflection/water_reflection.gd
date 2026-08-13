extends Node3D
## =============================================================================
## 水面倒影 —— 3D 波光水面 + 经典"镜像复制"倒影
## =============================================================================
## 实现思路（无需屏幕空间反射，经典的廉价倒影技巧）：
##   1. 把所有场景物体放进 World 容器；
##   2. Mirror 容器 = 同一份场景构建逻辑的副本，scale.y = -1，
##      世界坐标 y 上下翻转后恰好就是"水面的镜面反射"；
##   3. 半透明水面（water.gdshader：波浪顶点位移 + 菲涅尔 + 波光高光）
##      盖在水面 y=0 处，下面的镜像世界透出来 → 倒影。
##
## 交互：左键拖拽旋转视角，滚轮拉近拉远。
## =============================================================================

const WaterShader = preload("res://features/water_reflection/water.gdshader")

var _yaw := 0.65          # 相机水平角
var _pitch := 0.40        # 相机俯角（0.15~0.9 可调）
var _dist := 23.0         # 相机距离

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_build_world($World)
	_build_world($Mirror)       # 同一套构建逻辑 → 天然镜像
	$Mirror.scale.y = -1.0      # 关键：y 翻转 = 水面反射
	_build_water()
	_update_camera()


# ------------------------------------------------------------------ 场景搭建
## 小岛 + 小屋 + 树 + 漂浮光球 + 石头（镜像两个容器各建一份）
func _build_world(holder: Node3D) -> void:
	# 小岛（浮在水面上的平台）
	_make_box(holder, Vector3(7.0, 1.6, 7.0), Vector3(0, -0.8, 0), Color(0.52, 0.58, 0.34))
	# 小屋：墙 + 红屋顶
	_make_box(holder, Vector3(2.4, 1.8, 2.0), Vector3(0, 0.9, 0), Color(0.78, 0.62, 0.42))
	_make_box(holder, Vector3(2.8, 0.5, 2.4), Vector3(0, 2.05, 0), Color(0.62, 0.24, 0.20))
	# 烟囱
	_make_box(holder, Vector3(0.4, 1.1, 0.4), Vector3(0.8, 2.6, -0.5), Color(0.5, 0.45, 0.4))
	# 两棵树
	_make_tree(holder, Vector3(-2.4, 0, -1.9))
	_make_tree(holder, Vector3(2.6, 0, 2.1))
	# 漂浮光球（带呼吸浮动动画）
	_make_orb(holder, Vector3(3.3, 2.4, -2.9))
	# 几块石头
	_make_box(holder, Vector3(0.9, 0.7, 0.8), Vector3(-1.3, 0.35, 2.1), Color(0.48, 0.48, 0.52))
	_make_box(holder, Vector3(0.7, 0.5, 0.7), Vector3(1.5, 0.25, -2.4), Color(0.44, 0.45, 0.5))


func _make_box(holder: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # 镜像面也可见
	m.material_override = mat
	holder.add_child(m)
	m.position = pos


func _make_tree(holder: Node3D, pos: Vector3) -> void:
	# 树干
	var t := MeshInstance3D.new()
	var trunk := CylinderMesh.new()
	trunk.height = 1.4
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.22
	t.mesh = trunk
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.42, 0.30, 0.20)
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	t.material_override = tm
	holder.add_child(t)
	t.position = pos + Vector3(0, 0.7, 0)
	# 树冠
	var c := MeshInstance3D.new()
	var crown := SphereMesh.new()
	crown.radius = 0.9
	crown.height = 1.8
	c.mesh = crown
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.24, 0.48, 0.20)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	c.material_override = cm
	holder.add_child(c)
	c.position = pos + Vector3(0, 2.0, 0)


func _make_orb(holder: Node3D, pos: Vector3) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	s.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.9, 0.45)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.15)
	m.emission_energy_multiplier = 2.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	s.material_override = m
	holder.add_child(s)
	s.position = pos
	# 上下呼吸浮动
	var tw := s.create_tween().set_loops()
	tw.tween_property(s, "position:y", pos.y + 0.6, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(s, "position:y", pos.y, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(70, 70)
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = WaterShader
	water.material_override = mat
	add_child(water)


# ------------------------------------------------------------------ 相机
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(10.0, _dist - 1.3)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(42.0, _dist + 1.3)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.005, 0.12, 0.95)
		_update_camera()


func _update_camera() -> void:
	var target := Vector3(0, 1.2, 0)
	camera.position = target + Vector3(
		cos(_yaw) * cos(_pitch),
		sin(_pitch),
		sin(_yaw) * cos(_pitch)
	) * _dist
	camera.look_at(target)
