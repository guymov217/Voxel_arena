class_name BoutReport
extends RefCounted
## The report at the end of a campaign bout (user, #346: an eye-catching statistics report at the end of every fight: various measures per player, and who earned the
## most money): every man of the party's kills, the damage he dealt and took, his hardest blow, the limbs he cut off and lost, the friends he lifted, the crowd's favour for him and
## the money he won from the crowd; the awards each measure's leader takes and the bout's most valuable man. DOM-free: the match counts (Match._tally*, _bout_report), this builds,
## ranks and cleans what the host says (the wire), the menu draws it (Menu._report).
##
## Money: every man of the party takes home the same purse (the stage's pay, the rounds', the crowd's and its favourite's), so "who earned the most" is who brought the crowd's part
## of it in: what the crowd paid for the show (Match.CROWD_BONUS of the pay, by the bout's liveliness) is shared among the party by the favour each earned above the crowd's
## indifference, and the favourite's own bonus is his. What each takes home is not changed by any of this.

const MOST := 8              # men a report keeps (as the scroll: PartyGlory.MOST)
const INDIFFERENCE := 20.0   # the crowd's favour for a man who has done nothing (Spectacle: every man starts at it)
const NUM_MAX := 99999       # no figure on the wire past this
## What is counted, in the order of the table: [key, label].
const MEASURES := [
	["kills", "Kills"],
	["dmg", "Damage dealt"],
	["big", "Hardest blow"],
	["cut", "Limbs cut off"],
	["hurt", "Damage taken"],
	["limbs", "Limbs lost"],
	["lifts", "Friends lifted"],
	["fav", "Crowd favour"],
	["earned", "Won from the crowd"],
]
## The title each measure's leader takes: [key, title].
const AWARDS := [
	["kills", "Slayer"],
	["dmg", "Wrecker"],
	["big", "Hammer"],
	["cut", "Butcher"],
	["hurt", "Iron hide"],
	["lifts", "Good friend"],
	["fav", "The crowd's darling"],
	["earned", "Top earner"],
]
## What counts to a man's worth in the bout (the most valuable man takes the crown): a kill, a point of damage dealt, a limb cut off, a friend lifted, a point of the crowd's favour
## over indifference, and standing at the end.
const WORTH := {"kills": 10.0, "dmg": 0.4, "cut": 5.0, "lifts": 8.0, "fav": 0.5}
const WORTH_STANDING := 5.0

## `amount` whole denarii shared out by `weights` (the largest remainders take the odd ones, the first of them first), as many shares as weights, summing to `amount`; equally when nobody has any weight.
static func split(weights: Array, amount: int) -> Array:
	var n := weights.size()
	var out := []
	out.resize(n)
	out.fill(0)
	if n == 0 or amount <= 0:
		return out
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	var exact := []
	var given := 0
	for i in n:
		var share := float(amount) * (maxf(0.0, float(weights[i])) / total if total > 0.0 else 1.0 / float(n))
		exact.append(share)
		out[i] = int(floor(share))
		given += int(out[i])
	var order := range(n)
	order.sort_custom(func(a, b): return (exact[a] - floor(exact[a])) > (exact[b] - floor(exact[b])) or ((exact[a] - floor(exact[a])) == (exact[b] - floor(exact[b])) and a < b))
	var left := amount - given
	for k in order:
		if left <= 0:
			break
		out[k] = int(out[k]) + 1
		left -= 1
	return out

## The bout's report. `order`: the names of the party in the order they are listed, `tallies`: name -> the match's tally row (kills, dmg, hurt, big, cut, limbs, lifts, hits: what a man did),
## `alive`: name -> still alive, `favour`: name -> the crowd's favour for him (0..100), `purse`: {each, base, rounds, crowd, fav, favourite}: what each man takes home and what it is made of,
## `secs`: how long the bout lasted.
static func build(order: Array, tallies: Dictionary, alive: Dictionary, favour: Dictionary, purse: Dictionary, secs: float, won: bool) -> Dictionary:
	var names := order.slice(0, MOST)
	var weights := []
	for n in names:
		weights.append(maxf(0.0, float(favour.get(n, INDIFFERENCE)) - INDIFFERENCE))
	var shares := split(weights, maxi(0, int(purse.get("crowd", 0))))
	var rows := []
	for i in names.size():
		var n: String = names[i]
		var t: Dictionary = tallies.get(n, {}) if tallies.get(n) is Dictionary else {}
		var bonus := maxi(0, int(purse.get("fav", 0))) if String(purse.get("favourite", "")) == n else 0
		rows.append({
			"name": n,
			"kills": int(t.get("kills", 0)),
			"dmg": int(round(float(t.get("dmg", 0.0)))),
			"hurt": int(round(float(t.get("hurt", 0.0)))),
			"big": int(round(float(t.get("big", 0.0)))),
			"hits": int(t.get("hits", 0)),
			"cut": int(t.get("cut", 0)),
			"limbs": int(t.get("limbs", 0)),
			"lifts": int(t.get("lifts", 0)),
			"fav": int(round(float(favour.get(n, INDIFFERENCE)))),
			"earned": int(shares[i]) + bonus,
			"alive": bool(alive.get(n, false)),
		})
	return {"rows": rows, "purse": {"each": int(purse.get("each", 0)), "base": int(purse.get("base", 0)), "rounds": int(purse.get("rounds", 0)), "crowd": int(purse.get("crowd", 0)), "fav": int(purse.get("fav", 0)), "favourite": String(purse.get("favourite", ""))}, "secs": snappedf(secs, 0.1), "won": won}

