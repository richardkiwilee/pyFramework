extends CharacterBody3D
## =============================================================================
## Unit — 战棋角色单位
## =============================================================================
## 作用：地图上的可移动角色。拥有两个战棋核心属性：
##
##   【移动力 move_power】
##     每回合可以移动的格子总数。类似"步数"。
##     · 每移动 1 格消耗 1 点
##     · 回合结束时恢复到满值（在 main.gd 的回合流程中处理）
##
##   【跳跃力 jump_power】
##     决定能否移动到"有高度差"的格子。
##     · 两个相邻格子的高度差 |Δh| <= jump_power 时，可以跨过去
##     · |Δh| > jump_power 时，该格不可达（相当于"跳不上去/跳不下来"）
##
## 3D 节点选择 — CharacterBody3D：
##   这是 Godot 的"角色物理体"，自带移动/碰撞接口。本 Demo 不依赖
##   物理模拟移动（用 Tween 直接改位置），但用它来：
##   1. 作为 3D 场景中的实体节点（有 transform 可以摆放）
##   2. 自带 CapsuleShape 碰撞体（未来需要射线拾取角色时可用）
##
## GDScript 注意：
##   class_name Unit 注册全局类，main.gd 可以直接 Unit.new()。
##   类似 Python 的 class 定义 + import。
## =============================================================================

class_name Unit

# ------------------------------------------------------------------ 战棋属性
## 每回合移动力（可走的最大格数）
@export var move_power: int = 4
## 跳跃力（可跨越的最大高度差）
@export var jump_power: int = 1

## 本回合剩余移动力（回合开始时 = move_power，移动一格减 1）
var move_left: int = 4

## 当前所在的格子坐标（grid 坐标系，见 main.gd 的说明）
var cell_pos: Vector2i = Vector2i.ZERO

## 网格世界坐标的缩放系数（由 main.gd 注入，用于把 grid 坐标转成世界坐标）
var grid_scale: float = 2.0

# ------------------------------------------------------------------ 节点引用
## 角色视觉主体（CapsuleMesh 胶囊体）
@onready var body_mesh: MeshInstance3D = $BodyMesh
## 角色碰撞体（点击拾取/未来物理用途）
@onready var collision: CollisionShape3D = $CollisionShape3D


## ---------------------------------------------------------------------------
## _ready() — 初始化角色外观
## ---------------------------------------------------------------------------
## 代码构建材质与网格（不使用外部资源文件，保证 Demo 自包含）。
## 金色材质 + 深色描边感的纯色方案，让角色在蓝色高亮格中一眼可见。
## ---------------------------------------------------------------------------
func _ready() -> void:
	# 创建胶囊网格（CapsuleMesh 是内置网格类型，无需美术资源）
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.6

	# StandardMaterial3D：PBR 标准材质
	# albedo_color = 基础色（类似 CSS 的 background-color）
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#c8a23c")
	mat.metallic = 0.1   # 低金属度（布料/盔甲质感）
	mat.roughness = 0.6  # 中等粗糙度

	body_mesh.mesh = cap
	body_mesh.material_override = mat
	# 【关键】胶囊体总高 = height + 2×radius = 1.6 + 0.9 = 2.5
	# 半高 = 1.25。把网格抬高 1.25 让胶囊底端正好落在单位原点 y=0，
	# 这样 place_at/move_to 里 y = 格子顶面高度 时角色脚底刚好贴地，
	# 不会浮在半空。
	body_mesh.position = Vector3(0, 1.25, 0)

	# 同步设置碰撞体（胶囊形状与网格一致，用于未来拾取/物理）
	var cap_shape := CapsuleShape3D.new()
	cap_shape.radius = 0.45
	cap_shape.height = 1.6
	collision.shape = cap_shape
	collision.position = Vector3(0, 1.25, 0)


## ---------------------------------------------------------------------------
## set_grid_scale() — 注入网格缩放（由 main.gd 在创建角色后调用）
## ---------------------------------------------------------------------------
func set_grid_scale(s: float) -> void:
	grid_scale = s


## ---------------------------------------------------------------------------
## place_at() — 把角色摆放到指定格子（立即传送，不做动画）
## ---------------------------------------------------------------------------
## 参数：
##   cell  — 目标格坐标 (gx, gz)
##   height — 该格的高度（用于计算 y 坐标）
##
## 坐标转换：
##   grid (gx, gz) → world (x, y, z)
##   x = (gx + 0.5) × scale   取格子中心
##   z = (gz + 0.5) × scale
##   y = height × 高度步进（每层 1 单位）
## ===========================================================================
func place_at(cell: Vector2i, height: int) -> void:
	cell_pos = cell
	var h_step := 1.0  # 每层高度差 1 个世界单位
	# y = 格子顶面 + 0.05：胶囊底端已对齐单位原点，这里只需加
	# 极小偏移避免与格子顶面深度冲突（z-fighting）
	position = Vector3(
		(cell.x + 0.5) * grid_scale,
		height * h_step + 0.05,
		(cell.y + 0.5) * grid_scale
	)


## ---------------------------------------------------------------------------
## move_to() — 动画移动到目标格子
## ---------------------------------------------------------------------------
## 用 Tween 在 0.3 秒内平滑移动位置，并更新 cell_pos 记录。
## （移动力的消耗由 main.gd 在调用前处理——数据与表现分离）
##
## Tween 说明：
##   create_tween() 创建补间动画器
##   tween_property(对象, "属性", 目标值, 时长) 平滑过渡
##   类似 Python 的 animation 库，但直接驱动节点属性。
## ---------------------------------------------------------------------------
func move_to(cell: Vector2i, height: int) -> void:
	cell_pos = cell
	var target := Vector3(
		(cell.x + 0.5) * grid_scale,
		height * 1.0 + 0.05,
		(cell.y + 0.5) * grid_scale
	)
	var tween := create_tween()
	# TRANS_SINE + EASE_IN_OUT：缓入缓出（起步慢→中间快→到站慢）
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", target, 0.3)
