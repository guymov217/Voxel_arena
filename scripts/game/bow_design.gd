class_name BowDesign
## What a bow is, from the blocks it is made of (user: the forge's bow was only for looks: its height changed the draw, for the worse, and nothing else did). Held against the smith's
## Hunting Bow (the preset "bow"), which is 1.0 in everything, so the bow he sells shoots as it always did:
##  - the draw weight `weight`: how thick the limbs are (the blocks of the stave to a row: the middle of the rows) times how stiff their stuff is (STIFF);
##  - the length `length`: the bow's height over the Hunting Bow's: a longer bow is drawn farther and stores more;
##  - the arrow's speed `speed_k` and its harm `power_k` grow with the two together (the energy, weight times length), the harm faster than the speed (a blow's harm goes with the speed's square);
##  - the draw `draw_s` (seconds, at full breath) grows with the height and the square root of the weight, and the breath `breath` it costs with the weight: a stiff bow is slow and tiring to draw;
##  - the steadiness `steady`: a long bow is steadier and a stiff one shakes the hand (the scatter of a shot is divided by it).
## The string (leather behind the stave) and the grip are not the stave. Everything keeps to bounds, so a block more or less never makes an absurd bow. DOM-free (tests, tools).

const W_MIN := 0.25
const W_MAX := 3.0
const L_MIN := 0.4
const L_MAX := 2.5
const SPEED_EXP := 0.3
const POWER_EXP := 0.7
const DRAW_BASE := 0.9     # s, and
const DRAW_PER_BLOCK := 0.035   # s a block of the bow's height (the Hunting Bow's 20: 1.6 s)
## How stiff a stuff is as a limb, the Hunting Bow's wood being 1.
const STIFF := {"wood": 1.0, "bone": 0.85, "steel": 1.35, "iron": 1.2, "bronze": 1.0, "stone": 0.45, "gold": 0.35, "lead": 0.25, "leather": 0.6, "ice": 0.5,
	"ruby": 0.5, "sapphire": 0.5, "emerald": 0.5, "rubber": 0.3, "fish": 0.2, "feather": 0.05, "spring": 1.4, "glue": 0.2, "explosive": 0.3, "magnet": 0.6}
const DEFAULT_STIFF := 0.5

static var _ref_cache := {}

static func is_bow(d) -> bool:
	return d is Dictionary and str(d.get("shoots", "")) == "arrow"

## What the stave is made of, by the blocks: its height, how thick the limbs are (blocks to a row, the middle of the rows that have a limb in them), how stiff their stuff is (the mean),
## and whether there are limbs above the grip and below it.
static func measure(d: Dictionary) -> Dictionary:
	var vx: Array = d.get("voxels", [])
	var lo := 1 << 20
	var hi := -lo
	var glo := lo
	var ghi := hi
	var rows := {}
	var stiff_sum := 0.0
	var n := 0
	for v in vx:
		var y: int = int(v[1])
		lo = mini(lo, y)
		hi = maxi(hi, y)
		if String(v[4]) == "grip":
			glo = mini(glo, y)
			ghi = maxi(ghi, y)
			continue
		if String(v[3]) == "leather" and int(v[0]) < 0:
			continue   # (the string)
		rows[y] = int(rows.get(y, 0)) + 1
		stiff_sum += float(STIFF.get(String(v[3]), DEFAULT_STIFF))
		n += 1
	var counts: Array = rows.values()
	counts.sort()
	var above := false
	var below := false
	if ghi >= glo:
		for y in rows:
			if int(y) > ghi:
				above = true
			if int(y) < glo:
				below = true
	return {"span": float(hi - lo) if not vx.is_empty() else 0.0, "thick": float(counts[counts.size() / 2]) if not counts.is_empty() else 0.0, "stiff": stiff_sum / float(n) if n > 0 else 0.0, "above": above, "below": below, "limbs": n}

static func _ref() -> Dictionary:
	if _ref_cache.is_empty():
		_ref_cache = measure(Data.preset("bow"))
	return _ref_cache

## The bow a design is: see the top of the file. (1.0 and 1.6 s for the Hunting Bow.)
static func stats(d: Dictionary) -> Dictionary:
	var ref := _ref()
	var m := measure(d)
	var weight := clampf((float(m.thick) * float(m.stiff)) / (float(ref.thick) * float(ref.stiff)), W_MIN, W_MAX)
	var length := clampf(float(m.span) / float(ref.span), L_MIN, L_MAX)
	var energy := weight * length
	return {
		"weight": weight, "length": length, "span": m.span, "thick": m.thick, "stiff": m.stiff, "above": m.above, "below": m.below,
		"speed_k": clampf(pow(energy, SPEED_EXP), 0.7, 1.35),
		"power_k": clampf(pow(energy, POWER_EXP), 0.5, 1.6),
		"draw_s": clampf((DRAW_BASE + float(m.span) * DRAW_PER_BLOCK) * sqrt(weight), 0.5, 6.0),
		"breath": weight,
		"steady": clampf(pow(length, 0.4) / pow(weight, 0.25), 0.7, 1.3),
	}

## The forge's bars for a bow (each 0 to 1): how fast it is drawn, how hard its arrow strikes, how fast the arrow flies, how steady the hand keeps.
static func bars(b: Dictionary) -> Dictionary:
	return {
		"speed": clampf(1.0 - (float(b.draw_s) - DRAW_BASE) / 3.6, 0.0, 1.0),
		"damage": clampf(float(b.power_k) / 1.6, 0.0, 1.0),
		"reach": clampf(float(b.speed_k) / 1.35, 0.0, 1.0),
		"armour": clampf(float(b.steady) / 1.3, 0.0, 1.0),
	}

## The figures the forge counts a change on (per cent up or down): the same four in a bow's own words.
static func figures(b: Dictionary) -> Dictionary:
	return {"speed": 1.0 / float(b.draw_s), "damage": float(b.power_k), "reach": float(b.speed_k), "armour": float(b.steady)}
