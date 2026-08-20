## =====================================================================
## FormationScreen — 编队界面总装 + 焦点状态机 + 键盘路由
## =====================================================================
## 这是整个编队功能的「大脑」。所有面板都只负责显示和报告用户意图，
## **一切决策都在这个文件里**，所以只要读这一个文件就能搞清楚交互逻辑。
##
## ---- 焦点模型：单一 Surface 枚举 ----
## 不用「焦点在左还是右 + 一堆 overlay 布尔标志」那种写法，
## 而是把每种复合状态都做成枚举的一个取值。好处是从结构上不可能出现
## 「可选界面开着但单位详细界面没开」这类自相矛盾的状态。
##
## ---- readme 对应关系 ----
##   第 10-11 行 两个界面容器，失焦的一半所有控件都要失效  → _apply_surface()
##   第 14 行    QE 或点箭头切换队伍                      → _on_switch_team()
##   第 21 行    焦点在左时点九宫格 → 焦点进入右            → _on_cell_clicked()
##   第 22 行    新建队伍 → 焦点自动进入成员界面            → _on_new_team()
##   第 24 行    空格/左键点成员 → 弹出操作菜单             → _on_row_activated()
##   第 26 行    移动：焦点进九宫格，空位移动 / 占位互换     → _commit_move()
##   第 30 行    ESC 退出时的三段校验                      → _try_leave_right()
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control              → UI 控件基类，这里是整个场景的根
## enum Surface { A, B }        → 枚举，等价于 Python 的 enum.IntEnum
## match x:                     → 等价于 Python 3.10 的 match/case
## _unhandled_input(event)      → 没被任何 GUI 控件消费掉的输入会到这里。
##                                所有按钮都设了 FOCUS_NONE，所以按键一定能走到这。
## get_viewport().set_input_as_handled()
##                              → 标记「这个输入我处理了」，阻止它继续往下传。
##                                每个被消费的键都要调，否则 ESC 会漏到下层逻辑。
## event.keycode                → 按键码，如 KEY_ESCAPE / KEY_W
## get_tree().change_scene_to_file(p) → 切换场景
## create_tween()               → 造一个补间动画（这里用来让 toast 淡出）
## call_deferred("f")           → 延到本帧末尾再调用 f（等节点就位）
## posmod(a, b)                 → 结果恒非负的取模，用于首尾循环
## =====================================================================
extends Control

## 焦点表面。同一时刻只有一个表面接收输入。
enum Surface {
	LEFT,        # 队伍列表界面
	RIGHT,       # 队伍成员界面
	MENU,        # 成员操作菜单（移动/编辑/设为队长/下场）
	MOVE,        # 移动模式：焦点进入九宫格锚点
	DETAIL,      # 单位详细界面（覆盖右侧）
	PICKER,      # 可选界面（覆盖左侧），其下必定开着 DETAIL
	PICKER_ADD,  # 可选界面·添加成员模式（待命池），其下没有 DETAIL
	CONFIRM,     # 解散确认弹窗
}

var _layout: FormationLayout
var _left: TeamListPanel
var _right: MemberPanel
var _menu: ActionMenu
var _detail: UnitDetailPanel
var _picker: PickerPanel
var _confirm: DisbandConfirm
var _toast: Label
var _hint: Label

var _surface: int = Surface.LEFT
var _team_idx: int = 0
## 操作菜单当前针对的单位（菜单弹出时记下，之后各动作都用它）。
var _menu_unit: UnitModel = null


func _ready() -> void:
	# 根节点在 .tscn 里已设 FULL_RECT 锚点，这里只读 size。
	_build()
	_relayout()
	_refresh_all()
	_set_surface(Surface.LEFT)
	get_viewport().size_changed.connect(_relayout)
	set_process_unhandled_input(true)


# =====================================================================
#  一、搭建
# =====================================================================

