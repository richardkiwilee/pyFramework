extends Node
## =============================================================================
## BattleManager — 自动加载(Autoload)单例，战斗模拟引擎
## =============================================================================
## 这是整个战斗系统的核心，负责：
##   1. 战斗单位的创建和初始化（create_battle_unit）
##   2. 回合制战斗流程控制（start_battle -> _start_next_round -> next_action 循环）
##   3. 行动队列管理（_pending_actions）
##   4. 伤害计算（_calc_damage / _apply_damage）
##   5. 战斗结束判定（_check_battle_end）
##
## 注意：BattleManager 是"纯数据+逻辑"层，不处理任何 UI。
##       UI 由 battle_scene.gd 通过信号和 next_action() 轮询驱动。
##
## =============================================================================
##  核心概念：回合制战斗的"时点"系统（Timing Point System）
## =============================================================================
##
## 本游戏的战斗流程采用"逐行动播放"的模式。理解"时点"是理解整个
## 战斗系统的关键。下面详细解释每个时点和它们之间的转换关系。
##
## +-----------------------------------------------------------------+
## |                     战斗生命周期总览                              |
## +-----------------------------------------------------------------+
## |                                                                 |
## |  [main_screen] 玩家点击"开始战斗"                                 |
## |       |                                                         |
## |       v                                                         |
## |  ① start_battle(team_ids)                                       |
## |     · 创建玩家和敌方单位（create_battle_unit）                    |
## |     · 随机配装（equip_random_for_unit）                          |
## |     · battle_active = true                                      |
## |       |                                                         |
## |       v                                                         |
## |  [battle_scene] _ready() -> BattleManager.begin_combat()        |
## |       |                                                         |
## |       v                                                         |
## |  ② begin_combat()                                               |
## |     · 发出 battle_started 信号 -> UI 创建单位卡片                  |
## |     · 调用 _start_next_round() 进入第一回合                      |
## |       |                                                         |
## |       v                                                         |
## |  ③ _start_next_round()  <---------------------------+           |
## |     【回合开始时点】                                 |           |
## |     · round_num += 1                                |           |
## |     · 发出 round_started 信号 -> UI 更新回合标签       |           |
## |     · 重置所有存活单位的 AP/PP（资源恢复时点）         |           |
## |     · 按速度(spd)降序排列行动顺序（_turn_order）       |           |
## |     · 预计算所有单位的行动（_compute_unit_action）     |           |
## |     · 将行动压入 _pending_actions 队列               |           |
## |       |                                             |           |
## |       v                                             |           |
## |  [battle_scene] Timer 每 0.9 秒触发                  |           |
## |       |                                             |           |
## |       v                                             |           |
## |  ④ next_action()                                    |           |
## |     【行动取出时点】                                 |           |
## |     · 从 _pending_actions 队列头部取出一个行动        |           |
## |     · 检查行动者是否还存活（可能在本回合被先行动的     |           |
## |       单位击杀），如果已死则跳过并发出 skipped 信号    |           |
## |     · 返回该行动的 Dictionary，由 UI 播放动画         |           |
## |       |                                             |           |
## |       +- 队列非空 -> 返回下一个行动                    |           |
## |       |   回到④，下一次 Timer tick 继续取出           |           |
## |       |                                             |           |
## |       +- 队列为空 -> 【回合结束时点】                   |           |
## |          · _check_battle_end() 检查胜负              |           |
## |          · 未结束 -> 回到③ _start_next_round() ------+           |
## |          · 已结束 -> battle_active = false            |           |
## |                    · 发出 battle_ended 信号           |           |
## |                                                                 |
## +-----------------------------------------------------------------+
##
## 关键设计决策——"预计算"模式：
##   每个回合开始时，所有单位的行动被一次性计算好（_compute_unit_action），
##   存入 _pending_actions 队列。然后逐个取出播放。这不是"即算即打"，
##   而是"先算后播"，类似于棋类游戏的"先想好所有走法，再依次执行"。
##
##   优点：行动顺序清晰、可预测，调试方便。
##   缺点：预计算时的游戏状态和实际播放时的状态可能不同（某个单位在队列中被
##         先行动的单位击杀，但它的行动已经被预计算了）。这个问题通过
##         next_action() 中的存活检查来解决——发现行动者已死就跳过。
##
## =============================================================================
##  技能编程 & 目标选取（Skill Programming & Target Selection）
## =============================================================================
##
## 本游戏的技能系统和目标选取分为两个层面：
##
## 【数据层】skills.json 中的技能定义包含：
##   - target_type:  目标类型（如 single_enemy, all_enemies, self, ally 等）
##   - target_row:   目标行（front/back/all），限制前排/后排选取
##   - damage_type:  伤害类型（physical/magic）
##   - power:        技能威力（影响伤害公式）
##   - hits:         攻击次数
##   - ap_cost:      AP 消耗（Action Point）
##   - pp_cost:      PP 消耗（Passive Point）
##   - effects:      附加效果数组（如中毒、眩晕、回血等）
##   - condition:    发动条件（如"HP<50%时触发"，关联 skill_conditions 表）
##
## 【当前实现层】_compute_unit_action() 中的目标选取逻辑（简化版）：
##
##   当前版本的目标选取是非常简化的，只区分两种情况：
##
##   +----------------+-------------------------------------+
##   | 条件           | 目标选取逻辑                          |
##   +----------------+-------------------------------------+
##   | AP = 0         | 从敌方存活单位中取第一个(alive_targets[0])|
## |   | (普通攻击)     | -> 固定选取，无随机性                  |
## |   |                | -> 伤害公式用固定威力 60                |
##   +----------------+-------------------------------------+
##   | AP > 0         | 从敌方存活单位中随机选一个              |
## |   | (技能攻击)     | -> alive_targets.pick_random()        |
## |   |                | -> 伤害公式用随机威力 80~120            |
##   +----------------+-------------------------------------+
##
##   【重要】当前版本完全没有使用 skills.json 中的技能数据！
##   这意味着：
##     · 所有角色的"技能攻击"都是同一个通用逻辑（威力 80-120）
##     · 不存在前排/后排的目标限制
##     · 不存在"治疗友方"、"全体攻击"等不同目标类型的技能
##     · skills.json 中 222 个技能的 target_type 等字段未被读取
##     · 被动技能（passive）在战斗中完全未实现
##
##   这是有意为之的简化——先让战斗跑起来，技能系统的完整实现是后续迭代
##   的重头戏。理解当前简化版的逻辑后，再去看 skills.json 的数据结构，
##   就能清楚地知道完整版需要怎么扩展。
##
## 【扩展方向——如何实现完整的目标选取系统】
##
##   如果要从简化版升级到完整版，_compute_unit_action() 需要改为：
##
##   伪代码示意（Python 风格，帮助理解）：
##   ```
##   def _compute_unit_action_full(unit):
##       # 1. 遍历该角色的技能列表（从 JSON 获取）
##       available_skills = DataManager.get_character(unit.char_id).skills
## |       usable = [s for s in available_skills
##                  if s.ap_cost <= unit.ap and s.pp_cost <= unit.pp]
##       if not usable:
##           return basic_attack(unit)  # 没有可用技能 -> 普通攻击
##
##       # 2. 选择要使用的技能（AI 决策，可以用优先级/权重/随机）
##       skill = select_best_skill(usable)
##
##       # 3. 根据技能的 target_type 筛选目标
##       match skill.target_type:
##           "single_enemy":
##               pool = alive_enemies
## |               if skill.target_row == "front":
##                   pool = [e for e in pool if e.position < 3]  # 只选前排
## |               target = pick_best_target(pool, skill)
##           "all_enemies":
##               targets = alive_enemies  # 全体攻击
##           "self":
##               target = unit  # 自身
##           "ally":
##               pool = alive_allies
##               target = lowest_hp(pool)  # 例如治疗血量最低的友方
##           ...
##
##       # 4. 根据技能的 damage_type 选择攻击力/防御力组合
##       if skill.damage_type == "magic":
##           atk_stat = unit.mag; def_stat = target.mdf
##       else:
##           atk_stat = unit.atk; def_stat = target.def
##
##       # 5. 计算伤害 = f(skill.power, skill.hits, atk_stat, def_stat)
##       damage = calc_skill_damage(unit, target, skill)
##
##       # 6. 处理技能的附加效果（effects 数组）
##       for effect in skill.effects:
##           apply_effect(target, effect)
##
##       return build_action_dict(...)
##   ```
##
##   以上伪代码展示了完整技能系统需要的核心组件。对照 skills.json 的
##   数据结构，可以看到大部分字段都有清晰的用途。
## =============================================================================

