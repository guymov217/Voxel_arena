extends Node
## The Endless Arena of a full room, as the host's machine meets it (#310): men fighting wave after wave (a mix as in mix298, env MIX, e.g.
## "men:8,foe:6,beast:wolf*2,beast:lion"), the dead left lying as they are in the arena. Every EVERY seconds (game time) it prints what a
## step costs (mean, p99, worst), what the frame's own scripts cost (the `_process` phase, F3's "in the frame"), the draw calls, objects and
## primitives of the last frame (when the game draws: a display, not --headless), how many frames and steps a second came, the men alive, the
## fallen and the pieces lying about.
##   godot --path . -- --probe endless_fps                        on a screen: the FPS and the steps a second are what the room sees
##   godot --headless --fixed-fps 120 --path . -- --probe endless_fps     as fast as the machine goes: steps and scripts only, no drawing
##   xvfb-run -a godot --fixed-fps 120 --path . -- --probe endless_fps    a software renderer: the draw calls count right, the times do not
## env: MIX, SECS (60), EVERY (10), SEED (7), DRAW (1: the game draws, 0: not).

const Kit := preload("res://tests/e2e_kit.gd")

var t_start := 0
var spans := PackedInt32Array()      # the process phase, one entry a frame
var t_ph := 0
var phys := PackedInt32Array()       # the nodes' physics phase (first node's step to the last's), one entry a step
var gaps := PackedFloat32Array()     # the physics steps, ms between two
var frames := 0
var steps := 0
var t_prev := 0

class StartMark extends Node:
	var owner_: Node
	func _process(_dt: float) -> void:
		owner_.t_start = Time.get_ticks_usec()
		owner_.frames += 1
class EndMark extends Node:
	var owner_: Node
	func _process(_dt: float) -> void:
		if owner_.t_start > 0:
			owner_.spans.append(Time.get_ticks_usec() - owner_.t_start)

class PhysStart extends Node:
	var owner_: Node
	func _physics_process(_dt: float) -> void:
		owner_.t_ph = Time.get_ticks_usec()
class PhysEnd extends Node:
	var owner_: Node
	func _physics_process(_dt: float) -> void:
		if owner_.t_ph > 0:
			owner_.phys.append(Time.get_ticks_usec() - owner_.t_ph)

func _physics_process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if t_prev > 0:
		gaps.append(float(now - t_prev) / 1000.0)
	t_prev = now
	steps += 1

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

## The rigid bodies of the tree by what they are and whether they are awake: [alive men's parts, the fallen's parts, weapons, chunks, other] each as [awake, all].
func _census(n: Node, acc: Array) -> void:
	if n is RigidBody3D:
		var i := 4
		if n is VoxelPart:
			i = 0 if (n.fighter != null and is_instance_valid(n.fighter) and n.fighter.alive) else 1
		elif n is Weapon:
			i = 2
		elif n is Chunk:
			i = 3
		acc[i][1] += 1
		if not n.sleeping and not n.freeze:
			acc[i][0] += 1
	for k in n.get_children():
		_census(k, acc)

## The meshes of the tree that are drawn (visible, cast or not), by what carries them: {"what": [mesh instances, surfaces, of them casting shadows]}.
func _meshes(n: Node, acc: Dictionary, owner_what: String) -> void:
	var what := owner_what
	if n is VoxelPart:
		what = "men's parts (alive)" if (n.fighter != null and is_instance_valid(n.fighter) and n.fighter.alive) else "men's parts (fallen)"
	elif n is Weapon:
		what = "weapons"
	elif n is Chunk:
		what = "chunks"
	elif n is Fighter:
		what = "men (the body's own)"
	elif n is Beast:
		what = "beasts (the body's own)"
	if n is MeshInstance3D and n.is_visible_in_tree() and n.mesh != null:
		var r: Array = acc.get(what, [0, 0, 0])
		r[0] += 1
		r[1] += n.mesh.get_surface_count()
		if n.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			r[2] += n.mesh.get_surface_count()
		acc[what] = r
	elif n is MultiMeshInstance3D and n.is_visible_in_tree() and n.multimesh != null:
		var r2: Array = acc.get("multimeshes", [0, 0, 0])
		r2[0] += 1
		r2[1] += 1
		if n.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			r2[2] += 1
		acc["multimeshes"] = r2
	for k in n.get_children():
		_meshes(k, acc, what)