func _build() -> void:
	# 背景（比主场景更暗，突出两个界面容器）
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0.047, 0.039, 0.031)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	FormationSkin.add_filling(self, bg)

	# 锚点文件负责造两个界面容器 + 拦截层 + 覆盖层挂载点
	_layout = FormationLayout.new()
	_layout.build(self)

	# ---- 左：队伍列表界面 ----
	_left = TeamListPanel.new()
	_left.name = "TeamListPanel"
	_layout.zone_left.add_child(_left)
	_left.setup(_layout)
	_left.switch_team.connect(_on_switch_team)
	_left.new_team_pressed.connect(_on_new_team)
	_left.disband_pressed.connect(_on_disband_pressed)
	_left.cell_clicked.connect(_on_cell_clicked)

	# ---- 右：队伍成员界面 ----
	_right = MemberPanel.new()
	_right.name = "MemberPanel"
	_layout.zone_right.add_child(_right)
	_right.setup(_layout)
	_right.row_activated.connect(_on_row_activated)

	# 拦截层必须重新提到最上层 —— 上面刚往两个容器里加了面板，
	# 那些面板现在盖在拦截层之上，不提的话拦截就失效了。
	_layout.lift_blockers()

	# ---- 可选界面：完全覆盖左侧（readme 第 34 行）----
	_picker = PickerPanel.new()
	_layout.overlay_left.add_child(_picker)
	_picker.choice_made.connect(_on_picker_choice)
	_picker.canceled.connect(_on_picker_canceled)

	# ---- 单位详细界面：完全覆盖右侧（readme 第 32 行）----
	_detail = UnitDetailPanel.new()
	_layout.overlay_right.add_child(_detail)
	_detail.cell_activated.connect(_on_detail_cell)

	# ---- 操作菜单：浮在右区之上 ----
	_menu = ActionMenu.new()
	FormationSkin.add_filling(self, _menu)
	_menu.chosen.connect(_on_menu_chosen)

	# ---- 解散确认框：全屏模态，放最上层 ----
	_confirm = DisbandConfirm.new()
	FormationSkin.add_filling(self, _confirm)
	_confirm.confirmed.connect(_on_disband_confirmed)
	_confirm.canceled.connect(_on_disband_canceled)

	# ---- 底部操作提示 ----
	_hint = FormationSkin.make_text("", FormationSkin.INK_DIM, 11)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	# ---- Toast：校验失败时的提示 ----
	_toast = FormationSkin.make_text("", FormationSkin.RED, 14)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)


func _relayout() -> void:
	_layout.layout(size)
	_left.relayout()
	_right.relayout()

	_picker.position = Vector2.ZERO
	_picker.size = _layout.overlay_left.size
	_picker.relayout()

	_detail.position = Vector2.ZERO
	_detail.size = _layout.overlay_right.size
	_detail.relayout()

	_hint.position = Vector2(0, size.y - 20)
	_hint.size = Vector2(size.x, 16)
	_toast.position = Vector2(size.x * 0.25, size.y - 62)
	_toast.size = Vector2(size.x * 0.5, 30)


# =====================================================================
#  二、状态机
# =====================================================================

func _set_surface(s: int) -> void:
	_surface = s

	# ---- 哪一半是「活的」----
	# readme：「如果界面容器失去了焦点，这个界面容器下的所有控件都应该失效。」
	# set_zone_active 同时管两件事：外框金边（视觉）+ 透明拦截层（真正拦住鼠标）。
	var left_on := s == Surface.LEFT or s == Surface.MOVE
	var right_on := s == Surface.RIGHT
	_layout.set_zone_active(left_on, right_on)

	# ---- 移动模式的特例 ----
	# 九宫格在左区里，但移动模式下只有它该活着，左区其余控件必须失效。
	_left.set_grid_only(s == Surface.MOVE)

	# ---- 覆盖层显隐 ----
	# 注意 DETAIL 在 PICKER 状态下必须保持可见 —— 可选界面盖的是左边，
	# 单位详细界面还在右边开着，两者是叠加而不是互斥的。
	_detail.visible = s == Surface.DETAIL or s == Surface.PICKER
	_picker.visible = s == Surface.PICKER or s == Surface.PICKER_ADD
	if s != Surface.MENU:
		_menu.close()
	if s != Surface.CONFIRM:
		_confirm.close()
	if s != Surface.MOVE:
		_left.grid.exit_move_mode()

	_update_hint()