# ==================================================================
#  信号定义 (Signals)
# ==================================================================
## 信号是 Godot 的观察者模式机制。BattleManager 发出信号，
## battle_scene.gd 连接这些信号以驱动 UI 更新。

## 战斗开始时发出（begin_combat() 中）
signal battle_started()

## 战斗结束时发出。result 参数为 "victory"（胜利）或 "defeat"（败北）
signal battle_ended(result: String)

## 每个行动从队列中取出时发出。UI 层接收后播放动画、更新血条。
## 注意：这个信号用于 next_action() 中 skipped 行动的即时通知。
## 正常的 attack/death 行动通过 next_action() 的返回值传递。
signal battle_action(action: Dictionary)

## 新回合开始时发出。round_num 是当前回合数（从1开始）
signal round_started(round_num: int)

# ==================================================================
#  战斗状态 (Battle State)
# ==================================================================

## 玩家单位列表 — Array[Dictionary]，每个元素是 create_battle_unit() 的返回值
var player_units: Array = []

## 敌方单位列表 — 同上结构，is_enemy=true
var enemy_units: Array = []

## 当前回合数（从1开始）
var round_num: int = 0

## 战斗是否正在进行中
var battle_active: bool = false

# ==================================================================
#  行动队列 (Action Queue)
# ==================================================================
## 这是回合制战斗的"调度器"核心。理解这几个变量的关系至关重要。
##
## 数据流：
##
## _turn_order (Array[Dictionary])
##   +-- 当前回合的行动顺序表。按 spd 降序排列所有存活单位。
##       在 _start_next_round() 中生成，只在这一处生成。
##       用途：遍历它来预计算每个单位的行动。
##
## _pending_actions (Array[Dictionary])
##   +-- 待播放的行动队列。在 _start_next_round() 中，
##       遍历 _turn_order 并对每个单位调用 _compute_unit_action()，
##       将结果压入此队列。然后 next_action() 逐个取出。
##
##       队列中可以插入额外的行动（如 _apply_damage() 中，
##       当单位死亡时，用 push_front 把 death 行动插入队首，
##       确保死亡动画在下一个攻击动画之前播放）。
##
## _current_turn (int)
##   +-- 当前回合内已处理的行动计数（主要用于调试，不影响逻辑）
##
## _round_done (bool)
##   +-- 当前回合是否已处理完毕。在 next_action() 中，
##       当队列耗尽时设为 true，触发回合结束检测和下一回合开始。
## ==================================================================

## 待播放的行动队列。每个元素是 _compute_unit_action() 返回的 Dictionary
var _pending_actions: Array = []

## 当前回合的行动顺序表（按速度排序的单位列表）
var _turn_order: Array = []

## 当前回合已处理的行动数
var _current_turn: int = 0

## 当前回合是否已结束
var _round_done: bool = true


# ==================================================================
#  战斗单位创建 (Battle Unit Factory)
# ==================================================================

