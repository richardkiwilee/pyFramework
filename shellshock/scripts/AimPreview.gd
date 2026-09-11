# AimPreview.gd — Draws the predicted trajectory of the current shot as a
# dense dashed line, plus an aim arrow at the active tank. Updated each frame
# while a human is aiming. Wind and gravity match the Projectile physics.
extends Node2D
class_name AimPreview

var battle: Node
var tank: Tank
var show_preview: bool = true

const DASH_LEN: float = 7.0
const GAP_LEN: float = 4.0


func setup(p_battle: Node) -> void:
	battle = p_battle
	z_index = 3


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if battle == null or not show_preview:
		return
	tank = battle.active_tank()
	if tank == null or not tank.alive:
		return
	# Translucent aim disc around the firing origin (human turn only).
	# Shows the drag area for setting angle + power with the mouse.
	if not tank.is_ai:
		_draw_aim_disc()
	# Aim arrow from barrel tip
	var origin: Vector2 = tank.barrel_tip()
	var dir: Vector2 = tank.aim_vector()
	var arr_end: Vector2 = origin + dir * (20.0 + tank.power * 40.0)
	draw_line(origin, arr_end, Color(1, 1, 1, 0.7), 2.0)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = arr_end
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - dir * 10.0 + perp * 5.0,
		tip - dir * 10.0 - perp * 5.0,
	]), Color(1, 1, 1, 0.7))

	# Trajectory simulation (densely sampled for a tight dashed line)
	var w: Dictionary = WeaponDB.get_weapon(tank.weapon_id)
	if w.is_empty() or String(w.get("type", "")) == "laser":
		_draw_laser(origin, dir)
		return
	var pos: Vector2 = origin
	var vel: Vector2 = dir * (200.0 + tank.power * 700.0)
	var g: float = 420.0
	var wind: float = battle.current_wind * 60.0
	var pts: PackedVector2Array = []
	var steps: int = 240
	var dt: float = 0.02
	for i in steps:
		vel.x += wind * dt
		vel.y += g * dt * float(w.get("weight", 1.0))
		pos += vel * dt
		pts.append(pos)
		if battle.terrain.is_solid_at(pos.x, pos.y) or pos.y > battle.terrain.height + 50:
			break
	_draw_dashed_polyline(pts, Color(1, 1, 1, 0.75), 2.0)
	# landing marker
	if pts.size() > 0:
		var endp: Vector2 = pts[pts.size() - 1]
		draw_circle(endp, 4.0, Color(1, 1, 1, 0.5))
		draw_arc(endp, 4.0, 0, TAU, 16, Color(1, 1, 1, 0.8), 1.0)


## Translucent disc centered on the firing origin (cabin). The radius encodes
## the maximum power. While the mouse is held inside, dragging sets the aim.
func _draw_aim_disc() -> void:
	var center: Vector2 = tank.barrel_root()
	var r: float = float(battle.AIM_DISC_R)
	# soft fill
	draw_circle(center, r, Color(1, 1, 1, 0.06))
	# outline ring
	draw_arc(center, r, 0, TAU, 48, Color(1, 1, 1, 0.35), 1.5)
	# power ring: show the current power as a brighter arc radius
	var pr: float = r * tank.power
	if pr > 2.0:
		draw_arc(center, pr, 0, TAU, 48, Color(1, 1, 1, 0.18), 1.0)
	# center dot
	draw_circle(center, 2.0, Color(1, 1, 1, 0.6))


## Draw a polyline as a dashed line (dash, gap, dash, gap...). Dense dashes.
func _draw_dashed_polyline(pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		# single point -> draw a dot
		if pts.size() == 1:
			draw_circle(pts[0], width, col)
		return
	var budget: float = DASH_LEN  # start by drawing a dash
	var drawing: bool = true
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg < 0.001:
			continue
		var d: Vector2 = (b - a) / seg
		var traveled: float = 0.0
		while traveled < seg:
			var remain: float = seg - traveled
			if drawing:
				var take: float = min(budget, remain)
				var p0: Vector2 = a + d * traveled
				var p1: Vector2 = a + d * (traveled + take)
				draw_line(p0, p1, col, width)
				traveled += take
				budget -= take
				if budget <= 0.001:
					budget = GAP_LEN
					drawing = false
			else:
				var skip: float = min(budget, remain)
				traveled += skip
				budget -= skip
				if budget <= 0.001:
					budget = DASH_LEN
					drawing = true


func _draw_laser(origin: Vector2, dir: Vector2) -> void:
	# straight beam to first solid pixel or screen edge
	var pos: Vector2 = origin
	var step: Vector2 = dir * 4.0
	for i in 320:
		pos += step
		if battle.terrain.is_solid_at(pos.x, pos.y) or pos.x < 0 or pos.x > battle.terrain.width or pos.y > battle.terrain.height:
			break
	# dashed laser line
	var pts: PackedVector2Array = [origin, pos]
	_draw_dashed_polyline(pts, Color(1, 0.3, 0.3, 0.7), 2.0)
