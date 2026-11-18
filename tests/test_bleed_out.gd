extends Node
## Everyone can bleed to death (user: the lion boss never bled to death at all; make sure everyone
## can). The blood a body loses is the bleeding on it over its size, whoever it is: a man, a beast, a
## giant, a boss (Fighter.blood_lost). It used to go with the size squared (and a cut artery's flow was
## cut by the size as well, on top), so the Big Lion lost 4 blood in 160 s of a fight's cuts and a giant
## next to none, and neither could be bled out.

var t

## A body of size `s` (nothing built: the law needs only the size).
func _body(s: float) -> Fighter:
	var f := Fighter.new()
	f.S = s
	return f

func test_blood_goes_by_the_size_of_the_body() -> void:
	var man := _body(1.0)
	var flow := man.blood_lost(1.0, 1.0)
	t.check(is_equal_approx(flow, Fighter.BLEED_RATE), "a man loses BLEED_RATE of blood a second to each unit of bleeding (%.2f)" % flow)
	for s in [1.65, 2.2, 3.8, 4.12]:
		var b := _body(s)
		t.check(is_equal_approx(b.blood_lost(1.0, 1.0) * s, flow), "a body of %.2f loses it by its size (%.3f a second)" % [s, b.blood_lost(1.0, 1.0)])
		b.free()
	var slow := _body(1.0)
	slow.mods.bleed = 0.6
	t.check(is_equal_approx(slow.blood_lost(1.0, 1.0), flow * 0.6), "a player's slower bleeding (the mod) still counts")
	slow.free()
	man.free()

## What a torn organ runs out is by its share of the organ, not by the voxel: a lion's heart is 150
## voxels to a man's 27, and half of it torn ran out five times the blood a man's does, so the lion bled
## out in a second and a half, sooner than the man (whom a torn heart kills in three).
func test_a_torn_organ_bleeds_by_its_share_whatever_its_voxels() -> void:
	var man := _body(1.0)
	man.organ_total = {Anatomy.HEART: 27, Anatomy.LIVER: 90, Anatomy.STOMACH: 48, Anatomy.GUTS: 420, Anatomy.LUNG_R: 191, Anatomy.LUNG_L: 191}
	var lion := _body(1.65)
	lion.organ_total = {Anatomy.HEART: 150, Anatomy.LIVER: 444, Anatomy.GUTS: 724, Anatomy.LUNG_R: 360, Anatomy.LUNG_L: 360}
	var a := man._organ_bleed({Anatomy.HEART: 14, Anatomy.LIVER: 45, Anatomy.GUTS: 210, Anatomy.LUNG_R: 95})
	var b := lion._organ_bleed({Anatomy.HEART: 75, Anatomy.LIVER: 222, Anatomy.GUTS: 362, Anatomy.LUNG_R: 180})
	t.check(a > 30.0 and absf(b - a) < 0.06 * a, "half of each organ torn bleeds a lion as it does a man (%.1f, %.1f)" % [b, a])
	man.free()
	lion.free()

## No kind in the game is so big that a few of the deepest wounds one blow opens (BLEED_BLOW, 4 each:
## a dozen units of bleeding) do not bleed it dry inside a minute.
func test_no_kind_is_too_big_to_bleed_dry() -> void:
	var sizes := {}
	for k in Data.beasts:
		sizes["beast " + String(k)] = float(Data.beasts[k].scale) * float(Data.beasts[k].get("grow", 1.0))
	for k in Data.campaign.get("enemies", {}):
		var m: Dictionary = Data.enemy_type(String(k)).get("mods", {})
		sizes["man " + String(k)] = float(m.get("bodyScale", 1.0))
	t.check(sizes.size() > 30, "every kind is looked at (%d)" % sizes.size())
	var worst := ""
	var worst_s := 0.0
	for k in sizes:
		if float(sizes[k]) > worst_s:
			worst_s = float(sizes[k])
			worst = String(k)
		var b := _body(float(sizes[k]))
		var gone := b.blood_lost(12.0, 60.0)
		t.check(gone >= 100.0, "%s (size %.2f) loses %.0f blood to a dozen units of bleeding in a minute" % [k, sizes[k], gone])
		b.free()
	t.check(worst_s > 3.5, "(the biggest kind is %s, %.2f)" % [worst, worst_s])

