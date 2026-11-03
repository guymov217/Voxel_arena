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
	t.check(int(offer[0].price) > Body.medicine_price(1), "dearer than the rare medicine (%d)" % int(offer[0].price))
	var whole := Body.apply(b, "elixir:all")
	t.check(whole.missing.is_empty() and whole.prosthetics.is_empty() and whole.eyes.is_empty() and whole.scars.is_empty(), "whole again: %s" % Body.summary(whole))
	t.eq(int(whole.fights), 7, "the fights fought are still his")
	t.check(not Body.offers(Body.empty(), 1).any(func(o): return String(o.id) == "elixir:all"), "not sold to a whole man")
	t.eq(Body.price_of("elixir:all", {}, 1), Body.elixir_price(1), "priced the same at the physician as anywhere")
	for st in [1, 10, 30, 60]:
		var pay := Body.bout_pay(st)
		var pr := Body.elixir_price(st)
		t.check(pr >= pay and pr <= maxi(Body.ELIXIR_MIN, pay * 2), "stage %d: the elixir (%d) costs a bout or two's pay (%d each)" % [st, pr, pay])

## Badly hurt, one button sees to everything the physician's hands can (user: piles of things to
## buy), for less than the lot one at a time.
func test_one_treatment_sees_to_everything() -> void:
	var b := Body.sanitize({"fractures": {"forearmL": 3, "shinR": 2, "ribs": 2}, "fresh": {"torso": [1, 2, 3, 4, 5]}, "scars": {"torso": [1, 2, 3, 4, 5]}})
	var offers := Body.offers(b, 6)
	var all := offers.filter(func(o): return String(o.id) == "heal:all")
	t.eq(all.size(), 1, "one treatment for the lot")
	var sum := 0
	for o in offers:
		if String(o.id).begins_with("set:") or String(o.id).begins_with("stitch:"):
			sum += int(o.price)
	t.check(int(all[0].price) < sum and int(all[0].price) > 0, "cheaper than one at a time (%d against %d)" % [int(all[0].price), sum])
	t.eq(Body.price_of("heal:all", b, 6), int(all[0].price), "priced the same asked again")
	var healed := Body.apply(b, "heal:all")
	t.check((healed.fractures as Dictionary).is_empty() and (healed.fresh as Dictionary).is_empty(), "every bone set and every wound stitched")
	t.check(not (healed.scars as Dictionary).has("torso"), "the stitched wounds leave no scar")
	t.check(not Body.offers(Body.sanitize({"fractures": {"shinR": 1}}), 6).any(func(o): return String(o.id) == "heal:all"), "not offered for a single thing")

## Drunk in the yard, the Elixir gives the hand back there and then, with the weapon in it (he
## was healed and walked on armless, empty-handed, until the next bout: user).
func test_the_elixir_in_the_yard_gives_the_hand_back_at_once() -> void:
	var body0 = Save.get_value("body", {})
	Save.set_value("body", Body.sanitize({"missing": ["forearmR"]}))
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.enter_yard()
	for i in 10:
		await get_tree().physics_frame
	var f: Fighter = menu.match_.me.f
	t.check(f.arm.R.fore.missing and f.weapons.R == null, "he walks in without his right hand, and holds nothing in it")
	menu.set_body(Body.apply(menu.body(), "elixir:all"))
	for i in 10:
		await get_tree().physics_frame
	var g: Fighter = menu.match_.me.f
	t.check(not g.arm.R.fore.missing, "the hand is back on him in the yard")
	t.check(g.weapons.R != null, "and his weapon in it")
	menu._end_match()
	menu.queue_free()
	Save.set_value("body", body0 if body0 is Dictionary else {})
	await get_tree().process_frame

