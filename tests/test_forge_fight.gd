extends Node
## Forge and Fight: the host's times read safely from the wire, a player's kit made safe (only
## what he forged: no ready-made weapon or armour slipped in), the phases in order, and who takes
## it when the fight's time runs out.

var t

func _blade() -> Dictionary:
	var vox := []
	for y in range(0, 4):
		vox.append([0, y, 0, "wood", "grip"])
	for y in range(4, 12):
		vox.append([0, y, 0, "steel", "edge", 0])
	return {"name": "Mine", "voxels": vox, "sharpness": 0.7}

func test_times_from_the_host() -> void:
	t.eq(ForgeFight.clean_times({"weapons": 5, "armour": 0, "fight": 3}), {"weapons": 5, "armour": 0, "fight": 3}, "the choices on the lists come through")
	t.eq(ForgeFight.clean_times({"weapons": 999, "armour": -1, "fight": "x"}), ForgeFight.DEFAULT, "anything off the lists: the defaults")
	t.eq(ForgeFight.clean_times("nonsense"), ForgeFight.DEFAULT, "not a dictionary: the defaults")
	t.eq(ForgeFight.clean_times({"weapons": NAN}).weapons, ForgeFight.DEFAULT.weapons, "not a number: the default")

func test_phases_in_order() -> void:
	var with_armour := {"weapons": 3, "armour": 2, "fight": 0}
	var no_armour := {"weapons": 3, "armour": 0, "fight": 0}
	t.eq(ForgeFight.next_phase("weapons", with_armour), "armour", "weapons, then armour")
	t.eq(ForgeFight.next_phase("armour", with_armour), "fight", "then the fight")
	t.eq(ForgeFight.next_phase("weapons", no_armour), "fight", "no armour time: straight to the fight")
	t.eq(ForgeFight.phase_seconds("weapons", with_armour), 180.0, "minutes into seconds")
	t.eq(ForgeFight.clock(125.2), "2:06", "the clock rounds up")
	t.eq(ForgeFight.clock(-3.0), "0:00", "and never runs below nothing")

func test_a_kit_is_only_what_he_forged() -> void:
	var k := ForgeFight.clean_kit({"main": _blade(), "off": "roundShield", "armor": []})
	t.check(k.main is Dictionary and (k.main.voxels as Array).size() == 12, "a forged weapon comes through")
	t.eq(k.off, "roundShield", "the plain round shield may be taken")
	t.eq(ForgeFight.clean_kit({"main": "warhammer"}).main, "", "a ready-made weapon by name: no weapon at all")
	t.eq(ForgeFight.clean_kit({"main": "gladius", "off": "scutum"}).off, "", "nor a ready-made shield but the round one")
	t.eq(ForgeFight.clean_kit({"main": {"voxels": [[0, 999, 0, "steel", "edge"]]}}).main, "", "a design that does not hold up: bare fists, not a free sword")
	t.eq(ForgeFight.clean_kit({}).main, "", "nothing forged: bare fists")
	t.eq(ForgeFight.clean_kit("x").main, "", "not a kit at all: bare fists")

func test_armour_only_his_own_making() -> void:
	var shop_id: String = Armory.SHOP[0][0]
	t.eq(ForgeFight.clean_kit({"main": _blade(), "armor": [shop_id]}).armor, [], "a piece off the armourer's rack: not worn")
	var piece := Armory.design_piece("torso", "iron", 0.3, 1.0, false, true, "My plate")
	var c = Armory.clean_design(piece)
	t.check(c != null, "a bench piece is a sound design")
	var id := Armory.design_id(c)
	var k := ForgeFight.clean_kit({"main": _blade(), "armor": [id], "armor_defs": {id: piece}})
	t.eq(k.armor, [id], "a piece he made comes through, made known under its own id")
	t.check(Data.armor.has(id), "and the host knows it")

class FakeF:
	var blood := 0.0

func _e(b: float) -> Dictionary:
	var f := FakeF.new()
	f.blood = b
	return {"f": f}

func test_out_of_time_most_blood_wins() -> void:
	var a := _e(40.0)
	var b := _e(75.0)
	t.check(ForgeFight.leader([a, b]) == b, "the one with more blood left")
	t.eq(ForgeFight.leader([_e(50.0), _e(50.0)]), null, "level: a draw")
	t.eq(ForgeFight.leader([]), null, "nobody standing: a draw")
