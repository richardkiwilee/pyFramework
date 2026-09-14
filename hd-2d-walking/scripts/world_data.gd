extends RefCounted
## 读取 tools/gen_world.py 产出的 world.json，并提供 O(1) 的地形查询。
##
## 高度和水面在 JSON 里是"每行一个数字字符串"（108 行 × 192 字符），
## 载入时摊平成 PackedByteArray，避免运行时反复做字符串索引。

var w: int = 0
var h: int = 0
var max_h: int = 1
var bands: Array = []
var objects: Array = []
var spawn := Vector2.ZERO

var _height := PackedByteArray()
var _water := PackedByteArray()
var _solid := PackedByteArray()


func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("找不到世界数据: " + path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()

	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("world.json 解析失败")
		return false

	w = int(d["w"])
	h = int(d["h"])
	max_h = int(d["max_h"])
	bands = d["bands"]
	objects = d["objects"]
	spawn = Vector2(float(d["spawn"]["x"]), float(d["spawn"]["y"]))

	_height = _flatten(d["height"], w, h)
	_water = _flatten(d["water"], w, h)
	# 物件占位：房子、树、篱笆、井。老版本只挡水面，角色是直接穿过房子的。
	_solid = _flatten(d["solid"], w, h) if d.has("solid") else 		PackedByteArray()
	if _solid.size() != w * h:
		_solid.resize(w * h)
	return true


static func _flatten(rows: Array, ww: int, hh: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(ww * hh)
	for y in range(hh):
		var line: String = rows[y]
		for x in range(ww):
			out[y * ww + x] = line.unicode_at(x) - 48
	return out


func inside(tx: int, ty: int) -> bool:
	return tx >= 0 and ty >= 0 and tx < w and ty < h


## 该格的地面高度（越界返回 0，调用方应先查 inside）
func height_at(tx: int, ty: int) -> int:
	if not inside(tx, ty):
		return 0
	return _height[ty * w + tx]


## 该格是否不可通行（水面 / 物件 / 越界）
func blocked(tx: int, ty: int) -> bool:
	if not inside(tx, ty):
		return true
	var i := ty * w + tx
	if _water[i] != 0 or _solid[i] != 0:
		return true
	# 世界边缘一圈也算墙，免得走出地图
	if tx < 2 or ty < 2 or tx >= w - 2 or ty >= h - 2:
		return true
	return false


## 采样（浮点）坐标处的地面高度
func height_at_f(pos: Vector2) -> int:
	return height_at(int(floor(pos.x)), int(floor(pos.y)))
