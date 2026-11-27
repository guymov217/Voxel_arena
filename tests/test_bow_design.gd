extends Node
## A bow is what its blocks make it (user: the forge's bow was only for looks): the thicker and stiffer its limbs the harder it is drawn and the faster and harder its arrow, the longer it is the
## more it stores and the steadier it holds, and the smith's Hunting Bow is the measure of it all (BowDesign), so the bow he sells shoots as it always did.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	m.me.f.state = "dead"
	return m

func _man(m: Match, pos: Vector3, yaw: float, lo: Dictionary, name_: String, team: int, drive: Callable) -> Dictionary:
	var e = m.spawn_fighter({"kind": "bot", "name": name_, "loadout": lo, "team": team, "pos": pos, "yaw": yaw})
	e.erase("bot")
	e.drive = drive
	return e

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## A bow of the forge's simple kind: `blade` the length of each limb (7 to 14: the Hunting Bow's is 8), `width` 2 or more a second layer of `mat`, `limb` the stuff of the first.
func _bow(blade: int, width := 1, mat := "wood", limb := "wood") -> Dictionary:
	return ForgeLib.simple_weapon({"shape": "bow", "blade": blade, "width": width, "mat": mat, "handleMat": limb, "name": "Test bow"})

## An archer with that bow draws it to the full and looses: how long the draw took (s), the arrow's speed (m/s) and the harm it carries (`power`) as it leaves.
func _shoot(design: Dictionary) -> Dictionary:
	var m := _match()
	var phase := [0]
	var a := _man(m, Vector3(0, 0, -5), 0.0, {"main": "bow"}, "Archer", 0, func(_e):
		return {"main": {"x": 0.3, "y": 0.45}, "power": phase[0] == 1, "look": {"yaw": 0.0, "pitch": 0.0}})
	a.is_archer = true
	a.kind = "local"
	await _steps(30)
	if not design.is_empty():
		a.f.equip("R", design)
	await _steps(30)
	var w: Weapon = a.f.weapons.R
	phase[0] = 1
	var frames := 0
	for i in 900:
		await get_tree().physics_frame
		frames += 1
		if float(w.get_meta("draw", 0.0)) >= 1.0:
			break
	var breath := float(a.f.stamina)
	phase[0] = 2
	await _steps(3)
	var out := {"draw_s": float(frames) / 120.0, "speed": 0.0, "power": -1.0, "breath": breath, "loosed": false}
	for it in m.items.list:
		if String(it.type).begins_with("pot_arrow"):
			out.speed = (it.vel as Vector3).length()
			out.power = float(it.get("power", -1.0))
			out.loosed = true
	m.queue_free()
	await _steps(2)
	return out

func test_the_smiths_hunting_bow_is_the_measure_of_every_bow() -> void:
	var b := BowDesign.stats(Data.preset("bow"))
	t.check(b.weight == 1.0 and b.length == 1.0 and b.speed_k == 1.0 and b.power_k == 1.0 and b.steady == 1.0 and b.breath == 1.0, "1.0 in all of it: %s" % str(b))
	t.check(is_equal_approx(float(b.draw_s), 1.6), "and a draw of 1.6 s as it was (%.3f)" % float(b.draw_s))
	t.check(BowDesign.is_bow(Data.preset("bow")) and not BowDesign.is_bow(Data.preset("gladius")) and not BowDesign.is_bow(Data.preset("crossbow")), "a bow is what shoots arrows")

