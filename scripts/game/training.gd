class_name Training
## The trainer's yard (the ludus): what a gladiator's body can be taught between bouts, bought
## session by session with denarii and nothing else (the bouts teach nothing by themselves).
## Six abilities, each a few per cent on one thing the simulation already does: the arm's
## drive, the blow's weight, the breath, the hide, the blood and the footing. A session is
## STEP per cent; no ability goes past the stage's cap (a per cent a bout) or its own; the
## price climbs with every session; a death takes it all, as it takes the purse and the arms.

const ABILITIES := {
	"vis": {"name": "Vis", "title": "Strength", "max": 16, "mod": "strength", "sign": 1,
		"desc": "The arm's drive: a heavy weapon swung as fast as a light one, for less breath, held steadier."},
	"ictus": {"name": "Ictus", "title": "Blow", "max": 16, "mod": "blow", "sign": 1,
		"desc": "Weight behind the blow: every hit that lands, lands harder."},
	"spiritus": {"name": "Spiritus", "title": "Wind", "max": 20, "mod": "wind", "sign": 1,
		"desc": "More breath in the chest, and back sooner after a sprint or a flurry."},
	"corium": {"name": "Corium", "title": "Hide", "max": 24, "mod": "toughness", "sign": 1,
		"desc": "A thick hide: cuts bite less, bones hold, limbs come off harder."},
	"sanguis": {"name": "Sanguis", "title": "Blood", "max": 24, "mod": "bleed", "sign": -1,
		"desc": "Blood that clots: every wound bleeds slower."},
	"firmitas": {"name": "Firmitas", "title": "Footing", "max": 24, "mod": "footing", "sign": 1,
		"desc": "Hard to knock down, hard to stagger, and up again sooner."},
}
const ORDER := ["vis", "ictus", "spiritus", "corium", "sanguis", "firmitas"]
const STEP := 2           # per cent a session
const CAP_PER_STAGE := 1  # per cent a bout: no buying a champion's body in the first week
const DEMO_MAX := 4       # the demo's trainer teaches two sessions of each

## {ability: per cent}, made safe: known abilities, whole steps, within the ability's own limit.
static func sanitize(raw) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for id in raw:
		if ABILITIES.has(id) and (raw[id] is int or raw[id] is float):
			var v := clampi(int(raw[id]), 0, int(ABILITIES[id].max))
			v -= v % STEP
			if v > 0:
				out[id] = v
	return out

static func level(stats: Dictionary, id: String) -> int:
	return int(stats.get(id, 0))

## The most an ability may reach before bout `stage`.
static func cap(id: String, stage: int) -> int:
	var by_stage := maxi(0, stage - 1) * CAP_PER_STAGE
	var c := mini(int(ABILITIES[id].max), by_stage - by_stage % STEP)
	if Edition.demo():
		c = mini(c, DEMO_MAX)
	return c

## The price of the next session of `id`, climbing: 40, 70, 110, 160, 220, 290, 370...
static func price(stats: Dictionary, id: String) -> int:
	var n := level(stats, id) / STEP
	return 40 + 25 * n + 5 * n * n

## null-free: {stats, cost} when taught, else {error}.
static func buy(stats: Dictionary, id: String, stage: int, coins: int) -> Dictionary:
	if not ABILITIES.has(id):
		return {"error": "The trainer knows no such thing"}
	var s := sanitize(stats)
	var lv := level(s, id)
	if lv >= int(ABILITIES[id].max):
		return {"error": "%s is at its best: nothing more to teach" % ABILITIES[id].title}
	if lv >= cap(id, stage):
		return {"error": "Not yet: win the next bout first" if not (Edition.demo() and lv >= DEMO_MAX) else "The rest of the training is in the full game"}
	var p := price(s, id)
	if coins < p:
		return {"error": "Not enough denarii (%d needed)" % p}
	s[id] = lv + STEP
	return {"stats": s, "cost": p}

## The fighter's mods the abilities become (multiplied onto what he has).
static func mods_of(stats: Dictionary) -> Dictionary:
	var out := {}
	for id in sanitize(stats):
		var a: Dictionary = ABILITIES[id]
		out[a.mod] = 1.0 + float(a.sign) * float(level(stats, id)) / 100.0
	return out

## A line for the yard: what he has learned.
static func summary(stats: Dictionary) -> String:
	var bits := []
	for id in ORDER:
		if level(stats, id) > 0:
			bits.append("%s +%d%%" % [ABILITIES[id].title, level(stats, id)])
	return ", ".join(bits) if not bits.is_empty() else "untrained"
