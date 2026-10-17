class_name Edition
## Which build this is: the full game, or the free demo for its Steam page (an export with the
## "demo" feature: the Demo presets in export_presets.cfg; `-- --demo` on the command line, or
## WRECKSMITH_DEMO=1, for trying it out). The demo plays the campaign, alone or as a party, to
## its second boss and stops there; the arena and the training have the men and beasts of those
## bouts and the demo's arena modes, and nothing else.

const DEMO_STAGES := 8
## The arena modes the demo plays: alone, a duel and the free-for-all; in a room, the players'
## brawl (everyone against everyone) and the free-for-all. (The co-op campaign is at the gate.)
const DEMO_MODES_SOLO := ["duel", "bo3", "ffa"]
const DEMO_MODES_ROOM := ["pvp", "ffa"]
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
