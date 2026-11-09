class_name Masterworks
extends RefCounted
## The smith's masterworks: the one-off weapons on Vulcanus's stall (Arms.oddities), finer the
## further the campaign goes (user: dearer, more worked and stronger weapons as the stages go on,
## great swords, axes and hammers, grand and unforgettable). Six kinds, each made from its tier
## (1 fine .. 6 godforged) and the stall's own roll: a slab of a sword, a runed blade, a waved
## blade, a crescent axe, a bearded axe and a maul. Each is sized to what a man can swing at its
## tier by the fight's own measure of a weapon's weight in the hands (Fighter: the load on the
## arm); the higher the tier, the bigger, the keener, and the more gold and gems on it (fire,
## frost, venom: Match._gems). The same in a party as alone: the stall is the man's own run and bout.

const TIERS := ["Fine", "Masterwork", "Heroic", "Fabled", "Mythic", "Godforged"]
## The bout each tier comes in at: the stall's middle weapon is of it, one a tier under, one above
## (a jewel to save for).
const TIER_AT := [1, 4, 9, 17, 29, 45]
## The most load a tier's weapon may put on the arms (Fighter: (0.22 mass + 0.9 inertia) / 1.7, two
## hands): the zweihander is 1.8, the warhammer 3.7. The later tiers come when a man has trained
## his strength (up to a third more: Training), and so handle as those do.
const LOAD := [2.2, 2.8, 3.4, 4.0, 4.8, 5.6]
## What a tier asks over what the weapon is worth (an oddity asked 1.3).
const MARKUP := [1.3, 1.4, 1.5, 1.65, 1.85, 2.1]
## And within what (denarii): each tier dearer than the one under it, whatever it is made of (a
## light axe of the finest tier was cheaper than a heavy blade a tier under it).
const PRICE := [[250, 450], [450, 800], [800, 1400], [1400, 2400], [2400, 4000], [4000, 6500]]
## Its colour on the stall.
const COLOURS := [Color(0.72, 0.5, 0.28), Color(0.78, 0.82, 0.88), Color(0.95, 0.78, 0.3), Color(1.0, 0.56, 0.18), Color(0.74, 0.46, 0.98), Color(0.98, 0.26, 0.3)]

## Each kind: the first tier it comes in at, its length [shortest, at tier 0, more a tier] (voxels:
## the blade, or the haft above the grip), the gems and the trims it may have, its names.
const KINDS := {
	"slab": {"first": 3, "len": [26, 30, 3], "gems": ["ruby"], "trims": ["iron"],
		"names": ["The Ironwall", "Gravewarden", "The Black Slab", "Beastbane", "Mountainheart", "The Last Rampart"]},
	"rune": {"first": 1, "len": [24, 30, 4], "gems": ["sapphire", "sapphire", "emerald", "ruby"], "trims": ["bronze", "gold"],
		"names": ["Rimewarden", "Winter's Oath", "The Pale Vigil", "Hoarfang", "Wintersigil", "Stillwater"]},
	"flame": {"first": 1, "len": [24, 32, 4], "gems": ["ruby", "ruby", "sapphire"], "trims": ["bronze", "gold", "gold"],
		"names": ["Duskfall", "The Crownbreaker", "Gilded Ruin", "The Serpent's Tongue", "The Long Dusk", "Sunder"]},
	"ember": {"first": 1, "len": [16, 20, 2], "gems": ["ruby", "ruby", "emerald"], "trims": ["bronze", "gold", "gold"],
		"names": ["Ashmaker", "Cinderjaw", "The Pyre's Due", "Embersong", "Kindlecleaver", "Pyrecleaver"]},
	"reaver": {"first": 1, "len": [16, 18, 2], "gems": ["emerald", "emerald", "sapphire"], "trims": ["iron"],
		"names": ["Wyrmbite", "The Hooked Moon", "Raven's Beard", "Widowhook", "Gallowsbeard", "The Ferryman's Due"]},
	"maul": {"first": 1, "len": [14, 16, 2], "gems": ["emerald", "ruby", "sapphire"], "trims": ["bronze", "gold", "gold"],
		"names": ["The Quaking Fist", "The Mountain's Knuckle", "Tomb Gavel", "Thunderhead", "Anvilfall", "Titan's Gavel"]},
}

