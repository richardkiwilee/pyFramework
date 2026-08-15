extends Control
## =============================================================================
## ReelView — 老虎机式垂直滚轮组合控件（左侧核心）
## =============================================================================
## 作用：对标网页版"棋盘滚轮"。5 个槽位，居中槽位为当前队伍；
##       每个槽位是一块 3×3 等距菱形棋盘（ReelItem）。
##       包含：机框、居中指示框、上下遮罩、跟随选中单位的聚光灯。
##
## 动画（对标网页版 index.html）：
##   current（浮点中心）→ target 缓动，网页版每帧 0.16 系数，
##   此处用帧率无关形式：t = 1 - 0.84^(delta*60)，60fps 时恰为 0.16。
##   item 变换：ty = d*itemH；scale = max(0.42, 1-|d|*0.26)；
##   alpha = max(0, 1-|d|*0.40)；z 随距离递减。
##
## 交互门控（对齐网页版 pointer-events）：
##   仅居中且停稳的 item 可点击（mouse_filter STOP），其余 IGNORE。
##   滚轮事件由 ReelView 统一处理（item 不 accept 滚轮事件，冒泡至此）。
##
## 子节点结构（全部代码创建，参照现有 EquipPicker 动态创建模式）：
##   ReelView (STOP, clip_contents)
##   ├─ ItemLayer (IGNORE) → 5× ReelItem
##   ├─ Indicator (ReelOverlay 脚本 _draw，绘制逻辑在 ReelView)
##   ├─ Spotlight (ReelOverlay，零尺寸，位于选中单位格中心)
##   ├─ MaskTop / MaskBottom (ReelOverlay，阶梯色带模拟渐变遮罩)
##   └─ SnapTimer (one_shot 0.13s，滚轮停止后吸附到整数)
## =============================================================================

const ReelItemClass = preload("res://scripts/main/reel_item.gd")
const ReelOverlayClass = preload("res://scripts/main/reel_overlay.gd")

# ==================================================================
#  布局常量
# ==================================================================
const PAD := 6.0        # 机框内边距
const SLOT_COUNT := 5   # 槽位数（±2）
const RANGE := 2        # 槽位偏移范围
const SNAP_DELAY := 0.13  # 滚轮停止后吸附延迟（秒）
const FEED_SNAP_DELAY := 0.2  # feed/scroll_to 的吸附延迟（秒）

# ------------------------------------------------------------------ 信号
## 滚轮停稳且中心队伍索引变化时发出
signal settled(team_idx: int)
## 转发 item 的信号（MainScreen 统一处理）
signal unit_clicked(team_idx: int, r: int, c: int)
signal cell_clicked(team_idx: int, r: int, c: int)

# ------------------------------------------------------------------ 状态（由 MainScreen 通过 refresh() 注入）
var _teams: Array = []
var _active_idx := 0
var _sel_id := ""
var _move_src := ""
var _move_target := Vector2i(-1, -1)
var _focus_left := true

# ------------------------------------------------------------------ 滚轮运动状态
var _current := 0.0     # 浮点中心
var _target := 0.0      # 目标中心
var _snapping := false  # 是否正在吸附到整数
var _settled := true    # 是否停稳
var _last_centered := -1  # 上次 settle 时的中心队伍索引

# ------------------------------------------------------------------ 节点引用
var _items: Array[ReelItem] = []      # 5 × ReelItem
var _indicator: Control
var _spotlight: Control
var _snap_timer: Timer
var _spot_pos := Vector2.ZERO   # 聚光灯平滑位置
var _spot_alpha := 0.0

# ------------------------------------------------------------------ 几何
var _reel_h := 100.0
var _reel_w := 100.0
var _item_h := 100.0

# 数据版本号：每次 refresh() 自增，通知 item 队伍数据已变（即使索引未变也要重建缓存）
var _data_version := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true  # 溢出裁剪（网页版 overflow:hidden）
	_build_children()
	resized.connect(_recompute)
	_recompute()


