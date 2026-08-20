## =====================================================================
## ResourceManager — 统一的资源查找中心（带优雅回退）
## =====================================================================
## 所有美术资源统一放在 res://assets/ 下。调用方按"逻辑名"请求资源：
##   存在对应文件（svg/png/...）→ 加载并缓存；
##   找不到                → 返回 null，由调用方自行用 Godot 原生控件兜底。
## 这样 UI 在没有美术资源时也能照常运行。
##
## ---- Python 开发者速查 ----
## class_name ResourceManager → 注册一个全局类型名，别处可当作类型使用
## extends RefCounted         → 继承引用计数基类（类似 Python 的对象，靠 GC/引用计数回收）
## const X := "..."          → 常量（:= 是类型推导赋值，等价于 const X: String = "..."）
## static var / static func   → 静态成员/静态方法（类级，不属于实例），和 Python 的 @staticmethod 类似
## load(path)                 → 加载 res:// 路径的资源（引擎内建，带缓存）
## ResourceLoader.exists(p)  → 检查资源路径是否真实存在
## res://                     → 项目根目录的协议前缀（相当于 Python 项目根的相对路径）
## =====================================================================
class_name ResourceManager
extends RefCounted

## 资源所在目录（res:// 是项目根）。
const ASSET_DIR := "res://assets"
## 按顺序尝试的扩展名——找到第一个存在的就用。
const EXTENSIONS := ["svg", "png", "jpg", "jpeg", "webp"]

## 静态缓存字典：逻辑名 → 已加载纹理。避免重复加载同一张图。
## Python 里没有直接的"static var"，这里相当于挂在类上的共享字典。
static var _cache: Dictionary = {}

## 返回该逻辑名对应的第一个命中文件路径；找不到返回空串。
## 遍历扩展名列表，逐个用 ResourceLoader.exists 探测。
static func get_asset_path(asset_name: String) -> String:
	for ext in EXTENSIONS:
		# 字符串模板："%s/%s.%s" % [a, b, c] 依次替换占位符（和 Python 一致）。
		var path := "%s/%s.%s" % [ASSET_DIR, asset_name, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

## 是否存在任何美术文件（封装 get_asset_path 的判断）。
static func has_asset(asset_name: String) -> bool:
	return get_asset_path(asset_name) != ""

## 加载（并缓存）纹理。缺失返回 null，由调用方回退到原生控件。
## 返回类型 Texture2D 是 Godot 的 2D 纹理基类。
static func load_texture(asset_name: String) -> Texture2D:
	# 命中缓存直接返回，避免重复 load。
	if _cache.has(asset_name):
		return _cache[asset_name]
	var path := get_asset_path(asset_name)
	if path.is_empty():
		return null
	# load() 是引擎内建函数，返回 Resource；这里需要确认它是纹理。
	var res := load(path)
	if res is Texture2D:
		_cache[asset_name] = res
		return res
	return null
