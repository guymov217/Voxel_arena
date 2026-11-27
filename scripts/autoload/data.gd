extends Node
## The game's content, exported from the web version (tools/export-godot.mjs): materials,
## weapon designs, the human body, beasts, enemies, the campaign's stages, the shop.

var materials: Dictionary = {}
var weapon_voxel := 0.04
var body_voxel := 0.055
var body_res := 2
var presets: Dictionary = {}
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
## boss cycle repeats, harder). Fought as the ladder's bout `bout` (0: its own, `n`; another of the
## stretch chosen at the gate: GateChoice), the crowd's fight if `crowd` (one more of its foes,
## the prize doubled). The gear, the pay and the checkpoint are the stage's whichever bout it is.
func stage(n: int, players: int = 1, bout: int = 0, crowd := false) -> Dictionary:
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
	out["bout"] = bout if bout >= 1 and bout <= Ladder.BOUTS.size() else clampi(n, 1, maxi(1, Ladder.BOUTS.size()))
	out["crowd"] = crowd
	return duel(out, players)

## The campaign is a ladder of single bouts, authored bout by bout in Ladder (scripts/game/
## ladder.gd): each stage one bout, its men with the stage's gear, weapons and skill (the
## tables'), a beast at its species' size, a boss on every fourth stage, and on some a second
## wave through the other gate ("late"). A party (co-op) fights it together: not one foe more for
## every friend (four players met four where one man met one: user), but a few more of the bout's own
## men (or of its beast), on every choice at the gate: one more for two or three players, two more
## for four, and never more than six foes in all, the second wave counted (six against four). A boss
## comes alone, the tougher for each friend. The second wave comes as authored, for a party as for one man.
const PARTY_EXTRA := [0, 1, 1, 2]   # foes a party adds to the bout's own, by its players (one to four)
const PARTY_FOES_MAX := 6           # the most foes a party meets, the second wave counted
## What every player more makes a bout's foes harder (user, #347: a boss a little harder for each, mainly in health, skill and damage; the bout's ordinary foes a little too, in damage and
## skill, not much). A boss: `BOSS_HEALTH` tougher (Fighter.mods.toughness, a man's and a beast's alike) and `BOSS_STRENGTH` stronger (both multiplied into its own), its blows landing `BOSS_DAMAGE` harder (Fighter.foe_dmg)
## and its wits `BOSS_SKILL` keener (a man's Bot.diff, a beast's Beast.skill); any other foe, the second wave's too, only the last two, by `FOE_DAMAGE` and `FOE_SKILL`.
const BOSS_HEALTH := 0.35
const BOSS_STRENGTH := 0.08
const BOSS_DAMAGE := 0.10
const BOSS_SKILL := 0.05
const FOE_DAMAGE := 0.04
const FOE_SKILL := 0.03
func duel(st: Dictionary, players := 1) -> Dictionary:
	var n := int(st.get("n", 1))
	var b := Ladder.bout(int(st.get("bout", n)))
	if b.is_empty():
		return st
	var gear: Dictionary = st.get("gear", {})
	var foes: Array = []
	for en in b.get("foes", []):
		foes.append(_ladder_foe(en, gear))
	# The crowd's fight: one more of the first of them (GateChoice.crowd_ok: never a named man).
	if bool(st.get("crowd", false)) and not foes.is_empty():
		foes.append((foes[0] as Dictionary).duplicate(true))
	var late: Array = []
	for en in b.get("late", []):
		late.append(_ladder_foe(en, gear))
	var boss: bool = foes.any(func(f): return f.get("boss", false))
	if players > 1 and boss:
		for f in foes:
			# (A party has the better of a boss: tougher for each friend, but not by a whole man. Told as what it is tougher and stronger BY, which the match
			# multiplies into the boss's own, a man's or a beast's: it was written over them as a toughness and a strength of its own, and the giant, the troll and the
			# titan came to a pair of friends weaker than to one man.)
			f["party_hp"] = 1.0 + BOSS_HEALTH * (players - 1)
			f["party_str"] = 1.0 + BOSS_STRENGTH * (players - 1)
	elif players > 1:
		var own := foes.size()
		var extra := mini(int(PARTY_EXTRA[clampi(players, 1, PARTY_EXTRA.size()) - 1]), maxi(0, PARTY_FOES_MAX - own - late.size()))
		for i in extra:
			foes.append((foes[i % own] as Dictionary).duplicate(true))
	# Every foe of a party's bout, the second wave's too, lands a little harder and thinks a little keener for each friend (a boss more than the rest).
	if players > 1:
		for f in foes + late:
			var is_boss: bool = bool(f.get("boss", false))
			f["party_dmg"] = 1.0 + (BOSS_DAMAGE if is_boss else FOE_DAMAGE) * (players - 1)
			f["party_skill"] = 1.0 + (BOSS_SKILL if is_boss else FOE_SKILL) * (players - 1)
	st["rounds"] = [foes]
	st["late"] = late
	st["duel"] = true
	st["foe_name"] = Ladder.foe_name(foes)
	var title := Loc.t(String(b.get("title", foes[0].get("title", "")))) if String(b.get("title", foes[0].get("title", ""))) != "" else ""
	st["title"] = (Loc.t("Bout %d") % n) if title == "" else (title if boss or foes[0].has("title") else Loc.t("Bout %d: %s") % [n, title])
	st["stagePay"] = int(st.get("stagePay", 30)) + int(st.get("roundPay", 10)) * 2
	if bool(st.get("crowd", false)):
		st["stagePay"] = int(st.stagePay) * 2
		st["roundPay"] = int(st.get("roundPay", 10)) * 2
	return st

## A ladder entry as the match spawns it: with the stage's gear (a beast ignores it).
func _ladder_foe(en: Dictionary, gear: Dictionary) -> Dictionary:
	var f: Dictionary = en.duplicate(true)
	if not f.has("gear"):
		f["gear"] = gear
	return f

func enemy_type(id: String) -> Dictionary:
	return campaign.get("enemies", {}).get(id, {})
