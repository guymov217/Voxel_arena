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
	# A rating's bouts (RatingRunner) play on a save of their own, gone when they end: never on the player's.
	if args.has("--rate"):
		path = "user://rate_%d.json" % OS.get_process_id()
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
	box_kind = ""
	box_run = 0
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

# ---------- The gladiator of a room (the friends' sandbox, the party's campaign) ----------
# In a room the gladiator is not the single campaign's: his purse, arms, kit, armour, wounds and training (the BOX_KEYS) are read and
# written in a profile of their own, kept in this save, and nothing he buys, spends, wears out or loses there reaches the single
# campaign (nor does anything it holds get spent there). Two kinds:
#   "arena": a friends' Arena room. One profile (`arena_profile`) kept for good; money is no object (UNLIMITED).
#   "coop":  the party's campaign. The gladiator of one run of it (the run's number: `coop_profiles`, the last few runs kept): each
#            player, the host as much as any guest, begins it as a new single campaign begins, with a purse, a bag, a body and arms
#            that are his own and kept in his own save.

const UNLIMITED := 999999      # (the friends' purse: no limit, shown as an infinity)
const BOX_KEY := "arena_profile"
const COOP_KEY := "coop_profiles"
const COOP_KEPT := 40          # (runs of the party's campaign whose gladiator is kept: one for each group of friends the host plays with, and the oldest goes only past this many)
const BOX_KEYS := ["coins", "arms", "kit", "armor_worn", "armor_wear", "body", "trainer", "virtus", "oddities_sold", "missions", "rep", "market_open", "coop_market_open"]
var boxed := false
var box_kind := ""             # "arena" | "coop" while a profile is open
var box_run := 0               # (the party's campaign: the run whose gladiator it is)
var _box := {}

## Into a room's profile: the kept one (the arena's, or the run's), on top of which `fresh` is laid for what it has not got.
func box_begin(fresh := {}, kind := "arena", run := 0) -> void:
	if kind == "coop":
		var all = data.get(COOP_KEY, {})
		var runs: Dictionary = (all as Dictionary) if all is Dictionary else {}
		var rk := str(run)
		var kept = runs.get(rk, {})
		_box = (kept as Dictionary) if kept is Dictionary else {}
		runs.erase(rk)
		runs[rk] = _box   # (the newest last)
		while runs.size() > COOP_KEPT:
			runs.erase(runs.keys()[0])
		data[COOP_KEY] = runs
	else:
		var kept2 = data.get(BOX_KEY, {})
		_box = (kept2 as Dictionary) if kept2 is Dictionary else {}
		data[BOX_KEY] = _box
	for k in fresh:
		if not _box.has(k):
			_box[k] = fresh[k]
	boxed = true
	box_kind = kind
	box_run = run

## Out of it: the single campaign's own values are read again.
func box_end() -> void:
	boxed = false
	box_kind = ""
	box_run = 0
	_box = {}

## In the friends' Arena room (where money is no object and the campaign is never touched).
func arena() -> bool:
	return boxed and box_kind == "arena"

## In the party's campaign.
func coop() -> bool:
	return boxed and box_kind == "coop"

## The gladiator of a run of the party's campaign that is over, put away.
func coop_forget(run: int) -> void:
	var all = data.get(COOP_KEY, {})
	if all is Dictionary and (all as Dictionary).has(str(run)):
		(all as Dictionary).erase(str(run))
		save()

# ---------- The party's campaigns: one for each group of friends ----------
# The host plays the party's campaign with different friends at different times, and each group has its own: how far it has got (the
# `coop_` keys of the save: the stage, the lap, the checkpoint, the mode, the bouts won at the gate, the scroll, the favourite) and, in the
# profiles above, each player's gladiator. The open campaign's keys are the save's own, as every part of the game reads them; the others are put
# away here (`coop_slots`: the run's number -> its keys, who plays it, how far it has got, when it was last played), and opening another
# takes the open one's keys away into its place and brings the other's in. A run a guest plays with the host is the same number.
const SLOTS_KEY := "coop_slots"
const SLOT_NOT_STATE := ["coop_run", "coop_profiles", "coop_slots"]
const SLOT_MEMBERS := 12       # (the names kept of who plays a campaign: a medallion for each in the lobby)

static func _is_slot_key(k: String) -> bool:
	return k.begins_with("coop_") and not SLOT_NOT_STATE.has(k) and not BOX_KEYS.has(k)

func _slots() -> Dictionary:
	var all = data.get(SLOTS_KEY, {})
	var slots: Dictionary = (all as Dictionary) if all is Dictionary else {}
	data[SLOTS_KEY] = slots
	return slots

static func _copy(v):
	return v.duplicate(true) if (v is Dictionary or v is Array) else v

## The open campaign's keys put away in its slot (what it was, how far it has got, when it was last played).
func coop_stash() -> void:
	var cur := int(data.get("coop_run", 0))
	if cur <= 0:
		return
	var slots := _slots()
	var slot = slots.get(str(cur), {})
	var s: Dictionary = (slot as Dictionary) if slot is Dictionary else {}
	var state := {}
	for k in data.keys():
		if _is_slot_key(String(k)):
			state[k] = _copy(data[k])
	s["state"] = state
	s["stage"] = int(data.get("coop_stage", 1))
	s["last"] = Time.get_unix_time_from_system()
	if not (s.get("members") is Array):
		s["members"] = []
	slots[str(cur)] = s

