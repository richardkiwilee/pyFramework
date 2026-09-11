# Game.gd — Autoload singleton (named `Game`).
# Holds the minimal cross-scene state: chosen player count and which map
# index was picked. Everything else lives in the Battle scene.
extends Node
## Global cross-scene state. Keep this tiny — the Battle scene owns the match.

signal settings_changed

enum AIM_LEVEL { EASY = 0, NORMAL = 1, HARD = 2 }

# --- Match settings (set from MainMenu, read by Battle) ----------------------
var player_count: int = 2
var ai_level: int = AIM_LEVEL.NORMAL
var map_choice: int = -1  # -1 = random, else a specific map index

# --- Runtime, not persisted --------------------------------------------------
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


## Pick a map index respecting the menu selection (or random).
func resolve_map_index(map_count: int) -> int:
	if map_choice >= 0 and map_choice < map_count:
		return map_choice
	return rng.randi() % map_count


## Multiply damage by 2 if the owner tank currently carries an active x2 buff.
func damage_multiplier_for(owner: Object) -> float:
	if owner == null or not owner.has_method("has_active_buff"):
		return 1.0
	return 2.0 if owner.has_active_buff("x2") else 1.0


## Shared color palette for tanks (cycled by player index).
const TANK_COLORS := [
	Color(0.35, 0.78, 0.95),  # cyan
	Color(0.95, 0.45, 0.40),  # red
	Color(0.55, 0.85, 0.40),  # green
	Color(0.95, 0.75, 0.30),  # orange
	Color(0.75, 0.55, 0.95),  # purple
	Color(0.95, 0.55, 0.85),  # pink
]


func tank_color(idx: int) -> Color:
	return TANK_COLORS[idx % TANK_COLORS.size()]


# --- Font helper -------------------------------------------------------------
# CanvasItem/CanvasLayer nodes don't have theme methods; fetch from the root
# window (a Window) which does. Cached after first call.
var _default_font: Font = null

func default_font() -> Font:
	if _default_font == null:
		var root: Window = Engine.get_main_loop().root
		if root and root.has_method("get_theme_default_font"):
			_default_font = root.get_theme_default_font()
	return _default_font
