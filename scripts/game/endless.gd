class_name Endless
extends RefCounted
## The endless arena, to the last breath: wave after wave of men and beasts drawn at random,
## more of them and harder as the waves go, a great foe every BOSS_EVERY waves, until the player
## falls. Between waves he is patched up a little and takes one of three rewards (`offer`: the
## menu shows it, take() gives it). Today's challenge (`daily`) draws the same waves for everyone
## on the same day. The best wave is kept (Save "endless") and, with Steam, put on its board.
## In the demo the waves come from the demo's own men and beasts and its two great foes
## (Edition): what the full game holds beyond them is only counted, on the last screen. Host side;
## `m` is the Match.

const BOSS_EVERY := 5
const REST_HEAL := 35.0      # blood back as a wave is beaten (the breath all, the wounds closed)
const START_DELAY := 3.0     # from the pick to the horn
const KEEP_LOOSE := 12       # weapons left lying on the sand, the newest (the rest are cleared)
## The weapons a gladiator of the waves may be handed: the campaign's ladder of arms (what the
## demo's own bouts already show), one-handed and two-handed, the second blade of a man with two,
## and the shields.
const ONE_HAND := ["dagger", "fish", "chicken", "javelin", "plank", "gladius", "hammer", "axe", "chair", "mace"]
const TWO_HAND := ["spear", "trident", "longsword", "executionerAxe", "zweihander", "warhammer"]
const SIDEARM := ["dagger", "gladius", "axe", "mace", "hammer"]
const SHIELDS := ["roundShield", "scutum"]
## The weapons a reward may be: real ones (a rubber chicken is a foe's joke, not a prize).
const PRIZE_ARMS := ["gladius", "axe", "mace", "hammer", "spear", "trident", "longsword", "executionerAxe", "zweihander", "warhammer"]
## What a man of the waves may wear from which wave on.
const ARMOUR_BY_WAVE := [[4, "helmet"], [7, "manica"], [10, "greaves"], [13, "lorica"]]
## The campaign's great men: a boss wave's, never an ordinary one's.
const GREAT := ["cyclops", "giant", "minotaur", "troll", "titan", "emperor"]
## Men who keep their own arms: the archer his bow, the net-man his trident, the medicus his
## satchel, the fire-thrower his pole, the flail-man his flail, the skirmisher his javelins.
const OWN_ARMS := ["sagittarius", "retiarius", "medicus", "pyro", "flailman", "veles"]
## The great beasts come only as a boss wave's (and the decoy goat never).
const BIG_BEASTS := ["goat", "elephant", "mammoth", "dragon", "hydra", "cerberus", "griffin", "chimera", "manticore", "basilisk", "rhino"]
## The first waves' beasts.
const WEAK_BEASTS := ["rat", "hyena", "wolf", "boar", "ostrich"]
## The pots the stands may throw down between waves, and the armour a reward may be.
const POTS := ["thunderPot", "nailPot", "greekFire", "sandPot", "vitriol", "bola"]
const PIECES := ["helmet", "manica", "greaves", "lorica"]

signal offered(rewards: Array)

var m: Node
var daily := false
var day := ""                 # the date of today's challenge (UTC), "" in a free run
var seed_base := 0
var wave := 0
var phase := "next"           # "next": the horn to come; "fight"; "rest": the offer up; "over"
var next_t := START_DELAY
var offer: Array = []         # the rewards on offer while resting
var slain := 0
var rng := RandomNumberGenerator.new()

func _init(match_: Node, opts: Dictionary) -> void:
	m = match_
	daily = bool(opts.get("daily", false))
	day = Time.get_date_string_from_system(true) if daily else ""
	seed_base = hash("endless:" + day) if daily else int(opts.get("seed", randi()))
	rng.seed = seed_base

