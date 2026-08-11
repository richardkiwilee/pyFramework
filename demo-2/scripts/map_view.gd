extends Control
## MapView — 十字军圣地之路大地图。WASD沿虚线路线控制角色移动。

const MAP_W: float = 1200.0
const MAP_H: float = 820.0

# ============================================================
# 据点数据
# ============================================================
const CITIES: Array[Dictionary] = [
	{id="massilia",  cn="马赛",     lat="Massilia",         x=200,  y=395, type="port"},
	{id="genova",    cn="热那亚",   lat="Genua",            x=295,  y=345, type="port"},
	{id="roma",      cn="罗马",     lat="Roma",             x=390,  y=440, type="holy"},
	{id="venezia",   cn="威尼斯",   lat="Venetia",          x=495,  y=335, type="great"},
	{id="vindobona", cn="维也纳",   lat="Vindobona",        x=545,  y=245, type="land"},
	{id="ragusa",    cn="拉古萨",   lat="Ragusa",           x=590,  y=450, type="port"},
	{id="constant",  cn="君士坦丁堡",lat="Constantinopolis", x=735,  y=360, type="great"},
	{id="nicosia",   cn="尼科西亚", lat="Nicosia",          x=900,  y=645, type="port"},
	{id="antiochia", cn="安条克",   lat="Antiochia",        x=985,  y=425, type="great"},
	{id="tripolis",  cn="的黎波里", lat="Tripolis",         x=1045, y=510, type="port"},
	{id="acre",      cn="阿克",     lat="Acco",             x=1075, y=555, type="port"},
	{id="jerusalem", cn="耶路撒冷", lat="Hierosolyma",      x=1105, y=605, type="holy"},
]

# ============================================================
# 路线: [city_a, city_b, bend]
# ============================================================
const ROUTES: Array = [
	["massilia", "genova",   -22],
	["genova",   "roma",      34],
	["roma",     "venezia",  -30],
	["venezia",  "vindobona", 22],
	["venezia",  "ragusa",    34],
	["roma",     "ragusa",    42],
	["ragusa",   "constant", -36],
	["venezia",  "constant", -64],
	["constant", "nicosia",   44],
	["nicosia",  "antiochia", 52],
	["antiochia","tripolis", -24],
	["tripolis", "acre",     -20],
	["acre",     "jerusalem", 30],
	["antiochia","jerusalem",-56],
	["massilia", "roma",      58],
]

# ============================================================
# 运行时状态
# ============================================================
var current_city_id: String = "roma"
var is_moving: bool = false
var troop_pos: Vector2 = Vector2(390, 440)

var _city_by_id: Dictionary = {}
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO

## 每个据点的方向映射: {city_id: {up: target_id, down: ..., left: ..., right: ...}}
## 空字符串表示该方向无路
var _dir_map: Dictionary = {}

## 每条边的bend值: "cityA|cityB" → bend (用于取反)
var _edge_bend: Dictionary = {}


func _ready() -> void:
	for c in CITIES:
		_city_by_id[c.id] = c

	# Build edge bend lookup
	for r in ROUTES:
		var a: String = r[0]; var b: String = r[1]; var bend_val: int = int(r[2])
		_edge_bend[a + "|" + b] = bend_val
		_edge_bend[b + "|" + a] = -bend_val  # reverse = mirrored curve

	# Build per-city direction→target mapping
	for c in CITIES:
		_dir_map[c.id] = {up="", down="", left="", right=""}
		var cur_pos: Vector2 = Vector2(float(c.x), float(c.y))
		var dirs: Array = ["up", "down", "left", "right"]
		var dir_vecs: Dictionary = {"up":Vector2.UP, "down":Vector2.DOWN, "left":Vector2.LEFT, "right":Vector2.RIGHT}

		# Collect all neighbors
		var neighbors: Array = []
		for r in ROUTES:
			if r[0] == c.id:
				neighbors.append({id=r[1], bend=int(r[2])})
			elif r[1] == c.id:
				neighbors.append({id=r[0], bend=-int(r[2])})

		# Assign each neighbor to the best-matching direction, one neighbor per key
		var assigned: Array = []  # track which neighbors are already assigned
		for dk in dirs:
			var best_id: String = ""
			var best_dot: float = -2.0
			for nb in neighbors:
				if nb.id in assigned:
					continue
				var nb_pos: Vector2 = Vector2(float(_city_by_id[nb.id].x), float(_city_by_id[nb.id].y))
				var edge_dir: Vector2 = (nb_pos - cur_pos).normalized()
				var sim: float = edge_dir.dot(dir_vecs[dk])
				if sim > best_dot:
					best_dot = sim
					best_id = nb.id
			if best_id != "":
				_dir_map[c.id][dk] = best_id
				assigned.append(best_id)
		# Second pass: any unassigned neighbors go to their best direction (even if one key gets two)
		# But we guarantee ≤4 neighbors so each key gets at most one

	var c: Dictionary = _city_by_id[current_city_id]
	troop_pos = Vector2(float(c.x), float(c.y))

	var vp: Vector2 = get_viewport_rect().size
	_scale = min(vp.x / MAP_W, vp.y / MAP_H) * 0.92
	_offset = (vp - Vector2(MAP_W, MAP_H) * _scale) / 2.0


