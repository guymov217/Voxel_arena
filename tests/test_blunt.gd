extends Node
## Blunt and keen (user: a mace breaks bones, it does not cut limbs; that is the difference
## between a blunt weapon and a sharp one): a crushing weapon's blows go in to the bone, they
## break it sooner and more surely than the same blow of a fist or a cut does, and take less
## flesh away; the studs on a mace's head crush with it.

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

func test_a_mace_is_a_crusher_and_a_blade_is_not() -> void:
	var r := _victim()
	var m: Match = r[0]
	await _steps(5)
	for k in ["mace", "warhammer", "hammer"]:
		var w := m.spawn_loose_weapon(Data.preset(k), Vector3(3, 1, 3))
		t.check(w.crusher(), "%s crushes" % k)
	for k in ["gladius", "axe", "spear", "longsword"]:
		var w := m.spawn_loose_weapon(Data.preset(k), Vector3(-3, 1, 3))
		t.check(not w.crusher(), "%s does not" % k)
	m.queue_free()

## Blows of `J` on the front of each of the long bones: how many it broke, and the voxels taken.
func _beat(weapon: bool, J: float) -> Array:
	var broke := 0
	var lost := 0
	for n in ["forearmR", "forearmL", "shinR", "shinL", "thighR", "thighL", "upperArmR", "upperArmL"]:
		var r := _victim()
		var m: Match = r[0]
		var v: Fighter = r[1]
		await _steps(20)
		var p: VoxelPart = v.by_name.get(n)
		if p == null:
			m.queue_free()
			continue
		var n0 := p.alive_count
		for k in 3:
			p.hp = 1000.0
			var gt := p.global_transform
			var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
			v.apply_hit(p, {"impulse": J, "type": "blunt", "hardness": 0.9, "heavy": 0.3, "point": gt * Vector3(0, 0, p.half_ext.z), "dir": -bz, "weapon": weapon})
			await _steps(3)
		broke += 1 if p.fracture > 0 else 0
		lost += n0 - p.alive_count
		m.queue_free()
		await _steps(1)
	return [broke, lost]

func test_a_mace_breaks_bone_where_a_fist_bruises() -> void:
	seed(11)
	var mace = await _beat(true, 11.0)
	seed(11)
	var fist = await _beat(false, 11.0)
	t.check(int(mace[0]) >= 5, "three mace blows broke most of the bones they fell on (%d of 8)" % mace[0])
	t.check(int(mace[0]) > int(fist[0]), "more than the same blows without a crushing weapon (%d)" % fist[0])
	seed(11)
	var hard = await _beat(true, 22.0)
	seed(11)
	var hard_fist = await _beat(false, 22.0)
	t.check(int(hard[1]) <= int(hard_fist[1]), "and it pulps the flesh rather than knocking it away (%d voxels, %d without)" % [hard[1], hard_fist[1]])

## A fair blow of a hammer rocks a man, it does not floor him (user: blunt weapons knocked men
## down far too easily); a crushing one still can.
func test_a_hammer_blow_rocks_but_does_not_floor() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(40)
	var gt := v.torso.global_transform
	var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
	v.apply_hit(v.torso, {"impulse": 50.0, "type": "blunt", "hardness": 0.9, "heavy": 0.6, "weapon": true, "point": gt * Vector3(0, 0, v.torso.half_ext.z), "dir": -bz})
	t.check(v.state == "stand", "a fair hammer blow to the chest leaves him on his feet (%s, stagger %.2f)" % [v.state, v.stagger])
	m.queue_free()

## The warhammer stands its blows longer than its stone head alone would (user: it broke after a
## few blows).
func test_the_warhammer_is_made_to_last() -> void:
	var r := _victim()
	var m: Match = r[0]
	await _steps(5)
	var hammer := m.spawn_loose_weapon(Data.preset("warhammer"), Vector3(3, 1, 3))
	var mace := m.spawn_loose_weapon(Data.preset("mace"), Vector3(-3, 1, 3))
	t.check(hammer.durability() > 1.4, "the warhammer is tougher than its stuff (x%.1f)" % hammer.durability())
	t.check(is_equal_approx(mace.durability(), 1.0), "others as their stuff makes them")
	var lost := 0
	for i in 8:
		var k: Dictionary = hammer.knock(hammer.voxel_count() - 1 if hammer.has_method("voxel_count") else hammer.vox.size() - 1, Weapon.chip_score(32.0 * 0.25, 0.6, 0.5))
		lost += (k.get("indices", []) as Array).size()
	t.check(lost <= 2, "eight fair blows on one spot of its head take almost nothing off (%d voxels)" % lost)
	m.queue_free()


