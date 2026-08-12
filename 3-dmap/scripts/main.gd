extends Node3D
## =============================================================================
## Main — 斜45°等距3D战棋地图 Demo 主控制器
## =============================================================================
## 功能总览：
##   1. 程序化生成一张带高度差的格子地图（无需美术资源）
##   2. 斜45°正交相机，Q/E 键 90° 步进旋转视角
##   3. 一个角色：移动力(步数) + 跳跃力(跨高度差)
##   4. 点击角色 → 蓝色高亮所有可达格；点击可达格 → 角色移动
##   5. [回合结束]按钮：恢复移动力、回合数+1
##
## =============================================================================
##  核心概念1：Grid 坐标 vs 世界坐标（数据与视图分离）
## =============================================================================
## 【Grid 坐标】 (gx, gz, height)
##   逻辑层使用。gx/gz 是格子的行列索引（整数），height 是该格的地形
##   高度（0~3 层）。所有游戏规则（移动范围、跳跃判定）都在 grid
##   坐标中计算——和相机朝向完全无关。
##
## 【世界坐标】 (x, y, z)
##   3D 渲染层使用。转换公式：
##     x = (gx + 0.5) × GRID_SCALE      ← +0.5 取格子中心
##     y = height × 1.0                  ← 每层高度差 1 个世界单位
##     z = (gz + 0.5) × GRID_SCALE
##
## 为什么分离？——**视角旋转时数据不变**：
##   相机旋转只是改变"观察角度"，格子、角色、可达计算的坐标系不变。
##   所以 Q/E 旋转后，蓝色可达标记依然正确，不需要重新计算。
##   这是战棋游戏的标准架构（类似 Python 中 model 与 view 分离的 MVC）。
##
## =============================================================================
##  核心概念2：正交投影与等距视角
## =============================================================================
## Camera3D 有透视(perspective)和正交(orthographic)两种投影：
##   · 透视：近大远小（FPS/第三人称常用）
##   · 正交：无视距离，保持比例（策略/战棋/2.5D 常用）
##
## 斜45°等距视角 = 正交投影 + 固定俯角 + 45°水平偏航：
##   pitch = 45°（相机位于地图上方，从水平面 45° 高处俯瞰）
##   yaw   = 45°/135°/225°/315°（Q/E 按 90° 步进切换四个方向）
##   俯角45°让"高度差"在视觉上非常清晰：每层高度的侧面可见。
##   注意：pitch 必须为正——sin(负角) 会把相机放到地图下方！
##
## =============================================================================
##  核心概念3：BFS 可达计算（移动力+跳跃力）
## =============================================================================
## 从角色所在格出发做广度优先搜索（BFS，Breadth-First Search）：
##
##   1. 队列放入起点（步数=0）
##   2. 取出队首格子，检查它的 4 个相邻格：
##        · 在棋盘范围内
##        · 高度差 |Δh| <= 跳跃力（跳跃力决定能否跨过去）
##        · 步数+1 <= 剩余移动力（移动力决定走多远）
##   3. 满足条件且未访问过的格子入队
##   4. 队列为空时，所有访问过的格子（除起点）就是"可达格"
##
## 类比 Python：
##   标准 collections.deque 实现的 BFS 泛洪填充。
##   类似图像处理中的 flood fill 算法。
## =============================================================================

# ------------------------------------------------------------------ 常量
## 棋盘尺寸（16×16 格）
const GRID_W := 16
const GRID_D := 16
## 每个格子的世界尺寸（格间距）
const GRID_SCALE := 2.0
## 每层高度的世界单位
const HEIGHT_STEP := 1.0
## 相机俯角（度）——相机相对水平面的仰角
## 正值 = 相机在地图上方。俯角 45° 即"斜45°俯瞰"视角。
const CAM_PITCH := 45.0
## 相机与棋盘中心的距离
const CAM_DISTANCE := 34.0

