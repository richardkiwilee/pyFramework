extends Control
## =============================================================================
## 打字机对话 —— 逐字显示 + 点击加速/跳过 + 分支选项（RPG 对话组件）
## =============================================================================
## · 对话脚本是节点列表：{speaker, text, choices/branches}；
## · 文字逐字打出（可调速度），点击：未打完 → 立即显示全文；
##   已打完 → 进入下一句；带选项的节点显示选项按钮，点击走分支；
## · 左侧头像随说话人切换（铁匠/你）。
## =============================================================================

const TYPE_SPEED := 28.0     # 每秒字符数

const SCRIPT: Array[Dictionary] = [
	{"speaker": "铁匠", "text": "欢迎来到我的铁匠铺，冒险者！"},
	{"speaker": "铁匠", "text": "你今天想买点什么？", "choices": ["⚔ 长剑（50 金）", "🛡 盾牌（80 金）"], "branch": [2, 3]},
	{"speaker": "铁匠", "text": "好眼光！这把剑削铁如泥，跟着你准能斩龙。"},
	{"speaker": "你", "text": "这面盾牌能挡下巨龙的火焰吗？"},
	{"speaker": "铁匠", "text": "当然！用它的人还没有被烤熟的先例，哈哈！"},
]

var _node := 0
var _typed := 0.0
var _choices_shown := false

@onready var name_label: Label = $DialogPanel/Box/NameLabel
@onready var text_label: Label = $DialogPanel/Box/TextLabel
@onready var continue_label: Label = $DialogPanel/Box/ContinueLabel
@onready var choice_box: VBoxContainer = $DialogPanel/Box/ChoiceBox


func _ready() -> void:
	_enter_node(0)


func _enter_node(idx: int) -> void:
	_node = idx
	_typed = 0.0
	_choices_shown = false
	for c in choice_box.get_children():
		c.queue_free()
	var d: Dictionary = SCRIPT[_node]
	name_label.text = "🔨 %s" % d["speaker"] if d["speaker"] == "铁匠" else "🧝 你"
	queue_redraw()   # 头像随说话人重绘
	text_label.text = ""
	continue_label.visible = false
	if d.has("choices"):
		for i in d["choices"].size():
			var b := Button.new()
			b.text = d["choices"][i]
			b.custom_minimum_size = Vector2(260, 44)
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(_on_choice.bind(d["branch"][i]))
			choice_box.add_child(b)
		_choices_shown = true


func _process(delta: float) -> void:
	var d: Dictionary = SCRIPT[_node]
	if _typed < d["text"].length():
		_typed = minf(float(d["text"].length()), _typed + TYPE_SPEED * delta)
		text_label.text = d["text"].substr(0, int(_typed))
		continue_label.visible = false
	elif not _choices_shown:
		continue_label.visible = true   # ▼ 点击继续


## 点击：未打完 → 立即显示全文；已打完 → 下一句
## （用 _unhandled_input，选项按钮消费掉自己的点击后不会走到这里）
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var d: Dictionary = SCRIPT[_node]
	if _typed < d["text"].length():
		# 第一次点击：立即显示全文
		_typed = float(d["text"].length())
		text_label.text = d["text"]
		continue_label.visible = not _choices_shown
	elif not _choices_shown:
		# 第二次点击：下一句（到结尾则循环）
		_enter_node((_node + 1) % SCRIPT.size())
		get_viewport().set_input_as_handled()


func _on_choice(branch: int) -> void:
	_enter_node(branch)


## 头像：铁匠 = 棕色络腮大叔，你 = 蓝色兜帽
func _draw() -> void:
	var c := Vector2(220, 400)
	var d: Dictionary = SCRIPT[_node]
	if d["speaker"] == "铁匠":
		draw_circle(c + Vector2(0, -30), 62, Color(0.55, 0.40, 0.28))   # 头
		draw_rect(Rect2(c + Vector2(-85, 20), Vector2(170, 120)), Color(0.35, 0.25, 0.18))  # 肩
		draw_rect(Rect2(c + Vector2(-20, -52), Vector2(40, 26)), Color(0.30, 0.20, 0.14))  # 胡子
		draw_circle(c + Vector2(-20, -38), 5, Color(0.1, 0.08, 0.06))
		draw_circle(c + Vector2(20, -38), 5, Color(0.1, 0.08, 0.06))
	else:
		draw_circle(c + Vector2(0, -30), 58, Color(0.85, 0.72, 0.55))   # 头
		draw_circle(c + Vector2(0, -58), 52, Color(0.25, 0.42, 0.75))   # 兜帽
		draw_rect(Rect2(c + Vector2(-80, 18), Vector2(160, 110)), Color(0.28, 0.45, 0.78))  # 肩
		draw_circle(c + Vector2(-20, -36), 5, Color(0.1, 0.08, 0.06))
		draw_circle(c + Vector2(20, -36), 5, Color(0.1, 0.08, 0.06))
