class_name HexGeo
## 六边形网格几何（flat-top，轴向坐标 q/r）。
## 纯静态工具：距离、邻居、世界坐标互转、拾取反算。

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.y - b.y) + absi(a.x + a.y - b.x - b.y)) / 2


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for off: Vector2i in NEIGHBOR_OFFSETS:
		out.append(cell + off)
	return out


static func axial_to_world(cell: Vector2i, size: float) -> Vector3:
	var x: float = 1.5 * size * cell.x
	var z: float = sqrt(3.0) * size * (cell.y + cell.x * 0.5)
	return Vector3(x, 0.0, z)


static func world_to_axial(p: Vector3, size: float) -> Vector2i:
	var qf: float = (2.0 / 3.0) * p.x / size
	var rf: float = (-1.0 / 3.0 * p.x + sqrt(3.0) / 3.0 * p.z) / size
	return _axial_round(qf, rf)


static func _axial_round(qf: float, rf: float) -> Vector2i:
	# cube 坐标取整：保持 q + r + s == 0
	var sf: float = -qf - rf
	var rq: int = roundi(qf)
	var rr: int = roundi(rf)
	var rs: int = roundi(sf)
	var dq: float = absf(qf - rq)
	var dr: float = absf(rf - rr)
	var ds: float = absf(sf - rs)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(rq, rr)
