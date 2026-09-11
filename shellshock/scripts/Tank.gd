# Tank.gd — A tank entity on the battlefield.
# Position is the body center in world coords; the Battle scene owns the list
# and turn order. The tank draws itself: body rectangle + small cabin rectangle
# + 2 wheels + a barrel whose root is the cabin. The cabin is the firing origin.
# Green = self (human), Red = enemy (AI).
extends Node2D
class_name Tank

signal died(tank: Tank)

@export var player_index: int = 0
@export var max_hp: float = 100.0
@export var is_ai: bool = true

var hp: float = 100.0
var color: Color = Color.WHITE
var aim_angle: float = PI / 4.0    # true world angle (radians). aim_vector=(cos, -sin).
                                  # PI/4 = up-right, 3*PI/4 = up-left.
var power: float = 0.6
var weapon_id: int = 1
var ammo: Dictionary = {}
var alive: bool = true
var facing: int = 1                 # kept for reference; not used in aim_vector

# Turn-based buffs: "x2" -> turns remaining (int)
var buffs: Dictionary = {}

# Fuel per turn. Movement consumes fuel proportional to the distance traveled
# ALONG the terrain surface (arc length), not the horizontal world distance.
const FUEL_MAX: float = 100.0
var fuel: float = FUEL_MAX

# --- Visual dimensions (the "basic art resource") --------------------------
const BODY_W: float = 56.0
const BODY_H: float = 22.0
const CABIN_W: float = 24.0
const CABIN_H: float = 14.0
const WHEEL_R: float = 9.0
const BARREL_LEN: float = 32.0
const CONTACT: float = BODY_H / 2 + WHEEL_R  # body-center -> ground (wheels touch)

var _bob: float = 0.0
var _wheel_rot: float = 0.0


func _ready() -> void:
	hp = max_hp
	# Green = self (human player), Red = enemy (AI)
	color = Color(0.30, 0.82, 0.30) if not is_ai else Color(0.90, 0.25, 0.25)
	weapon_id = 1
	ammo = {}


func _process(delta: float) -> void:
	_bob += delta * 3.0
	queue_redraw()


# ---------------------------------------------------------------------------
# Buffs (turn-based, not time-based)
# ---------------------------------------------------------------------------
func has_active_buff(b: String) -> bool:
	return buffs.has(b) and int(buffs[b]) > 0

func grant_buff(b: String, turns: int) -> void:
	buffs[b] = turns

func tick_buff(b: String) -> void:
	if buffs.has(b):
		buffs[b] = int(buffs[b]) - 1
		if int(buffs[b]) <= 0:
			buffs.erase(b)


# ---------------------------------------------------------------------------
# Damage / heal
# ---------------------------------------------------------------------------
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp = max(0.0, hp - amount)
	if hp <= 0.0:
		alive = false
		emit_signal("died", self)

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)


# ---------------------------------------------------------------------------
# Aim — the cabin is the firing origin (barrel root).
# ---------------------------------------------------------------------------
func cabin_offset() -> Vector2:
	# cabin center relative to tank origin (body center)
	return Vector2(0.0, -BODY_H / 2 - CABIN_H / 2)

func barrel_root() -> Vector2:
	# world position of the cabin center = firing origin
	return position + cabin_offset()

func aim_vector() -> Vector2:
	# Pure world-space direction: aim_angle is a real angle (no facing flip).
	# We negate sin because screen y is downward (a positive angle should aim up).
	return Vector2(cos(aim_angle), -sin(aim_angle))

func barrel_tip() -> Vector2:
	return barrel_root() + aim_vector() * BARREL_LEN


# ---------------------------------------------------------------------------
# Movement / settling on terrain
# ---------------------------------------------------------------------------
func settle(terrain) -> void:
	var surf: float = terrain.surface_y_at(position.x, 0.0)
	position.y = surf - CONTACT

func reset_fuel() -> void:
	fuel = FUEL_MAX

## Move the tank along the terrain by a horizontal world-space delta `dx`.
## Fuel is consumed by the arc length actually traveled along the surface
## (approximated by sampling), not by |dx|. Stops at a wall or when fuel runs out.
func try_move(dx: float, terrain) -> void:
	if not alive or fuel <= 0.0:
		return
	# clamp the requested step to available fuel (fuel is in "surface pixels")
	var step: float = clamp(dx, -fuel, fuel)
	var nx: float = clamp(position.x + step, 20.0, terrain.width - 20.0)
	var cur_surf: float = terrain.surface_y_at(position.x, 0.0)
	var new_surf: float = terrain.surface_y_at(nx, 0.0)
	# block steep walls
	if abs(new_surf - cur_surf) > 32.0:
		return
	var actual_x: float = nx - position.x
	# arc-length along the surface: integrate hypot over the horizontal span
	var surf_dist: float = _surface_distance(position.x, nx, terrain)
	var cost: float = surf_dist
	if cost <= 0.0:
		cost = abs(actual_x)
	if cost > fuel:
		# scale the move so we only spend the remaining fuel
		var ratio: float = fuel / cost if cost > 0.001 else 0.0
		actual_x *= ratio
		nx = position.x + actual_x
		new_surf = terrain.surface_y_at(nx, 0.0)
		cost = fuel
	position.x = nx
	position.y = new_surf - CONTACT
	fuel -= cost
	_wheel_rot += cost / WHEEL_R

