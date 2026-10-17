extends Node
## The campaign body (Body): what a fight leaves on a gladiator is read off him, kept, and built
## back into him; the physician fits prosthetics; the rare medicine heals a scar; an elephant's
## stomp crushes the part it lands on.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_wounds_are_read_off_and_kept() -> void:
	var m := _match()
	var f: Fighter = m.me.f
	await _steps(30)
	var th: VoxelPart = f.by_name.thighR
	var hole := []
	for i in th.fx.size():
		if th.fx[i] < 2 and th.fy[i] > 6 and th.fy[i] < 10:
			hole.append(i)
	th.remove_voxels(hole)
	f.detach_limb(f.by_name.forearmL, {"removed": [], "severed": []})
	f.head.remove_voxels(Body.eye_voxels(f.head, "R"))
	var r := Body.merge(Body.empty(), Body.snapshot(f))
	t.check(r.body.missing.has("forearmL"), "the lost forearm is kept")
	t.check(r.body.scars.has("thighR") and r.body.scars.thighR.size() == hole.size(), "the hole in the thigh is kept as a scar (%d voxels)" % hole.size())
	t.eq(r.body.eyes.get("R", ""), "lost", "the right eye is lost")
	t.check(r.doctor, "a lost hand and eye take him to the physician")
	t.check(Body.summary(r.body).contains("no left forearm") or Body.summary(r.body).contains("forearm"), "the summary says so: " + Body.summary(r.body))
	# Built again from that body: the dent, the stump, the dark eye.
	var e2 = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 0, "pos": Vector3(3, 0, 0), "yaw": 0.0, "body": r.body})
	e2.erase("bot")
	e2.drive = func(_e): return {}
	var g: Fighter = e2.f
	await _steps(30)
	var th2: VoxelPart = g.by_name.thighR
	t.eq(th2.fx.size() - th2.alive_count, hole.size(), "the old wound is a dent of the same voxels")
	t.check(g.by_name.forearmL.missing and not g.by_name.forearmL.visible and g.weapons.L == null, "no left forearm, so no shield")
	t.check(g.eye_floor > 0.2, "one eye: the aim never quite steadies")
	m.queue_free()

func test_prosthetics_work_worse_and_a_blade_arm_cannot_be_dropped() -> void:
	var m := _match()
	var b := Body.empty()
	b.missing = ["shinR", "forearmR", "forearmL"]
	b = Body.apply(Body.apply(Body.apply(b, "peg:shinR"), "blade:forearmR"), "hook:forearmL")
	t.eq(b.prosthetics.get("shinR", ""), "peg", "a peg leg fitted")
	var e = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {"main": "longsword", "off": "roundShield"}, "team": 0, "pos": Vector3(0, 0, 3), "yaw": 0.0, "body": b})
	e.erase("bot")
	var f: Fighter = e.f
	e.drive = func(_e): return {"mz": 1.0}
	await _steps(300)
	t.eq(f.state, "stand", "he stands and walks on the peg")
	t.check(f.leg_func("R") <= 0.61 and f.leg_func("L") > 0.9, "a peg is never a foot (R %.2f, L %.2f)" % [f.leg_func("R"), f.leg_func("L")])
	t.check(f.weapons.R != null and String(f.weapons.R.design.name) == "Blade arm", "the right arm is a blade")
	t.check(f.release("R") == null and f.throw_weapon("R") == null and f.weapons.R != null, "and it cannot be dropped or thrown")
	t.check(f.weapons.L == null and not f.pick_up("L", m.spawn_loose_weapon(Data.preset("dagger"), Vector3(0, 1, 0))), "a hook holds nothing")
	t.check(f.handling.R < 0.75, "the blade arm swings clumsily (handling %.2f)" % f.handling.R)
	m.queue_free()

func test_the_rare_medicine_heals_one_scar() -> void:
	var b := Body.empty()
	b.scars = {"thighR": [1, 2, 3, 4, 5], "torso": [7, 8]}
	var stocked := -1
	for s in range(1, 9):
		if Body.medicine_in_stock(s):
			stocked = s
			break
	var none := -1
	for s in range(1, 9):
		if not Body.medicine_in_stock(s):
			none = s
			break
	t.check(stocked > 0 and none > 0, "in stock on some stages, not on others")
	t.check(not Body.offers(b, none).any(func(o): return String(o.id).begins_with("medicine")), "not every day")
	var o: Array = Body.offers(b, stocked).filter(func(x): return String(x.id).begins_with("medicine"))
	t.eq(o.size(), 1, "the physician has one jar")
	var healed := Body.apply(b, String(o[0].id))
	t.check(not healed.scars.has("thighR") and healed.scars.has("torso"), "it closes the worst scar, only that one")

