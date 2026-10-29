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
	# No ready-made weapon has a piece hanging in the air (the chicken's eye, the tickler's
	# feathers, the bow's string): each loose piece is joined on.
	for k in presets:
		if presets[k] is Dictionary and presets[k].get("voxels") is Array and not presets[k].has("chain"):
			if ForgeLib.bridge(presets[k]) > 0:
				presets[k].erase("stats")   # (worked out afresh for the joined-up weapon)
	damage_tuning = p.get("damageTuning", {})
	var b: Dictionary = _read("body")
	body_parts = b.get("parts", [])
	lobes = b.get("lobes", {})
	# The organs and bones inside the trunk and the head (Anatomy).
	Anatomy.dress(body_parts)
	armor = _read("armor")
	# The armourer's newer pieces, shaped round this body.
	armor.merge(Armory.extra(body_parts))
	armor.merge(MonsterLook.PIECES)
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

## The campaign is a ladder of single bouts, authored bout by bout in Ladder (scripts/game/
## ladder.gd): each stage one bout, its men with the stage's gear, weapons and skill (the
## tables'), a beast at its species' size, a boss on every fourth stage, and on some a second
## wave through the other gate ("late"). A party (co-op) fights it together: for the extra
## friends, more of the bout's own men (or of its beast), fewer than the friends, so a party
## always has the numbers (two for two, two for three, three for four); a boss comes alone, the
## tougher for each friend. The second wave comes as authored, for a party as for one man.
func duel(st: Dictionary, players := 1) -> Dictionary:
	var n := int(st.get("n", 1))
	var b := Ladder.bout(n)
	if b.is_empty():
		return st
	var gear: Dictionary = st.get("gear", {})
	var foes: Array = []
	for en in b.get("foes", []):
		foes.append(_ladder_foe(en, gear))
	var late: Array = []
	for en in b.get("late", []):
		late.append(_ladder_foe(en, gear))
	var boss: bool = foes.any(func(f): return f.get("boss", false))
	if players > 1 and boss:
		for f in foes:
			var m: Dictionary = f.get("mods", {}).duplicate()
			# (A party has the better of a boss: tougher for each friend, but not by a whole man.)
			m["toughness"] = float(m.get("toughness", 1.0)) * (1.0 + 0.35 * (players - 1))
			m["strength"] = float(m.get("strength", 1.0)) * (1.0 + 0.08 * (players - 1))
			f["mods"] = m
	elif players > 1:
		var own := foes.size()
		for i in roundi((players - 1) * 0.6):
			foes.append((foes[i % own] as Dictionary).duplicate(true))
	st["rounds"] = [foes]
	st["late"] = late
	st["duel"] = true
	st["foe_name"] = Ladder.foe_name(foes)
	var title := String(b.get("title", foes[0].get("title", "")))
	st["title"] = ("Bout %d" % n) if title == "" else (title if boss or foes[0].has("title") else "Bout %d: %s" % [n, title])
	st["stagePay"] = int(st.get("stagePay", 30)) + int(st.get("roundPay", 10)) * 2
	return st

## A ladder entry as the match spawns it: with the stage's gear (a beast ignores it).
func _ladder_foe(en: Dictionary, gear: Dictionary) -> Dictionary:
	var f: Dictionary = en.duplicate(true)
	if not f.has("gear"):
		f["gear"] = gear
	return f

func enemy_type(id: String) -> Dictionary:
	return campaign.get("enemies", {}).get(id, {})