func test_thicker_stiffer_and_longer_bows_are_stronger_and_slower_to_draw() -> void:
	var plain := BowDesign.stats(_bow(8))
	var thick := BowDesign.stats(_bow(8, 2))
	var steel := BowDesign.stats(_bow(8, 1, "steel", "steel"))
	var gold := BowDesign.stats(_bow(8, 1, "gold", "gold"))
	var long_ := BowDesign.stats(_bow(14))
	var short_ := BowDesign.stats(_bow(7))
	t.check(absf(float(plain.weight) - 1.0) < 0.05 and absf(float(plain.length) - 1.0) < 0.05, "a simple bow of the Hunting Bow's height is its weight (%.2f, %.2f)" % [plain.weight, plain.length])
	t.check(thick.weight > plain.weight * 1.8 and thick.speed_k > plain.speed_k * 1.15 and thick.power_k > plain.power_k * 1.3, "a second layer on the limbs: heavier to draw (%.2f), a faster arrow (%.2f), a harder one (%.2f)" % [thick.weight, thick.speed_k, thick.power_k])
	t.check(thick.draw_s > plain.draw_s * 1.3 and thick.breath > plain.breath * 1.8 and thick.steady < plain.steady, "and slower (%.2f s against %.2f), more tiring (%.2f) and less steady (%.2f against %.2f)" % [thick.draw_s, plain.draw_s, thick.breath, thick.steady, plain.steady])
	t.check(steel.weight > plain.weight * 1.25 and steel.speed_k > plain.speed_k and steel.draw_s > plain.draw_s, "steel limbs are stiffer (%.2f)" % steel.weight)
	t.check(gold.weight < plain.weight * 0.6 and gold.speed_k < plain.speed_k and gold.power_k < plain.power_k * 0.8 and gold.draw_s < plain.draw_s, "gold limbs hardly spring (%.2f): a quick draw and a poor arrow (%.2f)" % [gold.weight, gold.power_k])
	t.check(long_.length > 1.4 and long_.power_k > plain.power_k * 1.2 and long_.speed_k > plain.speed_k * 1.05 and long_.draw_s > plain.draw_s * 1.2 and long_.steady > plain.steady * 1.05, "a long bow stores more, takes longer to draw and holds steadier (%.2f s, %.2f)" % [long_.draw_s, long_.steady])
	t.check(short_.length < 0.95 and short_.power_k < plain.power_k * 0.96 and short_.speed_k < plain.speed_k and short_.draw_s < plain.draw_s * 0.97, "a short bow draws fast and hits softer (%.2f s, %.2f)" % [short_.draw_s, short_.power_k])
	# (Bounds: no number of blocks makes an absurd bow.)
	var huge := BowDesign.stats(_bow(34, 2, "steel", "steel"))
	var nothing := BowDesign.stats({"shoots": "arrow", "voxels": [[0, 0, 0, "leather", "grip"]]})
	t.check(huge.speed_k <= 1.35 and huge.power_k <= 1.6 and huge.draw_s <= 6.0 and huge.steady <= 1.3, "bounded above (%.2f, %.2f, %.1f s)" % [huge.speed_k, huge.power_k, huge.draw_s])
	t.check(nothing.speed_k >= 0.7 and nothing.power_k >= 0.5 and nothing.draw_s >= 0.5 and nothing.weight >= BowDesign.W_MIN, "and below (a grip and nothing else)")

func test_the_forge_shows_a_bow_by_what_it_shoots() -> void:
	var hunting: Dictionary = Data.preset("bow")
	var st := ForgeLib.compute_stats(hunting)
	t.check(st.has("bow") and not ForgeLib.compute_stats(Data.preset("gladius")).has("bow"), "a bow's stats carry its own")
	var bars := ForgeLib.three_bars(st)
	t.check(bars.speed > 0.7 and bars.speed < 0.9 and absf(float(bars.damage) - 0.625) < 0.01, "the Hunting Bow on the bars: draw %.2f, arrow %.2f" % [bars.speed, bars.damage])
	var rows := ForgeLib.bar_rows(hunting)
	t.check(rows[0][1] == "Draw speed" and rows[1][1] == "Arrow power" and rows[2][1] == "Arrow speed" and rows[3][1] == "Steadiness" and rows[4][1] == "Durability", "named for the bow: %s" % str(rows.map(func(r): return r[1])))
	t.check(ForgeLib.bar_rows(Data.preset("gladius"))[0][1] == "Speed", "a sword's as ever")
	var heavy := ForgeLib.three_bars(ForgeLib.compute_stats(_bow(8, 2)))
	var light := ForgeLib.three_bars(ForgeLib.compute_stats(_bow(7)))
	t.check(heavy.damage > bars.damage and heavy.speed < bars.speed and light.speed > bars.speed and light.damage < bars.damage, "heavier: a harder arrow, a slower draw (%.2f, %.2f); lighter the other way (%.2f, %.2f)" % [heavy.damage, heavy.speed, light.damage, light.speed])
	var fig := ForgeLib.bar_figures(hunting, st, bars)
	t.check(fig.speed > 0.6 and fig.speed < 0.65 and fig.damage == 1.0, "the figures a change is counted on are the bow's (%s)" % str(fig))
	var verdict := ForgeLib.dummy_verdict(hunting, st)
	t.check(verdict.contains("1.6 s") and verdict.contains("58 m/s") and verdict.contains("100%"), "the dummy says how it draws and shoots: %s" % verdict)
	var list := ForgeLib.checklist(hunting, st)
	t.check(list.size() == 2 and list[0].done and list[1].done, "a bow with limbs above and below the grip is done (%s)" % str(list))
	var stick := {"name": "Stick", "kind": "weapon", "shoots": "arrow", "sharpness": 0.0, "voxels": [[0, 0, 0, "leather", "grip"], [0, 1, 0, "leather", "grip"], [0, 2, 0, "wood", "blunt"], [0, 3, 0, "wood", "blunt"]]}
	var open := ForgeLib.checklist(stick, ForgeLib.compute_stats(stick))
	t.check(open[0].done and not open[1].done, "and one with limbs on one side only is not (%s)" % str(open))

