## 场景与窗口管理（Godot 最佳实践版）。
##
## 两类导航，各司其职：
##   - 主界面切换（主菜单 ↔ 游戏）：change_scene(path) 替换根下唯一主场景——
##     旧场景真正销毁，不再有"菜单残留"问题。
##   - 子界面：open_window(win) 弹出独立 Window（模态、独占焦点、可拖动/关闭），
##     close_window(value) 关闭并把回值交给打开者 on_return。
##
## 每个子界面是独立 .tscn 场景，可在编辑器里单独 F6 调试。
extends Node

## 当前主场景节点（根下唯一）。
var main_scene: Node = null

## 当前打开的子窗口栈（Window 实例）。
var window_stack: Array = []

## 切换主场景：销毁旧主场景，实例化新场景并加入树。
## 必须先关闭全部子窗口——否则模态 Window 残留盖在新场景上，
## 吞掉所有鼠标事件（"返回主菜单后鼠标失效"的根因）。
func change_scene(scene: Node) -> void:
	close_all_windows()
	if main_scene != null:
		main_scene.queue_free()
		main_scene = null
	add_child(scene)
	main_scene = scene
	if scene.has_method("enter_scene"):
		scene.enter_scene()

## 弹出子窗口。win 须为 Window（或其子类）。params 经 enter_window 交付。
func open_window(win: Window, params: Variant = null) -> void:
	if win == null:
		return
	window_stack.append(win)
	add_child(win)
	win.transient = true          # 依附主窗口
	win.exclusive = true          # 模态：主窗口不可交互直到关闭
	win.close_requested.connect(func(): close_window(null))
	if win.has_method("enter_window"):
		win.enter_window(params)
	win.grab_focus()

## 关闭栈顶窗口，携带回值交付给打开者 on_return（若有）。
func close_window(value: Variant = null) -> void:
	if window_stack.is_empty():
		return
	var win: Window = window_stack.pop_back()
	if win.has_method("exit_window"):
		win.exit_window()
	win.queue_free()
	# 打开者通常是主场景；新栈顶若有 return_window 也交付
	var next: Variant = window_stack.back() if not window_stack.is_empty() else null
	if next != null and next.has_method("return_window"):
		next.return_window(value)
	elif main_scene != null and main_scene.has_method("return_window"):
		main_scene.return_window(value)

## 关闭全部子窗口。
func close_all_windows() -> void:
	while not window_stack.is_empty():
		close_window(null)

## 栈顶窗口（无则 null）。
func top_window() -> Variant:
	return window_stack.back() if not window_stack.is_empty() else null
