extends Control
## =============================================================================
## MapView — 十字军圣地之路大地图
## =============================================================================
## 作用：一张中世纪风格的大地图，玩家用 WASD/方向键控制角色沿
##       虚线路线在据点（城市）之间移动。全部画面用代码手绘（_draw），
##       不使用任何图片资源。
##
## 核心功能拆解：
##   1. 数据定义 — 12 个据点（CITIES）和 15 条连接路线（ROUTES）
##   2. 方向映射 — 为每个据点计算"W/S/A/D 分别通往哪个相邻据点"
##   3. 手绘地图 — 海洋、陆地、装饰、虚线弧线路线、据点、角色、HUD
##   4. 曲线移动 — 角色沿贝塞尔曲线动画移动到目标据点
##
## Godot 概念说明 — 手绘（_draw）：
##   和 demo-1 的 BoardGrid 一样，本脚本继承 Control，在 _draw() 中
##   用 draw_rect / draw_circle / draw_line / draw_polygon 等函数直接
##   绘制画面。queue_redraw() 触发重绘。所有"美术"都是几何图形，
##   类似 Python 中用 turtle 或 matplotlib 画图。
##
## Godot 概念说明 — 贝塞尔曲线（Bezier Curve）：
##   路线用二次贝塞尔曲线绘制：起点 P0、控制点 P1、终点 P2。
##   曲线上参数 t (0~1) 处的点：
##     B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
##   t=0 在起点，t=1 在终点。控制点"拉"曲线向自己弯曲——
##   bend 值就是控制点相对中点的偏移量，bend>0 向右弯，bend<0 向左弯。
##   这正是"路线的弧线感"的来源，同时移动动画也沿同一条曲线走，
##   保证角色移动轨迹和画出的路线完全重合。
##
## Godot 概念说明 — 视口缩放（_scale / _offset）：
##   地图数据用固定坐标（1200×820 的"逻辑坐标系"），但窗口大小可变。
##   通过 _scale 把逻辑坐标缩放到屏幕坐标，_offset 把缩放后的地图
##   居中。_to_screen() 做坐标转换。这类似地图软件的"投影"概念。
## =============================================================================

# 地图逻辑尺寸（设计坐标系，独立于实际窗口大小）
const MAP_W: float = 1200.0
const MAP_H: float = 820.0

# ============================================================
#  据点数据 (Cities)
# ============================================================
## 每个据点是一个 Dictionary（类似 Python dict）：
##   id   — 唯一标识（内部使用）
##   cn   — 中文名（屏幕显示）
##   lat  — 拉丁文名（副标题显示，中世纪风味）
##   x, y — 逻辑坐标（地图设计坐标系中的位置）
##   type — 据点类型，决定圆点颜色：
##          "holy"  圣城（金色）    "great" 大城（红棕）
##          "port"  港口（蓝色）    "land"  内陆（绿色）
##
## GDScript 注意：
##   const CITIES: Array[Dictionary] — 带类型的常量数组。
##   {id="...", cn="..."} 是 Dictionary 字面量，和 Python dict 写法相同。
##   数组项写在一行（GDScript 允许省略换行分号）。
## ============================================================
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
#  路线数据 (Routes)
# ============================================================
## 每条路线是 3 元数组：[起点id, 终点id, bend]
##
## bend 的含义：路线的弯曲方向和程度。
##   bend > 0 → 弧线向右弯（相对行进方向）
##   bend < 0 → 弧线向左弯
##   bend 的绝对值越大，弧线越弯
##   实际上 bend 是贝塞尔控制点沿"垂直方向"的偏移量（像素）。
##
## 注意：路线是"无向边"（双向通行）。同一对城市不需要写两次；
## 反向通行时取 -bend（镜像弯曲），保证两个方向看到的弧线一致。
##
## 数据结构类似 Python 的 list[list[str, str, int]]。
## ============================================================
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
#  运行时状态 (Runtime State)
# ============================================================

