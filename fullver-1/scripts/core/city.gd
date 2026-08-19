class_name City
extends RefCounted
## =============================================================================
## City — 城市（大地图据点图上的节点）
## =============================================================================
## 领域术语见 CONTEXT.md：城市产出资源、可驻守军团、可被占领。
##
## 职责：
##   - 保存归属势力、等级、驻军
##   - 产出计算由 EconomySystem 执行（本类只存状态）
##
## 类比 Python：dataclass，无引擎依赖。
## =============================================================================

## 城市 ID（data/world/map.json 的 id，如 "roma"）
var id: String = ""

## 显示名（中文/英文，来自地图数据）
var name_zh: String = ""
var name_en: String = ""

## 地图逻辑坐标（demo-2 坐标系的 x/y）
var x: float = 0.0
var y: float = 0.0

## 城市类型：holy（圣城）/ great（大城）/ port（港口）/ land（内陆）
## 决定地图上的圆点颜色与图标（ArtIndex 按类型取）
var type: String = "land"

## 归属势力 ID；空串 = 中立城市
var owner_faction_id: String = ""

## 城市等级（1~max_city_level，数据见 resources.json）
var level: int = 1

## 驻守军团 ID（可空串 = 无驻军）
var garrison_army_id: String = ""


## 是否为中立城市（无归属）
func is_neutral() -> bool:
	return owner_faction_id == ""


## 归属变更（被占领/被解放）
func set_owner(faction_id: String) -> void:
	owner_faction_id = faction_id


## ---------------------------------------------------------------------------
## 序列化（存档用）
## ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name_zh": name_zh,
		"name_en": name_en,
		"x": x,
		"y": y,
		"type": type,
		"owner_faction_id": owner_faction_id,
		"level": level,
		"garrison_army_id": garrison_army_id,
	}


static func from_dict(d: Dictionary) -> City:
	var c := City.new()
	c.id = d.get("id", "")
	c.name_zh = d.get("name_zh", "")
	c.name_en = d.get("name_en", "")
	c.x = float(d.get("x", 0.0))
	c.y = float(d.get("y", 0.0))
	c.type = d.get("type", "land")
	c.owner_faction_id = d.get("owner_faction_id", "")
	c.level = int(d.get("level", 1))
	c.garrison_army_id = d.get("garrison_army_id", "")
	return c
