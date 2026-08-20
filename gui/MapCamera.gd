## =====================================================================
## MapCamera — 挂在图片层（带 clip_contents 的 Control）上
## =====================================================================
## 职责：
##   1. 加载大地图（缺失则用纯色 ColorRect 回退）；
##   2. 鼠标拖拽平移、滚轮缩放（缩放以鼠标位置为中心）；
##   3. 移动不超出地图边界（_apply_clamp）；
##   4. 管理地图上的"单位"标记，并提供 focus_on() 把镜头平滑聚焦到某单位。
##
## 实现思路：本节点是"视口"（带 clip_contents 裁剪超出部分），
## 内部放一个 map 子节点（真正的地图本体，会缩放/平移）。
## 拖拽/缩放只改 map 的 position 和 scale，本节点本身不动。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control               → 继承 UI 控件基类（有位置/尺寸/可接收输入）
## clip_contents = true          → 超出本控件边界的内容被裁剪掉（类似 overflow:hidden）
## mouse_filter                  → 鼠标处理模式：
##     STOP   拦截鼠标（在本控件消费，不向下传递）
##     PASS   透传（本控件处理，未消费则继续传给下层）
##     IGNORE 忽略（本控件不参与，事件直接穿过）
## _ready() / _process() / _gui_input()
##     → 生命周期/回调：就绪、每帧、本控件收到 GUI 输入时
## Vector2(x, y)                 → 二维向量，常用作坐标/尺寸
## func _process(_delta)         → 每帧调用一次；_ 前缀表示"这个参数我故意不用"
## match expr: PATTERN: ...      → 类似 Python 的 match/case 或 C 的 switch
## clampf(x, lo, hi)            → 把 x 限制在 [lo, hi] 区间
## lerp(a, b, t)                → 线性插值，t∈[0,1]，用于平滑过渡
## await get_tree().process_frame → 等待一帧（协程，类似 asyncio.sleep(一帧)）
## =====================================================================
class_name MapCamera
extends Control

var map: Control                         # 地图本体（TextureRect 或 ColorRect）
var base_size: Vector2 = Vector2.ZERO    # 地图原始尺寸（未缩放时）

# ---- 交互状态 ----
var dragging := false                    # 当前是否在拖拽
var last_pos := Vector2.ZERO             # 上一帧鼠标位置（用于算拖拽位移）
var zoom := 1.0                          # 当前缩放倍数
const MIN_ZOOM := 1.0                    # 缩放下限
const MAX_ZOOM := 5.0                    # 缩放上限
const ZOOM_STEP := 1.15                  # 每次滚轮缩放的倍率
const FOCUS_ZOOM := 2.5                   # 聚焦单位时使用的缩放
const FOCUS_SPEED := 0.18                 # 聚焦插值速度（越大越快，1.0 为瞬间）

# 地图上的单位标记。每项 = { "pos": Vector2(世界坐标), "node": Control }
# 注意：GDScript 的 Array 是弱类型数组（可装任意对象），这里用普通 Array 而非 Array[T]。
var units: Array = []
var _focus_target := Vector2.ZERO         # 聚焦目标的世界坐标
var _focusing := false                    # 是否正在执行聚焦动画

func _ready() -> void:
	clip_contents = true                   # 裁剪超出本层的内容
	mouse_filter = Control.MOUSE_FILTER_STOP # 本层拦截鼠标，自己处理拖拽/缩放
	_build_map()
	_apply_clamp()
	set_process(true)                     # 开启每帧 _process 回调
	pass

## 构建 map 子节点：优先用地图贴图，缺失则用纯色 ColorRect。
func _build_map() -> void:
	var tex := ResourceManager.load_texture("map")
	if tex != null:
		var t := TextureRect.new()
		t.name = "MapImage"
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# STRETCH_SCALE：把贴图拉伸到 size（此处即贴图原始尺寸）。
		t.stretch_mode = TextureRect.STRETCH_SCALE
		base_size = tex.get_size()
		t.size = base_size
		map = t
	else:
		# 回退：一张纯色大矩形当地图
		var c := ColorRect.new()
		c.name = "MapImage"
		c.color = Color(0.16, 0.30, 0.43)
		base_size = Vector2(1600, 1000)
		c.size = base_size
		map = c
		# 给纯色地图画几条参考线，避免完全空白
		_draw_fallback_grid(c)
	map.position = Vector2.ZERO
	map.scale = Vector2.ONE
	# 让 map 子节点透传鼠标（本层自己接管输入），避免 map 抢走点击。
	map.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(map)
	pass

## 给纯色回退地图画几条参考网格线（纯视觉占位）。
func _draw_fallback_grid(parent: Control) -> void:
	# 竖线
	for i in range(1, 8):
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color(1, 1, 1, 0.08)
		var x := float(i) * base_size.x / 8.0
		line.add_point(Vector2(x, 0))
		line.add_point(Vector2(x, base_size.y))
		parent.add_child(line)
	# 横线
	for j in range(1, 5):
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color(1, 1, 1, 0.08)
		var y := float(j) * base_size.y / 5.0
		line.add_point(Vector2(0, y))
		line.add_point(Vector2(base_size.x, y))
		parent.add_child(line)
	pass

