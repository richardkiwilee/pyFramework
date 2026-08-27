class_name PileArea
extends Control
## 牌堆区域:负责鼠标手势转发(按住拖动期间由 GUI 指针捕获持续收到事件),
## 并绘制空堆占位虚线框 / 非空堆的落影。

signal interaction(event: InputEvent)

var stack_count: int = 0:
	set(v):
		stack_count = v
		if is_inside_tree():
			queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	interaction.emit(event)

func _draw() -> void:
	if stack_count == 0:
		# 空堆:虚线圆角框提示
		var c := Color(1, 1, 1, 0.35)
		var w := size.x
		var h := size.y
		var r := 10.0
		_dashed(Vector2(r, 0), Vector2(w - r, 0), c)
		_dashed(Vector2(r, h), Vector2(w - r, h), c)
		_dashed(Vector2(0, r), Vector2(0, h - r), c)
		_dashed(Vector2(w, r), Vector2(w, h - r), c)
		draw_arc(Vector2(r, r), r, PI, PI * 1.5, 12, c, 1.5, true)
		draw_arc(Vector2(w - r, r), r, PI * 1.5, TAU, 12, c, 1.5, true)
		draw_arc(Vector2(w - r, h - r), r, 0, PI * 0.5, 12, c, 1.5, true)
		draw_arc(Vector2(r, h - r), r, PI * 0.5, PI, 12, c, 1.5, true)
	else:
		# 非空堆:右下偏移的柔和落影
		draw_rect(Rect2(Vector2(6, 10), size), Color(0, 0, 0, 0.25), true)

func _dashed(a: Vector2, b: Vector2, c: Color) -> void:
	draw_dashed_line(a, b, c, 1.5, 7.0, true)