## A blade into a part of the body, from the side (the cuts of tests/beastbleed241's probe).
func _cut(f: Fighter, part: VoxelPart, rng: RandomNumberGenerator) -> void:
	var side := Vector3(1.0, rng.randf_range(-0.2, 0.4), rng.randf_range(-0.4, 0.4)).normalized()
	var p: Vector3 = part.global_position + PD.quat_of(part) * (side * part.half_ext * 0.95)
	var dir := (part.global_position - p).normalized()
	var axis := dir.cross(Vector3.UP).normalized()
	f.apply_hit(part, {"impulse": 25.0, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": p, "dir": dir, "axis": axis, "edge": dir, "heavy": 0.6})

## The ring with the player standing far off and still, and one foe by itself that does nothing.
func _ring() -> Match:
	seed(5)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false, "immortal": true}, "headless": true, "seed": 4, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	m.me.f.teleport(Vector3(0, 0.02, -9))
	m.me.drive = func(_e): return {"look": {"yaw": 0.0, "pitch": 0.0}}
	return m

## Twelve blades into a foe's limbs, then up to `secs` of watching it: the second it died at (it
## bleeds out when its blood is gone, whatever else it lost), or -1.
func _bleed_out(f: Fighter, secs: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var limbs := []
	for p in f.parts:
		var pn := String(p.part_name)
		if pn.begins_with("thigh") or pn.begins_with("upperArm") or (pn.begins_with("leg") and not pn.ends_with("Lo")):
			limbs.append(p)
	for k in 12:
		var part: VoxelPart = limbs[k % limbs.size()]
		if not part.severed:
			_cut(f, part, rng)
	for i in int(secs * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		if not f.alive:
			return float(i + 1) / float(Engine.physics_ticks_per_second)
	return -1.0

## The Big Lion, the boss of the fourth bout (twice the size of a man and a third over his own
## kind's), is bled out by a dozen cuts in his legs: 57 s of it before, and with three blows' worth
## less than that in a fight, never.
func test_the_big_lion_bleeds_to_death() -> void:
	var m := _ring()
	var b: Beast = m.spawn_beast({"beast": "lion", "scale": 2.2, "boss": true, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.0), "yaw": 0.0}).f
	b.sp = b.sp.duplicate()
	b.sp.speed = 0.0
	b.sp.lunge = 0.0
	b.sp.ai = "statue"
	for i in 90:
		await get_tree().physics_frame
	var died: float = await _bleed_out(b, 30.0)
	t.check(died > 0.0 and died < 25.0, "he bleeds to death, in %.1f s" % died)
	t.check(b.blood <= 0.0, "of the blood he lost (%.1f left)" % b.blood)
	m.queue_free()

## A giant, the biggest man in the game (Polyphemus, 3.8 times a man's size) too: his cut arteries
## poured at a third of a man's and his blood went by the size squared, so he never bled out.
func test_polyphemus_bleeds_to_death() -> void:
	var m := _ring()
	var spec: Dictionary = m.enemy_spec({"e": "giant", "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, 2.5)
	spec.yaw = PI
	var ge = m.spawn_fighter(spec)
	ge.drive = func(_e): return {}
	for i in 240:
		await get_tree().physics_frame
	ge.erase("drive")
	ge.bot.think = 99.0
	var died: float = await _bleed_out(ge.f, 45.0)
	t.check(died > 0.0 and died < 40.0, "he bleeds to death, in %.1f s" % died)
	t.check(ge.f.blood <= 0.0, "of the blood he lost (%.1f left)" % ge.f.blood)
	m.queue_free()

## And the biggest beast of all, with its hide (the dragon: size 4.1): a cut takes little of it, but
## where wounds are open all over it, the deepest a blow opens, it bleeds out too.
func test_a_dragon_with_wounds_all_over_bleeds_to_death() -> void:
	var m := _ring()
	var b: Beast = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.0), "yaw": 0.0}).f
	b.sp = b.sp.duplicate()
	b.sp.speed = 0.0
	b.sp.lunge = 0.0
	b.sp.ai = "statue"
	for i in 90:
		await get_tree().physics_frame
	for p in b.parts:
		p.bleed = Fighter.BLEED_BLOW
	var died := -1.0
	for i in 40 * 120:
		await get_tree().physics_frame
		if not b.alive:
			died = float(i + 1) / 120.0
			break
	t.check(died > 0.0, "it bleeds to death, in %.1f s" % died)
	t.check(b.blood <= 0.0, "of the blood it lost (%.1f left)" % b.blood)
	m.queue_free()