## 角色当前所在的据点ID（初始在罗马）
var current_city_id: String = "roma"

## 是否正在移动（移动动画播放中，期间忽略新输入）
var is_moving: bool = false

## 角色当前位置（逻辑坐标）。移动动画中每一帧更新；
## 到达据点后等于据点坐标。
var troop_pos: Vector2 = Vector2(390, 440)

# ------------------------------------------------------------------ 缓存数据
## 据点ID → 据点数据 的查找表（_ready 中构建，O(1) 查询）
## 类似 Python 的 {city["id"]: city for city in CITIES}
var _city_by_id: Dictionary = {}

## 地图缩放系数（逻辑坐标 → 屏幕坐标 的乘数）
var _scale: float = 1.0

## 地图在屏幕上的偏移（用于居中显示）
var _offset: Vector2 = Vector2.ZERO

## 方向映射表：每个据点 → {up: 目标id, down: ..., left: ..., right: ...}
## 例如 _dir_map["roma"]["up"] = "venezia" 表示在罗马按 W 去威尼斯
## 空字符串 "" 表示该方向没有路（对应 UI 显示 "—"）
var _dir_map: Dictionary = {}

## 每条边的 bend 值："起点id|终点id" → bend
## 因为路线是无向边，存储双向键：A→B 用原值，B→A 用 -bend
## 用于移动动画时确定弧线方向
var _edge_bend: Dictionary = {}


# ============================================================
#  _ready() — 初始化
# ============================================================
## ---------------------------------------------------------------------------
## _ready() 做四件事：
##   1. 构建 _city_by_id 查找表
##   2. 构建 _edge_bend 双向弯曲表
##   3. 构建 _dir_map 方向映射（核心算法，见下方详解）
##   4. 计算缩放/偏移，把角色放到当前据点
## ---------------------------------------------------------------------------
func _ready() -> void:
	# --- 1. 据点查找表 ---
	for c in CITIES:
		_city_by_id[c.id] = c

	# --- 2. 边的 bend 双向表 ---
	for r in ROUTES:
		var a: String = r[0]; var b: String = r[1]; var bend_val: int = int(r[2])
		_edge_bend[a + "|" + b] = bend_val
		_edge_bend[b + "|" + a] = -bend_val  # 反向 = 镜像弯曲

	# --- 3. 方向映射构建 ---
	# 目标：为每个据点找出 4 个方向键（W/S/A/D）分别对应哪个相邻据点。
	#
	# 算法思路（类似"邻居分配问题"）：
	#   第一步：收集该据点的所有邻居（相邻据点id + bend值）
	#   第二步：对每个方向（up/down/left/right），在"尚未分配"的邻居中
	#           找方向最匹配的一个——用向量点积衡量方向相似度
	#   第三步：保证每个邻居只分配到一个方向键
	#
	# 为什么用点积？
	#   邻居方向向量 edge_dir 和方向键向量（如 Vector2.UP）做点积：
	#     dot > 0  表示两个方向大致一致（夹角 < 90°）
	#     dot ≈ 1  表示几乎完全同向
	#     dot < 0  表示方向相反
	#   选出 dot 最大的邻居 = "最接近正上方"的那个 → 分配给 W 键。
	for c in CITIES:
		_dir_map[c.id] = {up="", down="", left="", right=""}
		var cur_pos: Vector2 = Vector2(float(c.x), float(c.y))
		var dirs: Array = ["up", "down", "left", "right"]
		var dir_vecs: Dictionary = {"up":Vector2.UP, "down":Vector2.DOWN, "left":Vector2.LEFT, "right":Vector2.RIGHT}

		# 收集所有邻居
		var neighbors: Array = []
		for r in ROUTES:
			if r[0] == c.id:
				neighbors.append({id=r[1], bend=int(r[2])})
			elif r[1] == c.id:
				neighbors.append({id=r[0], bend=-int(r[2])})

		# 对每个方向键，从未分配的邻居中选最匹配的
		var assigned: Array = []  # 已分配的邻居id列表
		for dk in dirs:
			var best_id: String = ""
			var best_dot: float = -2.0  # 初始低于所有可能点积（dot 范围 [-1, 1]）
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
		# 注意：本数据集中每个据点最多 4 个邻居（venezia 恰好 4 个），
		# 所以一次分配足够；若未来据点超过 4 个邻居，需要第二轮分配。
		# （当前代码未实现第二轮，但数据保证不会触发。）

	# --- 4. 初始化角色位置和视图变换 ---
	var c: Dictionary = _city_by_id[current_city_id]
	troop_pos = Vector2(float(c.x), float(c.y))

	# 计算缩放：窗口尺寸 / 地图尺寸，取较小值保证地图完整可见，
	# 乘 0.92 留一点边距。
	var vp: Vector2 = get_viewport_rect().size
	_scale = min(vp.x / MAP_W, vp.y / MAP_H) * 0.92
	# 计算偏移：把缩放后的地图居中（窗口与地图的差值的一半）
	_offset = (vp - Vector2(MAP_W, MAP_H) * _scale) / 2.0


