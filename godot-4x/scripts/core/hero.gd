## 英雄单位与招募池（对应 pydemo/game/hero.py）。
## 招募需资源 + 信念门槛；每据点独立池，每 14 天刷新 3 个（固定 3 槽不压缩）。
class_name Heroes
extends RefCounted

class HeroDef:
	var id: String
	var name: String
	var tags: Array = []
	var base: Dictionary = {}
	var skills: Array = []
	var recruit_cost: Dictionary = {}
	var belief_req: Dictionary = {}
	var growth: Dictionary = {}
	var maintenance: Dictionary = {}
	var train_cost: Dictionary = {}
	var map_skills: Array = []
	var desc: String = ""

	func _init(id_: String, name_: String, tags_: Array = [], base_: Dictionary = {},
			skills_: Array = [], recruit_cost_: Dictionary = {},
			belief_req_: Dictionary = {}, growth_: Dictionary = {},
			maintenance_: Dictionary = {}, train_cost_: Dictionary = {},
			map_skills_: Array = [], desc_: String = "") -> void:
		id = id_
		name = name_
		tags = tags_.duplicate()
		base = base_
		skills = skills_.duplicate()
		recruit_cost = recruit_cost_
		belief_req = belief_req_
		growth = growth_
		maintenance = maintenance_
		train_cost = train_cost_
		map_skills = map_skills_.duplicate()
		desc = desc_

class RecruitmentPool:
	var stronghold_id: String
	var offerings: Array = []   # 固定 3 槽：hero_def id 或 null
	var refresh_day: int = 1

	func _init(stronghold_id_: String) -> void:
		stronghold_id = stronghold_id_

	## 刷新为 3 个固定槽位；不足 3 个英雄定义时用 null 补足。
	func refresh(all_hero_ids: Array, current_day: int, calendar_period: int = 14, rng: RandomNumberGenerator = null) -> void:
		if rng == null:
			rng = RandomNumberGenerator.new()
			rng.randomize()
		var ids := all_hero_ids.duplicate()
		ids.shuffle()
		var n := mini(3, ids.size())
		offerings = []
		for i in range(3):
			offerings.append(ids[i] if i < n else null)
		refresh_day = current_day + calendar_period

static func load_hero_defs(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for hid in d:
		var h: Dictionary = d[hid]
		out[hid] = HeroDef.new(hid, h["name"],
			h.get("tags", ["melee", "human"]), h.get("base", {}),
			h.get("skills", []), h.get("recruit_cost", {}),
			h.get("belief_req", {}), h.get("growth", {}),
			h.get("maintenance", {}), h.get("train_cost", {}),
			h.get("map_skills", []), h.get("desc", ""))
	return out

## 从英雄定义构造英雄单位实例（id 由调用方重设）。
static func make_hero_unit(hero_def: HeroDef) -> Units.Unit:
	return Units.Unit.new(
		"%s_%d" % [hero_def.id, RandomNumberGenerator.new().randi_range(1000, 9999)],
		hero_def.id, hero_def.name, hero_def.tags.duplicate(),
		hero_def.base.duplicate(), [], true,
		hero_def.skills.duplicate(), [], 0.0, "", 0.0, 0.0, 0.0, 0.0, true,
		{}, "", 1, 0, hero_def.growth.duplicate())

static func meets_belief_req(belief: Economy.Belief, req: Dictionary) -> bool:
	for dim in req:
		if not belief.meets(dim, int(req[dim])):
			return false
	return true

static func describe_req(req: Dictionary) -> String:
	if req.is_empty():
		return "无"
	var parts: Array[String] = []
	for d in req:
		parts.append("%s>=%d" % [Economy.BELIEF_CN.get(d, d), int(req[d])])
	return "、".join(parts)
