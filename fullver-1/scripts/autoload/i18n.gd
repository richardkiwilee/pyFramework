extends Node
## =============================================================================
## I18n — 自动加载(Autoload)单例，多语言支持
## =============================================================================
## 作用：把 UI 文案集中到 data/i18n/{语言}.json，运行时按当前语言取文案。
##       文案 key 采用点分扁平命名（如 "ui.world.end_turn"），与数据 ID 解耦。
##
## 设计约定（docs/00-design.md §14）：
##   - UI 文案（按钮/标题/提示）全部走 I18n.t("key")
##   - 游戏数据实体的显示名（角色名/技能名等）保留数据内联 name_zh 字段，
##     不做全量 key 化（222 个技能全 key 化收益低、维护重）
##
## 类比 Python：
##   相当于 gettext 的简化版：translations = {"ui.ok": "确定"}，
##   t("ui.ok") 查表返回 "确定"；查不到就原样返回 key（方便发现漏翻译）。
##
## ⚠️ 命名坑：Godot 原生类 Object 自带 tr(StringName) 翻译方法，
##   自己再定义 tr() 会触发"覆盖原生方法"警告（本环境警告视为错误，直接解析失败）。
##   因此本类方法命名为 t()。
##
## Godot 概念说明 — Setting（zfoo 框架）：
##   Setting 是 zfoo 的键值配置系统，持久化到 user://setting.config。
##   ⚠️ set_* 之后必须显式调用 Setting.save() 才会落盘（zfoo 约定）。
## =============================================================================

## 当前语言发生切换时发出，UI 监听后重建文案
signal language_changed(lang: String)

## 当前语言（"zh" / "en"）
var _lang: String = "zh"

## 已加载的文案表：key → 文案字符串（类比 Python dict[str, str]）
var _strings: Dictionary = {}


func _ready() -> void:
	# 启动时从 zfoo 配置读上次选择的语言，默认中文
	# Setting.get_string(key, default) — 键不存在时返回 default
	_lang = Setting.get_string("language", "zh")
	_load()


## ---------------------------------------------------------------------------
## t() — 翻译取词（带占位符替换）
## ---------------------------------------------------------------------------
## 占位符用 {} 风格（与 zfoo Log 的模板风格一致），按 args 顺序替换
## 例：t("ui.battle.round", ["3"]) 且 zh.json 里 "ui.battle.round": "第{}回合" → "第3回合"
## 查不到 key 时原样返回 key（宁可暴露问题也不静默吞掉）
## ---------------------------------------------------------------------------
func t(key: String, args: Array = []) -> String:
	var s: String = str(_strings.get(key, key))
	# 依次用 args 替换每个 {} 占位符
	# find() 返回子串位置，找不到返回 -1（类似 Python 的 str.find）
	for arg in args:
		var pos := s.find("{}")
		if pos == -1:
			break
		s = s.substr(0, pos) + str(arg) + s.substr(pos + 2)
	return s


## 返回当前语言代码
func language() -> String:
	return _lang


## 切换语言。语言文件不存在时拒绝切换并返回 false。
func set_language(lang: String) -> bool:
	var path := "res://data/i18n/%s.json" % lang
	if not FileAccess.file_exists(path):
		push_error("[I18n] 语言文件不存在: %s" % path)
		return false
	_lang = lang
	_load()
	# ⚠️ zfoo 约定：set 后必须显式 save() 才落盘
	Setting.set_string("language", lang)
	Setting.save()
	language_changed.emit(lang)
	return true


## ---------------------------------------------------------------------------
## _load() — 加载当前语言的文案表
## ---------------------------------------------------------------------------
## Godot 读 JSON 与 Python 的区别（同 DataManager._parse_json 的说明）：
##   Python: json.load(f) 直接返回结果
##   Godot:  JSON.new().parse(text) 返回错误码，结果用 .get_data() 取
## ---------------------------------------------------------------------------
func _load() -> void:
	var path := "res://data/i18n/%s.json" % _lang
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[I18n] 无法打开语言文件: %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("[I18n] 语言文件解析失败: %s" % path)
		return
	# JSON 顶层是 {key: 文案} 的扁平字典
	var data: Variant = json.get_data()
	_strings = data if data is Dictionary else {}
