class_name DiagFrames
extends Node
## What the frames of a stretch are made of, read as `FpsMeter` reads them but for a stretch asked for (a "window"): the length of each frame, the physics steps it took (from the first
## one's start to where the frame's own work begins: the engine's `process_frame`), what lay between them and the first script's process, the scripts (the first process to the last: this node
## is first and `FrameEnd` is last in every frame), and all the rest, the engine's drawing, presenting and waiting. With a screen also the card's time, the engine's recording of the frame,
## the draw calls, and the pipelines the engine compiled; and the frames over HITCH_MS with what the game had just said (`FpsMeter.note`) and how many nodes and pipelines they made.
## Used by the parts of the diagnostic test (`DiagPhase`); the node must be in the tree to read.

const HITCH_MS := 50.0
const KEEP_HITCHES := 12
const NOTE_SECS := 2.5
const PIPES := [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]

var windowed := false
var hitch_ms := HITCH_MS
var _rid := RID()

# the window being read
var _on := false
var _label := ""
var _t0_us := 0
var _steps0 := 0
var _pipes0 := 0
var _frame_us := PackedInt32Array()
var _draw := {"gpu": 0.0, "cpu": 0.0, "calls": 0.0, "objects": 0.0, "prims": 0.0, "n": 0}
var _hitches: Array = []
var _hitch_n := 0
var _fc := {}
var _notes: Array = []   # [when (us), text] the game's own words of the last moments

# the frame being read
var _last_us := 0
var _last_had_steps := false
var _last_steps := 0
var _last_nodes := 0
var _last_pipes := 0
var _last_res := 0
var _ps_n := 0           # this frame's steps so far, the first one's start, the last one's start
var _ps_t0 := 0
var _ps_prev := 0
var _step_t0 := 0        # where this step's first node began (the last node says where the nodes' part of it ended: StepEnd)
var _pf_at := 0          # where the frame's steps were over (`process_frame`)
var _fr_has := false
var _fr_t0 := 0
var _fr_pf := 0
var _fr_own := 0
var _fr_steps := 0
var _fr_tail := 0

func _ready() -> void:
	process_priority = -100000   # (first in every frame's steps and in its process, as FpsMeter is)
	process_physics_priority = -100000
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().process_frame.connect(_on_pf)
	var fe := FrameEnd.new()
	fe.rec = self
	add_child(fe)
	var se := StepEnd.new()
	se.rec = self
	add_child(se)
	windowed = DisplayServer.get_name() != "headless"
	if windowed:
		_rid = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_rid, true)
	FpsMeter.tap = _on_note
	_fresh()

func _exit_tree() -> void:
	if FpsMeter.tap == _on_note:
		FpsMeter.tap = Callable()
	if windowed and _rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_rid, false)

func _fresh() -> void:
	_fc = {"n": 0, "steps": 0, "pf": 0, "between": 0, "scripts": 0, "inner": 0, "tail": 0, "frame": 0, "nframe": 0, "sspan": 0, "nsteps": 0}

## What the game said of itself (a match set up, the foes in): the hitches name the last of it.
func _on_note(text: String) -> void:
	_notes.append([Time.get_ticks_usec(), text])
	while _notes.size() > 12:
		_notes.pop_front()

static func pipelines() -> int:
	var n := 0
	for m in PIPES:
		n += int(Performance.get_monitor(m))
	return n

func _physics_process(_dt: float) -> void:
	var t := Time.get_ticks_usec()
	if _ps_n == 0:
		_ps_t0 = t
	else:
		_fc.inner += t - _ps_prev   # (a step's own length but for the first of a frame's, which has the frame's preparing in it)
	_ps_prev = t
	_step_t0 = t
	_ps_n += 1

## The last node of a step's `_physics_process` says so (StepEnd): from the first node's start to here is what the game's scripts took of the step, the rest of it is the engine's.
func step_ended() -> void:
	if _on:
		_fc.sspan += Time.get_ticks_usec() - _step_t0
		_fc.nsteps += 1

func _on_pf() -> void:
	_pf_at = Time.get_ticks_usec()

func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _ps_n > 0:
		_fr_has = true
		_fr_t0 = _ps_t0
		_fr_pf = _pf_at if _pf_at >= _ps_t0 else now
		_fr_own = now
		_fr_steps = _ps_n
		_fr_tail = _fr_pf - _ps_prev
		_ps_n = 0
	if not _on:
		_last_us = now
		_last_had_steps = _fr_has
		return
	var steps := Engine.get_physics_frames()
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pipes := pipelines()
	var res := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	if _last_us > 0:
		var len := now - _last_us
		_frame_us.append(len)
		if _last_had_steps:
			_fc.frame += len
			_fc.nframe += 1
		if windowed:
			_draw.gpu += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
			_draw.cpu += RenderingServer.viewport_get_measured_render_time_cpu(_rid) + RenderingServer.get_frame_setup_time_cpu()
			_draw.calls += float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			_draw.objects += float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			_draw.prims += float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			_draw.n += 1
		if float(len) / 1000.0 > hitch_ms:
			_hitch_n += 1
			_keep_hitch(now, len, steps - _last_steps, nodes - _last_nodes, pipes - _last_pipes, res - _last_res)
	_last_had_steps = _fr_has
	_last_us = now
	_last_steps = steps
	_last_nodes = nodes
	_last_pipes = pipes
	_last_res = res

## The last node of a frame's process says so (FrameEnd).
func frame_ended() -> void:
	if not _fr_has:
		return
	_fr_has = false
	if not _on:
		return
	var end := Time.get_ticks_usec()
	_fc.n += 1
	_fc.steps += _fr_steps
	_fc.pf += _fr_pf - _fr_t0
	_fc.between += _fr_own - _fr_pf
	_fc.scripts += end - _fr_own
	_fc.tail += _fr_tail

