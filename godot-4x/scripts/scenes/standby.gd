## 待命池（对应 standby.py）：只读表格（单位/词条/状态），↑↓ 切换，ESC 返回。
## 原型暂未挂接入口（无绑定键）；本场景保留供后续接入。
class_name StandbyScreen
extends BaseWindow

var _list: ListWidget

func build() -> void:
	win_title = Loc.t("standby")
	win_size = Vector2i(800, 520)
	var vbox := make_content()
	var frame := Frame.new(Loc.t("standby"))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(frame)
	_list = ListWidget.new()
	frame.add_child(_list)
	_list.text_fn = func(d): return d[0]
	_list.color_fn = func(d): return d[1]

func enter_window(params: Variant = null) -> void:
	var g := GameController.game
	var p := GameController.player()
	var rows: Array = []
	for uid in p.standby:
		var u: Variant = g.unit_index.get(uid)
		if u == null:
			continue
		var cd := int(p.standby[uid])
		var st := Loc.t("standby_ok") if cd <= 0 else "%s(%d)" % [Loc.t("standby_cd"), cd]
		var col := UiTheme.C_OWN if cd <= 0 else UiTheme.WARN
		var tagstr := ""
		for i in range(u.tags.size()):
			if i > 0:
				tagstr += "/"
			tagstr += Units.TAG_CN.get(u.tags[i], u.tags[i])
		rows.append(["%s [%s] Lv%d %s" % [Loc.t(u.name), tagstr, u.level, st], col])
	rows.sort()
	_list.set_items(rows)

func get_hints() -> Array:
	return [["↑↓", "move"], ["ESC", "close"]]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
