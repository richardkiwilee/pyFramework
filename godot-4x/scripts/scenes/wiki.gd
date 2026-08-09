## 百科（对应 wiki.py）：全屏页面（顶栏"百科"按钮打开，占满顶栏下空间）。
## 实时模糊搜索（中文子串），输入即筛选；ESC 关闭返回大地图。
class_name WikiScreen
extends BasePage

var query: String = ""
var _search: LineEdit
var _list: ListWidget
var _detail: TextInfo
var _entries: Array = []      # wiki 记录
var _filtered: Array = []     # 索引列表

func build() -> void:
	page_title = Loc.t("wiki")
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 8
	top.offset_bottom = 44
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	var title := Label.new()
	title.text = Loc.t("wiki")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.HEADING)
	top.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = Loc.t("wiki_search")
	_search.custom_minimum_size = Vector2(360, 30)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _filter())
	top.add_child(_search)
	# 主体：左列表 + 右详情
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_top = 48
	hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)
	var left := Frame.new(Loc.t("wiki_results"))
	left.custom_minimum_size = Vector2(340, 0)
	hbox.add_child(left)
	_list = ListWidget.new()
	left.add_child(_list)
	_list.text_fn = func(d): return _entries[d].get("name", "?")
	_list.color_fn = func(d): return UiTheme.FG
	_list.row_selected.connect(func(idx): _show(idx))
	var right := Frame.new(Loc.t("wiki_detail"))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_detail = TextInfo.new()
	right.add_child(_detail)
	_detail.word_selected.connect(func(w): _jump(w))

func _load_entries() -> void:
	if not _entries.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/wiki.json"))
	if data is Array:
		for rec in data:
			if rec is Dictionary:
				_entries.append(rec)

func enter_page(params: Variant = null) -> void:
	_load_entries()
	_filter()
	if params is String and params != "":
		query = params
		_search.text = query
		_filter()
	_search.grab_focus()

func _filter() -> void:
	var q := _search.text.strip_edges()
	_filtered.clear()
	for i in range(_entries.size()):
		if q == "":
			_filtered.append(i)
			continue
		var rec: Dictionary = _entries[i]
		var hay := str(rec.get("name", "")) + str(rec.get("summary", "")) + str(rec.get("detail", ""))
		if hay.contains(q):
			_filtered.append(i)
	_list.set_items(_filtered)
	_show(0)

func _show(idx: int) -> void:
	if _filtered.is_empty():
		_detail.text = Loc.t("no_items")
		return
	var rec: Dictionary = _entries[_filtered[idx]]
	var lines: Array[String] = [
		"%s [%s]" % [rec.get("name", ""), Loc.t(rec.get("category", ""))],
		rec.get("summary", ""),
		"",
		rec.get("detail", ""),
	]
	var attrs: Dictionary = rec.get("attrs", {})
	if not attrs.is_empty():
		lines.append("")
		for k in attrs:
			lines.append("%s: %s" % [k, str(attrs[k])])
	_detail.text = "\n".join(lines)

func _jump(word: String) -> void:
	_search.text = word
	_filter()

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("backspace"):
		_search.text = _search.text.substr(0, _search.text.length() - 1)
		_filter()
		return
	# 字符输入（不阻塞搜索框）
	if event is InputEventKey and event.pressed and not event.echo:
		var txt: String = event.as_text()
		if txt.length() == 1 and (txt.is_valid_identifier() or txt.unicode_at(0) > 127):
			_search.text += txt
			_filter()
			return
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
		_show(_list.focused)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
		_show(_list.focused)
	elif event.is_action_pressed("scroll_up"):
		_detail.scroll_by(-5)
	elif event.is_action_pressed("scroll_down"):
		_detail.scroll_by(5)
	elif event.is_action_pressed("ui_cancel"):
		close_requested.emit()
