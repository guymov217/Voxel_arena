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
	# A friend who is not there (Friends, FriendPilot: a game the host's opens to try a room with) plays on a save of his own,
	# new each time, never on the player's.
	if args.has("--friend"):
		var i := args.find("--persona")
		path = "user://friend_%s.json" % (args[i + 1] if i >= 0 and args.size() > i + 1 else "0")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	load_save()

## Back to a new player's save (the test runner, before each test).
func reset() -> void:
	data = DEFAULTS.duplicate(true)
	boxed = false
	_box = {}

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
	if boxed and BOX_KEYS.has(key):
		return _box.get(key, default)
	return data.get(key, default)

func set_value(key: String, value) -> void:
	if boxed and BOX_KEYS.has(key):
		_box[key] = value
		save()
		return
	data[key] = value
	save()

## The key gone from the save (read again as its default).
func erase(key: String) -> void:
	if boxed and BOX_KEYS.has(key):
		_box.erase(key)
		save()
		return
	if data.has(key):
		data.erase(key)
		save()

# ---------- The friends' sandbox (an Arena room) ----------
# In a room made for the friends' fights the gladiator is another man from the campaign's: his purse, arms, kit, armour, wounds
# and training (the BOX_KEYS) are read and written in a profile of their own (`arena_profile`, kept in this save under that one
# key), never in the campaign's. Nothing he buys, spends, wears out or loses there reaches the campaign, and nothing the campaign
# holds is spent there.

const UNLIMITED := 999999      # (the friends' purse: no limit, shown as an infinity)
const BOX_KEY := "arena_profile"
const BOX_KEYS := ["coins", "arms", "kit", "armor_worn", "armor_wear", "body", "trainer", "virtus", "oddities_sold", "missions", "rep", "market_open", "coop_market_open"]
var boxed := false
var _box := {}

## Into the sandbox: the arena profile kept from the last time (or a new one made of `fresh`), on top of which `fresh` is laid
## for what it has not got.
func box_begin(fresh := {}) -> void:
	var kept = data.get(BOX_KEY, {})
	_box = (kept as Dictionary) if kept is Dictionary else {}
	for k in fresh:
		if not _box.has(k):
			_box[k] = fresh[k]
	data[BOX_KEY] = _box
	boxed = true

## Out of it: the campaign's own values are read again.
func box_end() -> void:
	boxed = false
	_box = {}

## The game was called Voxel Arena: Godot keeps user:// by the project's name, so the old save
## sits in a sibling folder. Copied over once, it keeps the campaign through the rename.
func _migrate_old_name() -> void:
	var here := ProjectSettings.globalize_path("user://")
	var old := here.trim_suffix("/").get_base_dir().path_join("Voxel Arena").path_join("save.json")
	if FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(PATH))
