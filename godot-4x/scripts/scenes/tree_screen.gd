## 科技/文化树（《文明》系列样式）。
## 顶部居中：科技/文化 切换按钮；主体：横向铺开的卷轴树——
## 卡片式节点（已学=绿、可学=金框、前置未满足=暗、资源不足=黄字），
## 前置关系用带箭头的连线；按住左键拖动或鼠标滚轮平移卷轴。
## 点卡片选中 → 底部详情栏（名称/费用/前置/描述 + 研究按钮）；双击卡片直接学习。
class_name TreeScreen
extends BasePage

const CARD_W := 150.0
const CARD_H := 62.0
const GAP_X := 52.0
const GAP_Y := 16.0
const PANEL_H := 120.0

enum Status { LEARNED, LEARNABLE, POOR, LOCKED }

var _kind := "tech"        # "tech" | "culture"
var _tab_tech: Button
var _tab_culture: Button
var _canvas: TreeCanvas
var _sel_id := ""
var _detail_bar: PanelContainer
var _detail_name: Label
var _detail_meta: Label
var _detail_desc: Label
var _learn_btn: Button
var _feedback_label: Label

func build() -> void:
	page_title = Loc.t("tech_culture")
	var vbox := make_content()
	vbox.add_theme_constant_override("separation", 6)
	# 顶部居中切换按钮
	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tab_row)
	_tab_tech = Button.new()
	_tab_tech.text = Loc.t("tech")
	_tab_tech.toggle_mode = true
	_tab_tech.pressed.connect(func(): _set_kind("tech"))
	tab_row.add_child(_tab_tech)
	_tab_culture = Button.new()
	_tab_culture.text = Loc.t("culture")
	_tab_culture.toggle_mode = true
	_tab_culture.pressed.connect(func(): _set_kind("culture"))
	tab_row.add_child(_tab_culture)
	# 卷轴画布
	_canvas = TreeCanvas.new()
	_canvas.custom_minimum_size = Vector2(0, 0)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.kind_provider = func(): return _kind
	_canvas.node_selected.connect(_on_canvas_node)
	vbox.add_child(_canvas)
	# 底部详情栏
	_detail_bar = PanelContainer.new()
	_detail_bar.custom_minimum_size = Vector2(0, PANEL_H)
	vbox.add_child(_detail_bar)
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 12)
	inner.add_theme_constant_override("margin_right", 12)
	inner.add_theme_constant_override("margin_top", 6)
	inner.add_theme_constant_override("margin_bottom", 6)
	_detail_bar.add_child(inner)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 16)
	inner.add_child(dh)
	var dleft := VBoxContainer.new()
	dleft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(dleft)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 16)
	_detail_name.add_theme_color_override("font_color", UiTheme.HEADING)
	dleft.add_child(_detail_name)
	_detail_meta = Label.new()
	_detail_meta.add_theme_font_size_override("font_size", 13)
	_detail_meta.add_theme_color_override("font_color", UiTheme.DIM)
	dleft.add_child(_detail_meta)
	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", 13)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dleft.add_child(_detail_desc)
	_learn_btn = Button.new()
	_learn_btn.custom_minimum_size = Vector2(120, 40)
	_learn_btn.pressed.connect(_do_learn)
	dh.add_child(_learn_btn)
	# 学习结果即时反馈（成功/失败原因）
	_feedback_label = Label.new()
	_feedback_label.add_theme_font_size_override("font_size", 12)
	_feedback_label.add_theme_color_override("font_color", UiTheme.DIM)
	vbox.add_child(_feedback_label)
	add_hint_label()

func enter_page(params: Variant = null) -> void:
	if params is Dictionary and params.get("kind", "") != "":
		_set_kind(params["kind"], true)
	else:
		_set_kind(_kind, true)
	refresh_hints()

func _set_kind(kind: String, force: bool = false) -> void:
	if kind == _kind and not force:
		return
	_kind = kind
	_tab_tech.button_pressed = _kind == "tech"
	_tab_culture.button_pressed = _kind == "culture"
	page_title = Loc.t("tech") if _kind == "tech" else Loc.t("culture")
	_sel_id = ""
	_canvas.rebuild()

func _defs() -> Dictionary:
	return GameController.game.tech_defs if _kind == "tech" else GameController.game.culture_defs

func _learned() -> Array:
	var f := GameController.player()
	return f.tech_learned if _kind == "tech" else f.culture_learned

func _learn_action(id: String) -> String:
	return GameController.game.action_learn_tech(GameController.game.player_id, id) \
		if _kind == "tech" else \
		GameController.game.action_learn_culture(GameController.game.player_id, id)

