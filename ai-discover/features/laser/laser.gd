extends Node2D
## =============================================================================
## 激光反射 —— 光线追踪 + 可拖拽旋转的镜面，把光束引导到靶心
## =============================================================================
## · 发射器固定在中左，光束沿直线前进；
## · 遇到镜面（线段）按反射定律反弹，最多 12 次弹跳；
## · 光束命中靶心 → 靶子发光 + 计数 +1，靶心随机换位；
## · 交互：拖拽镜面移动，选中镜面后按 R 旋转（或滚轮微调）。
## 核心是 _cast_beam()：纯函数式光线追踪，可单元测试。
## =============================================================================

const MAX_BOUNCES := 12
const EMITTER := Vector2(90, 360)

var _mirrors: Array = []        # {pos, angle}
var _target := Vector2(900, 200)
var _hits := 0
var _selected := -1
var _dragging := -1
var _beam_points: PackedVector2Array = []
var _hit_target := false

@onready var hits_label: Label = $CanvasLayer/HitsLabel


func _ready() -> void:
	# 初始三面镜：把光束折向靶心方向
	_mirrors.append({"pos": Vector2(380, 300), "angle": 0.9})
	_mirrors.append({"pos": Vector2(620, 440), "angle": -0.7})
	_mirrors.append({"pos": Vector2(740, 220), "angle": 0.3})
	_cast()


## 光线追踪：从发射器出发，遇镜反射，返回路径点与命中结果
## 每一跳先算"最近镜面距离"与"靶心距离"，谁近谁先发生：
## 靶心在镜面之前（或途中没有镜面）→ 直接命中。
func _cast_beam() -> Dictionary:
	var origin := EMITTER
	var dir := Vector2(1, 0)
	var pts := PackedVector2Array([origin])
	var hit := false
	for bounce in MAX_BOUNCES:
		# 1. 最近镜面
		var best_t := INF
		var best_m := -1
		for i in _mirrors.size():
			var t := _ray_mirror_hit(origin, dir, _mirrors[i])
			if t > 0.01 and t < best_t:
				best_t = t
				best_m = i
		# 2. 靶心距离（方向对准才算）
		var to_target := _target - origin
		var t_target := INF
		if to_target.length() > 40.0 and dir.normalized().dot(to_target.normalized()) > 0.999:
			t_target = to_target.length()
		# 3. 判定：无镜面 → 只看靶心；靶心比镜面近 → 命中
		if best_m < 0:
			if t_target < INF:
				pts.append(_target)
				hit = true
			break
		if t_target < best_t:
			pts.append(_target)
			hit = true
			break
		# 4. 镜面反射：d' = d - 2(d·n)n
		var hit_point := origin + dir * best_t
		pts.append(hit_point)
		var n: Vector2 = Vector2.from_angle(_mirrors[best_m]["angle"] + PI / 2.0)
		if dir.dot(n) > 0:
			n = -n
		dir = (dir - 2.0 * dir.dot(n) * n).normalized()
		origin = hit_point
	return {"points": pts, "hit": hit}


## 射线与镜面线段的交点参数 t（无交点返回 INF）
func _ray_mirror_hit(origin: Vector2, dir: Vector2, mirror: Dictionary) -> float:
	var n: Vector2 = Vector2.from_angle(mirror["angle"] + PI / 2.0)
	var denom := dir.dot(n)
	if absf(denom) < 0.0001:
		return INF
	var t: float = (mirror["pos"] - origin).dot(n) / denom
	if t <= 0:
		return INF
	var p := origin + dir * t
	# 镜面长度 110，交点在镜面范围内才算
	var along: Vector2 = Vector2.from_angle(mirror["angle"])
	if absf((p - mirror["pos"]).dot(along)) > 55.0:
		return INF
	return t


func _cast() -> void:
	var result := _cast_beam()
	_beam_points = result["points"]
	_hit_target = result["hit"]
	if _hit_target:
		_hits += 1
		hits_label.text = "🎯 命中：%d" % _hits
		_target = Vector2(randf_range(500, 1150), randf_range(120, 600))
	queue_redraw()


# ============================================================
#  交互：拖拽镜面 / R 旋转 / 滚轮微调
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var i := _mirror_at(event.position)
			_selected = i
			_dragging = i
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = -1
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and _selected >= 0:
			_mirrors[_selected]["angle"] += 0.08
			_cast()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and _selected >= 0:
			_mirrors[_selected]["angle"] -= 0.08
			_cast()
	elif event is InputEventMouseMotion and _dragging >= 0:
		_mirrors[_dragging]["pos"] = event.position
		_cast()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R and _selected >= 0:
		_mirrors[_selected]["angle"] += PI / 12.0
		_cast()
		get_viewport().set_input_as_handled()


func _mirror_at(p: Vector2) -> int:
	for i in _mirrors.size():
		if p.distance_to(_mirrors[i]["pos"]) < 45.0:
			return i
	return -1


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	# 光束（发光虚线感：先画粗暗再画细亮）
	for i in _beam_points.size() - 1:
		draw_line(_beam_points[i], _beam_points[i + 1], Color(1, 0.3, 0.2, 0.25), 10.0)
		draw_line(_beam_points[i], _beam_points[i + 1], Color(1, 0.45, 0.3), 3.5)
	# 发射器
	draw_circle(EMITTER, 16, Color(0.25, 0.27, 0.34))
	draw_circle(EMITTER, 9, Color(1, 0.5, 0.3))
	# 镜面
	for i in _mirrors.size():
		var m: Dictionary = _mirrors[i]
		var along: Vector2 = Vector2.from_angle(m["angle"])
		var p1: Vector2 = m["pos"] - along * 55.0
		var p2: Vector2 = m["pos"] + along * 55.0
		var col := Color(0.65, 0.75, 0.9) if i == _selected else Color(0.45, 0.55, 0.7)
		draw_line(p1, p2, Color(0.2, 0.25, 0.35), 9.0)
		draw_line(p1, p2, col, 5.0)
		draw_circle(m["pos"], 7, Color(1, 1, 1, 0.8))
	# 靶心
	if _hit_target:
		draw_circle(_target, 26, Color(0.3, 1.0, 0.5, 0.35))
	draw_circle(_target, 18, Color(0.15, 0.16, 0.22))
	draw_arc(_target, 18, 0, TAU, 32, Color(0.35, 1.0, 0.55), 4.0)
	draw_circle(_target, 6, Color(0.4, 1.0, 0.6))
