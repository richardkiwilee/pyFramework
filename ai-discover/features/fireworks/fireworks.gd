extends Node3D
## =============================================================================
## 粒子烟花 —— 点击夜空发射火箭，升到点击高度后炸成彩色光球
## =============================================================================
## 两个可复用的 GPUParticles3D（one_shot）：
##   · 火箭：单颗粒子从地面垂直升空，白热拖尾感；
##   · 爆裂：80 颗粒子球形四散 + 重力下坠，颜色每次随机 HSV。
## 交互：在画面上半部点击 → 烟花在点击高度爆炸（射线与 y=7 平面求交）。
## =============================================================================

const BURST_HEIGHT := 7.0     # 爆炸平面高度

var _rocket: GPUParticles3D
var _burst: GPUParticles3D

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# 地面（暗色）
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(50, 36)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.06, 0.07, 0.10)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	ground.position = Vector3(0, -0.05, -5)

	_rocket = _make_rocket()
	_burst = _make_burst()


func _make_rocket() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 1
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	var ppm := ParticleProcessMaterial.new()
	ppm.gravity = Vector3.ZERO
	ppm.direction = Vector3(0, 1, 0)
	ppm.spread = 2.0
	ppm.initial_velocity_min = 10.0
	ppm.initial_velocity_max = 11.0
	ppm.scale_min = 0.3
	ppm.scale_max = 0.3
	p.process_material = ppm
	var m := SphereMesh.new()
	m.radius = 0.13
	m.height = 0.26
	p.draw_pass_1 = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.3)
	mat.emission_energy_multiplier = 3.0
	p.material_override = mat
	add_child(p)
	return p


func _make_burst() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 80
	p.lifetime = 1.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	var ppm := ParticleProcessMaterial.new()
	ppm.gravity = Vector3(0, -5.5, 0)
	ppm.spread = 180.0
	ppm.initial_velocity_min = 4.5
	ppm.initial_velocity_max = 8.0
	ppm.scale_min = 0.4
	ppm.scale_max = 1.1
	ppm.damping_min = 20.0
	ppm.damping_max = 20.0
	p.process_material = ppm
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	p.draw_pass_1 = m
	add_child(p)
	return p


## 发射一枚烟花到 target 位置（火箭升空 → 0.75s 后爆裂）
func _launch(target: Vector3) -> void:
	_rocket.position = Vector3(target.x, 0.3, target.z)
	_rocket.restart()
	var tw := create_tween()
	tw.tween_interval(0.75)
	tw.tween_callback(_explode.bind(target))


func _explode(target: Vector3) -> void:
	_burst.position = target
	# 每次爆裂随机一种颜色（HSV 色相随机）
	var hue := randf()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(hue, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color.from_hsv(hue, 0.9, 0.75)
	mat.emission_energy_multiplier = 2.0
	_burst.material_override = mat
	_burst.restart()


## 鼠标点击 → 射线与爆炸平面求交
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target := _mouse_to_burst_plane(event.position)
		if target.y > 0.5:
			_launch(target)
			get_viewport().set_input_as_handled()


func _mouse_to_burst_plane(mpos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(mpos)
	var dir := camera.project_ray_normal(mpos)
	if dir.y >= -0.01:
		return Vector3.ZERO                     # 射线没指向地面方向
	var t := (BURST_HEIGHT - from.y) / dir.y   # 与 y=7 平面交点
	var hit := from + dir * t
	hit.x = clampf(hit.x, -9.0, 9.0)
	hit.z = clampf(hit.z, -13.0, 0.0)
	return hit