## `n` fresh men in a row, one blow into each at its own place on `part_name` (a little apart, a
## voxel's breadth or less: the grid hides a small change of depth at any one place), `J` the blow's
## impulse; the voxels each lost, in order.
func _taken(kind: String, part_name: String, J: float, n := 8) -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "decrees": [], "hazards": [], "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, 16))
	var men := []
	for i in n:
		var e = m.spawn_fighter({"kind": "bot", "name": "V%d" % i, "loadout": {}, "team": 1, "pos": Vector3(-9.0 + 2.5 * i, 0.1, 0), "yaw": 0.0})
		e.erase("bot")
		e.drive = func(_e): return {}
		men.append(e.f)
	await _steps(50)
	var out := []
	for i in n:
		var v: Fighter = men[i]
		var p: VoxelPart = v.by_name[part_name]
		var vfs: float = p.vf * p.part_scale
		var n0: int = p.alive_count
		var gt := p.global_transform
		var bx := gt.basis.orthonormalized()
		var into := -(bx * Vector3(0, 0, 1))
		var f := float(i) / float(n) - 0.5
		var at := Vector3(f * vfs, p.half_ext.y * (0.2 if part_name == "torso" else 0.0) + sin(float(i) * 2.4) * 0.5 * vfs, p.half_ext.z + cos(float(i) * 1.7) * 0.4 * vfs)
		var hit := {"impulse": J, "point": gt * at, "dir": into, "axis": into, "weapon": true, "heavy": 0.4, "wsz": 1.0}
		if kind == "edge":
			hit.merge({"type": "edge", "hardness": 0.9, "sharpness": 0.9, "edge": into, "axis": bx * Vector3(1, 0, 0), "mass": 1.7})
		else:
			hit.merge({"type": "blunt", "hardness": 0.7, "sharpness": 0.0, "mass": 2.0})
		v.apply_hit(p, hit)
		out.append(n0 - p.alive_count)
	m.queue_free()
	await get_tree().process_frame
	return out

func _mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1.0, float(a.size()))

## A blow is held to a ceiling of what it takes of a part, and past it still takes a little more, the
## harder it came: as the root of how far past the force reaches, never more than a quarter past.
func test_past_the_ceiling_a_blow_goes_on_a_little_further() -> void:
	t.check(is_equal_approx(Fighter.past_cap(0.05, 0.09, 3.0), 0.05), "under the ceiling nothing is changed")
	t.check(is_equal_approx(Fighter.past_cap(0.09, 0.09, 3.0), 0.09), "at it, the same")
	var a := Fighter.past_cap(0.12, 0.09, 3.0)
	var b := Fighter.past_cap(0.18, 0.09, 3.0)
	var c := Fighter.past_cap(0.30, 0.09, 3.0)
	t.check(a > 0.09 and b > a and c > b, "a harder blow goes further each time (%.3f, %.3f, %.3f)" % [a, b, c])
	t.check(is_equal_approx(b, 0.09 * pow(2.0, 0.5 / 3.0)), "as the root of the force, in volume: twice as far past the ceiling, a half more of it")
	t.check(is_equal_approx(Fighter.past_cap(50.0, 0.09, 3.0), 0.09 * Fighter.PAST_MAX), "and never more than a quarter past it (%.3f)" % Fighter.past_cap(50.0, 0.09, 3.0))
	t.check(Fighter.past_cap(0.12, 0.09, 1.0) > Fighter.past_cap(0.12, 0.09, 3.0), "a depth goes on faster than a radius, for the same volume")

## A club or a hammer swung harder crushes a bigger hollow, over the whole of what a man swings (the
## crater used to stop growing at J 35: every blow past it took the same).
func test_a_harder_blunt_blow_takes_more_flesh_the_harder_it_comes() -> void:
	var means := {}
	for J in [25.0, 35.0, 45.0, 60.0, 80.0]:
		means[J] = _mean(await _taken("blunt", "thighR", J))
	t.check(means[25.0] > 0.0 and means[35.0] > means[25.0], "a crater that grows to the ceiling (%.0f, %.0f voxels)" % [means[25.0], means[35.0]])
	t.check(means[45.0] > means[35.0] * 1.08, "and past it (%.0f at 35, %.0f at 45)" % [means[35.0], means[45.0]])
	t.check(means[60.0] > means[45.0] * 1.05, "still (%.0f at 60)" % means[60.0])
	t.check(means[80.0] > means[60.0] * 1.05, "and still (%.0f at 80)" % means[80.0])
	t.check(means[80.0] < means[35.0] * 2.0, "but a little, not a different weapon (%.0f at 80 against %.0f at 35)" % [means[80.0], means[35.0]])

## A cut goes the same way: the harder and the faster the swing, the more of the flesh it takes.
func test_a_harder_cut_takes_more_flesh_the_harder_it_comes() -> void:
	var means := {}
	for J in [15.0, 25.0, 45.0, 80.0]:
		means[J] = _mean(await _taken("edge", "thighR", J))
	t.check(means[25.0] > means[15.0] * 1.08, "a cut of 25 takes more than a cut of 15 (%.0f against %.0f voxels)" % [means[25.0], means[15.0]])
	t.check(means[45.0] > means[25.0] * 1.08, "45 more than 25 (%.0f)" % means[45.0])
	t.check(means[80.0] > means[45.0] * 1.08, "and 80 more than 45 (%.0f)" % means[80.0])
	t.check(means[80.0] < means[15.0] * 4.0, "but a little, not a different weapon (%.0f against %.0f)" % [means[80.0], means[15.0]])
