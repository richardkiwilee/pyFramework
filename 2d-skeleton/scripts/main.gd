@tool
extends Node2D

const GenAll = preload("res://scripts/gen_all.gd")
const BoneDef = preload("res://scripts/bone_def.gd")
const BoneSpec = preload("res://scripts/bone_spec.gd")
const ArtSetMeta = preload("res://scripts/art_meta.gd")

const SKEL_DIR := "res://skeletons"
const ANIM_DIR := "res://anims"
const ART_DIR := "res://art"

@onready var skeleton_opt: OptionButton = $CanvasLayer/HBox/SkeletonOpt
@onready var anim_opt: OptionButton = $CanvasLayer/HBox/AnimOpt
@onready var art_opt: OptionButton = $CanvasLayer/HBox/ArtOpt
@onready var apply_btn: Button = $CanvasLayer/HBox/ApplyBtn
@onready var stage: Node2D = $Stage

var _current_char: Node2D = null

# ── 启动 ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_ensure_assets()
	_fill_skeletons()
	_fill_anims()
	_fill_art()
	# 默认选第 0 项，让下拉框启动即显示文本
	if skeleton_opt.item_count > 0: skeleton_opt.select(0)
	if anim_opt.item_count > 0: anim_opt.select(0)
	if art_opt.item_count > 0: art_opt.select(0)
	if not apply_btn.is_connected("pressed", Callable(self, "_on_apply")):
		apply_btn.connect("pressed", Callable(self, "_on_apply"))
	# 启动屏幕为空，点应用才生成
	if Engine.is_editor_hint():
		return

# ── play(骨骼, 动作, 美术) —— 唯一入口 ───────────────────────────────────
# 用法：play("humanoid", "walk", "A")
# 销毁旧角色 → 按骨骼定义构建 Skeleton2D + Bone2D → 每骨挂美术 Sprite2D
# → 加载全部动画 → 立即播放选中动作；挥剑结束后自动转回呼吸。

func _ensure_assets() -> void:
	# 任一关键资源缺失则触发完整生成
	var need := false
	need = need or not ResourceLoader.exists("%s/humanoid.tres" % SKEL_DIR)
	need = need or not ResourceLoader.exists("%s/breath.tres" % ANIM_DIR)
	need = need or not FileAccess.file_exists("%s/A/head.png" % ART_DIR)
	if need:
		GenAll.generate()

# ── 下拉框填充（扫描文件夹） ────────────────────────────────────────────
func _fill_skeletons() -> void:
	skeleton_opt.clear()
	var files := _scan_files(SKEL_DIR, ".tres")
	for f in files:
		var path := "%s/%s" % [SKEL_DIR, f]
		var res := ResourceLoader.load(path, "BoneDef")
		if res == null:
			continue
		var bd: BoneDef = res
		skeleton_opt.add_item(bd.label, skeleton_opt.item_count)
		skeleton_opt.set_item_metadata(skeleton_opt.item_count - 1, bd.skeleton_key)

func _fill_anims() -> void:
	anim_opt.clear()
	var files := _scan_files(ANIM_DIR, ".tres")
	for f in files:
		var key := f.get_basename()
		var label := _anim_label(key)
		anim_opt.add_item(label, anim_opt.item_count)
		anim_opt.set_item_metadata(anim_opt.item_count - 1, key)

func _fill_art() -> void:
	art_opt.clear()
	var dirs := _scan_dirs(ART_DIR)
	for d in dirs:
		var meta_path := "%s/%s/_meta.tres" % [ART_DIR, d]
		var label := d
		var key := d
		if ResourceLoader.exists(meta_path):
			var m := ResourceLoader.load(meta_path, "ArtSetMeta") as ArtSetMeta
			if m != null:
				label = m.label
				key = m.key
		art_opt.add_item(label, art_opt.item_count)
		art_opt.set_item_metadata(art_opt.item_count - 1, key)

static func _anim_label(key: String) -> String:
	match key:
		"breath": return "呼吸"
		"walk": return "走动"
		"run": return "跑步"
		"sword_swing": return "挥剑"
	return key

