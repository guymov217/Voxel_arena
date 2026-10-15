class_name Decrees
extends RefCounted
## The Emperor's decrees (decrees.js): random modifiers for a fight. Pure data, so the host and
## the guests agree on what they do.

const LIST := [
	{"id": "moon", "name": "Moon Gravity", "desc": "Every jump is a journey", "gravity": 3.2},
	{"id": "fists", "name": "Fists Only", "desc": "All weapons were seized by the imperial treasury", "loadout": "fists"},
	{"id": "chickens", "name": "Rubber Chickens", "desc": "The official weapon of the Empire. It squeaks.", "loadout": "chickens"},
	{"id": "fish", "name": "Fish Fight", "desc": "Weapons kindly donated by the Roman fish market", "loadout": "fish"},
	{"id": "giant", "name": "Giant Weapons", "desc": "Size does matter", "mods": {"weaponScale": 1.7}},
	{"id": "drunk", "name": "Free Wine", "desc": "Everyone had a little too much", "mods": {"drunk": 0.45}},
	{"id": "turbo", "name": "Fast Forward", "desc": "The Emperor has a meeting in five minutes", "timeScale": 1.45},
	{"id": "confetti", "name": "Confetti Blood", "desc": "Celebrate! Every wound is a party", "confetti": true},
	{"id": "bloodbath", "name": "Bloodbath", "desc": "Every scratch bleeds three times as much", "mods": {"bleed": 3.0}},
	{"id": "paper", "name": "Paper Limbs", "desc": "Today's gladiators are made of papyrus", "mods": {"sever": 0.65}},
	{"id": "sparta", "name": "Spartan Kick", "desc": "This... is... Rome! (kicks send people flying)", "mods": {"superKick": true}},
	{"id": "glass", "name": "Glass Weapons", "desc": "Rome's blacksmiths drink on the job. Every hit breaks something", "chip": 3.0},
	{"id": "spikes", "name": "Spike Floor", "desc": "Watch where you step. Red plates mean trouble", "hazards": ["spikes"]},
	{"id": "lions", "name": "Lions' Den", "desc": "The Emperor brought his pets", "lions": true},
	{"id": "lottery", "name": "Weapon Lottery", "desc": "Everyone gets a random weapon from the armory", "loadout": "lottery"},
]
const LOTTERY := ["gladius", "axe", "mace", "spear", "longsword", "warhammer", "hammer", "trident", "dagger", "zweihander", "executionerAxe", "chicken", "fish", "chair", "plank", "goldenSpork", "nunchaku", "boing", "tickler"]

static func by_id(id: String) -> Dictionary:
	for d in LIST:
		if d.id == id:
			return d
	return {}

## Decrees for a fight: `chance` of any at all; chaos stacks three. Never two that each set the
## weapons.
static func roll(chance := 0.6, count := 1, rng: RandomNumberGenerator = null) -> Array:
	var r := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	if r.randf() > chance:
		return []
	var pool := LIST.duplicate()
	var out := []
	while out.size() < count and not pool.is_empty():
		var d: Dictionary = pool.pop_at(r.randi_range(0, pool.size() - 1))
		if d.has("loadout") and out.any(func(o): return o.has("loadout")):
			continue
		out.append(d)
	return out

## What several decrees add up to.
static func combine(list: Array) -> Dictionary:
	var out := {"mods": {}, "gravity": 9.81, "timeScale": 1.0, "confetti": false, "loadout": "", "chip": 1.0, "hazards": [], "lions": false, "names": []}
	for d in list:
		for k in d.get("mods", {}):
			out.mods[k] = d.mods[k]
		if d.has("gravity"):
			out.gravity = d.gravity
		if d.has("timeScale"):
			out.timeScale *= d.timeScale
		if d.get("confetti", false):
			out.confetti = true
		if d.has("loadout"):
			out.loadout = d.loadout
		if d.has("chip"):
			out.chip *= d.chip
		out.hazards.append_array(d.get("hazards", []))
		if d.get("lions", false):
			out.lions = true
		out.names.append(d.name)
	return out

## The weapons a "loadout" decree hands out (fists: none).
static func loadout(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	match kind:
		"fists": return {"main": "", "off": ""}
		"chickens": return {"main": "chicken", "off": ""}
		"fish": return {"main": "fish", "off": "fish"}
		"lottery": return {"main": LOTTERY[rng.randi_range(0, LOTTERY.size() - 1)], "off": ""}
	return {}
