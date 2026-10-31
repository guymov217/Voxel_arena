class_name Achievements
## What the game marks as done (Steam achievements when Steam runs; the save keeps them too, so
## nothing is lost offline and a Steam client that comes later gets them all). The ids are the
## API names to set up in Steamworks (docs/DEMO.md lists them with their texts).

const LIST := {
	"first_blood": {"name": "First Blood", "desc": "Your first kill in the arena."},
	"headsman": {"name": "Headsman", "desc": "Ten heads taken.", "count": 10},
	"beast_slayer": {"name": "Beast Slayer", "desc": "Bring down a beast."},
	"boss": {"name": "The Emperor's Pet", "desc": "Beat a boss of the campaign."},
	"eight_bouts": {"name": "Eight Bouts", "desc": "Clear the eighth bout of the campaign."},
	"halfway": {"name": "Halfway to the Rudis", "desc": "Clear the thirty-second bout."},
	"rudis": {"name": "The Rudis", "desc": "Win the campaign: the wooden sword is yours."},
	"rudis_again": {"name": "Twice Free", "desc": "Win the campaign a second time round."},
	"unbroken": {"name": "Unbroken", "desc": "Win the campaign on Ironman: one life, never once fallen."},
	"jupiter_hand": {"name": "The Hand of Jupiter", "desc": "Hurl a man hard enough that his landing hurts."},
	"trained": {"name": "A Body of Iron", "desc": "Take one of the trainer's abilities to its best."},
	"smith": {"name": "Wrecksmith", "desc": "Keep a weapon of your own design."},
	"armourer": {"name": "Armourer", "desc": "Keep a piece of armour of your own design."},
	"lifted": {"name": "Brother in Arms", "desc": "Lift a friend from death's door."},
	"javelin": {"name": "Javelin", "desc": "Kill a man with a thrown weapon."},
	"darling": {"name": "Darling of the Crowd", "desc": "Win the whole crowd over in one bout."},
}

static var _asked := false

static func unlocked(id: String) -> bool:
	return bool((Save.get_value("achievements", {}) as Dictionary).get(id, false))

## Marks `id` done: once in the save, and on Steam when it runs.
static func unlock(id: String) -> bool:
	if not LIST.has(id) or unlocked(id):
		return false
	var got: Dictionary = Save.get_value("achievements", {})
	got[id] = true
	Save.set_value("achievements", got)
	_steam_set(id)
	return true

## One more towards a counted achievement (the save keeps the count); done at its count.
static func count(id: String, n := 1) -> void:
	if not LIST.has(id) or unlocked(id):
		return
	var counts: Dictionary = Save.get_value("achievement_counts", {})
	counts[id] = int(counts.get(id, 0)) + n
	Save.set_value("achievement_counts", counts)
	if int(counts[id]) >= int(LIST[id].get("count", 1)):
		unlock(id)

## Everything the save says is done, told to Steam (a client that was not running the first time).
static func sync() -> void:
	for id in Save.get_value("achievements", {}):
		_steam_set(String(id))

static func _steam_set(id: String) -> void:
	if not Net.steam_ready or Net.steam == null:
		return
	if not _asked and Net.steam.has_method("requestCurrentStats"):
		Net.steam.call("requestCurrentStats")
		_asked = true
	if Net.steam.has_method("setAchievement"):
		Net.steam.call("setAchievement", id)
	if Net.steam.has_method("storeStats"):
		Net.steam.call("storeStats")
