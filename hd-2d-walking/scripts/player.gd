extends Node2D
## 主角：格为单位的连续坐标 + 平滑爬坡 + 四向动画 + 按投影深度排序。
##
## 位置用"格"为单位（pos.x/pos.y），而不是像素 —— 这样走位、碰撞、
## 高度采样三者天然一致，深度计算也不用做单位换算。

const Proj = preload("res://scripts/proj.gd")

const SPEED := 5.2          ## 格/秒
## 每步最多能爬升的高度（级/格）。height_at() 返回的是**整数**高度级，
## 所以这个阈值必须 > 1，否则任何一级台阶都会被判成悬崖、角色永远上不了坡。
## 本图的高度场相邻格差值只有 0 和 ±1，因此 1.5 等于"所有坡都能走"。
const STEP_UP := 1.5
const H_LERP := 9.0         ## 视觉高度逼近目标高度的速度（越大越干脆）

var world = null            ## WorldData
var pos := Vector2.ZERO     ## 格坐标（脚底所在的地面点）
var vis_h := 0.0            ## 视觉高度：平滑跟随目标高度，让上坡不是"啪"地弹一下
var target_h := 0

var _facing := "down"
var _anim_t := 0.0
var _moving := false
var _frames: Dictionary = {}   ## dir -> Array[Texture2D]（行走 6 帧）
var _idle: Dictionary = {}     ## dir -> Array[Texture2D]（待机 2 帧）
var _sprite: Sprite2D
var _sprite_offset := Vector2.ZERO   ## 贴图底边中点（脚底）在贴图里的位置


func setup(world_data, spawn: Vector2) -> void:
	world = world_data
	pos = spawn
	target_h = world.height_at(int(pos.x), int(pos.y))
	vis_h = float(target_h)
	_sprite.texture = _idle["down"][0]
	_refresh_transform()


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	# 深度写在**父节点** player 的 z_index 上（_refresh_transform），sprite 必须
	# 相对继承它。这里若写成 z_as_relative = false，sprite 自己的 z_index 是 0，
	# 就变成"绝对 0 层"——而地形分带都在 767 以上，角色会被整个埋在地面之下，
	# 看不见但也没报错。地面和物件的 sprite 可以直接用绝对 z，因为它们挂在根节点下。
	_sprite.z_as_relative = true
	add_child(_sprite)
	_load_frames()


func _load_frames() -> void:
	for dir in ["down", "side", "up"]:
		var walk := _strip("res://assets/characters/hero_%s.png" % dir)
		var idle := _strip("res://assets/characters/hero_idle_%s.png" % dir)
		_frames[dir] = walk
		_idle[dir] = idle
		if not walk.is_empty():
			# 贴图是"脚底贴下边、左右居中"的切图，锚点取底边中点
			var fs: int = walk[0].atlas.get_height()
			_sprite_offset = Vector2(fs * 0.5, float(fs))


## 把一条横向 sprite sheet 按正方形切成一帧一帧
func _strip(path: String) -> Array:
	var tex := load(path) as Texture2D
	var out: Array = []
	if tex == null:
		push_error("缺少角色贴图: " + path)
		return out
	var fs := tex.get_height()
	var n := int(tex.get_width() / fs)
	for i in range(n):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fs, 0, fs, fs)
		out.append(at)
	return out


func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_moving = dir.length() > 0.01

	if _moving:
		# 轴分离推进：斜着撞墙时还能沿墙滑，手感比整体拒绝好得多
		_advance(Vector2(dir.x, 0.0).normalized() * SPEED * delta)
		_advance(Vector2(0.0, dir.y).normalized() * SPEED * delta)
		if absf(dir.x) > absf(dir.y):
			_facing = "side"
			_sprite.flip_h = dir.x < 0.0
		elif absf(dir.y) > 0.001:
			_facing = "up" if dir.y < 0.0 else "down"

	target_h = world.height_at(int(floor(pos.x)), int(floor(pos.y)))
	_vis_h_update(delta)
	_refresh_transform()
	_animate(delta)


## 试着往 delta 方向挪一点，撞墙/悬崖/水面就原地不动
func _advance(delta: Vector2) -> void:
	if delta == Vector2.ZERO:
		return
	var np := pos + delta
	var tx := int(floor(np.x))
	var ty := int(floor(np.y))
	if world.blocked(tx, ty):
		return
	if absf(float(world.height_at(tx, ty)) - float(target_h)) > STEP_UP:
		return   # 太陡，爬不上去
	pos = np


func _vis_h_update(delta: float) -> void:
	if is_equal_approx(vis_h, float(target_h)):
		vis_h = float(target_h)
		return
	vis_h = lerpf(vis_h, float(target_h), clampf(H_LERP * delta, 0.0, 1.0))


func _refresh_transform() -> void:
	# 脚底对齐：贴图中心在身体中部，接地锚点由 main.gd 写进 _ground_off
	position = Proj.world_to_screen(pos.x, pos.y, vis_h) - _sprite_offset
	z_index = Proj.depth(pos.y, vis_h)


func _animate(delta: float) -> void:
	var seq: Array = _frames[_facing] if _moving else _idle[_facing]
	if seq.is_empty():
		return
	var fps := 11.0 if _moving else 2.2
	_anim_t += delta * fps
	var idx := int(_anim_t) % seq.size()
	_sprite.texture = seq[idx]


## 给相机 / 光照 / HUD 用的世界像素坐标
func screen_pos() -> Vector2:
	return Proj.world_to_screen(pos.x, pos.y, vis_h)


func facing() -> String:
	return _facing


func is_moving() -> bool:
	return _moving


## 给 shadows.gd 用：当前这一帧的贴图 + 脚底锚点 + 地面位置。
## 影子层本身不知道角色在放哪一帧，所以每帧来问一次。
func shadow_frame() -> Dictionary:
	var at := _sprite.texture as AtlasTexture
	if at == null:
		return {}
	var r := at.region
	return {
		"tex": at.atlas,
		"region": r,
		"pos": Proj.world_to_screen(pos.x, pos.y, vis_h),
		"ax": r.size.x * 0.5,
		"ay": r.size.y,
		"w": r.size.x,
		"h": r.size.y,
		"flip": _sprite.flip_h,
	}
