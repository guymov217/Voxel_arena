class_name Spectacle
extends RefCounted
## The crowd and the man with the scroll (crowd.js, announcer.js, drops.js): how much the
## spectators love each fighter (and their boredom), the Emperor's verdict, the announcer's
## lines on every big moment, and the weapons the crowd throws down into the sand mid-fight.

const FAVOR_GIFTS := [40, 70, 100]
const DROPS := [
	["fish", "Someone in row 9 threw a FISH!", 3], ["chicken", "A rubber chicken lands on the sand. The crowd giggles.", 3],
	["chair", "A folding chair! Classic.", 3], ["plank", "A plank falls from the scaffolding.", 3],
	["goldenSpork", "The Emperor drops his golden spork.", 1], ["swordfish", "A swordfish! Still wet.", 2],
	["goose", "A goose on a stick. It is furious.", 2], ["fishStick", "An angry fish on a stick slaps the ground.", 2],
	["hammer", "A hammer clatters down from the stands.", 2], ["nunchaku", "Nunchaku! Do not hit yourself.", 2],
	["whip", "A whip. Yank their weapon away.", 2],
	["boing", "A spring sword! BOING!", 2], ["sticky", "A glue mace. Everything sticks to it.", 2],
	["tickler", "A feather duster. Deadly to the dignified.", 1], ["magnet", "A magnet club: pulls iron out of hands.", 2],
	["icicle", "An icicle blade. Chills and shatters.", 2], ["badIdea", "A barrel of Bad Ideas. It is explosive.", 1],
	["bow", "A bow. Hold the left button to draw, release to loose.", 2],
	["javelin", "A javelin. F throws it point first.", 3], ["telescopicSpear", "A telescopic spear. C extends it.", 1],
	["zweihander", "A zweihander falls from the Emperor's box.", 1], ["trident", "A trident. Very Neptune.", 2],
	["flamePole", "A flame pole! C breathes fire.", 1], ["twoPersonSword", "A two-person sword. Grab a friend.", 1],
]
const DROP_INTERVAL := [110.0, 190.0]
const LINES := {
	"firstBlood": ["FIRST BLOOD! {a} opens the account.", "And {a} draws first blood! The crowd approves.", "{a} strikes first. Someone wake up the Emperor."],
	"decap": ["OFF WITH THE HEAD! {v} will not be needing a helmet.", "A clean cut! {v}'s head goes one way, the rest goes the other.", "DECAPITATION! {a} sends {v}'s head to the stands."],
	"limb": ["{v} loses a {part}! That's going to leave a mark.", "There goes {v}'s {part}. The surgeons sigh.", "{a} relieves {v} of a {part}. The crowd wants more."],
	"heart": ["THROUGH THE HEART! {v} has seconds left, and knows it.", "{a} finds {v}'s heart. The crowd holds its breath.", "Right in the heart! {v} is already a statue."],
	"lung": ["{a} opens {v}'s lung! Listen to that wheeze.", "{v} is breathing through the wrong hole now.", "A lung for {a}! {v} will not be running far."],
	"liver": ["{a} carves into {v}'s liver. That one bleeds and bleeds.", "The liver! {v}'s wine days are over."],
	"guts": ["{a} opens {v}'s belly! Mind your step down there.", "{v}'s guts see the sun. The front rows regret their seats."],
	"stomach": ["{a} skewers {v}'s stomach. Lunch is cancelled."],
	"spine": ["{a} cuts {v}'s spine! Those legs belong to nobody now.", "THE SPINE! {v} folds like a wet sail."],
	"brain": ["{a} into the brain! {v} forgets what day it is. Forever.", "That blow reached {v}'s brain. Goodnight."],
	"bones": ["CRACK! That was {v}'s {part}.", "{a} breaks {v}'s {part}. The front row heard that one.", "Bones go! {v}'s {part}, in pieces."],
	"bigHit": ["WHAT A HIT! {a} nearly folds {v} in half.", "OOOH! {v} felt that one in the afterlife.", "{a} with the mighty blow! The Emperor spills his wine."],
	"kill": ["{v} is down for good. {a} takes the kill.", "{a} finishes {v}! The sand drinks again.", "Farewell, {v}. {a} sends their regards."],
	"double": ["DOUBLE KILL! {a} is on a rampage!", "Two down for {a}! Someone check if that is legal."],
	"triple": ["TRIPLE KILL! {a} IS UNSTOPPABLE!", "{a} with THREE! The crowd is on its feet!"],
	"comeback": ["{a} was nearly dead and still took {v} with them! COMEBACK!", "Bleeding, limping, and still winning: {a} takes {v}!"],
	"friendly": ["{a} hits their own teammate {v}. The crowd laughs. {v} does not.", "FRIENDLY FIRE! {a}, that was {v}, your friend!", "{a} forgets which colour they are wearing. {v} pays for it."],
	"bored": ["The crowd is yawning. Hit someone!", "The Emperor checks his sundial. Do something!", "Thirty seconds without blood. Shameful."],
	"streakChant": ["{A}! {A}! {A}!"],
	"revenge": ["REVENGE! {a} pays {v} back!", "{a} remembers who hit them. {v} regrets it."],
	"survived": ["{v} is still standing with almost no blood left. Made of iron!"],
	"weaponThrow": ["{a} throws the weapon... and HITS {v}! Incredible!", "A flying weapon from {a} finds {v}!"],
	"beast": ["{a} slays the beast! The Emperor's pet is no more.", "BEAST SLAYER! {a} brings down the {v}!"],
	"roundStart": ["Gladiators, to your marks! Let the sand be red!", "The Emperor raises his hand... FIGHT!", "Welcome to the games! Try not to die in the first ten seconds."],
	"longFight": ["Two minutes and still going! The crowd is placing side bets."],
}

