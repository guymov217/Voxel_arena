class_name Training
## The trainer's yard (the ludus): what a gladiator's body can be taught between bouts, bought
## session by session with denarii and nothing else (the bouts teach nothing by themselves).
## Six abilities, each a few per cent on one thing the simulation already does: the arm's
## drive, the blow's weight, the breath, the hide, the blood and the footing. A session is
## STEP per cent; no ability goes past the stage's cap (CAP_PER_STAGE per cent a bout) or its
## own; the price climbs with every session; a death takes it all, as it takes the purse and the
## arms. (Sessions of 3% and limits nearly twice what they were: the giants of the campaign
## killed a trained man with one blow all the same, user.)

const ABILITIES := {
	"vis": {"name": "Vis", "title": "Strength", "max": 30, "mod": "strength", "sign": 1,
		"desc": "The arm's drive: a heavy weapon swung as fast as a light one, for less breath, held steadier; half of it goes into every blow."},
	"ictus": {"name": "Ictus", "title": "Blow", "max": 30, "mod": "blow", "sign": 1,
		"desc": "Weight behind the blow: every hit that lands, lands harder."},
	"spiritus": {"name": "Spiritus", "title": "Wind", "max": 36, "mod": "wind", "sign": 1,
		"desc": "More breath in the chest, and back sooner after a sprint or a flurry."},
	"corium": {"name": "Corium", "title": "Hide", "max": 45, "mod": "toughness", "sign": 1,
		"desc": "A thick hide: cuts bite less, bones hold, limbs come off harder."},
	"sanguis": {"name": "Sanguis", "title": "Blood", "max": 45, "mod": "bleed", "sign": -1,
		"desc": "Blood that clots: every wound bleeds slower."},
	"firmitas": {"name": "Firmitas", "title": "Footing", "max": 45, "mod": "footing", "sign": 1,
		"desc": "Hard to knock down, hard to stagger, and up again sooner."},
	# Taught only to the Unbroken (CampaignRun: the rudis won on Ironman). A little of every
	# other ability at once, and never lost: not to a death, not to a new campaign (its sessions
	# 2% as ever: what was won is kept as it was).
	"virtus": {"name": "Virtus", "title": "Valour", "max": 10, "step": 2, "mod": "", "sign": 1, "unbroken": true,
		"desc": "Doctore teaches it only to one who took the rudis without ever falling: a little more of everything, for good. A death does not take it."},
}
const ORDER := ["vis", "ictus", "spiritus", "corium", "sanguis", "firmitas"]
## The six it adds to, each with its sign (blood: slower is better).
const VIRTUS_MODS := {"strength": 1, "blow": 1, "wind": 1, "toughness": 1, "bleed": -1, "footing": 1}
const STEP := 3           # points a session (Virtus its own: step())
const CAP_PER_STAGE := 2  # per cent a bout: no buying a champion's body in the first week
const DEMO_MAX := 6       # the demo's trainer teaches two sessions of each

## What `level` points of an ability do for the man, in per cent (user: what the trainer gives must be
## felt: a session was 3 per cent of a thing, and 3 per cent is not felt). The first sessions count
## about twice what they did, each after it less, and at 45 points (what the ablest ability reaches)
## it is what it always was: a man trained to the limit is hardly more than he was, a man who has had
## a few sessions is much more. (The points are what is saved and sold and capped; this is what they
## are worth. Virtus is its own: its per cents are what it says.)
const EFFECT_START := 2.0   # per cent of effect a first point counts for
const EFFECT_AT := 45.0     # and the points at which a point is worth one per cent again
static func effect(level: float) -> float:
	var l := maxf(0.0, level)
	return EFFECT_START * EFFECT_AT * l / (l + EFFECT_AT)

## The per cent one session of `id` teaches.
static func step(id: String) -> int:
	return int(ABILITIES.get(id, {}).get("step", STEP))

