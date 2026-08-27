class_name PokerCard
extends Control
## 一张扑克牌。
## 背面:三种编织花纹(田字形 / 内切菱形 / 交叉对角线)密铺,左上角上下两个格子是记号
##   (上格最长连线 = 数字,下格最长连线 = 花色,见 readme.md)。
## 正面:普通牌面(角标 + 点数)。
## flip_progress:0 = 背面朝上,1 = 正面朝上;翻牌过程用 scale.x 压缩模拟绕竖直边旋转。

const CARD_SIZE := Vector2(100, 150)
## 牌背美术资源:13 张 2:3 卡片的网格图(A..K 每张一格)。
## 资源存在则牌背直接取对应 rank 的那格;不存在则回退到编织记号牌背。
const BACK_SHEET_PATH := "res://assets/card_backs.png"
const BACK_SHEET_COLS := 13
const RANK_TEXT := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const PIP_LAYOUT := {
	2: [[1, 0], [1, 6]],
	3: [[1, 0], [1, 3], [1, 6]],
	4: [[0, 0], [2, 0], [0, 6], [2, 6]],
	5: [[0, 0], [2, 0], [1, 3], [0, 6], [2, 6]],
	6: [[0, 0], [2, 0], [0, 3], [2, 3], [0, 6], [2, 6]],
	7: [[0, 0], [2, 0], [1, 1], [0, 3], [2, 3], [0, 6], [2, 6]],
	8: [[0, 0], [2, 0], [1, 1], [0, 3], [2, 3], [1, 5], [0, 6], [2, 6]],
	9: [[0, 0], [2, 0], [0, 1], [2, 1], [1, 3], [0, 5], [2, 5], [0, 6], [2, 6]],
	10: [[0, 0], [2, 0], [0, 1], [2, 1], [1, 2], [1, 4], [0, 5], [2, 5], [0, 6], [2, 6]],
}

const BACK_BG := Color8(46, 77, 143)
const WEAVE_SQUARE := Color(0.79, 0.85, 0.97, 0.38)
const WEAVE_DIAMOND := Color(0.50, 0.64, 0.87, 0.42)
const WEAVE_CROSS := Color(0.29, 0.44, 0.69, 0.50)
const WEAVE_FAINT := Color(0.85, 0.90, 1.0, 0.10)
const MARK_COLOR := Color(1.0, 0.84, 0.42, 0.88)
const RED := Color8(198, 40, 40)
const BLACK := Color8(33, 33, 33)

var rank: int = 1
var suit: int = 0
## 记号格最长连线的方向:0=横 1=竖 2=反斜杠 3=正斜杠 4=双对角线(A)
var rank_dir: int = 0
## 连线偏移档位(0..3),决定连线在格子里的位置
var rank_off: int = 1
var show_shadow: bool = false

var flip_progress: float = 0.0:
	set(v):
		flip_progress = v
		scale.x = absf(cos(v * PI))
		if is_inside_tree():
			queue_redraw()

var _back_box: StyleBoxFlat
var _front_box: StyleBoxFlat
var _back_sheet: Texture2D = null

func _init() -> void:
	size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_box = StyleBoxFlat.new()
	_back_box.bg_color = BACK_BG
	_back_box.border_color = Color8(233, 238, 248)
	_back_box.set_border_width_all(3)
	_back_box.set_corner_radius_all(8)
	_front_box = StyleBoxFlat.new()
	_front_box.bg_color = Color8(251, 250, 245)
	_front_box.border_color = Color8(207, 205, 189)
	_front_box.set_border_width_all(2)
	_front_box.set_corner_radius_all(8)
	if ResourceLoader.exists(BACK_SHEET_PATH):
		_back_sheet = load(BACK_SHEET_PATH)

func setup(rank_v: int, suit_v: int) -> void:
	rank = rank_v
	suit = suit_v
	if rank == 1:
		rank_dir = 4
		rank_off = 1
	else:
		var idx := rank - 2
		rank_dir = idx % 4
		rank_off = idx / 3

