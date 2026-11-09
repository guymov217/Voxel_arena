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

## What a checkpoint keeps: every key a death takes. (The trainer's teaching is kept under
## "trainer" and Virtus under its own: under "training", an old save's key for it now holding the
## training ground's settings, a death left him what he had been taught since the checkpoint.)
const KEPT := ["coins", "body", "arms", "armor_worn", "armor_wear", "trainer", "virtus", "kit", "run_seed", "oddities_sold"]

## What a guest in the co-op campaign keeps of his own (the purse, the run and the smith's
## oddities are the host's): his body, his arms, his armour, his teaching, his bag.
const OWN := ["body", "arms", "armor_worn", "armor_wear", "trainer", "virtus", "kit"]

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
	var snap := _snap(KEPT)
	snap["lap"] = Save.get_value(_k("lap", coop), 1)
	Save.set_value(_k("checkpoint_save", coop), snap)

## The save's `keys` as they are now, each its own copy, and which keys it took ("_keys": one not
## in the save then is not in it after a death either; one an older checkpoint did not take is
## left as it is).
static func _snap(keys: Array) -> Dictionary:
	var snap := {"_keys": keys.duplicate()}
	for key in keys:
		var v = Save.get_value(key, null)
		if v != null:
			snap[key] = _copy(v)
	return snap

## The save's `keys` put back as `snap` had them.
static func _put_back(snap: Dictionary, keys: Array) -> void:
	var took: Array = snap.get("_keys", []) if snap.get("_keys") is Array else []
	for key in keys:
		if snap.has(key):
			Save.set_value(key, _copy(snap[key]))
		elif took.has(key):
			Save.erase(key)

## A value of the save as it is now, its own (the checkpoint's: nothing done to the save after it,
## in place or not, reaches it; nor does what is done to what a death puts back).
static func _copy(v):
	return v.duplicate(true) if v is Dictionary or v is Array else v

## The checkpoint's own bout begins (the first after it, the one a death sends him back to): he
## walks out of the yard into it as he is now, and that is what is kept, the physician's mending
## and what he bought there since included. (Kept only as the checkpoint bout was won, the wounds
## that bout left on him came back with a death after the physician had closed them: back in the
## yard with a fight's wounds instead of as he left the checkpoint, user.)
static func walk_in(stage: int, coop := false) -> void:
	if walks_in(stage, coop):
		keep(coop)

## Whether bout `stage` is a Legionary run's checkpoint bout, with a checkpoint kept to fall back
## to: walking into it keeps him as he goes in (walk_in; and the host tells his guests, keep_own).
static func walks_in(stage: int, coop := false) -> bool:
	if mode(coop) != "legionary" or stage != int(Save.get_value(_k("checkpoint", coop), 1)):
		return false
	var snap = Save.get_value(_k("checkpoint_save", coop), {})
	return snap is Dictionary and not (snap as Dictionary).is_empty()

## A guest walking into the co-op campaign's checkpoint bout `stage` of the host's run `run` (the
## host's word: walks_in on his side): his own as he goes in, kept to come back to if the party
## falls in a bout after it.
static func keep_own(stage: int, run: int) -> void:
	var snap := _snap(OWN)
	snap["_at"] = [stage, run]
	Save.set_value("coop_own_save", snap)

## The party fallen and the host gone back to his checkpoint `stage` of run `run` (fall_back on
## his side): a guest's own put back as he walked into that bout. False if he kept nothing there
## (he came after it, or what he kept was another run's, another host's).
static func fall_back_own(stage: int, run: int) -> bool:
	var snap = Save.get_value("coop_own_save", {})
	if not (snap is Dictionary) or (snap as Dictionary).is_empty():
		return false
	# (Read back from the save file its numbers are floats: compared as whole numbers.)
	var at = snap.get("_at")
	if not (at is Array) or (at as Array).size() != 2 or int(at[0]) != stage or int(at[1]) != run:
		return false
	_put_back(snap, OWN)
	return true

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
	_put_back(snap, KEPT)
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
