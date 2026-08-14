extends Control
class_name ReelItem
## =============================================================================
## ReelItem — 滚轮中的一个槽位：3×3 等距菱形棋盘
## =============================================================================
## 作用：纯视图 + 输入。绘制一块队伍棋盘（标题、队长行、9 个菱形格、棋子），
##       处理鼠标点击（棋子优先于格子，同网页版重叠层级）。
##
## 几何（对标网页版 index.html）：
##   菱形格 78×40、间距 2 → 水平步长 (78+2)/2=40、垂直步长 (40+2)/2=21
##   cellX(r,c) = (c-r)*40      cellY(r,c) = (c+r)*21 - 42  （-42 使菱形整体居中）
##   格中心相对 item 中心（item 尺寸 = reelW × itemH）
##
## 缓存策略：标题/队长行/棋子缓存只在 set_team() 且队伍索引变化时重建
## （DataManager 查询只发生在这里），每帧只做 apply_state 的标量赋值。
## =============================================================================

# ==================================================================
#  布局常量
# ==================================================================
const TW := 78.0   # 菱形格宽度
const TH := 40.0   # 菱形格高度
const GAP := 2.0   # 格子间距
const STEP_X := (TW + GAP) / 2.0   # 水平步长 40
const STEP_Y := (TH + GAP) / 2.0   # 垂直步长 21
const HALF_W := TW / 2.0           # 菱形半宽 39
const HALF_H := TH / 2.0           # 菱形半高 20
const BOARD_Y_OFF := 42.0          # 菱形 y 跨度 0..84 的中点，上移使整体居中

## 棋子颜色色板（角色数据没有颜色字段，用 id hash 取模得到确定颜色）
const PIECE_COLORS := [
	Color("ffd86b"), Color("7fd4ff"), Color("9affb0"), Color("d59aff"),
	Color("ff8a5b"), Color("c9b48f"), Color("ff6b4a"), Color("5bc0be"),
	Color("f0d264"), Color("8affc1"), Color("ffb3e6"), Color("b8a06a"),
]

# ------------------------------------------------------------------ 信号
## 左键点击棋子（已放置角色的格子）
signal unit_clicked(team_idx: int, r: int, c: int)
## 左键点击空格子
signal cell_clicked(team_idx: int, r: int, c: int)

# ------------------------------------------------------------------ 状态
var team_idx_disp: int = -1     # 此槽位当前展示的队伍索引（缓存键）
var is_active: bool = false     # 是否为居中活跃棋盘
var sel_char_id: String = ""    # 选中单位（仅活跃棋盘有意义）
var move_src_id: String = ""    # 移动模式源单位
var move_target := Vector2i(-1, -1)  # 移动模式目标格 (r, c)

# 显示缓存（team 变化时重建）
var label_text := ""            # "第1队　3/9"
var cap_text := ""              # "队长：xxx" / "（无队长）"
var slots: Array = []           # 9 × {char_id, icon, name, color, captain}

# 重绘脏标记：状态变化才重绘（apply_state 每帧调用）
var _dirty := true


func _ready() -> void:
	# MOUSE_FILTER_STOP — 拦截点击；是否可点由 ReelView 每帧开关
	# （仅居中且停稳的 item 为 STOP，其余 IGNORE，对齐网页版 pointer-events 门控）
	mouse_filter = Control.MOUSE_FILTER_STOP


## ---------------------------------------------------------------------------
## set_team() — 设置此槽位展示哪支队伍（索引变化才重建缓存）
## ---------------------------------------------------------------------------
func set_team(team_idx: int, teams: Array) -> void:
	if team_idx == team_idx_disp:
		return
	team_idx_disp = team_idx
	slots.clear()
	if teams.is_empty() or team_idx < 0 or team_idx >= teams.size():
		label_text = ""
		cap_text = ""
		_dirty = true
		return

	var team: Dictionary = teams[team_idx]
	var captain: String = team.get("captain", "")
	var count := 0
	var cap_name := ""
	for uid in team.units:
		if uid == "":
			continue
		count += 1
	var items: Array = team.units
	for i in range(items.size()):
		var uid = items[i]
		if uid == "":
			slots.append({"char_id": "", "icon": "", "name": "", "color": Color.WHITE, "captain": false})
			continue
		var ch = DataManager.get_character(uid)
		var is_cap: bool = (uid == captain)
		if is_cap:
			cap_name = ch.get("name_zh", "???")
		slots.append({
			"char_id": uid,
			"icon": _char_icon(ch),
			"name": ch.get("name_zh", "???"),
			"color": PIECE_COLORS[posmod(uid.hash(), PIECE_COLORS.size())],
			"captain": is_cap,
		})
	label_text = "%s　%d/9" % [team.get("name", "?"), count]
	cap_text = ("队长：" + cap_name) if cap_name != "" else "（无队长）"
	_dirty = true


