# WeaponDB.gd — Autoload singleton (named `WeaponDB`).
# Static database of 50 weapons. Pure data; Battle/Projectile interpret it.
# A weapon is a Dictionary with at least: id, name, display, type, damage, radius.
# Optional fields are read with .get(key, default) so missing keys are fine.
extends Node
## Catalogue of 50 weapons. Access via `WeaponDB.get_weapon(id)` or `.ALL`.

# Weapon "type" values interpreted by Projectile.gd / Battle.gd:
#  basic     single bullet, explodes on impact
#  cluster   one bullet, splits into N after split_delay
#  roller    bounces/rolls, explodes on timer or when it stops
#  homing    steers toward the nearest enemy tank
#  napalm    on impact creates fire zones + small blast
#  mine      falls, arms on landing, explodes on proximity/timer
#  blackhole on impact creates a gravity well, then a blast
#  laser     instant beam (no travel), damages along a line, digs terrain
#  rain      spawns N bullets from the top of the screen
# Spread is implemented at fire time (Battle spawns N bullets with angle offsets).

const MAX_WEAPONS := 50

static var ALL: Array = []


func _ready() -> void:
	_build()


func _build() -> void:
	ALL.clear()
	# --- Basic shots (1-8) -----------------------------------------------------
	_define(1,   "single_shot",   "Single Shot",    "basic",   20, 18,   {color=Color("ffe27a"), size=4})
	_define(2,   "medium_shot",   "Medium Shot",    "basic",   30, 24,   {color=Color("ffc24a"), size=5})
	_define(3,   "heavy_shot",    "Heavy Shot",     "basic",   45, 32,   {color=Color("ff8a3a"), size=6})
	_define(4,   "mega_shot",     "Mega Shot",      "basic",   60, 44,   {color=Color("ff6a2a"), size=8})
	_define(5,   "tiny_shot",     "Tiny Shot",      "basic",   12, 14,   {color=Color("eaf6ff"), size=3, speed=1.25, weight=0.8})
	_define(6,   "sniper",        "Sniper",         "basic",   38, 16,   {color=Color("d4f0ff"), size=3, speed=1.4, weight=0.7})
	_define(7,   "nuke",         "Nuke",           "basic",   100, 90,   {color=Color("ff3a3a"), size=9, weight=1.3, speed=0.85})
	_define(8,   "piercer",       "Piercer",        "basic",   32, 20,   {color=Color("c0e8ff"), size=4, penetrate=true})
	# --- Spread (fired as N bullets at fire time) (9-14) ----------------------
	_define(9,   "shotgun",       "Shotgun",        "basic",   11, 14,   {color=Color("ffd070"), size=3, spread_count=5, spread=30})
	_define(10,  "spread3",       "Triple Threat",  "basic",   18, 18,   {color=Color("ffd070"), size=3, spread_count=3, spread=20})
	_define(11,  "spread5",       "Five Spread",    "basic",   14, 16,   {color=Color("ffd070"), size=3, spread_count=5, spread=26})
	_define(12,  "spread7",       "Seven Spread",   "basic",   11, 14,   {color=Color("ffd070"), size=3, spread_count=7, spread=34})
	_define(13,  "wide_fan",      "Wide Fan",       "basic",   9,  13,   {color=Color("ffd070"), size=3, spread_count=9, spread=52})
	_define(14,  "double_barrel", "Double Barrel",  "basic",   26, 20,   {color=Color("ffd070"), size=4, spread_count=2, spread=8})
	# --- Cluster (15-20) -----------------------------------------------------
	_define(15,  "cluster",       "Cluster Bomb",   "cluster", 15, 16,   {color=Color("ffcf4a"), size=5, split_count=3, split_delay=0.6})
	_define(16,  "cluster_big",   "Big Cluster",    "cluster", 14, 18,   {color=Color("ff9a3a"), size=6, split_count=5, split_delay=0.65})
	_define(17,  "cluster_7",     "Seven Cluster",  "cluster", 12, 15,   {color=Color("ff7a3a"), size=7, split_count=7, split_delay=0.7})
	_define(18,  "splitter",      "Splitter",       "cluster", 10, 14,   {color=Color("9affd0"), size=5, split_count=2, split_delay=0.5, split_again=true})
	_define(19,  "firework",      "Firework",       "cluster", 10, 12,   {color=Color("ff6ad5"), size=5, split_count=8, split_delay=0.0, split_at_apex=true})
	_define(20,  "annihilation",  "Annihilation",   "cluster", 26, 22,   {color=Color("ff3a6a"), size=8, split_count=6, split_delay=0.55})
	# --- Roller (21-25) -----------------------------------------------------
	_define(21,  "roller",        "Roller",         "roller",  26, 22,   {color=Color("7affc0"), size=6, bouncy=0.55, fuse=4.0})
	_define(22,  "heavy_roller",  "Heavy Roller",   "roller",  40, 30,   {color=Color("3aff9a"), size=7, bouncy=0.4, fuse=4.0, weight=1.2})
	_define(23,  "bouncy_ball",   "Bouncy Ball",    "roller",  22, 18,   {color=Color("7affff"), size=5, bouncy=0.8, fuse=6.0, weight=0.6})
	_define(24,  "pinball",       "Pinball",        "roller",  16, 16,   {color=Color("c0ffff"), size=5, bouncy=0.92, fuse=7.0, weight=0.55})
	_define(25,  "crawler",       "Crawler",        "roller",  24, 20,   {color=Color("a0ff80"), size=6, bouncy=0.3, fuse=5.0, homing=0.6})
	# --- Homing (26-30) -----------------------------------------------------
	_define(26,  "homing",        "Homing Shot",    "homing",  30, 24,   {color=Color("ff7aff"), size=5, homing=1.0})
	_define(27,  "homing_strong", "Strong Homing",  "homing",  26, 22,   {color=Color("ff4aff"), size=5, homing=2.0})
	_define(28,  "homing_cluster","Homing Cluster", "cluster", 14, 16,   {color=Color("ff7aff"), size=6, split_count=3, split_delay=0.5, homing=0.8})
	_define(29,  "guided",        "Guided Missile", "homing",  42, 26,   {color=Color("ff2aef"), size=6, homing=2.6, speed=1.1})
	_define(30,  "seeker",        "Seeker",         "homing",  22, 18,   {color=Color("ffaaff"), size=4, homing=1.4, speed=1.3, weight=0.7})
	# --- Napalm (31-35) -----------------------------------------------------
	_define(31,  "napalm",        "Napalm",         "napalm",  10, 20,   {color=Color("ff5a2a"), size=5, burn_time=4.0, burn_dps=10, burn_zones=6})
	_define(32,  "firebomb",      "Firebomb",       "napalm",  12, 26,   {color=Color("ff3a1a"), size=6, burn_time=5.0, burn_dps=12, burn_zones=9})
	_define(33,  "molotov",       "Molotov",        "napalm",  8,  18,   {color=Color("ff7a3a"), size=4, burn_time=4.0, burn_dps=9,  burn_zones=7})
	_define(34,  "inferno",       "Inferno",        "napalm",  16, 34,   {color=Color("ff2a00"), size=7, burn_time=6.0, burn_dps=16, burn_zones=12})
	_define(35,  "flame_jet",     "Flame Jet",      "napalm",  10, 22,   {color=Color("ff8a3a"), size=5, burn_time=3.5, burn_dps=11, burn_zones=8, spread_count=3, spread=22})
	# --- Mine (36-40) -----------------------------------------------------
	_define(36,  "mine",         "Mine",           "mine",    30, 26,   {color=Color("9a9aff"), size=6, arm_time=1.0, fuse=8.0})
	_define(37,  "mine_field",   "Minefield",      "mine",    24, 22,   {color=Color("9a9aff"), size=5, arm_time=1.0, fuse=8.0, spread_count=3, spread=40})
	_define(38,  "proximity",    "Proximity Mine",  "mine",    34, 30,   {color=Color("6a6aff"), size=6, arm_time=1.2, fuse=10.0, prox=70})
	_define(39,  "timed_mine",   "Timed Mine",      "mine",    30, 26,   {color=Color("5a5aff"), size=6, arm_time=0.4, fuse=3.5})
	_define(40,  "mine_cluster", "Mine Cluster",   "mine",    20, 20,   {color=Color("9a9aff"), size=6, arm_time=1.0, fuse=8.0, split_count=4, split_delay=0.0, split_at_apex=true})
	# --- Black hole (41-44) -------------------------------------------------
	_define(41,  "blackhole",    "Black Hole",     "blackhole",30, 36,   {color=Color("6a0aff").darkened(0.2), size=7, grav=900, grav_time=2.5, grav_radius=200})
	_define(42,  "singularity",  "Singularity",    "blackhole",40, 44,   {color=Color("4a00cc"), size=8, grav=1400, grav_time=3.0, grav_radius=260})
	_define(43,  "vortex",       "Vortex",         "blackhole",26, 30,   {color=Color("aa3aff"), size=6, grav=700, grav_time=2.0, grav_radius=180})
	_define(44,  "collapse",     "Collapse",       "blackhole",20, 24,   {color=Color("7a1aff"), size=5, grav=1100, grav_time=1.6, grav_radius=150})
	# --- Laser / special (45-50) --------------------------------------------
	_define(45,  "laser",        "Laser",          "laser",   28, 10,   {color=Color("ff4040"), laser_width=4})
	_define(46,  "laser_big",    "Big Laser",      "laser",   42, 14,   {color=Color("ff2020"), laser_width=8})
	_define(47,  "railgun",      "Railgun",        "laser",   55, 16,   {color=Color("40d0ff"), laser_width=5, penetrate=true})
	_define(48,  "laser_split",  "Split Laser",    "laser",   24, 10,   {color=Color("ff5050"), laser_width=4, spread_count=3, spread=24})
	_define(49,  "meteor",       "Meteor Shower",  "rain",    30, 26,   {color=Color("ff7a3a"), size=5, spread_count=4, rain_spread=300})
	_define(50,  "airstrike",    "Airstrike",      "rain",    26, 22,   {color=Color("ffd070"), size=4, spread_count=5, rain_spread=340})


