extends RefCounted
## =============================================================================
## 数据层测试（docs/00-design.md §16）
## =============================================================================
## gdtest 约定（zfoo/gdtest/UnitTest.gd）：
##   - 测试方法名（小写后）以 test 开头或结尾，且不能有参数
##   - 断言失败 = push_error(...) —— ⚠️ 不能用 Log.error！
##     实测：zfoo 的 Log.error 只调 printerr，不触发 gdf.events.log_error；
##     只有走引擎错误通道的 push_error / 脚本错误才会让测试 FAIL。
##   - 测试运行期间任何引擎错误都会导致 FAIL（fail-fast）
##
## 类比 Python：相当于 pytest 的约定式测试（函数名 test_*），
## 断言用"失败就推引擎错误"的方式表达。
## =============================================================================


## 断言失败：走引擎错误通道，触发测试框架 FAIL + quit(1)
func _fail(template: String, ...args: Array) -> void:
	push_error("[test_data] " + template.format(args, "{}"))


## 全部数据表非空（DataManager autoload 在启动时已完成加载）
func test_data_loaded() -> void:
	if DataManager.characters.is_empty():
		_fail("characters 表为空")
	if DataManager.classes.is_empty():
		_fail("classes 表为空")
	if DataManager.equipment.is_empty():
		_fail("equipment 表为空")
	if DataManager.items.is_empty():
		_fail("items 表为空")
	if DataManager.factions.is_empty():
		_fail("factions 表为空")
	if DataManager.skill_conditions.is_empty():
		_fail("skill_conditions 表为空")
	# demo-1 数据规模：222 技能 / 55 条件 / 290 装备 / 70 角色
	if DataManager.skills.size() < 100:
		_fail("skills 表异常（仅 {} 条，应为 222）", DataManager.skills.size())


## 大地图数据完整：城市与路线引用有效
func test_world_map_data() -> void:
	var map_data: Dictionary = DataManager.get_map_data()
	if map_data.is_empty():
		_fail("大地图数据为空")
		return
	var cities: Array = map_data.get("cities", [])
	var routes: Array = map_data.get("routes", [])
	if cities.size() != 22:
		_fail("城市数量应为 22，实际 {}", cities.size())
	if routes.size() != 31:
		_fail("路线数量应为 31，实际 {}", routes.size())
	# 每个城市都能 O(1) 查到，且归属势力存在
	for c in cities:
		var city_id: String = c.get("id", "")
		if DataManager.get_city(city_id).is_empty():
			_fail("城市 {} 无法通过索引查询", city_id)
		var owner: String = c.get("owner", "")
		if not DataManager.factions.has(owner):
			_fail("城市 {} 归属未知势力 {}", city_id, owner)


## 结构校验零错误（引用悬空/id 不一致/缺玩家势力都会在这里现形）
func test_validate_all_data() -> void:
	var errors: Array[String] = DataManager.validate_all_data()
	for e in errors:
		_fail("结构校验失败: {}", e)


## 玩家势力存在且唯一（get_player_faction_id 与 is_player 标记一致）
func test_player_faction() -> void:
	var pid: String = DataManager.get_player_faction_id()
	if pid == "":
		_fail("找不到玩家势力")
		return
	var p: Dictionary = DataManager.get_faction(pid)
	if not p.get("is_player", false):
		_fail("玩家势力 {} 的 is_player 标记为 false", pid)
	# AI 势力的 ai_strategy 字段必须存在（空串 = 内置 BasicAI）
	for fid in DataManager.get_all_faction_ids():
		if not DataManager.get_faction(fid).has("ai_strategy"):
			_fail("势力 {} 缺少 ai_strategy 字段", fid)


## 反向索引可用：职业 → 角色/技能 分组查询
func test_indices() -> void:
	# 职业表里每个职业中文名都能通过索引查到其角色与技能
	var found_any := false
	for cls_id in DataManager.classes:
		var cls_name: String = DataManager.classes[cls_id].get("name_zh", "")
		if cls_name == "":
			continue
		var chars: Array = DataManager.get_characters_by_class_name(cls_name)
		var sks: Array = DataManager.get_skills_by_class_name(cls_name)
		if not chars.is_empty() or not sks.is_empty():
			found_any = true
	if not found_any:
		_fail("反向索引全部为空（构建失败？）")
	# 装备子类型索引：sword 类装备存在
	if DataManager.get_equipment_by_subtype("sword").is_empty():
		_fail("equipment 索引缺少 sword 子类型")


## 效果覆盖：demo-1 数据里的被动时点效果全部注册（防静默丢失）
## 注意：此测试断言的是"demo-1 引擎实现集"的覆盖，见 EffectRegistry 头注释
func test_effect_coverage_known_set() -> void:
	# 核心时点效果必须全部注册（demo-1 实现集 + 本项目补齐的 heal_on_kill）
	# 直接引用全局类；若类不存在这里会编译失败——比 ClassDB.class_exists 更可靠
	# （GDScript 全局类注册在 ScriptServer，ClassDB.class_exists 返回 false，实测坑）
	var required := [
		"initiative_up", "first_strike", "pp_on_low_hp", "regen",
		"attack_up", "power_boost", "truestrike_once", "truestrike",
		"accuracy_up", "crit_up", "heal_on_hit", "lifesteal", "pp_on_hit",
		"ap_on_kill", "pp_on_kill", "follow_up", "attack_up_on_kill",
		"counter", "ally_defense_up", "end_of_battle_heal", "heal_on_kill",
	]
	for et in required:
		if not EffectRegistry.is_registered(et):
			_fail("效果 {} 未在 EffectRegistry 注册", et)