## ---------------------------------------------------------------------------
## create_battle_unit() — 从角色数据创建战斗单位
## ---------------------------------------------------------------------------
## 这是"图鉴数据"到"战斗数据"的转换工厂。
##
## 输入：char_id（如 "lord_01"），is_enemy（是否为敌方）
## 输出：一个战斗用的 Dictionary，包含所有战斗相关属性
##
## 属性来源优先级（逐级回退）：
##   base_stats > level_50_stats > 硬编码默认值
##
## 字段说明（Python 类比）：
##
##   基础身份：
##     char_id   — 角色ID，用于查询数据
##     name_zh   — 中文名
##     class_zh  — 职业中文名
##     is_enemy  — 是否为敌方
##     is_alive  — 是否存活
##     position  — 在阵型中的位置（0-5，0-2前排，3-5后排）
##
##   战斗属性（六维+命中/回避/暴击/格挡）：
##     max_hp / hp — 最大/当前生命值
##     atk — 物理攻击力（Physical Attack）
##     def — 物理防御力（Physical Defense）
##     mag — 魔法攻击力（Magic Attack）
##     mdf — 魔法防御力（Magic Defense）
##     spd — 速度/先制（Initiative），决定行动顺序
##     acc — 命中率（Accuracy）
##     eva — 回避率（Evasion）
##     crit — 暴击率（Critical Rate）
##     guard — 格挡率（Guard Rate）
##
##   资源系统：
##     ap / max_ap — 行动点（Action Point），用于主动技能
##     pp / max_pp — 被动点（Passive Point），用于被动技能
##     · AP 消耗型的技能是"主动技能"（红色🔴），玩家主动选择使用
##     · PP 消耗型的技能是"被动技能"（蓝色🔵），满足条件自动触发
##     · 每回合开始时 ap 和 pp 恢复到 max 值
##
##   技能：
##     skills — 角色可用的技能列表（从 JSON 拷贝）
##
##   其他：
##     equipment      — 装备映射 {"weapon": eq_id, ...}
##     statuses       — 异常状态列表（中毒、眩晕等，当前未使用）
##     damage_dealt   — 累计造成的伤害（用于战后统计）
##     damage_taken   — 累计承受的伤害（用于战后统计）
##
## GDScript 语法注意：
##   三元表达式：a if cond else b
##   和 Python 的语法完全一样！a if condition else b
##
##   .has(key) — 检查 Dictionary 是否包含某键。等价于 Python 的 key in dict
##   .get(key, default) — 安全取值。等价于 Python 的 dict.get(key, default)
## ---------------------------------------------------------------------------
func create_battle_unit(char_id: String, is_enemy: bool = false) -> Dictionary:
	# 从 DataManager 获取角色图鉴数据
	var char_data = DataManager.get_character(char_id)
	var class_data = DataManager.classes.get(char_data.get("class_id", ""), {})

	# JSON 中角色有两套属性数据：
	#   base_stats     — 1级基础属性
	#   level_50_stats — 50级属性（满级数据，战斗中优先使用）
	var base_stats = char_data.get("base_stats", {})
	var lv50 = char_data.get("level_50_stats", {})
	if base_stats == null: base_stats = {}
	if lv50 == null: lv50 = {}

	# 属性提取：优先 base_stats，回退 level_50_stats，再回退硬编码默认值
	# 注意 JSON 中的字段名不一致：
	#   base_stats 用英文缩写: hp, atk, def, mag, mdf, spd, acc, eva
	#   level_50_stats 用英文全称: HP, Physical Attack, Physical Defense, ...
	# 所以代码中先用 .has() 检查 base_stats，没有就回退到 lv50 的对应字段名
	var _bs = base_stats
	var _l5 = lv50
	var _hp  = _bs.get("hp")  if _bs.has("hp")  else (_l5.get("HP")  if _l5.has("HP")  else 80)
	var _atk = _bs.get("atk") if _bs.has("atk") else (_l5.get("Physical Attack")  if _l5.has("Physical Attack")  else 30)
	var _def = _bs.get("def") if _bs.has("def") else (_l5.get("Physical Defense") if _l5.has("Physical Defense") else 20)
	var _mag = _bs.get("mag") if _bs.has("mag") else (_l5.get("Magic Attack")    if _l5.has("Magic Attack")    else 30)
	var _mdf = _bs.get("mdf") if _bs.has("mdf") else (_l5.get("Magic Defense")   if _l5.has("Magic Defense")   else 20)
	var _spd = _bs.get("spd") if _bs.has("spd") else (_l5.get("Initiative")      if _l5.has("Initiative")      else 30)
	var _acc = _bs.get("acc") if _bs.has("acc") else (_l5.get("Accuracy")        if _l5.has("Accuracy")        else 100)
	var _eva = _bs.get("eva") if _bs.has("eva") else (_l5.get("Evasion")         if _l5.has("Evasion")         else 20)

	# 构建战斗单位字典并返回
	return {
		# --- 身份信息 ---
		"char_id": char_id,
		"name_zh": char_data.get("name_zh", "???"),
		"name_en": char_data.get("name_en", "???"),
		"class_zh": char_data.get("class_zh", ""),
		"class_id": class_data.get("id", ""),

		# --- 战斗属性 ---
		# _safe_int() 确保值是有效整数（有些 JSON 字段可能是字符串如 "120"）
		"max_hp": _safe_int(_hp, 80), "hp": _safe_int(_hp, 80),
		"atk": _safe_int(_atk, 30), "def": _safe_int(_def, 20),
		"mag": _safe_int(_mag, 30), "mdf": _safe_int(_mdf, 20),
		"spd": _safe_int(_spd, 30), "acc": _safe_int(_acc, 100), "eva": _safe_int(_eva, 20),
		"crit": _safe_int(_l5.get("Critical Rate", 10)),
		"guard": _safe_int(_l5.get("Guard Rate", 10)),

		# --- 资源 ---
		# AP/PP 从职业数据获取基准值
		# AP（stamina）：上限固定为 3，每回合恢复 1 点，使用主动技能消耗 1 点
		"ap": 2,
		"max_ap": 2,
		# PP（energy）：上限由职业决定，使用被动技能消耗 1 点
		"pp": class_data.get("base_pp", 1),
		"max_pp": class_data.get("base_pp", 1),

		# --- 技能 ---
		# 直接拷贝 JSON 中的技能数组（当前未在战斗中使用！）
		"skills": _resolve_unit_skills(char_data),

		# --- 状态标记 ---
		"is_enemy": is_enemy,
		"is_alive": true,
		"equipment": {},
		"position": 0,      # 在阵型中的位置，由 start_battle() 设置
		"statuses": [],     # 异常状态列表（预留）

		# --- 统计 ---
		"damage_dealt": 0,
		"damage_taken": 0,
	}


## ---------------------------------------------------------------------------
## equip_random_for_unit() — 为战斗单位随机装备武器和盾牌
## ---------------------------------------------------------------------------
## 根据职业可用装备类型，从装备池中随机选取 1 件武器和 1 件盾牌。
## 装备的属性加成直接叠加到单位基础属性上（因此单位的 atk/def 等
## 已经包含了装备加成）。
##
## 流程：
##   1. 查询职业可用的武器子类型（如 sword, axe, staff）
##   2. 从匹配的装备池中随机取1件
##   3. 把装备的 stats 加成加到单位属性上
##   4. 同样处理盾牌
##
## 注意：这个方法只被 start_battle() 调用，用于给玩家和敌方随机配装。
##       配装后属性直接修改，后续不再追踪装备来源。
## ---------------------------------------------------------------------------
func equip_random_for_unit(unit: Dictionary) -> void:
	# --- 武器 ---
	var class_id = unit.get("class_id", "")
	var weapon_subs = DataManager.get_class_weapon_subtypes(class_id)
	if weapon_subs.size() > 0:
		# 取第一个可用的武器子类型（通常职业只有一种武器类型）
		var wp = DataManager.get_random_equipment_for_slot(weapon_subs[0], 1)
		if wp.size() > 0:
			unit.equipment["weapon"] = wp[0]
			var eq = DataManager.get_equipment(wp[0])
			var st = eq.get("stats", {})
			# 直接将装备属性加到单位属性上
			unit.atk += st.get("atk", 0)
			unit.mag += st.get("mag", 0)
			unit.def += st.get("def", 0)
			unit.mdf += st.get("mdf", 0)
			unit.spd += st.get("spd", 0)
			var hp_bonus = st.get("hp", 0)
			unit.hp += hp_bonus
			unit.max_hp += hp_bonus

	# --- 盾牌 ---
	var shield_subs = DataManager.get_class_armor_subtypes(class_id)
	if shield_subs.size() > 0:
		var sh = DataManager.get_random_equipment_for_slot(shield_subs[0], 1)
		if sh.size() > 0:
			unit.equipment["shield"] = sh[0]
			# 盾牌的 stats 也直接加（如果 JSON 中有的话）
			var eq = DataManager.get_equipment(sh[0])
			var st = eq.get("stats", {})
			unit.def += st.get("def", 0)
			unit.mdf += st.get("mdf", 0)
			var hp_bonus = st.get("hp", 0)
			unit.hp += hp_bonus
			unit.max_hp += hp_bonus


