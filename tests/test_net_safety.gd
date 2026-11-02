extends Node
## Playing with friends safely: what a guest sends the host is read as data and made safe (names,
## weapons, kits, input), a guest cannot speak for the host, flood him, walk in twice, or fill
## the party's purse from nothing.

var t

func test_names_are_shown_as_names() -> void:
	t.eq(Net.clean_name("[color=red]Boss[/color]"), "(color=red)Boss(/color)", "no markup in a name")
	t.eq(Net.clean_name("a\nb\tc\u0007d"), "abcd", "no control characters")
	t.eq(Net.clean_name("x".repeat(500)).length(), 24, "24 letters at most")
	t.eq(Net.clean_name("   "), "Guest", "an empty name is Guest")
	t.eq(Net.clean_name({"a": 1}), "Guest", "not a string: no name, no error")
	t.eq(Net.clean_name("", 20, ""), "", "a lobby's empty mode stays empty")

func test_numbers_from_the_wire() -> void:
	t.eq(Net.num(3), 3.0, "an int")
	t.eq(Net.num(2.5), 2.5, "a float")
	t.eq(Net.num("7", -1.0), -1.0, "a string is not a number")
	t.eq(Net.num([1], -1.0), -1.0, "nor a list")
	t.eq(Net.num(NAN, 0.8), 0.8, "nor a NaN")
	t.eq(Net.num(INF, 0.8), 0.8, "nor infinity")

func _blade() -> Dictionary:
	var vox := []
	for y in range(0, 4):
		vox.append([0, y, 0, "wood", "grip"])
	for y in range(4, 12):
		vox.append([0, y, 0, "steel", "edge", 0])
	return {"name": "Mine", "voxels": vox, "sharpness": 0.7}

func test_a_forged_weapon_is_kept_to_what_the_forge_makes() -> void:
	var ok = Net.clean_design(_blade())
	t.check(ok != null and ok.voxels.size() == 12, "a real design comes through whole")
	var big := _blade()
	for i in ForgeLib.MAX_VOXELS:
		big.voxels.append([1, 1, 0, "steel", "edge"])
	t.eq(Net.clean_design(big), null, "more blocks than the forge allows: refused")
	for bad in [[0, 1, 0, "unobtainium", "edge"], [0, 999, 0, "steel", "edge"], [{"x": 1}, 1, 0, "steel", "edge"], [0, 1, 0, "steel", "laser"], [0, 1, 0, 5, "edge"], [0, 1]]:
		var d := _blade()
		d.voxels.append(bad)
		t.eq(Net.clean_design(d), null, "a block that is not a block (%s): refused" % str(bad))
	var odd := _blade()
	odd.sharpness = NAN
	odd.durability = INF
	odd.balance = [NAN, 2, 0]
	odd.imbue = "lightning"
	odd.grips = {"main": ["a", 0, 0]}
	odd.chain = {"head": _blade(), "links": 1e9}
	var c = Net.clean_design(odd)
	t.check(c != null, "a design with odd numbers is mended, not refused")
	if c != null:
		t.eq(c.sharpness, 0.8, "a NaN edge is the usual edge")
		t.eq(c.durability, 1.0, "an endless durability is the usual one")
		t.eq(c.has("balance"), false, "a NaN balance point is dropped")
		t.eq(c.has("imbue"), false, "an unknown gem power is dropped")
		t.eq(c.grips.has("main"), false, "a grip that is not a place is dropped")
		t.eq(int(c.chain.links), 16, "a chain of a billion links is 16")

func test_a_loadout_from_the_wire() -> void:
	var lo := Net.sanitize_loadout({"main": "no_such_weapon", "off": _blade(), "armor": ["helmet", "crown_of_hacks", 5], "armor_defs": "x"})
	t.eq(lo.main, "gladius", "an unknown weapon is the gladius")
	t.eq(lo.off is Dictionary, true, "his own forged weapon is kept")
	t.eq(lo.armor, ["helmet"], "only armour that exists")
	t.eq(Net.sanitize_loadout("not a loadout"), {"main": "gladius"}, "not a loadout: the gladius")
	var kit := Net.sanitize_kit({"thunderPot": 99, "nukePot": 3, "nailPot": "lots"})
	t.eq(kit.has("nukePot"), false, "no throwable that does not exist")
	t.check(int(kit.get("thunderPot", 0)) <= 20, "no more pots than a bag holds")
	t.eq(int(kit.get("nailPot", 0)), 0, "a count that is not a number is none")

func test_input_that_is_not_input() -> void:
	t.eq(PlayerInput.unpack([1, 2]), {}, "too short: dropped")
	var a := []
	for i in 13:
		a.append(0.0)
	a[0] = NAN
	t.eq(PlayerInput.unpack(a).mx, 0.0, "a NaN stick is still")
	a[3] = "x"
	t.eq(PlayerInput.unpack(a), {}, "a string in it: dropped")

## The host's own rules, run as a host: a guest's snapshot is not the host's word, a second
## hello does not bring a second fighter, a flood is cut off.
func test_a_guest_cannot_speak_for_the_host() -> void:
	var heard := []
	var joined := []
	var on_msg := func(type, _d, from): heard.append("%s/%d" % [type, from])
	var on_join := func(id, _info): joined.append(id)
	Net.message.connect(on_msg)
	Net.peer_joined.connect(on_join)
	Net.transport = "test"   # (the offline peer: this game is id 1, the host)
	t.check(Net.is_host(), "running as the host")
	for type in ["snap", "spawn", "banner", "end", "start", "kicked", "purse", "body"]:
		Net._receive(type, {}, 9)
	t.eq(heard, [], "nothing but what guests may say gets through")
	Net._receive("hello", {"name": "[b]Eve[/b]", "loadout": {"main": "axe"}}, 9)
	Net._receive("hello", {"name": "Eve again", "loadout": {"main": "axe"}}, 9)
	t.eq(joined, [9], "one hello, one fighter")
	t.eq(Net.peers[9].name, "(b)Eve(/b)", "his name, cleaned")
	Net._receive("doctor_done", {}, 9)
	t.eq(heard, ["doctor_done/9"], "what a guest may say is heard")
	Net._rate.clear()
	heard.clear()
	for i in Net.MSG_PER_S + 50:
		Net._receive("doctor_done", {}, 9)
	t.eq(heard.size(), Net.MSG_PER_S, "a flood is cut off at %d a second" % Net.MSG_PER_S)
	Net.message.disconnect(on_msg)
	Net.peer_joined.disconnect(on_join)
	Net.peers.erase(9)
	Net._rate.clear()
	Net.transport = ""

func test_the_purse_takes_no_more_than_a_guest_may_put_in() -> void:
	Net.purse_credit.clear()
	t.eq(Net.purse_take(9, 100000), Net.PURSE_JOIN, "a newcomer: a little, for what he brought to sell")
	t.eq(Net.purse_take(9, 50), 0, "then nothing from nothing")
	Net.purse_spent(9, 300)
	t.eq(Net.purse_take(9, 500), 300, "what he spent may come back (a sale)")
	Net.peers[9] = {"name": "Eve"}
	Net.purse_fight_over()
	t.eq(Net.purse_take(9, 1000), Net.PURSE_PER_FIGHT, "a fight's missions pay")
	t.eq(Net.purse_take(9, -20), 0, "a negative put-in is no put-in")
	Net.peers.erase(9)
	Net.purse_credit.clear()
