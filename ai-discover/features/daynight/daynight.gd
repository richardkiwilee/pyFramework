extends Node3D
## =============================================================================
## 昼夜循环 —— 太阳轨道 + 天空/环境光/太阳色连续渐变
## =============================================================================
## 时间 0..1 映射为一整天：太阳沿圆周轨道运行，
##   · 白天：蓝色天空、白色阳光、明亮环境光；
##   · 日出日落：低角度暖橙阳光；
##   · 夜晚：深蓝夜空、微弱月光、小屋窗户亮起自发光。
## UI：时间滑杆（0~1 可拖动）+ 播放/暂停 + 当前时刻。
## =============================================================================

const NIGHT_SKY_TOP := Color(0.02, 0.03, 0.10)
const DAY_SKY_TOP := Color(0.30, 0.55, 0.90)
const NIGHT_SKY_HORIZON := Color(0.06, 0.07, 0.14)
const DAY_SKY_HORIZON := Color(0.78, 0.82, 0.92)

var _time_of_day := 0.3    # 0..1（0.25 ≈ 清晨）
var _playing := true
const DAY_SPEED := 0.04    # 每秒推进 4% → 25 秒一整天

@onready var sun: DirectionalLight3D = $Sun
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var slider: HSlider = $CanvasLayer/Bar/Slider
@onready var play_btn: Button = $CanvasLayer/Bar/PlayBtn
@onready var time_label: Label = $CanvasLayer/Bar/TimeLabel
@onready var windows_mats: Array = []


func _ready() -> void:
	_build_scene()
	slider.value_changed.connect(func(v: float) -> void: _time_of_day = v)
	play_btn.pressed.connect(func() -> void: _playing = not _playing)
	_apply_time()


## 场景：地面 + 小屋（带夜光窗户）+ 树 + 栅栏
func _build_scene() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.38, 0.26)
	ground.material_override = gm
	add_child(ground)

	# 小屋
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 2.2, 2.6)
	wall.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.72, 0.58, 0.40)
	wall.material_override = wm
	add_child(wall)
	wall.position = Vector3(0, 1.1, 0)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(3.6, 0.5, 3.0)
	roof.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.55, 0.22, 0.18)
	roof.material_override = rmat
	add_child(roof)
	roof.position = Vector3(0, 2.45, 0)

	# 夜光窗户（两个发光方块，夜晚 energy 升高）
	for wx in [-0.9, 0.9]:
		var win := MeshInstance3D.new()
		var wmesh := BoxMesh.new()
		wmesh.size = Vector3(0.7, 0.6, 0.1)
		win.mesh = wmesh
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(1.0, 0.85, 0.5)
		wmat.emission_enabled = true
		wmat.emission = Color(1.0, 0.8, 0.4)
		win.material_override = wmat
		add_child(win)
		win.position = Vector3(wx, 1.3, 1.31)
		windows_mats.append(wmat)

	# 树 ×3
	for pos in [Vector3(-5, 0, -2), Vector3(4.5, 0, -4), Vector3(-3.5, 0, 4.5)]:
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.height = 2.0
		tm.top_radius = 0.14
		tm.bottom_radius = 0.24
		trunk.mesh = tm
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.40, 0.28, 0.18)
		trunk.material_override = tmat
		add_child(trunk)
		trunk.position = pos + Vector3(0, 1.0, 0)
		var crown := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 1.0
		cm.height = 2.0
		crown.mesh = cm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.20, 0.42, 0.18)
		crown.material_override = cmat
		add_child(crown)
		crown.position = pos + Vector3(0, 2.6, 0)


func _process(delta: float) -> void:
	if _playing:
		_time_of_day = fposmod(_time_of_day + DAY_SPEED * delta, 1.0)
		slider.set_value_no_signal(_time_of_day)
	_apply_time()
	time_label.text = "🕐 %02d:%02d" % [int(_time_of_day * 24.0), int(fposmod(_time_of_day * 24.0, 1.0) * 60.0)]
	play_btn.text = "⏸ 暂停" if _playing else "▶ 播放"


## 按当前时间推太阳、天空与光照
func _apply_time() -> void:
	var a := _time_of_day * TAU
	# 太阳沿轨道运行（elev > 0 = 白天）
	sun.position = Vector3(cos(a) * 20.0, sin(a) * 20.0, 6.0)
	sun.look_at(Vector3.ZERO)
	var elev: float = sin(a)

	var day_f := smoothstep(-0.12, 0.28, elev)          # 白天因子
	var sunset_f := smoothstep(0.4, 0.06, absf(elev))   # 低角度 = 暖橙

	var sky_mat: ProceduralSkyMaterial = env.environment.sky.sky_material
	sky_mat.sky_top_color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, day_f)
	sky_mat.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, day_f)
	sky_mat.ground_bottom_color = NIGHT_SKY_HORIZON.lerp(Color(0.2, 0.24, 0.2), day_f)
	sky_mat.ground_horizon_color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, day_f)

	sun.light_color = Color(0.14, 0.17, 0.3).lerp(Color(1.0, 0.97, 0.9), day_f)
	sun.light_color = sun.light_color.lerp(Color(1.0, 0.55, 0.3), sunset_f * (1.0 - day_f * 0.4))
	sun.light_energy = lerpf(0.04, 1.35, day_f)

	env.environment.ambient_light_color = Color(0.10, 0.12, 0.20).lerp(Color(0.52, 0.56, 0.66), day_f)
	env.environment.ambient_light_energy = lerpf(0.4, 1.0, day_f)

	# 窗户夜晚发光
	for wm in windows_mats:
		wm.emission_energy_multiplier = lerpf(0.05, 2.2, 1.0 - day_f)
