extends Node2D
## =============================================================================
## 转盘抽奖 —— 8 扇形转盘 + 指数缓动旋转 + 指针判奖
## =============================================================================
## · 点击【抽奖】随机定目标扇区，转盘旋转 5~7 圈后
##   EXPO_OUT 缓动停在目标扇区（扇区内带随机偏移，更自然）；
## · 顶部指针判定结果，中奖弹窗 + 历史记录。
## 判奖逻辑（_index_at_top/_spin_to）为纯函数，可确定性测试。
## =============================================================================

const SEGMENTS := 8
const LABELS: Array[String] = ["💎 大奖", "🍞 面包", "💰 50金", "😢 再接再厉", "⭐ 稀有星", "🧀 奶酪", "💰 10金", "🍎 苹果"]
const COLORS: Array[Color] = [
	Color(0.95, 0.4, 0.4), Color(0.95, 0.75, 0.4), Color(0.4, 0.8, 0.5),
	Color(0.4, 0.6, 0.95), Color(0.8, 0.5, 0.95), Color(0.95, 0.85, 0.5),
	Color(0.5, 0.85, 0.9), Color(0.9, 0.6, 0.75),
]

var _rotation := 0.0
var _spinning := false
var _history: Array[String] = []

@onready var result_label: Label = $CanvasLayer/ResultLabel
@onready var history_label: Label = $CanvasLayer/HistoryLabel
@onready var spin_btn: Button = $CanvasLayer/SpinBtn


func _ready() -> void:
	spin_btn.pressed.connect(_spin)


func _spin() -> void:
	if _spinning:
		return
	_spinning = true
	spin_btn.disabled = true
	result_label.text = "转起来…"
	var target := randi() % SEGMENTS
	_spin_to(target)


## 旋转到指定扇区（供测试与 _spin 共用）
## 落点取"目标扇区中心 ± 0.3 扇宽"的抖动——保证指针稳稳停在扇区内。
func _spin_to(target: int) -> void:
	var seg_angle := TAU / SEGMENTS
	var cur_top := fposmod(-PI / 2.0 - _rotation, TAU)      # 指针当前在轮上的角
	var jitter := randf_range(-0.3, 0.3) * seg_angle
	var want := target * seg_angle + seg_angle * 0.5 + jitter
	var d := fposmod(cur_top - want, TAU)                   # 向前转的增量
	var spins := 5 + randi() % 3
	var target_rot := _rotation + spins * TAU + d
	var tw := create_tween()
	tw.tween_property(self, "_rotation", target_rot, 3.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_finish.bind(target))


func _finish(target: int) -> void:
	_spinning = false
	spin_btn.disabled = false
	result_label.text = "🎉 抽中：%s" % LABELS[target]
	_history.push_front(LABELS[target])
	if _history.size() > 8:
		_history.pop_back()
	history_label.text = "历史：" + "  ".join(_history)


## 指针（顶部 -90°）当前指向的扇区
func _index_at_top() -> int:
	var seg_angle := TAU / SEGMENTS
	# 扇区 i 覆盖 [_rotation + i*seg, _rotation + (i+1)*seg)
	# 顶部角度 -PI/2 相对转盘的偏移
	var top := fposmod(-PI / 2.0 - _rotation, TAU)
	return int(top / seg_angle) % SEGMENTS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := Vector2(640, 380)
	var r := 250.0
	var seg_angle := TAU / SEGMENTS
	for i in SEGMENTS:
		var a0 := _rotation + i * seg_angle
		var pts := PackedVector2Array([c])
		for j in 12:
			pts.append(c + Vector2.from_angle(a0 + seg_angle * j / 11.0) * r)
		draw_colored_polygon(pts, COLORS[i])
		# 标签（沿扇区中轴）
		var mid := a0 + seg_angle / 2.0
		var lp := c + Vector2.from_angle(mid) * (r * 0.68)
		draw_string(ThemeDB.fallback_font, lp, LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(0.1, 0.1, 0.14))
	# 外圈与中心
	draw_arc(c, r, 0, TAU, 64, Color(0.85, 0.8, 0.6), 6.0)
	draw_circle(c, 22, Color(0.2, 0.2, 0.26))
	# 顶部指针
	var top := Vector2(c.x, c.y - r - 8)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(-20, 46), top + Vector2(20, 46)]), Color(0.95, 0.85, 0.3))