# ============================================================
# 绘制
# ============================================================
func _draw() -> void:
	_draw_sea()
	_draw_landmass()
	_draw_decorations()
	_draw_routes()
	_draw_cities()
	_draw_troop()
	_draw_hud()


func _to_screen(x: float, y: float) -> Vector2:
	return Vector2(x, y) * _scale + _offset


func _draw_sea() -> void:
	draw_rect(Rect2(_offset, Vector2(MAP_W, MAP_H) * _scale), Color("#44687b"))


func _draw_landmass() -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		_to_screen(150,300), _to_screen(200,230), _to_screen(250,205),
		_to_screen(320,205), _to_screen(400,205), _to_screen(480,235),
		_to_screen(560,220), _to_screen(640,205), _to_screen(740,250),
		_to_screen(820,295), _to_screen(900,335), _to_screen(960,330),
		_to_screen(1000,360), _to_screen(1060,400), _to_screen(1140,440),
		_to_screen(1150,520), _to_screen(1158,580), _to_screen(1150,630),
		_to_screen(1110,645), _to_screen(1050,660), _to_screen(980,620),
		_to_screen(920,560), _to_screen(870,510), _to_screen(810,495),
		_to_screen(760,480), _to_screen(660,500), _to_screen(560,510),
		_to_screen(470,500), _to_screen(400,495), _to_screen(360,480),
		_to_screen(320,460), _to_screen(250,440), _to_screen(190,430),
		_to_screen(150,410), _to_screen(120,380), _to_screen(120,340),
		_to_screen(150,300),
	])
	draw_colored_polygon(pts, Color("#e0c98f"))
	draw_polyline(pts, Color("#7a5a32"), 2.0 * _scale, true)

	# Small islands (circles)
	var isle_data: Array = [
		[900.0, 650.0, 20.0],
		[815.0, 555.0, 8.0],
		[250.0, 560.0, 7.0],
		[300.0, 600.0, 5.0],
	]
	for isle in isle_data:
		var center: Vector2 = _to_screen(isle[0], isle[1])
		var r: float = isle[2] * _scale
		draw_circle(center, r, Color("#e0c98f"))
		draw_arc(center, r, 0, TAU, 24, Color("#7a5a32"), max(1.0, 1.5 * _scale), true)


func _draw_decorations() -> void:
	# Compass at bottom-left (simplified)
	var comp_center: Vector2 = _to_screen(160, 700)
	var comp_r: float = 55.0 * _scale
	draw_circle(comp_center, comp_r, Color("#f0e0b8"))
	draw_arc(comp_center, comp_r, 0, TAU, 32, Color("#7a5a32"), max(1.0, 1.4 * _scale), true)
	draw_circle(comp_center, comp_r - 8.0 * _scale, Color("#f0e0b8"), false, -1, true)
	var font := get_theme_default_font()
	var small_fs: int = max(8, int(10 * _scale))
	draw_string(font, comp_center + Vector2(0, -comp_r - 4), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(0, comp_r + 12), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(-comp_r - 12, 4), "W", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(comp_r + 10, 4), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))


# ============================================================
# 路线绘制 — 带弧线的虚线
# ============================================================
func _draw_routes() -> void:
	for route in ROUTES:
		var a: Dictionary = _city_by_id[route[0]]
		var b: Dictionary = _city_by_id[route[1]]
		var bend: float = float(route[2]) * _scale
		var from: Vector2 = _to_screen(float(a.x), float(a.y))
		var to: Vector2 = _to_screen(float(b.x), float(b.y))
		_draw_dashed_bezier(from, to, bend)


