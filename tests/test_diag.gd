extends Node
## The diagnostic test (scripts/diag, tools/diagnose.bat): its arithmetic and wording, the plan, the files it leaves and takes away, the reading of a frame's make-up, a part run in this
## very game, and the report it writes. (The whole of it, one run of every part, is the "diag" check of run_tests.sh.)

var t

class Burner extends Node:
	var us := 0
	func _init(prio: int, micro: int) -> void:
		process_priority = prio
		us = micro
	func _process(_dt: float) -> void:
		OS.delay_usec(us)

class StepBurner extends Node:
	var us := 0
	func _physics_process(_dt: float) -> void:
		OS.delay_usec(us)

## A coroutine that waited for the frame, as the staged builds are.
class Waiter extends Node:
	var us := 0
	var on := true
	func _ready() -> void:
		_loop()
	func _loop() -> void:
		while on and is_inside_tree():
			await get_tree().process_frame
			OS.delay_usec(us)

class Napper extends Node:
	var go := false
	func _process(_dt: float) -> void:
		if go:
			go = false
			OS.delay_msec(90)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

# ---------- the numbers and the words ----------

func test_the_numbers() -> void:
	var a := PackedFloat32Array()
	for i in 100:
		a.append(float(i + 1))
	t.check(DiagStats.percentile(a, 0.99) == 99.0 and DiagStats.percentile(a, 0.5) == 50.0 and DiagStats.worst(a) == 100.0, "percentiles of 1 to 100 (%.0f, %.0f)" % [DiagStats.percentile(a, 0.99), DiagStats.percentile(a, 0.5)])
	t.check(DiagStats.median([3.0, 1.0, 2.0]) == 2.0 and DiagStats.mean([2.0, 4.0]) == 3.0 and DiagStats.mean([]) == 0.0, "median and mean, and the mean of nothing")
	t.check(DiagStats.change(10.0, 8.0) == "-20%" and DiagStats.change(10.0, 12.0) == "+20%" and DiagStats.change(0.0, 5.0) == "n/a", "a change as a percent (%s %s)" % [DiagStats.change(10.0, 8.0), DiagStats.change(0.0, 5.0)])
	t.check(DiagStats.clock(754.0) == "12m34s" and DiagStats.clock(5.0) == "0m05s", "a clock (%s)" % DiagStats.clock(754.0))

func test_what_a_part_is_told_and_what_it_says() -> void:
	var cfg := DiagStats.parse_cfg("mixes=men:4+men:8,foe:3#gd+men:8@30;secs=6;label=a = b")
	t.check(cfg.mixes == "men:4+men:8,foe:3#gd+men:8@30" and cfg.secs == "6" and cfg.label == "a = b", "the arguments are read (%s)" % str(cfg))
	t.check(DiagStats.plus_list(cfg.mixes).size() == 3 and DiagStats.plus_list(cfg.mixes)[1] == "men:8,foe:3#gd", "a list of mixes")
	t.check(DiagStats.cfg_i(cfg, "secs", 1) == 6 and DiagStats.cfg_f(cfg, "nope", 2.5) == 2.5 and DiagStats.cfg_s(cfg, "label", "") == "a = b", "with a fallback for what is not there")
	t.check(DiagStats.parse_cfg(DiagStats.cfg_text({"a": 1, "b": "x+y"})).b == "x+y", "written and read back")
	var d := {"kind": "step", "ms": 7.123456, "list": [1.23456, 2], "n": {"x": 0.00123}}
	var back := DiagStats.decode(DiagStats.encode(d))
	t.check(is_equal_approx(float(back.ms), 7.12) and is_equal_approx(float(back.list[0]), 1.23) and int(back.list[1]) == 2 and is_equal_approx(float(back.n.x), 0.0), "a result line: floats to two places, the rest as it was (%s)" % DiagStats.encode(d))
	t.check(DiagStats.decode("not json").is_empty() and DiagStats.read_results("{\"a\": 1}\ngarbage\n\n{\"b\": 2}\n").size() == 2, "a line that is not a result is not one")