## Why the fallen's parts are awake: for each awake part of a dead man, what it presses on (by kind), and whether it presses on anything awake.
func _why(m: Match) -> String:
	var awake := 0
	var none := 0
	var kinds := {}
	var only_dead := 0
	var with_awake_other := 0
	var spots := 0
	var fast := 0
	for e in m.entities:
		var f = e.f
		if not is_instance_valid(f) or f.alive:
			continue
		for p in f.parts:
			if p.severed or p.sleeping or p.freeze:
				continue
			awake += 1
			if not p.spots.is_empty():
				spots += 1
			if p.linear_velocity.length_squared() > 0.04:
				fast += 1
			var cs: Array = p.get_colliding_bodies()
			if cs.is_empty():
				none += 1
			var other_awake := false
			var only_corpse := not cs.is_empty()
			for o in cs:
				var k := "ground/static"
				if o is VoxelPart:
					k = "own part" if o.fighter == f else ("dead man's part" if (o.fighter != null and not o.fighter.alive) else "living man's part")
					if not (o.fighter != null and not o.fighter.alive):
						only_corpse = false
					if not o.sleeping and not o.freeze:
						other_awake = true
				elif o is Weapon:
					k = "weapon"
					only_corpse = false
					other_awake = true
				elif o is Chunk:
					k = "chunk"
					only_corpse = false
					if not o.sleeping:
						other_awake = true
				else:
					only_corpse = false
				kinds[k] = int(kinds.get(k, 0)) + 1
			if other_awake:
				with_awake_other += 1
	return "awake dead parts %d: no contact %d, touching an awake body %d, fast(v>0.2) %d, burning %d | contacts by kind %s" % [awake, none, with_awake_other, fast, spots, str(kinds)]

func _count(n: Node, what: String) -> int:
	var c := 0
	if what == "rigid" and n is RigidBody3D:
		c = 1
	for k in n.get_children():
		c += _count(k, what)
	return c