## Who the waves are drawn from: the men (by campaign type), the beasts, the great foes (as the
## campaign's own boss entries); in the demo only what its bouts bring.
static func pool() -> Dictionary:
	var men: Array = Data.campaign.get("enemies", {}).keys()
	var beasts: Array = Data.beasts.keys()
	men = men.filter(func(k): return not GREAT.has(k) and Edition.foe_open("foe:" + String(k)))
	beasts = beasts.filter(func(k): return not BIG_BEASTS.has(k) and Edition.foe_open(String(k)))
	var bosses: Array = great_foes().filter(func(b): return _open(b))
	return {"men": men, "beasts": beasts, "bosses": bosses}

## The campaign's great foes in the order its bouts bring them (the Big Lion before the Cyclops).
static func great_foes() -> Array:
	var titles := []
	for s in Data.campaign.get("stages", []):
		if s.get("boss", false):
			titles.append(String(s.get("byPlayers", {}).get("1", {}).get("title", "")))
	var at := func(b) -> int:
		var i := titles.find(String(b.get("title", "")))
		return i if i >= 0 else 999
	var out: Array = (Data.campaign.get("bosses", []) as Array).duplicate()
	out.sort_custom(func(a, b): return at.call(a) < at.call(b))
	return out

static func _open(b: Dictionary) -> bool:
	return Edition.foe_open("foe:" + String(b.e)) if b.has("e") else Edition.foe_open(String(b.get("beast", "")))

## How many great foes the demo keeps back for the full game (named on its last screen by
## their number alone).
static func held_back() -> int:
	return great_foes().filter(func(b): return not _open(b)).size() if Edition.demo() else 0

## Wave `n` as Match.enemy_spec entries ({"e": type} a man, {"beast": key} a beast, "boss"),
## the same for the same seed and wave (today's challenge is everyone's).
func plan(n: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_base, n])
	var p := pool()
	var out := []
	if n % BOSS_EVERY == 0 and not p.bosses.is_empty():
		var b: Dictionary = (p.bosses[(n / BOSS_EVERY - 1) % p.bosses.size()] as Dictionary).duplicate(true)
		b.erase("title")
		b.boss = true
		out.append(b)
		# From the second great foe on, he does not come alone.
		for k in mini(2, (n - BOSS_EVERY) / BOSS_EVERY):
			out.append(_one(r, n, p))
		return out
	for k in clampi(1 + (n - 1) / 3, 1, 4):
		out.append(_one(r, n, p))
	return out

func _one(r: RandomNumberGenerator, n: int, p: Dictionary) -> Dictionary:
	var beasts: Array = p.beasts
	if n < 4:
		var weak := beasts.filter(func(k): return WEAK_BEASTS.has(k))
		if not weak.is_empty():
			beasts = weak
	if n >= 2 and not beasts.is_empty() and (p.men.is_empty() or r.randf() < 0.35):
		return {"beast": beasts[r.randi_range(0, beasts.size() - 1)]}
	return {"e": p.men[r.randi_range(0, p.men.size() - 1)]}

## A gladiator of the waves takes up whatever comes to hand: a blade and a shield, a blade in
## each hand, one great two-handed weapon, or a blade alone, the better the later the wave
## (the campaign's ladder of arms and its budget, Match.weapon_budget).
static func arms(r: RandomNumberGenerator, n: int) -> Dictionary:
	var cap := Match.weapon_budget(1 + n)
	var fits := func(k): return Match.ladder_power(String(k)) <= cap
	var one := ONE_HAND.filter(fits)
	var two := TWO_HAND.filter(fits)
	var side := SIDEARM.filter(fits)
	if one.is_empty():
		one = ["dagger"]
	if side.is_empty():
		side = ["dagger"]
	var main: String = one[r.randi_range(0, one.size() - 1)]
	var roll := r.randf()
	if roll < 0.3:
		return {"main": main, "off": side[r.randi_range(0, side.size() - 1)]}
	if roll < 0.55:
		return {"main": main, "off": SHIELDS[r.randi_range(0, SHIELDS.size() - 1)]}
	if roll < 0.78 and not two.is_empty():
		return {"main": two[r.randi_range(0, two.size() - 1)], "off": ""}
	return {"main": main, "off": ""}

