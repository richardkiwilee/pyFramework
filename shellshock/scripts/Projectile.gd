# Projectile.gd — A flying weapon projectile.
# Spawned by Battle. Physics is hand-rolled (gravity + wind) so it interacts
# with the bitmap terrain via Terrain.is_solid_at. On impact it either explodes
# or performs its special behaviour (cluster split, napalm zones, mine arm...).
# The projectile reports outcomes back to its `battle` owner node.
extends Node2D
class_name Projectile

# Who fired it and with what weapon data.
var battle: Node          # Battle scene (has on_explode, on_split, on_effect, spawn_pickup_chance)
var weapon: Dictionary
var owner_tank: Tank
var velocity: Vector2
var gravity: float = 420.0
var wind: float = 0.0      # px/s^2 horizontal accel from wind
# State
var t: float = 0.0
var armed: bool = false
var apex_reached: bool = false
var peak_y: float = -1e9
var bounced: int = 0
var max_bounces: int = 4
var dead: bool = false
var trail: PackedVector2Array = []
var is_child: bool = false # children from cluster/rain don't re-split (unless split_again)


func _ready() -> void:
	z_index = 5


func launch(p_weapon: Dictionary, p_owner: Tank, start: Vector2, dir: Vector2, p_speed: float, p_battle: Node, p_is_child: bool = false) -> void:
	weapon = p_weapon
	owner_tank = p_owner
	battle = p_battle
	is_child = p_is_child
	position = start
	velocity = dir * p_speed
	wind = battle.current_wind * 60.0  # wind in px/s^2 (battle stores -10..10 m/s-ish)
	# Roller / mine physics use a slower gravity feel for rolling
	if weapon.type == "roller":
		gravity = 520.0
	t = 0.0
	peak_y = start.y


func _physics_process(delta: float) -> void:
	if dead or battle == null:
		return
	t += delta
	# Homing steering
	if weapon.get("homing", 0.0) > 0.0 and not apex_reached:
		_steer_homing(delta)
	# Wind + gravity
	velocity.x += wind * delta
	velocity.y += gravity * delta * weapon.get("weight", 1.0)
	# Roller slow in air? keep; rolling handled on ground contact
	position += velocity * delta
	# Track apex for split_at_apex
	if position.y < peak_y:
		peak_y = position.y
	elif not apex_reached and velocity.y > 0.0:
		apex_reached = true
		if weapon.get("split_at_apex", false) and not is_child:
			_do_split()
			return
	# Fuse timer for rollers/mines
	if weapon.get("fuse", 0.0) > 0.0 and (weapon.type == "roller" or weapon.type == "mine"):
		if t >= weapon.fuse:
			_explode()
			return
	# Trail
	trail.append(position)
	if trail.size() > 12:
		trail.remove_at(0)
	queue_redraw()

	# Out of bounds
	if position.y > battle.terrain.height + 80:
		dead = true
		battle.on_projectile_done(self)
		queue_free()
		return
	if position.x < -40 or position.x > battle.terrain.width + 40:
		# bounce off side walls
		if position.x < 0:
			position.x = 0
			velocity.x = abs(velocity.x) * 0.6
		else:
			position.x = battle.terrain.width
			velocity.x = -abs(velocity.x) * 0.6

	# Terrain / ground collision
	if battle.terrain.is_solid_at(position.x, position.y):
		_on_impact()


func _steer_homing(delta: float) -> void:
	var target: Tank = battle.nearest_enemy_tank(owner_tank)
	if target == null:
		return
	var to: Vector2 = (target.position - position)
	if to.length() < 4.0:
		return
	var desired: Vector2 = to.normalized() * velocity.length()
	var strength: float = float(weapon.get("homing", 0.0)) * delta * 2.0
	velocity = velocity.lerp(desired, clamp(strength, 0.0, 0.25))


func _on_impact() -> void:
	match weapon.type:
		"basic":
			_explode()
		"cluster":
			if is_child:
				_explode()
			else:
				_do_split()
		"roller":
			_roll()
		"homing":
			_explode()
		"napalm":
			_napalm()
		"mine":
			_arm_mine()
		"blackhole":
			_blackhole()
		"laser":
			_explode()  # lasers don't travel; safety
		"rain":
			_explode()
		_:
			_explode()


func _explode() -> void:
	if dead: return
	dead = true
	battle.on_explode(position, weapon, owner_tank)
	battle.on_projectile_done(self)
	queue_free()