## A bone the physician sets in the yard is whole on him there and then (user: whatever he bought
## at the physician's, the broken arm stayed broken).
func test_a_bone_set_in_the_yard_is_whole_at_once() -> void:
	var body0 = Save.get_value("body", {})
	Save.set_value("body", Body.sanitize({"fractures": {"forearmL": 2, "shinR": 3}}))
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.enter_yard()
	for i in 10:
		await get_tree().physics_frame
	var f: Fighter = menu.match_.me.f
	t.check(f.by_name.forearmL.fractured and f.by_name.shinR.fracture == 3, "he walks in with the forearm broken and the shin broken open")
	var arm0 := f.arm_func("L")
	menu.set_body(Body.apply(menu.body(), "set:forearmL"))
	for i in 10:
		await get_tree().physics_frame
	var g: Fighter = menu.match_.me.f
	t.check(g.by_name.forearmL.fracture == 0 and not g.by_name.forearmL.fractured, "the forearm set: whole on him at once")
	t.check(g.arm_func("L") > arm0 + 0.5, "and the arm works again (%.2f, was %.2f)" % [g.arm_func("L"), arm0])
	t.check(g.by_name.shinR.fracture == 3, "the shin not yet set")
	menu.set_body(Body.apply(menu.body(), "set:shinR"))
	for i in 10:
		await get_tree().physics_frame
	var h: Fighter = menu.match_.me.f
	t.check(h.by_name.shinR.fracture == 0 and h.by_name.shinR.bo_pos.is_empty(), "the open break set: the bone back in")
	t.check(h.leg_func("R") > 0.9, "and the leg bears him (%.2f)" % h.leg_func("R"))
	t.check((menu.body().fractures as Dictionary).is_empty(), "nothing left broken in his save")
	menu._end_match()
	menu.queue_free()
	Save.set_value("body", body0 if body0 is Dictionary else {})
	await get_tree().process_frame

## A weapon that fell to the sand with the arm cut off holding it comes back from the bout with
## the chips it had, not "lost" down to its grip.
func test_a_weapon_that_fell_with_its_arm_is_not_lost() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "gladius"}})
	var f: Fighter = m.me.f
	for i in 20:
		await get_tree().physics_frame
	t.check(f.weapons.R != null, "a sword in his right hand")
	var fore: VoxelPart = f.arm.R.fore
	var all := PackedInt32Array()
	for i in fore.fx.size():
		if fore.alive[i]:
			all.append(i)
	f.sever(fore, {"severed": []}, all)
	for i in 5:
		await get_tree().physics_frame
	t.check(f.weapons.R == null and f.fell_with_arm.has("R"), "the sword fell with the arm")
	var w := m.my_wear()
	t.check(w.get("R") is Array, "the sword is picked up off the sand, chips and all (%s)" % [w.get("R")])
	m.queue_free()

