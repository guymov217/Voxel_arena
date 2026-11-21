class_name Series
extends RefCounted
## A fight played over several rounds (the host's "Rounds" for a fight in the Arena): who won each round, the score,
## and when the match is decided. Pure logic, DOM-free. The one who hosts (or plays alone) keeps it between bouts
## (Menu), each bout and each round's end tell it to the guests (`to_dict`), who read it back made safe (`clean`).
##
## Every fight has a rounds setting, each in its own sense (`kind`):
##   "series": a bout of the fight is a round, the one who wins it a point; all the rounds are played (the match ends
##             early when nobody can catch the leader), most rounds wins; level after the last, up to MAX_EXTRA deciding
##             rounds more, then a draw.
##   "own":    the fight counts for itself: best of N (the duel with its yield), the reign to win (King of the Arena).
##   "waves":  clear N waves to win (the hunt, the waves of gladiators); 0: until you fall.
## A fight with none of these (the endless arena, the campaign) has no rounds setting.

const SERIES_MODES := ["ffa", "teams", "forgefight", "lastLimb", "hill", "emperor", "tourney"]
const OWN_MODES := ["bo3", "king"]
const WAVE_MODES := ["hunt"]
const MOST := 9
const MAX_EXTRA := 2          # level after the last round: this many deciding rounds more, then a draw
const MOST_KEYS := 8          # (a room of eight; more is not kept)

var rounds := 1               # the number chosen
var played := 0               # rounds finished
var extra := 0                # deciding rounds added after a level finish
var wins := {}                # who (a key) -> rounds won
var names := {}               # who -> how he is called

func _init(n := 1) -> void:
	rounds = clampi(n, 1, MOST)

# ---------- What a fight's setting means ----------

static func kind(mode: String) -> String:
	if SERIES_MODES.has(mode):
		return "series"
	if OWN_MODES.has(mode):
		return "own"
	if WAVE_MODES.has(mode):
		return "waves"
	return ""

## What a fight is played to unless the host says otherwise: one bout; the duel's three; the king's seven; the waves without end.
static func default_rounds(mode: String) -> int:
	match mode:
		"bo3": return 3
		"king": return 7
	return 0 if WAVE_MODES.has(mode) else 1

## The numbers on offer for a fight (empty: it has no setting).
static func choices(mode: String) -> Array:
	match kind(mode):
		"series": return [1, 3, 5, 7, 9]
		"own": return [3, 5, 7, 9]
		"waves": return [0, 3, 5, 7, 10]
	return []

## What the host asked for, made safe: one of the numbers on offer, else the fight's own.
static func clean_rounds(mode: String, v) -> int:
	var on := choices(mode)
	if on.is_empty():
		return 0
	if (v is int or v is float) and is_finite(float(v)) and on.has(int(v)):
		return int(v)
	return default_rounds(mode)

## The setting as it reads on a card: "Best of 5", "Reign: 7", "5 waves", "Until you fall".
static func label(mode: String, n: int) -> String:
	match kind(mode):
		"series": return Loc.t("1 round") if n <= 1 else Loc.t("%d rounds") % n
		"own": return (Loc.t("Best of %d") % n) if mode == "bo3" else (Loc.t("Reign of %d") % n)
		"waves": return Loc.t("Until you fall") if n <= 0 else Loc.t("%d waves") % n
	return ""

# ---------- The score ----------

## The round just fought was won by `key` ("": nobody).
func record(key: String, name: String) -> void:
	played += 1
	if key != "":
		if not wins.has(key) and wins.size() >= MOST_KEYS:
			pass   # (a room has no more than eight: the rest are not counted)
		else:
			wins[key] = int(wins.get(key, 0)) + 1
			names[key] = name.left(24)
	if played >= rounds + extra and leaders().size() != 1 and extra < MAX_EXTRA:
		extra += 1

func total() -> int:
	return rounds + extra

func left() -> int:
	return maxi(0, total() - played)

func round_now() -> int:
	return played + 1

func best() -> int:
	var b := 0
	for k in wins:
		b = maxi(b, int(wins[k]))
	return b

## Those with the most rounds (none while nobody has won one).
func leaders() -> Array:
	var b := best()
	var out := []
	if b <= 0:
		return out
	for k in wins:
		if int(wins[k]) == b:
			out.append(k)
	out.sort()
	return out

