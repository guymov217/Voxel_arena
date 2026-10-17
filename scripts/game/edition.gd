class_name Edition
## Which build this is: the full game, or the free demo for its Steam page (an export with the
## "demo" feature: the Demo presets in export_presets.cfg; `-- --demo` on the command line, or
## WRECKSMITH_DEMO=1, for trying it out). The demo plays the campaign, alone or as a party, to
## its second boss and stops there with a look at what the full game holds; the arena and the
## training have the men and beasts of those bouts, the rest are on the menus under lock.

const DEMO_STAGES := 8
## The arena modes the demo plays: alone, a duel and the free-for-all; in a room, the players'
## brawl (everyone against everyone) and the free-for-all. (The co-op campaign is at the gate.)
const DEMO_MODES_SOLO := ["duel", "bo3", "ffa"]
const DEMO_MODES_ROOM := ["pvp", "ffa"]
## The full game's store page (set it in Project Settings: wrecksmith/store_url, and the full
## game's Steam app id in wrecksmith/full_app_id to open it in the Steam overlay).
const STORE_URL_DEFAULT := "https://store.steampowered.com/"

## Beasts the demo lets a player face in the training and the arena beyond its bouts' own: one
## big monster to show off with (the gorilla that tears men in two) and a bear.
const DEMO_EXTRA_BEASTS := ["bear", "gorilla"]

static var forced = null   # tests: true/false overrides the build

static func demo() -> bool:
	if forced != null:
		return bool(forced)
	return OS.has_feature("demo") or OS.get_cmdline_user_args().has("--demo") or OS.get_environment("WRECKSMITH_DEMO") == "1"

## Past the demo's last bout: the campaign stops here in the demo.
static func demo_over(stage: int) -> bool:
	return demo() and stage > DEMO_STAGES

## Whether arena mode `k` is in this build (alone, or in a room).
static func mode_open(k: String, in_room: bool) -> bool:
	if not demo():
		return true
	return (DEMO_MODES_ROOM if in_room else DEMO_MODES_SOLO).has(k)

static var _foes: Dictionary = {}

## The men (campaign enemies) and beasts the demo's bouts bring, for a party of any size: the
## arena and the training offer these and no others.
static func demo_foes() -> Dictionary:
	if not _foes.is_empty():
		return _foes
	var men := {}
	var beasts := {}
	for s in range(1, DEMO_STAGES + 1):
		for p in range(1, 5):
			for r in Data.stage(s, p).get("rounds", []):
				for en in r:
					if en.get("beast"):
						beasts[String(en.beast)] = true
					elif en.get("e"):
						men[String(en.e)] = true
	for k in DEMO_EXTRA_BEASTS:
		beasts[k] = true
	_foes = {"men": men, "beasts": beasts}
	return _foes

## Whether foe `key` ("foe:<enemy>", a beast's key, or a plain kind) can be faced in this build.
static func foe_open(key: String) -> bool:
	if not demo() or key == "none" or key == "gladiator":
		return true
	var f := demo_foes()
	if key.begins_with("foe:"):
		return f.men.has(key.trim_prefix("foe:"))
	return f.beasts.has(key) or f.men.has(key)

## What waits in the full game, for the demo's last screen: the bouts, the bosses and the
## monsters the demo never shows.
static func full_game_tease() -> Dictionary:
	var stages: int = (Data.campaign.get("stages", []) as Array).size()
	var bosses := 0
	for row in Data.campaign.get("stages", []):
		if row.get("boss", false):
			bosses += 1
	var f := demo_foes()
	var locked := []
	for k in Data.beasts:
		if not f.beasts.has(k) and k != "goat":
			locked.append(String(Data.beasts[k].get("name", k)))
	for k in Data.campaign.get("enemies", {}):
		var en: Dictionary = Data.campaign.enemies[k]
		if not f.men.has(k) and (en.get("boss", false) or ["giant", "minotaur", "troll", "titan", "emperor", "champion"].has(k)):
			locked.append(String(en.get("label", k)))
	return {"stages": stages, "bosses": bosses, "locked": locked}

static func store_url() -> String:
	return str(ProjectSettings.get_setting("wrecksmith/store_url", STORE_URL_DEFAULT))

## Opens the full game's store page: in the Steam overlay when Steam runs, else the browser.
static func open_store() -> void:
	var app := int(ProjectSettings.get_setting("wrecksmith/full_app_id", 0))
	if app > 0 and Net.steam_ready and Net.steam.has_method("activateGameOverlayToStore"):
		Net.steam.call("activateGameOverlayToStore", app, 0)
		return
	OS.shell_open(store_url())