## 底部操作提示，按当前状态显示可用按键。
func _update_hint() -> void:
	match _surface:
		Surface.LEFT:
			_hint.text = "Q/E 或点箭头 切换队伍　·　点九宫格 进入队伍成员界面　·　ESC 返回主场景"
		Surface.RIGHT:
			_hint.text = "W/S 或鼠标悬停 选择成员　·　空格/左键 打开操作菜单　·　ESC 保存并返回队伍列表"
		Surface.MENU:
			_hint.text = "W/S 选择操作　·　空格 确认　·　ESC 关闭菜单"
		Surface.MOVE:
			_hint.text = "WASD 移动目标格　·　空格/左键 确认（空位移动 / 占位互换）　·　ESC 取消"
		Surface.DETAIL:
			_hint.text = "W/S 选择格子　·　空格 打开可选界面　·　ESC 返回队伍成员界面"
		Surface.PICKER, Surface.PICKER_ADD:
			_hint.text = "W/S 选择　·　空格 确认（第一行是卸下）　·　ESC 返回"
		Surface.CONFIRM:
			_hint.text = "解散队伍需要确认　·　ESC 取消"


# =====================================================================
#  三、数据 → 界面
# =====================================================================

func _current_team() -> TeamModel:
	if FormationData.teams.is_empty():
		return null
	_team_idx = clampi(_team_idx, 0, FormationData.teams.size() - 1)
	return FormationData.teams[_team_idx]


func _refresh_all(keep_cursor: bool = true) -> void:
	var t := _current_team()
	_left.refresh(t, _team_idx, FormationData.teams.size())
	_right.refresh(t, keep_cursor)


# =====================================================================
#  四、左：队伍列表界面
# =====================================================================

## Q/E 或点箭头切换队伍。首尾循环。
func _on_switch_team(dir: int) -> void:
	if _surface != Surface.LEFT:
		return
	if FormationData.teams.is_empty():
		return
	_team_idx = posmod(_team_idx + dir, FormationData.teams.size())
	_refresh_all(false)


## readme 第 22 行：「当点击新建队伍时，新建一个空白的九宫格，
## 然后焦点自动进入它的队伍成员管理界面。」
## 注意此时队伍是 0 人、无队长；用户若立刻 ESC，会走 VOID 分支被自动删除。
func _on_new_team() -> void:
	if _surface != Surface.LEFT:
		return
	FormationData.create_team()
	_team_idx = FormationData.teams.size() - 1
	_refresh_all(false)
	_set_surface(Surface.RIGHT)


func _on_disband_pressed() -> void:
	if _surface != Surface.LEFT:
		return
	var t := _current_team()
	if t == null:
		return
	# readme 第 16 行明确要求「解散队伍需要弹窗确认」。
	_confirm.ask(t.team_name, t.unit_count())
	_set_surface(Surface.CONFIRM)


func _on_disband_confirmed() -> void:
	var t := _current_team()
	if t != null:
		FormationData.delete_team(t)
		# 删完可能越界，往前挪一格。
		_team_idx = clampi(_team_idx, 0, maxi(0, FormationData.teams.size() - 1))
	_refresh_all(false)
	_set_surface(Surface.LEFT)


func _on_disband_canceled() -> void:
	_set_surface(Surface.LEFT)


## 九宫格某格被点击。同一个信号在两种状态下含义完全不同 ——
## 这正是 GridPanel 只报告「点了第几格」而不自己做决策的原因。
func _on_cell_clicked(slot: int) -> void:
	match _surface:
		Surface.LEFT:
			# readme 第 21 行：焦点在队伍列表界面时，点九宫格区域 → 焦点进入成员界面。
			# 空格也算，整片九宫格都可点，没有死角。
			if _current_team() != null:
				_set_surface(Surface.RIGHT)
		Surface.MOVE:
			_commit_move(slot)


