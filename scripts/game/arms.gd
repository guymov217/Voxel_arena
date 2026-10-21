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

## A sharp voxel (an edge or a point) costs the more the keener it is honed: the smith's hours
## at the stone, nothing for a blunt one.
const SHARP_PRICE := 3.0

## (Fractions of a denarius a block: the honing of a whole blade is summed, then rounded once, so
## every step of the sharpness moves the price, and no keener setting is ever the cheaper.)
static func sharp_cost(job: String, sharpness: float) -> float:
	return SHARP_PRICE * sharpness * sharpness if job == "edge" or job == "point" else 0.0

static func sharp_price(job: String, sharpness: float) -> int:
	return roundi(sharp_cost(job, sharpness))

## The honing of every Cut and Stab block of `jobs` (job names) at `sharpness`, in denarii.
static func honing(jobs: Array, sharpness: float) -> int:
	var h := 0.0
	for j in jobs:
		h += sharp_cost(String(j), sharpness)
	return roundi(h)

static func value(d) -> int:
	if not (d is Dictionary):
		return 0
	var s := 0
	var jobs := []
	var sh := clampf(float(d.get("sharpness", 0.8)), 0.0, 1.0)
	for v in d.get("voxels", []):
		s += voxel_price(v[3])
		if v.size() > 4:
			jobs.append(v[4])
	return s + honing(jobs, sh)

## Weapons kept aside for now (still in the data, out of the shop, the lists, the lottery
## and the drops from the stands): the chain weapons and the crossbow.
const SHELVED := ["flail", "imperialFlail", "meteorHammer", "crossbow", "whip"]

static func shelved(key: String) -> bool:
	return SHELVED.has(key)

## What kind of weapon a design is, read off its voxels: "blade" (a sword or a dagger: a long
## edge down its length), "axe" (a short edge on a head), "spear" (a point on a long shaft),
## "blunt" (no edge: a hammer, a mace, a club), "shield", "bow", "crossbow", "chain" or
## "other". The smith reshapes a weapon only within its kind.
static func family(d) -> String:
	if not (d is Dictionary) or not (d.get("voxels") is Array) or d.voxels.is_empty():
		return ""
	if d.get("kind", "weapon") == "shield":
		return "shield"
	match String(d.get("shoots", "")):
		"arrow":
			return "bow"
		"bolt":
			return "crossbow"
		"":
			pass
		_:
			return "other"
	if d.get("chain") is Dictionary:
		return "chain"
	var lo := 1 << 20
	var hi := -lo
	var elo := lo
	var ehi := hi
	var edges := 0
	var points := 0
	var narrow := true
	var edge_x := 0.0
	var grip_x := 0.0
	var grips := 0
	for v in d.voxels:
		var y := int(v[1])
		lo = mini(lo, y)
		hi = maxi(hi, y)
		if absi(int(v[0])) > 1:
			narrow = false
		match v[4]:
			"edge":
				edges += 1
				edge_x += float(v[0])
				elo = mini(elo, y)
				ehi = maxi(ehi, y)
			"point":
				points += 1
			"grip":
				grips += 1
				grip_x += float(v[0])
	var length := hi - lo + 1
	if edges == 0:
		return "spear" if points > 0 and narrow and length >= 25 else "blunt"
	# An axe's edge stands off the haft, on one side of it.
	if absf(edge_x / edges - (grip_x / grips if grips > 0 else 0.0)) >= 2.0:
		return "axe"
	# A spear's head is at the far end of a long shaft; a sword's edge runs from near the guard.
	if float(elo - lo) >= 0.6 * float(length):
		return "spear"
	return "blade"

## What the smith's base cards make, by kind.
const BASE_FAMILY := {"gladius": "blade", "spatha": "blade", "dagger": "blade", "axe": "axe", "throwingAxe": "axe",
	"hammer": "blunt", "mace": "blunt", "spear": "spear", "javelin": "spear", "shield": "shield", "bow": "bow"}

## Whether it has an edge to hone at all: a hammer or a mace (spikes or not) is not sharpened.
static func sharpenable(d) -> bool:
	return ["blade", "axe", "spear"].has(family(d))

