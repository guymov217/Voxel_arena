class_name GateChoice
## The fight chosen at the gate (the campaign a different way each run, user). Before every bout
## the yard's gate offers two or three of the ladder's bouts (Ladder) from the stretch
## of eight the campaign has reached, none of them won yet this time round: the ladder's own (or,
## won already, the first of the stretch still to win); the crowd's fight, that bout with one more
## of its foes for double the prize; and another of the stretch's bouts drawn by the run (a beast
## hunt for a bout of men, men for a bout of beasts). Each bout is won once a time round, the
## stretches keep their order (their gear, their pay and their checkpoints are the stage's:
## Data.stage), and every run takes its own way through them. A boss's bout is no choice: which
## of the stretch's two bosses comes first is the run's draw (never in the last stretch: the
## Dragon ends it). Alone he picks the card of the fight he wants (GateScreen); a party picks each
## the card he wants, and the one most of them picked is fought (the host's, as many by two).
## DOM-free: the gate's cards show the fights, the menu starts what is chosen.

const BAND := 8   # a stretch of the ladder: two bosses, six bouts between

## Bout `b` of the ladder is a boss's.
static func boss_bout(b: int) -> bool:
	return (Ladder.bout(b).get("foes", []) as Array).any(func(f): return bool(f.get("boss", false)))

## Bout `b` is fought against beasts only.
static func beasts(b: int) -> bool:
	var bt := Ladder.bout(b)
	var foes: Array = (bt.get("foes", []) as Array) + (bt.get("late", []) as Array)
	return not foes.is_empty() and foes.all(func(f): return f.has("beast"))

## The crowd's fight can be made of bout `b`: one more of its first foe, unless he is someone (a
## named man, the Emperor: there is one of him).
static func crowd_ok(b: int) -> bool:
	var foes: Array = Ladder.bout(b).get("foes", [])
	return not foes.is_empty() and not boss_bout(b) and not (foes[0] as Dictionary).has("name") and not (foes[0] as Dictionary).has("title")

static func _rng(run_seed: int, salt: Array) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([run_seed] + salt)
	return r

## What the gate offers at `stage` of a run drawn by `run_seed`, with the ladder's bouts in `won`
## won already this time round: [{"bout": n, "kind": "ladder" | "crowd" | "other" | "boss"}]. The
## first is the one the gate itself leads to.
static func offers(stage: int, run_seed: int, won: Array) -> Array:
	var n := Ladder.BOUTS.size()
	stage = clampi(stage, 1, n)
	var done := won.map(func(x): return int(x))
	var lo := ((stage - 1) / BAND) * BAND + 1
	var hi := mini(lo + BAND - 1, n)
	if boss_bout(stage):
		var bosses := range(lo, hi + 1).filter(func(b): return boss_bout(b))
		var pick := stage
		if bosses.size() == 2 and hi < n and _rng(run_seed, ["boss", lo]).randi() % 2 == 1:
			pick = bosses[1] if stage == bosses[0] else bosses[0]
		return [{"bout": pick, "kind": "boss"}]
	var free := range(lo, hi + 1).filter(func(b): return not boss_bout(b) and not done.has(b))
	if free.is_empty():
		free = [stage]
	var first: int = stage if free.has(stage) else int(free[0])
	var out := [{"bout": first, "kind": "ladder"}]
	if crowd_ok(first):
		out.append({"bout": first, "kind": "crowd"})
	var others := free.filter(func(b): return b != first)
	if not others.is_empty():
		var unlike := others.filter(func(b): return beasts(b) != beasts(first))
		var pool: Array = unlike if not unlike.is_empty() else others
		out.append({"bout": int(pool[_rng(run_seed, ["other", stage]).randi_range(0, pool.size() - 1)]), "kind": "other"})
	return out

## The fight most of a party picked. `stands`: the fight each picked (-1 for none), the host's
## first. As many by two: the host's if his is one of them, else the first of them; nobody's
## pick: the first (the gate's own).
static func majority(stands: Array, n_offers: int) -> int:
	if n_offers <= 0:
		return 0
	var count := []
	count.resize(n_offers)
	count.fill(0)
	for s in stands:
		if int(s) >= 0 and int(s) < n_offers:
			count[int(s)] += 1
	var most: int = count.max()
	if most == 0:
		return 0
	var host := int(stands[0]) if not stands.is_empty() else -1
	if host >= 0 and host < n_offers and int(count[host]) == most:
		return host
	return count.find(most)

# ---------- The run's own, in the save ----------

## The save's key for the bouts won this time round (alone, or the party's: the host's save).
static func key(coop: bool) -> String:
	return "coop_gate_won" if coop else "gate_won"

static func won_list(coop: bool) -> Array:
	var v = Save.get_value(key(coop), [])
	return (v as Array).map(func(x): return int(x)) if v is Array else []

## The gate's offers now, as the save has the run (its seed, the time round, its stage).
static func now(coop: bool) -> Array:
	return at(int(Save.get_value("coop_stage" if coop else "stage", 1)), coop)

## The gate's offers at `stage` of the run in the save. (A run begun before there was a choice
## at the gate has no list of bouts won: it walked the ladder in order, the stretch's bouts before
## `stage` are won.)
static func at(stage: int, coop: bool) -> Array:
	var lap := int(Save.get_value("coop_lap" if coop else "lap", 1))
	return offers(stage, hash([int(Save.get_value("run_seed", 0)), lap]), _won_by(stage, coop))

## The bouts won by `stage` this time round: the list, or for a run with none the stretch's bouts
## walked in order before it.
static func _won_by(stage: int, coop: bool) -> Array:
	if Save.get_value(key(coop), null) == null:
		return range(((maxi(1, stage) - 1) / BAND) * BAND + 1, maxi(1, stage))
	return won_list(coop)

## Bout `b` won: not offered again this time round.
static func mark_won(b: int, coop: bool) -> void:
	var w := _won_by(int(Save.get_value("coop_stage" if coop else "stage", 1)), coop)
	if not w.has(b):
		w.append(b)
	Save.set_value(key(coop), w)

## A new time round (a new run; the rudis won and the ladder begun again): every bout to win again.
static func clear(coop: bool) -> void:
	Save.set_value(key(coop), [])
