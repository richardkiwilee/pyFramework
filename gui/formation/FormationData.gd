## =====================================================================
## FormationData — 编队数据中心（Autoload 全局单例）
## =====================================================================
## 两件事：
##   1. 启动时把 data/*.json 一次性读进内存，提供 O(1) 的 id 查询。
##   2. 持有玩家的全部队伍 + 待命池，并提供上场/下场/解散等操作。
##
## 数据来源：data/ 下的 4 个 json 是从 fullver-1 原样复制来的，**不要改**，
## 方便日后整份替换。gui 自己的规则写在 data/formation_rules.json（见 TeamRules.gd）。
##
## ---- 关于「待命池」----
## readme 里「下场」要把单位移进待命池。参考项目都没有这个概念，这里的定义是：
##   待命池 = 花名册里当前不属于任何队伍的单位。
## 一个单位在任意时刻只可能在「某一支队伍的某一格」或「待命池」里，二选一。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Node          → Autoload 必须是 Node（引擎会实例化它并挂到场景树根下）
## Autoload              → 在 project.godot 的 [autoload] 段注册后成为全局单例，
##                         任何脚本直接用名字 FormationData 访问，不需要 import。
## signal xxx()          → 声明信号（观察者模式）。.connect(f) 订阅，.emit() 触发。
## func _ready()         → 节点进入场景树时自动调用一次（类似 __init__ 的时机）
## FileAccess.get_file_as_string(path) → 读整个文件为字符串（等价于 open().read()）
## JSON.parse_string(s)  → 解析 JSON，失败返回 null（等价于 json.loads，但不抛异常）
## randi_range(a, b)     → 随机整数，闭区间 [a, b]（等价于 random.randint）
## Array.pick_random()   → 随机取一个元素（等价于 random.choice）
## push_error / push_warning → 往 Godot 控制台输出错误/警告
## =====================================================================
extends Node

## 队伍集合有变化（新建/解散/改名）时发出，UI 据此刷新。
signal teams_changed
## 某支队伍的内部构成有变化（上场/下场/移动/换队长）时发出。
signal team_modified

# ---------------- 静态数据表（id → 数据字典）----------------
var characters: Dictionary = {}        # 角色 id → characters.json 条目
var classes_by_name: Dictionary = {}   # 职业中文名 → classes.json 条目
var equipment: Dictionary = {}         # 装备 id → equipment.json 条目
var skills: Dictionary = {}            # 技能 id → skills.json 条目
var conditions: Dictionary = {}        # 条件 id → skill_conditions 条目

## 反向索引：装备子类型（sword/shield/accessory…）→ [装备 id, ...]
var equipment_by_subtype: Dictionary = {}

# ---------------- 运行期数据 ----------------
var roster: Array = []       # 全部单位（Array[UnitModel]），花名册
var teams: Array = []        # 全部队伍（Array[TeamModel]）
var _next_unit_seq: int = 1  # 单位 id 自增序号
var _next_team_seq: int = 1  # 队伍 id 自增序号


func _ready() -> void:
	_load_all_json()
	_build_initial_roster()


# =====================================================================
#  一、JSON 装载
# =====================================================================

## 读一个 json 文件，返回顶层字典。任何一步失败都返回 {} 并报错（不会崩）。
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[FormationData] 数据文件不存在：%s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("[FormationData] JSON 解析失败：%s" % path)
		return {}
	return parsed


## 把「顶层字典里某个数组字段」按 id 建成查询表。
## 例：_index_by_id(data, "characters") → { "alain": {...}, ... }
func _index_by_id(data: Dictionary, list_key: String) -> Dictionary:
	var out: Dictionary = {}
	var arr = data.get(list_key, [])
	if typeof(arr) != TYPE_ARRAY:
		return out
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var iid := str(item.get("id", ""))
		if not iid.is_empty():
			out[iid] = item
	return out


func _load_all_json() -> void:
	# ---- 角色 ----
	characters = _index_by_id(_read_json("res://data/characters.json"), "characters")

	# ---- 职业：按**中文名**建索引 ----
	# characters.json 里没有 class_id，和 classes.json 的唯一关联就是中文职业名，
	# 所以这里用 name_zh 当 key，而不是 id。
	# ⚠️ 但 70 个角色里有 17 个的 class_zh 在 classes.json 里查不到
	#   （精灵弓箭手、狼人、天使剑兵…），查不到是**正常情况**，调用方要能接受空字典。
	var cls_data := _read_json("res://data/classes.json")
	var cls_arr = cls_data.get("classes", [])
	if typeof(cls_arr) == TYPE_ARRAY:
		for c in cls_arr:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var nm := str(c.get("name_zh", ""))
			if not nm.is_empty():
				classes_by_name[nm] = c

	# ---- 装备 ----
	equipment = _index_by_id(_read_json("res://data/equipment.json"), "equipment")
	for eid in equipment:
		var sub := str(equipment[eid].get("subtype", ""))
		if sub.is_empty():
			continue
		if not equipment_by_subtype.has(sub):
			equipment_by_subtype[sub] = []
		equipment_by_subtype[sub].append(eid)

	# ---- 技能 + 条件（在同一个文件的两个字段里）----
	var sk_data := _read_json("res://data/skills.json")
	skills = _index_by_id(sk_data, "skills")
	conditions = _index_by_id(sk_data, "skill_conditions")

	print("[FormationData] 已载入 角色%d / 职业%d / 装备%d / 技能%d / 条件%d" \
		% [characters.size(), classes_by_name.size(), equipment.size(), skills.size(), conditions.size()])