## ---------------------------------------------------------------------------
## apply_state() — 每帧由 ReelView 调用，赋值活跃/选中/移动状态
## ---------------------------------------------------------------------------
func apply_state(active: bool, sel_id: String, move_src: String, mt: Vector2i) -> void:
	if active != is_active or sel_id != sel_char_id or move_src != move_src_id or mt != move_target:
		_dirty = true
	is_active = active
	sel_char_id = sel_id
	move_src_id = move_src
	move_target = mt
	if _dirty:
		queue_redraw()


## ---------------------------------------------------------------------------
## _char_icon() — 角色职业 → emoji 图标查表
## ---------------------------------------------------------------------------
func _char_icon(ch: Dictionary) -> String:
	var cls = ch.get("class_zh", "")
	var cls_icons := {
		"领主": "👑", "君主": "👑", "女祭司": "🙏", "斗士": "🛡️", "先锋": "🛡️",
		"兵士": "🔱", "剑士": "⚔️", "剑豪": "⚔️", "佣兵": "⚔️", "重装步兵": "🛡️",
		"角斗士": "💪", "狂战士": "💪", "战士": "🔨", "扫荡者": "🔨",
		"猎人": "🏹", "神猎手": "🏹", "射手": "🏹", "盗贼": "🗡️",
		"骑士": "🐴", "重骑士": "🐴", "白骑士": "🐴", "黑骑士": "🐴",
		"牧师": "✨", "主教": "✨", "法师": "🔥", "术士": "🔥",
		"魔女": "❄️", "女巫": "❄️", "萨满": "🌿", "德鲁伊": "🌿",
		"狮鹫骑士": "🦅", "飞龙骑士": "🐉", "精灵剑士": "⚔️",
	}
	return cls_icons.get(cls, "👤")  # 未知职业默认显示人头图标


## ---------------------------------------------------------------------------
## _cell_center() — 格子中心坐标（item 本地坐标）
## ---------------------------------------------------------------------------
func _cell_center(r: int, c: int) -> Vector2:
	return Vector2(size.x / 2.0 + (c - r) * STEP_X, size.y / 2.0 + (c + r) * STEP_Y - BOARD_Y_OFF)


