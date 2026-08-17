class_name Main
extends Node3D
## =============================================================================
## 文明 6 · 高度六边形地图 —— 场景编排:环境、相机、输入交互与区域建造流程
## =============================================================================
## 交互:
## · 左键拖拽 旋转视角 / 右键拖拽 平移 / 滚轮 缩放;
## · 左键点击(无拖动)地块:普通模式查看信息,建造模式下尝试放置区域;
## · 右上选择区域类型 → 悬停地块实时预览合法性与预计加成(绿圈/红圈);
## · Esc 或"取消建造"退出建造模式。
## 默认展示:学院(靠山)、商业中心(临河)、水渠(邻城临河)已自动建造,
## 其余区域(圣地/工业区/剧院广场/港口)交给玩家摆放。
## =============================================================================

const SEED := 20260817
const HINT_DEFAULT := "左键拖拽 旋转视角 · 右键拖拽 平移 · 滚轮 缩放 · 点击地块 查看/建造 · Esc 取消建造"

var _map: HexMap
var _sys: DistrictSystem
var _view: MapView
var _ui: MapUI
var _cam: Camera3D

var _yaw_deg := -32.0
var _pitch_deg := 40.0
var _dist := 11.5
var _target := Vector3(0.0, 0.35, 0.0)

var _build_mode := -1
var _selected: HexMap.HexTile = null
var _hovered := Vector2i(99999, 99999)
var _last_mouse := Vector2.ZERO

var _drag_active := false
var _drag_button := 0
var _drag_start := Vector2.ZERO
var _drag_moved := 0.0


func _ready() -> void:
	_map = HexMap.new()
	_map.generate(SEED)
	_sys = DistrictSystem.new()
	_cam = _build_camera()
	_build_environment()
	_view = MapView.new()
	add_child(_view)
	_view.init(_map, _sys)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = MapUI.new()
	layer.add_child(_ui)
	_ui.setup(_sys, _map)
	_ui.build_requested.connect(_on_build_requested)
	_ui.cancel_requested.connect(_on_cancel_build)
	_ui.set_hint(HINT_DEFAULT)
	_auto_setup_showcase()
	_refresh_after_change()


## ----------------------------------------------------------------------------
## 环境与相机
## ----------------------------------------------------------------------------

func _build_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 50.0
	add_child(cam)
	_cam = cam
	_update_cam()
	return cam


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("5b8ec9")
	sky_mat.sky_horizon_color = Color("c9d8e8")
	sky_mat.ground_bottom_color = Color("2e5a8a")
	sky_mat.ground_horizon_color = Color("9fb8cc")
	sky.sky_material = sky_mat
	env.sky = sky
	# 环境光禁用:Godot 4.6 中无光照(unshaded)材质仍会吃到天空环境光,
	# 实测会把纯色染灰蓝、饱和度大减;
	# 色调映射用线性:filmic 的白点抬升(~1.15×)会把中间调提亮冲淡,
	# 线性模式下顶点色渲染出来就是指定的颜色,棋盘风地形颜色完全可控
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -26.0, 0.0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	add_child(light)


func _update_cam() -> void:
	var yaw := deg_to_rad(_yaw_deg)
	var pitch := deg_to_rad(_pitch_deg)
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	_cam.position = _target + dir * _dist
	_cam.look_at(_target)


## ----------------------------------------------------------------------------
## 输入
## ----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_cancel_build()
			_selected = null
			_view.set_selected(null)
			_force_hover_refresh()


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_dist = clampf(_dist * 0.88, 5.5, 22.0)
		_update_cam()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_dist = clampf(_dist * 1.12, 5.5, 22.0)
		_update_cam()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			if not _drag_active:
				_drag_active = true
				_drag_button = mb.button_index
				_drag_start = mb.position
				_drag_moved = 0.0
		else:
			if _drag_active and _drag_button == mb.button_index:
				_end_drag()


func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	_last_mouse = mm.position
	if _drag_active:
		_drag_moved += mm.relative.length()
		if _drag_button == MOUSE_BUTTON_LEFT:
			_yaw_deg = fmod(_yaw_deg - mm.relative.x * 0.35, 360.0)
			_pitch_deg = clampf(_pitch_deg - mm.relative.y * 0.25, 14.0, 78.0)
		else:
			var fwd := _cam.global_position - _target
			fwd.y = 0.0
			fwd = fwd.normalized()
			var right := fwd.cross(Vector3.UP).normalized()
			_target += (right * -mm.relative.x + fwd * mm.relative.y) * (0.009 * _dist)
		_update_cam()
	_update_hover(mm.position)


func _end_drag() -> void:
	var was_click := _drag_moved < 6.0
	var btn := _drag_button
	var pos := _drag_start
	_drag_active = false
	if btn == MOUSE_BUTTON_LEFT and was_click:
		_on_click(pos)


## ----------------------------------------------------------------------------
## 点击 / 悬停
## ----------------------------------------------------------------------------

func _on_click(screen_pos: Vector2) -> void:
	var td := _view.pick_tile(_cam, screen_pos)
	if td == null:
		_on_cancel_build()
		_selected = null
		_view.set_selected(null)
		return
	if _build_mode >= 0:
		var res := _sys.can_place(_map, _build_mode, Vector2i(td.q, td.r))
		if res.ok:
			_sys.place(_map, _build_mode, Vector2i(td.q, td.r))
			_on_cancel_build()
			_selected = td
			_view.set_selected(td)
			_refresh_after_change()
		else:
			_ui.set_hint("无法建造: %s" % res.reason)
		return
	_selected = td
	_view.set_selected(td)
	_update_info()