static func bases() -> Array:
	return Data.shop.get("bases", []).filter(func(b): return not SHELVED.has(String(b.key)))

## A weapon's price at the smith: what the list says, or what it can do in a fight if more.
static func base_price(b: Dictionary) -> int:
	return maxi(int(b.get("price", 0)), power_price(Data.preset(String(b.key))))

static func base(key: String) -> Dictionary:
	for b in bases():
		if b.key == key:
			return b
	return {}

## Buys a base at the smith. It goes into a free hand: the right one if it holds only the
## training stick, else the left (a shield only ever goes on the left; a two-handed weapon
## takes both). With no hand free the buyer picks which weapon the smith takes in part
## exchange (`sell` "R" or "L"); without that pick, when there is a choice, the answer is
## {"choose": [sides], "price"}. What is sold fetches half its worth.
static func buy(a: Dictionary, key: String, sell := "") -> Dictionary:
	var b := base(key)
	if b.is_empty():
		return {"error": "The smith has no such thing"}
	return _acquire(a, Data.preset(key).duplicate(true), base_price(b), b.slot == "off", sell)

## Has a design from the player's own gallery made at the smith, at what it is worth.
static func buy_design(a: Dictionary, d: Dictionary, sell := "", price := -1) -> Dictionary:
	if not (d.get("voxels") is Array) or d.voxels.is_empty() or d.voxels.size() > ForgeLib.MAX_VOXELS or not ForgeLib.compute_stats(d).hasGrip:
		return {"error": "The smith cannot make that"}
	var nd := d.duplicate(true)
	nd.erase("imbue")
	nd.erase("oddity")
	return _acquire(a, nd, design_price(nd) if price < 0 else price, nd.get("kind", "weapon") == "shield", sell)

# ---------- Vulcanus's oddities: a few one-off weapons each bout ----------

const ODDITY_NAMES := ["The Widowmaker", "Old Grudge", "Sorrow", "The Butcher's Apology", "Bonebiter", "Mercy", "The Last Word", "Thunderjaw", "Lady Ruin", "The Emperor's Itch", "Gutspiller", "Kindly Death"]
const ODDITY_MARKUP := 1.3

## The odd weapons on the smith's stall for `stage` of the campaign run `run_seed`: the same
## on every visit through the bout, other ones the next bout and other ones every run. Later
## bouts bring better stuff: steel for iron, lead in the heads, and now and then gem sockets.
static func oddities(run_seed: int, stage: int, n := 3) -> Array:
	var out := []
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run_seed, stage, i])
		var d := ForgeLib.surprise_weapon(rng)
		var better := clampf(0.15 + 0.07 * stage, 0.15, 0.85)
		var gem_p := clampf(0.04 * (stage - 1), 0.0, 0.5)
		var gem: String = ["ruby", "sapphire", "emerald"][rng.randi_range(0, 2)]
		var head := []
		for v in d.voxels:
			if v[4] != "grip" and v[3] != "wood":
				head.append(v)
		for v in head:
			if v[3] == "iron" and rng.randf() < better:
				v[3] = "steel"
			elif v[3] == "stone" and v[4] == "blunt" and rng.randf() < better * 0.5:
				v[3] = "lead"
		var rare := rng.randf() < gem_p and not head.is_empty()
		if rare:
			var k := mini(head.size(), rng.randi_range(3, 4 + stage))
			for j in k:
				head[rng.randi_range(0, head.size() - 1)][3] = gem
			d.name = ODDITY_NAMES[rng.randi_range(0, ODDITY_NAMES.size() - 1)]
		ForgeLib.one_piece(d)   # (the gems and swaps change no shape, but be sure: nothing in the air)
		# Never more than a man can lift: two hands for a heavy one, and the lead of a head that
		# is too much even so goes back to stone.
		if ForgeLib.too_heavy(d) != "":
			d.twoHanded = true
		if ForgeLib.too_heavy(d) != "":
			for v in d.voxels:
				if v[3] == "lead":
					v[3] = "stone"
		d.erase("stats")
		d["oddity"] = {"stage": stage, "i": i, "rare": rare}
		out.append(d)
	return out

