## AI：贪心启发式（对应 pydemo/game/ai.py）。
## 规则：补经济 → 学科技/文化 → 招英雄 → 重建兜底 → 上场 → 招兵 → 移动进攻。
## 返回动作列表 [(kind, payload)]，由 Game 执行。
class_name Ai
extends RefCounted

## 生成 AI 本回合动作列表。
static func ai_take_turn(faction: Faction.Faction_, game) -> Array:
	var actions: Array = []
	if not faction.alive:
		return actions
	var capital = game.map.strongholds.get(faction.capital_id) if faction.capital_id != "" else null

	# 1. 在己方据点空槽建建筑（产出免门控；recruit/special 需 requires 已学）
	for sid in faction.stronghold_ids:
		var sh: Variant = game.map.strongholds.get(sid)
		if sh == null or sh.free_slots() <= 0:
			continue
		for bid in game.building_defs:
			var bdef: Dictionary = game.building_defs[bid]
			var kind: String = bdef.get("kind", "")
			if kind not in ["produce", "recruit", "special"]:
				continue
			var requires: Array = bdef.get("requires", [])
			if not requires.is_empty():
				var learned: Array = []
				learned.append_array(faction.tech_learned)
				learned.append_array(faction.culture_learned)
				var ok := true
				for r in requires:
					if not learned.has(r):
						ok = false
						break
				if not ok:
					continue
			var cost: Dictionary = bdef.get("cost", {})
			if faction.resources.can_afford(cost):
				actions.append({"kind": "build", "stronghold": sid, "building": bid})
				break

	# 1.5 学习科技/文化（各一条）
	var learned_all: Array = []
	learned_all.append_array(faction.tech_learned)
	learned_all.append_array(faction.culture_learned)
	for tid in game.tech_defs:
		if faction.tech_learned.has(tid):
			continue
		var tdef: Dictionary = game.tech_defs[tid]
		var prereqs: Array = tdef.get("prereqs", [])
		var ok := true
		for p in prereqs:
			if not learned_all.has(p):
				ok = false
				break
		if ok and faction.resources.can_afford(tdef.get("cost", {})):
			actions.append({"kind": "learn_tech", "tech": tid})
			break
	for cid in game.culture_defs:
		if faction.culture_learned.has(cid):
			continue
		var cdef: Dictionary = game.culture_defs[cid]
		var prereqs: Array = cdef.get("prereqs", [])
		var ok := true
		for p in prereqs:
			if not learned_all.has(p):
				ok = false
				break
		if ok and faction.resources.can_afford(cdef.get("cost", {})):
			actions.append({"kind": "learn_culture", "culture": cid})
			break

	# 2. 招英雄（信念 + 资源）
	for sid in faction.stronghold_ids:
		var pool: Variant = faction.recruitment_pools.get(sid)
		if pool == null or pool.offerings.is_empty():
			continue
		var has_offer := false
		for hid in pool.offerings:
			if hid != null:
				has_offer = true
				break
		if not has_offer:
			continue
		for hid in pool.offerings:
			if hid == null:
				continue
			var hdef: Variant = game.hero_defs.get(hid)
			if hdef == null:
				continue
			if not Heroes.meets_belief_req(faction.belief, hdef.belief_req):
				continue
			if faction.resources.can_afford(hdef.recruit_cost):
				actions.append({"kind": "recruit_hero", "stronghold": sid, "hero": hid})
				break

	# 2.5 重建兜底：无部队但有待命·可用英雄 → 首都新建部队
	var player_armies: Array = []
	for aid in faction.army_ids:
		if game.armies.has(aid):
			player_armies.append(game.armies[aid])
	if player_armies.is_empty():
		var node_id: String = faction.capital_id
		if node_id != "" and faction.stronghold_ids.has(node_id):
			var hero: Variant = null
			for uid in faction.standby_available_ids():
				var u: Variant = game.unit_index.get(uid)
				if u != null and u.is_hero and u.alive:
					hero = u
					break
			if hero != null:
				actions.append({"kind": "new_army", "stronghold": node_id,
					"hero": hero.id, "name": "%s的部队" % hero.name})

	# 2.6 上场：待命·可用单位派进己方据点内部队（占用升序）
	var avail_ids := faction.standby_available_ids()
	if not avail_ids.is_empty():
		for army in player_armies:
			if not faction.stronghold_ids.has(army.node_id):
				continue
			if not army.grid.has(null):
				continue
			var cands: Array = []
			for uid in avail_ids:
				var u: Variant = game.unit_index.get(uid)
				if u != null and u.alive:
					cands.append([u, uid])
			cands.sort_custom(func(a, b): return a[0].occupy() < b[0].occupy())
			for pair in cands:
				var u = pair[0]
				if army.can_add(u, game.unit_index):
					actions.append({"kind": "deploy", "army": army.id, "unit": u.id})
					break   # 一支部队本回合先派一个

	# 2.7 招普通兵（全局存在性 + 资源）
	for bid in game.building_defs:
		var bdef: Dictionary = game.building_defs[bid]
		var recruits: Array = bdef.get("recruits", [])
		if recruits.is_empty():
			continue
		var has_building := false
		for sid in faction.stronghold_ids:
			var sh: Variant = game.map.strongholds.get(sid)
			if sh == null:
				continue
			for b in sh.buildings:
				if b.type_id == bid:
					has_building = true
					break
			if has_building:
				break
		if not has_building:
			continue
		for tid in recruits:
			var ut: Variant = game.unit_type_defs.get(tid)
			if ut == null:
				continue
			if faction.resources.can_afford(ut.recruit_cost):
				actions.append({"kind": "recruit_unit", "unit": tid})
				break
		break   # 本回合先处理第一个可招兵种

	# 3 & 5. 移动进攻：BFS 朝敌方首都推进
	var enemy_capital := ""
	for fid in game.factions:
		if fid == faction.id:
			continue
		var f: Faction.Faction_ = game.factions[fid]
		if f.capital_id != "" and f.alive:
			enemy_capital = f.capital_id
			break
	var dist := _bfs_distances(game, enemy_capital) if enemy_capital != "" else {}

	for aid in faction.army_ids:
		var army: Variant = game.armies.get(aid)
		if army == null or army.is_wiped(game.unit_index):
			continue
		if army.has_acted_this_turn:
			continue
		var node: String = army.node_id
		var nbrs: Array = game.map.neighbors(node)
		# 优先：邻接的敌方/中立据点直接进攻（首都最优先）
		var target := ""
		for n in nbrs:
			if game.map.strongholds.has(n):
				var sh: Variant = game.map.strongholds[n]
				if sh.owner != faction.id:
					target = n
					if n == enemy_capital:
						break
		if target != "":
			actions.append({"kind": "move_attack", "army": aid, "to": target})
			continue
		# 朝敌方首都方向移动（选距离更小的邻接点）
		if nbrs.is_empty():
			continue
		var cur_d: int = dist.get(node, 1000000000)
		var best := ""
		var best_d := cur_d
		for n in nbrs:
			var nd: int = dist.get(n, 1000000000)
			if nd < best_d:
				best_d = nd
				best = n
		if best == "":
			for n in nbrs:
				var sh: Variant = game.map.strongholds.get(n)
				if sh == null or sh.owner != faction.id:
					best = n
					break
			if best == "":
				best = nbrs[0]
		actions.append({"kind": "move_attack", "army": aid, "to": best})

	return actions

## 从 target_node 出发 BFS 距离表。
static func _bfs_distances(game, target_node: String) -> Dictionary:
	var dist: Dictionary = {target_node: 0}
	var q: Array = [target_node]
	var qi := 0
	while qi < q.size():
		var cur: String = q[qi]
		qi += 1
		for n in game.map.neighbors(cur):
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				q.append(n)
	return dist