# ============================================================
#  绘制 (Drawing)
# ============================================================
## _draw() 是主绘制函数。Godot 在每帧或 queue_redraw() 后调用。
## 绘制顺序 = 图层顺序：先画的在底层，后画的覆盖在上面。
## 层级：海洋 → 陆地 → 装饰 → 路线 → 据点 → 角色 → HUD
func _draw() -> void:
	_draw_sea()
	_draw_landmass()
	_draw_decorations()
	_draw_routes()
	_draw_cities()
	_draw_troop()
	_draw_hud()


## 坐标转换：逻辑坐标 → 屏幕坐标
## 公式：screen = logical × scale + offset
## 类似地图的缩放+平移变换（Python: np.array * scale + offset）
func _to_screen(x: float, y: float) -> Vector2:
	return Vector2(x, y) * _scale + _offset


## 绘制海洋背景：整个地图区域填海蓝色
## draw_rect(Rect2(位置, 尺寸), 颜色) — 绘制填充矩形
## Rect2 类似 Python 的 (x, y, w, h) 元组结构
func _draw_sea() -> void:
	draw_rect(Rect2(_offset, Vector2(MAP_W, MAP_H) * _scale), Color("#44687b"))


## ---------------------------------------------------------------------------
## 绘制大陆块：用多边形描出地中海沿岸陆地轮廓
## ---------------------------------------------------------------------------
## 实现方式：
##   1. 硬编码一串逻辑坐标点（手工调整的轮廓）
##   2. 逐个转换为屏幕坐标
##   3. draw_colored_polygon 填充多边形（沙土色）
##   4. draw_polyline 描边（棕色），closed=true 表示首尾相连
##
## PackedVector2Array 是 GDScript 的紧凑 Vector2 数组
## （类似 Python 的 numpy array，比普通 Array 更省内存）。
## ============================================================
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

	# --- 小岛：圆形 + 描边 ---
	# 数据格式：[x, y, 半径]（逻辑坐标）
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
		# draw_arc 画圆弧：360度（TAU）就是整圆轮廓，24 段近似
		draw_arc(center, r, 0, TAU, 24, Color("#7a5a32"), max(1.0, 1.5 * _scale), true)


