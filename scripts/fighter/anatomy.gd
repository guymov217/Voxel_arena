class_name Anatomy
## What is inside a gladiator: the organs in the trunk and the head, laid into the red flesh of
## data/body.json as voxels of their own (a colour, and an organ id on every voxel). They are lost
## like any other voxel, to a cut, a stab or a crushing blow, and what is lost of each says what
## it does to him (Fighter._organ_lost, Fighter._organs_tick). No DOM, no nodes: runs headless.
##
## The torso's fine grid is 16 x 22 x 10 (x from his right to his left, y up from the hips, z from
## the back to the front at z = 9); one voxel of skin all round. The head is 10 x 12 x 10.

enum { NONE, HEART, LUNG_R, LUNG_L, LIVER, STOMACH, GUTS, SPINE, BRAIN, RIBS, PELVIS, SKULL }

const BONE := 0xe8e0c8

const INFO := {
	HEART: {"name": "heart", "color": 0x7c1424},
	LUNG_R: {"name": "lung", "color": 0xc9727a},
	LUNG_L: {"name": "lung", "color": 0xc9727a},
	LIVER: {"name": "liver", "color": 0x5e1913},
	STOMACH: {"name": "stomach", "color": 0xc0806a},
	GUTS: {"name": "guts", "color": 0xd49184},
	SPINE: {"name": "spine", "color": 0xe8e0c8},
	BRAIN: {"name": "brain", "color": 0xd9a3a8},
	RIBS: {"name": "ribs", "color": BONE},
	PELVIS: {"name": "pelvis", "color": BONE},
	SKULL: {"name": "skull", "color": BONE},
}

## The bones among them (drawn and cut as bone).
static func is_bone(id: int) -> bool:
	return id == SPINE or id == RIBS or id == PELVIS or id == SKULL

## The gore setting (Settings): "full" shows the insides as they are (organ colours, guts that
## spill, bone through an open break); "reduced" draws the insides as plain flesh and lets
## nothing spill. Only the look: the wounds do the same either way, so every player in a match
## fights the same fight.
static func gore() -> String:
	var s = Save.get_value("settings", {})
	return "reduced" if s is Dictionary and s.get("gore", "full") == "reduced" else "full"

static func organ_name(id: int) -> String:
	return INFO.get(id, {}).get("name", "")

## The bone at a cell of the torso or the head, just inside the skin: the ribs every other row
## round the chest (the gaps between them let a point through), the breastbone and the
## collarbones, the pelvis round the hips, the skull round the brain and the jaw.
static func bone_at(part: String, x: int, y: int, z: int) -> int:
	if part == "torso":
		if y >= 11 and y <= 19:
			if x >= 7 and x <= 8 and z == 8:
				return RIBS           # the breastbone
			if y % 2 == 1 and (x == 1 or x == 14 or z == 1 or z == 8):
				return RIBS
		if y == 20 and z == 8:
			return RIBS               # the collarbones
		if y >= 1 and y <= 4 and z >= 2 and z <= 7 and (x <= 2 or x >= 13):
			return PELVIS
		if y >= 1 and y <= 5 and z == 1 and x >= 4 and x <= 11:
			return PELVIS             # the sacrum
	elif part == "head":
		if y >= 5 and y <= 10 and (x == 1 or x == 8 or z == 1 or z == 8 or y == 5 or y == 10):
			return SKULL
		if y >= 1 and y <= 2 and z == 8:
			return SKULL              # the jaw
	return NONE

## The organ at a cell of the torso or the head (NONE: plain flesh, skin or anything else).
static func organ_at(part: String, x: int, y: int, z: int) -> int:
	if part == "torso":
		if x >= 7 and x <= 8 and z >= 1 and z <= 2 and y >= 1 and y <= 20:
			return SPINE
		if x >= 8 and x <= 10 and y >= 14 and y <= 16 and z >= 5 and z <= 7:
			return HEART
		if y >= 12 and y <= 19 and z >= 3 and z <= 7:
			if x >= 2 and x <= 6:
				return LUNG_R
			if x >= 9 and x <= 13:
				return LUNG_L
		if y >= 9 and y <= 11:
			if x >= 2 and x <= 7 and z >= 3 and z <= 7:
				return LIVER
			if x >= 9 and x <= 12 and z >= 4 and z <= 7:
				return STOMACH
		if y >= 2 and y <= 8 and x >= 2 and x <= 13 and z >= 3 and z <= 7:
			return GUTS
	elif part == "head":
		if x >= 2 and x <= 7 and y >= 6 and y <= 9 and z >= 2 and z <= 7:
			return BRAIN
	return NONE

## The big vessels near the skin, where a cut bleeds out in seconds and spurts with every beat:
## the throat (under the jaw, and the root of the neck on the trunk), the groin (high on the
## inside of a thigh), the armpit (high on the inside of an upper arm). A beast's neck and throat.
static func artery_at(part: String, x: int, y: int, z: int) -> bool:
	match part:
		"head":
			return y <= 2 and z >= 2 and z <= 7
		"torso":
			return y >= 19 and x >= 5 and x <= 10 and z >= 3 and z <= 7
		"thighR":
			return x >= 5 and y >= 8 and z >= 2 and z <= 5
		"thighL":
			return x <= 2 and y >= 8 and z >= 2 and z <= 5
		"upperArmR":
			return x >= 4 and y >= 8
		"upperArmL":
			return x <= 1 and y >= 8
		"neck":
			return true
	return false

