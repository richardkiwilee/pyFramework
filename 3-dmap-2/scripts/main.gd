extends Node3D
## =============================================================================
## Main — 斜45°等距3D战棋地图【编辑器】(3-dmap 的高级版)
## =============================================================================
## 在 3-dmap 原版（程序化地图 + 角色移动 + 回合流程 + Q/E 旋转视角）基础上，
## 新增三大能力，把它升级成一个真正的地图编辑器：
##
##   【1. 建筑编辑】
##      左侧边栏预设 6 种不同体积的建筑物。左键点击选中后，光标移到地图上
##      会出现半透明"放置预览"（绿色=可放，红色=不可放并提示原因），再次
##      点击左键即在该位置放置。预览状态下按 R，建筑绕锚点格逆时针旋转 90°。
##      右键点击已放置的建筑 → 删除。
##
##   【2. 水域编辑】
##      水不是独立物体，而是"格子的一种变体"——它是地图数据里格子上的
##      一种状态（水面片只是它的可视化），水不能脱离格子独立存在。
##      · 放置（注水）：以目标格高度为"水面"，泛洪填充（flood fill / BFS）
##        所有相邻且高度 <= 水面的格子——地势更低的空间会一并填满
##        （水往低处流），直到被更高高度的格子包围。
##      · 包围检查：水必须"困得住"。若水域贴到了地图边缘，说明真实
##        世界里水会向旁边流走——注水失败（地图最高点更是如此）。
##      · 删除（排水）：右键水面只删除与被点格子【同深度】的连通水层；
##        漏斗形水域里更深的坑保留，各自以新高度继续成湖。
##
##   【3. 角色规则升级】
##      · 角色不能移动到水域格（建筑格同样不可通行）。
##      · 移动由"一步直达"改为"沿 BFS 路径逐格短跳"：每一跳的落点都
##        精确压在格子顶面——角色始终紧贴地面，绝不浮空。
##      · 地图改动会打断行进路线：若剩余路径被新水域/建筑阻断，
##        移动立即取消并把角色压回当前立足格顶面。
##
## 保留 3-dmap 的核心架构（详见原版注释）：
##   · Grid 坐标 (gx, gz, height) 与 世界坐标 (x, y, z) 分离（MVC）
##   · 正交投影 + 斜45°等距视角，Q/E 按 90° 步进旋转
##   · BFS 可达计算：移动力 = 步数上限，跳跃力 = |Δh| 上限
##
## 新增的编辑数据模型（也是"编辑器"的本体）：
##   _height_by_cell  Vector2i → 高度层数   （地形，只读）
##   _water_by_cell   Vector2i → true       （水域 = 格子变体）
##   _building_by_cell Vector2i → building_id（建筑占位反查表）
##   _buildings       id → {node, cells, preset}（建筑实例）
## =============================================================================

# ------------------------------------------------------------------ 常量
## 棋盘尺寸（16×16 格）
const GRID_W := 16
const GRID_D := 16
## 每个格子的世界尺寸（格间距）
const GRID_SCALE := 2.0
## 每层高度的世界单位
const HEIGHT_STEP := 1.0
## 相机俯角（度）——斜45°俯瞰
const CAM_PITCH := 45.0
## 相机与棋盘中心的距离
const CAM_DISTANCE := 34.0
## 正交视野尺寸：默认值 / 滚轮缩放的下限 / 上限
## （size 越小 = 拉得越近，画面越大；类似望远镜倍率的倒数）
const CAM_SIZE_DEFAULT := 38.0
const CAM_SIZE_MIN := 22.0
const CAM_SIZE_MAX := 62.0

## 四个邻接方向（战棋 4 邻接：上下左右，无对角线）
## 泛洪填充（水域）与 BFS 可达（移动）共用
const DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## "无悬停格"哨兵值（鼠标不在棋盘上时用）
const NONE_CELL := Vector2i(-9999, -9999)

## 建筑预设表：6 种不同体积的建筑物（size.x=宽 w、size.y=层高 h、size.z=深 d）
## 体积差异正是编辑器要演示的：从 1×1×1 的小屋到 1×1×4 的高塔
const BUILDING_PRESETS: Array = [
	{"icon": "🏠", "name": "小屋",   "size": Vector3i(1, 1, 1), "color": Color(0.69, 0.52, 0.31)},
	{"icon": "🏡", "name": "农舍",   "size": Vector3i(2, 1, 1), "color": Color(0.61, 0.42, 0.27)},
	{"icon": "🏰", "name": "大宅",   "size": Vector3i(2, 2, 2), "color": Color(0.64, 0.30, 0.30)},
	{"icon": "🗼", "name": "高塔",   "size": Vector3i(1, 4, 1), "color": Color(0.49, 0.50, 0.53)},
	{"icon": "🏬", "name": "仓库",   "size": Vector3i(3, 1, 2), "color": Color(0.43, 0.35, 0.25)},
	{"icon": "🧱", "name": "城墙段", "size": Vector3i(3, 2, 1), "color": Color(0.42, 0.48, 0.55)},
]

## 工具索引约定：0..5 = 建筑预设（BUILDING_PRESETS 下标），
## WATER_TOOL = 水域工具，-1 = 角色移动模式（默认）
const WATER_TOOL := 6

