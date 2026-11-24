class_name DiagPhase
extends Node
## One part of the diagnostic test, run in a game of its own: `-- --diag-phase NAME --diag-out FILE --diag-cfg "key=value;key=value"`. What it sees it writes to FILE, a result a line
## (`DiagStats.encode`), and the last line is `{"kind": "done"}`; the test (`Diag`) reads the file when the game ends. The parts:
##   steps   headless, `--fixed-fps 120`: what a physics step costs with fighters of the sand's kinds, split into the scripts' part and the engine's; the native core on and off; a drift over time
##   fight   the endless arena with eight bot players, drawn for real (a window), as the engine's frames are made: the steps, the scripts, the drawing and the waiting, the card, the hitches
##   render  eight men walking in the yard (nothing changes from one second to the next), under a list of settings changed one at a time: what each of them is worth to the frame
##   room    the game's own menu, a room of eight with seven friend windows (as the playtest), the endless arena begun from the yard's gate, with the record the game keeps of itself
## Each takes what the engine was started with (the thread settings, the renderer, the cache) from the test, which writes an `override.cfg` or gives engine flags; what the part
## says first (`start`) is what it found itself running under.

const ARMOUR := ["helmet", "lorica", "manica", "greaves"]
const WEAPONS := ["gladius", "axe", "mace", "spear"]
const FOES := ["recruit", "shieldbearer", "brute", "murmillo"]
const BEASTS := ["wolf", "lion", "bear", "boar"]
## How long the loop of `_cpu_loop` takes on the machine the test was made on (the build machine's core, the editor's binary): a faster computer reads less.
const REF_LOOP_MS := 66.0

var kind := ""
var cfg := {}
var out_path := ""
var rec: DiagFrames
var windowed := false
var _sampling := false

static func kind_of(args) -> String:
	var i: int = args.find("--diag-phase")
	return String(args[i + 1]) if i >= 0 and args.size() > i + 1 else ""

static func arg_of(args, name: String) -> String:
	var i: int = args.find(name)
	return String(args[i + 1]) if i >= 0 and args.size() > i + 1 else ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	kind = kind_of(args)
	windowed = DisplayServer.get_name() != "headless"
	if kind == "":
		return   # (made by a test, which asks for the parts itself)
	out_path = arg_of(args, "--diag-out")
	cfg = DiagStats.parse_cfg(arg_of(args, "--diag-cfg"))
	if windowed:
		DisplayServer.window_move_to_foreground()   # (a window behind another is drawn less: the parts are measured in front)
	await get_tree().process_frame   # (the autoloads and the tree settle)
	say({"kind": "start", "part": kind, "cfg": cfg, "facts": facts()})
	match kind:
		"steps":
			await _steps()
		"fight":
			await _fight()
		"render":
			await _render()
		"room":
			await _room()
		"burn":
			await _burn()
		_:
			say({"kind": "error", "what": "no such part: '%s'" % kind})
	say({"kind": "done"})
	get_tree().quit()

## One result: printed, and added to the part's file.
func say(d: Dictionary) -> void:
	var line := DiagStats.encode(d)
	print("DIAG ", line)
	if out_path == "":
		return
	var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()

