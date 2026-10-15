extends Node
## Settings and campaign progress, saved in user://.

const PATH := "user://save.json"
var data := {"name": "Gladiator", "coins": 150, "stage": 1, "checkpoint": 1, "arms": {}, "settings": {"sensitivity": 1.0, "volume": 0.8, "music": 0.6}}

func _ready() -> void:
	load_save()

func load_save() -> void:
	if not FileAccess.file_exists(PATH):
		_migrate_old_name()
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			data[k] = d[k]

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func get_value(key: String, default = null):
	return data.get(key, default)

func set_value(key: String, value) -> void:
	data[key] = value
	save()

## The game was called Voxel Arena: Godot keeps user:// by the project's name, so the old save
## sits in a sibling folder. Copied over once, it keeps the campaign through the rename.
func _migrate_old_name() -> void:
	var here := ProjectSettings.globalize_path("user://")
	var old := here.trim_suffix("/").get_base_dir().path_join("Voxel Arena").path_join("save.json")
	if FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(PATH))
