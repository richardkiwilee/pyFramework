# Battle.gd — The match controller. Owns terrain, tanks, projectiles, effects,
# pickups, HUD, aim preview. Manages turn order, input (human) and AI, firing,
# explosion resolution, wind, pickups, and win/lose.
extends Node2D
class_name Battle

# --- Children ---------------------------------------------------------------
var terrain: Terrain
var tanks: Array[Tank] = []
var hud: HUD
var aim_preview: AimPreview

# --- Match state ------------------------------------------------------------
var current_wind: float = 0.0          # -10..10 (display); *60 for px/s^2
var turn_index: int = 0
var turn_timer: float = 30.0
var turn_active: bool = false          # aiming phase
var firing: bool = false               # a shot is in flight
var projectiles: Array[Projectile] = []
var effects: Array[EffectZone] = []
var pickups: Array[Pickup] = []
var mines: Array[Projectile] = []      # armed mines waiting for trigger
var float_texts: Array = []            # {pos, text, color, t}
var over: bool = false
var winner: Tank = null
var end_timer: SceneTreeTimer = null

# Mouse aim dragging state (human turn only)
var mouse_aiming: bool = false          # true while left button is held inside the aim disc
const AIM_DISC_R: float = 90.0          # radius of the aim disc around the tank

# AI state
var ai_phase: String = "idle"          # "aim" | "adjust" | "fire" | "wait"
var ai_adjust_t: float = 0.0
var ai_target_angle: float = 0.0
var ai_target_power: float = 0.6
var ai_hold_t: float = 0.0


func _ready() -> void:
	# Terrain
	terrain = Terrain.new()
	terrain.map_index = Game.resolve_map_index(4)
	add_child(terrain)

	# Sky background behind terrain
	var bg := ColorRect.new()
	bg.color = terrain.sky_color()
	bg.size = Vector2(terrain.width, terrain.height)
	bg.z_index = -10
	add_child(bg)

	# HUD + aim preview
	hud = preload("res://scripts/HUD.gd").new()
	hud.battle = self
	add_child(hud)
	aim_preview = preload("res://scripts/AimPreview.gd").new()
	aim_preview.setup(self)
	add_child(aim_preview)

	_spawn_tanks()
	for tk in tanks:
		_settle_tank(tk)
		tk.reset_fuel()

	current_wind = Game.rng.randf_range(-6.0, 6.0)
	_start_turn()


# ---------------------------------------------------------------------------
# Tank setup
# ---------------------------------------------------------------------------
func _spawn_tanks() -> void:
	var n := Game.player_count
	var margin := 160
	var usable := terrain.width - margin * 2
	for i in n:
		var tk := Tank.new()
		tk.player_index = i
		tk.is_ai = (i != 0)  # player 0 is human; others are AI
		tk.max_hp = 100.0
		add_child(tk)
		var x := margin + (usable * (i + 1) / float(n + 1))
		x += Game.rng.randf_range(-30, 30)
		tk.position = Vector2(x, 100)
		# Give everyone a starting single shot
		tk.weapon_id = 1
		tanks.append(tk)


func _settle_tank(tk: Tank) -> void:
	tk.settle(terrain)


# ---------------------------------------------------------------------------
# Turn management
# ---------------------------------------------------------------------------
func active_tank() -> Tank:
	if tanks.is_empty():
		return null
	return tanks[turn_index]


func _start_turn() -> void:
	end_timer = null
	# skip dead tanks
	for _attempt in tanks.size():
		var tk := tanks[turn_index]
		if tk.alive:
			break
		turn_index = (turn_index + 1) % tanks.size()
	turn_timer = 30.0
	turn_active = true
	firing = false
	mouse_aiming = false
	current_wind = Game.rng.randf_range(-7.0, 7.0)
	# Refuel the active tank at the start of its turn.
	var pre_tk := active_tank()
	if pre_tk and pre_tk.alive:
		pre_tk.reset_fuel()
	# Supply drops happen at the START of a turn (per design): a chance to
	# airdrop a pickup. x2 spawns as a red circle in the air; health/weapon
	# fall as blue crates onto the ground (Pickup handles landing by kind).
	if not over and Game.rng.randf() < 0.4:
		_maybe_drop_pickup()
	var tk := active_tank()
	if tk and tk.is_ai:
		_begin_ai_turn()


