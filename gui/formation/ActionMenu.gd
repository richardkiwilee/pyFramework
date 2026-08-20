## =====================================================================
## ActionMenu — 成员操作菜单
## =====================================================================
## readme 第 24 行：「空格或鼠标左键点击一个成员，弹出操作选项，
##                    分别是移动、编辑、设为队长、下场。」
##
## 一个贴在成员行旁边的小竖排菜单。可以用 W/S + 空格选，也可以直接点。
## 它是一个「浮在右区上方」的小面板，不是全屏遮罩 —— 全屏遮罩留给解散确认框。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control       → UI 控件基类
## signal chosen(a)      → 选中某一项时发出，参数是动作标识串
## visible = false       → 隐藏节点（隐藏的节点收不到任何鼠标事件）
## PRESET_FULL_RECT      → 锚点预设：填满父节点
## Array[String]         → 元素类型受限的数组（类似 list[str]，但运行时强制）
## const X := [...]      → 常量数组
## =====================================================================
class_name ActionMenu
extends Control

## 选中了某个动作。action 是下面 ACTIONS 里的 id。
signal chosen(action: String)

## 四个动作，顺序即显示顺序（和 readme 的列举顺序一致）。
const ACTIONS := [
	{ "id": "move",    "label": "移动" },
	{ "id": "edit",    "label": "编辑" },
	{ "id": "captain", "label": "设为队长" },
	{ "id": "bench",   "label": "下场" },
]

const ITEM_H := 32.0
const MENU_W := 120.0
const PAD := 6.0

var _panel: Panel
var _items: Array = []      # 每项一个 Panel
var _cursor: int = 0


func _init() -> void:
	name = "ActionMenu"
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 菜单外的区域不拦截
	visible = false

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel",
		FormationSkin.box(Color(0.086, 0.070, 0.043, 0.98), FormationSkin.GOLD, 2, 7))
	add_child(_panel)

	for i in ACTIONS.size():
		var item := Panel.new()
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		# 闭包陷阱：循环变量先拷贝再用。
		var idx := i
		item.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				chosen.emit(str(ACTIONS[idx].id)))
		item.mouse_entered.connect(func():
			_cursor = idx
			_paint())
		_panel.add_child(item)

		var lbl := FormationSkin.make_text(str(ACTIONS[i].label), FormationSkin.INK, 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		FormationSkin.add_filling(item, lbl)
		_items.append(item)


## 在指定位置弹出菜单。anchor_rect 是成员行的矩形（本控件父坐标系），
## 菜单会贴在它的右侧；贴不下就翻到左侧，再不行就夹回可视范围内。
func open_at(anchor_rect: Rect2, bounds: Vector2) -> void:
	visible = true
	_cursor = 0

	var h := ACTIONS.size() * ITEM_H + PAD * 2.0
	var x := anchor_rect.position.x + anchor_rect.size.x * 0.55
	var y := anchor_rect.position.y + anchor_rect.size.y * 0.5 - h * 0.5

	# 右边放不下就往左挪
	if x + MENU_W > bounds.x:
		x = bounds.x - MENU_W - 4.0
	# 上下夹进可视范围
	y = clampf(y, 4.0, maxf(4.0, bounds.y - h - 4.0))
	x = maxf(x, 4.0)

	_panel.position = Vector2(x, y)
	_panel.size = Vector2(MENU_W, h)
	for i in _items.size():
		var it: Panel = _items[i]
		it.position = Vector2(PAD, PAD + float(i) * ITEM_H)
		it.size = Vector2(MENU_W - PAD * 2.0, ITEM_H)
	_paint()


func close() -> void:
	visible = false


## W/S 移动菜单光标，首尾循环。
func step(step_dir: int) -> void:
	_cursor = posmod(_cursor + step_dir, ACTIONS.size())
	_paint()


## 确认当前光标项（空格键走这里）。
func activate_cursor() -> void:
	chosen.emit(str(ACTIONS[_cursor].id))


func _paint() -> void:
	for i in _items.size():
		var sel := i == _cursor
		var bg := Color(0.227, 0.176, 0.102) if sel else Color(0, 0, 0, 0)
		var edge := FormationSkin.GOLD if sel else Color(0, 0, 0, 0)
		_items[i].add_theme_stylebox_override("panel", FormationSkin.box(bg, edge, 1, 4))
