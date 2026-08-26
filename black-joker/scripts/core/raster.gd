class_name Raster
extends RefCounted
## =============================================================================
## Raster — CPU Image 光栅化工具集（牌背/牌面共用）
## =============================================================================
## Godot 的 Image 只有 set_pixel/fill_rect，没有画圆/多边形/文字 API；
## Font.draw_string 需要 CanvasItem RID（headless 不可用）。因此全部手写：
## 圆、线、多边形扫描线填充、花色符号、5×7 点阵字体（A/2-10/J/Q/K 够用）。
## =============================================================================

# 5×7 点阵字体（每字符 7 行，每行 5 位，bit4 在最左）
const GLYPHS := {
	"0": [14, 17, 19, 21, 25, 17, 14],
	"1": [4, 12, 4, 4, 4, 4, 14],
	"2": [14, 17, 1, 2, 4, 8, 31],
	"3": [31, 2, 4, 2, 1, 17, 14],
	"4": [2, 6, 10, 18, 31, 2, 2],
	"5": [31, 16, 30, 1, 1, 17, 14],
	"6": [6, 8, 16, 30, 17, 17, 14],
	"7": [31, 1, 2, 4, 8, 8, 8],
	"8": [14, 17, 17, 14, 17, 17, 14],
	"9": [14, 17, 17, 15, 1, 2, 12],
	"A": [14, 17, 17, 31, 17, 17, 17],
	"J": [7, 2, 2, 2, 2, 18, 12],
	"Q": [14, 17, 17, 17, 21, 18, 13],
	"K": [17, 18, 20, 24, 20, 18, 17],
}


## 画一个 5×7 点阵文本（每个字符占 6 像素宽：5 字形 + 1 间距）
static func draw_bitmap_text(img: Image, text: String, x: int, y: int, scale: int, color: Color) -> void:
	var cursor := x
	for ch in text:
		var rows: Array = GLYPHS.get(ch, [])
		for row_i in rows.size():
			var bits: int = rows[row_i]
			for col in range(5):
				if bits & (1 << (4 - col)):
					img.fill_rect(Rect2i(
						cursor + col * scale,
						y + row_i * scale,
						scale, scale), color)
		cursor += 6 * scale


static func fill_circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(cx + dx, cy + dy, color)


static func stroke_circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	var r_in := r - 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d2 := dx * dx + dy * dy
			if d2 <= r * r and d2 >= r_in * r_in:
				img.set_pixel(cx + dx, cy + dy, color)


static func stroke_line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	# Bresenham（越界像素跳过——斜纹线会延伸到图外，set_pixel 越界会刷错误日志）
	var w := img.get_width()
	var h := img.get_height()
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		if x >= 0 and x < w and y >= 0 and y < h:
			img.set_pixel(x, y, color)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


static func stroke_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	stroke_line(img, x, y, x + w - 1, y, color)
	stroke_line(img, x + w - 1, y, x + w - 1, y + h - 1, color)
	stroke_line(img, x + w - 1, y + h - 1, x, y + h - 1, color)
	stroke_line(img, x, y + h - 1, x, y, color)


static func stroke_polygon(img: Image, pts: PackedVector2Array, color: Color) -> void:
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		stroke_line(img, int(round(a.x)), int(round(a.y)), int(round(b.x)), int(round(b.y)), color)


static func fill_polygon(img: Image, pts: PackedVector2Array, color: Color) -> void:
	# 扫描线填充（每行与各边求交，交点排序后成对填充）
	if pts.size() < 3:
		return
	var min_y := 1 << 30
	var max_y := -(1 << 30)
	for p in pts:
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))
	for y in range(min_y, max_y + 1):
		var xs := PackedFloat32Array()
		for i in pts.size():
			var j := (i + 1) % pts.size()
			var y0 := pts[i].y
			var y1 := pts[j].y
			if (y0 <= float(y) and y1 > float(y)) or (y1 <= float(y) and y0 > float(y)):
				var t := (float(y) - y0) / (y1 - y0)
				xs.append(pts[i].x + t * (pts[j].x - pts[i].x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var xa := int(round(xs[k]))
			var xb := int(round(xs[k + 1]))
			for x in range(xa, xb + 1):
				img.set_pixel(x, y, color)
			k += 2


## 花色符号（心/桃/菱/梅），中心 (cx, cy)，scale 倍缩放
static func draw_suit_symbol(img: Image, suit: int, cx: int, cy: int, scale: int, color: Color) -> void:
	match suit:
		CardData.Suit.HEARTS:
			fill_circle(img, cx - 4 * scale, cy - 3 * scale, 4 * scale, color)
			fill_circle(img, cx + 4 * scale, cy - 3 * scale, 4 * scale, color)
			fill_polygon(img, PackedVector2Array([
				Vector2(cx - 8 * scale, cy + 1 * scale),
				Vector2(cx + 8 * scale, cy + 1 * scale),
				Vector2(cx, cy + 10 * scale),
			]), color)
		CardData.Suit.DIAMONDS:
			fill_polygon(img, PackedVector2Array([
				Vector2(cx, cy - 10 * scale),
				Vector2(cx + 8 * scale, cy),
				Vector2(cx, cy + 10 * scale),
				Vector2(cx - 8 * scale, cy),
			]), color)
		CardData.Suit.SPADES:
			fill_circle(img, cx - 4 * scale, cy + 3 * scale, 4 * scale, color)
			fill_circle(img, cx + 4 * scale, cy + 3 * scale, 4 * scale, color)
			fill_polygon(img, PackedVector2Array([
				Vector2(cx - 8 * scale, cy - 1 * scale),
				Vector2(cx + 8 * scale, cy - 1 * scale),
				Vector2(cx, cy - 10 * scale),
			]), color)
			stroke_line(img, cx, cy + 6 * scale, cx, cy + 12 * scale, color)
			stroke_line(img, cx + 1 * scale, cy + 6 * scale, cx + 1 * scale, cy + 12 * scale, color)
		CardData.Suit.CLUBS:
			fill_circle(img, cx, cy - 5 * scale, 4 * scale, color)
			fill_circle(img, cx - 5 * scale, cy + 2 * scale, 4 * scale, color)
			fill_circle(img, cx + 5 * scale, cy + 2 * scale, 4 * scale, color)
			stroke_line(img, cx, cy + 4 * scale, cx, cy + 12 * scale, color)
			stroke_line(img, cx + 1 * scale, cy + 4 * scale, cx + 1 * scale, cy + 12 * scale, color)
