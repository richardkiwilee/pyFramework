extends Node
class_name TeamManager
## =============================================================================
## TeamManager — 队伍编成数据层（由 MainScreen 创建，非 Autoload）
## =============================================================================
## 作用：维护所有队伍的数据（每队最多9个角色，最多8支队伍）。
##       通过信号 team_changed 通知 UI 刷新。
##
## 队伍结构（老虎机滚轮棋盘版，对标网页版队伍编成）：
##   {
##     "name": "第1队",            # 队伍名称
##     "units": ["", "", ...],     # 长度为 9 的数组，每个元素是角色ID或空字符串
##     "captain": "char_id"        # 队长角色ID（"" = 无队长）
##   }
##
##   units 数组的索引含义（3×3 九宫格，slot = r*3 + c）：
##     slot 0,1,2 → 第0行（后排，棋盘顶部）
##     slot 3,4,5 → 第1行（中排）
##     slot 6,7,8 → 第2行（前排，棋盘底部）
##
##   棋盘布局示意（菱形等距视角，从玩家角度看）：
##              [slot0] [slot1] [slot2]
##           [slot3] [slot4] [slot5]
##        [slot6] [slot7] [slot8]     ← 离敌人近（前排）
## =============================================================================

# ------------------------------------------------------------------ 信号
## 队伍数据变更时发出。team_index 是变更的队伍索引。
## 信号是 Godot 的观察者模式实现：一处 emit，多处 connect 监听。
## 类比 Python：类似于 Qt 的 signal/slot 或 blinker 库的信号机制。
signal team_changed(team_index: int)
## 某个角色被选中时发出（预留，当前未使用）
signal unit_selected(char_id: String, team_index: int)

# ------------------------------------------------------------------ 队伍数据

## teams 是核心数据结构：Array[Dictionary]，每个元素代表一支队伍。
## 详细结构见文件头注释。
var teams: Array = []

## 当前选中的队伍索引（在 UI 中高亮显示）
var current_team: int = 0

## 常量定义
const MAX_TEAMS := 8          # 最多 8 支队伍
const MAX_UNITS_PER_TEAM := 9 # 每队最多 9 个角色（3×3 九宫格）
const ROWS := 3               # 棋盘行数
const COLS := 3               # 棋盘列数
const CENTER_SLOT := 4        # 中心格 slot（r=1, c=1）


## ---------------------------------------------------------------------------
## _init() — Godot 对象构造函数
## ---------------------------------------------------------------------------
## 创建 3 支默认空队伍。注意：这里不碰 DataManager——
## 默认队伍的随机预填充由 MainScreen._ready 调用 prefill_default_teams() 完成
## （Autoload 的 _ready 先于主场景执行，数据此时已加载）。
## ---------------------------------------------------------------------------
func _init() -> void:
	_create_default_teams()


func _create_default_teams() -> void:
	for i in range(3):
		teams.append({
			"name": "第%d队" % (i + 1),
			"units": _empty_units(),
			"captain": "",
		})


## 构造一个 9 槽全空的 units 数组
func _empty_units() -> Array:
	var units: Array = []
	for i in range(MAX_UNITS_PER_TEAM):
		units.append("")
	return units


## ---------------------------------------------------------------------------
## prefill_default_teams() — 为默认空队伍随机预填充角色
## ---------------------------------------------------------------------------
## 开局效果对齐网页版：每支默认队伍 3 名角色（中排）+ 队长。
## 幂等：已有单位的队伍不覆盖（防止清掉恢复的战斗数据）。
## ---------------------------------------------------------------------------
func prefill_default_teams() -> void:
	if DataManager.characters.is_empty():
		return  # 数据未加载时防御
	var assigned: Array = []
	for team in teams:
		if _team_has_units(team):
			continue  # 已有单位的队伍不覆盖
		var picks: Array = DataManager.get_random_characters(3, assigned)
		for p in picks:
			assigned.append(p)
		# 放在中排（slot 3/4/5），队长居中——对齐网页版开局阵型
		team.units[3] = picks[0]
		team.units[4] = picks[1]
		team.units[5] = picks[2]
		team.captain = picks[0]
	team_changed.emit(current_team)


func _team_has_units(team: Dictionary) -> bool:
	for uid in team.units:
		if uid != "":
			return true
	return false


## ---------------------------------------------------------------------------
## get_team() — 获取队伍数据
## ---------------------------------------------------------------------------
## 参数 idx: 队伍索引，-1 表示使用 current_team（当前选中队伍）
## 返回: 队伍 Dictionary，索引越界返回空字典 {}
## ---------------------------------------------------------------------------
func get_team(idx: int = -1) -> Dictionary:
	if idx < 0:
		idx = current_team
	if idx >= 0 and idx < teams.size():
		return teams[idx]
	return {}


