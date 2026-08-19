extends Node
## =============================================================================
## DataManager — 自动加载(Autoload)单例，数据层
## =============================================================================
## 作用：在游戏启动时，一次性从 JSON 数据文件中加载所有静态数据到内存中，
##       然后提供 O(1) 的 ID 查找接口，供其他脚本随时查询。
##
## 移植自 demo-1 的 scripts/autoload/data_manager.gd（ADR-0003 的既定方案），
## 扩展了本项目的四张新表：
##   + data/world/map.json      — 据点图（城市 + 路线）
##   + data/factions.json       — 势力与 AI 策略挂载
##   + data/resources.json      — 资源与经济参数
##   + data/diplomacy.json      — 外交参数
## 并新增 validate_all_data() / validate_effect_coverage() 数据校验。
##
## 类比 Python：
##   就像用一个全局的 dict 来存储所有游戏配置，key 是 ID，value 是数据字典。
##   `characters["lord_01"]` 就能取出该角色的全部属性。
##
## Godot 概念说明 — Autoload（自动加载）：
##   Autoload 是 Godot 的一种特殊节点。在项目设置中注册后，引擎启动时会
##   自动创建该节点的唯一实例，并让它在所有场景切换中保持存活（不会被销毁）。
##   任何脚本都可以通过节点名直接访问它，比如 DataManager.get_character("id")。
##   这是 Godot 实现"全局单例"的标准方式，相当于 Python 中的模块级单例。
##
## Godot 概念说明 — Dictionary（字典）：
##   GDScript 的 Dictionary 和 Python 的 dict 几乎一模一样：
##   - 定义：var d = {"key": "value"}
##   - 取值：d["key"] 或 d.get("key", default)
##   - 遍历：for key in d: ...
##   区别是 GDScript 的 Dictionary 是引用类型，赋值是传引用不是拷贝。
## =============================================================================

# ------------------------------------------------------------------ 数据缓存
# 这些 Dictionary 就是"数据库表"，以 ID 为 key 存储所有记录。
# 例如 characters["alain"] = { "name_zh": "亚连", "class_zh": "领主", ... }
var characters: Dictionary = {}         # id → 角色数据
var classes: Dictionary = {}            # id → 职业数据
var equipment: Dictionary = {}          # id → 装备数据
var skills: Dictionary = {}             # id → 技能数据
var skill_conditions: Dictionary = {}   # id → 技能条件数据（如"HP<50%时触发"）
var items: Dictionary = {}              # id → 道具数据
var factions: Dictionary = {}           # id → 势力数据
var factions_config: Dictionary = {}    # factions.json 完整内容（含开局参数）
var map_data: Dictionary = {}           # {map_width, map_height, cities, routes}
var resources: Dictionary = {}          # {resources: Array, economy: Dictionary}
var diplomacy_config: Dictionary = {}   # 外交参数（阈值/朝贡/贸易/条约）

# ------------------------------------------------------------------ 反向索引
# 原始数据以 ID 为 key，但 UI 经常需要"查某个职业有哪些角色"。
# 这些索引在 _build_indices() 中构建，避免每次都遍历全表。
# 类比 Python：相当于 defaultdict(list)，按类别名分组。
var characters_by_class: Dictionary = {}  # 职业中文名 → [角色ID列表]
var skills_by_class: Dictionary = {}      # 职业中文名 → [技能ID列表]
var equipment_by_subtype: Dictionary = {} # 子类型(sword/axe/...) → [装备ID列表]
var city_by_id: Dictionary = {}           # 城市ID → 城市数据（大地图 O(1) 查询）

# 是否已经加载过数据（防止重复加载）
var _loaded: bool = false


## ---------------------------------------------------------------------------
## _ready() — Godot 生命周期回调
## ---------------------------------------------------------------------------
## 当节点进入场景树时自动调用。Autoload 的 _ready() 在游戏启动时执行一次。
## 这里做两件事：加载全部数据 + 跑一遍数据校验（结果打到控制台）。
## ---------------------------------------------------------------------------
func _ready() -> void:
	load_all_data()
	# 启动时校验数据：结构错误用 Log.error（会触发 gdf.events.log_error，
	# 测试环境下会导致 FAIL——数据坏了测试必须红），覆盖告警用 Log.info 打印
	var errors: Array[String] = validate_all_data()
	for e in errors:
		Log.error("[DataManager] 数据校验错误: {}", e)
	var warnings: Array[String] = validate_effect_coverage()
	for w in warnings:
		Log.info("[DataManager] 效果覆盖告警: {}", w)
	var translation: Array[String] = validate_class_translation()
	for w in translation:
		Log.info("[DataManager] 翻译不一致告警: {}", w)


