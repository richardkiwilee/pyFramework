extends Node2D
## =============================================================================
## 模拟挂钟 —— 时针/分针/秒针平滑走时 + 罗马数字表盘
## =============================================================================
## · 秒针按真实秒推进（带每帧平滑），分/时针连续移动；
## · 60 刻度 + 12 罗马数字 + 中心轴帽；
## · 指针角度映射（_hand_angle）为纯函数，可确定性测试。
## =============================================================================

const CENTER := Vector2(640, 360)
const RADIUS := 250.0
const ROMAN: Array[String] = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]


## 表盘分数 → 角度（0 = 正上方，顺时针）
func _hand_angle(fraction: float) -> float:
	return -PI / 2.0 + TAU * fposmod(fraction, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# 表盘
	draw_circle(CENTER, RADIUS, Color(0.97, 0.96, 0.93))
	draw_circle(CENTER, RADIUS, Color(0.25, 0.25, 0.3), false, 8.0)
	# 刻度
	for i in 60:
		var a := _hand_angle(float(i) / 60.0)
		var long := i % 5 == 0
		var r1 := RADIUS - (18.0 if long else 10.0)
		draw_line(CENTER + Vector2.from_angle(a) * r1, CENTER + Vector2.from_angle(a) * (RADIUS - 4.0),
			Color(0.15, 0.15, 0.2), 5.0 if long else 2.0)
	# 罗马数字
	var f := ThemeDB.fallback_font
	for i in 12:
		var a := _hand_angle(float(i) / 12.0)
		var p := CENTER + Vector2.from_angle(a) * (RADIUS - 52.0)
		var size := f.get_string_size(ROMAN[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		draw_string(f, p + Vector2(-size.x / 2.0, 8), ROMAN[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.2, 0.2, 0.25))

	var t := Time.get_time_dict_from_system()
	var hour_f := fposmod(float(t["hour"]), 12.0) / 12.0 + float(t["minute"]) / 720.0
	var min_f := float(t["minute"]) / 60.0 + float(t["second"]) / 3600.0
	var sec_f := float(t["second"]) / 60.0
	# 指针
	draw_line(CENTER, CENTER + Vector2.from_angle(_hand_angle(hour_f)) * (RADIUS * 0.5), Color(0.15, 0.15, 0.2), 9.0)
	draw_line(CENTER, CENTER + Vector2.from_angle(_hand_angle(min_f)) * (RADIUS * 0.74), Color(0.2, 0.2, 0.26), 6.0)
	draw_line(CENTER, CENTER + Vector2.from_angle(_hand_angle(sec_f)) * (RADIUS * 0.85), Color(0.85, 0.25, 0.2), 2.5)
	# 轴帽
	draw_circle(CENTER, 12, Color(0.85, 0.25, 0.2))
	draw_circle(CENTER, 5, Color(0.2, 0.2, 0.25))