func _pause(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

## Frames until `cond` holds (or `secs` pass: false).
func _until(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			return false
	return true

## What this game is and what it runs on, for the part's first line and the report's head.
static func facts() -> Dictionary:
	var windowed_ := DisplayServer.get_name() != "headless"
	var mem := OS.get_memory_info()
	var d := {
		"godot": String(Engine.get_version_info().get("string", "?")), "game": String(ProjectSettings.get_setting("application/config/version", "?")),
		"os": OS.get_name(), "os_version": OS.get_version(), "distribution": OS.get_distribution_name(),
		"cpu": OS.get_processor_name(), "threads": OS.get_processor_count(), "ram_mb": int(mem.get("physical", 0)) / 1048576, "ram_free_mb": int(mem.get("available", 0)) / 1048576,
		"os_alias": OS.get_version_alias(),
		"exe": OS.get_executable_path(), "editor_binary": OS.has_feature("editor"), "export_template": OS.has_feature("template"), "debug_build": OS.is_debug_build(),
		"screen": DisplayServer.get_name(), "ticks": Engine.physics_ticks_per_second, "max_steps_a_frame": Engine.max_physics_steps_per_frame,
		"interpolation": bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
		"jolt_velocity_steps": ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/velocity_steps", "?"), "jolt_position_steps": ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/position_steps", "?"),
		"worker_threads": ProjectSettings.get_setting("threading/worker_pool/max_threads", -1), "thread_model": ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1),
		"pipeline_cache": ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/enable", true), "shader_cache": ProjectSettings.get_setting("rendering/shader_compiler/shader_cache/enabled", true),
		"native_core": Greedy.core() != null, "native_arms": Greedy.arm_ok,
	}
	var st: Dictionary = Save.get_value("settings", {}) if Save != null else {}
	var mine := {}
	for k in ["quality", "aa", "renderScale", "vsync", "fpsCap", "display", "windowW", "windowH", "bodies", "voxelAO", "killcam", "fps_meter"]:
		if st.has(k):
			mine[k] = st[k]
	d["player_settings"] = mine
	if windowed_:
		var root := (Engine.get_main_loop() as SceneTree).root
		d["driver"] = RenderingServer.get_current_rendering_driver_name()
		d["method"] = RenderingServer.get_current_rendering_method()
		d["adapter"] = RenderingServer.get_video_adapter_name()
		d["adapter_vendor"] = RenderingServer.get_video_adapter_vendor()
		d["adapter_api"] = RenderingServer.get_video_adapter_api_version()
		d["adapter_type"] = int(RenderingServer.get_video_adapter_type())
		d["refresh_hz"] = DisplayServer.screen_get_refresh_rate()
		d["screen_size"] = str(DisplayServer.screen_get_size())
		d["screens"] = DisplayServer.get_screen_count()
		d["screen_scale"] = DisplayServer.screen_get_scale()
		d["window_size"] = str(DisplayServer.window_get_size())
		d["window_mode"] = int(DisplayServer.window_get_mode())
		d["vsync_mode"] = int(DisplayServer.window_get_vsync_mode())
		d["max_fps"] = Engine.max_fps
		d["msaa_3d"] = int(root.msaa_3d)
		d["screen_space_aa"] = int(root.screen_space_aa)
		d["scale_3d"] = root.scaling_3d_scale
		d["scale_3d_mode"] = int(root.scaling_3d_mode)
		d["focused"] = DisplayServer.window_is_focused()
	return d

## Nothing of the game is heard while it is measured.
func _quiet() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, true)

## The picture as the player has set it (his Options: the anti-aliasing, the 3D resolution, vsync and the frame cap), as the menu applies them when the game opens; a part that asks
## for `display=fullscreen` is full screen, the game's own default.
func _player_graphics() -> void:
	if not windowed:
		return
	var st: Dictionary = Save.get_value("settings", {})
	var menu_script = load("res://scripts/ui/menu.gd")
	menu_script.apply_picture(st)
	menu_script.apply_render_scale(st)
	menu_script.apply_frame(st)
	if DiagStats.cfg_s(cfg, "display", "") == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		await _pause(1.5)
	if DiagStats.cfg_s(cfg, "vsync", "") == "off":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0

# ---------- steps ----------

static func _loadout(armoured: bool, i := 0) -> Dictionary:
	var lo := {"main": WEAPONS[i % 4], "off": "roundShield" if i % 4 == 0 else ""}
	if armoured:
		lo["armor"] = ARMOUR
	return lo

