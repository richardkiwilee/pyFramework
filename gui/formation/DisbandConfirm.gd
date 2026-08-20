## =====================================================================
## DisbandConfirm — 解散队伍确认弹窗
## =====================================================================
## readme 第 16 行：「解散队伍需要弹窗确认。」
##
## 注意这里**刻意没有**照抄参考项目 demo-1 的做法 —— 那个项目的解散是
## 立即执行 + 弹个 toast 提示，没有确认步骤。readme 明确要求确认，所以按 readme 来。
##
## 结构沿用本项目 SettingsMenu.gd 的模态套路：
##   全屏半透明遮罩 ColorRect（点它 = 取消）+ 居中面板 + 两个按钮。
##
## 名字没有叫 ConfirmDialog，是为了避免和 Godot 内置的 ConfirmationDialog 混淆。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control                → UI 控件基类
## ColorRect                      → 纯色矩形控件，这里当半透明遮罩
## MOUSE_FILTER_STOP              → 拦截鼠标，点遮罩可捕获点击
## get_viewport().get_visible_rect().size → 视口可见区域尺寸，用于手动居中
## visible = false                → 初始隐藏
## signal confirmed / canceled    → 两个结果各发一个信号，调用方各接各的
## =====================================================================
class_name DisbandConfirm
extends Control

signal confirmed
signal canceled

const PANEL_W := 380.0
const PANEL_H := 170.0

var _panel: Panel
var _msg: Label


func _init() -> void:
	name = "DisbandConfirm"
	visible = false
	# 遮罩层自己就要吃满鼠标：确认框弹出时，下面所有东西都不该能点。
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 点遮罩空白处 = 取消（和 SettingsMenu 的行为一致）
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			canceled.emit())
	FormationSkin.add_filling(self, dim)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel",
		FormationSkin.box(Color(0.078, 0.063, 0.039, 0.99), FormationSkin.GOLD, 3, 10))
	add_child(_panel)

	var title := FormationSkin.make_title("解散队伍")
	title.position = Vector2(20, 16)
	title.size = Vector2(PANEL_W - 40, 28)
	_panel.add_child(title)

	_msg = FormationSkin.make_text("", FormationSkin.INK, 13)
	_msg.position = Vector2(20, 54)
	_msg.size = Vector2(PANEL_W - 40, 56)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 自动换行
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_panel.add_child(_msg)

	var bw := 130.0
	var by := PANEL_H - 52.0
	var btn_cancel := FormationSkin.make_button("取消")
	btn_cancel.position = Vector2(PANEL_W - 20 - bw * 2 - 12, by)
	btn_cancel.size = Vector2(bw, 34)
	btn_cancel.pressed.connect(func(): canceled.emit())
	_panel.add_child(btn_cancel)

	var btn_ok := FormationSkin.make_button("确认解散", true)  # true = 危险色
	btn_ok.position = Vector2(PANEL_W - 20 - bw, by)
	btn_ok.size = Vector2(bw, 34)
	btn_ok.pressed.connect(func(): confirmed.emit())
	_panel.add_child(btn_ok)


## 弹出确认框。team_name / member_count 用来把提示写具体一点。
func ask(team_name: String, member_count: int) -> void:
	_msg.text = "确定要解散「%s」吗？\n队伍中的 %d 名单位会回到待命池，此操作不可撤销。" \
		% [team_name, member_count]
	visible = true
	_center()


func close() -> void:
	visible = false


## 面板居中。本控件用 FULL_RECT 铺满屏幕，面板要手动算位置。
func _center() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	var vp := get_viewport_rect().size
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.position = (vp - _panel.size) * 0.5