func _end_turn() -> void:
	# Expire the x2 buff for the tank whose turn is ending (lasts 1 turn).
	var tk := active_tank()
	if tk and tk.alive:
		tk.tick_buff("x2")
	turn_active = false
	turn_index = (turn_index + 1) % tanks.size()
	end_timer = get_tree().create_timer(0.6)
	end_timer.timeout.connect(_start_turn)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Float texts lifetime
	var keep := []
	for ft in float_texts:
		ft.t += delta
		ft.pos.y -= 30.0 * delta
		if ft.t < 1.2:
			keep.append(ft)
	float_texts = keep

	if over:
		return

	if turn_active and not firing:
		turn_timer -= delta
		var tk := active_tank()
		if tk and not tk.is_ai and turn_timer <= 0.0:
			_end_turn()
			return

	if turn_active and active_tank() and active_tank().is_ai:
		_process_ai(delta)

	_process_mines(delta)
	_process_effects(delta)
	_process_pickups(delta)

	# Win check
	var alive_count := 0
	for tk in tanks:
		if tk.alive:
			alive_count += 1
	if alive_count <= 1 and not over:
		over = true
		for tk in tanks:
			if tk.alive:
				winner = tk
		_show_game_over()


# ---------------------------------------------------------------------------
# Input (human)
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		elif event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	if not turn_active or firing:
		return
	var tk := active_tank()
	if tk == null or not tk.alive or tk.is_ai:
		return
	# --- Mouse aim disc -------------------------------------------------------
	# Left-click inside the translucent disc around the tank snaps aim/power to
	# the click position; holding and dragging continuously adjusts.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = event.position
		if event.pressed:
			if _inside_aim_disc(tk, mp):
				mouse_aiming = true
				_apply_mouse_aim(tk, mp)
		else:
			mouse_aiming = false
	elif event is InputEventMouseMotion and mouse_aiming:
		_apply_mouse_aim(tk, event.position)
	# --- Keys -----------------------------------------------------------------
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE, KEY_ENTER:
				_fire()
			KEY_TAB:
				_cycle_weapon(1)
			KEY_1: _select_quick(0)
			KEY_2: _select_quick(1)
			KEY_3: _select_quick(2)
			KEY_4: _select_quick(3)
			KEY_5: _select_quick(4)
			KEY_6: _select_quick(5)
			KEY_7: _select_quick(6)
			KEY_8: _select_quick(7)
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _inside_aim_disc(tk: Tank, mp: Vector2) -> bool:
	# Disc is centered on the cabin (firing origin).
	return mp.distance_to(tk.barrel_root()) <= AIM_DISC_R


## Snap the tank's aim_angle and power to the mouse position relative to the
## firing origin. angle = atan2 of the direction; power = clamped distance.
func _apply_mouse_aim(tk: Tank, mp: Vector2) -> void:
	var origin: Vector2 = tk.barrel_root()
	var d: Vector2 = mp - origin
	if d.length() < 2.0:
		return
	# Direction from origin to mouse = world aim direction. aim_vector() is
	# (cos, -sin), so aim_angle = atan2(-d.y, d.x).
	tk.aim_angle = atan2(-d.y, d.x)
	tk.aim_angle = clamp(tk.aim_angle, 0.05, PI - 0.05)  # forward arc only
	# power from radial distance within the disc
	var p: float = clamp(d.length() / AIM_DISC_R, 0.1, 1.0)
	tk.power = p


func _physics_process(delta: float) -> void:
	if over or not turn_active or firing:
		return
	var tk := active_tank()
	if tk == null or not tk.alive or tk.is_ai:
		return
	# Aim: arrows only. Up/Down adjusts power, Left/Right adjusts angle.
	var aim_speed := 1.4
	var pow_speed := 0.9
	if Input.is_key_pressed(KEY_LEFT):
		tk.aim_angle += aim_speed * delta
	if Input.is_key_pressed(KEY_RIGHT):
		tk.aim_angle -= aim_speed * delta
	if Input.is_key_pressed(KEY_UP):
		tk.power = clamp(tk.power + pow_speed * delta, 0.1, 1.0)
	if Input.is_key_pressed(KEY_DOWN):
		tk.power = clamp(tk.power - pow_speed * delta, 0.1, 1.0)
	tk.aim_angle = clamp(tk.aim_angle, 0.05, PI - 0.05)
	# Move: A/D travel along the terrain surface, consuming fuel.
	var move_speed: float = 120.0  # surface px per second
	if Input.is_key_pressed(KEY_A):
		tk.try_move(-move_speed * delta, terrain)
	if Input.is_key_pressed(KEY_D):
		tk.try_move(move_speed * delta, terrain)


