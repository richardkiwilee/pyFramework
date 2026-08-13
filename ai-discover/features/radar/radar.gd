extends Node3D
## =============================================================================
## 小地图雷达 —— SubViewport 俯视小地图 + 旋转扫描线 + 巡逻智能体
## =============================================================================
## 右下角的小地图是一台【俯视正交相机】渲染进 SubViewport 的结果
## （与主相机共享同一个 3D 世界，智能体在两边同时可见）；
## 雷达装饰（同心圆环 + 旋转扫描扇）是 SubViewport 里的 2D 层。
## 主场景：6 个发光的巡逻智能体随机游走，箱体障碍做空间参照。
## 交互：左键拖拽旋转主视角，滚轮缩放。
## =============================================================================

const GridShader = preload("res://features/radar/grid.gdshader")

const AGENT_COLORS: Array[Color] = [
	Color(1.0, 0.30, 0.30), Color(0.35, 1.0, 0.40), Color(0.35, 0.60, 1.0),
	Color(1.0, 0.85, 0.25), Color(0.80, 0.40, 1.0), Color(0.30, 1.0, 0.95),
]

var _yaw := 0.65
var _pitch := 0.42
var _dist := 24.0
var _sweep_angle := 0.0
var _agents: Array = []      # 每项 {mesh, target, speed}

@onready var camera: Camera3D = $Camera3D
@onready var sweep: Control = $Minimap/SubViewportContainer/SubViewport/Sweep


func _ready() -> void:
	_build_ground()
	_build_obstacles()
	_build_agents()
	_update_camera()


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(46, 46)
	ground.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = GridShader
	ground.material_override = gm
	add_child(ground)


func _build_obstacles() -> void:
	for pos in [Vector3(-6, 0, -4), Vector3(5, 0, 6), Vector3(-2, 0, 8), Vector3(8, 0, -7), Vector3(0, 0, -10)]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 2.8, 2.2)
		b.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.58, 0.50)
		b.material_override = mat
		add_child(b)
		b.position = pos + Vector3(0, 1.4, 0)


func _build_agents() -> void:
	for i in AGENT_COLORS.size():
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.45
		cm.height = 2.0
		m.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = AGENT_COLORS[i]
		mat.emission_enabled = true
		mat.emission = AGENT_COLORS[i]
		mat.emission_energy_multiplier = 1.8
		m.material_override = mat
		add_child(m)
		m.position = Vector3(randf_range(-16, 16), 1.0, randf_range(-16, 16))
		_agents.append({
			"mesh": m,
			"target": Vector3(randf_range(-16, 16), 0, randf_range(-16, 16)),
			"speed": randf_range(2.5, 5.5),
		})


func _process(delta: float) -> void:
	# 智能体巡逻：朝目标走，到了换新目标
	for a in _agents:
		var mesh: MeshInstance3D = a["mesh"]
		var to: Vector3 = a["target"] - mesh.position
		to.y = 0.0
		if to.length() < 0.6:
			a["target"] = Vector3(randf_range(-16, 16), 0, randf_range(-16, 16))
		else:
			mesh.position += to.normalized() * a["speed"] * delta
	# 雷达扫描旋转（GDScript 没有 TIME，手动累加角度）
	_sweep_angle += delta * 1.4
	sweep.rotation = _sweep_angle


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(12.0, _dist - 1.3)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(40.0, _dist + 1.3)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.005, 0.15, 0.9)
		_update_camera()


func _update_camera() -> void:
	var target := Vector3(0, 1.0, 0)
	camera.position = target + Vector3(
		cos(_yaw) * cos(_pitch),
		sin(_pitch),
		sin(_yaw) * cos(_pitch)
	) * _dist
	camera.look_at(target)
