class_name CardView
extends TextureRect
## =============================================================================
## CardView — 一张牌的显示（牌面或牌背），纹理来自 FaceDrawer/BackDrawer
## =============================================================================
## 展示尺寸 100×140（纹理 140×196 等比缩放）。
## =============================================================================

const DISPLAY_SIZE := Vector2(100, 140)


static func face(card: CardData) -> CardView:
	var v := CardView.new()
	v.texture = FaceDrawer.face_texture(card.suit, card.rank)
	v._setup()
	return v


static func back(card: CardData) -> CardView:
	var v := CardView.new()
	v.texture = BackDrawer.back_texture(card.suit, card.rank)
	v._setup()
	return v


func _setup() -> void:
	custom_minimum_size = DISPLAY_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