## The weapon a reward after wave `n` holds out: a real one, within the budget of a few waves on
## and not far below it (Match.ladder_weapon's rule), the best few once the budget buys any.
static func prize(r: RandomNumberGenerator, n: int) -> String:
	var cap := Match.weapon_budget(4 + n)
	var pool := PRIZE_ARMS.filter(func(k): return Match.ladder_power(k) <= cap and Match.ladder_power(k) >= cap * 0.4)
	if pool.is_empty():
		var by := PRIZE_ARMS.duplicate()
		by.sort_custom(func(a, b): return Match.ladder_power(a) > Match.ladder_power(b))
		pool = by.filter(func(k): return Match.ladder_power(k) <= cap).slice(0, 4)
	if pool.is_empty():
		pool = ["gladius"]
	return pool[r.randi_range(0, pool.size() - 1)]

# ---------- Each step (Modes.update / Modes.check) ----------

func begin() -> void:
	phase = "next"
	next_t = START_DELAY
	m._banner("To the last breath!", Loc.t("Today's challenge: the same waves for everyone") if daily else "Wave after wave, until you fall")

func update(dt: float) -> void:
	if phase == "next":
		next_t -= dt
		if next_t <= 0.0:
			_spawn_wave()

func check(_dt: float, alive: Array, humans_alive: Array) -> void:
	if phase == "over":
		return
	if humans_alive.is_empty():
		_fall()
		return
	if phase != "fight":
		return
	if not alive.any(func(e): return int(e.team) == Match.ENEMY_TEAM):
		_beaten()

func status() -> String:
	match phase:
		"rest":
			return Loc.t("Wave %d beaten!") % wave
		"next":
			return Loc.t("Wave %d in %d") % [wave + 1, ceili(maxf(0.0, next_t))]
	return Loc.t("Wave %d · %d slain") % [wave, slain]

func _spawn_wave() -> void:
	wave += 1
	phase = "fight"
	_clear_old()
	var list := plan(wave)
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_base, wave, "arms"])
	var names := []
	for i in list.size():
		var en: Dictionary = list[i]
		var spec: Dictionary = m.enemy_spec(en, i, list.size())
		var e
		if spec.kind == "beast":
			spec.scale = float(spec.scale) * (1.0 + minf(0.25, 0.01 * wave))
			e = m.spawn_beast(spec)
		else:
			_arm(spec, en, r)
			e = m.spawn_fighter(spec)
		if e:
			e["endless_wave"] = wave
			names.append(String(e.f.display_name))
	m._open_gates(list.size())
	var boss: bool = list.any(func(x): return x.get("boss", false))
	m._banner(Loc.t("Wave %d") % wave, ", ".join(names))
	if boss:
		m.feed.emit(Loc.t("A great foe walks in: %s!") % names[0])
	# The music the wave calls for (as Menu.fight_mood): a great foe's, a beast hunt's, a fight's.
	if Sfx.music and not m.headless:
		Sfx.music.set_state("boss" if boss else ("beast" if list.all(func(x): return x.has("beast")) else "fight"))

## A man of the waves: his arms at random (but the ones who keep their own), his armour and his
## skill by the wave.
func _arm(spec: Dictionary, en: Dictionary, r: RandomNumberGenerator) -> void:
	var lo: Dictionary = spec.get("loadout", {})
	if not en.get("boss", false) and not OWN_ARMS.has(String(en.get("e", ""))):
		var a := arms(r, wave)
		lo.main = Data.preset(a.main)
		lo.off = Data.preset(a.off) if a.off != "" else {}
	var armor: Array = (lo.get("armor", []) as Array).duplicate()
	for step in ARMOUR_BY_WAVE:
		if wave >= int(step[0]) and r.randf() < 0.6 and not armor.has(step[1]):
			armor.append(step[1])
	lo.armor = armor
	spec.loadout = lo
	spec.diff = clampf(float(spec.get("diff", 0.8)) * (0.75 + 0.03 * wave), 0.4, 1.1)
	var mods: Dictionary = spec.get("mods", {})
	mods.toughness = float(mods.get("toughness", 1.0)) * (1.0 + minf(0.6, 0.03 * (wave - 1)))
	spec.mods = mods

