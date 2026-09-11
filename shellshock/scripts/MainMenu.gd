# MainMenu.gd — Title screen + setup. Lets the player choose player count,
# AI difficulty, and map (or random), then launches the Battle scene.
# The Battle scene reads its config from the Game autoload.
extends Control

var title_label: Label
var info_label: Label
var player_count: int = 2
var ai_difficulty: int = 1  # 0 easy, 1 normal, 2 hard
var map_choice: int = -1    # -1 random
var map_names := ["Random", "Rolling Hills", "Mesa Plateau", "Rocky Valley", "Twin Peaks"]
var _font: Font


func _ready() -> void:
	_font = Game.default_font()
	# Full-screen dark background
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.18)
	bg.size = get_viewport_rect().size
	add_child(bg)

	title_label = Label.new()
	title_label.text = "SHELLSHOCK LIVE"
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 70)
	title_label.size = Vector2(1280, 80)
	add_child(title_label)

	info_label = Label.new()
	info_label.text = "Single-player artillery combat — Godot 4.6"
	info_label.add_theme_font_size_override("font_size", 20)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.position = Vector2(0, 150)
	info_label.size = Vector2(1280, 30)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	add_child(info_label)

	# Controls list
	var ctl := Label.new()
	ctl.text = "Controls:  WASD/Arrows = aim & power   1-8 = weapons   Space/Enter = fire   Tab = cycle   ESC = menu"
	ctl.add_theme_font_size_override("font_size", 16)
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctl.position = Vector2(0, 540)
	ctl.size = Vector2(1280, 30)
	ctl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	add_child(ctl)

	# Start prompt
	var start := Label.new()
	start.text = "Press ENTER to start battle   |   ESC to quit"
	start.add_theme_font_size_override("font_size", 22)
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.position = Vector2(0, 610)
	start.size = Vector2(1280, 30)
	start.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	add_child(start)

	# Pre-set Game state with sensible defaults (in case user hits ENTER immediately)
	Game.player_count = 2
	Game.ai_level = Game.AIM_LEVEL.NORMAL
	Game.map_choice = -1


func _draw() -> void:
	var y := 210
	# Player count
	_draw_line(y, "Players", "← 2 (You + 1 CPU) →   [1-4]")
	y += 36
	_draw_line(y, "AI Difficulty", _diff_name(ai_difficulty) + "   [E/N/H]")
	y += 36
	_draw_line(y, "Map", map_names[map_choice + 1] + "   [M to cycle]")
	# Decorative tanks
	var t := Time.get_ticks_msec() / 1000.0
	for i in 4:
		var x := 200.0 + i * 220.0
		var yy := 470.0 + sin(t * 2.0 + i) * 4.0
		draw_circle(Vector2(x, yy), 18, Game.tank_color(i))
		draw_rect(Rect2(x - 18, yy + 8, 36, 8), Color(0.2, 0.2, 0.25), true)
		var ang := sin(t + i) * 0.3 - 0.5
		draw_line(Vector2(x, yy), Vector2(x + cos(ang) * 26, yy - sin(ang) * 26), Color(0.2, 0.2, 0.25), 4)


func _diff_name(d: int) -> String:
	return ["Easy", "Normal", "Hard"][d]


func _draw_line(y: int, key: String, val: String) -> void:
	draw_string(_font, Vector2(440, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.85, 0.9))
	draw_string(_font, Vector2(640, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.3))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER, KEY_SPACE:
				Game.player_count = player_count
				Game.ai_level = ai_difficulty
				Game.map_choice = map_choice
				get_tree().change_scene_to_file("res://scenes/Battle.tscn")
			KEY_ESCAPE:
				get_tree().quit()
			KEY_LEFT:
				player_count = max(2, player_count - 1)
			KEY_RIGHT:
				player_count = min(4, player_count + 1)
			KEY_E:
				ai_difficulty = 0
			KEY_N:
				ai_difficulty = 1
			KEY_H:
				ai_difficulty = 2
			KEY_M:
				map_choice = (map_choice + 2) % 5 - 1  # -1..3