# =====================================================================
#  五、右：队伍成员界面
# =====================================================================

## 成员行被激活（空格或左键）。
func _on_row_activated(row: int) -> void:
	if _surface != Surface.RIGHT:
		return
	var t := _current_team()
	if t == null:
		return
	if _right.cursor_is_add_row():
		# readme 只说第一个空栏位显示加号表示添加成员，没说点下去弹什么。
		# 按可选界面的定位实现为弹待命池列表（这也是待命池唯一可见的地方）。
		if t.first_empty_slot() < 0:
			_show_toast("九宫格已经满了（9/9）")
			return
		_picker.open_reserve(FormationData.reserve_pool())
		_set_surface(Surface.PICKER_ADD)
		return

	var u := _right.cursor_unit()
	if u == null:
		return
	_menu_unit = u
	# 菜单弹在该成员行旁边。行矩形是相对 MemberPanel 的，
	# 加上右区容器的位置才是本节点（全屏）的坐标。
	var r := _right.row_rect(row)
	r.position += _layout.zone_right.position
	_menu.open_at(r, size)
	_set_surface(Surface.MENU)


## readme 第 24 行的四个操作。
func _on_menu_chosen(action: String) -> void:
	var t := _current_team()
	if t == null or _menu_unit == null:
		_set_surface(Surface.RIGHT)
		return

	match action:
		"move":
			# readme 第 26 行：焦点进入九宫格的锚点，WSAD 进行循环。
			var src := t.slot_of(_menu_unit)
			if src < 0:
				_set_surface(Surface.RIGHT)
				return
			_left.grid.enter_move_mode(src)
			_set_surface(Surface.MOVE)
		"edit":
			# readme 第 29 行：点击编辑，进入单位详细界面。
			_detail.open(_menu_unit)
			_set_surface(Surface.DETAIL)
		"captain":
			# readme 第 28 行：直接设为队长，把合法性检查留到退出界面。
			t.set_captain(_menu_unit)
			_refresh_all()
			_set_surface(Surface.RIGHT)
		"bench":
			# readme 第 27 行：点击下场，把这个单位移动到待命池。
			FormationData.send_to_reserve(t, _menu_unit)
			_refresh_all(false)
			_set_surface(Surface.RIGHT)
		_:
			_set_surface(Surface.RIGHT)


# =====================================================================
#  六、移动模式
# =====================================================================

## 提交移动。目标空 → 移过去；目标有人 → 互换。
func _commit_move(target_slot: int) -> void:
	var t := _current_team()
	if t == null:
		_set_surface(Surface.RIGHT)
		return
	var src := _left.grid.move_source()
	# move_unit 内部已经处理了「同格 = 什么都不做」和「空位移动 / 占位互换」。
	t.move_unit(src, target_slot)
	_left.grid.exit_move_mode()
	_refresh_all(false)
	_set_surface(Surface.RIGHT)


# =====================================================================
#  七、单位详细界面 → 可选界面
# =====================================================================

func _on_detail_cell(kind: String, row: int, field: String) -> void:
	var u := _detail.unit()
	if u == null:
		return
	match kind:
		"equip":
			var sdef: Dictionary = UnitModel.EQUIP_SLOTS[row]
			_picker.open_equip(u, str(sdef.key), str(sdef.label))
			_set_surface(Surface.PICKER)
		"skill":
			_picker.open_skill(u, row)
			_set_surface(Surface.PICKER)
		"cond":
			_picker.open_condition(u, row, field)
			_set_surface(Surface.PICKER)
		"del":
			# 删策略行不需要弹列表，直接改数据重绘。
			u.remove_strategy_row(row)
			_detail.rebuild()
		"add":
			u.add_strategy_row()
			_detail.rebuild()


