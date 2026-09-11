class_name BoneDef extends Resource

const BoneSpec = preload("res://scripts/bone_spec.gd")

@export var skeleton_key: String = ""
@export var label: String = ""
@export var bones: Array[BoneSpec] = []