## ---------------------------------------------------------------------------
## 绘制装饰：左下角的简易罗盘
## ---------------------------------------------------------------------------
## 结构：外圆 → 内圆（空心）→ N/S/W/E 四个字母
##
## draw_circle 参数：
##   (圆心, 半径, 颜色, filled, 线宽, antialiased)
##   filled=true 填充，filled=false 且线宽=-1 表示只画空心圆
## draw_string 参数：
##   (字体, 位置, 文字, 对齐方式, 宽度限制, 字号, 颜色)
## ---------------------------------------------------------------------------
func _draw_decorations() -> void:
	var comp_center: Vector2 = _to_screen(160, 700)
	var comp_r: float = 55.0 * _scale
	draw_circle(comp_center, comp_r, Color("#f0e0b8"))
	draw_arc(comp_center, comp_r, 0, TAU, 32, Color("#7a5a32"), max(1.0, 1.4 * _scale), true)
	draw_circle(comp_center, comp_r - 8.0 * _scale, Color("#f0e0b8"), false, -1, false)
	var font := get_theme_default_font()
	var small_fs: int = max(8, int(10 * _scale))
	draw_string(font, comp_center + Vector2(0, -comp_r - 4), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(0, comp_r + 12), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(-comp_r - 12, 4), "W", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))
	draw_string(font, comp_center + Vector2(comp_r + 10, 4), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, small_fs, Color("#5a3a1a"))


# ============================================================
#  路线绘制 — 带弧线的虚线 (Dashed Bezier Routes)
# ============================================================
## 遍历所有路线，每条画一条虚线弧线。
func _draw_routes() -> void:
	for route in ROUTES:
		var a: Dictionary = _city_by_id[route[0]]
		var b: Dictionary = _city_by_id[route[1]]
		var bend: float = float(route[2]) * _scale
		var from: Vector2 = _to_screen(float(a.x), float(a.y))
		var to: Vector2 = _to_screen(float(b.x), float(b.y))
		_draw_dashed_bezier(from, to, bend)


## ---------------------------------------------------------------------------
## _draw_dashed_bezier() — 沿二次贝塞尔曲线画虚线
## ---------------------------------------------------------------------------
## 核心思路：
##   1. 计算控制点：中点 + 垂直方向偏移 bend 像素
##      （垂直于线段的方向 = (-dy, dx) 归一化；这就是"弧线弯曲"）
##   2. 沿曲线采样很多小线段（sample_count 个采样点）
##   3. 边走边累计长度，交替"画"与"不画"形成虚线：
##      accum < dash_len 时画，然后进入 gap（间隔）状态
##      accum < gap_len 时不画，然后重新开始画
##      切换瞬间用 lerp 插值精确切出线段终点，避免虚线长短不齐
##
## 类比 Python：
##   类似 matplotlib 中沿参数曲线画 dashed linestyle 的实现思路。
## ============================================================
func _draw_dashed_bezier(from: Vector2, to: Vector2, bend: float) -> void:
	# --- 计算贝塞尔控制点 ---
	var mid: Vector2 = (from + to) / 2.0
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	var length: float = max(1.0, sqrt(dx * dx + dy * dy))
	var perp: Vector2 = Vector2(-dy / length, dx / length)  # 单位垂直向量
	var control: Vector2 = Vector2(mid.x + perp.x * bend, mid.y + perp.y * bend)

	# --- 虚线参数 ---
	var dash_len: float = 9.0 * _scale   # 实线段长度
	var gap_len: float = 7.0 * _scale    # 空白段长度
	var route_color: Color = Color("#7a3b22")
	var route_width: float = max(1.0, 2.0 * _scale)

	# --- 沿曲线采样并分段绘制 ---
	var sample_count: int = max(20, int(length / 2.0))  # 采样密度与曲线长度成正比
	var prev_point: Vector2 = from
	var accum: float = 0.0        # 当前段已累计的长度
	var drawing: bool = true      # 当前处于"实线"还是"空白"状态

	for i in range(1, sample_count + 1):
		var t: float = float(i) / sample_count
		var point: Vector2 = _bezier_point(from, control, to, t)
		var seg_len: float = prev_point.distance_to(point)
		accum += seg_len

		if drawing:
			# 实线状态：累计长度达到 dash_len 就切出线段并转入空白
			if accum >= dash_len:
				var frac: float = 1.0 - (accum - dash_len) / seg_len
				draw_line(prev_point, prev_point.lerp(point, frac), route_color, route_width)
				accum -= dash_len
				drawing = false
			else:
				# 还没到虚线长度，整段都画
				draw_line(prev_point, point, route_color, route_width)
		else:
			# 空白状态：累计长度达到 gap_len 就切出起点并转回实线
			if accum >= gap_len:
				var frac: float = 1.0 - (accum - gap_len) / seg_len
				var restart: Vector2 = prev_point.lerp(point, frac)
				prev_point = restart
				accum -= gap_len
				drawing = true
			else:
				pass  # 还在空白段内，不画

		# 更新画笔位置
		if drawing:
			prev_point = point
		else:
			prev_point = point
			accum = min(accum, gap_len)