## ---------------------------------------------------------------------------
## get_all_assigned_char_ids() — 获取所有已编入队伍的角色ID
## ---------------------------------------------------------------------------
## 遍历所有队伍的所有槽位，收集非空角色ID（去重）。
## 用途：计算"待命池"（不属于任何队伍的角色 = 全部 - 已编入）。
## ---------------------------------------------------------------------------
func get_all_assigned_char_ids() -> Array:
	var result: Array = []
	for team in teams:
		for uid in team.units:
			if uid != "" and uid not in result:
				result.append(uid)
	return result


## ---------------------------------------------------------------------------
## add_team() — 新增空队伍
## ---------------------------------------------------------------------------
## 不超过 MAX_TEAMS 限制。新增后发出 team_changed 信号。
## ---------------------------------------------------------------------------
func add_team() -> void:
	if teams.size() >= MAX_TEAMS:
		return
	var num := teams.size() + 1
	teams.append({
		"name": "第%d队" % num,
		"units": _empty_units(),
		"captain": "",
	})
	# 通知 UI 刷新（emit 信号，所有连接了 team_changed 的地方都会收到）
	team_changed.emit(teams.size() - 1)


## ---------------------------------------------------------------------------
## add_team_with_captain() — 以队长为中心创建新队伍
## ---------------------------------------------------------------------------
## 对齐网页版"新增队伍 → 选择队长"流程：
## 队长置于棋盘中心格（slot 4），其余 8 格为空。
## 返回新队伍索引；达到上限返回 -1。
## ---------------------------------------------------------------------------
func add_team_with_captain(char_id: String) -> int:
	if teams.size() >= MAX_TEAMS:
		return -1
	var num := teams.size() + 1
	var units := _empty_units()
	units[CENTER_SLOT] = char_id
	teams.append({
		"name": "新队伍 %d" % num,
		"units": units,
		"captain": char_id,
	})
	team_changed.emit(teams.size() - 1)
	return teams.size() - 1


## ---------------------------------------------------------------------------
## remove_char_from_all_teams() — 将角色从所有队伍中移除
## ---------------------------------------------------------------------------
## 用途：放置待命池角色时确保单位唯一归属（对齐网页版）。
## 若角色是某队队长，队长自动回退到该队首个存活单位。
## ---------------------------------------------------------------------------
func remove_char_from_all_teams(char_id: String) -> void:
	for i in range(teams.size()):
		var units: Array = teams[i].units
		for s in range(units.size()):
			if units[s] == char_id:
				units[s] = ""
		_fix_captain(i)
	team_changed.emit(current_team)


## ---------------------------------------------------------------------------
## remove_team() — 删除队伍
## ---------------------------------------------------------------------------
## 至少保留 1 支队伍。删除后如果 current_team 越界则修正。
## ---------------------------------------------------------------------------
func remove_team(idx: int) -> void:
	if teams.size() <= 1:
		return  # 至少保留一支队伍
	teams.remove_at(idx)  # .remove_at() 类似 Python 的 list.pop(index)
	# 修正当前选中索引
	if current_team >= teams.size():
		current_team = teams.size() - 1
	team_changed.emit(current_team)


## ---------------------------------------------------------------------------
## set_unit() — 将角色放置到指定队伍的指定槽位
## ---------------------------------------------------------------------------
## 参数：
##   team_idx — 队伍索引
##   slot     — 槽位索引 (0-8)
##   char_id  — 角色ID
##
## 如果同一角色被放到不同槽位，会被覆盖（不检查重复）。
## 移除角色（写入 ""）后自动修正队长。
## ---------------------------------------------------------------------------
func set_unit(team_idx: int, slot: int, char_id: String) -> void:
	if team_idx < 0 or team_idx >= teams.size():
		return
	if slot < 0 or slot >= MAX_UNITS_PER_TEAM:
		return
	teams[team_idx].units[slot] = char_id
	if char_id == "":
		_fix_captain(team_idx)
	team_changed.emit(team_idx)


## ---------------------------------------------------------------------------
## remove_unit() — 从槽位移除角色（设为空字符串）
## ---------------------------------------------------------------------------
func remove_unit(team_idx: int, slot: int) -> void:
	set_unit(team_idx, slot, "")


## ---------------------------------------------------------------------------
## get_unit_at() — 获取指定槽位的角色ID
## ---------------------------------------------------------------------------
func get_unit_at(team_idx: int, slot: int) -> String:
	if team_idx < 0 or team_idx >= teams.size():
		return ""
	if slot < 0 or slot >= MAX_UNITS_PER_TEAM:
		return ""
	return teams[team_idx].units[slot]


## ---------------------------------------------------------------------------
## get_unit_at_rc() — 按棋盘行列 (r, c) 获取角色ID
## ---------------------------------------------------------------------------
func get_unit_at_rc(team_idx: int, r: int, c: int) -> String:
	return get_unit_at(team_idx, r * COLS + c)


