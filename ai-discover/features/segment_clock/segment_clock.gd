extends Node2D
## =============================================================================
## 七段数码管时钟 —— 经典 LED 数码管显示当前时间
## =============================================================================
## · 6 位数字（HH:MM:SS）+ 每秒闪烁的冒号；
## · 每位由 7 段矩形组成（段编码表驱动），亮段橙红、暗段微光可见；
## · 段编码（_segments_for）为纯函数，可确定性测试。
## =============================================================================

const DIGIT_W := 60.0
const DIGIT_H := 100.0
const SPACING := 76.0
const ORIGIN := Vector2(280, 250)

## 数字 → 亮起的段索引（0=上横 1=右上竖 2=右下竖 3=下横 4=左下竖 5=左上竖 6=中横）
const SEGMENT_MAP: Dictionary = {
	"0": [0, 1, 2, 3, 4, 5],
	"1": [1, 2],
	"2": [0, 1, 6, 4, 3],
	"3": [0, 1, 6, 2, 3],
	"4": [5, 6, 1, 2],
	"5": [0, 5, 6, 2, 3],
	"6": [0, 5, 6, 2, 3, 4],
	"7": [0, 1, 2],
	"8": [0, 1, 2, 3, 4, 5, 6],
	"9": [0, 1, 2, 3, 5, 6],
}


func _segments_for(digit: String) -> Array:
	return SEGMENT_MAP[digit]


## 段 i 在 digit 原点 (x,y) 处的矩形
func _seg_rect(i: int, x: float, y: float) -> Rect2:
	match i:
		0: return Rect2(x + 8, y + 2, 44, 10)
		1: return Rect2(x + 50, y + 10, 10, 38)
		2: return Rect2(x + 50, y + 52, 10, 38)
		3: return Rect2(x + 8, y + 88, 44, 10)
		4: return Rect2(x + 0, y + 52, 10, 38)
		5: return Rect2(x + 0, y + 10, 10, 38)
		_: return Rect2(x + 8, y + 45, 44, 10)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t := Time.get_time_dict_from_system()
	var text := "%02d:%02d:%02d" % [t["hour"], t["minute"], t["second"]]
	for i in 6:
		if text[i] == ":":
			# 冒号（每秒闪烁）
			var on := int(t["second"]) % 2 == 0
			var cx := ORIGIN.x + i * SPACING - 6.0
			draw_circle(Vector2(cx, ORIGIN.y + 38), 6, Color(1, 0.55, 0.2, 1.0 if on else 0.15))
			draw_circle(Vector2(cx, ORIGIN.y + 62), 6, Color(1, 0.55, 0.2, 1.0 if on else 0.15))
		else:
			var x := ORIGIN.x + i * SPACING
			for seg in 7:
				var lit := seg in _segments_for(text[i])
				var col := Color(1.0, 0.5, 0.15, 0.95) if lit else Color(1.0, 0.45, 0.15, 0.08)
				draw_rect(_seg_rect(seg, x, ORIGIN.y), col)