func _draw() -> void:
	if show_shadow:
		draw_rect(Rect2(Vector2(6, 9), CARD_SIZE), Color(0, 0, 0, 0.22), true)
	if flip_progress < 0.5:
		_draw_back()
	else:
		_draw_front()

# ---------- 牌背 ----------

func _draw_back() -> void:
	if _back_sheet != null:
		# 牌背直接用美术资源:按 rank 取 13 格网格里的对应一格
		var col_w := _back_sheet.get_width() / float(BACK_SHEET_COLS)
		var col_h := _back_sheet.get_height()
		var src := Rect2((rank - 1) * col_w, 0.0, col_w, col_h)
		draw_texture_rect_region(_back_sheet, Rect2(Vector2.ZERO, CARD_SIZE), src)
		return
	draw_style_box(_back_box, Rect2(Vector2.ZERO, CARD_SIZE))
	var cell := 20.0
	var x0 := 10.0
	var y0 := 10.0
	for col in 4:
		for row in 6:
			var cx := x0 + col * cell
			var cy := y0 + row * cell
			if col == 0 and row == 0:
				_draw_mark_cell(cx, cy, cell, rank_dir, rank_off)
			elif col == 0 and row == 1:
				_draw_mark_cell(cx, cy, cell, suit % 4, 1)
			else:
				_draw_weave_cell(cx, cy, cell, (col + row) % 2,
						WEAVE_SQUARE, WEAVE_DIAMOND, WEAVE_CROSS)

## 普通编织格:三种花纹层层叠压
func _draw_weave_cell(cx: float, cy: float, cell: float, parity: int,
		c_sq: Color, c_di: Color, c_cr: Color) -> void:
	var o := 0.5 if parity == 0 else -0.5
	var left := cx + 2.0 + o
	var top := cy + 2.0 - o
	var right := cx + cell - 2.0 + o
	var bottom := cy + cell - 2.0 - o
	var mid_x := cx + cell * 0.5 + o
	var mid_y := cy + cell * 0.5 - o
	# 田字形:外框 + 十字
	draw_rect(Rect2(left, top, right - left, bottom - top), c_sq, false, 1.1, true)
	draw_line(Vector2(mid_x, top), Vector2(mid_x, bottom), c_sq, 1.1, true)
	draw_line(Vector2(left, mid_y), Vector2(right, mid_y), c_sq, 1.1, true)
	# 内切菱形
	var m := 6.0
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(cx + cell * 0.5, cy + m), Vector2(cx + cell - m, cy + cell * 0.5),
		Vector2(cx + cell * 0.5, cy + cell - m), Vector2(cx + m, cy + cell * 0.5)])
	draw_colored_polygon(pts, c_di)
	# 交叉对角线
	draw_line(Vector2(cx + 2, cy + 2), Vector2(cx + cell - 2, cy + cell - 2), c_cr, 1.1, true)
	draw_line(Vector2(cx + cell - 2, cy + 2), Vector2(cx + 2, cy + cell - 2), c_cr, 1.1, true)

## 记号格:编织"失效"(花纹淡到几乎看不见),只剩一条最长的连线露出来
func _draw_mark_cell(cx: float, cy: float, cell: float, dir: int, off: int) -> void:
	_draw_weave_cell(cx, cy, cell, 0, WEAVE_FAINT, WEAVE_FAINT, WEAVE_FAINT)
	var shift := (off - 1.5) * 6.0
	var inset := 1.5
	match dir:
		0:
			draw_line(Vector2(cx + inset, cy + cell * 0.5 + shift),
					Vector2(cx + cell - inset, cy + cell * 0.5 + shift), MARK_COLOR, 2.4, true)
		1:
			draw_line(Vector2(cx + cell * 0.5 + shift, cy + inset),
					Vector2(cx + cell * 0.5 + shift, cy + cell - inset), MARK_COLOR, 2.4, true)
		2:
			draw_line(Vector2(cx + inset, cy + inset),
					Vector2(cx + cell - inset, cy + cell - inset), MARK_COLOR, 2.4, true)
		3:
			draw_line(Vector2(cx + cell - inset, cy + inset),
					Vector2(cx + inset, cy + cell - inset), MARK_COLOR, 2.4, true)
		4:
			draw_line(Vector2(cx + inset, cy + inset),
					Vector2(cx + cell - inset, cy + cell - inset), MARK_COLOR, 2.4, true)
			draw_line(Vector2(cx + cell - inset, cy + inset),
					Vector2(cx + inset, cy + cell - inset), MARK_COLOR, 2.4, true)

