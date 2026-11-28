class_name Tourney
extends RefCounted
## A tournament of one-on-one bouts, single elimination: the entrants (the room's players, and bots to fill the bracket) are
## drawn into pairs, each pair fights a bout (a duel, over as many rounds as the host set: Series), the winner goes on to the
## next round, a lone one is passed through, until one is crowned. Pure logic, DOM-free: the bracket, whose turn it is, the
## words for each round, the tree to draw (`tree`) and its form on the wire; the menu (the host's) plays it out bout by bout, every
## bout fought where all look on (those not in it, or out of it, are spectators), and tells the guests.
##
## An entrant is {key, name, peer, bot}: key as Series keys him (a player "p<peer>", a bot "b<name>"), peer the player's
## (1 the host's own, -1 for a bot). A match is {a, b, winner}: `b` "" is a bye; `winner` "" while it is to be fought.

const MOST := 8                # (a room of eight; a bracket of eight is three rounds)

var entrants: Array = []
var rounds_list: Array = []    # each round: an Array of matches
var round_i := 0
var best_of := 1               # the rounds of each bout (Series)

## The bracket for `entrants_`, drawn with `seed_`: pairs in the order drawn, a bye for the odd one out.
static func make(entrants_: Array, seed_: int, best_of_ := 1) -> Tourney:
	var tr := Tourney.new()
	tr.best_of = best_of_
	var list := entrants_.slice(0, MOST)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp
	tr.entrants = list
	tr._build_round(list.map(func(e): return String(e.key)))
	return tr

func _build_round(keys: Array) -> void:
	var round_matches := []
	var i := 0
	while i < keys.size():
		if i + 1 < keys.size():
			round_matches.append({"a": keys[i], "b": keys[i + 1], "winner": ""})
		else:
			round_matches.append({"a": keys[i], "b": "", "winner": keys[i]})   # (a bye)
		i += 2
	rounds_list.append(round_matches)

func entrant(key: String) -> Dictionary:
	for e in entrants:
		if String(e.key) == key:
			return e
	return {}

func name_of(key: String) -> String:
	return String(entrant(key).get("name", key))

func is_bot(key: String) -> bool:
	return bool(entrant(key).get("bot", false))

func current_round() -> Array:
	return rounds_list[round_i] if round_i < rounds_list.size() else []

## How many stand in this round (the number of its entrants, byes included).
func in_round() -> int:
	var n := 0
	for m in current_round():
		n += 1 if String(m.b) == "" else 2
	return n

func round_name() -> String:
	match in_round():
		2: return Loc.t("The final")
		3, 4: return Loc.t("The semi-final")
		5, 6, 7, 8: return Loc.t("The quarter-final")
	return Loc.t("Round %d") % (round_i + 1)

## The first match of the round still to be fought ({} when the round is done).
func open_match() -> Dictionary:
	for m in current_round():
		if String(m.winner) == "":
			return m
	return {}

func round_done() -> bool:
	return open_match().is_empty() and not current_round().is_empty()

## The match `m` was won by `key` (one of its two).
func report(m: Dictionary, key: String) -> void:
	if key == String(m.a) or key == String(m.b):
		m.winner = key

## The winners go on: the next round is drawn from them, in order. (False when the tournament is decided.)
func advance() -> bool:
	if not round_done():
		return false
	var winners := current_round().map(func(m): return String(m.winner))
	if winners.size() <= 1:
		return false
	round_i += 1
	_build_round(winners)
	return true

func finished() -> bool:
	return champion() != ""

## Who was crowned ("" while it goes on).
func champion() -> String:
	var r := current_round()
	if r.size() == 1 and String(r[0].winner) != "":
		return String(r[0].winner)
	return ""

## Those still in it.
func alive() -> Array:
	var out := []
	for m in current_round():
		if String(m.winner) == "":
			out.append(String(m.a))
			if String(m.b) != "":
				out.append(String(m.b))
		else:
			out.append(String(m.winner))
	return out

## How many players (not bots) are still in it.
func humans_left() -> int:
	return alive().filter(func(k): return not is_bot(String(k))).size()

## A player left: whoever he was to fight goes on.
func forfeit(key: String) -> void:
	for m in current_round():
		if String(m.winner) == "" and (String(m.a) == key or String(m.b) == key):
			m.winner = String(m.b) if String(m.a) == key else String(m.a)
	for e in entrants:
		if String(e.key) == key:
			e["gone"] = true

## "The semi-final · Aulus against Brutus".
func match_text(m: Dictionary) -> String:
	if String(m.b) == "":
		return Loc.t("%s goes through") % name_of(String(m.a))
	return Loc.t("%s against %s") % [name_of(String(m.a)), name_of(String(m.b))]

## The bracket as lines for the screen: a line a match, the winner marked, round by round.
func lines() -> Array:
	var out := []
	var rn := 0
	for r in rounds_list:
		rn += 1
		out.append(Loc.t("Round %d") % rn)
		for m in r:
			var a := name_of(String(m.a))
			var b := name_of(String(m.b)) if String(m.b) != "" else Loc.t("(bye)")
			var w := String(m.winner)
			out.append("  %s%s  –  %s%s" % [a, " ✓" if w == String(m.a) and String(m.b) != "" else "", b, " ✓" if w == String(m.b) else ""])
	return out