## How far the leader is ahead of the next.
func lead() -> int:
	var b := best()
	var second := 0
	for k in wins:
		var w := int(wins[k])
		if w < b:
			second = maxi(second, w)
		elif w == b and leaders().size() > 1:
			second = b
	return b - second

## No round more to play: all of them were, or nobody can catch the leader.
func decided() -> bool:
	if played >= total():
		return true
	return lead() > left()

## Who won the match ("": a draw).
func winner() -> String:
	var l := leaders()
	return String(l[0]) if decided() and l.size() == 1 else ""

func name_of(key: String) -> String:
	return String(names.get(key, key))

## "Aulus 2 : 1 Brutus" for two, "Aulus 2 · Brutus 1 · Cato 0" for more.
func score_line() -> String:
	var keys := wins.keys()
	keys.sort_custom(func(a, b): return int(wins[a]) > int(wins[b]) or (int(wins[a]) == int(wins[b]) and String(a) < String(b)))
	if keys.is_empty():
		return Loc.t("no rounds won yet")
	if keys.size() == 2:
		return "%s %d : %d %s" % [name_of(keys[0]), int(wins[keys[0]]), int(wins[keys[1]]), name_of(keys[1])]
	return " · ".join(keys.slice(0, 4).map(func(k): return "%s %d" % [name_of(k), int(wins[k])]))

## "Round 2 of 5", or the deciding round's own words.
func round_text() -> String:
	if played >= rounds:
		return Loc.t("Deciding round")
	return Loc.t("Round %d of %d") % [round_now(), rounds]

## The line under a fight's name on the HUD: "Round 2 of 5 · Aulus 1 : 1 Brutus".
func hud_line() -> String:
	return "%s · %s" % [round_text(), score_line()] if not wins.is_empty() else round_text()

## What the match ends on: "Aulus wins the match 3 : 1", or the draw.
func final_text() -> String:
	var w := winner()
	return (Loc.t("%s wins the match") % name_of(w)) if w != "" else Loc.t("The match is a draw")

# ---------- On the wire ----------

func to_dict() -> Dictionary:
	return {"n": rounds, "p": played, "x": extra, "w": wins.duplicate(), "nm": names.duplicate()}

static func from_dict(v) -> Series:
	var d := clean(v)
	var s := Series.new(int(d.get("n", 1)))
	if d.is_empty():
		return s
	s.played = int(d.p)
	s.extra = int(d.x)
	s.wins = (d.w as Dictionary).duplicate()
	s.names = (d.nm as Dictionary).duplicate()
	return s

## A series as it is told (the host's start and round-end messages, or the host's own copy): numbers within their bounds,
## keys and names short, eight of them at most. {} for anything that is not one.
static func clean(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("n") is int or v.get("n") is float):
		return {}
	var n = v.get("n", 1)
	if not is_finite(float(n)):
		return {}
	var out := {"n": clampi(int(n), 1, MOST), "p": 0, "x": 0, "w": {}, "nm": {}}
	var p = v.get("p", 0)
	var x = v.get("x", 0)
	out.p = clampi(int(p), 0, MOST + MAX_EXTRA) if (p is int or p is float) and is_finite(float(p)) else 0
	out.x = clampi(int(x), 0, MAX_EXTRA) if (x is int or x is float) and is_finite(float(x)) else 0
	var w = v.get("w")
	var nm = v.get("nm")
	if w is Dictionary:
		for k in (w as Dictionary).keys():
			if out.w.size() >= MOST_KEYS:
				break
			var val = w[k]
			if (k is String) and (val is int or val is float) and is_finite(float(val)):
				var key := String(k).left(24)
				out.w[key] = clampi(int(val), 0, MOST + MAX_EXTRA)
				out.nm[key] = Net.clean_name(nm[k]) if nm is Dictionary and (nm as Dictionary).get(k) is String else key
	return out

# ---------- Who a round is for ----------

static func human_key(peer: int) -> String:
	return "p%d" % peer

static func bot_key(name: String) -> String:
	return "b" + name.left(20)

static func team_key(team: int) -> String:
	return "t%d" % team

static func team_name(team: int) -> String:
	return Loc.t(["Red", "Blue", "Green", "Yellow"][clampi(team, 0, 3)])
