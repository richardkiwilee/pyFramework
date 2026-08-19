class_name Army
extends RefCounted
## =============================================================================
## Army — 军团（战略层大地图上的可移动单位容器）
## =============================================================================
## 领域术语见 CONTEXT.md：军团内含一支编队（Team），沿据点图路线移动。
##
## 职责：
##   - 保存所属势力、当前所在城市、移动力
##   - 移动本身由 WorldMapModel 执行（校验路线/点数），本类只存状态
##
## 类比 Python：dataclass + 少量查询方法，纯数据无引擎依赖。
## =============================================================================

## 唯一 ID（运行期生成，如 "army_1"）
var id: String = ""

## 所属势力 ID（data/factions.json 的 id）
var owner_faction_id: String = ""

## 当前所在城市 ID（data/world/map.json 的 id）
var current_city_id: String = ""

## 本回合剩余移动力（每沿一条路线移动一次消耗 1 点）
var move_points: int = 0

## 每回合开始时的满移动力（数据驱动，见 data/factions.json 的 army_move_points）
var max_move_points: int = 2

## 编队（3×3）
var team: Team


func _init() -> void:
	# 空编队兜底：确保 team 永远非 null（战斗/编成界面可以安全访问）
	team = Team.new()


## 军团是否还有战斗力（编队非空）
func can_fight() -> bool:
	return team != null and not team.is_empty()


## 消耗 1 点移动力；没点数返回 false
func spend_move_point() -> bool:
	if move_points <= 0:
		return false
	move_points -= 1
	return true


## 每回合开始回满移动力（TurnManager 调用）
func refresh_move_points() -> void:
	move_points = max_move_points


## ---------------------------------------------------------------------------
## 序列化（存档用）
## ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner_faction_id": owner_faction_id,
		"current_city_id": current_city_id,
		"move_points": move_points,
		"max_move_points": max_move_points,
		"team": team.to_dict() if team != null else {"units": [], "captain": ""},
	}


static func from_dict(d: Dictionary) -> Army:
	var a := Army.new()
	a.id = d.get("id", "")
	a.owner_faction_id = d.get("owner_faction_id", "")
	a.current_city_id = d.get("current_city_id", "")
	a.move_points = int(d.get("move_points", 0))
	a.max_move_points = int(d.get("max_move_points", 2))
	# Team 自包含单位数据（见 Team.to_dict 的设计说明）
	a.team = Team.from_dict(d.get("team", {}))
	return a
