class_name WeaponRating
extends RefCounted
## A weapon's rating (user, forge: a real rating of a weapon, by duels against standard foes, ranked against the arsenal's own): the design in the hands of a bot, fought a fixed set of bouts
## (headless, by RatingRunner, in a game of its own that the forge starts) against the same standard foes every weapon of the arsenal was fought against (data/weapon_ratings.json, made by
## tools/rate_presets.sh), a score for each bout by what it came to, a score for the weapon, and its place among the arsenal's. DOM-free: this is the battery, the scoring, the ranking and
## what the wire (the files the two games trade) carries; the runner fights, the forge shows.
##
## The numbers are the battery's: when any of them changes the arsenal's table has to be made again (`stamp()` says whether it was made with these: a test holds it to that). A change to how
## a man fights, to a weapon or to the physics moves the table too, and nothing says so but the table itself: run tools/rate_presets.sh after such a change.

const VERSION := 1
const TABLE := "res://data/weapon_ratings.json"
## The bot that wields the weapon (the arsenal's own weapons are wielded by the same).
const WIELDER_DIFF := 0.7
## The standard foes: men in the arena's kit, as the duel probe (tests/duel.gd) gives them: a skill, a weapon and a shield, armour.
const FOES := [
	{"key": "gladiator", "diff": 0.6, "main": "gladius", "off": "roundShield", "armor": []},
	{"key": "armoured", "diff": 0.6, "main": "gladius", "off": "roundShield", "armor": ["helmet", "lorica"]},
	{"key": "champion", "diff": 0.9, "main": "gladius", "off": "roundShield", "armor": ["helmet", "lorica"]},
]
const BOUTS_PER_FOE := 6
## A bout lasts to the death or this long (s of the game's own time), then whoever has more of his blood and body left wins.
const BOUT_SECS := 40.0
const FIRST_SEED := 11
const SEED_STEP := 7
## What a bout's score is made of: the result (won 1, drawn 0.5, lost 0) and the share of the harm done that he dealt.
const W_RESULT := 0.55
const W_SHARE := 0.45
## Most bouts a file may claim (the wire).
const MAX_BOUTS := 64
const NUM_MAX := 1000000.0

## The bouts of the battery, in the order they are fought: [{"foe": a FOES entry, "seed": the match's}].
static func battery() -> Array:
	var out := []
	var i := 0
	for foe in FOES:
		for b in BOUTS_PER_FOE:
			out.append({"foe": foe, "seed": FIRST_SEED + i * SEED_STEP})
			i += 1
	return out

## What the battery is, in a word: the table says what it was made with, and a test holds the two to each other.
static func stamp() -> String:
	return "%d-%08x" % [VERSION, hash(JSON.stringify([WIELDER_DIFF, FOES, BOUTS_PER_FOE, BOUT_SECS, FIRST_SEED, SEED_STEP, W_RESULT, W_SHARE]))]

## Why a design cannot be rated, in a line ("" when it can): the duels are fought with a weapon in the hand.
static func unrateable(d: Dictionary, st := {}) -> String:
	if (d.get("voxels", []) as Array).is_empty():
		return "There is nothing to rate yet"
	if str(d.get("kind", "weapon")) == "shield":
		return "Duels are fought with a weapon in the hand: a shield is not rated"
	if str(d.get("shoots", "")) != "":
		return "Duels are fought with a weapon in the hand: a bow is not rated"
	if not bool((st if not st.is_empty() else ForgeLib.compute_stats(d)).hasGrip):
		return "It needs somewhere to be held: build a Grip block, or Move hand"
	return ""

## A design in a word, the same for the same weapon however its blocks happen to be listed: to know that a rating is of the weapon that is on the anvil.
static func key(d: Dictionary) -> String:
	var rows := []
	for v in d.get("voxels", []):
		rows.append("%d,%d,%d,%s,%s,%d" % [int(v[0]), int(v[1]), int(v[2]), str(v[3]), str(v[4]), ForgeLib.face_of(v)])
	rows.sort()
	var g = d.get("grips")
	var hands := str(g) if g is Dictionary else ""
	return "%08x" % hash("%s|%s|%s|%.2f|%s|%s" % ["\n".join(rows), str(bool(d.get("twoHanded", false))), str(bool(d.get("throwable", false))), float(d.get("sharpness", 0.8)), hands, str(d.get("chain", ""))])

## What one bout came to, as a score from 0 to 100: `r` the bout's row ({"won", "draw", "dmg", "taken"}).
static func bout_score(r: Dictionary) -> float:
	var result := 1.0 if bool(r.get("won", false)) else (0.5 if bool(r.get("draw", false)) else 0.0)
	var dealt := maxf(0.0, float(r.get("dmg", 0.0)))
	var taken := maxf(0.0, float(r.get("taken", 0.0)))
	var share := dealt / (dealt + taken) if dealt + taken > 0.001 else 0.5
	return 100.0 * (W_RESULT * result + W_SHARE * share)

