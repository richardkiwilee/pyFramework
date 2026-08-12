extends Node
## =============================================================================
## DataManager — 自动加载(Autoload)单例
## =============================================================================
## 作用：在游戏启动时，一次性从 JSON 数据文件中加载所有游戏数据到内存中，
##       然后提供 O(1) 的 ID 查找接口，供其他脚本随时查询。
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
# 例如 characters["lord_01"] = { "name_zh": "亚连", "class_zh": "领主", ... }
var characters: Dictionary = {}       # id → 角色数据
var classes: Dictionary = {}          # id → 职业数据
var equipment: Dictionary = {}        # id → 装备数据
var skills: Dictionary = {}           # id → 技能数据
var skill_conditions: Dictionary = {} # id → 技能条件数据（如"HP<50%时触发"）
var items: Dictionary = {}            # id → 道具数据

# ------------------------------------------------------------------ 反向索引
# 原始数据以 ID 为 key，但 UI 经常需要"查某个职业有哪些角色"。
# 这些索引在 _build_indices() 中构建，避免每次都遍历全表。
# 类比 Python：相当于 defaultdict(list)，按类别名分组。
var characters_by_class: Dictionary = {}  # 职业中文名 → [角色ID列表]
var skills_by_class: Dictionary = {}      # 职业中文名 → [技能ID列表]
var equipment_by_subtype: Dictionary = {} # 子类型(sword/axe/...) → [装备ID列表]

# 是否已经加载过数据（防止重复加载）
var _loaded: bool = false

# 队伍数据备份 — 战斗前保存，编队界面恢复时使用
# 结构: Array[Dictionary]，每项为 {name, units: Array[String]}
var saved_teams: Array = []


## ---------------------------------------------------------------------------
## _ready() — Godot 生命周期回调
## ---------------------------------------------------------------------------
## 当节点进入场景树时自动调用。Autoload 的 _ready() 在游戏启动时执行一次。
## 这里只做一件事：调用 load_all_data() 把所有 JSON 读入内存。
## ---------------------------------------------------------------------------
func _ready() -> void:
	load_all_data()


## ---------------------------------------------------------------------------
## load_all_data() — 加载全部游戏数据
## ---------------------------------------------------------------------------
## 依次调用各 _load_xxx() 方法读取 JSON 文件，然后构建反向索引。
## 设计为幂等操作：如果已加载则直接返回，防止重复加载。
##
## GDScript 注意：
##   % 运算符用于字符串格式化，和 Python 老式的 % 格式化语法完全相同。
##   [a, b, c] 是数组字面量，类似于 Python 的 list。
##   .size() 返回数组/字典的元素个数，等价于 Python 的 len()。
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

	# 构建反向索引以加速后续查询
	_build_indices()

	# 打印加载统计到控制台，方便调试
	print("[DataManager] Loaded: %d chars, %d classes, %d equipment, %d skills, %d items" % [
		characters.size(), classes.size(), equipment.size(), skills.size(), items.size()
	])


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
	# 每个角色记录的 id 字段（如 "lord_01"）作为 key
	for rec in data.get("characters", []):
		characters[rec.id] = rec


func _load_classes() -> void:
	var data = _parse_json("res://data/classes.json")
	if data == null:
		return
	# classes.json 的顶层结构：{"classes": [{...}, {...}, ...]}
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


# ==================================================================
#  反向索引构建 (Index Building)
# ==================================================================
# 加载完原始数据后，构建"分类→ID列表"的反向索引。
# 例如 characters_by_class["领主"] = ["lord_01", "lord_02", ...]
# 这样 UI 按职业筛选角色时就无需遍历全表，直接 O(1) 取出列表。
# ==================================================================

func _build_indices() -> void:
	# --- 角色按职业索引 ---
	for char_id in characters:
		var c = characters[char_id]
		var cls = c.get("class_zh", "")          # 职业中文名，如"领主"、"法师"
		if not characters_by_class.has(cls):      # .has() 等价于 Python 的 `key in dict`
			characters_by_class[cls] = []
		characters_by_class[cls].append(char_id)

	# --- 装备按子类型索引 ---
	# 子类型如 sword（剑）、axe（斧）、spear（枪）、bow（弓）、staff（杖）、shield（盾）
	for eq_id in equipment:
		var eq = equipment[eq_id]
		var st = eq.get("subtype", "other")
		if not equipment_by_subtype.has(st):
			equipment_by_subtype[st] = []
		equipment_by_subtype[st].append(eq_id)

	# --- 技能按职业索引 ---
	# 技能记录的 class_zh 字段表示该技能属于哪个职业
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


## ---------------------------------------------------------------------------
## get_random_characters() — 随机获取角色
## ---------------------------------------------------------------------------
## 参数：
##   count      — 需要返回的角色数量
##   exclude_ids — 要排除的角色ID列表（避免重复选取已编入队伍的角色）
##
## 流程：
##   1. 遍历所有角色ID，排除掉 exclude_ids 中的
##   2. 打乱顺序（.shuffle() 是原地操作，类似 Python 的 random.shuffle）
##   3. 取前 count 个（.slice() 类似 Python 的 list[0:count]）
##
## GDScript 注意：
##   `cid not in exclude_ids` — GDScript 的 `in` 运算符可以用于 Array，
##   检查元素是否在数组中。和 Python 的 `in` 语义相同。
## ---------------------------------------------------------------------------
func get_random_characters(count: int, exclude_ids: Array = []) -> Array:
	var pool: Array = []
	for cid in characters:
		if cid not in exclude_ids:
			pool.append(cid)
	pool.shuffle()
	# .slice(begin, end) — 返回子数组。end 可以超出范围，自动截断。
	return pool.slice(0, min(count, pool.size()))


## ---------------------------------------------------------------------------
## get_random_equipment_for_slot() — 获取指定类型的随机装备
## ---------------------------------------------------------------------------
## 用于给敌方单位随机配装，增加战斗的变化性。
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
## 但装备数据用的是英文子类型（如 "sword", "axe"）。
## 这个方法做这个翻译映射。
##
## GDScript 注意：
##   var x := value  使用 := 做类型推断，等价于 var x = value，
##   x 的类型由右侧表达式推断。这是 GDScript 的可选写法。
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
## 检查职业的 armor_types 数组，如果包含"盾"字则返回 "shield" 子类型。
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
##
## 返回：
##   解析后的数据（通常是 Dictionary 或 Array），失败返回 null
## ---------------------------------------------------------------------------
func _parse_json(path: String):
	# 第一步：检查文件是否存在
	if not FileAccess.file_exists(path):
		push_error("[DataManager] File not found: %s" % path)
		return null

	# 第二步：打开并读取
	# FileAccess.READ 是枚举常量，表示以只读模式打开
	var file = FileAccess.open(path, FileAccess.READ)
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
