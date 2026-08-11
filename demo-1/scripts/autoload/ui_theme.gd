extends Node
## UITheme - Autoload singleton providing the dark medieval theme colors and style utilities.

# ------------------------------------------------------------------ color palette (from web-demo/队伍编成)
const BG: Color = Color("0c0a08")
const BG2: Color = Color("14110d")
const PANEL: Color = Color("241d14")
const PANEL2: Color = Color("2e2519")
const LINE: Color = Color("4a3a24")
const LINE2: Color = Color("6a5436")
const INK: Color = Color("e8dcc4")
const INK2: Color = Color("c4b596")
const INK_DIM: Color = Color("8a7a5c")
const GOLD: Color = Color("d4af37")
const GOLD_BRIGHT: Color = Color("f0d264")
const GLOW: Color = Color("ffd86b")
const RED: Color = Color("c2553a")
const GREEN: Color = Color("7ab85a")
const BLUE: Color = Color("4a90c2")

# ------------------------------------------------------------------ rarity colors
const RARITY_COLORS := {
	"common": Color("9a9a9a"),
	"uncommon": Color("7ab85a"),
	"rare": Color("4a90c2"),
	"epic": Color("9b59b6"),
	"legendary": Color("f0d264"),
}

# ------------------------------------------------------------------ theme
var app_theme: Theme


func _ready() -> void:
	app_theme = Theme.new()
	# Configure default font
	var default_font = SystemFont.new()
	default_font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans SC", "sans-serif"])
	app_theme.default_font = default_font
	app_theme.default_font_size = 13


func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, INK_DIM)


# ------------------------------------------------------------------ style factories
func panel_style(margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


func panel_header_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("352a1a")
	sb.border_width_bottom = 1
	sb.border_color = LINE
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	return sb


func gold_button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	return sb


func default_button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2a2114")
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	return sb


func slot_dashed_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.28)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	return sb


func slot_filled_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("3a2d1a")
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	return sb
