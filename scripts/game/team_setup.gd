class_name TeamSetup
extends RefCounted
## The teams of a team fight, chosen in the yard (the lobby): a circle on the sand for each team, and each player walks into the
## one he plays for. When everybody in the room stands in a circle the host may begin; a team with no player in it is filled
## with bots. Pure logic, DOM-free: where the circles are, who stands in which, whether the fight may begin and what it says;
## the yard (YardPlay) feeds it the players' places and puts the circles on the sand, and tells the guests `state`.

const MODES := ["teams"]
const TEAMS := 2
const RADIUS := 2.4
## Red to the left, Blue to the right (the same sides the fight starts on).
const CENTRES := [Vector3(-4.6, 0.0, 1.0), Vector3(4.6, 0.0, 1.0)]
const COLORS := [Color(0.88, 0.2, 0.16), Color(0.22, 0.42, 0.92)]
const MOST_NAMES := 8

var mode := "teams"
var opts := {}     # what the fight is started with besides the teams (its rounds, its bots)
var places := {}   # who (a peer's id; 1 for the host) -> {"name", "x", "z"}

func _init(mode_ := "teams", opts_ := {}) -> void:
	mode = mode_ if MODES.has(mode_) else "teams"
	opts = opts_.duplicate()

static func is_team_mode(mode_: String) -> bool:
	return MODES.has(mode_)

## The circle a place on the sand is in (-1: none).
static func ring_at(x: float, z: float) -> int:
	for i in TEAMS:
		if Vector2(x - (CENTRES[i] as Vector3).x, z - (CENTRES[i] as Vector3).z).length() < RADIUS:
			return i
	return -1

static func team_name(team: int) -> String:
	return Series.team_name(team)

## Where a player stands now.
func set_place(who: int, name_: String, x: float, z: float) -> void:
	places[who] = {"name": name_, "x": x, "z": z}

## A player who left.
func forget(who: int) -> void:
	places.erase(who)

func team_of(who: int) -> int:
	var p: Dictionary = places.get(who, {})
	return ring_at(float(p.x), float(p.z)) if not p.is_empty() else -1

## Who is in a team's circle, by name, in the order they came into the room.
func members(team: int) -> Array:
	var out := []
	var ids := places.keys()
	ids.sort()
	for id in ids:
		if team_of(int(id)) == team:
			out.append(String(places[id].name))
	return out

## Who is not in a circle yet.
func waiting() -> Array:
	var out := []
	var ids := places.keys()
	ids.sort()
	for id in ids:
		if team_of(int(id)) < 0:
			out.append(String(places[id].name))
	return out

## Everybody stands in a circle: the host may begin.
func ready() -> bool:
	return not places.is_empty() and waiting().is_empty()

## The team of each player, for the fight (those not in a circle are left out).
func assignment() -> Dictionary:
	var out := {}
	for id in places:
		var t := team_of(int(id))
		if t >= 0:
			out[int(id)] = t
	return out

## What the host is told while the teams are chosen.
func why_not() -> String:
	var w := waiting()
	if places.is_empty():
		return Loc.t("Nobody is here")
	if not w.is_empty():
		return Loc.t("Waiting for %s to pick a team") % ", ".join(w.slice(0, 3))
	return ""

## The one line on the screen, for the host and for every guest (from `state`: the guest reads what the host said).
static func line_of(st: Dictionary, host: bool) -> String:
	if bool(st.get("ok", false)):
		return Loc.t("Everyone is in a circle · E: begin") if host else Loc.t("Everyone is in a circle")
	var w: Array = st.get("w", [])
	return (Loc.t("Waiting for %s") % ", ".join(w.slice(0, 3))) if not w.is_empty() else ""

func line(host: bool) -> String:
	return line_of(state(), host)

## What the guests are told (and the yard reads back, made safe by `clean_state`): the fight, its rounds, who is in each circle
## and who is still out, and whether the host may begin.
func state() -> Dictionary:
	return {"m": mode, "r": int(opts.get("rounds", 0)), "t": [members(0), members(1)], "w": waiting(), "ok": ready()}

static func clean_state(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("t") is Array) or (v.t as Array).size() != TEAMS:
		return {}
	var out := {"m": str(v.get("m", "teams")) if MODES.has(str(v.get("m", ""))) else "teams", "r": 1, "t": [], "w": [], "ok": v.get("ok") == true}
	var r = v.get("r", 1)
	out.r = clampi(int(r), 0, Series.MOST) if (r is int or r is float) and is_finite(float(r)) else 1
	for side in v.t:
		(out.t as Array).append((side as Array).slice(0, MOST_NAMES).map(func(n): return Net.clean_name(n)) if side is Array else [])
	if v.get("w") is Array:
		out.w = (v.w as Array).slice(0, MOST_NAMES).map(func(n): return Net.clean_name(n))
	return out

## The sign over a circle: the team's name and who stands in it.
static func sign_text(team: int, names: Array) -> String:
	return "%s\n%s" % [team_name(team).to_upper(), "\n".join(names.slice(0, 5))] if not names.is_empty() else team_name(team).to_upper()

## `n` bots, each to the smaller side (the first to Red when they are level), as the team of each bot, one by one.
static func balance_plan(counts: Array, n: int) -> Array:
	var c := counts.duplicate()
	var out := []
	for i in n:
		var t := 0
		for k in c.size():
			if int(c[k]) < int(c[t]):
				t = k
		c[t] = int(c[t]) + 1
		out.append(t)
	return out

## The bots that fill the sides: each side to the size of the biggest (at least two to a side), as the team of each bot, one by one.
static func fill_plan(counts: Array) -> Array:
	var most := 2
	for c in counts:
		most = maxi(most, int(c))
	var out := []
	for team in counts.size():
		for k in most - int(counts[team]):
			out.append(team)
	return out

## Where a side's fighters start: in a line on their side of the sand, facing the middle (Red to the left, Blue to the right).
static func spawn_pos(team: int, k: int, n: int) -> Vector3:
	var side := -1.0 if team == 0 else 1.0
	return Vector3(side * 4.5, 0.02, (float(k) - float(n - 1) / 2.0) * 2.0)
