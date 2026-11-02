class_name ForgeFight
extends RefCounted
## Forge and Fight, a room's game: every player forges his own weapons and makes his own armour
## against the clock the host set, then all of them fight to the death with what they made
## (user: a set time to build weapons and armour, then everyone fights to the death; the host
## sets the times). The rules here; the screens are the menu's (Menu._ff_*), the fight is Modes'.

## The host's choices, in minutes (0 armour: none made; 0 fight: no limit, to the death).
const WEAPON_MIN := [1, 2, 3, 5, 8, 10]
const ARMOUR_MIN := [0, 1, 2, 3, 5]
const FIGHT_MIN := [0, 2, 3, 5, 10]
const DEFAULT := {"weapons": 3, "armour": 2, "fight": 0}
## How long the host waits for the last kits after the forges go cold (s).
const GRACE := 1.5

## The host's times from the wire: whole minutes from the lists above, else the defaults.
static func clean_times(d) -> Dictionary:
	var out := DEFAULT.duplicate()
	if d is Dictionary:
		for k in [["weapons", WEAPON_MIN], ["armour", ARMOUR_MIN], ["fight", FIGHT_MIN]]:
			var v = d.get(k[0])
			if (v is int or v is float) and is_finite(float(v)) and (k[1] as Array).has(int(v)):
				out[k[0]] = int(v)
	return out

## A player's kit from the wire (what he forged and made), made safe as any loadout is
## (Net.sanitize_loadout: the forge's own grid, materials and block count), its armour designs
## made known under their own ids and nothing worn that is not known. Every weapon here is
## forged: no ready-made one in either hand but the plain round shield (a name sent for one, or a
## design that does not hold up, leaves the hand empty: who forged nothing fights with his fists).
static func clean_kit(d) -> Dictionary:
	if not (d is Dictionary):
		return {"main": ""}
	var lo := Net.sanitize_loadout(d)
	if not (lo.get("main") is Dictionary) or not (d.get("main") is Dictionary):
		lo.main = ""
	if not lo.has("off") or (lo.off is String and not ["", "roundShield"].has(lo.off)):
		lo.off = ""
	if lo.has("armor_defs"):
		Armory.register(lo.armor_defs)
	# (and only armour he made himself: none off the armourer's racks)
	lo.armor = (lo.get("armor", []) as Array).filter(func(id): return Data.armor.has(String(id)) and Armory.custom(String(id)))
	return lo

## The one who wins when the fight's time runs out: the one standing with the most blood left
## (null: two level, a draw).
static func leader(alive: Array):
	var best = null
	var b := -1.0
	var tie := false
	for e in alive:
		var bl := float(e.f.blood)
		if bl > b + 0.01:
			best = e
			b = bl
			tie = false
		elif absf(bl - b) <= 0.01:
			tie = true
	return null if tie else best

## The phase after `phase`: the armour if there is time for it, then the fight.
static func next_phase(phase: String, times: Dictionary) -> String:
	if phase == "weapons" and int(times.get("armour", 0)) > 0:
		return "armour"
	return "fight"

## How long a phase runs (s).
static func phase_seconds(phase: String, times: Dictionary) -> float:
	match phase:
		"weapons": return float(times.get("weapons", 3)) * 60.0
		"armour": return float(times.get("armour", 0)) * 60.0
	return 0.0

## "2:05"
static func clock(s: float) -> String:
	var n := maxi(0, ceili(s))
	return "%d:%02d" % [n / 60, n % 60]
