extends SceneTree
## 定向排查脚本：同一地点、同一时刻，切换可疑因素各出一张图。
## godot --path . -s tools/exp.gd

const OUT := "D:/pyFramework/hd-2d-walking/tools/_scratch/exp"

var main


func _init() -> void:
	_run()


func _run() -> void:
	for i in range(8):
		await process_frame
	main = root.get_node_or_null("Main")
	if main == null:
		print("EXP ERROR: no Main")
		quit()
		return
	DirAccess.make_dir_recursive_absolute(OUT)

	main.teleport(48.0, 66.0)
	main.set_time(0.30)

	main.shadows.visible = false
	await _shot("01_noshadow")

	main.shadows.visible = true
	await _shot("02_shadow_sun30")

	# 影子参数直接读出来看
	var arc: Dictionary = main.daynight._celestial()
	print("EXP celestial t=0.30 -> s=%.3f t=%.3f" % [arc["s"], arc["t"]])
	main.set_time(0.50)
	arc = main.daynight._celestial()
	print("EXP celestial t=0.50 -> s=%.3f t=%.3f" % [arc["s"], arc["t"]])

	# 放大看细节
	main.set_time(0.32)
	main.camera.zoom = Vector2(2.5, 2.5)
	main.camera.position_smoothing_enabled = false
	await _wait(3)
	await _shot("03_zoom_shadow")

	main.shadows.visible = false
	await _wait(3)
	await _shot("04_zoom_noshadow")

	main.camera.zoom = Vector2.ONE
	main.set_time(0.94)
	await _wait(3)
	await _shot("05_night_lamp")

	quit()


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	await _wait(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	print("exp: ", name)
