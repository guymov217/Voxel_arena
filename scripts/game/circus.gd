class_name Circus
## "Bread & Circuses": the seven-day campaign (campaign.js, blessings.js). The run state, the
## days and their bouts (data/modes.json), pay, the blessings of the gods picked after each day,
## Fortuna's wheel, the ludus upgrades bought between runs, the Daily Games seed and the Hall of
## Fame. No nodes: Match plays the bouts, the menu shows the screens.

const PLAYER_COLORS := [0xa02020, 0x2050b0, 0x208040, 0xc0a020]

static func days() -> Array:
	return Data.modes.get("days", [])

static func bout_count() -> int:
	var n := 0
	for d in days():
		n += d.bouts.size()
	return n

static func bout_at(day: int, bout: int) -> Dictionary:
	var ds := days()
	if day < 0 or day >= ds.size() or bout < 0 or bout >= ds[day].bouts.size():
		return {}
	return ds[day].bouts[bout]

static func current(run: Dictionary) -> Dictionary:
	return bout_at(int(run.day), int(run.bout))

## A new run: gold and items from the ludus, a seed (fixed for today's Daily Games).
static func new_run(ludus: Dictionary, daily := false) -> Dictionary:
	var st := ludus_start(ludus)
	var seed := daily_seed() if daily else randi()
	return {"version": 1, "seed": seed, "daily": daily, "day": 0, "bout": 0, "over": false, "won": false,
		"gold": st.gold, "inventory": st.inventory, "reroll": st.reroll, "blessings": [], "pluto_day": -1,
		"pending_blessing": [], "log": [], "kills": 0, "bouts_won": 0}

## More players: one extra copy of the first ordinary enemy for every extra player.
static func scaled_enemies(bout: Dictionary, players: int) -> Array:
	var list: Array = bout.get("enemies", []).duplicate(true)
	if list.is_empty():
		return list
	var extra: Dictionary = list[0]
	for e in list:
		if not e.get("boss", false):
			extra = e
			break
	for i in range(1, players):
		var c := extra.duplicate(true)
		c.boss = false
		list.append(c)
	return list

## Gold for a won bout.
static func reward(run: Dictionary, kills: int, favor: float, fast := false) -> int:
	var base := 25 + int(run.day) * 15 + (40 if current(run).get("boss", false) else 0)
	return int(round(base + kills * 12 + favor * 0.3 + (20 if fast else 0)))

## Record a bout; returns "next", "dayEnd", "victory", "wipe" or "spared" (Pluto sends you back
## once a day: the lost bout is fought again).
static func finish(run: Dictionary, win: bool, kills: int, pay: int) -> String:
	run.kills = int(run.kills) + kills
	run.log.append({"day": run.day, "bout": run.bout, "win": win})
	if not win:
		if run.blessings.has("pluto") and int(run.pluto_day) != int(run.day):
			run.pluto_day = run.day
			return "spared"
		run.over = true
		return "wipe"
	run.gold = int(run.gold) + pay
	run.bouts_won = int(run.bouts_won) + 1
	run.bout = int(run.bout) + 1
	if run.bout >= days()[run.day].bouts.size():
		run.bout = 0
		run.day = int(run.day) + 1
		if run.day >= days().size():
			run.over = true
			run.won = true
			return "victory"
		run.pending_blessing = roll_blessings(run, rng_for(run, "bless"))
		return "dayEnd"
	return "next"

# ---------- The gods ----------

static func blessings() -> Dictionary:
	return Data.modes.get("blessings", {})

## Three blessings the run does not have yet.
static func roll_blessings(run: Dictionary, r: RandomNumberGenerator) -> Array:
	var pool: Array = blessings().keys().filter(func(id): return not run.blessings.has(id))
	var out := []
	while out.size() < 3 and not pool.is_empty():
		out.append(pool.pop_at(r.randi_range(0, pool.size() - 1)))
	return out

