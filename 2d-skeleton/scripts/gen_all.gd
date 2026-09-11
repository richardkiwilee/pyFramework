@tool
class_name GenAll
extends RefCounted

# ──────────────────────────────────────────────────────────────────────
# 单一数据源：骨骼定义 + 动画关键帧 + 美术配色
# GenAll.generate() 把派生资源写到磁盘。
# ──────────────────────────────────────────────────────────────────────

const BoneDef = preload("res://scripts/bone_def.gd")
const BoneSpec = preload("res://scripts/bone_spec.gd")
const ArtSetMeta = preload("res://scripts/art_meta.gd")

const ART_DIR := "res://art"
const SKEL_DIR := "res://skeletons"
const ANIM_DIR := "res://anims"
const SKEL_KEY := "humanoid"

# ── 内部数据类（替代 struct） ───────────────────────────────────────────
class BoneW:
	var name: String
	var parent: String
	var pos: Vector2
	var dir: float
	var shape: String
	var w: float
	var h: float
	var r: float
	var z: int
	func _init(n: String = "", p: String = "", x: float = 0.0, y: float = 0.0, d: float = 0.0,
			   sh: String = "", ww: float = 0.0, hh: float = 0.0, rr: float = 0.0, zz: int = 0) -> void:
		name = n; parent = p; pos = Vector2(x, y); dir = d
		shape = sh; w = ww; h = hh; r = rr; z = zz

class AnimKF:
	var bone: String
	var times: PackedFloat32Array
	var rots: PackedFloat32Array
	var poss: Array
	var scales: Array
	func _init(b: String = "", ts: Array = [], rs: Array = [], ps: Array = [], ss: Array = []) -> void:
		bone = b
		times = PackedFloat32Array(ts)
		rots = PackedFloat32Array(rs)
		poss = ps
		scales = ss

# 美术 PNG 画布尺寸（2× 骨尺寸 + padding）
static func _tex_size(sh: String, w: float, h: float) -> Vector2:
	var pad := 8.0
	match sh:
		"circle":
			var d := int(w * 2.0 + pad * 2.0)
			return Vector2(d, d)
		"sword":
			return Vector2(int(h * 2.0 + pad * 2.0), int(w * 2.0 + pad * 2.0))
		_:
			return Vector2(int(w * 2.0 + pad * 2.0), int(h * 2.0 + pad * 2.0))

# ── 骨骼数据（pos = 相对父骨的偏移；dir = 世界朝向角，90°=向下） ──────────
# 约定：每骨 origin 在骨首（关节），精灵以 offset=(0, h/2) 沿骨局部 +Y（向下）绘制。
# 根骨 hip 放 (0,0)；torso 向上（负 Y）到肩膀；头在肩上方；手臂从肩向下；腿从髋向下。
# 全部 dir≈90°（向下），使静息 local_rot≈0 → 角色直立，不横躺。
static func _bone_data() -> Dictionary:
	var B := func(n, p, x, y, d, sh, w, h, r, z) -> BoneW: return BoneW.new(n, p, x, y, d, sh, w, h, r, z)
	var bones: Array = [
		# 躯干（向上）
		B.call("hip", "", 0, 0, deg_to_rad(90), "round_rect", 26, 22, 8, 0),
		B.call("torso", "hip", 0, -56, deg_to_rad(90), "round_rect", 30, 56, 10, 0),
		B.call("head", "torso", 0, -8, deg_to_rad(90), "circle", 14, 14, 14, 0),
		# 右臂（近侧，z=+1）从肩向下，略外撇 5°
		B.call("upper_arm_R", "torso", 14, -50, deg_to_rad(95), "round_rect", 12, 36, 6, 1),
		B.call("fore_arm_R", "upper_arm_R", 0, 36, deg_to_rad(95), "round_rect", 10, 34, 5, 1),
		B.call("hand_R", "fore_arm_R", 0, 34, deg_to_rad(95), "round_rect", 12, 10, 5, 1),
		B.call("sword", "hand_R", 0, 12, deg_to_rad(90), "sword", 8, 70, 0, 2),
		# 左臂（远侧，z=-1）
		B.call("upper_arm_L", "torso", -14, -50, deg_to_rad(85), "round_rect", 12, 36, 6, -1),
		B.call("fore_arm_L", "upper_arm_L", 0, 36, deg_to_rad(85), "round_rect", 10, 34, 5, -1),
		B.call("hand_L", "fore_arm_L", 0, 34, deg_to_rad(85), "round_rect", 12, 10, 5, -1),
		# 右腿（近侧）从髋向下
		B.call("thigh_R", "hip", 7, 10, deg_to_rad(90), "round_rect", 14, 46, 7, 1),
		B.call("shin_R", "thigh_R", 0, 46, deg_to_rad(90), "round_rect", 12, 44, 6, 1),
		B.call("foot_R", "shin_R", 0, 44, deg_to_rad(105), "round_rect", 22, 10, 5, 1),
		# 左腿（远侧）
		B.call("thigh_L", "hip", -7, 10, deg_to_rad(90), "round_rect", 14, 46, 7, -1),
		B.call("shin_L", "thigh_L", 0, 46, deg_to_rad(90), "round_rect", 12, 44, 6, -1),
		B.call("foot_L", "shin_L", 0, 44, deg_to_rad(105), "round_rect", 22, 10, 5, -1),
	]
	var by_name: Dictionary = {}
	for b in bones:
		by_name[(b as BoneW).name] = b
	return {"bones": bones, "by": by_name}

# ── 世界坐标 → local pos/rot ────────────────────────────────────────────
# 骨数据约定：bw.pos 是“相对父骨关节的局部偏移”（标准骨骼层级），bw.dir 是世界朝向角。
# Bone2D.rotation 只应存“相对父骨的角度差”，根骨为 0——绝对朝向（90°向下）由 bone_angle
# 元数据标记，不烤进 rotation，否则 90° 会级联到所有子 Sprite 使角色横躺。
static func _to_local(bones: Array, by: Dictionary) -> Dictionary:
	var local: Dictionary = {}
	for b in bones:
		var bw: BoneW = b
		if bw.parent == "":
			local[bw.name] = {"pos": bw.pos, "rot": 0.0}
			continue
		var p: BoneW = by[bw.parent]
		# pos 直接作为父骨局部系下的偏移（父骨 rotation=角度差，向下累积）
		var lr: float = bw.dir - p.dir
		local[bw.name] = {"pos": bw.pos, "rot": lr}
	return local

static func _build_bone_def() -> BoneDef:
	var d: Dictionary = _bone_data()
	var bones: Array = d["bones"]
	var by: Dictionary = d["by"]
	var loc: Dictionary = _to_local(bones, by)
	var def := BoneDef.new()
	def.skeleton_key = SKEL_KEY
	def.label = "持剑人形"
	for b in bones:
		var bw: BoneW = b
		var bs := BoneSpec.new()
		bs.name = bw.name
		bs.parent = bw.parent
		var L: Dictionary = loc[bw.name]
		bs.local_pos = L["pos"]
		bs.local_rot = L["rot"]
		bs.sprite_offset = Vector2(0, bw.h * 0.5)
		bs.flip_v = false
		bs.tex_size = _tex_size(bw.shape, bw.w, bw.h)
		bs.z_index = bw.z
		bs.shape = bw.shape
		bs.shape_w = bw.w
		bs.shape_h = bw.h
		bs.shape_r = bw.r
		def.bones.append(bs)
	return def

# ── 美术配色 ────────────────────────────────────────────────────────────
static func _art_colors(set_key: String) -> Dictionary:
	match set_key:
		"A":
			return {
				"hip": Color(0.353, 0.416, 0.541),
				"torso": Color(0.353, 0.416, 0.541),
				"head": Color(0.941, 0.753, 0.565),
				"upper_arm_R": Color(0.784, 0.690, 0.565),
				"fore_arm_R": Color(0.353, 0.416, 0.541),
				"hand_R": Color(0.941, 0.753, 0.565),
				"upper_arm_L": Color(0.784, 0.690, 0.565),
				"fore_arm_L": Color(0.353, 0.416, 0.541),
				"hand_L": Color(0.941, 0.753, 0.565),
				"thigh_R": Color(0.227, 0.290, 0.416),
				"shin_R": Color(0.227, 0.290, 0.416),
				"foot_R": Color(0.165, 0.165, 0.220),
				"thigh_L": Color(0.227, 0.290, 0.416),
				"shin_L": Color(0.227, 0.290, 0.416),
				"foot_L": Color(0.165, 0.165, 0.220),
				"sword": Color(0.784, 0.816, 0.878),
				"_outline": Color(0.10, 0.10, 0.14),
				"_hair": Color(0.227, 0.165, 0.102),
				"_grip": Color(0.416, 0.290, 0.165),
			}
		"B":
			return {
				"hip": Color(0.416, 0.290, 0.165),
				"torso": Color(0.416, 0.290, 0.165),
				"head": Color(0.416, 0.604, 0.353),
				"upper_arm_R": Color(0.353, 0.541, 0.290),
				"fore_arm_R": Color(0.416, 0.290, 0.165),
				"hand_R": Color(0.416, 0.604, 0.353),
				"upper_arm_L": Color(0.353, 0.541, 0.290),
				"fore_arm_L": Color(0.416, 0.290, 0.165),
				"hand_L": Color(0.416, 0.604, 0.353),
				"thigh_R": Color(0.290, 0.227, 0.102),
				"shin_R": Color(0.290, 0.227, 0.102),
				"foot_R": Color(0.165, 0.102, 0.039),
				"thigh_L": Color(0.290, 0.227, 0.102),
				"shin_L": Color(0.290, 0.227, 0.102),
				"foot_L": Color(0.165, 0.102, 0.039),
				"sword": Color(0.627, 0.125, 0.165),
				"_outline": Color(0.06, 0.08, 0.04),
				"_hair": Color(0.165, 0.227, 0.102),
				"_grip": Color(0.847, 0.784, 0.627),
			}
	return {}

# ── 光栅化单骨 PNG ──────────────────────────────────────────────────────
static func _render_bone_png(b: BoneW, colors: Dictionary) -> Image:
	var tex := _tex_size(b.shape, b.w, b.h)
	var iw := int(tex.x)
	var ih := int(tex.y)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: Color = colors.get(b.name, Color.MAGENTA)
	var outline: Color = colors["_outline"]
	var ox := iw * 0.5
	var scale := 2.0
	if b.shape == "circle":
		var rad := b.w * scale
		_draw_circle_outline(img, Vector2(ox, rad + 4), rad + 2.0, outline)
		_draw_circle_fill(img, Vector2(ox, rad + 4), rad, col)
		if colors.has("_hair"):
			_draw_arc_top(img, Vector2(ox, rad + 4), rad, colors["_hair"], deg_to_rad(-110), deg_to_rad(110))
	elif b.shape == "sword":
		var blade_len := b.h * scale
		var grip_len := 14.0
		var guard_w := b.w * scale * 2.4
		var blade_w := b.w * scale
		_fill_rect(img, Rect2(ox - blade_w * 0.4, 4, blade_w * 0.8, grip_len), colors["_grip"])
		_fill_rect(img, Rect2(ox - guard_w * 0.5, 4 + grip_len, guard_w, 5), outline.lightened(0.2))
		_fill_rect(img, Rect2(ox - blade_w * 0.5, 4 + grip_len + 5, blade_w, blade_len - grip_len - 5), col)
		_rect_outline(img, Rect2(ox - blade_w * 0.5, 4 + grip_len + 5, blade_w, blade_len - grip_len - 5), outline)
		_fill_triangle(img, Vector2(ox, 4 + blade_len), Vector2(ox - blade_w * 0.5, 4 + blade_len - 8), Vector2(ox + blade_w * 0.5, 4 + blade_len - 8), col)
	else:
		var rw := b.w * scale
		var rh := b.h * scale
		var rr := b.r * scale
		_fill_round_rect_outline(img, Rect2(ox - rw * 0.5, 4, rw, rh), rr + 1.5, outline)
		_fill_round_rect(img, Rect2(ox - rw * 0.5, 4, rw, rh), rr, col)
	return img

# ── Image 绘图辅助 ──────────────────────────────────────────────────────
static func _set_px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

static func _fill_rect(img: Image, r: Rect2, c: Color) -> void:
	var x0 := int(r.position.x); var y0 := int(r.position.y)
	var x1 := int(r.position.x + r.size.x); var y1 := int(r.position.y + r.size.y)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_set_px(img, x, y, c)

static func _rect_outline(img: Image, r: Rect2, c: Color) -> void:
	var x0 := int(r.position.x); var y0 := int(r.position.y)
	var x1 := int(r.position.x + r.size.x) - 1; var y1 := int(r.position.y + r.size.y) - 1
	for x in range(x0, x1 + 1):
		_set_px(img, x, y0, c); _set_px(img, x, y1, c)
	for y in range(y0, y1 + 1):
		_set_px(img, x0, y, c); _set_px(img, x1, y, c)

static func _fill_round_rect(img: Image, r: Rect2, rad: float, c: Color) -> void:
	var x0 := int(r.position.x); var y0 := int(r.position.y)
	var x1 := int(r.position.x + r.size.x); var y1 := int(r.position.y + r.size.y)
	var irad := int(rad)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if _round_rect_skip(x, y, x0, y0, x1, y1, irad):
				continue
			_set_px(img, x, y, c)

static func _fill_round_rect_outline(img: Image, r: Rect2, rad: float, c: Color) -> void:
	var x0 := int(r.position.x) - 1; var y0 := int(r.position.y) - 1
	var x1 := int(r.position.x + r.size.x) + 1; var y1 := int(r.position.y + r.size.y) + 1
	var irad := int(rad) + 1
	for y in range(y0, y1):
		for x in range(x0, x1):
			if _round_rect_skip(x, y, x0, y0, x1, y1, irad):
				continue
			var ix := x - int(r.position.x)
			var iy := y - int(r.position.y)
			if ix >= 0 and iy >= 0 and ix < int(r.size.x) and iy < int(r.size.y):
				if not _round_rect_skip(int(r.position.x) + ix, int(r.position.y) + iy, int(r.position.x), int(r.position.y), int(r.position.x + r.size.x), int(r.position.y + r.size.y), int(rad)):
					continue
			_set_px(img, x, y, c)

static func _round_rect_skip(x: int, y: int, x0: int, y0: int, x1: int, y1: int, rad: int) -> bool:
	var cx := 0; var cy := 0
	if x < x0 + rad and y < y0 + rad:        cx = x0 + rad; cy = y0 + rad
	elif x >= x1 - rad and y < y0 + rad:     cx = x1 - rad - 1; cy = y0 + rad
	elif x < x0 + rad and y >= y1 - rad:     cx = x0 + rad; cy = y1 - rad - 1
	elif x >= x1 - rad and y >= y1 - rad:    cx = x1 - rad - 1; cy = y1 - rad - 1
	else:
		return false
	var dx := x - cx; var dy := y - cy
	return (dx * dx + dy * dy) > rad * rad

static func _fill_circle(img: Image, center: Vector2, rad: float, c: Color) -> void:
	var r2 := rad * rad
	var x0 := int(center.x - rad) - 1; var y0 := int(center.y - rad) - 1
	var x1 := int(center.x + rad) + 1; var y1 := int(center.y + rad) + 1
	for y in range(y0, y1):
		for x in range(x0, x1):
			var dx := x + 0.5 - center.x
			var dy := y + 0.5 - center.y
			if dx * dx + dy * dy <= r2:
				_set_px(img, x, y, c)

static func _draw_circle_fill(img: Image, center: Vector2, rad: float, c: Color) -> void:
	_fill_circle(img, center, rad, c)

static func _draw_circle_outline(img: Image, center: Vector2, rad: float, c: Color) -> void:
	_fill_circle(img, center, rad, c)
	_fill_circle(img, center, rad - 2.0, Color(0, 0, 0, 0))

static func _draw_arc_top(img: Image, center: Vector2, rad: float, c: Color, a0: float, a1: float) -> void:
	var steps := 24
	for i in range(steps + 1):
		var t := a0 + (a1 - a0) * float(i) / float(steps)
		var px := center.x + cos(t) * rad
		var py := center.y + sin(t) * rad
		_fill_circle(img, Vector2(px, py), 3.0, c)

static func _fill_triangle(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, c: Color) -> void:
	var minx := int(min(p0.x, min(p1.x, p2.x))) - 1
	var maxx := int(max(p0.x, max(p1.x, p2.x))) + 1
	var miny := int(min(p0.y, min(p1.y, p2.y))) - 1
	var maxy := int(max(p0.y, max(p1.y, p2.y))) + 1
	for y in range(miny, maxy):
		for x in range(minx, maxx):
			if _point_in_tri(Vector2(x + 0.5, y + 0.5), p0, p1, p2):
				_set_px(img, x, y, c)

static func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign(p, a, b)
	var d2 := _sign(p, b, c)
	var d3 := _sign(p, c, a)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)

static func _sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)

# ── 动画关键帧数据 ──────────────────────────────────────────────────────
static func _anim_data(anim_key: String) -> Array:
	match anim_key:
		"breath":
			return [
				[AnimKF.new("torso", [0, 1.5, 3.0], [0, -1.2, 0], [], [Vector2(1,1), Vector2(1, 1.03), Vector2(1,1)]), 3.0],
				[AnimKF.new("head", [0, 1.5, 3.0], [0, 1.5, 0], [], []), 3.0],
				[AnimKF.new("upper_arm_R", [0, 1.5, 3.0], [0, 2.0, 0], [], []), 3.0],
				[AnimKF.new("upper_arm_L", [0, 1.5, 3.0], [0, -2.0, 0], [], []), 3.0],
				[AnimKF.new("fore_arm_R", [0, 1.5, 3.0], [0, 3.0, 0], [], []), 3.0],
				[AnimKF.new("fore_arm_L", [0, 1.5, 3.0], [0, -3.0, 0], [], []), 3.0],
			]
		"walk":
			return [
				[AnimKF.new("thigh_R", [0, 0.25, 0.5, 0.75, 1.0], [-25, 0, 25, 0, -25], [], []), 1.0],
				[AnimKF.new("thigh_L", [0, 0.25, 0.5, 0.75, 1.0], [25, 0, -25, 0, 25], [], []), 1.0],
				[AnimKF.new("shin_R", [0, 0.25, 0.5, 0.75, 1.0], [10, 40, 10, 0, 10], [], []), 1.0],
				[AnimKF.new("shin_L", [0, 0.25, 0.5, 0.75, 1.0], [10, 0, 10, 40, 10], [], []), 1.0],
				[AnimKF.new("upper_arm_R", [0, 0.25, 0.5, 0.75, 1.0], [20, 0, -20, 0, 20], [], []), 1.0],
				[AnimKF.new("upper_arm_L", [0, 0.25, 0.5, 0.75, 1.0], [-20, 0, 20, 0, -20], [], []), 1.0],
				[AnimKF.new("fore_arm_R", [0, 0.5, 1.0], [-20, -10, -20], [], []), 1.0],
				[AnimKF.new("fore_arm_L", [0, 0.5, 1.0], [20, 10, 20], [], []), 1.0],
				[AnimKF.new("torso", [0, 0.5, 1.0], [-2, 2, -2], [], []), 1.0],
			]
		"run":
			return [
				[AnimKF.new("thigh_R", [0, 0.125, 0.25, 0.375, 0.5], [-40, -10, 35, 50, -40], [], []), 0.5],
				[AnimKF.new("thigh_L", [0, 0.125, 0.25, 0.375, 0.5], [35, 50, -40, -10, 35], [], []), 0.5],
				[AnimKF.new("shin_R", [0, 0.125, 0.25, 0.375, 0.5], [20, 60, 20, 0, 20], [], []), 0.5],
				[AnimKF.new("shin_L", [0, 0.125, 0.25, 0.375, 0.5], [20, 0, 20, 60, 20], [], []), 0.5],
				[AnimKF.new("upper_arm_R", [0, 0.125, 0.25, 0.375, 0.5], [40, 0, -40, 0, 40], [], []), 0.5],
				[AnimKF.new("upper_arm_L", [0, 0.125, 0.25, 0.375, 0.5], [-40, 0, 40, 0, -40], [], []), 0.5],
				[AnimKF.new("fore_arm_R", [0, 0.25, 0.5], [-50, -30, -50], [], []), 0.5],
				[AnimKF.new("fore_arm_L", [0, 0.25, 0.5], [50, 30, 50], [], []), 0.5],
				[AnimKF.new("torso", [0, 0.25, 0.5], [-8, -6, -8], [], [Vector2(1,1), Vector2(1,0.98), Vector2(1,1)]), 0.5],
				[AnimKF.new("hip", [0, 0.125, 0.25, 0.375, 0.5], [0, -3, 0, -3, 0], [], []), 0.5],
			]
		"sword_swing":
			return [
				[AnimKF.new("upper_arm_R", [0, 0.2, 0.45, 0.7], [-10, -120, 30, -10], [], []), 0.7],
				[AnimKF.new("fore_arm_R", [0, 0.2, 0.45, 0.7], [-30, -90, 10, -30], [], []), 0.7],
				[AnimKF.new("hand_R", [0, 0.2, 0.45, 0.7], [0, -20, 30, 0], [], []), 0.7],
				[AnimKF.new("torso", [0, 0.2, 0.45, 0.7], [0, -8, 12, 0], [], []), 0.7],
				[AnimKF.new("upper_arm_L", [0, 0.2, 0.45, 0.7], [0, 10, -15, 0], [], []), 0.7],
				[AnimKF.new("thigh_R", [0, 0.2, 0.45, 0.7], [0, -5, 8, 0], [], []), 0.7],
			]
	return []

