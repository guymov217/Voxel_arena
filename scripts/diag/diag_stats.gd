class_name DiagStats
extends RefCounted
## The arithmetic and the wording of the diagnostic test (`Diag`, `DiagPhase`, `DiagFrames`), with no node and no clock in it so that a test can hand it numbers.
## The test is ONE thing for the player (`tools/diagnose.bat`, one report); inside it is a list of parts, each run in a game of its own, which say what they saw
## in lines of JSON (one result a line) in a file the test reads back.

# ---------- Numbers ----------

static func mean(a) -> float:
	var n: int = a.size()
	if n == 0:
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(n)

static func sorted(a) -> Array:
	var b := Array(a)
	b.sort()
	return b

## The value that `p` (0 to 1) of the numbers are at or under (nearest rank: no number is made up).
static func percentile(a, p: float) -> float:
	var n: int = a.size()
	if n == 0:
		return 0.0
	var b := sorted(a)
	return float(b[clampi(int(ceil(p * float(n))) - 1, 0, n - 1)])

static func median(a) -> float:
	return percentile(a, 0.5)

static func worst(a) -> float:
	var w := 0.0
	for x in a:
		w = maxf(w, float(x))
	return w

static func r1(x: float) -> float:
	return snappedf(x, 0.1)

static func r2(x: float) -> float:
	return snappedf(x, 0.01)

## "+12%" / "-14%": what `to` is against `from` (n/a when there is no `from`).
static func change(from: float, to: float) -> String:
	if from <= 0.0:
		return "n/a"
	var p := (to - from) / from * 100.0
	return "%s%d%%" % ["+" if p >= 0.0 else "-", roundi(absf(p))]

## 754 -> "12m34s".
static func clock(secs: float) -> String:
	var s := maxi(0, roundi(secs))
	return "%dm%02ds" % [s / 60, s % 60]

# ---------- What a part is told ----------

## "a=1;b=men:8,foe:3" -> {"a": "1", "b": "men:8,foe:3"} (what the test hands a part on its command line: one argument, no quotes to get wrong).
static func parse_cfg(text: String) -> Dictionary:
	var d := {}
	for part in text.split(";", false):
		var i := part.find("=")
		if i > 0:
			d[part.substr(0, i).strip_edges()] = part.substr(i + 1).strip_edges()
	return d