# ==================================================================
#  战斗流程控制 (Battle Flow Control)
# ==================================================================
# 以下方法构成了战斗的状态机。调用顺序必须是：
#   start_battle() -> begin_combat() -> 循环 next_action() -> (自动结束)
# ==================================================================

## ---------------------------------------------------------------------------
## ① start_battle() — 初始化战斗
## ---------------------------------------------------------------------------
## 【时点：战斗准备阶段】
##
## 由 main_screen._on_start_battle() 在切换场景前调用。
## 此方法只做数据准备，不开始实际的回合流程。
##
## 参数：
##   player_team_ids — 玩家出战角色的ID列表（最多6个）
##
## 流程：
##   1. 重置所有状态变量
##   2. 遍历玩家队伍ID，为每个非空ID创建战斗单位
##   3. 为每个玩家单位随机配装
##   4. 随机生成同等数量的敌方单位
##   5. 为每个敌方单位随机配装
##
## 注意：这里不调用 begin_combat()。begin_combat() 由 battle_scene 在
##       _ready() 中调用，确保 UI 初始化完成后再开始回合。
## ---------------------------------------------------------------------------
func start_battle(player_team_ids: Array) -> void:
	battle_active = true
	round_num = 0
	_pending_actions.clear()
	_turn_order.clear()
	_current_turn = 0

	# --- 创建玩家单位 ---
	player_units.clear()
	for i in range(player_team_ids.size()):
		var uid = player_team_ids[i]
		if uid == "":
			continue  # 跳过空格子
		var unit = create_battle_unit(uid, false)
		unit.position = i  # 记录阵型中的位置（0=前排左, 1=前排中, 2=前排右...）
		equip_random_for_unit(unit)  # 随机配装
		player_units.append(unit)

	# --- 创建敌方单位 ---
	# 随机抽取与玩家数量相等的敌方角色（排除玩家已使用的）
	var enemy_char_ids = DataManager.get_random_characters(player_units.size(), player_team_ids)
	enemy_units.clear()
	for i in range(enemy_char_ids.size()):
		var unit = create_battle_unit(enemy_char_ids[i], true)
		unit.position = i
		equip_random_for_unit(unit)
		enemy_units.append(unit)


## ---------------------------------------------------------------------------
## ② begin_combat() — 正式开始战斗
## ---------------------------------------------------------------------------
## 【时点：战斗开始】
##
## 由 battle_scene._ready() 调用（确保 UI 已初始化）。
## 发出 battle_started 信号（UI 收到后创建单位卡片、开始计时器），
## 然后进入第一个回合。
## ---------------------------------------------------------------------------
func begin_combat() -> void:
	battle_started.emit()
	_start_next_round()


## ---------------------------------------------------------------------------
## ③ _start_next_round() — 开始下一回合
## ---------------------------------------------------------------------------
## 【时点：回合开始】
##
## 这是每个回合的入口。回合内做的事情按顺序：
##
##   步骤1: round_num += 1
##          发出 round_started 信号（UI 更新回合标签、战斗日志）
##
##   步骤2: 资源恢复（AP/PP 重置）
##          遍历所有存活单位，将 ap 和 pp 恢复到最大值。
##          这是回合制游戏的标准设计——每个回合开始时刷新行动资源。
##
##   步骤3: 构建行动顺序（_turn_order）
##          将所有存活单位按 spd（速度）降序排列。
##          .sort_custom(func(a, b): return a.spd > b.spd)
## |          spd 最高的单位最先行动，spd 最低的最后行动。
##          这决定了同一回合内单位行动的先后顺序。
##
##   步骤4: 预计算所有行动（_pending_actions）
##          遍历 _turn_order 中的每个单位，调用 _compute_unit_action()
##          计算该单位的行动（选择目标、计算伤害）。因为 _compute_unit_action
##          会直接修改目标单位的 hp，所以预计算时就已经应用了伤害！
##
##          【重要】这是"预计算"模式的关键：
##           预计算时伤害已经生效，但 UI 还不知道。
##           next_action() 逐个取出行动时，UI 才逐步播放动画、更新血条。
##           这样设计的好处是：后续单位的预计算看到的是前面单位行动后
##           的真实状态（包括可能的死亡），但播放时按顺序展示。
##
##   步骤5: 设置 _round_done = false
##          标记回合进行中，next_action() 开始逐个返回行动。
##
## GDScript 的 sort_custom 说明：
##   Array.sort_custom(Callable) 用自定义比较函数排序。
##   回调返回 true 表示 a 应排在 b 前面。
##   这和 Python 3 中不再支持的 cmp 参数类似（Python 现在用 key=）。
##   相当于 Python 2 的 list.sort(cmp=lambda a,b: ...)
## ---------------------------------------------------------------------------
func _start_next_round() -> void:
	if not battle_active:
		return

	# --- 步骤1: 回合数递增 + 发信号 ---
	round_num += 1
	round_started.emit(round_num)

	# --- 步骤2: 本回合开始（资源不自动恢复）---

	# --- 步骤3: 构建行动顺序 ---
	# 按速度(spd)降序排列：速度最快的先行动
	_turn_order.clear()
	var all_units = player_units + enemy_units
	all_units.sort_custom(func(a, b): return a.spd > b.spd)
	for u in all_units:
		if u.is_alive:
			_turn_order.append(u)
	_current_turn = 0

	# --- 步骤4: 预计算所有行动 ---
	# 遍历速度顺序，为每个单位计算行动
	# 注意：_compute_unit_action() 内部会直接修改目标单位的 hp
	_pending_actions.clear()
	for u in _turn_order:
		if not u.is_alive:
			continue
		var action = _compute_unit_action(u)
		if not action.is_empty():
			_pending_actions.append(action)

	# --- 如果本回合所有人都资源不足待机，战斗强制结束 ---
	var all_waited := true
	for a in _pending_actions:
		if a.get("kind", "") != "wait":
			all_waited = false
			break
	if all_waited:
		battle_active = false
		battle_ended.emit("draw")
		return

	# --- 步骤5: 标记回合进行中 ---
	_round_done = false


