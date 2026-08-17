class_name HexCore
extends RefCounted
## =============================================================================
## 六边形网格几何 —— 轴向坐标(pointy-top)纯静态工具
## =============================================================================
## 地图数据与生成见 hex_map.gd(HexMap),区域规则见 districts.gd。
## =============================================================================

const SQRT3 := 1.7320508
const RADIUS := 5                  # 地图半径(环数),共 3*R*(R+1)+1 = 91 格
const HEX_R := 1.0                 # 六边形外接圆半径(世界单位)
const ELEV_H := 0.32               # 每层海拔的垂直高度
const WATER_Y := -0.1              # 海面相对高度(0 层陆地顶面为 0)
const SEA_FLOOR_Y := -1.0          # 海底 / 陆地基座底部
const HILL := 2                    # 丘陵海拔
const MOUNTAIN := 3                # 山脉海拔

## 轴向坐标 6 邻接方向(东 / 东北 / 西北 / 西 / 西南 / 东南)
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


## 世界坐标(二维,渲染时映射到 XZ 平面)
static func center(q: int, r: int) -> Vector2:
	return Vector2(HEX_R * SQRT3 * (float(q) + float(r) * 0.5), HEX_R * 1.5 * float(r))


static func corners(q: int, r: int, radius: float = HEX_R) -> PackedVector2Array:
	var c := center(q, r)
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + float(i) * PI / 3.0
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	return pts


## 轴向坐标六边形距离
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := b.x - a.x
	var dr := b.y - a.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## 立方坐标取整
static func cube_round(f: Vector3) -> Vector2i:
	var rx := roundi(f.x)
	var ry := roundi(f.y)
	var rz := roundi(f.z)
	var dx := absf(f.x - float(rx))
	var dy := absf(f.y - float(ry))
	var dz := absf(f.z - float(rz))
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)


## 世界坐标(XZ)→ 最近的六边形轴向坐标
static func axial_round(p: Vector2) -> Vector2i:
	var qf := (SQRT3 / 3.0 * p.x - 1.0 / 3.0 * p.y) / HEX_R
	var rf := (2.0 / 3.0 * p.y) / HEX_R
	return cube_round(Vector3(qf, -qf - rf, rf))