func _on_canvas_node(id: String) -> void:
	_sel_id = id
	_render_detail()

func _render_detail() -> void:
	var g := GameController.game
	if _sel_id == "" or not _defs().has(_sel_id):
		_detail_name.text = ""
		_detail_meta.text = ""
		_detail_desc.text = ""
		_learn_btn.visible = false
		return
	var def: Dictionary = _defs()[_sel_id]
	_detail_name.text = Loc.t(def.get("name", _sel_id))
	var learned := _learned().has(_sel_id)
	var parts: Array[String] = [Loc.t("cost") + " " + _cost_str(def.get("cost", {}))]
	var prereqs: Array = def.get("prereqs", [])
	if not prereqs.is_empty():
		var names: Array[String] = []
		for p in prereqs:
			var pdef: Variant = g.tech_defs.get(p, g.culture_defs.get(p))
			names.append(Loc.t(pdef.get("name", p)) if pdef != null else p)
		parts.append(Loc.t("prereqs") + " " + "、".join(names))
	var unlocks: Array = def.get("unlocks", [])
	if not unlocks.is_empty():
		parts.append(Loc.t("unlocks") + " " + "、".join(unlocks))
	_detail_meta.text = "   ".join(parts)
	_detail_desc.text = def.get("desc", "")
	_learn_btn.text = Loc.t("learned") if learned else Loc.t("learn")
	_learn_btn.disabled = learned
	_learn_btn.visible = true

func _do_learn() -> void:
	if _sel_id == "":
		return
	var msg := _learn_action(_sel_id)
	GameController.push_log(msg, msg.begins_with("失败"))
	# 页面内即时反馈（成功/失败原因，避免"点了没反应"）
	_feedback(msg, msg.begins_with("失败"))
	_canvas.rebuild()
	_render_detail()

## 学习结果即时反馈（成功/失败原因，避免"点了没反应"）。
func _feedback(msg: String, warn: bool) -> void:
	_feedback_label.text = msg
	_feedback_label.add_theme_color_override("font_color", UiTheme.C_ENEMY if warn else UiTheme.C_OWN)

func _cost_str(cost: Dictionary) -> String:
	if cost.is_empty():
		return Loc.t("cost_free")
	var parts: Array[String] = []
	for k in cost:
		parts.append("%s %d" % [Economy.RESOURCE_CN.get(k, k), int(cost[k])])
	return "、".join(parts)

func get_hints() -> Array:
	return [["drag", "drag_hint"], ["wheel", "wheel_hint"], ["Esc", "close"]]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_canvas.focus_move(Vector2(0, -1))
	elif event.is_action_pressed("ui_down"):
		_canvas.focus_move(Vector2(0, 1))
	elif event.is_action_pressed("ui_left"):
		_canvas.focus_move(Vector2(-1, 0))
	elif event.is_action_pressed("ui_right"):
		_canvas.focus_move(Vector2(1, 0))
	elif event.is_action_pressed("ui_accept"):
		_do_learn()

