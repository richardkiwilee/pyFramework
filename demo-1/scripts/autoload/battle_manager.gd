extends Node
## BattleManager - Autoload singleton. Manages battle state, processes one action at a time.

signal battle_started()
signal battle_ended(result: String)  # "victory" or "defeat"
signal battle_action(action: Dictionary)  # emitted for UI to animate
signal round_started(round_num: int)

# ------------------------------------------------------------------ battle state
var player_units: Array = []
var enemy_units: Array = []
var round_num: int = 0
var battle_active: bool = false

# Turn queue: actions to play one-by-one
var _pending_actions: Array = []
var _turn_order: Array = []
var _current_turn: int = 0
var _round_done: bool = true


# ------------------------------------------------------------------ unit state factory
func create_battle_unit(char_id: String, is_enemy: bool = false) -> Dictionary:
	var char_data = DataManager.get_character(char_id)
	var class_data = DataManager.classes.get(char_data.get("class_id", ""), {})
	var base_stats = char_data.get("base_stats", {})
	var lv50 = char_data.get("level_50_stats", {})
	if base_stats == null: base_stats = {}
	if lv50 == null: lv50 = {}

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

	return {
		"char_id": char_id,
		"name_zh": char_data.get("name_zh", "???"),
		"name_en": char_data.get("name_en", "???"),
		"class_zh": char_data.get("class_zh", ""),
		"class_id": class_data.get("id", ""),
		"max_hp": int(_hp), "hp": int(_hp),
		"atk": int(_atk), "def": int(_def),
		"mag": int(_mag), "mdf": int(_mdf),
		"spd": int(_spd), "acc": int(_acc), "eva": int(_eva),
		"crit": int(_l5.get("Critical Rate", 10)),
		"guard": int(_l5.get("Guard Rate", 10)),
		"ap": class_data.get("base_ap", 1),
		"max_ap": class_data.get("base_ap", 1),
		"pp": class_data.get("base_pp", 1),
		"max_pp": class_data.get("base_pp", 1),
		"skills": char_data.get("skills", []),
		"is_enemy": is_enemy,
		"is_alive": true,
		"equipment": {},
		"position": 0,
		"statuses": [],
		"damage_dealt": 0,
		"damage_taken": 0,
	}


func equip_random_for_unit(unit: Dictionary) -> void:
	var class_id = unit.get("class_id", "")
	var weapon_subs = DataManager.get_class_weapon_subtypes(class_id)
	if weapon_subs.size() > 0:
		var wp = DataManager.get_random_equipment_for_slot(weapon_subs[0], 1)
		if wp.size() > 0:
			unit.equipment["weapon"] = wp[0]
			var eq = DataManager.get_equipment(wp[0])
			var st = eq.get("stats", {})
			unit.atk += st.get("atk", 0)
			unit.mag += st.get("mag", 0)
			unit.def += st.get("def", 0)
			unit.mdf += st.get("mdf", 0)
			unit.spd += st.get("spd", 0)
			var hp_bonus = st.get("hp", 0)
			unit.hp += hp_bonus
			unit.max_hp += hp_bonus

	var shield_subs = DataManager.get_class_armor_subtypes(class_id)
	if shield_subs.size() > 0:
		var sh = DataManager.get_random_equipment_for_slot(shield_subs[0], 1)
		if sh.size() > 0:
			unit.equipment["shield"] = sh[0]


# ------------------------------------------------------------------ battle flow
func start_battle(player_team_ids: Array) -> void:
	battle_active = true
	round_num = 0
	_pending_actions.clear()
	_turn_order.clear()
	_current_turn = 0

	player_units.clear()
	for i in range(player_team_ids.size()):
		var uid = player_team_ids[i]
		if uid == "":
			continue
		var unit = create_battle_unit(uid, false)
		unit.position = i
		equip_random_for_unit(unit)
		player_units.append(unit)

	var enemy_char_ids = DataManager.get_random_characters(player_units.size(), player_team_ids)
	enemy_units.clear()
	for i in range(enemy_char_ids.size()):
		var unit = create_battle_unit(enemy_char_ids[i], true)
		unit.position = i
		equip_random_for_unit(unit)
		enemy_units.append(unit)


func begin_combat() -> void:
	battle_started.emit()
	_start_next_round()


func _start_next_round() -> void:
	if not battle_active:
		return
	round_num += 1
	round_started.emit(round_num)

	# Reset AP/PP
	for u in player_units + enemy_units:
		if u.is_alive:
			u.ap = u.max_ap
			u.pp = u.max_pp

	# Build turn order sorted by speed desc
	_turn_order.clear()
	var all_units = player_units + enemy_units
	all_units.sort_custom(func(a, b): return a.spd > b.spd)
	for u in all_units:
		if u.is_alive:
			_turn_order.append(u)
	_current_turn = 0

	# Pre-compute all actions for this round
	_pending_actions.clear()
	for u in _turn_order:
		if not u.is_alive:
			continue
		var action = _compute_unit_action(u)
		if not action.is_empty():
			_pending_actions.append(action)

	_round_done = false