## ---------------------------------------------------------------------------
## _bezier_point() — 二次贝塞尔曲线求值
## ---------------------------------------------------------------------------
## 公式：B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
##   P0 = 起点, P1 = 控制点, P2 = 终点, t ∈ [0, 1]
## 这是数学中的标准二次贝塞尔公式（同 CSS/SVG 的 quadratic bezier）。
## ============================================================
func _bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var mt: float = 1.0 - t
	return p0 * mt * mt + p1 * 2.0 * mt * t + p2 * t * t


# ============================================================
#  据点绘制 (Cities)
# ============================================================
## ---------------------------------------------------------------------------
## 每个据点画三层：
##   1. 外圈（象牙白圆环，半径 10）
##   2. 内部彩色圆点（按据点类型着色，半径 5）
##   3. 名称两行（中文名 + 拉丁名）
## 当前所在据点额外画金色光环 + 名称变橙色。
##
## draw_circle / draw_arc 配合画"圆环"：先画填充圆，再画同圆心的
## 圆弧描边（线宽 > 0）。antialiased=true 开启抗锯齿。
## ============================================================
func _draw_cities() -> void:
	var font := get_theme_default_font()
	for c in CITIES:
		var pos: Vector2 = _to_screen(float(c.x), float(c.y))
		var is_current: bool = (c.id == current_city_id)

		# 按类型选圆点颜色
		var dot_color: Color
		match c.type:
			"holy":  dot_color = Color("#c9a227")
			"great": dot_color = Color("#8a3a2a")
			"port":  dot_color = Color("#3f6f88")
			_:       dot_color = Color("#4a5a3a")

		# 当前据点的金色光环
		var ring_r: float = 10.0 * _scale
		if is_current:
			draw_circle(pos, ring_r + 3.0 * _scale, Color.GOLDENROD, true, -1, true)

		draw_circle(pos, ring_r, Color("#f4e6c0"))
		draw_arc(pos, ring_r, 0, TAU, 24, Color("#3a2412"), 1.6 * _scale, true)
		draw_circle(pos, 5.0 * _scale, dot_color)
		draw_arc(pos, 5.0 * _scale, 0, TAU, 16, Color("#2c1c0e"), 1.0 * _scale, true)

		# 名称：当前据点橙色高亮
		var name_color := Color("#c2410c") if is_current else Color("#3a2410")
		var name_fs: int = max(10, int(13 * _scale))
		draw_string(font, pos + Vector2(0, 18 * _scale), c.cn, HORIZONTAL_ALIGNMENT_CENTER, -1, name_fs, name_color)
		var sub_fs: int = max(8, int(9 * _scale))
		draw_string(font, pos + Vector2(0, 31 * _scale), c.lat, HORIZONTAL_ALIGNMENT_CENTER, -1, sub_fs, Color("#6a4f33"))


