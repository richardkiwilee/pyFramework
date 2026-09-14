extends SceneTree
## 性能与移动基准：godot --path . -s tools/bench.gd
##
## 两件事：
##   1. 四方向位移断言 —— 只截图不算数，得证明角色真的动了。
##   2. 在最拥挤的地段（村庄）连续行走时测帧率与绘制开销。
##
## 注意：必须带窗口跑，加 --headless 就没有渲染，帧率数字全是假的。

const DIRECTIONS := {
	"move_up": Vector2(0.0, -1.0),
	"move_down": Vector2(0.0, 1.0),
	"move_left": Vector2(-1.0, 0.0),
	"move_right": Vector2(1.0, 0.0),
}

var main


func _init() -> void:
	_run()


func _run() -> void:
	for i in range(8):
		await process_frame
	main = root.get_node_or_null("Main")
	if main == null:
		print("BENCH ERROR: autoload Main 不存在")
		quit()
		return

	await _movement()
	await _fps()
	quit()


## 每个方向按固定物理帧数走一段，断言位移方向和量级都对
func _movement() -> void:
	var ok := true
	var parts: Array[String] = []
	for action in DIRECTIONS:
		# (157,26) 是全图四向净空最大的点（各方向 ≥14 格无障碍）——
		# 随便挑个"看起来空旷"的地方会被树挡住，测出来是碰撞不是移动。
		main.teleport(157.0, 26.0)
		for i in range(3):
			await physics_frame
		var p0: Vector2 = main.player_pos()

		Input.action_press(action)
		for i in range(150):
			if i % 30 == 0:
				Input.action_press(action)   # 长按会被松开，周期重按
			await physics_frame
		Input.action_release(action)

		var d: Vector2 = main.player_pos() - p0
		var want: Vector2 = DIRECTIONS[action]
		var along: float = d.dot(want)
		var across: float = absf(d.dot(Vector2(-want.y, want.x)))
		# 沿目标方向至少走 5 格，横向漂移不超过 0.5 格
		var good: bool = along > 5.0 and across < 0.5
		ok = ok and good
		parts.append("%s 前进%.1f格 横漂%.2f" % [action, along, across])

	print("BENCH 移动: ", " | ".join(parts), "  ->  ", "OK" if ok else "FAIL")


## 在村里来回走，取样帧率
func _fps() -> void:
	main.teleport(48.0, 66.0)
	main.set_time(0.42)
	for i in range(20):
		await process_frame

	var samples: Array[float] = []
	Input.action_press("move_right")
	for i in range(600):
		if i % 30 == 0:
			Input.action_press("move_right")
		if i == 300:
			Input.action_release("move_right")
			Input.action_press("move_left")
		await process_frame
		if i > 60:
			samples.append(Engine.get_frames_per_second())
	Input.action_release("move_left")

	samples.sort()
	var n := samples.size()
	var avg := 0.0
	for v in samples:
		avg += v
	avg /= maxf(float(n), 1.0)
	var p1: float = samples[int(n * 0.01)] if n > 0 else 0.0

	var obj_count: int = main.data.objects.size()
	var shadow_count: int = main.shadows.last_drawn
	var lights := 0
	for c in main.daynight.get_children():
		for g in c.get_children():
			if g is PointLight2D:
				lights += 1

	print("BENCH 规模: 物件 %d | 本帧影子 %d | 点光 %d | 地形带 %d"
		% [obj_count, shadow_count, lights, main.data.bands.size()])
	print("BENCH 帧率: 平均 %.1f | 1%% 低帧 %.1f | 最低 %.1f"
		% [avg, p1, samples[0] if n > 0 else 0.0])
	print("BENCH 绘制: draw_calls=%d | 顶点=%d | 可见节点=%d"
		% [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
