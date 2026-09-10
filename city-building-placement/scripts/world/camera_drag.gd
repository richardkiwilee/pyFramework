class_name CameraDrag
extends Camera3D
## 固定视角相机：左键拖动平移（位移 >8px 视为拖动），松开时位移过小则视为点击并拾取地块。

signal map_clicked(cell: Vector2i)
signal map_hovered(cell: Vector2i)

const HexGeo := preload("res://scripts/hex/hex_geometry.gd")
const TerrainData := preload("res://scripts/data/terrain_data.gd")

const DRAG_THRESHOLD: float = 8.0
const NO_CELL: Vector2i = Vector2i(-99999, -99999)

@export var hex_size: float = 1.0

var _target: Vector3 = Vector3.ZERO
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragging: bool = false
var _hover_cell: Vector2i = NO_CELL


func _ready() -> void:
	_position_from_target()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var me := event as InputEventMouseMotion
		if _pressing:
			var moved: float = _press_pos.distance_to(me.position)
			if moved > DRAG_THRESHOLD:
				_dragging = true
			if _dragging:
				_pan(me.relative)
		else:
			_update_hover(me.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_dragging = false
				_press_pos = mb.position
			elif _pressing:
				_pressing = false
				if not _dragging:
					map_clicked.emit(_hover_cell)


func _pan(rel: Vector2) -> void:
	var right: Vector3 = basis.x
	right.y = 0.0
	right = right.normalized()
	var up: Vector3 = basis.y
	var up_ground_len: float = Vector3(up.x, 0.0, up.z).length()
	up.y = 0.0
	up = up.normalized()
	# 屏幕像素 -> 地面世界单位（size 为全高；屏幕竖向在水平面投影需除以 cos(pitch)）
	var px: float = size / get_viewport().get_visible_rect().size.y
	var ground_scale: float = px / maxf(up_ground_len, 0.0001)
	_target += right * (-rel.x * px) + up * (-rel.y * ground_scale)
	_clamp_target()
	_position_from_target()


func _clamp_target() -> void:
	var m: float = 6.5
	_target.x = clampf(_target.x, -m, m)
	_target.z = clampf(_target.z, -m, m)


func _position_from_target() -> void:
	# 相机置于目标点沿视线反方向 30 单位处（即空中俯视地图）
	position = _target + basis.z * 30.0


func _update_hover(mpos: Vector2) -> void:
	var cell := _ray_cell(mpos)
	if cell != _hover_cell:
		_hover_cell = cell
		map_hovered.emit(cell)


## 射线与 y=0 平面求交，再反算轴向坐标（数学拾取，不依赖物理）
func _ray_cell(mpos: Vector2) -> Vector2i:
	var origin: Vector3 = project_ray_origin(mpos)
	var normal: Vector3 = project_ray_normal(mpos)
	if absf(normal.y) < 0.0001:
		return NO_CELL
	var t: float = -origin.y / normal.y
	var p: Vector3 = origin + normal * t
	var cell: Vector2i = HexGeo.world_to_axial(p, hex_size)
	if not TerrainData.LAYOUT.has(cell):
		return NO_CELL
	return cell


## 地块中心在屏幕上的位置（测试驱动用）
func cell_screen_pos(cell: Vector2i) -> Vector2:
	var wp: Vector3 = HexGeo.axial_to_world(cell, hex_size)
	wp.y = 0.0
	return unproject_position(wp)