# ---------- 牌面 ----------

func _draw_front() -> void:
	draw_style_box(_front_box, Rect2(Vector2.ZERO, CARD_SIZE))
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var col := RED if suit == 1 or suit == 2 else BLACK
	var rtext: String = RANK_TEXT[rank - 1]
	# 左上角标
	draw_string(font, Vector2(8, 23), rtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
	_draw_suit(Vector2(11, 38), 13.0, col, false)
	# 右下角标(旋转 180°)
	draw_set_transform(Vector2(92, 127), PI, Vector2.ONE)
	draw_string(font, Vector2.ZERO, rtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
	_draw_suit(Vector2(3, 15), 13.0, col, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 中间点数 / 人牌
	if rank == 1:
		_draw_suit(Vector2(50, 87), 40.0, col, false)
	elif rank <= 10:
		var layout: Array = PIP_LAYOUT.get(rank, [])
		for p in layout:
			var gx: int = p[0]
			var gy: int = p[1]
			_draw_suit(Vector2(16 + gx * 34, 34 + gy * 17.67), 11.0, col, gy > 3)
	else:
		var letter: String = ["J", "Q", "K"][rank - 11]
		draw_string(font, Vector2(20, 100), letter, HORIZONTAL_ALIGNMENT_CENTER, 60, 54, col)
		_draw_suit(Vector2(50, 124), 16.0, col, false)

## 程序化画花色符号(不依赖字体里的 ♠♥♦♣ 字形)
func _draw_suit(center: Vector2, s: float, col: Color, flipped: bool) -> void:
	if flipped:
		draw_set_transform(center, PI, Vector2.ONE)
	var c := Vector2.ZERO if flipped else center
	match suit:
		0: # 黑桃
			draw_circle(c + Vector2(0, -0.14 * s), 0.30 * s, col)
			var pts0: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -0.30 * s), c + Vector2(0.44 * s, 0.28 * s),
				c + Vector2(0, 0.60 * s), c + Vector2(-0.44 * s, 0.28 * s)])
			draw_colored_polygon(pts0, col)
			var stem0: PackedVector2Array = PackedVector2Array([
				c + Vector2(-0.06 * s, 0.46 * s), c + Vector2(0.06 * s, 0.46 * s),
				c + Vector2(0, 0.68 * s)])
			draw_colored_polygon(stem0, col)
		1: # 红桃
			draw_circle(c + Vector2(-0.20 * s, -0.16 * s), 0.30 * s, col)
			draw_circle(c + Vector2(0.20 * s, -0.16 * s), 0.30 * s, col)
			var pts1: PackedVector2Array = PackedVector2Array([
				c + Vector2(-0.48 * s, -0.08 * s), c + Vector2(0.48 * s, -0.08 * s),
				c + Vector2(0, 0.60 * s)])
			draw_colored_polygon(pts1, col)
		2: # 方块
			var pts2: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -0.58 * s), c + Vector2(0.42 * s, 0),
				c + Vector2(0, 0.58 * s), c + Vector2(-0.42 * s, 0)])
			draw_colored_polygon(pts2, col)
		3: # 梅花
			draw_circle(c + Vector2(0, -0.30 * s), 0.30 * s, col)
			draw_circle(c + Vector2(-0.26 * s, 0.06 * s), 0.30 * s, col)
			draw_circle(c + Vector2(0.26 * s, 0.06 * s), 0.30 * s, col)
			var pts3: PackedVector2Array = PackedVector2Array([
				c + Vector2(-0.15 * s, 0.28 * s), c + Vector2(0.15 * s, 0.28 * s),
				c + Vector2(0, 0.60 * s)])
			draw_colored_polygon(pts3, col)
	if flipped:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