## ---------------------------------------------------------------------------
## load_all_data() — 加载全部游戏数据
## ---------------------------------------------------------------------------
## 依次调用各 _load_xxx() 方法读取 JSON 文件，然后构建反向索引。
## 设计为幂等操作：如果已加载则直接返回，防止重复加载。
## ---------------------------------------------------------------------------
func load_all_data() -> void:
	if _loaded:
		return
	_loaded = true

	# 依次加载每种 JSON 数据文件
	_load_characters()   # 角色
	_load_classes()      # 职业
	_load_equipment()    # 装备
	_load_skills()       # 技能（含技能条件）
	_load_items()        # 道具
	_load_world_map()    # 大地图（据点图）
	_load_factions()     # 势力
	_load_resources()    # 资源与经济参数
	_load_diplomacy()    # 外交参数

	# 构建反向索引以加速后续查询
	_build_indices()

	# 打印加载统计到控制台，方便调试
	# 注意 zfoo Log 的 {} 占位符是变参（不是数组），与 Python 的 % 不同
	Log.info("[DataManager] Loaded: {} chars, {} classes, {} equipment, {} skills, {} items, {} factions, {} cities",
		characters.size(), classes.size(), equipment.size(), skills.size(), items.size(),
		factions.size(), city_by_id.size())


# ==================================================================
#  数据加载器 (Loaders)
# ==================================================================
# 每个 _load_xxx() 方法的流程完全一样：
#   1. 调用 _parse_json("res://data/xxx.json") 解析 JSON 文件
#   2. 取出数组字段（如 data.get("characters", [])）
#   3. 遍历数组，以 rec.id 为 key 存入对应的 Dictionary
#
# GDScript 路径说明：
#   "res://" 是 Godot 的资源路径前缀，指向项目的根目录。
#   类似于 Python 中 __file__ 所在的项目根目录。
# ==================================================================

func _load_characters() -> void:
	var data = _parse_json("res://data/characters.json")
	if data == null:
		return
	# characters.json 的顶层结构：{"characters": [{...}, {...}, ...]}
	for rec in data.get("characters", []):
		characters[rec.id] = rec


func _load_classes() -> void:
	var data = _parse_json("res://data/classes.json")
	if data == null:
		return
	for rec in data.get("classes", []):
		classes[rec.id] = rec


func _load_equipment() -> void:
	var data = _parse_json("res://data/equipment.json")
	if data == null:
		return
	for rec in data.get("equipment", []):
		equipment[rec.id] = rec


func _load_skills() -> void:
	var data = _parse_json("res://data/skills.json")
	if data == null:
		return
	# skills.json 包含两个数组：skills（技能定义）和 skill_conditions（触发条件）
	for rec in data.get("skills", []):
		skills[rec.id] = rec
	for rec in data.get("skill_conditions", []):
		skill_conditions[rec.id] = rec


func _load_items() -> void:
	var data = _parse_json("res://data/items.json")
	if data == null:
		return
	for rec in data.get("items", []):
		items[rec.id] = rec


func _load_world_map() -> void:
	var data = _parse_json("res://data/world/map.json")
	if data == null:
		return
	map_data = data
	# 城市 id 索引（大地图查询 O(1)）
	for c in data.get("cities", []):
		city_by_id[c.id] = c


func _load_factions() -> void:
	var data = _parse_json("res://data/factions.json")
	if data == null:
		return
	factions_config = data
	for rec in data.get("factions", []):
		factions[rec.id] = rec


func _load_resources() -> void:
	var data = _parse_json("res://data/resources.json")
	if data == null:
		return
	resources = data


func _load_diplomacy() -> void:
	var data = _parse_json("res://data/diplomacy.json")
	if data == null:
		return
	diplomacy_config = data


# ==================================================================
#  反向索引构建 (Index Building)
# ==================================================================

