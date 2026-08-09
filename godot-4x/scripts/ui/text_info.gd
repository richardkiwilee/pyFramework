## 详情文本面板（滚动、多行、可点击词条 [[词]] 跳转——对应 TUI 详情窗 + PgUp/PgDn）。
## 词条用 [[名称]] 包裹；点击或回车触发 word_selected(名称)。
class_name TextInfo
extends Control

signal word_selected(word: String)

var text: String = "":
	set(v):
		text = v
		_parse()
		queue_redraw()

var _lines: Array = []      # 渲染行（纯文本，词条已展开）
var _line_words: Array = [] # 每行 [ [word, x_start], ... ] 词条命中区
var scroll := 0

const FONT_SIZE := 14
const LINE_H := 22

func _parse() -> void:
	_lines.clear()
	_line_words.clear()
	var font := get_theme_default_font()
	for raw_line in text.split("\n"):
		var segs := _split_words(raw_line)
		var line := ""
		var words: Array = []
		var x := 4.0
		for seg in segs:
			if seg.begins_with("[["):
				var w: String = seg.trim_prefix("[[").trim_suffix("]]")
				words.append([w, x])
				line += w
				x += font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			else:
				line += seg
				x += font.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		_lines.append(line)
		_line_words.append(words)

## 把一行切成 [普通段, [[词条]], ...]。
func _split_words(line: String) -> Array:
	var out: Array = []
	var rest := line
	while true:
		var a := rest.find("[[")
		if a < 0:
			if rest != "":
				out.append(rest)
			break
		if a > 0:
			out.append(rest.substr(0, a))
		var b := rest.find("]]", a + 2)
		if b < 0:
			out.append(rest.substr(a))
			break
		out.append(rest.substr(a, b + 2 - a))
		rest = rest.substr(b + 2)
	return out

func _draw() -> void:
	var font := get_theme_default_font()
	var y := 2
	var view_h := int(size.y)
	for i in range(scroll, _lines.size()):
		if y > view_h:
			break
		draw_string(font, Vector2(4, y + 16), _lines[i], HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 8, FONT_SIZE, UiTheme.FG)
		y += LINE_H
	# 滚动条
	var total_h := _lines.size() * LINE_H
	if total_h > view_h:
		var frac := view_h / float(total_h)
		draw_rect(Rect2(size.x - 4, scroll * frac, 4, view_h * frac), UiTheme.BORDER)

func scroll_by(delta: int) -> void:
	scroll = clampi(scroll + delta, 0, maxi(0, _lines.size() - maxi(1, int(size.y / LINE_H))))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_by(-3)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_by(3)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# 词条命中检测
			var row := int(event.position.y / LINE_H) + scroll
			if row >= 0 and row < _line_words.size():
				var click_x: float = event.position.x
				for hit in _line_words[row]:
					var w: String = hit[0]
					var x0: float = hit[1]
					var font := get_theme_default_font()
					var ww := font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
					if click_x >= x0 and click_x <= x0 + ww:
						word_selected.emit(w)
						accept_event()
						return
