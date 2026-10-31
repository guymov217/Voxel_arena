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