## A bout won is won (user: came back to the yard badly hurt and bled to death there). The old
## wounds built back into him tear nothing open, over the heart and the liver too: no bleeding,
## no torn heart counting down, the organs healed. And in the yard nothing bleeds at all, a cut
## artery, an open cut and a fresh stump included.
func test_nobody_bleeds_to_death_in_the_yard() -> void:
	var m := _match()
	var f: Fighter = m.me.f
	await _steps(30)
	var tor: VoxelPart = f.torso
	var cap := int(tor.fx.size() * 0.2)
	var hole := []
	for o in [Anatomy.HEART, Anatomy.LIVER, Anatomy.LUNG_L]:
		for i in tor.fx.size():
			if tor.organ[i] == o and hole.size() < cap:
				hole.append(i)
	tor.remove_voxels(hole)
	var r := Body.merge(Body.empty(), Body.snapshot(f))
	t.check(r.body.scars.has("torso") and (r.body.scars.torso as Array).size() >= hole.size() - 1, "the hole through the heart and the liver is kept as a scar (%d voxels)" % hole.size())
	# Built into a man for the next bout: the scar is old, nothing in him is torn now.
	var e2 = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(3, 0, 0), "yaw": 0.0, "body": r.body})
	e2.erase("bot")
	e2.drive = func(_e): return {}
	var g: Fighter = e2.f
	await _steps(10)
	t.check(g.torso.fx.size() - g.torso.alive_count >= hole.size() - 1, "the dent is there")
	t.check(g.torso.bleed == 0.0 and g.heart_t < 0.0 and g.organ_lost.is_empty(), "and it tears nothing open: bleed %.2f, heart %.2f, organs lost %s" % [g.torso.bleed, g.heart_t, str(g.organ_lost)])
	var b0 := g.blood
	await _steps(240)
	t.check(g.alive and g.blood >= b0 - 0.5, "he does not bleed from it (blood %.1f -> %.1f)" % [b0, g.blood])
	m.queue_free()
	await _steps(2)
	# The yard, with that body: and a fresh cut there, an artery, an open wound and a stump.
	var y := Match.new()
	add_child(y)
	y.setup({"mode": "yard", "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "body": r.body})
	await _steps(10)
	var h: Fighter = y.me.f
	t.check(h.torso.bleed == 0.0 and h.heart_t < 0.0, "in the yard the old wound is shut (bleed %.2f)" % h.torso.bleed)
	h.by_name.thighR.artery = 3.0
	h.by_name.thighR.bleed = 4.0
	h.torso.bleed = 5.0
	h.by_name.forearmL.stump = true
	h.by_name.forearmL.stump_t = 0.0
	var b1 := h.blood
	await _steps(5 * 120)
	t.check(is_instance_valid(h) and h.alive and h.blood >= b1 - 1.0, "nothing bleeds in the yard: blood %.1f -> %.1f" % [b1, h.blood if is_instance_valid(h) else 0.0])
	t.check(is_instance_valid(h) and h.by_name.thighR.artery == 0.0 and h.torso.bleed == 0.0, "the artery and the cut are staunched")
	y.queue_free()
	await _steps(2)

## The blade arm a physician fitted is that arm's weapon in the next bout, whole: the chips of the
## sword that hand used to hold are not laid on it (by index they tore out its grip: user, no
## control of the arm with the prosthesis); it swings where the mouse sends it; and a hook takes
## up nothing it is handed (bought at the smith, a sword went into the hook).
func test_a_fitted_prosthetic_arm_works_in_the_next_bout() -> void:
	var m := _match()
	await _steps(5)
	var e2 = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(3, 0, 0), "yaw": 0.0, "worn": {"R": range(0, 30), "L": []}, "body": {"prosthetics": {"forearmR": "blade"}}})
	e2.erase("bot")
	var g: Fighter = e2.f
	var st := {"x": 0.1, "y": 0.15}
	e2.drive = func(_e): return {"main": {"x": st.x, "y": st.y}, "off": {"x": -0.35, "y": 0.1}, "power": true, "look": {"yaw": g.yaw, "pitch": 0.0}}
	await _steps(60)
	var w = g.weapons.R
	t.check(w != null and is_instance_valid(w) and g.fixed_hand.R, "the blade arm in the right hand")
	if w != null and is_instance_valid(w):
		t.eq((w as Weapon).alive_count(), (w as Weapon).vox.size(), "whole: the sword's chips are not laid on it")
	st.x = -1.2
	await _steps(100)
	var at_l: Vector3 = g.torso.global_transform.affine_inverse() * g.hand_world("R")
	st.x = 1.2
	await _steps(100)
	var at_r: Vector3 = g.torso.global_transform.affine_inverse() * g.hand_world("R")
	t.check(at_l.distance_to(at_r) > 0.25, "it swings where the mouse sends it (%.2f m from one side to the other)" % at_l.distance_to(at_r))
	var e3 = m.spawn_fighter({"kind": "bot", "name": "H", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(-3, 0, 0), "yaw": 0.0, "body": {"prosthetics": {"forearmR": "hook"}}})
	e3.erase("bot")
	e3.drive = func(_e): return {}
	await _steps(10)
	var h: Fighter = e3.f
	t.check(h.weapons.R == null, "the hook holds nothing at the start of the bout")
	h.rearm("gladius", "roundShield")
	await _steps(5)
	t.check(h.weapons.R == null and h.weapons.L != null, "nor what the smith sells him: the shield goes to the good hand, the hook stays empty")
	m.queue_free()
	await _steps(2)

## Each prosthetic is whole from the stump to where the hand or the foot was (user: the blade arm
## had a hole in its middle, with nothing in it): a row of it at every height of the part, the
## end where the blade's grip sits or the foot met the sand included; and it is made of what it is
## made of (leather, iron, bronze, wood), not drawn as skin.
func test_every_prosthetic_is_whole_and_made_of_its_stuff() -> void:
	var m := _match()
	var b := Body.empty()
	b.missing = ["forearmR", "forearmL", "shinL"]
	b = Body.apply(Body.apply(Body.apply(b, "blade:forearmR"), "hook:forearmL"), "peg:shinL")
	var e = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(0, 0, 3), "yaw": 0.0, "body": b})
	e.erase("bot")
	e.drive = func(_e): return {}
	await _steps(5)
	var f: Fighter = e.f
	for n in ["forearmR", "shinL"]:
		var p: VoxelPart = f.by_name[n]
		var rows := {}
		var stuff := true
		for i in p.fx.size():
			if p.alive[i]:
				rows[p.fy[i]] = true
				stuff = stuff and [1, 4, 5, 13].has(int(p.kinds[i]))
		var gaps := []
		for y in p.grid.y:
			if not rows.has(y):
				gaps.append(y)
		t.check(gaps.is_empty(), "%s (%s): no gap from the stump to the end (rows missing: %s)" % [n, p.prosthetic, str(gaps)])
		t.check(stuff, "%s: leather, iron, bronze and wood, not skin" % n)
	var hook: VoxelPart = f.by_name.forearmL
	var low := hook.grid.y
	for i in hook.fx.size():
		if hook.alive[i]:
			low = mini(low, hook.fy[i])
	t.eq(low, 0, "the hook reaches down to where the hand was")
	m.queue_free()
	await _steps(2)

