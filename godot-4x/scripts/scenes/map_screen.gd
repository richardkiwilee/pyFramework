## 地图一览（对应 map_scene.py）：全屏只读拓扑图，ESC 返回。
class_name MapScreen
extends BasePage

var _map_view: MapView
var _legend: Label

func build() -> void:
	page_title = Loc.t("map_overview")
	var vbox := make_content()
	var frame := Frame.new(Loc.t("map_overview"))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(frame)
	_map_view = MapView.new()
	_map_view.selectable = false
	frame.add_child(_map_view)
	# 图例
	_legend = Label.new()
	_legend.add_theme_font_size_override("font_size", 13)
	_legend.add_theme_color_override("font_color", UiTheme.DIM)
	vbox.add_child(_legend)

func get_hints() -> Array:
	return [["ESC", "close"]]

func enter_page(params: Variant = null) -> void:
	_map_view.set_game(GameController.game)
	_legend.text = "%s ◆ %s ◆ %s ◆ %s" % [Loc.t("legend_own"), Loc.t("legend_enemy"),
		Loc.t("legend_neutral"), Loc.t("legend_minor")]
	refresh()
	refresh_hints()

func refresh() -> void:
	_map_view.queue_redraw()

func handle_input(event: InputEvent) -> void:
	pass