## The fallen of two waves back are carried off, and the oldest weapons lying about cleared (a
## run is long: the sand was a heap of bodies and blades and the game crawled).
func _clear_old() -> void:
	for e in m.entities.duplicate():
		if int(e.get("endless_wave", 0)) > 0 and int(e.endless_wave) <= wave - 2 and not e.f.alive:
			m._remove_entity(e)
	var loose: Array = m.combat.loose_weapons.filter(func(w): return is_instance_valid(w) and w.holder == null)
	while loose.size() > KEEP_LOOSE:
		var w = loose.pop_front()
		m.combat.loose_weapons.erase(w)
		w.queue_free()

func _beaten() -> void:
	phase = "rest"
	# Those of the wave still breathing but out of the fight (down for good, Match._unfit) are
	# finished: none of them gets up behind the player's back in the next one.
	for e in m.enemies():
		if is_instance_valid(e.f) and e.f.alive:
			e.f.die("wounds")
	slain += m.entities.filter(func(e): return int(e.get("endless_wave", 0)) == wave).size()
	var you = m.me
	if you and is_instance_valid(you.f):
		var f: Fighter = you.f
		f.blood = minf(100.0, f.blood + REST_HEAL)
		f.stamina = 100.0
		for p in f.parts:
			if not p.severed:
				p.bleed = 0.0
				p.artery = 0.0
	_record()
	offer = rewards()
	m.sfx("horn", Vector3.ZERO)
	offered.emit(offer)

## Three of the rewards, as they may be had now: no mending of whole weapons, no armour already
## worn. Each {id, title, text, arg}.
func rewards() -> Array:
	var f = m.me.f if m.me and is_instance_valid(m.me.f) else null
	var can := ["bind", "pot"]
	if f and _free_right(f):
		can.append("blade")
	if f and _chipped(f):
		can.append("mend")
	var pieces := _pieces_left(f) if f else []
	if not pieces.is_empty():
		can.append("armour")
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_base, wave, "rewards"])
	var out := []
	while out.size() < 3 and not can.is_empty():
		var id: String = can.pop_at(r.randi_range(0, can.size() - 1))
		match id:
			"bind":
				out.append({"id": id, "title": "Bind your wounds", "text": "Your bones set, your wounds bound, all your blood back"})
			"mend":
				out.append({"id": id, "title": "Mend your weapons", "text": "Every chip and crack made good"})
			"pot":
				var pot: String = POTS[r.randi_range(0, POTS.size() - 1)]
				out.append({"id": id, "arg": pot, "title": "A gift from the stands", "text": Loc.t("Two × %s") % Loc.t(String(Data.shop.throwables.get(pot, {}).get("name", pot)))})
			"blade":
				var key := prize(r, wave)
				out.append({"id": id, "arg": key, "title": "A new weapon", "text": Loc.t("%s in your right hand (yours is left on the sand)") % Loc.t(String(Data.preset(key).get("name", key)))})
			"armour":
				var piece: String = pieces[r.randi_range(0, pieces.size() - 1)]
				out.append({"id": id, "arg": piece, "title": "A piece of armour", "text": Loc.t(String(Data.armor.get(piece, {}).get("name", piece)))})
	return out

