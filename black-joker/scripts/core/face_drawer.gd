class_name FaceDrawer
extends RefCounted
## =============================================================================
## FaceDrawer — 牌面程序化绘制（角标点数 + 花色符号 + 中央大符号）
## =============================================================================
## 点数文字用 Raster 的 5×7 点阵字体（Image 无法使用 Font 画字，且 headless
## 下 CanvasItem 渲染不可用）。红桃/方块红色，黑桃/梅花黑色。
## =============================================================================

const IVORY := Color("f2ead8")           # 牌面象牙白底
const BORDER := Color("8a7a5c")          # 牌面边框
const SUIT_RED := Color("c0392b")        # 红桃/方块
const SUIT_BLACK := Color("16120d")      # 黑桃/梅花（偏暖黑）

const CARD_W := 140
const CARD_H := 196

static var _texture_cache := {}


static func suit_color(suit: int) -> Color:
	if suit == CardData.Suit.HEARTS or suit == CardData.Suit.DIAMONDS:
		return SUIT_RED
	return SUIT_BLACK


static func rank_text(rank: int) -> String:
	var names: Array = CardData.RANK_NAMES
	var r: String = names[rank]
	return r


## 渲染一张牌面到 CPU Image
static func render_face_image(suit: int, rank: int, scale: int = 1) -> Image:
	var w := CARD_W * scale
	var h := CARD_H * scale
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var color := suit_color(suit)
	img.fill(IVORY)
	Raster.stroke_rect(img, 0, 0, w, h, BORDER)
	# 左上角标：点数（2 倍缩放的点阵字）+ 小花色符号
	var text := rank_text(rank)
	var ts := 2 * scale
	Raster.draw_bitmap_text(img, text, 10 * scale, 8 * scale, ts, color)
	# 角标符号：位于文字正下方（"10" 两个字形宽 11 像素，单字符 5 像素）
	var text_w := (text.length() * 6 - 1) * ts
	Raster.draw_suit_symbol(img, suit,
		10 * scale + text_w / 2,
		(8 + 14 + 12) * scale, 1 * scale, color)
	# 中央大符号（scale 倍基准）
	Raster.draw_suit_symbol(img, suit, 70 * scale, 98 * scale, 3 * scale, color)
	# 右下角小符号（对称装饰）
	Raster.draw_suit_symbol(img, suit, 112 * scale, 166 * scale, 2 * scale, color)
	return img


## 带缓存的牌面纹理（UI 用）
static func face_texture(suit: int, rank: int) -> ImageTexture:
	var key := "%d-%d" % [suit, rank]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img := render_face_image(suit, rank)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex
