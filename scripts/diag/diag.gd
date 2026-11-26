class_name Diag
extends Node
## THE diagnostic test (`tools/diagnose.bat`, `-- --diag`): everything that decides why a computer cannot hold a full room, measured in one run by itself, and ONE report
## (`diagnose_report.txt`, in the game's folder) to send. It is a list of parts (`plan`), each run in a game of its own (`DiagPhase`: its engine settings, its renderer and its
## thread count are the engine's at start, so they take a restart), one after another with the computer left alone; the test opens no part's window in front of another and
## writes the report as it goes, so a run cut short has what it had. What the parts are, in the order they are run:
##   facts        what this computer is, and what else is busy on it
##   steps        a physics step under 2 to 16 fighters: the scripts' part and the engine's, the native core on and off, bare men, a drift; then the thread settings one by one
##   release      the same, in a build made from this project's pack and Godot's release template (the build a player runs; this run is the editor's binary)
##   fight        the endless arena with eight bot players drawn for real: what each frame is made of; again with the shader cache off (a first launch), with the render thread,
##                with the other renderer, with physics interpolation off, full screen, at high priority
##   render       eight men walking, one setting changed at a time (the men not drawn, the shadows, the resolution, ...): what each is worth
##   room         the game's own menu: a room of eight with seven friend windows, the endless arena from the gate, four minutes, with the game's own record of it
## It reads nothing to the player: a window with the list and the time left, and at the end the report's place.

const MARK := "WRECKSMITH diagnostic test: temporary, removed when the part ends"
const REPORT := "diagnose_report.txt"
const BUDGET_MS := 1000.0 / 120.0

var opts := {}
var windowed := false
var proj := ""             # the project's folder (a run from the editor's binary) or "" (an exported game)
var out_dir := ""
var parts_dir := ""
var facts := {}
var plan_: Array = []
var results := {}          # id -> [results]
var problems := PackedStringArray()
var sections := PackedStringArray()   # the report's parts so far
var t_start := 0
var release := {"ok": false, "why": "not tried", "dir": "", "exe": ""}
var _aborted := false
var _pid := 0
var _running := ""
var _done_ids := {}
var _skipped := {}
var _took := {}
var _step_t0 := 0
var _ui_text: RichTextLabel
var _ui_foot: Label
var _ui_next_us := 0

# ---------- the plan ----------

## The parts of a run, in order. `opts`: quick (the whole of it in minutes, for a look), windowed (this game has a window), editor (this is the editor's binary), driver (the renderer it runs,
## "" without a window), os; only, skip (lists of ids or of the words before an underscore: "fight", "steps_t4"). Each part: id, title, part (the DiagPhase's name, or facts / export), window
## (needs a window), release (run in the release build), engine (flags before `--`), user (arguments after it), settings (override.cfg), cfg (what the part is told), est and timeout (s).
static func plan(o: Dictionary) -> Array:
	var quick: bool = o.get("quick", false)
	var win: bool = o.get("windowed", false)
	var editor: bool = o.get("editor", true)
	var windows_os: bool = String(o.get("os", "")) == "Windows"
	var drv := String(o.get("driver", ""))
	# (The parts the first report answered, on the one machine that has run it: the threads' number, other games beside it, the sound, the caches, the other renderer, interpolation, full
	# screen, priority, most of the picture's settings. They are run when asked for, `--all`; a quick look runs them too, shortened.)
	var every: bool = o.get("all", false)
	var wide: bool = every or quick
	var p := []
	var headless_flags := ["--headless", "--fixed-fps", "120"]
	var window_flags := ["--position", "40,60", "--resolution", String(o.get("size", "1280x720"))]
	var small_window := ["--position", "0,0", "--resolution", "160x90"]
	var sk := 2.0 if quick else 6.0   # (seconds of a fight's steps in a mix)
	p.append({"id": "facts", "title": "what this computer is, and what else is busy on it", "part": "facts", "est": 8, "timeout": 60})
	if every:   # (answered by the second report: twelve fast and eight slow on the owner's, the game on a fast one)
		p.append({"id": "cores", "title": "how fast each of this processor's cores is, and which of them the system gives a game", "part": "cores", "engine": ["--headless"], "est": 25, "timeout": 150})   # (with no window: a game held to one processor shares it with its own drawing)
	# --- the step ---
	var curve := "men:4+men:8+men:8,foe:3+men:8,foe:8+men:8#gd+men:8@60"   # (the long one with nobody to kill: a fight thins out, and its step with it; a clock that slows would show)
	if every:
		curve = "men:2+men:4+men:6+men:8+men:8,foe:3+men:8,foe:8+men:8,beast:lion*3+men:8,great:cyclops+men:8#bare+men:8#gd+men:8,foe:3#gd+men:8@60"
	if quick:
		curve = "men:4+men:8,foe:3+men:8,foe:3#gd"
	p.append({"id": "steps_auto", "title": "a physics step under 4 to 16 fighters (the threads the engine picks)", "part": "steps", "engine": headless_flags, "cfg": {"mixes": curve, "secs": sk, "cpu": 1}, "est": 20 if quick else (145 if every else 110), "timeout": 120 if quick else 460})
	if every:
		p.append({"id": "steps_window", "title": "the same fights with a small window of their own (does the system give a game with no window less of the processor?)", "part": "steps", "window": true,
			"engine": ["--fixed-fps", "120", "--disable-vsync"] + small_window, "cfg": {"mixes": "men:8+men:8,foe:3", "secs": sk, "cpu": 1}, "est": 30, "timeout": 150})
		p.append({"id": "steps_fast", "title": "the same fights with no window, held to this processor's fast cores", "part": "steps", "engine": headless_flags, "affinity": "fast",
			"cfg": {"mixes": "men:8+men:8,foe:3", "secs": sk, "cpu": 1}, "est": 30, "timeout": 150})
	if every or quick:
		p.append({"id": "steps_threads", "title": "the same fights with the men's controls on the worker threads (an experiment: off in the game)", "part": "steps", "engine": headless_flags,
			"cfg": {"mixes": "men:8,foe:3#thr" if quick else "men:8#thr+men:8,foe:3#thr+men:8,foe:8#thr", "secs": sk}, "est": 14 if quick else 34, "timeout": 180})
	if every or quick:   # (measured here, section 19: a third off a step, and pick-ups, jumps and the blades' aim broken by it: not a way as it is)
		p.append({"id": "steps_half", "title": "the same fights with a man's control every other step (an experiment: off in the game)", "part": "steps", "engine": headless_flags,
			"cfg": {"mixes": "men:8,foe:3#half" if quick else "men:8#half+men:8,foe:3#half+men:8,foe:8#half", "secs": sk}, "est": 14 if quick else 34, "timeout": 180})
	var threads := [1, 2, 4, 8] if every else ([1] if quick else [])
	for n in threads:
		p.append({"id": "steps_t%d" % n, "title": "the step with %d physics worker thread%s" % [n, "" if n == 1 else "s"], "part": "steps", "engine": headless_flags, "settings": {"threading/worker_pool/max_threads": n},
			"cfg": {"mixes": "men:8,foe:3" if quick else "men:8+men:8,foe:3+men:8,foe:8", "secs": sk}, "est": 14 if quick else 34, "timeout": 100 if quick else 180})
	if every:
		p.append({"id": "steps_burners", "title": "the step with seven other games busy beside it (what the friend windows take of the processor, with no network)", "part": "steps", "engine": headless_flags, "burners": 7,
			"cfg": {"mixes": "men:8+men:8,foe:3+men:8,foe:8", "secs": sk}, "est": 48, "timeout": 220})
	# --- the release build ---
	if editor:
		p.append({"id": "release_export", "title": "a release build made from this project (the game's pack and Godot's release template)", "part": "export", "est": 20 if quick else 45, "timeout": 420})
		p.append({"id": "release_steps", "title": "the step in the release build", "part": "steps", "release": true, "engine": headless_flags, "cfg": {"mixes": "men:8,foe:3" if quick else "men:8+men:8,foe:3+men:8,foe:8", "secs": sk}, "est": 14 if quick else 34, "timeout": 180})
	# --- the frame, drawn for real ---
	var fs := 10.0 if quick else 36.0
	var fight := {"secs": fs, "first": 4.0 if quick else 12.0}
	var fe := 30 if quick else 62
	p.append({"id": "fight_base", "title": "a fight of eight in the endless arena, drawn: what a frame is made of", "part": "fight", "window": true, "engine": window_flags, "cfg": fight.merged({"cpu": 1}), "est": fe, "timeout": 200})
	if editor:
		p.append({"id": "release_fight", "title": "the same fight in the release build", "part": "fight", "window": true, "release": true, "engine": window_flags, "cfg": fight, "est": fe, "timeout": 200})
	if every:
		p.append({"id": "fight_half", "title": "the same fight with a man's control every other step (an experiment: off in the game)", "part": "fight", "window": true, "engine": window_flags,
			"cfg": fight.merged({"half": 1}), "est": fe, "timeout": 200})
		p.append({"id": "fight_fast", "title": "the same fight held to this processor's fast cores", "part": "fight", "window": true, "engine": window_flags, "affinity": "fast", "cfg": fight, "est": fe, "timeout": 200})
		p.append({"id": "fight_threads", "title": "the same fight with the men's controls on the worker threads (an experiment: off in the game)", "part": "fight", "window": true, "engine": window_flags,
			"cfg": fight.merged({"threads": 1}), "est": fe, "timeout": 200})
		p.append({"id": "fight_render_thread", "title": "the same fight with the engine's own render thread (multi-threaded rendering)", "part": "fight", "window": true, "engine": window_flags,
			"settings": {"rendering/driver/threads/thread_model": 2}, "cfg": fight, "est": fe, "timeout": 200})
	if wide:
		p.append({"id": "fight_sound", "title": "the same fight with the sound on (it is muted in the others)", "part": "fight", "window": true, "engine": window_flags, "cfg": fight.merged({"sound": 1}), "est": fe, "timeout": 200})
		p.append({"id": "fight_cold", "title": "the same fight with the shader and pipeline caches off (what a first launch is)", "part": "fight", "window": true, "engine": window_flags,
			"settings": {"rendering/rendering_device/pipeline_cache/enable": false, "rendering/shader_compiler/shader_cache/enabled": false}, "cfg": fight, "est": fe, "timeout": 200})
		if windows_os and (drv == "d3d12" or drv == "vulkan"):
			var other := "vulkan" if drv == "d3d12" else "d3d12"
			p.append({"id": "fight_" + other, "title": "the same fight on the other renderer (%s instead of %s)" % [other, drv], "part": "fight", "window": true, "engine": window_flags + ["--rendering-driver", other], "cfg": fight, "est": fe, "timeout": 200})
		p.append({"id": "fight_no_interpolation", "title": "the same fight with physics interpolation off (what it costs a frame)", "part": "fight", "window": true, "engine": window_flags,
			"settings": {"physics/common/physics_interpolation": false}, "cfg": fight, "est": fe, "timeout": 200})
		p.append({"id": "fight_fullscreen", "title": "the same fight full screen at this screen's own size (the game's default)", "part": "fight", "window": true, "engine": ["--position", "0,0"],
			"cfg": fight.merged({"display": "fullscreen"}), "est": fe + 2, "timeout": 200})
		if windows_os:
			p.append({"id": "fight_high_priority", "title": "the same fight with the game at high priority", "part": "fight", "window": true, "engine": window_flags, "priority": "high", "cfg": fight, "est": fe, "timeout": 200})
	if every:
		p.append({"id": "readback", "title": "what it costs on this card to ask a part's voxels back from it (a blow's chips do)", "part": "readback", "window": true, "engine": window_flags, "est": 15, "timeout": 90})
	var variants := "3D not drawn+the men not drawn+no sun shadows" if quick else ("+".join(DiagPhase.RENDER_VARIANTS) if every else "3D not drawn+the men not drawn+the HUD not drawn+no sun shadows")
	if every or quick:   # (answered twice: the HUD's 0.6 ms, the sun's shadows 1.0, the men 0.5)
		p.append({"id": "render_steady", "title": "eight men walking in the yard, under settings changed one at a time", "part": "render", "window": true, "engine": window_flags,
			"cfg": {"secs": 2.0 if quick else 5.0, "warm": 6.0, "variants": variants}, "est": 25 if quick else (120 if every else 60), "timeout": 360})
	# (With vsync off: a frame of it is what the drawing costs, not the screen's rate.)
	var wreck := {"id": "wreck", "title": "what a fight leaves on the sand, drawn: the fight of eight stopped at %d s of the game, each kind of thing taken out of the picture in turn" % (8 if quick else 45), "part": "wreck", "window": true,
		"engine": window_flags + ["--disable-vsync"], "cfg": {"play": 8.0 if quick else 45.0, "secs": 1.0 if quick else 3.0}, "est": 45 if quick else 150, "timeout": 420}
	if editor and not quick:
		wreck["release"] = true
	p.append(wreck)
	# --- the room ---
	var room_user := ["--keep-window", "--host", "--arena", "--yard", "--playtest", "--bot", "--no-intro", "--name", "Diag", "--port"]
	var room_cfg := {"secs": 40.0 if quick else 150.0, "friends": 3 if quick else 7}
	if quick or every or not editor:   # (from the editor the room is played in the release build, below: what a player's game does)
		p.append({"id": "room_eight", "title": "the game's own room: eight players with seven friend windows, the endless arena", "part": "room", "window": true, "engine": window_flags,
			"user": room_user + ["17961"], "cfg": room_cfg, "est": 75 if quick else 300, "timeout": 300 if quick else 900})
	if editor and not quick:
		p.append({"id": "release_room", "title": "the same room in the release build (what a player's game does with eight in it)", "part": "room", "window": true, "release": true, "engine": window_flags,
			"user": room_user + ["17962"], "cfg": room_cfg, "est": 300, "timeout": 900})
	if every:
		var rh := {"id": "room_half", "title": "the same room with a man's control every other step (an experiment: off in the game)", "part": "room", "window": true, "engine": window_flags,
			"user": room_user + ["17964", "--control-half"], "cfg": room_cfg, "est": 300, "timeout": 900}
		if editor:
			rh["release"] = true
		p.append(rh)
	if every:
		p.append({"id": "room_threads", "title": "the same room with the men's controls on the worker threads (an experiment: off in the game)", "part": "room", "window": true, "engine": window_flags,
			"user": room_user + ["17963", "--control-threads"], "cfg": room_cfg, "est": 300, "timeout": 900})
	# the ones asked for
	var only: PackedStringArray = o.get("only", PackedStringArray())
	var skip: PackedStringArray = o.get("skip", PackedStringArray())
	var out := []
	for st in p:
		var id := String(st.id)
		if id == "facts":
			out.append(st)
			continue
		if not only.is_empty() and not _named(id, only):
			continue
		if _named(id, skip):
			continue
		out.append(st)
	return out

## Whether `id` is one of `names` or begins with one followed by an underscore.
static func _named(id: String, names: PackedStringArray) -> bool:
	for n in names:
		if id == n or id.begins_with(n + "_"):
			return true
	return false

## `override.cfg` as a part is run under (DiagStats.override_text with this test's mark).
static func override_for(settings: Dictionary) -> String:
	return DiagStats.override_text(settings, MARK)

## Where Godot keeps the release template of a platform for this version, or "".
static func template_path() -> String:
	var v := Engine.get_version_info()
	var ver := "%d.%d.%s" % [int(v.major), int(v.minor), String(v.status)] if int(v.patch) == 0 else "%d.%d.%d.%s" % [int(v.major), int(v.minor), int(v.patch), String(v.status)]
	match OS.get_name():
		"Windows":
			return OS.get_data_dir().path_join("Godot/export_templates/%s/windows_release_x86_64.exe" % ver)
		"Linux":
			return OS.get_data_dir().path_join("godot/export_templates/%s/linux_release.x86_64" % ver)
	return ""

## The folder the report lies in: the project's, or the game's own (an exported game), or the user data (a folder the game may not write in).
static func report_dir() -> String:
	var dir := OS.get_executable_path().get_base_dir() if (OS.has_feature("template") and not OS.has_feature("editor")) else ProjectSettings.globalize_path("res://").trim_suffix("/")
	var p := dir.path_join(".diag_write_test")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return ProjectSettings.globalize_path("user://").trim_suffix("/")
	f.close()
	DirAccess.remove_absolute(p)
	return dir

# ---------- a run ----------

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	windowed = DisplayServer.get_name() != "headless"
	opts = {"quick": args.has("--quick"), "windowed": windowed, "editor": OS.has_feature("editor"), "os": OS.get_name(), "driver": RenderingServer.get_current_rendering_driver_name() if windowed else "",
		"only": _list_arg(args, "--only"), "skip": _list_arg(args, "--skip"), "keep": args.has("--keep"), "size": _arg(args, "--size", "1280x720"), "all": args.has("--all")}
	proj = ProjectSettings.globalize_path("res://").trim_suffix("/") if OS.has_feature("editor") else ""
	out_dir = report_dir()
	parts_dir = ProjectSettings.globalize_path("user://diag_parts")
	DirAccess.make_dir_recursive_absolute(parts_dir)
	if windowed:
		get_tree().auto_accept_quit = false       # (closing the window ends the test the way it ends: the part's game stopped, its files taken away, the report written)
		OS.low_processor_usage_mode = true       # (this window only waits: the parts are measured beside it, and it must cost them nothing)
		OS.low_processor_usage_mode_sleep_usec = 250000
		_build_ui()
	_clean_stale()
	_run()

static func _arg(args, name: String, fallback: String) -> String:
	var i: int = args.find(name)
	return String(args[i + 1]) if i >= 0 and args.size() > i + 1 else fallback

static func _list_arg(args, name: String) -> PackedStringArray:
	var i: int = args.find(name)
	if i < 0 or args.size() <= i + 1:
		return PackedStringArray()
	return String(args[i + 1]).split(",", false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_aborted = true
		if _pid > 0:
			OS.kill(_pid)

func _run() -> void:
	t_start = Time.get_ticks_msec()
	_say("WRECKSMITH diagnostic test: %s" % ("quick" if opts.quick else ("every part there is" if opts.get("all", false) else "the whole of it")))
	plan_ = plan(opts)
	for i in plan_.size():
		var st: Dictionary = plan_[i]
		if _aborted:
			break
		_step_t0 = Time.get_ticks_msec()
		_running = String(st.id)
		_refresh_ui(true)
		_say("[%d/%d] %s" % [i + 1, plan_.size(), st.title])
		await _do(st, i + 1)
		_took[st.id] = float(Time.get_ticks_msec() - _step_t0) / 1000.0
		_done_ids[st.id] = true
		_running = ""
		_write_report(false)
	_clean_release()
	_clean_stale()
	_write_report(true)
	var lines := Diag.summary(results, facts, problems)
	for l in lines:
		_say(l)
	_say("The report: %s" % report_path())
	_refresh_ui(true, true)
	if windowed and not opts.get("keep", false) and not _aborted:
		await get_tree().create_timer(25.0).timeout
	get_tree().quit()

func _say(text: String) -> void:
	print("DIAGNOSE ", text)

func report_path() -> String:
	return out_dir.path_join(REPORT)

## One part: skipped when it cannot be run here, else run, read back, and told in the report.
func _do(st: Dictionary, n: int) -> void:
	var id := String(st.id)
	if bool(st.get("window", false)) and not windowed:
		_skipped[id] = "needs a window (this run has none)"
	elif bool(st.get("release", false)) and not release.ok:
		_skipped[id] = "no release build: %s" % String(release.why)
	elif String(st.get("affinity", "")) == "fast" and fast_mask(results) == 0:
		_skipped[id] = "this processor's cores are all of one speed (or the cores' part did not tell them apart)"
	elif id == "facts":
		await _facts()
		return
	elif String(st.part) == "export":
		await _export()
		if not release.ok:
			_skipped[id] = String(release.why)
		else:
			results[id] = [{"kind": "export", "exe": release.exe, "dir": release.dir}]
			_section(st, n, "made %s" % String(release.exe), results[id])
		if _skipped.has(id):
			_section(st, n, "NOT RUN: %s" % String(_skipped[id]), [])
		return
	if _skipped.has(id):
		_section(st, n, "NOT RUN: %s" % String(_skipped[id]), [])
		return
	var r := await _spawn(st, n)
	results[id] = r.results
	var head := "took %s" % DiagStats.clock(float(r.secs))
	if not bool(r.finished):
		head += ", DID NOT FINISH (%s)" % String(r.why)
		problems.append("%s did not finish: %s" % [id, String(r.why)])
	if int(r.errors) > 0:
		head += ", %d errors in its log" % int(r.errors)
		problems.append("%s: %d errors in the game's log, first: %s" % [id, int(r.errors), String(r.first_error)])
	if not (r.top as Array).is_empty() and int(r.top[0][0]) >= 50:
		problems.append("%s: the game wrote the same line %d times (%d lines in all): %s" % [id, int(r.top[0][0]), int(r.lines), String(r.top[0][1])])
	_section(st, n, head, r.results, r)

## The first part: this computer, and what else is using it (three seconds' census of the processes: in a thread, the window stays alive).
func _facts() -> void:
	facts = DiagPhase.facts()
	var th := Thread.new()
	th.start(FpsMeter.census_samples)
	while th.is_alive():
		await get_tree().create_timer(0.2).timeout
	var samples: Array = th.wait_to_finish()
	facts["census"] = FpsMeter.census_line(samples, OS.get_processor_count(), PackedInt32Array(), OS.get_process_id())
	var busy := 0
	for s in samples:
		if int(s[1]) != OS.get_process_id():   # (this window's own part of it is not "something else")
			busy += int(s[2])
	facts["busy_pct"] = float(busy) / float(maxi(1, OS.get_processor_count()) * 100) * 100.0
	if OS.get_name() == "Windows":
		var out := []
		OS.execute("powercfg", ["/getactivescheme"], out, true)
		facts["power_plan"] = " ".join(PackedStringArray(out)).strip_edges()
		var cpu_out := []   # (the cores and the clock the system says, the card's driver and its date: a stale driver is a place for stalls to hide)
		OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command", "Get-CimInstance Win32_Processor | ForEach-Object { '{0}; {1} cores, {2} logical, max {3} MHz, now {4} MHz' -f $_.Name, $_.NumberOfCores, $_.NumberOfLogicalProcessors, $_.MaxClockSpeed, $_.CurrentClockSpeed }"], cpu_out, true)
		facts["cpu_system"] = " ".join(PackedStringArray(cpu_out)).strip_edges()
		var gpu_out := []
		OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command", "Get-CimInstance Win32_VideoController | ForEach-Object { '{0}; driver {1} of {2}; {3}x{4} at {5} Hz' -f $_.Name, $_.DriverVersion, $_.DriverDate, $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate }"], gpu_out, true)
		facts["gpu_system"] = " ".join(PackedStringArray(gpu_out)).strip_edges()
	results["facts"] = [{"kind": "facts", "facts": facts}]
	if float(facts.busy_pct) > 25.0:
		problems.append("the computer was %.0f%% busy before the test began (%s): close the other programs and run it again" % [float(facts.busy_pct), String(facts.census)])
	_section({"id": "facts", "title": "what this computer is, and what else is busy on it"}, 1, "", results["facts"])

## The logical processors by their speed (the cores part's times, ms each): `fast`, those within a sixth of the fastest, and `slow`, the rest. `two` when there are at least two
## slow ones (and two fast) and they take nearly half as long again or more (a processor of two kinds of core); `mask` then holds a game to the fast ones (DiagPhase.pin), else it is 0.
static func core_classes(ms: Array) -> Dictionary:
	var out := {"fast": [], "slow": [], "fast_ms": 0.0, "slow_ms": 0.0, "two": false, "mask": 0}
	if ms.is_empty():
		return out
	var best := 1e9
	for v in ms:
		best = minf(best, float(v))
	var fast_v := []
	var slow_v := []
	for i in ms.size():
		if float(ms[i]) <= best * 1.17:
			(out.fast as Array).append(i)
			fast_v.append(float(ms[i]))
		else:
			(out.slow as Array).append(i)
			slow_v.append(float(ms[i]))
	out.fast_ms = DiagStats.median(fast_v)
	out.slow_ms = DiagStats.median(slow_v) if not slow_v.is_empty() else 0.0
	out.two = slow_v.size() >= 2 and fast_v.size() >= 2 and float(out.slow_ms) >= float(out.fast_ms) * 1.45   # (Intel's slow cores take 1.6 to 1.8 times as long; a busy or a rented machine's noise is under that)
	if bool(out.two):
		var mask := 0
		for i in out.fast:
			mask |= 1 << int(i)
		out.mask = mask
	return out

static func _cores_of(results: Dictionary) -> Dictionary:
	for d in results.get("cores", []):
		if String(d.get("kind", "")) == "cores":
			return d
	return {}

static func fast_mask(results: Dictionary) -> int:
	var d := _cores_of(results)
	return int(core_classes(d.get("ms", [])).mask) if not d.is_empty() else 0

## Starts a game for a part and waits for it (a window of this one stays alive and idle), then reads what it wrote.
func _spawn(st: Dictionary, n: int) -> Dictionary:
	var id := String(st.id)
	var rel := bool(st.get("release", false))
	var exe := String(release.exe) if rel else OS.get_executable_path()
	var base := String(release.dir) if rel else (proj if proj != "" else OS.get_executable_path().get_base_dir())
	var out_file := parts_dir.path_join("%02d_%s.txt" % [n, id])
	var log_file := parts_dir.path_join("%02d_%s.log" % [n, id])
	for f in [out_file, log_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var args := PackedStringArray()
	if not rel and proj != "":
		args.append_array(["--path", proj])
	args.append_array(PackedStringArray(st.get("engine", [])))
	args.append_array(["--log-file", log_file, "--", "--diag-phase", String(st.part), "--diag-out", out_file, "--diag-cfg", DiagStats.cfg_text(st.get("cfg", {}))])
	args.append_array(PackedStringArray(st.get("user", [])))
	var settings: Dictionary = st.get("settings", {})
	_put_override(settings, base)
	var burners := await _start_burners(int(st.get("burners", 0)))
	var t0 := Time.get_ticks_msec()
	_pid = OS.create_process(exe, args)
	var finished := false
	var why := ""
	if _pid <= 0:
		why = "the game could not be started (%s)" % exe
	else:
		if String(st.get("affinity", "")) == "fast" and not DiagPhase.pin(_pid, fast_mask(results)):
			problems.append("%s: the game could not be held to the fast cores" % id)
		if String(st.get("priority", "")) == "high" and OS.get_name() == "Windows":
			OS.execute("powershell", ["-NoProfile", "-Command", "(Get-Process -Id %d).PriorityClass = 'High'" % _pid], [], false)
		var limit := int(st.get("timeout", 300)) * 1000
		while OS.is_process_running(_pid):
			await get_tree().create_timer(0.3).timeout
			_refresh_ui()
			if _aborted:
				why = "stopped by the player"
				break
			if Time.get_ticks_msec() - t0 > limit:
				why = "no end after %d s: stopped" % int(limit / 1000)
				break
		if OS.is_process_running(_pid):
			OS.kill(_pid)
			await get_tree().create_timer(0.5).timeout
		else:
			finished = true
	_pid = 0
	for b in burners:
		OS.kill(int(b))
	_remove_override(base)
	var text := FileAccess.get_file_as_string(out_file) if FileAccess.file_exists(out_file) else ""
	var res := DiagStats.read_results(text)
	var done := res.any(func(d): return String(d.get("kind", "")) == "done")
	if finished and not done:
		finished = false
		why = "the game ended without saying it was done (it crashed?)"
	for d in res:   # (friend windows the room's game left behind)
		if String(d.get("kind", "")) == "room" and d.has("pids"):
			for pid in d.pids:
				if OS.is_process_running(int(pid)):
					OS.kill(int(pid))
	var scan := _scan_log(log_file)
	return {"results": res, "finished": finished, "why": why, "secs": float(Time.get_ticks_msec() - t0) / 1000.0, "errors": scan.errors, "first_error": scan.first, "log": log_file, "lines": scan.lines, "top": scan.top}

## Errors a pack made for the test always has: the libraries of the extensions that are not the native core's (Steam's) are not beside its executable.
static func _benign(line: String) -> bool:
	return line.contains("GDExtension") or line.contains("dynamic library") or line.contains("Error loading extension") or line.contains("status < 0")

## What a game's log says of trouble: the lines that are errors and the first of them, how many lines it wrote, and the lines it wrote over and over (digits aside): a game that
## writes thousands of lines is slowed by it, above all one run in a console.
static var _digits_re: RegEx = null
static func _scan_log(path: String) -> Dictionary:
	var n := 0
	var first := ""
	var lines := 0
	var counts := {}
	if _digits_re == null:
		_digits_re = RegEx.new()
		_digits_re.compile("[0-9]+")
	if FileAccess.file_exists(path):
		for l in FileAccess.get_file_as_string(path).split("\n", false):
			if l.begins_with("DIAG "):
				continue   # (the part's own results)
			lines += 1
			if (l.begins_with("ERROR:") or l.begins_with("SCRIPT ERROR") or l.begins_with("USER ERROR") or l.contains("Parse Error")) and not _benign(l):
				n += 1
				if first == "":
					first = l.left(220)
			var key := _digits_re.sub(l.left(100), "#", true)
			counts[key] = int(counts.get(key, 0)) + 1
	var top := []
	for k in counts:
		if int(counts[k]) >= 20:
			top.append([int(counts[k]), k])
	top.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	return {"errors": n, "first": first, "lines": lines, "top": top.slice(0, 3)}

## The burners: games that take a third of a core each, at below-normal priority as the playtest's friend windows are, given time to load before the part begins.
func _start_burners(n: int) -> Array:
	var pids := []
	if n <= 0:
		return pids
	for i in n:
		var a := PackedStringArray()
		if proj != "":
			a.append_array(["--path", proj])
		a.append_array(["--headless", "--log-file", parts_dir.path_join("burn_%d.log" % i), "--", "--diag-phase", "burn"])
		var pid := OS.create_process(OS.get_executable_path(), a)
		if pid > 0:
			pids.append(pid)
	if OS.get_name() == "Windows" and not pids.is_empty():
		OS.execute("powershell", ["-NoProfile", "-Command", "Get-Process -Id %s | ForEach-Object { $_.PriorityClass = 'BelowNormal' }" % ",".join(PackedStringArray(pids.map(func(x): return str(x))))], [], false)
	elif not pids.is_empty():
		OS.execute("renice", ["-n", "10", "-p"] + pids.map(func(x): return str(x)), [], false)
	await get_tree().create_timer(10.0).timeout
	return pids

# ---------- override.cfg ----------

func _put_override(settings: Dictionary, dir: String) -> void:
	if settings.is_empty():
		return
	var p := dir.path_join("override.cfg")
	if FileAccess.file_exists(p) and not FileAccess.get_file_as_string(p).begins_with("; " + MARK):
		DirAccess.rename_absolute(p, p + ".diag_backup")   # (the player's own: put back when the part ends)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(override_for(settings))
		f.close()

func _remove_override(dir: String) -> void:
	var p := dir.path_join("override.cfg")
	if FileAccess.file_exists(p) and FileAccess.get_file_as_string(p).begins_with("; " + MARK):
		DirAccess.remove_absolute(p)
	if FileAccess.file_exists(p + ".diag_backup") and not FileAccess.file_exists(p):
		DirAccess.rename_absolute(p + ".diag_backup", p)

## A file of ours left by a run that was killed, and the player's own put back.
func _clean_stale() -> void:
	for d in [proj, String(release.dir)]:
		if d != "":
			_remove_override(d)

# ---------- the release build ----------

## A game as a player runs it: the project's pack (`--export-pack`: no icon to edit, no installer) next to a copy of Godot's release template and the native core's library.
func _export() -> void:
	release = {"ok": false, "why": "", "dir": "", "exe": ""}
	if not OS.has_feature("editor"):
		release.why = "this game is already an exported one"
		return
	var tmpl := template_path()
	if tmpl == "" or not FileAccess.file_exists(tmpl):
		release.why = "Godot's export templates for %s are not installed (Editor, Manage Export Templates, Download; or tools\\package.bat --install-templates): %s" % [String(Engine.get_version_info().get("string", "?")), tmpl if tmpl != "" else "no template for this system"]
		return
	var dir := proj.path_join("build/diag")
	DirAccess.make_dir_recursive_absolute(dir)
	var windows_os := OS.get_name() == "Windows"
	var pack := dir.path_join("diag.pck")
	var exe := dir.path_join("diag.exe" if windows_os else "diag.x86_64")
	var log_file := parts_dir.path_join("export.log")
	for f in [pack, exe, log_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var preset := "Windows Desktop" if windows_os else "Linux"
	_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--quiet", "--path", proj, "--log-file", log_file, "--export-pack", preset, pack])
	var t0 := Time.get_ticks_msec()
	while _pid > 0 and OS.is_process_running(_pid):
		await get_tree().create_timer(0.3).timeout
		_refresh_ui()
		if _aborted or Time.get_ticks_msec() - t0 > 400000:
			OS.kill(_pid)
			break
	_pid = 0
	if not FileAccess.file_exists(pack):
		var errs := _scan_log(log_file)
		release.why = "the pack was not made (%s)" % (String(errs.first) if String(errs.first) != "" else "no preset named '%s'?" % preset)
		return
	if DirAccess.copy_absolute(tmpl, exe) != OK:
		release.why = "the template could not be copied to %s" % exe
		return
	if not windows_os:
		OS.execute("chmod", ["+x", exe])
	var native_dir := proj.path_join("native/bin")
	var d := DirAccess.open(native_dir)
	if d != null:
		for f in d.get_files():
			if (windows_os and f.ends_with(".dll")) or (not windows_os and f.ends_with(".so")):
				DirAccess.copy_absolute(native_dir.path_join(f), dir.path_join(f))   # (next to the executable, where the engine looks for a library that is not on the disk under res://)
	release = {"ok": true, "why": "", "dir": dir, "exe": exe}

func _clean_release() -> void:
	if String(release.dir) == "" or opts.get("keep", false):
		return
	var d := DirAccess.open(String(release.dir))
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(String(release.dir).path_join(f))
	DirAccess.remove_absolute(String(release.dir))

# ---------- the report ----------

func _section(st: Dictionary, n: int, head: String, res: Array, info := {}) -> void:
	var lines := PackedStringArray(["", "== %d. %s  [%s] %s ==" % [n, String(st.title), String(st.id), head]])
	for d in res:
		var t := DiagStats.result_text(d)
		if t != "":
			lines.append(t)
	if info.has("top") and not (info.top as Array).is_empty():
		lines.append("  the game's log: %d lines; the lines it wrote over and over:" % int(info.lines))
		for tp in info.top:
			lines.append("    x%d  %s" % [int(tp[0]), String(tp[1])])
	if info.has("log") and (not bool(info.finished) or int(info.errors) > 0):
		var log := FileAccess.get_file_as_string(String(info.log)) if FileAccess.file_exists(String(info.log)) else ""
		lines.append("  --- the game's log (the first lines that are errors):")
		var shown := 0
		for l in log.split("\n", false):
			if (l.begins_with("ERROR:") or l.begins_with("SCRIPT ERROR") or l.begins_with("USER ERROR") or l.contains("Parse Error")) and not _benign(l):
				lines.append("  " + l.left(240))
				shown += 1
				if shown >= 8:
					break
	sections.append("\n".join(lines))

func _write_report(final: bool) -> void:
	var head := PackedStringArray()
	head.append("WRECKSMITH diagnostic report (test version %d)  %s  %s" % [DIAG_VERSION, Time.get_datetime_string_from_system(), "took %s" % DiagStats.clock(float(Time.get_ticks_msec() - t_start) / 1000.0)])
	head.append("%s" % ("a quick run: shortened, for a look" if opts.get("quick", false) else "the whole test"))
	if not final:
		head.append("(not finished: this is what had been measured so far)")
	var text := "\n".join(head) + "\n"
	if final:
		text += "\n== SUMMARY ==\n" + "\n".join(Diag.summary(results, facts, problems)) + "\n"
	text += "\n".join(sections) + "\n"
	if final:
		text += "\n== RAW (one result a line) ==\n"
		for id in results:
			for d in results[id]:
				if String(d.get("kind", "")) != "record":
					text += "%s %s\n" % [id, DiagStats.encode(d)]
	var f := FileAccess.open(report_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

const DIAG_VERSION := 3

## What the run found, in the numbers that decide, as lines (the top of the report and what the window says at the end).
static func summary(results: Dictionary, facts: Dictionary, problems: PackedStringArray) -> Array:
	var out := []
	if not facts.is_empty():
		out.append("THIS COMPUTER  %s, %d threads, %d MB of memory; %s %s; %s; %s" % [String(facts.get("cpu", "?")), int(facts.get("threads", 0)), int(facts.get("ram_mb", 0)), String(facts.get("os", "?")), String(facts.get("os_version", "")),
			(String(facts.get("adapter", "")) + " (" + String(facts.get("driver", "?")) + ")") if facts.has("adapter") else "no window", String(facts.get("godot", "?")) + (", the editor's binary (a debug build)" if bool(facts.get("editor_binary", false)) else ", an exported game")])
		out.append("               native core %s; busy before the test %.0f%%" % ["ON" if bool(facts.get("native_core", false)) else "OFF (a fifth dearer a step)", float(facts.get("busy_pct", 0.0))])
	# the step
	var steps: Array = results.get("steps_auto", [])
	for d in steps:
		if String(d.get("kind", "")) == "step" and not String(d.get("flags", "")).contains("gd") and not String(d.get("flags", "")).contains("bare") and not d.has("win"):
			out.append("THE STEP       %-24s %5.2f ms (the scripts' %.2f, the engine's %.2f) of the %.2f there is: %s" % [String(d.mix), float(d.ms), float(d.get("scripts_ms", 0.0)), float(d.get("engine_ms", 0.0)), BUDGET_MS, _speed_word(float(d.ms))])
	var base8 := _step_of(steps, "men:8", "")
	var gd8 := _step_of(steps, "men:8", "gd")
	var bare8 := _step_of(steps, "men:8", "bare")
	if not base8.is_empty() and not gd8.is_empty():
		out.append("NATIVE CORE    men:8 %.2f ms; with the scripts' own ways %.2f ms (%s)" % [float(base8.ms), float(gd8.ms), DiagStats.change(float(gd8.ms), float(base8.ms))])
	if not base8.is_empty() and not bare8.is_empty():
		out.append("ARMOUR         men:8 in armour %.2f ms, bare %.2f ms (%s)" % [float(base8.ms), float(bare8.ms), DiagStats.change(float(bare8.ms), float(base8.ms))])
	for d in steps:
		if String(d.get("kind", "")) == "step" and d.has("win"):
			var w: Array = d.win
			if w.size() >= 2:
				out.append("DRIFT          %s over %d s: %.2f ms in the first five seconds, %.2f in the last (%s; a fight that thins out falls by itself, men standing still would show a clock that slows)" % [String(d.label), int(d.secs), float(w[0]), float(w[w.size() - 1]), DiagStats.change(float(w[0]), float(w[w.size() - 1]))])
		if String(d.get("kind", "")) == "cpu_loop":
			out.append("CORE SPEED     a fixed piece of script work took %.0f ms (the test's own machine: %.0f ms): %.2f times as fast" % [float(d.ms), float(d.ref_ms), float(d.ref_ms) / maxf(0.01, float(d.ms))])
	# the cores
	var cd := _cores_of(results)
	var cc := core_classes(cd.get("ms", []))
	if not cd.is_empty():
		var ref := float(cd.get("ref_ms", 8.25))
		var who := "a game with a window" if bool(cd.get("window", false)) else "a game with no window"
		if bool(cc.two):
			out.append("CORES          %d logical processors are fast (an eighth of that work in %.1f ms: %.2f times the test's own machine) and %d are slow (%.1f ms: %.2f times as fast as the fast ones); let go, the system gave %s %.1f ms" % [(cc.fast as Array).size(), float(cc.fast_ms),
				ref / maxf(0.01, float(cc.fast_ms)), (cc.slow as Array).size(), float(cc.slow_ms), float(cc.fast_ms) / maxf(0.01, float(cc.slow_ms)), who, float(cd.get("free_ms", 0.0))])
		else:
			var all_ms: Array = cd.ms
			out.append("CORES          the %d logical processors are of one speed (an eighth of that work in %.1f to %.1f ms: %.2f times the test's own machine); let go, the system gave %s %.1f ms" % [all_ms.size(), float(DiagStats.sorted(all_ms)[0]),
				DiagStats.worst(all_ms), ref / maxf(0.01, DiagStats.median(all_ms)), who, float(cd.get("free_ms", 0.0))])
	var plays := []
	for id in ["fight_base", "release_fight", "fight_half", "fight_fast", "fight_threads", "room_eight", "release_room", "room_half", "room_threads"]:
		var v := []
		for d in results.get(id, []):
			if String(d.get("kind", "")) == "sample" and d.has("core_ms"):
				v.append(float(d.core_ms))
		if v.size() >= 2:
			plays.append("%s %.1f ms (%.1f to %.1f)" % [id, DiagStats.median(v), float(DiagStats.sorted(v)[0]), DiagStats.worst(v)])
	if not plays.is_empty():
		out.append("IN PLAY        the same work on the game's own thread while it played (the middle one, the least and the most): " + "; ".join(plays))
	# the threads
	var tl := []
	for n in [1, 2, 4, 8]:
		var d := _step_of(results.get("steps_t%d" % n, []), "men:8,foe:3", "")
		if not d.is_empty():
			tl.append("%d thread%s %.2f (engine %.2f)" % [n, "" if n == 1 else "s", float(d.ms), float(d.get("engine_ms", 0.0))])
	var auto3 := _step_of(steps, "men:8,foe:3", "")
	if not auto3.is_empty():
		tl.append("the engine's pick %.2f (engine %.2f)" % [float(auto3.ms), float(auto3.get("engine_ms", 0.0))])
	if not tl.is_empty():
		out.append("THREADS        men:8,foe:3: " + ", ".join(tl))
	# release
	var rel := _step_of(results.get("release_steps", []), "men:8,foe:3", "")
	if not rel.is_empty() and not auto3.is_empty():
		out.append("RELEASE BUILD  men:8,foe:3 %.2f ms against the editor's %.2f ms (%s)" % [float(rel.ms), float(auto3.ms), DiagStats.change(float(auto3.ms), float(rel.ms))])
	var rel8 := _step_of(results.get("release_steps", []), "men:8", "")
	if not rel8.is_empty() and not base8.is_empty():
		out.append("               men:8 %.2f ms against the editor's %.2f ms (%s)" % [float(rel8.ms), float(base8.ms), DiagStats.change(float(base8.ms), float(rel8.ms))])
	var win3 := _step_of(results.get("steps_window", []), "men:8,foe:3", "")
	if not win3.is_empty() and not auto3.is_empty():
		var wl := "%.2f ms with a window of its own, %.2f ms with none (%s)" % [float(win3.ms), float(auto3.ms), DiagStats.change(float(auto3.ms), float(win3.ms))]
		var loop_w := 0.0
		var loop_h := 0.0
		var loop_f := 0.0
		for d in results.get("steps_window", []):
			if String(d.get("kind", "")) == "cpu_loop":
				loop_w = float(d.ms)
		for d in steps:
			if String(d.get("kind", "")) == "cpu_loop":
				loop_h = float(d.ms)
		for d in results.get("fight_base", []):
			if String(d.get("kind", "")) == "cpu_loop":
				loop_f = float(d.ms)
		out.append("WINDOWLESS     men:8,foe:3 %s; a fixed piece of script work %.0f ms in the fight's window, %.0f ms in the small one, %.0f ms with none" % [wl, loop_f, loop_w, loop_h])
	var thr_bits := []
	for mix in ["men:8", "men:8,foe:3", "men:8,foe:8"]:
		var a := _step_of(steps, mix, "")
		var b := _step_of(results.get("steps_threads", []), mix, "thr")
		if not a.is_empty() and not b.is_empty():
			thr_bits.append("%s %.2f ms against %.2f (%s)" % [mix, float(b.ms), float(a.ms), DiagStats.change(float(a.ms), float(b.ms))])
	if not thr_bits.is_empty():
		out.append("CONTROL THREADS (an experiment) the men's controls on the worker threads: " + "; ".join(thr_bits))
	var half_bits := []
	for mix in ["men:8", "men:8,foe:3", "men:8,foe:8"]:
		var a2 := _step_of(steps, mix, "")
		var b2 := _step_of(results.get("steps_half", []), mix, "half")
		if not a2.is_empty() and not b2.is_empty():
			half_bits.append("%s %.2f ms against %.2f (%s)" % [mix, float(b2.ms), float(a2.ms), DiagStats.change(float(a2.ms), float(b2.ms))])
	if not half_bits.is_empty():
		out.append("CONTROL AT 60  (an experiment) a man's control every other step, the bodies stepped as ever: " + "; ".join(half_bits))
	var fast3 := _step_of(results.get("steps_fast", []), "men:8,foe:3", "")
	if not fast3.is_empty() and not auto3.is_empty():
		out.append("FAST CORES     men:8,foe:3 %.2f ms with no window held to the fast cores, %.2f ms where the system puts a game with no window (%s)" % [float(fast3.ms), float(auto3.ms), DiagStats.change(float(auto3.ms), float(fast3.ms))])
	var burn := _step_of(results.get("steps_burners", []), "men:8,foe:3", "")
	if not burn.is_empty() and not auto3.is_empty():
		out.append("FRIEND WINDOWS men:8,foe:3 %.2f ms with seven busy games beside it (a third of a core each, no network), %.2f ms alone (%s)" % [float(burn.ms), float(auto3.ms), DiagStats.change(float(auto3.ms), float(burn.ms))])
	# the frame
	for id in FIGHTS:
		var w := _frames_of(results.get(id, []), "fight, the rest")
		if not w.is_empty():
			var c: Dictionary = w.get("comp", {})
			out.append("THE FRAME      %-22s %5.1f ms a frame, %4.0f%% speed; steps %.1f (scripts %.1f, engine %.1f) + between %.1f + scripts %.1f + drawing/waiting %.1f; card %.1f ms, %d draws" % [id, float(w.ms.mean), float(w.speed) * 100.0,
				float(c.get("steps", 0.0)), float(c.get("step_scripts", 0.0)) * float(c.get("per_frame", 1.0)), float(c.get("step_engine", 0.0)) * float(c.get("per_frame", 1.0)), float(c.get("between", 0.0)), float(c.get("scripts", 0.0)), float(c.get("draw_wait", 0.0)), float(w.get("gpu", 0.0)), int(w.get("calls", 0))])
	out.append_array(_fight_ab(results))
	# the stalls
	for id in ["fight_base", "fight_cold", "release_fight"]:
		var w1 := _frames_of(results.get(id, []), "fight, the first")
		if not w1.is_empty():
			out.append("STALLS         %-22s the first seconds: %d frames over 50 ms, %d over 100, the worst %.0f ms, %d pipelines compiled" % [id, int(w1.over50), int(w1.over100), float(w1.ms.max), int(w1.get("pipes", 0))])
	# render A/B
	var base_r := _frames_of(results.get("render_steady", []), "as the player has it")
	if not base_r.is_empty():
		var bits := []
		for w2 in results.get("render_steady", []):
			if String(w2.get("kind", "")) == "frames" and String(w2.label) != "as the player has it" and String(w2.label) != "as the player has it, again":
				bits.append("%s %.1f" % [String(w2.label), float(w2.ms.mean)])
		out.append("RENDER A/B     as the player has it %.1f ms (card %.1f); %s" % [float(base_r.ms.mean), float(base_r.get("gpu", 0.0)), "; ".join(bits)])
	# what a fight leaves, drawn
	var base_w := _frames_of(results.get("wreck", []), "stopped where it is")
	if not base_w.is_empty():
		var bits_w := []
		for w3 in results.get("wreck", []):
			if String(w3.get("kind", "")) == "frames" and w3.has("took_away"):
				bits_w.append("%s %+.1f%s" % [String(w3.label), float(w3.ms.mean) - float(base_w.ms.mean), (" (%d things)" % int(w3.took_away)) if int(w3.took_away) > 0 else ""])
		var played := 45.0
		for w4 in results.get("wreck", []):
			if String(w4.get("kind", "")) == "start":
				played = DiagStats.cfg_f(w4.get("cfg", {}), "play", 45.0)
		out.append("WRECK          a fight stopped where it is at %d s: %.1f ms a frame (card %.1f, %d draws); against it: %s" % [int(played), float(base_w.ms.mean), float(base_w.get("gpu", 0.0)), int(base_w.get("calls", 0)), "; ".join(bits_w)])
	# the read-back
	for d in results.get("readback", []):
		if String(d.get("kind", "")) == "readback":
			var g1: Dictionary = d.get("get_first", {})
			var s1: Dictionary = d.get("set_first", {})
			var b1: Dictionary = d.get("buffer_first", {})
			out.append("READ-BACK      a part's MultiMesh asked for one voxel the first time: %.2f ms (the worst %.2f); written one the first time: %.2f ms (the worst %.2f); its whole buffer read: %.2f ms (the worst %.2f); the time after: %.3f ms" % [float(g1.get("median", 0.0)),
				float(g1.get("worst", 0.0)), float(s1.get("median", 0.0)), float(s1.get("worst", 0.0)), float(b1.get("median", 0.0)), float(b1.get("worst", 0.0)), float((d.get("get_next", {}) as Dictionary).get("median", 0.0))])
	# the room
	for room in [["room_eight", "THE ROOM       "], ["release_room", "ROOM, RELEASE  "], ["room_half", "ROOM, AT 60    "], ["room_threads", "ROOM, THREADS  "]]:
		var rw := []
		for d in results.get(String(room[0]), []):
			if String(d.get("kind", "")) == "frames" and String(d.label).begins_with("room, endless"):
				rw.append("%.0f%% %.0f fps (a step %.1f)" % [float(d.speed) * 100.0, float(d.fps), float(d.get("step_ms", 0.0))])
		if not rw.is_empty():
			out.append(String(room[1]) + "game speed and frames in each half minute: " + ", ".join(rw))
	for p in problems:
		out.append("PROBLEM        " + p)
	if out.is_empty():
		out.append("nothing was measured")
	return out

const FIGHTS := ["fight_base", "release_fight", "fight_half", "fight_fast", "fight_threads", "fight_sound", "fight_cold", "fight_render_thread", "fight_vulkan", "fight_d3d12", "fight_no_interpolation", "fight_fullscreen", "fight_high_priority"]

## Each fight against the base: the game's speed, a step, and what the rest of a frame is (between + scripts + drawing and waiting): which of the two a setting changes.
static func _fight_ab(results: Dictionary) -> Array:
	var out := []
	var base := _frames_of(results.get("fight_base", []), "fight, the rest")
	if base.is_empty() or not base.has("comp"):
		return out
	var bc: Dictionary = base.comp
	var b_step := float(bc.get("steps", 0.0)) / maxf(0.5, float(bc.get("per_frame", 1.0)))
	var b_rest := float(bc.get("between", 0.0)) + float(bc.get("scripts", 0.0)) + float(bc.get("draw_wait", 0.0))
	var bits := []
	for id in FIGHTS:
		if id == "fight_base":
			continue
		var w := _frames_of(results.get(id, []), "fight, the rest")
		if w.is_empty() or not w.has("comp"):
			continue
		var c: Dictionary = w.comp
		var step := float(c.get("steps", 0.0)) / maxf(0.5, float(c.get("per_frame", 1.0)))
		var rest := float(c.get("between", 0.0)) + float(c.get("scripts", 0.0)) + float(c.get("draw_wait", 0.0))
		bits.append("%s: speed %.0f%% (%+.0f points), a step %.1f ms (%s), the rest of a frame %.1f ms (%s)" % [id.trim_prefix("fight_"), float(w.speed) * 100.0, (float(w.speed) - float(base.speed)) * 100.0, step, DiagStats.change(b_step, step), rest, DiagStats.change(b_rest, rest)])
	if not bits.is_empty():
		out.append("FIGHT A/B      against the base (speed %.0f%%, a step %.1f ms, the rest of a frame %.1f ms):" % [float(base.speed) * 100.0, b_step, b_rest])
		for b in bits:
			out.append("                 " + b)
	return out

static func _speed_word(ms: float) -> String:
	return "smooth" if ms <= BUDGET_MS * 0.85 else ("at the limit" if ms <= BUDGET_MS * 1.1 else "too slow: %d%% of the game's speed" % roundi(100.0 * BUDGET_MS / maxf(0.01, ms)))

static func _step_of(list: Array, mix: String, flag: String) -> Dictionary:
	for d in list:
		if String(d.get("kind", "")) == "step" and String(d.get("mix", "")) == mix and (flag == "" and String(d.get("flags", "")) == "" or (flag != "" and String(d.get("flags", "")).contains(flag))) and not d.has("win"):
			return d
	return {}

static func _frames_of(list: Array, label_start: String) -> Dictionary:
	for d in list:
		if String(d.get("kind", "")) == "frames" and String(d.get("label", "")).begins_with(label_start):
			return d
	return {}

# ---------- the window ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24
	box.offset_top = 18
	box.offset_right = -24
	box.offset_bottom = -18
	layer.add_child(box)
	var title := Label.new()
	title.text = "WRECKSMITH diagnostic test"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.93, 0.78, 0.45))
	box.add_child(title)
	_ui_text = RichTextLabel.new()
	_ui_text.bbcode_enabled = true
	_ui_text.scroll_active = false
	_ui_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_text.add_theme_font_size_override("normal_font_size", 14)
	_ui_text.add_theme_font_size_override("bold_font_size", 14)
	box.add_child(_ui_text)
	_ui_foot = Label.new()
	_ui_foot.add_theme_font_size_override("font_size", 14)
	_ui_foot.add_theme_color_override("font_color", Color(0.75, 0.68, 0.58))
	_ui_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_ui_foot)

func _refresh_ui(force := false, finished := false) -> void:
	if _ui_text == null:
		return
	var now := Time.get_ticks_usec()
	if not force and now < _ui_next_us:
		return
	_ui_next_us = now + 500000
	var lines := PackedStringArray()
	var left := 0.0
	var elapsed := float(Time.get_ticks_msec() - t_start) / 1000.0
	for st in plan_:
		var id := String(st.id)
		var mark := "[color=#7a6d5c][ ][/color]"
		var est := float(st.get("est", 30))
		if _done_ids.has(id):
			mark = "[color=#7ac36a][ok][/color]" if not _skipped.has(id) else "[color=#9a8f80][--][/color]"
		elif _running == id:
			var spent := float(Time.get_ticks_msec() - _step_t0) / 1000.0
			mark = "[color=#e0b44c][>>][/color]"
			left += maxf(est * 0.2, est - spent)
		else:
			left += est
		lines.append("%s %s%s" % [mark, String(st.title), (" [color=#9a8f80](%s)[/color]" % String(_skipped[id])) if _skipped.has(id) else ""])
	_ui_text.text = "\n".join(lines)
	if finished:
		_ui_foot.text = "Done in %s. The report is %s: send that one file.\nThis window closes by itself." % [DiagStats.clock(elapsed), report_path()]
	else:
		_ui_foot.text = "Running: %s elapsed, about %s to go. Leave the computer alone (no browser, no recorder, no other game) until this window says it is done.\nClosing this window stops the test and keeps what was measured." % [DiagStats.clock(elapsed), DiagStats.clock(left)]
