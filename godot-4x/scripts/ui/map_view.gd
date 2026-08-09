## 大地图视图（现代 4X 风格）。
## - 美术底图：加载 res://assets/map_bg.png（生成式，可换真实美术），拉伸覆盖世界矩形
## - 摄像机：滚轮缩放（朝光标）、左键拖动平移；右键/拖动不误触
## - 道路：坐标对 + 曲线信息，二次贝塞尔虚线绘制
## - 据点：◆ 菱形（归属色）；小地点：· 圆点
## - 部队：领队小人形象（头部+身体，归属色），节点旁错位排布，带存活数徽标
## - 交互（selectable=true）：左键点据点 → node_clicked；左键点部队 → 选中并拉起箭头，
##   再点相邻节点 → army_move_requested；右键 → 取消（army_cancelled）
class_name MapView
extends Control

signal node_clicked(nid: String)
signal army_selected(aid: String)
signal army_move_requested(aid: String, to_nid: String)
signal army_cancelled()

const V_Y_SCALE := 2.0          # 纵向视觉拉伸（坐标 y 仅 0..2，拉出地图感）
const PAD_X := 1.4              # 世界矩形外扩（世界单位）
const PAD_Y := 1.0
const ZOOM_MIN := 1.0           # 缩放倍数下限 = 覆盖式适配（世界矩形盖满视口，永不露灰）
const ZOOM_MAX := 3.5
const NODE_R := 18.0            # 节点点击半径
const ARMY_W := 30.0            # 部队形象尺寸
const ARMY_H := 38.0
const DRAG_THRESHOLD := 6.0     # 位移超过则视为拖动（不触发点击）

const BG_PATH := "res://assets/map_bg.png"

var game: Game = null
var selectable := false         # 是否可交互（游戏主场景 true；地图一览只读）

var _bg: Texture2D = null
var _zoom_mult := 1.0           # 相对适配比例
var _offset := Vector2.ZERO     # 世界矩形原点在屏幕的位置
var _needs_fit := true
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_moved := 0.0
var _cursor := Vector2(-999, -999)
var _selected_army := ""        # 地图上选中的部队（移动模式）
var _hover_node := ""           # 悬停的相邻目标节点（移动目标高亮）

var _screen: Dictionary = {}    # nid -> Vector2
var _army_screen: Dictionary = {}  # aid -> Vector2
var _world_rect := Rect2()      # 世界矩形（含外扩）

func set_game(g: Game) -> void:
	game = g
	_needs_fit = true
	queue_redraw()

# ---------- 摄像机 ----------
## 覆盖式适配比例：世界矩形放大到盖满视口（任何缩放级别下都看不到世界外灰色）。
func _fit_zoom() -> float:
	if _world_rect.size.x <= 0 or _world_rect.size.y <= 0:
		return 1.0
	return maxf(size.x / _world_rect.size.x, size.y / _world_rect.size.y)

func _zoom() -> float:
	return _fit_zoom() * _zoom_mult

func _world_to_screen(p: Vector2) -> Vector2:
	return _offset + p * _zoom()

## 摄像机钳制：世界矩形必须完全覆盖视口（看不见世界外的灰色）。
## 世界比视口大的方向：offset 限制在「世界左/上边缘 ≤ 视口边缘 ≤ 世界右/下边缘」。
## 世界窄于视口的方向（zoom 下限 1.0 时不会发生）：居中。
func _clamp_camera() -> void:
	if _world_rect.size.x <= 0:
		return
	var z := _zoom()
	var w_px := _world_rect.size * z
	var wr_min := _world_rect.position
	var wr_max := _world_rect.position + _world_rect.size
	# 水平
	if w_px.x <= size.x:
		_offset.x = (size.x - w_px.x) / 2.0 - wr_min.x * z
	else:
		# offset.x ∈ [size.x - wr_max.x*z, -wr_min.x*z]（世界覆盖视口）
		_offset.x = clampf(_offset.x, size.x - wr_max.x * z, -wr_min.x * z)
	# 垂直
	if w_px.y <= size.y:
		_offset.y = (size.y - w_px.y) / 2.0 - wr_min.y * z
	else:
		_offset.y = clampf(_offset.y, size.y - wr_max.y * z, -wr_min.y * z)

