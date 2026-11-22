extends Node
## Does the way steps are shared out among frames change the game (#298)? The same fight (bots and the campaign's armoured men, seed 7) for exactly STEPS
## physics steps, then a fingerprint of every body. Run with --fixed-fps 120 (a step to a frame), and in real time (RT=1: the frames at 60 a second at most, the men's
## drawing on) with the engine's cap at 4 and at 2 (CAP, PACE=0), or with the governor (no PACE), on one core, so that the frames come with a different number of
## steps each. One worker thread (override.cfg: tools/mix_load.sh makes it), or the physics' jobs come back in a different order from run to run.
## env STEPS (720), MEN (8), FOES (6), CAP, RT, DRAW (1/0: the men's drawing on or off whatever the mode), PACE=0 (the governor off), EVERY=n (also a
## fingerprint every n steps: how far two runs go together), SEEDSTEP=1 (the dice seeded afresh at the start of every step: see the README).
var m: Match
var steps := 0
var want := 720
var every := 0
var seed_step := false
var done := false
var frames0 := 0
var t0 := 0

func _ready() -> void:
	want = int(OS.get_environment("STEPS")) if OS.get_environment("STEPS") != "" else 720
	every = int(OS.get_environment("EVERY")) if OS.get_environment("EVERY") != "" else 0
	seed_step = OS.get_environment("SEEDSTEP") == "1"
	if OS.get_environment("RT") == "1":
		Engine.max_fps = 60
		Fighter.process_in_headless = true
	if OS.get_environment("DRAW") != "":
		Fighter.process_in_headless = OS.get_environment("DRAW") == "1"   # (the men's drawing on or off, whatever the mode)
	if OS.get_environment("CAP") != "":
		Engine.max_physics_steps_per_frame = int(OS.get_environment("CAP"))
	if OS.get_environment("PACE") == "0":
		Net.overload_on = false   # (the engine's four steps to a frame, as before the two)
	seed(7)
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -20))
	var weapons := ["gladius", "axe", "mace", "spear"]
	var foes := ["recruit", "shieldbearer", "brute", "murmillo"]
	var n_men := int(OS.get_environment("MEN")) if OS.get_environment("MEN") != "" else 8
	var n_foes := int(OS.get_environment("FOES")) if OS.get_environment("FOES") != "" else 6
	var total := n_men + n_foes
	for i in total:
		var a := TAU * i / total
		var pos := Vector3(sin(a) * 6.0, 0.1, cos(a) * 6.0)
		if i % 2 == 0 and i / 2 < n_men:
			m.spawn_fighter({"kind": "bot", "name": "P%d" % i, "loadout": {"main": weapons[i % 4], "off": "roundShield" if i % 4 == 0 else ""}, "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
		else:
			var sp: Dictionary = m.enemy_spec({"e": foes[i % foes.size()]}, 0, 1)
			sp.pos = pos
			sp.yaw = a + PI
			m.spawn_fighter(sp)
	frames0 = Engine.get_process_frames()
	t0 = Time.get_ticks_msec()

func _world_hash() -> Array:   # [the fingerprint of every body, how many are alive]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var alive := 0
	for e in m.entities:
		if not is_instance_valid(e.f):
			continue
		alive += 1 if e.f.alive else 0
		ctx.update(Match.pack_parts(e.f.parts))
		var hp := PackedFloat32Array()
		for p in e.f.parts:
			hp.append(p.hp)
		ctx.update(hp.to_byte_array())
	return [ctx.finish().hex_encode(), alive]

func _physics_process(_dt: float) -> void:
	if done:
		return
	steps += 1
	if seed_step:
		seed(steps)   # (before the step's own dice are rolled: this node's physics comes before the fight's)
	if every > 0 and steps % every == 0 and steps < want:
		var w := _world_hash()
		print("PHASH step=%d alive=%d %s" % [steps, w[1], w[0]])
	if steps < want:
		return
	done = true
	var h := _world_hash()
	var frames := Engine.get_process_frames() - frames0
	print("PACEHASH steps=%d fighters=%d alive=%d frames=%d (%.1f steps a frame) wall %.1f s cap %d: %s" % [steps, m.entities.size(), h[1], frames, float(steps) / maxf(1.0, frames), (Time.get_ticks_msec() - t0) / 1000.0, Engine.max_physics_steps_per_frame, h[0]])
	get_tree().quit(0)
