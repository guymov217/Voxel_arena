class_name Armory
## The armourer's stock: the pieces a gladiator can buy and wear in the campaign. The old ones
## come from armor.json; the newer ones are shaped here as shells of plates round the body's
## parts (cells just outside a part's voxel box, in its own dims), so they always fit the body.

## id, price. Ordered as on the smith's rack: light leather first, the steel and gold last.
const SHOP := [
	["leatherCap", 25], ["vambraces", 30], ["ironJaw", 30], ["leatherJerkin", 45], ["skullPlate", 45],
	["greaves", 50], ["cuisses", 55], ["helmet", 60], ["pauldrons", 60], ["manica", 70], ["manicaL", 70],
	["steelGreaves", 80], ["scaleMail", 110], ["murmilloHelm", 120], ["lorica", 140], ["goldHelmet", 150],
	["steelLorica", 200], ["goldLorica", 240],
]

const BLURB := {
	"leatherCap": "Boiled leather over the crown. Light; takes the sting out of a glancing blow.",
	"vambraces": "Leather bracers on both forearms: the arms that parry live longer.",
	"ironJaw": "An iron guard over the jaw and chin.",
	"leatherJerkin": "A thick leather jerkin round the chest and belly. Cheap, and better than skin.",
	"skullPlate": "An iron cap riveted over the skull.",
	"greaves": "Bronze shin guards, front and sides.",
	"cuisses": "Bronze plates over both thighs, where a low cut opens the big vessels.",
	"helmet": "The bronze galea: crown, sides and the back of the neck.",
	"pauldrons": "Iron shoulder caps over both upper arms.",
	"manica": "The iron arm guard of the sword arm, shoulder to wrist.",
	"manicaL": "The iron arm guard for the shield arm.",
	"steelGreaves": "Steel greaves all round both shins.",
	"scaleMail": "Bronze scales from the hips to the shoulders.",
	"murmilloHelm": "The murmillo's steel helm: the whole head, a grilled face and the crest.",
	"lorica": "The iron lorica: chest, back and shoulders.",
	"goldHelmet": "A golden helmet. Soft metal, but the crowd loves it.",
	"steelLorica": "A steel lorica from the hips to the neck. The best a smith can make.",
	"goldLorica": "A golden lorica. It dents easily; the Emperor approves.",
}

static func price(id: String) -> int:
	for r in SHOP:
		if r[0] == id:
			return int(r[1])
	return 0

static func sold(id: String) -> bool:
	return price(id) > 0

## The new pieces, shaped round the parts of `body` (body.json's parts, by name).
static func extra(body_parts: Array) -> Dictionary:
	var dims := {}
	for p in body_parts:
		dims[p.name] = p.dims
	var out := {}
	var piece := func(id: String, name: String, mat: String, parts: Dictionary) -> void:
		# Plate steel a shade darker than a blade's polished edge, so it reads as armour.
		out[id] = {"name": name, "mat": mat, "color": 0x8c939b if mat == "steel" else null, "parts": parts}
	var both := func(a: String, b: String, f: Callable) -> Dictionary:
		return {a: f.call(dims[a]), b: f.call(dims[b])}
	piece.call("leatherCap", "Leather cap", "leather", {"head": _wrap(dims.head, 4, 5, "all") + _cap(dims.head)})
	piece.call("vambraces", "Leather vambraces", "leather", both.call("forearmR", "forearmL", func(d): return _wrap(d, 0, 4, "all")))
	piece.call("leatherJerkin", "Leather jerkin", "leather", {"torso": _wrap(dims.torso, 2, 9, "all")})
	piece.call("cuisses", "Bronze cuisses", "bronze", both.call("thighR", "thighL", func(d): return _wrap(d, 1, 7, "front")))
	piece.call("pauldrons", "Iron pauldrons", "iron", both.call("upperArmR", "upperArmL", func(d): return _wrap(d, 4, 6, "all") + _cap(d)))
	piece.call("manicaL", "Manica (shield arm)", "iron", {"upperArmL": _wrap(dims.upperArmL, 2, 6, "all"), "forearmL": _wrap(dims.forearmL, 2, 6, "all")})
	piece.call("steelGreaves", "Steel greaves", "steel", both.call("shinR", "shinL", func(d): return _wrap(d, 0, 7, "all")))
	piece.call("scaleMail", "Scale mail", "bronze", {"torso": _wrap(dims.torso, 1, 10, "all") + _cap(dims.torso, 1)})
	piece.call("steelLorica", "Steel lorica", "steel", {"torso": _wrap(dims.torso, 0, 10, "all") + _cap(dims.torso, 1)})
	piece.call("murmilloHelm", "Murmillo helm", "steel", {"head": _helm(dims.head)})
	return out