## The node whose process is the last of every frame's.
class FrameEnd extends Node:
	var rec
	func _init() -> void:
		process_priority = 100000
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _process(_dt: float) -> void:
		if rec != null and is_instance_valid(rec):
			rec.frame_ended()

## The node whose `_physics_process` is the last of every step's.
class StepEnd extends Node:
	var rec
	func _init() -> void:
		process_physics_priority = 100000
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _physics_process(_dt: float) -> void:
		if rec != null and is_instance_valid(rec):
			rec.step_ended()

func _keep_hitch(now: int, len: int, steps: int, dnodes: int, dpipes: int, dres: int) -> void:
	var words := PackedStringArray()
	for n in _notes:
		if now - int(n[0]) <= int(NOTE_SECS * 1e6):
			words.append(String(n[1]).left(70))
	var h := {"t": float(now - _t0_us) / 1e6, "ms": float(len) / 1000.0, "steps": steps, "dnodes": dnodes, "dpipes": dpipes, "dres": dres, "note": " | ".join(words.slice(maxi(0, words.size() - 3)))}
	if _hitches.size() < KEEP_HITCHES:
		_hitches.append(h)
		return
	var low := 0
	for i in _hitches.size():
		if float(_hitches[i].ms) < float(_hitches[low].ms):
			low = i
	if float(h.ms) > float(_hitches[low].ms):
		_hitches[low] = h

## A window begins: what is read from now on is its.
func begin(label: String) -> void:
	_label = label
	_on = true
	_t0_us = Time.get_ticks_usec()
	_steps0 = Engine.get_physics_frames()
	_pipes0 = pipelines()
	_frame_us = PackedInt32Array()
	_draw = {"gpu": 0.0, "cpu": 0.0, "calls": 0.0, "objects": 0.0, "prims": 0.0, "n": 0}
	_hitches = []
	_hitch_n = 0
	_fresh()
	_last_us = 0   # (the frame the window began in is not read: its start was before it)

## The window ends: what it saw (see DiagStats.frames_text for the fields).
func end() -> Dictionary:
	_on = false
	var secs := float(Time.get_ticks_usec() - _t0_us) / 1e6
	var ms := []
	var sum_us := 0
	var o33 := 0
	var o50 := 0
	var o100 := 0
	for u in _frame_us:
		var f := float(u) / 1000.0
		ms.append(f)
		sum_us += int(u)
		if f > 33.4:
			o33 += 1
		if f > 50.0:
			o50 += 1
		if f > 100.0:
			o100 += 1
	var n := ms.size()
	var steps := Engine.get_physics_frames() - _steps0
	var ticks := float(Engine.physics_ticks_per_second)
	var d := {"kind": "frames", "label": _label, "secs": secs, "frames": n, "fps": float(n) / maxf(0.001, float(sum_us) / 1e6),
		"ms": {"mean": DiagStats.mean(ms), "p50": DiagStats.percentile(ms, 0.5), "p95": DiagStats.percentile(ms, 0.95), "p99": DiagStats.percentile(ms, 0.99), "max": DiagStats.worst(ms)},
		"over33": o33, "over50": o50, "over100": o100, "steps": steps, "steps_s": float(steps) / maxf(0.001, secs), "speed": float(steps) / maxf(0.001, secs) / (ticks * maxf(0.001, Engine.time_scale)),
		"hitch_ms": hitch_ms, "hitch_n": _hitch_n, "hitches": _hitches.duplicate(true)}
	var c := int(_fc.n)
	if c > 0:
		var per := 1000.0 * float(c)
		var steps_ms := float(_fc.pf) / per
		var between := float(_fc.between) / per
		var scripts := float(_fc.scripts) / per
		var frame_ms := float(_fc.frame) / 1000.0 / float(_fc.nframe) if int(_fc.nframe) > 0 else steps_ms + between + scripts
		var inner_n := int(_fc.steps) - c
		var ns := maxf(1.0, float(_fc.steps))
		d["comp"] = {"n": c, "frame": frame_ms, "steps": steps_ms, "per_frame": float(_fc.steps) / float(c), "gap": float(_fc.inner) / 1000.0 / float(inner_n) if inner_n > 0 else 0.0,
			"between": between, "scripts": scripts, "tail": float(_fc.tail) / per, "draw_wait": frame_ms - steps_ms - between - scripts,
			"step_scripts": float(_fc.sspan) / 1000.0 / maxf(1.0, float(_fc.nsteps)), "step_engine": (float(_fc.pf) - float(_fc.sspan)) / 1000.0 / ns}
	if windowed and int(_draw.n) > 0:
		var k := float(_draw.n)
		d["gpu"] = float(_draw.gpu) / k
		d["cpu_draw"] = float(_draw.cpu) / k
		d["calls"] = float(_draw.calls) / k
		d["objects"] = float(_draw.objects) / k
		d["prims"] = float(_draw.prims) / k
		d["vram_mb"] = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
		d["tex_mb"] = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)
	if windowed:
		d["focused"] = DisplayServer.window_is_focused()
	d["pipes"] = pipelines() - _pipes0
	d["phys"] = {"active": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), "pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)), "islands": int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))}
	d["orphans"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	d["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	d["mem_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	return d

## A window of `secs` seconds (by the wall clock), and what it saw.
func measure(label: String, secs: float) -> Dictionary:
	begin(label)
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) < secs * 1e6:
		await get_tree().process_frame
	return end()
