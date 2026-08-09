## 本地化入口（i18n 接口）。
##
## 方案：以中文源串为 msgid。UI 文案与数据驱动名称（单位/建筑/资源名等）都经
## loc.t() 翻译；i18n/en.csv 提供英文。切换语言无需改任何数据文件，
## 未翻译词条回退原文（中文）。
##
## 实现：不依赖 Godot 的 CSV 导入系统（headless/脚本模式下不加载），
## 启动时直接解析 en.csv 构造 Translation 注册进 TranslationServer。
##
## 语言切换：L 键 / 主菜单按钮。选择写入 user:// 存档，下次启动保持。
extends Node

const CSV_PATH := "res://i18n/en.csv"
const SETTINGS_PATH := "user://loc_settings.json"

func _ready() -> void:
	_register_translations()
	# 读取上次选择的语言
	var data: Variant = _read_settings()
	if data is Dictionary and data.has("locale") and TranslationServer.get_locale() != data["locale"]:
		TranslationServer.set_locale(data["locale"])

## 解析 en.csv 注册进 TranslationServer（自包含，不依赖 .import 产物）。
func _register_translations() -> void:
	if not FileAccess.file_exists(CSV_PATH):
		return
	var text := FileAccess.get_file_as_string(CSV_PATH)
	if text.begins_with("﻿"):
		text = text.substr(1)
	var t := Translation.new()
	t.locale = "en"
	var rows := text.split("\n")
	for i in range(1, rows.size()):
		var row := rows[i].strip_edges()
		if row == "":
			continue
		var cols := _split_csv(row)
		if cols.size() >= 2 and cols[0] != "":
			t.add_message(cols[0], cols[1])
	TranslationServer.add_translation(t)

## 简易 CSV 行解析（支持引号包裹与内嵌逗号）。
static func _split_csv(row: String) -> Array:
	var out: Array = []
	var cur := ""
	var in_q := false
	var i := 0
	while i < row.length():
		var ch := row[i]
		if in_q:
			if ch == '"':
				if i + 1 < row.length() and row[i + 1] == '"':
					cur += '"'
					i += 1
				else:
					in_q = false
			else:
				cur += ch
		else:
			if ch == '"':
				in_q = true
			elif ch == ',':
				out.append(cur)
				cur = ""
			else:
				cur += ch
		i += 1
	out.append(cur)
	return out

## 翻译入口。msgid 为中文源串；未翻译时返回原文。
func t(msgid: String) -> String:
	if msgid == "":
		return ""
	return tr(msgid)

## 当前语言是否为英文。
static func is_english() -> bool:
	return TranslationServer.get_locale().begins_with("en")

## 切换语言（zh_CN <-> en），并持久化。
func toggle_language() -> void:
	var cur := TranslationServer.get_locale()
	var next := "en" if not cur.begins_with("en") else "zh_CN"
	TranslationServer.set_locale(next)
	_save_settings({"locale": next})

## 设置语言并持久化。
func set_language(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_save_settings({"locale": locale})

func _read_settings() -> Variant:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return {}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())

func _save_settings(data: Dictionary) -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