func _build_children() -> void:
	# --- ItemLayer：5 个棋盘槽位 ---
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	for k in range(SLOT_COUNT):
		var item := ReelItemClass.new()
		layer.add_child(item)
		item.unit_clicked.connect(func(ti, r, c): unit_clicked.emit(ti, r, c))
		item.cell_clicked.connect(func(ti, r, c): cell_clicked.emit(ti, r, c))
		_items.append(item)

	# --- Indicator：居中指示框（独立脚本 _draw，绘制逻辑在 ReelView）---
	_indicator = _make_overlay(ReelOverlayClass.Mode.INDICATOR, 110)
	add_child(_indicator)

	# --- Spotlight：聚光灯（零尺寸，位置=选中单位格中心）---
	_spotlight = _make_overlay(ReelOverlayClass.Mode.SPOTLIGHT, 120)
	_spotlight.modulate.a = 0.0
	add_child(_spotlight)

	# --- 上下遮罩 ---
	var mask_top := _make_overlay(ReelOverlayClass.Mode.MASK_TOP, 130)
	add_child(mask_top)
	var mask_bottom := _make_overlay(ReelOverlayClass.Mode.MASK_BOTTOM, 130)
	add_child(mask_bottom)

	# --- 吸附计时器 ---
	_snap_timer = Timer.new()
	_snap_timer.one_shot = true
	_snap_timer.wait_time = SNAP_DELAY
	add_child(_snap_timer)
	_snap_timer.timeout.connect(func(): _snapping = true)


## 创建一个覆盖层节点（ReelOverlay 脚本，IGNORE 鼠标，指定 z）
## 注意：SPOTLIGHT 是零尺寸自由定位节点（position=选中单位格中心），不设全矩形锚
func _make_overlay(mode: int, z: int) -> Control:
	var ov := ReelOverlayClass.new()
	ov.mode = mode
	ov.reel = self
	if mode != ReelOverlayClass.Mode.SPOTLIGHT:
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.z_index = z
	return ov


## ---------------------------------------------------------------------------
## refresh() — MainScreen 注入状态快照
## ---------------------------------------------------------------------------
func refresh(state: Dictionary) -> void:
	_teams = state.get("teams", [])
	_active_idx = state.get("active_idx", 0)
	_sel_id = state.get("sel_id", "")
	_move_src = state.get("move_src", "")
	_move_target = state.get("move_target", Vector2i(-1, -1))
	_focus_left = state.get("focus_left", true)
	_data_version += 1


## ---------------------------------------------------------------------------
## feed() — 滚动 n 队（dir 方向；big=true 时滚动 teams.size() 队）
## ---------------------------------------------------------------------------
func feed(dir: int, big: bool = false) -> void:
	if _teams.is_empty():
		return
	var step: int = _teams.size() if big else 1
	_target += float(dir * step)
	_snapping = true
	_settled = false
	_snap_timer.start(FEED_SNAP_DELAY)


## ---------------------------------------------------------------------------
## scroll_to() — 直接滚动到指定队伍索引（点击其他棋盘/新建队伍后调用）
## ---------------------------------------------------------------------------
func scroll_to(idx: int) -> void:
	if _teams.is_empty():
		return
	_target = float(idx)
	_snapping = true
	_settled = false
	_snap_timer.start(FEED_SNAP_DELAY)


## ---------------------------------------------------------------------------
## get_center_index() / is_settled()
## ---------------------------------------------------------------------------
func get_center_index() -> int:
	if _teams.is_empty():
		return 0
	return posmod(int(roundf(_current)), _teams.size())


func is_settled() -> bool:
	return _settled


# ==================================================================
#  几何
# ==================================================================

## 机框内边距 PAD 内外，内容区 = [PAD, size-PAD]
## item 中心 y = PAD + reelH/2 + ty = size.y/2 + ty（与指示框严格同心）
func _recompute() -> void:
	if size.y < 50.0:
		return  # 首次布局前防御
	_reel_h = size.y - 2.0 * PAD
	_reel_w = roundf(_reel_h * 5.0 / 9.0)
	_item_h = roundf(_reel_h / 3.0)


