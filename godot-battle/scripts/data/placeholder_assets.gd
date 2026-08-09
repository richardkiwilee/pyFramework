# placeholder_assets.gd
# Autoload — 程序化生成占位符素材
# 当外部素材未下载时，使用此脚本生成的占位符
extends Node

const BLUE_COLOR = Color("#4488ff")
const RED_COLOR = Color("#ff4444")
const GOLD_COLOR = Color("#ffd700")
const HEAL_COLOR = Color("#44ff44")
const DARK_BG = Color("#1a1a2e")

# 角色颜色映射（按职业）
const CLASS_COLORS = {
	"knight": Color("#4488ff"),       # 骑士 - 蓝
	"mage": Color("#aa44ff"),          # 法师 - 紫
	"archer": Color("#44cc44"),        # 弓手 - 绿
	"cleric": Color("#ffffff"),        # 牧师 - 白
	"thief": Color("#888888"),         # 盗贼 - 灰
	"tank": Color("#886644"),          # 重甲 - 棕
	"soldier": Color("#ff8844"),       # 枪兵 - 橙
	"dark_knight": Color("#cc2222"),   # 暗骑 - 深红
	"berserker": Color("#ff2222"),     # 狂战 - 红
}

# 职业形状
const CLASS_SHAPES = {
	"knight": "diamond",       # 菱形
	"mage": "circle",          # 圆形
	"archer": "triangle",      # 三角形
	"cleric": "cross",         # 十字
	"thief": "star",           # 星形
	"tank": "square",          # 正方形
	"soldier": "hexagon",      # 六边形
	"dark_knight": "diamond",
	"berserker": "triangle",
}


# 生成单位占位符精灵（ImageTexture）
func generate_unit_sprite(cls: String, team: String, size: Vector2 = Vector2(128, 128)) -> ImageTexture:
	var image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var center = size / 2
	var body_color = CLASS_COLORS.get(cls, Color.GRAY)
	var team_tint = BLUE_COLOR if team == "blue" else RED_COLOR
	var shape = CLASS_SHAPES.get(cls, "circle")

	# 绘制阴影/底座
	_draw_ellipse(image, center + Vector2(0, 20), Vector2(35, 12), Color.BLACK)

	# 绘制身体（按形状）
	match shape:
		"circle":
			_draw_ellipse(image, center, Vector2(30, 30), body_color)
		"square":
			_draw_rect(image, Rect2i(center.x - 25, center.y - 30, 50, 50), body_color)
		"triangle":
			_draw_triangle(image, center + Vector2(0, -30), center + Vector2(-30, 25), center + Vector2(30, 25), body_color)
		"diamond":
			_draw_diamond(image, center, Vector2(30, 35), body_color)
		"cross":
			_draw_cross(image, center, 30, 12, body_color)
		"star":
			_draw_star(image, center, 28, 14, body_color)
		"hexagon":
			_draw_hexagon(image, center, 28, body_color)
		_:
			_draw_ellipse(image, center, Vector2(28, 28), body_color)

	# 绘制队伍标识（底部色带）
	var band_rect = Rect2i(center.x - 25, center.y + 40, 50, 8)
	for x in range(band_rect.position.x, band_rect.position.x + band_rect.size.x):
		for y in range(band_rect.position.y, band_rect.position.y + band_rect.size.y):
			if x >= 0 and x < size.x and y >= 0 and y < size.y:
				image.set_pixel(x, y, team_tint)

	# 绘制职业首字母
	_draw_pixel_letter(image, center - Vector2(6, 8), cls[0].to_upper(), Color.WHITE)

	var texture = ImageTexture.create_from_image(image)
	return texture


# 绘制实心椭圆
func _draw_ellipse(img: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	for x in range(max(0, int(center.x - radius.x)), min(img.get_width(), int(center.x + radius.x + 1))):
		for y in range(max(0, int(center.y - radius.y)), min(img.get_height(), int(center.y + radius.y + 1))):
			var dx = (x - center.x) / radius.x
			var dy = (y - center.y) / radius.y
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, color)


# 绘制矩形
func _draw_rect(img: Image, rect: Rect2i, color: Color) -> void:
	for x in range(max(0, rect.position.x), min(img.get_width(), rect.position.x + rect.size.x)):
		for y in range(max(0, rect.position.y), min(img.get_height(), rect.position.y + rect.size.y)):
			img.set_pixel(x, y, color)


# 绘制三角形
func _draw_triangle(img: Image, p1: Vector2, p2: Vector2, p3: Vector2, color: Color) -> void:
	var min_x = max(0, int(min(p1.x, p2.x, p3.x)))
	var max_x = min(img.get_width(), int(max(p1.x, p2.x, p3.x) + 1))
	var min_y = max(0, int(min(p1.y, p2.y, p3.y)))
	var max_y = min(img.get_height(), int(max(p1.y, p2.y, p3.y) + 1))

	for x in range(min_x, max_x):
		for y in range(min_y, max_y):
			if _point_in_triangle(Vector2(x, y), p1, p2, p3):
				img.set_pixel(x, y, color)