## ---------------------------------------------------------------------------
## ④ next_action() — 取出下一个待播放的行动
## ---------------------------------------------------------------------------
## 【时点：行动取出 / 回合结束检测】
##
## 由 battle_scene 的 Timer 每 0.9 秒调用一次。
## 每次返回一个行动的 Dictionary，由 UI 播放动画。
## 返回空字典 {} 表示当前没有需要播放的行动（回合间隙或战斗结束）。
##
## 这是整个战斗播放系统的"心跳"函数，逻辑比较精细：
##
## +----------------------------------------------+
## | next_action() 流程                            |
## +----------------------------------------------+
## |                                              |
## |  +- battle_active? --No---> return {}         |
## |  |                                           |
## |  +- Yes                                      |
## |     |                                        |
## |     v                                        |
## |  while _pending_actions 非空:                  |
## |     |                                        |
## |     +- 取出队首 action = pop_front()          |
## |     |                                        |
## |     +- action.kind == "death"?               |
## |     |   Yes -> 直接 return（死亡动画必须播放）  |
## |     |                                        |
## |     +- 检查 action.actor_name 对应的单位        |
## |         是否还存活？                           |
## |         +- 存活 -> return action              |
## |         +- 已死 -> 发出 skipped 信号           |
## |                  继续 while 循环取下一个       |
## |                                              |
## |  while 循环结束（队列为空）:                    |
## |     |                                        |
## |     +- _round_done == false?                   |
## |     |   Yes -> 回合结束处理...                  |
## |     |   +- _round_done = true                |
## |     |   +- _check_battle_end()  检测胜负      |
## |     |   +- 未结束? -> _start_next_round()      |
## |     |   |   如果新回合有行动 -> return 第一个    |
## |     |   +- 已结束? -> return {}                |
## |     |                                        |
## |     +- _round_done == true?                    |
## |         -> return {}（战斗已结束）              |
## |                                              |
## +----------------------------------------------+
##
## "存活检查"的意义（为什么预计算了还要检查）：
##   因为采用了预计算模式，所有行动在回合开始时就计算好了。
##   但如果单位 A 被单位 B 的攻击击杀，而 B 在 _turn_order 中排在 A 前面，
##   那么 A 预计算的行动（在轮到 A 时取出）就已经失效了。
##   所以取出时发现 A 已死，就跳过它的行动并发出 skipped 信号。
## ---------------------------------------------------------------------------
func next_action() -> Dictionary:
	if not battle_active:
		return {}

	# --- 从待播放队列中取行动 ---
	# 使用 while 循环而非 if，因为可能需要跳过多个行动
	while _pending_actions.size() > 0:
		var action = _pending_actions.pop_front()  # pop_front = 队列头部取出（FIFO）

		# 死亡通知永远播放（即使用户已看到单位死亡，也要触发死亡动画）
		if action.get("kind", "") == "death":
			return action

		# 检查行动者是否还活着
		# 如果行动者在本回合被先行动的单位击杀，就跳过它的行动
		var actor = _find_unit(action.get("actor_name", ""))
		if actor != null and actor.is_alive:
			return action

		# 行动者已死亡 — 发出跳过信号并继续取下一个
		battle_action.emit({
			"kind": "skipped",
			"actor_name": action.actor_name,
			"actor_side": action.actor_side,
			"target_name": "",
			"target_side": "",
			"damage": 0,
			"skill_name": "行动取消(已阵亡)",
			"target_hp": 0, "target_max_hp": 0, "target_alive": false,
			"actor_hp": 0, "actor_max_hp": 0,
			"actor_ap": 0, "actor_max_ap": 0,
		})

	# --- 队列为空 — 回合结束 ---
	# 【时点：回合结束】
	if not _round_done:
		_round_done = true

		# 检查战斗是否结束
		_check_battle_end()
		if not battle_active:
			return {}  # 战斗结束，返回空

		# 战斗未结束 -> 开始下一回合
		_start_next_round()
		# 新回合产生的第一个行动直接返回（不等下一个 timer tick）
		if _pending_actions.size() > 0:
			return _pending_actions.pop_front()

	# 没有更多行动（理论上不会到这里，但作为兜底）
	return {}


## ---------------------------------------------------------------------------
## _find_unit() — 根据中文名查找战斗单位
## ---------------------------------------------------------------------------
## 遍历玩家和敌方单位列表，按 name_zh 匹配。
## 返回 null 如果找不到（GDScript 中 null 表示空引用）。
## ---------------------------------------------------------------------------
func _find_unit(name: String):
	for u in player_units + enemy_units:
		if u.name_zh == name:
			return u
	return null


# ==================================================================
#  行动计算 (Action Computation)
# ==================================================================
# 这是战斗 AI 的核心 — 决定每个单位做什么、打谁、造成多少伤害。
# ==================================================================