## 高度图：16×16 的整数矩阵，每个值是 0~4 的层数（以 3-dmap 原版为基础）
## 地形设计：基底为 2 层高原，散布 4 层山峰与 0~1 层洼地。
## 对水域编辑器而言，这张图提供三类天然演示场地：
##   · 西北盆地（行 1~4、列 7~12）：一大片 1 层洼地，内含 4 个 0 层深坑；
##     北侧边缘特意抬到 2 层把它完全包围——注水时水面 1、深坑一并填满，
##     正是"漏斗形水域"的演示点（分层排水一目了然）；
##   · 零星单格 0 层深坑：注水后是独立的小水洼；
##   · 2 层大高原与 4 层峰顶：与地图边缘连通——真实世界里水会流走，
##     注水失败（演示"包围检查"）。
## 2 层平台面积最大，是摆放各种体积建筑的主场地。
const HEIGHTMAP: Array = [
	[0, 2, 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2],
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

## 每层高度的显示颜色（低→高：草地→丘陵→岩石→山脊→雪顶）
const HEIGHT_COLORS := [
	Color("#5a8c4a"),
	Color("#a8b35c"),
	Color("#8c7a62"),
	Color("#6e6152"),
	Color("#e8e4da"),
]

## 提示文字配色
const COLOR_HINT := Color(0.54, 0.48, 0.36)  # 米灰褐：默认提示
const COLOR_WARN := Color(0.91, 0.77, 0.30)  # 金黄：警告/注意
const COLOR_OK   := Color(0.49, 0.81, 0.43)  # 绿：成功
const COLOR_ERR  := Color(0.88, 0.35, 0.31)  # 红：错误/不可放置

## 放置预览（ghost）配色：绿=可放 / 红=不可放
const GHOST_OK_COLOR     := Color(0.25, 0.85, 0.45, 0.40)
const GHOST_BAD_COLOR    := Color(0.90, 0.25, 0.20, 0.45)
const GHOST_WATER_COLOR      := Color(0.20, 0.60, 1.00, 0.50)
const GHOST_WATER_BAD_COLOR  := Color(0.90, 0.30, 0.25, 0.50)

## 角色脚本预加载（preload 在编译期加载，避免依赖全局类注册）
const UnitClass = preload("res://scripts/unit.gd")

# ------------------------------------------------------------------ 数据表（编辑器的"模型"层）
## 格子高度查询表：Vector2i(gx, gz) → height
var _height_by_cell: Dictionary = {}
## 水域表：Vector2i → true（水 = 格子的一种变体，只存在于此表与对应水面片）
var _water_by_cell: Dictionary = {}
## 建筑实例表：id → { "node": Node3D, "cells": Array, "preset": Dictionary }
var _buildings: Dictionary = {}
## 建筑占位反查表：Vector2i → building_id（O(1) 查询"这格是谁的楼"）
var _building_by_cell: Dictionary = {}
var _next_building_id: int = 0

## 地图版本号：每次放置/删除建筑或水域 +1，用于强制刷新悬停预览
## （例如右键删除脚下建筑后，预览无需移动鼠标就立即变成绿色）
var _map_version: int = 0

# ------------------------------------------------------------------ 编辑器状态
## 当前工具：-1 = 角色移动模式，0..5 = 建筑预设，WATER_TOOL = 水域
var tool_idx: int = -1
## 预览旋转次数（0..3，R 键 +1，即绕锚点格逆时针 90°）
var _ghost_rot: int = 0
var _ghost_rot_rendered: int = -1
## 当前悬停格与最近一次渲染的预览状态（用于避免每帧重建预览）
var _hover_cell: Vector2i = NONE_CELL
var _ghost_map_version: int = -1
## 最近一次预览的"不可放置原因"（空串 = 可放置）
var _ghost_reason: String = ""

## 侧边栏工具按钮（角色模式按钮 + 水域按钮；建筑按钮按预设动态创建）
var _move_btn: Button
var _water_btn: Button

# ------------------------------------------------------------------ 回合状态
var turn_num: int = 1                 # 当前回合数
var selected: bool = false            # 是否选中了角色
var reachable_cells: Array = []       # 当前可达格列表（Vector2i 数组）
## BFS 父指针表：目标格 → 父格（用于从目标反推整条移动路径）
var _reachable_parent: Dictionary = {}

## 移动动画状态：剩余路径（含当前跳跃目标）与当前跳跃 Tween
## cell_pos 只在每一跳落地后更新，跳跃途中指向"最后踩实的格子"，
## 因此移动被地图编辑打断时可以安全地把角色吸附回去。
var _move_path: Array = []
var _move_tween: Tween = null

# ------------------------------------------------------------------ 场景容器
## 高亮/建筑/水面/预览分别放在独立容器里，方便整体管理
var _highlight_parent: Node3D
var _buildings_parent: Node3D
var _water_parent: Node3D
var _ghost_parent: Node3D

# ------------------------------------------------------------------ 节点引用
## 角色节点引用
@onready var unit = $Unit
## 相机引用
@onready var camera: Camera3D = $Camera3D
## UI 引用
@onready var turn_label: Label = $CanvasLayer/HUD/TopBar/HBox/TurnLabel
@onready var unit_info_label: Label = $CanvasLayer/HUD/TopBar/HBox/UnitInfoLabel
@onready var map_info_label: Label = $CanvasLayer/HUD/TopBar/HBox/MapInfoLabel
@onready var end_turn_btn: Button = $CanvasLayer/HUD/TopBar/HBox/EndTurnBtn
@onready var hint_label: Label = $CanvasLayer/HUD/HintLabel
@onready var topbar: PanelContainer = $CanvasLayer/HUD/TopBar
@onready var sidebar: PanelContainer = $CanvasLayer/HUD/Sidebar
@onready var tool_vbox: VBoxContainer = $CanvasLayer/HUD/Sidebar/ToolVBox

## 目标 yaw（度）——初始 45°，Q/E 每次 ±90°
var _camera_yaw: float = 45.0
## 实际渲染的 yaw（Tween 动画的当前值）
var _render_yaw: float = 45.0


# ============================================================
#  _ready() — 初始化
# ============================================================
func _ready() -> void:
	# 1. 构建高度查询表
	for gz in range(GRID_D):
		for gx in range(GRID_W):
			_height_by_cell[Vector2i(gx, gz)] = HEIGHTMAP[gz][gx]

	# 2. 分层容器：建筑 / 水面 / 高亮 / 预览（与格子分开，便于一键管理）
	_buildings_parent = _make_container("Buildings")
	_water_parent = _make_container("Water")
	_highlight_parent = _make_container("Highlights")
	_ghost_parent = _make_container("GhostPreview")

	# 3. 建格子 + 建角色 + 相机就位
	_build_cells()
	_setup_unit()
	_setup_camera(45.0)  # 初始 yaw = 45°（经典菱形视角）

	# 4. 侧边栏工具按钮 & UI 绑定
	_build_sidebar()
	end_turn_btn.pressed.connect(_on_end_turn)
	_set_tool(-1)  # 默认进入角色移动模式


## 创建一个具名的空容器节点（挂在 Main 下）
func _make_container(container_name: String) -> Node3D:
	var c := Node3D.new()
	c.name = container_name
	add_child(c)
	return c


# ============================================================
#  地图构建（地形格子）
# ============================================================
## ---------------------------------------------------------------------------
## _build_cells() — 程序化生成所有格子（与 3-dmap 原版一致）
## ---------------------------------------------------------------------------
## 每个格子 = Node3D 容器：
##   【底座 BoxMesh】scale.y = 高度层数，颜色随高度变化
##   【StaticBody3D + BoxShape】静态碰撞体——鼠标点击（左键放置/移动、
##     右键删除水域）都通过它的 input_event 信号触发，无需手写射线检测。
##     metadata 存格子坐标，点击时取回。
## ---------------------------------------------------------------------------
func _build_cells() -> void:
	for gz in range(GRID_D):
		for gx in range(GRID_W):
			var h: int = _height_by_cell[Vector2i(gx, gz)]
			var cell_pos := Vector3((gx + 0.5) * GRID_SCALE, 0, (gz + 0.5) * GRID_SCALE)

			# --- 容器 ---
			var cell := Node3D.new()
			cell.name = "Cell_%d_%d" % [gx, gz]
			cell.position = cell_pos
			add_child(cell)

			# --- 底座方块 ---
			var box := MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(GRID_SCALE, 1.0, GRID_SCALE)
			box.mesh = box_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = HEIGHT_COLORS[h]
			mat.roughness = 0.9
			box.material_override = mat
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
			body.set_meta("grid", Vector2i(gx, gz))
			body.set_meta("height", h)
			body.input_event.connect(_on_cell_clicked.bind(body))
			cell.add_child(body)


## ---------------------------------------------------------------------------
## _on_cell_clicked() — 格子鼠标点击回调（左右键分派）
## ---------------------------------------------------------------------------
## Godot 在鼠标点击碰撞体时自动触发。本编辑器里：
##   左键 = 放置/移动（按当前工具分派）
##   右键 = 删除（水域→排干整片；建筑→删除该建筑）
## ---------------------------------------------------------------------------
func _on_cell_clicked(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, body: StaticBody3D) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var grid: Vector2i = body.get_meta("grid")
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click(grid)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(grid)


## 右键：删除已放置的建筑 / 删除同深度的连通水层（漏斗水域里深坑保留）
func _handle_right_click(grid: Vector2i) -> void:
	if _water_by_cell.has(grid):
		_remove_water_layer(grid)
	elif _building_by_cell.has(grid):
		_delete_building(_building_by_cell[grid])


## 左键：按当前工具分派——水域工具注水、建筑工具放置、角色模式移动
func _handle_left_click(grid: Vector2i) -> void:
	if tool_idx == WATER_TOOL:
		_try_add_water(grid)
	elif tool_idx >= 0:
		_try_place_building(grid)
	else:
		_handle_grid_click(grid, _height_by_cell[grid])


# ============================================================
#  建筑编辑
# ============================================================
## ---------------------------------------------------------------------------
## _cells_for_building() — 计算建筑占地格列表
## ---------------------------------------------------------------------------
## 未旋转时：占地 = 锚点格 + (0..w-1, 0..d-1) 的偏移。
## 每按一次 R，所有偏移绕锚点格逆时针旋转 90°：(x, z) → (-z, x)。
## 这与渲染节点绕 Y 轴的 -90° 旋转严格对应，所以预览与实际落地、
## 占位表与视觉轮廓完全一致。旋转可能让占地伸到锚点的西/北侧——
## 越界时预览会变红（不可放置）。
## ---------------------------------------------------------------------------
func _cells_for_building(anchor: Vector2i, p: Dictionary, rot: int) -> Array:
	var cells: Array = []
	for z in range(p["size"].z):
		for x in range(p["size"].x):
			var off := Vector2i(x, z)
			for _i in range(rot % 4):
				off = Vector2i(-off.y, off.x)
			cells.append(anchor + off)
	return cells


## ---------------------------------------------------------------------------
## _building_block_reason() — 建筑能否放置的判定（返回原因，空串=可以）
## ---------------------------------------------------------------------------
## 依次检查：越界 → 与已有建筑重叠 → 格子上是水域 → 角色所在格 → 高度不平。
## "高度不平"限制：建筑要坐落在等高平台上，否则会悬空/插进山体。
## ---------------------------------------------------------------------------
func _building_block_reason(cells: Array) -> String:
	var h0: int = 0
	for i in cells.size():
		var c: Vector2i = cells[i]
		if c.x < 0 or c.x >= GRID_W or c.y < 0 or c.y >= GRID_D:
			return "超出地图边界"
		if _building_by_cell.has(c):
			return "与已有建筑重叠"
		if _water_by_cell.has(c):
			return "格子上是水域"
		if c == unit.cell_pos:
			return "角色所在格不能放置"
		var h: int = _height_by_cell[c]
		if i == 0:
			h0 = h
		elif h != h0:
			return "建筑必须建在等高平台上"
	return ""


## ---------------------------------------------------------------------------
## _spawn_building_visual() — 生成建筑的视觉（主体+屋顶+门），实建与预览共用
## ---------------------------------------------------------------------------
## 建筑由三个 BoxMesh 拼成：
##   · 主体：w×h×d（网格尺度），颜色 = 预设色
##   · 屋顶：比主体略大一圈的薄片，颜色 = 主体色压暗 45%
##   · 门：贴在 +z 正面的小方块——它让 R 键旋转的方向在预览里一目了然
##
## 坐标要点：
##   · 节点原点 = 占地包围盒中心，y = 地形顶面 + 楼高/2 + y_lift
##   · 绕节点自身中心旋转 -90°×rot，与 _cells_for_building 的偏移旋转对应
##   · y_lift：实体建筑用 0.01（贴地但避免与地形顶面深度冲突），
##     预览用 0.06（悬浮感，避免与格子顶面重叠闪烁）
## ---------------------------------------------------------------------------
func _spawn_building_visual(parent: Node3D, cells: Array, p: Dictionary, rot: int, h_terrain: float, body_color: Color, y_lift := 0.01) -> Node3D:
	# 占地包围盒（grid 坐标）→ 世界坐标中心
	var min_x: int = cells[0].x
	var max_x: int = cells[0].x
	var min_z: int = cells[0].y
	var max_z: int = cells[0].y
	for c in cells:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y)
		max_z = maxi(max_z, c.y)
	var cx := (min_x + max_x + 1) / 2.0 * GRID_SCALE
	var cz := (min_z + max_z + 1) / 2.0 * GRID_SCALE
	var h: float = float(p["size"].y)

	var node := Node3D.new()
	node.position = Vector3(cx, h_terrain + h / 2.0 + y_lift, cz)
	node.rotation.y = -PI / 2.0 * float(rot % 4)

	var transparent := body_color.a < 1.0

	# --- 主体 ---
	var body := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(p["size"].x * GRID_SCALE, h, p["size"].z * GRID_SCALE)
	body.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.85
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.material_override = mat
	node.add_child(body)

	# --- 屋顶 ---
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(m.size.x * 1.06, 0.35, m.size.z * 1.06)
	roof.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = body_color.darkened(0.45)
	rmat.roughness = 0.7
	if transparent:
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	roof.material_override = rmat
	roof.position = Vector3(0, h / 2.0 + 0.175, 0)
	node.add_child(roof)

	# --- 门（+z 正面，贴底） ---
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.55, 0.85, 0.1)
	door.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = body_color.darkened(0.3)
	dmat.roughness = 0.7
	if transparent:
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	door.material_override = dmat
	door.position = Vector3(0, -h / 2.0 + 0.425, m.size.z / 2.0 + 0.05)
	node.add_child(door)

	parent.add_child(node)
	return node


