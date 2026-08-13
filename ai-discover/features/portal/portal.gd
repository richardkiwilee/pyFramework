extends Node3D
## =============================================================================
## 传送门 —— 漩涡 shader 能量门 + 走进即传送
## =============================================================================
## 两个 billboard 能量圆盘（蓝门 ↔ 橙门，portal.gdshader 漩涡噪声），
## 玩家（发光球）用 WASD 在科技网格地面上移动；
## 走进任意一个传送门 → 立即被传送到另一个门旁边 + 白闪转场。
## 传送后 0.8 秒冷却，避免在两门之间来回弹跳。
## =============================================================================

const PortalShader = preload("res://features/portal/portal.gdshader")
const GridShader = preload("res://features/portal/grid.gdshader")

const SPEED := 7.0
const PORTAL_A := Vector3(-4.5, 0, -1.5)
const PORTAL_B := Vector3(4.5, 0, 1.5)
const PORTAL_R := 1.05          # 触发半径
const TELEPORT_COOLDOWN := 0.8

var _cooldown := 0.0
var _flash: ColorRect
var _hint: Label

@onready var player: MeshInstance3D = $Player
@onready var portal_a: MeshInstance3D = $Portals/PortalA
@onready var portal_b: MeshInstance3D = $Portals/PortalB
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# 玩家发光球材质
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.9, 0.95, 1.0)
	pmat.emission_enabled = true
	pmat.emission = Color(0.5, 0.7, 1.0)
	pmat.emission_energy_multiplier = 1.6
	player.material_override = pmat

	# 地面（网格 shader）
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(34, 34)
	ground.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = GridShader
	ground.material_override = gm
	add_child(ground)

	# 两扇门：billboard 能量圆盘
	_build_portal(portal_a, Color(0.30, 0.60, 1.0), PORTAL_A)
	_build_portal(portal_b, Color(1.0, 0.45, 0.15), PORTAL_B)

	# 几根柱子做空间参照
	for i in 4:
		var pillar := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.7, 2.6, 0.7)
		pillar.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.30, 0.34, 0.44)
		mat.emission_enabled = true
		mat.emission = Color(0.05, 0.08, 0.18)
		pillar.material_override = mat
		add_child(pillar)
		var a := TAU / 4.0 * i + 0.6
		pillar.position = Vector3(cos(a) * 8.0, 1.3, sin(a) * 8.0)

	# HUD
	var layer := CanvasLayer.new()
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	_hint = Label.new()
	_hint.position = Vector2(16, 690)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.text = "WASD 移动 · 走进传送门 → 从另一扇门出现"
	layer.add_child(_hint)


func _build_portal(node: MeshInstance3D, color: Color, pos: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	node.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = PortalShader
	m.set_shader_parameter("core_color", color)
	node.material_override = m
	node.position = pos


# ============================================================
#  每帧
# ============================================================
func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)

	# WASD 移动（xz 平面）
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
		player.position += dir.normalized() * SPEED * delta
	# 活动范围限制
	player.position.x = clampf(player.position.x, -11.0, 11.0)
	player.position.z = clampf(player.position.z, -11.0, 11.0)

	# 传送判定
	if _cooldown <= 0.0:
		var pp := player.position
		var hit: Vector3 = Vector3.ZERO
		var target: Vector3 = Vector3.ZERO
		if _xz_dist(pp, PORTAL_A) < PORTAL_R:
			hit = PORTAL_A
			target = PORTAL_B
		elif _xz_dist(pp, PORTAL_B) < PORTAL_R:
			hit = PORTAL_B
			target = PORTAL_A
		if hit != Vector3.ZERO:
			player.position = target + Vector3(1.2, 0, 0)
			_cooldown = TELEPORT_COOLDOWN
			_flash_effect()
			_hint.text = "🌀 传送！%s → %s" % [_portal_name(hit), _portal_name(target)]

	# 能量门始终面对相机（billboard）
	portal_a.look_at(camera.global_position)
	portal_b.look_at(camera.global_position)


func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _portal_name(pos: Vector3) -> String:
	return "蓝门" if pos == PORTAL_A else "橙门"


func _flash_effect() -> void:
	_flash.color.a = 0.65
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.35)
