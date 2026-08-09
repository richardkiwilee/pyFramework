## 输入绑定：动作名 ↔ 物理键 的唯一映射点（按键替换接口）。
##
## Python 原型把按键抽象为动作字符串（pyconsole/core/keys.py + pydemo/tui/keys.py），
## 场景按 event.action 分支，与物理键解耦。本文件在 Godot 中的等价物：
## 把动作名注册进 InputMap，场景只认动作名；改键只需改本文件 BINDINGS。
## 提示栏（hint_bar.gd）从本文件读键名渲染，改键后提示自动跟随。
extends Node

## 动作 → 主键列表（Key 枚举值）。第一项为主键，其余为备用键。
const DEFAULT_BINDINGS: Dictionary = {
	# 导航（复用 Godot 内置 ui_* 即可，见 InputMap 默认动作）
	# 游戏专属动作（对应 pydemo/tui/actions.py）
	"open_tech": [KEY_K],
	"open_culture": [KEY_W],
	"open_wiki": [KEY_H],
	"open_stronghold": [KEY_C],
	"open_army": [KEY_A],
	"open_recruit": [KEY_Z],
	"open_recruit_unit": [KEY_Q],
	"open_map": [KEY_M],
	"open_unit": [KEY_X],
	"open_stronghold_overview": [KEY_V],
	"open_inventory": [KEY_I],
	"end_turn": [KEY_T],
	"focus_capital": [KEY_HOME],
	"new_army": [KEY_N],
	"filter_1": [KEY_1],
	"filter_2": [KEY_2],
	"filter_3": [KEY_3],
	"filter_4": [KEY_4],
	"sell_artifact": [KEY_S],
	"unequip_artifact": [KEY_X],
	"scroll_up": [KEY_PAGEUP],
	"scroll_down": [KEY_PAGEDOWN],
	"backspace": [KEY_BACKSPACE],
	"toggle_language": [KEY_L],
}

## 当前生效绑定（默认 + 用户覆盖，user://keybindings.cfg）。
var bindings: Dictionary = {}

const BINDINGS_PATH := "user://keybindings.cfg"

## 动作 → 用户可读键名（用于提示栏）。动态从 InputMap 读取更稳妥，
## 但显示顺序与分组由本表控制。键名支持 i18n（经 Loc.tr 翻译）。
const HINTS: Array = [
	["open_tech", "hint_tech"],
	["open_culture", "hint_culture"],
	["open_wiki", "hint_wiki"],
	["open_stronghold", "hint_stronghold"],
	["open_army", "hint_army"],
	["open_recruit", "hint_recruit"],
	["open_unit", "hint_unit"],
	["open_stronghold_overview", "hint_stronghold_overview"],
	["open_inventory", "hint_inventory"],
	["open_map", "hint_map"],
	["end_turn", "hint_end_turn"],
	["focus_capital", "hint_focus_capital"],
]

## 把动作注册进 InputMap（幂等）。
func setup() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		# 清掉已有绑定再写入（重跑时保持幂等）
		for ev in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, ev)
		for k in bindings[action]:
			var ie := InputEventKey.new()
			ie.physical_keycode = k
			InputMap.action_add_event(action, ie)

## 改键：更新绑定表 + InputMap + 持久化。返回是否成功。
func rebind(action: String, key: Key) -> bool:
	if not bindings.has(action):
		return false
	bindings[action] = [key]
	save_bindings()
	setup()
	return true

func save_bindings() -> void:
	var cf := ConfigFile.new()
	for action in bindings:
		cf.set_value("bindings", action, bindings[action])
	cf.save(BINDINGS_PATH)

func load_bindings() -> void:
	var cf := ConfigFile.new()
	if cf.load(BINDINGS_PATH) != OK:
		return
	for action in bindings:
		var v: Variant = cf.get_value("bindings", action, null)
		if v is Array and not (v as Array).is_empty():
			bindings[action] = v

## 动作当前主键的可读名（如 "K" / "PageUp"）。改键后提示栏自动跟随。
static func action_key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var evs := InputMap.action_get_events(action)
	for ev in evs:
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
	return "?"

## 动作当前是否被按下。
static func is_action_pressed(action: String) -> bool:
	return Input.is_action_pressed(action)

func _ready() -> void:
	bindings = DEFAULT_BINDINGS.duplicate(true)
	load_bindings()
	setup()
