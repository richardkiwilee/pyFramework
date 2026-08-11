extends Node
## DataManager - Autoload singleton that loads and caches all game data from JSON files.
## Provides O(1) id-based lookups for characters, classes, equipment, skills, and items.

# ------------------------------------------------------------------ data caches
var characters: Dictionary = {}   # id → character record
var classes: Dictionary = {}      # id → class record
var equipment: Dictionary = {}    # id → equipment record
var skills: Dictionary = {}       # id → skill record
var skill_conditions: Dictionary = {}  # id → condition record
var items: Dictionary = {}        # id → item record

# index by class name for quick lookup
var characters_by_class: Dictionary = {}  # class_zh → [character_id, ...]
var skills_by_class: Dictionary = {}      # class_zh → [skill_id, ...]
var equipment_by_subtype: Dictionary = {} # subtype → [equipment_id, ...]

var _loaded: bool = false


func _ready() -> void:
	load_all_data()


func load_all_data() -> void:
	if _loaded:
		return
	_loaded = true

	# Load each JSON file
	_load_characters()
	_load_classes()
	_load_equipment()
	_load_skills()
	_load_items()

	# Build indices
	_build_indices()
	print("[DataManager] Loaded: %d chars, %d classes, %d equipment, %d skills, %d items" % [
		characters.size(), classes.size(), equipment.size(), skills.size(), items.size()
	])


# ------------------------------------------------------------------ loaders
func _load_characters() -> void:
	var data = _parse_json("res://data/characters.json")
	if data == null:
		return
	for rec in data.get("characters", []):
		characters[rec.id] = rec


func _load_classes() -> void:
	var data = _parse_json("res://data/classes.json")
	if data == null:
		return
	for rec in data.get("classes", []):
		classes[rec.id] = rec


func _load_equipment() -> void:
	var data = _parse_json("res://data/equipment.json")
	if data == null:
		return
	for rec in data.get("equipment", []):
		equipment[rec.id] = rec


func _load_skills() -> void:
	var data = _parse_json("res://data/skills.json")
	if data == null:
		return
	for rec in data.get("skills", []):
		skills[rec.id] = rec
	for rec in data.get("skill_conditions", []):
		skill_conditions[rec.id] = rec


func _load_items() -> void:
	var data = _parse_json("res://data/items.json")
	if data == null:
		return
	for rec in data.get("items", []):
		items[rec.id] = rec


# ------------------------------------------------------------------ index building
func _build_indices() -> void:
	# Characters by class
	for char_id in characters:
		var c = characters[char_id]
		var cls = c.get("class_zh", "")
		if not characters_by_class.has(cls):
			characters_by_class[cls] = []
		characters_by_class[cls].append(char_id)

	# Equipment by subtype
	for eq_id in equipment:
		var eq = equipment[eq_id]
		var st = eq.get("subtype", "other")
		if not equipment_by_subtype.has(st):
			equipment_by_subtype[st] = []
		equipment_by_subtype[st].append(eq_id)

	# Skills by class (match by class name in skill's class_zh field)
	for sk_id in skills:
		var sk = skills[sk_id]
		var cls = sk.get("class_zh", "")
		if cls != "":
			if not skills_by_class.has(cls):
				skills_by_class[cls] = []
			skills_by_class[cls].append(sk_id)


# ------------------------------------------------------------------ public lookups
func get_character(char_id: String) -> Dictionary:
	return characters.get(char_id, {})


func get_class_data(class_id: String) -> Dictionary:
	return classes.get(class_id, {})


func get_equipment(eq_id: String) -> Dictionary:
	return equipment.get(eq_id, {})


func get_skill(sk_id: String) -> Dictionary:
	return skills.get(sk_id, {})


func get_condition(cond_id: String) -> Dictionary:
	return skill_conditions.get(cond_id, {})


func get_characters_by_class_name(cls_name: String) -> Array:
	return characters_by_class.get(cls_name, [])


func get_skills_by_class_name(cls_name: String) -> Array:
	return skills_by_class.get(cls_name, [])


func get_equipment_by_subtype(subtype: String) -> Array:
	return equipment_by_subtype.get(subtype, [])


func get_all_character_ids() -> Array:
	return characters.keys()


func get_all_equipment_ids() -> Array:
	return equipment.keys()


func get_all_skill_ids() -> Array:
	return skills.keys()


func get_all_condition_ids() -> Array:
	return skill_conditions.keys()


func get_random_characters(count: int, exclude_ids: Array = []) -> Array:
	"""Return `count` random character ids not in exclude_ids."""
	var pool: Array = []
	for cid in characters:
		if cid not in exclude_ids:
			pool.append(cid)
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))


func get_random_equipment_for_slot(subtype: String, count: int = 1) -> Array:
	"""Return random equipment ids of given subtype."""
	var pool: Array = []
	for eq_id in equipment:
		var eq = equipment[eq_id]
		if eq.get("subtype", "") == subtype:
			pool.append(eq_id)
	pool.shuffle()
	return pool.slice(0, min(count, pool.size()))


func get_class_weapon_subtypes(class_id: String) -> Array:
	"""Return valid weapon subtypes for a class."""
	var cls = classes.get(class_id, {})
	var weapons = cls.get("weapon_types", [])
	var subtype_map := {
		"剑": "sword", "斧": "axe", "枪": "spear", "弓": "bow", "杖": "staff",
		"短剑": "sword", "锤": "axe", "弩": "bow", "爪": "sword",
		"拳/爪": "sword"
	}
	var result: Array = []
	for w in weapons:
		for kw in subtype_map:
			if w.find(kw) != -1:
				var st = subtype_map[kw]
				if st not in result:
					result.append(st)
	return result


func get_class_armor_subtypes(class_id: String) -> Array:
	"""Return valid armor/shield subtypes for a class."""
	var cls = classes.get(class_id, {})
	var armors = cls.get("armor_types", [])
	# Shields are separate from armor in our equipment data
	var result: Array = []
	for a in armors:
		if a.find("盾") != -1 or a.find("大盾") != -1:
			result.append("shield")
	return result


# ------------------------------------------------------------------ helper
func _parse_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("[DataManager] File not found: %s" % path)
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("[DataManager] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	return json.get_data()
