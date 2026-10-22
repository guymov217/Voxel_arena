extends Node
## Settings and campaign progress, saved in user://.

const PATH := "user://save.json"
const DEFAULTS := {"name": "Gladiator", "coins": 150, "stage": 1, "checkpoint": 1, "arms": {}, "settings": {"sensitivity": 1.0, "volume": 0.8, "music": 0.6}}
var data := DEFAULTS.duplicate(true)
var path := PATH

func _ready() -> void:
	# The tests and probes play on a save of their own, fresh each run: never on the player's
	# campaign, and never on what an earlier run left (armour one test bought was worn in the next).
	var args := OS.get_cmdline_user_args()
	if args.has("--test") or args.has("--probe"):
		path = "user://test_save.json"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	load_save()

## Back to a new player's save (the test runner, before each test).
func reset() -> void:
	data = DEFAULTS.duplicate(true)

func load_save() -> void:
	if not FileAccess.file_exists(path):
		_migrate_old_name()
	# The save, or, when it cannot be read (a write cut off by a crash or the power), the copy
	# kept of the one before.
	for p in [path, path + ".bak"]:
		var d = _read(p)
		if d is Dictionary:
			if p != path:
				push_warning("Save: %s could not be read; the backup was used" % path)
			for k in d:
				data[k] = d[k]
			return

static func _read(p: String):
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

## Written to a file beside it and moved into place whole, the last good save kept as .bak:
## a crash or the power going mid-write leaves one of the two readable.
func save() -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(abs_path, ProjectSettings.globalize_path(path + ".bak"))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)

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