## The drawing, the breath, the arrow's speed and the harm it carries come from the bow's own blocks.
func test_what_the_bow_is_decides_the_draw_and_the_arrow() -> void:
	var plain := await _shoot({})
	var thick := await _shoot(_bow(8, 2))
	var short_ := await _shoot(_bow(7))
	var long_ := await _shoot(_bow(14))
	t.check(plain.loosed and thick.loosed and short_.loosed and long_.loosed, "every bow looses an arrow")
	t.check(plain.draw_s > 1.5 and plain.draw_s < 1.75 and plain.speed > 50.0 and plain.speed < 60.0 and absf(float(plain.power) - 1.0) < 0.01, "the Hunting Bow as it was: %.2f s to draw, %.1f m/s, a harm of %.2f" % [plain.draw_s, plain.speed, plain.power])
	t.check(thick.draw_s > plain.draw_s * 1.25, "a second layer of wood draws slower: %.2f s against %.2f" % [thick.draw_s, plain.draw_s])
	t.check(thick.speed > plain.speed * 1.12 and thick.speed < plain.speed * 1.3, "and looses a faster arrow: %.1f m/s against %.1f" % [thick.speed, plain.speed])
	t.check(thick.power > plain.power * 1.4, "that strikes harder (a harm of %.2f against %.2f)" % [thick.power, plain.power])
	t.check(short_.draw_s < plain.draw_s * 0.97 and short_.speed < plain.speed * 0.99 and short_.power < plain.power * 0.96, "a short bow: %.2f s, %.1f m/s, a harm of %.2f" % [short_.draw_s, short_.speed, short_.power])
	t.check(long_.draw_s > plain.draw_s * 1.2 and long_.speed > plain.speed * 1.05 and long_.power > plain.power * 1.2, "a long one: %.2f s, %.1f m/s, a harm of %.2f" % [long_.draw_s, long_.speed, long_.power])
	t.check(thick.breath < plain.breath, "and the stiff bow's full draw held tires him more (%.0f breath left against %.0f)" % [thick.breath, plain.breath])

## A harder arrow is a harder blow: the harm it carries is the draw times the bow's.
func test_a_stronger_bows_arrow_strikes_harder() -> void:
	var m := _match()
	var v1: Fighter = _man(m, Vector3(-4, 0, 0), PI, {}, "V1", 1, func(_e): return {}).f
	var v2: Fighter = _man(m, Vector3(4, 0, 0), PI, {}, "V2", 1, func(_e): return {}).f
	var shooter: Fighter = _man(m, Vector3(0, 0, -9), 0.0, {}, "S", 0, func(_e): return {}).f
	await _steps(40)
	var js := {}
	m.combat.hit.connect(func(h):
		if h.get("char") != null and String(h.get("type", "")) == "point":
			js[h.char] = float(h.J))
	var front := func(f: Fighter) -> Vector3: return f.torso.global_position + f.torso.global_basis * Vector3(0, 0, f.torso.half_ext.z)
	m.throwables._dart("pot_arrow", front.call(v1), shooter, Vector3(0, 0, 1), v1, v1.torso, 1.0)
	m.throwables._dart("pot_arrow", front.call(v2), shooter, Vector3(0, 0, 1), v2, v2.torso, 1.6)
	t.check(js.has(v1) and js.has(v2), "both arrows landed")
	if js.has(v1) and js.has(v2):
		var k: float = float(js[v2]) / maxf(0.01, float(js[v1]))
		t.check(absf(k - (3.0 + 13.0 * 1.6) / 16.0) < 0.03, "a harm of 1.6 lands %.2f times as hard (%.3f)" % [k, (3.0 + 13.0 * 1.6) / 16.0])
	m.queue_free()

## A limb chipped off a bow in a fight weakens it: what it is is worked out anew when a block comes off, and the same answer is given while none does.
func test_a_chipped_bow_is_worked_out_anew() -> void:
	var m := _match()
	var a := _man(m, Vector3(0, 0, -5), 0.0, {"main": "bow"}, "Archer", 0, func(_e): return {})
	await _steps(30)
	var w: Weapon = a.f.weapons.R
	var s1: Dictionary = m.throwables._bow_stats(w)
	t.check(is_same(m.throwables._bow_stats(w), s1), "the same answer again while no block comes off")
	var top := -1
	for v in w.design.voxels:
		top = maxi(top, int(v[1]))
	var kept: Array = (w.design.voxels as Array).filter(func(v): return int(v[1]) < top - 6 and int(v[1]) > 0)
	w.design.voxels = kept
	var s2: Dictionary = m.throwables._bow_stats(w)
	t.check(s2.span < s1.span and s2.draw_s < s1.draw_s and s2.power_k < s1.power_k, "a shorter stave is worked out anew (span %s against %s)" % [s2.span, s1.span])
	m.queue_free()