func _draw_dashed_bezier(from: Vector2, to: Vector2, bend: float) -> void:
	var mid: Vector2 = (from + to) / 2.0
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	var length: float = max(1.0, sqrt(dx * dx + dy * dy))
	var perp: Vector2 = Vector2(-dy / length, dx / length)
	var control: Vector2 = Vector2(mid.x + perp.x * bend, mid.y + perp.y * bend)

	var dash_len: float = 9.0 * _scale
	var gap_len: float = 7.0 * _scale
	var route_color: Color = Color("#7a3b22")
	var route_width: float = max(1.0, 2.0 * _scale)

	# Sample bezier and draw dashed segments
	var sample_count: int = max(20, int(length / 2.0))
	var prev_point: Vector2 = from
	var accum: float = 0.0
	var drawing: bool = true

	for i in range(1, sample_count + 1):
		var t: float = float(i) / sample_count
		var point: Vector2 = _bezier_point(from, control, to, t)
		var seg_len: float = prev_point.distance_to(point)
		accum += seg_len

		if drawing:
			if accum >= dash_len:
				var frac: float = 1.0 - (accum - dash_len) / seg_len
				draw_line(prev_point, prev_point.lerp(point, frac), route_color, route_width)
				accum -= dash_len
				drawing = false
			else:
				draw_line(prev_point, point, route_color, route_width)
		else:
			if accum >= gap_len:
				var frac: float = 1.0 - (accum - gap_len) / seg_len
				var restart: Vector2 = prev_point.lerp(point, frac)
				prev_point = restart
				accum -= gap_len
				drawing = true
			else:
				pass  # still in gap

		if drawing:
			prev_point = point
		else:
			prev_point = point
			accum = min(accum, gap_len)


func _bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var mt: float = 1.0 - t
	return p0 * mt * mt + p1 * 2.0 * mt * t + p2 * t * t


# ============================================================
# 据点绘制
# ============================================================
func _draw_cities() -> void:
	var font := get_theme_default_font()
	for c in CITIES:
		var pos: Vector2 = _to_screen(float(c.x), float(c.y))
		var is_current: bool = (c.id == current_city_id)

		var dot_color: Color
		match c.type:
			"holy":  dot_color = Color("#c9a227")
			"great": dot_color = Color("#8a3a2a")
			"port":  dot_color = Color("#3f6f88")
			_:       dot_color = Color("#4a5a3a")

		var ring_r: float = 10.0 * _scale
		if is_current:
			draw_circle(pos, ring_r + 3.0 * _scale, Color.GOLDENROD, true, -1, true)

		draw_circle(pos, ring_r, Color("#f4e6c0"))
		draw_arc(pos, ring_r, 0, TAU, 24, Color("#3a2412"), 1.6 * _scale, true)
		draw_circle(pos, 5.0 * _scale, dot_color)
		draw_arc(pos, 5.0 * _scale, 0, TAU, 16, Color("#2c1c0e"), 1.0 * _scale, true)

		var name_color := Color("#c2410c") if is_current else Color("#3a2410")
		var name_fs: int = max(10, int(13 * _scale))
		draw_string(font, pos + Vector2(0, 18 * _scale), c.cn, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs, name_color)
		var sub_fs: int = max(8, int(9 * _scale))
		draw_string(font, pos + Vector2(0, 31 * _scale), c.lat, HORIZONTAL_ALIGNMENT_CENTER, -1, sub_fs, Color("#6a4f33"))


# ============================================================
# 人物绘制
# ============================================================
func _draw_troop() -> void:
	var pos: Vector2 = _to_screen(troop_pos.x, troop_pos.y)
	draw_circle(pos, 15.0 * _scale, Color(0.76, 0.25, 0.05, 0.3))
	draw_circle(pos, 12.0 * _scale, Color("#c2410c"))
	draw_arc(pos, 12.0 * _scale, 0, TAU, 16, Color("#2c1c0e"), 2.0 * _scale, true)
	draw_circle(pos, 6.0 * _scale, Color("#e8c34d"))
	draw_arc(pos, 6.0 * _scale, 0, TAU, 12, Color("#2c1c0e"), 1.5 * _scale, true)
	var icon_fs: int = max(10, int(12 * _scale))
	draw_string(get_theme_default_font(), pos + Vector2(0, 4), "⚔",
		HORIZONTAL_ALIGNMENT_CENTER, -1, icon_fs, Color("#2c1c0e"))


