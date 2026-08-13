extends Control
## =============================================================================
## 背包拖拽 —— 5×4 格子，物品拖拽交换位置（UI 组件）
## =============================================================================
## 使用 Godot 内建拖拽协议（见 slot.gd）：
##   按住物品拖到另一个格子 → 两格内容交换；
##   拖到空格子 → 物品移动过去。
## 物品是纯代码生成的彩色方块（无美术资源），带名字标签。
## =============================================================================

const SlotScript = preload("res://features/inventory/slot.gd")

const GRID_W := 5
const GRID_H := 4

const ITEM_POOL: Array[Dictionary] = [
	{"name": "长剑", "color": Color(0.80, 0.85, 0.92)},
	{"name": "药水", "color": Color(0.85, 0.30, 0.30)},
	{"name": "盾牌", "color": Color(0.55, 0.50, 0.30)},
	{"name": "金币", "color": Color(0.95, 0.80, 0.25)},
	{"name": "宝石", "color": Color(0.45, 0.30, 0.90)},
	{"name": "卷轴", "color": Color(0.85, 0.75, 0.55)},
	{"name": "钥匙", "color": Color(0.60, 0.65, 0.70)},
	{"name": "面包", "color": Color(0.75, 0.50, 0.30)},
	{"name": "羽毛", "color": Color(0.75, 0.80, 0.90)},
	{"name": "炸弹", "color": Color(0.30, 0.32, 0.36)},
]

var _slots: Array[Control] = []

@onready var grid: GridContainer = $Center/VBox/Frame/Grid
@onready var status_label: Label = $Center/VBox/StatusLabel


func _ready() -> void:
	for y in GRID_H:
		for x in GRID_W:
			var slot := _make_slot(x + y * GRID_W)
			grid.add_child(slot)
			_slots.append(slot)
	# 前 10 格放满物品
	for i in ITEM_POOL.size():
		_slots[i].set_item(ITEM_POOL[i])


func _make_slot(idx: int) -> Control:
	var slot := Control.new()
	slot.set_script(SlotScript)
	slot.custom_minimum_size = Vector2(86, 86)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := ColorRect.new()
	bg.name = "BG"
	bg.size = Vector2(86, 86)
	# 关键：子矩形鼠标穿透(IGNORE)，否则点击物品时事件被它吃掉，
	# 格子的 _get_drag_data 永远收不到 → 无法拖拽
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bg)

	var item := ColorRect.new()
	item.name = "Item"
	item.size = Vector2(64, 64)
	item.position = Vector2(11, 6)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(item)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.size = Vector2(86, 20)
	name_label.position = Vector2(0, 70)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	slot.add_child(name_label)

	slot.index = idx   # 纯变量，_ready 前可安全赋值（显示由 _ready 初始化）
	return slot


## slot.gd 的 _drop_data 回调：交换 from / to 两格的物品
func _on_drop(from: int, to: int, item: Dictionary) -> void:
	var taken: Dictionary = _slots[to]._item   # 落点原有物品（可能为空）
	_slots[to].set_item(item)
	_slots[from].set_item(taken)
	status_label.text = "🎒 交换：%s ↔ %s" % [_describe(from), _describe(to)]


func _describe(idx: int) -> String:
	var it: Dictionary = _slots[idx]._item
	return it["name"] if not it.is_empty() else "空格(%d)" % idx