func _update_hover(screen_pos: Vector2) -> void:
	var td := _view.pick_tile(_cam, screen_pos)
	var coord := Vector2i(99999, 99999)
	if td != null:
		coord = Vector2i(td.q, td.r)
	if coord != _hovered:
		_hovered = coord
		_view.set_preview(null, "", Color.WHITE)
		if td == null:
			_view.set_hover(Vector2i.ZERO, MapView.RingState.NONE)
		elif _build_mode >= 0:
			var res := _sys.can_place(_map, _build_mode, coord)
			var state := MapView.RingState.VALID if res.ok else MapView.RingState.INVALID
			_view.set_hover(coord, state)
			if res.ok:
				var def := _sys.get_def(_build_mode)
				var adj := _sys.adjacency(_map, _build_mode, coord)
				_view.set_preview(td, "%s 预计 +%d %s" % [def.name, adj.total, def.yield_name],
						Color(0.55, 0.95, 0.6))
			else:
				_view.set_preview(td, res.reason, Color(1.0, 0.45, 0.4))
		else:
			_view.set_hover(coord, MapView.RingState.HOVER)
	_update_info()


func _update_info() -> void:
	if _map.tiles.has(_hovered):
		_ui.set_tile_info(_map.tiles[_hovered])
	elif _selected != null:
		_ui.set_tile_info(_selected)
	else:
		_ui.set_tile_info(null)


## ----------------------------------------------------------------------------
## 建造流程
## ----------------------------------------------------------------------------

func _on_build_requested(id: int) -> void:
	_build_mode = id
	_ui.set_build_mode(id)
	var def := _sys.get_def(id)
	_ui.set_hint("建造 %s: %s(绿圈可建、红圈不可建)" % [def.name, def.note])
	_force_hover_refresh()


func _on_cancel_build() -> void:
	_build_mode = -1
	_ui.set_build_mode(-1)
	_ui.set_hint(HINT_DEFAULT)
	_view.set_preview(null, "", Color.WHITE)
	_force_hover_refresh()


func _force_hover_refresh() -> void:
	_hovered = Vector2i(99999, 99999)
	_update_hover(_last_mouse)


func _refresh_after_change() -> void:
	_view.rebuild_all_districts()
	_ui.refresh_bonus_panel()


## ----------------------------------------------------------------------------
## 默认展示:自动建造 学院 / 商业中心 / 水渠
## ----------------------------------------------------------------------------

func _auto_setup_showcase() -> void:
	# 水渠:城市邻居中临河的空地(城市河流保证存在)
	for d in HexCore.DIRS:
		var n := _map.city_coord + d
		if not _map.tiles.has(n):
			continue
		if _map.adjacent_river_count(n) > 0 \
				and _sys.can_place(_map, DistrictSystem.DistrictType.AQUEDUCT, n).ok:
			_sys.place(_map, DistrictSystem.DistrictType.AQUEDUCT, n)
			break
	# 学院:相邻山脉最多
	_try_place(DistrictSystem.DistrictType.CAMPUS, _mountain_score)
	# 商业中心:相邻河岸最多
	_try_place(DistrictSystem.DistrictType.COMMERCIAL_HUB, _river_score)


func _try_place(def_id: int, score: Callable) -> void:
	var spot := _best_spot(def_id, score)
	if spot.x > 99998:
		return
	_sys.place(_map, def_id, spot)


func _best_spot(def_id: int, score: Callable) -> Vector2i:
	var best := Vector2i(99999, 99999)
	var best_score := -1000000
	for coord in _map.tiles:
		if not _sys.can_place(_map, def_id, coord).ok:
			continue
		var s: int = int(score.call(coord))
		if s > best_score:
			best_score = s
			best = coord
	return best


func _mountain_score(coord: Vector2i) -> int:
	return _count_neighbors(coord, func(t: HexMap.HexTile) -> bool:
		return t.elevation >= HexCore.MOUNTAIN)


func _river_score(coord: Vector2i) -> int:
	return _map.adjacent_river_count(coord)


func _count_neighbors(coord: Vector2i, pred: Callable) -> int:
	var n := 0
	for d in HexCore.DIRS:
		var nb := coord + d
		if _map.tiles.has(nb) and bool(pred.call(_map.tiles[nb])):
			n += 1
	return n


## ----------------------------------------------------------------------------
## 调试钩子(截图驱动使用)
## ----------------------------------------------------------------------------

func debug_set_camera(yaw: float, pitch: float, dist: float) -> void:
	_yaw_deg = yaw
	_pitch_deg = pitch
	_dist = dist
	_update_cam()


func debug_place(def_id: int, q: int, r: int) -> void:
	var coord := Vector2i(q, r)
	if _sys.can_place(_map, def_id, coord).ok:
		_sys.place(_map, def_id, coord)
		_refresh_after_change()


func debug_place_all() -> void:
	# 把剩余可建的区域类型各找一个好位置放下(截图展示用)
	var remaining: Array[int] = [
		DistrictSystem.DistrictType.HOLY_SITE,
		DistrictSystem.DistrictType.INDUSTRIAL_ZONE,
		DistrictSystem.DistrictType.THEATER_SQUARE,
		DistrictSystem.DistrictType.HARBOR,
	]
	for id in remaining:
		var spot := _best_spot(id, func(coord: Vector2i) -> int:
			return -HexCore.hex_distance(_map.city_coord, coord))
		if spot.x <= 99998:
			_sys.place(_map, id, spot)
	_refresh_after_change()
