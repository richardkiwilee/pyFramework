extends Control
## BoardGrid - A single team formation board showing a 3x2 hexagonal grid.
class_name BoardGrid

const HEX_W := 78.0
const HEX_H := 62.0
const FRONT_Y := 58.0
const BACK_Y := 130.0
const X_OFFSETS := [120.0, 210.0, 300.0]  # X positions for slots 0,1,2 and 3,4,5

var team_index: int = -1
var team_data: Dictionary = {}
var is_active: bool = false
var hovered_slot: int = -1
var selected_slot: int = -1
var unit_icons: Dictionary = {}  # slot → icon string
var unit_names: Dictionary = {}  # slot → name string

# signals
signal slot_clicked(slot: int, board: BoardGrid)
signal slot_right_clicked(slot: int, board: BoardGrid)


func _ready() -> void:
	custom_minimum_size = Vector2(380, 210)
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh(team_idx: int, units: Array, active: bool) -> void:
	team_index = team_idx
	team_data = {"units": units}
	is_active = active
	unit_icons.clear()
	unit_names.clear()

	for i in range(units.size()):
		var cid = units[i]
		if cid != "":
			var ch = DataManager.get_character(cid)
			unit_icons[i] = _char_icon(ch)
			unit_names[i] = ch.get("name_zh", "???")

	queue_redraw()


func _char_icon(ch: Dictionary) -> String:
	var cls = ch.get("class_zh", "")
	var cls_icons := {
		"领主": "👑", "君主": "👑", "女祭司": "🙏", "斗士": "🛡️", "先锋": "🛡️",
		"兵士": "🔱", "剑士": "⚔️", "剑豪": "⚔️", "佣兵": "⚔️", "重装步兵": "🛡️",
		"角斗士": "💪", "狂战士": "💪", "战士": "🔨", "扫荡者": "🔨",
		"猎人": "🏹", "神猎手": "🏹", "射手": "🏹", "盗贼": "🗡️",
		"骑士": "🐴", "重骑士": "🐴", "白骑士": "🐴", "黑骑士": "🐴",
		"牧师": "✨", "主教": "✨", "法师": "🔥", "术士": "🔥",
		"魔女": "❄️", "女巫": "❄️", "萨满": "🌿", "德鲁伊": "🌿",
		"狮鹫骑士": "🦅", "飞龙骑士": "🐉", "精灵剑士": "⚔️",
	}
	return cls_icons.get(cls, "👤")


func _draw() -> void:
	# Draw team label
	var label_color := UITheme.GOLD_BRIGHT if is_active else UITheme.INK_DIM
	draw_string(get_theme_default_font(), Vector2(10, 18), "第%d队" % (team_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_color)

	# Draw hex cells
	for slot in range(6):
		var x = X_OFFSETS[slot % 3]
		var y = FRONT_Y if slot < 3 else BACK_Y
		var pos = Vector2(x, y)

		# Determine colors
		var is_light := (slot % 2 == (0 if slot < 3 else 1))
		var fill_color: Color
		if slot == selected_slot and is_active:
			fill_color = Color(1.0, 0.85, 0.4, 0.4)
		elif unit_icons.has(slot):
			fill_color = UITheme.PANEL2
		elif is_light:
			fill_color = Color("c9b48f") if is_active else Color("c9b48f").darkened(0.5)
		else:
			fill_color = Color("6b5a42") if is_active else Color("6b5a42").darkened(0.5)

		_draw_hex(pos, fill_color, UITheme.LINE if is_active else UITheme.LINE.darkened(0.5))

		# Draw unit icon and name
		if unit_icons.has(slot):
			var icon = unit_icons[slot]
			var name = unit_names.get(slot, "")
			draw_string(get_theme_default_font(), pos + Vector2(-16, -26), icon,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
			if is_active:
				draw_string(get_theme_default_font(), pos + Vector2(0, 12), name,
					HORIZONTAL_ALIGNMENT_CENTER, -1, 10, UITheme.INK)


func _draw_hex(center: Vector2, fill: Color, border: Color) -> void:
	var points := PackedVector2Array()
	var sides := 6
	var radius := 38.0
	for i in range(sides):
		var angle = PI / 6 + i * TAU / sides
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.65))
	draw_colored_polygon(points, fill)
	draw_polyline(points, border, 1.5)


func _gui_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventMouseButton and event.pressed:
		var mp = event.position
		for slot in range(6):
			var x = X_OFFSETS[slot % 3]
			var y = FRONT_Y if slot < 3 else BACK_Y
			if mp.distance_to(Vector2(x, y)) < 38:
				if event.button_index == MOUSE_BUTTON_LEFT:
					selected_slot = slot
					slot_clicked.emit(slot, self)
					queue_redraw()
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					slot_right_clicked.emit(slot, self)
				return
