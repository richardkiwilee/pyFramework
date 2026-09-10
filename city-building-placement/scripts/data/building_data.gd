extends RefCounted
## 建筑数据：20 种建筑 + 市中心（特殊 tag），全部数值集中在此单文件，可随时调整。

const TerrainData := preload("res://scripts/data/terrain_data.gd")

enum Res { GOLD, WOOD, FOOD, STONE }

const RES_NAMES: Dictionary = {
	Res.GOLD: "金币",
	Res.WOOD: "木头",
	Res.FOOD: "食物",
	Res.STONE: "石头",
}

const CITY_CENTER_ID: String = "city_center"

## 类别顺序（用于 UI 筛选）
const CATEGORIES: Array[String] = ["food", "production", "economy", "military", "civic", "housing", "special"]

const CATEGORY_NAMES: Dictionary = {
	"food": "食物",
	"production": "生产",
	"economy": "经济",
	"military": "军事",
	"civic": "市政",
	"housing": "住宅",
	"special": "特殊",
}

const CATEGORY_COLORS: Dictionary = {
	"food": Color("#7cb342"),
	"production": Color("#8d6e63"),
	"economy": Color("#f9a825"),
	"military": Color("#b71c1c"),
	"civic": Color("#3949ab"),
	"housing": Color("#ff8a65"),
	"special": Color("#bdbdbd"),
}