func _recompute_world() -> void:
	var m := game.map
	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9
	# 世界坐标缓存（世界单位，绘制时经 _world_to_screen 变换）
	_screen.clear()
	for sid in m.strongholds:
		var sh: MapSystem.Stronghold = m.strongholds[sid]
		_screen[sid] = Vector2(sh.x, sh.y * V_Y_SCALE)
		min_x = minf(min_x, sh.x)
		max_x = maxf(max_x, sh.x)
		min_y = minf(min_y, sh.y * V_Y_SCALE)
		max_y = maxf(max_y, sh.y * V_Y_SCALE)
	for mid in m.minors:
		var mi: MapSystem.MinorLocation = m.minors[mid]
		_screen[mid] = Vector2(mi.x, mi.y * V_Y_SCALE)
		min_x = minf(min_x, mi.x)
		max_x = maxf(max_x, mi.x)
		min_y = minf(min_y, mi.y * V_Y_SCALE)
		max_y = maxf(max_y, mi.y * V_Y_SCALE)
	if min_x > max_x:
		_world_rect = Rect2()
		return
	_world_rect = Rect2(Vector2(min_x - PAD_X, min_y - PAD_Y),
		Vector2(max_x - min_x + PAD_X * 2, max_y - min_y + PAD_Y * 2))

func _zoom_at(anchor_screen: Vector2, factor: float) -> void:
	# 保持锚点下的世界点不动：world = (anchor - offset) / z
	var z0 := _zoom()
	var world_pt := (anchor_screen - _offset) / z0
	_zoom_mult = clampf(_zoom_mult * factor, ZOOM_MIN, ZOOM_MAX)
	_offset = anchor_screen - world_pt * _zoom()
	_clamp_camera()
	queue_redraw()

func _pan(delta: Vector2) -> void:
	_offset += delta
	_clamp_camera()
	queue_redraw()

## 镜头立即居中到指定节点的世界坐标（TW3K: Home 切首都 / Ctrl+T 循环据点）。
func center_on(nid: String) -> void:
	if not _screen.has(nid):
		return
	var wp: Vector2 = _screen[nid]
	_offset = size / 2.0 - wp * _zoom()
	_clamp_camera()
	queue_redraw()

# ---------- 绘制 ----------
func _draw() -> void:
	if game == null:
		return
	if _needs_fit:
		_recompute_world()
		# 初始视图：世界中心对准视口中心（覆盖式适配，盖满视口）
		_zoom_mult = 1.0
		_offset = size / 2.0 - _world_rect.get_center() * _zoom()
		_clamp_camera()
		_needs_fit = false
	# 1. 美术底图
	if _bg == null:
		_bg = load(BG_PATH) if ResourceLoader.exists(BG_PATH) else null
	if _bg != null:
		var br := Rect2(_world_to_screen(_world_rect.position), _world_rect.size * _zoom())
		draw_texture_rect(_bg, br, false)
	else:
		draw_rect(Rect2(_world_to_screen(_world_rect.position), _world_rect.size * _zoom()),
			Color("1a2b20"))
	# 2. 道路（虚线二次贝塞尔）
	_draw_roads()
	# 3. 相邻目标高亮（移动模式）
	_draw_move_targets()
	# 4. 节点
	_draw_nodes()
	# 5. 部队（领队小人）
	_draw_armies()
	# 6. 选中部队的引导箭头
	_draw_selection_arrow()

func _draw_roads() -> void:
	var m := game.map
	if m.roads.is_empty():
		return
	var dash_on := 10.0
	var dash_off := 7.0
	for r in m.roads:
		if not _screen.has(r.a) or not _screen.has(r.b):
			continue
		var pa := _world_to_screen(_screen[r.a])
		var pb := _world_to_screen(_screen[r.b])
		var ctrl := _road_control(r.a, r.b, r.curve)
		var pts: Array[Vector2] = []
		for i in range(25):
			var t := i / 24.0
			pts.append(_bezier(pa, ctrl, pb, t))
		# 折线化虚线
		var total := 0.0
		var head := pts[0]
		for i in range(1, pts.size()):
			var seg_len := head.distance_to(pts[i])
			var seg_dir := (pts[i] - head) / maxf(0.001, seg_len)
			var walked := 0.0
			while walked < seg_len:
				var phase := fmod(total + walked, dash_on + dash_off)
				if phase < dash_on:
					var s0 := head + seg_dir * walked
					var s1_len := minf(seg_len - walked, dash_on - phase)
					draw_line(s0, head + seg_dir * (walked + s1_len),
						UiTheme.BORDER.lightened(0.05), 2.0)
				walked += 2.0
			total += seg_len
			head = pts[i]

