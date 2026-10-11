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
	armor = _read("armor")
	beasts = _read("beasts")
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
	return out

func enemy_type(id: String) -> Dictionary:
	return campaign.get("enemies", {}).get(id, {})