var m: Node
var favor := {}          # fighter -> 0..100
var gifted := {}
var time := 0.0
var last_action := 0.0
var events: Array = []   # {f, amount, reason} for the HUD
# The announcer.
var cool := {}
var first_blood := false
var kill_times := {}
var last_hit := {}
var quiet_t := 0.0
var said_long := false
var round_time := 0.0
# Drops.
var drop_t := 6.0
var recent_drops: Array = []
var drops_on := false

func _init(match_: Node) -> void:
	m = match_

func reset() -> void:
	favor.clear()
	gifted.clear()
	time = 0.0
	last_action = 0.0
	events.clear()
	cool.clear()
	first_blood = false
	kill_times.clear()
	last_hit.clear()
	quiet_t = 0.0
	said_long = false
	round_time = 0.0

# ---------- Crowd favour ----------

func get_favor(f) -> float:
	return favor.get(f, 20.0)

func add(f, amount: float, reason := "") -> void:
	if f == null or not is_instance_valid(f):
		return
	if amount > 0.0:
		amount *= float(f.mods.get("favorMult", 1.0))
	favor[f] = clampf(get_favor(f) + amount, 0.0, 100.0)
	if amount >= 5.0:
		last_action = time
	if reason != "":
		events.append({"f": f, "amount": roundi(amount), "reason": reason})

## 0 while the fight is lively, rising to 1 after about 20 s without real action.
func boredom() -> float:
	return clampf((time - last_action - 7.0) / 14.0, 0.0, 1.0)

## The Emperor's thumb at the end of a fight.
func verdict(winner) -> Dictionary:
	var f := get_favor(winner) if winner else 0.0
	if f >= 55.0:
		return {"thumb": "up", "text": "The Emperor is pleased!", "bonus": roundi(f)}
	if f >= 25.0:
		return {"thumb": "side", "text": "The Emperor nods, unimpressed", "bonus": roundi(f / 3.0)}
	return {"thumb": "down", "text": "The Emperor yawns. Next time: lions.", "bonus": 0}

# ---------- The announcer ----------

func say(key: String, a = null, v = null, part := "", center := false, cooldown := 1.5) -> bool:
	if cool.get(key, -1.0) > time:
		return false
	cool[key] = time + cooldown
	var lines: Array = LINES[key]
	var an: String = a.display_name if a is Object and is_instance_valid(a) else (a.get("name", "someone") if a is Dictionary else "someone")
	var vn: String = v.display_name if v is Object and is_instance_valid(v) else (v.get("name", "someone") if v is Dictionary else "someone")
	var up := ""
	for ch in an.to_upper():
		if ch >= "A" and ch <= "Z" and up.length() < 7:
			up += ch
	var line: String = lines[randi() % lines.size()].replace("{a}", an).replace("{v}", vn).replace("{part}", part if part != "" else "limb").replace("{A}", up if up != "" else "ROME")
	m.feed.emit(line)
	if center:
		m.banner.emit(line, "")
	if m.role == "host":
		Net.send_all("feed", line)
	return true

func on_round_start() -> void:
	say("roundStart", null, null, "", false, 0.0)

