## 大地图美术底图生成器（一次性工具，headless 运行）。
## 用法：godot --headless --path . -s tools/gen_map_bg.gd
## 生成 res://assets/map_bg.png（噪声地形：平原/草地/森林/丘陵/山脉/湖泊，带色差）。
## 日后换成真实美术资源时直接覆盖该 PNG 或改 MapView 的加载路径。
extends SceneTree

const OUT_PATH := "res://assets/map_bg.png"
const W := 1600
const H := 800

func _init() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.seed = 20260809
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.55
	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.05
	detail.seed = 7
	# 调色板（地形色，均可后期替换）
	var water := Color("274b6b")
	var plains := Color("5b8a5a")
	var grass := Color("48764a")
	var forest := Color("33593c")
	var hills := Color("6d5c45")
	var mtn := Color("8a8f98")
	var snow := Color("cdd3da")
	for y in range(H):
		for x in range(W):
			var n := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			var d := (detail.get_noise_2d(x, y) + 1.0) * 0.5
			var c := plains
			if n < 0.30:
				c = water
			elif n < 0.42:
				c = plains.lerp(grass, d)
			elif n < 0.58:
				c = grass.lerp(forest, d * 0.6)
			elif n < 0.72:
				c = forest
			elif n < 0.84:
				c = hills.lerp(mtn, d * 0.8)
			else:
				c = mtn.lerp(snow, d)
			# 湖面零星点缀（纯陆地地图也有水色点缀）
			if n < 0.26 and n > 0.22:
				c = water.lightened(0.08)
			img.set_pixel(x, y, c)
	img.save_png(OUT_PATH)
	print("map_bg.png generated: ", OUT_PATH)
	quit()
