extends Node
## The end-to-end multiplayer run (`-- --probe e2e_run`): starts three games of this project, a host, a friend and a friend who comes
## in late, which play a whole evening of multiplayer through the game's own screens (e2e_host.gd, e2e_guest.gd), shows each thing
## they check as it is checked and, at the end, the whole list with what failed, and writes it to e2e_report.txt.
##   --visible        the games open in windows you can watch (else they run without a picture)
##   --watch guest    only that game (host, guest or late) gets a window
##   --quick          leaves out the tournament and the single modes (about half the time)
##   --lag 120 --loss 3   pretend a poor connection (milliseconds, percent) for every game
##   --port 17900     the port of the room
##   --shots folder   a picture of each game at the main steps, into the folder (with windows)
## Exit code 0: everything checked passed and every game finished.

const ROLES := ["host", "guest", "late"]
const TITLES := {"mp": "The Multiplayer screen", "lobby": "The room's lobby", "yard": "The yard and the smith", "pause": "The pause menu's door to the room", "fights": "The Arena's fights", "ffa": "Free for all: rounds and bots", "teams": "Red vs Blue: the team circles", "tourney": "The tournament", "mode": "The other fights of the Arena", "late": "A friend who comes late", "endless": "The endless arena with friends", "kick": "Removing a friend", "close": "Closing the room", "campaign": "A campaign room: the co-op campaign", "join": "Joining", "cue": "Waiting for each other", "run": "The run itself"}

var visible_games := false
var watch := ""
var quick := false
var port := 17900
var lag := 0
var loss := 0
var shots := ""
var exe := ""
var proj := ""
var pids := {}
var started_at := 0
var read := {}                  # role -> how many lines of its file are shown
var rows: Array = []            # [role, ok, id, what, seen]
var _ended := false
var _t := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	visible_games = args.has("--visible")
	if args.has("--watch") and args.size() > args.find("--watch") + 1:
		watch = args[args.find("--watch") + 1]
	quick = args.has("--quick")
	port = int(args[args.find("--port") + 1]) if args.has("--port") and args.size() > args.find("--port") + 1 else 17900
	if args.has("--lag") and args.size() > args.find("--lag") + 1:
		lag = int(args[args.find("--lag") + 1])
		loss = int(args[args.find("--loss") + 1]) if args.has("--loss") and args.size() > args.find("--loss") + 1 else 0
	if args.has("--shots") and args.size() > args.find("--shots") + 1:
		shots = args[args.find("--shots") + 1]
		OS.set_environment("E2E_SHOTS", shots)
	exe = OS.get_executable_path()
	proj = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dir := ProjectSettings.globalize_path("user://e2e")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, f])
	print("")
	print("WRECKSMITH multiplayer, from the first click to the last: a host, a friend and a late friend play it out%s%s%s" % [" (quick)" if quick else "", " on a poor connection (%d ms, %d%% lost)" % [lag, loss] if lag > 0 else "", ", in windows" if visible_games else ""])
	print("")
	started_at = Time.get_ticks_msec()
	pids["host"] = _spawn("host", Vector2i(30, 40))
	await get_tree().create_timer(2.5).timeout
	pids["guest"] = _spawn("guest", Vector2i(420, 120))
	pids["late"] = _spawn("late", Vector2i(810, 200))

func _spawn(role: String, at: Vector2i) -> int:
	var a := PackedStringArray(["--path", proj])
	var windowed := visible_games or watch == role
	if windowed:
		a.append_array(["--resolution", "1100x650", "--position", "%d,%d" % [at.x, at.y]])
	else:
		a.append("--headless")
	a.append_array(["--log-file", "%s/%s.log" % [ProjectSettings.globalize_path("user://e2e"), role]])
	a.append_array(["--", "--probe", "e2e_host" if role == "host" else "e2e_guest", "--port", str(port)])
	if role == "late":
		a.append_array(["--role", "late"])
	if quick:
		a.append("--quick")
	if lag > 0:
		a.append_array(["--lag", str(lag), "--loss", str(loss)])
	if windowed:
		a.append("--keep-window")
	var pid := OS.create_process(exe, a)
	if pid <= 0:
		print("Could not start the %s game (%s)" % [role, exe])
	return pid