# 绘制菱形
func _draw_diamond(img: Image, center: Vector2, sz: Vector2, color: Color) -> void:
	var half_x = int(sz.x)
	var half_y = int(sz.y)
	for x in range(max(0, int(center.x - half_x)), min(img.get_width(), int(center.x + half_x + 1))):
		for y in range(max(0, int(center.y - half_y)), min(img.get_height(), int(center.y + half_y + 1))):
			var dx = abs(x - center.x) / sz.x
			var dy = abs(y - center.y) / sz.y
			if dx + dy <= 1.0:
				img.set_pixel(x, y, color)


# 绘制十字
func _draw_cross(img: Image, center: Vector2, sz: float, thickness: float, color: Color) -> void:
	var h_rect = Rect2i(center.x - sz, center.y - thickness / 2.0, sz * 2, thickness)
	var v_rect = Rect2i(center.x - thickness / 2.0, center.y - sz, thickness, sz * 2)
	_draw_rect(img, h_rect, color)
	_draw_rect(img, v_rect, color)


# 绘制星形
func _draw_star(img: Image, center: Vector2, outer_r: float, inner_r: float, color: Color) -> void:
	for x in range(max(0, int(center.x - outer_r)), min(img.get_width(), int(center.x + outer_r + 1))):
		for y in range(max(0, int(center.y - outer_r)), min(img.get_height(), int(center.y + outer_r + 1))):
			var dx = x - center.x
			var dy = y - center.y
			var dist = sqrt(dx * dx + dy * dy)
			var angle = atan2(dy, dx)
			var star_r = _star_radius(angle, outer_r, inner_r, 5)
			if dist <= star_r:
				img.set_pixel(x, y, color)


func _star_radius(angle: float, outer: float, inner: float, points: int) -> float:
	var sector = TAU / (points * 2)
	var a = fmod(angle + TAU, TAU)
	var sector_idx = floor(a / sector)
	if int(sector_idx) % 2 == 0:
		return outer
	return inner


# 绘制六边形
func _draw_hexagon(img: Image, center: Vector2, radius: float, color: Color) -> void:
	for x in range(max(0, int(center.x - radius)), min(img.get_width(), int(center.x + radius + 1))):
		for y in range(max(0, int(center.y - radius)), min(img.get_height(), int(center.y + radius + 1))):
			var dx = abs(x - center.x)
			var dy = abs(y - center.y)
			if dx * 0.866 + dy * 0.5 <= radius and dy <= radius * 0.866:
				img.set_pixel(x, y, color)


# 简单像素字母绘制（仅支持大写）
func _draw_pixel_letter(img: Image, pos: Vector2, letter: String, color: Color) -> void:
	var patterns = {
		"A": [" ## ", "#  #", "####", "#  #", "#  #"],
		"B": ["### ", "#  #", "### ", "#  #", "### "],
		"C": [" ## ", "#   ", "#   ", "#   ", " ## "],
		"D": ["### ", "#  #", "#  #", "#  #", "### "],
		"F": ["####", "#   ", "### ", "#   ", "#   "],
		"G": [" ## ", "#   ", "# ##", "#  #", " ## "],
		"H": ["#  #", "#  #", "####", "#  #", "#  #"],
		"K": ["#  #", "# # ", "##  ", "# # ", "#  #"],
		"M": ["#   #", "## ##", "# # #", "#   #", "#   #"],
		"R": ["### ", "#  #", "### ", "# # ", "#  #"],
		"S": [" ## ", "#   ", " ## ", "   #", " ## "],
		"T": ["####", "  # ", "  # ", "  # ", "  # "],
		"W": ["#   #", "#   #", "# # #", "## ##", "#   #"],
	}

	var pattern = patterns.get(letter, [" ?? ", "#  #", "####", "#  #", "#  #"])
	for row in range(pattern.size()):
		var line = pattern[row]
		for col in range(line.length()):
			var px = int(pos.x) + col * 2
			var py = int(pos.y) + row * 2
			if line[col] == "#":
				for dx in range(2):
					for dy in range(2):
						var sx = px + dx
						var sy = py + dy
						if sx >= 0 and sx < img.get_width() and sy >= 0 and sy < img.get_height():
							img.set_pixel(sx, sy, color)


# 判断点是否在三角形内
func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 = _sign(p, a, b)
	var d2 = _sign(p, b, c)
	var d3 = _sign(p, c, a)
	var has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


func _sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


# 生成UI占位符素材
func generate_button_texture(text: String, width: int = 200, height: int = 50, base_color: Color = Color("#334466")) -> ImageTexture:
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)

	# 填充背景
	for x in range(width):
		for y in range(height):
			var edge = (x < 2 or x >= width - 2 or y < 2 or y >= height - 2)
			var col = base_color.lightened(0.2) if edge else base_color
			image.set_pixel(x, y, col)

	var texture = ImageTexture.create_from_image(image)
	return texture


