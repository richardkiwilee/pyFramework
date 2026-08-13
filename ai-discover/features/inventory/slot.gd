extends Control
## =============================================================================
## slot.gd — 背包格子（配合 inventory.gd 使用）
## =============================================================================
## 使用 Godot 内建拖拽协议实现物品交换：
##   _get_drag_data  有物品时按住拖出 → 返回 {"item":…, "from": 下标}，
##                   并生成半透明拖拽预览；
##   _can_drop_data  允许接收任何物品数据；
##   _drop_data      把物品交给父级 inventory 处理交换。
## 被拖拽物品格子作为"数据源"，悬停的格子作为"落点"。
## =============================================================================

var index: int = -1
var _item: Dictionary = {}

@onready var bg: ColorRect = $BG
@onready var item_rect: ColorRect = $Item
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	bg.color = Color(0.13, 0.15, 0.21)
	item_rect.visible = false
	name_label.text = ""


## 父级填充物品后调用，刷新显示
func set_item(item: Dictionary) -> void:
	_item = item
	if item.is_empty():
		item_rect.visible = false
		name_label.text = ""
	else:
		item_rect.visible = true
		item_rect.color = item["color"]
		name_label.text = item["name"]


func has_item() -> bool:
	return not _item.is_empty()


## 拖出：生成预览 + 返回数据
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _item.is_empty():
		return null
	var preview := Control.new()
	var pr := ColorRect.new()
	pr.size = Vector2(60, 60)
	pr.position = Vector2(8, 8)
	pr.color = _item["color"]
	pr.color.a = 0.75
	preview.add_child(pr)
	set_drag_preview(preview)
	return {"item": _item, "from": index}


## 可以接收拖来的物品
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("item")


## 落点：交给父级做交换
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	get_parent()._on_drop(data["from"], index, data["item"])


## 悬停高亮（可选落点提示）
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		bg.color = Color(0.22, 0.28, 0.42)
	elif what == NOTIFICATION_DRAG_END:
		bg.color = Color(0.13, 0.15, 0.21)
