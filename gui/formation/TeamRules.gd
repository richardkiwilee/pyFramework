## =====================================================================
## TeamRules — 规模 / 领导力 / AP-PP 的推导规则（唯一需要手工调优的文件）
## =====================================================================
## 「规模」和「领导力」是 readme 新引入的概念，参考项目里都没有，所以必须自己定义：
##   规模 size       —— 单位属性。不管规模多大，在九宫格里**永远只占 1 格**。
##   领导力 leadership —— 只有队长的领导力有意义。
##   合法条件         —— sum(全队规模) <= 队长领导力。
##
## 所有数值都写在 res://data/formation_rules.json 里，改数值不用动这个文件。
## 这个文件只负责「怎么查」，不负责「查出来是多少」。
##
## ---- 实际查过数据后发现的四个坑（本文件的存在意义就是挡住它们）----
## 1. 70 个角色里有 17 个的 class_zh 在 classes.json 里根本不存在
##    （精灵弓箭手、狼人、天使剑兵、十字军、雪原游侠…这些兽人/精灵/天使种族）。
##    所以**不能**用 class_zh 去 join classes.json 当主要手段，那会丢掉 24% 的角色。
##    改用角色自带的 character.classes[0]（内嵌字段，覆盖 69/70）。
## 2. 64 个职业里有 39 个**完全没有 base_ap / base_pp 这两个键**（是键缺失，不是值为 null）。
##    所以必须 .get("base_ap", 默认值)，不能 ["base_ap"]，否则直接报错。
## 3. classes.json 里每个职业的 base_stats 都是空字典 {}，属性只能从 characters.json 取。
## 4. 角色 hermann 没有 base_stats；有 1 个角色的 classes[] 是空数组。取值一律判空。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## class_name TeamRules   → 注册全局类型名，别处直接 TeamRules.size_for(...) 调用
## extends RefCounted     → 引用计数基类（这里只用静态方法，不会真的实例化）
## static var / static func → 类级成员/方法，等价于 Python 的类属性 / @staticmethod
## Dictionary             → 和 Python 的 dict 几乎一样；取值用 d.get(key, default)
## Array                  → 和 Python 的 list 一样
## Vector2i(a, b)         → 两个整数组成的值对象，这里拿来一次返回 AP 和 PP 两个值
##                          （GDScript 不能像 Python 那样 return a, b 返回元组）
## String.to_lower()      → 转小写，等价于 Python 的 str.lower()
## String.contains(s)     → 子串判断，等价于 Python 的 `s in text`
## FileAccess             → 文件读取 API（见 _load_rules）
## JSON.parse_string(txt) → 解析 JSON 字符串，失败返回 null（等价于 json.loads）
## typeof(x) == TYPE_DICT → 类型判断，等价于 Python 的 isinstance(x, dict)
## =====================================================================
class_name TeamRules
extends RefCounted

## 规则表文件路径。想整套换规则，换这个 json 即可。
const RULES_PATH := "res://data/formation_rules.json"

## 规则表缓存。静态变量 = 挂在类上的共享数据，第一次用到时才加载（懒加载）。
static var _rules: Dictionary = {}
## 是否已经尝试过加载（避免文件缺失时每次调用都重复读盘 + 重复报错）。
static var _loaded: bool = false


## 读取规则表。内部函数，其余方法用到时会自动调用。
static func _load_rules() -> void:
	if _loaded:
		return
	_loaded = true  # 先置位：即使下面失败也不再重试
	if not FileAccess.file_exists(RULES_PATH):
		push_error("[TeamRules] 找不到规则表：%s（将全部使用内置兜底值）" % RULES_PATH)
		return
	var txt := FileAccess.get_file_as_string(RULES_PATH)
	var parsed = JSON.parse_string(txt)
	# JSON 解析失败会返回 null；顶层也必须是个字典才算合法。
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("[TeamRules] 规则表解析失败：%s" % RULES_PATH)
		return
	_rules = parsed


## 取规则表里的某一段（比如 "size" / "leadership"）。缺失时返回空字典。
static func _section(key: String) -> Dictionary:
	_load_rules()
	var v = _rules.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}


# =====================================================================
#  职业信息提取 —— 统一从 character.classes[0] 拿，绕开坑 1
# =====================================================================

## 取角色的「基础职业」内嵌数据块。
## characters.json 里每个角色都自带一个 classes 数组，[0] 是基础职业、[1] 是转职后。
## 这份内嵌数据覆盖 69/70 个角色，比 join classes.json（只覆盖 53/70）可靠得多。
## 找不到时返回空字典 {}，调用方用 .get() 取值自然会落到默认值上。
static func base_class_of(char_data: Dictionary) -> Dictionary:
	var arr = char_data.get("classes", [])
	# 必须同时判「是数组」和「非空」——坑 4：确实有角色的 classes[] 是空数组。
	if typeof(arr) != TYPE_ARRAY or arr.is_empty():
		return {}
	var first = arr[0]
	return first if typeof(first) == TYPE_DICTIONARY else {}