## On a peg (either leg, or both) a man stands, walks (slower than on two feet, never stopped),
## turns full round without falling, gets up again after a fall and kicks (user: check the leg
## prostheses look right and work right).
func test_a_man_on_a_peg_walks_turns_rises_and_kicks() -> void:
	for pro in [{"shinL": "peg"}, {"shinR": "peg"}, {"shinL": "peg", "shinR": "peg"}]:
		var m := _match()
		m.me.f.teleport(Vector3(10, 0, 10))
		var e = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(0, 0, -4), "yaw": 0.0, "body": {"prosthetics": pro}})
		e.erase("bot")
		var f: Fighter = e.f
		var st := {"mz": 0.0, "yaw": 0.0, "kick": false}
		e.drive = func(_e): return {"mz": st.mz, "kick": st.kick, "look": {"yaw": st.yaw, "pitch": 0.0}}
		await _steps(240)
		t.eq(f.state, "stand", "%s: he stands" % str(pro.keys()))
		var p0: Vector3 = f.torso.global_position
		st.mz = 1.0
		await _steps(4 * 120)
		var walked := Vector2(f.torso.global_position.x - p0.x, f.torso.global_position.z - p0.z).length()
		t.check(walked > 4.5 and walked < 8.5, "%s: he walks, slower than on two feet (%.1f m in 4 s)" % [str(pro.keys()), walked])
		var fell := false
		for i in 4 * 120:
			st.yaw = TAU * float(i) / (4.0 * 120.0)
			await get_tree().physics_frame
			fell = fell or f.state != "stand"
		t.check(not fell, "%s: he turns full round walking and keeps his feet" % str(pro.keys()))
		st.mz = 0.0
		await _steps(60)
		f.fall(1.5, true)
		var up := -1.0
		for i in 8 * 120:
			await get_tree().physics_frame
			if f.state == "stand":
				up = float(i) / 120.0
				break
		t.check(up >= 0.0 and up < 6.0, "%s: felled, he is up again (%.1f s)" % [str(pro.keys()), up])
		await _steps(60)
		st.kick = true
		await get_tree().physics_frame
		st.kick = false
		var kicked := false
		for i in 60:
			await get_tree().physics_frame
			kicked = kicked or f.kick_timer > 0.0
		t.check(kicked, "%s: and he kicks" % str(pro.keys()))
		m.queue_free()
		await _steps(2)