## ---------------------------------------------------------------------------
## _try_place_building() — 左键尝试放置建筑（按当前预设与旋转）
## ---------------------------------------------------------------------------
func _try_place_building(grid: Vector2i) -> void:
	var p: Dictionary = BUILDING_PRESETS[tool_idx]
	var cells := _cells_for_building(grid, p, _ghost_rot)
	var reason := _building_block_reason(cells)
	_refresh_hud()
	if reason != "":
		_flash_hint("❌ " + reason, COLOR_ERR)
		return
	_place_building(cells, p, _ghost_rot)
	_validate_unit_path()   # 若新建筑阻断了角色行进路线，取消移动并贴地
	_refresh_hud()
	_flash_hint("✅ 已放置 %s（占地 %d 格）" % [p["name"], cells.size()], COLOR_OK)


## ---------------------------------------------------------------------------
## _place_building() — 真正落楼：视觉 + 碰撞体（右键删除用）+ 占位表
## ---------------------------------------------------------------------------
func _place_building(cells: Array, p: Dictionary, rot: int) -> void:
	var id := _next_building_id
	_next_building_id += 1
	var h_terrain := float(_height_by_cell[cells[0]])

	var node := _spawn_building_visual(_buildings_parent, cells, p, rot, h_terrain, p["color"])
	node.name = "Building_%d" % id

	# 碰撞体：覆盖整个楼体。作用有二：
	#   1. 接收右键点击 → 删除该建筑
	#   2. 遮挡下方格子的射线/点击（楼下的格子点不到，也不会误放置）
	var static_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(p["size"].x * GRID_SCALE, float(p["size"].y), p["size"].z * GRID_SCALE)
	shape.shape = box_shape
	static_body.add_child(shape)
	static_body.set_meta("building_id", id)
	static_body.input_event.connect(_on_building_clicked.bind(id))
	node.add_child(static_body)

	for c in cells:
		_building_by_cell[c] = id
	_buildings[id] = {"node": node, "cells": cells, "preset": p}
	_map_version += 1


