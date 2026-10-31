extends Node
## J and H on a weapon taken up off the sand do what they do on one he came in with: J crosses it
## to the other hand, H puts both hands on the haft; it is never let fall (user).

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _base() -> Dictionary:
	return {"main": {"x": 0.2, "y": 0.2}, "off": {"x": -0.35, "y": 0.1}, "power": false, "look": {"yaw": 0.0, "pitch": 0.0}, "mx": 0.0, "mz": 0.0}

func _setup(lo: Dictionary) -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": lo})
	var f: Fighter = m.me.f
	f.teleport(Vector3(5, 0, 0))
	var q := []
	m.me.drive = func(_e): return q.pop_front() if not q.is_empty() else _base()
	await _steps(60)
	return [m, f, q]

func _take(m: Match, f: Fighter, q: Array, preset: String, side: String) -> Weapon:
	var w := m.spawn_loose_weapon(Data.preset(preset), f.hand_world(side) + Vector3(0.3 * (1 if side == "R" else -1), -0.3, 0.3))
	await _steps(30)
	var g := _base()
	g.grab = true
	q.append(g)
	for i in 420:
		await get_tree().physics_frame
		if f.weapons[side] == w:
			break
	await _steps(20)
	return w

func test_j_and_h_on_a_weapon_off_the_sand() -> void:
	for preset in (OS.get_environment("PRESETS").split(",") if OS.get_environment("PRESETS") != "" else PackedStringArray(["gladius", "longsword", "axe", "mace"])):
		for key in ["swap", "grip"]:
			var side := "L" if key.ends_with("L") else "R"
			key = key.trim_suffix("L")
			var s = await _setup({"main": "", "off": ""})
			var m: Match = s[0]
			var f: Fighter = s[1]
			var q: Array = s[2]
			var w := await _take(m, f, q, preset, side)
			var held_r: bool = f.weapons[side] == w
			var k := _base()
			k[key] = true
			q.append(k)
			await _steps(90)
			var held: bool = f.weapons.R == w or f.weapons.L == w
			print("%s %s %s: taken %s  after: R=%s L=%s two=%s wait=%.2f holder=%s" % [preset, key, side, held_r, f.weapons.R == w, f.weapons.L == w, f.two_handed, f.grip_wait, w.holder == f])
			t.check(held_r, "%s taken up" % preset)
			t.check(held, "%s after %s: still in hand" % [preset, key])
			m.queue_free()
			await _steps(2)

func test_j_and_h_with_a_weapon_already_in_the_other_hand() -> void:
	for key in ["swap", "grip"]:
		var s = await _setup({"main": "gladius", "off": ""})
		var m: Match = s[0]
		var f: Fighter = s[1]
		var q: Array = s[2]
		var main: Weapon = f.weapons.R
		var w := await _take(m, f, q, "mace", "L")
		var held_l: bool = f.weapons.L == w
		var k := _base()
		k[key] = true
		q.append(k)
		await _steps(90)
		print("%s: taken L %s  after: R=%s L=%s main R=%s main L=%s two=%s" % [key, held_l, f.weapons.R == w, f.weapons.L == w, f.weapons.R == main, f.weapons.L == main, f.two_handed])
		t.check(held_l, "mace taken up in the left hand")
		t.check(f.weapons.R == w or f.weapons.L == w, "after %s the mace taken up is still in hand" % key)
		t.check(f.weapons.R == main or f.weapons.L == main, "after %s the sword is still in hand" % key)
		m.queue_free()
		await _steps(2)
