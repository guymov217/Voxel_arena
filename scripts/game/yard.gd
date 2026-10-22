class_name Yard
## The Ludus yard (yard.js): where the gladiators wait between fights. A walkable hub with its
## stations (the arena gate, the smith, the market, the mission board), training dummies and
## throwing targets; and the progression the yard pays out: missions for the
## next fight, denarii and reputation, and the ranks that reputation buys.

const STATIONS := {
	"gate": {"p": Vector3(0, 0, 11.5), "r": 1.8, "label": "The arena gate", "hint": "E: into the arena, the next fight"},
	"smith": {"p": Vector3(-9.5, 0, 5), "r": 2.0, "label": "The smith", "hint": "E: talk to the smith · buy, mend and reshape your weapons", "npc": {"name": "Vulcanus the smith", "main": "hammer", "color": 0x4a3020, "armor": ["leatherJerkin", "hat_bandana", "beard_braided"], "work": ""}},
	"market": {"p": Vector3(9.5, 0, 5), "r": 2.0, "label": "The market", "hint": "E: talk to the trader · pots, bread and gadgets", "npc": {"name": "Mercator the trader", "main": "", "color": 0x2a5a8a, "armor": ["cape", "hat_straw", "hair_curly"], "work": "wares"}},
	"board": {"p": Vector3(0, 0, -11), "r": 1.4, "label": "The mission board", "hint": "E: your missions for the next fight"},
	"trainer": {"p": Vector3(5, 0, -10), "r": 2.0, "label": "The trainer", "hint": "E: talk to the trainer · strength, wind, hide, blood and footing, session by session", "npc": {"name": "Doctore the trainer", "main": "hammer", "color": 0x6a4a2a, "armor": ["vambraces", "leatherCap", "beard_braided"], "work": ""}},
	"physician": {"p": Vector3(-5, 0, -10), "r": 2.0, "label": "The physician", "hint": "E: talk to the physician · stitch your wounds, fit a prosthetic", "npc": {"name": "Galen the physician", "main": "dagger", "color": 0xe8e0d0, "armor": ["hat_laurel", "hair_long", "beard_braided"], "work": "stitch"}},
}
const DUMMIES := [Vector3(-8, 0, -5), Vector3(-10.5, 0, -2)]
const TARGETS := [Vector3(12.6, 1.5, -3), Vector3(11.6, 1.5, -6.5), Vector3(10.2, 1.5, -9.5)]

## The mission board is put away for now (its missions still count, quietly).
const SHOW_BOARD := false

## The stations standing in the yard.
static func stations() -> Dictionary:
	var out := {}
	for id in STATIONS:
		if id != "board" or SHOW_BOARD:
			out[id] = STATIONS[id]
	return out

static func station_at(p: Vector3) -> String:
	var st := stations()
	for id in st:
		if Vector2(p.x - st[id].p.x, p.z - st[id].p.z).length() < float(st[id].r):
			return id
	return ""

## Points for a throw by how close to the middle of the board it struck.
static func target_score(dist: float) -> int:
	return 10 if dist < 0.15 else (5 if dist < 0.3 else (2 if dist < 0.5 else 0))

# ---------- Ranks ----------
## Reputation is earned in fights and from missions; it never goes down.
const RANKS := [
	{"id": "tiro", "name": "Tiro", "rep": 0, "perk": "A recruit. The throwables are yours to buy."},
	{"id": "gladiator", "name": "Gladiator", "rep": 150, "perk": "The crowd starts to know your name."},
	{"id": "veteran", "name": "Veteran", "rep": 400, "perk": "Heavy armour is for sale to you."},
	{"id": "champion", "name": "Champion", "rep": 900, "perk": "Missions pay half again."},
	{"id": "rudiarius", "name": "Rudiarius", "rep": 1800, "perk": "Given the wooden sword: free. Every mission pays double."},
]

static func rank_of(rep: int) -> Dictionary:
	var idx := 0
	for i in RANKS.size():
		if rep >= int(RANKS[i].rep):
			idx = i
	var r: Dictionary = RANKS[idx].duplicate()
	r["index"] = idx
	r["next"] = RANKS[idx + 1] if idx + 1 < RANKS.size() else null
	return r

static func mission_pay(rep: int) -> float:
	return [1.0, 1.0, 1.0, 1.5, 2.0][rank_of(rep).index]

# ---------- Missions ----------
## Three for the next fight; `count` events of `kind` complete one.
const MISSIONS := {
	"kill2": {"text": "Kill two enemies", "kind": "kill", "count": 2, "coins": 30, "rep": 20},
	"sever": {"text": "Cut a limb off an enemy", "kind": "sever", "count": 1, "coins": 35, "rep": 25},
	"fists": {"text": "Land 8 punches", "kind": "punch", "count": 8, "coins": 30, "rep": 20},
	"head": {"text": "Hit an enemy in the head 5 times", "kind": "head", "count": 5, "coins": 30, "rep": 20},
	"throwKill": {"text": "Kill an enemy with something thrown", "kind": "throwKill", "count": 1, "coins": 50, "rep": 35},
	"shove": {"text": "Shove enemies 4 times", "kind": "shove", "count": 4, "coins": 25, "rep": 15},
	"survive": {"text": "Be standing at the end of the fight", "kind": "survive", "count": 1, "coins": 25, "rep": 20},
	"bigOne": {"text": "Help bring down a giant or a boss", "kind": "bigKill", "count": 1, "coins": 60, "rep": 45},
	"untouched": {"text": "Win having lost less than a third of your blood", "kind": "clean", "count": 1, "coins": 45, "rep": 30},
}

static func roll_missions(seed_: int, n := 3) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var ids: Array = MISSIONS.keys()
	var out := []
	while out.size() < mini(n, ids.size()):
		out.append({"id": ids.pop_at(r.randi_range(0, ids.size() - 1)), "n": 0})
	return out

## Counts from a fight applied to the missions; returns the ones completed this fight.
static func apply_counts(missions: Array, counts: Dictionary) -> Array:
	var done := []
	for ms in missions:
		var d: Dictionary = MISSIONS.get(ms.id, {})
		if d.is_empty() or ms.get("done", false):
			continue
		ms.n = mini(int(d.count), int(ms.n) + int(counts.get(d.kind, 0)))
		if int(ms.n) >= int(d.count):
			ms.done = true
			done.append(ms.id)
	return done

## What the finished missions pay: {coins, rep}.
static func payout(ids: Array, rep: int) -> Dictionary:
	var k := mission_pay(rep)
	var c := 0
	var r := 0
	for id in ids:
		c += int(round(int(MISSIONS[id].coins) * k))
		r += int(MISSIONS[id].rep)
	return {"coins": c, "rep": r}

## Reputation from a fight itself: something for showing up, more for winning and for kills.
static func fight_rep(won: bool, kills: int, boss: bool) -> int:
	return (10 if won else 3) + kills * 4 + (25 if boss and won else 0)