## ---------------------------------------------------------------------------
## _on_building_clicked() — 建筑的鼠标回调：右键 = 删除
## ---------------------------------------------------------------------------
func _on_building_clicked(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_delete_building(id)


## 删除建筑：移除节点、清空占位表
func _delete_building(id: int) -> void:
	if not _buildings.has(id):
		return
	var b: Dictionary = _buildings[id]
	for c in b["cells"]:
		_building_by_cell.erase(c)
	b["node"].queue_free()
	_buildings.erase(id)
	_map_version += 1
	_refresh_hud()
	_flash_hint("🗑 已删除建筑", COLOR_WARN)


# ============================================================
#  水域编辑（泛洪填充）
# ============================================================
## ---------------------------------------------------------------------------
## _compute_flood() — 泛洪填充：计算注水会覆盖的格子集合
## ---------------------------------------------------------------------------
## 水的规则（BFS，与图像处理的 flood fill 同构）：
##   1. 以放置目标格的高度为"水面"；
##   2. 从目标格向 4 个邻接方向扩展：凡是高度 <= 水面的格子都并入水域
##      ——地势更低的空间会一并填满（水往低处流），直到被更高格子挡住；
##   3. 高度 > 水面的格子成为"堤坝"，包围住这片水。
## 水域能否成立由 _water_enclosure_reason 判定：贴到地图边缘 = 水会
## 向界外流走（例如地图最高点，全图都低于它，必然一路流到边缘）。
## ---------------------------------------------------------------------------
func _compute_flood(target: Vector2i) -> Array:
	var surface: int = _height_by_cell[target]
	var region: Array = []
	var queue: Array = [target]
	var seen: Dictionary = {target: true}

	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		region.append(cur)
		for dir in DIRS:
			var nb: Vector2i = cur + dir
			if nb.x < 0 or nb.x >= GRID_W or nb.y < 0 or nb.y >= GRID_D:
				continue
			if seen.has(nb):
				continue
			if _height_by_cell[nb] > surface:
				continue  # 堤坝：比水面高的格子不再蔓延
			seen[nb] = true
			queue.push_back(nb)

	return region


## ---------------------------------------------------------------------------
## _water_enclosure_reason() — 水域能否"困住水"的判定
## ---------------------------------------------------------------------------
## 泛洪填充只会被更高的格子挡住（<= 水面的邻居必然被并入水域），
## 所以唯一的漏水口是地图边缘：水域贴边 = 真实世界里水会流向界外，
## 注水失败。地图最高点之所以失败，正是因为全图都低于它、
## 水必然一路流到边缘。
## ---------------------------------------------------------------------------
func _water_enclosure_reason(region: Array) -> String:
	for c in region:
		if c.x <= 0 or c.x >= GRID_W - 1 or c.y <= 0 or c.y >= GRID_D - 1:
			return "水会从地图边缘流走，无法注水"
	return ""


## ---------------------------------------------------------------------------
## _try_add_water() — 左键注水：泛洪填满整个封闭洼地（含更低处）
## ---------------------------------------------------------------------------
func _try_add_water(grid: Vector2i) -> void:
	var surface: int = _height_by_cell[grid]
	var region := _compute_flood(grid)
	var reason := _water_enclosure_reason(region)
	if reason == "":
		for c in region:
			if _building_by_cell.has(c):
				reason = "洼地中有建筑，无法注水"
				break
	if reason == "" and region.has(unit.cell_pos):
		reason = "水域会淹没角色所在格，无法注水"
	_refresh_hud()
	if reason != "":
		_flash_hint("❌ " + reason, COLOR_ERR)
		return

	var added := 0
	for c in region:
		if _water_by_cell.has(c):
			continue  # 已在水中（水面可能抬升，之后统一重建水面片）
		_water_by_cell[c] = true
		added += 1
	_map_version += 1
	_refresh_water_slabs()
	_validate_unit_path()
	_refresh_hud()
	if added > 0:
		_flash_hint("💧 注水成功：水面高度 %d，共 %d 格" % [surface, region.size()], COLOR_OK)
	else:
		_flash_hint("这里已经是水域了", COLOR_WARN)


## ---------------------------------------------------------------------------
## _spawn_water_slab() — 生成单个格子的水面片（水的可视化）
## ---------------------------------------------------------------------------
## 水是格子的变体：水面片不是独立物体，而是该格子的"皮肤"。
## 关键：水面永远平齐该片湖的"水面高度"——地势更低的格子，水面片
## 浮得更高（视觉上水深 = 水面 - 格高），颜色随深度略微加深。
## 无碰撞体：点击穿透水面落到格子碰撞体上，由格子统一处理右键排水。
## ---------------------------------------------------------------------------
func _spawn_water_slab(c: Vector2i, surface: int) -> void:
	var h: int = _height_by_cell[c]
	var depth := surface - h
	var slab := MeshInstance3D.new()
	slab.name = "Water_%d_%d" % [c.x, c.y]
	var m := BoxMesh.new()
	m.size = Vector3(GRID_SCALE * 0.96, 0.12, GRID_SCALE * 0.96)
	slab.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.45, 0.85, 0.62).darkened(depth * 0.08)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.15, 0.35).darkened(depth * 0.08)
	slab.material_override = mat
	slab.position = Vector3((c.x + 0.5) * GRID_SCALE, float(surface) + 0.06, (c.y + 0.5) * GRID_SCALE)
	_water_parent.add_child(slab)


