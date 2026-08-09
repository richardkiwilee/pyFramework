## 部队九宫格视图（对应 army.py 3x3 + army scene 的九宫格编辑）。
## 显示前/中/后三排、每个格子内的单位（名称 + 词条/角色缩写）、队长标记。
## 可选键盘焦点（编辑模式）：方向键移动焦点格，回车/空格触发 cell_selected。
class_name Grid9
extends Control

signal cell_selected(slot: int)

const CELL := 104.0
const GAP := 6.0
const ROW_CN: Array[String] = ["前", "中", "后"]

var army: Armies.Army = null
var unit_index: Dictionary = {}
var focus_slot := -1   # -1 = 无焦点
var show_rows := true
var editable := false

func _init() -> void:
	custom_minimum_size = Vector2(CELL * 3 + GAP * 2, CELL * 3 + GAP * 2 + 24)
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_army(a: Armies.Army, ui: Dictionary) -> void:
	army = a
	unit_index = ui
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	# 排标签
	if show_rows:
		for r in range(3):
			draw_string(font, Vector2(2, r * (CELL + GAP) + 16), Loc.t(ROW_CN[r]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.DIM)
	for slot in range(9):
		var col := slot % 3
		var row := slot / 3
		var pos := Vector2(26 + col * (CELL + GAP), 8 + row * (CELL + GAP))
		var r := Rect2(pos, Vector2(CELL, CELL))
		# 底框
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.PANEL_BG.darkened(0.25)
		sb.set_corner_radius_all(8)
		sb.border_color = UiTheme.BORDER
		sb.set_border_width_all(1)
		draw_style_box(sb, r)
		# 焦点
		if editable and slot == focus_slot:
			var fsb := StyleBoxFlat.new()
			fsb.bg_color = Color(UiTheme.ACCENT, 0.15)
			fsb.set_corner_radius_all(8)
			fsb.border_color = UiTheme.ACCENT
			fsb.set_border_width_all(2)
			draw_style_box(fsb, r)
		# 格子内容
		var uid = army.grid[slot] if army != null else null
		if uid != null and unit_index.has(uid):
			var u: Units.Unit = unit_index[uid]
			var name_col := UiTheme.FG
			if u.is_hero:
				name_col = UiTheme.GOLD
			draw_string(font, pos + Vector2(8, 20), Loc.t(u.name),
				HORIZONTAL_ALIGNMENT_LEFT, CELL - 16, 14, name_col)
			var tagstr := _tag_abbr(u)
			draw_string(font, pos + Vector2(8, 40), Loc.t(tagstr),
				HORIZONTAL_ALIGNMENT_LEFT, CELL - 16, 12, UiTheme.DIM)
			# HP 条
			var hp_frac := clampf(float(u.cur_hp) / maxf(1.0, float(u.base.get("hp", 1))), 0.0, 1.0)
			draw_rect(Rect2(pos + Vector2(8, 52), Vector2(CELL - 16, 6)), Color(0.2, 0.2, 0.25))
			var hp_col := UiTheme.C_OWN if hp_frac > 0.5 else (UiTheme.WARN if hp_frac > 0.25 else UiTheme.C_ENEMY)
			draw_rect(Rect2(pos + Vector2(8, 52), Vector2((CELL - 16) * hp_frac, 6)), hp_col)
			draw_string(font, pos + Vector2(8, 80), "Lv%d %s" % [u.level, ("队长" if army.captain_id == u.id else "")],
				HORIZONTAL_ALIGNMENT_LEFT, CELL - 16, 12,
				UiTheme.ACCENT2 if army.captain_id == u.id else UiTheme.DIM)
			if not u.alive:
				draw_string(font, pos + Vector2(8, 96), Loc.t("阵亡"),
					HORIZONTAL_ALIGNMENT_LEFT, CELL - 16, 12, UiTheme.C_ENEMY)
		else:
			draw_string(font, pos + Vector2(CELL / 2 - 6, CELL / 2 + 4), "空",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.DIM.darkened(0.3))

func _tag_abbr(u: Units.Unit) -> String:
	var parts: Array[String] = []
	for t in u.tags:
		parts.append(Units.TAG_CN.get(t, t))
	return "/".join(parts)

func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for slot in range(9):
			var col := slot % 3
			var row := slot / 3
			var r := Rect2(26 + col * (CELL + GAP), 8 + row * (CELL + GAP), CELL, CELL)
			if r.has_point(event.position):
				focus_slot = slot
				queue_redraw()
				cell_selected.emit(slot)
				accept_event()
				return

## 焦点移动；返回新的焦点槽（-1 越界）。
func focus_move(delta: Vector2) -> int:
	if focus_slot < 0:
		focus_slot = 0
	var col := focus_slot % 3
	var row := focus_slot / 3
	col = clampi(col + int(delta.x), 0, 2)
	row = clampi(row + int(delta.y), 0, 2)
	focus_slot = row * 3 + col
	queue_redraw()
	return focus_slot