func _define(id: int, name: String, display: String, type: String, damage: float, radius: float, extra: Dictionary = {}) -> void:
	var d := {
		"id": id,
		"name": name,
		"display": display,
		"type": type,
		"damage": damage,
		"radius": radius,
	}
	for k in extra.keys():
		d[k] = extra[k]
	# Sensible defaults so callers can read freely
	d.merge({
		"color": Color("ffffff"),
		"size": 5.0,
		"weight": 1.0,
		"speed": 1.0,
		"spread_count": 0,     # >0 means fire N bullets with angle offsets
		"spread": 0.0,         # total fan degrees
		"split_count": 0,
		"split_delay": 0.0,
		"split_again": false,
		"split_at_apex": false,
		"bouncy": 0.0,
		"fuse": 0.0,
		"homing": 0.0,
		"penetrate": false,
		"burn_time": 0.0,
		"burn_dps": 0.0,
		"burn_zones": 0,
		"arm_time": 0.0,
		"prox": 0.0,
		"grav": 0.0,
		"grav_time": 0.0,
		"grav_radius": 0.0,
		"laser_width": 4.0,
		"rain_spread": 0.0,
	}, false) # false = do not overwrite explicit keys
	ALL.append(d)


## Lookup by id (1-based). Returns null if out of range.
func get_weapon(id: int) -> Dictionary:
	if id >= 1 and id <= ALL.size():
		return ALL[id - 1]
	return {}

func get_by_name(n: String) -> Dictionary:
	for d in ALL:
		if d.name == n:
			return d
	return {}

func count() -> int:
	return ALL.size()

## A random weapon id (used for supply-crate pickups that grant a weapon).
func random_id() -> int:
	return (Game.rng.randi() % ALL.size()) + 1
