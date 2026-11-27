extends Node
## Head and brain damage change how a man works (user: make sure head and brain damage affect his functions; the brain bigger and clearer): a brain torn or bruised leaves a ringing that does not clear, any ringing
## slows him and weakens his arms, a bot with a ringing head sees a blow late and does less about it, a bound wound does not mend the brain, and the brain is one to look at when a head is opened.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _victim() -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -8))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	return [m, e.f]

## The voxels of the brain still there, a share of them (nearest the front first).
func _brain(v: Fighter, share: float) -> Array:
	var out := []
	for i in v.head.organ.size():
		if v.head.organ[i] == Anatomy.BRAIN and v.head.alive[i]:
			out.append(i)
	out.sort_custom(func(a, b): return v.head.fz[a] > v.head.fz[b])
	return out.slice(0, ceili(out.size() * share))

func test_a_torn_brain_leaves_a_ringing_that_does_not_clear() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(20)
	t.eq(v.brain_floor, 0.0, "a whole brain leaves nothing")
	v.concussion = 0.01
	await _steps(40)
	t.eq(v.concussion, 0.0, "and a knock's ringing clears with the seconds (%.3f)" % v.concussion)
	v.head.remove_voxels(_brain(v, 0.25))
	await _steps(20)
	t.check(absf(v.brain_floor - 0.25 / Fighter.BRAIN_DEATH * Fighter.BRAIN_FLOOR) < 0.01, "a quarter of it torn: a floor of its share of what kills (%.3f)" % v.brain_floor)
	t.check(v.alive and v.concussion >= v.brain_floor - 0.001, "he lives, rung at least that much (%.3f)" % v.concussion)
	# Whatever clears, this does not: the ringing set to nothing comes back to the floor at the next step.
	v.concussion = 0.0
	await _steps(3)
	t.check(v.concussion >= v.brain_floor - 0.001 and v.concussion > 0.2, "cleared by hand, it is back at the floor (%.3f)" % v.concussion)
	m.queue_free()
	await get_tree().process_frame

func test_the_floor_grows_with_the_brain_lost_or_bruised_and_stays_under_the_edge_of_death() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(10)
	var nb: int = v.organ_total.get(Anatomy.BRAIN, 0)
	t.check(nb >= 100, "a man has a brain (%d voxels)" % nb)
	v.organ_lost[Anatomy.BRAIN] = int(nb * 0.35)
	v._brain_changed()
	var half := v.brain_floor
	t.check(absf(half - 0.5 * Fighter.BRAIN_FLOOR) < 0.01, "half the way to death, half the floor (%.3f)" % half)
	v.organ_lost[Anatomy.BRAIN] = int(nb * 0.69)
	v._brain_changed()
	t.check(v.brain_floor > half and v.brain_floor < Fighter.BRAIN_FLOOR + 0.001 and v.brain_floor < 0.85, "nearer death, a bigger floor, and one that does not fell him by itself (%.3f)" % v.brain_floor)
	v.organ_lost[Anatomy.BRAIN] = 0
	v.organ_bruise[Anatomy.BRAIN] = 0.35
	v._brain_changed()
	t.check(absf(v.brain_floor - half) < 0.01, "a brain bruised as much as the other was torn leaves as much (%.3f)" % v.brain_floor)
	m.queue_free()
	await get_tree().process_frame

func test_a_ringing_head_is_slower_and_weaker() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(20)
	v.concussion = 0.0
	await _steps(2)
	var quick := v.pace_now
	v.concussion = 0.8
	await _steps(2)
	var slow := v.pace_now
	t.check(quick > 0.9, "a whole head walks at the full pace (%.3f)" % quick)
	t.check(absf(slow / quick - (1.0 - Fighter.CONC_SLOW * 0.8)) < 0.02, "a ringing one at %.0f%% of it (%.3f against %.3f)" % [100.0 * (1.0 - Fighter.CONC_SLOW * 0.8), slow, quick])
	t.eq(Fighter.ringing_weak(0.0), 1.0, "nothing takes nothing off the arms' strength")
	t.check(absf(Fighter.ringing_weak(0.8) - (1.0 - Fighter.CONC_WEAK * 0.8)) < 1e-6 and Fighter.ringing_weak(1.0) > 0.7, "a ringing head takes a share, never most of it (%.2f)" % Fighter.ringing_weak(1.0))
	m.queue_free()
	await get_tree().process_frame

func test_wine_is_as_it_was_and_slows_nobody() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(20)
	v.concussion = 0.0
	await _steps(2)
	var sober := v.pace_now
	v.mods.drunk = 0.3
	v.concussion = 0.3
	await _steps(2)
	t.check(is_equal_approx(v.pace_now, sober), "a little drunk, he walks as he did (%.3f, %.3f)" % [v.pace_now, sober])
	t.check(v.ringing() < 0.01, "and none of it is an injury (%.3f)" % v.ringing())
	v.concussion = 0.6
	await _steps(2)
	t.check(absf(v.ringing() - 0.3) < 0.01 and v.pace_now < sober * 0.95, "a knock to the head on top of the wine counts (%.3f, %.3f)" % [v.ringing(), v.pace_now])
	m.queue_free()
	await get_tree().process_frame

