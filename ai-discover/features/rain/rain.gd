extends Node2D
## =============================================================================
## 雨滴特效 —— 倾斜雨丝下落 + 落地溅花 + 随机闪电
## =============================================================================
## · 160 条雨丝（近处快长、远处慢短，视差感）；
## · 落地生成扩散溅花（椭圆环），雨丝回收到顶部循环；
## · 随机闪电：屏幕白闪渐隐 + 间歇出现；
## · 滑杆调节雨量（雨丝密度）。
## 推进逻辑（_drop_step）为纯函数，可确定性测试。
## =============================================================================

const GROUND_Y := 640.0
const DROP_COUNT := 160
const MAX_DROPS := 260

var _drops: Array = []       # {pos, speed, len}
var _splashes: Array = []    # {pos, t}
var _flash := 0.0
var _lightning_t := 0.0

@onready var slider: HSlider = $CanvasLayer/Slider


func _ready() -> void:
	for i in DROP_COUNT:
		_drops.append(_new_drop(true))
	slider.min_value = 0.3
	slider.max_value = 1.0
	slider.value = 1.0
	slider.value_changed.connect(func(v: float) -> void:
		while _drops.size() > int(MAX_DROPS * v) and _drops.size() > 10:
			_drops.pop_back()
		while _drops.size() < int(MAX_DROPS * v):
			_drops.append(_new_drop(true)))


func _new_drop(anywhere: bool) -> Dictionary:
	var depth := randf_range(0.4, 1.0)
	return {
		"pos": Vector2(randf_range(-60, 1340), randf_range(-640, GROUND_Y) if anywhere else -40.0),
		"speed": 480.0 * depth + 260.0,
		"len": 12.0 * depth + 8.0,
	}


## 单步推进（供测试）
func _drop_step(delta: float) -> int:
	var splashes := 0
	for d in _drops:
		d["pos"] += Vector2(-d["speed"] * 0.18, d["speed"]) * delta
		if d["pos"].y >= GROUND_Y:
			_splashes.append({"pos": Vector2(d["pos"].x, GROUND_Y), "t": 0.0})
			splashes += 1
			d["pos"] = Vector2(randf_range(-60, 1340), randf_range(-80, -20))
			d["speed"] = randf_range(520, 760)
			d["len"] = randf_range(14, 24)
	return splashes


func _process(delta: float) -> void:
	_drop_step(delta)
	for sp in _splashes:
		sp["t"] += delta
	_splashes = _splashes.filter(func(sp: Dictionary) -> bool: return float(sp["t"]) < 0.5)
	# 随机闪电
	_flash = maxf(0.0, _flash - delta * 1.8)
	_lightning_t -= delta
	if _lightning_t <= 0.0:
		_lightning_t = randf_range(2.5, 6.0)
		_flash = randf_range(0.35, 0.8)
	queue_redraw()


func _draw() -> void:
	# 阴天背景
	draw_rect(Rect2(0, 0, 1280, GROUND_Y), Color(0.07, 0.08, 0.12).lerp(Color(0.16, 0.18, 0.26), 0.4))
	draw_rect(Rect2(0, GROUND_Y, 1280, 80), Color(0.10, 0.12, 0.14))
	# 雨丝
	for d in _drops:
		var p: Vector2 = d["pos"]
		var a := clampf(d["speed"] / 900.0, 0.25, 1.0)
		draw_line(p, p + Vector2(6.0, -d["len"]), Color(0.7, 0.8, 0.95, a * 0.75), 1.5)
	# 溅花（扩散椭圆）
	for sp in _splashes:
		var f: float = 1.0 - sp["t"] / 0.5
		draw_ellipse(sp["pos"], 10.0 + (1.0 - f) * 30.0, 3.0 + (1.0 - f) * 8.0, Color(0.6, 0.75, 0.95, f * 0.6))
	# 闪电白闪
	if _flash > 0.02:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.9, 0.92, 1.0, _flash * 0.55))
