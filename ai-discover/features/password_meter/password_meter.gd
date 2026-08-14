extends Control
## =============================================================================
## 密码强度计 —— 实时规则评估 + 彩色强度条 + 建议提示（UI 组件）
## =============================================================================
## · 输入框实时评估：长度 / 大小写 / 数字 / 特殊字符 / 常见弱密码；
## · 五段强度条随分数点亮（红→黄→绿），列出改进建议；
## · 评估（_evaluate）为纯函数，可确定性测试。
## =============================================================================

const WEAK_WORDS := ["password", "123456", "qwerty", "admin", "iloveyou", "abc123"]

var _score := 0
var _checks: Array = []      # {label, ok}

@onready var edit: LineEdit = $Center/VBox/Input
@onready var score_label: Label = $Center/VBox/ScoreLabel
@onready var tips_label: Label = $Center/VBox/TipsLabel
@onready var bar: Control = $Center/VBox/Bar


func _ready() -> void:
	edit.text_changed.connect(_on_text)


## 评估密码（供测试与 UI）：返回 [分数0..5, 检查项]
func _evaluate(pw: String) -> Array:
	var checks: Array = [
		{"label": "长度 ≥ 8", "ok": pw.length() >= 8},
		{"label": "长度 ≥ 12（加分）", "ok": pw.length() >= 12},
		{"label": "含大小写字母", "ok": pw != pw.to_lower() and pw != pw.to_upper()},
		{"label": "含数字", "ok": pw.contains("0") or pw.contains("1") or pw.contains("2") or pw.contains("3") or pw.contains("4") or pw.contains("5") or pw.contains("6") or pw.contains("7") or pw.contains("8") or pw.contains("9")},
		{"label": "含特殊字符", "ok": pw.contains("!") or pw.contains("@") or pw.contains("#") or pw.contains("$") or pw.contains("%") or pw.contains("^") or pw.contains("&") or pw.contains("*")},
		{"label": "不是常见弱密码", "ok": not WEAK_WORDS.has(pw.to_lower())},
	]
	var score := 0
	for c in checks:
		if c["ok"]:
			score += 1
	return [score, checks]


func _on_text(pw: String) -> void:
	var result: Array = _evaluate(pw)
	_score = result[0]
	_checks = result[1]
	score_label.text = "强度：%d / 6" % _score
	var tips := ""
	for c in _checks:
		tips += ("✅ " if c["ok"] else "❌ ") + c["label"] + "\n"
	tips_label.text = tips
	queue_redraw()


func _draw() -> void:
	# 五段强度条
	var n := 6
	var seg_w := 620.0 / n
	var colors := [Color(0.9, 0.3, 0.3), Color(0.95, 0.6, 0.25), Color(0.9, 0.8, 0.25), Color(0.6, 0.85, 0.35), Color(0.35, 0.8, 0.45), Color(0.25, 0.7, 0.45)]
	for i in n:
		var lit := i < _score
		var col: Color = colors[i] if lit else Color(0.25, 0.27, 0.33)
		draw_rect(Rect2(i * seg_w + 2, 0, seg_w - 4, 26), col)
