## 启动入口：压入主菜单场景。
## 调试：`godot --headless --path . -- --ui-smoke` 跑 UI 冒烟（逐页面/窗口打开 + 直接调交互方法）。
extends Node

var _smoke_errors: Array = []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--ui-smoke"):
		_run_ui_smoke()
	else:
		SceneStack.change_scene(load("res://scenes/main_menu.tscn").instantiate())

# ---------- UI 冒烟 ----------
## headless 下输入事件会被 GUI 系统消费，故冒烟用直接调用式：
## 验证每个页面/窗口场景能独立构建、打开、关闭无错误；交互逻辑直接调方法。
func _run_ui_smoke() -> void:
	print("=== UI 冒烟测试 ===")
	# 主菜单构建
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	SceneStack.change_scene(menu)
	await _frames(3)
	_ok(SceneStack.main_scene is MainMenu, "主菜单构建")
	# 开始游戏（直接走按钮逻辑）
	menu.call("_start_game")
	await _frames(5)
	_ok(GameController.game != null, "开始游戏创建对局")
	# 开始回合可能触发事件弹窗（40% 概率）——先关掉
	if SceneStack.top_window() is EventDialog:
		SceneStack.close_window("event_chosen")
		await _frames(3)
	_ok(SceneStack.main_scene is GameScreen, "进入大地图主场景")
	var gs: GameScreen = SceneStack.main_scene
	# 地图数据：世界坐标缓存已填充（据点/道路/部队可见的前提）
	gs._map_view.call("_recompute_world")
	_ok(gs._map_view._screen.size() >= 8, "地图节点坐标已填充(据点可见)")
	# 全屏页面逐页打开/关闭（顶栏在其上，ESC 关闭）
	var pages: Array = ["tech_culture", "stronghold", "stronghold_overview",
		"army", "unit_roster", "inventory", "recruit", "recruit_unit", "map_screen"]
	for name in pages:
		gs.call("_open_page", load("res://scenes/windows/%s.tscn" % name).instantiate())
		await _frames(4)
		_ok(gs._pages.size() == 1, "打开页面 %s" % name)
		gs.call("_close_page")
		await _frames(3)
	_ok(gs._pages.is_empty(), "所有页面已关闭")
	# 科技/文化树：参数切换 + 学习（直接调方法）
	gs.call("_open_page", load("res://scenes/windows/tech_culture.tscn").instantiate(),
		{"kind": "tech"})
	await _frames(4)
	var tech: Node = gs._pages.back()
	tech.call("_set_kind", "culture", true)
	await _frames(2)
	tech.call("_do_learn")
	await _frames(2)
	gs.call("_close_page")
	await _frames(3)
	# 管理小队：切换待命页
	gs.call("_open_page", load("res://scenes/windows/army.tscn").instantiate())
	await _frames(4)
	var ap: Node = gs._pages.back()
	ap.call("_set_tab", 1, true)
	await _frames(2)
	gs.call("_close_page")
	await _frames(3)
	# 百科全屏页面（不再 change_scene，主场景保留）
	gs.call("_open_page", load("res://scenes/wiki.tscn").instantiate())
	await _frames(4)
	_ok(gs._pages.back() is WikiScreen, "百科全屏页面")
	gs.call("_close_page")
	await _frames(3)
	_ok(gs._pages.is_empty() and SceneStack.main_scene is GameScreen, "百科关闭后回到大地图")
	# 保持窗口形态的：日志 / 设置 / ESC 选单
	for name in ["log_window", "settings_window"]:
		var win: Window = load("res://scenes/windows/%s.tscn" % name).instantiate()
		SceneStack.open_window(win)
		await _frames(3)
		_ok(SceneStack.top_window() != null, "打开窗口 %s" % name)
		SceneStack.close_window()
		await _frames(3)
	# 大地图交互（直接调方法）：据点信息栏 + 建造浮层
	gs.call("_on_node_clicked", "p_cap")
	await _frames(2)
	_ok(gs._info_panel.visible, "点击据点显示底部信息栏")
	gs.call("_show_build_popup", "p_cap")
	await _frames(2)
	_ok(gs._build_popup.visible, "点槽位弹出建造选项")
	# 建造浮层：点击外部（遮罩区域）必须关闭
	var dim_rect: Control = gs._build_popup.get_child(0)
	var click_out := InputEventMouseButton.new()
	click_out.button_index = MOUSE_BUTTON_LEFT
	click_out.pressed = true
	click_out.position = Vector2(5, 5)
	dim_rect.emit_signal("gui_input", click_out)
	await _frames(1)
	_ok(not gs._build_popup.visible, "建造浮层点击外部关闭")
	gs.call("_on_node_clicked", "p_cap")
	await _frames(1)
	_ok(not gs._info_panel.visible, "再点据点关闭信息栏")
	# 建筑槽：点方块中心 ≠ 拆除；只有点右上角红×才拆除（端到端）
	gs.call("_on_node_clicked", "p_cap")
	await _frames(2)
	var sh: MapSystem.Stronghold = GameController.game.map.strongholds["p_cap"]
	var before_demo: int = sh.buildings.size()
	var built_slot: Control = null
	for ch in gs._slot_box.get_children():
		if ch is BuildingSlot and ch.state == BuildingSlot.State.BUILDING and not ch.is_landmark:
			built_slot = ch
			break
	_ok(built_slot != null, "信息栏中存在已建建筑槽")
	if built_slot != null:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = built_slot.size / 2.0
		built_slot.call("_gui_input", press)
		var rel := InputEventMouseButton.new()
		rel.button_index = MOUSE_BUTTON_LEFT
		rel.pressed = false
		rel.position = built_slot.size / 2.0
		built_slot.call("_gui_input", rel)
		await _frames(2)
		_ok(sh.buildings.size() == before_demo, "点方块中心不拆除(仅显示信息)")
		press.position = Vector2(built_slot.size.x - 12, 12)
		rel.position = Vector2(built_slot.size.x - 12, 12)
		built_slot.call("_gui_input", press)
		built_slot.call("_gui_input", rel)
		await _frames(2)
		_ok(sh.buildings.size() == before_demo - 1, "点右上角红×拆除建筑")
	# 部队地图移动（直接调动作）
	var aid: String = ""
	for a in GameController.game.armies:
		if GameController.game.armies[a].owner == GameController.game.player_id:
			aid = a
			break
	gs.call("_on_army_move", aid, "m1")
	await _frames(2)
	# 事件弹窗：点击选项 → 完成事件并关闭（直接调 _choose 验证路径）
	var ev := GameEvents.GameEvent.new("smoke_ev", "测试事件", "点击选项应完成事件并关闭",
		[GameEvents.EventOption.new("选项A", {"gold": 5}), GameEvents.EventOption.new("选项B")])
	GameController.game.pending_event = ev
	SceneStack.open_window(load("res://scenes/windows/event_dialog.tscn").instantiate(), ev)
	await _frames(3)
	_ok(SceneStack.top_window() is EventDialog, "事件弹窗打开")
	SceneStack.top_window().call("_choose", 0)
	await _frames(3)
	_ok(SceneStack.top_window() == null, "点击选项后事件完成并关闭")
	_ok(GameController.game.pending_event == null, "事件已结算")
	# ESC 选单（保持窗口；直接关闭不回主菜单，后续断言仍在大地图）
	SceneStack.open_window(load("res://scenes/windows/esc_menu.tscn").instantiate())
	await _frames(3)
	_ok(SceneStack.top_window() is EscMenu, "ESC 选单打开")
	SceneStack.close_window()
	await _frames(3)
	# 结束回合
	GameController.run_ai_and_advance()
	await _frames(4)
	if SceneStack.top_window() is EventDialog:
		SceneStack.close_window("event_chosen")
		await _frames(3)
	if SceneStack.top_window() is Message:
		SceneStack.close_window()
		await _frames(3)
	_ok(GameController.game.calendar.day >= 2, "结束回合后天数推进")
	print("=== UI 冒烟结束，错误 %d ===" % _smoke_errors.size())
	for e in _smoke_errors:
		print("FAIL: ", e)
	get_tree().quit(1 if not _smoke_errors.is_empty() else 0)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _ok(cond: bool, msg: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	if not cond:
		_smoke_errors.append(msg)