## 可选界面选中了某项。id 为空串 = 卸下。
func _on_picker_choice(id: String) -> void:
	if _surface == Surface.PICKER_ADD:
		_place_from_reserve(id)
		return

	var u := _detail.unit()
	if u == null:
		_set_surface(Surface.DETAIL)
		return

	var ctx := _picker.context()
	match _picker.kind():
		"equip":
			var slot_key := str(ctx.get("slot_key", ""))
			if id.is_empty():
				u.unequip(slot_key)     # 首行「卸下」
			else:
				u.equip(slot_key, id)
		"skill":
			u.set_strategy_cell(int(ctx.get("row", -1)), "skill", id)
		"cond":
			u.set_strategy_cell(int(ctx.get("row", -1)), str(ctx.get("field", "cond1")), id)

	_picker.close()
	_detail.rebuild()
	_refresh_all()   # 成员行里的装备栏也要跟着变
	_set_surface(Surface.DETAIL)


## 从待命池选了一个人 → 放到九宫格第一个空格。
func _place_from_reserve(unit_id: String) -> void:
	var t := _current_team()
	if t == null:
		_set_surface(Surface.RIGHT)
		return
	var slot := t.first_empty_slot()
	if slot < 0:
		_show_toast("九宫格已经满了（9/9）")
		_set_surface(Surface.RIGHT)
		return
	for u in FormationData.reserve_pool():
		var unit: UnitModel = u
		if unit.id == unit_id:
			FormationData.place_unit(t, slot, unit)
			break
	_picker.close()
	_refresh_all(false)
	_set_surface(Surface.RIGHT)


func _on_picker_canceled() -> void:
	_picker.close()
	# 从哪来回哪去：add 模式是从成员界面来的，其余是从详细界面来的。
	_set_surface(Surface.RIGHT if _surface == Surface.PICKER_ADD else Surface.DETAIL)


# =====================================================================
#  八、退出校验（readme 第 30 行 —— 本功能的核心规则）
# =====================================================================

## 从队伍成员界面按 ESC 想回队伍列表界面时调用。
## 只有这一跳会校验；DETAIL→RIGHT、MOVE→RIGHT 都不校验，
## 这样用户永远能退一层回去改。
func _try_leave_right() -> void:
	var t := _current_team()
	if t == null:
		_set_surface(Surface.LEFT)
		return

	var res: Array = t.is_valid()
	var code := str(res[0])
	var msg := str(res[1])

	match code:
		TeamModel.VOID:
			# 没有任何单位 → 允许弹出焦点，但队伍不再成立，自动删除。
			FormationData.delete_team(t)
			_team_idx = clampi(_team_idx, 0, maxi(0, FormationData.teams.size() - 1))
			_refresh_all(false)
			_show_toast("队伍没有任何单位，已自动解散", false)
			_set_surface(Surface.LEFT)
		TeamModel.OK:
			# readme：成功保存队伍时，更新队伍的名字，使用「<队长名>队」。
			t.rename_by_captain()
			_refresh_all()
			_set_surface(Surface.LEFT)
		_:
			# NO_CAPTAIN / OVERLOAD → 拒绝弹出焦点，必须先改正。
			_show_toast(msg)


# =====================================================================
#  九、统一的键盘路由
# =====================================================================
## 所有按键都在这一个函数里分发，顺序即优先级。
## 之所以能这么写，是因为所有 Button 都设了 focus_mode = FOCUS_NONE，
## 不会有按钮抢走方向键/空格/回车。