## ---------------------------------------------------------------------------
## _refresh_water_slabs() — 全量重建水面片
## ---------------------------------------------------------------------------
## 把所有水格按连通性分组（每片湖一组），水面高度 = 组内最高格，
## 然后统一重建水面片。放置/分层排水后调用：
##   · 保证同一片湖的水面绝对水平（深度不同的格子水面片浮在同一高度）；
##   · 分层排水后，剩下的深坑各自以新高度成湖。
## ---------------------------------------------------------------------------
func _refresh_water_slabs() -> void:
	for child in _water_parent.get_children():
		child.free()

	var visited: Dictionary = {}
	for start in _water_by_cell.keys():
		if visited.has(start):
			continue
		# BFS：收集这一片连通水域，取组内最高格为水面
		var component: Array = []
		var surface: int = -99999
		var queue: Array = [start]
		visited[start] = true
		while queue.size() > 0:
			var cur: Vector2i = queue.pop_front()
			component.append(cur)
			surface = maxi(surface, _height_by_cell[cur])
			for dir in DIRS:
				var nb: Vector2i = cur + dir
				if nb.x < 0 or nb.x >= GRID_W or nb.y < 0 or nb.y >= GRID_D:
					continue
				if visited.has(nb) or not _water_by_cell.has(nb):
					continue
				visited[nb] = true
				queue.push_back(nb)
		for c in component:
			_spawn_water_slab(c, surface)


## ---------------------------------------------------------------------------
## _remove_water_layer() — 右键排水：只删与"被点格子同深度"的整层水
## ---------------------------------------------------------------------------
## 漏斗形水域的关键规则：水按"深度"分层。右键点击水面：
##   1. 先 BFS 找到被点格子所在的整片湖（不限深度）；
##   2. 只删除湖中与被点格子【地形高度相同】的全部水格；
##   3. 更深的坑（高度更低）不受影响，排水后各自以新高度成湖
##      （由 _refresh_water_slabs 重建）。
## 例如：大片浅水（相对-1）里嵌着几格深坑（相对-2），删除浅水层后
## 深坑仍然留着一洼水，不会被连带删除。
## ---------------------------------------------------------------------------
func _remove_water_layer(target: Vector2i) -> void:
	var level: int = _height_by_cell[target]
	# 1. 整片湖（任意深度的连通水格）
	var lake: Array = []
	var queue: Array = [target]
	var seen: Dictionary = {target: true}
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		lake.append(cur)
		for dir in DIRS:
			var nb: Vector2i = cur + dir
			if nb.x < 0 or nb.x >= GRID_W or nb.y < 0 or nb.y >= GRID_D:
				continue
			if seen.has(nb) or not _water_by_cell.has(nb):
				continue
			seen[nb] = true
			queue.push_back(nb)

	# 2. 只删除同深度的水格
	var removed := 0
	for c in lake:
		if _height_by_cell[c] == level:
			_water_by_cell.erase(c)
			removed += 1
	_map_version += 1
	_refresh_water_slabs()
	_refresh_hud()
	_flash_hint("🗑 已排干该深度水域（%d 格），更深的坑保留" % removed, COLOR_WARN)


