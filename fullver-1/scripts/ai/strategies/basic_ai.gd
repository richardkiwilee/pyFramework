class_name BasicAI
extends BaseAIStrategy
## =============================================================================
## BasicAI — 内置简单 AI 策略（同时是用户写自定义 AI 的范本）
## =============================================================================
## 决策规则（刻意保持简单，注释解释每一条怎么想、怎么用 ctx）：
##   - on_turn_start：   有钱就征兵（征募成本从 data/resources.json 读）
##   - on_army_phase：   每个有移动力的军团，优先进攻邻接的敌对/中立城市
##                       （命令 "move"，系统校验合法性；无目标则不动）
##   - on_diplomacy_phase：对好感 < -60 的非交战友军宣战（命令 "declare_war"）
##   - on_turn_end：     无操作（预留）
##
## 自定义 AI 的写法 = 复制本文件改决策逻辑 + 改 data/factions.json 挂载。
## =============================================================================


func on_turn_start(ctx: AIContext) -> void:
	# 征兵：资源够且城市数 > 军团数时，在首都（第一座城）征募
	var econ: Dictionary = DataManager.get_economy_config()
	var cost: Dictionary = econ.get("recruit_cost", {})
	if ctx.faction.can_afford(cost):
		# 数据驱动的征募费用足够 → 发征募指令（"recruit" 指令由 P7 接线，
		# 未接线时命令返回 ok=false，不影响流程——这正是指令式设计的容错）
		var my_cities: Array[City] = ctx.my_cities()
		if not my_cities.is_empty():
			var cap_id: String = my_cities[0].id
			ctx.command("recruit", {"city_id": cap_id})


func on_army_phase(ctx: AIContext) -> void:
	# 每个军团独立决策：只动一次（每次移动消耗 1 移动力）
	for army in ctx.my_armies():
		# 已经没有移动力的军团跳过
		if army.move_points <= 0 or not army.can_fight():
			continue
		# 挑目标：优先敌对城市 → 其次中立城市 → 其次敌方势力的城市
		# （get_target 是决策辅助函数，见文件底部）
		var target: City = _pick_adjacent_target(ctx, army)
		if target == null:
			continue
		# 发移动指令。若目标城有敌军，move 处理器会把战斗请求写进
		# ctx.pending_battle，AIController 检测后中断回合流程进入战斗。
		var result: Dictionary = ctx.command("move", {
			"army_id": army.id,
			"target_city_id": target.id,
		})
		if not result.get("ok", false):
			# 移动被系统拒绝（无路/无点数/其他）——本策略不做重试，跳过即可
			continue
		# 发生战斗时 stop 本轮后续军团（战斗结果可能改变局面，
		# 剩下的军团下一回合再动）——AIController 会中断，这里提前返回亦可
		if not ctx.pending_battle.is_empty():
			return


func on_diplomacy_phase(ctx: AIContext) -> void:
	# 外交：好感跌破 -60 且未交战的势力 → 宣战
	for target in ctx.enemy_factions():
		var rel := ctx.relation_to(target.id)
		if rel == null or rel.at_war:
			continue
		if rel.attitude < -60.0:
			# 宣战指令由 DiplomacySystem 校验（P5 接线），
			# 同阵营/已同盟等情况会被拒绝——AI 信任系统的判断
			ctx.command("declare_war", {"target_faction_id": target.id})


## ---------------------------------------------------------------------------
## 决策辅助：为军团挑一个邻接的目标城市
## ---------------------------------------------------------------------------
## 优先级：敌对城市 > 中立城市 > 其他势力的城市。
## 挑不到返回 null（军团不动）。
## ---------------------------------------------------------------------------
func _pick_adjacent_target(ctx: AIContext, army: Army) -> City:
	var best: City = null
	var best_priority := 99  # 越小越优先
	for adj_id in ctx.adjacent_city_ids(army.current_city_id):
		var city := ctx.state.get_city(adj_id)
		if city == null:
			continue
		var owner: String = city.owner_faction_id
		var priority := 99
		if owner != "" and owner != ctx.faction.id:
			# 敌方城市：是否交战决定 0 还是 1
			var rel := ctx.relation_to(owner)
			priority = 0 if (rel != null and rel.at_war) else 1
		elif owner == "":
			priority = 2  # 中立城市（占领扩张）
		else:
			continue  # 自己的城市
		if priority < best_priority:
			best_priority = priority
			best = city
	return best