func _unhandled_input(event: InputEvent) -> void:
	# 必须先 as 成 InputEventKey 再取 keycode。
	# 形参声明的是基类 InputEvent，就算前面用 `is` 判断过，GDScript 也不会
	# 因此收窄类型，直接 `var k := event.keycode` 会报「无法推断类型」的解析错误。
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var k := key_event.keycode

	# ---- ESC：一次只弹一层，最内层先吃 ----
	if k == KEY_ESCAPE:
		_handle_escape()
		get_viewport().set_input_as_handled()
		return

	match _surface:
		Surface.LEFT:
			# readme 第 14 行：使用 QE 来进行队伍的切换。
			if k == KEY_Q:
				_on_switch_team(-1)
			elif k == KEY_E:
				_on_switch_team(1)
			else:
				return
		Surface.RIGHT:
			# readme 第 24 行：按 WS 切换成员，空格弹出操作选项。
			if k == KEY_W:
				_right.step_cursor(-1)
			elif k == KEY_S:
				_right.step_cursor(1)
			elif k == KEY_SPACE:
				_on_row_activated(_right.cursor())
			else:
				return
		Surface.MENU:
			if k == KEY_W:
				_menu.step(-1)
			elif k == KEY_S:
				_menu.step(1)
			elif k == KEY_SPACE:
				_menu.activate_cursor()
			else:
				return
		Surface.MOVE:
			# readme 第 26 行：焦点进入九宫格的锚点，WSAD 进行循环。
			# W/S 在这个状态下归 WASD 管，不再是「切换成员」。
			if k == KEY_W:
				_left.grid.step_cursor(0, -1)
			elif k == KEY_S:
				_left.grid.step_cursor(0, 1)
			elif k == KEY_A:
				_left.grid.step_cursor(-1, 0)
			elif k == KEY_D:
				_left.grid.step_cursor(1, 0)
			elif k == KEY_SPACE:
				_commit_move(_left.grid.move_cursor())
			else:
				return
		Surface.DETAIL:
			if k == KEY_W:
				_detail.step(-1)
			elif k == KEY_S:
				_detail.step(1)
			elif k == KEY_SPACE:
				_detail.activate_cursor()
			else:
				return
		Surface.PICKER, Surface.PICKER_ADD:
			if k == KEY_W:
				_picker.step(-1)
			elif k == KEY_S:
				_picker.step(1)
			elif k == KEY_SPACE:
				_picker.activate_cursor()
			else:
				return
		Surface.CONFIRM:
			if k == KEY_SPACE:
				_on_disband_confirmed()
			else:
				return
		_:
			return

	# 走到这里说明这个键被消费了，标记一下阻止继续下传。
	get_viewport().set_input_as_handled()


## ESC 优先级链：CONFIRM → MENU → MOVE → PICKER → PICKER_ADD → DETAIL
##                → RIGHT（校验）→ LEFT（退出场景）
func _handle_escape() -> void:
	match _surface:
		Surface.CONFIRM:
			_on_disband_canceled()
		Surface.MENU:
			_set_surface(Surface.RIGHT)
		Surface.MOVE:
			# 取消移动，什么也不改（这就是「光标 + 确认」两步式的好处：没有痕迹要撤销）。
			_left.grid.exit_move_mode()
			_set_surface(Surface.RIGHT)
		Surface.PICKER:
			_picker.close()
			_set_surface(Surface.DETAIL)
		Surface.PICKER_ADD:
			_picker.close()
			_set_surface(Surface.RIGHT)
		Surface.DETAIL:
			_detail.close()
			_refresh_all()
			_set_surface(Surface.RIGHT)
		Surface.RIGHT:
			_try_leave_right()
		Surface.LEFT:
			# readme 没规定左侧按 ESC 干嘛，按最小惊讶原则：返回主场景。
			GameState.add_log("离开编队界面")
			get_tree().change_scene_to_file("res://Main.tscn")


# =====================================================================
#  十、提示条
# =====================================================================

## 弹一条淡出提示。is_error = true 用红色，false 用金色。
func _show_toast(msg: String, is_error: bool = true) -> void:
	_toast.text = msg
	_toast.add_theme_color_override("font_color",
		FormationSkin.RED if is_error else FormationSkin.GOLD)
	_toast.modulate.a = 1.0
	# 停 1.6 秒再用 0.8 秒淡出。create_tween 造的补间会自己回收。
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8).set_delay(1.6)
