class_name PartyGlory
## A party's own glory in the co-op campaign (the friends against one another too, not only the
## arena, user): after every bout won the crowd crowns the one of them who gave it the best show
## (the most favour: Spectacle), who brings the party's purse FAV_SHARE of the bout's prize more
## and wears a laurel through the next bout (Fighter.set_wreath); the run's scroll, kept bout by
## bout (who killed the most, who lifted the most friends, who left the most limbs on the sand, who
## was the crowd's favourite most often), unrolled when the run ends; and at the end of the ladder
## the Emperor's one rudis, the party voting to share the glory or to fight one another for it.
## DOM-free: the match counts, the menu keeps the scroll in the host's save and shows it.

const FAV_SHARE := 0.2
const FAV_MIN := 20.0    # the crowd's indifference (Spectacle: every man starts at it)
const TALLIES := ["kills", "lifts", "limbs"]
const HONOURS := ["kills", "lifts", "limbs", "fav"]
const MOST := 8          # names a scroll keeps (a room holds four; a run may see more come and go)

## The crowd's favourite of a party (`favour`: name -> the crowd's favour at the bout's end): the
## one it loved most, above indifference; "" alone, or when nobody gave it anything.
static func favourite(favour: Dictionary) -> String:
	if favour.size() < 2:
		return ""
	var best := ""
	var most := FAV_MIN
	for n in favour:
		if float(favour[n]) > most:
			best = String(n)
			most = float(favour[n])
	return best

## What the favourite brings the party's purse: FAV_SHARE of the bout's prize.
static func bonus(prize: int) -> int:
	return int(round(maxf(0.0, float(prize)) * FAV_SHARE))

## A bout's tallies (`bout`: name -> {kills, lifts, limbs}) set down on the run's scroll, a bout
## more for each of them, and the favourite's crown.
static func add_bout(scroll: Dictionary, bout: Dictionary, fav := "") -> Dictionary:
	var out := scroll.duplicate(true)
	for n in bout:
		var row: Dictionary = out.get(n, {})
		var b: Dictionary = bout[n] if bout[n] is Dictionary else {}
		for k in TALLIES:
			row[k] = int(row.get(k, 0)) + int(b.get(k, 0))
		row["bouts"] = int(row.get("bouts", 0)) + 1
		row["fav"] = int(row.get("fav", 0)) + (1 if String(n) == fav else 0)
		out[n] = row
	return out

## The scroll's honours: for each of HONOURS the one who leads it and by how many ([key, name, n]);
## none for what nobody did. (As many as two: the first on the scroll.)
static func honours(scroll: Dictionary) -> Array:
	var out := []
	for k in HONOURS:
		var best := ""
		var most := 0
		for n in scroll:
			var v := int((scroll[n] as Dictionary).get(k, 0)) if scroll[n] is Dictionary else 0
			if v > most:
				best = String(n)
				most = v
		if best != "":
			out.append([k, best, most])
	return out

## The party's word on the one rudis: "fight" when more would fight for it than share it; as many
## each, or nobody: shared.
static func verdict(votes: Array) -> String:
	return "fight" if votes.count("fight") > votes.count("share") else "share"

## A scroll from the wire (the host's), made safe: names as names (Net.clean_name), MOST of them,
## each tally a whole number 0..9999.
static func clean(v) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for n in (v as Dictionary).keys().slice(0, MOST):
		var row = v[n]
		if not (row is Dictionary):
			continue
		var r := {}
		for k in TALLIES + ["fav", "bouts"]:
			var x = (row as Dictionary).get(k, 0)
			r[k] = clampi(int(x), 0, 9999) if (x is int or x is float) and is_finite(float(x)) else 0
		out[Net.clean_name(n)] = r
	return out