## ---------------------------------------------------------------------------
## _compute_unit_action() — 计算单位的行动
## ---------------------------------------------------------------------------
## 这是战斗 AI 的核心决策函数。给定一个单位，决定它的行动并直接应用效果。
##
## =========================================================================
##  目标选取逻辑（Target Selection Logic）— 详细解析
## =========================================================================
##
## 当前版本的目标选取是极简化的，但理解它有助于后续扩展为完整系统。
##
## 【步骤1: 确定候选目标池】
##
##   敌方单位 -> 目标池 = player_units 中的存活单位
##   玩家单位 -> 目标池 = enemy_units 中的存活单位
##
##   ```
##   var targets = enemy_units if not unit.is_enemy else player_units
##   ```
##   这是"敌我识别"的最基本形式 — 攻击对方的所有存活单位。
##   当前没有"治疗友方"、"自buff"等目标类型。
##
## 【步骤2: 过滤存活目标】
##
##   只保留 is_alive == true 的目标。
##   如果所有目标都死了（理论上不会），返回空行动。
##
## 【步骤3: 根据 AP 选择攻击方式】
##
##   +---------------+--------------------------------------+
##   | 条件           | 行为                                  |
##   +---------------+--------------------------------------+
##   | AP = 0        | 普通攻击：                              |
## |   | (无行动点)    |   · 目标 = alive_targets[0]（第一个）   |
## |   |               |   · 威力 = 60（固定值）                 |
## |   |               |   · 不消耗 AP                          |
##   +---------------+--------------------------------------+
##   | AP > 0        | 技能攻击：                              |
## |   | (有行动点)    |   · 目标 = alive_targets.pick_random() |
## |   |               |   · 威力 = 80 + randi() % 40 (80~119) |
## |   |               |   · 消耗 1 AP                          |
##   +---------------+--------------------------------------+
##
##   "普通攻击"使用 alive_targets[0] 而非随机选取的原因：
##     这是一个"确定性"选择。由于目标池的排列顺序是固定的（按 position），
##     所以同一回合的普通攻击总是打同一个目标（队列中的第一个存活单位）。
##     这虽然不是最好的设计，但简化了逻辑。完整实现应该根据位置/仇恨等
##     因素选择最优目标。
##
##   "技能攻击"使用 pick_random()：
##     pick_random() 从数组中均匀随机选取一个元素。
##     完整实现中应该替换为基于技能 target_type 的目标选取逻辑
##     （见文件头部伪代码中的目标选取扩展方向）。
##
## 【步骤4: 计算并应用伤害】
##
##   调用 _calc_damage(attacker, defender, power) 计算伤害值。
##   调用 _apply_damage(attacker, target, dmg) 应用伤害（修改 hp）。
##   如果目标死亡，_apply_damage 会自动插入 death 行动到队列。
##
## 【步骤5: 构建行动 Dictionary】
##
##   返回的行动 Dictionary 包含 UI 需要显示的所有信息：
##     kind         — 行动类型："attack"
##     actor_name   — 行动者中文名
##     actor_side   — 行动者阵营："player" 或 "enemy"
##     target_name  — 目标中文名
##     target_side  — 目标阵营
##     damage       — 造成的伤害值
##     skill_name   — 技能名称（"普通攻击" 或 "技能攻击"）
##     target_hp/max_hp/alive — 目标当前状态
##     actor_hp/max_hp/ap/max_ap — 行动者当前状态
##
## 返回值：Dictionary（行动描述），如果无法行动则返回空 {}
## =========================================================================
## ---------------------------------------------------------------------------
func _compute_unit_action(unit: Dictionary) -> Dictionary:
	# --- 分离主动/被动技能 ---
	var active_skills: Array = []
	var passive_skills: Array = []
	for sk in unit.skills:
		if sk.get("type", "") == "active":
			active_skills.append(sk)
		elif sk.get("type", "") == "passive":
			passive_skills.append(sk)

	# --- 筛选付得起的主动技能 ---
	var affordable: Array = []
	for sk in active_skills:
		if sk.get("ap_cost", 1) <= unit.ap:
			affordable.append(sk)

	if affordable.is_empty():
		return {
			"kind": "wait",
			"actor_name": unit.name_zh,
			"actor_side": "enemy" if unit.is_enemy else "player",
		}

	# --- 随机选一个技能 ---
	var skill: Dictionary = affordable[randi() % affordable.size()]
	var ap_cost: int = max(1, skill.get("ap_cost", 1))  # 主动技能至少消耗1AP
	unit.ap -= ap_cost

	# --- 确定敌我目标池 ---
	var foes = enemy_units if not unit.is_enemy else player_units
	var allies = player_units if not unit.is_enemy else enemy_units
	var alive_foes: Array = []
	for t in foes:
		if t.is_alive: alive_foes.append(t)
	var alive_allies: Array = []
	for t in allies:
		if t.is_alive: alive_allies.append(t)

	# --- 按 target_type 选取目标 ---
	var target_type: String = skill.get("target_type", "single")
	var targets: Array = []
	match target_type:
		"single", "":
			if alive_foes.size() > 0:
				targets = [alive_foes[randi() % alive_foes.size()]]
		"row":
			var row_idx := randi() % 2
			for t in alive_foes:
				var is_front: bool = t.position < 3
				if (row_idx == 0 and is_front) or (row_idx == 1 and not is_front):
					targets.append(t)
			if targets.is_empty() and alive_foes.size() > 0:
				targets = [alive_foes[0]]
		"column":
			var col_idx := randi() % 3
			for t in alive_foes:
				if t.position % 3 == col_idx:
					targets.append(t)
			if targets.is_empty() and alive_foes.size() > 0:
				targets = [alive_foes[0]]
		"all_enemies", "aoe":
			targets = alive_foes.duplicate()
		"multi":
			var pool = alive_foes.duplicate()
			pool.shuffle()
			targets = pool.slice(0, min(2, pool.size()))
		"self":
			targets = [unit]
		"ally", "ally_single":
			if alive_allies.size() > 0:
				alive_allies.sort_custom(func(a, b): return a.hp < b.hp)
				targets = [alive_allies[0]]
			else:
				targets = [unit]
		"ally_row":
			var row_idx := randi() % 2
			for t in alive_allies:
				var is_front: bool = t.position < 3
				if (row_idx == 0 and is_front) or (row_idx == 1 and not is_front):
					targets.append(t)
			if targets.is_empty():
				targets = [unit]
		_:
			if alive_foes.size() > 0:
				targets = [alive_foes[randi() % alive_foes.size()]]

	if targets.is_empty():
		return {
			"kind": "wait",
			"actor_name": unit.name_zh,
			"actor_side": "enemy" if unit.is_enemy else "player",
		}

	# --- 计算伤害/治疗 ---
	var damage_type: String = skill.get("damage_type", "physical")
	var power: float = float(skill.get("power", 80))
	var hits: int = max(1, int(skill.get("hits", 1)))
	var total_dmg := 0
	var total_heal := 0
	var results: Array = []

	for t in targets:
		var t_dmg := 0
		var t_heal := 0
		if damage_type == "heal":
			t_heal = _calc_heal(unit, power) * hits
			_apply_heal(t, t_heal)
			total_heal += t_heal
		elif damage_type in ["buff", "shield", "debuff", "utility", "special", "summon"]:
			pass
		else:
			for _h in range(hits):
				t_dmg += _calc_damage(unit, t, power, damage_type)
			_apply_damage(unit, t, t_dmg)
			total_dmg += t_dmg
		results.append({
			"name": t.name_zh,
			"side": "player" if not t.is_enemy else "enemy",
			"damage": t_dmg,
			"heal": t_heal,
			"hp": t.hp,
			"max_hp": t.max_hp,
			"alive": t.is_alive,
		})

	var primary: Dictionary = results[0]

	# --- 尝试触发被动技能 ---
	var pp_cost := 0
	var passive_name := ""
	if unit.pp >= 1 and passive_skills.size() > 0 and randi() % 100 < 30:
		var psk = passive_skills[randi() % passive_skills.size()]
		pp_cost = psk.get("pp_cost", 1)
		if pp_cost <= unit.pp:
			unit.pp -= pp_cost
			passive_name = psk.get("name_en", psk.get("name_zh", ""))

	# --- 构建行动字典 ---
	return {
		"kind": "attack",
		"actor_name": unit.name_zh,
		"actor_side": "enemy" if unit.is_enemy else "player",
		"skill_name": skill.get("name_zh", skill.get("name_en", "技能")),
		"skill_name_en": skill.get("name_en", ""),
		"ap_cost": ap_cost,
		"pp_cost": pp_cost,
		"passive_name": passive_name,
		"damage_type": damage_type,
		"hits": hits,
		"target_name": primary.name,
		"target_side": primary.side,
		"damage": total_dmg,
		"heal": total_heal,
		"target_hp": primary.hp,
		"target_max_hp": primary.max_hp,
		"target_alive": primary.alive,
		"targets": results,
		"actor_hp": unit.hp,
		"actor_max_hp": unit.max_hp,
		"actor_ap": unit.ap,
		"actor_max_ap": unit.max_ap,
	}