func test_override_cfg_text() -> void:
	var s := DiagStats.override_text({"threading/worker_pool/max_threads": 4, "rendering/driver/threads/thread_model": 2, "physics/common/physics_interpolation": false, "rendering/rendering_device/driver.windows": "vulkan"}, "mark")
	t.check(s.begins_with("; mark\n"), "the first line is the mark: how the test knows the file is its own")
	t.check(s.contains("[threading]\n\nworker_pool/max_threads=4\n"), "a setting under its section: %s" % s)
	t.check(s.contains("driver/threads/thread_model=2") and s.contains("common/physics_interpolation=false") and s.contains("rendering_device/driver.windows=\"vulkan\""), "numbers as they are, a bool in lower case, a string in quotes")
	var cfg := ConfigFile.new()
	t.check(cfg.parse(s) == OK and int(cfg.get_value("threading", "worker_pool/max_threads", 0)) == 4 and cfg.get_value("physics", "common/physics_interpolation", true) == false, "the engine's own reader takes it")

func test_the_words_of_a_window() -> void:
	var w := {"kind": "frames", "label": "fight, the rest", "secs": 30.0, "frames": 600, "fps": 20.0, "ms": {"mean": 50.0, "p50": 48.0, "p95": 70.0, "p99": 90.0, "max": 130.0}, "over33": 500, "over50": 200, "over100": 3, "steps": 1800, "steps_s": 60.0, "speed": 0.5,
		"hitch_ms": 50.0, "hitch_n": 20, "hitches": [{"t": 3.2, "ms": 130.0, "steps": 4, "dnodes": 20, "dres": 5, "dpipes": 3, "note": "match setup"}],
		"comp": {"n": 590, "frame": 50.0, "steps": 30.0, "per_frame": 3.0, "gap": 10.0, "step_scripts": 7.0, "step_engine": 2.5, "between": 5.5, "scripts": 6.0, "tail": 2.0, "draw_wait": 8.5}, "gpu": 6.0, "cpu_draw": 1.5, "calls": 900, "objects": 400, "prims": 2000000, "pipes": 3, "nodes": 1800, "mem_mb": 700}
	var s := DiagStats.frames_text(w)
	t.check(s.contains("speed  50%") and s.contains("steps 30.0 (3.0 a frame: the scripts' 7.00 and the engine's 2.50 each") and s.contains("between them and the scripts 5.5") and s.contains("drawing and waiting 8.5"), "the make-up of a frame is told: %s" % s)
	t.check(s.contains("the card 6.0 ms") and s.contains("900 draw calls") and s.contains("HITCH at 3.2 s: 130 ms") and s.contains("after: match setup") and s.contains("20 frames over 50 ms in all"), "and the card, the stalls with what came before them")
	t.check(DiagStats.result_text(w).begins_with("  fight, the rest"), "indented into the report")
	var st := {"kind": "step", "label": "men:8", "men": 9, "ms": 10.0, "median": 8.5, "p99": 14.0, "worst": 20.0, "scripts_ms": 6.5, "engine_ms": 1.5}
	var line := DiagStats.step_text(st)
	t.check(line.contains("too slow: 83% speed") and line.contains("the nodes' scripts 6.50 ms") and line.contains("2.00 ms before them"), "a step: the verdict and where it went (%s)" % line)
	t.check(DiagStats.step_text({"ms": 6.0}).contains("smooth") and DiagStats.step_text({"ms": 8.8}).contains("at the limit"), "smooth and at the limit")

# ---------- the plan ----------

func _ids(p: Array) -> Array:
	return p.map(func(s): return String(s.id))

