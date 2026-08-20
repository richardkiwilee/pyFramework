## =====================================================================
## GameState — 全局单例（Autoload）
## =====================================================================
## 职责：跨场景存活，保存"当前回合"与"日志历史"。
## 顶部栏的"回合"文本、日志面板、各场景切换都依赖这里的状态与信号。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Node        → 相当于 class GameState(Node)，继承 Godot 的 Node 基类
##                      （Node 是所有场景节点的根基类，无 UI）
## signal xxx(args)    → 声明一个信号（类似 C# 的 event / Python 的观察者钩子）
##                      用 .connect(callable) 订阅，.emit(...) 触发
## var x: int = 1      → 类型注解（GDScript 会强制检查，比 Python 的 hint 更严格）
## Array[String]       → 元素类型受限的数组（类似 list[str]，但运行时强制）
## func _ready()       → 生命周期：节点进入场景树时自动调用一次（类似 __init__）
## pass                → 空语句占位（和 Python 一样）
##
## Autoload（自动加载）：在 project.godot 的 [autoload] 段注册后，这个脚本会被
## 引擎实例化成全局单例，任意脚本都能直接用名字 GameState 访问，无需 import。
## 它在游戏启动时创建、退出时销毁，切换场景时不会丢失状态。
## =====================================================================
extends Node

## 回合变化信号：next_turn() 里 emit，订阅者（如顶部栏文本）据此刷新。
signal turn_changed(turn: int)
## 日志新增信号：每加一条日志就 emit，订阅者（LogPanel）据此追加一行。
signal log_added(entry: String)

## 当前回合数。整个游戏共享这一份（因为是单例）。
var current_turn: int = 1
## 日志历史。Array[String] 表示元素只能是字符串（GDScript 的泛型数组）。
var log_entries: Array[String] = []

func _ready() -> void:
	# 节点就绪时记一条开局日志。
	_add_log("游戏开始")

## 结束回合：回合 +1，写日志，再广播 turn_changed。
## 注意 GDScript 的字符串格式化用 % 运算符（和 Python 旧式 % 格式化一致）。
func next_turn() -> void:
	current_turn += 1
	_add_log("进入第 %d 回合" % current_turn)
	# emit 相当于"触发事件"，所有 connect 过的回调都会被调用。
	turn_changed.emit(current_turn)

## 外部追加一条日志（公开接口，转发到内部 _add_log）。
func add_log(msg: String) -> void:
	_add_log(msg)

## 内部追加日志：拼上回合戳，存进数组，再广播 log_added。
func _add_log(msg: String) -> void:
	# % [current_turn, msg] → 依次填入 %d 和 %s 的占位符。
	var stamp := "[回合%d] %s" % [current_turn, msg]
	log_entries.append(stamp)
	log_added.emit(stamp)
