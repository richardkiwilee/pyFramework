extends SceneTree
## 状态探针：把角色/相机/贴图的实际数值打出来，别靠截图猜。
## godot --path . -s tools/probe.gd

func _init() -> void:
	for i in range(8):
		await process_frame
	var m = root.get_node_or_null("Main")
	if m == null:
		print("PROBE: no Main")
		quit()
		return

	m.set_time(0.42)
	m.teleport(63.0, 66.0)
	for i in range(4):
		await process_frame
	m.camera.position_smoothing_enabled = false
	for i in range(4):
		await process_frame

	var pl = m.player
	var sp = pl.get_node_or_null("") if false else null
	print("PROBE player.pos      = ", pl.pos)
	print("PROBE player.position = ", pl.position)
	print("PROBE vis_h/target_h  = ", pl.vis_h, " / ", pl.target_h)
	print("PROBE z_index         = ", pl.z_index)
	print("PROBE screen_pos()    = ", pl.screen_pos())
	print("PROBE camera.position = ", m.camera.position)
	print("PROBE camera limits   = ", m.camera.limit_left, " ", m.camera.limit_top,
		" ", m.camera.limit_right, " ", m.camera.limit_bottom)
	print("PROBE camera zoom     = ", m.camera.zoom)
	print("PROBE viewport size   = ", root.get_visible_rect().size)

	# 精灵本体
	for c in pl.get_children():
		if c is Sprite2D:
			print("PROBE sprite: name=", c.name, " visible=", c.visible,
				" centered=", c.centered, " tex=", c.texture,
				" pos=", c.position, " z=", c.z_index,
				" modulate=", c.modulate, " scale=", c.scale)
			if c.texture != null:
				print("PROBE sprite tex size = ", c.texture.get_size())
			print("PROBE sprite global   = ", c.global_position)
			print("PROBE sprite rect     = pos .. pos+size = ",
				c.position, " .. ", c.position + c.texture.get_size() if c.texture else "?")
	print("PROBE player visible  = ", pl.visible, " modulate=", pl.modulate)

	# 相机实际看到的世界矩形
	var vp: Vector2 = root.get_visible_rect().size
	var half: Vector2 = vp * 0.5 / m.camera.zoom
	print("PROBE view rect       = ", Rect2(m.camera.position - half, half * 2.0))

	quit()
