extends Node2D
## 世界装配：地形、物件、主角、相机、光照、HUD。
##
## 渲染分层（同一棵 CanvasItem 树，用绝对 z_index 排序）：
##   地形波段  z = 12·首行 − 1      （见 Proj.band_z）
##   物件      z = 12·y + 16·h      （见 Proj.depth）
##   主角      z = 12·y + 16·h
## 这套顺序不是拍脑袋定的：它和道具贴图里"高度上移 12px"是同一个几何，
## 所以角色走上坡会被坡上的树挡住、走到树后面会被树干挡住，前后关系永远自洽。

const Proj = preload("res://scripts/proj.gd")
const WorldData = preload("res://scripts/world_data.gd")
const PlayerScript = preload("res://scripts/player.gd")
const DayNight = preload("res://scripts/daynight.gd")
const Hud = preload("res://scripts/hud.gd")
const Shadows = preload("res://scripts/shadows.gd")

const WORLD_JSON := "res://assets/world/world.json"
const ATLAS_PNG := "res://assets/world/objects.png"
const ATLAS_META := "res://assets/world/objects.json"

var data: WorldData
var player                    ## player.gd，动态挂载
var daynight                  ## daynight.gd，动态挂载
var hud                       ## hud.gd，动态挂载
var camera: Camera2D

var shadows                   ## shadows.gd，动态挂载

var _atlas: Texture2D
var _meta: Dictionary = {}


func _ready() -> void:
	_setup_input()
	data = WorldData.new()
	if not data.load_from(WORLD_JSON):
		push_error("世界数据加载失败")
		return
	_atlas = load(ATLAS_PNG)
	_meta = _load_json(ATLAS_META)

	_build_terrain()
	_build_objects()

	player = Node2D.new()
	player.set_script(PlayerScript)
	add_child(player)
	player.setup(data, data.spawn)

	shadows = Node2D.new()
	shadows.set_script(Shadows)
	add_child(shadows)
	shadows.setup(data.objects, _meta, _atlas, player)

	daynight = Node2D.new()
	daynight.set_script(DayNight)
	add_child(daynight)
	daynight.build_point_lights(data.objects)
	daynight.attach_player_light(player)
	daynight.set_shadows(shadows)

	_setup_camera()
	_setup_hud()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("读不到 " + path)
		return {}
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return v if typeof(v) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------------ 地形

func _build_terrain() -> void:
	for b in data.bands:
		var s := Sprite2D.new()
		s.texture = load("res://assets/world/" + String(b["file"]))
		s.centered = false
		s.position = Vector2(0.0, float(b["y"]))
		s.z_index = Proj.band_z(int(b["row"]))
		s.z_as_relative = false
		add_child(s)


# ------------------------------------------------------------------ 物件

func _build_objects() -> void:
	for o in data.objects:
		var n := String(o["n"])
		var m: Dictionary = _meta.get(n, {})
		if m.is_empty():
			continue
		var at := AtlasTexture.new()
		at.atlas = _atlas
		at.region = Rect2(float(m["x"]), float(m["y"]), float(m["w"]), float(m["h"]))

		var s := Sprite2D.new()
		s.texture = at
		s.centered = false
		s.position = Vector2(
			float(o["x"]) * Proj.TILE + float(o["ox"]) - float(m["ax"]),
			float(o["y"]) * Proj.TILE - float(o["h"]) * Proj.ELEV_H + float(o["oy"]) - float(m["ay"]))
		s.z_index = Proj.depth(float(o["y"]), float(o["h"]))
		s.z_as_relative = false
		add_child(s)



# ------------------------------------------------------------------ 相机

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	# 上边界正好卡在最北一带有高度的地形顶边（0 行、最高 h 的地面被抬高 h*ELEV_H）。
	# 再往上放就会露出地形贴图之外的黑边 —— 地形最上沿就被画在这里，多给没有意义。
	camera.limit_left = 0
	camera.limit_top = -Proj.ELEV_H * Proj.MAX_H
	camera.limit_right = data.w * Proj.TILE
	camera.limit_bottom = data.h * Proj.ROW_H + Proj.ROW_H
	camera.position = player.screen_pos()
	add_child(camera)
	camera.make_current()


# ------------------------------------------------------------------ HUD

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(Hud)
	add_child(hud)
	hud.setup(self)


# ------------------------------------------------------------------ 每帧

func _process(delta: float) -> void:
	if player == null or daynight == null:
		return
	var target: Vector2 = player.screen_pos()
	# 相机跟随会抖：向上取整到像素，避免贴图在采样时"呼吸"
	camera.position = camera.position.lerp(target, clampf(7.0 * delta, 0.0, 1.0))

	shadows.set_camera(camera.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F1:
				shadows.visible = not shadows.visible
			KEY_F2:
				hud.visible = not hud.visible
			KEY_T:
				daynight.auto_advance = not daynight.auto_advance


# ------------------------------------------------------------------ 输入映射

## 在代码里注册按键，省得手写 project.godot 里那一大坨 InputEventKey 序列化。
func _setup_input() -> void:
	var defs := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
	}
	for action in defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in defs[action]:
			if InputMap.action_has_event(action, _key_event(k)):
				continue
			InputMap.action_add_event(action, _key_event(k))


func _key_event(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


# ------------------------------------------------------------------ 对外接口（capture / bench 用）

func set_time(t: float) -> void:
	daynight.time = t
	daynight.apply()


func teleport(tx: float, ty: float) -> void:
	player.pos = Vector2(tx, ty)
	player.target_h = data.height_at(int(tx), int(ty))
	player.vis_h = float(player.target_h)
	player._refresh_transform()
	if camera:
		camera.position = player.screen_pos()
		camera.reset_smoothing()


func player_pos() -> Vector2:
	return player.pos


func player_px() -> Vector2:
	return player.screen_pos()