## 在地图世界坐标 world_pos 处放一个单位标记（用 portrait 资源）。
## 返回单位索引。
func add_unit(world_pos: Vector2, portrait_asset: String, label: String) -> int:
	# marker 是单位标记的根容器，固定 36×36。
	var marker := Control.new()
	marker.name = "Unit_%s" % label
	marker.position = world_pos
	marker.size = Vector2(36, 36)
	# 让标记不拦截鼠标（单位点击暂不实现）。
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 外框：金色描边的小框
	var frame := Panel.new()
	frame.size = Vector2(36, 36)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.55)
	sb.border_color = UiBuilder.GOLD
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	frame.add_theme_stylebox_override("panel", sb)
	marker.add_child(frame)

	# 人像：有资源用贴图，没有用首字母 Label 回退
	var tex := ResourceManager.load_texture(portrait_asset)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.position = Vector2(3, 3)
		t.size = Vector2(30, 30)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(t)
	else:
		var l := Label.new()
		l.text = label.substr(0, 1)        # 取首字母当占位文字
		l.add_theme_color_override("font_color", UiBuilder.GOLD)
		l.add_theme_font_size_override("font_size", 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# FULL_RECT 锚点：让 Label 自动填满 marker。
		l.anchors_preset = Control.PRESET_FULL_RECT
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(l)

	# 单位挂在 map 上，这样会随地图一起缩放/平移。
	map.add_child(marker)
	units.append({ "pos": world_pos, "node": marker })
	return units.size() - 1

## 返回单位数量（封装访问）。
func get_unit_count() -> int:
	return units.size()

## 返回某索引单位的世界坐标；越界返回零向量。
func get_unit_world_pos(index: int) -> Vector2:
	if index < 0 or index >= units.size():
		return Vector2.ZERO
	return units[index].pos

## 把镜头平滑聚焦到某单位（按索引）。先抬到 FOCUS_ZOOM，再插值 map.position。
func focus_on(index: int) -> void:
	if index < 0 or index >= units.size():
		return
	_focus_target = units[index].pos
	zoom = FOCUS_ZOOM
	map.scale = Vector2.ONE * zoom
	_focusing = true
	pass

## 每帧回调：当处于聚焦中时，把 map.position 平滑插值到目标位置。
func _process(_delta: float) -> void:
	if _focusing:
		var vp := size
		# 让 focus_target 这个世界点落在视口中心：map.position = vp/2 - target*zoom
		# （因为 map 内部坐标 = (世界点)*zoom，再平移 map.position 使其居中）
		var target_pos := vp * 0.5 - _focus_target * zoom
		# lerp 实现平滑插值；FOCUS_SPEED 越大越快。
		map.position = map.position.lerp(target_pos, FOCUS_SPEED)
		_apply_clamp()
		# 足够接近就吸附并结束聚焦，避免永远微抖。
		if map.position.distance_to(target_pos) < 0.5:
			map.position = target_pos
			_apply_clamp()
			_focusing = false
	pass

## 本控件收到 GUI 输入时触发（鼠标点击/移动/滚轮等）。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# match：按鼠标按键类型分支处理。
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					dragging = true
					_focusing = false     # 用户手动拖拽时取消聚焦
					last_pos = mb.position
				else:
					dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion:
		if dragging:
			map.position += (mb_event_delta(event))
			last_pos = (event as InputEventMouseMotion).position
			_apply_clamp()
	pass

## 计算鼠标移动位移（当前位置 - 上次记录位置）。
func mb_event_delta(event: InputEvent) -> Vector2:
	var mot := event as InputEventMouseMotion
	return mot.position - last_pos

## 以鼠标位置 mouse 为中心缩放 factor 倍。
## 关键：保持"鼠标所指的世界点"在屏幕上不动，否则会感觉地图往别处跑。
func _zoom_at(mouse: Vector2, factor: float) -> void:
	# 新缩放值（限制在 [MIN_ZOOM, MAX_ZOOM]）。
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, zoom):
		return
	# 反推鼠标所在的世界坐标：world = (screen - map.position) / zoom
	var local := (mouse - map.position) / zoom
	zoom = new_zoom
	map.scale = Vector2.ONE * zoom
	# 缩放后把该世界点重新放回鼠标位置：map.position = mouse - world * zoom
	map.position = mouse - local * zoom
	_apply_clamp()
	pass

## 关键：把地图限制在视口内，永远不露出地图外。
## 规则：
##   地图比视口大 → 贴着对应边，不允许超出（clamp 到 [vp - scaled, 0]）；
##   地图比视口小 → 居中。
func _apply_clamp() -> void:
	var vp := size
	var scaled := base_size * zoom
	# 横向
	if scaled.x >= vp.x:
		map.position.x = clampf(map.position.x, vp.x - scaled.x, 0.0)
	else:
		map.position.x = (vp.x - scaled.x) * 0.5
	# 纵向
	if scaled.y >= vp.y:
		map.position.y = clampf(map.position.y, vp.y - scaled.y, 0.0)
	else:
		map.position.y = (vp.y - scaled.y) * 0.5
	pass
