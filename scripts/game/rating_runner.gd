class_name RatingRunner
extends Node
## Fights a rating's bouts (WeaponRating's battery): `godot --headless --fixed-fps 120 -- --rate <job.json>` (the forge starts the game this way, in a game of its own: a bout is a fight in a physics
## world, minutes of the PC's time that the forge's own frames cannot spare; tools/rate_presets.sh starts it for the arsenal). The job is a file: {"design": {...}} (a weapon) or {"presets": [keys]} (the
## arsenal's own), "out": where to write, "bouts"/"secs": a shorter battery for a test. The result is written to "out" after each bout
## (WeaponRating.clean_result reads it) and a last time when the battery is done: {"state": "running" | "done" | "failed", "bouts": [...]} (or, for presets, "presets": {key: summary}).

## The longest a run may take, however it goes (s of the PC's time): a game that is stuck ends itself.
const WALL_S := 1800.0

var job := {}
var out_path := ""
var started_ms := 0

func run(path: String) -> void:
	started_ms = Time.get_ticks_msec()
	var j = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (j is Dictionary):
		push_error("rating: no job at %s" % path)
		get_tree().quit(2)
		return
	job = j
	out_path = String(job.get("out", ""))
	if out_path == "":
		push_error("rating: the job names no output")
		get_tree().quit(2)
		return
	if job.get("presets") is Array:
		await _run_presets(job.presets as Array)
	else:
		await _run_design()
	_clean_up()
	get_tree().quit(0)

## The bouts of one weapon, written as they are fought.
func _run_design() -> void:
	var d = Net.clean_design(job.get("design", {})) if job.get("design") is Dictionary else null
	if d == null:
		_write({"state": "failed", "error": "The weapon would not do", "bouts": [], "of": 0})
		return
	var why := WeaponRating.unrateable(d)
	if why != "":
		_write({"state": "failed", "error": why, "bouts": [], "of": 0})
		return
	var rows: Array = await rate(d, func(done: Array, of: int): _write({"state": "running", "bouts": done, "of": of}))
	if rows.is_empty() or _stopped():
		_write({"state": "failed", "error": "The rating was cut short", "bouts": rows, "of": WeaponRating.battery().size()})
		return
	_write({"state": "done", "bouts": rows, "of": rows.size()})

## The arsenal's weapons, each rated in turn; the table's rows (WeaponRating.summary) written as they are made.
func _run_presets(keys: Array) -> void:
	var table := {}
	for k in keys:
		var d: Dictionary = Data.preset(String(k))
		if d.is_empty() or WeaponRating.unrateable(d) != "":
			continue
		var rows: Array = await rate(d)
		if _stopped():
			break
		table[String(k)] = WeaponRating.summary(rows)
		print("rated %-16s %5.1f  (%d of %d)" % [k, table[k].score, int(table[k].won), int(table[k].of)])
		_write({"state": "running", "presets": table, "stamp": WeaponRating.stamp()})
	_write({"state": "done", "presets": table, "stamp": WeaponRating.stamp()})

## The battery fought by `d`: its bouts' rows ({"foe", "won", "draw", "dmg", "taken", "secs", "hits", "big"}). `progress` is called with the rows so far and how many there will be.
func rate(d: Dictionary, progress := Callable()) -> Array:
	var bat := WeaponRating.battery()
	var n := mini(bat.size(), int(job.get("bouts", bat.size())))
	var secs := float(job.get("secs", WeaponRating.BOUT_SECS))
	var rows := []
	for i in n:
		if _stopped():
			break
		var r: Dictionary = await bout(d, bat[i].foe, int(bat[i].seed), secs)
		if r.is_empty():
			break
		rows.append(r)
		if progress.is_valid():
			progress.call(rows, n)
	return rows

## One bout: the weapon in a bot's hands against the foe `foe` (a WeaponRating.FOES entry), to the death or `secs`, then whoever has more of his blood and body left. Empty if the bout could not be set up.
func bout(d: Dictionary, foe: Dictionary, sd: int, secs: float) -> Dictionary:
	# The game's own dice (a blow's chips, a wound's wander) are the same for a bout every time: the same weapon is rated the same way, whatever was fought before it in this game.
	seed(sd)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": sd, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(30, 0, 30))
	var two := bool(d.get("twoHanded", false))
	var ea = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": d, "off": "" if two else "roundShield", "armor": []}, "team": 1, "pos": Vector3(0, 0.1, -2.5), "yaw": 0.0, "diff": WeaponRating.WIELDER_DIFF, "personality": "standard"})
	var eb = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": String(foe.main), "off": String(foe.off), "armor": foe.armor}, "team": 2, "pos": Vector3(0, 0.1, 2.5), "yaw": PI, "diff": float(foe.diff), "personality": "standard"})
	if ea == null or eb == null:
		m.queue_free()
		await get_tree().physics_frame
		return {}
	var fa: Fighter = ea.f
	var fb: Fighter = eb.f
	var st := {"dmg": 0.0, "taken": 0.0, "hits": 0, "big": 0.0}
	m.combat.hit.connect(func(h):
		var att = h.get("attacker")
		var vic = h.get("char")
		var dmg := float((h.get("res", {}) as Dictionary).get("dmg", 0.0))
		if att == fa and vic == fb:
			st.dmg += dmg
			st.hits += 1
			st.big = maxf(st.big, dmg)
		elif att == fb and vic == fa:
			st.taken += dmg)
	# Each keeps to the other.
	ea.target_lock = eb
	eb.target_lock = ea
	var t := 0.0
	while t < secs and fa.alive and fb.alive:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if _stopped():
			break
	var ha := _health(fa)
	var hb := _health(fb)
	var won := (fa.alive and not fb.alive) or (fa.alive == fb.alive and ha > hb + 0.01)
	var draw := fa.alive == fb.alive and absf(ha - hb) <= 0.01
	var row := {"foe": String(foe.key), "won": won, "draw": draw, "dmg": snappedf(st.dmg, 0.1), "taken": snappedf(st.taken, 0.1), "secs": snappedf(t, 0.1), "hits": st.hits, "big": snappedf(st.big, 0.1)}
	m.queue_free()
	await get_tree().physics_frame
	return row

## How much of a man there is left: his blood, less what his wounds take off it.
static func _health(f: Fighter) -> float:
	if not f.alive:
		return 0.0
	return f.blood * (1.0 - 0.6 * f.wound())

## Whether to stop: this has gone on too long. (The game that asked ends it with OS.kill when the forge is left; if that game is gone without a word, the bouts are fought to their end and the game quits.)
func _stopped() -> bool:
	return float(Time.get_ticks_msec() - started_ms) / 1000.0 > WALL_S

## The save this game played on is of no use to anyone.
func _clean_up() -> void:
	for p in [Save.path, Save.path + ".bak", Save.path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

## The result written whole to a file beside the output and moved into place, so that no reader sees half of it.
func _write(v: Dictionary) -> void:
	var tmp := out_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(v))
	f.close()
	# (A rename onto a file that is there fails on some systems.)
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
	DirAccess.rename_absolute(tmp, out_path)
