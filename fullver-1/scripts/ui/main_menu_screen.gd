class_name MainMenuScreen
extends Control
## =============================================================================
## MainMenuScreen — 主菜单场景（readme 场景结构第 1 项）
## =============================================================================
## 职责：新游戏 / 继续 / 读档 / 设置（语言、音量）/ 退出。
## 场景切换走 GameManager.change_scene（zfoo SceneHelper 转场）。
## =============================================================================

var _button_box: VBoxContainer


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG
	add_child(bg)

	var panel := PanelContainer.new()
	panel.size = Vector2(420, 560)
	UITheme.center(panel)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(28))
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	# 标题
	var title := UITheme.make_label(I18n.t("ui.menu.title"), 34, UITheme.GOLD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(UITheme.make_label(I18n.t("app.title"), 13, UITheme.INK_DIM))

	# 主按钮
	_add_menu_button(box, I18n.t("ui.menu.new_game"), _on_new_game, true)
	_add_menu_button(box, I18n.t("ui.menu.continue"), _on_continue, false)
	_add_menu_button(box, I18n.t("ui.menu.load_game"), _on_load, false)
	_add_menu_button(box, I18n.t("ui.menu.settings"), _on_settings, false)
	_add_menu_button(box, I18n.t("ui.menu.quit"), _on_quit, false)

	_button_box = box


func _add_menu_button(box: VBoxContainer, text: String, callback: Callable, primary: bool) -> void:
	var bt := UITheme.make_button(text, UITheme.gold_button_style() if primary else UITheme.default_button_style(), 16)
	if not primary:
		bt.add_theme_color_override("font_color", UITheme.INK)
	bt.custom_minimum_size = Vector2(0, 46)
	bt.pressed.connect(callback)
	box.add_child(bt)


# ==================================================================
#  按钮动作
# ==================================================================

func _on_new_game() -> void:
	GameManager.new_game()
	await GameManager.change_scene("res://scenes/world_map.tscn")


func _on_continue() -> void:
	if GameManager.has_current_game():
		await GameManager.change_scene("res://scenes/world_map.tscn")
	else:
		Alert.alert(I18n.t("ui.menu.empty_slot"), UITheme.INK2)


func _on_load() -> void:
	_show_save_slots()


func _on_settings() -> void:
	_show_settings()


func _on_quit() -> void:
	await gdf.quit(0)


# ==================================================================
#  读档面板（模态）
# ==================================================================

func _show_save_slots() -> void:
	var saves: Array = GameManager.list_saves()
	var panel := _open_modal(I18n.t("ui.menu.select_slot"))
	var box: VBoxContainer = panel.get_child(0)
	if saves.is_empty():
		box.add_child(UITheme.make_label(I18n.t("ui.menu.empty_slot"), 13, UITheme.INK_DIM))
	for s in saves:
		var slot: int = int(s.get("slot", 0))
		var turn: int = int(s.get("turn", 0))
		var bt := UITheme.make_button("%s %d — %s" % [I18n.t("ui.menu.slot"), slot, I18n.t("ui.world.turn", [turn])], UITheme.default_button_style(), 13)
		bt.add_theme_color_override("font_color", UITheme.INK)
		var slot_copy := slot
		bt.pressed.connect(func() -> void:
			if GameManager.load_game(slot_copy):
				_switch_to_world()
			else:
				Alert.alert(I18n.t("ui.menu.load_failed"), UITheme.RED))
		box.add_child(bt)


func _switch_to_world() -> void:
	await GameManager.change_scene("res://scenes/world_map.tscn")


# ==================================================================
#  设置面板（模态）：语言 + 音量
# ==================================================================

func _show_settings() -> void:
	var panel := _open_modal(I18n.t("ui.menu.settings"))
	var box: VBoxContainer = panel.get_child(0)

	# 语言切换
	box.add_child(UITheme.make_label(I18n.t("ui.menu.language"), 14, UITheme.INK))
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	box.add_child(lang_row)
	for lang in ["zh", "en"]:
		var lang_name: String = lang
		var bt := UITheme.make_button(lang_name, UITheme.default_button_style(), 13)
		bt.add_theme_color_override("font_color", UITheme.INK if I18n.language() != lang_name else UITheme.GOLD_BRIGHT)
		# ⚠️ 闭包陷阱 + 类型：循环变量是 Variant，必须显式复制为 String
		var lang_copy: String = lang_name
		bt.pressed.connect(func() -> void:
			I18n.set_language(lang_copy)
			# 语言切换后重进主菜单（文案全量刷新，最可靠的方式）
			await GameManager.change_scene("res://scenes/main_menu.tscn"))
		lang_row.add_child(bt)

	# 音量（Music 总线；zfoo Audio 无音量 getter，读 Setting 持久化值）
	box.add_child(UITheme.make_label(I18n.t("ui.menu.volume"), 14, UITheme.INK))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Setting.get_float("volume_music", 1.0)
	slider.value_changed.connect(func(v: float) -> void:
		Audio.set_audio_bus_volume_linear(Audio.AudioBusType.Music, v)
		# ⚠️ zfoo 约定：Setting set 后必须显式 save()
		Setting.set_float("volume_music", v)
		Setting.save())
	box.add_child(slider)


## 模态面板工厂：暗遮罩 + 居中面板（返回面板，其第一个子节点是内容 VBox）
func _open_modal(title_text: String) -> PanelContainer:
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.z_index = 300
	add_child(modal)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			modal.queue_free())
	modal.add_child(dim)
	var panel := PanelContainer.new()
	panel.size = Vector2(420, 420)
	UITheme.center(panel)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(20))
	modal.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UITheme.make_label(title_text, 18, UITheme.GOLD_BRIGHT))
	return panel


## 语言切换后由设置面板回调重进场景刷新文案（见 _show_settings）
