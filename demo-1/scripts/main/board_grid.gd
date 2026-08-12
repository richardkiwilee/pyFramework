extends Control
## =============================================================================
## BoardGrid — 单支队伍的阵型棋盘控件
## =============================================================================
## 作用：用 _draw() 手绘一个 3×2 的六边形阵型棋盘，显示角色图标和名称。
##       处理鼠标点击来选中/放置/移除角色。
##
## class_name BoardGrid — 注册为全局类名，其他脚本可以 `var b = BoardGrid.new()`
##
## Godot 概念说明 — _draw() 手绘：
##   这是 Godot 中完全代码控制渲染的方式。在 _draw() 中调用绘图函数，
##   引擎会在每个帧渲染时自动执行。调用 queue_redraw() 触发重绘。
##   类似 Python 中 matplotlib/tkinter Canvas 的绘制回调。
##
##   常用 _draw() 函数：
##     draw_string(font, pos, text)  — 绘制文字
##     draw_colored_polygon(points, color) — 绘制填充多边形
##     draw_polyline(points, color, width) — 绘制多边形边框
##
## Godot 概念说明 — _gui_input()：
##   Control 节点的输入处理回调。当鼠标在控件区域内操作时触发。
##   通过 event is InputEventMouseButton 判断是否为鼠标事件。
## =============================================================================

# ==================================================================
#  布局常量 (Layout Constants)
# ==================================================================
# 六边形格子的定位参数。这些值经过手动调整以达到美观的排列效果。

## HEX_W/HEX_H — 六边形格子的视觉尺寸参考值
const HEX_W := 78.0   # 六边形宽度参考
const HEX_H := 62.0   # 六边形高度参考

## FRONT_Y / BACK_Y — 前排和后排格子的 Y 坐标（从上到下的像素位置）
## 前排在上，后排在下
const FRONT_Y := 58.0
const BACK_Y := 130.0

## X_OFFSETS — 3 列的 X 坐标。前排和后排共享同一组 X 位置。
## slot % 3 得到列号 (0,1,2)，对应三个 X 坐标
const X_OFFSETS := [120.0, 210.0, 300.0]

# ==================================================================
#  运行时状态
# ==================================================================

## 这个棋盘属于第几队（0-based）
var team_index: int = -1

## 队伍数据引用（包含 units 数组）
var team_data: Dictionary = {}

## 是否为当前选中的队伍（影响高亮/可交互状态）
var is_active: bool = false

## 当前鼠标悬停的格子（-1 表示无）
var hovered_slot: int = -1

## 当前选中的格子（-1 表示无选中）
var selected_slot: int = -1

## 已放置角色的图标缓存 — slot(int) → emoji 字符串
var unit_icons: Dictionary = {}  # {0: "👑", 1: "🔥", ...}

## 已放置角色的名称缓存 — slot(int) → 名称字符串
var unit_names: Dictionary = {}  # {0: "亚连", 1: "梅丽桑德", ...}

# ------------------------------------------------------------------ 信号
## 左键点击格子时发出
signal slot_clicked(slot: int, board: BoardGrid)
## 右键点击格子时发出（用于移除角色）
signal slot_right_clicked(slot: int, board: BoardGrid)


func _ready() -> void:
	# 设置控件的最小尺寸，确保布局不被压缩
	custom_minimum_size = Vector2(380, 210)
	# MOUSE_FILTER_STOP — 控件会拦截鼠标事件，防止穿透到下层控件
	# 类似 CSS 的 pointer-events: auto
	mouse_filter = Control.MOUSE_FILTER_STOP


## ---------------------------------------------------------------------------
## refresh() — 刷新棋盘显示
## ---------------------------------------------------------------------------
## 当队伍数据变化时由 main_screen 调用。
## 重建 unit_icons 和 unit_names 缓存，然后触发重绘。
##
## 参数：
##   team_idx — 队伍索引（0-based）
##   units    — 角色ID数组，长度6，空位为 ""
##   active   — 是否为当前活跃队伍
## ---------------------------------------------------------------------------
func refresh(team_idx: int, units: Array, active: bool) -> void:
	team_index = team_idx
	team_data = {"units": units}
	is_active = active
	unit_icons.clear()
	unit_names.clear()

	# 遍历6个槽位，为有角色的槽位缓存图标和名称
	for i in range(units.size()):
		var cid = units[i]
		if cid != "":
			var ch = DataManager.get_character(cid)
			unit_icons[i] = _char_icon(ch)
			unit_names[i] = ch.get("name_zh", "???")

	# 触发 _draw() 重绘
	queue_redraw()


