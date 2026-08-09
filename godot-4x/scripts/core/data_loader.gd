## 数据加载与 mod 层叠覆盖（对应 pydemo/game/data_loader.py）。
## 基础定义从 res://data/*.json 加载；mod 从 res://mods/ 子目录按目录名排序覆盖
## （同名 id 整条记录覆盖）。data/wiki.json 是百科只读参考层。
class_name DataLoader

const DEFINITION_FILES := [
	"resources", "buildings", "unit_types", "heroes", "skills",
	"events", "synergies", "terrain", "artifacts",
]

static func load_definitions() -> Dictionary:
	var defs: Dictionary = {}
	for name in DEFINITION_FILES:
		defs[name] = _load_one("res://data/%s.json" % name)
	# mod 层叠覆盖：res://mods/ 下每个子目录一个 mod，按目录名排序
	var mods_path := "res://mods/"
	if DirAccess.dir_exists_absolute(mods_path):
		var dir := DirAccess.open(mods_path)
		if dir != null:
			var mod_dirs: Array = []
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if dir.current_is_dir() and not entry.begins_with("."):
					mod_dirs.append(entry)
				entry = dir.get_next()
			mod_dirs.sort()
			for mod_dir in mod_dirs:
				for name in DEFINITION_FILES:
					var fpath := "res://mods/%s/%s.json" % [mod_dir, name]
					if FileAccess.file_exists(fpath):
						defs[name] = _merge(defs[name], _load_one(fpath))
	return defs

## 加载 techs/cultures 等 [{id,...}] 列表为 {id: record}。失败返回 {}。
static func load_list_defs(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Dictionary = {}
	if data is Array:
		for rec in data:
			if rec is Dictionary and rec.has("id"):
				out[str(rec["id"])] = rec
	return out

static func _load_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

static func _merge(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for k in overlay:
		result[k] = overlay[k].duplicate(true)
	return result