# ============================================================
#  放置预览（ghost）
# ============================================================
## ---------------------------------------------------------------------------
## _process() — 悬停格跟踪与预览刷新
## ---------------------------------------------------------------------------
## 只在选中编辑工具时工作。每一帧从相机向鼠标位置打一条射线找悬停格，
## 悬停格/旋转次数/地图版本任一变化就重建预览。
## 用 _process 而不是鼠标事件驱动的理由：Q/E 旋转相机时鼠标没动，
## 但画面下方的格子变了——逐帧射线让预览始终跟着画面走。
## ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if tool_idx < 0:
		return
	var cell := _get_hover_cell()
	if cell != _hover_cell or _ghost_rot != _ghost_rot_rendered or _map_version != _ghost_map_version:
		_hover_cell = cell
		_ghost_rot_rendered = _ghost_rot
		_ghost_map_version = _map_version
		_update_ghost(cell)


## ---------------------------------------------------------------------------
## _get_hover_cell() — 射线求鼠标下的格子（返回 NONE_CELL 表示无）
## ---------------------------------------------------------------------------
## camera.project_ray_origin/normal 把屏幕像素转成世界射线，
## intersect_ray 求最近命中点，再 floor(p / GRID_SCALE) 还原格子坐标。
## 注意两点：
##   · 排除角色本体（unit.get_rid()），否则射线会被胶囊挡住，
##     角色脚下/身后的格子无法悬停；
##   · 射线命中的可能是建筑碰撞体——这正合意，floor 出来就是楼下的格子，
##     预览自然变红（重叠）。
## ---------------------------------------------------------------------------
func _get_hover_cell() -> Vector2i:
	var mouse := get_viewport().get_mouse_position()
	# 鼠标在 UI 面板上时不算悬停（避免隔着面板预览/误放）
	if sidebar.get_global_rect().has_point(mouse) or topbar.get_global_rect().has_point(mouse):
		return NONE_CELL
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var to := from + dir * 300.0
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [unit.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return NONE_CELL
	var p: Vector3 = hit["position"]
	var gx := int(floor(p.x / GRID_SCALE))
	var gz := int(floor(p.z / GRID_SCALE))
	if gx < 0 or gx >= GRID_W or gz < 0 or gz >= GRID_D:
		return NONE_CELL
	return Vector2i(gx, gz)


## 重建预览：先清空，再按工具类型绘制
func _update_ghost(cell: Vector2i) -> void:
	_clear_ghost()
	if cell == NONE_CELL:
		_apply_ghost_reason("")
		return
	if tool_idx == WATER_TOOL:
		_update_water_ghost(cell)
	else:
		_update_building_ghost(cell)


## 建筑预览：半透明楼体 + 屋顶 + 门；绿色可放、红色不可放
func _update_building_ghost(cell: Vector2i) -> void:
	var p: Dictionary = BUILDING_PRESETS[tool_idx]
	var cells := _cells_for_building(cell, p, _ghost_rot)
	var reason := _building_block_reason(cells)
	var h_terrain := float(_height_by_cell[cell])
	var color := GHOST_OK_COLOR if reason == "" else GHOST_BAD_COLOR
	_spawn_building_visual(_ghost_parent, cells, p, _ghost_rot, h_terrain, color, 0.06)
	_apply_ghost_reason(reason)


## 水域预览：把泛洪填充会覆盖的每个格子盖上薄片（水面高度平齐），
## 蓝色 = 能困住水的封闭洼地，红色 = 会从边缘流走/被阻挡。
## ——左键前就能看到"这片湖会淹到哪里、淹多深"
func _update_water_ghost(cell: Vector2i) -> void:
	var surface: int = _height_by_cell[cell]
	var region := _compute_flood(cell)
	var invalid := false
	var reason := _water_enclosure_reason(region)
	if reason == "":
		for c in region:
			if _building_by_cell.has(c):
				invalid = true
				reason = "洼地中有建筑，无法注水"
				break
	if not invalid and region.has(unit.cell_pos):
		invalid = true
		reason = "水域会淹没角色所在格，无法注水"

	for c in region:
		if _water_by_cell.has(c):
			continue  # 已在水中，无需预览
		var slab := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(GRID_SCALE * 0.96, 0.1, GRID_SCALE * 0.96)
		slab.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GHOST_WATER_BAD_COLOR if invalid else GHOST_WATER_COLOR
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		slab.material_override = mat
		slab.position = Vector3((c.x + 0.5) * GRID_SCALE, float(surface) + 0.07, (c.y + 0.5) * GRID_SCALE)
		_ghost_parent.add_child(slab)
	_apply_ghost_reason(reason)


## 清空预览（free 立即释放，避免与下一帧的预览重叠闪烁）
func _clear_ghost() -> void:
	for child in _ghost_parent.get_children():
		child.free()


## 预览原因变化时更新底部提示：有原因 → 红字显示；无原因 → 恢复默认提示
func _apply_ghost_reason(reason: String) -> void:
	if reason == _ghost_reason:
		return
	_ghost_reason = reason
	if reason != "":
		hint_label.text = "❌ " + reason
		hint_label.add_theme_color_override("font_color", COLOR_ERR)
	else:
		_refresh_hud()


# ============================================================
#  角色：可达计算（BFS）与贴地移动
# ============================================================
## ---------------------------------------------------------------------------
## _compute_reachable() — BFS 可达计算（返回 目标格 → 父格 的父指针表）
## ---------------------------------------------------------------------------
## 与 3-dmap 原版的两点差异：
##   1. 水域格、建筑格不可通行（角色不能走到水里/楼里）；
##   2. 记录父指针——有了父指针链就能重建"起点 → 任意可达格"的完整路径，
##      供逐格短跳使用（原版只记可达性，移动时一步飞过去）。
## ---------------------------------------------------------------------------
func _compute_reachable() -> Dictionary:
	var start: Vector2i = unit.cell_pos
	var parent: Dictionary = {}
	var queue: Array = [start]
	var dist: Dictionary = {start: 0}

	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		var d: int = dist[cur]
		if d >= unit.move_left:
			continue  # 移动力用尽，不再扩展

		for dir in DIRS:
			var nb: Vector2i = cur + dir
			if nb.x < 0 or nb.x >= GRID_W or nb.y < 0 or nb.y >= GRID_D:
				continue
			if dist.has(nb):
				continue
			if _water_by_cell.has(nb) or _building_by_cell.has(nb):
				continue  # 【新规则】水域/建筑不可通行
			if abs(_height_by_cell[nb] - _height_by_cell[cur]) > unit.jump_power:
				continue  # 跳不上去/跳不下来
			dist[nb] = d + 1
			parent[nb] = cur
			queue.push_back(nb)

	return parent


## 蓝色高亮可达格（与 3-dmap 原版一致）
func _show_reachable() -> void:
	_clear_highlights()
	_reachable_parent = _compute_reachable()
	reachable_cells = _reachable_parent.keys()

	for cell in reachable_cells:
		var h: int = _height_by_cell[cell]
		var hl := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(GRID_SCALE * 0.9, 0.08, GRID_SCALE * 0.9)
		hl.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.55, 1.0, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hl.material_override = mat
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


## ---------------------------------------------------------------------------
## _handle_grid_click() — 角色模式下的格子点击逻辑（原版逻辑 + 障碍格判定）
## ---------------------------------------------------------------------------
func _handle_grid_click(grid: Vector2i, _h: int) -> void:
	# 水域/建筑格：不可通行，给出明确提示
	if _water_by_cell.has(grid) or _building_by_cell.has(grid):
		_deselect()
		_refresh_hud()
		_flash_hint("🚫 该格不可通行", COLOR_ERR)
		return

	if not selected:
		if grid == unit.cell_pos:
			if unit.move_left <= 0:
				_refresh_hud()
				_flash_hint("⚠ 移动力已耗尽 — 点击右上角【回合结束】恢复移动力", COLOR_WARN)
				return
			selected = true
			_show_reachable()
		_refresh_hud()
	else:
		if grid == unit.cell_pos:
			_deselect()  # 再点自己 = 取消选中
		elif grid in reachable_cells:
			_move_unit_to(grid)
		else:
			_deselect()  # 点击不可达格 = 取消选中
		_refresh_hud()


## ---------------------------------------------------------------------------
## _move_unit_to() — 沿 BFS 路径逐格移动（贴地短跳链）
## ---------------------------------------------------------------------------
## 1. 从父指针表反推 起点 → 目标 的完整路径
## 2. 按路径长度扣移动力（原版简化为每次扣 1，这里修正）
## 3. 交给 _hop_next() 一格一格跳——每一跳落点都在格子顶面，绝不浮空
## ---------------------------------------------------------------------------
func _move_unit_to(target: Vector2i) -> void:
	_cancel_move(true)  # 先取消可能存在的上一次移动（静默）

	var path: Array = []
	var cur := target
	while cur != unit.cell_pos:
		path.push_front(cur)
		cur = _reachable_parent[cur]
	unit.move_left -= path.size()

	_move_path = path
	_hop_next()
	_deselect()


## ---------------------------------------------------------------------------
## _hop_next() / _on_hop_finished() — 逐格短跳的状态机
## ---------------------------------------------------------------------------
## 一跳 = 从当前立足格跳到路径上的下一格，落地瞬间更新 cell_pos 并
## snap_to_ground 精确贴地（防浮空的最后一道保险），然后继续下一跳。
## ---------------------------------------------------------------------------
func _hop_next() -> void:
	if _move_path.is_empty():
		_move_tween = null
		return
	var next: Vector2i = _move_path[0]
	var h: int = _height_by_cell[next]
	var from_h: int = _height_by_cell[unit.cell_pos]
	_move_tween = unit.hop_to(next, h, from_h)
	_move_tween.finished.connect(_on_hop_finished)


func _on_hop_finished() -> void:
	if _move_path.is_empty():
		return
	var arrived: Vector2i = _move_path.pop_front()
	unit.cell_pos = arrived  # 此刻起该格受"不能放置"保护
	unit.snap_to_ground(_height_by_cell[arrived])
	_hop_next()


## ---------------------------------------------------------------------------
## _cancel_move() / _validate_unit_path() — 移动与地图编辑的联动
## ---------------------------------------------------------------------------
## 放置建筑/注水后调用 _validate_unit_path()：若角色剩余路线上的任何一格
## 被新水域/建筑占据，立即取消移动并把角色吸附回当前立足格顶面——
## 角色永远不会"走到水里/楼里"，也不会停在半空。
## ---------------------------------------------------------------------------
func _cancel_move(silent: bool = false) -> void:
	var had_path := _move_path.size() > 0
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	_move_path.clear()
	unit.snap_to_ground(_height_by_cell[unit.cell_pos])
	if had_path and not silent:
		_flash_hint("⛔ 路线被阻断，移动已取消", COLOR_WARN)


func _validate_unit_path() -> void:
	for c in _move_path:
		if _water_by_cell.has(c) or _building_by_cell.has(c):
			_cancel_move()
			return


# ============================================================
#  角色 & 相机
# ============================================================
func _setup_unit() -> void:
	# 起始格：西南平原 (8, 12)（与 3-dmap 原版一致）
	var start_cell := Vector2i(8, 12)
	unit.set_grid_scale(GRID_SCALE)
	unit.move_left = unit.move_power
	unit.place_at(start_cell, _height_by_cell[start_cell])

	# 关闭角色的射线拾取：让鼠标射线直接穿过胶囊体命中脚下的格子
	# （角色本体的碰撞在预览射线里也通过 exclude 排除）
	unit.input_ray_pickable = false


## ---------------------------------------------------------------------------
## _setup_camera() / _rotate_camera() / _set_camera_yaw()
## 与 3-dmap 原版完全一致：正交投影 + 固定俯角 + 绕棋盘中心公转
## ---------------------------------------------------------------------------
func _setup_camera(yaw_deg: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAM_SIZE_DEFAULT
	_render_yaw = yaw_deg
	_rotate_camera(yaw_deg)


func _rotate_camera(yaw_deg: float) -> void:
	_camera_yaw = fposmod(yaw_deg, 360.0)

	var from_yaw := _render_yaw
	var to_yaw := _camera_yaw
	if abs(to_yaw - from_yaw) > 180.0:
		if to_yaw > from_yaw:
			from_yaw += 360.0
		else:
			to_yaw += 360.0

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_camera_yaw, from_yaw, to_yaw, 0.4)


func _set_camera_yaw(yaw_deg: float) -> void:
	_render_yaw = fposmod(yaw_deg, 360.0)
	var center := Vector3(GRID_W * GRID_SCALE / 2.0, 0, GRID_D * GRID_SCALE / 2.0)
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(CAM_PITCH)
	var offset := Vector3(
		cos(yaw) * cos(pitch),
		sin(pitch),
		sin(yaw) * cos(pitch)
	) * CAM_DISTANCE
	camera.position = center + offset
	camera.look_at(center)


## ---------------------------------------------------------------------------
## _unhandled_input() — 键盘/鼠标快捷键
##   Q/E = 旋转视角 90°（原版）
##   滚轮 = 缩放正交视野（上滚拉近、下滚拉远，clamp 在 MIN/MAX 之间）
##   R   = 建筑预览逆时针旋转 90°（仅建筑工具下有效）
##   ESC = 退出编辑工具，回到角色移动模式
## ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_left"):
		_rotate_camera(_camera_yaw - 90.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_right"):
		_rotate_camera(_camera_yaw + 90.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		# 正交相机缩放 = 改 camera.size（值越小看得越近）
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = clampf(camera.size * 0.9, CAM_SIZE_MIN, CAM_SIZE_MAX)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clampf(camera.size * 1.1, CAM_SIZE_MIN, CAM_SIZE_MAX)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_building"):
		if tool_idx >= 0 and tool_idx < BUILDING_PRESETS.size():
			_ghost_rot = (_ghost_rot + 1) % 4
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_move_btn.button_pressed = true  # 同步侧边栏按钮的选中态
		_set_tool(-1)
		get_viewport().set_input_as_handled()


# ============================================================
#  侧边栏（编辑器工具面板）
# ============================================================
## ---------------------------------------------------------------------------
## _build_sidebar() — 动态创建工具按钮
## ---------------------------------------------------------------------------
## 布局自上而下：角色移动模式 → 6 个建筑预设 → 水域工具。
## 按钮用 ButtonGroup 做互斥选中（radio 行为）：同一时刻只有一个工具生效。
## 建筑按钮的文案/提示直接取自 BUILDING_PRESETS，改预设表即改界面。
## ---------------------------------------------------------------------------
func _build_sidebar() -> void:
	var group := ButtonGroup.new()

	_move_btn = _make_tool_button("🧍 角色移动", group)
	_move_btn.tooltip_text = "选择并移动角色（默认模式）"
	_move_btn.pressed.connect(_on_tool_pressed.bind(-1))

	_make_section_label("🏗 建筑物")
	for i in BUILDING_PRESETS.size():
		var p: Dictionary = BUILDING_PRESETS[i]
		var b := _make_tool_button("%s %s  %d×%d×%d" % [p["icon"], p["name"], p["size"].x, p["size"].z, p["size"].y], group)
		b.tooltip_text = "占地 %d×%d 格、高 %d 层\n左键选中 → 地图上预览并放置，R 旋转，右键删除" % [p["size"].x, p["size"].z, p["size"].y]
		b.pressed.connect(_on_tool_pressed.bind(i))

	_make_section_label("🌊 地形")
	_water_btn = _make_tool_button("💧 水域", group)
	_water_btn.tooltip_text = "左键注水：以目标格为水面，填满连通且 <= 水面的封闭洼地（含更低处）\n贴到地图边缘 = 水会流走，注水失败\n右键水面：只删除被点格子同深度的连通水层（更深的坑保留）"
	_water_btn.pressed.connect(_on_tool_pressed.bind(WATER_TOOL))

	_move_btn.button_pressed = true  # 默认选中角色移动模式


func _make_tool_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 40)
	tool_vbox.add_child(b)
	return b


func _make_section_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.50, 0.42))
	tool_vbox.add_child(l)


