class_name DistrictSystem
extends RefCounted
## =============================================================================
## 区域系统 —— 《文明 6》式区域定义、放置规则与邻接加成引擎(纯逻辑)
## =============================================================================
## 邻接规则(简化但忠于原作):
## · 学院  科技: 每个相邻山脉 +1;每 2 个相邻区域 +1
## · 圣地  信仰: 每个相邻山脉 +1;每 2 格相邻森林 +1;每 2 个相邻区域 +1
## · 商业  金币: 每条相邻河流 +2;每 2 个相邻区域 +1;每个相邻港口 +1
## · 工业  产能: 每个相邻丘陵 +1;每 2 个相邻区域 +1;每个相邻水渠 +2
## · 剧院  文化: 每 2 个相邻区域 +1
## · 水渠  供水: 自身无产出;为相邻工业区 +2 产能(需邻接城市中心且临河)
## · 港口  金币: 每个相邻城市中心 +2;每 2 个相邻鱼群 +1(需水域且邻接陆地)
## 放置规则:区域必须在城市 3 格内;每类区域每城限建一个;
##           水渠需邻接城市中心且临河;港口只能建在邻接陆地的水域。
## =============================================================================

enum DistrictType {
	NONE = -1, CAMPUS, HOLY_SITE, COMMERCIAL_HUB, INDUSTRIAL_ZONE,
	THEATER_SQUARE, AQUEDUCT, HARBOR,
}

## 邻接要素种类
enum Rule { MOUNTAIN, HILL, WOODS, RIVER_EDGE, DISTRICT, HARBOR_D, AQUEDUCT_D, FISH, CITY_CENTER }


## 一条加成规则:要素每 per 个 → bonus 点
class AdjRule extends RefCounted:
	var kind: Rule = Rule.MOUNTAIN
	var per: int = 1
	var bonus: int = 1
	var label: String = ""


## 区域类型定义(数据驱动,UI 与引擎共用)
class DistrictDef extends RefCounted:
	var id: DistrictType = DistrictType.CAMPUS
	var name: String = ""
	var yield_name: String = ""
	var color: Color = Color.WHITE
	var base_yield: int = 1
	var rules: Array[AdjRule] = []
	var on_water: bool = false
	var needs_city_adj: bool = false
	var needs_river: bool = false
	var note: String = ""


class AdjacencyResult extends RefCounted:
	var total: int = 0
	var lines: Array[String] = []   # 加成明细,如 "每个相邻山脉 ×2 → +2"


class PlaceResult extends RefCounted:
	var ok: bool = true
	var reason: String = ""


var defs: Array[DistrictDef] = []


func _init() -> void:
	defs = [
		_def(DistrictType.CAMPUS, "学院", "科技", Color("4a90d9"), [
			_rule(Rule.MOUNTAIN, 1, 1, "每个相邻山脉"),
			_rule(Rule.DISTRICT, 2, 1, "每 2 个相邻区域"),
		], "依山而建,山脉越多科技加成越高"),
		_def(DistrictType.HOLY_SITE, "圣地", "信仰", Color("e8e0c8"), [
			_rule(Rule.MOUNTAIN, 1, 1, "每个相邻山脉"),
			_rule(Rule.WOODS, 2, 1, "每 2 格相邻森林"),
			_rule(Rule.DISTRICT, 2, 1, "每 2 个相邻区域"),
		], "靠山或临林,静修之地"),
		_def(DistrictType.COMMERCIAL_HUB, "商业中心", "金币", Color("e8c84a"), [
			_rule(Rule.RIVER_EDGE, 1, 2, "每条相邻河流"),
			_rule(Rule.DISTRICT, 2, 1, "每 2 个相邻区域"),
			_rule(Rule.HARBOR_D, 1, 1, "每个相邻港口"),
		], "临河而市,商贸兴旺"),
		_def(DistrictType.INDUSTRIAL_ZONE, "工业区", "生产力", Color("b06a3f"), [
			_rule(Rule.HILL, 1, 1, "每个相邻丘陵"),
			_rule(Rule.DISTRICT, 2, 1, "每 2 个相邻区域"),
			_rule(Rule.AQUEDUCT_D, 1, 2, "每个相邻水渠"),
		], "丘陵开矿、水渠供水,工业勃兴"),
		_def(DistrictType.THEATER_SQUARE, "剧院广场", "文化", Color("b06ac4"), [
			_rule(Rule.DISTRICT, 2, 1, "每 2 个相邻区域"),
		], "与城市肌理共生,文化繁荣"),
		_def(DistrictType.AQUEDUCT, "水渠", "供水", Color("7fc8d8"), [],
			"需邻接城市中心且临河;为相邻工业区提供 +2 生产力", false, true, true),
		_def(DistrictType.HARBOR, "港口", "金币", Color("d97a4a"), [
			_rule(Rule.CITY_CENTER, 1, 2, "每个相邻城市中心"),
			_rule(Rule.FISH, 2, 1, "每 2 个相邻鱼群"),
		], "必须建在水域且邻接陆地", true),
	]


