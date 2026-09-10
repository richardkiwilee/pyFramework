class_name World
extends Node3D
## 世界：37 个地块、领土环/悬停高亮、建筑实例。监听 _cs().changed 刷新。

const TerrainData := preload("res://scripts/data/terrain_data.gd")
const HexGeo := preload("res://scripts/hex/hex_geometry.gd")
const HexTileScript := preload("res://scripts/world/hex_tile.gd")
const BuildingFactory := preload("res://scripts/world/building_factory.gd")

const NO_CELL: Vector2i = Vector2i(-99999, -99999)

@export var hex_size: float = 1.0

var tiles: Dictionary = {}  # Vector2i -> HexTile
var _buildings_root: Node3D
var _hover_cell: Vector2i = NO_CELL


## headless -s 下 autoload 标识符编译期不可见，统一走 /root 访问
func _cs() -> CityCore:
	return get_node("/root/CityState") as CityCore


func _ready() -> void:
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)
	for cell: Vector2i in TerrainData.LAYOUT.keys():
		var t: HexTile = HexTileScript.new()
		t.setup(cell, TerrainData.terrain_at(cell), hex_size)
		t.position = HexGeo.axial_to_world(cell, hex_size)
		add_child(t)
		tiles[cell] = t
	_cs().changed.connect(refresh)
	refresh()


func refresh() -> void:
	for cell: Vector2i in tiles.keys():
		var t: HexTile = tiles[cell]
		t.set_owned(_cs().is_owned(cell))
	_update_hover_highlight()
	_rebuild_buildings()


func on_hover(cell: Vector2i) -> void:
	if _hover_cell == cell:
		return
	_hover_cell = cell
	_update_hover_highlight()


func _update_hover_highlight() -> void:
	for cell: Vector2i in tiles.keys():
		var t: HexTile = tiles[cell]
		if cell == _hover_cell:
			if _cs().is_built(cell) or _cs().is_owned(cell):
				t.set_hover(HexTileScript.HoverState.WHITE)
			elif _cs().can_expand(cell):
				t.set_hover(HexTileScript.HoverState.YELLOW)
			else:
				t.set_hover(HexTileScript.HoverState.RED)
		else:
			t.set_hover(HexTileScript.HoverState.NONE)


func _rebuild_buildings() -> void:
	for child: Node in _buildings_root.get_children():
		_buildings_root.remove_child(child)
		child.free()
	for cell: Vector2i in _cs().buildings.keys():
		var b: Dictionary = _cs().buildings[cell]
		var id: String = str(b.get("id", ""))
		var level: int = int(b.get("level", 1))
		var node: Node3D = BuildingFactory.make(id, level)
		var wp: Vector3 = HexGeo.axial_to_world(cell, hex_size)
		wp.y = _cs().terrain_top(cell)
		node.position = wp
		_buildings_root.add_child(node)