## The sand's fighters of a mix ("men:8,foe:3", "men:4,beast:wolf*2", "great:cyclops"), placed round a ring, as `tests/mix298.gd` does them; the men in armour as the game's are.
func _fill(m: Match, spec: String, armoured: bool) -> void:
	var list := []   # [kind, arg]
	for tok in spec.split(","):
		var kv := tok.split(":")
		if kv.size() < 2:
			continue
		var arg := kv[1]
		var n := 1
		if arg.contains("*"):
			var a := arg.split("*")
			arg = a[0]
			n = int(a[1])
		if kv[0] == "men" or kv[0] == "foe":
			n = int(arg)
			arg = ""
		for i in n:
			list.append([kv[0], arg])
	var total := list.size()
	var radius := 5.0 + 0.35 * maxf(0.0, total - 8.0)
	var men_i := 0
	var foe_i := 0
	for i in total:
		var a := TAU * i / total
		var pos := Vector3(sin(a) * radius, 0.1, cos(a) * radius)
		var k: String = list[i][0]
		var arg: String = list[i][1]
		if k == "men":
			m.spawn_fighter({"kind": "bot", "name": "P%d" % men_i, "loadout": _loadout(armoured, men_i), "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
			men_i += 1
		elif k == "foe":
			var sp: Dictionary = m.enemy_spec({"e": FOES[foe_i % FOES.size()]}, 0, 1)
			sp.pos = pos
			sp.yaw = a + PI
			m.spawn_fighter(sp)
			foe_i += 1
		elif k == "beast":
			m.spawn_beast({"beast": arg, "team": Match.ENEMY_TEAM, "pos": pos, "yaw": a + PI})
		elif k == "great":
			var sp2: Dictionary = m.enemy_spec({"e": arg}, 0, 1)
			sp2.pos = pos
			sp2.yaw = a + PI
			m.spawn_fighter(sp2)

## A fight's step, by the wall clock: `mix[@secs][#gd][#bare]` (#gd: the scripts' own ways, the native core off; #bare: no armour). The same fight every time (seed 7).
func _bout(token: String, default_secs: float) -> Dictionary:
	var spec := token
	var secs := default_secs
	var flags := PackedStringArray()
	if spec.contains("#"):
		var p := spec.split("#")
		spec = p[0]
		flags = p.slice(1)
	if spec.contains("@"):
		var p2 := spec.split("@")
		spec = p2[0]
		secs = float(p2[1])
	var gd := flags.has("gd")
	Greedy.use_native = not gd
	seed(7)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -20))
	_fill(m, spec, not flags.has("bare"))
	for k in 120:
		await get_tree().physics_frame
	var steps := int(secs * 120.0)
	var gaps := PackedFloat32Array()
	rec.begin(token)
	var t_prev := Time.get_ticks_usec()
	for k in steps:
		await get_tree().physics_frame
		var t_now := Time.get_ticks_usec()
		gaps.append(float(t_now - t_prev) / 1000.0)
		t_prev = t_now
	var w := rec.end()
	var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
	var sand := m.entities.size()
	m.queue_free()
	Greedy.use_native = true
	for k in 10:
		await get_tree().physics_frame
	var ms := DiagStats.mean(gaps)
	var d := {"kind": "step", "label": token, "mix": spec, "flags": ",".join(flags), "men": sand, "alive": alive, "secs": secs, "ms": ms, "median": DiagStats.median(gaps),
		"p99": DiagStats.percentile(gaps, 0.99), "worst": DiagStats.worst(gaps), "keeps_up": minf(120.0, 1000.0 / maxf(0.01, ms)), "native": not gd}
	var c: Dictionary = w.get("comp", {})
	d["scripts_ms"] = float(c.get("step_scripts", 0.0))
	d["engine_ms"] = float(c.get("step_engine", 0.0))
	d["phys"] = w.get("phys", {})
	d["orphans"] = int(w.get("orphans", 0))
	if secs >= 12.0:
		var win := []   # a step's mean in each five seconds: a machine that slows as it warms shows it
		var per := 600
		var i := 0
		while i + per <= gaps.size():
			win.append(DiagStats.mean(gaps.slice(i, i + per)))
			i += per
		d["win"] = win
	return d

## A fixed piece of the scripts' own kind of work (vectors and bases), best of three: how fast this computer's core is against the one the test was made on.
func _cpu_loop() -> Dictionary:
	var best := 1e9
	for r in 3:
		var t0 := Time.get_ticks_usec()
		var acc := Vector3.ZERO
		var b := Basis.IDENTITY
		for i in 1000000:
			b = b.rotated(Vector3.UP, 0.001)
			acc += b * Vector3(1.0, 2.0, 3.0) * 0.0001
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
	return {"kind": "cpu_loop", "ms": best, "ref_ms": REF_LOOP_MS}

func _steps() -> void:
	rec = DiagFrames.new()
	add_child(rec)
	var secs := DiagStats.cfg_f(cfg, "secs", 6.0)
	if DiagStats.cfg_i(cfg, "cpu", 0) == 1:
		say(_cpu_loop())
	for token in DiagStats.plus_list(DiagStats.cfg_s(cfg, "mixes", "men:8")):
		say(await _bout(token, secs))

## A game that takes about a third of a core, as a friend's window does (the playtest's windows cost 29% of one): thirty frames a second, ten milliseconds of each spent. The test starts
## some of these beside a part to see what that costs the part; it ends them, and they end themselves after three minutes.
func _burn() -> void:
	Engine.max_fps = 30
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		OS.delay_usec(10000)
		await get_tree().process_frame

