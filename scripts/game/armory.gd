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

## What a piece weighs on a man (kg): a plate's worth of its material for every cell it covers.
const KG_PER_CELL := 0.9   # × the material's mass (materials.json): a steel lorica ~13 kg, a jerkin ~1.5
static func kg(id: String) -> float:
	var a: Dictionary = Data.armor.get(id, {})
	var n := 0
	for part in a.get("parts", {}):
		n += (a.parts[part] as Array).size()
	return n * float(Data.material(String(a.get("mat", "iron"))).get("mass", 0.03)) * KG_PER_CELL

## How well a piece keeps a blow out (0..1), by its material's hardness.
static func protection(id: String) -> float:
	return float(Data.material(String(Data.armor.get(id, {}).get("mat", "iron"))).get("hardness", 0.6))

## What the weight of armour worn does: breath spent sprinting and swinging is multiplied by
## `breath`, the pace by `pace`. Light leather hardly shows; a full kit of steel tells.
static func burden(kg_worn: float) -> Dictionary:
	return {"breath": 1.0 + maxf(0.0, kg_worn) / 35.0, "pace": 1.0 - clampf((kg_worn - 6.0) / 100.0, 0.0, 0.3)}

static func price(id: String) -> int:
	if custom(id):
		return design_price(Data.armor[id])
	for r in SHOP:
		if r[0] == id:
			return int(r[1])
	return 0

static func sold(id: String) -> bool:
	return price(id) > 0

## A piece the player designed at the armourer's bench (id "custom_..."), known to Data.armor.
static func custom(id: String) -> bool:
	return id.begins_with("custom_") and Data.armor.has(id)

# ---------- The armourer's bench: pieces the player designs ----------

## What a designed piece may be made of: from soft and light to hard and heavy.
const BENCH_MATS := ["leather", "bone", "bronze", "iron", "steel", "gold"]
## Where it goes: a part, or a pair of them done alike.
const REGIONS := {
	"head": {"label": "Head", "parts": ["head"]},
	"torso": {"label": "Body", "parts": ["torso"]},
	"upperArms": {"label": "Upper arms", "parts": ["upperArmR", "upperArmL"]},
	"forearms": {"label": "Forearms", "parts": ["forearmR", "forearmL"]},
	"thighs": {"label": "Thighs", "parts": ["thighR", "thighL"]},
	"shins": {"label": "Shins", "parts": ["shinR", "shinL"]},
}
const DESIGN_MAX_CELLS := 2400
## How far out from the body part plates may stand (cells, 4 cm each): a crest, a broad
## pauldron, a skirt of plates. Every plate must still touch the part or another plate; what
## it costs is its weight (breath and pace).
const DESIGN_OUT := 6

static func _dims(part: String) -> Array:
	for p in Data.body_parts:
		if String(p.name) == part:
			return p.dims
	return [4, 4, 4]

## A piece from the bench's choices: `region` (REGIONS), `mat`, the rows covered from `y0` to
## `y1` (0 the bottom of the part, 1 its top), all round or the front and sides only, and the
## top capped (a helmet's crown, a lorica's shoulders).
static func design_piece(region: String, mat: String, y0: float, y1: float, front_only: bool, cap: bool, name := "") -> Dictionary:
	var reg: Dictionary = REGIONS.get(region, REGIONS.torso)
	var parts := {}
	for part in reg.parts:
		var d := _dims(part)
		var top := int(d[1]) - 1
		var a := clampi(int(round(minf(y0, y1) * top)), 0, top)
		var b := clampi(int(round(maxf(y0, y1) * top)), 0, top)
		var cells := _wrap(d, a, b, "front" if front_only else "all")
		if cap and b == top:
			cells += _cap(d, 1 if part == "torso" else 0)
		parts[part] = cells
	var nm := name.strip_edges().substr(0, 24)
	if nm == "":
		nm = "%s %s" % [mat.capitalize(), String(reg.label).to_lower()]
	return {"name": nm, "mat": mat if BENCH_MATS.has(mat) else "iron", "color": 0x8c939b if mat == "steel" else null, "parts": parts}

static func design_cells(def: Dictionary) -> int:
	var n := 0
	for part in def.get("parts", {}):
		n += (def.parts[part] as Array).size()
	return n

## What the smith asks for making it: its plates, by the price of the stuff.
static func design_price(def: Dictionary) -> int:
	return 10 + int(ceil(design_cells(def) * Arms.voxel_price(String(def.get("mat", "iron"))) * 0.5))

static func design_kg(def: Dictionary) -> float:
	return design_cells(def) * float(Data.material(String(def.get("mat", "iron"))).get("mass", 0.03)) * KG_PER_CELL

## Its id: from what it is, so the same piece is the same id on every machine.
static func design_id(def: Dictionary) -> String:
	return "custom_%d" % absi(hash(JSON.stringify([def.get("mat"), def.get("parts")])))