func _build_indices() -> void:
	# --- 角色按职业索引 ---
	for char_id in characters:
		var c = characters[char_id]
		var cls = c.get("class_zh", "")          # 职业中文名，如"领主"、"法师"
		if not characters_by_class.has(cls):     # .has() 等价于 Python 的 `key in dict`
			characters_by_class[cls] = []
		characters_by_class[cls].append(char_id)

	# --- 装备按子类型索引 ---
	for eq_id in equipment:
		var eq = equipment[eq_id]
		var st = eq.get("subtype", "other")
		if not equipment_by_subtype.has(st):
			equipment_by_subtype[st] = []
		equipment_by_subtype[st].append(eq_id)

	# --- 技能按职业索引 ---
	for sk_id in skills:
		var sk = skills[sk_id]
		var cls = sk.get("class_zh", "")
		if cls != "":
			if not skills_by_class.has(cls):
				skills_by_class[cls] = []
			skills_by_class[cls].append(sk_id)


# ==================================================================
#  公开查询接口 (Public Lookups)
# ==================================================================
# 以下方法都是 O(1) 的字典查找，非常高效。
# 使用 .get(key, default) 确保 key 不存在时返回空字典/数组而不是报错。
# ⚠️ Godot 坑：key 存在但值为 null 时 .get() 返回 null 而非默认值，
#    调用方需要时自行判空（demo-1 踩过）。
# ==================================================================

func get_character(char_id: String) -> Dictionary:
	"""根据角色ID获取角色完整数据。找不到返回空字典 {}"""
	return characters.get(char_id, {})


func get_class_data(class_id: String) -> Dictionary:
	"""根据职业ID获取职业定义数据"""
	return classes.get(class_id, {})


func get_equipment(eq_id: String) -> Dictionary:
	"""根据装备ID获取装备完整数据（名称、属性加成、稀有度等）"""
	return equipment.get(eq_id, {})


func get_skill(sk_id: String) -> Dictionary:
	"""根据技能ID获取技能定义数据（名称、消耗、效果等）"""
	return skills.get(sk_id, {})


func get_condition(cond_id: String) -> Dictionary:
	"""根据条件ID获取技能触发条件数据"""
	return skill_conditions.get(cond_id, {})


func get_skill_id_by_name(name_en: String) -> String:
	"""按英文名反查技能 ID（编成界面的技能下拉池用；找不到返回空串）"""
	for sk_id in skills:
		var sk: Dictionary = skills[sk_id]
		if String(sk.get("name_en", "")).to_lower() == name_en.to_lower():
			return sk_id
	return ""


func get_characters_by_class_name(cls_name: String) -> Array:
	"""根据职业中文名获取该职业所有角色ID列表"""
	return characters_by_class.get(cls_name, [])


func get_skills_by_class_name(cls_name: String) -> Array:
	"""根据职业中文名获取该职业技能ID列表"""
	return skills_by_class.get(cls_name, [])


func get_equipment_by_subtype(subtype: String) -> Array:
	"""根据装备子类型(sword/axe/bow/...)获取装备ID列表"""
	return equipment_by_subtype.get(subtype, [])


func get_all_character_ids() -> Array:
	"""获取全部角色ID列表。GDScript 中 .keys() 返回的是 Array，不是 Python 的 dict_keys"""
	return characters.keys()


func get_all_equipment_ids() -> Array:
	"""获取全部装备ID列表"""
	return equipment.keys()


func get_all_skill_ids() -> Array:
	"""获取全部技能ID列表"""
	return skills.keys()


func get_all_condition_ids() -> Array:
	"""获取全部技能条件ID列表"""
	return skill_conditions.keys()


# ---------------- 本项目扩展的查询接口 ----------------

func get_faction(faction_id: String) -> Dictionary:
	"""根据势力ID获取势力数据（含 ai_strategy 路径）。找不到返回空字典"""
	return factions.get(faction_id, {})


func get_all_faction_ids() -> Array:
	"""获取全部势力ID列表"""
	return factions.keys()


func get_player_faction_id() -> String:
	"""获取玩家势力ID（factions 中 is_player=true 的那一方）。找不到返回空串"""
	for fid in factions:
		if factions[fid].get("is_player", false):
			return fid
	return ""


func get_map_data() -> Dictionary:
	"""获取大地图原始数据：{map_width, map_height, cities, routes}"""
	return map_data


func get_city(city_id: String) -> Dictionary:
	"""根据城市ID获取城市数据。找不到返回空字典"""
	return city_by_id.get(city_id, {})


func get_map_cities() -> Array:
	"""获取全部城市数据列表（数组，非字典）"""
	return map_data.get("cities", [])