# ============================================================
# HUD
# ============================================================
func _draw_hud() -> void:
	var font := get_theme_default_font()
	var c: Dictionary = _city_by_id[current_city_id]
	var vp: Vector2 = get_viewport_rect().size

	# Top-left: current city
	var info := "📍 %s (%s)" % [c.cn, c.lat]
	draw_string(font, Vector2(12, 24), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8d4a0"))

	# Top-right: direction guide
	var dmap: Dictionary = _dir_map.get(current_city_id, {})
	var dir_labels := {"up": "W ↑", "down": "S ↓", "left": "A ←", "right": "D →"}
	var guide_lines: Array[String] = []
	for dk in ["up", "down", "left", "right"]:
		var tid: String = dmap.get(dk, "")
		if tid != "":
			var nb: Dictionary = _city_by_id[tid]
			guide_lines.append("%s  %s" % [dir_labels[dk], nb.cn])
		else:
			guide_lines.append("%s  —" % dir_labels[dk])

	var guide_x: float = vp.x - 160
	for i in range(guide_lines.size()):
		var color := Color("#8a7a5c") if guide_lines[i].ends_with("—") else Color("#e8d4a0")
		draw_string(font, Vector2(guide_x, 24 + i * 16), guide_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)

	# Bottom-left hint
	draw_string(font, Vector2(12, vp.y - 16),
		"WASD/方向键 沿虚线路线移动",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a7a5c"))

	if is_moving:
		draw_string(font, Vector2(vp.x / 2 - 60, vp.y - 16),
			"行进中...", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color("#e8c34d"))


# ============================================================
# 输入处理
# ============================================================
## 曲线动画状态
var _curve_from: Vector2 = Vector2.ZERO
var _curve_ctrl: Vector2 = Vector2.ZERO
var _curve_to: Vector2 = Vector2.ZERO
var _curve_progress: float = 0.0
var _curve_duration: float = 0.0

func _input(event: InputEvent) -> void:
	if is_moving or not event.is_pressed():
		return

	var dir_key: String = ""
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_w"):
		dir_key = "up"
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_s"):
		dir_key = "down"
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_a"):
		dir_key = "left"
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_d"):
		dir_key = "right"
	else:
		return

	var target_id: String = _dir_map.get(current_city_id, {}).get(dir_key, "")
	if target_id == "":
		return
	var target: Dictionary = _city_by_id[target_id]
	_animate_along_route(target)


func _animate_along_route(target: Dictionary) -> void:
	is_moving = true
	var cur_city: Dictionary = _city_by_id[current_city_id]
	_curve_from = Vector2(float(cur_city.x), float(cur_city.y))
	_curve_to = Vector2(float(target.x), float(target.y))

	# Get the bend for this specific traversal direction
	var edge_key: String = current_city_id + "|" + target.id
	var bend: float = float(_edge_bend.get(edge_key, 0))

	# Bezier control point
	var mid: Vector2 = (_curve_from + _curve_to) / 2.0
	var dx: float = _curve_to.x - _curve_from.x
	var dy: float = _curve_to.y - _curve_from.y
	var length: float = max(1.0, sqrt(dx * dx + dy * dy))
	var perp: Vector2 = Vector2(-dy / length, dx / length)
	_curve_ctrl = Vector2(mid.x + perp.x * bend, mid.y + perp.y * bend)

	var dist: float = _curve_from.distance_to(_curve_to)
	_curve_duration = clamp(dist / 350.0, 0.25, 1.5)
	_curve_progress = 0.0

	troop_pos = _curve_from


func _process(delta: float) -> void:
	if is_moving:
		_curve_progress += delta / max(0.01, _curve_duration)
		if _curve_progress >= 1.0:
			_curve_progress = 1.0
			is_moving = false
			troop_pos = _curve_to
			for c in CITIES:
				var cp: Vector2 = Vector2(float(c.x), float(c.y))
				if cp.distance_to(_curve_to) < 5.0:
					current_city_id = c.id
					break
		else:
			var t: float = _curve_progress
			var mt: float = 1.0 - t
			troop_pos = _curve_from * mt * mt + _curve_ctrl * 2.0 * mt * t + _curve_to * t * t
	queue_redraw()