## 曲线控制点：中点 + 垂直于连线的凸起（curve 为相对长度比例，屏幕坐标）。
func _road_control(a: String, b: String, curve: float) -> Vector2:
	var pa := _world_to_screen(_screen[a])
	var pb := _world_to_screen(_screen[b])
	var mid := (pa + pb) / 2.0
	var dir := (pb - pa).normalized()
	var perp := Vector2(-dir.y, dir.x)
	return mid + perp * (pb - pa).length() * curve

func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + c * 2.0 * u * t + b * t * t

func _draw_move_targets() -> void:
	if _selected_army == "" or game == null:
		return
	if not game.armies.has(_selected_army):
		_selected_army = ""
		return
	var a: Armies.Army = game.armies[_selected_army]
	for nid in game.map.neighbors(a.node_id):
		if nid == a.node_id:
			continue
		if not _screen.has(nid):
			continue
		var pos := _world_to_screen(_screen[nid])
		var ring_r := NODE_R + 10
		if nid == _hover_node:
			draw_circle(pos, ring_r, Color(UiTheme.C_OWN, 0.28))
		else:
			draw_arc(pos, ring_r, 0, TAU, 40, Color(UiTheme.C_OWN, 0.55), 2.0)

func _draw_nodes() -> void:
	if game == null:
		return
	var m := game.map
	var font := get_theme_default_font()
	for nid in _screen:
		var pos := _world_to_screen(_screen[nid])
		var is_sh := m.strongholds.has(nid)
		var color: Color
		if is_sh:
			var sh: MapSystem.Stronghold = m.strongholds[nid]
			if sh.owner == game.player_id:
				color = UiTheme.C_OWN
			elif sh.owner == "":
				color = UiTheme.C_NEUTRAL
			else:
				color = UiTheme.C_ENEMY
		else:
			color = UiTheme.C_MINOR
		if is_sh:
			# 据点：菱形 ◆ + 外圈
			draw_circle(pos, NODE_R + 3, Color(color, 0.18))
			var pts := PackedVector2Array([
				pos + Vector2(0, -14), pos + Vector2(14, 0),
				pos + Vector2(0, 14), pos + Vector2(-14, 0)])
			draw_colored_polygon(pts, color)
		else:
			draw_circle(pos, 7, color)
		# 名称
		var label := Loc.t(m.node_name(nid))
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, pos + Vector2(-tw / 2, 26), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color.lightened(0.2))
		if is_sh and m.strongholds[nid].is_capital:
			draw_string(font, pos + Vector2(tw / 2 + 4, -8), "(都)",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.GOLD)

