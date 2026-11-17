class_name Market
## The trader's table (user: a new ware after every boss beaten, the wares in tabs by what they
## do, the Hand of Jupiter dearer as the purses grow). DOM-free: the market screen shows it, the
## tests read it. Training has every ware, free (the menu's own bag); the physician sells the
## supplies used on yourself (bandages, bread, wine, the water skin).

## The tabs: id, name, and the wares in the order they lie on the table.
const TABS := [
	["fire", "Fire & blast", ["thunderPot", "nailPot", "greekFire", "vitriol", "torch"]],
	["floor", "Floor traps", ["bananas", "caltrops", "oliveOil", "honey"]],
	["snare", "Snares & tricks", ["smoke", "garum", "bola", "bigNet", "harpoon", "telekinesis"]],
	["arms", "Thrown arms", ["darts", "discus", "boomerang", "anvil"]],
	["crowd", "For the crowd", ["goat", "cheese", "chickens", "mystery"]],
]
## On the table from the first visit: something of every tab.
const BASIC := ["thunderPot", "nailPot", "smoke", "bananas", "caltrops", "oliveOil", "darts", "mystery"]
## One more brought after each boss beaten, in this order (the first after the first boss); the
## last boss's bout ends the campaign, and from the second time round everything is there.
const AFTER_BOSS := ["torch", "goat", "bola", "greekFire", "cheese", "honey", "discus", "garum", "harpoon", "vitriol", "boomerang", "bigNet", "anvil", "chickens", "telekinesis"]

## The trader's road: what each boss brings, in the order they come, with the bout whose boss
## brings it and whether it is on the table yet (`opened` brought so far); the next to come is marked.
static func road(opened: int) -> Array:
	var out := []
	for i in AFTER_BOSS.size():
		var id: String = AFTER_BOSS[i]
		out.append({"id": id, "bout": comes_after(id), "brought": i < opened, "next": i == opened})
	return out

static func tab_of(id: String) -> String:
	for t in TABS:
		if (t[2] as Array).has(id):
			return t[0]
	return ""

static func wares(tab: String) -> Array:
	for t in TABS:
		if t[0] == tab:
			return t[2]
	return []

## The bosses beaten by the time a run is at `stage` (the bout it is on) of time round `lap`: the
## boss bouts behind it (whichever of a stretch's two bosses the gate drew first: GateChoice), or
## all of them once round.
static func bosses_beaten(stage: int, lap: int) -> int:
	if lap >= 2:
		return AFTER_BOSS.size()
	var n := 0
	for b in range(1, clampi(stage, 1, Ladder.BOUTS.size() + 1)):
		if GateChoice.boss_bout(b):
			n += 1
	return mini(n, AFTER_BOSS.size())

## On the table with `opened` wares brought past the basics (a ware not in the plan is too).
static func is_open(id: String, opened: int) -> bool:
	var i := AFTER_BOSS.find(id)
	return BASIC.has(id) or i < 0 or i < opened

## The bout whose boss brings `id` (0: on the table from the start).
static func comes_after(id: String) -> int:
	var i := AFTER_BOSS.find(id)
	if i < 0:
		return 0
	var seen := 0
	for b in range(1, Ladder.BOUTS.size() + 1):
		if GateChoice.boss_bout(b):
			seen += 1
			if seen == i + 1:
				return b
	return 0

static func _key(coop: bool) -> String:
	return "coop_market_open" if coop else "market_open"

## The wares brought past the basics, as the save has it (alone and in a party apart).
static func saved(coop: bool) -> int:
	var v = Save.get_value(_key(coop), 0)
	return clampi(int(v), 0, AFTER_BOSS.size()) if (v is int or v is float) and is_finite(float(v)) else 0

## The wares brought past the basics now: one for each boss beaten, or more if the table had more
## before (a death that sent him back takes nothing off it). Kept in the save.
static func opened(coop: bool, stage: int, lap: int) -> int:
	var n := maxi(saved(coop), bosses_beaten(stage, lap))
	if n != saved(coop):
		Save.set_value(_key(coop), n)
	return n

## What `id` costs at `stage`: its list price; the Hand of Jupiter's, nine tenths of the best purse
## a bout has paid by then (its two lifts a bout cost next to nothing once the purses grew).
static func price(id: String, list_price: int, stage: int) -> int:
	if id != "telekinesis":
		return list_price
	var best := 0
	for n in range(1, clampi(stage, 1, maxi(1, (Data.campaign.get("stages", []) as Array).size())) + 1):
		var st: Dictionary = Data.stage(n)
		best = maxi(best, int(round(float(st.get("stagePay", 30)) * Match.PAY_SCALE)) + int(round(float(st.get("roundPay", 10)) * Match.PAY_SCALE)))
	return maxi(list_price, int(round(0.9 * best / 5.0)) * 5)