func _ready() -> void:
	var spec := _env("MIX", "men:8,foe:6,beast:wolf*2,beast:lion")
	var total_s := int(_env("SECS", "60"))
	var every := int(_env("EVERY", "10"))
	var draw := _env("DRAW", "1") != "0"
	var headless := DisplayServer.get_name() == "headless"
	process_physics_priority = -100000
	var s0 := StartMark.new()
	s0.owner_ = self
	s0.process_priority = -100000
	add_child(s0)
	var s1 := EndMark.new()
	s1.owner_ = self
	s1.process_priority = 100000
	add_child(s1)
	var p0 := PhysStart.new()
	p0.owner_ = self
	p0.process_physics_priority = -100000
	add_child(p0)
	var p1 := PhysEnd.new()
	p1.owner_ = self
	p1.process_physics_priority = 100000
	add_child(p1)
	Fighter.process_in_headless = true
	var m := Match.new()
	add_child(m)
	var visuals := _env("VISUALS", "0") == "1"
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": (headless or not draw) and not visuals, "seed": int(_env("SEED", "7")), "decrees": [], "hazards": []})
	m.me.drive = func(_e): return {}
	m.me.f.teleport(Vector3(0, 0, -9))
	var weapons := ["gladius", "axe", "mace", "spear"]
	var foes := ["recruit", "shieldbearer", "brute", "murmillo"]
	var list := []
	for tok in spec.split(","):
		var kv := tok.split(":")
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
	var count := list.size()
	var radius := 5.0 + 0.35 * maxf(0.0, count - 8.0)
	var men_i := 0
	var foe_i := 0
	for i in count:
		var a := TAU * i / count
		var pos := Vector3(sin(a) * radius, 0.1, cos(a) * radius)
		var kind: String = list[i][0]
		var arg: String = list[i][1]
		if kind == "men":
			m.spawn_fighter({"kind": "bot", "name": "P%d" % men_i, "loadout": {"main": weapons[men_i % 4], "off": "roundShield" if men_i % 4 == 0 else ""}, "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
			men_i += 1
		elif kind == "foe":
			var sp: Dictionary = m.enemy_spec({"e": foes[foe_i % foes.size()]}, 0, 1)
			sp.pos = pos
			sp.yaw = a + PI
			m.spawn_fighter(sp)
			foe_i += 1
		elif kind == "beast":
			m.spawn_beast({"beast": arg, "team": Match.ENEMY_TEAM, "pos": pos, "yaw": a + PI})
	# SAMPLE=1: the game is not drawn at all but for a few frames at the end of each stretch, when the draw calls are read (a software renderer
	# draws a frame in seconds: the sand fought at the speed of the steps, the drawing only looked at).
	var sample := _env("SAMPLE", "0") == "1" and not headless and draw
	if sample:
		RenderingServer.render_loop_enabled = false
	for k in 120:
		await get_tree().physics_frame
	print("ENDLESSFPS %s: %d on the sand, %s, drawing %s" % [spec, m.entities.size(), DisplayServer.get_name(), str(not headless and draw) + (" (sampled)" if sample else "")])
	var done := 0
	var t_win := Time.get_ticks_usec()
	spans.clear()
	gaps.clear()
	phys.clear()
	frames = 0
	steps = 0
	while done < total_s:
		var steps_goal := steps + 120 * every
		while steps < steps_goal:
			await get_tree().physics_frame
		done += every
		var wall := float(Time.get_ticks_usec() - t_win) / 1e6
		var sg := Array(gaps)
		sg.sort()
		var sm := 0.0
		for v in sg:
			sm += float(v)
		sm /= maxf(1.0, float(sg.size()))
		var sp_ := Array(spans)
		sp_.sort()
		var pm := 0.0
		for v in sp_:
			pm += float(v)
		pm /= maxf(1.0, float(sp_.size()))
		var ph := 0.0
		for v in phys:
			ph += float(v)
		ph /= maxf(1.0, float(phys.size()))
		var alive := 0
		var fallen := 0
		for e in m.entities:
			if is_instance_valid(e.f):
				if e.f.alive:
					alive += 1
				else:
					fallen += 1
		var cen := [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]
		_census(m, cen)
		var dc := 0
		var ob := 0
		var pr := 0
		if sample:
			RenderingServer.render_loop_enabled = true
			for k in 3:
				await get_tree().process_frame
			RenderingServer.render_loop_enabled = false
		if not headless and draw:
			dc = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			ob = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			pr = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		if sample or visuals:
			var mc := {}
			_meshes(get_tree().root, mc, "the arena and the rest")
			var keys := mc.keys()
			keys.sort_custom(func(a, b): return mc[a][1] > mc[b][1])
			for key in keys:
				print("      meshes: %-26s %5d instances %5d surfaces (%5d cast shadows)" % [key, mc[key][0], mc[key][1], mc[key][2]])
		print("ENDLESSFPS t=%3d s  a step %5.2f ms (p99 %5.2f, worst %6.2f) of which the nodes' %5.2f | frame scripts %5.2f ms (p99 %5.2f) | draw calls %5d objects %5d prims %8d | %3.0f frames/s %3.0f steps/s | alive %2d fallen %2d of %2d | awake/all: alive's parts %d/%d fallen's parts %d/%d weapons %d/%d chunks %d/%d other %d/%d" % [
			done, sm, sg[int(sg.size() * 0.99)] if sg.size() > 0 else 0.0, sg[sg.size() - 1] if sg.size() > 0 else 0.0, ph / 1000.0,
			pm / 1000.0, float(sp_[int(sp_.size() * 0.99)]) / 1000.0 if sp_.size() > 0 else 0.0,
			dc, ob, pr, float(frames) / wall, float(steps) / wall, alive, fallen, m.entities.size(), cen[0][0], cen[0][1], cen[1][0], cen[1][1], cen[2][0], cen[2][1], cen[3][0], cen[3][1], cen[4][0], cen[4][1]])
		print("   WHY ", _why(m))
		spans.clear()
		gaps.clear()
		phys.clear()
		frames = 0
		steps = 0
		t_win = Time.get_ticks_usec()
	get_tree().quit(0)