## The men that lead `key` in `rows`: the ones with the most of it, none when nobody has any of it or when every man has the same (nothing sets one apart).
static func leaders(rows: Array, key: String) -> Array:
	var most := 0.0
	var least := INF
	for r in rows:
		most = maxf(most, float(r.get(key, 0)))
		least = minf(least, float(r.get(key, 0)))
	var out := []
	if most <= 0.0 or (rows.size() > 1 and most == least):
		return out
	for r in rows:
		if float(r.get(key, 0)) == most:
			out.append(String(r.name))
	return out

## The awards: for each of AWARDS the men who lead it and by what: [key, title, [names], value]. A lone man takes none (he is not set against anyone).
static func awards(rows: Array) -> Array:
	var out := []
	if rows.size() < 2:
		return out
	for a in AWARDS:
		var who := leaders(rows, a[0])
		if not who.is_empty():
			var v := 0
			for r in rows:
				if String(r.name) == String(who[0]):
					v = int(r.get(a[0], 0))
			out.append([a[0], a[1], who, v])
	return out

## What a man was worth in the bout (WORTH).
static func worth(r: Dictionary) -> float:
	var s := WORTH_STANDING if bool(r.get("alive", false)) else 0.0
	for k in WORTH:
		var v := float(r.get(k, 0))
		if k == "fav":
			v = maxf(0.0, v - INDIFFERENCE)
		s += float(WORTH[k]) * v
	return s

## The most valuable man of the party: the one who was worth the most, none for a lone man or when all were worth the same.
static func mvp(rows: Array) -> String:
	if rows.size() < 2:
		return ""
	var best := ""
	var most := -1.0
	var tie := false
	for r in rows:
		var w := worth(r)
		if w > most:
			most = w
			best = String(r.name)
			tie = false
		elif w == most:
			tie = true
	return "" if tie else best

## A plain yes from the wire: a true, and nothing else (comparing a string with a bool is an error).
static func _yes(v) -> bool:
	return v is bool and v

## A figure from the wire: a whole number 0..NUM_MAX.
static func _whole(v) -> int:
	return clampi(int(Net.num(v)), 0, NUM_MAX)

## A report from the wire (the host's), made safe: men as names (Net.clean_name), MOST of them, every figure a whole number 0..NUM_MAX.
static func clean(v) -> Dictionary:
	var out := {"rows": [], "purse": {"each": 0, "base": 0, "rounds": 0, "crowd": 0, "fav": 0, "favourite": ""}, "secs": 0.0, "won": false}
	if not (v is Dictionary):
		return out
	var rows = v.get("rows")
	if rows is Array:
		for r in (rows as Array).slice(0, MOST):
			if not (r is Dictionary):
				continue
			var row := {"name": Net.clean_name(r.get("name")), "alive": _yes(r.get("alive"))}
			for k in ["kills", "dmg", "hurt", "big", "hits", "cut", "limbs", "lifts", "fav", "earned"]:
				row[k] = _whole(r.get(k))
			out.rows.append(row)
	var p = v.get("purse")
	if p is Dictionary:
		for k in ["each", "base", "rounds", "crowd", "fav"]:
			out.purse[k] = _whole(p.get(k))
		out.purse["favourite"] = Net.clean_name(p.get("favourite"), 24, "")
	out["secs"] = clampf(Net.num(v.get("secs")), 0.0, 36000.0)
	out["won"] = _yes(v.get("won"))
	return out

## Seconds as a clock: 2:41.
static func clock(secs: float) -> String:
	var s := maxi(0, int(round(secs)))
	return "%d:%02d" % [s / 60, s % 60]