## How many rounds a bracket of `n` has (an odd one out is passed through, as `advance` does): two make one, three and four make two, five to eight three.
static func rounds_for(n: int) -> int:
	var r := 1
	var m := ceili(maxi(1, n) / 2.0)
	while m > 1:
		m = ceili(m / 2.0)
		r += 1
	return r

## The name of round `r` (counted from 0) of `total` rounds: the final, the semi-final, the quarter-final, else its number.
static func round_title(r: int, total: int) -> String:
	match total - r:
		1: return Loc.t("The final")
		2: return Loc.t("The semi-final")
		3: return Loc.t("The quarter-final")
	return Loc.t("Round %d") % (r + 1)

## The whole bracket as the screen draws it (user: a tree to be seen through the tournament, to know who goes on): every round, those not reached yet too, the places of
## winners not yet known left empty. Each {"title", "matches"}; a match {"a", "b" (keys: "" is empty, or the bye's), "w" (the winner's key, "" while it is to be fought), "bye",
## "open" (the bout being fought now)}.
func tree() -> Array:
	var total := rounds_for(entrants.size())
	var out := []
	var open := open_match()
	var prev: Array = []
	for r in total:
		var ms := []
		if r < rounds_list.size():
			for m in rounds_list[r]:
				ms.append({"a": String(m.a), "b": String(m.b), "w": String(m.winner), "bye": String(m.b) == "", "open": r == round_i and not open.is_empty() and is_same(m, open)})
		else:
			for j in ceili(prev.size() / 2.0):
				var fa: Dictionary = prev[2 * j]
				var fb: Dictionary = prev[2 * j + 1] if 2 * j + 1 < prev.size() else {}
				var a := String(fa.w)
				ms.append({"a": a, "b": String(fb.get("w", "")), "w": a if fb.is_empty() else "", "bye": fb.is_empty(), "open": false})
		out.append({"title": round_title(r, total), "matches": ms})
		prev = ms
	return out

## Whom the bracket has put out (the loser of a bout that was won), as keys.
func out_keys() -> Array:
	var out := []
	for r in rounds_list:
		for m in r:
			if String(m.winner) != "" and String(m.b) != "":
				out.append(String(m.b) if String(m.winner) == String(m.a) else String(m.a))
	return out

## The bracket as it goes over the wire (small: the entrants, and the bouts of each round with their winners), read back made safe by `from_dict`.
func to_dict() -> Dictionary:
	return {"e": entrants.map(func(e): return [String(e.key), String(e.name), 1 if bool(e.bot) else 0, 1 if bool(e.get("gone", false)) else 0]),
		"r": rounds_list.map(func(r): return r.map(func(m): return [String(m.a), String(m.b), String(m.winner)])), "i": round_i, "n": best_of}

## What a guest was told of the bracket, made safe: at most MOST entrants, a few short rounds of bouts of keys. Nothing real in it gives a bracket with nothing in it.
static func from_dict(d) -> Tourney:
	var tr := Tourney.new()
	if not (d is Dictionary):
		return tr
	var seen := {}
	var es = d.get("e")
	if es is Array:
		for e in (es as Array).slice(0, MOST):
			if e is Array and (e as Array).size() >= 3 and e[0] is String and e[1] is String and not seen.has(String(e[0]).left(24)):
				var key := String(e[0]).left(24)
				seen[key] = true
				tr.entrants.append({"key": key, "name": Net.clean_name(e[1]), "peer": -1, "bot": Net.num(e[2]) > 0.5, "gone": (e as Array).size() > 3 and Net.num(e[3]) > 0.5})
	var rs = d.get("r")
	if rs is Array:
		for r in (rs as Array).slice(0, 4):
			var ms := []
			if r is Array:
				for m in (r as Array).slice(0, MOST):
					if m is Array and (m as Array).size() >= 3 and m[0] is String and m[1] is String and m[2] is String:
						ms.append({"a": String(m[0]).left(24), "b": String(m[1]).left(24), "winner": String(m[2]).left(24)})
			if not ms.is_empty():
				tr.rounds_list.append(ms)
	tr.round_i = clampi(int(Net.num(d.get("i"))), 0, maxi(0, tr.rounds_list.size() - 1))
	tr.best_of = clampi(int(Net.num(d.get("n"), 1.0)), 1, 9)
	return tr

## Plain checks of an entrants list (the room's, made safe): up to MOST, each with a key and a name.
static func clean_entrants(list) -> Array:
	var out := []
	if not (list is Array):
		return out
	var seen := {}
	for e in (list as Array).slice(0, MOST):
		if e is Dictionary and e.get("key") is String and not seen.has(e.key):
			seen[e.key] = true
			out.append({"key": String(e.key).left(24), "name": Net.clean_name(e.get("name", "?")), "peer": int(e.get("peer", -1)) if (e.get("peer") is int or e.get("peer") is float) else -1, "bot": bool(e.get("bot", false))})
	return out

## The bracket's size for `humans` players with the host's bots setting: -1 fills to four or eight.
static func entrant_count(humans: int, bots: int) -> int:
	if bots >= 0:
		return clampi(humans + bots, 0, MOST)
	var size := 4
	while size < humans:
		size *= 2
	return mini(MOST, size)