## What an oddity costs: what it is worth to make, and a little more for being one of a kind.
static func oddity_price(d: Dictionary) -> int:
	var nd := d.duplicate()
	nd.erase("oddity")
	return int(ceil(design_price(nd) * ODDITY_MARKUP))

## What the smith asks to make a design: its stuff, block by block, and his labour on it, or
## what it can do in a fight, whichever is more (lead is cheap stuff, a lead head is not a cheap
## weapon).
static func design_price(d: Dictionary) -> int:
	# (The grip block a new weapon starts from is the smith's own: an empty anvil costs nothing.)
	return maxi(maxi(0, value(d) - 1) + labour(d), power_price(d))

## The smith's work on a design, by how much there is of it: a handful of blocks is next to
## nothing (a blank anvil cost a flat 15 before a block was laid), a whole weapon the full fee.
static func labour(d: Dictionary) -> int:
	var n: int = d.get("voxels", []).size()
	return mini(15, n / 4) + n / 10

const POWER_PRICE := 20.0
const BODY_KG := 5.0   # about what a head or a limb weighs: the most of a weapon a blow can use

## The worth of a design by its harm: the blow it lands (its weight at the tip, as much of it
## as a body part can take, times the tip's speed), sharpened or hardened into a wound, plus
## its gems and its powder. Bows and shields go by their stuff.
static func power_price(d: Dictionary) -> int:
	if d.get("voxels", []).is_empty() or d.get("kind", "weapon") == "shield" or d.get("shoots", "") != "":
		return 0
	var st := ForgeLib.compute_stats(d)
	var reach := maxf(0.2, float(st.reach))
	var meff := float(st.inertia) / (reach * reach)
	var blow := meff * BODY_KG / (meff + BODY_KG) * float(st.swingSpeed) * reach
	var harm := blow * (0.5 + float(ForgeLib.three_bars(st).damage))
	var extra := 0
	for v in d.voxels:
		match String(v[3]):
			"ruby", "sapphire", "emerald": extra += 30
			"explosive": extra += 10
	return int(round(POWER_PRICE * harm)) + mini(15, d.voxels.size() / 4) + extra

static func _acquire(a: Dictionary, d: Dictionary, price: int, off_hand: bool, sell: String) -> Dictionary:
	var arms := sanitize(a)
	var two := bool(d.get("twoHanded", false))
	var held_two := bool(arms.main.get("twoHanded", false)) and not is_stick(arms.main)
	var r_free := is_stick(arms.main)
	var l_free: bool = arms.off == null and not held_two
	var side := ""
	var sold: Array = []
	if two:
		side = "R"
		sold = ["R", "L"]
	elif off_hand:
		side = "L"
		if not l_free:
			sold = ["R"] if held_two else ["L"]
	elif r_free:
		side = "R"
	elif l_free:
		side = "L"
	else:
		var options: Array = ["R"] if held_two else ["R", "L"]
		if options.size() > 1 and not options.has(sell):
			return {"choose": options, "price": price}
		side = sell if options.has(sell) else options[0]
		sold = [side]
	var trade_in := 0
	for s_ in sold:
		var old = arms.main if s_ == "R" else arms.off
		if old and not is_stick(old):
			trade_in += int(value(old) * 0.5)
		if s_ == "R":
			arms.main = empty().main
		else:
			arms.off = null
		arms.wear[s_] = []
	if side == "R":
		arms.main = d
	else:
		arms.off = d
	arms.wear[side] = []
	if two:
		arms.off = null
	return {"arms": arms, "cost": price - trade_in, "trade_in": trade_in, "side": side, "sold": sold}

## The training stick everyone starts with: a hand that holds it is as good as free.
static func is_stick(d) -> bool:
	return d is Dictionary and String(d.get("name", "")) == String(Data.shop.get("stick", {}).get("name", "Training Stick"))

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
		# No longer sold: fire, frost and venom come from gems set in the forge (ruby, sapphire,
		# emerald). A weapon coated before keeps its coating.
		return false
	match id:
		"whetstone":
			return sharpenable(d) and float(d.get("sharpness", 0.0)) < 1.0
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
