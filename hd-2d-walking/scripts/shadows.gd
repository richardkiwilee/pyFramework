extends Node2D
## 投影阴影：把每个物件的精灵沿光方向"压"到地面上。
##
## 为什么不用 DirectionalLight2D + LightOccluder2D：
## Godot 的 2D 平行光影子长度是无限的，一棵树的影子会一路拖到屏幕外，
## 满屏都是斜的长条（height 属性只影响法线贴图，对影子长度毫无作用，实测确认）。
##
## 这里的做法是数学上等价的仿射投影：
##   精灵上离脚底高度 p 像素的一点，其影子落在脚底偏移 (s·p, t·p) 处。
##   于是"影子"就是把精灵图按矩阵 [[1, -s], [0, -t]] 变换一次 —— 逐像素一一对应，
##   不需要求交、不需要遮挡体，而且影子长度天然被 t 控制住。
##
## 整张贴图一次性画在一个 CanvasItem 里，共享一个 ShaderMaterial，能合批。

const Proj = preload("res://scripts/proj.gd")

var _items: Array = []          ## [{tex, region, ax, ay, w, h, pos}]
var _player = null
var _cam := Vector2.ZERO

var last_drawn := 0             ## 上一帧实际画了几个影子（bench 用来量剔除效果）
var _s := 0.0                   ## 每像素高度在横向投出的影子长度
var _t := 1.0                   ## 每像素高度在纵向投出的影子长度
var _strength := 0.0
var _mat: ShaderMaterial
var _atlas: Texture2D


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/shadow.gdshader")
	material = _mat
	# 影子高于所有地形与物件：它是一层贴在地上的暗色滤镜，
	# 让角色从树影里走过时真的会被"压暗"。
	z_as_relative = false
	z_index = 4095
	set_sun(0.0, 1.0, 0.0, Color(0.07, 0.08, 0.18))


## 收集所有够大的物件（小花小草不需要影子）
func setup(objects: Array, meta: Dictionary, atlas: Texture2D, player_node) -> void:
	_player = player_node
	_atlas = atlas
	for o in objects:
		var m: Dictionary = meta.get(String(o["n"]), {})
		if m.is_empty():
			continue
		var w := int(m["w"])
		var h := int(m["h"])
		if w * h < 240:
			continue
		var reg := Rect2(float(m["x"]), float(m["y"]), float(w), float(h))
		_items.append({
			"tex": atlas,
			"region": reg,
			"ax": float(m["ax"]),
			"ay": float(m["ay"]),
			"w": w, "h": h,
			"pos": Proj.world_to_screen(float(o["x"]), float(o["y"]), float(o["h"])),
		})


func set_camera(p: Vector2) -> void:
	_cam = p


## s/t：每像素高度投出的影子长度（屏幕像素）。direction 由 daynight.gd 按太阳位置算好。
func set_sun(s: float, t: float, strength: float, tint: Color) -> void:
	_s = s
	_t = maxf(absf(t), 0.02)
	_strength = strength
	_mat.set_shader_parameter("shadow_color", Color(tint.r, tint.g, tint.b, tint.a * strength))
	queue_redraw()


func _draw() -> void:
	last_drawn = 0
	if _strength <= 0.004:
		return
	var view := Rect2(_cam - Vector2(420, 320), Vector2(840, 640))
	# 影子往南/西甩得远，剔除框要按影子长度放大一点
	var pad := 220.0
	for it in _items:
		var p: Vector2 = it["pos"]
		if not view.grow(pad).has_point(p):
			continue
		last_drawn += 1
		_blit(it["tex"], it["region"], p, float(it["ax"]), float(it["ay"]),
			float(it["w"]), float(it["h"]))
	if _player != null and _player.has_method("shadow_frame"):
		var pf: Dictionary = _player.shadow_frame()
		if not pf.is_empty():
			last_drawn += 1
			_blit(pf["tex"], pf["region"], pf["pos"], pf["ax"], pf["ay"], pf["w"], pf["h"],
				bool(pf.get("flip", false)))


## 把一张精灵按影子矩阵贴到地面。脚底锚点 (ax, ay) 必须映射到 p。
func _blit(tex: Texture2D, region: Rect2, p: Vector2, ax: float, ay: float,
		w: float, h: float, flip := false) -> void:
	if not is_finite(_s) or not is_finite(_t):
		return
	# 贴图左右翻转时，影子矩阵也要跟着翻，否则右向行走的影子是反的
	var xa := Vector2(-1.0, 0.0) if flip else Vector2(1.0, 0.0)
	var ya := Vector2(_s if flip else -_s, -_t)
	var origin := p - (xa * ax + ya * ay)
	draw_set_transform_matrix(Transform2D(xa, ya, origin))
	draw_texture_rect_region(tex, Rect2(0.0, 0.0, w, h), region)