# ==================================================================
#  输入：滚轮滚动（仅左焦点且鼠标悬停在滚轮上时生效）
# ==================================================================

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if not _focus_left or _teams.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_feed_fraction(-1.0)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_feed_fraction(1.0)
		accept_event()


## 自由滚动一小段（对齐网页版 deltaY/100*0.9），130ms 后吸附
func _feed_fraction(dy: float) -> void:
	_target += dy * 0.9
	_snapping = false
	_settled = false
	_snap_timer.start(SNAP_DELAY)


# ==================================================================
#  每帧更新
# ==================================================================

func _process(delta: float) -> void:
	var n := _teams.size()
	if n == 0:
		return

	# --- 缓动（帧率无关，等价网页版每帧 0.16） ---
	var t := 1.0 - pow(0.84, delta * 60.0)
	_current = lerpf(_current, _target, t)

	# --- 吸附 ---
	if _snapping:
		_target = roundf(_target)  # 吸附到最近整数（幂等）
		if absf(_target - _current) < 0.01:
			_current = _target
			_snapping = false
			var centered := posmod(int(roundf(_current)), n)
			if centered != _last_centered:
				_last_centered = centered
				settled.emit(centered)  # MainScreen 切换活跃队伍
	_settled = (not _snapping) and absf(_target - _current) < 0.005

	_update_items()
	_update_spotlight(delta)


## 每帧更新 5 个槽位的变换与状态
func _update_items() -> void:
	var n := _teams.size()
	var base := int(roundf(_current))
	for k in range(SLOT_COUNT):
		var i := base + (k - RANGE)
		var team_idx := posmod(i, n)
		var d := float(i) - _current
		var ad := absf(d)
		var item: ReelItem = _items[k]
		item.set_team(team_idx, _teams, _data_version)  # 索引或数据版本变化时重建缓存
		item.size = Vector2(_reel_w, _item_h)
		item.pivot_offset = Vector2(_reel_w / 2.0, _item_h / 2.0)
		item.position = Vector2((size.x - _reel_w) / 2.0, size.y / 2.0 - _item_h / 2.0 + d * _item_h)
		var s := maxf(0.42, 1.0 - ad * 0.26)
		item.scale = Vector2(s, s)
		item.modulate.a = maxf(0.0, 1.0 - ad * 0.40)
		item.z_index = 100 - int(roundf(ad * 10.0))
		# 仅居中且停稳的 item 可点击（网页版 pointer-events 门控）
		var centered := (team_idx == posmod(int(roundf(_current)), n)) and _settled
		item.mouse_filter = Control.MOUSE_FILTER_STOP if centered else Control.MOUSE_FILTER_IGNORE
		item.apply_state(centered and _active_idx == team_idx, _sel_id, _move_src, _move_target)


## 聚光灯：平滑移动到选中单位格中心，未选中/滚动中淡出
func _update_spotlight(delta: float) -> void:
	var n := _teams.size()
	var target_pos := Vector2.ZERO
	var visible := false
	if _settled and n > 0 and _sel_id != "":
		var team: Dictionary = _teams[posmod(_active_idx, n)]
		for s in range(team.units.size()):
			if team.units[s] == _sel_id:
				var r := s / 3
				var c := s % 3
				target_pos = Vector2(size.x / 2.0 + (c - r) * ReelItemClass.STEP_X,
					size.y / 2.0 + (c + r) * ReelItemClass.STEP_Y - ReelItemClass.BOARD_Y_OFF)
				visible = true
				break
	var ease_t := 1.0 - pow(0.7, delta * 60.0)
	_spot_pos = _spot_pos.lerp(target_pos, ease_t)
	_spot_alpha = lerpf(_spot_alpha, 1.0 if visible else 0.0, ease_t)
	# 节点必须有非零矩形才不会被渲染剔除；绘制内容相对节点左上角偏移 (80, 300)，
	# 使局部 (80, 300) 对准选中单位格中心（锥底锚点）
	_spotlight.position = _spot_pos + Vector2(-80, -300)
	_spotlight.size = Vector2(160, 320)
	_spotlight.modulate.a = _spot_alpha