func test_the_plan_of_a_whole_run() -> void:
	var p := Diag.plan({"windowed": true, "editor": true, "os": "Windows", "driver": "d3d12"})
	var ids := _ids(p)
	t.check(ids[0] == "facts" and ids.size() == (ids as Array).size() and ids.count("facts") == 1, "the facts come first")
	for id in ["steps_auto", "steps_t1", "steps_t2", "steps_t4", "steps_t8", "steps_burners", "fight_sound", "release_export", "release_steps", "fight_base", "release_fight", "fight_cold", "fight_render_thread", "fight_vulkan", "fight_no_interpolation", "fight_fullscreen", "fight_high_priority", "render_steady", "room_eight"]:
		t.check(ids.has(id), "the plan has %s (%s)" % [id, ", ".join(PackedStringArray(ids))])
	t.check(not ids.has("fight_d3d12"), "the other renderer is the one that is not in use")
	t.check(ids.find("steps_auto") < ids.find("release_export") and ids.find("release_export") < ids.find("release_steps") and ids.find("release_steps") < ids.find("fight_base") and ids.find("fight_base") < ids.find("room_eight"), "in the order: the step, the release build, the frame, the room")
	var seen := {}
	var ok := true
	for st in p:
		if seen.has(st.id) or not ["facts", "steps", "fight", "render", "room", "export"].has(String(st.part)) or float(st.get("est", 0)) <= 0.0 or float(st.get("timeout", 0)) <= 0.0:
			ok = false
		seen[st.id] = true
		if bool(st.get("release", false)) and (st.has("settings") or not (st.get("engine", []) as Array).has("--headless") and String(st.part) == "steps"):
			ok = false
	t.check(ok, "every part has a name of its own, a kind the parts know, an estimate and a timeout")
	var room: Dictionary = p[ids.find("room_eight")]
	t.check((room.user as Array).has("--host") and (room.user as Array).has("--playtest") and (room.user as Array).has("--bot") and int(DiagStats.cfg_i(room.cfg, "friends", 0)) == 7 and room.window, "the room is the playtest's: a host, seven friends, the host's man played by a bot")
	var cold: Dictionary = p[ids.find("fight_cold")]
	t.check(cold.settings.has("rendering/rendering_device/pipeline_cache/enable") and cold.settings.has("rendering/shader_compiler/shader_cache/enabled"), "the cold run turns the caches off")
	var thr: Dictionary = p[ids.find("steps_t4")]
	t.check(int(thr.settings["threading/worker_pool/max_threads"]) == 4, "a thread part sets its thread count")
	var burn: Dictionary = p[ids.find("steps_burners")]
	t.check(int(burn.burners) == 7 and not burn.has("settings") and String(burn.part) == "steps", "seven games are busy beside the step, with the engine's own thread pick")
	var snd: Dictionary = p[ids.find("fight_sound")]
	t.check(int(DiagStats.cfg_i(snd.cfg, "sound", 0)) == 1 and int(DiagStats.cfg_i(p[ids.find("fight_base")].cfg, "sound", 0)) == 0, "the sound is on in one fight and off in the rest")

func test_the_plan_of_other_runs() -> void:
	var quick := _ids(Diag.plan({"quick": true, "windowed": true, "editor": true, "os": "Linux", "driver": "vulkan"}))
	t.check(quick.has("steps_t1") and not quick.has("steps_t4") and not quick.has("steps_burners") and quick.has("room_eight") and not quick.has("fight_high_priority") and not quick.has("fight_d3d12"), "a quick run has fewer thread parts, and the Windows ones only on Windows (%s)" % ", ".join(PackedStringArray(quick)))
	var none := _ids(Diag.plan({"windowed": true, "editor": false, "os": "Windows", "driver": "d3d12"}))
	t.check(not none.has("release_export") and not none.has("release_steps") and not none.has("release_fight"), "an exported game makes no release build of itself")
	var only := _ids(Diag.plan({"windowed": true, "editor": true, "os": "Windows", "driver": "d3d12", "only": PackedStringArray(["steps", "fight_cold"])}))
	t.check(only.has("facts") and only.has("steps_auto") and only.has("steps_t8") and only.has("fight_cold") and not only.has("fight_base") and not only.has("room_eight"), "--only: the facts, and what was named (a word before an underscore names its family)")
	var skip := _ids(Diag.plan({"windowed": true, "editor": true, "os": "Windows", "driver": "d3d12", "skip": PackedStringArray(["fight", "room"])}))
	t.check(skip.has("steps_auto") and not skip.has("fight_base") and not skip.has("fight_cold") and not skip.has("room_eight") and skip.has("render_steady") and skip.has("release_fight"), "--skip: a family goes with all its parts, the rest stay (release_fight is of the release family)")
	var nowin := Diag.plan({"windowed": false, "editor": true, "os": "Linux", "driver": ""})
	var windows_needed := nowin.filter(func(s): return bool(s.get("window", false))).size()
	t.check(windows_needed >= 5 and not _ids(nowin).has("fight_vulkan"), "with no window the parts that need one stay in the plan (to be told as not run) but the renderer is not known")
	t.check(Diag._named("fight_cold", PackedStringArray(["fight"])) and Diag._named("steps_auto", PackedStringArray(["steps_auto"])) and not Diag._named("steps_auto", PackedStringArray(["step"])), "names")