## Plain red flesh (what lies under the skin in body.json), not hair, eyes, a mouth or a belt.
static func _is_flesh(rgb: int) -> bool:
	var r := (rgb >> 16) & 0xff
	var g := (rgb >> 8) & 0xff
	var b := rgb & 0xff
	return r > 80 and r > g * 2.2 and r > b * 2.2

## Lays the organs and the bones into the body's parts (Data.load_all): every voxel of plain
## flesh (type 0, not bone) that an organ or a bone fills takes its colour, a little grain of its
## own, and gets its id as a 7th field; the rest get 0. Bones are marked bone.
static func dress(body_parts: Array) -> void:
	for d in body_parts:
		var name := str(d.name)
		for v in d.voxels:
			var id := NONE
			if int(v[3]) == 0 and not v[5] and _is_flesh(int(v[4])):
				id = organ_at(name, int(v[0]), int(v[1]), int(v[2]))
				if id == NONE:
					id = bone_at(name, int(v[0]), int(v[1]), int(v[2]))
			if id != NONE:
				v[4] = _organ_rgb(id, int(v[0]), int(v[1]), int(v[2]))
				if is_bone(id):
					v[5] = 1
			if v.size() < 7:
				v.append(id)
			else:
				v[6] = id

## An organ's colour at a cell: guts in coils, lungs spongy, the rest a little mottled.
static func _organ_rgb(id: int, x: int, y: int, z: int) -> int:
	var c := Color.hex(int(INFO[id].color) << 8 | 0xff)
	var k := 1.0
	if id == GUTS:
		k = 0.82 if (x + y * 2) % 3 == 0 else 1.0
	elif (x * 7 + y * 3 + z * 5) % 4 == 0:
		k = 0.9
	return (int(c.r8 * k) << 16) | (int(c.g8 * k) << 8) | int(c.b8 * k)

## Species whose insides are not a beast's (a shell of chitin round a different body): no organs.
const NO_ORGANS := ["scorpion", "spider"]

## The organs of a beast, by proportion of its body (beastBody: x across, y up, z along it, the
## head at +z) and its head: the heart low in the chest, the lungs above it, the liver behind,
## the guts in the belly, the brain at the back of the skull. Plain red flesh only.
static func beast_organ_at(part: String, g: Array, x: int, y: int, z: int) -> int:
	var u := (float(x) + 0.5) / float(g[0])
	var v := (float(y) + 0.5) / float(g[1])
	var w := (float(z) + 0.5) / float(g[2])
	if part == "beastBody":
		var mid := absf(u - 0.5)
		if w > 0.6 and w < 0.74 and v > 0.25 and v < 0.48 and mid < 0.14:
			return HEART
		if w > 0.55 and w < 0.82 and v >= 0.42 and v < 0.78 and mid > 0.06 and mid < 0.36:
			return LUNG_R if u < 0.5 else LUNG_L
		if w > 0.44 and w <= 0.58 and v > 0.22 and v < 0.6 and mid < 0.34:
			return LIVER
		if w > 0.16 and w <= 0.44 and v > 0.12 and v < 0.52 and mid < 0.36:
			return GUTS
	elif part == "beastHead":
		if w > 0.12 and w < 0.45 and v > 0.5 and v < 0.85 and absf(u - 0.5) < 0.22:
			return BRAIN
	return NONE

static func _buried(filled: Dictionary, x: int, y: int, z: int) -> bool:
	for d in [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]:
		if not filled.has((x + d[0]) | ((y + d[1]) << 8) | ((z + d[2]) << 16)):
			return false
	return true

## Lays the organs into the beasts' bodies (Data.load_all): an organ id as the 6th field of every
## voxel of beasts.json ([x, y, z, colour, bone, organ]).
static func dress_beasts(beasts: Dictionary) -> void:
	for key in beasts:
		var none: bool = key in NO_ORGANS
		for d in beasts[key].get("parts", []):
			var name := str(d.name)
			var g: Array = d.get("grid", [1, 1, 1])
			# Organs lie under the skin: only a voxel with flesh on all six sides may be one (a
			# body modelled leaning, the gorilla's, had its guts showing through the rump).
			var filled := {}
			for v in d.voxels:
				filled[int(v[0]) | (int(v[1]) << 8) | (int(v[2]) << 16)] = true
			for v in d.voxels:
				var id := NONE
				if not none and not v[4] and _is_flesh(int(v[3])) and _buried(filled, int(v[0]), int(v[1]), int(v[2])):
					id = beast_organ_at(name, g, int(v[0]), int(v[1]), int(v[2]))
				if id != NONE:
					v[3] = _organ_rgb(id, int(v[0]), int(v[1]), int(v[2]))
				if v.size() < 6:
					v.append(id)
				else:
					v[5] = id
