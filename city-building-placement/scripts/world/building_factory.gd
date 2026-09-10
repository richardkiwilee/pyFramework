extends RefCounted
## 程序化建筑模型工厂：基础几何体组合出 21 种剪影。
## piece: {"kind":"box|cyl", "pos":Vector3, "size":Vector3 / "r","r2","h", "rot":Vector3(度), "color":Color}
## deco_pos: 升级装饰挂点（屋顶上某点）

const MODELS: Dictionary = {
	# ── 食物 ──
	"farm": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.025, 0), "size": Vector3(0.75, 0.05, 0.75), "color": Color("#9ccc65")},
			{"kind": "box", "pos": Vector3(-0.05, 0.175, 0.05), "size": Vector3(0.45, 0.35, 0.4), "color": Color("#8d6e63")},
			{"kind": "cyl", "pos": Vector3(-0.05, 0.45, 0.05), "r": 0.34, "r2": 0.0, "h": 0.2, "color": Color("#795548")},
		],
		"deco_pos": Vector3(-0.05, 0.52, 0.05),
	},
	"pasture": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.06, 0), "size": Vector3(1.0, 0.12, 1.0), "color": Color("#a5d6a7")},
			{"kind": "box", "pos": Vector3(0, 0.18, 0.45), "size": Vector3(0.9, 0.18, 0.04), "color": Color("#8d6e63")},
			{"kind": "box", "pos": Vector3(0, 0.18, -0.45), "size": Vector3(0.9, 0.18, 0.04), "color": Color("#8d6e63")},
			{"kind": "box", "pos": Vector3(0.45, 0.18, 0), "size": Vector3(0.04, 0.18, 0.9), "color": Color("#8d6e63")},
			{"kind": "box", "pos": Vector3(-0.45, 0.18, 0), "size": Vector3(0.04, 0.18, 0.9), "color": Color("#8d6e63")},
			{"kind": "box", "pos": Vector3(0.25, 0.27, 0.25), "size": Vector3(0.35, 0.3, 0.35), "color": Color("#a1887f")},
			{"kind": "box", "pos": Vector3(0.25, 0.46, 0.25), "size": Vector3(0.42, 0.08, 0.42), "color": Color("#795548")},
		],
		"deco_pos": Vector3(0.25, 0.5, 0.25),
	},
	"mill": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.325, 0), "size": Vector3(0.55, 0.65, 0.55), "color": Color("#f5f0e1")},
			{"kind": "box", "pos": Vector3(0, 0.71, 0), "size": Vector3(0.65, 0.12, 0.65), "color": Color("#c62828")},
			{"kind": "cyl", "pos": Vector3(0, 1.02, 0), "r": 0.2, "h": 0.5, "color": Color("#8d6e63")},
			{"kind": "box", "pos": Vector3(0, 1.3, 0), "size": Vector3(1.4, 0.05, 0.12), "color": Color("#5d4037")},
			{"kind": "box", "pos": Vector3(0, 1.3, 0), "size": Vector3(0.12, 0.05, 1.4), "color": Color("#5d4037")},
		],
		"deco_pos": Vector3(0, 1.3, 0),
	},
	"granary": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.3, 0), "size": Vector3(0.95, 0.6, 0.75), "color": Color("#a1887f")},
			{"kind": "box", "pos": Vector3(0, 0.8, 0), "size": Vector3(1.05, 0.4, 0.85), "color": Color("#c62828")},
		],
		"deco_pos": Vector3(0, 1.0, 0),
	},
	# ── 生产 ──
	"lumberyard": {
		"pieces": [
			{"kind": "cyl", "pos": Vector3(-0.35, 0.14, 0.0), "r": 0.14, "h": 0.7, "rot": Vector3(90, 0, 0), "color": Color("#8d6e63")},
			{"kind": "cyl", "pos": Vector3(-0.35, 0.42, 0.0), "r": 0.14, "h": 0.7, "rot": Vector3(90, 0, 0), "color": Color("#8d6e63")},
			{"kind": "cyl", "pos": Vector3(-0.2, 0.14, 0.15), "r": 0.14, "h": 0.7, "rot": Vector3(90, 0, 0), "color": Color("#8d6e63")},
			{"kind": "box", "pos": Vector3(0.3, 0.175, -0.1), "size": Vector3(0.5, 0.35, 0.4), "color": Color("#795548")},
			{"kind": "box", "pos": Vector3(0.3, 0.4, -0.1), "size": Vector3(0.58, 0.1, 0.48), "color": Color("#5d4037")},
		],
		"deco_pos": Vector3(0.3, 0.45, -0.1),
	},
	"quarry": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.16, 0), "size": Vector3(0.5, 0.32, 0.5), "color": Color("#9e9e9e")},
			{"kind": "box", "pos": Vector3(-0.12, 0.45, 0.05), "size": Vector3(0.4, 0.26, 0.42), "color": Color("#8d8d8d")},
			{"kind": "box", "pos": Vector3(0.15, 0.53, -0.1), "size": Vector3(0.36, 0.3, 0.3), "color": Color("#b0b0b0")},
		],
		"deco_pos": Vector3(0, 0.68, 0),
	},
	"workshop": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.25, 0), "size": Vector3(0.7, 0.5, 0.7), "color": Color("#6d4c41")},
			{"kind": "box", "pos": Vector3(0, 0.58, 0), "size": Vector3(0.82, 0.16, 0.82), "color": Color("#8d6e63")},
			{"kind": "cyl", "pos": Vector3(0.2, 0.85, 0.2), "r": 0.07, "h": 0.4, "color": Color("#424242")},
		],
		"deco_pos": Vector3(0.2, 1.05, 0.2),
	},
	"smelter": {
		"pieces": [
			{"kind": "cyl", "pos": Vector3(0, 0.3, 0), "r": 0.42, "h": 0.6, "color": Color("#5d4037")},
			{"kind": "cyl", "pos": Vector3(0, 0.72, 0), "r": 0.3, "h": 0.25, "color": Color("#424242")},
			{"kind": "cyl", "pos": Vector3(0.15, 1.3, -0.05), "r": 0.09, "h": 0.9, "color": Color("#424242")},
		],
		"deco_pos": Vector3(0.15, 1.75, -0.05),
	},
	# ── 经济 ──
	"market": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.14, 0), "size": Vector3(0.85, 0.28, 0.5), "color": Color("#e0e0e0")},
			{"kind": "cyl", "pos": Vector3(-0.35, 0.515, 0.15), "r": 0.04, "h": 0.75, "color": Color("#795548")},
			{"kind": "cyl", "pos": Vector3(0.35, 0.515, 0.15), "r": 0.04, "h": 0.75, "color": Color("#795548")},
			{"kind": "box", "pos": Vector3(0, 0.89, 0), "size": Vector3(1.1, 0.08, 0.7), "color": Color("#f9a825")},
		],
		"deco_pos": Vector3(0, 0.93, 0),
	},
	"shop": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.25, 0), "size": Vector3(0.5, 0.5, 0.5), "color": Color("#fff8e1")},
			{"kind": "box", "pos": Vector3(0, 0.58, 0), "size": Vector3(0.62, 0.16, 0.62), "color": Color("#f9a825")},
			{"kind": "box", "pos": Vector3(0, 0.45, 0.3), "size": Vector3(0.3, 0.05, 0.62), "color": Color("#ef6c00")},
		],
		"deco_pos": Vector3(0, 0.66, 0),
	},
	"bank": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.35, 0), "size": Vector3(0.8, 0.7, 0.7), "color": Color("#e8eaf6")},
			{"kind": "cyl", "pos": Vector3(-0.28, 0.35, -0.24), "r": 0.06, "h": 0.7, "color": Color("#cfd8dc")},
			{"kind": "cyl", "pos": Vector3(0.28, 0.35, -0.24), "r": 0.06, "h": 0.7, "color": Color("#cfd8dc")},
			{"kind": "cyl", "pos": Vector3(-0.28, 0.35, 0.24), "r": 0.06, "h": 0.7, "color": Color("#cfd8dc")},
			{"kind": "cyl", "pos": Vector3(0.28, 0.35, 0.24), "r": 0.06, "h": 0.7, "color": Color("#cfd8dc")},
			{"kind": "box", "pos": Vector3(0, 0.81, 0), "size": Vector3(0.95, 0.22, 0.85), "color": Color("#b0bec5")},
			{"kind": "box", "pos": Vector3(0, 0.955, 0), "size": Vector3(1.0, 0.07, 0.9), "color": Color("#f9a825")},
		],
		"deco_pos": Vector3(0, 1.0, 0),
	},
	# ── 军事 ──
	"barracks": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.225, 0), "size": Vector3(0.9, 0.45, 0.7), "color": Color("#455a64")},
			{"kind": "box", "pos": Vector3(0, 0.54, 0), "size": Vector3(1.0, 0.18, 0.8), "color": Color("#b71c1c")},
			{"kind": "cyl", "pos": Vector3(0.25, 0.93, 0.15), "r": 0.025, "h": 0.6, "color": Color("#212121")},
			{"kind": "box", "pos": Vector3(0.35, 1.05, 0.15), "size": Vector3(0.2, 0.12, 0.03), "color": Color("#ef5350")},
		],
		"deco_pos": Vector3(0.25, 0.63, 0.15),
	},
	"watchtower": {
		"pieces": [
			{"kind": "cyl", "pos": Vector3(0, 0.55, 0), "r": 0.22, "h": 1.1, "color": Color("#607d8b")},
			{"kind": "cyl", "pos": Vector3(0, 1.21, 0), "r": 0.3, "h": 0.22, "color": Color("#78909c")},
			{"kind": "cyl", "pos": Vector3(0, 1.49, 0), "r": 0.34, "r2": 0.0, "h": 0.34, "color": Color("#b71c1c")},
		],
		"deco_pos": Vector3(0, 1.66, 0),
	},
	"wall": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.25, 0), "size": Vector3(1.15, 0.5, 0.35), "color": Color("#9e9e9e")},
			{"kind": "box", "pos": Vector3(-0.3, 0.58, 0), "size": Vector3(0.18, 0.16, 0.38), "color": Color("#9e9e9e")},
			{"kind": "box", "pos": Vector3(0, 0.58, 0), "size": Vector3(0.18, 0.16, 0.38), "color": Color("#9e9e9e")},
			{"kind": "box", "pos": Vector3(0.3, 0.58, 0), "size": Vector3(0.18, 0.16, 0.38), "color": Color("#9e9e9e")},
		],
		"deco_pos": Vector3(0, 0.66, 0),
	},
	# ── 市政 ──
	"shrine": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.08, 0), "size": Vector3(0.8, 0.16, 0.8), "color": Color("#e0e0e0")},
			{"kind": "cyl", "pos": Vector3(-0.28, 0.41, -0.28), "r": 0.05, "h": 0.5, "color": Color("#eceff1")},
			{"kind": "cyl", "pos": Vector3(0.28, 0.41, -0.28), "r": 0.05, "h": 0.5, "color": Color("#eceff1")},
			{"kind": "cyl", "pos": Vector3(-0.28, 0.41, 0.28), "r": 0.05, "h": 0.5, "color": Color("#eceff1")},
			{"kind": "cyl", "pos": Vector3(0.28, 0.41, 0.28), "r": 0.05, "h": 0.5, "color": Color("#eceff1")},
			{"kind": "box", "pos": Vector3(0, 0.76, 0), "size": Vector3(0.88, 0.2, 0.88), "color": Color("#3949ab")},
		],
		"deco_pos": Vector3(0, 0.86, 0),
	},
	"library": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.275, 0), "size": Vector3(0.85, 0.55, 0.7), "color": Color("#eceff1")},
			{"kind": "box", "pos": Vector3(0, 0.625, 0), "size": Vector3(0.97, 0.15, 0.82), "color": Color("#3949ab")},
			{"kind": "box", "pos": Vector3(0, 0.2, 0.37), "size": Vector3(0.24, 0.4, 0.06), "color": Color("#5c4033")},
		],
		"deco_pos": Vector3(0, 0.7, 0),
	},
	"academy": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.07, 0), "size": Vector3(0.9, 0.14, 0.9), "color": Color("#e0e0e0")},
			{"kind": "cyl", "pos": Vector3(0, 0.54, 0), "r": 0.38, "h": 0.8, "color": Color("#eceff1")},
			{"kind": "cyl", "pos": Vector3(0, 1.11, 0), "r": 0.4, "r2": 0.0, "h": 0.34, "color": Color("#3949ab")},
		],
		"deco_pos": Vector3(0, 1.2, 0),
	},
	# ── 住宅 ──
	"hut": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.2, 0), "size": Vector3(0.5, 0.4, 0.5), "color": Color("#ffcc80")},
			{"kind": "box", "pos": Vector3(0, 0.51, 0), "size": Vector3(0.62, 0.22, 0.62), "color": Color("#e65100")},
		],
		"deco_pos": Vector3(0, 0.62, 0),
	},
	"house": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.35, 0), "size": Vector3(0.6, 0.7, 0.55), "color": Color("#ffcc80")},
			{"kind": "box", "pos": Vector3(0, 0.79, 0), "size": Vector3(0.72, 0.18, 0.67), "color": Color("#bf360c")},
			{"kind": "box", "pos": Vector3(0, 0.45, 0.33), "size": Vector3(0.6, 0.06, 0.16), "color": Color("#fff3e0")},
		],
		"deco_pos": Vector3(0, 0.88, 0),
	},
	"estate": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.325, 0), "size": Vector3(1.0, 0.65, 0.8), "color": Color("#ffe0b2")},
			{"kind": "box", "pos": Vector3(0, 0.77, 0), "size": Vector3(1.15, 0.24, 0.95), "color": Color("#e65100")},
			{"kind": "box", "pos": Vector3(0.62, 0.225, -0.15), "size": Vector3(0.5, 0.45, 0.45), "color": Color("#ffcc80")},
		],
		"deco_pos": Vector3(0, 0.89, 0),
	},
	# ── 特殊 ──
	"city_center": {
		"pieces": [
			{"kind": "box", "pos": Vector3(0, 0.125, 0), "size": Vector3(1.2, 0.25, 1.2), "color": Color("#9e9e9e")},
			{"kind": "cyl", "pos": Vector3(0, 0.85, 0), "r": 0.35, "h": 1.2, "color": Color("#e0e0e0")},
			{"kind": "cyl", "pos": Vector3(0, 1.65, 0), "r": 0.12, "r2": 0.0, "h": 0.4, "color": Color("#f9a825")},
		],
		"deco_pos": Vector3(0, 1.85, 0),
	},
}

