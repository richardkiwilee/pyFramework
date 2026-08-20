## =====================================================================
## TeamListPanel — 队伍列表界面（屏幕左半边）
## =====================================================================
## readme 第 12-17 行：
##   · 左上角标题「编队管理」，标题独占一行
##   · 三个控件：左箭头、队伍名称、右箭头。QE 或点箭头切换队伍
##   · 队伍的九宫格信息（交给 GridPanel 负责，本文件只负责摆它）
##   · 最下方两个按钮：新建队伍、解散队伍（解散需要弹窗确认）
##
## 本文件只管「显示」和「把用户意图报上去」，不做任何决策 ——
## 切哪支队、能不能解散，都由 FormationScreen 决定。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control     → UI 控件基类
## signal xxx(a)       → 信号。emit 出去后由 FormationScreen 接。
## @onready            → 本文件没用它；节点都是代码里 new 出来的（和 Main.gd 同风格）
## Button.pressed      → 按钮被按下的信号
## .bind(x)            → 给回调预绑参数（类似 functools.partial）
## clip_text = true    → 文本超长时裁剪而不是撑大控件
## =====================================================================
class_name TeamListPanel
extends Control

## 请求切换队伍。dir = -1 上一队 / +1 下一队。
signal switch_team(dir: int)
## 请求新建队伍。
signal new_team_pressed
## 请求解散队伍（FormationScreen 收到后会先弹确认框）。
signal disband_pressed
## 九宫格某格被点击（原样转发 GridPanel 的信号）。
signal cell_clicked(slot: int)

var _layout: FormationLayout
var grid: GridPanel               # 九宫格子控件（对外暴露，FormationScreen 要直接操作它）

var _title: Label
var _btn_prev: Button
var _btn_next: Button
var _name_label: Label
var _capacity: Label
var _btn_new: Button
var _btn_disband: Button

## 移动模式下需要「除九宫格外全部失效」的控件清单。
## 数量固定且很少，逐个设 mouse_filter 比递归遍历整棵树更直白，
## 也符合本项目手写布局的风格。
var _non_grid_widgets: Array = []


func setup(layout: FormationLayout) -> void:
	_layout = layout
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 自己不吃鼠标，交给具体子控件

	# ---- 标题（readme：独占一行）----
	_title = FormationSkin.make_title("编队管理")
	add_child(_title)

	# ---- ◀ 队名 ▶ ----
	_btn_prev = FormationSkin.make_button("◀")
	_btn_prev.pressed.connect(func(): switch_team.emit(-1))
	add_child(_btn_prev)

	_name_label = FormationSkin.make_text("—", FormationSkin.GOLD, 17)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	add_child(_name_label)

	_btn_next = FormationSkin.make_button("▶")
	_btn_next.pressed.connect(func(): switch_team.emit(1))
	add_child(_btn_next)

	# ---- 九宫格 ----
	grid = GridPanel.new()
	grid.name = "Grid"
	add_child(grid)
	grid.setup(layout)
	grid.cell_clicked.connect(func(slot: int): cell_clicked.emit(slot))

	# ---- 规模 / 领导力 提示行 ----
	_capacity = FormationSkin.make_text("—", FormationSkin.INK_DIM, 12)
	_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capacity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_capacity)

	# ---- 底部两个按钮 ----
	_btn_new = FormationSkin.make_button("新建队伍")
	_btn_new.pressed.connect(func(): new_team_pressed.emit())
	add_child(_btn_new)

	_btn_disband = FormationSkin.make_button("解散队伍", true)  # true = 危险色
	_btn_disband.pressed.connect(func(): disband_pressed.emit())
	add_child(_btn_disband)

	_non_grid_widgets = [_btn_prev, _btn_next, _name_label, _btn_new, _btn_disband]


## 按锚点文件给的矩形摆位置。窗口缩放时重调。
func relayout() -> void:
	position = Vector2.ZERO
	size = _layout.zone_left.size

	var r: Rect2 = _layout.rect_title()
	_title.position = r.position
	_title.size = r.size

	var sw: Array = _layout.rects_team_switch()
	_apply(_btn_prev, sw[0])
	_apply(_name_label, sw[1])
	_apply(_btn_next, sw[2])

	# 九宫格子控件铺满整个左区，格子位置由它自己按锚点算。
	grid.position = Vector2.ZERO
	grid.size = size
	grid.relayout()

	_apply(_capacity, _layout.rect_capacity())
	var bb: Array = _layout.rects_bottom_buttons()
	_apply(_btn_new, bb[0])
	_apply(_btn_disband, bb[1])


## 小helper：把 Rect2 套到控件上。
func _apply(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size


## 刷新显示。
##   team        当前队伍（可能为 null，比如一支队都没有）
##   index/total 当前是第几支 / 共几支，用来显示「2/3」
func refresh(team: TeamModel, index: int, total: int) -> void:
	if team == null:
		_name_label.text = "（没有队伍）"
		_capacity.text = "点「新建队伍」开始编队"
		grid.set_team(null)
		_btn_disband.disabled = true
		return

	_btn_disband.disabled = false
	_name_label.text = "%s   %d/%d" % [team.team_name, index + 1, total]

	# 规模 / 领导力：这是 readme 那条退出校验规则的实时预览，
	# 超了就标红，让用户在按 ESC 之前就能看出问题。
	var used := team.total_size()
	if team.captain != null:
		var cap := team.captain.leadership
		_capacity.text = "规模 %d / 领导力 %d　·　%d 人" % [used, cap, team.unit_count()]
		_capacity.add_theme_color_override("font_color",
			FormationSkin.RED if used > cap else FormationSkin.INK_DIM)
	else:
		_capacity.text = "规模 %d　·　%d 人　·　尚未指定队长" % [used, team.unit_count()]
		_capacity.add_theme_color_override("font_color",
			FormationSkin.RED if team.unit_count() > 0 else FormationSkin.INK_DIM)

	grid.set_team(team)


## 进入移动模式：除九宫格外，左区其余控件全部失效。
##
## 这是「失焦即失效」的一个特例 —— 九宫格明明在左区里，
## 但移动模式下只有它该活着。不去跟 z-order 较劲，直接把那 5 个控件
## 逐个设成鼠标穿透即可（拦截层由 FormationScreen 统一放行左区）。
func set_grid_only(grid_only: bool) -> void:
	var f := Control.MOUSE_FILTER_IGNORE if grid_only else Control.MOUSE_FILTER_STOP
	for w in _non_grid_widgets:
		# Label 平时本来就是 IGNORE，这里只对按钮有实际意义；
		# 统一处理省得漏，Label 被设成 STOP 也无害（它没有点击回调）。
		if w is Button:
			w.mouse_filter = f
