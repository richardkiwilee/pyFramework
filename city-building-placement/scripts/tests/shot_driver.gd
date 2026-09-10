extends Node
## 截图验证驱动（工具脚本，不常驻）。
## 用法：临时把 `ShotDriver="*res://scripts/tests/shot_driver.gd"` 加进 project.godot 的 [autoload]，
## 窗口模式运行一次，截图输出到 _shots/，验证后移除该 autoload 行。
## 窗口移到屏幕外以隔绝真实鼠标输入；合成输入、切换 UI 状态、逐帧截图 + 像素断言。

var _fail_count: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	# 移出屏幕，真实鼠标/点击无法干扰
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	for i in 30:
		await get_tree().process_frame
	var ui: Node = get_node("/root/Main/UI/Root")
	var camera: Node = get_node("/root/Main/Camera")
	var cs: Node = get_node("/root/CityState")
	var shots_dir: String = ProjectSettings.globalize_path("res://_shots")
	DirAccess.make_dir_recursive_absolute(shots_dir)
	print("POS center=", _pos(camera, Vector2i(0, 0)))
	print("POS (0,-1)=", _pos(camera, Vector2i(0, -1)))
	print("POS (3,0)=", _pos(camera, Vector2i(3, 0)))
	print("POS (-2,3)=", _pos(camera, Vector2i(-2, 3)))
	print("POS (1,1)=", _pos(camera, Vector2i(1, 1)))

	# 01 初始：顶栏 + 地形
	await _shot("01_initial")
	var c: Color = _px(640, 24)
	_check(c.r > 0.098 and c.r < 0.275 and c.g > 0.137 and c.g < 0.314, "顶栏深色面板 (640,24)=%s" % c)
	c = _px(640, 360)
	_check(c.r > 0.39 and c.g > 0.39 and c.b > 0.39 and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < 0.157, "市中心灰白塔 (640,360)=%s" % c)
	c = _px_at(_pos(camera, Vector2i(0, -1)))
	_check(c.g > c.r + 0.117 and c.g > c.b + 0.157 and c.g > 0.35, "平原绿色 (0,-1)=%s" % c)
	c = _px_at(_pos(camera, Vector2i(3, 0)))
	_check(c.b > c.r + 0.157 and c.b > 0.55, "水域蓝色 (3,0)=%s" % c)
	c = _px_at(_pos(camera, Vector2i(-2, 3)))
	_check(maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) < 0.118 and c.r > 0.30 and c.r < 0.62, "高山灰 (侧面, -2,3)=%s" % c)

	# 02 悬停可开拓格（黄色）
	await _mouse_move(_pos(camera, Vector2i(1, 1)))
	await _shot("02_hover_expandable")
	c = _px_at(_pos(camera, Vector2i(1, 1)))
	_check(c.r > 0.51 and c.g > 0.59 and c.b < 0.47, "悬停黄色高亮 (1,1)=%s" % c)

	# 03 点击 -> 开拓确认框
	await _mouse_click(_pos(camera, Vector2i(1, 1)))
	await _shot("03_expand_confirm")
	_check(bool(ui.get("expand_overlay").get("visible")), "开拓确认框打开")
	c = _px(640, 360)
	_check(c.r < 60.0 and c.g < 75.0, "确认框深色面板 (640,360)=%s" % c)
	ui.call("_on_expand_cancel")
	cs.call("expand", Vector2i(1, 1))

	# 04 小城：多建筑 + 升级装饰
	cs.call("add_resources_debug", 1000)
	for cell: Vector2i in [Vector2i(2, 0), Vector2i(2, -1), Vector2i(0, 2), Vector2i(-2, 1), Vector2i(-2, 2), Vector2i(-3, 1), Vector2i(-1, 2)]:
		_check(bool(cs.call("expand", cell)), "开拓 %s 成功" % cell)
	_check(bool(cs.call("build", Vector2i(1, 1), "farm")), "建造农场")
	_check(bool(cs.call("build", Vector2i(2, 0), "mill")), "建造磨坊")
	_check(bool(cs.call("build", Vector2i(2, -1), "market")), "建造市场")
	_check(bool(cs.call("build", Vector2i(0, 1), "quarry")), "建造采石场")
	_check(bool(cs.call("build", Vector2i(-2, 2), "academy")), "建造学院")
	_check(bool(cs.call("build", Vector2i(-1, 0), "hut")), "建造小屋")
	_check(bool(cs.call("build", Vector2i(1, 0), "shop")), "建造商铺")
	_check(bool(cs.call("upgrade", Vector2i(1, 1))), "农场升级 Lv2")
	_check(bool(cs.call("upgrade", Vector2i(2, 0))), "磨坊升级 Lv2")
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("04_city")
	c = _px_at(_pos(camera, Vector2i(1, 1)))
	_check(c.r > 0.35 and c.r > c.g and c.g > c.b, "农场建筑(屋顶棕) (1,1)=%s" % c)

	# 05 三栏建造窗口
	ui.call("open_build_window", Vector2i(0, -1))
	await get_tree().process_frame
	await _shot("05_build_window")
	c = _px(640, 360)
	_check(c.r < 60.0 and c.g < 75.0, "建造窗口深色面板 (640,360)=%s" % c)
	var farm_btn: Button = ui.get("card_buttons").get("farm")
	var lum_btn: Button = ui.get("card_buttons").get("lumberyard")
	var market_btn: Button = ui.get("card_buttons").get("market")
	var farm_rect: Rect2 = farm_btn.get_global_rect()
	var lum_rect: Rect2 = lum_btn.get_global_rect()
	var market_rect: Rect2 = market_btn.get_global_rect()
	_check(absf(farm_rect.position.y - lum_rect.position.y) < 5.0, "农场/伐木场同行")
	_check(absf(farm_rect.position.y - market_rect.position.y) > 50.0, "市场在下一行")
	_check(lum_rect.position.x > farm_rect.position.x + 100.0, "伐木场在第5列（右移4列）")
	var icon: Vector2 = farm_rect.position + Vector2(farm_rect.size.x * 0.5, 18.0)
	c = _pxv(icon)
	_check(c.g > 0.55 and c.g > c.r + 0.12, "农场卡片图标=食物绿 %s" % c)

	# 06 详情：农场
	ui.call("select_card", "farm")
	await get_tree().process_frame
	await _shot("06_details_farm")
	_check(not bool(ui.get("bw_build_button").get("disabled")), "农场可建造（按钮启用）")

	# 06b 取消建造：窗口关闭、回到六边形地图
	ui.call("_on_cancel_build_pressed")
	await get_tree().process_frame
	await _shot("11_cancel_build")
	_check(not bool(ui.get("bw_overlay").get("visible")), "取消建造后窗口关闭回到地图")

	# 07 详情：学院（相邻高山不满足 -> 拒绝）
	ui.call("open_build_window", Vector2i(0, -1))
	ui.call("select_card", "academy")
	await get_tree().process_frame
	await _shot("07_details_academy_denied")
	_check(bool(ui.get("bw_build_button").get("disabled")), "学院被拒（按钮置灰）")
	ui.call("close_build_window")

	# 08/09 建筑弹窗 + 拆除二次确认
	ui.call("open_building_popup", Vector2i(1, 1))
	await get_tree().process_frame
	await _shot("08_building_popup")
	_check(bool(ui.get("bp_actions").get("visible")), "建筑弹窗操作行可见")
	ui.call("show_popup_demolish_confirm")
	await get_tree().process_frame
	await _shot("09_demolish_confirm")
	_check(bool(ui.get("bp_confirm_box").get("visible")), "拆除二次确认显示")
	ui.call("close_building_popup")

	# 09b 市中心弹窗（纯信息 + 关闭按钮）
	ui.call("open_building_popup", Vector2i.ZERO)
	await get_tree().process_frame
	await _shot("12_center_popup")
	_check(bool(ui.get("bp_close_row").get("visible")), "市中心弹窗关闭行可见")
	ui.call("_on_popup_close_pressed")
	await get_tree().process_frame
	_check(not bool(ui.get("bp_overlay").get("visible")), "市中心弹窗可关闭")

	# 10 未接壤点击 -> toast（(3,-3) 无任何接壤的已拥有地块）
	await _mouse_move(_pos(camera, Vector2i(3, -3)))
	await _mouse_click(_pos(camera, Vector2i(3, -3)))
	await get_tree().process_frame
	await _shot("10_toast")
	_check(bool(ui.get("toast_panel").get("visible")), "未接壤 toast 显示")

	if _fail_count == 0:
		print("SHOTS: 全部通过")
		get_tree().quit(0)
	else:
		push_error("SHOTS: %d 项失败" % _fail_count)
		get_tree().quit(1)


func _pos(camera: Node, cell: Vector2i) -> Vector2:
	return camera.call("cell_screen_pos", cell)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var dir: String = ProjectSettings.globalize_path("res://_shots")
	img.save_png(dir + "/" + name + ".png")
	print("SHOT %s" % name)


func _px(x: float, y: float) -> Color:
	return get_viewport().get_texture().get_image().get_pixel(int(x), int(y))


func _px_at(pos: Vector2) -> Color:
	return _px(pos.x, pos.y)


func _pxv(pos: Vector2) -> Color:
	return _px(pos.x, pos.y)


func _mouse_move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _mouse_click(pos: Vector2) -> void:
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	p.position = pos
	p.global_position = pos
	Input.parse_input_event(p)
	await get_tree().process_frame
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = pos
	r.global_position = pos
	Input.parse_input_event(r)
	await get_tree().process_frame
	await get_tree().process_frame


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS: %s" % label)
	else:
		_fail_count += 1
		print("  FAIL: %s" % label)