# 生成特效占位符（简单的渐变圆形）
func generate_effect_sprite(effect_type: String, sz: int = 64) -> ImageTexture:
	var image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var center = Vector2(sz / 2.0, sz / 2.0)
	var effect_colors = {
		"slash": Color("#ffffff"),
		"fire": Color("#ff6622"),
		"ice": Color("#66ccff"),
		"heal": Color("#44ff88"),
		"shield": Color("#ffdd44"),
	}
	var col = effect_colors.get(effect_type, Color.WHITE)

	for x in range(sz):
		for y in range(sz):
			var dist = (Vector2(x, y) - center).length()
			var max_dist = sz / 2.0
			if dist < max_dist:
				var alpha = 1.0 - (dist / max_dist)
				image.set_pixel(x, y, Color(col, alpha))

	var texture = ImageTexture.create_from_image(image)
	return texture


## 运行时获取单位精灵（不保存到磁盘，直接在内存中使用）
func get_unit_texture(cls: String, team: String) -> ImageTexture:
	return generate_unit_sprite(cls, team)


## 运行时获取圆形头像（用于速度条等小图标）
func get_unit_portrait(cls: String, team: String) -> ImageTexture:
	var sz = Vector2(48, 48)
	var image = Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var center = sz / 2
	var body_color = CLASS_COLORS.get(cls, Color.GRAY)
	var team_tint = BLUE_COLOR if team == "blue" else RED_COLOR
	var shape = CLASS_SHAPES.get(cls, "circle")

	# 背景圆形（队伍颜色）
	for x in range(4, 44):
		for y in range(4, 44):
			var dx = x - center.x
			var dy = y - center.y
			if dx * dx + dy * dy <= 21 * 21:
				image.set_pixel(x, y, team_tint.darkened(0.4))

	# 内部形状
	match shape:
		"circle":
			_draw_ellipse(image, center, Vector2(14, 14), body_color)
		"square":
			_draw_rect(image, Rect2i(center.x - 11, center.y - 12, 22, 22), body_color)
		"triangle":
			_draw_triangle(image, center + Vector2(0, -14), center + Vector2(-14, 11), center + Vector2(14, 11), body_color)
		"diamond":
			_draw_diamond(image, center, Vector2(13, 15), body_color)
		"cross":
			_draw_cross(image, center, 13, 5, body_color)
		"star":
			_draw_star(image, center, 12, 6, body_color)
		"hexagon":
			_draw_hexagon(image, center, 12, body_color)
		_:
			_draw_ellipse(image, center, Vector2(13, 13), body_color)

	return ImageTexture.create_from_image(image)


## 运行时获取状态图标
func get_status_icon(status_type: String) -> ImageTexture:
	var sz = Vector2(24, 24)
	var image = Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var colors = {
		"poison": Color("#8844cc"),
		"burn": Color("#ff4422"),
		"freeze": Color("#66aaff"),
		"stun": Color("#ffcc00"),
	}

	var col = colors.get(status_type, Color.WHITE)
	for x in range(4, 20):
		for y in range(4, 20):
			var dx = x - 12.0
			var dy = y - 12.0
			if dx * dx + dy * dy <= 64:
				image.set_pixel(x, y, col)

	return ImageTexture.create_from_image(image)


## 获取职业颜色
func get_class_color(cls: String) -> Color:
	return CLASS_COLORS.get(cls, Color.GRAY)


## 获取队伍颜色
func get_team_color(team: String) -> Color:
	return BLUE_COLOR if team == "blue" else RED_COLOR


# 生成所有占位符素材并保存到磁盘
func generate_all_placeholders() -> void:
	var base_path = "res://assets/"
	var dirs = ["sprites/units", "ui", "effects"]

	# 确保目录存在
	for d in dirs:
		DirAccess.make_dir_recursive_absolute(base_path + d)

	# 生成双方角色精灵
	for cls in CLASS_COLORS.keys():
		for team in ["blue", "red"]:
			var texture = generate_unit_sprite(cls, team)
			var path = base_path + "sprites/units/" + team + "_" + cls + ".png"
			var img = texture.get_image()
			img.save_png(path)

	# 生成UI素材
	for btn_name in ["button_normal", "button_hover", "button_pressed"]:
		var texture = generate_button_texture(btn_name)
		var img = texture.get_image()
		img.save_png(base_path + "ui/" + btn_name + ".png")

	# 生成特效素材
	for effect in ["slash", "fire", "ice", "heal", "shield"]:
		var texture = generate_effect_sprite(effect)
		var img = texture.get_image()
		img.save_png(base_path + "effects/" + effect + ".png")

	print("Placeholder assets generated successfully!")