# ---------------------------------------------------------------------------
# Weapon selection
# ---------------------------------------------------------------------------
const QUICK_SLOTS := [1, 2, 7, 15, 21, 26, 31, 45]

func _select_quick(slot: int) -> void:
	if slot < 0 or slot >= QUICK_SLOTS.size():
		return
	var tk := active_tank()
	if tk:
		tk.weapon_id = QUICK_SLOTS[slot]

func _cycle_weapon(dir: int) -> void:
	var tk := active_tank()
	if tk == null:
		return
	tk.weapon_id = ((tk.weapon_id - 1 + dir) % WeaponDB.count()) + 1


# ---------------------------------------------------------------------------
# Firing
# ---------------------------------------------------------------------------
func _fire() -> void:
	var tk := active_tank()
	if tk == null or not tk.alive:
		return
	turn_active = false
	firing = true
	var w := WeaponDB.get_weapon(tk.weapon_id)
	if w.is_empty():
		_end_turn()
		return

	# Laser: instant beam, no projectile travel
	if w.type == "laser":
		_fire_laser(tk, w)
		# small delay then end turn
		get_tree().create_timer(0.8).timeout.connect(_after_fire_resolve)
		return

	# Rain: spawn N bullets from the top of the screen above the target area
	if w.type == "rain":
		_fire_rain(tk, w)
		return

	# Spread: multiple bullets at once
	var count := int(w.get("spread_count", 0))
	if count > 1:
		_fire_spread(tk, w, count)
	else:
		_spawn_projectile(tk, w, tk.barrel_tip(), tk.aim_vector(), _power_to_speed(tk.power))

	# Apply x2 buff consumption: buff stays active for the turn; we let it
	# expire naturally. (Damage multiplier is read at explosion time.)


func _power_to_speed(p: float) -> float:
	return 200.0 + p * 700.0


func _spawn_projectile(owner: Tank, w: Dictionary, start: Vector2, dir: Vector2, speed: float) -> Projectile:
	var p := Projectile.new()
	add_child(p)
	p.launch(w, owner, start, dir, speed, self)
	projectiles.append(p)
	return p


func _fire_spread(owner: Tank, w: Dictionary, count: int) -> void:
	var base_dir := owner.aim_vector()
	var spread: float = deg_to_rad(float(w.get("spread", 20.0)))
	for i in count:
		var off: float = spread * (float(i) / float(max(1, count - 1)) - 0.5) if count > 1 else 0.0
		var d := base_dir.rotated(off)
		_spawn_projectile(owner, w, owner.barrel_tip(), d, _power_to_speed(owner.power))
	# spread fire resolves when all projectiles are done


func _fire_rain(owner: Tank, w: Dictionary) -> void:
	var count := int(w.get("spread_count", 4))
	var spread: float = float(w.get("rain_spread", 300.0))
	# target around a point above the nearest enemy (or center)
	var target := owner.position
	var foe := nearest_enemy_tank(owner)
	if foe:
		target = foe.position
	for i in count:
		var x: float = target.x + Game.rng.randf_range(-spread, spread) * 0.5
		x = clamp(x, 40.0, terrain.width - 40.0)
		var start := Vector2(x, -30.0)
		var dir := Vector2(0.0, 1.0)
		var speed := 260.0
		_spawn_projectile(owner, w, start, dir, speed)
	# rain resolves when projectiles are done


func _fire_laser(owner: Tank, w: Dictionary) -> void:
	var origin := owner.barrel_tip()
	var dir := owner.aim_vector()
	# march along the beam
	var pos := origin
	var step := dir * 3.0
	var hit_pos := origin
	var max_steps := 420
	for i in max_steps:
		pos += step
		if terrain.is_solid_at(pos.x, pos.y) or pos.x < 0 or pos.x > terrain.width or pos.y < 0 or pos.y > terrain.height:
			hit_pos = pos
			break
		hit_pos = pos
		# damage any tank along the beam (except owner)
		for tk in tanks:
			if tk == owner or not tk.alive:
				continue
			if tk.position.distance_to(pos) < 18.0:
				tk.take_damage(w.damage * Game.damage_multiplier_for(owner))
	# carve a thin trench along the beam
	_carve_beam(origin, hit_pos, w.get("laser_width", 4.0) * 0.5)
	# visual
	_draw_laser_flash(origin, hit_pos, w)
	float_text(origin + Vector2(0, -20), "ZAP!", w.color)


