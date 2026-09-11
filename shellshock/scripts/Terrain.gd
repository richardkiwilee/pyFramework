# Terrain.gd — Destructible bitmap terrain.
# One Image holds the RGBA pixels we draw; we also keep a fast solid query.
# Explosions carve circles out of the image and we re-upload the texture.
# Tanks rest on the surface and fall when ground beneath them is removed.
extends Node2D
class_name Terrain

@export var map_index: int = 0

var width: int = 1280
var height: int = 720

var _image: Image
var _texture: ImageTexture

# Palette per map. Plain Dictionaries; values read with explicit casts.
const MAPS := [
	{ name = "Rolling Hills",  top = Color(0.62, 0.80, 0.34), body = Color(0.45, 0.55, 0.22), shadow = Color(0.30, 0.40, 0.16), sky = Color(0.55, 0.72, 0.86) },
	{ name = "Mesa Plateau",   top = Color(0.80, 0.55, 0.30), body = Color(0.60, 0.40, 0.22), shadow = Color(0.42, 0.28, 0.16), sky = Color(0.85, 0.70, 0.55) },
	{ name = "Rocky Valley",   top = Color(0.55, 0.55, 0.58), body = Color(0.40, 0.40, 0.44), shadow = Color(0.26, 0.26, 0.30), sky = Color(0.45, 0.50, 0.58) },
	{ name = "Twin Peaks",     top = Color(0.92, 0.94, 0.98), body = Color(0.70, 0.74, 0.82), shadow = Color(0.50, 0.55, 0.65), sky = Color(0.60, 0.72, 0.92) },
]


func _ready() -> void:
	if map_index < 0 or map_index >= MAPS.size():
		map_index = Game.rng.randi() % MAPS.size()
	_generate()


func map_name() -> String:
	return String(MAPS[map_index]["name"])

func sky_color() -> Color:
	return Color(MAPS[map_index]["sky"])


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------
func _generate() -> void:
	_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	var pal: Dictionary = MAPS[map_index]
	var hmap := _heightmap(map_index)

	# Fill solid below height for each column. Add a darker band near top (grass).
	var top_col: Color = pal["top"]
	var body_col: Color = pal["body"]
	var shadow_col: Color = pal["shadow"]
	for x in range(width):
		var top_y: int = hmap[x]
		for y in range(top_y, height):
			var col: Color
			var depth: float = float(y - top_y) / 60.0
			if y - top_y < 6:
				col = top_col
			elif depth < 1.0:
				col = top_col.lerp(body_col, depth)
			else:
				col = body_col.lerp(shadow_col, clamp((depth - 1.0) * 0.5, 0.0, 1.0))
			_image.set_pixel(x, y, col)

	_texture = ImageTexture.create_from_image(_image)
	queue_redraw()


func _heightmap(idx: int) -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(width)
	var base: float = height * 0.62  # average ground level
	match idx:
		0: # Rolling Hills — layered sines
			for x in range(width):
				var y: float = base + sin(x * 0.012) * 60.0 + sin(x * 0.035) * 22.0 + sin(x * 0.07) * 10.0
				h[x] = int(y)
		1: # Mesa Plateau — high flat middle, lower stepped sides
			for x in range(width):
				var t: float = x / float(width)
				var mid: float = 1.0 - abs(t - 0.5) * 2.0  # 1 in middle, 0 at edges
				var y: float = base + 70.0 * smoothstep(0.2, 0.8, mid) - 10.0
				# small roughness
				y += sin(x * 0.09) * 4.0
				h[x] = int(y)
		2: # Rocky Valley — high edges, low middle
			for x in range(width):
				var t: float = x / float(width)
				var d: float = abs(t - 0.5) * 2.0  # 0 middle, 1 edges
				var y: float = base + 90.0 * smoothstep(0.0, 1.0, d) * (1.0 - smoothstep(0.85, 1.0, d) * 0.2)
				y += sin(x * 0.05) * 8.0 + sin(x * 0.13) * 4.0
				h[x] = int(y)
		3: # Twin Peaks — two peaks with a saddle
			for x in range(width):
				var p1: float = exp(-pow((x - width * 0.30) / 120.0, 2)) * 120.0
				var p2: float = exp(-pow((x - width * 0.70) / 120.0, 2)) * 120.0
				var y: float = base - (p1 + p2) + 20.0
				y += sin(x * 0.08) * 5.0
				h[x] = int(clamp(y, 60.0, float(height - 40)))
		_:
			for x in range(width): h[x] = int(base)
	return h


# ---------------------------------------------------------------------------
# Collision queries
# ---------------------------------------------------------------------------
func is_solid_at(x: float, y: float) -> bool:
	var ix: int = int(round(x))
	var iy: int = int(round(y))
	if ix < 0 or ix >= width:
		return true  # invisible side walls keep things in
	if iy < 0:
		return false
	if iy >= height:
		return false  # open below; projectile culls when far under
	return _image.get_pixel(ix, iy).a > 0.5


## First solid y scanning downward from the top at column x. Returns height if none.
func surface_y_at(x: float, from_y: float = 0.0) -> float:
	var ix: int = int(round(x))
	if ix < 0 or ix >= width:
		return float(height)
	var y: int = max(0, int(from_y))
	while y < height:
		if _image.get_pixel(ix, y).a > 0.5:
			return float(y)
		y += 1
	return float(height)


# ---------------------------------------------------------------------------
# Destruction
# ---------------------------------------------------------------------------
## Carve a circle out of the terrain.
func carve_circle(cx: float, cy: float, r: float) -> void:
	var x0: int = int(cx - r - 1)
	var x1: int = int(cx + r + 1)
	var y0: int = int(cy - r - 1)
	var y1: int = int(cy + r + 1)
	x0 = max(x0, 0); y0 = max(y0, 0)
	x1 = min(x1, width - 1); y1 = min(y1, height - 1)
	var r2: float = r * r
	var changed: bool = false
	for y in range(y0, y1 + 1):
		var dy: float = y - cy
		for x in range(x0, x1 + 1):
			var dx: float = x - cx
			if dx * dx + dy * dy <= r2:
				_image.set_pixel(x, y, Color(0, 0, 0, 0))
				changed = true
	if changed:
		_texture = ImageTexture.create_from_image(_image)
		queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw() -> void:
	if _texture:
		draw_texture(_texture, Vector2.ZERO)