func _do_split() -> void:
	# Spawn split_count children with fanned velocities.
	if dead: return
	dead = true
	var n: int = int(weapon.get("split_count", 0))
	if n <= 0:
		_explode()
		return
	var child_w: Dictionary = weapon.duplicate()
	child_w["type"] = "basic"
	childw_damage(child_w)
	var spread_deg: float = 50.0
	for i in n:
		var ang_offset: float = deg_to_rad(spread_deg) * (float(i) / float(max(1, n - 1)) - 0.5) if n > 1 else 0.0
		var dir := velocity.normalized().rotated(ang_offset)
		var spd: float = velocity.length() * 0.85
		battle.spawn_child(child_w, owner_tank, position, dir, spd, bool(weapon.get("split_again", false)))
	battle.on_projectile_done(self)
	queue_free()


func childw_damage(w: Dictionary) -> void:
	# children do a fraction of parent damage unless overridden
	pass


func _roll() -> void:
	# Determine surface normal approximately
	var n := _surface_normal(position)
	# Reflect velocity around normal with bounciness
	var v := velocity
	var dot := v.dot(n)
	if dot < 0.0:
		v = v - 2.0 * dot * n
	velocity = v * float(weapon.get("bouncy", 0.5))
	# Push out of the ground a tiny bit along normal
	position += n * 1.5
	bounced += 1
	# Homing rollers crawl toward enemy
	if float(weapon.get("homing", 0.0)) > 0.0:
		var target: Tank = battle.nearest_enemy_tank(owner_tank)
		if target:
			var to: Vector2 = (target.position - position)
			velocity.x = lerp(velocity.x, sign(to.x) * 120.0, 0.2)
	if bounced > max_bounces or (velocity.length() < 25.0 and bounced > 1):
		_explode()
		return


func _surface_normal(p: Vector2) -> Vector2:
	# Sample a small ring around p; normal points toward least solid.
	var n := Vector2.ZERO
	var samples := 8
	for i in samples:
		var a := TAU * i / samples
		var sp := p + Vector2(cos(a), sin(a)) * 3.0
		if not battle.terrain.is_solid_at(sp.x, sp.y):
			n += Vector2(cos(a), sin(a))
	if n.length() < 0.01:
		return Vector2.UP
	return n.normalized()


func _napalm() -> void:
	if dead: return
	dead = true
	# small blast + fire zones
	battle.on_explode(position, weapon, owner_tank, 0.4)
	var zones: int = int(weapon.get("burn_zones", 6))
	for i in zones:
		var off: Vector2 = Vector2(Game.rng.randf_range(-1, 1), Game.rng.randf_range(-1, 1)) * float(weapon.get("radius", 20.0))
		battle.spawn_effect_zone("fire", position + off, weapon, owner_tank)
	battle.on_projectile_done(self)
	queue_free()


func _arm_mine() -> void:
	# Settle on ground: snap to surface and become a stationary hazard.
	var surf: float = battle.terrain.surface_y_at(position.x, position.y - 2)
	position = Vector2(position.x, surf - 4)
	velocity = Vector2.ZERO
	weapon["type"] = "mine_armed"
	# turn off physics gravity by marking; handled in _physics_process via type
	# Actually simpler: set a flag and stop moving unless prox triggered
	armed = true
	set_physics_process(false)
	# schedule a proximity/timer check via Battle processing
	battle.register_mine(self)


func _blackhole() -> void:
	if dead: return
	dead = true
	battle.spawn_effect_zone("blackhole", position, weapon, owner_tank)
	battle.on_projectile_done(self)
	queue_free()


# ---------------------------------------------------------------------------
# Drawing — simple flight animation: a colored ball + a fading trail of dots.
# NOTE: _draw() is in local coords (origin = the node's position). The physics
# code writes to `position`, so the body is drawn at Vector2.ZERO and the trail
# (stored in world coords) is translated by -position to local coords.
# ---------------------------------------------------------------------------
func _draw() -> void:
	if dead:
		return
	var col: Color = weapon.get("color", Color.WHITE)
	var sz: float = weapon.get("size", 5.0)
	# trail (world coords -> local)
	var n: int = trail.size()
	for i in n:
		var a: float = float(i) / float(n)
		draw_circle(trail[i] - position, sz * (0.3 + a * 0.5), Color(col.r, col.g, col.b, a * 0.4))
	# body
	draw_circle(Vector2.ZERO, sz, col)
	draw_arc(Vector2.ZERO, sz, 0, TAU, 16, Color.WHITE.darkened(0.4), 1.0)