func _carve_beam(from: Vector2, to: Vector2, half_w: float) -> void:
	var dist := from.distance_to(to)
	var steps := int(dist / 3.0) + 1
	for i in steps:
		var p := from.lerp(to, float(i) / steps)
		terrain.carve_circle(p.x, p.y, half_w)


func _draw_laser_flash(from: Vector2, to: Vector2, w: Dictionary) -> void:
	# Use a temporary Line2D-like effect via an Explosion-ish node? Simpler: queue a float_text and a short-lived node.
	var ln := Line2D.new()
	ln.add_point(from)
	ln.add_point(to)
	ln.default_color = w.color
	ln.width = w.get("laser_width", 4.0)
	ln.z_index = 8
	add_child(ln)
	# fade out
	var tw := create_tween()
	tw.tween_property(ln, "modulate:a", 0.0, 0.25)
	tw.tween_callback(ln.queue_free)


# ---------------------------------------------------------------------------
# Projectile resolution callbacks
# ---------------------------------------------------------------------------
func on_projectile_done(p: Projectile) -> void:
	if is_instance_valid(p) and projectiles.has(p):
		projectiles.erase(p)
	_check_firing_done()


func _check_firing_done() -> void:
	if firing and projectiles.is_empty():
		_after_fire_resolve()


func _after_fire_resolve() -> void:
	# settle tanks that may be floating after terrain changes
	for tk in tanks:
		if tk.alive:
			_settle_tank_if_floating(tk)
	if not over:
		_end_turn()


func _settle_tank_if_floating(tk: Tank) -> void:
	# If the ground directly under the tank is gone, drop it until it lands.
	if not terrain.is_solid_at(tk.position.x, tk.position.y + tk.CONTACT + 1):
		var surf: float = terrain.surface_y_at(tk.position.x, tk.position.y)
		if surf >= terrain.height:
			# no ground at all -> fall off (kill)
			tk.take_damage(tk.hp)
		else:
			tk.position.y = surf - tk.CONTACT


# ---------------------------------------------------------------------------
# Explosions
# ---------------------------------------------------------------------------
func on_explode(pos: Vector2, w: Dictionary, owner: Tank, dmg_scale: float = 1.0, is_blackhole_blast: bool = false) -> void:
	var dmg: float = float(w.get("damage", 0.0)) * dmg_scale * Game.damage_multiplier_for(owner)
	var r: float = float(w.get("radius", 20.0))
	# carve terrain
	terrain.carve_circle(pos.x, pos.y, r)
	# damage tanks in radius (linear falloff)
	for tk in tanks:
		if not tk.alive:
			continue
		var d := tk.position.distance_to(pos)
		if d <= r + 16.0:
			var falloff: float = clamp(1.0 - d / (r + 16.0), 0.0, 1.0)
			tk.take_damage(dmg * falloff)
	# explosion visual
	var ex := preload("res://scripts/Explosion.gd").new()
	add_child(ex)
	ex.position = pos
	ex.setup(r, Color(w.get("color", Color(1, 0.6, 0.2))))
	# shake-ish float text
	float_text(pos + Vector2(0, -r), str(int(dmg)), Color(1, 0.9, 0.4))
	# chance to drop a pickup from big explosions
	if r >= 26.0 and Game.rng.randf() < 0.12:
		_maybe_drop_pickup_at(pos.x)


# ---------------------------------------------------------------------------
# Child projectiles (cluster splits)
# ---------------------------------------------------------------------------
func spawn_child(w: Dictionary, owner: Tank, start: Vector2, dir: Vector2, speed: float, split_again: bool) -> void:
	var p := Projectile.new()
	add_child(p)
	# children are 'basic' and shouldn't split again unless split_again
	var cw := w.duplicate()
	if not split_again:
		cw.split_count = 0
		cw.split_at_apex = false
	p.launch(cw, owner, start, dir, speed, self)
	p.is_child = true
	projectiles.append(p)


