class_name CampaignRun
## How a campaign deals with death, chosen when one begins (DOM-free: the menu calls it).
## Ironman: a death ends the run, back to bout 1 with nothing, as it always was; win the rudis
## that way and the Emperor gives what nobody else gets (the Unbroken laurel, and the trainer
## teaches Virtus). Legionary: a death sends him back to the last checkpoint (every few bouts,
## the campaign's own `checkpoint` rows), as he walked out of it: the purse, the arms, the armour,
## the body and the training he had then. Alone and in co-op each keeps its own (`coop_` keys).

const MODES := {
	"legionary": {"name": "Legionary", "desc": "A death sends you back to the last checkpoint (every four bouts), with the purse, arms, armour, body and training you had there."},
	"ironman": {"name": "Ironman", "desc": "One life. A death ends the run: back to bout 1 with nothing. Win the rudis this way and the Emperor gives you what no one else gets."},
}

## What a checkpoint keeps: every key a death takes.
const KEPT := ["coins", "body", "arms", "armor_worn", "armor_wear", "training", "kit", "run_seed", "oddities_sold"]

static func _k(key: String, coop: bool) -> String:
	return ("coop_" + key) if coop else key

## The run's mode. An old save with none is an Ironman run: that was the only rule there was.
static func mode(coop := false) -> String:
	var m := str(Save.get_value(_k("campaign_mode", coop), "ironman"))
	return m if MODES.has(m) else "ironman"

## Whether a mode has been chosen for this save (the menu asks before the first bout if not).
static func chosen(coop := false) -> bool:
	return MODES.has(str(Save.get_value(_k("campaign_mode", coop), "")))

## A new run in `m`: the checkpoint it may fall back to is the start.
static func begin(m: String, coop := false) -> void:
	Save.set_value(_k("campaign_mode", coop), m if MODES.has(m) else "legionary")
	Save.set_value(_k("checkpoint_save", coop), {})

## A checkpoint bout won: what he walks out with is kept, to come back to after a death.
static func keep(coop := false) -> void:
	var snap := {}
	for key in KEPT:
		var v = Save.get_value(key, null)
		if v != null:
			snap[key] = v
	snap["lap"] = Save.get_value(_k("lap", coop), 1)
	Save.set_value(_k("checkpoint_save", coop), snap)

## The checkpoint's own bout begins (the first after it, the one a death sends him back to): he
## walks out of the yard into it as he is now, and that is what is kept, the physician's mending
## and what he bought there since included. (Kept only as the checkpoint bout was won, the wounds
## that bout left on him came back with a death after the physician had closed them: back in the
## yard with a fight's wounds instead of as he left the checkpoint, user.)
static func walk_in(stage: int, coop := false) -> void:
	if mode(coop) != "legionary" or stage != int(Save.get_value(_k("checkpoint", coop), 1)):
		return
	var snap = Save.get_value(_k("checkpoint_save", coop), {})
	if snap is Dictionary and not (snap as Dictionary).is_empty():
		keep(coop)

## The bout a death would send him back to now (0: none, the run would be over).
static func falls_back_to(coop := false) -> int:
	if mode(coop) != "legionary":
		return 0
	var snap = Save.get_value(_k("checkpoint_save", coop), {})
	if not (snap is Dictionary) or (snap as Dictionary).is_empty():
		return 0
	return maxi(1, int(Save.get_value(_k("checkpoint", coop), 1)))

## After a death: in a Legionary run with a checkpoint kept, put everything back as it was there
## and return the bout he goes on from; 0 when the run is over (Ironman, or no checkpoint yet).
static func fall_back(coop := false) -> int:
	if mode(coop) != "legionary":
		return 0
	var snap = Save.get_value(_k("checkpoint_save", coop), {})
	var at := int(Save.get_value(_k("checkpoint", coop), 1))
	if not (snap is Dictionary) or (snap as Dictionary).is_empty():
		return 0
	at = maxi(1, at)
	for key in KEPT:
		if snap.has(key):
			Save.set_value(key, snap[key])
	Save.set_value(_k("lap", coop), int(snap.get("lap", 1)))
	Save.set_value(_k("stage", coop), at)
	return at

## The rudis won: on an Ironman run the reward is his for good (every campaign after, too).
## True the first time it is earned.
static func won(coop := false) -> bool:
	if mode(coop) != "ironman":
		return false
	var first := not unbroken()
	Save.set_value("ironman_won", true)
	Achievements.unlock("unbroken")
	return first

static func unbroken() -> bool:
	return bool(Save.get_value("ironman_won", false))
