extends SceneTree
## 开发用截图：godot --path . -s tools/capture.gd
## 主场景是 autoload（Main），这里直接取节点，在若干时间点/位置出图到 tools/captures/。
## 截图统一 1280x720（2 倍整数缩放），单张太小看不清，配合 tools/sheet.py 拼成一张大图再回看。

const OUT := "D:/pyFramework/hd-2d-walking/tools/captures"

const Proj = preload("res://scripts/proj.gd")

var main


func _init() -> void:
	_run()


func _run() -> void:
	for i in range(8):
		await process_frame
	main = root.get_node_or_null("Main")
	if main == null:
		print("CAPTURE ERROR: autoload Main 不存在")
		quit()
		return

	await _shot("01_spawn_morning", 0.30, 62.0, 80.0)
	await _shot("02_village_noon", 0.50, 48.0, 66.0)
	await _shot("03_village_dusk", 0.73, 44.0, 68.0)
	await _shot("04_village_night", 0.94, 48.0, 66.0)
	await _shot("05_windmill", 0.42, 72.0, 54.0)
	await _shot("06_farm_barn", 0.46, 116.0, 66.0)
	await _shot("07_lake", 0.38, 148.0, 82.0)
	await _shot("08_highland_ridge", 0.36, 70.0, 26.0)
	await _shot("09_shrine_torii", 0.40, 84.0, 12.0)
	await _shot("10_south_mound", 0.34, 58.0, 94.0)
	await _shot("11_pine_forest", 0.32, 20.0, 20.0)
	await _shot("12_slope_up", 0.44, 90.0, 84.0)
	# 台地边界：x=46 那条通道在 y=23 / y=17 / y=12 各升一级，
	# 站在边界南侧一眼能看见三级台阶和崖壁 —— "上下坡"得真的拍出来。
	await _shot("12b_terrace_low", 0.40, 46.0, 26.0)
	await _shot("12c_terrace_high", 0.40, 46.0, 15.0)

	# 上坡：沿 x=46 的通道一路向北（y 33 -> 3，高度 0 -> 3，全程无阻挡）。
	# 断言必须落在**高度**上。上一版写成 "h1 > h0 or y 变小了"，结果 STEP_UP 只有 0.1、
	# 任何一级台阶都上不去，角色只在平地上滑了一段，测试照样打勾 —— 位置断言证明不了爬坡。
	await _climb_check(46.0, 33.0)

	# 遮挡：角色在物件的北侧必须被挡住，走到南侧必须盖住它。
	# 这条是需求里明写的，靠肉眼看截图不算数，所以把 z 序断言出来。
	#
	# 特意选 96px 高的松树而不是房子：房子占地 5x5，角色最近只能站到 3 格外，
	# 那时两者的贴图在屏幕上几乎不重叠，"谁挡谁"根本看不出来，断言等于白写。
	# 松树只占脚下 1 格，可以站到贴图正面重叠的位置，遮挡才真的发生。
	await _occlusion_check(164.0, 37.0, 96.0)

	quit()


func _occlusion_check(ox: float, oy: float, sprite_h: float) -> void:
	var oh: int = main.data.height_at(int(ox), int(oy))
	var z_obj: int = Proj.depth(oy, float(oh))

	await _shot("14_occlude_behind", 0.42, ox, oy - 1.0)
	var z_north: int = main.player.z_index
	await _shot("15_occlude_front", 0.42, ox, oy + 1.0)
	var z_south: int = main.player.z_index

	var ok: bool = z_north < z_obj and z_south > z_obj
	# 顺带确认"确实重叠"：物件贴图向上伸 sprite_h，角色约 32px 高，相邻 1 格 = 16px，
	# 所以身体必然压在物件贴图范围内。不重叠的话测试就没意义了。
	print("OCCLUSION CHECK: 物件 z=%d 高=%.0fpx | 角色北侧 z=%d (需 <) | 南侧 z=%d (需 >)  %s"
		% [z_obj, sprite_h, z_north, z_south, "OK" if ok else "FAIL"])


func _climb_check(x: float, y0: float) -> void:
	main.set_time(0.44)
	main.teleport(x, y0)
	for i in range(3):
		await process_frame
	var h0: int = main.data.height_at(int(x), int(y0))
	var y_start: float = main.player_pos().y

	# 必须等 physics_frame，不能等 process_frame：_physics_process 是固定步长，
	# 渲染帧却随负载浮动，两者比例不稳定，同样 1500 帧有时走 30 格、有时走 3 格，
	# 测试会随机翻脸。
	#
	# 另外 action_press 不是立刻生效的，而且长时间奔跑会被"松开"，
	# 所以要周期性重按；否则会拍到角色原地不动、测试随机 FAIL。
	Input.action_press(&"move_up")
	var y_target := y0 - 30.0
	var frames := 0
	var stall := 0
	var last_y := y_start
	while frames < 20000 and stall < 600:
		if frames % 30 == 0:
			Input.action_press(&"move_up")
		await physics_frame
		frames += 1
		var cy: float = main.player_pos().y
		if cy < y_target:
			break
		if absf(cy - last_y) < 0.001:
			stall += 1
		else:
			stall = 0
			last_y = cy
	Input.action_release(&"move_up")

	var p: Vector2 = main.player_pos()
	var h1: int = main.data.height_at(int(p.x), int(p.y))
	await _shot("13_after_climb", 0.44, p.x, p.y)

	var climbed: bool = h1 > h0
	var advanced: bool = p.y < y_start - 10.0
	print("CLIMB CHECK: h %d -> %d, y %.1f -> %.1f (%d 帧, 停滞 %d)  %s"
		% [h0, h1, y_start, p.y, frames, stall,
		"OK" if (climbed and advanced) else
		"FAIL (爬升=%s 前进=%s)" % [str(climbed), str(advanced)]])


func _shot(name: String, t: float, tx: float, ty: float) -> void:
	main.set_time(t)
	main.teleport(tx, ty)
	# 关掉相机平滑：teleport 只 snap 一次，但跟随逻辑每帧还会 lerp，
	# 平滑没收敛就截图会拍到"世界边缘的黑边"这类根本不存在的现象。
	main.camera.position_smoothing_enabled = false
	for i in range(3):
		await process_frame
	main.camera.position_smoothing_enabled = true
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(path)
	print("captured: ", path)
