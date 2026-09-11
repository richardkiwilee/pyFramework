# EffectZone.gd — A persistent area effect: fire (DoT) or blackhole (pull + blast).
# Fire zones damage tanks standing inside them each frame and burn out.
# Blackhole zones pull nearby tanks toward the center for grav_time seconds,
# then detonate in a blast (damage + terrain carve).
extends Node2D
class_name EffectZone

var battle: Node
var kind: String         # "fire" | "blackhole"
var weapon: Dictionary
var owner_tank: Tank
var center: Vector2
var life: float = 0.0
var max_life: float = 4.0
var radius: float = 40.0
var dps: float = 10.0
var _t: float = 0.0
var _particles: PackedVector2Array = []


func setup(p_kind: String, p_center: Vector2, p_weapon: Dictionary, p_owner: Tank, p_battle: Node) -> void:
	kind = p_kind
	center = p_center
	weapon = p_weapon
	owner_tank = p_owner
	battle = p_battle
	position = center
	match kind:
		"fire":
			max_life = weapon.get("burn_time", 4.0)
			radius = weapon.get("radius", 30.0)
			dps = weapon.get("burn_dps", 10.0)
			_init_fire_particles()
		"blackhole":
			max_life = weapon.get("grav_time", 2.5)
			radius = weapon.get("grav_radius", 200.0)
	z_index = 4


func _init_fire_particles() -> void:
	_particles.clear()
	for i in 8:
		_particles.append(Vector2(Game.rng.randf_range(-radius, radius), Game.rng.randf_range(-radius * 0.3, 0)))


func _physics_process(delta: float) -> void:
	if battle == null: return
	_t += delta
	life = _t
	match kind:
		"fire":
			_tick_fire(delta)
		"blackhole":
			_tick_blackhole(delta)
	queue_redraw()
	if _t >= max_life:
		if kind == "blackhole":
			# final detonation
			battle.on_explode(center, weapon, owner_tank, 1.0, true)
		queue_free()


func _tick_fire(delta: float) -> void:
	# damage any tank whose center is within radius
	for tk in battle.tanks:
		if not tk.alive: continue
		if tk.position.distance_to(center) < radius:
			tk.take_damage(dps * delta)
	# flicker particles upward
	for i in _particles.size():
		_particles[i].y -= 30.0 * delta
		if _particles[i].y < -radius:
			_particles[i] = Vector2(Game.rng.randf_range(-radius, radius), 0)


func _tick_blackhole(delta: float) -> void:
	# pull tanks toward center (they are not physics bodies, so move them directly)
	var g: float = float(weapon.get("grav", 900.0))
	for tk in battle.tanks:
		if not tk.alive: continue
		var to: Vector2 = center - tk.position
		var d: float = to.length()
		if d < 4.0 or d > radius:
			continue
		var pull: float = g * (1.0 - d / radius) * delta
		tk.position += to.normalized() * pull
		# small chip damage
		tk.take_damage(4.0 * delta)
	# keep tanks from being dragged into solid ground: settle if they hit terrain
	for tk in battle.tanks:
		if tk.alive and battle.terrain.is_solid_at(tk.position.x, tk.position.y):
			tk.position.y -= 2.0


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw() -> void:
	match kind:
		"fire":
			_draw_fire()
		"blackhole":
			_draw_blackhole()


func _draw_fire() -> void:
	var fade := 1.0 - (_t / max_life)
	for p in _particles:
		var c := Color(1.0, 0.5 + Game.rng.randf() * 0.4, 0.1, fade * 0.8)
		draw_circle(p, 6.0 + sin(_t * 10.0 + p.x) * 2.0, c)
	# glow
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 0.4, 0.0, fade * 0.15))


func _draw_blackhole() -> void:
	var fade := 1.0 - (_t / max_life)
	# swirling rings
	for i in 5:
		var r := radius * (0.2 + 0.16 * i) * (1.0 - fade * 0.3)
		var rot := _t * (2.0 + i * 0.5)
		var col := Color(0.4, 0.1, 0.9, fade * (0.5 - i * 0.08))
		draw_arc(Vector2.ZERO, r, rot, rot + TAU * 0.8, 32, col, 2.0)
	# core
	draw_circle(Vector2.ZERO, 12.0, Color(0.05, 0.0, 0.15, fade))
	draw_circle(Vector2.ZERO, 6.0, Color.BLACK)