# ============================================================
#  角色绘制 (Troop)
# ============================================================
## 角色标记：半透明光晕 + 红色圆盘 + 金色核心 + ⚔ 图标
func _draw_troop() -> void:
	var pos: Vector2 = _to_screen(troop_pos.x, troop_pos.y)
	# 外层光晕（半透明橙色，alpha=0.3）
	draw_circle(pos, 15.0 * _scale, Color(0.76, 0.25, 0.05, 0.3))
	# 主体圆盘（红色）
	draw_circle(pos, 12.0 * _scale, Color("#c2410c"))
	draw_arc(pos, 12.0 * _scale, 0, TAU, 16, Color("#2c1c0e"), 2.0 * _scale, true)
	# 核心（金色）
	draw_circle(pos, 6.0 * _scale, Color("#e8c34d"))
	draw_arc(pos, 6.0 * _scale, 0, TAU, 12, Color("#2c1c0e"), 1.5 * _scale, true)
	# ⚔ 剑图标（emoji 直接当文字画）
	var icon_fs: int = max(10, int(12 * _scale))
	draw_string(get_theme_default_font(), pos + Vector2(0, 4), "⚔",
		HORIZONTAL_ALIGNMENT_CENTER, -1, icon_fs, Color("#2c1c0e"))


# ============================================================
#  HUD (Heads-Up Display)
# ============================================================
## 三个信息区：
##   左上 — 当前据点名
##   右上 — 方向指南（W/S/A/D 各通向哪里，无路显示 —）
##   左下 — 操作提示
##   底部中央 — 移动中提示
func _draw_hud() -> void:
	var font := get_theme_default_font()
	var c: Dictionary = _city_by_id[current_city_id]
	var vp: Vector2 = get_viewport_rect().size

	# 左上：当前据点
	var info := "📍 %s (%s)" % [c.cn, c.lat]
	draw_string(font, Vector2(12, 24), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e8d4a0"))

	# 右上：方向指南
	# 从 _dir_map 读取当前据点的四方向映射
	# 有路的方向显示"键位 目标城市"，无路显示"键位 —"（灰色）
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
		# .ends_with("—") 判断无路 → 灰色；有路 → 米色
		var color := Color("#8a7a5c") if guide_lines[i].ends_with("—") else Color("#e8d4a0")
		draw_string(font, Vector2(guide_x, 24 + i * 16), guide_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)

	# 左下：操作提示
	draw_string(font, Vector2(12, vp.y - 16),
		"WASD/方向键 沿虚线路线移动",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8a7a5c"))

	# 底部中央：移动中提示（只在 is_moving 时显示）
	if is_moving:
		draw_string(font, Vector2(vp.x / 2 - 60, vp.y - 16),
			"行进中...", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color("#e8c34d"))


# ============================================================
#  输入处理 & 移动动画 (Input & Movement Animation)
# ============================================================
## ---------------------------------------------------------------------------
## 曲线动画状态 (Curve Animation State)
## ---------------------------------------------------------------------------
## 移动动画的参数：
##   _curve_from     — 动画起点（当前据点坐标）
##   _curve_ctrl     — 贝塞尔控制点（bend 决定弧线方向）
##   _curve_to       — 动画终点（目标据点坐标）
##   _curve_progress — 动画进度 t ∈ [0, 1]（每帧累加）
##   _curve_duration — 动画总时长（秒），按直线距离动态计算
##
## 动画与路线绘制的弧线使用完全相同的控制点计算方式，
## 所以角色会精确地沿着画出来的虚线移动。
## ---------------------------------------------------------------------------
var _curve_from: Vector2 = Vector2.ZERO
var _curve_ctrl: Vector2 = Vector2.ZERO
var _curve_to: Vector2 = Vector2.ZERO
var _curve_progress: float = 0.0
var _curve_duration: float = 0.0


## ---------------------------------------------------------------------------
## _input() — 键盘输入处理
## ---------------------------------------------------------------------------
## _input() 是 Godot 的全局输入回调：任何输入事件（键盘/鼠标）都会触发。
## 与 _gui_input()（仅控件区域内的鼠标）不同，_input 接收所有事件。
##
## 逻辑：
##   1. 移动中或非按下事件 → 直接忽略
##   2. 识别方向键（WASD 或方向键，两者都支持）
##   3. 查 _dir_map：该方向是否有路？
##   4. 有路 → 开始移动到目标据点的曲线动画
##
## event.is_action_pressed("move_w") 说明：
##   输入动作（Input Action）在 project.godot 的 [input] 段定义。
##   move_w 绑定 W 键，move_s/a/d 同理。
##   ui_up/ui_down/ui_left/ui_right 是 Godot 内置的方向键动作。
##   用动作名而不是硬编码键位，便于日后改键。
## ============================================================
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

	# 查方向映射表：该方向无路则忽略
	var target_id: String = _dir_map.get(current_city_id, {}).get(dir_key, "")
	if target_id == "":
		return
	var target: Dictionary = _city_by_id[target_id]
	_animate_along_route(target)


## ---------------------------------------------------------------------------
## _animate_along_route() — 启动移动动画
## ---------------------------------------------------------------------------
## 设置动画的起点/终点/控制点/时长，并把 is_moving 置 true。
## 实际的逐帧位置更新在 _process() 中完成。
## ---------------------------------------------------------------------------
func _animate_along_route(target: Dictionary) -> void:
	is_moving = true
	var cur_city: Dictionary = _city_by_id[current_city_id]
	_curve_from = Vector2(float(cur_city.x), float(cur_city.y))
	_curve_to = Vector2(float(target.x), float(target.y))

	# 查这条边的 bend 值（当前行进方向）
	# 例如 roma→venezia 用 -30，反方向 venezia→roma 用 +30（镜像）
	var edge_key: String = current_city_id + "|" + target.id
	var bend: float = float(_edge_bend.get(edge_key, 0))

	# 计算贝塞尔控制点（与 _draw_dashed_bezier 相同的公式）
	var mid: Vector2 = (_curve_from + _curve_to) / 2.0
	var dx: float = _curve_to.x - _curve_from.x
	var dy: float = _curve_to.y - _curve_from.y
	var length: float = max(1.0, sqrt(dx * dx + dy * dy))
	var perp: Vector2 = Vector2(-dy / length, dx / length)
	_curve_ctrl = Vector2(mid.x + perp.x * bend, mid.y + perp.y * bend)

	# 动画时长：与直线距离成正比，限制在 0.25~1.5 秒
	# clamp(x, min, max) 把数值限制在范围内（Python 中需手写）
	var dist: float = _curve_from.distance_to(_curve_to)
	_curve_duration = clamp(dist / 350.0, 0.25, 1.5)
	_curve_progress = 0.0

	troop_pos = _curve_from


## ---------------------------------------------------------------------------
## _process(delta) — 每帧更新
## ---------------------------------------------------------------------------
## _process 是 Godot 的逐帧回调，delta 是距上一帧的秒数
## （类似 Python 游戏循环中 clock.tick() 得到的时间差）。
##
## 移动中的每帧：
##   1. 进度 += delta / duration（按时间比例推进动画）
##   2. 进度 >= 1 → 动画结束：角色落在终点，更新 current_city_id
##   3. 进度 < 1  → 按贝塞尔公式计算当前位置
## 无论是否移动都 queue_redraw() 触发重绘（动画需要每帧刷新画面）。
## ============================================================
func _process(delta: float) -> void:
	if is_moving:
		_curve_progress += delta / max(0.01, _curve_duration)
		if _curve_progress >= 1.0:
			# --- 动画完成 ---
			_curve_progress = 1.0
			is_moving = false
			troop_pos = _curve_to
			# 找到离终点最近的据点，更新 current_city_id
			# （用距离 < 5 判定，防止浮点误差）
			for c in CITIES:
				var cp: Vector2 = Vector2(float(c.x), float(c.y))
				if cp.distance_to(_curve_to) < 5.0:
					current_city_id = c.id
					break
		else:
			# --- 动画进行中：贝塞尔曲线求值 ---
			var t: float = _curve_progress
			var mt: float = 1.0 - t
			troop_pos = _curve_from * mt * mt + _curve_ctrl * 2.0 * mt * t + _curve_to * t * t
	queue_redraw()
