extends Node3D
## =============================================================================
## 物理塔 —— RigidBody3D 积木塔 + 炮弹轰击（Jolt 物理）
## =============================================================================
## · 20 层木箱交错堆成高塔，每个都是独立刚体（真实倒塌连锁）；
## · 【发射炮弹】从右前方轰向塔基；【重建】恢复整齐的塔；
## · 顶部计数器：倒塌箱数 = 位移超过阈值的箱子数量。
## =============================================================================

const TOWER_LAYERS := 14
const BOX_SIZE := Vector3(1.0, 0.5, 1.0)

var _boxes: Array = []
var _ball: RigidBody3D

@onready var count_label: Label = $CanvasLayer/Bar/CountLabel


func _ready() -> void:
	# 地面
	var floor := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(24, 1, 24)
	fs.shape = fb
	floor.add_child(fs)
	add_child(floor)
	floor.position = Vector3(0, -0.5, 0)
	var fm := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(24, 1, 24)
	fm.mesh = fmesh
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.38, 0.30)
	fm.material_override = fmat
	floor.add_child(fm)

	# 炮弹
	_ball = RigidBody3D.new()
	var bs := CollisionShape3D.new()
	var bshape := SphereShape3D.new()
	bshape.radius = 0.55
	bs.shape = bshape
	_ball.add_child(bs)
	var bm := MeshInstance3D.new()
	var bmesh := SphereMesh.new()
	bmesh.radius = 0.55
	bmesh.height = 1.1
	bm.mesh = bmesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.15, 0.16, 0.2)
	bmat.metallic = 0.6
	bmat.roughness = 0.3
	bm.material_override = bmat
	_ball.add_child(bm)
	add_child(_ball)
	_ball.position = Vector3(14, 1.5, 0)
	_ball.mass = 4.0             # 真正的"炮弹"重量（默认 0.7kg 碰不动塔）
	_ball.continuous_cd = true   # 开启连续碰撞检测，防止高速穿透
	_ball.sleeping = true

	_build_tower()
	$CanvasLayer/Bar/ShootBtn.pressed.connect(_shoot)
	$CanvasLayer/Bar/RebuildBtn.pressed.connect(_rebuild)


func _build_tower() -> void:
	for b in _boxes:
		b.queue_free()
	_boxes.clear()
	for i in TOWER_LAYERS:
		var box := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = BOX_SIZE
		cs.shape = shape
		box.add_child(cs)
		var m := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = BOX_SIZE
		m.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(float(i) / TOWER_LAYERS * 0.12 + 0.08, 0.55, 0.85)
		m.material_override = mat
		box.add_child(m)
		add_child(box)
		box.position = Vector3(0, 0.25 + i * 0.51, 0)
		if i % 2 == 1:
			box.rotation.y = PI / 2.0   # 交错叠放
		_boxes.append(box)


func _shoot() -> void:
	_ball.sleeping = false
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = Vector3(9, 0.7, 0)
	# 冲量 = 质量 × 速度增量：4kg × 18m/s ≈ 72 N·s，正面轰击塔基
	_ball.apply_central_impulse(Vector3(-18.0, 1.2, 0) * _ball.mass)


func _rebuild() -> void:
	for b in _boxes:
		b.queue_free()
	_boxes.clear()
	_build_tower()


func _process(_delta: float) -> void:
	# 统计倒塌：水平位移超过 1.2 或跌落到地面以下的箱子
	# （注意不能直接用 position.length()——高层箱子本来就高）
	var fallen := 0
	for b in _boxes:
		if absf(b.position.x) > 1.2 or absf(b.position.z) > 1.2 or b.position.y < 0.1:
			fallen += 1
	count_label.text = "🧱 倒塌：%d / %d" % [fallen, _boxes.size()]
