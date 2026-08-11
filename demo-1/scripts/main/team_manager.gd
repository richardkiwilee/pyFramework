extends Node
## TeamManager - manages player team formations. Attached to main screen.
class_name TeamManager

signal team_changed(team_index: int)
signal unit_selected(char_id: String, team_index: int)

# ------------------------------------------------------------------ team data
var teams: Array = []          # Array[Dictionary] - each team {name, units: Array[String]}
var current_team: int = 0
const MAX_TEAMS := 8
const MAX_UNITS_PER_TEAM := 6


func _init() -> void:
	# Create default team
	_create_default_teams()


func _create_default_teams() -> void:
	# Create 3 empty teams
	for i in range(3):
		teams.append({
			"name": "第%d队" % (i + 1),
			"units": ["", "", "", "", "", ""],  # 6 slots: front 3, back 3
		})


func get_team(idx: int = -1) -> Dictionary:
	if idx < 0:
		idx = current_team
	if idx >= 0 and idx < teams.size():
		return teams[idx]
	return {}


func get_all_assigned_char_ids() -> Array:
	"""Return all character IDs currently assigned to any team."""
	var result: Array = []
	for team in teams:
		for uid in team.units:
			if uid != "" and uid not in result:
				result.append(uid)
	return result


func add_team() -> void:
	if teams.size() >= MAX_TEAMS:
		return
	var num := teams.size() + 1
	teams.append({
		"name": "第%d队" % num,
		"units": ["", "", "", "", "", ""],
	})
	team_changed.emit(teams.size() - 1)


func remove_team(idx: int) -> void:
	if teams.size() <= 1:
		return
	teams.remove_at(idx)
	if current_team >= teams.size():
		current_team = teams.size() - 1
	team_changed.emit(current_team)


func set_unit(team_idx: int, slot: int, char_id: String) -> void:
	if team_idx < 0 or team_idx >= teams.size():
		return
	if slot < 0 or slot >= MAX_UNITS_PER_TEAM:
		return
	teams[team_idx].units[slot] = char_id
	team_changed.emit(team_idx)


func remove_unit(team_idx: int, slot: int) -> void:
	set_unit(team_idx, slot, "")


func get_unit_at(team_idx: int, slot: int) -> String:
	if team_idx < 0 or team_idx >= teams.size():
		return ""
	if slot < 0 or slot >= MAX_UNITS_PER_TEAM:
		return ""
	return teams[team_idx].units[slot]


func get_team_unit_ids(team_idx: int) -> Array:
	"""Return non-empty unit IDs in a team."""
	var result: Array = []
	var team = get_team(team_idx)
	for uid in team.units:
		if uid != "":
			result.append(uid)
	return result


func has_any_units() -> bool:
	for team in teams:
		for uid in team.units:
			if uid != "":
				return true
	return false


func is_slot_front(slot: int) -> bool:
	return slot < 3


func get_slot_row(slot: int) -> int:
	return 0 if slot < 3 else 1
