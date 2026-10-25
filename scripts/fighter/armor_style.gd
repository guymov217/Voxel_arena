class_name ArmorStyle
extends RefCounted
## How each piece a gladiator wears looks, voxel by voxel (only the look: the plates, their
## places and what they stop are data/armor.json's, untouched). Hats, hair, beards and the cape
## take their own colour from the table (it used to be ignored: every hair was its material's
## white); hair and beards are coloured to go with the skin. Then each piece is shaded as what it
## is: hair in strands, lighter on top; straw woven, with a red band; a laurel in two greens; a
## crown with red and blue stones; a cape in folds with a dark hem; plate armour in rows of
## plates with a bright rim and rivets.

const HAIR_FOR_SKIN := [Color8(0x4a, 0x2c, 0x18), Color8(0x2e, 0x1c, 0x10), Color8(0x1a, 0x12, 0x0c), Color8(0x12, 0x0d, 0x09), Color8(0x8a, 0x4a, 0x22), Color8(0x22, 0x18, 0x10), Color8(0x0e, 0x0a, 0x08), Color8(0x6a, 0x30, 0x16)]
const SKIN_TONES := [0xe0b48c, 0xc68e5e, 0x9a6440, 0x6e4529, 0xf1c9a5, 0xb98a5e, 0x4f3220, 0xd9a07c]

## The piece's own colour: the table's, the hair's for this skin, or its material's.
static func base_color(id: String, a: Dictionary, skin: Color) -> Color:
	if id.begins_with("hair_") or id.begins_with("beard_"):
		var best := 0
		var bd := INF
		for i in SKIN_TONES.size():
			var t := Color.hex(SKIN_TONES[i] << 8 | 0xff)
			var d := Vector3(t.r - skin.r, t.g - skin.g, t.b - skin.b).length()
			if d < bd:
				bd = d
				best = i
		return HAIR_FOR_SKIN[best]
	if a.get("color") != null:
		return Color.hex(int(a.color) << 8 | 0xff)
	return Weapon.voxel_color(str(a.get("mat", "iron")), "blunt")

## [colour, kind] for every cell of the piece on one part (kinds: shaders/voxel_body.gdshader).
static func cells(id: String, a: Dictionary, cells_: Array, base: Color) -> Array:
	var mat := str(a.get("mat", "iron"))
	var kind := VoxelPart.kind_of_material(mat)
	var ylo := 1 << 20
	var yhi := -(1 << 20)
	var zhi := -(1 << 20)
	for c in cells_:
		ylo = mini(ylo, int(c[1]))
		yhi = maxi(yhi, int(c[1]))
		zhi = maxi(zhi, int(c[2]))
	var span := float(maxi(1, yhi - ylo))
	var hair := id.begins_with("hair_") or id.begins_with("beard_")
	var metal := kind == 3 or kind == 4
	var out := []
	for c in cells_:
		var x := int(c[0])
		var y := int(c[1])
		var z := int(c[2])
		var h := float(y - ylo) / span
		var n := _hash(x, y, z)
		var col := Color.hex((int(c[3]) << 8) | 0xff) if c.size() > 3 else base   # a painted cell
		var k := 1.0
		var kd := kind
		if hair:
			kd = 2
			k = (0.78 + 0.3 * h) * (0.88 if posmod(x + z, 2) == 0 else 1.0) * (0.94 + 0.12 * n)
		elif id == "hat_straw":
			kd = 2
			k = (0.84 if posmod(x + z, 2) == 0 else 1.04) * (0.95 + 0.1 * n)
			if y == ylo + 1 and yhi > ylo + 1:      # the band round the crown, above the brim
				col = Color(0.6, 0.12, 0.09)
				kd = 1
				k = 1.0
		elif id == "hat_laurel":
			kd = 2
			k = 0.72 if posmod(x + y + z, 2) == 0 else 1.05
		elif id == "hat_crest" or id == "hat_feather":
			kd = 1
			k = 0.8 + 0.3 * h
		elif id == "hat_bandana":
			kd = 1
			if n < 0.18:
				col = Color(0.92, 0.88, 0.8)
		elif id == "hat_crown":
			if y == ylo and z == zhi and posmod(x, 2) == 0:
				col = Color(0.75, 0.08, 0.1) if posmod(x, 4) == 0 else Color(0.12, 0.25, 0.75)
				kd = 7
			elif y == yhi:
				k = 1.12
		elif id == "cape":
			kd = 1
			k = (0.84 if posmod(x, 2) == 0 else 1.0) * (0.95 + 0.1 * n)
			if y == ylo:
				k *= 0.68
			elif y == yhi and (x == 0 or x == int(cells_.map(func(cc): return cc[0]).max())):
				col = Color(0.8, 0.62, 0.25)
				kd = 4
		elif metal:
			# Plates in rows, the rim bright, rivets along it.
			if y == ylo or y == yhi:
				k = 1.16
				if posmod(x + z, 3) == 0:
					k = 1.35
			elif posmod(y - ylo, 2) == 0:
				k = 0.84
			k *= 0.95 + 0.1 * n
		elif kind == 6:
			k = 0.85 + 0.3 * h
		var lin := col.srgb_to_linear()
		out.append([Color(clampf(lin.r * k, 0.0, 1.0), clampf(lin.g * k, 0.0, 1.0), clampf(lin.b * k, 0.0, 1.0)).linear_to_srgb(), kd])
	return out

static func _hash(x: int, y: int, z: int) -> float:
	return float(posmod(hash(Vector3i(x, y, z) + Vector3i(17, 5, 3)), 1000)) / 1000.0