## ---------------------------------------------------------------------------
## find_unit_cell() — 查找角色在队伍中的格子坐标
## ---------------------------------------------------------------------------
## 返回 Vector2i(r, c)，找不到返回 Vector2i(-1, -1)。
## ---------------------------------------------------------------------------
func find_unit_cell(team_idx: int, char_id: String) -> Vector2i:
	for slot in range(MAX_UNITS_PER_TEAM):
		if get_unit_at(team_idx, slot) == char_id:
			return Vector2i(slot / COLS, slot % COLS)
	return Vector2i(-1, -1)


## ---------------------------------------------------------------------------
## move_unit() — 把角色从 from_slot 移动到 to_slot
## ---------------------------------------------------------------------------
## to_slot 必须为空（调用方保证）。移动后发出 team_changed。
## ---------------------------------------------------------------------------
func move_unit(team_idx: int, from_slot: int, to_slot: int) -> void:
	if team_idx < 0 or team_idx >= teams.size():
		return
	var units: Array = teams[team_idx].units
	if from_slot < 0 or from_slot >= units.size() or to_slot < 0 or to_slot >= units.size():
		return
	units[to_slot] = units[from_slot]
	units[from_slot] = ""
	team_changed.emit(team_idx)


## ---------------------------------------------------------------------------
## swap_units() — 交换两个槽位的角色
## ---------------------------------------------------------------------------
func swap_units(team_idx: int, a_slot: int, b_slot: int) -> void:
	if team_idx < 0 or team_idx >= teams.size():
		return
	var units: Array = teams[team_idx].units
	if a_slot < 0 or a_slot >= units.size() or b_slot < 0 or b_slot >= units.size():
		return
	var tmp = units[a_slot]
	units[a_slot] = units[b_slot]
	units[b_slot] = tmp
	team_changed.emit(team_idx)


## ---------------------------------------------------------------------------
## get_captain() — 获取队伍队长角色ID（"" = 无队长）
## ---------------------------------------------------------------------------
func get_captain(team_idx: int) -> String:
	var team = get_team(team_idx)
	return team.get("captain", "")


## ---------------------------------------------------------------------------
## _fix_captain() — 修正队长：队长不在队中时回退到首个存活单位
## ---------------------------------------------------------------------------
func _fix_captain(team_idx: int) -> void:
	var team: Dictionary = teams[team_idx]
	var cap: String = team.get("captain", "")
	if cap != "" and cap in team.units:
		return  # 队长还在队中，无需修正
	team.captain = _first_unit(team)


## 队伍中第一个非空角色ID（空队返回 ""）
func _first_unit(team: Dictionary) -> String:
	for uid in team.units:
		if uid != "":
			return uid
	return ""


## ---------------------------------------------------------------------------
## normalize_team() — 补齐队伍结构（用于恢复 saved_teams 的旧形状数据）
## ---------------------------------------------------------------------------
## units 不足 9 槽补 ""，缺失 captain 键补上并修正。
## ---------------------------------------------------------------------------
func normalize_team(t: Dictionary) -> void:
	while t.units.size() < MAX_UNITS_PER_TEAM:
		t.units.append("")
	if not t.has("captain"):
		t.captain = _first_unit(t)
	elif t.captain != "" and t.captain not in t.units:
		t.captain = _first_unit(t)


## ---------------------------------------------------------------------------
## get_team_unit_ids() — 获取队伍中所有非空角色ID
## ---------------------------------------------------------------------------
## 用途：开始战斗时，获取出战角色的ID列表传给 BattleManager
## ---------------------------------------------------------------------------
func get_team_unit_ids(team_idx: int) -> Array:
	var result: Array = []
	var team = get_team(team_idx)
	for uid in team.units:
		if uid != "":
			result.append(uid)
	return result


## ---------------------------------------------------------------------------
## has_any_units() — 检查是否至少有一个队伍放置了角色
## ---------------------------------------------------------------------------
## 用途：开始战斗前校验，防止空队伍出战
## ---------------------------------------------------------------------------
func has_any_units() -> bool:
	for team in teams:
		for uid in team.units:
			if uid != "":
				return true
	return false


## ---------------------------------------------------------------------------
## is_slot_front() — 判断槽位是否为前排
## ---------------------------------------------------------------------------
## 3×3 九宫格中 slot 6,7,8 = 前排（棋盘底部，离敌人近）。
## slot 0-5 = 中后排。
## ---------------------------------------------------------------------------
func is_slot_front(slot: int) -> bool:
	return slot >= 6


## ---------------------------------------------------------------------------
## get_slot_row() — 获取槽位所在行号
## ---------------------------------------------------------------------------
## 返回 0（第0行/后排）1（中排）2（前排）
## ---------------------------------------------------------------------------
func get_slot_row(slot: int) -> int:
	return slot / COLS
