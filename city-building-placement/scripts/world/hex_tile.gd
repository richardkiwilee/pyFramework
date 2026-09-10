class_name HexTile
extends Node3D
## 单个地块：地形棱柱 + 悬停高亮盘 + 领土环。

enum HoverState { NONE, WHITE, YELLOW, RED }

const TerrainData := preload("res://scripts/data/terrain_data.gd")
const Factory := preload("res://scripts/world/terrain_factory.gd")

var cell: Vector2i = Vector2i.ZERO
var terrain: int = TerrainData.Terrain.PLAIN
var top_height: float = 0.0

var _hover: MeshInstance3D
var _ring: MeshInstance3D


func setup(p_cell: Vector2i, p_terrain: int, hex_size: float) -> void:
	cell = p_cell
	terrain = p_terrain
	top_height = float(TerrainData.TOP_HEIGHT.get(terrain, 0.0))
	_build_prism(hex_size)
	_build_highlights(hex_size)


## 六边形棱柱：底面固定在 y=-0.5，顶面为地形高度；高山收窄成锥台
func _build_prism(hex_size: float) -> void:
	var radius: float = hex_size * 0.98
	var height: float = top_height + 0.5
	var top_radius: float = radius
	if terrain == TerrainData.Terrain.MOUNTAIN:
		top_radius = radius * 0.55
	var side := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 6
	cm.cap_top = false
	cm.cap_bottom = false
	cm.top_radius = top_radius
	cm.bottom_radius = radius
	cm.height = height
	side.mesh = cm
	side.position = Vector3(0, top_height - height * 0.5, 0)
	side.material_override = Factory.terrain_side_material(terrain)
	add_child(side)
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.radial_segments = 6
	tm.cap_top = true
	tm.cap_bottom = false
	tm.top_radius = top_radius
	tm.bottom_radius = top_radius
	tm.height = 0.02
	top.mesh = tm
	top.position = Vector3(0, top_height - 0.01, 0)
	top.material_override = Factory.terrain_top_material(terrain)
	add_child(top)


func _build_highlights(hex_size: float) -> void:
	_hover = MeshInstance3D.new()
	_hover.mesh = Factory.disc_mesh(hex_size * 0.92)
	_hover.position = Vector3(0, top_height + 0.03, 0)
	_hover.visible = false
	add_child(_hover)
	_ring = MeshInstance3D.new()
	_ring.mesh = Factory.ring_mesh(hex_size * 0.95, hex_size * 0.80)
	_ring.position = Vector3(0, top_height + 0.05, 0)
	_ring.visible = false
	_ring.material_override = Factory.hover_material(Color("#66bb6a"), 0.55, 10)
	add_child(_ring)


func set_owned(v: bool) -> void:
	_ring.visible = v


func set_hover(state: int) -> void:
	match state:
		HoverState.NONE:
			_hover.visible = false
		HoverState.WHITE:
			_hover.visible = true
			_hover.material_override = Factory.hover_material(Color("#ffffff"), 0.45, 20)
		HoverState.YELLOW:
			_hover.visible = true
			_hover.material_override = Factory.hover_material(Color("#ffd54f"), 0.45, 20)
		HoverState.RED:
			_hover.visible = true
			_hover.material_override = Factory.hover_material(Color("#ef5350"), 0.4, 20)