func get_resource_defs() -> Array:
	"""获取资源定义列表：[{id, name_zh, icon, production_per_city_level}, ...]"""
	return resources.get("resources", [])


func get_economy_config() -> Dictionary:
	"""获取经济参数：军费/升级/征兵费用等"""
	return resources.get("economy", {})


func get_diplomacy_config() -> Dictionary:
	"""获取外交参数：阈值/朝贡/贸易/条约等"""
	return diplomacy_config


func get_factions_config() -> Dictionary:
	"""获取 factions.json 完整内容（含 starting_resources / army_team_size / army_move_points）"""
	return factions_config


func get_class_id_by_character(char_data: Dictionary) -> String:
	"""按角色数据反查职业 ID（角色表只有 class_zh/class_en，没有 class_id）。
	优先按 class_en 匹配职业表 name_en（demo-1 数据中英文名一致），
	退而按 class_zh 匹配 name_zh。找不到返回空串。"""
	var en: String = char_data.get("class_en", "")
	var zh: String = char_data.get("class_zh", "")
	for cls_id in classes:
		var cls: Dictionary = classes[cls_id]
		if en != "" and cls.get("name_en", "") == en:
			return cls_id
	for cls_id in classes:
		var cls: Dictionary = classes[cls_id]
		if zh != "" and cls.get("name_zh", "") == zh:
			return cls_id
	return ""


## ---------------------------------------------------------------------------
## get_random_characters() — 随机获取角色
## ---------------------------------------------------------------------------
## 参数：
##   count       — 需要返回的角色数量
##   exclude_ids — 要排除的角色ID列表（避免重复选取已编入队伍的角色）
## 流程：遍历角色ID → 排除 → 打乱（.shuffle() 原地操作，类似 random.shuffle）
##       → 取前 count 个（.slice() 类似 Python 的 list[0:count]）
## ---------------------------------------------------------------------------
func get_random_characters(count: int, exclude_ids: Array = []) -> Array:
	var pool: Array = []
	for cid in characters:
		if cid not in exclude_ids:
			pool.append(cid)
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))


## ---------------------------------------------------------------------------
## get_random_equipment_for_slot() — 获取指定类型的随机装备
## ---------------------------------------------------------------------------
## 用于给新征募的军团随机配装，增加变化性。
## ---------------------------------------------------------------------------
func get_random_equipment_for_slot(subtype: String, count: int = 1) -> Array:
	var pool: Array = []
	for eq_id in equipment:
		var eq = equipment[eq_id]
		if eq.get("subtype", "") == subtype:
			pool.append(eq_id)
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))


## ---------------------------------------------------------------------------
## get_class_weapon_subtypes() — 获取职业可用的武器子类型
## ---------------------------------------------------------------------------
## 数据文件中的职业定义包含 weapon_types 数组（如 ["剑", "斧"]），
## 但装备数据用的是英文子类型（如 "sword", "axe"）。这个方法做翻译映射。
## ---------------------------------------------------------------------------
func get_class_weapon_subtypes(class_id: String) -> Array:
	var cls = classes.get(class_id, {})
	var weapons = cls.get("weapon_types", [])
	# 中文武器类型 → 英文子类型的映射表
	var subtype_map := {
		"剑": "sword", "斧": "axe", "枪": "spear", "弓": "bow", "杖": "staff",
		"短剑": "sword", "锤": "axe", "弩": "bow", "爪": "sword",
		"拳/爪": "sword"
	}
	var result: Array = []
	for w in weapons:
		for kw in subtype_map:
			# .find() 返回子字符串位置，找不到返回 -1
			if w.find(kw) != -1:
				var st = subtype_map[kw]
				if st not in result:
					result.append(st)
	return result


## ---------------------------------------------------------------------------
## get_class_armor_subtypes() — 获取职业可用的防具/盾牌子类型
## ---------------------------------------------------------------------------
func get_class_armor_subtypes(class_id: String) -> Array:
	var cls = classes.get(class_id, {})
	var armors = cls.get("armor_types", [])
	var result: Array = []
	for a in armors:
		if a.find("盾") != -1 or a.find("大盾") != -1:
			result.append("shield")
	return result


# ==================================================================
#  数据校验 (Validation)
# ==================================================================
# ADR-0003 的补偿手段：JSON + Dictionary 没有编译期字段校验，
# 用启动时校验 + 测试兜底。两类校验分开：
#   validate_all_data()        — 结构错误（引用悬空/id 不一致/缺玩家势力）→ 硬错误
#   validate_effect_coverage() — 效果覆盖告警（数据效果未被引擎实现）→ 软告警
# ==================================================================

