class_name Arms
## The campaign's arms (arms.js): a training stick to start with; at the smith a base of any
## weapon, reshaped voxel by voxel (each voxel its material's price, refunded when taken off);
## the chips a stage leaves stay until mended; upgrades that are not voxels.

static func empty() -> Dictionary:
	return {"main": Data.shop.get("stick", {}).duplicate(true), "off": null, "wear": {"R": [], "L": []}}

static func sanitize(a) -> Dictionary:
	var out := empty()
	if not (a is Dictionary):
		return out
	if a.get("main") is Dictionary and a.main.get("voxels") is Array and not a.main.voxels.is_empty():
		out.main = a.main
	if a.get("off") is Dictionary and a.off.get("voxels") is Array:
		out.off = a.off
	if out.main.get("twoHanded", false):
		out.off = null
	for side in ["R", "L"]:
		var d = out.main if side == "R" else out.off
		var w = a.get("wear", {}).get(side, []) if a.get("wear") is Dictionary else []
		var clean := []
		if d and w is Array:
			for n in w:
				var i := int(n)
				if i >= 0 and i < d.voxels.size() and not clean.has(i):
					clean.append(i)
		out.wear[side] = clean
	return out

static func voxel_price(mat: String) -> int:
	return int(Data.shop.get("voxelPrice", {}).get(mat, 2))

static func value(d) -> int:
	if not (d is Dictionary):
		return 0
	var s := 0
	for v in d.get("voxels", []):
		s += voxel_price(v[3])
	return s

## Weapons kept aside for now (still in the data, out of the shop, the lists, the lottery
## and the drops from the stands): the chain weapons and the crossbow.
const SHELVED := ["flail", "imperialFlail", "meteorHammer", "crossbow"]

static func shelved(key: String) -> bool:
	return SHELVED.has(key)

static func bases() -> Array:
	return Data.shop.get("bases", []).filter(func(b): return not SHELVED.has(String(b.key)))

static func base(key: String) -> Dictionary:
	for b in bases():
		if b.key == key:
			return b
	return {}

static func buy(a: Dictionary, key: String) -> Dictionary:
	var b := base(key)
	if b.is_empty():
		return {"error": "The smith has no such thing"}
	var arms := sanitize(a)
	var slot: String = b.slot
	var side := "R" if slot == "main" else "L"
	var trade_in := int(value(arms[slot]) * 0.5) if arms[slot] else 0
	arms[slot] = Data.preset(key).duplicate(true)
	arms.wear[side] = []
	if slot == "main" and arms.main.get("twoHanded", false):
		arms.off = null
	return {"arms": arms, "cost": int(b.price) - trade_in, "trade_in": trade_in}

static func repair_cost(a: Dictionary, side: String) -> int:
	var d = a.main if side == "R" else a.off
	if not d:
		return 0
	var c := 0
	for i in a.wear.get(side, []):
		c += maxi(1, ceili(voxel_price(d.voxels[i][3]) * 0.5))
	return c

static func repair(a: Dictionary, side: String) -> Dictionary:
	var arms := sanitize(a)
	var cost := repair_cost(arms, side)
	arms.wear[side] = []
	return {"arms": arms, "cost": cost}

## After a stage: the chips it left on top of the old ones ("lost": everything but the grip).
static func add_wear(a: Dictionary, report: Dictionary) -> Dictionary:
	var arms := sanitize(a)
	for side in ["R", "L"]:
		var d = arms.main if side == "R" else arms.off
		var r = report.get(side)
		if not d or r == null:
			continue
		var idx := []
		if r is String and r == "lost":
			for i in d.voxels.size():
				if d.voxels[i][4] != "grip":
					idx.append(i)
		elif r is Array:
			idx = r
		for i in idx:
			if int(i) >= 0 and int(i) < d.voxels.size() and not arms.wear[side].has(int(i)):
				arms.wear[side].append(int(i))
	return arms

static func condition(a: Dictionary, side: String) -> float:
	var d = a.main if side == "R" else a.off
	if not d or d.voxels.is_empty():
		return 1.0
	return 1.0 - float(a.wear.get(side, []).size()) / d.voxels.size()

const UPGRADES := {
	"whetstone": {"label": "Hone the edge", "desc": "A sharper edge and point: cuts and thrusts go deeper (+10% sharpness)."},
	"temper": {"label": "Temper the blade", "desc": "Bronze and iron reforged as steel: harder, holds an edge, chips less."},
	"venom": {"label": "Coat with venom", "desc": "Snake venom on the edge: every cut poisons. The wound bleeds more, the poisoned man slows and weakens."},
	"fire": {"label": "Pitch and fire", "desc": "Pitch on the head, set alight: it burns as you fight, and sets alight what it strikes."},
	"frost": {"label": "Frost rune", "desc": "A rune of the north: every blow chills to the bone, slowing the man it lands on and sapping his breath."},
}
## The coatings: one at a time on a weapon (a new one replaces the old).
const COATINGS := ["venom", "fire", "frost"]
const COATING_NAMES := {"venom": "Venom", "fire": "Burning", "frost": "Frost"}

static func upgrade_price(id: String, d: Dictionary) -> int:
	match id:
		"whetstone": return int(round(15 + 45 * float(d.get("sharpness", 0.0))))
		"temper":
			var n := 0
			for v in d.voxels:
				if v[4] != "grip" and (v[3] == "bronze" or v[3] == "iron"):
					n += 1
			return 15 + int(round(n * 1.5))
		"venom": return 60
		"fire": return 75
		"frost": return 65
	return 0

static func can_upgrade(id: String, d) -> bool:
	if not (d is Dictionary) or d.get("kind", "weapon") == "shield":
		return id == "temper" and d is Dictionary and upgrade_price("temper", d) > 15
	if COATINGS.has(id):
		# Venom wants an edge or a point to go in by; fire and frost go on anything that hits.
		if d.get("imbue", "") == id or d.get("shoots", false):
			return false
		if id == "venom":
			return d.voxels.any(func(v): return v[4] == "edge" or v[4] == "point")
		return true
	match id:
		"whetstone":
			var edged := false
			for v in d.voxels:
				if v[4] == "edge" or v[4] == "point":
					edged = true
			return edged and float(d.get("sharpness", 0.0)) < 1.0
		"temper":
			return upgrade_price("temper", d) > 15
	return false

static func upgrade(a: Dictionary, side: String, id: String) -> Dictionary:
	var arms := sanitize(a)
	var slot := "main" if side == "R" else "off"
	var d = arms[slot]
	if not can_upgrade(id, d):
		return {"error": "That will not go on this one"}
	var cost := upgrade_price(id, d)
	match id:
		"whetstone":
			d.sharpness = minf(1.0, snappedf(float(d.get("sharpness", 0.0)) + 0.1, 0.01))
		"temper":
			d = Match.temper(d, "steel")
			arms[slot] = d
		"venom", "fire", "frost":
			d.imbue = id
	return {"arms": arms, "cost": cost}

## The loadout a fight is built from, with the chips marked to knock off.
static func loadout(a: Dictionary) -> Dictionary:
	var arms := sanitize(a)
	return {"main": arms.main, "off": arms.off, "worn": arms.wear.duplicate(true)}
