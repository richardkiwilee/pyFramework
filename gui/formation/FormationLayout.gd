## =====================================================================
## FormationLayout — 界面锚点定义文件（readme 基本准则第 2 条）
## =====================================================================
## 「界面UI逻辑单独一个文件，定义锚点。」
## 整个编队界面的**几何**全部集中在这里：屏幕怎么切成左右两个界面容器、
## 每个容器内部各段占多高、九宫格每格在哪、成员行的 1:4:2 怎么分。
##
## 这个文件**不接收输入、不含业务逻辑**，只做两件事：
##   1. 造出两个界面容器（左/右）和它们的透明拦截层；
##   2. 按视口尺寸算出所有锚点矩形，供各面板取用。
## 想调界面比例，只改这里的常量，不用碰任何一个面板文件。
##
##   ┌─ 左：队伍列表界面 ────────┬─ 右：队伍成员界面 ──────────┐
##   │ 编队管理                  │ ┌──┬──────────┬────┐        │
##   │ ◀   亚连队   ▶            │ │头│ 名字 等级 │装备│ ×9 行  │
##   │ ┌───┬───┬───┐            │ │像│ 经验 AP/PP│ 栏 │        │
##   │ │ 0 │ 1 │ 2 │ ← 后排      │ └──┴──────────┴────┘        │
##   │ ├───┼───┼───┤            │  1  :    4     :  2         │
##   │ │ 3 │ 4 │ 5 │            │                             │
##   │ ├───┼───┼───┤            │                             │
##   │ │ 6 │ 7 │ 8 │ ← 前排      │                             │
##   │ └───┴───┴───┘            │                             │
##   │ 规模 65 / 领导力 132      │                             │
##   │ [新建队伍] [解散队伍]      │                             │
##   └──────────────────────────┴─────────────────────────────┘
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends RefCounted   → 纯对象，不进场景树（它只是「持有」节点，自己不是节点）
## Rect2(x, y, w, h)    → 矩形值对象。.position 是左上角，.size 是宽高。
## Vector2(x, y)        → 二维向量
## Panel                → 一块可以贴样式盒的矩形控件（这里当界面容器的外框）
## Control              → 所有 UI 控件的基类，有 position / size
## anchors_preset       → 锚点预设。PRESET_FULL_RECT = 填满父节点。
##                        本项目主要用**手写 position/size**，只在拦截层等
##                        需要「永远填满」的地方用锚点，和 Main.gd 的风格一致。
## node.add_child(x)    → 加子节点。兄弟顺序 = 绘制顺序，后加的画在上面。
## move_to_front()      → 把节点移到同级最后（= 最上层）
## =====================================================================
class_name FormationLayout
extends RefCounted

# ---------------- 全局比例 ----------------
const MARGIN := 12.0        # 屏幕四周留白
const ZONE_GAP := 10.0      # 左右两个界面容器之间的缝
const LEFT_RATIO := 0.46    # 左区占可用宽度的比例（右区放 9 行信息，给它多一点）

# ---------------- 左区（队伍列表界面）内部分段 ----------------
const TITLE_H := 34.0       # 「编队管理」标题行，readme 要求独占一行
const SWITCH_H := 40.0      # ◀ 队名 ▶ 这一行
const ARROW_W := 44.0       # 左右箭头按钮宽度
const SEC_GAP := 10.0       # 段与段之间的间距
const CAPACITY_H := 24.0    # 「规模 / 领导力」提示行
const BUTTON_H := 36.0      # 新建/解散按钮行
const GRID_CELL_GAP := 6.0  # 九宫格格子间距

# ---------------- 右区（队伍成员界面）内部 ----------------
const MEMBER_ROWS := 9      # readme：最多可以上场 9 个单位
const ROW_GAP := 5.0        # 成员行之间的间距
## 成员行的 1:4:2 分栏（readme 原文：「每个栏位分成 1：4：2」）
const ROW_PART_PORTRAIT := 1.0   # 左：单位头像
const ROW_PART_INFO := 4.0       # 中：等级、经验值、AP/PP
const ROW_PART_EQUIP := 2.0      # 右：装备栏（仅展示）
const ROW_PART_GAP := 6.0        # 三栏之间的缝

# ---------------- 持有的节点 ----------------
var root: Control            # 整个编队界面的根（由 FormationScreen 传入）
var zone_left: Panel         # 左：队伍列表界面容器
var zone_right: Panel        # 右：队伍成员界面容器
var blocker_left: Control    # 左区透明拦截层（失焦时吃掉鼠标）
var blocker_right: Control   # 右区透明拦截层

