class_name BeastStyle
extends RefCounted
## How a beast's voxels look (only the look; the voxels, their places and the beast's body stay
## as data/beasts.json has them). Each voxel gets what it is made of, for the voxel shader
## (shaders/voxel_body.gdshader): flesh inside, bone for horns, teeth and claws, glossy eyes
## (glowing, for the monsters), fur, scales or chitin on the outside. The outside is shaded the
## way animals are, the back darker and the belly lighter, with each species' markings: a tiger's
## stripes, a hyena's spots, a wolf's dark saddle, scales in plates, an elephant's wrinkles,
## the joints of a scorpion's shell.

const SCALED := ["crocodile", "python", "basilisk", "dragon", "hydra"]
const CHITIN := ["scorpion", "spider"]
const GLOWING_EYES := ["dragon", "basilisk", "cerberus", "hydra", "manticore", "chimera", "griffin"]
## Beasts whose nose and lips are wet: the dark at the very front of the head shines.
const WET_NOSES := ["lion", "tiger", "wolf", "hyena", "bear", "boar", "bull", "goat", "rat", "cerberus", "chimera", "manticore"]
const FLESH_A := Color8(0x9e, 0x1b, 0x1b)
const FLESH_B := Color8(0x6e, 0x0f, 0x0f)
const BONE := Color8(0xe8, 0xe0, 0xc8)

## The voxels of one part, restyled: [[x, y, z, Color, bone, kind], ...].
static func style_part(species: String, part: String, grid: Array, voxels: Array) -> Array:
	var occ := {}
	for v in voxels:
		occ[Vector3i(v[0], v[1], v[2])] = true
	var gy := maxi(1, int(grid[1]) - 1)
	var out := []
	for v in voxels:
		var p := Vector3i(v[0], v[1], v[2])
		var c: Color = v[3]
		var kind := _kind_of(species, part, c, float(p.y) / float(gy), p.z >= int(grid[2]) - 2)
		var outside := false
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if not occ.has(p + d):
				outside = true
				break
		if outside and (kind == 8 or kind == 10 or kind == 11):
			c = _mark(species, part, p, c, float(p.y) / float(gy), kind)
		elif kind == 12:
			c = Color(1.0, 0.55, 0.1) if species != "basilisk" else Color(0.75, 1.0, 0.2)
		out.append([v[0], v[1], v[2], c, v[4], kind])
	return out

## (A dark voxel high on a monster's head is an eye and glows; lower down it is the mouth.)
static func _kind_of(species: String, part: String, c: Color, h: float, front := false) -> int:
	if c.is_equal_approx(FLESH_A) or c.is_equal_approx(FLESH_B):
		return 9
	if c.get_luminance() < 0.06 and part.to_lower().contains("head"):
		return 12 if species in GLOWING_EYES and h > 0.45 else 7
	var low := part.to_lower()
	if front and species in WET_NOSES and low.contains("head") and c.get_luminance() < 0.3 and not c.is_equal_approx(BONE):
		return 7
	# Bone: the skeleton's own colour, and horns, tusks and spines (a white goat is still fur).
	if c.is_equal_approx(BONE) or ((low.contains("horn") or low.contains("tusk") or low.contains("fang")) and c.get_luminance() > 0.6):
		return 6
	if species in CHITIN:
		return 11
	if species in SCALED:
		return 10
	return 8

## The markings and the shading of an outside voxel; `h` is its height in the part, 0..1.
static func _mark(species: String, part: String, p: Vector3i, c: Color, h: float, kind: int) -> Color:
	var lin := c.srgb_to_linear()
	# Darker on the back and lighter underneath (the sun does the rest), a little.
	var k := 1.08 - 0.22 * h if kind == 8 else 1.0
	var body := part == "beastBody" or part.begins_with("tail") or part == "neck"
	match species:
		"tiger":
			if (posmod(p.z * 2 + (p.y / 3), 7) < 2) and h > 0.25:
				return Color(0.12, 0.07, 0.04)
		"hyena", "chimera":
			if body and _hash(p / 3) < 0.22:
				lin = lin * 0.45
		"wolf":
			if body and h > 0.7:
				k *= 0.7
			# Grizzled, hair by hair.
			k *= 0.9 + 0.2 * _hash(p * 3)
		"boar":
			if body and h > 0.85:
				k *= 0.6
			# A coat of coarse bristles, grizzled tip by tip.
			k *= 0.88 + 0.22 * _hash(p * 3)
		"bear":
			k *= 0.9 + 0.18 * _hash(p * 3)
		"goat":
			# Patches of brown on the white.
			if body and _hash(p / 4) < 0.22:
				lin = Color(lin.r * 0.55, lin.g * 0.42, lin.b * 0.3)
			k *= 0.94 + 0.1 * _hash(p * 3)
		"elephant", "mammoth", "rhino":
			if posmod(p.y, 3) == 0:
				k *= 0.9
		"lion", "manticore", "griffin":
			if part.to_lower().contains("head") and h > 0.6:
				k *= 0.85
			# The mane in strands: each lock its own shade, darker toward the roots.
			if species == "lion" and (part.to_lower().contains("head") or part == "tuft") and c.get_luminance() < 0.5:
				k *= 0.78 + 0.34 * _hash(Vector3i(p.x * 5, p.y / 3, p.z * 5))
	if kind == 10:
		# Plates of scales two voxels across, each its own shade, with darker seams.
		var cell := Vector3i(p.x / 2, p.y / 2, p.z / 2)
		k *= 0.88 + 0.22 * _hash(cell)
		if posmod(p.x, 2) == 0 and posmod(p.z, 2) == 0:
			k *= 0.85
	elif kind == 11:
		# The shell in segments.
		if posmod(p.z, 4) == 0:
			k *= 0.6
	return Color(lin.r * k, lin.g * k, lin.b * k).linear_to_srgb()

static func _hash(p: Vector3i) -> float:
	return float(posmod(hash(p) , 1000)) / 1000.0