# ==================================================================
#  伤害计算 (Damage Calculation)
# ==================================================================

## ---------------------------------------------------------------------------
## _calc_damage() — 伤害公式
## ---------------------------------------------------------------------------
## 伤害计算公式（当前简化版）：
##
##   base = max(1.0, power/100 * attacker.atk - defender.def * 0.4)
##   base *= 0.85 + random(0, 0.3)     <- 随机浮动 85%~115%
##   final = max(1, int(base))         <- 至少 1 点伤害，取整
##
## 公式解析（Python 风格注释）：
##
##   # 第一项：攻击力部分
##   atk_component = (power / 100.0) * attacker.atk
##   # power 类似于"技能威力百分比"。power=100 表示 100% 攻击力。
##   # power=60 的普通攻击就是攻击力的 60%。
##
##   # 第二项：防御力减伤
##   def_reduction = defender.def * 0.4
##   # 防御力的 40% 用于抵消伤害。系数 0.4 控制防御的收益。
##
##   # 基础伤害
##   base = max(1.0, atk_component - def_reduction)
##   # 确保基础伤害至少为 1，防止防御过高导致伤害归零。
##
##   # 随机浮动
##   base *= 0.85 + randf() * 0.3
##   # randf() 返回 0.0~1.0 之间的随机浮点数。
##   # 0.85 + 0.0~0.3 = 0.85~1.15，即 ±15% 的随机波动。
##
## 注意事项：
##   · 当前公式只使用 atk/def（物理攻击/防御），没有区分物理/魔法伤害。
##   · mag/mdf（魔法攻击/防御）在当前实现中未被使用。
##   · 完整实现中应根据技能 damage_type 选择用 (atk,def) 还是 (mag,mdf)。
##   · acc/eva（命中/回避）、crit（暴击）、guard（格挡）均未实现。
## ---------------------------------------------------------------------------
func _calc_damage(attacker: Dictionary, defender: Dictionary, power: float,
		damage_type: String = "physical") -> int:
	# 根据伤害类型选择攻防属性
	var atk_val: float
	var def_val: float
	match damage_type:
		"magical":
			atk_val = attacker.mag
			def_val = defender.mdf
		"mixed":
			atk_val = (attacker.atk + attacker.mag) / 2.0
			def_val = (defender.def + defender.mdf) / 2.0
		_:
			atk_val = attacker.atk
			def_val = defender.def

	var base = max(1.0, power / 100.0 * atk_val - def_val * 0.4)
	base *= 0.85 + randf() * 0.3
	return max(1, int(base))


## 治疗量 = power% × 施法者mag，浮动 85%~115%
func _calc_heal(caster: Dictionary, power: float) -> int:
	var base: float = power / 100.0 * caster.mag
	base *= 0.85 + randf() * 0.3
	return max(1, int(base))


## 应用治疗，不超过 max_hp
func _apply_heal(target: Dictionary, amount: int) -> void:
	target.hp = min(target.max_hp, target.hp + amount)


## ---------------------------------------------------------------------------
## _apply_damage() — 应用伤害到目标单位
## ---------------------------------------------------------------------------
## 【关键时点：伤害应用 + 死亡检测 + 死亡行动插入】
##
## 这个方法做的事：
##   1. 扣减目标 hp（不低于 0）
##   2. 更新双方的累计伤害统计
##   3. 如果目标死亡：
##      a. 设置 is_alive = false
##      b. 构造一个 death 类型的行动 Dictionary
##      c. 用 push_front() 将 death 行动插入到 _pending_actions 的队首
##
## 为什么 death 行动用 push_front 插到队首？
##
##   假设当前回合的 _turn_order 是 [A, B, C]。
##   A 的行动先被预计算，A 击杀了 C。但因为 C 排在 A 后面，
##   C 的行动已经被预计算并排在 _pending_actions 中。
##
##   _pending_actions（预计算后）: [A的attack, B的attack, C的attack]
##
##   但 A 击杀了 C！所以需要把 C 的死亡动画插入到 A 的攻击之后、
##   B 的攻击之前。push_front 会把 death 行动放到队首：
##
##   _pending_actions（A行动后+死亡插入）: [C的death, B的attack, C的attack]
##
##   等等，push_front 是放到最前面。实际上这里的逻辑是：
##   A 的行动已经通过 next_action() 被取出了（return 给 UI 了），
##   此时 _apply_damage 在 _compute_unit_action 中被调用。
##   所以 push_front 的效果是把 death 放到"下一个待取出"的位置。
##
##   更准确的时间线：
##     1. _start_next_round 预计算所有行动
##        _pending_actions = [A_action, B_action, C_action]
##     2. next_action() 取出 A_action 并返回
##     3. _apply_damage 被调用（A 击杀了 C）
##        C.is_alive = false
##        _pending_actions.push_front(C_death)
##        _pending_actions = [C_death, B_action, C_action]
##     4. 下一次 next_action() 取出 C_death -> 播放死亡动画
##     5. 再下一次 next_action() 取出 B_action
##        B 的 action 原本可能攻击 C，但 next_action 的存活检查
##        发现 B 的目标或 B 自身可能已经死亡...
##
##   所以死亡行动被插入到队首，确保死亡动画在下一个攻击行动之前播放。
##   这是为了 UI 的视觉连贯性——"看到伤害->看到死亡"而不是"看到伤害->
##   看到另一个攻击->看到死亡"。
## ---------------------------------------------------------------------------
func _apply_damage(attacker: Dictionary, target: Dictionary, damage: int) -> void:
	# 扣血（不低于 0）
	target.hp = max(0, target.hp - damage)

	# 更新统计数据
	target.damage_taken += damage
	attacker.damage_dealt += damage

	# --- 死亡检测 ---
	if target.hp <= 0:
		target.is_alive = false

		# 构造死亡行动并插入队列队首
		# push_front — 插入到数组开头（和 push_back 对应）
		# 等效于 Python 的 list.insert(0, item)
		_pending_actions.append({
			"kind": "death",                       # 行动类型：死亡
			"actor_name": target.name_zh,           # "actor" = 死亡的单位
			"actor_side": "enemy" if target.is_enemy else "player",
			"target_name": "",                      # 死亡没有"目标"
			"target_side": "",
			"damage": 0,
			"skill_name": "",
			"target_hp": 0,
			"target_max_hp": target.max_hp,
			"target_alive": false,
			"actor_hp": target.hp,                  # hp 已经为 0
			"actor_max_hp": target.max_hp,
			"actor_ap": 0,
			"actor_max_ap": 0,
		})


