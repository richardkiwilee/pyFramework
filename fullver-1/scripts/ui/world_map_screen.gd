class_name WorldMapScreen
extends Control
## =============================================================================
## WorldMapScreen — 大地图场景根脚本（渲染 + 交互）
## =============================================================================
## 职责边界（docs/00-design.md §2）：本类只做展示与输入，
## 移动规则/战斗触发全部走 GameManager.player_move_army → WorldMapModel。
##
## 渲染：移植 demo-2 的方案（ADR-0002）——
##   - 逻辑坐标系（map.json 的 map_width × map_height）+ _to_screen() 缩放平移投影
##   - 分层 _draw()：海洋 → 陆地 → 装饰 → 路线（虚线贝塞尔）→ 城市 → 军团 → 选中高亮
##   - 移动动画与路线绘制共用同一贝塞尔控制点公式（零偏差）
##
## 交互：
##   - 点击军团标记 → 选中（仅本回合可操作的玩家军团）
##   - 点击相邻城市 → 移动指令（有敌军 → GameManager 发战斗请求 → 切战斗场景）
##   - 点击其他城市 → 选中该城（Overlay 的"城市管理"用）
##   - 右键 / Esc → 取消选中
##
## ⚠️ 本环境实测坑（记忆库）：
##   - draw_* 只能在 _draw() 内调用（覆盖层各自独立脚本）
##   - 零尺寸 Control 会被剔除绘制——本节点锚点全屏
##   - 静止时不重绘（demo-2 每帧 queue_redraw 的浪费，这里用脏标记）
##   - emoji 绘制用 UITheme.emoji_font（主题字体不含 emoji 字形）
## =============================================================================

## 城市标记半径（逻辑坐标像素）
const CITY_RADIUS := 12.0

## 军团标记半径（逻辑坐标像素）
const ARMY_RADIUS := 14.0

## 选中城市的 id（Overlay 的城市管理按钮用）
var selected_city_id: String = ""

## 选中的玩家军团
var _selected_army: Army = null

## 移动动画状态（同时只放一个动画，简单可控）
## {army: Army, from: Vector2, ctrl: Vector2, to: Vector2, progress: float, duration: float}
var _moving: Dictionary = {}

## 逻辑 → 屏幕投影参数（_ready 时按视口计算，同 demo-2）
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO

## 需要重绘的脏标记（状态变化才置 true；动画期间每帧置 true）
var _dirty: bool = true


func _ready() -> void:
	# 投影参数：缩放 = 视口/地图 取较小值 × 0.92（留边距），偏移居中
	var map_w: float = float(DataManager.get_map_data().get("map_width", 1200.0))
	var map_h: float = float(DataManager.get_map_data().get("map_height", 820.0))
	var vp: Vector2 = get_viewport_rect().size
	_scale = min(vp.x / map_w, vp.y / map_h) * 0.92
	_offset = (vp - Vector2(map_w, map_h) * _scale) / 2.0

	# 订阅全局信号：事件/回合 → 刷新
	GameManager.game_event.connect(_on_game_event)
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.battle_requested.connect(_on_battle_requested)

	# 场景切换回来时视口可能变了，重算投影
	resized.connect(func() -> void: _recalc_projection())

	queue_redraw()

	# 兜底：进入场景时若已有挂起的战斗请求（信号在场景切换间隙发出），
	# 立即切战斗场景——防战斗请求丢失导致回合流程卡死
	if not GameManager.pending_battle.is_empty() and ResourceLoader.exists("res://scenes/battle.tscn"):
		await GameManager.change_scene("res://scenes/battle.tscn")


func _on_game_event(_kind: String, _data: Dictionary) -> void:
	_dirty = true
	queue_redraw()


func _on_turn_started(_turn: int) -> void:
	_selected_army = null
	_dirty = true
	queue_redraw()


## 战斗请求 → 切战斗场景（P6 的 battle.tscn 就绪前忽略）
func _on_battle_requested(_battle: Dictionary) -> void:
	if ResourceLoader.exists("res://scenes/battle.tscn"):
		await GameManager.change_scene("res://scenes/battle.tscn")
	else:
		Log.info("[WorldMap] 战斗请求但战斗场景未实现（P6）：{}", _battle)


