extends Node
## Every beast's insides as they should be (user: the skeleton, the muscles and the organs of every
## animal): the organs under the skin of its trunk (a spider's in its abdomen), a brain in every head
## (the hydra's five, Cerberus's three); a spine down its back, ribs round its chest, a pelvis, a skull
## round the brain, bone down every leg, horns and tusks bone all through; and between the bones and
## the skin, flesh. Scorpions and spiders have no bones: their shell is their skeleton. Read off the
## beasts as the game lays them (Data.beasts, dressed by Anatomy.dress_beasts; the skeletons laid by
## tools/gen_beast_bones.py).

var t

const FLESH := [0x9e1b1b, 0x6e0f0f]

func _filled(d: Dictionary) -> Dictionary:
	var f := {}
	for v in d.voxels:
		f[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = true
	return f

func _buried(f: Dictionary, v: Array) -> bool:
	var c := Vector3i(int(v[0]), int(v[1]), int(v[2]))
	for dd in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if not f.has(c + dd):
			return false
	return true

func _part(sp: Dictionary, name: String) -> Dictionary:
	for d in sp.parts:
		if str(d.name) == name:
			return d
	return {}

func test_every_beast_has_its_organs_under_the_skin() -> void:
	var bad := []
	var on_skin := 0
	for key in Data.beasts:
		var sp: Dictionary = Data.beasts[key]
		var trunk := _part(sp, "abdomen") if key == "spider" else _part(sp, "beastBody")
		var n := {}
		for v in trunk.voxels:
			n[int(v[5])] = int(n.get(int(v[5]), 0)) + 1
		for o in [Anatomy.HEART, Anatomy.LUNG_R, Anatomy.LUNG_L, Anatomy.LIVER, Anatomy.GUTS]:
			if int(n.get(o, 0)) < 4:
				bad.append("%s %s %d" % [key, Anatomy.organ_name(o), int(n.get(o, 0))])
		for d in sp.parts:
			var f := _filled(d)
			for v in d.voxels:
				if int(v[5]) != Anatomy.NONE and not _buried(f, v):
					on_skin += 1
	t.check(bad.is_empty(), "every beast's trunk has its heart, lungs, liver and guts (%s)" % [bad])
	t.check(on_skin == 0, "no organ lies on the skin (%d)" % on_skin)

## (A head with nothing under its skin, a scorpion's flat plate, has its brain in the front of the
## body, where a scorpion's is.)
func test_every_head_has_a_brain_in_a_skull() -> void:
	var no_brain := []
	var no_skull := []
	for key in Data.beasts:
		var in_body := 0
		for v in _part(Data.beasts[key], "beastBody").voxels:
			in_body += 1 if int(v[5]) == Anatomy.BRAIN else 0
		for d in Data.beasts[key].parts:
			if not (bool(d.get("head", false)) or str(d.name) == "beastHead"):
				continue
			var brain := 0
			var bone := 0
			var inside := 0
			var f := _filled(d)
			for v in d.voxels:
				brain += 1 if int(v[5]) == Anatomy.BRAIN else 0
				bone += 1 if v[4] else 0
				inside += 1 if _buried(f, v) else 0
			if brain == 0 and not (inside == 0 and str(d.name) == "beastHead" and in_body > 0):
				no_brain.append("%s.%s" % [key, d.name])
			if bone == 0 and not (key in Beast.BONELESS):
				no_skull.append("%s.%s" % [key, d.name])
	t.check(no_brain.is_empty(), "every head has a brain (%s)" % [no_brain])
	t.check(no_skull.is_empty(), "every head has its skull (%s)" % [no_skull])

func test_every_beast_has_a_skeleton_the_shelled_ones_a_shell() -> void:
	var bad := []
	for key in Data.beasts:
		var sp: Dictionary = Data.beasts[key]
		var shelled: bool = key in Beast.BONELESS
		for d in sp.parts:
			var name := str(d.name).to_lower()
			var bones := 0
			for v in d.voxels:
				bones += 1 if v[4] else 0
			if shelled:
				if name.begins_with("leg") and bones > 0:
					bad.append("%s.%s has bone in its shell" % [key, d.name])
				continue
			if name.begins_with("leg") and bones == 0:
				bad.append("%s.%s has no bone" % [key, d.name])
			if (name.begins_with("horn") or name.begins_with("tusk") or name.begins_with("goathorn")) and bones < d.voxels.size():
				bad.append("%s.%s is not bone all through (%d of %d)" % [key, d.name, bones, d.voxels.size()])
		if shelled:
			continue
		# The trunk: a spine along the back, ribs round the front half (rows of them), a pelvis
		# behind: bone from near one end of it to near the other, in many rows.
		var trunk := _part(sp, "beastBody")
		var rows := {}
		var z0 := 1 << 20
		var z1 := -z0
		for v in trunk.voxels:
			z0 = mini(z0, int(v[2]))
			z1 = maxi(z1, int(v[2]))
			if v[4]:
				rows[int(v[2])] = true
		if float(rows.size()) < 0.5 * float(z1 - z0 + 1):
			bad.append("%s's trunk has bone in only %d of its %d rows" % [key, rows.size(), z1 - z0 + 1])
	t.check(bad.is_empty(), "every beast has its bones (%s)" % [bad])

func test_under_the_skin_it_is_flesh() -> void:
	var bad := []
	for key in Data.beasts:
		if key in Beast.BONELESS:
			continue
		for d in Data.beasts[key].parts:
			var f := _filled(d)
			var inside := 0
			var not_flesh := 0
			for v in d.voxels:
				if _buried(f, v) and not v[4] and int(v[5]) == Anatomy.NONE:
					inside += 1
					if not FLESH.has(int(v[3])):
						not_flesh += 1
			if inside > 20 and not_flesh * 4 > inside:
				bad.append("%s.%s %d of %d" % [key, d.name, not_flesh, inside])
	t.check(bad.is_empty(), "the muscle under the skin is flesh (%s)" % [bad])
