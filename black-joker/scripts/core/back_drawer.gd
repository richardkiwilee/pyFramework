class_name BackDrawer
extends RefCounted
## =============================================================================
## BackDrawer — 52 种唯一牌背的程序化绘制（本作的灵魂）
## =============================================================================
## 编码规范（见 docs/00-design.md §3）：
##   - 点数通道：上沿铆钉（小圆点）数量 = 点数（A=1 … K=13）
##   - 花色通道：中央菱形徽章的边框/填充色调 + 徽章中心的花色符号（双重冗余）
##   - 四角花纹与斜纹底纹完全对称，不携带信息
## 全部绘制到 CPU Image（headless 可测），UI 侧再用 ImageTexture 展示。
## 光栅化工具在 Raster 类中。
## =============================================================================

# 公共底纹（52 张共享，不携带信息）
const FRAME := Color("3a1414")           # 深红边框
const BACK_BG := Color("1a1210")         # 背底近黑
const INNER_LINE := Color("8a6a3a")      # 内框金棕线
const LATTICE := Color("2a1412")         # 斜纹底纹
const STUD := Color("6a3a28")            # 上沿铆钉（暗铜色）
const CORNER := Color("5a3a28")          # 四角花纹

# 花色色调（索引与 CardData.Suit 一致）
const SUIT_BORDER := [Color("4a5a72"), Color("7a3040"), Color("7a5a28"), Color("4a5a34")]
const SUIT_FILL := [Color("2c3644"), Color("4a1e28"), Color("4a3a1a"), Color("2c341e")]
const SUIT_SYMBOL := [Color("7d94b8"), Color("c86a7c"), Color("c8965a"), Color("8aa86a")]

const CARD_W := 140
const CARD_H := 196

static var _texture_cache := {}


## 花色对应的徽章边框色（编码恒等接口，供测试与对照表使用）
static func suit_tint(suit: int) -> Color:
	return SUIT_BORDER[suit]


## 点数对应的铆钉数（编码恒等接口）
static func stud_count(rank: int) -> int:
	return rank


## 渲染一张牌背到 CPU Image。scale 用于放大镜（清晰放大而非拉伸）。
static func render_back_image(suit: int, rank: int, scale: int = 1) -> Image:
	var w := CARD_W * scale
	var h := CARD_H * scale
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 外框：深红底 + 内嵌黑底
	img.fill_rect(Rect2i(0, 0, w, h), FRAME)
	img.fill_rect(Rect2i(6 * scale, 6 * scale, w - 12 * scale, h - 12 * scale), BACK_BG)
	# 内框线
	Raster.stroke_rect(img, 16 * scale, 16 * scale, 108 * scale, 164 * scale, INNER_LINE)
	# 斜纹底纹（两方向对角线，对称无信息）
	var step := 14 * scale
	var t := 0
	while t * step < w + h:
		Raster.stroke_line(img, t * step, 0, t * step - h, h, LATTICE)
		Raster.stroke_line(img, 0, t * step, w, t * step - w, LATTICE)
		t += 1
	# 点数通道：上沿铆钉
	for k in range(1, rank + 1):
		var cx := int(round((16.0 + k * 108.0 / (rank + 1.0)) * scale))
		Raster.fill_circle(img, cx, 11 * scale, 2 * scale, STUD)
	# 花色通道：中央菱形徽章（填充 + 边框）
	var pts := PackedVector2Array([
		Vector2(70, 56) * scale, Vector2(112, 98) * scale,
		Vector2(70, 140) * scale, Vector2(28, 98) * scale,
	])
	Raster.fill_polygon(img, pts, SUIT_FILL[suit])
	Raster.stroke_polygon(img, pts, SUIT_BORDER[suit])
	# 徽章中心的花色符号
	Raster.draw_suit_symbol(img, suit, 70 * scale, 98 * scale, scale, SUIT_SYMBOL[suit])
	# 四角对称花纹（无信息）
	var corners: Array[Vector2i] = [
		Vector2i(22, 22), Vector2i(118, 22), Vector2i(22, 174), Vector2i(118, 174),
	]
	for corner in corners:
		Raster.fill_circle(img, corner.x * scale, corner.y * scale, 2 * scale, CORNER)
		Raster.stroke_circle(img, corner.x * scale, corner.y * scale, 5 * scale, CORNER)
	return img


## 带缓存的牌背纹理（UI 用）
static func back_texture(suit: int, rank: int) -> ImageTexture:
	var key := "%d-%d" % [suit, rank]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img := render_back_image(suit, rank)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex
