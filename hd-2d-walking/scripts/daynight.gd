extends Node2D
## 昼夜与光照。
##
## 三层叠加，各管一件事：
##   1. CanvasModulate —— 环境色。决定"这一刻世界整体偏什么颜色"，是画面基调。
##   2. DirectionalLight2D（日/月）—— 只贡献颜色和强度，投影阴影交给 shadows.gd。
##   3. PointLight2D —— 夜里的灯柱与窗火，白昼能量为 0。
##
## time ∈ [0,1)：0.00 午夜，0.25 日出，0.50 正午，0.75 日落。
##
## 注意：Godot 2D 里环境色与平行光是**相加**的（CanvasModulate 是乘，光在其上再叠一份）。
## 两者之和必须控制在 1.0 附近，加起来超过 1.3 画面就整个过曝、草会变成荧光绿。

const Proj = preload("res://scripts/proj.gd")

## (时刻, 环境色, 太阳强度, 太阳颜色, 月亮强度, 影子强度)
const KEYS := [
	[0.00, Color(0.30, 0.34, 0.54), 0.00, Color(0.60, 0.70, 1.00), 0.10, 0.30],
	[0.20, Color(0.32, 0.36, 0.56), 0.00, Color(0.60, 0.70, 1.00), 0.09, 0.30],
	[0.26, Color(0.58, 0.50, 0.52), 0.24, Color(1.00, 0.58, 0.38), 0.00, 0.56],
	[0.33, Color(0.68, 0.64, 0.62), 0.40, Color(1.00, 0.86, 0.68), 0.00, 0.50],
	[0.42, Color(0.70, 0.70, 0.71), 0.40, Color(1.00, 0.97, 0.90), 0.00, 0.44],
	[0.50, Color(0.71, 0.72, 0.73), 0.40, Color(1.00, 0.99, 0.96), 0.00, 0.40],
	[0.60, Color(0.70, 0.70, 0.70), 0.40, Color(1.00, 0.95, 0.84), 0.00, 0.44],
	[0.70, Color(0.66, 0.62, 0.60), 0.38, Color(1.00, 0.82, 0.60), 0.00, 0.52],
	[0.75, Color(0.56, 0.48, 0.50), 0.24, Color(1.00, 0.54, 0.36), 0.00, 0.58],
	[0.80, Color(0.38, 0.38, 0.56), 0.05, Color(0.80, 0.66, 0.90), 0.05, 0.36],
	[1.00, Color(0.30, 0.34, 0.54), 0.00, Color(0.60, 0.70, 1.00), 0.10, 0.30],
]

## 影子色：不用纯黑，用偏蓝紫的深色，夜里才不会显脏
const SHADOW_TINT := Color(0.07, 0.08, 0.18)
## 影子长度换算：1 像素高的东西投出多少像素影子。
## 由投影几何定——横向 1 单位高 = TILE 像素，纵向 = ELEV_H 像素，
## 而地面上一格纵向是 ROW_H 像素，所以比例是 ROW_H/ELEV_H = 16/12 = 1.333。
const SHADOW_K := float(Proj.ROW_H) / float(Proj.ELEV_H)

var time := 0.34
var auto_advance := false
var speed := 0.010

var _ambient: CanvasModulate
var _sun: DirectionalLight2D
var _moon: DirectionalLight2D
var _lamp_root: Node2D
var _lamps: Array = []
var _shadows = null


func _ready() -> void:
	_ambient = CanvasModulate.new()
	add_child(_ambient)

	_sun = _new_light(Color(1, 1, 1), 1.0)
	_moon = _new_light(Color(0.6, 0.7, 1.0), 0.0)
	_lamp_root = Node2D.new()
	add_child(_lamp_root)
	apply()


func _new_light(col: Color, energy: float) -> DirectionalLight2D:
	var l := DirectionalLight2D.new()
	l.color = col
	l.energy = energy
	l.height = 300.0
	# 2D 光默认只照亮 z_index ∈ [-1024, 1024] 的物件；本项目的深度键最大到 1344，
	# 不放开的话靠南的地形会整片不受光，出现一条诡异的分界线。
	l.range_z_min = -4096
	l.range_z_max = 4096
	add_child(l)
	return l


func set_shadows(node) -> void:
	_shadows = node


## 主角提的灯。挂在角色节点下面，位置自动跟随，不用每帧同步。
##
## 没有它的话，夜里角色就是一团糊在暗蓝里的黑影，玩家根本找不到自己。
## 一盏小灯既解决可读性，又正好是"大世界光照系统"该有的东西。
func attach_player_light(player_node: Node2D) -> void:
	var warm := load("res://assets/world/light_radial.png") as Texture2D
	var l := PointLight2D.new()
	l.texture = warm
	l.texture_scale = 46.0 / 128.0
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	l.position = Vector2(0.0, -18.0)      # 提在手上，不是踩在脚下
	l.energy = 0.0
	l.color = Color(1.0, 0.88, 0.66)
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.range_z_min = -4096
	l.range_z_max = 4096
	player_node.add_child(l)
	_lamps.append({"node": l, "energy": 0.85})


