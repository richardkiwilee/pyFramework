extends RefCounted
## =============================================================================
## 经济系统测试（docs/00-design.md §12）
## 覆盖：城市产出、回合结算、升级、征募。断言失败 = push_error。
## =============================================================================


func _fail(template: String, ...args: Array) -> void:
	push_error("[test_economy] " + template.format(args, "{}"))


## 造最小状态：玩家 2 城 + 1 军团
func _make_state() -> GameState:
	var gs := GameState.new()
	var p := Faction.new()
	p.id = "player"; p.is_player = true
	p.resources = {"gold": 100, "food": 100, "wood": 50, "horse": 10}
	gs.factions = [p]
	for i in range(2):
		var c := City.new()
		c.id = "c%d" % i; c.owner_faction_id = "player"; c.level = 1
		gs.cities.append(c)
	var a := Army.new()
	a.id = "a0"; a.owner_faction_id = "player"; a.current_city_id = "c0"
	a.team = Team.new()
	gs.armies.append(a)
	return gs


## 城市产出 = 等级 × 每级产出（数据驱动）
func test_city_production() -> void:
	var gs := _make_state()
	var econ := EconomySystem.new(gs)
	var city: City = gs.get_city("c0")
	var prod: Dictionary = econ.get_city_production(city)
	# resources.json: gold 5/级, food 6/级, wood 3/级, horse 1/级；等级 1
	if int(prod.get("gold", 0)) != 5 or int(prod.get("food", 0)) != 6:
		_fail("1 级城产出不对: {}", prod)
	city.level = 3
	prod = econ.get_city_production(city)
	if int(prod.get("gold", 0)) != 15 or int(prod.get("horse", 0)) != 3:
		_fail("3 级城产出不对: {}", prod)


## 回合结算：收入(Σ城产出) − 军费(军团数×每军费用)
func test_settle_turn() -> void:
	var gs := _make_state()
	var econ := EconomySystem.new(gs)
	# 2 城（1 级）+ 1 军团：收入 gold 10，军费 gold 2 → 净 +8
	var before: int = int(gs.player_faction().resources.get("gold", 0))
	var detail: Array = econ.settle_turn()
	var p: Faction = gs.player_faction()
	var income: Dictionary = detail[0]["income"]
	var upkeep: Dictionary = detail[0]["upkeep"]
	if int(income.get("gold", 0)) != 10:
		_fail("两座 1 级城 gold 收入应为 10，实际 {}", income)
	if int(upkeep.get("gold", 0)) != 2:
		_fail("1 军团 gold 军费应为 2，实际 {}", upkeep)
	if int(p.resources.get("gold", 0)) != before + 8:
		_fail("结算后 gold 应为 {}，实际 {}", before + 8, p.resources.get("gold", 0))


## 城市升级：费用/上限/归属校验
func test_upgrade_city() -> void:
	var gs := _make_state()
	var econ := EconomySystem.new(gs)
	var p: Faction = gs.player_faction()
	var city: City = gs.get_city("c0")
	# 资源不足拒绝
	p.resources = {"gold": 0, "wood": 0}
	if econ.upgrade_city(p, city).get("ok", false):
		_fail("资源不足应拒绝升级")
	# 足额成功（升级费 gold 50 + wood 30）
	p.resources = {"gold": 100, "wood": 100}
	var r: Dictionary = econ.upgrade_city(p, city)
	if not r.get("ok", false):
		_fail("资源足够应升级成功: {}", r)
	if city.level != 2 or p.resources["gold"] != 50:
		_fail("升级后等级/资源不对: level={} gold={}", city.level, p.resources["gold"])
	# 上限拒绝
	city.level = 5
	if econ.upgrade_city(p, city).get("ok", false):
		_fail("满级城应拒绝升级")
	# 归属校验
	var enemy := Faction.new(); enemy.id = "ai1"
	if econ.upgrade_city(enemy, city).get("ok", false):
		_fail("非归属城应拒绝升级")


## 征募：费用扣取 + 军团编成 + 一城一军
func test_recruit_army() -> void:
	var gs := _make_state()
	var econ := EconomySystem.new(gs)
	var p: Faction = gs.player_faction()
	# 夹具里 c0 已有军团 a0，征募改在空城 c1
	var city: City = gs.get_city("c1")
	var before_gold: int = int(p.resources.get("gold", 0))
	var r: Dictionary = econ.recruit_army(p, city)
	if not r.get("ok", false):
		_fail("征募应成功: {}", r)
	if int(p.resources.get("gold", 0)) != before_gold - 30:
		_fail("征募应扣 30 金，实际 {} → {}", before_gold, p.resources.get("gold", 0))
	var army: Army = gs.get_army(r.get("army_id", ""))
	if army == null or army.team.unit_count() == 0:
		_fail("征募应生成有编队的军团")
	if city.garrison_army_id != army.id:
		_fail("征募军团应成为驻军")
	# 一城一军：再次征募拒绝
	if econ.recruit_army(p, city).get("ok", false):
		_fail("已有驻军应拒绝再征募")
	# 免费征募（开局用）：不扣资源
	var gs2 := _make_state()
	var econ2 := EconomySystem.new(gs2)
	var p2: Faction = gs2.player_faction()
	var city2: City = gs2.get_city("c1")
	var before2: int = int(p2.resources.get("gold", 0))
	if not econ2.recruit_army(p2, city2, 6, true).get("ok", false):
		_fail("免费征募应成功")
	if int(p2.resources.get("gold", 0)) != before2:
		_fail("免费征募不应扣资源")