static func cfg_text(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in d:
		parts.append("%s=%s" % [k, str(d[k])])
	return ";".join(parts)

static func cfg_i(d: Dictionary, key: String, fallback: int) -> int:
	return int(str(d[key])) if d.has(key) and (str(d[key]).is_valid_int() or str(d[key]).is_valid_float()) else fallback

static func cfg_f(d: Dictionary, key: String, fallback: float) -> float:
	return float(str(d[key])) if d.has(key) and str(d[key]).is_valid_float() else fallback

static func cfg_s(d: Dictionary, key: String, fallback: String) -> String:
	return str(d[key]) if d.has(key) else fallback

## "men:4+men:8+men:8,foe:3" -> ["men:4", "men:8", "men:8,foe:3"].
static func plus_list(text: String) -> PackedStringArray:
	return text.split("+", false)

# ---------- What a part says ----------

## One result as a line (floats to two places: the lines are read by a person too).
static func encode(d: Dictionary) -> String:
	return JSON.stringify(_rounded(d))

static func decode(line: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(line.strip_edges()) != OK:   # (a line cut off by a game that crashed: not a result, and not an error of ours)
		return {}
	return j.data if j.data is Dictionary else {}

static func _rounded(v):
	if v is float:
		if is_nan(v) or is_inf(v):
			return -1.0   # (JSON has no such number: a screen that does not say its refresh rate)
		return snappedf(v, 0.01)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _rounded(v[k])
		return out
	if v is Array:
		var out2 := []
		for x in v:
			out2.append(_rounded(x))
		return out2
	return v

## Every line of a part's file that is a result.
static func read_results(text: String) -> Array:
	var out := []
	for l in text.split("\n", false):
		var d := decode(l)
		if not d.is_empty():
			out.append(d)
	return out

# ---------- The settings a part is run under ----------

## `override.cfg` text for project settings given by path ("threading/worker_pool/max_threads": 4): the engine reads the file next to the project (or the
## executable) before it starts anything, so these are the ones that take a restart. `mark` is the first line, how the test knows the file is its own.
static func override_text(settings: Dictionary, mark: String) -> String:
	var sections := {}   # section -> [lines]
	for path in settings:
		var parts := String(path).split("/", false)
		if parts.size() < 2:
			continue
		var section: String = parts[0]
		var key := "/".join(parts.slice(1))
		var v = settings[path]
		var text := str(v)
		if v is String:
			text = "\"%s\"" % v
		elif v is bool:
			text = "true" if v else "false"
		if not sections.has(section):
			sections[section] = []
		sections[section].append("%s=%s" % [key, text])
	var out := PackedStringArray(["; " + mark])
	var names := sections.keys()
	names.sort()
	for s in names:
		out.append("")
		out.append("[%s]" % s)
		out.append("")
		for l in sections[s]:
			out.append(l)
	return "\n".join(out) + "\n"

# ---------- The wording ----------

## A window of frames (DiagFrames.end) as the lines of the report.
static func frames_text(d: Dictionary) -> String:
	var ms: Dictionary = d.get("ms", {})
	var out := "%-22s %5.1f s  %5.1f fps  frame %5.1f ms (median %.1f, p95 %.1f, p99 %.1f, worst %.0f)  over 33/50/100 ms: %d/%d/%d  speed %3.0f%% (%.0f steps a second)" % [
		String(d.get("label", "?")), float(d.get("secs", 0.0)), float(d.get("fps", 0.0)), float(ms.get("mean", 0.0)), float(ms.get("p50", 0.0)), float(ms.get("p95", 0.0)),
		float(ms.get("p99", 0.0)), float(ms.get("max", 0.0)), int(d.get("over33", 0)), int(d.get("over50", 0)), int(d.get("over100", 0)), float(d.get("speed", 0.0)) * 100.0, float(d.get("steps_s", 0.0))]
	var c: Dictionary = d.get("comp", {})
	if int(c.get("n", 0)) > 0:
		out += "\n%-22s   a frame of %.1f ms = steps %.1f (%.1f a frame: the scripts' %.2f and the engine's %.2f each; a step's gap %.1f) + between them and the scripts %.1f + scripts %.1f + drawing and waiting %.1f" % [
			"", float(c.get("frame", 0.0)), float(c.get("steps", 0.0)), float(c.get("per_frame", 0.0)), float(c.get("step_scripts", 0.0)), float(c.get("step_engine", 0.0)), float(c.get("gap", 0.0)), float(c.get("between", 0.0)), float(c.get("scripts", 0.0)), float(c.get("draw_wait", 0.0))]
	if d.has("phys") and int((d.phys as Dictionary).get("active", 0)) + int((d.phys as Dictionary).get("pairs", 0)) > 0:
		var ph: Dictionary = d.phys
		out += "\n%-22s   physics: %d bodies awake, %d contact pairs, %d islands; %d orphan nodes" % ["", int(ph.get("active", 0)), int(ph.get("pairs", 0)), int(ph.get("islands", 0)), int(d.get("orphans", 0))]
	elif int(d.get("orphans", 0)) > 0:
		out += "\n%-22s   %d orphan nodes" % ["", int(d.get("orphans", 0))]
	if d.has("friends"):
		out += "\n%-22s   the room: %d friend windows on this machine, the game's own step reading %.1f ms%s%s; the 3D drawn at %.0f%%, the frames capped at %s" % ["", int(d.get("friends", 0)), float(d.get("step_ms", 0.0)), ", OVER BUDGET (two steps a frame)" if bool(d.get("over", false)) else "",
			(", the host sends %.0f KB/s and takes in %.0f" % [float(d.get("sent_kbs", 0.0)), float(d.get("recv_kbs", 0.0))]) if d.has("sent_kbs") else "", float(d.get("scale_3d", 1.0)) * 100.0, str(int(d.get("max_fps", 0))) if int(d.get("max_fps", 0)) > 0 else "nothing"]
	if d.has("gpu"):
		out += "\n%-22s   the card %.1f ms, the engine's recording %.1f ms, %d draw calls, %d objects, %dk primitives; video memory %d MB (textures %d); pipelines compiled %d; %d nodes, %d MB; %s" % [
			"", float(d.get("gpu", 0.0)), float(d.get("cpu_draw", 0.0)), int(d.get("calls", 0)), int(d.get("objects", 0)), int(d.get("prims", 0)) / 1000, int(d.get("vram_mb", 0)), int(d.get("tex_mb", 0)), int(d.get("pipes", 0)), int(d.get("nodes", 0)), int(d.get("mem_mb", 0)),
			"the window was in front" if bool(d.get("focused", true)) else "THE WINDOW WAS NOT IN FRONT"]
	for h in d.get("hitches", []):
		out += "\n%-22s   HITCH at %.1f s: %.0f ms (%d steps, %+d nodes, %+d resources, %d pipelines)%s" % ["", float(h.get("t", 0.0)), float(h.get("ms", 0.0)), int(h.get("steps", 0)), int(h.get("dnodes", 0)), int(h.get("dres", 0)), int(h.get("dpipes", 0)), (" after: " + String(h.get("note"))) if String(h.get("note", "")) != "" else ""]
	if int(d.get("hitch_n", 0)) > (d.get("hitches", []) as Array).size():
		out += "\n%-22s   (%d frames over %.0f ms in all; the worst are listed)" % ["", int(d.get("hitch_n", 0)), float(d.get("hitch_ms", 50.0))]
	return out

## A step's cost (a headless fight) as a line.
static func step_text(d: Dictionary) -> String:
	var budget := 1000.0 / 120.0
	var ms := float(d.get("ms", 0.0))
	var verdict := "smooth" if ms <= budget * 0.85 else ("at the limit" if ms <= budget * 1.1 else "too slow: %d%% speed" % roundi(100.0 * budget / maxf(0.01, ms)))
	var out := "%-34s %2d on the sand: a step %5.2f ms (median %.2f, p99 %.1f, worst %.0f) of the %.1f there is -> %s" % [
		String(d.get("label", "?")), int(d.get("men", 0)), ms, float(d.get("median", 0.0)), float(d.get("p99", 0.0)), float(d.get("worst", 0.0)), budget, verdict]
	if d.has("scripts_ms"):
		out += "\n%-34s    of it the nodes' scripts %.2f ms, the engine's step after them %.2f ms, and %.2f ms before them (the engine's preparing, the loop)" % ["", float(d.get("scripts_ms", 0.0)), float(d.get("engine_ms", 0.0)), maxf(0.0, ms - float(d.get("scripts_ms", 0.0)) - float(d.get("engine_ms", 0.0)))]
		var ph: Dictionary = d.get("phys", {})
		if int(ph.get("active", 0)) + int(ph.get("pairs", 0)) > 0:
			out += "; %d bodies awake, %d contact pairs, %d islands" % [int(ph.get("active", 0)), int(ph.get("pairs", 0)), int(ph.get("islands", 0))]
	if d.has("win"):
		out += "\n%-34s    a step in each five seconds: %s" % ["", ", ".join(PackedStringArray((d.win as Array).map(func(x): return "%.2f" % float(x))))]
	return out

## What a part (or the test itself) said, as the report's lines.
static func result_text(d: Dictionary) -> String:
	match String(d.get("kind", "")):
		"start":
			var f: Dictionary = d.get("facts", {})
			return "  ran as %s: %s, %s%s; native core %s; worker threads %s, render thread model %s, caches %s/%s, interpolation %s; %s" % [String(f.get("exe", "?")).get_file(),
				String(f.get("godot", "?")), "the editor's binary" if bool(f.get("editor_binary", false)) else ("an export template" if bool(f.get("export_template", false)) else "a game"),
				", a debug build" if bool(f.get("debug_build", false)) else ", a release build", "on" if bool(f.get("native_core", false)) else "OFF", str(int(f.get("worker_threads", -1))), str(int(f.get("thread_model", 1))),
				"pipeline " + str(f.get("pipeline_cache", "?")), "shader " + str(f.get("shader_cache", "?")), str(f.get("interpolation", "?")),
				("%s on %s (%s), screen %s, window %s, vsync %s, cap %s, 3D scale %.2f, msaa %s" % [str(f.get("driver", "?")), str(f.get("adapter", "?")), str(f.get("method", "?")), str(f.get("screen_size", "?")), str(f.get("window_size", "?")), str(f.get("vsync_mode", "?")), str(f.get("max_fps", "?")), float(f.get("scale_3d", 1.0)), str(f.get("msaa_3d", "?"))]) if f.has("driver") else "no window"]
		"facts":
			return facts_text(d.get("facts", {}))
		"step":
			return "  " + step_text(d).replace("\n", "\n  ")
		"frames":
			return "  " + frames_text(d).replace("\n", "\n  ")
		"sample":
			return "  at %5.1f s: wave %d, %d men and %d foes alive, %d held at the gate, %d on their way in, step %.1f ms%s, %.0f fps, %d nodes (%d orphans), %d MB, %d bodies awake%s" % [float(d.get("t", 0.0)), int(d.get("wave", 0)), int(d.get("men", 0)), int(d.get("foes", 0)),
				int(d.get("held", 0)), int(d.get("coming", 0)), float(d.get("step_ms", 0.0)), " OVER BUDGET" if bool(d.get("over", false)) else "", float(d.get("fps", 0.0)), int(d.get("nodes", 0)), int(d.get("orphans", 0)), int(d.get("mem_mb", 0)), int(d.get("awake", 0)),
				((", %d friend windows" % int(d.friends)) if d.has("friends") else "") + ((", its core %.1f ms" % float(d.core_ms)) if d.has("core_ms") else "")]
		"setup":
			return "  %s: %.0f ms" % [String(d.get("label", "?")), float(d.get("ms", 0.0))]
		"cpu_loop":
			return "  a fixed piece of script work: %.0f ms (the machine the test was made on: %.0f ms)" % [float(d.get("ms", 0.0)), float(d.get("ref_ms", 0.0))]
		"cores":
			var ms: Array = d.get("ms", [])
			var out_c := "  an eighth of that work on each logical processor in turn (%s; the machine the test was made on: %.1f ms):" % ["a game with a window" if bool(d.get("window", false)) else "a game with no window", float(d.get("ref_ms", 0.0))]
			for i in ms.size():
				out_c += "%s%5.1f" % ["\n    " if i % 10 == 0 else " ", float(ms[i])]
			return out_c + "\n    let go, where the system puts it by itself: %.1f ms" % float(d.get("free_ms", 0.0))
		"readback":
			var out_r := "  asking a MultiMesh of %d instances for one of them, %d MultiMeshes each way (ms: the first time, the worst first time, the time after):" % [int(d.get("instances", 0)), int(d.get("of", 0))]
			for a in [["get", "reading one instance's colour"], ["set", "writing one instance's colour"], ["buffer", "reading the whole buffer"]]:
				var f1: Dictionary = d.get(String(a[0]) + "_first", {})
				var f2: Dictionary = d.get(String(a[0]) + "_next", {})
				out_r += "\n    %-30s %7.3f %7.3f %7.3f" % [String(a[1]), float(f1.get("median", 0.0)), float(f1.get("worst", 0.0)), float(f2.get("median", 0.0))]
			return out_r
		"room":
			return "  room: %s" % ", ".join(PackedStringArray((d.keys() as Array).filter(func(k): return k != "kind" and k != "t").map(func(k): return "%s %s" % [k, str(d[k])])))
		"record":
			var lines: Array = d.get("lines", [])
			var out := "  the game's own record (%s), %d lines of this run:" % [String(d.get("path", "?")), lines.size()]
			for l in lines:
				out += "\n    " + String(l)
			return out
		"export":
			return ""
		"error":
			return "  ERROR: %s" % String(d.get("what", "?"))
		"skipped":
			return "  skipped: %s" % String(d.get("what", "?"))
		"done":
			return ""
	return "  " + encode(d)

## The facts of the machine, one to a line.
static func facts_text(f: Dictionary) -> String:
	var keys := ["cpu", "cpu_system", "threads", "ram_mb", "ram_free_mb", "os", "os_version", "os_alias", "distribution", "gpu_system", "adapter", "adapter_vendor", "adapter_api", "driver", "method", "refresh_hz", "screen_size", "screens", "screen_scale", "godot", "game", "exe", "editor_binary", "export_template", "debug_build",
		"native_core", "native_arms", "ticks", "max_steps_a_frame", "interpolation", "jolt_velocity_steps", "jolt_position_steps", "worker_threads", "thread_model", "pipeline_cache", "shader_cache", "power_plan", "busy_pct", "census", "player_settings"]
	var out := PackedStringArray()
	var done := {}
	for k in keys:
		if f.has(k):
			out.append("  %-18s %s" % [k, str(f[k])])
			done[k] = true
	for k in f:
		if not done.has(k) and k != "kind":
			out.append("  %-18s %s" % [k, str(f[k])])
	return "\n".join(out)