# ---------- the endless arena, drawn ----------

## Eight players, all played by bots (the host's man by the autopilot), against the arena's waves, as `tests/gate298.gd` plays them.
func _party(m: Match, lo: Dictionary) -> void:
	for i in 7:
		var e = m.spawn_fighter({"kind": "local", "name": "P%d" % i, "loadout": lo.duplicate(true), "team": 0, "pos": Vector3(cos(TAU * float(i) / 7.0) * 3.0, 0.1, sin(TAU * float(i) / 7.0) * 3.0 - 6.0), "yaw": 0.0})
		e.bot = Bot.new(e.f, 0.8, "standard", 99 + i)

## What the match is made of now, a line a few seconds: how far the fight has come, and what the machine's counters say.
func _sample(m: Match, t0_ms: int) -> Dictionary:
	var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
	var foes := m.enemies().filter(func(e): return is_instance_valid(e.f) and e.f.alive).size()
	var men := alive - foes
	var wave := 0
	if m.modes != null and m.modes.endless != null:
		wave = int(m.modes.endless.wave)
	return {"kind": "sample", "t": float(Time.get_ticks_msec() - t0_ms) / 1000.0, "wave": wave, "men": men, "foes": foes, "held": int(m.gate_held), "coming": int(m.coming),
		"step_ms": Net.step_ms, "over": Net.overloaded, "fps": Engine.get_frames_per_second(), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), "mem_mb": int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		"awake": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), "bodies_pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))}

func _sampler(m: Match, every: float) -> void:
	var t0 := Time.get_ticks_msec()
	while _sampling and is_instance_valid(m):
		await _pause(every)
		if _sampling and is_instance_valid(m):
			say(_sample(m, t0))

func _fight() -> void:
	var secs := DiagStats.cfg_f(cfg, "secs", 40.0)
	var first := minf(DiagStats.cfg_f(cfg, "first", 12.0), secs * 0.5)
	if DiagStats.cfg_i(cfg, "sound", 0) == 0:
		_quiet()
	await _player_graphics()
	rec = DiagFrames.new()
	add_child(rec)
	seed(7)
	var lo := {"main": "gladius", "off": "scutum", "armor": ARMOUR}
	var t0 := Time.get_ticks_usec()
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "endless", "role": "host", "headless": not windowed, "autopilot": true, "seed": 7, "decrees": [], "hazards": [], "loadout": lo})
	if not windowed:
		m.stage_always = true
	if DiagStats.cfg_i(cfg, "gate", 0) == 0:
		m.gate_cost_ms = 0.0   # (the foes' gate off, as the arena was: the load is the same from one run to the next, and every wave comes in whole)
	_party(m, lo)
	if windowed:
		add_child(Hud.new(m))
	say({"kind": "setup", "label": "the match, the arena and eight armoured men built at once", "ms": float(Time.get_ticks_usec() - t0) / 1000.0})
	var t_fight := Time.get_ticks_msec()
	_sampling = true
	_sampler(m, 5.0)
	say(await rec.measure("fight, the first %d s" % int(first), first))
	say(await rec.measure("fight, the rest", secs - first))
	_sampling = false
	say(_sample(m, t_fight))

# ---------- the steady scene, under settings ----------

func _apply(name: String, c: Dictionary) -> void:
	var vp := get_viewport()
	match name:
		"3D not drawn":
			vp.disable_3d = true
		"3D at half the size":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.5
		"no anti-aliasing":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"quality low":
			Arena.apply_quality(c.env, c.sun, "low")
		"quality ultra":
			Arena.apply_quality(c.env, c.sun, "ultra")
		"no sun shadows":
			c.sun.shadow_enabled = false
		"no fog, no ambient occlusion, no glow":
			c.env.volumetric_fog_enabled = false
			c.env.ssao_enabled = false
			c.env.ssil_enabled = false
			c.env.glow_enabled = false
		"the men not drawn":
			for e in c.m.entities:
				if is_instance_valid(e.f):
					e.f.visible = false
		"the HUD not drawn":
			c.hud.visible = false
		"vsync off, no frame cap":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0

