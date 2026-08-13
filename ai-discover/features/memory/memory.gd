extends Control
## =============================================================================
## 记忆翻牌 —— 4×4 配对记忆游戏（翻转动画 + 匹配判定）
## =============================================================================
## · 16 张背面朝上的卡片（8 对表情），点击翻面；
## · 连续翻开两张：相同 → 保持翻开并闪亮；不同 → 0.7 秒后翻回；
## · 全部配对 → 胜利结算（步数）；【重新开始】洗牌。
## 游戏规则集中在 _on_card_clicked，可确定性测试。
## =============================================================================

const EMOJIS: Array[String] = ["🐶", "🐱", "🐸", "🦊", "🐼", "🐨", "🦁", "🐯"]

var _cards: Array = []          # {btn, emoji, matched}
var _flipped: Array = []        # 当前翻开（最多 2）的卡下标
var _moves := 0
var _lock := false              # 等待翻回期间锁输入

@onready var grid: GridContainer = $Center/VBox/Grid
@onready var status_label: Label = $Center/VBox/StatusLabel


func _ready() -> void:
	$Center/VBox/RestartBtn.pressed.connect(_restart)
	_build_grid()


func _build_grid() -> void:
	for c in _cards:
		c["btn"].queue_free()
	_cards.clear()
	_flipped.clear()
	_moves = 0
	_lock = false
	# 8 对表情洗牌
	var pool: Array[String] = []
	for e in EMOJIS:
		pool.append(e)
		pool.append(e)
	pool.shuffle()
	for i in 16:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 110)
		btn.add_theme_font_size_override("font_size", 42)
		btn.text = "❓"
		btn.pressed.connect(_on_card_clicked.bind(i))
		grid.add_child(btn)
		_cards.append({"btn": btn, "emoji": pool[i], "matched": false})
	status_label.text = "翻开两张配对 · 步数：0"


func _restart() -> void:
	_build_grid()


## 点击翻牌（规则核心）
func _on_card_clicked(i: int) -> void:
	if _lock or _flipped.size() >= 2 or _cards[i]["matched"] or _flipped.has(i):
		return
	_flip_open(i)
	_flipped.append(i)
	if _flipped.size() == 2:
		_moves += 1
		status_label.text = "翻开两张配对 · 步数：%d" % _moves
		if _cards[_flipped[0]]["emoji"] == _cards[_flipped[1]]["emoji"]:
			# 配对成功
			for idx in _flipped:
				_cards[idx]["matched"] = true
				var tw: Tween = _cards[idx]["btn"].create_tween()
				tw.tween_property(_cards[idx]["btn"], "modulate", Color(0.6, 1.0, 0.6), 0.25)
				tw.tween_property(_cards[idx]["btn"], "modulate", Color.WHITE, 0.25)
			_flipped.clear()
			_check_win()
		else:
			# 配对失败：0.7 秒后翻回
			_lock = true
			var tw := create_tween()
			tw.tween_interval(0.7)
			tw.tween_callback(func() -> void:
				for idx in _flipped:
					_flip_close(idx)
				_flipped.clear()
				_lock = false)


func _flip_open(i: int) -> void:
	var btn: Button = _cards[i]["btn"]
	# 翻转动画：横向压缩 → 换面 → 展开
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale:x", 0.0, 0.1)
	tw.tween_callback(func() -> void: btn.text = _cards[i]["emoji"])
	tw.tween_property(btn, "scale:x", 1.0, 0.1)


func _flip_close(i: int) -> void:
	var btn: Button = _cards[i]["btn"]
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale:x", 0.0, 0.1)
	tw.tween_callback(func() -> void: btn.text = "❓")
	tw.tween_property(btn, "scale:x", 1.0, 0.1)


func _check_win() -> void:
	for c in _cards:
		if not c["matched"]:
			return
	status_label.text = "🎉 全部配对！共 %d 步 · 点击重新开始" % _moves