## The tier a bout's stall is of (its middle weapon).
static func tier_of(stage: int) -> int:
	var t := 1
	for i in TIER_AT.size():
		if stage >= int(TIER_AT[i]):
			t = i + 1
	return t

## The stall for `stage` of the campaign run `run_seed`: the same on every visit through the bout,
## other ones the next bout and every run; never two of a kind on it.
static func stall(run_seed: int, stage: int, n := 3) -> Array:
	var base := tier_of(stage)
	var used := []
	var out := []
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run_seed, stage, i])
		var t := clampi(base - 1 + i, 1, TIERS.size())
		var kinds: Array = KINDS.keys().filter(func(k): return int(KINDS[k].first) <= t and not used.has(k))
		if kinds.is_empty():
			kinds = KINDS.keys().filter(func(k): return int(KINDS[k].first) <= t)
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		used.append(kind)
		var d := make(kind, t, rng)
		d["oddity"] = {"stage": stage, "i": i, "rare": t >= 3, "tier": t, "kind": kind}
		out.append(d)
	return out

## The load a weapon puts on a man's arms, held in two hands (Fighter's own measure).
static func load_of(st: Dictionary) -> float:
	return (0.22 * float(st.mass) + 0.9 * float(st.inertia)) / 1.7

## One masterwork of `kind` at `tier` (no lower than the kind's first): as long as its tier allows,
## made shorter (then slighter) until a man can swing it within the tier's load.
static func make(kind: String, tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var t := clampi(maxi(tier, int(k.first)), 1, TIERS.size())
	var gems: Array = k.gems
	var trims: Array = k.trims
	var o := {
		"gem": gems[rng.randi_range(0, gems.size() - 1)],
		"trim": trims[rng.randi_range(0, trims.size() - 1)] if t >= 3 else ("bronze" if trims.has("bronze") else trims[0]),
		"studs": rng.randf() < 0.6,
		# (A man's own: a hand's width more or less on the grip, a broader guard or head.)
		"gj": rng.randi_range(0, 1),
		"wide": rng.randi_range(0, 1),
	}
	var names: Array = k.names
	var nm: String = names[rng.randi_range(0, names.size() - 1)]
	var lo: int = k.len[0]
	var hi: int = int(k.len[1]) + int(k.len[2]) * t - rng.randi_range(0, 2)
	var budget: float = LOAD[t - 1] + (0.6 if kind == "slab" else 0.0)
	var d := {}
	for sh in 3:
		var L := hi
		while L >= lo:
			d = _design(_build(kind, t, L, o, sh), nm)
			var st := ForgeLib.compute_stats(d)
			if load_of(st) <= budget and ForgeLib.too_heavy(d, st) == "":
				ForgeLib.one_piece(d)
				return d
			L -= 1
	ForgeLib.one_piece(d)
	return d

## The tier's name and its numeral, for the stall ("Heroic · III").
static func title(t: int) -> String:
	t = clampi(t, 1, TIERS.size())
	return "%s · %s" % [Loc.t(TIERS[t - 1]), ["I", "II", "III", "IV", "V", "VI"][t - 1]]

static func colour(t: int) -> Color:
	return COLOURS[clampi(t, 1, COLOURS.size()) - 1]

# ---------- Building ----------

## A design in the making: cells (Vector3i -> [stuff, job]), those to stay blunt whatever their
## place (a gem or a gold line set into an edge), and how keen it is honed.
class Build:
	extends RefCounted
	var cells := {}
	var blunt := {}
	var sharp := 0.8

	func put(x: int, y: int, z: int, mat: String, job := "blunt") -> void:
		cells[Vector3i(x, y, z)] = [mat, job]

	func keep(x: int, y: int, z: int, mat: String) -> void:
		put(x, y, z, mat)
		blunt[Vector3i(x, y, z)] = true

	func box(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, mat: String) -> void:
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				for z in range(z0, z1 + 1):
					put(x, y, z, mat)

	func has(x: int, y: int, z: int) -> bool:
		return cells.has(Vector3i(x, y, z))

	func grip(n: int) -> void:
		for y in n:
			put(0, y, 0, "leather", "grip")

static func _design(b: Build, nm: String) -> Dictionary:
	var vox := []
	for c in b.cells:
		var e: Array = b.cells[c]
		vox.append([c.x, c.y, c.z, e[0], e[1]])
	# (Named in the player's language, as the stall's oddities were.)
	var d := {"name": Loc.t(nm), "kind": "weapon", "twoHanded": true, "sharpness": minf(1.0, snappedf(b.sharp, 0.01)), "voxels": vox}
	ForgeLib.auto_sharpen(d)
	for v in d.voxels:
		if b.blunt.has(Vector3i(v[0], v[1], v[2])):
			v[4] = "blunt"
	return d

static func _build(kind: String, t: int, L: int, o: Dictionary, sh: int) -> Build:
	match kind:
		"slab":
			return _slab(t, L, o, sh)
		"rune":
			return _rune(t, L, o, sh)
		"flame":
			return _flame(t, L, o, sh)
		"ember":
			return _ember(t, L, o)
		"reaver":
			return _reaver(t, L, o)
	return _maul(t, L, o, sh)

## The slab: a sword too big to be called a sword. Dark iron as wide as a man's thigh, squared off to
## a short point, the edges honed bright; a heavy bar of a guard, rivets at its root, a lead
## counterweight in the pommel so that it can be lifted at all; gold rivets and a ruby from tier 5,
## the root of the blade bound in leather for a second grip at 6.
static func _slab(t: int, L: int, o: Dictionary, sh: int) -> Build:
	var b := Build.new()
	var G := 12 + (1 if t >= 5 else 0) + int(o.gj)
	b.grip(G)
	var hw := maxi(2, (2 if t <= 4 else 3) - sh)
	var gy := G
	var gw := hw + 2 + (1 if t >= 5 else 0) + int(o.wide)
	b.box(-gw, gw, gy, gy, 0, 0, "iron")
	b.box(-gw + 1, gw - 1, gy, gy, -1, 1, "iron")
	b.box(-hw, hw, gy + 1, gy + 1, -1, 1, "iron")
	var b0 := gy + 2
	var top := b0 + L - 1
	for y in range(b0, top + 1):
		var k := top - y
		var w := hw if k > hw else maxi(0, k - 1 + (1 if hw == 2 else 0))
		w = mini(hw, w)
		for x in range(-w, w + 1):
			b.put(x, y, 0, "steel" if absi(x) == w and w >= 1 else "iron")
		# The root of it thick; the rest one hand's breadth of iron.
		if y < b0 + 4:
			for x in range(-hw + 1, hw):
				b.put(x, y, 1, "iron")
				b.put(x, y, -1, "iron")
	var stud := "gold" if t >= 5 else "steel"
	var sz := 2 if o.studs else 1
	for yy in [b0 + 1, b0 + 3]:
		for x in [-(hw - 1), hw - 1]:
			b.put(x, yy, sz, stud)
			b.put(x, yy, -sz, stud)
	b.box(-1, 1, -3, -1, -1, 1, "iron")
	b.box(0, 0, -3, -1, 0, 0, "lead")
	if t >= 5:
		b.box(-2, 2, -2, -2, 0, 0, "iron")
		b.put(0, -4, 0, "iron")
		b.put(0, -2, 2, o.gem)
		b.put(0, -2, -2, o.gem)
	if t >= 6:
		for y in range(b0 + 4, b0 + 7):
			for x in range(-hw + 1, hw):
				b.put(x, y, 1, "leather")
				b.put(x, y, -1, "leather")
	b.sharp = 0.7 + 0.05 * t
	return b

## The runed blade: broad at the guard and a long taper to its point, gems set like runes down its
## spine on both faces (tier 3+, closer together each tier); the guard's arms swept up into horns,
## barbs under them from tier 5; a gem in a cage at the pommel, crowned from tier 5.
static func _rune(t: int, L: int, o: Dictionary, sh: int) -> Build:
	var b := Build.new()
	var gem: String = o.gem
	var trim: String = o.trim
	var G := 10 + (1 if t >= 4 else 0) + int(o.gj)
	b.grip(G)
	var hw0 := maxi(1, int([1, 2, 2, 3, 3, 3][t - 1]) - sh)
	var gy := G
	var gw := hw0 + 3 + (1 if t >= 4 else 0) + int(o.wide)
	b.box(-gw, gw, gy, gy, 0, 0, "steel")
	b.box(-hw0, hw0, gy, gy, -1, 1, "steel")
	var horn := 2 + (1 if t >= 3 else 0) + (1 if t >= 5 else 0)
	for s in [-1, 1]:
		for k in range(1, horn + 1):
			b.put(s * (gw + (1 if k >= horn - 1 and t >= 4 else 0)), gy + k, 0, "steel")
			if k >= 2:
				b.put(s * gw, gy + k - 1, 0, "steel")
		if t >= 3:
			b.put(s * (gw - 1), gy, 1, gem)
			b.put(s * (gw - 1), gy, -1, gem)
		if t >= 5:
			b.put(s * gw, gy - 1, 0, "steel")
			b.put(s * gw, gy - 2, 0, "steel")
	b.box(-1, 1, gy + 1, gy + 1, -1, 1, trim)
	if t >= 4:
		b.put(0, gy + 1, 2, gem)
		b.put(0, gy + 1, -2, gem)
	var b0 := gy + 2
	var top := b0 + L - 1
	var step: int = [0, 0, 5, 4, 3, 2][t - 1]
	for y in range(b0, top + 1):
		var f := float(y - b0) / maxf(1.0, float(L - 1))
		var w := roundi(hw0 - (hw0 - 1) * pow(f, 1.3))
		var k := top - y
		if k <= 1:
			w = 0
		elif k <= 4:
			w = mini(w, 1)
		for x in range(-w, w + 1):
			b.put(x, y, 0, "steel")
		if k >= 5 and w >= 1:
			var on := t >= 3 and (y - b0) % step == 1
			var m := gem if on else ("iron" if t >= 5 else "steel")
			b.put(0, y, 1, m)
			b.put(0, y, -1, m)
	b.box(-1, 1, -2, -1, -1, 1, "steel")
	b.put(0, -3, 0, "steel")
	if t >= 3:
		for c in [Vector3i(0, -2, 1), Vector3i(0, -2, -1), Vector3i(1, -2, 0), Vector3i(-1, -2, 0)]:
			b.put(c.x, c.y, c.z, gem)
		b.put(0, -2, 0, "steel")
	if t >= 5:
		b.box(-2, 2, -1, -1, 0, 0, trim)
		for c in [Vector3i(2, -2, 0), Vector3i(-2, -2, 0), Vector3i(0, -2, 2), Vector3i(0, -2, -2), Vector3i(2, -3, 0), Vector3i(-2, -3, 0)]:
			b.put(c.x, c.y, c.z, trim)
	b.sharp = 0.75 + 0.05 * t
	return b

## The waved blade: long, waved along both edges; bright steel at first, dark iron with a gold line
## down its middle from tier 3; the guard's arms bent down toward the blade, a gem at its heart.
static func _flame(t: int, L: int, o: Dictionary, sh: int) -> Build:
	var b := Build.new()
	var gem: String = o.gem
	var trim: String = o.trim
	var G := 10 + (1 if t >= 4 else 0) + int(o.gj)
	b.grip(G)
	var hw0 := maxi(1, (1 if t <= 2 else 2) - sh)
	var gy := G
	var body := "steel" if t <= 2 else "iron"
	var gw := hw0 + 4 + (1 if t >= 4 else 0) + int(o.wide)
	var gm := trim if t >= 3 else "steel"
	b.box(-gw, gw, gy, gy, 0, 0, gm)
	b.box(-1, 1, gy, gy, -1, 1, gm)
	for s in [-1, 1]:
		b.put(s * gw, gy + 1, 0, gm)
		b.put(s * (gw - 1), gy + 2, 0, gm)
		if t >= 4:
			b.put(s * (gw - 2), gy + 3, 0, gm)
	if t >= 3:
		b.put(0, gy, 2, gem)
		b.put(0, gy, -2, gem)
	var b0 := gy + 1
	var top := b0 + L - 1
	for y in range(b0, top + 1):
		var k := top - y
		var w := hw0
		if y - b0 >= 3:
			var sn := sin(float(y - b0 - 3) * TAU / 8.0)
			w = hw0 + (1 if sn > 0.2 else 0) - (1 if sn < -0.7 and hw0 >= 2 else 0)
		if k <= 1:
			w = 0
		elif k <= 5:
			w = mini(w, 1)
		for x in range(-w, w + 1):
			b.put(x, y, 0, body)
		if k >= 6 and w >= 1:
			var m := trim if t >= 3 and (y - b0) % 2 == 0 else body
			b.put(0, y, 1, m)
			b.put(0, y, -1, m)
	b.box(-1, 1, -2, -1, -1, 1, trim if t >= 2 else "steel")
	if t >= 3:
		b.put(0, -3, 0, gem)
	b.sharp = 0.75 + 0.05 * t
	return b

## The crescent axe: a long haft banded with iron, a crescent head (two from tier 3) with a line of
## bronze or gold along its inner rim and gems set behind the edge; a spike on top.
static func _ember(t: int, L: int, o: Dictionary) -> Build:
	var b := Build.new()
	var gem: String = o.gem
	var trim: String = o.trim
	var G := 10 + int(o.gj)
	b.grip(G)
	var haft_top := G + L
	for y in range(G, haft_top + 1):
		b.put(0, y, 0, "wood")
	for y in range(G + 3, haft_top - 4, 7):
		for c in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			b.put(c.x, y, c.y, "iron")
	var yc := haft_top - 3
	var h := 3 + int(t / 2.0)
	var R := 5 + int((t + 1) / 2.0) + int(o.wide)
	var sides := [1, -1] if t >= 3 else [1]
	for s in sides:
		for x in range(1, R + 1):
			var u := float(x - 1) / maxf(1.0, float(R - 1))
			var reach_h := 1.0 + (h - 1) * pow(u, 0.75)
			for dy in range(-h, h + 1):
				if absf(dy) > reach_h + 0.5:
					continue
				if x > R - roundi(1.5 * pow(float(dy) / h, 2.0)):
					continue
				b.put(s * x, yc + dy, 0, "steel")
			if x <= 2:
				for dy in range(-1, 2):
					b.put(s * x, yc + dy, 1, "iron")
					b.put(s * x, yc + dy, -1, "iron")
		if t >= 2:
			for dy in range(-h, h + 1):
				if b.has(s * 3, yc + dy, 0):
					b.keep(s * 3, yc + dy, 0, trim)
		if t >= 3:
			var n: int = [0, 0, 1, 1, 2, 3][t - 1]
			for dy in range(-n, n + 1):
				if b.has(s * (R - 2), yc + dy, 0):
					b.keep(s * (R - 2), yc + dy, 0, gem)
	if sides.size() == 1:
		b.box(-2, -1, yc - 1, yc + 1, 0, 0, "iron")   # the back of a single head: a short hammer face
	b.box(0, 0, yc - h, yc + h, 0, 0, "iron")
	for y in range(haft_top + 1, haft_top + 3 + (2 if t >= 4 else 0)):
		b.put(0, y, 0, "steel")
	b.box(-1, 1, -1, -1, 0, 0, "iron")
	b.put(0, -2, 0, "iron" if t < 3 else "steel")
	b.sharp = 0.75 + 0.05 * t
	return b

## The bearded axe: its haft bone-white from tier 3, the beard of the blade hooked down long, a
## spike behind; gems along the cheek from tier 4.
static func _reaver(t: int, L: int, o: Dictionary) -> Build:
	var b := Build.new()
	var gem: String = o.gem
	var G := 10 + int(o.gj)
	b.grip(G)
	var haft_top := G + L
	var shaft := "bone" if t >= 3 else "wood"
	for y in range(G, haft_top + 1):
		b.put(0, y, 0, shaft)
	var h := 4 + int(t / 2.0)
	var R := 6 + int(t / 2.0) + int(o.wide)
	var yc := haft_top - 3
	for x in range(1, R + 1):
		var u := float(x - 1) / maxf(1.0, float(R - 1))
		var up := roundi(1.0 + h * 0.55 * u)
		var down := roundi(1.0 + h * 1.2 * pow(u, 1.6))
		for y in range(yc - down, yc + up + 1):
			b.put(x, y, 0, "steel" if x >= R - 1 else "iron")
		if x <= 2:
			for y in range(yc - 1, yc + 2):
				b.put(x, y, 1, "iron")
				b.put(x, y, -1, "iron")
	for x in range(1, 2 + int(t / 3.0) + 1):
		b.put(-x, yc, 0, "steel" if t >= 3 else "iron")
	if t >= 3:
		b.put(-1, yc + 1, 0, "steel")
		b.put(-1, yc - 1, 0, "steel")
	if t >= 4:
		for x in range(2, R - 1, 2):
			b.put(x, yc, 1, gem)
			b.put(x, yc, -1, gem)
	b.box(-1, 1, yc - 2, yc + 2, 0, 0, "iron")
	b.put(0, haft_top + 1, 0, "steel")
	b.put(0, haft_top + 2, 0, "steel")
	b.box(-1, 1, -1, -1, 0, 0, "iron" if t < 3 else "bone")
	b.sharp = 0.75 + 0.05 * t
	return b

## The maul: a great block of a head on a long haft, banded in bronze or gold, its striking faces
## studded, a spike on top from tier 3; gems for eyes on its cheeks at 4, a skull of bone on each
## from 5. (A shell: what is inside a head is never seen, and it is kept liftable.)
static func _maul(t: int, L: int, o: Dictionary, sh: int) -> Build:
	var b := Build.new()
	var gem: String = o.gem
	var trim: String = o.trim
	var G := 11 + int(o.gj)
	b.grip(G)
	var haft_top := G + L
	var haft := "wood" if t <= 2 else "iron"
	for y in range(G, haft_top + 1):
		b.put(0, y, 0, haft)
	var hx := maxi(2, int([2, 3, 3, 3, 4, 4][t - 1]) - sh)
	var hy := maxi(2, int([2, 2, 2, 3, 3, 3][t - 1]) + int(o.wide) - (1 if sh >= 1 else 0))
	var hz := 1 if t == 1 else 2
	var yc := haft_top + hy
	var head := "iron" if t <= 2 else "steel"
	for x in range(-hx, hx + 1):
		for y in range(yc - hy, yc + hy + 1):
			for z in range(-hz, hz + 1):
				if not (absi(x) < hx and absi(y - yc) < hy and absi(z) < hz):
					b.put(x, y, z, head)
	if t >= 2:
		for x in range(-hx, hx + 1):
			for z in range(-hz, hz + 1):
				if absi(x) == hx or absi(z) == hz:
					b.put(x, yc - hy, z, trim)
					b.put(x, yc + hy, z, trim)
		for s in [-1, 1]:
			for y in [yc - 1, yc + 1]:
				for z in [-1, 1]:
					b.put(s * (hx + 1), y, z, "steel")
	if t >= 3:
		for y in range(yc + hy + 1, yc + hy + 3 + (1 if t >= 5 else 0)):
			b.put(0, y, 0, "steel")
	if t == 4:
		for s in [-1, 1]:
			b.put(s * 2, yc, hz + 1, gem)
			b.put(s * 2, yc, -hz - 1, gem)
	if t >= 5:
		for zs in [hz + 1, -hz - 1]:
			for x in range(-2, 3):
				for y in range(yc - 2, yc + 2):
					b.put(x, y, zs, "bone")
			b.put(-1, yc, zs, gem)
			b.put(1, yc, zs, gem)
			b.put(0, yc - 1, zs, "iron")
			b.put(-2, yc - 2, zs, "iron")
			b.put(2, yc - 2, zs, "iron")
	b.box(0, 0, yc - hy, yc + hy, 0, 0, haft)   # (the haft runs up through the head)
	b.box(-1, 1, -1, -1, -1, 1, "iron")
	b.sharp = 0.8
	return b