func next_action() -> Dictionary:
	"""Called by battle scene timer. Returns one action at a time, or {} when done."""
	if not battle_active:
		return {}

	# If we have pending actions in the queue, return the next one
	if _pending_actions.size() > 0:
		return _pending_actions.pop_front()

	# Queue empty but round still going — check battle end before next round
	if not _round_done:
		_round_done = true
		_check_battle_end()
		if not battle_active:
			return {}  # battle ended during check
		# Start next round
		_start_next_round()
		var act = {} if _pending_actions.is_empty() else _pending_actions.pop_front()
		return act

	return {}


func _compute_unit_action(unit: Dictionary) -> Dictionary:
	var targets = enemy_units if not unit.is_enemy else player_units
	var alive_targets: Array = []
	for t in targets:
		if t.is_alive:
			alive_targets.append(t)

	if alive_targets.is_empty():
		return {}

	if unit.ap <= 0:
		var target = alive_targets[0]
		var dmg = _calc_damage(unit, target, 60)
		_apply_damage(unit, target, dmg)
		return {
			"kind": "attack",
			"actor_name": unit.name_zh,
			"actor_side": "enemy" if unit.is_enemy else "player",
			"target_name": target.name_zh,
			"target_side": "player" if unit.is_enemy else "enemy",
			"damage": dmg,
			"skill_name": "普通攻击",
			"target_hp": target.hp,
			"target_max_hp": target.max_hp,
			"target_alive": target.is_alive,
			"actor_hp": unit.hp,
			"actor_max_hp": unit.max_hp,
			"actor_ap": unit.ap,
			"actor_max_ap": unit.max_ap,
		}
	else:
		var pwr = 80 + randi() % 40
		var target = alive_targets.pick_random()
		var dmg = _calc_damage(unit, target, pwr)
		unit.ap -= 1
		_apply_damage(unit, target, dmg)
		return {
			"kind": "attack",
			"actor_name": unit.name_zh,
			"actor_side": "enemy" if unit.is_enemy else "player",
			"target_name": target.name_zh,
			"target_side": "player" if unit.is_enemy else "enemy",
			"damage": dmg,
			"skill_name": "技能攻击",
			"target_hp": target.hp,
			"target_max_hp": target.max_hp,
			"target_alive": target.is_alive,
			"actor_hp": unit.hp,
			"actor_max_hp": unit.max_hp,
			"actor_ap": unit.ap,
			"actor_max_ap": unit.max_ap,
		}


func _calc_damage(attacker: Dictionary, defender: Dictionary, power: float) -> int:
	var atk_val = attacker.atk
	var def_val = defender.def
	var base = max(1.0, power / 100.0 * atk_val - def_val * 0.4)
	base *= 0.85 + randf() * 0.3
	return max(1, int(base))


func _apply_damage(attacker: Dictionary, target: Dictionary, damage: int) -> void:
	target.hp = max(0, target.hp - damage)
	target.damage_taken += damage
	attacker.damage_dealt += damage
	if target.hp <= 0:
		target.is_alive = false
		# Also emit death as an extra action for animation
		_pending_actions.push_front({
			"kind": "death",
			"actor_name": target.name_zh,
			"actor_side": "enemy" if target.is_enemy else "player",
			"target_name": "",
			"target_side": "",
			"damage": 0,
			"skill_name": "",
			"target_hp": 0,
			"target_max_hp": target.max_hp,
			"target_alive": false,
			"actor_hp": target.hp,
			"actor_max_hp": target.max_hp,
			"actor_ap": 0,
			"actor_max_ap": 0,
		})


func _check_battle_end() -> void:
	var player_alive := false
	for u in player_units:
		if u.is_alive:
			player_alive = true
			break
	var enemy_alive := false
	for u in enemy_units:
		if u.is_alive:
			enemy_alive = true
			break

	if not player_alive:
		battle_active = false
		battle_ended.emit("defeat")
	elif not enemy_alive:
		battle_active = false
		battle_ended.emit("victory")


func get_stats_summary() -> Dictionary:
	"""Return battle statistics for summary display."""
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


func reset() -> void:
	battle_active = false
	player_units.clear()
	enemy_units.clear()
	_pending_actions.clear()
	_turn_order.clear()
	_current_turn = 0
	round_num = 0
	_round_done = true