# ---------------------------------------------------------------------------
# Effect zones (fire, blackhole)
# ---------------------------------------------------------------------------
func spawn_effect_zone(kind: String, pos: Vector2, w: Dictionary, owner: Tank) -> void:
	var z := preload("res://scripts/EffectZone.gd").new()
	add_child(z)
	z.position = pos
	z.setup(kind, pos, w, owner, self)
	effects.append(z)


func _process_effects(_delta: float) -> void:
	var keep: Array[EffectZone] = []
	for e in effects:
		if is_instance_valid(e):
			keep.append(e)
	effects = keep


# ---------------------------------------------------------------------------
# Mines
# ---------------------------------------------------------------------------
func register_mine(p: Projectile) -> void:
	mines.append(p)


func _process_mines(delta: float) -> void:
	var to_remove: Array = []
	for m in mines:
		if not is_instance_valid(m):
			to_remove.append(m)
			continue
		# proximity check
		var prox: float = float(m.weapon.get("prox", 60.0))
		var triggered: bool = false
		for tk in tanks:
			if not tk.alive:
				continue
			if tk == m.owner_tank:
				continue
			if tk.position.distance_to(m.position) < prox:
				triggered = true
				break
		# also explode if the mine's owner is dead and another tank near
		if triggered:
			_detonate_mine(m)
			to_remove.append(m)
	# rebuild the typed array keeping only still-valid mines (erase() fails on freed instances)
	var keep: Array[Projectile] = []
	for m in mines:
		if is_instance_valid(m) and not to_remove.has(m):
			keep.append(m)
	mines = keep


func _detonate_mine(m: Projectile) -> void:
	if not is_instance_valid(m):
		return
	var w := m.weapon
	w.type = "basic"
	on_explode(m.position, w, m.owner_tank)
	if is_instance_valid(m):
		m.queue_free()


# ---------------------------------------------------------------------------
# Pickups
# ---------------------------------------------------------------------------
func _maybe_drop_pickup() -> void:
	# drop at a random x over the playfield
	var x := Game.rng.randf_range(120.0, terrain.width - 120.0)
	_maybe_drop_pickup_at(x)


func _maybe_drop_pickup_at(x: float) -> void:
	# weighted kind selection
	var r := Game.rng.randf()
	var kind := "x2" if r < 0.45 else ("health" if r < 0.80 else "weapon")
	var pk := preload("res://scripts/Pickup.gd").new()
	add_child(pk)
	pk.setup(kind, self, x, WeaponDB.random_id())
	pickups.append(pk)


func _process_pickups(_delta: float) -> void:
	var keep: Array[Pickup] = []
	for pk in pickups:
		if is_instance_valid(pk):
			keep.append(pk)
	pickups = keep


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func nearest_enemy_tank(from: Tank) -> Tank:
	var best: Tank = null
	var best_d := 1e9
	for tk in tanks:
		if tk == from or not tk.alive:
			continue
		var d := tk.position.distance_to(from.position)
		if d < best_d:
			best_d = d
			best = tk
	return best


func float_text(pos: Vector2, text: String, color: Color) -> void:
	float_texts.append({ "pos": pos + Vector2(0, 0), "text": text, "color": color, "t": 0.0 })