func _scan_files(dir: String, ext: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if not da.current_is_dir() and f.ends_with(ext):
			out.append(f)
		f = da.get_next()
	da.list_dir_end()
	return out

func _scan_dirs(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if da.current_is_dir() and not f.begins_with("."):
			out.append(f)
		f = da.get_next()
	da.list_dir_end()
	return out

# ── play(骨骼, 动作, 美术) ──────────────────────────────────────────────
func play(skeleton_name: String, anim: String, art_set: String) -> void:
	_free_current()
	var char_root := _build(skeleton_name, art_set)
	stage.add_child(char_root)
	var player: AnimationPlayer = char_root.get_node("AnimationPlayer")
	# 加载所有动画进库
	var lib := AnimationLibrary.new()
	var anim_keys := ["breath", "walk", "run", "sword_swing"]
	for k in anim_keys:
		var ap := "%s/%s.tres" % [ANIM_DIR, k]
		if ResourceLoader.exists(ap):
			var a := ResourceLoader.load(ap, "Animation")
			if a != null:
				lib.add_animation(k, a)
	player.add_animation_library("", lib)
	# 挥剑后自动回呼吸
	if not player.is_connected("animation_finished", Callable(self, "_on_anim_finished")):
		player.connect("animation_finished", Callable(self, "_on_anim_finished"))
	player.play(anim)

func _on_anim_finished(name: String) -> void:
	# AnimationPlayer 动画名格式为 "<lib_name>/<anim>" 或 "<anim>"
	var key := name
	if key.contains("/"):
		key = key.get_slice("/", 1)
	if key == "sword_swing":
		var player: AnimationPlayer = stage.get_node_or_null("Character/AnimationPlayer")
		if player != null:
			player.play("breath")

func _free_current() -> void:
	if _current_char != null and is_instance_valid(_current_char):
		_current_char.queue_free()
	_current_char = null

# ── 构建角色：Skeleton2D + Bone2D + 每骨 Sprite2D ─────────────────────────
func _build(skeleton_key: String, art_set: String) -> Node2D:
	var root := Node2D.new()
	root.name = "Character"
	var skel := Skeleton2D.new()
	skel.name = "Skeleton2D"
	root.add_child(skel)
	# 加载骨骼定义
	var sk_path := "%s/%s.tres" % [SKEL_DIR, skeleton_key]
	var def: BoneDef = ResourceLoader.load(sk_path, "BoneDef")
	# 按父子关系建 Bone2D
	var bone_nodes: Dictionary = {}
	# 先建所有 Bone2D，再按 parent 挂载（保证父先存在）
	var pending := def.bones.duplicate()
	var guard := 0
	while pending.size() > 0 and guard < 1000:
		guard += 1
		var next_pending: Array = []
		for bs in pending:
			if bs.parent == "":
				var bn := Bone2D.new()
				bn.name = bs.name
				bn.set_autocalculate_length_and_angle(false)
				bn.position = bs.local_pos
				bn.rotation = bs.local_rot
				bn.set_length(_bone_length(bs))
				bn.set_bone_angle(deg_to_rad(90))
				skel.add_child(bn)
				bone_nodes[bs.name] = bn
			elif bone_nodes.has(bs.parent):
				var bn := Bone2D.new()
				bn.name = bs.name
				bn.set_autocalculate_length_and_angle(false)
				bn.position = bs.local_pos
				bn.rotation = bs.local_rot
				bn.set_length(_bone_length(bs))
				bn.set_bone_angle(deg_to_rad(90))
				(bone_nodes[bs.parent] as Bone2D).add_child(bn)
				bone_nodes[bs.name] = bn
			else:
				next_pending.append(bs)
		pending = next_pending
	# 每骨挂 Sprite2D
	for bs in def.bones:
		if bs.shape == "none":
			continue
		var png_path := "%s/%s/%s.png" % [ART_DIR, art_set, bs.name]
		if not ResourceLoader.exists(png_path):
			continue
		var tex := ResourceLoader.load(png_path, "Texture2D")
		if tex == null:
			continue
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = true
		sp.offset = bs.sprite_offset
		sp.z_index = bs.z_index
		(bone_nodes[bs.name] as Bone2D).add_child(sp)
	# AnimationPlayer
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	_current_char = root
	return root

func _bone_length(bs: BoneSpec) -> float:
	return bs.shape_h

# ── 应用按钮 ────────────────────────────────────────────────────────────
func _on_apply() -> void:
	var sk := _opt_key(skeleton_opt)
	var an := _opt_key(anim_opt)
	var ar := _opt_key(art_opt)
	play(sk, an, ar)

func _opt_key(opt: OptionButton) -> String:
	if opt.item_count == 0:
		return ""
	var idx := opt.selected
	if idx < 0:
		idx = 0
	var m = opt.get_item_metadata(idx)
	if m == null:
		return ""
	return str(m)