# ── 构建 Animation 资源 ─────────────────────────────────────────────────
static func _build_animation(anim_key: String, def: BoneDef) -> Animation:
	var data: Array = _anim_data(anim_key)
	if data.is_empty():
		push_error("GenAll: unknown anim " + anim_key)
		return null
	var duration: float = data[0][1]
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_NONE
	if anim_key != "sword_swing":
		anim.loop_mode = Animation.LOOP_LINEAR
	var rest_rot: Dictionary = {}
	for b in def.bones:
		var bs: BoneSpec = b
		rest_rot[bs.name] = bs.local_rot
	for entry in data:
		var kf: AnimKF = entry[0]
		if kf.bone == "":
			continue
		var base: float = rest_rot.get(kf.bone, 0.0)
		if kf.rots.size() > 0:
			var track := anim.add_track(Animation.TYPE_VALUE)
			var path := "Skeleton2D/%s:rotation" % _full_path(kf.bone, def)
			anim.track_set_path(track, path)
			anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
			for i in kf.times.size():
				var t: float = kf.times[i]
				var deg: float = kf.rots[i]
				var val: float = base + deg_to_rad(deg)
				anim.track_insert_key(track, t, val)
			anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC_ANGLE)
		if kf.scales.size() > 0 and kf.times.size() == kf.scales.size():
			var track := anim.add_track(Animation.TYPE_VALUE)
			var path := "Skeleton2D/%s:scale" % _full_path(kf.bone, def)
			anim.track_set_path(track, path)
			anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
			for i in kf.times.size():
				anim.track_insert_key(track, kf.times[i], kf.scales[i])
			anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		if kf.poss.size() > 0 and kf.times.size() == kf.poss.size():
			var track := anim.add_track(Animation.TYPE_VALUE)
			var path := "Skeleton2D/%s:position" % _full_path(kf.bone, def)
			anim.track_set_path(track, path)
			anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
			for i in kf.times.size():
				anim.track_insert_key(track, kf.times[i], kf.poss[i])
			anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	return anim

# 构造从 Skeleton2D 到某骨的节点路径
static func _full_path(bone_name: String, def: BoneDef) -> String:
	var chain: Array = []
	var cur := bone_name
	var guard := 0
	while cur != "" and guard < 100:
		guard += 1
		chain.push_front(cur)
		cur = _parent_of(cur, def)
	return "/".join(chain)

static func _parent_of(bone_name: String, def: BoneDef) -> String:
	for b in def.bones:
		var bs: BoneSpec = b
		if bs.name == bone_name:
			return bs.parent
	return ""

# ── 入口 ────────────────────────────────────────────────────────────────
static func generate(force: bool = false) -> void:
	_ensure_dirs()
	var def := _build_bone_def()
	var sk_path := "%s/%s.tres" % [SKEL_DIR, SKEL_KEY]
	if force or not ResourceLoader.exists(sk_path):
		var err := ResourceSaver.save(def, sk_path)
		if err != OK:
			push_error("GenAll: save skeleton failed %d" % err)
	var anim_keys := ["breath", "walk", "run", "sword_swing"]
	for ak in anim_keys:
		var ap := "%s/%s.tres" % [ANIM_DIR, ak]
		if not force and ResourceLoader.exists(ap):
			continue
		var anim := _build_animation(ak, def)
		if anim == null:
			continue
		var err := ResourceSaver.save(anim, ap)
		if err != OK:
			push_error("GenAll: save anim %s failed %d" % [ak, err])
	var sets := ["A", "B"]
	var labels := {"A": "骑士(钢甲)", "B": "兽人(皮甲)"}
	for set in sets:
		var meta_path := "%s/%s/_meta.tres" % [ART_DIR, set]
		if force or not ResourceLoader.exists(meta_path):
			var m := ArtSetMeta.new()
			m.key = set
			m.label = labels[set]
			ResourceSaver.save(m, meta_path)
		var colors := _art_colors(set)
		var d: Dictionary = _bone_data()
		var bones: Array = d["bones"]
		for b in bones:
			var bw: BoneW = b
			var png_path := "%s/%s/%s.png" % [ART_DIR, set, bw.name]
			if not force and FileAccess.file_exists(png_path):
				continue
			var img := _render_bone_png(bw, colors)
			var err := img.save_png(png_path)
			if err != OK:
				push_error("GenAll: save png %s failed %d" % [png_path, err])

static func _ensure_dirs() -> void:
	for d in [SKEL_DIR, ANIM_DIR, ART_DIR + "/A", ART_DIR + "/B"]:
		DirAccess.make_dir_recursive_absolute(d)