## 建筑定义
## - cost: 建造费 {Res: int}
## - yields: 基础产出/回合 {Res: int}
## - adjacency: 相邻建筑加成，逐格计数；{"ids": [建筑id], "cats": [类别], "res", "amt"}
## - water_bonus: 相邻水域加成 {Res: int}（每格相邻水域单独计）
## - match_bonus: 匹配地形加成 {Terrain: {Res: int}}
## - terrain_req: 地形要求（可建的地形列表）
## - adj_req: 相邻要求（至少 1 格相邻满足），{"terrains": [Terrain]}
## - max_level: 等级上限
const BUILDINGS: Dictionary = {
	# ── 食物 ──
	"farm": {
		"name": "农场", "category": "food",
		"cost": {Res.GOLD: 10, Res.WOOD: 20},
		"yields": {Res.FOOD: 2},
		"adjacency": [
			{"ids": ["farm"], "cats": [], "res": Res.FOOD, "amt": 1},
		],
		"water_bonus": {Res.FOOD: 1},
		"match_bonus": {TerrainData.Terrain.PLAIN: {Res.FOOD: 1}},
		"terrain_req": [TerrainData.Terrain.PLAIN],
		"adj_req": [],
		"max_level": 4,
	},
	"pasture": {
		"name": "牧场", "category": "food",
		"cost": {Res.GOLD: 15, Res.WOOD: 10},
		"yields": {Res.FOOD: 2, Res.GOLD: 1},
		"adjacency": [
			{"ids": ["farm"], "cats": [], "res": Res.GOLD, "amt": 1},
		],
		"water_bonus": {Res.FOOD: 1},
		"match_bonus": {TerrainData.Terrain.HILL: {Res.FOOD: 1}},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 4,
	},
	"mill": {
		"name": "磨坊", "category": "food",
		"cost": {Res.GOLD: 30, Res.WOOD: 20},
		"yields": {Res.FOOD: 1, Res.GOLD: 2},
		"adjacency": [
			{"ids": ["farm"], "cats": [], "res": Res.FOOD, "amt": 1},
		],
		"water_bonus": {Res.FOOD: 1},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN],
		"adj_req": [{"terrains": [TerrainData.Terrain.WATER]}],
		"max_level": 3,
	},
	"granary": {
		"name": "谷仓", "category": "food",
		"cost": {Res.GOLD: 20, Res.WOOD: 30},
		"yields": {Res.FOOD: 3},
		"adjacency": [
			{"ids": ["granary"], "cats": [], "res": Res.FOOD, "amt": 1},
		],
		"water_bonus": {Res.FOOD: 1},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	# ── 生产 ──
	"lumberyard": {
		"name": "伐木场", "category": "production",
		"cost": {Res.GOLD: 10},
		"yields": {Res.WOOD: 2},
		"adjacency": [
			{"ids": ["lumberyard"], "cats": [], "res": Res.WOOD, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 4,
	},
	"quarry": {
		"name": "采石场", "category": "production",
		"cost": {Res.GOLD: 10},
		"yields": {Res.STONE: 2},
		"adjacency": [
			{"ids": ["quarry"], "cats": [], "res": Res.STONE, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {TerrainData.Terrain.HILL: {Res.STONE: 1}},
		"terrain_req": [TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 4,
	},
	"workshop": {
		"name": "工坊", "category": "production",
		"cost": {Res.GOLD: 30, Res.WOOD: 15},
		"yields": {Res.WOOD: 1, Res.STONE: 1},
		"adjacency": [
			{"ids": [], "cats": ["production"], "res": Res.WOOD, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"smelter": {
		"name": "冶炼厂", "category": "production",
		"cost": {Res.GOLD: 40, Res.STONE: 20},
		"yields": {Res.STONE: 3},
		"adjacency": [
			{"ids": ["quarry"], "cats": [], "res": Res.STONE, "amt": 2},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 2,
	},
	# ── 经济 ──
	"market": {
		"name": "市场", "category": "economy",
		"cost": {Res.GOLD: 20},
		"yields": {Res.GOLD: 3},
		"adjacency": [
			{"ids": ["shop"], "cats": [], "res": Res.GOLD, "amt": 2},
		],
		"water_bonus": {Res.GOLD: 1},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"shop": {
		"name": "商铺", "category": "economy",
		"cost": {Res.GOLD: 15},
		"yields": {Res.GOLD: 2},
		"adjacency": [
			{"ids": ["market"], "cats": [], "res": Res.GOLD, "amt": 2},
		],
		"water_bonus": {Res.GOLD: 1},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"bank": {
		"name": "银行", "category": "economy",
		"cost": {Res.GOLD: 60},
		"yields": {Res.GOLD: 4},
		"adjacency": [
			{"ids": ["market", "shop"], "cats": [], "res": Res.GOLD, "amt": 2},
		],
		"water_bonus": {Res.GOLD: 1},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 2,
	},
	# ── 军事 ──
	"barracks": {
		"name": "兵营", "category": "military",
		"cost": {Res.GOLD: 30, Res.STONE: 15},
		"yields": {Res.GOLD: 1},
		"adjacency": [
			{"ids": [], "cats": ["military"], "res": Res.GOLD, "amt": 2},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"watchtower": {
		"name": "瞭望塔", "category": "military",
		"cost": {Res.GOLD: 25, Res.STONE: 10},
		"yields": {Res.GOLD: 1},
		"adjacency": [
			{"ids": ["wall"], "cats": [], "res": Res.GOLD, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {TerrainData.Terrain.MOUNTAIN: {Res.GOLD: 2}},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL, TerrainData.Terrain.MOUNTAIN],
		"adj_req": [],
		"max_level": 3,
	},
	"wall": {
		"name": "城墙", "category": "military",
		"cost": {Res.GOLD: 20, Res.STONE: 10},
		"yields": {},
		"adjacency": [
			{"ids": ["wall"], "cats": [], "res": Res.GOLD, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	# ── 市政 ──
	"shrine": {
		"name": "神殿", "category": "civic",
		"cost": {Res.GOLD: 25},
		"yields": {Res.GOLD: 1, Res.FOOD: 1},
		"adjacency": [
			{"ids": [], "cats": ["civic"], "res": Res.GOLD, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"library": {
		"name": "图书馆", "category": "civic",
		"cost": {Res.GOLD: 35},
		"yields": {Res.GOLD: 2},
		"adjacency": [
			{"ids": ["academy"], "cats": [], "res": Res.GOLD, "amt": 2},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"academy": {
		"name": "学院", "category": "civic",
		"cost": {Res.GOLD: 50},
		"yields": {Res.GOLD: 3},
		"adjacency": [
			{"ids": ["library"], "cats": [], "res": Res.GOLD, "amt": 2},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [{"terrains": [TerrainData.Terrain.MOUNTAIN]}],
		"max_level": 2,
	},
	# ── 住宅 ──
	"hut": {
		"name": "小屋", "category": "housing",
		"cost": {Res.GOLD: 15, Res.WOOD: 10},
		"yields": {Res.GOLD: 1},
		"adjacency": [
			{"ids": [], "cats": ["housing"], "res": Res.GOLD, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"house": {
		"name": "民居", "category": "housing",
		"cost": {Res.GOLD: 30, Res.WOOD: 20},
		"yields": {Res.GOLD: 2},
		"adjacency": [
			{"ids": ["hut"], "cats": [], "res": Res.GOLD, "amt": 1},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 3,
	},
	"estate": {
		"name": "庄园", "category": "housing",
		"cost": {Res.GOLD: 50, Res.WOOD: 30},
		"yields": {Res.GOLD: 3},
		"adjacency": [
			{"ids": [], "cats": ["housing"], "res": Res.GOLD, "amt": 2},
		],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN, TerrainData.Terrain.HILL],
		"adj_req": [],
		"max_level": 2,
	},
	# ── 特殊：市中心（天生存在，不可拆/不可升级）──
	"city_center": {
		"name": "市中心", "category": "special",
		"cost": {},
		"yields": {Res.GOLD: 3, Res.WOOD: 1, Res.FOOD: 1, Res.STONE: 1},
		"adjacency": [],
		"water_bonus": {},
		"match_bonus": {},
		"terrain_req": [TerrainData.Terrain.PLAIN],
		"adj_req": [],
		"max_level": 1,
	},
}


static func get_building(id: String) -> Dictionary:
	return BUILDINGS.get(id, {})


static func building_name(id: String) -> String:
	return str(get_building(id).get("name", id))