## Every hit the host deals out (after the damage).
func on_hit(h: Dictionary) -> void:
	quiet_t = 0.0
	var a = h.get("attacker")
	var v = h.get("char")
	if a == null or a == v or not is_instance_valid(a) or v == null:
		return
	var J: float = h.get("J", 0.0)
	var res: Dictionary = h.get("res", {})
	var severed: Array = res.get("severed", [])
	# The crowd.
	if J > 8.0:
		add(a, minf(6.0, J * 0.25), "Mighty blow" if J > 30.0 else "")
	if h.get("thrown", false) and J > 5.0:
		add(a, 30.0 if h.get("killed", false) else 10.0, "Deadly throw!" if h.get("killed", false) else "Thrown hit!")
	for p in severed:
		if p.part_name == "head":
			add(a, 45, "Decapitation!")
		elif p.part_name.begins_with("forearm") or p.part_name.begins_with("upperArm"):
			add(a, 22, "Disarmed!")
		else:
			add(a, 20, "Dismembered!")
	if h.get("killed", false):
		add(a, 45 if v.kind == "beast" else 25, "Beast slayer!" if v.kind == "beast" else "Kill!")
	var organs: Array = res.get("organs", [])
	for o in organs:
		match o:
			"heart": add(a, 30, "Heart strike!")
			"spine": add(a, 25, "Spine cut!")
			"brain": add(a, 30, "Brain strike!")
			_: add(a, 8, "")
	# The announcer.
	var ea = m.entity_of(a)
	var ev = m.entity_of(v)
	if not first_blood and J > 4.0:
		first_blood = true
		say("firstBlood", a, null, "", false, 0.0)
	if ea and ev and ea.team == ev.team and J > 5.0 and not ev.get("harmless", false):
		say("friendly", a, v, "", false, 6.0)
	var broke := ""
	if res.get("fractured") is VoxelPart:
		broke = String(res.fractured.label).to_lower()
	elif res.get("broke", "") != "":
		broke = res.broke
	if broke != "":
		add(a, 12, "Bone breaker!")
		say("bones", a, v, broke, false, 5.0)
	# Inside: the worst organ the blow reached, once per organ and victim in a while.
	for o in ["heart", "brain", "spine", "lung", "liver", "guts", "stomach"]:
		if organs.has(o) and LINES.has(o):
			say(o, a, v, "", o == "heart" or o == "spine", 8.0)
			break
	if not severed.is_empty():
		var sp: VoxelPart = severed[0]
		if sp.part_name == "head":
			say("decap", a, v, "", true, 0.0)
		else:
			say("limb", a, v, String(sp.label).to_lower(), false, 2.0)
	elif J > 34.0:
		say("bigHit", a, v, "", false, 5.0)
	if h.get("thrown", false) and J > 6.0:
		say("weaponThrow", a, v, "", false, 6.0)
	if last_hit.get(a) == v and J > 8.0:
		say("revenge", a, v, "", false, 12.0)
	last_hit[v] = a
	if v.alive and v.blood < 12.0 and J > 6.0:
		say("survived", null, v, "", false, 15.0)

func on_death(c) -> void:
	var a = c.last_attacker
	if a == null or a == c or not is_instance_valid(a):
		return
	var list: Array = kill_times.get(a, [])
	list.append(time)
	kill_times[a] = list
	var recent := list.filter(func(t): return time - t < 10.0).size()
	if c.kind == "beast":
		say("beast", a, {"name": c.display_name.to_lower()}, "", true, 0.0)
	elif recent >= 3:
		say("triple", a, null, "", true, 0.0)
		chant(a)
	elif recent == 2:
		say("double", a, null, "", true, 0.0)
	elif a.blood < 25.0 and a.alive:
		say("comeback", a, c, "", true, 0.0)
	else:
		say("kill", a, c, "", false, 3.0)
	if (list.size() == 5 or list.size() == 10) and c.kind != "beast":
		chant(a)

func chant(a) -> void:
	say("streakChant", a, null, "", true, 0.0)
	m.sfx("cheer", a.torso.global_position if is_instance_valid(a) else Vector3.ZERO)

# ---------- Each step ----------

func update(dt: float) -> void:
	if m.over:
		return
	time += dt
	round_time += dt
	for e in m.entities:
		var f = e.f
		if not f.alive:
			continue
		var val := get_favor(f)
		var given: int = gifted.get(f, 0)
		for level in FAVOR_GIFTS:
			if val >= level and given < level:
				gifted[f] = level
				given = level
		if val >= 100.0:
			favor[f] = 65.0
			gifted[f] = 40
		# Passive gladiators slowly lose the crowd.
		if time - last_action > 6.0:
			favor[f] = maxf(0.0, get_favor(f) - dt * 1.2)
	quiet_t += dt
	if quiet_t > 30.0:
		quiet_t = 10.0
		say("bored", null, null, "", false, 0.0)
	if round_time > 120.0 and not said_long:
		said_long = true
		say("longFight", null, null, "", false, 0.0)
	if drops_on:
		drop_t -= dt
		if drop_t <= 0.0:
			drop_t = randf_range(DROP_INTERVAL[0], DROP_INTERVAL[1])
			arena_drop()

## A weapon from the stands lands on a clear patch of sand, for anyone to grab.
func arena_drop() -> void:
	var pool := DROPS.filter(func(d): return not recent_drops.has(d[0]) and not Data.preset(d[0]).is_empty())
	if pool.is_empty():
		return
	var total := 0
	for d in pool:
		total += d[2]
	var r := randf() * total
	var pick: Array = pool[-1]
	for d in pool:
		r -= d[2]
		if r <= 0.0:
			pick = d
			break
	recent_drops = recent_drops.slice(-4) + [pick[0]]
	var lim := 15.0 - 1.5
	for tries in 12:
		var a := randf() * TAU
		var rr := sqrt(randf()) * (lim - 1.0)
		var cand := Vector3(sin(a) * rr, 7.0, cos(a) * rr)
		var clear := true
		for e in m.entities:
			if e.f.alive and Vector2(e.f.torso.global_position.x - cand.x, e.f.torso.global_position.z - cand.z).length() < 2.2 * e.f.S:
				clear = false
		if clear:
			m.spawn_loose_weapon(Data.preset(pick[0]), cand)
			m.feed.emit(pick[1])
			if m.role == "host":
				Net.send_all("feed", pick[1])
			m.sfx("cheer", cand, 0.4)
			return