## A band of plates round a part from row y0 to y1: "all" round it, or "front" and sides only.
static func _wrap(d: Array, y0: int, y1: int, sides: String) -> Array:
	var X: int = d[0]
	var Z: int = d[2]
	var cells := []
	for y in range(maxi(0, y0), mini(int(d[1]) - 1, y1) + 1):
		for x in range(-1, X + 1):
			for z in range(-1, Z + 1):
				if not (x == -1 or x == X or z == -1 or z == Z):
					continue
				if sides == "front" and z == -1:
					continue
				cells.append([x, y, z])
	return cells

## The top of a part covered, with a hole of `hole` cells round the middle (for a neck).
static func _cap(d: Array, hole := 0) -> Array:
	var X: int = d[0]
	var Y: int = d[1]
	var Z: int = d[2]
	var cells := []
	for x in range(-1, X + 1):
		for z in range(-1, Z + 1):
			if hole > 0 and absf(x - (X - 1) * 0.5) <= hole and absf(z - (Z - 1) * 0.5) <= hole:
				continue
			cells.append([x, Y, z])
	return cells

## The murmillo's helm: the whole head boxed in, a grille over the face (every other bar left
## out at the eyes) and a crest along the top.
static func _helm(d: Array) -> Array:
	var X: int = d[0]
	var Y: int = d[1]
	var Z: int = d[2]
	var cells := []
	for c in _wrap(d, 1, Y - 1, "all"):
		var eyes: bool = c[2] == Z and c[1] >= Y - 3 and c[1] <= Y - 2 and c[0] >= 0 and c[0] < X
		if eyes and c[0] % 2 == 1:
			continue
		cells.append(c)
	cells += _cap(d)
	var mid := int((X - 1) / 2)
	for z in range(0, Z):
		cells.append([mid, Y + 1, z])
	return cells

## What a piece covers, for the picture on the rack and for which pieces clash.
static func parts_of(id: String) -> Array:
	return (Data.armor.get(id, {}).get("parts", {}) as Dictionary).keys()

## Two pieces clash when they put plates on the same cell: buying one takes the other off.
static func clashes(a: String, b: String) -> bool:
	var pa: Dictionary = Data.armor.get(a, {}).get("parts", {})
	var pb: Dictionary = Data.armor.get(b, {}).get("parts", {})
	for part in pa:
		if not pb.has(part):
			continue
		var seen := {}
		for c in pa[part]:
			seen[Vector3i(c[0], c[1], c[2])] = true
		for c in pb[part]:
			if seen.has(Vector3i(c[0], c[1], c[2])):
				return true
	return false

## The pieces worn, cleaned: only what the armourer sells, once each, no two clashing.
static func sanitize(ids) -> Array:
	var out := []
	if not (ids is Array):
		return out
	for id in ids:
		if id is String and sold(id) and Data.armor.has(id) and not out.has(id) and not out.any(func(o): return clashes(o, id)):
			out.append(id)
	return out.slice(0, 10)

## Buying `id`: what is worn after (the clashing pieces taken off, sold back for half) and the cost.
static func buy(worn: Array, id: String) -> Dictionary:
	if not sold(id) or not Data.armor.has(id):
		return {"error": "The armourer has no such thing"}
	var have := sanitize(worn)
	if have.has(id):
		return {"error": "You already wear it"}
	var back := 0
	var keep := []
	for o in have:
		if clashes(o, id):
			back += price(o) / 2
		else:
			keep.append(o)
	keep.append(id)
	return {"worn": keep, "cost": price(id) - back, "refund": back}

static func take_off(worn: Array, id: String) -> Dictionary:
	var have := sanitize(worn)
	if not have.has(id):
		return {"error": "You do not wear it"}
	have.erase(id)
	return {"worn": have, "cost": -(price(id) / 2)}