## The reward picked (0, 1 or 2): given, and the next wave called.
func take(i: int) -> void:
	if phase != "rest" or i < 0 or i >= offer.size():
		return
	var rw: Dictionary = offer[i]
	offer = []
	var you = m.me
	var f: Fighter = you.f if you and is_instance_valid(you.f) else null
	if f:
		match String(rw.id):
			"bind":
				f.bind_wounds()
			"mend":
				_mend(f)
			"pot":
				var inv: Dictionary = you.get("inventory", {})
				inv[rw.arg] = int(inv.get(rw.arg, 0)) + 2
				you.inventory = Throwables.bag_clamp(inv)
			"blade":
				if f.release("R") != null or f.weapons.R == null:
					f.equip("R", Data.preset(String(rw.arg)))
			"armour":
				f.set_armor_pieces(_worn(f) + [String(rw.arg)])
	m.feed.emit(Loc.t("Taken: %s") % Loc.t(String(rw.title)))
	phase = "next"
	next_t = START_DELAY

## Weapons as they were made: what is in his hands taken up afresh from its own design
## (Fighter.rearm), held as it was.
func _mend(f: Fighter) -> void:
	var was_two := f.two_handed
	var d := {}
	for side in ["R", "L"]:
		var w = f.weapons[side]
		d[side] = (w.design as Dictionary).duplicate(true) if w and is_instance_valid(w) else {}
	f.rearm(d.R, d.L)
	if was_two and not f.two_handed:
		f.toggle_grip()

## A right hand that can let go of what it holds and take up another (not a blade arm, not lost).
func _free_right(f: Fighter) -> bool:
	var fore: VoxelPart = f.arm.R.fore
	return not f.fixed_hand.R and not fore.severed and not fore.missing and fore.prosthetic == ""

func _chipped(f: Fighter) -> bool:
	for side in ["R", "L"]:
		var w = f.weapons[side]
		if w and is_instance_valid(w) and w.has_method("alive_count") and int(w.alive_count()) < int(w.design.get("voxels", []).size()):
			return true
	return false

func _worn(f: Fighter) -> Array:
	var out := []
	for p in f.parts:
		for ad in p.get_meta("armor", []):
			var id := String(ad.id)
			if Armory.sold(id) and not out.has(id):
				out.append(id)
	return out

func _pieces_left(f: Fighter) -> Array:
	var worn := _worn(f)
	return PIECES.filter(func(id): return not worn.has(id) and not worn.any(func(w): return Armory.clashes(id, String(w))))

func _fall() -> void:
	phase = "over"
	var reached := maxi(0, wave - 1) if wave > 0 else 0
	var best := _record()
	var held := held_back()
	var sub := Loc.t("Best: wave %d") % best
	if held > 0:
		sub += " · " + Loc.t("%d more great foes wait in the full game") % held
	m._end(false, Loc.t("You fell in wave %d") % wave, sub, 0)
	submit(reached)

## The run as far as it went, kept: the best wave ever, and today's for the day's challenge.
## Returns the best.
func _record() -> int:
	var done := wave if phase == "rest" else maxi(0, wave - 1)
	var s: Dictionary = Save.get_value("endless", {})
	s.best = maxi(int(s.get("best", 0)), done)
	if daily:
		var d: Dictionary = s.get("daily", {})
		if String(d.get("day", "")) != day:
			d = {"day": day, "best": 0}
		d.best = maxi(int(d.get("best", 0)), done)
		s.daily = d
	Save.set_value("endless", s)
	return int(s.best)

## The waves beaten on Steam's board (today's own board for the day's challenge), when Steam is
## there: GodotSteam's leaderboards, looked for (or made) and the score sent, the best kept.
func submit(waves_beaten: int) -> void:
	if waves_beaten <= 0 or not Net.steam_available():
		return
	var st = Net.steam
	if not (st.has_method("findOrCreateLeaderboard") and st.has_method("uploadLeaderboardScore") and st.has_signal("leaderboard_find_result")):
		return
	var board := ("endless_" + day.replace("-", "")) if daily else "endless_best"
	st.connect("leaderboard_find_result", func(handle, found):
		if int(found) != 0:
			st.call("uploadLeaderboardScore", waves_beaten, true, PackedInt32Array(), int(handle)), CONNECT_ONE_SHOT)
	st.call("findOrCreateLeaderboard", board, 2, 1)   # descending, numeric
