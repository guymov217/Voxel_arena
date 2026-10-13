extends Node
## The game's content, exported from the web version (tools/export-godot.mjs): materials,
## weapon designs, the human body, beasts, enemies, the campaign's stages, the shop.

var materials: Dictionary = {}
var weapon_voxel := 0.04
var body_voxel := 0.055
var body_res := 2
var presets: Dictionary = {}
var damage_tuning: Dictionary = {}
var body_parts: Array = []
var lobes: Dictionary = {}
var armor: Dictionary = {}
var beasts: Dictionary = {}
var campaign: Dictionary = {}
var shop: Dictionary = {}
var controls: Dictionary = {}
var modes: Dictionary = {}

func _init() -> void:
	load_all()

func _read(name: String) -> Variant:
	var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
	if f == null:
		push_error("Missing data file %s" % name)
		return {}
	return JSON.parse_string(f.get_as_text())

func load_all() -> void:
	var m: Dictionary = _read("materials")
	materials = m.get("materials", {})
	weapon_voxel = m.get("weaponVoxel", 0.04)
	body_voxel = m.get("bodyVoxel", 0.055)
	body_res = int(m.get("bodyRes", 2))
	var p: Dictionary = _read("presets")
	presets = p.get("presets", {})
	damage_tuning = p.get("damageTuning", {})
	var b: Dictionary = _read("body")
	body_parts = b.get("parts", [])
	lobes = b.get("lobes", {})
	# The organs and bones inside the trunk and the head (Anatomy).
	Anatomy.dress(body_parts)
	armor = _read("armor")
	# The armourer's newer pieces, shaped round this body.
	armor.merge(Armory.extra(body_parts))
	beasts = _read("beasts")
	Anatomy.dress_beasts(beasts)
	campaign = _read("campaign")
	shop = _read("shop")
	controls = _read("controls")
	modes = _read("modes")

func material(id: String) -> Dictionary:
	return materials.get(id, materials.get("wood", {}))

func preset(key: String) -> Dictionary:
	return presets.get(key, {})

func body_def(name: String) -> Dictionary:
	for d in body_parts:
		if d.name == name:
			return d
	return {}

## The campaign's stage `n` for `players` players (the tables run to 64; past that the last
## boss cycle repeats, harder).
func stage(n: int, players: int = 1) -> Dictionary:
	var rows: Array = campaign.get("stages", [])
	if rows.is_empty():
		return {}
	var row: Dictionary = rows[clampi(n, 1, rows.size()) - 1]
	var by: Dictionary = row.get("byPlayers", {})
	var key := str(clampi(players, 1, 4))
	var out: Dictionary = by.get(key, {}).duplicate(true)
	out["n"] = n
	out["boss"] = row.get("boss", false)
	out["checkpoint"] = row.get("checkpoint", null)
	out["gear"] = row.get("gear", {})
	return duel(out, players)

## The campaign is a ladder of single bouts: each stage one opponent, one on one, harder every
## time. Every boss stage brings its boss (the Cyclops, the Minotaur, Polyphemus the giant, the
## Hydra, the Dragon...); every third stage a beast comes through the gate instead of a man,
## from the wolf at the start to the monsters late on; the rest are the stage's strongest
## gladiator. A party (co-op) fights it together: each friend gets a foe of his own (other men
## from the stage, or a pack of the beast), and a boss comes alone, the tougher for each friend.
const LADDER_BEASTS := ["wolf", "boar", "hyena", "goat", "lion", "bear", "crocodile", "tiger", "bull", "ostrich", "rhino", "python", "scorpion", "spider", "elephant", "griffin", "basilisk", "manticore", "chimera"]
func duel(st: Dictionary, players := 1) -> Dictionary:
	var rounds: Array = st.get("rounds", [])
	if rounds.is_empty():
		return st
	var n := int(st.get("n", 1))
	var gear: Dictionary = st.get("gear", {})
	var foe: Dictionary = {}
	if st.get("boss", false):
		for en in rounds[rounds.size() - 1]:
			if en.get("boss", false):
				foe = en.duplicate(true)
	if foe.is_empty() and n % 3 == 0:
		var bid: String = LADDER_BEASTS[mini(n / 3 - 1, LADDER_BEASTS.size() - 1)]
		if beasts.has(bid):
			foe = {"beast": bid, "gear": gear}
	if foe.is_empty():
		# The stage's hardest man: the first gladiator of its last wave (the latest wave
		# that has one, beasts left to their own stages).
		for r in range(rounds.size() - 1, -1, -1):
			for en in rounds[r]:
				if foe.is_empty() and en.has("e") and not en.get("boss", false):
					foe = (en as Dictionary).duplicate(true)
		if foe.is_empty():
			foe = (rounds[rounds.size() - 1][0] as Dictionary).duplicate(true)
		foe.erase("boss")
	var foes: Array = [foe]
	if players > 1 and (st.get("boss", false) or foe.get("boss", false)):
		var m: Dictionary = foe.get("mods", {}).duplicate()
		m["toughness"] = float(m.get("toughness", 1.0)) * (1.0 + 0.6 * (players - 1))
		m["strength"] = float(m.get("strength", 1.0)) * (1.0 + 0.12 * (players - 1))
		foe["mods"] = m
	elif players > 1:
		# Every friend his own man: the stage's other gladiators, latest waves first.
		var pool: Array = []
		for r in range(rounds.size() - 1, -1, -1):
			for en in rounds[r]:
				if en.has("e") and not en.get("boss", false) and en.e != foe.get("e"):
					pool.append(en)
		for i in players - 1:
			if foe.has("beast") or pool.is_empty():
				foes.append(foe.duplicate(true))
			else:
				var o: Dictionary = (pool[i % pool.size()] as Dictionary).duplicate(true)
				o.erase("boss")
				foes.append(o)
	var name := String(foe.get("title", foe.get("name", "")))
	if name == "":
		name = String(beasts.get(foe.beast, {}).get("name", foe.beast)) if foe.has("beast") else String(enemy_type(String(foe.get("e", ""))).get("label", String(foe.get("e", "a gladiator")).capitalize()))
	st["rounds"] = [foes]
	st["duel"] = true
	st["foe_name"] = name
	st["title"] = String(foe.get("title", "Bout %d" % n))
	st["stagePay"] = int(st.get("stagePay", 30)) + int(st.get("roundPay", 10)) * 2
	return st

func enemy_type(id: String) -> Dictionary:
	return campaign.get("enemies", {}).get(id, {})
