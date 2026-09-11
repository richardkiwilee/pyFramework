# Pickup.gd — Two kinds of pickup:
#   "x2"      — a RED CIRCLE hovering in the AIR. Grants the x2 damage buff for
#               1 turn (turn-based). Never settles on the ground; bobs in place.
#               Collected by the active tank driving underneath it (horizontal
#               proximity), so a faint guide column is drawn below it.
#   "health"  — a BLUE supply crate that falls from the sky and lands on the
#   "weapon"     ground. Grants healing / a random weapon when a tank touches it.
# Per the design: 补给 (supply) drops at the start of a turn onto the ground and
# uses BLUE; x2 uses RED and floats in the air for only 1 turn.
# Only the active tank (the one whose turn it is) can collect either pickup.
extends Node2D
class_name Pickup

signal picked_up(pickup: Pickup, tank: Tank)

var battle: Node
var kind: String = "x2"
var velocity: Vector2 = Vector2.ZERO
var settled: bool = false
var age: float = 0.0
var life: float = 25.0  # despawn after a while if not grabbed
var weapon_id: int = 1  # for "weapon" kind
var hover_y: float = -40.0  # fixed air height for x2 (set in setup)
var _bob: float = 0.0

const CRATE_R: float = 12.0  # half-size of supply crate
const X2_R: float = 14.0    # radius of x2 circle
const GRAB_W: float = 20.0  # horizontal grab slack


func setup(p_kind: String, p_battle: Node, x: float, p_weapon_id: int = 1) -> void:
	kind = p_kind
	battle = p_battle
	weapon_id = p_weapon_id
	position = Vector2(x, -40.0)
	velocity = Vector2(0.0, 60.0)
	z_index = 6
	if kind == "x2":
		hover_y = Game.rng.randf_range(120.0, 240.0)


func _physics_process(delta: float) -> void:
	age += delta
	_bob += delta
	if age > life:
		queue_free()
		return
	if kind == "x2":
		# float up to the hover height, then bob in place
		if position.y < hover_y:
			velocity.y += 40.0 * delta
			position += velocity * delta
			if position.y >= hover_y:
				position.y = hover_y
				velocity = Vector2.ZERO
		_check_pickup()
	else:
		# supply crate falls and lands on the ground
		if not settled:
			velocity.y += 600.0 * delta
			position += velocity * delta
			if battle.terrain.is_solid_at(position.x, position.y + CRATE_R):
				var surf: float = battle.terrain.surface_y_at(position.x, position.y - 4)
				position.y = surf - CRATE_R
				settled = true
		_check_pickup()
	queue_redraw()


func _check_pickup() -> void:
	var active: Tank = battle.active_tank()
	if active == null or not active.alive:
		return
	var grabbed: bool = false
	if kind == "x2":
		# in the air: grab by horizontal proximity (drive underneath)
		grabbed = abs(active.position.x - position.x) < X2_R + GRAB_W
	else:
		# on the ground: grab by full distance
		grabbed = active.position.distance_to(position) < CRATE_R + 18.0
	if grabbed:
		_apply(active)
		emit_signal("picked_up", self, active)
		queue_free()


func _apply(tk: Tank) -> void:
	match kind:
		"x2":
			tk.grant_buff("x2", 1)  # turn-based: lasts 1 turn
		"health":
			tk.heal(35.0)
		"weapon":
			tk.weapon_id = weapon_id
			tk.ammo[weapon_id] = int(tk.ammo.get(weapon_id, 0)) + 3
	if battle.has_method("float_text"):
		battle.float_text(tk.position + Vector2(0, -40), _label(), _label_color())


func _label() -> String:
	match kind:
		"x2": return "x2 DMG!"
		"health": return "+35 HP"
		"weapon": return "+AMMO"
		_: return kind


func _label_color() -> Color:
	match kind:
		"x2": return Color(0.95, 0.20, 0.20)
		"health": return Color(0.40, 0.80, 1.0)
		"weapon": return Color(0.40, 0.80, 1.0)
		_: return Color.WHITE


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw() -> void:
	var bob: float = sin(_bob * 3.0) * 2.0
	var p: Vector2 = Vector2(0, bob)
	if kind == "x2":
		_draw_x2(p)
	else:
		_draw_supply(p)
	# glow when near expiring
	if age > life - 5.0:
		var a: float = (sin(_bob * 12.0) * 0.5 + 0.5) * 0.4
		var ring_r: float = X2_R + 4.0 if kind == "x2" else CRATE_R + 4.0
		draw_arc(p, ring_r, 0, TAU, 24, Color(1, 1, 1, a), 2.0)


func _draw_x2(p: Vector2) -> void:
	# Red circle hovering in the air.
	var col: Color = Color(0.92, 0.18, 0.18)
	# faint guide column down to the ground (hints: drive under to collect)
	var ground_y: float = battle.terrain.surface_y_at(position.x, 0.0) - position.y
	if ground_y > p.y + X2_R:
		var top: float = p.y + X2_R + 2.0
		var dash: float = 6.0
		var gap: float = 5.0
		var yy: float = top
		var drawing: bool = true
		while yy < ground_y:
			if drawing:
				var e: float = min(yy + dash, ground_y)
				draw_line(Vector2(0, yy), Vector2(0, e), Color(0.92, 0.18, 0.18, 0.25), 2.0)
				yy = e
				drawing = false
			else:
				yy += gap
				drawing = true
	# outer glow
	draw_circle(p, X2_R + 6.0, Color(0.92, 0.18, 0.18, 0.18))
	# body circle
	draw_circle(p, X2_R, col)
	draw_arc(p, X2_R, 0, TAU, 24, Color.WHITE, 2.0)
	# inner highlight
	draw_circle(p - Vector2(4, 4), X2_R * 0.35, Color(1, 1, 1, 0.25))
	# label
	draw_string(Game.default_font(), p + Vector2(-10, 5), "×2",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)


func _draw_supply(p: Vector2) -> void:
	# Blue supply crate. Shadow only after landing.
	if settled:
		draw_circle(Vector2(0, CRATE_R + 2 - p.y), CRATE_R * 0.8, Color(0, 0, 0, 0.25))
	var col: Color = Color(0.25, 0.55, 1.0)  # blue
	var letter: String = "+" if kind == "health" else "W"
	# crate body
	draw_rect(Rect2(p.x - CRATE_R, p.y - CRATE_R, CRATE_R * 2, CRATE_R * 2), col, true)
	draw_rect(Rect2(p.x - CRATE_R, p.y - CRATE_R, CRATE_R * 2, CRATE_R * 2), Color.BLACK, false, 2.0)
	# cross straps
	draw_line(Vector2(p.x, p.y - CRATE_R), Vector2(p.x, p.y + CRATE_R), Color(0.12, 0.3, 0.7), 2.0)
	draw_line(Vector2(p.x - CRATE_R, p.y), Vector2(p.x + CRATE_R, p.y), Color(0.12, 0.3, 0.7), 2.0)
	# icon
	draw_string(Game.default_font(), p + Vector2(-6, 5), letter,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color.WHITE)
