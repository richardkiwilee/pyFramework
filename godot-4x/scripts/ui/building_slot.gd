## 建筑槽位方块（据点信息栏：屏幕下方居中一排正方形图块）。
## 最左 = 稍大的地标建筑方块；其后按据点规模排列普通建筑槽位。
## 状态：BUILDING(已建) / EMPTY(空槽可建) / LOCKED(非己方只读)。
class_name BuildingSlot
extends Control

signal clicked
signal demolish_clicked   # 仅点右上角红×触发（拆除建筑）

enum State { BUILDING, EMPTY, LOCKED }

var state := State.EMPTY
var title := ""
var subtitle := ""            # 效果描述（如 "+5 食物" / 地标档位）
var is_landmark := false      # 地标方块稍大、金框
var corner_radius := 10

var _hovered := false
var _pressed := false
var _press_pos := Vector2.ZERO   # 按下位置，松开时按区域分发点击

func _init(landmark: bool = false) -> void:
	is_landmark = landmark
	var side := 118.0 if is_landmark else 84.0
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		_pressed = false
		queue_redraw())

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(corner_radius)
	match state:
		State.BUILDING:
			sb.bg_color = UiTheme.PANEL_BG.lightened(0.06 if is_landmark else 0.0)
			sb.border_color = UiTheme.GOLD if is_landmark else UiTheme.C_OWN
		State.EMPTY:
			sb.bg_color = UiTheme.PANEL_BG.darkened(0.25)
			sb.border_color = UiTheme.BORDER
		State.LOCKED:
			sb.bg_color = UiTheme.PANEL_BG.darkened(0.35)
			sb.border_color = UiTheme.DISABLED
	sb.set_border_width_all(3 if is_landmark else (2 if _hovered else 1))
	draw_style_box(sb, r)
	# 空槽：内层虚线框提示可建
	if state == State.EMPTY and not is_landmark:
		var dash := 6.0
		var gap := 4.0
		var inset := 7.0
		_draw_dashed_rect(Rect2(r.position + Vector2(inset, inset),
			r.size - Vector2(inset * 2, inset * 2)), UiTheme.DIM, dash, gap)
	# 已建普通槽：右上角红色 ×（点击 = 拆除该建筑）
	if state == State.BUILDING and not is_landmark:
		var cx := r.size.x - 12.0
		var cy := 12.0
		draw_circle(Vector2(cx, cy), 9.0, Color(UiTheme.C_ENEMY, 0.85))
		draw_line(Vector2(cx - 4, cy - 4), Vector2(cx + 4, cy + 4), Color.WHITE, 2.0)
		draw_line(Vector2(cx - 4, cy + 4), Vector2(cx + 4, cy - 4), Color.WHITE, 2.0)
	# 文字
	var font := get_theme_default_font()
	var cx := size.x / 2.0
	var head_col: Color
	match state:
		State.BUILDING:
			head_col = UiTheme.GOLD if is_landmark else UiTheme.FG
		State.EMPTY:
			head_col = UiTheme.DIM
		State.LOCKED:
			head_col = UiTheme.DISABLED
	var title_y := size.y * 0.42
	draw_multiline_string(font, Vector2(8, title_y), title,
		HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 2, 14, head_col)
	if subtitle != "":
		draw_string(font, Vector2(cx - font.get_string_size(subtitle,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x / 2.0, size.y - 14),
			subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.DIM)
	# 地标标识（左上角星标）
	if is_landmark:
		draw_string(font, Vector2(10, 16), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.ACCENT)

func _draw_dashed_rect(r: Rect2, color: Color, dash: float, gap: float) -> void:
	var pts: Array[Vector2] = [
		r.position, r.position + Vector2(r.size.x, 0),
		r.position + r.size, r.position + Vector2(0, r.size.y), r.position]
	for i in range(4):
		_draw_dashed_line(pts[i], pts[i + 1], color, dash, gap)

func _draw_dashed_line(a: Vector2, b: Vector2, color: Color, dash: float, gap: float) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(0.001, len)
	var walked := 0.0
	while walked < len:
		var seg := minf(dash, len - walked)
		draw_line(a + dir * walked, a + dir * (walked + seg), color, 1.0)
		walked += seg + gap

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
			queue_redraw()
		elif _pressed:
			_pressed = false
			queue_redraw()
			if state != State.LOCKED:
				if _on_demolish_x(_press_pos):
					demolish_clicked.emit()
				else:
					clicked.emit()
		accept_event()

## 命中判断：已建普通槽右上角红×区域（点×=拆除，点方块本体=查看信息）。
func _on_demolish_x(pos: Vector2) -> bool:
	if state != State.BUILDING or is_landmark:
		return false
	var cx := size.x - 12.0
	var cy := 12.0
	return pos.distance_to(Vector2(cx, cy)) <= 13.0
