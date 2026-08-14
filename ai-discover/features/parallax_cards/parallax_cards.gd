extends Control
## =============================================================================
## 视差卡片 —— 卡片随鼠标位置伪 3D 倾斜（UI 精致感组件）
## =============================================================================
## · 2×3 卡片网格，每张卡片根据"鼠标相对卡片中心的偏移"倾斜旋转，
##   悬停的卡片轻微放大；
## · 卡片内文字做反向视差（内容层随倾斜方向微移，增强立体感）。
## 倾斜映射（_tilt_for）为纯函数，可确定性测试。
## =============================================================================

const CARD_SIZE := Vector2(300, 170)
const GRID_ORIGIN := Vector2(180, 130)
const MAX_TILT := 0.35   # 弧度

var _cards: Array = []   # {panel, content, idx}

@onready var hint_label: Label = $CanvasLayer/HintLabel


func _ready() -> void:
	for i in 6:
		var panel := PanelContainer.new()
		var gx := i % 3
		var gy := i / 3
		panel.position = GRID_ORIGIN + Vector2(gx * (CARD_SIZE.x + 30), gy * (CARD_SIZE.y + 26))
		panel.custom_minimum_size = CARD_SIZE
		panel.pivot_offset = CARD_SIZE / 2.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.from_hsv(float(i) / 6.0, 0.55, 0.32)
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(2)
		sb.border_color = Color.from_hsv(float(i) / 6.0, 0.5, 0.75)
		sb.content_margin_left = 20.0
		sb.content_margin_top = 16.0
		panel.add_theme_stylebox_override("panel", sb)

		var content := Label.new()
		content.text = "🎴 卡片 %d\n鼠标移过来\n我会倾斜向你" % (i + 1)
		content.add_theme_font_size_override("font_size", 19)
		panel.add_child(content)

		add_child(panel)
		_cards.append({"panel": panel, "content": content})
	queue_redraw()


## 偏移 → 倾斜角（供测试与 _process）
func _tilt_for(offset: Vector2) -> Vector2:
	return Vector2(
		clampf(-offset.y * 0.0011, -MAX_TILT, MAX_TILT),   # 绕 X（上下）
		clampf(offset.x * 0.0011, -MAX_TILT, MAX_TILT)     # 绕 Y（左右）
	)


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	for c in _cards:
		var panel: Control = c["panel"]
		var center := panel.position + CARD_SIZE / 2.0
		var offset := mouse - center
		var dist := offset.length()
		var tilt := _tilt_for(offset)
		panel.rotation = tilt.x * 0.6
		var hover := dist < 220.0
		panel.scale = Vector2.ONE * (1.08 if hover else 1.0)
		# 内容反向视差
		var content: Label = c["content"]
		content.position = Vector2(20 + tilt.y * 16.0, 16 + tilt.x * 10.0)
		# 悬停时 z 置顶
		panel.z_index = 5 if hover else 0