func _undo(name: String, c: Dictionary) -> void:
	var vp := get_viewport()
	match name:
		"3D not drawn":
			vp.disable_3d = false
		"3D at half the size":
			vp.scaling_3d_mode = c.base.mode
			vp.scaling_3d_scale = c.base.scale
		"no anti-aliasing":
			vp.msaa_3d = c.base.msaa
			vp.screen_space_aa = c.base.saa
		"quality low", "quality ultra", "no fog, no ambient occlusion, no glow":
			Arena.apply_quality(c.env, c.sun, c.quality)
		"no sun shadows":
			c.sun.shadow_enabled = true
		"the men not drawn":
			for e in c.m.entities:
				if is_instance_valid(e.f):
					e.f.visible = true
		"the HUD not drawn":
			c.hud.visible = true
		"vsync off, no frame cap":
			DisplayServer.window_set_vsync_mode(c.base.vsync)
			Engine.max_fps = c.base.fps

const RENDER_VARIANTS := ["3D not drawn", "the men not drawn", "the HUD not drawn", "no sun shadows", "3D at half the size", "no anti-aliasing", "quality low", "quality ultra", "no fog, no ambient occlusion, no glow", "vsync off, no frame cap"]

func _render() -> void:
	if not windowed:
		say({"kind": "skipped", "what": "needs a window"})
		return
	_quiet()
	await _player_graphics()
	rec = DiagFrames.new()
	add_child(rec)
	seed(7)
	var lo := {"main": "gladius", "off": "scutum", "armor": ARMOUR}
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": false, "seed": 7, "decrees": [], "hazards": [], "loadout": lo, "role": "host"})
	m.me.drive = func(_e): return {}
	for e in m.entities.duplicate():
		if e.kind == "npc":
			m._remove_entity(e)
	var heading := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:
		var a := TAU * float(i) / 7.0
		var e = m.spawn_fighter({"kind": "bot", "name": "F%d" % i, "loadout": lo.duplicate(true), "team": 10 + i, "pos": Vector3(cos(a) * 3.0, 0.1, sin(a) * 3.0 + 4.0), "yaw": a + PI})
		e.erase("bot")
		heading[e.id] = rng.randf() * TAU
		e.drive = func(en):
			var id: int = en.id
			if rng.randf() < 0.01:
				heading[id] = rng.randf() * TAU
			return {"mz": 1.0, "look": {"yaw": heading[id], "pitch": 0.0}}
	var hud := Hud.new(m)
	add_child(hud)
	var vp := get_viewport()
	var c := {"m": m, "hud": hud, "env": m.arena.env, "sun": m.arena.sun, "quality": str(Save.get_value("settings", {}).get("quality", "high")),
		"base": {"mode": vp.scaling_3d_mode, "scale": vp.scaling_3d_scale, "msaa": vp.msaa_3d, "saa": vp.screen_space_aa, "vsync": DisplayServer.window_get_vsync_mode(), "fps": Engine.max_fps}}
	var secs := DiagStats.cfg_f(cfg, "secs", 5.0)
	await _pause(DiagStats.cfg_f(cfg, "warm", 3.0))
	say(await rec.measure("as the player has it", secs))
	for name in DiagStats.plus_list(DiagStats.cfg_s(cfg, "variants", "+".join(RENDER_VARIANTS))):
		_apply(name, c)
		await _pause(1.0)
		say(await rec.measure(name, secs))
		_undo(name, c)
		await _pause(0.5)
	say(await rec.measure("as the player has it, again", secs))

# ---------- the room ----------

func _find_menu() -> Node:
	for i in 900:
		for ch in get_parent().get_children():
			if ch != self and ch is Control and ch.has_method("_open_station"):
				return ch
		await get_tree().process_frame
	return null

func _find_strip() -> FriendsStrip:
	for i in 600:
		for ch in get_tree().root.get_children():
			if ch is FriendsStrip:
				return ch
		await get_tree().process_frame
	return null

## The lines the game's own record (hitches.txt) gained since `from` bytes: the slow stretches, the stalls, the match's starts, who had the processor.
func _record_since(from: int) -> Array:
	var p := FpsMeter.log_path()
	if not FileAccess.file_exists(p):
		return []
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return []
	if from > f.get_length():
		from = 0   # (the file was begun again)
	f.seek(from)
	var out := []
	while not f.eof_reached():
		var l := f.get_line()
		if l.strip_edges() != "":
			out.append(l.left(600))
	return out

## The room's connection, where the game's own is an ENet one.
func _enet() -> ENetConnection:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		return (peer as ENetMultiplayerPeer).host
	return null