func test_a_bot_with_a_ringing_head_sees_the_blow_late_and_does_less_about_it() -> void:
	t.check(Bot.see_time(0.5, 0.8) > Bot.see_time(0.5, 0.0) + 0.2, "later: %.2f s against %.2f" % [Bot.see_time(0.5, 0.8), Bot.see_time(0.5, 0.0)])
	t.check(Bot.dodge_chance(0.5, 0.0, 0.8) < 0.7 * Bot.dodge_chance(0.5, 0.0, 0.0), "and a smaller chance to do anything about it")
	t.check(is_equal_approx(Bot.see_time(0.9, 0.0), 0.3 - 0.24 * 0.9) and is_equal_approx(Bot.dodge_chance(0.6, 0.3, 0.0), (0.06 + 0.84 * 0.6) * (1.0 - 0.6 * 0.3)), "a clear head is as it was")

func test_bound_wounds_do_not_mend_a_torn_brain() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(10)
	v.head.remove_voxels(_brain(v, 0.3))
	await _steps(10)
	var floor_was := v.brain_floor
	t.check(floor_was > 0.25, "a brain torn (%.3f)" % floor_was)
	v.bind_wounds()
	t.check(absf(v.concussion - floor_was) < 0.001, "bound up, his head clears of what a knock left, not of that (%.3f)" % v.concussion)
	m.queue_free()
	await get_tree().process_frame

func test_the_brain_is_one_to_look_at() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(5)
	var colours := {}
	var fissure := 0
	var lilac := 0
	for i in v.head.organ.size():
		if v.head.organ[i] != Anatomy.BRAIN:
			continue
		var c: Color = v.head.colors[i]
		colours[c.to_html(false)] = true
		if v.head.fx[i] == 4 and v.head.fy[i] >= 7:
			fissure += 1
		if v.head.fy[i] == 6 and v.head.fz[i] <= 3:
			lilac += 1
	t.check(colours.size() >= 5, "pink, its folds, a fissure and a cerebellum: %d colours" % colours.size())
	t.check(fissure >= 8, "a fissure down the middle between the halves (%d voxels)" % fissure)
	t.check(lilac >= 6, "a cerebellum low at the back (%d voxels)" % lilac)
	var man := Anatomy._brain_rgb(3, 8, 5, true)
	var beast := Anatomy._brain_rgb(4, 8, 5, false)
	t.check(man != Anatomy._brain_rgb(4, 8, 5, true), "a man's head has the fissure at its middle")
	t.check(beast != 0 and ((beast >> 16) & 0xff) > 150, "a beast's brain is pink too, with no fissure of a man's (%x)" % beast)
	m.queue_free()
	await get_tree().process_frame

func test_a_ringing_head_sees_double_and_blurred_and_a_clear_one_sees_as_ever() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 4, "decrees": [], "hazards": []})
	var hud := Hud.new(m)
	add_child(hud)
	for i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame
	var f: Fighter = m.me.f
	f.concussion = 0.0
	f.eye_hurt = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(hud.daze_fx != null and not hud.daze_fx.visible, "a clear head: the view as it is")
	t.eq(hud.daze_fx.get_index(), 0, "the effect lies under the rest of the HUD, over the view only")
	f.concussion = 0.7
	await get_tree().process_frame
	await get_tree().process_frame
	var amount: float = float((hud.daze_fx.material as ShaderMaterial).get_shader_parameter("amount"))
	t.check(hud.daze_fx.visible and amount > 0.6, "a ringing one: the view swims (%.2f)" % amount)
	t.check(hud.sight.modulate.a > 0.25, "and closes in at the edges (%.2f)" % hud.sight.modulate.a)
	f.concussion = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(not hud.daze_fx.visible, "cleared, the view is as it was")
	hud.queue_free()
	m.queue_free()

## A brain hurt in the campaign goes into the next bout and into the yard with him (Body.brain); in the yard he rings (he walks slower) but the view stays clear behind his
## menus: what a ringing head does to the view is for the fights, and the physician's table says it (a pin on his head).
func test_a_brain_hurt_in_the_campaign_rings_in_the_yard_but_the_view_stays_clear() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "roundShield"}, "body": Body.sanitize({"brain": 0.5})})
	var hud := Hud.new(m)
	add_child(hud)
	for i in 8:
		await get_tree().physics_frame
	await get_tree().process_frame
	var f: Fighter = m.me.f
	var want := 0.5 / Fighter.BRAIN_DEATH * Fighter.BRAIN_FLOOR
	t.check(absf(f.brain_floor - want) < 0.02 and f.ringing() > 0.45, "he stands in the yard with the ringing his hurt left (%.3f of %.3f)" % [f.brain_floor, want])
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(m.yard != null and hud.daze_fx != null and not hud.daze_fx.visible, "and the view behind his menus is clear")
	hud.queue_free()
	m.queue_free()