## 夜晚光源：灯柱 + 建筑窗火
func build_point_lights(objects: Array) -> void:
	var warm := load("res://assets/world/light_radial.png") as Texture2D
	for o in objects:
		var n := String(o["n"])
		var px: float = float(o["x"]) * Proj.TILE + float(o["ox"])
		var py: float = float(o["y"]) * Proj.TILE - float(o["h"]) * Proj.ELEV_H + float(o["oy"])
		if n == "lamp":
			_add_lamp(warm, Vector2(px, py - 30.0), 58.0, 1.15)
		elif n.begins_with("house") or n == "barn":
			_add_lamp(warm, Vector2(px + 6.0, py + 2.0), 54.0, 0.90)
		elif n == "torii":
			_add_lamp(warm, Vector2(px, py + 2.0), 64.0, 0.75)


func _add_lamp(tex: Texture2D, p: Vector2, radius: float, energy: float) -> void:
	var l := PointLight2D.new()
	l.texture = tex
	l.texture_scale = radius / 128.0
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	l.position = p
	l.energy = 0.0
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.range_z_min = -4096
	l.range_z_max = 4096
	_lamp_root.add_child(l)
	_lamps.append({"node": l, "energy": energy})


func _process(delta: float) -> void:
	if auto_advance:
		set_time(fposmod(time + speed * delta, 1.0))


func set_time(t: float) -> void:
	time = t
	apply()


func apply() -> void:
	var s := _sample(time)
	_ambient.color = s["ambient"]
	_sun.color = s["sun_color"]
	_sun.energy = s["sun_energy"]
	_moon.energy = s["moon_energy"]

	var arc := _celestial()
	_sun.rotation = arc["body_rot"]
	_moon.rotation = arc["body_rot"] + PI

	if _shadows != null:
		# 影子越长越淡：一抹影子挡下的光是一定的，摊到更长的面积上，每像素自然更浅。
		# 不做这一步的话，清晨和黄昏会得到"又长又黑"的影子，整片地都糊死。
		var len_fade := clampf(pow(0.34 / maxf(float(arc["length"]), 0.05), 0.75), 0.34, 1.0)
		_shadows.set_sun(arc["s"], arc["t"], float(s["shadow"]) * len_fade,
			Color(SHADOW_TINT.r, SHADOW_TINT.g, SHADOW_TINT.b, 0.90))

	var lit := clampf((s["sun_energy"] + s["moon_energy"]) * 2.6, 0.0, 1.0)
	var lamp_boost := clampf(1.0 - lit, 0.0, 1.0)
	for e in _lamps:
		var l: PointLight2D = e["node"]
		l.energy = float(e["energy"]) * lamp_boost


## 天体位置 → 光源朝向与影子参数
func _celestial() -> Dictionary:
	# 把一整天折成"当前主宰天体"从地平线到地平线的进度 u ∈ [0,1]
	var day := time >= 0.25 and time < 0.75
	var u := 0.0
	var body_rot := 0.0
	if day:
		u = (time - 0.25) / 0.5
		body_rot = deg_to_rad(lerpf(-96.0, 96.0, u))
	else:
		var nt: float = time - 0.75 if time >= 0.75 else time + 0.25
		u = clampf(nt / 0.5, 0.0, 1.0)

	# 影子方向：日出偏左、正午朝正下、日落偏右。
	# 正午不让影子朝上（远离镜头），那样影子会被物体自己挡住，画面反而看不出光照。
	# 方位只摆 ±30°：这是俯视视角，影子一旦横过来就不像"地上的一片暗"，
	# 而像贴在屏幕上的一道斜杠。正午近乎垂直向下，早晚才稍微偏。
	var az := deg_to_rad(lerpf(-30.0, 30.0, u))
	var dirv := Vector2(sin(az), cos(az))
	if not day:
		dirv = -dirv          # 月光从对面来
	var horizon := sin(PI * u)                       # 0 = 贴着地平线，1 = 最高
	var length := lerpf(0.95, 0.30, pow(clampf(horizon, 0.0, 1.0), 0.6))
	return {
		"body_rot": body_rot,
		"length": length,
		"s": SHADOW_K * dirv.x * length,
		"t": SHADOW_K * dirv.y * length,
	}


func _sample(t: float) -> Dictionary:
	var a: Array = KEYS[0]
	var b: Array = KEYS[KEYS.size() - 1]
	for i in range(KEYS.size() - 1):
		if t >= float(KEYS[i][0]) and t <= float(KEYS[i + 1][0]):
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var span := float(b[0]) - float(a[0])
	var k := 0.0 if span <= 0.0 else clampf((t - float(a[0])) / span, 0.0, 1.0)
	return {
		"ambient": (a[1] as Color).lerp(b[1] as Color, k),
		"sun_energy": lerpf(float(a[2]), float(b[2]), k),
		"sun_color": (a[3] as Color).lerp(b[3] as Color, k),
		"moon_energy": lerpf(float(a[4]), float(b[4]), k),
		"shadow": lerpf(float(a[5]), float(b[5]), k),
	}


func clock_text() -> String:
	var mins := int(round(time * 1440.0)) % 1440
	return "%02d:%02d" % [mins / 60, mins % 60]


func phase_text() -> String:
	if time < 0.22 or time >= 0.86:
		return "深夜"
	if time < 0.28:
		return "黎明"
	if time < 0.35:
		return "清晨"
	if time < 0.58:
		return "正午"
	if time < 0.72:
		return "午后"
	if time < 0.79:
		return "黄昏"
	return "入夜"