## 覆盖层的挂载点。readme 规定：
##   单位详细界面「位置完全覆盖队伍成员界面」→ 挂在 overlay_right
##   可选界面    「位置完全覆盖队伍列表界面」→ 挂在 overlay_left
## 它们是和 zone_left / zone_right 同尺寸、同位置的空 Control。
var overlay_left: Control
var overlay_right: Control


## 造出两个界面容器 + 拦截层 + 覆盖层挂载点。
## parent 就是编队场景的根节点。
func build(parent: Control) -> void:
	root = parent

	zone_left = Panel.new()
	zone_left.name = "ZoneLeft"
	zone_left.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(zone_left)

	zone_right = Panel.new()
	zone_right.name = "ZoneRight"
	zone_right.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(zone_right)

	# 拦截层加在各自容器内，且必须是**最后一个子节点**才能盖住所有兄弟。
	# 各面板稍后往容器里加控件时，要记得调用 lift_blockers() 把它重新提到最上层。
	# 用 add_filling 而不是 add_child + anchors_preset：
	# 拦截层必须真的填满整个容器，0 尺寸的拦截层什么也挡不住。
	blocker_left = FormationSkin.make_blocker()
	FormationSkin.add_filling(zone_left, blocker_left)
	blocker_right = FormationSkin.make_blocker()
	FormationSkin.add_filling(zone_right, blocker_right)

	# 覆盖层挂载点加在根节点上（不在容器内），这样覆盖层能盖住容器的边框，
	# 也不会被容器的拦截层挡住 —— 覆盖层出现时本来就该接管输入。
	overlay_left = Control.new()
	overlay_left.name = "OverlayLeft"
	overlay_left.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 自己不吃，交给里面的面板
	parent.add_child(overlay_left)

	overlay_right = Control.new()
	overlay_right.name = "OverlayRight"
	overlay_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(overlay_right)


## 把两个拦截层重新提到各自容器的最上层。
## 每次往 zone_left / zone_right 里加完控件后都要调一次，
## 否则新加的控件会盖在拦截层之上，拦截就失效了。
func lift_blockers() -> void:
	if blocker_left != null:
		blocker_left.move_to_front()
	if blocker_right != null:
		blocker_right.move_to_front()


## 按视口尺寸重算所有位置。窗口缩放时由 FormationScreen 调用。
func layout(view_size: Vector2) -> void:
	var avail_w := view_size.x - MARGIN * 2.0 - ZONE_GAP
	var avail_h := view_size.y - MARGIN * 2.0
	# 用 floorf 而不是 floor：全局 floor() 的返回类型是 Variant，
	# 配合 := 推导会触发「从 Variant 推断类型」的警告，而本项目把警告当错误。
	# floorf/minf/maxf/clampf 这些带后缀的版本返回类型是明确的 float。
	var lw := floorf(avail_w * LEFT_RATIO)
	var rw := avail_w - lw

	zone_left.position = Vector2(MARGIN, MARGIN)
	zone_left.size = Vector2(lw, avail_h)
	zone_right.position = Vector2(MARGIN + lw + ZONE_GAP, MARGIN)
	zone_right.size = Vector2(rw, avail_h)

	# 覆盖层和它要覆盖的容器完全同位同尺寸 —— readme 说的「完全覆盖」。
	overlay_left.position = zone_left.position
	overlay_left.size = zone_left.size
	overlay_right.position = zone_right.position
	overlay_right.size = zone_right.size


# =====================================================================
#  左区内部锚点（坐标都是**相对 zone_left 内容区**的局部坐标）
# =====================================================================
# 说明：zone_left 的样式盒设了 12px 的 content_margin，但 content_margin 只影响
# 容器自己的「内容区」概念，手写布局的子节点并不会自动缩进，所以这里统一
# 从 PAD 开始排，PAD 与样式盒的 content_margin 保持一致。
const PAD := 12.0

## 左区内容区的可用宽度。
func left_inner_width() -> float:
	return zone_left.size.x - PAD * 2.0


## 「编队管理」标题。readme：标题独占一行。
func rect_title() -> Rect2:
	return Rect2(PAD, PAD, left_inner_width(), TITLE_H)


## ◀ 按钮 / 队名 / ▶ 按钮 这一行的三个矩形。
## 返回 [左箭头, 队名, 右箭头]。
func rects_team_switch() -> Array:
	var y := PAD + TITLE_H + SEC_GAP
	var w := left_inner_width()
	var name_w := w - ARROW_W * 2.0
	return [
		Rect2(PAD, y, ARROW_W, SWITCH_H),
		Rect2(PAD + ARROW_W, y, name_w, SWITCH_H),
		Rect2(PAD + ARROW_W + name_w, y, ARROW_W, SWITCH_H),
	]


