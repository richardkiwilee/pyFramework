extends Node3D
## =============================================================================
## 粒子光环 —— 发光核心 + 双轨道粒子环（GPUParticles3D）
## =============================================================================
## · 核心：脉冲呼吸的发光球体；
## · 水平光环：600 粒子从环形发射器出生，切向初速 + 向心加速度 → 轨道环绕；
## · 倾斜光环：300 粒子挂在倾斜 Node3D 下的第二道环，陀螺仪式交错旋转；
## · 交互：左键拖拽旋转视角、滚轮缩放（观察三维结构）。
## 注意：粒子发光 energy 不宜 >2——全通道过曝会被色调映射压成纯白。
## =============================================================================

var _yaw := 0.6
var _pitch := 0.35
var _dist := 9.0
var _core: MeshInstance3D

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# 核心（呼吸脉冲）
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	_core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.7, 0.85, 1.0)
	cm.emission_enabled = true
	cm.emission = Color(0.45, 0.7, 1.0)
	cm.emission_energy_multiplier = 3.0
	_core.material_override = cm
	add_child(_core)
	var tw := _core.create_tween().set_loops()
	tw.tween_property(_core, "scale", Vector3(1.15, 1.15, 1.15), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_core, "scale", Vector3.ONE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	add_child(_make_ring())
	add_child(_make_disc())
	_update_camera()


## 轨道光环：环形发射 + 切向初速 + 向心加速度
func _make_ring() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 600
	p.lifetime = 3.0
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	ppm.emission_ring_axis = Vector3(0, 1, 0)
	ppm.emission_ring_radius = 1.7
	ppm.emission_ring_height = 0.06
	ppm.direction = Vector3(0, 0, 1)   # 切向
	ppm.spread = 0.0
	ppm.initial_velocity_min = 2.4
	ppm.initial_velocity_max = 3.0
	ppm.gravity = Vector3.ZERO
	ppm.radial_accel_min = -7.0       # 向心 → 轨道运动
	ppm.radial_accel_max = -7.0
	# 注意：scale 是相对粒子网格的倍率（0.05 × 3 = 0.15 世界单位 ≈ 10px）
	ppm.scale_min = 3.0
	ppm.scale_max = 3.0
	p.process_material = ppm
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	p.draw_pass_1 = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.60, 0.90)
	mat.emission_energy_multiplier = 1.6
	p.material_override = mat
	return p


## 倾斜光环：第二道环绕倾斜轴旋转（把整组粒子挂在一个倾斜的 Node3D 下，
## 环的切向逻辑不变、天然倾斜，从任何角度看都可见）
func _make_disc() -> Node3D:
	var holder := Node3D.new()
	holder.rotation.x = 1.15   # 绕 X 轴倾斜 ≈ 66°

	var p := GPUParticles3D.new()
	p.amount = 300
	p.lifetime = 2.5
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	ppm.emission_ring_axis = Vector3(0, 1, 0)
	ppm.emission_ring_radius = 1.05
	ppm.emission_ring_height = 0.05
	ppm.direction = Vector3(0, 0, 1)
	ppm.spread = 0.0
	ppm.initial_velocity_min = 3.2
	ppm.initial_velocity_max = 3.8
	ppm.gravity = Vector3.ZERO
	ppm.radial_accel_min = -10.0
	ppm.radial_accel_max = -10.0
	ppm.scale_min = 2.2
	ppm.scale_max = 2.2
	p.process_material = ppm
	var m := SphereMesh.new()
	m.radius = 0.04
	m.height = 0.08
	p.draw_pass_1 = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.35, 0.70)
	mat.emission_energy_multiplier = 1.5
	p.material_override = mat
	holder.add_child(p)
	return holder


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(4.0, _dist - 0.6)
			_update_camera()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(18.0, _dist + 0.6)
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
	camera.look_at(Vector3.ZERO)