func _recalc_projection() -> void:
	var map_w: float = float(DataManager.get_map_data().get("map_width", 1200.0))
	var map_h: float = float(DataManager.get_map_data().get("map_height", 820.0))
	var vp: Vector2 = get_viewport_rect().size
	_scale = min(vp.x / map_w, vp.y / map_h) * 0.92
	_offset = (vp - Vector2(map_w, map_h) * _scale) / 2.0
	_dirty = true
	queue_redraw()


## ---------------------------------------------------------------------------
## 坐标转换（同 demo-2：screen = logical × scale + offset）
## ---------------------------------------------------------------------------
func _to_screen(x: float, y: float) -> Vector2:
	return Vector2(x, y) * _scale + _offset


func _to_logical(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _offset) / _scale


# ==================================================================
#  绘制（分层）
# ==================================================================

func _draw() -> void:
	_draw_sea()
	_draw_landmass()
	_draw_decorations()
	_draw_routes()
	_draw_cities()
	_draw_armies()
	_draw_selection()


## 海洋背景
func _draw_sea() -> void:
	var map_w: float = float(DataManager.get_map_data().get("map_width", 1200.0))
	var map_h: float = float(DataManager.get_map_data().get("map_height", 820.0))
	draw_rect(Rect2(_offset, Vector2(map_w, map_h) * _scale), Color("#44687b"))


## 陆地轮廓（1600×1000 大地图的近似地中海沿岸轮廓，逻辑坐标）
func _draw_landmass() -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		_to_screen(80, 300), _to_screen(140, 200), _to_screen(240, 130),
		_to_screen(400, 110), _to_screen(560, 100), _to_screen(720, 110),
		_to_screen(880, 100), _to_screen(1020, 130), _to_screen(1150, 160),
		_to_screen(1290, 150), _to_screen(1400, 200), _to_screen(1500, 300),
		_to_screen(1530, 420), _to_screen(1510, 560), _to_screen(1460, 680),
		_to_screen(1500, 800), _to_screen(1410, 880), _to_screen(1300, 930),
		_to_screen(1180, 960), _to_screen(1050, 930), _to_screen(960, 940),
		_to_screen(860, 900), _to_screen(760, 920), _to_screen(650, 950),
		_to_screen(540, 900), _to_screen(460, 800), _to_screen(380, 720),
		_to_screen(300, 640), _to_screen(200, 560), _to_screen(120, 460),
		_to_screen(80, 380), _to_screen(80, 300),
	])
	draw_colored_polygon(pts, Color("#e0c98f"))
	draw_polyline(pts, Color("#7a5a32"), 2.0 * _scale, true)

	# --- 小岛：圆形 + 描边（逻辑坐标 [x, y, 半径]）---
	var isle_data: Array = [
		[700.0, 620.0, 16.0],
		[620.0, 520.0, 9.0],
		[1120.0, 320.0, 12.0],
		[990.0, 420.0, 8.0],
	]
	for isle in isle_data:
		var center: Vector2 = _to_screen(isle[0], isle[1])
		var r: float = isle[2] * _scale
		draw_circle(center, r, Color("#e0c98f"))
		draw_arc(center, r, 0, TAU, 24, Color("#7a5a32"), max(1.0, 1.5 * _scale), true)


## 装饰：右上角简易罗盘（左下角是统帅条/消息面板 UI 区，不能放装饰）
func _draw_decorations() -> void:
	var comp_center: Vector2 = _to_screen(1470, 110)
	var comp_r: float = 44.0 * _scale
	draw_circle(comp_center, comp_r, Color("#f0e0b8"))
	draw_arc(comp_center, comp_r, 0, TAU, 32, Color("#7a5a32"), max(1.0, 1.4 * _scale), true)
	draw_circle(comp_center, comp_r - 8.0 * _scale, Color("#f0e0b8"), false, -1, false)
	var font := get_theme_default_font()
	var small_fs: int = max(8, int(10 * _scale))
	draw_string(font, comp_center + Vector2(0, -comp_r - 4), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(0, comp_r + 12), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(-comp_r - 12, 4), "W", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(comp_r + 10, 4), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))


## 路线：虚线贝塞尔（绘制与动画共用 _bezier_point / 控制点公式）
func _draw_routes() -> void:
	var routes: Array = DataManager.get_map_data().get("routes", [])
	for route in routes:
		var a: Dictionary = DataManager.get_city(route[0])
		var b: Dictionary = DataManager.get_city(route[1])
		if a.is_empty() or b.is_empty():
			continue
		var bend: float = float(route[2]) * _scale
		var from: Vector2 = _to_screen(float(a.x), float(a.y))
		var to: Vector2 = _to_screen(float(b.x), float(b.y))
		_draw_dashed_bezier(from, to, bend)


