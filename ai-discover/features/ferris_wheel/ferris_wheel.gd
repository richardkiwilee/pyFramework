extends Node3D
## =============================================================================
## 摩天轮 —— 3D 转轮 + 吊舱始终保持竖直 + 彩灯
## =============================================================================
## · 8 个吊舱绕轮心匀速旋转，吊舱位置随转轮、姿态独立保持竖直；
## · 辐条与彩灯随轮转动，夜空点缀星星（自发光小球）；
## · 鼠标拖拽环绕观察、滚轮缩放。
## 吊舱位置（_cabin_pos）为纯函数，可确定性测试。
## =============================================================================

const CABIN_COUNT := 8
const RADIUS := 6.0

var _angle := 0.0
var _speed := 0.3
var _cabins: Array = []      # {mesh, base_angle}
var _yaw := 0.6
var _pitch := 0.35
var _dist := 20.0

@onready var wheel: Node3D = $Wheel
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# 地面
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.14, 0.16, 0.12)
	ground.material_override = gmat
	add_child(ground)
	ground.position = Vector3(0, -0.5, 0)
	# 支撑架（两个斜腿）
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = 8.5
		cyl.top_radius = 0.2
		cyl.bottom_radius = 0.2
		leg.mesh = cyl
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.5, 0.52, 0.6)
		leg.material_override = lmat
		add_child(leg)
		leg.position = Vector3(side * 3.2, 3.8, 0)
		leg.rotation.z = -side * 0.7
	_build_wheel()
	_build_cabins()
	_build_stars()
	_update_camera()


func _build_wheel() -> void:
	# 轮辋
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.25
	torus.outer_radius = RADIUS + 0.25
	rim.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.85, 0.8, 0.75)
	rim.material_override = rmat
	wheel.add_child(rim)
	# 辐条 + 彩灯
	for i in CABIN_COUNT:
		var a := TAU * i / CABIN_COUNT
		var spoke := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = RADIUS * 2.0
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.08
		spoke.mesh = cyl
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.6, 0.62, 0.7)
		spoke.material_override = smat
		spoke.rotation.z = PI / 2.0
		spoke.rotation.y = -a
		wheel.add_child(spoke)
		var light := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		light.mesh = sm
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color.from_hsv(float(i) / CABIN_COUNT, 0.85, 1.0)
		lmat.emission_enabled = true
		lmat.emission = lmat.albedo_color
		lmat.emission_energy_multiplier = 1.8
		light.material_override = lmat
		light.position = Vector3(cos(a) * RADIUS, 0, sin(a) * RADIUS)
		wheel.add_child(light)


func _build_cabins() -> void:
	for i in CABIN_COUNT:
		var cabin := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 1.5, 1.6)
		cabin.mesh = bm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color.from_hsv(float(i) / CABIN_COUNT, 0.6, 0.9)
		cabin.material_override = cmat
		add_child(cabin)
		_cabins.append({"mesh": cabin, "base_angle": TAU * i / CABIN_COUNT})


func _build_stars() -> void:
	for i in 40:
		var star := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		star.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.emission_enabled = true
		smat.emission = Color(1, 1, 1)
		star.material_override = smat
		add_child(star)
		star.position = Vector3(randf_range(-40, 40), randf_range(8, 30), randf_range(-40, 40))


## 吊舱位置（供绘制与测试）：随转轮角度，保持竖直由调用方处理
func _cabin_pos(base_angle: float, wheel_angle: float) -> Vector3:
	var a := base_angle + wheel_angle
	return Vector3(cos(a) * RADIUS, sin(a) * RADIUS, 0)


func _process(delta: float) -> void:
	_angle += _speed * delta
	wheel.rotation.z = _angle
	for c in _cabins:
		var pos := _cabin_pos(c["base_angle"], _angle)
		c["mesh"].position = pos
		c["mesh"].rotation = Vector3.ZERO   # 吊舱保持竖直


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(8.0, _dist - 0.8)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(40.0, _dist + 0.8)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.005, 0.1, 0.9)
		_update_camera()


func _update_camera() -> void:
	camera.position = Vector3(
		cos(_yaw) * cos(_pitch),
		sin(_pitch),
		sin(_yaw) * cos(_pitch)
	) * _dist
	camera.look_at(Vector3(0, 2, 0))