## The party's campaigns kept, in the order they were begun: [{run, stage, members (names), last, active}].
func coop_slots() -> Array:
	var out := []
	var slots := _slots()
	var cur := int(data.get("coop_run", 0))
	for rk in slots:
		var slot = slots[rk]
		if not (slot is Dictionary):
			continue
		var run := int(rk)
		var d: Dictionary = slot
		out.append({"run": run, "stage": int(data.get("coop_stage", 1)) if run == cur else int(d.get("stage", 1)),
			"members": ((d.get("members", []) as Array).duplicate() if d.get("members") is Array else []), "last": float(d.get("last", 0.0)), "active": run == cur})
	if cur > 0 and not slots.has(str(cur)):
		# (The one open that was never put away: a save from before there were more than one.)
		out.append({"run": cur, "stage": int(data.get("coop_stage", 1)), "members": [], "last": Time.get_unix_time_from_system(), "active": true})
	return out

## Open the campaign of run `run`: the open one's keys put away, the other's brought in (a run with none kept begins as a campaign begins).
func coop_open(run: int) -> void:
	var cur := int(data.get("coop_run", 0))
	if cur == run:
		return
	coop_stash()
	for k in data.keys():
		if _is_slot_key(String(k)):
			data.erase(k)
	var slots := _slots()
	var slot = slots.get(str(run))
	if slot is Dictionary and (slot as Dictionary).get("state") is Dictionary:
		for k in (slot as Dictionary).state:
			data[k] = _copy((slot as Dictionary).state[k])
		(slot as Dictionary)["last"] = Time.get_unix_time_from_system()
	else:
		slots[str(run)] = {"state": {}, "stage": 1, "last": Time.get_unix_time_from_system(), "members": []}
	data["coop_run"] = run
	_trim_slots()
	save()

## A new campaign, for a new group: a number of its own, begun as a campaign begins (the others are kept as they are).
func coop_begin_new() -> int:
	var run := randi_range(1, 2147483000)
	while _slots().has(str(run)) or int(data.get("coop_run", 0)) == run:
		run = randi_range(1, 2147483000)
	coop_open(run)
	return run

## Who plays the open campaign: names added to the slot's (the group it is, shown in the lobby), the newest last.
func coop_note_members(names: Array) -> void:
	var cur := int(data.get("coop_run", 0))
	if cur <= 0:
		return
	var slots := _slots()
	var slot = slots.get(str(cur))
	var s: Dictionary = (slot as Dictionary) if slot is Dictionary else {"state": {}, "stage": int(data.get("coop_stage", 1)), "last": Time.get_unix_time_from_system(), "members": []}
	var members: Array = (s.get("members") as Array) if s.get("members") is Array else []
	var changed := not slots.has(str(cur))
	for n in names:
		var nm := String(n).strip_edges().left(40)
		if nm != "" and not members.has(nm):
			members.append(nm)
			changed = true
	while members.size() > SLOT_MEMBERS:
		members.remove_at(0)
	s["members"] = members
	slots[str(cur)] = s
	if changed:
		save()

## The open campaign begun again (lost with no checkpoint to go back to): the same group, so its slot goes on under the new number (the
## friends who play it noted still; its keys are the game's to reset, as they were), and the gladiators of the old number are given up.
func coop_restart(new_run: int) -> void:
	var old := int(data.get("coop_run", 0))
	var members: Array = []
	var slot = _slots().get(str(old))
	if slot is Dictionary and (slot as Dictionary).get("members") is Array:
		members = ((slot as Dictionary).members as Array).duplicate()
	if old > 0:
		_slots().erase(str(old))
		var all = data.get(COOP_KEY, {})
		if all is Dictionary:
			(all as Dictionary).erase(str(old))
	_slots()[str(new_run)] = {"state": {}, "stage": int(data.get("coop_stage", 1)), "last": Time.get_unix_time_from_system(), "members": members}
	data["coop_run"] = new_run
	save()

## Past COOP_KEPT campaigns the one played longest ago goes (never the open one).
func _trim_slots() -> void:
	var slots := _slots()
	var cur := int(data.get("coop_run", 0))
	while slots.size() > COOP_KEPT:
		var oldest := ""
		var at := INF
		for rk in slots:
			if int(rk) == cur:
				continue
			var t := float((slots[rk] as Dictionary).get("last", 0.0)) if slots[rk] is Dictionary else 0.0
			if t < at:
				at = t
				oldest = String(rk)
		if oldest == "":
			break
		slots.erase(oldest)
		var all = data.get(COOP_KEY, {})
		if all is Dictionary:
			(all as Dictionary).erase(oldest)

## The game was called Voxel Arena: Godot keeps user:// by the project's name, so the old save
## sits in a sibling folder. Copied over once, it keeps the campaign through the rename.
func _migrate_old_name() -> void:
	var here := ProjectSettings.globalize_path("user://")
	var old := here.trim_suffix("/").get_base_dir().path_join("Voxel Arena").path_join("save.json")
	if FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(PATH))