## ---------------------------------------------------------------------------
## _char_icon() — 根据角色职业返回对应 emoji 图标
## ---------------------------------------------------------------------------
## 这是一个简单的查表映射。职业中文名 → Unicode emoji。
## 类似 Unicorn Overlord（圣兽之王）风格的职业图标表示。
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
## _draw() — Godot 的绘制回调（每帧或 queue_redraw() 后触发）
## ---------------------------------------------------------------------------
## 绘制顺序很重要：先画格子，再画图标和文字（文字在最上层）。
##
## draw_string() 参数说明：
##   draw_string(font, position, text, alignment, width, font_size, color)
##   - font: 使用 get_theme_default_font() 获取主题默认字体
##   - alignment: HORIZONTAL_ALIGNMENT_CENTER 水平居中
##   - width: -1 表示不限制宽度
## ---------------------------------------------------------------------------
func _draw() -> void:
	# --- 绘制队伍标签 ---
	# 活跃队伍用金色，非活跃队伍用暗色
	var label_color := UITheme.GOLD_BRIGHT if is_active else UITheme.INK_DIM
	draw_string(get_theme_default_font(), Vector2(10, 18), "第%d队" % (team_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_color)

	# --- 绘制 6 个六边形格子 ---
	for slot in range(6):
		# 计算格子的中心位置
		# slot % 3 → 列号(0,1,2)，对应 X_OFFSETS
		# slot < 3 → 前排(FRONT_Y)，slot >= 3 → 后排(BACK_Y)
		var x = X_OFFSETS[slot % 3]
		var y = FRONT_Y if slot < 3 else BACK_Y
		var pos = Vector2(x, y)

		# 决定格子颜色（实现棋盘格交替效果）
		# 前排：slot 0(偶数=亮), 1(奇数=暗), 2(偶数=亮)
		# 后排：slot 3(奇数=暗), 4(偶数=亮), 5(奇数=暗)
		# is_light 决定用亮色还是暗色
		var is_light := (slot % 2 == (0 if slot < 3 else 1))

		var fill_color: Color
		if slot == selected_slot and is_active:
			# 选中状态：高亮金色半透明覆盖
			fill_color = Color(1.0, 0.85, 0.4, 0.4)  # RGBA，最后一个值 0.4 是透明度
		elif unit_icons.has(slot):
			# 已放置角色的格子：使用面板色
			fill_color = UITheme.PANEL2
		elif is_light:
			# 空格子（亮色）
			fill_color = Color("c9b48f") if is_active else Color("c9b48f").darkened(0.5)
		else:
			# 空格子（暗色）
			fill_color = Color("6b5a42") if is_active else Color("6b5a42").darkened(0.5)

		# .darkened(0.5) — Color 的内置方法，返回变暗50%的颜色
		# 非活跃队伍的格子色调更暗，形成视觉对比

		_draw_hex(pos, fill_color, UITheme.LINE if is_active else UITheme.LINE.darkened(0.5))

		# --- 在已放置角色的格子上绘制图标和名称 ---
		if unit_icons.has(slot):
			var icon = unit_icons[slot]
			var name = unit_names.get(slot, "")
			# 图标绘制在格子中心偏上的位置
			draw_string(get_theme_default_font(), pos + Vector2(-16, -26), icon,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
			# 名称只在活跃队伍时显示
			if is_active:
				draw_string(get_theme_default_font(), pos + Vector2(0, 12), name,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 10, UITheme.INK)


## ---------------------------------------------------------------------------
## _draw_hex() — 绘制单个六边形格子
## ---------------------------------------------------------------------------
## 参数：
##   center — 六边形的中心坐标
##   fill   — 填充色
##   border — 边框色
##
## 六边形绘制原理：
##   用极坐标计算6个顶点的位置。从角度 PI/6（30°）开始，每次增加
##   TAU/6（60°），得到正六边形的6个顶点。
##
##   TAU = 2*PI ≈ 6.283（Godot 内置常量）
##   六边形的外接圆半径为 radius，但 Y 方向乘以 0.65 得到压扁效果。
##
##   先画填充多边形（draw_colored_polygon），再画边框（draw_polyline），
##   这样边框覆盖在填充之上，形成清晰的轮廓。
## ---------------------------------------------------------------------------
func _draw_hex(center: Vector2, fill: Color, border: Color) -> void:
	var points := PackedVector2Array()  # 存储6个顶点的紧凑数组
	var sides := 6
	var radius := 38.0
	for i in range(sides):
		# cos/sin 计算顶点偏移：angle 从 PI/6(30°) 开始，每次加 TAU/6(60°)
		var angle = PI / 6 + i * TAU / sides
		# Y 乘以 0.65 得到略扁的六边形（更符合等距视角的美术风格）
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.65))
	draw_colored_polygon(points, fill)
	draw_polyline(points, border, 1.5)  # 线宽 1.5 像素


## ---------------------------------------------------------------------------
## _gui_input() — 鼠标输入处理
## ---------------------------------------------------------------------------
## 这是 Control 节点的输入回调。当鼠标在控件区域内操作时，
## Godot 引擎自动调用此方法。
##
## InputEvent 体系（类比 Python）：
##   InputEvent 是 Godot 输入事件的基类。
##   `event is InputEventMouseButton` — 用 `is` 判断事件类型，类似于
##   Python 的 `isinstance(event, MouseEvent)`。
##
## 事件属性：
##   event.position  — 鼠标在控件内的坐标（相对于控件左上角）
##   event.pressed   — true=按下, false=释放
##   event.button_index — 哪个按钮（MOUSE_BUTTON_LEFT / MOUSE_BUTTON_RIGHT）
##
## 点击检测逻辑：
##   遍历6个槽位，计算鼠标位置与每个格子中心点的距离。
##   距离 < 38（六边形外接圆半径）就算点击命中。
##   这种"圆碰撞检测"比精确的六边形碰撞简单，且实际使用中精度足够。
## ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	# 所有棋盘都响应点击（不在 is_active 时提前返回）
	# 这样点击任意队伍的角色即可切换出战队伍
	if event is InputEventMouseButton and event.pressed:
		var mp = event.position  # 鼠标位置
		# 遍历6个格子检测点击命中
		for slot in range(6):
			var x = X_OFFSETS[slot % 3]
			var y = FRONT_Y if slot < 3 else BACK_Y
			# .distance_to() — Vector2 的内置方法，计算两点间欧几里得距离
			if mp.distance_to(Vector2(x, y)) < 38:
				if event.button_index == MOUSE_BUTTON_LEFT:
					# 左键：选中格子并发出信号
					selected_slot = slot
					slot_clicked.emit(slot, self)
					queue_redraw()  # 触发重绘以显示选中高亮
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					# 右键：发出移除信号
					slot_right_clicked.emit(slot, self)
				# 命中后立即返回，避免重复触发
				return