## 高度图：16×16 的整数矩阵，每个值是 0~4 的层数
## 地形设计：基底为 2 层高原，散布 4 层山峰（西北山脊、东南双峰、
## 东北孤峰）与 0~1 层洼地（北部低谷、中部小坑），叠加随机陡坎
## （高度差 2+ 的"悬崖"，跳跃力不足的单位无法跨越）。
## 高低参差使得不同跳跃力的角色可达范围显著不同。
const HEIGHTMAP: Array = [
	[0, 2, 4, 2, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 1, 2],
	[2, 0, 2, 2, 2, 2, 2, 1, 1, 0, 1, 1, 4, 1, 1, 1],
	[2, 2, 2, 3, 3, 3, 3, 1, 0, 1, 0, 1, 2, 2, 1, 2],
	[2, 2, 3, 3, 3, 3, 2, 1, 1, 0, 1, 1, 1, 2, 2, 2],
	[2, 2, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 2, 2, 2, 2],
	[1, 2, 3, 4, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	[2, 4, 2, 3, 3, 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	[4, 2, 2, 2, 2, 2, 2, 2, 2, 4, 2, 2, 2, 2, 2, 2],
	[2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 2, 2, 1, 2, 2],
	[1, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2],
	[2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 0, 2],
	[2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 2, 2],
	[2, 3, 3, 3, 2, 2, 2, 2, 2, 2, 3, 3, 4, 3, 3, 2],
	[2, 3, 2, 3, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 2, 2],
	[2, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 4, 2],
	[2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
]

# ------------------------------------------------------------------ 运行时状态
## 每层高度的显示颜色（低→高：草地→丘陵→岩石→山脊→雪顶）
const HEIGHT_COLORS := [
	Color("#5a8c4a"),  # 0层：草地绿
	Color("#a8b35c"),  # 1层：浅草/丘陵绿
	Color("#8c7a62"),  # 2层：岩石灰棕
	Color("#6e6152"),  # 3层：深岩灰
	Color("#e8e4da"),  # 4层：雪顶白
]

## 格子高度查询表：Vector2i(gx, gz) → height
var _height_by_cell: Dictionary = {}

## 角色脚本预加载（preload 在编译期加载，避免依赖全局类注册）
const UnitClass = preload("res://scripts/unit.gd")

## 角色节点引用
@onready var unit = $Unit

## 相机引用
@onready var camera: Camera3D = $Camera3D

## UI 引用
@onready var turn_label: Label = $CanvasLayer/HUD/TopBar/HBox/TurnLabel
@onready var unit_info_label: Label = $CanvasLayer/HUD/TopBar/HBox/UnitInfoLabel
@onready var end_turn_btn: Button = $CanvasLayer/HUD/TopBar/HBox/EndTurnBtn
@onready var hint_label: Label = $CanvasLayer/HUD/HintLabel

# ------------------------------------------------------------------ 回合状态
var turn_num: int = 1                 # 当前回合数
var selected: bool = false            # 是否选中了角色
var reachable_cells: Array = []       # 当前可达格列表（Vector2i 数组）

# ------------------------------------------------------------------ 高亮层
## 可达格蓝色高亮块的容器（与格子分开放，方便一键清除）
var _highlight_parent: Node3D


# ============================================================
#  _ready() — 初始化
# ============================================================
func _ready() -> void:
	# 1. 构建高度查询表
	for gz in range(GRID_D):
		for gx in range(GRID_W):
			_height_by_cell[Vector2i(gx, gz)] = HEIGHTMAP[gz][gx]

	# 2. 高亮容器
	_highlight_parent = Node3D.new()
	_highlight_parent.name = "Highlights"
	add_child(_highlight_parent)

	# 3. 建格子 + 建角色 + 相机就位
	_build_cells()
	_setup_unit()
	_setup_camera(45.0)  # 初始 yaw = 45°（经典菱形视角）

	# 4. UI 绑定
	end_turn_btn.pressed.connect(_on_end_turn)
	_refresh_hud()


# ============================================================
#  地图构建
# ============================================================
## ---------------------------------------------------------------------------
## _build_cells() — 程序化生成所有格子
## ---------------------------------------------------------------------------
## 每个格子由一个 Node3D 容器组成，包含：
##
##   【底座 BoxMesh】 颜色随高度变化；其 scale.y = 高度层数，
##     所以低层格子矮、高层格子高（类似积木堆叠）。
##
##   【StaticBody3D + BoxShape】
##     静态碰撞体——让格子可以被鼠标点击。碰撞盒覆盖整个格子体。
##     Godot 4 内建机制：鼠标点击会触发 CollisionObject3D 的
##     input_event 信号，无需手写射线检测。
##
##   【顶面高亮片】 半透明片，仅用于被选中时的蓝色标记（静态隐藏）。
##
## 3D 概念速览：
##   MeshInstance3D — 渲染网格的节点（mesh=形状, material=皮肤）
##   BoxMesh         — 内置立方体网格（可 scale 拉伸）
##   StandardMaterial3D — PBR 材质；transparency=ALPHA 开启半透明
## ---------------------------------------------------------------------------
func _build_cells() -> void:
	for gz in range(GRID_D):
		for gx in range(GRID_W):
			var h: int = _height_by_cell[Vector2i(gx, gz)]
			var cell_pos := Vector3((gx + 0.5) * GRID_SCALE, 0, (gz + 0.5) * GRID_SCALE)

			# --- 容器 ---
			var cell := Node3D.new()
			cell.name = "Cell_%d_%d" % [gx, gz]
			cell.position = cell_pos  # 【关键】把容器摆到格子所在位置！
			add_child(cell)

			# --- 底座方块 ---
			var box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(GRID_SCALE, 1.0, GRID_SCALE)  # 单位立方
			box.mesh = box_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = HEIGHT_COLORS[h]
			mat.roughness = 0.9
			box.material_override = mat
			# 关键：scale.y = 高度层数 → 每层 1 单位高；y 偏移让方块底端贴地
			box.scale = Vector3(1, h, 1)
			box.position = Vector3(0, float(h) / 2.0, 0)
			cell.add_child(box)

			# --- 碰撞体（鼠标拾取） ---
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(GRID_SCALE, max(1.0, float(h)), GRID_SCALE)
			shape.shape = box_shape
			shape.position = Vector3(0, float(h) / 2.0, 0)
			body.add_child(shape)
			# 格子坐标存入 metadata（点击时取回）
			body.set_meta("grid", Vector2i(gx, gz))
			body.set_meta("height", h)
			# 连接鼠标事件信号
			body.input_event.connect(_on_cell_clicked.bind(body))
			cell.add_child(body)


## ---------------------------------------------------------------------------
## _on_cell_clicked() — 格子鼠标点击回调
## ---------------------------------------------------------------------------
## Godot 在鼠标点击碰撞体时自动触发（每格都连接了此信号）。
##
## 参数：
##   _camera — 触发事件的相机（本 Demo 只有一台，忽略）
##   event   — 输入事件（用于判断左键按下）
##   _pos    — 点击的世界坐标位置
##   _normal — 点击面的法线
##   _idx    — 形状索引
##   body    — 被点击的 StaticBody3D（bind 参数传入）
##
## 交互逻辑：
##   1. 点击角色所在格 → 选中角色，计算可达格（蓝色高亮）
##   2. 已选中时点击可达格 → 移动角色
##   3. 点击其他位置 → 取消选中
## ---------------------------------------------------------------------------
func _on_cell_clicked(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, body: StaticBody3D) -> void:
	# 只响应左键按下（event is InputEventMouseButton 判断事件类型）
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	_handle_grid_click(body.get_meta("grid"), body.get_meta("height"))


## ---------------------------------------------------------------------------
## _handle_grid_click() — 统一的格子点击逻辑
## ---------------------------------------------------------------------------
## 从两处调用：格子碰撞体点击（_on_cell_clicked）和角色点击（_on_unit_clicked，
## 点击角色=点击其脚下格子）。把"点击含义"集中在一个函数里：
##   1. 未选中时点击角色所在格 → 选中 + 显示可达格
##   2. 已选中时点击可达格 → 移动
##   3. 其他情况 → 取消选中
## ---------------------------------------------------------------------------
func _handle_grid_click(grid: Vector2i, h: int) -> void:
	if not selected:
		# --- 未选中：点击角色所在格才选中 ---
		if grid == unit.cell_pos:
			if unit.move_left <= 0:
				# 移动力耗尽：给出明确提示（而不是静默无反应）
				hint_label.text = "⚠ 移动力已耗尽 — 点击右上角【回合结束】恢复移动力"
				hint_label.add_theme_color_override("font_color", Color("#e8c34d"))
				_refresh_hud()
				return
			selected = true
			_show_reachable()
	else:
		# --- 已选中 ---
		if grid == unit.cell_pos:
			# 再点自己 = 取消选中
			_deselect()
		elif grid in reachable_cells:
			# 点击可达格 → 移动
			_move_unit_to(grid, h)
		else:
			# 点击不可达格 → 取消选中
			_deselect()

	_refresh_hud()


# ============================================================
#  可达格计算（BFS）
# ============================================================
## ---------------------------------------------------------------------------
## _compute_reachable() — BFS 计算可达格
## ---------------------------------------------------------------------------
## 返回：可达格坐标数组（不含起点）。
##
## 两个属性的作用在这里体现：
##   · 移动力（move_left）：BFS 的深度上限——决定"最多走几步"
##   · 跳跃力（jump_power）：边的合法判定——|Δh| > jump 的相邻格不可跨
##
## BFS 数据结构：
##   queue — 待扩展的格子（Array 当队列用，pop_front/push_back）
##   dist  — 每个格的最短步数（Dictionary: Vector2i → int）
##   四个方向 = 上下左右 4 邻接（战棋无对角线移动）
## ---------------------------------------------------------------------------
func _compute_reachable() -> Array:
	var start: Vector2i = unit.cell_pos
	var result: Array = []
	var queue: Array = [start]          # BFS 队列（FIFO）
	var dist: Dictionary = {start: 0}   # 已访问格 → 步数

	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		var d: int = dist[cur]
		if d >= unit.move_left:
			continue  # 步数用尽，不再扩展（移动力上限）

		# 四个方向邻接
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + dir
			# 边界检查
			if nb.x < 0 or nb.x >= GRID_W or nb.y < 0 or nb.y >= GRID_D:
				continue
			if dist.has(nb):
				continue  # 已访问
			# 【跳跃力判定】高度差绝对值必须 <= jump_power
			var dh: int = abs(_height_by_cell[nb] - _height_by_cell[cur])
			if dh > unit.jump_power:
				continue  # 跳不上去/跳不下来
			dist[nb] = d + 1
			queue.push_back(nb)
			result.append(nb)

	return result


## ---------------------------------------------------------------------------
## _show_reachable() — 蓝色高亮可达格
## ---------------------------------------------------------------------------
## 为每个可达格创建一个半透明蓝色方块，浮在格子顶面之上。
## 蓝色 = 传统的"可移动范围"标记色（战棋通用约定）。
##
## 透明材质要点：
##   transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  开启 alpha 混合
##   albedo_color 的 alpha 通道 = 0.35 控制半透明程度
## ---------------------------------------------------------------------------
func _show_reachable() -> void:
	_clear_highlights()
	reachable_cells = _compute_reachable()

	for cell in reachable_cells:
		var h: int = _height_by_cell[cell]
		var hl := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(GRID_SCALE * 0.9, 0.08, GRID_SCALE * 0.9)
		hl.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.55, 1.0, 0.35)  # 半透明蓝
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # 不受光照，纯色醒目
		hl.material_override = mat
		# 位置：格子中心上方，y = 格子顶面 + 0.06
		hl.position = Vector3(
			(cell.x + 0.5) * GRID_SCALE,
			float(h) + 0.06,
			(cell.y + 0.5) * GRID_SCALE
		)
		_highlight_parent.add_child(hl)


## 清除所有高亮块
func _clear_highlights() -> void:
	for child in _highlight_parent.get_children():
		child.queue_free()
	reachable_cells.clear()


## 取消选中
func _deselect() -> void:
	selected = false
	_clear_highlights()


# ============================================================
#  移动
# ============================================================
## ---------------------------------------------------------------------------
## _move_unit_to() — 角色移动到目标格
## ---------------------------------------------------------------------------
## 1. 扣移动力（BFS 保证目标可达，dist 即消耗步数——这里简化为扣 1，
##    因为 demo 每次移动一格；实际上应当扣路径长度，但 BFS 只记了可达性。
##    为演示清晰，每走一格扣 1。）
## 2. 播放移动动画
## 3. 清高亮并取消选中
## ---------------------------------------------------------------------------
func _move_unit_to(cell: Vector2i, h: int) -> void:
	unit.move_left -= 1          # 消耗 1 点移动力
	unit.move_to(cell, h)        # 动画移动
	_deselect()                  # 移动后取消选中、清高亮


# ============================================================
#  角色 & 相机
# ============================================================
func _setup_unit() -> void:
	# 起始格：西南平原 (8, 12)，高度 0（靠近东南小山，方便测试爬坡）
	var start_cell := Vector2i(8, 12)
	unit.set_grid_scale(GRID_SCALE)
	unit.move_left = unit.move_power
	unit.place_at(start_cell, _height_by_cell[start_cell])

	# 【关键】关闭角色的射线拾取：input_ray_pickable = false 让鼠标射线
	# 直接穿过胶囊体命中脚下的格子。否则点击角色本体时射线被胶囊挡住，
	# 格子收不到点击 → 表现为"点角色没反应"。
	unit.input_ray_pickable = false


## ---------------------------------------------------------------------------
## _setup_camera() / _rotate_camera() — 等距相机与视角旋转
## ---------------------------------------------------------------------------
## 相机采用正交投影 + 固定俯角 + 绕棋盘中心公转：
##   yaw   — 水平朝向（Q/E 每 90° 一步）
##   pitch — 固定 -45°（斜45°俯瞰）
##
## 旋转实现：每次旋转 90°，把相机放到中心点的四个对角方向之一。
## 相机始终 look_at 棋盘中心。
##
## 坐标系说明（Godot 3D 约定）：
##   +X 右，+Y 上，+Z 后（右手系）
##   yaw 角度用三角函数求水平偏移：x = cos(yaw), z = sin(yaw)
## ---------------------------------------------------------------------------
func _setup_camera(yaw_deg: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 38.0  # 正交视野尺寸（越大看到越多，覆盖 16×16 地图对角线+高度投影）
	_render_yaw = yaw_deg
	_rotate_camera(yaw_deg)


func _rotate_camera(yaw_deg: float) -> void:
	# 目标角度标准化到 [0, 360)
	_camera_yaw = fposmod(yaw_deg, 360.0)

	# 用 Tween 平滑旋转：从当前渲染角度补间到目标角度
	# 这样旋转是肉眼可见的"水平环绕"动画，而不是瞬间跳变
	var from_yaw := _render_yaw
	var to_yaw := _camera_yaw
	# 短路径环绕：如 315°→45° 应走 +90° 而不是 -270°
	if abs(to_yaw - from_yaw) > 180.0:
		if to_yaw > from_yaw:
			from_yaw += 360.0
		else:
			to_yaw += 360.0

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# tween_method：每帧调用 _set_camera_yaw，参数从 from_yaw 平滑过渡到 to_yaw
	tween.tween_method(_set_camera_yaw, from_yaw, to_yaw, 0.4)


## ---------------------------------------------------------------------------
## _set_camera_yaw() — 按给定水平角定位相机（由旋转 Tween 每帧调用）
## ---------------------------------------------------------------------------
## 这是"水平旋转"的核心：只改变 yaw（绕 Y 轴的公转角），
## pitch（俯角）和距离恒定——相机始终在地图上方同一高度
## 环绕棋盘中心公转，从不会上下翻转或倾斜。
## ---------------------------------------------------------------------------
func _set_camera_yaw(yaw_deg: float) -> void:
	_render_yaw = fposmod(yaw_deg, 360.0)
	# 棋盘中心点（世界坐标）
	var center := Vector3(GRID_W * GRID_SCALE / 2.0, 0, GRID_D * GRID_SCALE / 2.0)
	# 角度转弧度：deg_to_rad（Python: math.radians）
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(CAM_PITCH)
	# 球面坐标 → 笛卡尔坐标：水平方向 (cos, sin)，高度由 pitch 决定
	var offset := Vector3(
		cos(yaw) * cos(pitch),
		sin(pitch),                 # 负 pitch → y 为负 → 相机在上方
		sin(yaw) * cos(pitch)
	) * CAM_DISTANCE
	camera.position = center + offset
	# 让相机始终看向棋盘中心
	camera.look_at(center)


## _unhandled_input — 键盘旋转
## Q = 逆时针（yaw - 90°），E = 顺时针（yaw + 90°）
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_left"):
		_rotate_camera(_camera_yaw - 90.0)
		get_viewport().set_input_as_handled()  # 阻止事件继续传播（避免UI抢焦点）
	elif event.is_action_pressed("rotate_right"):
		_rotate_camera(_camera_yaw + 90.0)
		get_viewport().set_input_as_handled()


## 目标 yaw（度）——初始 45°，Q/E 每次 ±90°
var _camera_yaw: float = 45.0
## 实际渲染的 yaw（Tween 动画的当前值）
var _render_yaw: float = 45.0


# ============================================================
#  回合流程 & UI
# ============================================================
## ---------------------------------------------------------------------------
## _on_end_turn() — [回合结束]按钮
## ---------------------------------------------------------------------------
## 恢复移动力、取消选中、清高亮、回合数+1。
## 真实战棋中这里还会切换到敌方 AI 回合——本 Demo 只演示单人回合循环。
## ---------------------------------------------------------------------------
func _on_end_turn() -> void:
	turn_num += 1
	unit.move_left = unit.move_power  # 移动力恢复满
	_deselect()
	_refresh_hud()


## ---------------------------------------------------------------------------
## _refresh_hud() — 刷新界面文字
## ---------------------------------------------------------------------------
## 顶部信息栏三块：
##   回合数 | 角色属性（跳跃力/移动力/剩余移动力）| [回合结束]按钮
## 底部提示行：操作说明
## ---------------------------------------------------------------------------
func _refresh_hud() -> void:
	turn_label.text = "第 %d 回合" % turn_num
	unit_info_label.text = "⚔ 骑士  跳跃力: %d | 移动力: %d/%d%s" % [
		unit.jump_power, unit.move_left, unit.move_power,
		"  [已选中]" if selected else ""
	]
	if unit.move_left <= 0:
		hint_label.text = "⚠ 移动力已耗尽 — 点击右上角【回合结束】恢复移动力"
		hint_label.add_theme_color_override("font_color", Color("#e8c34d"))
	else:
		hint_label.text = "左键点击角色选中 · 点击蓝色格移动 · Q/E 旋转视角 · 回合结束按钮恢复移动力"
		hint_label.add_theme_color_override("font_color", Color("#8a7a5c"))