# ==================================================================
#  战斗结束判定 (Battle End Check)
# ==================================================================

## ---------------------------------------------------------------------------
## _check_battle_end() — 检查战斗是否结束
## ---------------------------------------------------------------------------
## 【时点：回合结束后检测胜负】
##
## 逻辑很简单：
##   - 如果玩家单位全部阵亡 -> "defeat"（败北）
##   - 如果敌方单位全部阵亡 -> "victory"（胜利）
##   - 其他情况 -> 战斗继续
##
## 当判定胜负后：
##   · battle_active = false（停止 next_action 返回行动）
##   · 发出 battle_ended 信号（UI 收到后停止计时器、显示结果界面）
## ---------------------------------------------------------------------------


func _check_battle_end() -> void:
	# 检查玩家是否还有存活单位
	var player_alive := false
	for u in player_units:
		if u.is_alive:
			player_alive = true
			break

	# 检查敌方是否还有存活单位
	var enemy_alive := false
	for u in enemy_units:
		if u.is_alive:
			enemy_alive = true
			break

	# 判定结果
	if not player_alive:
		battle_active = false
		battle_ended.emit("defeat")
	elif not enemy_alive:
		battle_active = false
		battle_ended.emit("victory")


# ==================================================================
#  战后统计 (Post-Battle Stats)
# ==================================================================

## ---------------------------------------------------------------------------
## get_stats_summary() — 获取战斗统计数据
## ---------------------------------------------------------------------------
## 返回包含双方累计数据的 Dictionary，用于战斗结果界面的统计展示。
##
## 返回结构：
##   {
##     "player": {
##       "total_damage_dealt": 1234,
##       "total_damage_taken": 567,
##       "units": [{name, class, hp, max_hp, damage_dealt, damage_taken, alive}, ...]
##     },
##     "enemy": { ... },
##     "rounds": 5
##   }
## ---------------------------------------------------------------------------
func get_stats_summary() -> Dictionary:
	var player_stats := {"total_damage_dealt": 0, "total_damage_taken": 0, "units": []}
	var enemy_stats := {"total_damage_dealt": 0, "total_damage_taken": 0, "units": []}

	for u in player_units:
		player_stats.total_damage_dealt += u.damage_dealt
		player_stats.total_damage_taken += u.damage_taken
		player_stats.units.append({
			"name": u.name_zh,
			"class": u.class_zh,
			"hp": u.hp, "max_hp": u.max_hp,
			"damage_dealt": u.damage_dealt,
			"damage_taken": u.damage_taken,
			"alive": u.is_alive,
		})

	for u in enemy_units:
		enemy_stats.total_damage_dealt += u.damage_dealt
		enemy_stats.total_damage_taken += u.damage_taken
		enemy_stats.units.append({
			"name": u.name_zh,
			"class": u.class_zh,
			"hp": u.hp, "max_hp": u.max_hp,
			"damage_dealt": u.damage_dealt,
			"damage_taken": u.damage_taken,
			"alive": u.is_alive,
		})

	return {"player": player_stats, "enemy": enemy_stats, "rounds": round_num}


# ==================================================================
#  工具函数
# ==================================================================

## ---------------------------------------------------------------------------
## _safe_int() — 安全地将任意值转换为整数
## ---------------------------------------------------------------------------
## JSON 中的数值可能是字符串格式（如 "120"）、整数或浮点数。
## 这个方法统一处理：提取数字部分，转换为 int。
##
## 参数：
##   val      — 待转换的值（可以是 int、float、String）
##   fallback — 转换失败时的默认值
##
## GDScript 语法：
##   val is int / val is float / val is String
##   `is` 是类型检查运算符。等价于 Python 的 isinstance(val, int)。
##
##   for c in val:  — 遍历字符串的每个字符。和 Python 的 for c in s: 完全一样。
##   c in "0123456789" — GDScript 中 in 可以用于字符串，检查字符是否在字符串中。
## ---------------------------------------------------------------------------
## 解析角色技能：按英文名匹配 skills.json，失败则用默认值兜底
func _resolve_unit_skills(char_data: Dictionary) -> Array:
	var result: Array = []
	for embedded in char_data.get("skills", []):
		result.append(_match_skill(embedded))
	return result


func _match_skill(embedded: Dictionary) -> Dictionary:
	var name := String(embedded.get("name", ""))
	# 在 DataManager.skills 中按 name_en 模糊匹配
	for sk_id in DataManager.skills:
		var sk = DataManager.skills[sk_id]
		if String(sk.get("name_en", "")).to_lower() == name.to_lower():
			var full: Dictionary = sk.duplicate()
			# 类型以角色数据为准
			full["type"] = embedded.get("type", full.get("type", "active"))
			# 主动技能必须消耗至少1AP
			if full["type"] == "active" and full.get("ap_cost", 0) < 1:
				full["ap_cost"] = 1
			return full
	# 未匹配：构建默认技能
	return {
		"name_zh": embedded.get("name", "???"),
		"name_en": embedded.get("name", ""),
		"type": embedded.get("type", "active"),
		"ap_cost": 1, "pp_cost": 0,
		"power": 80, "hits": 1,
		"target_type": "single", "damage_type": "physical",
		"effects": [],
	}


func _safe_int(val, fallback: int = 10) -> int:
	if val is int or val is float:
		return int(val)

	# 如果是字符串，提取其中的数字部分
	if val is String:
		var digits := ""
		for c in val:
			if c in "0123456789":  # GDScript 中 in 可以用于检查子字符串
				digits += c
		if digits != "":
			return int(digits)

	# 转换失败，返回默认值
	return fallback


## ---------------------------------------------------------------------------
## reset() — 清空所有战斗状态
## ---------------------------------------------------------------------------
## 在返回编成界面时调用，确保下次战斗从一个干净的状态开始。
## .clear() 方法清空数组（等价于 Python 的 list.clear()）。
## ---------------------------------------------------------------------------
func reset() -> void:
	battle_active = false
	player_units.clear()
	enemy_units.clear()
	_pending_actions.clear()
	_turn_order.clear()
	_current_turn = 0
	round_num = 0
	_round_done = true
