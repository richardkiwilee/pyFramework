# HUD.gd — Top-of-screen overlay: weapon name, power bar, wind gauge, turn timer,
# active buffs, and a simple bottom weapon list (numbers 1-8 quick-select).
# Drawn as a Control (full-screen) so _draw works; kept on top via a high z_index.
extends Control
class_name HUD

var battle: Node
var _font: Font


func _ready() -> void:
	# Full-screen control anchored to the viewport.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_font = Game.default_font()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if battle == null or battle.active_tank() == null or _font == null:
		return
	var tk: Tank = battle.active_tank()
	var w: Dictionary = WeaponDB.get_weapon(tk.weapon_id)
	# --- Top bar background -------------------------------------------------
	draw_rect(Rect2(0, 0, 1280, 46), Color(0.08, 0.08, 0.12, 0.8), true)
	# Player turn label
	var label := "Player %d" % (tk.player_index + 1) if not tk.is_ai else "CPU %d" % (tk.player_index + 1)
	draw_string(_font, Vector2(16, 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, tk.color)
	# Weapon name
	var wname: String = String(w.get("display", "?")) if not w.is_empty() else "?"
	draw_string(_font, Vector2(180, 28), "Weapon: " + wname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	# Power bar
	var px: int = 420
	draw_string(_font, Vector2(px, 28), "Power", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.LIGHT_GRAY)
	var bx: int = px + 60
	draw_rect(Rect2(bx, 12, 150, 14), Color(0.2, 0.2, 0.2), true)
	var pfrac: float = tk.power
	var pc := Color.RED.lerp(Color.YELLOW, pfrac).lerp(Color.GREEN, pfrac)
	draw_rect(Rect2(bx, 12, 150 * pfrac, 14), pc, true)
	draw_rect(Rect2(bx, 12, 150, 14), Color.BLACK, false, 1)
	# Fuel bar
	var fx: int = 670
	draw_string(_font, Vector2(fx, 28), "Fuel", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.LIGHT_GRAY)
	var fbx: int = fx + 40
	draw_rect(Rect2(fbx, 12, 110, 14), Color(0.2, 0.2, 0.2), true)
	var ffrac: float = clamp(tk.fuel / tk.FUEL_MAX, 0.0, 1.0)
	draw_rect(Rect2(fbx, 12, 110 * ffrac, 14), Color(0.30, 0.80, 1.0), true)
	draw_rect(Rect2(fbx, 12, 110, 14), Color.BLACK, false, 1)
	# Wind gauge
	var wx: int = 860
	draw_string(_font, Vector2(wx, 28), "Wind", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.LIGHT_GRAY)
	var wbx: int = wx + 60
	draw_rect(Rect2(wbx, 12, 120, 14), Color(0.2, 0.2, 0.2), true)
	var wmid: int = wbx + 60
	draw_line(Vector2(wmid, 10), Vector2(wmid, 28), Color(0.5, 0.5, 0.5), 1)
	var wfrac: float = clamp(battle.current_wind / 10.0, -1.0, 1.0)
	var wcol := Color(0.4, 0.8, 1.0) if wfrac >= 0 else Color(1.0, 0.5, 0.4)
	draw_rect(Rect2(wmid, 12, wfrac * 60, 14), wcol, true)
	draw_rect(Rect2(wbx, 12, 120, 14), Color.BLACK, false, 1)

	# Buffs
	var buffx: int = 1000
	if tk.has_active_buff("x2"):
		draw_rect(Rect2(buffx, 10, 80, 22), Color(0.92, 0.18, 0.18), true)
		draw_string(_font, Vector2(buffx + 12, 28), "x2 DMG", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		buffx += 90

	# --- Turn timer ---------------------------------------------------------
	var tx: int = 1180
	var secs: int = int(ceil(battle.turn_timer))
	draw_string(_font, Vector2(tx, 28), "%ds" % secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color.RED if secs <= 5 else Color.WHITE)

	# --- Bottom weapon strip (quick slots) ----------------------------------
	draw_rect(Rect2(0, 690, 1280, 30), Color(0.08, 0.08, 0.12, 0.8), true)
	var ids := [1, 2, 7, 15, 21, 26, 31, 45]  # a representative quick set
	var slotw: int = 150
	for i in ids.size():
		var id: int = ids[i]
		var wd: Dictionary = WeaponDB.get_weapon(id)
		var rx: int = i * slotw + 10
		var sel: bool = (tk.weapon_id == id)
		var bgc := Color(0.2, 0.3, 0.5) if sel else Color(0.14, 0.14, 0.18)
		draw_rect(Rect2(rx, 692, slotw - 6, 26), bgc, true)
		draw_string(_font, Vector2(rx + 8, 712), "%d  %s" % [i + 1, String(wd.get("display", "?"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color.YELLOW if sel else Color.LIGHT_GRAY)

	# --- Help line ----------------------------------------------------------
	draw_string(_font, Vector2(16, 666), "A/D: move (uses fuel)   Arrows: aim+power   Mouse: drag in disc to aim   1-8: weapon   Space: fire   ESC: menu",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.7, 0.8, 0.8))