## ---------------------------------------------------------------------------
## _draw() — 绘制整块棋盘
## ---------------------------------------------------------------------------
## 顺序：标题 → 队长行 → 9 格 → 棋子（棋子在最上层）
## 变暗规则（对齐网页版 .board.dim）：
##   - 非活跃棋盘：整体变暗
##   - 活跃棋盘且有选中单位：其他棋子变暗，选中棋子发光放大
## ---------------------------------------------------------------------------
func _draw() -> void:
	_dirty = false
	if slots.size() < 9:
		return  # 缓存尚未构建（首次入树早于 set_team），跳过
	var font := get_theme_default_font()

	# --- 标题行 ---
	if label_text != "":
		draw_string(font, Vector2(0, 2), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, UITheme.GOLD_BRIGHT)
	if cap_text != "":
		draw_string(font, Vector2(0, 17), cap_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, UITheme.INK_DIM)

	var dim_board := (not is_active) or (sel_char_id != "")
	var dim_factor := 0.55  # 变暗幅度

	# --- 9 个菱形格 ---
	for r in range(3):
		for c in range(3):
			var cc := _cell_center(r, c)
			var pts := PackedVector2Array([
				cc + Vector2(0, -HALF_H), cc + Vector2(HALF_W, 0),
				cc + Vector2(0, HALF_H), cc + Vector2(-HALF_W, 0),
			])
			var is_light := (r + c) % 2 == 0
			var fill: Color = UITheme.TILE_LIGHT if is_light else UITheme.TILE_DARK
			var border: Color = UITheme.LINE
			if dim_board:
				fill = fill.darkened(dim_factor)
				border = border.darkened(dim_factor)
			# 已放置角色的格子加深一点（层次感）
			if slots[r * 3 + c].char_id != "":
				fill = fill.darkened(0.25)
			# 移动模式目标格 → 绿色高亮
			if is_active and move_src_id != "" and move_target == Vector2i(r, c):
				fill = Color(0.48, 0.72, 0.35, 0.25)
				border = UITheme.GREEN
			# 选中单位所在格 → 金色描边
			if is_active and sel_char_id != "" and slots[r * 3 + c].char_id == sel_char_id:
				border = UITheme.GOLD
			draw_colored_polygon(pts, fill)
			draw_polyline(pts + PackedVector2Array([pts[0]]), border, 1.5)

	# --- 棋子（emoji + 名字 + 队长皇冠） ---
	for r in range(3):
		for c in range(3):
			var s: Dictionary = slots[r * 3 + c]
			if s.char_id == "":
				continue
			var cc := _cell_center(r, c)
			var icon_color: Color = s.color
			var is_sel: bool = is_active and s.char_id == sel_char_id
			var is_src: bool = is_active and s.char_id == move_src_id
			if dim_board and not is_sel:
				icon_color = icon_color.darkened(0.5)
			var icon_pos := cc + Vector2(0, -6)
			if is_sel:
				# 选中：金色光晕 + 放大 1.2
				draw_circle(icon_pos, 16, Color(1.0, 0.85, 0.42, 0.30))
				draw_set_transform(icon_pos, 0.0, Vector2(1.2, 1.2))
				draw_string(ThemeDB.fallback_font, Vector2(-11, 8), s.icon, HORIZONTAL_ALIGNMENT_CENTER, 22, 22, icon_color)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_string(ThemeDB.fallback_font, icon_pos + Vector2(-11, -11), s.icon, HORIZONTAL_ALIGNMENT_CENTER, 22, 22, icon_color)
			if s.captain:
				# 队长皇冠（图标上方）
				draw_string(ThemeDB.fallback_font, icon_pos + Vector2(-6, -22), "👑", HORIZONTAL_ALIGNMENT_CENTER, 12, 12, UITheme.GOLD_BRIGHT)
			# 名字小字（图标下方）
			draw_string(font, cc + Vector2(-20, 14), s.name, HORIZONTAL_ALIGNMENT_CENTER, 40, 8, UITheme.INK if is_active else UITheme.INK.darkened(0.4))
			if is_src:
				# 移动源：蓝色脉冲环
				draw_arc(icon_pos, 18, 0, TAU, 24, Color(0.47, 0.78, 1.0, 0.8), 2.0)


## ---------------------------------------------------------------------------
## _gui_input() — 鼠标点击处理
## ---------------------------------------------------------------------------
## 命中检测顺序：棋子优先（半径 18 圆），然后菱形格
## （菱形判定 |dx|/39 + |dy|/20 <= 1，与 CSS clip-path 命中区域一致）
##
## 滚轮事件：不处理、不 accept_event() —— 冒泡给 ReelView 是滚轮路由机制。
## ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	# --- 棋子命中优先 ---
	for r in range(3):
		for c in range(3):
			var s: Dictionary = slots[r * 3 + c]
			if s.char_id == "":
				continue
			var cc := _cell_center(r, c) + Vector2(0, -6)
			if event.position.distance_to(cc) <= 18.0:
				unit_clicked.emit(team_idx_disp, r, c)
				accept_event()
				return

	# --- 菱形格命中 ---
	for r in range(3):
		for c in range(3):
			var cc := _cell_center(r, c)
			var d: Vector2 = event.position - cc
			if absf(d.x) / HALF_W + absf(d.y) / HALF_H <= 1.0:
				cell_clicked.emit(team_idx_disp, r, c)
				accept_event()
				return