# ================= 卷轴画布 =================
## 树画布：计算布局（前置深度→列，拓扑序→行）、绘制卡片与连线、平移/点选。
class TreeCanvas:
	extends Control
	signal node_selected(id: String)

	var kind_provider: Callable = Callable()

	var _cards: Dictionary = {}      # id -> {pos: Vector2, status: int}
	var _ids: Array = []             # 拓扑序
	var _content := Rect2()
	var _pan := Vector2.ZERO
	var _dragging := false
	var _drag_from := Vector2.ZERO
	var _moved := 0.0
	var _focus := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func rebuild() -> void:
		_cards.clear()
		_ids.clear()
		_content = Rect2()
		_focus = ""
		var screen := kind_provider.call() as String
		if screen == "":
			return
		var game := GameController.game
		var defs: Dictionary = game.tech_defs if screen == "tech" else game.culture_defs
		var learned := _learned_of(screen)
		var all_learned: Array = []
		all_learned.append_array(game.factions[game.player_id].tech_learned)
		all_learned.append_array(game.factions[game.player_id].culture_learned)
		var p := GameController.player()
		# 深度（前置链最长）+ 拓扑序（Kahn 迭代，避免递归 lambda）
		var depth: Dictionary = {}
		var order: Dictionary = {}
		var indeg: Dictionary = {}
		var ready: Array = []
		for id in defs:
			var cnt := 0
			for pr in defs[id].get("prereqs", []):
				if defs.has(pr):
					cnt += 1
			indeg[id] = cnt
			if cnt == 0:
				ready.append(id)
		var counter := 0
		while not ready.is_empty():
			var cur = ready.pop_front()
			var d := 0
			for pr in defs[cur].get("prereqs", []):
				if defs.has(pr):
					d = maxi(d, int(depth[pr]) + 1)
			depth[cur] = d
			order[cur] = counter
			counter += 1
			for other in defs:
				if indeg[other] > 0 and defs[other].get("prereqs", []).has(cur):
					indeg[other] -= 1
					if indeg[other] == 0:
						ready.append(other)
		# 状态
		for id in defs:
			var status := Status.LEARNED
			if not learned.has(id):
				var prereq_ok := true
				for pr in defs[id].get("prereqs", []):
					if not all_learned.has(pr):
						prereq_ok = false
						break
				var affordable := p.resources.can_afford(defs[id].get("cost", {}))
				if prereq_ok:
					status = Status.LEARNABLE if affordable else Status.POOR
				else:
					status = Status.LOCKED
			_cards[id] = {"depth": int(depth[id]), "status": status}
			_ids.append(id)
		# 按深度分列、列内按拓扑序排行
		var col_rows: Dictionary = {}    # depth -> [id...]
		for id in _ids:
			var d: int = _cards[id]["depth"]
			if not col_rows.has(d):
				col_rows[d] = []
			col_rows[d].append(id)
		var rows: Dictionary = {}        # id -> 行号
		for d in col_rows:
			var list: Array = col_rows[d]
			list.sort_custom(func(a, b): return int(order[a]) < int(order[b]))
			for i in range(list.size()):
				rows[list[i]] = i
		# 布局
		_content = Rect2(20, 20, 0, 0)
		for id in _ids:
			var d: int = _cards[id]["depth"]
			var pos := Vector2(20 + d * (CARD_W + GAP_X), 20 + int(rows[id]) * (CARD_H + GAP_Y))
			_cards[id]["pos"] = pos
			_content = _content.merge(Rect2(pos, Vector2(CARD_W, CARD_H)))
		_content = _content.grow(30)
		if _ids.size() > 0:
			_focus = _ids[0]
		queue_redraw()

	func _learned_of(kind: String) -> Array:
		var f := GameController.player()
		return f.tech_learned if kind == "tech" else f.culture_learned

	func _draw() -> void:
		if _ids.is_empty():
			return
		var font := get_theme_default_font()
		# 卷轴底纹：固定铺满画布（内容在其上滚动；画在 _pan 偏移会导致只盖住局部）
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL_BG.darkened(0.3))
		# 连线（前置 → 节点）
		var game := GameController.game
		var defs: Dictionary = game.tech_defs if kind_provider.call() == "tech" else game.culture_defs
		for id in _ids:
			var pos: Vector2 = _cards[id]["pos"]
			var p0 := pos + _pan
			for pr in defs[id].get("prereqs", []):
				if not _cards.has(pr):
					continue
				var pp: Vector2 = _cards[pr]["pos"] + _pan
				var from := pp + Vector2(CARD_W, CARD_H * 0.5)
				var to := p0 + Vector2(0, CARD_H * 0.5)
				draw_line(from, to, UiTheme.BORDER, 2.0)
				var dir := (to - from).normalized()
				draw_colored_polygon(PackedVector2Array([
					to, to - dir.rotated(2.7) * 8, to - dir.rotated(-2.7) * 8]), UiTheme.BORDER)
		# 卡片
		for id in _ids:
			var card: Dictionary = _cards[id]
			var pos: Vector2 = card["pos"] + _pan
			_draw_card(id, pos, card["status"], font)
		# 焦点框
		if _focus != "" and _cards.has(_focus):
			var fp: Vector2 = _cards[_focus]["pos"] + _pan
			draw_rect(Rect2(fp - Vector2(4, 4), Vector2(CARD_W + 8, CARD_H + 8)),
				Color(UiTheme.ACCENT, 0.0), false, 2.0)

	func _draw_card(id: String, pos: Vector2, status: int, font: Font) -> void:
		var def: Dictionary = (GameController.game.tech_defs if kind_provider.call() == "tech"
			else GameController.game.culture_defs)[id]
		var sb := StyleBoxFlat.new()
		match status:
			Status.LEARNED:
				sb.bg_color = Color("1d3a26")   # 实底绿：已学习
				sb.border_color = UiTheme.C_OWN
			Status.LEARNABLE:
				sb.bg_color = Color(UiTheme.PANEL_BG, 1.0)
				sb.border_color = UiTheme.ACCENT
			Status.POOR:
				sb.bg_color = Color(UiTheme.PANEL_BG, 1.0)
				sb.border_color = UiTheme.WARN
			_:
				sb.bg_color = UiTheme.PANEL_BG.darkened(0.35)
				sb.border_color = UiTheme.BORDER
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2 if status == Status.LEARNABLE or status == Status.POOR else 1)
		draw_style_box(sb, Rect2(pos, Vector2(CARD_W, CARD_H)))
		# 名称（两行内）
		var name := Loc.t(def.get("name", id))
		var name_col := UiTheme.FG
		if status == Status.LEARNED:
			name_col = UiTheme.C_OWN
		elif status == Status.POOR:
			name_col = UiTheme.WARN
		elif status == Status.LOCKED:
			name_col = UiTheme.DIM
		draw_multiline_string(font, pos + Vector2(8, 16), name,
			HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 16, 2, 13, name_col)
		# 费用
		var cost: Dictionary = def.get("cost", {})
		if not cost.is_empty():
			var parts: Array[String] = []
			for k in cost:
				parts.append("%s%d" % [str(Economy.RESOURCE_CN.get(k, k)).left(1), int(cost[k])])
			draw_string(font, pos + Vector2(8, CARD_H - 8), "、".join(parts),
				HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 16, 11, UiTheme.DIM)

	func _screen_to_card(p: Vector2) -> String:
		for id in _cards:
			var pos: Vector2 = _cards[id]["pos"] + _pan
			if Rect2(pos, Vector2(CARD_W, CARD_H)).has_point(p):
				return id
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					if event.pressed:
						_dragging = true
						_drag_from = event.position
						_moved = 0.0
					else:
						_dragging = false
						if _moved < 5.0:
							var hit := _screen_to_card(event.position)
							if hit != "":
								_focus = hit
								queue_redraw()
								node_selected.emit(hit)
				MOUSE_BUTTON_WHEEL_UP:
					if event.pressed:
						_pan_center(Vector2(0, -40))
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.pressed:
						_pan_center(Vector2(0, 40))
				MOUSE_BUTTON_RIGHT:
					if event.pressed:
						# 右键也选中（现代树形 UI 习惯）
						var hit2 := _screen_to_card(event.position)
						if hit2 != "":
							_focus = hit2
							queue_redraw()
							node_selected.emit(hit2)
			accept_event()
		elif event is InputEventMouseMotion:
			if _dragging:
				_pan += event.relative
				_clamp_pan()
				_moved += event.relative.length()
				queue_redraw()

	func _pan_center(delta: Vector2) -> void:
		_pan += delta
		_clamp_pan()
		queue_redraw()

	func _clamp_pan() -> void:
		var max_x := maxf(0.0, _content.size.x - size.x + 40)
		var max_y := maxf(0.0, _content.size.y - size.y + 40)
		_pan.x = clampf(_pan.x, -max_x, 40)
		_pan.y = clampf(_pan.y, -max_y, 40)

	func focus_move(delta: Vector2) -> void:
		if _ids.is_empty():
			return
		var cur := _ids.find(_focus)
		if cur < 0:
			cur = 0
		var d: int = _cards[_focus]["depth"] if _focus != "" else 0
		# 简单邻近：列 ±1 内深度最近的卡片
		if delta.x != 0:
			var best := ""
			var best_d := 1e18
			for id in _ids:
				var dd: int = _cards[id]["depth"]
				if dd == d + int(delta.x):
					var pos: Vector2 = _cards[id]["pos"]
					var cur_pos: Vector2 = _cards[_focus]["pos"]
					var dist := pos.distance_to(cur_pos)
					if dist < best_d:
						best_d = dist
						best = id
			if best != "":
				_focus = best
		elif delta.y != 0:
			var pos2: Vector2 = _cards[_focus]["pos"]
			var best2 := ""
			var best_d2 := 1e18
			for id in _ids:
				if id == _focus:
					continue
				var p2: Vector2 = _cards[id]["pos"]
				if signf(p2.y - pos2.y) == delta.y and absf(p2.y - pos2.y) > absf(p2.x - pos2.x) * 0.6:
					var dist2 := p2.distance_to(pos2)
					if dist2 < best_d2:
						best_d2 = dist2
						best2 = id
			if best2 != "":
				_focus = best2
		if _focus != "":
			# 焦点居中显示
			_pan = -_cards[_focus]["pos"] + size / 2.0 - Vector2(CARD_W / 2, CARD_H / 2)
			_clamp_pan()
			queue_redraw()
			node_selected.emit(_focus)
