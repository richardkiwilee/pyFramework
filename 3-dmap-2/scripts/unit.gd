extends CharacterBody3D
## =============================================================================
## Unit — 战棋角色单位（3-dmap 高级版）
## =============================================================================
## 与 3-dmap 原版相同的两个战棋核心属性：
##
##   【移动力 move_power】
##     每回合可以移动的格子总数。本版按实际路径长度扣除：
##     走 3 格扣 3 点（原版每步扣 1 的简化被修正）。
##
##   【跳跃力 jump_power】
##     两个相邻格子的高度差 |Δh| <= jump_power 时，可以跨过去。
##
## 与 3-dmap 原版的差异（对应"角色始终紧贴地面"的要求）：
##
##   · 原版 move_to() 是一次 Tween 从起点直达终点——如果中途高度起伏，
##     角色会沿直线"飞"过去（浮空）。本版改为 hop_to() 逐格短跳：
##     main.gd 沿 BFS 路径一格一格调用，每一跳的落点都精确压在
##     目标格子顶面（y = 格子高度 + 0.05），全程贴地。
##
##   · 新增 snap_to_ground()：立刻把角色压回脚下格子的顶面。
##     地图被编辑（注水/放建筑阻断行进路线）或移动取消时调用，
##     作为"绝不浮空"的最后一道保险。
## =============================================================================

class_name Unit

# ------------------------------------------------------------------ 战棋属性
## 每回合移动力（可走的最大格数）
@export var move_power: int = 4
## 跳跃力（可跨越的最大高度差）
@export var jump_power: int = 1

## 本回合剩余移动力
var move_left: int = 4

## 当前立足的格子坐标（grid 坐标系）。只有在一跳完成后才更新——
## 跳跃途中它始终指向"最后踩实的那一格"，取消移动时可安全吸附回去。
var cell_pos: Vector2i = Vector2i.ZERO

## 网格世界坐标的缩放系数（由 main.gd 注入）
var grid_scale: float = 2.0

## 单格短跳时长（秒）——短促利落，一格一格贴地前进
const HOP_SECONDS := 0.12

# ------------------------------------------------------------------ 节点引用
## 角色视觉主体（CapsuleMesh 胶囊体）
@onready var body_mesh: MeshInstance3D = $BodyMesh
## 角色碰撞体（未来物理用途）
@onready var collision: CollisionShape3D = $CollisionShape3D


## ---------------------------------------------------------------------------
## _ready() — 初始化角色外观（与 3-dmap 原版一致）
## ---------------------------------------------------------------------------
func _ready() -> void:
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.6

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#c8a23c")
	mat.metallic = 0.1
	mat.roughness = 0.6

	body_mesh.mesh = cap
	body_mesh.material_override = mat
	# 胶囊总高 = 1.6 + 2×0.45 = 2.5，半高 1.25。抬高 1.25 让底端落在
	# 单位原点 y=0，这样 place_at/hop_to 里 y = 格子顶面高度时脚底刚好贴地。
	body_mesh.position = Vector3(0, 1.25, 0)

	var cap_shape := CapsuleShape3D.new()
	cap_shape.radius = 0.45
	cap_shape.height = 1.6
	collision.shape = cap_shape
	collision.position = Vector3(0, 1.25, 0)


## ---------------------------------------------------------------------------
## set_grid_scale() — 注入网格缩放（由 main.gd 调用）
## ---------------------------------------------------------------------------
func set_grid_scale(s: float) -> void:
	grid_scale = s


## ---------------------------------------------------------------------------
## place_at() — 把角色传送到指定格子（立即，无动画）
## ---------------------------------------------------------------------------
## grid (gx, gz) → world (x, y, z)：
##   x = (gx + 0.5) × scale
##   y = height + 0.05   （+0.05 避免与格子顶面深度冲突）
##   z = (gz + 0.5) × scale
## ---------------------------------------------------------------------------
func place_at(cell: Vector2i, height: int) -> void:
	cell_pos = cell
	position = Vector3(
		(cell.x + 0.5) * grid_scale,
		height * 1.0 + 0.05,
		(cell.y + 0.5) * grid_scale
	)


## ---------------------------------------------------------------------------
## hop_to() — 跳到【相邻】目标格（单格短跳动画）
## ---------------------------------------------------------------------------
## 与 move_to 的关键区别：只跳一格，落点严格 = 目标格顶面 + 0.05。
##
## 下坡时的"贴地"处理（解决"从高处回到低处感觉浮空"的问题）：
##   单段斜线 tween 会让角色沿对角线"飘"下去。改为两段式——
##   第一段：平移到两格的交界处（y 保持当前高格顶面，此时角色仍站在
##   崖边，脚底踩着实地）；第二段：从崖边沿"墙壁"快速落到低格顶面。
##   看起来就是"走到崖边、迈步下台阶"，全程没有悬空滑翔感。
## 上坡/平路保持单段斜线：爬坡时身体贴着墙上升，视觉上不会觉得悬空。
##
## 返回本次跳跃的 Tween，供 main.gd 挂接"到达"回调或中途取消。
## ---------------------------------------------------------------------------
func hop_to(cell: Vector2i, height: int, from_height: int) -> Tween:
	var target := Vector3(
		(cell.x + 0.5) * grid_scale,
		height * 1.0 + 0.05,
		(cell.y + 0.5) * grid_scale
	)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if height < from_height:
		# 下坡：先走到两格交界处（仍站在高格顶面），再沿墙落下
		var edge := Vector3(
			(cell_pos.x + cell.x + 1) / 2.0 * grid_scale,
			from_height * 1.0 + 0.05,
			(cell_pos.y + cell.y + 1) / 2.0 * grid_scale
		)
		tween.tween_property(self, "position", edge, 0.06)
		tween.tween_property(self, "position", target, 0.09)
	else:
		# 上坡/平路：单段
		tween.tween_property(self, "position", target, 0.12)
	return tween


## ---------------------------------------------------------------------------
## snap_to_ground() — 立刻压回脚下格子顶面（消除浮空的保险）
## ---------------------------------------------------------------------------
## 地图编辑打断移动时调用：无论角色此刻在什么高度（比如跳跃途中），
## 都立刻重新按 cell_pos 所在格的高度计算落点，保证脚底贴地。
## ---------------------------------------------------------------------------
func snap_to_ground(height: int) -> void:
	position = Vector3(
		(cell_pos.x + 0.5) * grid_scale,
		height * 1.0 + 0.05,
		(cell_pos.y + 0.5) * grid_scale
	)
