class_name BoneSpec extends Resource

@export var name: String = ""
@export var parent: String = ""
@export var local_pos: Vector2 = Vector2.ZERO
@export var local_rot: float = 0.0
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var flip_v: bool = false
@export var tex_size: Vector2 = Vector2.ZERO
@export var z_index: int = 0
@export var shape: String = "none"      # none | round_rect | circle | sword
@export var shape_w: float = 0.0
@export var shape_h: float = 0.0
@export var shape_r: float = 0.0