# ==================================================================
#  绘制（全平涂——仓库风格不使用渐变，用阶梯色带模拟）
# ==================================================================

## 机框：深紫底 + 金边 + 内描边（网页版 .reel-container）
func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0a0718")
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.831, 0.686, 0.216, 0.32)
	sb.set_corner_radius_all(18)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	# 内描边（模拟内阴影）
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0, 0, 0, 0)
	inner.border_width_left = 6
	inner.border_width_right = 6
	inner.border_width_top = 6
	inner.border_width_bottom = 6
	inner.border_color = Color(0.071, 0.047, 0.18, 0.8)  # #120c2e
	draw_style_box(inner, Rect2(3, 3, size.x - 6, size.y - 6))


## 居中指示框：金色上下边 + 两侧发光圆点 + 中心淡金色带
## cv = 正在 _draw 的覆盖层节点（绘制调用必须落在其上，不能落在 self）
func draw_indicator_overlay(cv: Control) -> void:
	var cy := cv.size.y / 2.0
	cv.draw_rect(Rect2(0, cy - _item_h / 2.0, cv.size.x, 2), UITheme.GOLD)
	cv.draw_rect(Rect2(0, cy + _item_h / 2.0 - 2, cv.size.x, 2), UITheme.GOLD)
	cv.draw_rect(Rect2(0, cy - _item_h / 2.0, cv.size.x, _item_h), Color(1.0, 0.81, 0.25, 0.05))
	# 两侧发光圆点
	cv.draw_circle(Vector2(6, cy), 9, Color(1.0, 0.85, 0.42, 0.3))
	cv.draw_circle(Vector2(6, cy), 4.5, UITheme.GLOW)
	cv.draw_circle(Vector2(cv.size.x - 6, cy), 9, Color(1.0, 0.85, 0.42, 0.3))
	cv.draw_circle(Vector2(cv.size.x - 6, cy), 4.5, UITheme.GLOW)


## 上下遮罩：3 条阶梯色带模拟 CSS 渐变（网页版 .mask）
func draw_mask_overlay(cv: Control, is_top: bool) -> void:
	var alphas := [0.5, 0.28, 0.12]
	if not is_top:
		alphas.reverse()
	var band_h := _item_h / 3.0
	for b in range(3):
		var y: float
		if is_top:
			y = b * band_h
		else:
			y = cv.size.y - _item_h + b * band_h
		cv.draw_rect(Rect2(0, y, cv.size.x, band_h), Color(0.02, 0.012, 0.047, alphas[b]))


## 聚光灯（局部 (80, 300) = 锥底中心，对应网页版 translate(-50%,-100%) 原点）
## 节点矩形 160×320，位置 = 目标点 + (-80, -300)（见 _update_spotlight）
## 层次：光环梯形 → 锥形梯形 → 地面光斑椭圆 → 顶部光源点
func draw_spotlight_overlay(cv: Control) -> void:
	var o := Vector2(80, 300)  # 局部原点偏移：锥底中心
	# 光环（160×150 梯形，收口 30%/70%）
	cv.draw_colored_polygon(PackedVector2Array([
		o + Vector2(-24, -150), o + Vector2(24, -150), o + Vector2(80, 0), o + Vector2(-80, 0),
	]), Color(1.0, 0.85, 0.42, 0.10))
	# 锥形（96×130 梯形，收口 38%/62%）
	cv.draw_colored_polygon(PackedVector2Array([
		o + Vector2(-18.24, -130), o + Vector2(18.24, -130), o + Vector2(48, 0), o + Vector2(-48, 0),
	]), Color(1.0, 0.85, 0.42, 0.16))
	# 地面光斑（椭圆，24 点多边形近似）
	var pool := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		pool.append(o + Vector2(0, 26) + Vector2(cos(a) * 52, sin(a) * 27))
	cv.draw_colored_polygon(pool, Color(1.0, 0.91, 0.59, 0.25))
	# 顶部光源点
	cv.draw_circle(o + Vector2(0, -132), 8, Color(1.0, 0.97, 0.87, 0.8))