## 城市：外圈 + 类型色点 + 归属势力色环 + 名称
func _draw_cities() -> void:
	var font := get_theme_default_font()
	var state: GameState = GameManager.game_state
	if state == null:
		return
	for city in state.cities:
		var pos: Vector2 = _to_screen(city.x, city.y)
		var dot_color: Color
		match city.type:
			"holy":  dot_color = Color("#c9a227")
			"great": dot_color = Color("#8a3a2a")
			"port":  dot_color = Color("#3f6f88")
			_:       dot_color = Color("#4a5a3a")

		# 归属势力色环（中立城市灰色）
		var owner_color: Color = Color("#8a8a8a")
		if not city.is_neutral():
			owner_color = UITheme.faction_color(city.owner_faction_id)
		draw_circle(pos, CITY_RADIUS * _scale + 3.0 * _scale, owner_color)

		draw_circle(pos, CITY_RADIUS * _scale, Color("#f4e6c0"))
		draw_arc(pos, CITY_RADIUS * _scale, 0, TAU, 24, Color("#3a2412"), 1.6 * _scale, true)
		draw_circle(pos, 5.0 * _scale, dot_color)
		draw_arc(pos, 5.0 * _scale, 0, TAU, 16, Color("#2c1c0e"), 1.0 * _scale, true)

		# 名称：选中城市金色
		var name_color := UITheme.GOLD_BRIGHT if city.id == selected_city_id else Color("#3a2410")
		var name_fs: int = max(10, int(13 * _scale))
		draw_string(font, pos + Vector2(0, 22 * _scale), city.name_zh,
			HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs, name_color)


## 军团标记：势力色圆盘 + ⚔
func _draw_armies() -> void:
	var state: GameState = GameManager.game_state
	if state == null:
		return
	for army in state.armies:
		var city := state.get_city(army.current_city_id)
		if city == null:
			continue
		# 移动动画中的军团画在曲线上，其余画在城市旁偏移位（避免与城市圆重叠）
		var pos: Vector2
		if _moving.has(army.id):
			var m: Dictionary = _moving[army.id]
			var t: float = m.progress
			var mt: float = 1.0 - t
			pos = m.from * mt * mt + m.ctrl * 2.0 * mt * t + m.to * t * t
		else:
			pos = _to_screen(city.x, city.y) + Vector2(0, -30.0 * _scale)

		var col: Color = UITheme.faction_color(army.owner_faction_id)
		draw_circle(pos, ARMY_RADIUS * _scale, Color(col.r, col.g, col.b, 0.35))
		draw_circle(pos, ARMY_RADIUS * _scale * 0.75, col)
		draw_arc(pos, ARMY_RADIUS * _scale * 0.75, 0, TAU, 16, Color("#2c1c0e"), 1.6 * _scale, true)
		# ⚔ 用 emoji 字体画（主题字体没有该字形）
		var icon_fs: int = max(10, int(13 * _scale))
		draw_string(UITheme.emoji_font, pos + Vector2(0, icon_fs * 0.35), "⚔",
			HORIZONTAL_ALIGNMENT_CENTER, -1, icon_fs, Color("#2c1c0e"))
		# 选中军团金色光环
		if army == _selected_army:
			draw_arc(pos, ARMY_RADIUS * _scale * 1.15, 0, TAU, 24, UITheme.GOLD_BRIGHT, 2.5 * _scale, true)


