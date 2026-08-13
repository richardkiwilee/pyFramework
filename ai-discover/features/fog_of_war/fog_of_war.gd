extends Node2D
## =============================================================================
## 战争迷雾 —— 双层揭示：已探索（永久暗色记忆） + 视野（实时高亮）
## =============================================================================
## · 场景：程序化"战略地图"（噪声地块 + 城市/据点标记）；
## · 迷雾层：全屏 ColorRect + fog.gdshader——
##     已探索层 = 128×72 的 ImageTexture，玩家走过的圆斑永久画进去；
##     视野层   = uniform 数组传玩家当前位置，实时软边照亮；
## · WASD 移动侦察兵探索地图，迷雾随足迹揭开、远离后变暗但不消失。
## =============================================================================

const FogShader = preload("res://features/fog_of_war/fog.gdshader")
const EXPLORE_W := 128
const EXPLORE_H := 72
const VIEW_RADIUS := 150.0
const SPEED := 260.0

var _explore_img: Image
var _explore_tex: ImageTexture
var _player: Vector2 = Vector2(200, 200)
var _mat: ShaderMaterial

@onready var fog_rect: ColorRect = $FogRect


func _ready() -> void:
	_explore_img = Image.create(EXPLORE_W, EXPLORE_H, false, Image.FORMAT_R8)
	_explore_img.fill(Color(0, 0, 0))
	_explore_tex = ImageTexture.create_from_image(_explore_img)
	_mat = ShaderMaterial.new()
	_mat.shader = FogShader
	_mat.set_shader_parameter("explored_tex", _explore_tex)
	_mat.set_shader_parameter("view_size", Vector2(1280, 720))
	fog_rect.material = _mat
	_paint_explored(_player, 60.0)
	_push_reveal()
	queue_redraw()


## 把玩家足迹（圆斑）永久画进探索层
func _paint_explored(world_pos: Vector2, radius: float) -> void:
	var cx := int(world_pos.x / 1280.0 * EXPLORE_W)
	var cy := int(world_pos.y / 720.0 * EXPLORE_H)
	var r := int(radius / 1280.0 * EXPLORE_W) + 1
	for y in range(maxi(0, cy - r), mini(EXPLORE_H, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(EXPLORE_W, cx + r + 1)):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				_explore_img.set_pixel(x, y, Color(1, 1, 1))
	_explore_tex.update(_explore_img)


func _push_reveal() -> void:
	var pos_arr := PackedVector2Array()
	for i in 4:
		pos_arr.append(_player if i == 0 else Vector2(-1, -1))
	_mat.set_shader_parameter("reveal_pos", pos_arr)
	_mat.set_shader_parameter("reveal_radius", VIEW_RADIUS)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if dir.length() > 0:
		_player += dir.normalized() * SPEED * delta
		_player.x = clampf(_player.x, 24, 1256)
		_player.y = clampf(_player.y, 24, 696)
		_paint_explored(_player, VIEW_RADIUS * 0.9)
		_push_reveal()
		queue_redraw()


## 底层"战略地图"：噪声地块 + 城市据点 + 侦察兵
func _draw() -> void:
	# 地块（哈希噪声着色）
	for gy in 12:
		for gx in 20:
			var c := Color(0.14, 0.22, 0.14)
			var h := _hash2(gx, gy)
			if h > 0.62:
				c = Color(0.13, 0.16, 0.28)      # 水域
			elif h > 0.40:
				c = Color(0.30, 0.24, 0.16)      # 山地
			draw_rect(Rect2(gx * 64, gy * 60, 63, 59), c)
	# 城市标记
	for city in [Vector2(380, 180), Vector2(860, 420), Vector2(240, 500), Vector2(1040, 160)]:
		draw_circle(city, 14, Color(0.9, 0.85, 0.7))
		draw_arc(city, 20, 0, TAU, 24, Color(0.9, 0.85, 0.7), 2.0)
	# 侦察兵
	draw_circle(_player, 10, Color(0.2, 0.8, 1.0))
	draw_arc(_player, 15, 0, TAU, 24, Color(0.2, 0.8, 1.0), 2.5)


func _hash2(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n & 0x7fffffff) % 1000) / 1000.0