## The endless arena's counters every few seconds, whichever match of the room is the arena now.
func _room_sampler(menu: Node, every: float, t0_ms: int) -> void:
	while _sampling and is_instance_valid(menu):
		await _pause(every)
		var m: Match = menu.match_
		if _sampling and m != null and is_instance_valid(m) and m.mode == "endless":
			var s := _sample(m, t0_ms)
			s["friends"] = Friends.live_pids.size()
			say(s)

func _room() -> void:
	var secs := DiagStats.cfg_f(cfg, "secs", 240.0)
	var want := DiagStats.cfg_i(cfg, "friends", 7)
	var rec_from := 0
	if FileAccess.file_exists(FpsMeter.log_path()):
		var f0 := FileAccess.open(FpsMeter.log_path(), FileAccess.READ)
		if f0 != null:
			rec_from = int(f0.get_length())
	var menu := await _find_menu()
	if menu == null:
		say({"kind": "error", "what": "the game's menu did not come up"})
		return
	_quiet()
	rec = DiagFrames.new()
	add_child(rec)
	var strip := await _find_strip()
	if strip == null:
		say({"kind": "error", "what": "the room did not open (no friends' strip: is port %d free?)" % Net.PORT})
		return
	var t0 := Time.get_ticks_msec()
	for i in want:
		strip.friends.add()
		await _pause(1.5)
	var came := await _until(func(): return Net.peers.size() >= want, 120.0)
	say({"kind": "room", "step": "friends", "wanted": want, "in": Net.peers.size(), "ok": came, "pids": Array(Friends.live_pids), "s": float(Time.get_ticks_msec() - t0) / 1000.0})
	var in_yard := await _until(func(): return menu.in_yard() and menu.match_ != null and not menu.match_.hold and menu.match_.humans().size() >= want + 1, 150.0)
	say({"kind": "room", "step": "yard", "ok": in_yard, "humans": menu.match_.humans().size() if menu.match_ != null else 0, "s": float(Time.get_ticks_msec() - t0) / 1000.0})
	await _pause(8.0)   # (they spread out)
	say(await rec.measure("the yard, eight players", 15.0))
	var rounds := 0
	var began := false
	var t_fight := Time.get_ticks_msec()
	var win_left := secs
	while win_left > 0.0:
		var m: Match = menu.match_
		if m == null or m.mode != "endless" or m.hold:
			if m == null or m.mode != "endless":
				if Net.active() and Net.is_host():
					menu._fight_press("endless")   # (what the gate's card does in a room, whatever language the game is in)
					rounds += 1
				await _pause(1.0)
			var ok := await _until(func(): return menu.match_ != null and menu.match_.mode == "endless" and not menu.match_.hold and menu.match_.modes != null and menu.match_.modes.endless != null, 90.0)
			if not ok:
				say({"kind": "error", "what": "the endless arena did not begin"})
				break
			if not began:
				began = true
				t_fight = Time.get_ticks_msec()
				_sampling = true
				_room_sampler(menu, 5.0, t_fight)
				say({"kind": "room", "step": "endless", "ok": true, "rounds": rounds, "s": float(Time.get_ticks_msec() - t0) / 1000.0})
		# the rewards a beaten wave holds out: whoever stands at the host's cards takes the first
		if menu.endless_layer != null and is_instance_valid(menu.endless_layer):
			var cards: Array = menu.endless_layer.find_children("*", "Button", true, false)
			if not cards.is_empty():
				(cards[0] as Button).pressed.emit()
		var len := minf(30.0, win_left)
		var enet := _enet()
		if enet != null:
			enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
			enet.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
		var w := await rec.measure("room, endless, %d-%d s" % [int(secs - win_left), int(secs - win_left + len)], len)
		if enet != null:
			w["sent_kbs"] = enet.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / 1024.0 / len
			w["recv_kbs"] = enet.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA) / 1024.0 / len
		w["friends"] = Friends.live_pids.size()
		w["scale_3d"] = get_viewport().scaling_3d_scale   # (a room of this one computer's own windows is drawn at 70% and capped at 60 frames: Menu.room_scale, room_fps)
		w["max_fps"] = Engine.max_fps
		w["over"] = Net.overloaded
		w["step_ms"] = Net.step_ms
		say(w)
		win_left -= len
	_sampling = false
	say({"kind": "room", "step": "over", "rounds": rounds})
	say({"kind": "record", "path": FpsMeter.log_path(), "lines": _record_since(rec_from).slice(0, 220)})