static func grant(run: Dictionary, id: String) -> bool:
	if not blessings().has(id) or run.blessings.has(id):
		return false
	run.blessings.append(id)
	run.pending_blessing = []
	return true

## The fighter's mods for one bout from the run's blessings (and Fortuna's roll).
static func blessing_mods(run: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var mods := {}
	var fortune = null
	for id in run.blessings:
		var b: Dictionary = blessings().get(id, {})
		for k in b.get("mods", {}):
			var v = b.mods[k]
			mods[k] = (float(mods[k]) * float(v)) if (v is float or v is int) and (mods.get(k) is float or mods.get(k) is int) and k != "drunk" else v
		if id == "fortuna":
			var fs: Array = Data.modes.get("fortunes", [])
			if not fs.is_empty():
				fortune = fs[r.randi_range(0, fs.size() - 1)]
				for k in fortune.get("mods", {}):
					mods[k] = fortune.mods[k]
	return {"mods": mods, "fortune": fortune}

# ---------- The ludus (between runs) ----------

static func ludus_upgrades() -> Dictionary:
	return Data.modes.get("ludus", {})

static func ludus_price(id: String, lvl: int) -> int:
	match id:
		"purse": return 60 + lvl * 60
		"pot": return 80 + lvl * 80
		"reroll": return 150
		"bread": return 40 + lvl * 40
	return 9999

## null when bought, or why not.
static func buy_upgrade(ludus: Dictionary, id: String):
	var u: Dictionary = ludus_upgrades().get(id, {})
	if u.is_empty():
		return "Unknown upgrade"
	var lvl := int(ludus.levels.get(id, 0))
	if lvl >= int(u.get("max", 1)):
		return "Already maxed"
	var price := ludus_price(id, lvl)
	if int(ludus.denarii) < price:
		return "Not enough denarii"
	ludus.denarii = int(ludus.denarii) - price
	ludus.levels[id] = lvl + 1
	return null

static func empty_ludus() -> Dictionary:
	return {"denarii": 0, "levels": {}, "runs": 0}

static func ludus_start(ludus: Dictionary) -> Dictionary:
	var l: Dictionary = ludus.get("levels", {})
	var inv := {}
	if int(l.get("pot", 0)) > 0:
		inv["thunderPot"] = int(l.pot)
	if int(l.get("bread", 0)) > 0:
		inv["bread"] = int(l.bread)
	return {"gold": 30 + 20 * int(l.get("purse", 0)), "inventory": inv, "reroll": int(l.get("reroll", 0)) > 0}

## What a finished run leaves in the ludus: half the gold, 10 per bout won, 200 for the crown.
static func payout(run: Dictionary) -> int:
	return int(round(int(run.gold) * 0.5 + int(run.bouts_won) * 10 + (200 if run.won else 0)))

# ---------- Daily Games and the Hall of Fame ----------

static func daily_label() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%d-%d-%d" % [d.year, d.month, d.day]

static func daily_seed() -> int:
	var h := 2166136261
	for ch in daily_label().to_utf8_buffer():
		h = ((h ^ ch) * 16777619) & 0xffffffff
	return h

## A random stream for one purpose, the same for everyone on a daily run.
static func rng_for(run: Dictionary, tag: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	if run.get("daily", false):
		r.seed = hash("%d:%s:%d:%d" % [int(run.seed), tag, int(run.day), int(run.bout)])
	else:
		r.randomize()
	return r

## The Hall of Fame keeps the ten best runs: furthest first, then most kills.
static func hall_add(hall: Array, name_: String, run: Dictionary, fate: String) -> Array:
	var h := hall.duplicate(true)
	h.append({"name": name_, "day": int(run.day) + (0 if run.won else 1), "won": run.won, "kills": int(run.kills),
		"bouts": int(run.bouts_won), "fate": fate, "daily": run.get("daily", false), "date": daily_label()})
	h.sort_custom(func(a, b): return a.bouts > b.bouts or (a.bouts == b.bouts and a.kills > b.kills))
	return h.slice(0, 10)