## Approximate the arc length of the terrain surface between x0 and x1 by
## sampling columns every SURF_STEP pixels and summing hypot(dx, dy).
func _surface_distance(x0: float, x1: float, terrain) -> float:
	const SURF_STEP: float = 2.0
	var lo: float = min(x0, x1)
	var hi: float = max(x0, x1)
	if hi - lo < 0.5:
		return abs(x1 - x0)
	var total: float = 0.0
	var prev_y: float = terrain.surface_y_at(lo, 0.0)
	var x: float = lo + SURF_STEP
	while x <= hi:
		var y: float = terrain.surface_y_at(x, 0.0)
		total += sqrt(SURF_STEP * SURF_STEP + (y - prev_y) * (y - prev_y))
		prev_y = y
		x += SURF_STEP
	return total


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw() -> void:
	if not alive:
		return
	# NOTE: in _draw() the local origin (0,0) is already at the node's world
	# position, so we draw everything in local coords — do NOT add `position`.
	# Ground shadow (slightly below the wheels)
	draw_set_transform(Vector2(0, CONTACT + 1), 0.0, Vector2.ONE)
	draw_rect(Rect2(-BODY_W / 2, 0, BODY_W, 5), Color(0, 0, 0, 0.22), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var body_col: Color = color
	var dark_col: Color = color.darkened(0.35)

	# Wheels (2)
	var wy: float = BODY_H / 2
	for sx in [-BODY_W * 0.30, BODY_W * 0.30]:
		var wc := Vector2(sx, wy)
		draw_circle(wc, WHEEL_R, Color(0.14, 0.14, 0.16))
		draw_arc(wc, WHEEL_R, 0, TAU, 18, Color.BLACK, 2.0)
		draw_circle(wc, 3.0, Color(0.30, 0.30, 0.32))
		var sp: Vector2 = Vector2(cos(_wheel_rot), sin(_wheel_rot)) * (WHEEL_R - 3.0)
		draw_line(wc - sp, wc + sp, Color(0.30, 0.30, 0.32), 2.0)

	# Body (rectangle)
	draw_rect(Rect2(-BODY_W / 2, -BODY_H / 2, BODY_W, BODY_H), body_col, true)
	draw_rect(Rect2(-BODY_W / 2, -BODY_H / 2, BODY_W, BODY_H), Color.BLACK, false, 2.0)
	draw_line(Vector2(-BODY_W / 2 + 4, 0), Vector2(BODY_W / 2 - 4, 0), dark_col, 1.0)

	# Cabin (small rectangle on top of the body)
	var co: Vector2 = cabin_offset()
	draw_rect(Rect2(co.x - CABIN_W / 2, co.y - CABIN_H / 2, CABIN_W, CABIN_H), body_col.lightened(0.18), true)
	draw_rect(Rect2(co.x - CABIN_W / 2, co.y - CABIN_H / 2, CABIN_W, CABIN_H), Color.BLACK, false, 2.0)
	# viewport slit
	draw_rect(Rect2(co.x - CABIN_W / 2 + 4, co.y - 2, CABIN_W - 8, 4), Color(0.20, 0.30, 0.40), true)

	# Barrel — root at the cabin center, points along aim
	var dir: Vector2 = aim_vector()
	var root_l: Vector2 = co
	var tip_l: Vector2 = co + dir * BARREL_LEN
	draw_line(root_l, tip_l, Color(0.18, 0.18, 0.22), 6.0)
	draw_line(root_l, tip_l, dark_col, 4.0)
	draw_circle(tip_l, 3.0, Color(0.10, 0.10, 0.12))  # muzzle

	# x2 buff indicator (red text above the health bar)
	if has_active_buff("x2"):
		var iy: float = -BODY_H / 2 - CABIN_H - 26.0
		draw_string(Game.default_font(), Vector2(-12, iy), "×2", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.95, 0.20, 0.20))

	# Health bar
	_draw_health_bar()
	# Fuel bar (under the health bar) — only meaningful for the active tank,
	# but drawing it for all tanks is cheap and informative.
	_draw_fuel_bar()


func _draw_fuel_bar() -> void:
	var bw: float = BODY_W
	var bh: float = 5.0
	var by: float = -BODY_H / 2 - CABIN_H - 3.0
	var bx: float = -bw / 2
	draw_rect(Rect2(bx - 1, by - 1, bw + 2, bh + 2), Color(0, 0, 0, 0.7), true)
	var frac: float = clamp(fuel / FUEL_MAX, 0.0, 1.0)
	# cyan fuel
	draw_rect(Rect2(bx, by, bw * frac, bh), Color(0.30, 0.80, 1.0), true)


func _draw_health_bar() -> void:
	var bw: float = BODY_W
	var bh: float = 6.0
	var by: float = -BODY_H / 2 - CABIN_H - 12.0
	var bx: float = -bw / 2
	draw_rect(Rect2(bx - 1, by - 1, bw + 2, bh + 2), Color(0, 0, 0, 0.7), true)
	var frac: float = hp / max_hp
	var hc := Color.GREEN if frac > 0.5 else (Color.YELLOW if frac > 0.25 else Color.RED)
	draw_rect(Rect2(bx, by, bw * frac, bh), hc, true)
	draw_string(Game.default_font(), Vector2(bx, by - 3), "P%d" % (player_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