## 选中状态提示（军团信息小卡）
func _draw_selection() -> void:
	if _selected_army == null:
		return
	var army: Army = _selected_army
	var font := get_theme_default_font()
	var lines: Array[String] = [
		"⚔ %s" % DataManager.get_faction(army.owner_faction_id).get("name_zh", army.owner_faction_id),
		"兵力: %d" % army.team.unit_count(),
		"移动力: %d/%d" % [army.move_points, army.max_move_points],
		"位于: %s" % (DataManager.get_city(army.current_city_id).get("name_zh", "") if DataManager.get_city(army.current_city_id) else ""),
	]
	var y := 60.0
	for line in lines:
		draw_string(font, Vector2(16, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8d4a0"))
		y += 20


# ==================================================================
#  虚线贝塞尔（demo-2 原算法）
# ==================================================================

func _draw_dashed_bezier(from: Vector2, to: Vector2, bend: float) -> void:
	var mid: Vector2 = (from + to) / 2.0
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	var length: float = max(1.0, sqrt(dx * dx + dy * dy))
	var perp: Vector2 = Vector2(-dy / length, dx / length)
	var control: Vector2 = Vector2(mid.x + perp.x * bend, mid.y + perp.y * bend)

	var dash_len: float = 9.0 * _scale
	var gap_len: float = 7.0 * _scale
	var route_color := Color("#7a3b22")
	var route_width: float = max(1.0, 2.0 * _scale)

	var sample_count: int = max(20, int(length / 2.0))
	var prev_point: Vector2 = from
	var accum := 0.0
	var drawing := true
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
				prev_point = prev_point.lerp(point, frac)
				accum -= gap_len
				drawing = true
		if drawing:
			prev_point = point
		else:
			prev_point = point
			accum = min(accum, gap_len)


func _bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var mt: float = 1.0 - t
	return p0 * mt * mt + p1 * 2.0 * mt * t + p2 * t * t


# ==================================================================
#  输入
# ==================================================================

func _gui_input(event: InputEvent) -> void:
	# 右键取消选中
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_selected_army = null
		_dirty = true
		queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# 移动动画播放中屏蔽输入（demo-2 的 is_moving 简化版）
	if not _moving.is_empty():
		return

	var logical: Vector2 = _to_logical(event.position)
	# 命中顺序：军团 > 城市
	var clicked_army: Army = _hit_army(logical)
	if clicked_army != null:
		_on_army_clicked(clicked_army)
		return
	var clicked_city: City = _hit_city(logical)
	if clicked_city != null:
		_on_city_clicked(clicked_city)


## 命中军团标记（逻辑坐标距离判定）
func _hit_army(logical: Vector2) -> Army:
	var state: GameState = GameManager.game_state
	if state == null:
		return null
	for army in state.armies:
		var city := state.get_city(army.current_city_id)
		if city == null:
			continue
		# 军团标记在城市上方偏移 30 逻辑像素
		var marker := Vector2(city.x, city.y - 30.0)
		if logical.distance_to(marker) <= ARMY_RADIUS + 4.0:
			return army
	return null


## 命中城市（距离判定）
func _hit_city(logical: Vector2) -> City:
	var state: GameState = GameManager.game_state
	if state == null:
		return null
	for city in state.cities:
		if logical.distance_to(Vector2(city.x, city.y)) <= CITY_RADIUS + 4.0:
			return city
	return null


func _on_army_clicked(army: Army) -> void:
	var player_id: String = DataManager.get_player_faction_id()
	if army.owner_faction_id != player_id:
		# 敌方军团：只显示归属（选中其城市）
		selected_city_id = army.current_city_id
		_selected_army = null
	else:
		_selected_army = army
		selected_city_id = army.current_city_id
		# 记录出发城（移动动画的起点）
		_army_origin[army.id] = army.current_city_id
	_dirty = true
	queue_redraw()


func _on_city_clicked(city: City) -> void:
	selected_city_id = city.id
	if _selected_army != null:
		# 有选中军团：沿最短路径行军（可多步，直到移动力耗尽或遇敌）
		var result: Dictionary = GameManager.player_move_army_toward(_selected_army.id, city.id)
		if result.get("ok", false):
			# 模型层已走完路径 → 逐段播放动画
			var moves: Array = result.get("moves", [])
			_animate_path_moves(_selected_army, moves)
			# 未到达目标（移动力中途耗尽）→ 明确提示，避免玩家以为没动
			if not moves.is_empty():
				var last_id: String = moves[moves.size() - 1]
				if last_id != city.id:
					var last_city: City = GameManager.game_state.get_city(last_id)
					Alert.alert("%s：%s" % [I18n.t("ui.world.no_move_points"), last_city.name_zh if last_city != null else last_id], UITheme.GOLD)
		elif result.has("battle"):
			# 行军途中遭遇敌军：先播放已走段，战斗场景由 battle_requested 信号切换
			_animate_path_moves(_selected_army, result.get("moves", []))
		else:
			var reason: String = result.get("reason", "")
			if reason == "no_move_points":
				Alert.alert(I18n.t("ui.world.no_move_points"), UITheme.RED)
			elif reason == "already_there":
				pass  # 点自己所在城市：无事发生
			else:
				Alert.alert(I18n.t("ui.world.no_path"), UITheme.RED)
		return
	# 无选中军团：选中城市（Overlay 城市管理按钮用）
	_dirty = true
	queue_redraw()


## ---------------------------------------------------------------------------
## select_army_by_id() — 快速选中军团（左下角统帅条点击调用）
## ---------------------------------------------------------------------------
func select_army_by_id(army_id: String) -> void:
	var state: GameState = GameManager.game_state
	if state == null:
		return
	var army: Army = state.get_army(army_id)
	if army == null:
		return
	var player_id: String = DataManager.get_player_faction_id()
	if army.owner_faction_id != player_id:
		return
	_selected_army = army
	selected_city_id = army.current_city_id
	_army_origin[army.id] = army.current_city_id
	_dirty = true
	queue_redraw()


## ---------------------------------------------------------------------------
## _animate_path_moves() — 沿路径逐段播放移动动画
## ---------------------------------------------------------------------------
## moves：模型层已实际走完的城市 ID 序列（不含起点）。
## 逐段 await 播放；起点逐段更新（上一段终点 = 下一段起点）。
## ---------------------------------------------------------------------------
func _animate_path_moves(army: Army, moves: Array) -> void:
	var prev_id: String = _army_origin.get(army.id, "")
	if prev_id == "" and not moves.is_empty():
		prev_id = moves[0]
	for i in range(moves.size()):
		var target_id: String = moves[i]
		var from_city: City = GameManager.game_state.get_city(prev_id)
		var to_city: City = GameManager.game_state.get_city(target_id)
		if from_city != null and to_city != null:
			await _animate_step(army, from_city, to_city)
		prev_id = target_id
	# 行军完毕：清除选中状态（军团已在新位置，选中圈随之消失）
	if _selected_army != null and _selected_army.id == army.id:
		_selected_army = null
	_army_origin.erase(army.id)
	_dirty = true
	queue_redraw()


## ---------------------------------------------------------------------------
## _animate_step() — 单段移动动画（与路线绘制共用控制点公式）
## ---------------------------------------------------------------------------
## 启动 _moving 动画条目，然后每帧等待直到 _process 推进到终点并擦除。
## ---------------------------------------------------------------------------
func _animate_step(army: Army, from_city: City, to_city: City) -> void:
	var from: Vector2 = _to_screen(from_city.x, from_city.y)
	var to: Vector2 = _to_screen(to_city.x, to_city.y)
	# 查 bend（同 demo-2 的 _edge_bend：反向镜像）
	var bend: float = _route_bend(from_city.id, to_city.id)
	# 控制点公式与 _draw_dashed_bezier 完全一致（移动轨迹与画出的路线重合）
	var mid: Vector2 = (from + to) / 2.0
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	var length: float = max(1.0, sqrt(dx * dx + dy * dy))
	var perp: Vector2 = Vector2(-dy / length, dx / length)
	var ctrl: Vector2 = Vector2(mid.x + perp.x * bend, mid.y + perp.y * bend)
	_moving[army.id] = {
		"army": army, "from": from, "ctrl": ctrl, "to": to,
		"progress": 0.0, "duration": clamp(from.distance_to(to) / 600.0, 0.25, 0.8),
	}
	# _process 每帧推进动画（_moving 为空时零开销返回）
	while _moving.has(army.id):
		await get_tree().process_frame


## 选中军团时的出发城记录（移动动画起点）
var _army_origin: Dictionary = {}


func _route_bend(from_id: String, to_id: String) -> float:
	var routes: Array = DataManager.get_map_data().get("routes", [])
	for r in routes:
		if r[0] == from_id and r[1] == to_id:
			return float(r[2]) * _scale
		if r[0] == to_id and r[1] == from_id:
			return -float(r[2]) * _scale  # 反向镜像
	return 0.0


## 每帧推进移动动画（_moving 为空时零开销返回）
func _process(delta: float) -> void:
	if _moving.is_empty():
		return
	# 边遍历边删除：先收集已完成项再擦除（GDScript 遍历中不能改字典键集）
	var done: Array = []
	for army_id in _moving.keys():
		var m: Dictionary = _moving[army_id]
		m.progress += delta / max(0.01, m.duration)
		if m.progress >= 1.0:
			done.append(army_id)
	for army_id in done:
		_moving.erase(army_id)
		# 动画结束：军团已在新城，取消选中
		if _selected_army != null and _selected_army.id == army_id:
			_selected_army = null
			_army_origin.erase(army_id)
	_dirty = true
	queue_redraw()