## 取用于关键字匹配的职业类型串，已转小写。
## class_type 长这样："Sword / Shield / Infantry"、"Bow/ Infantry /Archer"、"Ax / Shield / Cavalry"
## —— 自由文本，空格还不规范，所以后面一律用**子串匹配**而不是按 "/" 分词。
## 顺带把 movement_type（Infantryman / Infantry / Cavalry / Flying）也拼进去，
## 这样 class_type 缺失时还能靠移动类型兜一层。
static func class_keywords_of(char_data: Dictionary) -> String:
	var cls := base_class_of(char_data)
	var ct := str(cls.get("class_type", ""))
	var mt := str(cls.get("movement_type", ""))
	# 再补上角色顶层的 class_zh/class_en，多一条匹配线索（比如 "Lord" 能命中 lord）。
	var en := str(char_data.get("class_en", ""))
	return ("%s %s %s" % [ct, mt, en]).to_lower()


## 在一张 [{keyword, value}, ...] 规则表里按顺序做子串匹配，返回第一个命中的 value。
## 都不命中就返回 fallback。这是规模和领导力共用的匹配逻辑。
static func _match_keyword(table: Array, haystack: String, fallback: int) -> int:
	for entry in table:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kw := str(entry.get("keyword", "")).to_lower()
		# 空关键字会匹配一切，跳过，防止规则表写错时全表命中第一行。
		if kw.is_empty():
			continue
		if haystack.contains(kw):
			return int(entry.get("value", fallback))
	return fallback


# =====================================================================
#  对外接口
# =====================================================================

## 规模：单位占多少「队伍容量」。注意它**不影响占几格**，永远只占 1 格。
## 校准（与项目主人给的两个基准一致）：
##   剑士 class_type = "Sword / Infantry"      → 不命中任何关键字 → 默认 20 ✅
##   射手 class_type = "Bow/ Infantry /Archer" → 命中 archer      → 15 ✅
static func size_for(char_data: Dictionary) -> int:
	var sec := _section("size")
	var fallback := int(sec.get("default", 20))
	var table = sec.get("by_class_keyword", [])
	if typeof(table) != TYPE_ARRAY:
		return fallback
	return _match_keyword(table, class_keywords_of(char_data), fallback)


## 领导力：队长能容纳的全队规模上限。
## 公式 = 职业基础值（关键字匹配，不命中用 base_default）+ 每级增量 * 等级。
## 随等级成长是刻意的：readme 要求成员行显示等级，等级就该有实际作用。
static func leadership_for(char_data: Dictionary, level: int) -> int:
	var sec := _section("leadership")
	var base := int(sec.get("base_default", 60))
	var table = sec.get("base_by_class_keyword", [])
	if typeof(table) == TYPE_ARRAY:
		base = _match_keyword(table, class_keywords_of(char_data), base)
	var per_level := int(sec.get("per_level", 2))
	return base + per_level * level


## AP / PP：返回 Vector2i(ap, pp)。
## class_data 是 classes.json 里查到的职业条目，查不到时传空字典 {}。
##
## 优先级：
##   1. classes.json 里有 base_ap → 直接用（只有 25/64 个职业有）
##   2. 没有就看转职状态：promotes_from 非空 = 转职职业 → 2/2，基础职业 → 1/1
##      这不是拍脑袋：25 个有值的职业里，22 个转职职业正好都是 2/2，
##      3 个基础职业正好都是 1/1，相关性是完美的。
##   3. 连职业都查不到（坑 1，17/70 个角色）→ 用规则表里的 fallback
static func ap_pp_for(class_data: Dictionary) -> Vector2i:
	_load_rules()
	var fb = _rules.get("ap_pp_fallback", {})
	# 写成 `var x: int = ...` 而不是 `var x := ...`：fb 是 Variant，
	# 三元表达式里 GDScript 推不出类型，用 := 会解析失败。
	var fb_ap: int = int(fb.get("ap", 1)) if typeof(fb) == TYPE_DICTIONARY else 1
	var fb_pp: int = int(fb.get("pp", 1)) if typeof(fb) == TYPE_DICTIONARY else 1

	# 职业没查到 → 兜底
	if class_data.is_empty():
		return Vector2i(fb_ap, fb_pp)

	# 坑 2：39/64 个职业连 base_ap 这个键都没有，所以必须用 .get() 而不是 []。
	var ap_raw = class_data.get("base_ap", null)
	if ap_raw != null:
		return Vector2i(int(ap_raw), int(class_data.get("base_pp", fb_pp)))

	# 没有 base_ap → 按转职状态推导
	if class_data.get("promotes_from", null) != null:
		var pr = _rules.get("ap_pp_promoted", {})
		var pr_ap: int = int(pr.get("ap", 2)) if typeof(pr) == TYPE_DICTIONARY else 2
		var pr_pp: int = int(pr.get("pp", 2)) if typeof(pr) == TYPE_DICTIONARY else 2
		return Vector2i(pr_ap, pr_pp)
	return Vector2i(fb_ap, fb_pp)


## 开局花名册参数（单位数量、等级范围、初始队伍人数）。
## 返回原始字典，由 FormationData 决定怎么用。
static func roster_config() -> Dictionary:
	return _section("roster")