## A design as sent by someone else (or read from a save), made safe: known stuff, known parts,
## cells round the part only, not too many. Null if it is not a piece at all.
static func clean_design(def) -> Variant:
	if not (def is Dictionary) or not (def.get("parts") is Dictionary) or not BENCH_MATS.has(String(def.get("mat", ""))):
		return null
	var allowed := []
	for r in REGIONS.values():
		allowed += r.parts
	var parts := {}
	var n := 0
	for part in def.parts:
		if not allowed.has(String(part)) or not (def.parts[part] is Array):
			continue
		var d := _dims(String(part))
		var cells := []
		for c in def.parts[part]:
			if c is Array and c.size() >= 3 and n < DESIGN_MAX_CELLS:
				var x := int(c[0])
				var y := int(c[1])
				var z := int(c[2])
				if x >= -DESIGN_OUT and x < int(d[0]) + DESIGN_OUT and y >= -DESIGN_OUT and y < int(d[1]) + DESIGN_OUT and z >= -DESIGN_OUT and z < int(d[2]) + DESIGN_OUT:
					# a 4th number is the cell's paint (0xRRGGBB); a plain cell has none
					if c.size() > 3 and (c[3] is int or c[3] is float) and int(c[3]) >= 0:
						cells.append([x, y, z, int(c[3]) & 0xffffff])
					else:
						cells.append([x, y, z])
					n += 1
		if not cells.is_empty():
			parts[String(part)] = cells
	if parts.is_empty():
		return null
	var mat := String(def.mat)
	return {"name": String(def.get("name", "Piece")).substr(0, 24), "mat": mat, "color": 0x8c939b if mat == "steel" else null, "parts": parts}

## Makes designed pieces known (Data.armor), each under the id its content gives it: the ids
## given back, in order (an unusable design is left out).
static func register(defs) -> Array:
	var ids := []
	if not (defs is Dictionary or defs is Array):
		return ids
	for d in (defs.values() if defs is Dictionary else defs):
		var c = clean_design(d)
		if c == null:
			continue
		var id := design_id(c)
		Data.armor[id] = c
		ids.append(id)
	return ids

## The designs of the pieces in `ids` that are the player's own (to send with them).
static func defs_of(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		if custom(String(id)):
			out[id] = Data.armor[id]
	return out

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
		if id is String and (sold(id) or custom(id)) and Data.armor.has(id) and not out.has(id) and not out.any(func(o): return clashes(o, id)):
			out.append(id)
	return out.slice(0, 10)

# ---------- Wear: the plates a bout knocked off stay off until the smith mends the piece ----------

## {id: {part: [cell index, ...]}}, made safe against what is worn: known pieces, known parts,
## cells the piece has, each once.
static func clean_wear(w, worn: Array) -> Dictionary:
	var out := {}
	if not (w is Dictionary):
		return out
	for id in w:
		if not (id is String) or not worn.has(id) or not Data.armor.has(id) or not (w[id] is Dictionary):
			continue
		var parts: Dictionary = Data.armor[id].get("parts", {})
		var piece := {}
		for part in w[id]:
			if not parts.has(part) or not (w[id][part] is Array):
				continue
			var n: int = (parts[part] as Array).size()
			var idx := []
			for c in w[id][part]:
				var i := int(c)
				if i >= 0 and i < n and not idx.has(i):
					idx.append(i)
			if not idx.is_empty():
				piece[String(part)] = idx
		if not piece.is_empty():
			out[id] = piece
	return out

## The wear after a bout: what it knocked off, on top of what was off already.
static func add_wear(w: Dictionary, report, worn: Array) -> Dictionary:
	var out := clean_wear(w, worn)
	var rep := clean_wear(report, worn)
	for id in rep:
		var piece: Dictionary = out.get(id, {})
		for part in rep[id]:
			var idx: Array = piece.get(part, [])
			for i in rep[id][part]:
				if not idx.has(int(i)):
					idx.append(int(i))
			piece[part] = idx
		out[id] = piece
	return out

## How many plates of the piece are off, and how many it has.
static func plates_lost(id: String, w: Dictionary) -> Array:
	var total := 0
	for part in Data.armor.get(id, {}).get("parts", {}):
		total += (Data.armor[id].parts[part] as Array).size()
	var lost := 0
	for part in w.get(id, {}):
		lost += (w[id][part] as Array).size()
	return [lost, total]

## 1.0 whole, down to 0.0 with every plate off.
static func condition(id: String, w: Dictionary) -> float:
	var n := plates_lost(id, w)
	return 1.0 - float(n[0]) / maxf(1.0, float(n[1]))

## The smith's price for putting every plate back: half a plate's stuff for each, like a chip.
static func mend_cost(id: String, w: Dictionary) -> int:
	var lost: int = plates_lost(id, w)[0]
	if lost == 0:
		return 0
	var mat := String(Data.armor.get(id, {}).get("mat", "iron"))
	return lost * maxi(1, ceili(Arms.voxel_price(mat) * 0.5))

static func mend(w: Dictionary, id: String) -> Dictionary:
	var out := w.duplicate(true)
	var cost := mend_cost(id, w)
	out.erase(id)
	return {"wear": out, "cost": cost}

## Buying `id`: what is worn after (the clashing pieces taken off, sold back for half) and the cost.
static func buy(worn: Array, id: String) -> Dictionary:
	if not (sold(id) or custom(id)) or not Data.armor.has(id):
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
