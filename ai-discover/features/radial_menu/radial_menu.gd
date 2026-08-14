extends Control
## =============================================================================
## 环形菜单 —— 右键呼出饼图菜单，悬停高亮扇区，点击执行动作
## =============================================================================
## · 6 个扇区（图标+文字），中心圆形取消区；
## · 悬停扇区放大高亮，点击选择（左下角反馈），点外部关闭；
## · 扇区角度映射（_segment_at）为纯函数，可确定性测试。
## =============================================================================

const ITEMS: Array = ["🔍 查看", "✏️ 编辑", "📋 复制", "🗑 删除", "⭐ 收藏", "↗ 分享"]
const RADIUS := 170.0
const INNER := 56.0

var _open := false
var _center := Vector2.ZERO
var _hover := -1

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	status_label.text = "🖱 右键呼出环形菜单"


## 扇区 i 的中心角（供绘制与测试）
func _segment_center_angle(i: int) -> float:
	return TAU * i / ITEMS.size() - PI / 2.0


## 屏幕位置 → 扇区下标（供测试与输入）：-1 = 中心取消区/外部
func _segment_at(p: Vector2) -> int:
	var d := p.distance_to(_center)
	if d < INNER or d > RADIUS:
		return -1
	var a := (p - _center).angle()
	var rel := fposmod(a + PI / 2.0, TAU)
	# 四舍五入取整：fposmod(0, TAU) 因浮点误差会绕回 ≈TAU，
	# 直接截断会把正上方误判到最后一个扇区
	return int(floor(rel / (TAU / ITEMS.size()) + 0.5)) % ITEMS.size()


func _select(i: int) -> void:
	status_label.text = "✅ 执行：%s" % ITEMS[i]
	_open = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_open = true
			_center = event.position
			_hover = -1
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _open:
				var idx := _segment_at(event.position)
				if idx >= 0:
					_select(idx)
				else:
					_open = false
					queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _open:
		_hover = _segment_at(event.position)
		queue_redraw()


func _draw() -> void:
	if not _open:
		return
	# 扇区
	for i in ITEMS.size():
		var a0 := _segment_center_angle(i) - PI / ITEMS.size()
		var a1 := _segment_center_angle(i) + PI / ITEMS.size()
		var pts := PackedVector2Array([_center])
		for j in 12:
			var a := a0 + (a1 - a0) * j / 11.0
			pts.append(_center + Vector2.from_angle(a) * RADIUS)
		var col := Color.from_hsv(float(i) / ITEMS.size(), 0.55, 0.35)
		if i == _hover:
			col = Color.from_hsv(float(i) / ITEMS.size(), 0.7, 0.6)
		draw_colored_polygon(pts, col)
		# 图标
		var f := ThemeDB.fallback_font
		var mid := _center + Vector2.from_angle(_segment_center_angle(i)) * (RADIUS * 0.62)
		var size := f.get_string_size(ITEMS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(f, mid + Vector2(-size.x / 2.0, 6), ITEMS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.95, 1.0))
	# 中心取消区
	draw_circle(_center, INNER, Color(0.12, 0.13, 0.18))
	draw_arc(_center, INNER, 0, TAU, 32, Color(0.5, 0.55, 0.7), 2.0)