func test_the_release_template_is_looked_for_where_godot_keeps_it() -> void:
	var p := Diag.template_path()
	var v := Engine.get_version_info()
	var want := "%d.%d.%d.%s" % [int(v.major), int(v.minor), int(v.patch), String(v.status)]
	if OS.get_name() == "Linux":
		t.check(p.ends_with("/godot/export_templates/%s/linux_release.x86_64" % want), "Linux: %s" % p)
	elif OS.get_name() == "Windows":
		t.check(p.ends_with("/Godot/export_templates/%s/windows_release_x86_64.exe" % want), "Windows: %s" % p)
	else:
		t.check(p == "", "no template for this system is looked for")

# ---------- the files it leaves ----------

func test_the_override_file_is_ours_and_goes_away() -> void:
	var dir := ProjectSettings.globalize_path("user://diag_test_override")
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir.path_join("override.cfg")
	for f in [p, p + ".diag_backup"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var d := Diag.new()
	d._put_override({"threading/worker_pool/max_threads": 2}, dir)
	t.check(FileAccess.file_exists(p) and FileAccess.get_file_as_string(p).begins_with("; " + Diag.MARK) and FileAccess.get_file_as_string(p).contains("max_threads=2"), "a part with settings gets a file of ours")
	d._remove_override(dir)
	t.check(not FileAccess.file_exists(p), "and it goes when the part ends")
	d._put_override({}, dir)
	t.check(not FileAccess.file_exists(p), "a part with no settings writes none")
	var his := "[rendering]\n\nanti_aliasing/quality/msaa_3d=3\n"
	var f1 := FileAccess.open(p, FileAccess.WRITE)
	f1.store_string(his)
	f1.close()
	d._put_override({"threading/worker_pool/max_threads": 1}, dir)
	t.check(FileAccess.get_file_as_string(p).begins_with("; " + Diag.MARK) and FileAccess.get_file_as_string(p + ".diag_backup") == his, "the player's own file is put aside while ours is there")
	d._remove_override(dir)
	t.check(FileAccess.get_file_as_string(p) == his and not FileAccess.file_exists(p + ".diag_backup"), "and put back when it goes")
	DirAccess.remove_absolute(p)
	var f2 := FileAccess.open(p, FileAccess.WRITE)   # (a run that was killed in the middle of a part)
	f2.store_string(Diag.override_for({"threading/worker_pool/max_threads": 3}))
	f2.close()
	var f3 := FileAccess.open(p + ".diag_backup", FileAccess.WRITE)
	f3.store_string(his)
	f3.close()
	d._remove_override(dir)
	t.check(FileAccess.get_file_as_string(p) == his and not FileAccess.file_exists(p + ".diag_backup"), "what a killed run left is cleaned and the player's file is back")
	DirAccess.remove_absolute(p)
	d.free()

func test_the_log_is_read_for_trouble() -> void:
	var p := ProjectSettings.globalize_path("user://diag_test.log")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("fine\nERROR: Condition \"x\" is true.\n   at: foo\nSCRIPT ERROR: Parse Error: nope\nWARNING: not an error\n")
	f.close()
	var r := Diag._scan_log(p)
	t.check(int(r.errors) == 2 and String(r.first).begins_with("ERROR: Condition"), "two errors, the first named (%s)" % str(r))
	t.check(int(Diag._scan_log("/nonexistent/x.log").errors) == 0, "no log, no errors")
	var f2 := FileAccess.open(p, FileAccess.WRITE)
	f2.store_string("DIAG {\"a\": 1}\n")
	for i in 120:
		f2.store_string("Buffer full, dropping packets! (%d)\n" % i)
	for i in 5:
		f2.store_string("a line now and then %d\n" % i)
	f2.close()
	var r2 := Diag._scan_log(p)
	t.check(int(r2.lines) == 125 and (r2.top as Array).size() == 1 and int(r2.top[0][0]) == 120 and String(r2.top[0][1]).contains("(#)"), "a line written 120 times is told, with its digits aside, and the part's own lines are not counted (%s)" % str(r2))
	DirAccess.remove_absolute(p)

func test_the_report_is_written_with_its_summary() -> void:
	var dir := ProjectSettings.globalize_path("user://diag_test_report")
	DirAccess.make_dir_recursive_absolute(dir)
	var d := Diag.new()
	d.out_dir = dir
	d.opts = {"quick": true}
	d.results = {"steps_auto": [{"kind": "step", "label": "men:8", "mix": "men:8", "flags": "", "men": 9, "ms": 7.5, "scripts_ms": 5.5, "engine_ms": 1.0, "secs": 6.0, "native": true}]}
	d.facts = {"cpu": "A test CPU", "threads": 8, "ram_mb": 16000, "os": "Linux", "os_version": "1", "godot": "4.7.2", "editor_binary": true, "native_core": true, "busy_pct": 3.0}
	d.sections = PackedStringArray(["== 1. a part  [x] ==\n  something"])
	d.t_start = Time.get_ticks_msec()
	d._write_report(false)
	var s1 := FileAccess.get_file_as_string(d.report_path())
	t.check(s1.contains("not finished") and not s1.contains("== SUMMARY =="), "a run cut short says so and has what it had")
	d._write_report(true)
	var s2 := FileAccess.get_file_as_string(d.report_path())
	t.check(s2.contains("== SUMMARY ==") and s2.contains("A test CPU") and s2.contains("THE STEP") and s2.contains("== 1. a part") and s2.contains("== RAW") and s2.contains("steps_auto {"), "the whole one: the summary first, the parts, the raw lines last")
	DirAccess.remove_absolute(d.report_path())
	d.free()

func test_the_summary_says_what_each_way_is_worth() -> void:
	var step := func(mix: String, flag: String, ms: float, extra := {}) -> Dictionary:
		var d := {"kind": "step", "label": mix, "mix": mix, "flags": flag, "men": 12, "ms": ms, "scripts_ms": ms * 0.7, "engine_ms": ms * 0.15, "secs": 6.0}
		d.merge(extra)
		return d
	var res := {
		"steps_auto": [step.call("men:8", "", 6.6), step.call("men:8", "gd", 7.9), step.call("men:8", "bare", 5.0), step.call("men:8,foe:3", "", 9.4), step.call("men:8,foe:3", "", 9.4, {"win": [9.0, 9.2, 9.8], "label": "men:8,foe:3@30", "secs": 30.0}), {"kind": "cpu_loop", "ms": 33.0, "ref_ms": 66.0}],
		"steps_t1": [step.call("men:8,foe:3", "", 10.1)], "steps_t4": [step.call("men:8,foe:3", "", 9.0)], "steps_burners": [step.call("men:8,foe:3", "", 10.7)],
		"fight_render_thread": [{"kind": "frames", "label": "fight, the rest", "ms": {"mean": 26.0, "max": 80.0}, "speed": 0.9, "comp": {"steps": 12.0, "step_scripts": 3.5, "step_engine": 2.0, "per_frame": 2.0, "between": 4.0, "scripts": 4.0, "draw_wait": 2.0}, "gpu": 5.0, "calls": 900}],
		"release_steps": [step.call("men:8", "", 5.6), step.call("men:8,foe:3", "", 7.9)],
		"fight_base": [{"kind": "frames", "label": "fight, the rest", "ms": {"mean": 30.0, "max": 90.0}, "speed": 0.8, "comp": {"steps": 14.0, "step_scripts": 4.0, "step_engine": 2.0, "per_frame": 2.0, "between": 5.0, "scripts": 4.0, "draw_wait": 7.0}, "gpu": 5.0, "calls": 900},
			{"kind": "frames", "label": "fight, the first 12 s", "ms": {"mean": 40.0, "max": 400.0}, "over50": 7, "over100": 2, "pipes": 12}],
		"room_eight": [{"kind": "frames", "label": "room, endless, 0-30 s", "speed": 0.62, "fps": 24.0, "step_ms": 10.2}]}
	var lines := Diag.summary(res, {"cpu": "Fast CPU", "threads": 20, "ram_mb": 32000, "os": "Windows", "os_version": "10", "godot": "4.7.2", "editor_binary": true, "native_core": true, "adapter": "A card", "driver": "d3d12"}, PackedStringArray(["something went wrong"]))
	var all := "\n".join(PackedStringArray(lines))
	t.check(all.contains("Fast CPU") and all.contains("A card (d3d12)") and all.contains("the editor's binary"), "the computer: %s" % all)
	t.check(all.contains("NATIVE CORE") and all.contains("(-16%)"), "the native core's worth: 7.9 without, 6.6 with")
	t.check(all.contains("ARMOUR") and all.contains("(+32%)"), "armour's: 5.0 bare, 6.6 in armour")
	t.check(all.contains("RELEASE BUILD") and all.contains("(-16%)") and all.contains("7.90 ms against the editor's 9.40"), "the release build's: 7.9 against 9.4")
	t.check(all.contains("THREADS") and all.contains("1 thread 10.10") and all.contains("4 threads 9.00") and all.contains("the engine's pick 9.40"), "the thread counts side by side")
	t.check(all.contains("DRIFT") and all.contains("CORE SPEED") and all.contains("2.00 times as fast"), "the drift and the core's speed")
	t.check(all.contains("THE FRAME") and all.contains("STALLS") and all.contains("7 frames over 50 ms") and all.contains("12 pipelines compiled") and all.contains("THE ROOM") and all.contains("62%") and all.contains("PROBLEM        something went wrong"), "the frame, the stalls, the room, the problems")
	t.check(all.contains("FRIEND WINDOWS") and all.contains("(+14%)"), "the friend windows' share: 10.7 with seven games beside it, 9.4 alone")
	t.check(all.contains("FIGHT A/B") and all.contains("render_thread: speed 90% (+10 points), a step 6.0 ms (-14%), the rest of a frame 10.0 ms (-38%)"), "a fight against the base: the speed, the step and the rest of the frame (%s)" % all)
	t.check(Diag.summary({}, {}, PackedStringArray()).size() == 1, "a run that measured nothing says so")

# ---------- reading a frame ----------

func test_a_window_tells_the_coroutines_from_the_scripts_and_the_steps_from_both() -> void:
	var rec := DiagFrames.new()
	add_child(rec)
	var b := Burner.new(0, 9000)    # (a script of the frame: 9 ms)
	add_child(b)
	var w := Waiter.new()
	w.us = 5000                     # (a coroutine that waited for the frame: 5 ms)
	add_child(w)
	var sb := StepBurner.new()
	sb.us = 3000                    # (a node's step: 3 ms)
	add_child(sb)
	await _steps(5)
	rec.begin("t")
	await _steps(60)
	var d := rec.end()
	var c: Dictionary = d.get("comp", {})
	t.check(int(d.frames) >= 40 and int(c.get("n", 0)) >= 40, "frames with steps were counted (%d, %d)" % [int(d.frames), int(c.get("n", 0))])
	t.check(float(c.get("between", 0.0)) > 4.0 and float(c.get("between", 0.0)) < 9.0, "the coroutine's 5 ms is between the steps and the process (%.1f)" % float(c.get("between", 0.0)))
	t.check(float(c.get("scripts", 0.0)) > 8.0 and float(c.get("scripts", 0.0)) < 13.0, "the script's 9 ms is in the scripts (%.1f)" % float(c.get("scripts", 0.0)))
	t.check(float(c.get("step_scripts", 0.0)) > 2.5 and float(c.get("step_scripts", 0.0)) < 6.0, "the node's 3 ms is the scripts' part of the step (%.1f)" % float(c.get("step_scripts", 0.0)))
	t.check(float(c.get("steps", 0.0)) < 12.0 and float(c.get("steps", 0.0)) >= float(c.get("step_scripts", 0.0)) * float(c.get("per_frame", 1.0)) - 0.5, "and the steps' span holds it, not the coroutine or the script (%.1f)" % float(c.get("steps", 0.0)))
	t.check(float(d.speed) > 0.2 and float(d.get("fps", 0.0)) > 5.0 and not d.has("gpu") or DisplayServer.get_name() != "headless", "no card's figures without a window")
	for n in [b, w, sb]:
		n.queue_free()
	w.on = false
	rec.queue_free()
	await _steps(2)

func test_a_frame_that_stopped_is_named_with_what_the_game_had_just_said() -> void:
	var rec := DiagFrames.new()
	add_child(rec)
	var nap := Napper.new()
	add_child(nap)
	await _steps(3)
	rec.begin("t")
	await _steps(10)
	FpsMeter.note("match setup: a test as host, 4 men in 12 ms")
	nap.go = true
	await _steps(12)
	var d := rec.end()
	t.check(int(d.hitch_n) >= 1 and (d.hitches as Array).size() >= 1, "a frame of 90 ms is a hitch (%d)" % int(d.hitch_n))
	var h: Dictionary = (d.hitches as Array)[0] if (d.hitches as Array).size() > 0 else {}
	t.check(float(h.get("ms", 0.0)) > 70.0 and String(h.get("note", "")).contains("match setup"), "with the game's own words before it (%s)" % str(h))
	t.check(FpsMeter.tap.is_valid(), "the recorder listens to the notes while it lives")
	rec.queue_free()
	nap.queue_free()
	await _steps(2)
	t.check(not FpsMeter.tap.is_valid(), "and stops when it is gone")

func test_a_stretch_with_no_hitch_has_none() -> void:
	var rec := DiagFrames.new()
	add_child(rec)
	await _steps(3)
	rec.begin("quiet")
	await _steps(30)
	var d := rec.end()
	t.check(int(d.hitch_n) == 0 and (d.hitches as Array).is_empty() and String(d.label) == "quiet", "nothing stopped")
	rec.queue_free()
	await _steps(2)

# ---------- a part, run in this game ----------

func test_a_part_is_found_on_the_command_line() -> void:
	var args := PackedStringArray(["--keep-window", "--diag-phase", "steps", "--diag-out", "/x/y.txt", "--diag-cfg", "a=1"])
	t.check(DiagPhase.kind_of(args) == "steps" and DiagPhase.arg_of(args, "--diag-out") == "/x/y.txt" and DiagPhase.arg_of(args, "--diag-cfg") == "a=1" and DiagPhase.arg_of(args, "--nope") == "", "the part, its file and its arguments")
	t.check(DiagPhase.kind_of(PackedStringArray(["--diag-phase"])) == "" and DiagPhase.kind_of(PackedStringArray()) == "", "none given")

func test_a_steps_part_says_what_a_step_costs_and_where() -> void:
	var ph := DiagPhase.new()
	add_child(ph)   # (no part on this game's command line: it does nothing by itself)
	ph.rec = DiagFrames.new()
	ph.add_child(ph.rec)
	var d: Dictionary = await ph._bout("men:2,foe:1", 1.0)
	t.check(String(d.kind) == "step" and int(d.men) == 4 and float(d.ms) > 0.05 and float(d.worst) >= float(d.ms), "a bout of three fighters says its step (%s)" % DiagStats.step_text(d))
	t.check(float(d.scripts_ms) > 0.0 and float(d.scripts_ms) + float(d.engine_ms) <= float(d.ms) * 1.1 + 0.2, "split into the scripts' part and the engine's (%.2f + %.2f of %.2f)" % [float(d.scripts_ms), float(d.engine_ms), float(d.ms)])
	var g: Dictionary = await ph._bout("men:2#gd#bare", 1.0)
	t.check(not bool(g.native) and String(g.flags) == "gd,bare" and Greedy.use_native, "the scripts' own ways and bare men run, and the native core is on again after")
	var long: Dictionary = await ph._bout("men:1@13", 99.0)
	t.check(float(long.secs) == 13.0 and (long.win as Array).size() == 2, "a mix can name its own seconds, and a long one is read in five-second windows (%d)" % (long.win as Array).size())
	ph.queue_free()
	await _steps(2)

func test_every_setting_the_render_part_changes_is_put_back() -> void:
	var ph := DiagPhase.new()
	add_child(ph)
	var vp := get_viewport()
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var hud := CanvasLayer.new()
	add_child(hud)
	Arena.apply_quality(env, sun, "high")
	var man := Node3D.new()
	add_child(man)
	var c := {"m": {"entities": [{"f": man}]}, "hud": hud, "env": env, "sun": sun, "quality": "high",
		"base": {"mode": vp.scaling_3d_mode, "scale": vp.scaling_3d_scale, "msaa": vp.msaa_3d, "saa": vp.screen_space_aa, "vsync": DisplayServer.window_get_vsync_mode(), "fps": Engine.max_fps}}
	var state := func() -> Array:
		return [vp.disable_3d, vp.scaling_3d_scale, vp.scaling_3d_mode, vp.msaa_3d, vp.screen_space_aa, sun.shadow_enabled, sun.directional_shadow_mode, env.volumetric_fog_enabled, env.ssao_enabled, env.ssil_enabled, env.glow_enabled, env.sdfgi_enabled, hud.visible, man.visible, Engine.max_fps]
	var before: Array = state.call()
	for name in DiagPhase.RENDER_VARIANTS:
		ph._apply(name, c)
		var changed: Array = state.call()
		t.check(changed != before or name == "vsync off, no frame cap", "'%s' changes something (%s)" % [name, str(changed)])
		ph._undo(name, c)
		t.check(state.call() == before, "'%s' is put back (%s against %s)" % [name, str(state.call()), str(before)])
	ph._apply("3D not drawn", c)
	t.check(vp.disable_3d, "the 3D is not drawn")
	ph._undo("3D not drawn", c)
	ph._apply("the HUD not drawn", c)
	t.check(not hud.visible, "the HUD is not drawn")
	ph._undo("the HUD not drawn", c)
	t.check(DiagPhase.RENDER_VARIANTS.size() >= 8 and DiagPhase.RENDER_VARIANTS.has("the men not drawn") and DiagPhase.RENDER_VARIANTS.has("no sun shadows"), "the list of settings is the one the plan hands the part")
	ph.queue_free()
	sun.queue_free()
	hud.queue_free()
	man.queue_free()
	await _frames(2)

func test_the_machine_is_described() -> void:
	var f := DiagPhase.facts()
	t.check(String(f.cpu) != "" and int(f.threads) > 0 and String(f.godot).begins_with("4.") and f.has("native_core") and f.has("worker_threads") and f.has("thread_model") and f.has("debug_build") and f.has("player_settings"), "the facts a report opens with")
	t.check(not f.has("driver") or DisplayServer.get_name() != "headless", "no renderer is named where there is none")