## The first bout before which an ability may reach `lv` per cent.
static func bout_for(lv: int) -> int:
	return ceili(float(lv) / CAP_PER_STAGE) + 1

## What the trainer taught as it was kept before (sessions of 2%, under the training ground's
## own save): each session kept, worth a session of today.
static func from_old(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for id in ORDER:
			if raw.get(id) is int or raw.get(id) is float:
				out[id] = int(raw[id]) / 2 * step(id)
	return out

## {ability: per cent}, made safe: known abilities, whole steps, within the ability's own limit.
static func sanitize(raw) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for id in raw:
		if ABILITIES.has(id) and (raw[id] is int or raw[id] is float):
			var v := clampi(int(raw[id]), 0, int(ABILITIES[id].max))
			v -= v % step(id)
			if v > 0:
				out[id] = v
	return out

static func level(stats: Dictionary, id: String) -> int:
	return int(stats.get(id, 0))

## The most an ability may reach before bout `stage`.
static func cap(id: String, stage: int) -> int:
	if bool(ABILITIES[id].get("unbroken", false)):
		return int(ABILITIES[id].max) if CampaignRun.unbroken() and not Edition.demo() else 0
	var by_stage := maxi(0, stage - 1) * CAP_PER_STAGE
	var c := mini(int(ABILITIES[id].max), by_stage - by_stage % step(id))
	if Edition.demo():
		c = mini(c, DEMO_MAX)
	return c

## The price of the next session of `id`, climbing: 40, 70, 110, 160, 220, 290, 370...
static func price(stats: Dictionary, id: String) -> int:
	var n := level(stats, id) / step(id)
	if bool(ABILITIES[id].get("unbroken", false)):
		return 150 + 75 * n
	return 40 + 25 * n + 5 * n * n

## null-free: {stats, cost} when taught, else {error}.
static func buy(stats: Dictionary, id: String, stage: int, coins: int) -> Dictionary:
	if not ABILITIES.has(id):
		return {"error": "The trainer knows no such thing"}
	var s := sanitize(stats)
	var lv := level(s, id)
	if lv >= int(ABILITIES[id].max):
		return {"error": Loc.t("%s is at its best: nothing more to teach") % Loc.t(String(ABILITIES[id].title))}
	if bool(ABILITIES[id].get("unbroken", false)) and not CampaignRun.unbroken():
		return {"error": "Doctore teaches Virtus only to one who won the rudis on Ironman"}
	if lv >= cap(id, stage):
		return {"error": "Not yet: win the next bout first" if not (Edition.demo() and lv >= DEMO_MAX) else "The rest of the training is in the full game"}
	var p := price(s, id)
	if coins < p:
		return {"error": Loc.t("Not enough denarii (%d needed)") % p}
	s[id] = lv + step(id)
	return {"stats": s, "cost": p}

## The fighter's mods the abilities become (multiplied onto what he has).
static func mods_of(stats: Dictionary) -> Dictionary:
	var out := {}
	var st := sanitize(stats)
	for id in st:
		var a: Dictionary = ABILITIES[id]
		if String(a.mod) != "":
			out[a.mod] = 1.0 + float(a.sign) * effect(float(level(st, id))) / 100.0
	var vt := level(st, "virtus")
	if vt > 0:
		for m in VIRTUS_MODS:
			out[m] = float(out.get(m, 1.0)) * (1.0 + float(VIRTUS_MODS[m]) * float(vt) / 100.0)
	return out

## What `id` at `lv` points is worth to him, in per cent, as the trainer and the yard say it.
static func shown(id: String, lv: float) -> int:
	return int(round(lv)) if id == "virtus" else int(round(effect(lv)))

## A line for the yard: what he has learned.
static func summary(stats: Dictionary) -> String:
	var bits := []
	for id in ORDER + ["virtus"]:
		if level(stats, id) > 0:
			bits.append("%s +%d%%" % [ABILITIES[id].title, shown(id, level(stats, id))])
	return ", ".join(bits) if not bits.is_empty() else "untrained"