func validate_all_data() -> Array[String]:
	"""结构校验。返回错误消息数组，空数组 = 通过。"""
	var errors: Array[String] = []

	# --- 1. 记录内 id 字段与字典键一致 ---
	_validate_id_field("characters", characters, errors)
	_validate_id_field("classes", classes, errors)
	_validate_id_field("equipment", equipment, errors)
	_validate_id_field("skills", skills, errors)
	_validate_id_field("items", items, errors)
	_validate_id_field("factions", factions, errors)

	# --- 2. 角色职业引用存在 ---
	# demo-1 数据实测：部分角色的 class_zh 与 classes 表的 name_zh 翻译不一致
	# （如角色表"Crusader=十字军"、职业表"Crusader=圣骑士"），但 name_en 一致。
	# 因此：中文、英文任一匹配即视为引用有效（硬校验），
	# 中文不匹配但英文匹配的情况由 validate_class_translation() 报软告警。
	var class_names_zh: Dictionary = {}
	var class_names_en: Dictionary = {}
	for cls_id in classes:
		class_names_zh[classes[cls_id].get("name_zh", "")] = true
		class_names_en[classes[cls_id].get("name_en", "")] = true
	for char_id in characters:
		var c: Dictionary = characters[char_id]
		var cls_zh: String = c.get("class_zh", "")
		var cls_en: String = c.get("class_en", "")
		var found := (cls_zh != "" and class_names_zh.has(cls_zh)) or (cls_en != "" and class_names_en.has(cls_en))
		if not found:
			errors.append("characters.%s 的职业 %s/%s 在 classes 中不存在（中英文均未命中）" % [char_id, cls_zh, cls_en])

	# --- 3. 角色技能引用存在 ---
	# 数据形状（demo-1 实测）：skills = [技能id, ...]（数组）；
	# leader_skill / valor_skill = {"id": 技能id, ...}（字典）或 null
	for char_id in characters:
		var c: Dictionary = characters[char_id]
		var skill_refs: Array = _skill_refs_of(c.get("skills", []))
		for ref in skill_refs:
			if not skills.has(ref):
				errors.append("characters.%s 的 skills 引用了不存在的技能 %s" % [char_id, ref])
		for key in ["leader_skill", "valor_skill"]:
			var ls: Variant = c.get(key, null)
			if ls is Dictionary:
				var ls_id: String = ls.get("id", "")
				if ls_id != "" and not skills.has(ls_id):
					errors.append("characters.%s 的 %s 引用了不存在的技能 %s" % [char_id, key, ls_id])

	# --- 4. 地图路线引用的城市存在 ---
	var city_ids: Dictionary = {}
	for c in map_data.get("cities", []):
		city_ids[c.get("id", "")] = true
	for r in map_data.get("routes", []):
		if not city_ids.has(r[0]) or not city_ids.has(r[1]):
			errors.append("map 路线引用了不存在的城市: %s-%s" % [r[0], r[1]])

	# --- 5. 城市归属的势力存在 ---
	for c in map_data.get("cities", []):
		var owner: String = c.get("owner", "")
		if owner != "" and not factions.has(owner):
			errors.append("城市 %s 归属不存在的势力 %s" % [c.get("id", ""), owner])

	# --- 6. 必须存在且仅有一个玩家势力 ---
	var player_count := 0
	for f in factions:
		if factions[f].get("is_player", false):
			player_count += 1
	if player_count == 0:
		errors.append("factions: 缺少 is_player=true 的玩家势力")
	elif player_count > 1:
		errors.append("factions: 存在 %d 个玩家势力，应只有一个" % player_count)

	return errors