## 九宫格整体占用的矩形。
## 它吃掉标题、切换行之上的剩余空间，底部给容量提示行和按钮行留位。
func rect_grid_area() -> Rect2:
	var top := PAD + TITLE_H + SEC_GAP + SWITCH_H + SEC_GAP
	var bottom_reserved := CAPACITY_H + SEC_GAP + BUTTON_H + PAD
	var h := zone_left.size.y - top - bottom_reserved
	return Rect2(PAD, top, left_inner_width(), maxf(h, 60.0))


## 九宫格第 slot 格（0..8）的矩形，坐标同样相对 zone_left。
## 格子做成正方形并整体居中 —— readme 选的是正方 3×3 网格。
func rect_grid_cell(slot: int) -> Rect2:
	var area := rect_grid_area()
	# 先按「三格 + 两条缝」算出边长，取宽高里较小的那个，保证是正方形。
	var cell := minf(
		(area.size.x - GRID_CELL_GAP * 2.0) / 3.0,
		(area.size.y - GRID_CELL_GAP * 2.0) / 3.0)
	var total := cell * 3.0 + GRID_CELL_GAP * 2.0
	# 在 area 里居中
	var ox := area.position.x + (area.size.x - total) * 0.5
	var oy := area.position.y + (area.size.y - total) * 0.5
	var rc := TeamModel.slot_to_rc(slot)
	return Rect2(
		ox + float(rc.y) * (cell + GRID_CELL_GAP),
		oy + float(rc.x) * (cell + GRID_CELL_GAP),
		cell, cell)


## 「规模 65 / 领导力 132」提示行。
func rect_capacity() -> Rect2:
	var y := zone_left.size.y - PAD - BUTTON_H - SEC_GAP - CAPACITY_H
	return Rect2(PAD, y, left_inner_width(), CAPACITY_H)


## 底部两个按钮：[新建队伍, 解散队伍]。
func rects_bottom_buttons() -> Array:
	var y := zone_left.size.y - PAD - BUTTON_H
	var w := left_inner_width()
	var bw := (w - SEC_GAP) * 0.5
	return [
		Rect2(PAD, y, bw, BUTTON_H),
		Rect2(PAD + bw + SEC_GAP, y, bw, BUTTON_H),
	]


# =====================================================================
#  右区内部锚点（相对 zone_right 的局部坐标）
# =====================================================================

func right_inner_width() -> float:
	return zone_right.size.x - PAD * 2.0


## 右区标题行（显示当前队伍名 + 人数）。
func rect_right_title() -> Rect2:
	return Rect2(PAD, PAD, right_inner_width(), TITLE_H)


## 第 idx 个成员栏位（0..8）的矩形。
## readme：均分为 9 个栏位，从上往下紧密排列。
func rect_member_row(idx: int) -> Rect2:
	var top := PAD + TITLE_H + SEC_GAP
	var avail := zone_right.size.y - top - PAD
	var row_h := (avail - ROW_GAP * float(MEMBER_ROWS - 1)) / float(MEMBER_ROWS)
	return Rect2(PAD, top + float(idx) * (row_h + ROW_GAP), right_inner_width(), row_h)


## 把一个成员行的矩形按 1:4:2 切成三块，返回 [头像, 信息, 装备]。
## 坐标是**相对该行**的局部坐标（因为每行是一个独立的 Control 子树）。
static func split_member_row(row_size: Vector2) -> Array:
	var total_parts := ROW_PART_PORTRAIT + ROW_PART_INFO + ROW_PART_EQUIP
	var usable := row_size.x - ROW_PART_GAP * 2.0
	var w_portrait := usable * ROW_PART_PORTRAIT / total_parts
	var w_info := usable * ROW_PART_INFO / total_parts
	var w_equip := usable * ROW_PART_EQUIP / total_parts
	return [
		Rect2(0.0, 0.0, w_portrait, row_size.y),
		Rect2(w_portrait + ROW_PART_GAP, 0.0, w_info, row_size.y),
		Rect2(w_portrait + ROW_PART_GAP + w_info + ROW_PART_GAP, 0.0, w_equip, row_size.y),
	]


# =====================================================================
#  焦点视觉
# =====================================================================

## 设置哪一半是「活的」。同时管两件事：
##   1. 外框样式（金边 vs 无边）—— 视觉提示
##   2. 拦截层开关            —— 真正让失焦的一半点不动、也没有悬停反馈
## readme：「如果界面容器失去了焦点，这个界面容器下的所有控件都应该失效。」
func set_zone_active(left_active: bool, right_active: bool) -> void:
	zone_left.add_theme_stylebox_override("panel", FormationSkin.zone_box(left_active))
	zone_right.add_theme_stylebox_override("panel", FormationSkin.zone_box(right_active))
	FormationSkin.set_blocker_active(blocker_left, left_active)
	FormationSkin.set_blocker_active(blocker_right, right_active)