## The weapon's score from its bouts: the mean of theirs (0 for none).
static func score(bouts: Array) -> float:
	if bouts.is_empty():
		return 0.0
	var s := 0.0
	for b in bouts:
		s += bout_score(b)
	return s / bouts.size()

## How many bouts were won (a draw is half), and of how many.
static func record(bouts: Array) -> Dictionary:
	var won := 0.0
	for b in bouts:
		won += 1.0 if bool(b.get("won", false)) else (0.5 if bool(b.get("draw", false)) else 0.0)
	return {"won": won, "of": bouts.size()}

## What a rated weapon comes to, for the wire and the table: its score and what it is made of.
static func summary(bouts: Array) -> Dictionary:
	var dmg := 0.0
	var taken := 0.0
	var hits := 0
	var big := 0.0
	var secs := 0.0
	for b in bouts:
		dmg += float(b.get("dmg", 0.0))
		taken += float(b.get("taken", 0.0))
		hits += int(b.get("hits", 0))
		big = maxf(big, float(b.get("big", 0.0)))
		secs += float(b.get("secs", 0.0))
	var rec := record(bouts)
	return {"score": snappedf(score(bouts), 0.1), "won": rec.won, "of": rec.of, "dmg": roundi(dmg), "taken": roundi(taken), "hits": hits, "big": roundi(big), "secs": snappedf(secs, 0.1)}

## The arsenal's table (data/weapon_ratings.json): {"version", "stamp", "presets": {key: summary}}; empty when there is none.
static var _table := {}
static func table() -> Dictionary:
	if _table.is_empty() and FileAccess.file_exists(TABLE):
		var v = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		if v is Dictionary and v.get("presets") is Dictionary:
			_table = v
	return _table

## Which of the arsenal's weapons are rated (the ones a bot can fight a duel with): the table's own list.
static func arsenal() -> Array:
	var out := []
	for k in table().get("presets", {}):
		out.append(String(k))
	out.sort()
	return out

## Where a score stands among the arsenal's: {"better": how many of them it beats, "of": how many there are, "rank": 1 for the best, "below": the key of the best weapon it beats, "above": the key of
## the weakest that beats it ("" at the ends)}; empty with no table. A score level with a weapon's is not above it.
static func rank(sc: float, tab := {}) -> Dictionary:
	var t: Dictionary = tab if not tab.is_empty() else table()
	var ps = t.get("presets")
	if not (ps is Dictionary) or (ps as Dictionary).is_empty():
		return {}
	var better := 0
	var below := ""
	var below_s := -INF
	var above := ""
	var above_s := INF
	for k in ps:
		var s := float((ps[k] as Dictionary).get("score", 0.0))
		if s <= sc:
			better += 1
			if s > below_s or (s == below_s and String(k) < below):
				below = String(k)
				below_s = s
		else:
			if s < above_s or (s == above_s and String(k) < above):
				above = String(k)
				above_s = s
	return {"better": better, "of": (ps as Dictionary).size(), "rank": (ps as Dictionary).size() - better + 1, "below": below, "above": above}

## The arsenal's scores in order, low to high: what the forge draws its strip from.
static func scores(tab := {}) -> Array:
	var t: Dictionary = tab if not tab.is_empty() else table()
	var out := []
	var ps = t.get("presets")
	if ps is Dictionary:
		for k in ps:
			out.append(float((ps[k] as Dictionary).get("score", 0.0)))
	out.sort()
	return out

## A figure from a file the other game wrote: a finite number kept within what is sensible.
static func _num(v, lo := 0.0, hi := NUM_MAX) -> float:
	var f := Net.num(v)
	return clampf(f, lo, hi) if is_finite(f) else lo

## A result file made safe: whatever it says, a progress or a verdict of known shape. {"state": "running" | "done" | "failed", "done", "of", "bouts": [..], "error"} (and, once done, "summary" and "rank").
static func clean_result(v) -> Dictionary:
	var out := {"state": "running", "done": 0, "of": 0, "bouts": [], "error": ""}
	if not (v is Dictionary):
		return out
	var st := str(v.get("state", "running"))
	out.state = st if ["running", "done", "failed"].has(st) else "running"
	var rows := []
	var bs = v.get("bouts")
	if bs is Array:
		for b in (bs as Array).slice(0, MAX_BOUTS):
			if not (b is Dictionary):
				continue
			var foe := str(b.get("foe", "")).left(24)
			rows.append({
				"foe": foe,
				"won": b.get("won") is bool and bool(b.won),
				"draw": b.get("draw") is bool and bool(b.draw),
				"dmg": _num(b.get("dmg")), "taken": _num(b.get("taken")), "secs": _num(b.get("secs"), 0.0, 36000.0),
				"hits": int(_num(b.get("hits"))), "big": _num(b.get("big")),
			})
	out.bouts = rows
	out.done = rows.size()
	out.of = clampi(int(_num(v.get("of"), 0.0, float(MAX_BOUTS))), rows.size(), MAX_BOUTS)
	out.error = str(v.get("error", "")).left(160)
	if out.state == "done":
		out["summary"] = summary(rows)
		out["rank"] = rank(float(out.summary.score))
	return out
