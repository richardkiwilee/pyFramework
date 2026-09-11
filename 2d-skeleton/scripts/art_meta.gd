class_name ArtSetMeta extends Resource

@export var key: String = ""
@export var label: String = ""

func _to_string() -> String:
	return "ArtSetMeta(%s/%s)" % [key, label]