# ---------------- 查询接口（全部保证「查不到返回空字典」，绝不返回 null）----------------

func get_character(cid: String) -> Dictionary:
	return characters.get(cid, {})


## 按中文职业名查职业。查不到返回 {} —— 这是常态，不是错误（见上面的 ⚠️）。
func get_class_by_name(name_zh: String) -> Dictionary:
	return classes_by_name.get(name_zh, {})


func get_equipment(eid: String) -> Dictionary:
	return equipment.get(eid, {})


func get_skill(sid: String) -> Dictionary:
	return skills.get(sid, {})


func get_condition(cid: String) -> Dictionary:
	return conditions.get(cid, {})


## 取某个装备槽位可用的全部装备 id。
## slot_key ∈ weapon / shield / acc1 / acc2，对应的 subtypes 写在 UnitModel.EQUIP_SLOTS。
func equipment_for_slot(slot_key: String) -> Array:
	var out: Array = []
	for s in UnitModel.EQUIP_SLOTS:
		if s.key != slot_key:
			continue
		for sub in s.subtypes:
			out.append_array(equipment_by_subtype.get(sub, []))
		break
	return out


## 全部主动技能 id（技能编程只让选主动技能）。
func active_skill_ids() -> Array:
	var out: Array = []
	for sid in skills:
		if str(skills[sid].get("type", "")) == "active":
			out.append(sid)
	return out


func all_condition_ids() -> Array:
	return conditions.keys()


# =====================================================================
#  二、开局花名册与队伍
# =====================================================================

## 造一个单位。会自动补上职业数据（查不到就是空字典，TeamRules 有兜底）。
func make_unit(character_id: String, level: int) -> UnitModel:
	var cd := get_character(character_id)
	var class_zh := str(cd.get("class_zh", ""))
	var class_data := get_class_by_name(class_zh)
	var u := UnitModel.new("unit_%d" % _next_unit_seq, cd, class_data, level)
	_next_unit_seq += 1
	return u


## 开局造花名册 + 两支示例队伍。参数来自 formation_rules.json 的 roster 段。
func _build_initial_roster() -> void:
	var cfg := TeamRules.roster_config()
	var want := int(cfg.get("unit_count", 16))
	var lv_min := int(cfg.get("level_min", 8))
	var lv_max := int(cfg.get("level_max", 22))

	# characters.json 的 key 顺序就是文件里的顺序，取前 want 个即可。
	var ids := characters.keys()
	for i in mini(want, ids.size()):
		roster.append(make_unit(str(ids[i]), randi_range(lv_min, lv_max)))

	# 按 initial_teams 里写的人数，顺序把花名册前面的人编进队。
	var plan = cfg.get("initial_teams", [3, 2])
	if typeof(plan) != TYPE_ARRAY:
		plan = [3, 2]
	var cursor := 0
	for n in plan:
		var t := create_team()
		for k in int(n):
			if cursor >= roster.size():
				break
			# 从后排(0)往前排(8)顺序填格子。
			t.set_unit(t.first_empty_slot(), roster[cursor])
			cursor += 1
		# 开局队伍直接用队长名命名，和退出时的命名规则保持一致。
		t.rename_by_captain()


## 新建一支空队伍并加入列表。
func create_team() -> TeamModel:
	var t := TeamModel.new("team_%d" % _next_team_seq, "新队伍 %d" % _next_team_seq)
	_next_team_seq += 1
	teams.append(t)
	teams_changed.emit()
	return t


## 解散队伍：成员自动回到待命池（因为待命池就是「不在任何队伍里的人」，
## 所以把队伍从列表里删掉，成员自然就回池了，不需要额外搬运）。
func delete_team(t: TeamModel) -> void:
	var idx := teams.find(t)
	if idx < 0:
		return
	teams.remove_at(idx)
	teams_changed.emit()


## 待命池 = 花名册里不在任何队伍中的单位。
func reserve_pool() -> Array:
	var used := {}
	for t in teams:
		for u in t.members():
			used[u] = true
	var out: Array = []
	for u in roster:
		if not used.has(u):
			out.append(u)
	return out


## 把某个单位从它当前所在的队伍里摘出来（用于「下场」和「换队」）。
## 单位唯一归属：放进 A 队之前必须先从 B 队摘掉。
func detach_unit(u: UnitModel) -> void:
	for t in teams:
		# 注意这里必须写 `var s: int =` 而不是 `var s :=`。
		# teams 是无类型 Array，循环变量 t 就是 Variant，GDScript 无法从
		# t.slot_of(u) 推断返回类型，用 := 会直接报解析错误。
		var s: int = t.slot_of(u)
		if s >= 0:
			t.remove_at(s)
			return


## 把待命池里的单位放到指定队伍的指定格子。
## 成功返回 true；格子被占或单位无效返回 false。
func place_unit(t: TeamModel, slot: int, u: UnitModel) -> bool:
	if t == null or u == null:
		return false
	if t.unit_at(slot) != null:
		return false
	detach_unit(u)  # 先从原队摘掉，保证唯一归属
	var ok := t.set_unit(slot, u)
	if ok:
		team_modified.emit()
	return ok


## 「下场」：把单位移回待命池。
func send_to_reserve(t: TeamModel, u: UnitModel) -> void:
	var s := t.slot_of(u)
	if s >= 0:
		t.remove_at(s)
		team_modified.emit()