static var _mat_cache: Dictionary = {}


## 组装建筑节点（含升级装饰件）
static func make(id: String, level: int) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var data: Dictionary = MODELS.get(id, {})
	for p: Dictionary in data.get("pieces", []):
		root.add_child(_make_piece(p))
	var deco: Vector3 = data.get("deco_pos", Vector3(0, 0.5, 0))
	for p: Dictionary in _deco_pieces(deco, level):
		root.add_child(_make_piece(p))
	return root


static func _make_piece(p: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var kind: String = str(p.get("kind", "box"))
	var pos: Vector3 = p.get("pos", Vector3.ZERO)
	var rot: Vector3 = p.get("rot", Vector3.ZERO)
	var color: Color = p.get("color", Color.WHITE)
	if kind == "cyl":
		var m := CylinderMesh.new()
		m.radial_segments = 12
		m.top_radius = float(p.get("r2", p.get("r", 0.2)))
		m.bottom_radius = float(p.get("r", 0.2))
		m.height = float(p.get("h", 0.5))
		mi.mesh = m
	else:
		var m := BoxMesh.new()
		m.size = p.get("size", Vector3.ONE)
		mi.mesh = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = _mat(color)
	return mi


## 升级装饰：Lv2 烟囱、Lv3 旗帜、Lv4 小塔（挂于 deco_pos）
static func _deco_pieces(deco_pos: Vector3, level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if level >= 2:
		out.append({"kind": "cyl", "pos": deco_pos + Vector3(0.15, 0.15, 0.08), "r": 0.06, "h": 0.3, "color": Color("#424242")})
	if level >= 3:
		out.append({"kind": "cyl", "pos": deco_pos + Vector3(-0.12, 0.25, -0.02), "r": 0.02, "h": 0.5, "color": Color("#212121")})
		out.append({"kind": "box", "pos": deco_pos + Vector3(-0.01, 0.45, -0.02), "size": Vector3(0.22, 0.12, 0.03), "color": Color("#ef5350")})
	if level >= 4:
		out.append({"kind": "cyl", "pos": deco_pos + Vector3(0.0, 0.22, -0.1), "r": 0.13, "r2": 0.06, "h": 0.44, "color": Color("#607d8b")})
	return out


static func _mat(color: Color) -> StandardMaterial3D:
	if not _mat_cache.has(color):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		_mat_cache[color] = m
	return _mat_cache[color]