## The smith works a prosthetic as he hones a blade (user: upgrade the prosthesis at the smith
## like a weapon): two steps, each dearer, never past the last; only on a prosthetic he has; lost
## with it (knocked off in a bout, the elixir), and a new one starts as the physician made it.
func test_the_smith_works_a_prosthetic_step_by_step() -> void:
	var b := Body.empty()
	b.missing = ["forearmR", "shinL"]
	b = Body.apply(Body.apply(b, "blade:forearmR"), "peg:shinL")
	var on: Array = Body.smith_prosthetics(b).keys()
	on.sort()
	t.eq(", ".join(on), "forearmR, shinL", "both on the smith's counter")
	t.eq(Body.pro_level(b, "forearmR"), 0, "as the physician made it")
	var p0 := Body.pro_step_price("blade", 0)
	var p1 := Body.pro_step_price("blade", 1)
	t.check(p0 > 0 and p1 > p0, "each step dearer (%d, then %d)" % [p0, p1])
	t.check(Body.pro_step_price("peg", 0) < p0, "a peg is cheaper to work than a blade arm (%d)" % Body.pro_step_price("peg", 0))
	var r := Body.upgrade_prosthetic(b, "forearmR")
	t.eq(int(r.get("cost", -1)), p0, "the first step at its price")
	t.eq(Body.pro_level(r.body, "forearmR"), 1, "refitted")
	t.eq(Body.pro_level(r.body, "shinL"), 0, "the peg not touched")
	var r2 := Body.upgrade_prosthetic(r.body, "forearmR")
	t.eq(int(r2.get("cost", -1)), p1, "the second step at its price")
	t.eq(Body.pro_level(r2.body, "forearmR"), 2, "a master's work")
	t.check(Body.upgrade_prosthetic(r2.body, "forearmR").has("error"), "nothing finer can be made")
	t.check(Body.upgrade_prosthetic(r2.body, "shinR").has("error"), "no prosthetic, nothing to work on")
	for lv in 3:
		t.check(Body.pro_fn("peg", lv) > Body.pro_fn("peg", lv - 1) if lv > 0 else is_equal_approx(Body.pro_fn("peg", 0), Body.PROSTHETIC_FN.peg), "a peg works better at each step (%.2f)" % Body.pro_fn("peg", lv))
		t.check(Body.pro_fn("hook", lv) < 1.0, "never as well as a hand of his own (%.2f)" % Body.pro_fn("hook", lv))
	# What comes off a save or the wire: only steps on a prosthetic he has, none past the last.
	var s := Body.sanitize({"prosthetics": {"forearmR": "blade"}, "pro_up": {"forearmR": 99, "shinL": 1, "forearmL": "x", "eyeL": 1, "thighR": -4}})
	t.eq(str(s.pro_up), str({"forearmR": 2}), "steps only on his blade arm, at most two")
	t.check((Body.sanitize({"prosthetics": {"forearmR": "blade"}, "pro_up": {"forearmR": -2}}).pro_up as Dictionary).is_empty(), "none below the physician's")
	t.check((Body.sanitize({"pro_up": "junk"}).pro_up as Dictionary).is_empty(), "nothing from junk")
	# Knocked off in a bout: the steps go with it; the new one is the physician's again.
	var lost: Dictionary = Body.merge(r2.body, {"lost": ["forearmR"]}).body
	t.check(not lost.prosthetics.has("forearmR") and not lost.pro_up.has("forearmR"), "the blade arm knocked off, and the smith's work with it")
	t.eq(Body.pro_level(Body.apply(lost, "hook:forearmR"), "forearmR"), 0, "a new hook in its place is the physician's")
	t.check((Body.apply(r2.body, "elixir:all").pro_up as Dictionary).is_empty(), "the elixir gives the arm back: no prosthetic left to have been worked")

## The smith's work tells in the bout and on the sight of it: a refitted blade arm is keener and
## steadier, a refitted peg bears more; the bands and rivets go bronze, then gilt and polished.
func test_a_refitted_prosthetic_works_better_and_shows_it() -> void:
	var m := _match()
	await _steps(5)
	var fs := []
	for lv in 3:
		var e = m.spawn_fighter({"kind": "bot", "name": "P%d" % lv, "loadout": {"main": "gladius", "off": ""}, "team": 0, "pos": Vector3(3.0 * lv - 3.0, 0, 3), "yaw": 0.0, "body": {"prosthetics": {"forearmR": "blade", "shinL": "peg"}, "pro_up": {"forearmR": lv, "shinL": lv}}})
		e.erase("bot")
		e.drive = func(_e): return {"main": {"x": 0.3, "y": 0.2}}
		fs.append(e.f)
	await _steps(60)
	var bronze := []
	for lv in 3:
		var f: Fighter = fs[lv]
		var fore: VoxelPart = f.by_name.forearmR
		t.eq(fore.pro_level, lv, "level %d: fitted as the smith left it" % lv)
		t.check(is_equal_approx(fore.function(), Body.pro_fn("blade", lv)), "level %d: the blade arm works %.2f (%.2f)" % [lv, fore.function(), Body.pro_fn("blade", lv)])
		t.check(is_equal_approx(f.by_name.shinL.function(), Body.pro_fn("peg", lv)), "level %d: the peg bears %.2f" % [lv, f.by_name.shinL.function()])
		var w = f.weapons.R
		t.check(w != null and is_instance_valid(w) and is_equal_approx(float(w.design.sharpness), minf(1.0, 0.85 + 0.05 * lv)), "level %d: the blade's edge %.2f" % [lv, float(w.design.sharpness) if w else -1.0])
		var n4 := 0
		var gilt := 0
		for i in fore.fx.size():
			if fore.alive[i] and fore.kinds[i] == 4:
				n4 += 1
				if fore.colors[i].is_equal_approx(Fighter.PRO_GILT):
					gilt += 1
		bronze.append([n4, gilt])
	t.check(fs[1].handling.R > fs[0].handling.R * 1.1 and fs[2].handling.R > fs[1].handling.R * 1.1, "steadier at each step (handling %.2f, %.2f, %.2f)" % [fs[0].handling.R, fs[1].handling.R, fs[2].handling.R])
	t.check(bronze[1][0] > bronze[0][0], "refitted: more bronze on it (%d, was %d)" % [bronze[1][0], bronze[0][0]])
	t.check(bronze[0][1] == 0 and bronze[1][1] == 0 and bronze[2][1] >= bronze[1][0], "a master's work: its fittings gilt (%d)" % bronze[2][1])
	m.queue_free()
	await _steps(2)