func _draw_armies() -> void:
	if game == null:
		return
	_army_screen.clear()
	# 按节点分组，水平错位排布
	var per_node: Dictionary = {}
	for aid in game.armies:
		var a: Armies.Army = game.armies[aid]
		if a.is_wiped(game.unit_index):
			continue
		if not per_node.has(a.node_id):
			per_node[a.node_id] = []
		per_node[a.node_id].append(aid)
	var font := get_theme_default_font()
	for nid in per_node:
		if not _screen.has(nid):
			continue
		var pos := _world_to_screen(_screen[nid])
		var ids: Array = per_node[nid]
		for i in range(ids.size()):
			var aid: String = ids[i]
			var a: Armies.Army = game.armies[aid]
			var x := pos.x + (i - (ids.size() - 1) * 0.5) * (ARMY_W + 8)
			var y := pos.y - 44
			var ap := Vector2(x, y)
			_army_screen[aid] = ap
			var own := a.owner == game.player_id
			var col := UiTheme.C_OWN if own else UiTheme.C_ENEMY
			# 领队小人：头 + 身体
			var body := Rect2(ap.x - 9, ap.y + 12, 18, 16)
			var sb := StyleBoxFlat.new()
			sb.bg_color = col.darkened(0.15)
			sb.set_corner_radius_all(6)
			sb.border_color = col
			sb.set_border_width_all(1)
			draw_style_box(sb, body)
			draw_circle(ap + Vector2(0, 6), 6.5, col.lightened(0.15))
			# 选中光环
			if aid == _selected_army:
				draw_arc(ap + Vector2(0, 6), 11, 0, TAU, 32, UiTheme.ACCENT, 2.0)
				draw_arc(ap + Vector2(0, 6), 15, 0, TAU, 32, Color(UiTheme.ACCENT, 0.35), 4.0)
			# 存活数徽标
			var cnt: int = a.alive_units(game.unit_index).size()
			if cnt > 0:
				var ctxt := str(cnt)
				var cw := font.get_string_size(ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_rect(Rect2(ap.x + 8, ap.y - 10, cw + 8, 15), Color(0, 0, 0, 0.55))
				draw_string(font, ap + Vector2(12, 1), ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					UiTheme.GOLD)
			# 名称
			var ntxt := Loc.t(a.name)
			var nw := font.get_string_size(ntxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, ap + Vector2(-nw / 2, 34), ntxt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lightened(0.25))

func _draw_selection_arrow() -> void:
	if _selected_army == "" or not _army_screen.has(_selected_army):
		return
	if _cursor.x < -100:
		return
	var from: Vector2 = _army_screen[_selected_army] + Vector2(0, 6)
	var to := _cursor
	var dir := (to - from).normalized()
	var len := from.distance_to(to)
	if len < 4:
		return
	draw_line(from, to - dir * 10, UiTheme.ACCENT, 2.0)
	var tip := to - dir * 10
	draw_colored_polygon(PackedVector2Array([
		tip, tip + dir.rotated(2.7) * 10, tip + dir.rotated(-2.7) * 10]), UiTheme.ACCENT)

# ---------- 输入 ----------
func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseMotion:
		_cursor = event.position
		if _dragging:
			_pan(event.relative)
			_drag_moved += event.relative.length()
		else:
			_hover_node = _hit_adjacent_target(event.position)
			queue_redraw()
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(event.position, 1.18)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(event.position, 1.0 / 1.18)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_from = event.position
					_drag_moved = 0.0
				else:
					_dragging = false
					if _drag_moved < DRAG_THRESHOLD:
						_handle_click(event.position)
			MOUSE_BUTTON_RIGHT:
				if event.pressed and _selected_army != "":
					_selected_army = ""
					_hover_node = ""
					queue_redraw()
					army_cancelled.emit()
		accept_event()

## 点击命中：部队 > 据点 > 空白（空白取消选中）。
func _handle_click(at: Vector2) -> void:
	if not selectable:
		return
	# 部队
	var aid := _hit_army(at)
	if aid != "":
		var a: Armies.Army = game.armies[aid]
		if a.owner == game.player_id:
			_selected_army = aid
			_hover_node = ""
			queue_redraw()
			army_selected.emit(aid)
		return
	# 据点/小地点
	var nid := _hit_node(at)
	if nid != "":
		if _selected_army != "" and game.armies.has(_selected_army) \
				and game.map.neighbors(game.armies[_selected_army].node_id).has(nid) \
				and nid != game.armies[_selected_army].node_id:
			# 移动模式：点击相邻目标
			var target := _selected_army
			_selected_army = ""
			_hover_node = ""
			queue_redraw()
			army_move_requested.emit(target, nid)
			return
		# 非相邻：取消部队选择，改选据点
		if _selected_army != "":
			_selected_army = ""
			army_cancelled.emit()
		queue_redraw()
		node_clicked.emit(nid)
		return
	# 空白
	if _selected_army != "":
		_selected_army = ""
		_hover_node = ""
		queue_redraw()
		army_cancelled.emit()

func _hit_army(at: Vector2) -> String:
	for aid in _army_screen:
		var p: Vector2 = _army_screen[aid]
		if absf(at.x - p.x) <= ARMY_W * 0.6 and at.y >= p.y - 12 and at.y <= p.y + 30:
			return aid
	return ""

func _hit_node(at: Vector2) -> String:
	for nid in _screen:
		if _world_to_screen(_screen[nid]).distance_to(at) <= NODE_R + 8:
			return nid
	return ""

## 悬停时是否落在当前选中部队的相邻目标上。
func _hit_adjacent_target(at: Vector2) -> String:
	if _selected_army == "" or not game.armies.has(_selected_army):
		return ""
	var a: Armies.Army = game.armies[_selected_army]
	for nid in game.map.neighbors(a.node_id):
		if not _screen.has(nid):
			continue
		if _world_to_screen(_screen[nid]).distance_to(at) <= NODE_R + 12:
			return nid
	return ""

func _exit_tree() -> void:
	game = null