func validate_effect_coverage() -> Array[String]:
	"""效果覆盖校验：被动/统帅/勇气类技能的 effect_type 是否在 EffectRegistry 注册。
	返回告警数组（软校验——框架阶段允许有未实现效果，但必须显式可见、绝不静默）。
	P6 战斗引擎完成后，注册表与引擎实现集对齐，此处告警应收敛到已知范围。"""
	var warnings: Array[String] = []
	# EffectRegistry 为静态工具类（class_name），直接类名调用
	# ⚠️ 不要用 ClassDB.class_exists() 判断 GDScript 全局类是否存在——
	# 全局类注册在 ScriptServer 而不是 ClassDB，headless 下返回 false（实测坑）
	var triggers: Dictionary = EffectRegistry.get_passive_triggers()
	if triggers.is_empty():
		return warnings  # 注册表尚未填充（P6 之前）——跳过覆盖校验
	for sk_id in skills:
		var sk: Dictionary = skills[sk_id]
		var sk_type: String = sk.get("type", "")
		# 只有被动类技能（被动/勇气/统帅）走时点注册表
		if sk_type not in ["passive", "valor", "leader"]:
			continue
		for ef in sk.get("effects", []):
			var et: String = ef.get("effect_type", "")
			if et == "":
				continue
			if not triggers.has(et) and et not in EffectRegistry.get_contextual_effects():
				warnings.append("技能 %s(%s) 的被动效果 %s 未在 EffectRegistry 注册" % [sk_id, sk.get("name_zh", ""), et])
	return warnings


func validate_class_translation() -> Array[String]:
	"""软校验：角色 class_zh 与职业表 name_zh 不一致但 name_en 一致的记录。
	不影响引擎（属性取自角色自身数据），只影响按中文职业名做的查询与显示。"""
	var warnings: Array[String] = []
	var class_names_zh: Dictionary = {}
	for cls_id in classes:
		class_names_zh[classes[cls_id].get("name_zh", "")] = true
	for char_id in characters:
		var c: Dictionary = characters[char_id]
		var cls_zh: String = c.get("class_zh", "")
		if cls_zh != "" and not class_names_zh.has(cls_zh):
			warnings.append("characters.%s 的 class_zh=%s 与职业表 name_zh 不一致（name_en 已匹配）" % [char_id, cls_zh])
	return warnings


## _skill_refs_of() — 把技能引用字段（数组或单条记录）归一化为 id 数组
## 防御 JSON 形状不一致：数组里可能是字符串 id，也可能是 {"id": ...} 字典
func _skill_refs_of(raw: Variant) -> Array:
	var refs: Array = []
	if raw is Array:
		for item in raw:
			if item is String and item != "":
				refs.append(item)
			elif item is Dictionary and item.get("id", "") != "":
				refs.append(item.id)
	return refs


## _validate_id_field() — 检查表内每条记录的 id 字段与键一致
func _validate_id_field(table_name: String, table: Dictionary, errors: Array[String]) -> void:
	for rec_id in table:
		var rec: Dictionary = table[rec_id]
		if rec.get("id", "") != rec_id:
			errors.append("%s: 记录 id 字段与键不一致: %s" % [table_name, rec_id])


# ==================================================================
#  JSON 解析工具
# ==================================================================

## ---------------------------------------------------------------------------
## _parse_json() — 读取并解析 JSON 文件
## ---------------------------------------------------------------------------
## Godot 读取文件的流程和 Python 很不一样：
##
## Python 做法：
##   with open("data.json", "r", encoding="utf-8") as f:
##       data = json.load(f)
##
## Godot 做法（4.x）：
##   1. FileAccess.file_exists(path) — 检查文件是否存在
##   2. FileAccess.open(path, FileAccess.READ) — 打开文件，返回 FileAccess 对象
##   3. file.get_as_text() — 读取全部内容为字符串
##   4. JSON.new() 创建 JSON 解析器 → json.parse(text) 解析
##   5. json.get_data() 获取解析后的 Variant（Dictionary/Array）
##
## Godot 的 JSON 解析器和 Python 的一个关键区别：
##   - Python 的 json.loads() 直接返回解析结果
##   - Godot 的 JSON.parse() 返回的是错误码（OK 或错误），
##     解析结果需要通过 .get_data() 单独获取
##
## 参数：
##   path — 以 "res://" 开头的资源路径
## 返回：
##   解析后的数据（通常是 Dictionary），失败返回 null
## ---------------------------------------------------------------------------
func _parse_json(path: String):
	# 第一步：检查文件是否存在
	if not FileAccess.file_exists(path):
		push_error("[DataManager] File not found: %s" % path)
		return null

	# 第二步：打开并读取
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DataManager] Cannot open: %s" % path)
		return null
	var text = file.get_as_text()

	# 第三步：解析 JSON 文本
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:  # OK 是 GDScript 的内置常量，表示"无错误"
		push_error("[DataManager] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null

	# 第四步：返回解析后的数据
	# .get_data() 返回 Variant 类型（GDScript 的"任意类型"），实际是 Dictionary 或 Array
	return json.get_data()
