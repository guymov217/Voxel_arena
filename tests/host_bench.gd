extends Node
## How many fighters this computer can host (`--headless --fixed-fps 120 -- --probe host_bench`,
## or tools/host_bench.bat): the host's game runs every fighter's physics, so whether a room is
## smooth is whether its step stays inside 1/120 s. Fights of 4, 8, 12 and 16 fighters (half
## men, half the campaign's men and beasts against them) are run as fast as the machine goes, and
## each says the time of a step and what that means for a room. No network, no players needed.

const BUDGET_MS := 1000.0 / 120.0
const SIZES := [4, 8, 12, 16]
const SECONDS := 6.0

func _ready() -> void:
	var rows := []
	print("WRECKSMITH host check: %s, %d threads" % [OS.get_processor_name(), OS.get_processor_count()])
	for n in SIZES:
		var ms := await _bout(n)
		rows.append([n, ms])
		print("  %2d fighters: %5.1f ms a step (budget %.1f ms) -> %s" % [n, ms, BUDGET_MS, _verdict(ms)])
	var best := 0
	for r in rows:
		if float(r[1]) <= BUDGET_MS * 0.85:
			best = int(r[0])
	print("")
	if best == 0:
		print("RESULT this computer is too slow to host even 4 fighters smoothly")
	else:
		print("RESULT this computer hosts up to about %d fighters smoothly (players + enemies on the sand at once)" % best)
	print("       a guest's computer does far less (it only draws what the host sends)")
	get_tree().quit()

func _verdict(ms: float) -> String:
	if ms <= BUDGET_MS * 0.85:
		return "smooth"
	if ms <= BUDGET_MS * 1.1:
		return "at the limit (a heavy moment slows it)"
	return "too slow: the game would run at %d%% speed" % roundi(100.0 * BUDGET_MS / ms)

func _bout(n: int) -> float:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -14))
	var foes := ["recruit", "shieldbearer", "brute", "murmillo"]
	var beasts := ["wolf", "lion", "bear", "boar"]
	var weapons := ["gladius", "axe", "mace", "spear"]
	for i in n:
		var a := TAU * i / n
		var pos := Vector3(sin(a) * 5.0, 0.1, cos(a) * 5.0)
		if i % 2 == 0:
			var e = m.spawn_fighter({"kind": "bot", "name": "P%d" % i, "loadout": {"main": weapons[i % 4], "off": "roundShield" if i % 4 == 0 else ""}, "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
		elif i % 4 == 1:
			var spec: Dictionary = m.enemy_spec({"e": foes[(i / 4) % foes.size()]}, 0, 1)
			spec.pos = pos
			spec.yaw = a + PI
			m.spawn_fighter(spec)
		else:
			m.spawn_beast({"beast": beasts[(i / 4) % beasts.size()], "team": Match.ENEMY_TEAM, "pos": pos, "yaw": a + PI})
	for k in 120:
		await get_tree().physics_frame
	var t0 := Time.get_ticks_usec()
	var steps := int(SECONDS * 120.0)
	for k in steps:
		await get_tree().physics_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	m.queue_free()
	for k in 10:
		await get_tree().physics_frame
	return ms
