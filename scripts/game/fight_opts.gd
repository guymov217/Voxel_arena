class_name FightOpts
extends RefCounted
## The settings an Arena fight is started with, each fight offering its own (the host's; Menu's fight screen sets them, kept per
## fight in the settings): how many rounds it is played over (Series), how many bots fight beside the players, and how many
## of the Emperor's decrees it is under. Pure logic, DOM-free: what a fight offers, the numbers on offer, their defaults and
## words, and a setting made safe.

const BOT_MODES := ["ffa", "teams", "hill", "lastLimb", "emperor"]
const MOST_BOTS := 7
## A room of eight and the bots with them: more than that is more than a host's physics keeps up with.
const MAX_FIGHTERS := 12
const DECREES := [0, 1, 3]
const FILL := -1              # (the teams, the tournament) the bots that make the sides even, the bracket full

## What a fight lets the host set, in the order the screen shows them.
static func offers(mode: String) -> Array:
	var out := []
	if not Series.choices(mode).is_empty():
		out.append("rounds")
	if has_bots(mode):
		out.append("bots")
	if mode == "ffa":
		out.append("decrees")
	return out

## Does the fight let the host say how many bots there are? (The tournament's are the ones that fill its bracket.)
static func has_bots(mode: String) -> bool:
	return BOT_MODES.has(mode) or mode == "tourney"

static func choices(mode: String, key: String) -> Array:
	match key:
		"rounds":
			return Series.choices(mode)
		"bots":
			if not has_bots(mode):
				return []
			var out := [FILL] if (mode == "teams" or mode == "tourney") else []
			for n in MOST_BOTS + 1:
				out.append(n)
			return out
		"decrees":
			return DECREES.duplicate() if mode == "ffa" else []
	return []

static func default_of(mode: String, key: String) -> int:
	match key:
		"rounds":
			return Series.default_rounds(mode)
		"bots":
			return FILL if (mode == "teams" or mode == "tourney") else 3
	return 0

static func clean_value(mode: String, key: String, v) -> int:
	var on := choices(mode, key)
	if on.is_empty():
		return 0
	if (v is int or v is float) and is_finite(float(v)) and on.has(int(v)):
		return int(v)
	return default_of(mode, key)

## A fight's settings, each within what the fight offers (the ones it does not offer are left out).
static func clean(mode: String, raw) -> Dictionary:
	var out := {}
	var src: Dictionary = raw if raw is Dictionary else {}
	for key in offers(mode):
		out[key] = clean_value(mode, key, src.get(key))
	return out

static func title(key: String) -> String:
	return Loc.t({"rounds": "Rounds", "bots": "Bots", "decrees": "Decrees"}.get(key, key))

static func label(mode: String, key: String, v: int) -> String:
	match key:
		"rounds":
			return Series.label(mode, v)
		"bots":
			if v == FILL:
				return Loc.t("Fill the bracket") if mode == "tourney" else Loc.t("Fill the sides")
			return Loc.t("No bots") if v <= 0 else (Loc.t("1 bot") if v == 1 else Loc.t("%d bots") % v)
		"decrees":
			return Loc.t("No decrees") if v <= 0 else (Loc.t("One decree") if v == 1 else Loc.t("%d decrees") % v)
	return str(v)

## The bots a fight may have beside `players` (the room's): no more than the sand holds.
static func bots_allowed(players: int, bots: int) -> int:
	return clampi(bots, 0, maxi(0, MAX_FIGHTERS - players))

## What the settings say of the fighters: "You and 2 friends, with 3 bots".
static func fighters_text(players: int, bots: int) -> String:
	var who := Loc.t("You alone") if players <= 1 else (Loc.t("You and %d friends") % (players - 1) if players > 2 else Loc.t("You and a friend"))
	if bots <= 0:
		return who
	return Loc.t("%s, with %d bots") % [who, bots] if bots != 1 else Loc.t("%s, with a bot") % who