func _draw() -> void:
	# float texts
	var font: Font = Game.default_font()
	for ft in float_texts:
		var a: float = clamp(1.0 - float(ft["t"]) / 1.2, 0.0, 1.0)
		var fc: Color = ft["color"]
		draw_string(font, ft["pos"], ft["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 22,
			Color(fc.r, fc.g, fc.b, a))


# ---------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------
func _begin_ai_turn() -> void:
	var tk := active_tank()
	if tk == null:
		return
	# If this AI is buffed with x2, prefer a high-damage single-shot to exploit it.
	_choose_ai_weapon(tk)
	# pick a target
	var foe := nearest_enemy_tank(tk)
	if foe == null:
		return
	# compute a rough aim solution with wind compensation
	var p := _solve_aim(tk, foe)
	ai_target_angle = p.angle
	ai_target_power = p.power
	ai_phase = "adjust"
	ai_adjust_t = 0.0
	ai_hold_t = Game.rng.randf_range(0.6, 1.4)  # think time before firing


func _choose_ai_weapon(tk: Tank) -> void:
	# If carrying x2, lean toward high single-shot damage to make it count.
	if tk.has_active_buff("x2"):
		var roll := Game.rng.randf()
		if roll < 0.5:
			tk.weapon_id = 7       # Nuke
		elif roll < 0.8:
			tk.weapon_id = 4       # Mega Shot
		else:
			tk.weapon_id = 3       # Heavy Shot
		return
	# bias toward mid-power weapons; occasionally special
	var roll := Game.rng.randf()
	if roll < 0.5:
		tk.weapon_id = Game.rng.randi_range(1, 8)  # basic family
	elif roll < 0.7:
		tk.weapon_id = Game.rng.randi_range(15, 20) # cluster
	elif roll < 0.82:
		tk.weapon_id = Game.rng.randi_range(21, 25) # roller
	elif roll < 0.92:
		tk.weapon_id = Game.rng.randi_range(26, 30) # homing
	else:
		tk.weapon_id = Game.rng.randi_range(31, 50) # napalm/mine/blackhole/laser/rain


# Multi-assignment helper — returns a Dictionary with keys angle/power.
func _solve_aim(tk: Tank, foe: Tank) -> Dictionary:
	# Simple ballistic solve: choose a launch angle toward the foe, adjust
	# power for distance + wind. aim_angle is a true world angle
	# (aim_vector = (cos, -sin)), so we pick left or right hemisphere.
	var to := foe.position - tk.position
	var dist := to.length()
	# base angle 45° up, in the foe's direction
	var ang := PI / 4.0 if to.x >= 0.0 else 3.0 * PI / 4.0
	# raise angle if target higher, lower if target lower (screen y down)
	var height_diff := to.y  # positive means foe is below
	ang -= height_diff * 0.0009
	ang = clamp(ang, 0.2, PI - 0.2)
	# power: distance based, plus wind compensation
	var base_pow: float = clamp(dist / 760.0, 0.25, 0.95)
	var wind_dir: float = sign(to.x)
	var wind_effect: float = current_wind * wind_dir  # positive = tailwind
	base_pow -= wind_effect * 0.012
	base_pow = clamp(base_pow, 0.2, 1.0)
	# add some inaccuracy based on AI level
	var inacc := 0.0
	match Game.ai_level:
		Game.AIM_LEVEL.EASY: inacc = 0.18
		Game.AIM_LEVEL.NORMAL: inacc = 0.09
		Game.AIM_LEVEL.HARD: inacc = 0.03
	ang += Game.rng.randf_range(-inacc, inacc)
	base_pow += Game.rng.randf_range(-inacc, inacc) * 0.5
	return { "angle": ang, "power": base_pow }


func _process_ai(delta: float) -> void:
	var tk := active_tank()
	if tk == null or not tk.alive:
		return
	if ai_phase == "idle":
		_begin_ai_turn()  # sets ai_target_angle/power and phase=adjust
	match ai_phase:
		"adjust":
			# ease the tank's aim/power toward the target
			ai_adjust_t += delta
			tk.aim_angle = lerp(tk.aim_angle, ai_target_angle, clamp(ai_adjust_t * 3.0, 0.0, 1.0))
			tk.aim_angle = clamp(tk.aim_angle, 0.05, PI - 0.05)
			tk.power = lerp(tk.power, ai_target_power, clamp(ai_adjust_t * 3.0, 0.0, 1.0))
			if ai_adjust_t > 0.45:
				ai_phase = "fire"
				ai_hold_t = Game.rng.randf_range(0.4, 1.0)
		"fire":
			ai_hold_t -= delta
			if ai_hold_t <= 0.0:
				ai_phase = "idle"
				_fire()


# ---------------------------------------------------------------------------
# Game over
# ---------------------------------------------------------------------------
func _show_game_over() -> void:
	var txt := "Game Over"
	if winner:
		txt = ("You Win!" if not winner.is_ai else "CPU %d Wins" % winner.player_index) if winner else "Game Over"
	float_text(Vector2(terrain.width / 2.0, terrain.height / 2.0 - 40), txt, Color.YELLOW)
	# also a panel via a label
	var lbl := Label.new()
	lbl.text = txt + "\n\nPress ENTER to return to menu"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.position = Vector2(terrain.width / 2.0 - 250, terrain.height / 2.0 - 60)
	lbl.size = Vector2(500, 120)
	add_child(lbl)
