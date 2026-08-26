class_name Magnifier
extends PanelContainer
## =============================================================================
## Magnifier — 牌堆顶牌牌背的放大镜（本作核心交互）
## =============================================================================
## 悬停牌堆时显示：×2 牌背放大渲染 + （新手模式）解码提示文字。
## 由 table.gd 喂入顶牌并控制显隐。
## =============================================================================

const _VBOX_SIZE := Vector2(320, 470)

var _tex_rect: TextureRect
var _label: Label


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("241d14")
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color("d4af37")
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", sb)
	size = _VBOX_SIZE  # 直接挂在根 Control 下，显式定尺寸
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := UITheme.make_label("牌堆顶牌 · 牌背观察", 16, UITheme.GOLD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_tex_rect = TextureRect.new()
	_tex_rect.custom_minimum_size = Vector2(280, 392)
	_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_tex_rect)

	_label = UITheme.make_label("", 16, UITheme.GOLD_BRIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_label)


## 设置顶牌并显示。card 为 null 表示牌堆已空。training=true 时显示解码提示。
func show_card(card: CardData, training: bool) -> void:
	if card == null:
		visible = false
		return
	# 放大镜用 2 倍清晰渲染，展示尺寸 280×392 正好 1:1
	_tex_rect.texture = _mag_texture(card)
	if training:
		_label.text = "%s %s · 点数 %d" % [
			card.display(), CardData.SUIT_NAMES_CN[card.suit], card.rank]
	else:
		_label.text = "仔细观察……"
	visible = true


static var _mag_cache := {}

## ×2 放大渲染纹理（缓存）
static func _mag_texture(card: CardData) -> ImageTexture:
	var key := "mag-%s" % card.id()
	if _mag_cache.has(key):
		return _mag_cache[key]
	var img := BackDrawer.render_back_image(card.suit, card.rank, 2)
	var tex := ImageTexture.create_from_image(img)
	_mag_cache[key] = tex
	return tex