func _rule(kind: Rule, per: int, bonus: int, label: String) -> AdjRule:
	var r := AdjRule.new()
	r.kind = kind
	r.per = per
	r.bonus = bonus
	r.label = label
	return r


func _def(id: DistrictType, name: String, yname: String, color: Color,
		rules: Array[AdjRule], note: String, on_water := false,
		needs_city_adj := false, needs_river := false) -> DistrictDef:
	var d := DistrictDef.new()
	d.id = id
	d.name = name
	d.yield_name = yname
	d.color = color
	d.rules = rules
	d.note = note
	d.on_water = on_water
	d.needs_city_adj = needs_city_adj
	d.needs_river = needs_river
	return d


func get_def(id: int) -> DistrictDef:
	for d in defs:
		if int(d.id) == id:
			return d
	return defs[0]


func get_name(id: int) -> String:
	if id == DistrictType.NONE:
		return "无"
	return get_def(id).name


## 计算在 pos 建造 def_id 的邻接加成(含基础产出)
func adjacency(map: HexMap, def_id: int, pos: Vector2i) -> AdjacencyResult:
	var res := AdjacencyResult.new()
	var def := get_def(def_id)
	var counts: Dictionary[int, int] = {}
	for d in HexCore.DIRS:
		var n := pos + d
		if not map.tiles.has(n):
			continue
		var t := map.tiles[n]
		if t.elevation >= HexCore.MOUNTAIN:
			counts[Rule.MOUNTAIN] = int(counts.get(Rule.MOUNTAIN, 0)) + 1
		if t.elevation == HexCore.HILL:
			counts[Rule.HILL] = int(counts.get(Rule.HILL, 0)) + 1
		if t.has_woods:
			counts[Rule.WOODS] = int(counts.get(Rule.WOODS, 0)) + 1
		if map.is_river_edge(pos, n):
			counts[Rule.RIVER_EDGE] = int(counts.get(Rule.RIVER_EDGE, 0)) + 1
		if t.is_city_center or t.district != DistrictType.NONE:
			counts[Rule.DISTRICT] = int(counts.get(Rule.DISTRICT, 0)) + 1
		if t.district == DistrictType.HARBOR:
			counts[Rule.HARBOR_D] = int(counts.get(Rule.HARBOR_D, 0)) + 1
		if t.district == DistrictType.AQUEDUCT:
			counts[Rule.AQUEDUCT_D] = int(counts.get(Rule.AQUEDUCT_D, 0)) + 1
		if t.has_fish:
			counts[Rule.FISH] = int(counts.get(Rule.FISH, 0)) + 1
		if t.is_city_center:
			counts[Rule.CITY_CENTER] = int(counts.get(Rule.CITY_CENTER, 0)) + 1
	if def.base_yield > 0:
		res.total += def.base_yield
		res.lines.append("基础产出 +%d" % def.base_yield)
	for rule in def.rules:
		var c: int = int(counts.get(rule.kind, 0))
		var b := c / rule.per * rule.bonus
		if b > 0:
			res.total += b
			res.lines.append("%s ×%d → +%d" % [rule.label, c, b])
	return res


## 放置规则校验
func can_place(map: HexMap, def_id: int, pos: Vector2i) -> PlaceResult:
	var res := PlaceResult.new()
	var def := get_def(def_id)
	if not map.tiles.has(pos):
		res.ok = false
		res.reason = "超出地图范围"
		return res
	var t := map.tiles[pos]
	if HexCore.hex_distance(map.city_coord, pos) > 3:
		res.ok = false
		res.reason = "超出城市 3 格范围"
		return res
	if def.on_water:
		if t.terrain != HexMap.Terrain.OCEAN:
			res.ok = false
			res.reason = "港口必须建在水域"
		elif not map.has_land_neighbor(pos):
			res.ok = false
			res.reason = "港口必须邻接陆地"
		return res
	if t.is_city_center:
		res.ok = false
		res.reason = "城市中心不能建造区域"
		return res
	if t.terrain == HexMap.Terrain.OCEAN:
		res.ok = false
		res.reason = "海洋地块不能建造区域"
		return res
	if t.elevation >= HexCore.MOUNTAIN:
		res.ok = false
		res.reason = "山脉不可建造区域"
		return res
	if t.district != DistrictType.NONE:
		res.ok = false
		res.reason = "该地块已有区域"
		return res
	if _has_built(map, def_id):
		res.ok = false
		res.reason = "该区域已建造(每城限建一个)"
		return res
	if def.needs_city_adj and HexCore.hex_distance(map.city_coord, pos) != 1:
		res.ok = false
		res.reason = "水渠必须邻接城市中心"
		return res
	if def.needs_river and map.adjacent_river_count(pos) == 0:
		res.ok = false
		res.reason = "水渠必须临河"
		return res
	return res


## 执行建造(砍掉森林腾出空地,文明 6 传统)
func place(map: HexMap, def_id: int, pos: Vector2i) -> void:
	var t := map.tiles[pos]
	t.district = def_id
	t.has_woods = false


func _has_built(map: HexMap, def_id: int) -> bool:
	for coord in map.tiles:
		if map.tiles[coord].district == def_id:
			return true
	return false