## At the smith's counter in the yard: his prosthetic with the next step and its price; paid,
## the purse is lighter and the man in the yard has the refitted one on him at once.
func test_the_smith_refits_a_prosthetic_in_the_yard() -> void:
	var body0 = Save.get_value("body", {})
	var coins0 = Save.get_value("coins", null)
	Save.set_value("body", Body.sanitize({"missing": ["forearmR"], "prosthetics": {"forearmR": "blade"}}))
	Save.set_value("coins", 500)
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.enter_yard()
	for i in 10:
		await get_tree().physics_frame
	t.eq(menu.match_.me.f.arm.R.fore.pro_level, 0, "he walks in with the physician's blade arm")
	var price := Body.pro_step_price("blade", 0)
	menu.smith_tab = "weapons"
	menu.show_screen("yard")
	await get_tree().process_frame
	var step: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if String(b.text).begins_with(Loc.t("Refit and rivet")):
			step = b
	t.check(step != null and not step.disabled and String(step.text).contains(str(price)), "the smith offers the first step at its price (%s)" % (step.text if step else "none"))
	if step:
		step.pressed.emit()
	for i in 10:
		await get_tree().physics_frame
	t.eq(menu.coins(), 500 - price, "paid for")
	t.eq(Body.pro_level(menu.body(), "forearmR"), 1, "kept in his save")
	t.eq(menu.match_.me.f.arm.R.fore.pro_level, 1, "and on him in the yard at once")
	t.check(menu.match_.me.f.weapons.R != null and menu.match_.me.f.fixed_hand.R, "the blade still his right arm")
	menu.set_body(Body.upgrade_prosthetic(menu.body(), "forearmR").body)
	menu.show_screen("yard")
	await get_tree().process_frame
	var last: Array = menu.find_children("*", "Button", true, false).filter(func(b): return String(b.text) == Loc.t("Nothing finer can be made"))
	t.check(last.size() == 1 and last[0].disabled, "a master's work: nothing more offered")
	var start: int = menu.START_COINS
	menu._end_match()
	menu.queue_free()
	Save.set_value("body", body0 if body0 is Dictionary else {})
	Save.set_value("coins", coins0 if coins0 != null else start)
	await get_tree().process_frame

## A limb cut off passes through the man it came off for as long as it lies in him, however long
## that is, and is solid to him only once clear of him. (Made solid after a few seconds whether
## clear or not, a dummy's leg lying in the leg he stood on was thrown out by the solver, and again
## each time his foot came down on it: it jumped about the arena on its own, user.)
func test_a_severed_leg_inside_him_is_not_thrown_out() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var e = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	var f: Fighter = e.f
	await _steps(60)
	var leg: VoxelPart = f.by_name.shinL
	var stand: VoxelPart = f.by_name.shinR
	f.detach_limb(leg, {"removed": [], "severed": []})
	# Laid along the shin he stands on, inside it, for nine seconds (past the twenty checks after
	# which a piece used to be made solid to him whether clear of him or not).
	for i in 120 * 9:
		f.blood = 100.0
		leg.global_transform = stand.global_transform
		leg.linear_velocity = Vector3.ZERO
		leg.angular_velocity = Vector3.ZERO
		await get_tree().physics_frame
	t.check(leg.get_collision_exceptions().has(stand), "nine seconds inside the leg he stands on, the cut-off shin still passes through it")
	var fastest := 0.0
	var p0 := leg.global_position
	for i in 120 * 3:
		f.blood = 100.0
		await get_tree().physics_frame
		fastest = maxf(fastest, leg.linear_velocity.length())
	t.check(fastest < 3.0, "let go, it is not thrown out of him (fastest %.2f m/s, moved %.2f m)" % [fastest, leg.global_position.distance_to(p0)])
	m.queue_free()