func _on_tool_pressed(idx: int) -> void:
	_set_tool(idx)


## 切换工具：-1 = 角色模式，0..5 = 建筑，WATER_TOOL = 水域
func _set_tool(idx: int) -> void:
	tool_idx = idx
	_ghost_rot = 0
	_ghost_reason = ""
	_clear_ghost()
	_refresh_hud()


# ============================================================
#  回合流程 & UI
# ============================================================
## 回合结束：取消进行中的移动（贴地）、恢复移动力、回合数+1
func _on_end_turn() -> void:
	_cancel_move(true)
	turn_num += 1
	unit.move_left = unit.move_power
	_deselect()
	_refresh_hud()


## ---------------------------------------------------------------------------
## _refresh_hud() — 刷新界面文字（顶栏信息 + 按工具切换的底部提示）
## ---------------------------------------------------------------------------
func _refresh_hud() -> void:
	turn_label.text = "第 %d 回合" % turn_num
	unit_info_label.text = "⚔ 骑士  跳跃力: %d | 移动力: %d/%d%s" % [
		unit.jump_power, unit.move_left, unit.move_power,
		"  [已选中]" if selected else ""
	]
	map_info_label.text = "建筑 %d 座 · 水域 %d 格" % [_buildings.size(), _water_by_cell.size()]

	var hint := ""
	var color := COLOR_HINT
	if unit.move_left <= 0:
		hint = "⚠ 移动力已耗尽 — 点击右上角【回合结束】恢复移动力"
		color = COLOR_WARN
	elif tool_idx == WATER_TOOL:
		hint = "💧 水域工具：左键注水（自动填满封闭洼地，含更低处） · 右键水面删除同深度水层 · ESC 返回角色模式"
	elif tool_idx >= 0:
		var p: Dictionary = BUILDING_PRESETS[tool_idx]
		hint = "🏗 %s（%d×%d×%d）：左键放置 · R 旋转 · 右键已建建筑删除 · ESC 返回角色模式" % [p["name"], p["size"].x, p["size"].z, p["size"].y]
	else:
		hint = "左键点击角色选中 · 点击蓝色格移动 · 左侧栏选建筑/水域工具 · Q/E 旋转视角 · 滚轮缩放"
	hint_label.text = hint
	hint_label.add_theme_color_override("font_color", color)


## 临时覆盖底部提示（放置成功/失败、删除等反馈；下次 _refresh_hud 恢复）
func _flash_hint(text: String, color: Color) -> void:
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", color)
