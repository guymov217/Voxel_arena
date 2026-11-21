class_name Tourney
extends RefCounted
## A tournament of one-on-one bouts, single elimination: the entrants (the room's players, and bots to fill the bracket) are
## drawn into pairs, each pair fights a bout (a duel, over as many rounds as the host set: Series), the winner goes on to the
## next round, a lone one is passed through, until one is crowned. Pure logic, DOM-free: the bracket, whose turn it is, the
## words for each round; the menu (the host's) plays it out bout by bout and tells the guests.
##
## An entrant is {key, name, peer, bot}: key as Series keys him (a player "p<peer>", a bot "b<name>"), peer the player's
## (1 the host's own, -1 for a bot). A match is {a, b, winner}: `b` "" is a bye; `winner` "" while it is to be fought.

const MOST := 8                # (a room of eight; a bracket of eight is three rounds)

var entrants: Array = []
var rounds_list: Array = []    # each round: an Array of matches
var round_i := 0
var best_of := 1               # the rounds of each bout (Series)
var log: Array = []            # what was settled unseen ("Crixus beat Cato")

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

## Has a player a bout still to fight? (A match of two bots is settled unseen.)
func is_seen(m: Dictionary) -> bool:
	return not (is_bot(String(m.a)) and (String(m.b) == "" or is_bot(String(m.b))))

## The matches of two bots in this round are settled unseen, by a coin (the one who beat the other is noted in `log`).
func settle_bots(rng: RandomNumberGenerator) -> void:
	for m in current_round():
		if String(m.winner) == "" and String(m.b) != "" and is_bot(String(m.a)) and is_bot(String(m.b)):
			var win := String(m.a) if rng.randf() < 0.5 else String(m.b)
			var lose := String(m.b) if win == String(m.a) else String(m.a)
			m.winner = win
			log.append(Loc.t("%s beat %s") % [name_of(win), name_of(lose)])

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
