extends Node2D
## =============================================================================
## 心形粒子爆发 —— 点击生成爱心粒子喷泉（程序化心形纹理）
## =============================================================================
## · 心形贴图由 Image 逐像素生成（两个圆 + 倒三角的解析判定），
##   供 CPUParticles2D 作为纹理；
## · 点击任意位置：爱心粒子向上喷发 + 重力回落 + 随机粉色系；
## · 【🧹 清空】重置画面。
## 心形判定（_inside_heart）为纯函数，可确定性测试。
## =============================================================================

const HEART_SIZE := 48

var _bursts: Array = []      # 每击生成一个 CPUParticles2D（一次性的简单实现）

@onready var clear_btn: Button = $CanvasLayer/ClearBtn


func _ready() -> void:
	clear_btn.pressed.connect(_clear)


## 心形解析判定（供测试与纹理生成）：(0,0) 为心形中心，y 向下
## 上半 = 两瓣圆（圆心 ±11,-9 半径 14，中间自然形成凹槽），下半 = 倒三角
func _inside_heart(p: Vector2) -> bool:
	if p.y <= -2.0:
		var l := sqrt((p.x - 11.0) * (p.x - 11.0) + (p.y + 9.0) * (p.y + 9.0))
		var r := sqrt((p.x + 11.0) * (p.x + 11.0) + (p.y + 9.0) * (p.y + 9.0))
		return l <= 14.0 or r <= 14.0
	# 下半：由左右腰线包住的三角
	var half_w := 16.0 + p.y * 1.2
	return absf(p.x) <= half_w and p.y <= 18.0


func _heart_texture(color: Color) -> ImageTexture:
	var img := Image.create(HEART_SIZE, HEART_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in HEART_SIZE:
		for x in HEART_SIZE:
			var p := (Vector2(x, y) - Vector2(HEART_SIZE, HEART_SIZE) / 2.0) * 0.62
			if _inside_heart(p):
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


## 生成一次爱心爆发（供输入与测试）
func _spawn_burst(at: Vector2) -> void:
	var hue := randf_range(0.88, 1.0)   # 粉-红区间
	var col := Color.from_hsv(fposmod(hue, 1.0), 0.85, 1.0)
	var p := CPUParticles2D.new()
	p.texture = _heart_texture(col)
	p.amount = 16
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.gravity = Vector2(0, 420)
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 420.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	p.position = at
	add_child(p)
	p.restart()
	_bursts.append(p)


func _clear() -> void:
	for b in _bursts:
		b.queue_free()
	_bursts.clear()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn_burst(event.position)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.10, 0.07, 0.12))