func test_the_physician_between_rounds_rebuilds_the_man() -> void:
	var m := _match()
	var f: Fighter = m.me.f
	var seen := []
	m.doctor.connect(func(e, b, news): seen.append([e, b, news]))
	await _steps(30)
	f.detach_limb(f.by_name.shinL, {"removed": [], "severed": []})
	m._round_wounds()
	t.eq(seen.size(), 1, "losing a foot takes him to the physician")
	t.check(not m.doctor_wait.is_empty(), "the next round waits for him")
	var nb := Body.apply(seen[0][1], "peg:shinL")
	m.doctor_done(m.me.id, nb)
	await _steps(10)
	t.check(m.doctor_wait.is_empty(), "and goes on when he is back")
	t.check(is_instance_valid(m.me.f) and m.me.f != f and m.me.f.by_name.shinL.prosthetic == "peg", "he comes back on a peg leg")
	m.queue_free()

func test_an_elephant_stomp_crushes_what_it_lands_on() -> void:
	var m := _match()
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 0, "pos": Vector3(0, 0, 2.6), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	var v: Fighter = e.f
	m.me.f.teleport(Vector3(0, 0, -12))
	var be = m.spawn_beast({"beast": "elephant", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "harmless": true})
	await _steps(60)
	var before: int = v.parts.reduce(func(a, p): return a + p.alive_count, 0)
	m._stomp(be.f)
	await _steps(5)
	var after: int = v.parts.reduce(func(a, p): return a + p.alive_count, 0)
	t.check(before - after >= 20, "a crater crushed into him (%d voxels)" % (before - after))
	t.check(v.state != "stand", "and he is knocked off his feet")
	m.queue_free()

func test_on_one_leg_he_hops() -> void:
	var m := _match()
	var e = m.spawn_fighter({"kind": "bot", "name": "H", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 1, "pos": Vector3(4, 0, 3), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {"mz": 1.0}
	var f: Fighter = e.f
	await _steps(2)
	f.detach_limb(f.by_name.shinL, {"removed": [], "severed": []})
	var p0 := f.torso.global_position
	var lo := INF
	var hi := -INF
	for i in 600:
		f.blood = 100.0
		for p in f.parts:
			p.bleed = 0.0
		await get_tree().physics_frame
		if i > 240:
			lo = minf(lo, f.torso.global_position.y)
			hi = maxf(hi, f.torso.global_position.y)
	t.eq(f.state, "stand", "he keeps his one foot")
	t.check(f.torso.global_position.distance_to(p0) > 1.5, "and gets on, hop by hop")
	t.check(hi - lo > 0.05, "rising and dropping with each hop (%.2f m)" % (hi - lo))
	m.queue_free()

## The Elixir of Asclepius: dear, and it gives back all the campaign took (a lost leg, a
## replaced hand, a blind eye, the old wounds); offered only to a body that needs it.
func test_the_elixir_gives_back_everything() -> void:
	var b := Body.sanitize({"missing": ["shinL", "forearmR"], "prosthetics": {"forearmR": "hook"}, "eyes": {"L": "lost"}, "fights": 7})
	b.missing.erase("forearmR")
	var offer := Body.offers(b, 1).filter(func(o): return String(o.id) == "elixir:all")
	t.eq(offer.size(), 1, "the physician has it for a body that needs it")
	t.check(int(offer[0].price) >= 300 and int(offer[0].price) > Body.MEDICINE_PRICE * 2, "and it costs a fortune (%d)" % int(offer[0].price))
	var whole := Body.apply(b, "elixir:all")
	t.check(whole.missing.is_empty() and whole.prosthetics.is_empty() and whole.eyes.is_empty() and whole.scars.is_empty(), "whole again: %s" % Body.summary(whole))
	t.eq(int(whole.fights), 7, "the fights fought are still his")
	t.check(not Body.offers(Body.empty(), 1).any(func(o): return String(o.id) == "elixir:all"), "not sold to a whole man")
	t.eq(Body.price_of("elixir:all"), Body.ELIXIR_PRICE, "priced the same everywhere")
