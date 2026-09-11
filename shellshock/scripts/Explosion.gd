# Explosion.gd — One-shot visual for a blast. Does not deal damage itself;
# the Battle scene applies damage at on_explode time, then spawns this node for
# the visual only. Lifetime ~0.5s.
extends Node2D
class_name Explosion

var radius: float = 40.0
var color: Color = Color(1.0, 0.6, 0.2)
var t: float = 0.0
var life: float = 0.5


func setup(p_radius: float, p_color: Color) -> void:
	radius = p_radius
	color = p_color
	z_index = 7


func _process(delta: float) -> void:
	t += delta
	queue_redraw()
	if t >= life:
		queue_free()


func _draw() -> void:
	var p := t / life
	# expanding ring + fading core
	var r := radius * (0.3 + p * 1.1)
	var a := 1.0 - p
	draw_circle(Vector2.ZERO, r * 0.7, Color(color.r, color.g, color.b, a * 0.5))
	draw_circle(Vector2.ZERO, r, Color(1.0, 1.0, 0.7, a * 0.25))
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(1, 1, 1, a * 0.6), 3.0)