func _process(dt: float) -> void:
	if _ended or pids.is_empty():
		return
	_t += dt
	if _t < 0.4:
		return
	_t = 0.0
	_show_new()
	var running := 0
	for role in pids:
		if int(pids[role]) > 0 and OS.is_process_running(int(pids[role])):
			running += 1
	var gone_for := (Time.get_ticks_msec() - started_at) / 1000.0
	# The host is done: the friends are given a moment to say what they saw, then the run is over.
	if (running == 0) or gone_for > 1800.0 or (not OS.is_process_running(int(pids["host"])) and _idle_since_host_ended()):
		_ended = true
		_finish()

var _host_ended_at := 0
func _idle_since_host_ended() -> bool:
	if _host_ended_at == 0:
		_host_ended_at = Time.get_ticks_msec()
	return Time.get_ticks_msec() - _host_ended_at > 25000

func _lines(role: String) -> PackedStringArray:
	var p := "%s/%s.txt" % [ProjectSettings.globalize_path("user://e2e"), role]
	if not FileAccess.file_exists(p):
		return PackedStringArray()
	return FileAccess.get_file_as_string(p).split("\n", false)

## The checks written since last looked, shown as they come.
func _show_new() -> void:
	for role in ROLES:
		var ls := _lines(role)
		var from := int(read.get(role, 0))
		for i in range(from, ls.size()):
			var f := ls[i].split("\t")
			if f.size() >= 4 and f[0] == "RESULT":
				var row := [role, f[1] == "ok", f[2], f[3], f[4] if f.size() > 4 else ""]
				rows.append(row)
				print("  [%s] %-5s %-22s %s%s" % ["ok" if row[1] else "FAIL", role, row[2], row[3], ("  (" + String(row[4]) + ")") if (not row[1] and String(row[4]) != "") else ""])
		read[role] = ls.size()

func _finish() -> void:
	for role in pids:
		var pid := int(pids[role])
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_show_new()
	var out := PackedStringArray()
	out.append("WRECKSMITH multiplayer: the end-to-end run")
	out.append("%s, %s%s" % [Time.get_datetime_string_from_system(), "quick" if quick else "everything", " on a poor connection (%d ms, %d%% lost)" % [lag, loss] if lag > 0 else ""])
	out.append("")
	# By area: the part of an id before its first dot.
	var areas: Array = []
	var by_area := {}
	for r in rows:
		var area := String(r[2]).get_slice(".", 0)
		if not by_area.has(area):
			by_area[area] = []
			areas.append(area)
		by_area[area].append(r)
	var failed := 0
	for area in areas:
		out.append(String(TITLES.get(area, area)).to_upper())
		for r in by_area[area]:
			out.append("  %s %-24s %s" % ["✔" if r[1] else "✘", r[2], r[3]])
			if not r[1]:
				failed += 1
				if String(r[4]) != "":
					out.append("      saw: %s" % r[4])
		out.append("")
	var exits := []
	for role in pids:
		var code := OS.get_process_exit_code(int(pids[role])) if int(pids[role]) > 0 else -1
		exits.append("%s %d" % [role, code])
	var crashed: Array = exits.filter(func(e): return not String(e).ends_with(" 0") and not String(e).ends_with(" 1"))
	var missing := rows.is_empty() or not rows.any(func(r): return String(r[2]) == "campaign.guest_end" or String(r[2]) == "campaign.won")
	var ok := failed == 0 and not rows.is_empty() and crashed.is_empty() and not missing
	out.append("%d checks, %d failed. Games ended: %s" % [rows.size(), failed, ", ".join(exits)])
	if missing and failed == 0:
		out.append("The run did not reach the end (the campaign room): see the games' logs in %s" % ProjectSettings.globalize_path("user://e2e"))
	out.append("RESULT: %s" % ("EVERYTHING PASSED" if ok else "SOMETHING FAILED"))
	var text := "\n".join(out)
	print("")
	print(text)
	for path in [proj + "/e2e_report.txt", ProjectSettings.globalize_path("user://e2e/report.txt")]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(text + "\n")
			f.close()
			print("Report: %s" % path)
			break
	get_tree().quit(0 if ok else 1)
