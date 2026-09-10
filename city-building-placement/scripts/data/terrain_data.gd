extends RefCounted
## 地形数据：4 种地形 + 半径 3 的 37 格固定布局（手绘，可改）。

enum Terrain { PLAIN, HILL, WATER, MOUNTAIN }

const NAMES: Dictionary = {
	Terrain.PLAIN: "平原",
	Terrain.HILL: "丘陵",
	Terrain.WATER: "水域",
	Terrain.MOUNTAIN: "高山",
}

## 地形顶面高度（建筑底座、高亮面都以此为准）
const TOP_HEIGHT: Dictionary = {
	Terrain.PLAIN: 0.0,
	Terrain.HILL: 0.35,
	Terrain.WATER: -0.3,
	Terrain.MOUNTAIN: 1.0,
}

const TOP_COLOR: Dictionary = {
	Terrain.PLAIN: Color("#6aa84f"),
	Terrain.HILL: Color("#a8955f"),
	Terrain.WATER: Color("#4a86c8"),
	Terrain.MOUNTAIN: Color("#8d8d8d"),
}

const SIDE_COLOR: Dictionary = {
	Terrain.PLAIN: Color("#58883f"),
	Terrain.HILL: Color("#8a7848"),
	Terrain.WATER: Color("#3a6ea8"),
	Terrain.MOUNTAIN: Color("#6b6b6b"),
}

## 固定布局：轴向坐标 -> Terrain
## 布局：东侧 4 格连湖；西南群山弧 + 东北独峰；丘陵散布（1 环内 2 格）
const LAYOUT: Dictionary = {
	# r = -3
	Vector2i(0, -3): Terrain.PLAIN,
	Vector2i(1, -3): Terrain.PLAIN,
	Vector2i(2, -3): Terrain.MOUNTAIN,
	Vector2i(3, -3): Terrain.PLAIN,
	# r = -2
	Vector2i(-1, -2): Terrain.PLAIN,
	Vector2i(0, -2): Terrain.PLAIN,
	Vector2i(1, -2): Terrain.HILL,
	Vector2i(2, -2): Terrain.PLAIN,
	Vector2i(3, -2): Terrain.PLAIN,
	# r = -1
	Vector2i(-2, -1): Terrain.HILL,
	Vector2i(-1, -1): Terrain.HILL,
	Vector2i(0, -1): Terrain.PLAIN,
	Vector2i(1, -1): Terrain.PLAIN,
	Vector2i(2, -1): Terrain.PLAIN,
	Vector2i(3, -1): Terrain.WATER,
	# r = 0
	Vector2i(-3, 0): Terrain.PLAIN,
	Vector2i(-2, 0): Terrain.HILL,
	Vector2i(-1, 0): Terrain.HILL,
	Vector2i(0, 0): Terrain.PLAIN,
	Vector2i(1, 0): Terrain.PLAIN,
	Vector2i(2, 0): Terrain.PLAIN,
	Vector2i(3, 0): Terrain.WATER,
	# r = 1
	Vector2i(-3, 1): Terrain.PLAIN,
	Vector2i(-2, 1): Terrain.PLAIN,
	Vector2i(-1, 1): Terrain.PLAIN,
	Vector2i(0, 1): Terrain.HILL,
	Vector2i(1, 1): Terrain.PLAIN,
	Vector2i(2, 1): Terrain.WATER,
	# r = 2
	Vector2i(-3, 2): Terrain.MOUNTAIN,
	Vector2i(-2, 2): Terrain.PLAIN,
	Vector2i(-1, 2): Terrain.PLAIN,
	Vector2i(0, 2): Terrain.PLAIN,
	Vector2i(1, 2): Terrain.WATER,
	# r = 3
	Vector2i(-3, 3): Terrain.PLAIN,
	Vector2i(-2, 3): Terrain.MOUNTAIN,
	Vector2i(-1, 3): Terrain.MOUNTAIN,
	Vector2i(0, 3): Terrain.PLAIN,
}

## 地图半径（最远环数）
const MAP_RADIUS: int = 3


static func terrain_at(cell: Vector2i) -> int:
	return int(LAYOUT.get(cell, Terrain.PLAIN))


static func terrain_name(terrain: int) -> String:
	return str(NAMES.get(terrain, "?"))
