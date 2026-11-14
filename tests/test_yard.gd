extends Node
## The Ludus yard (yard.js): the stations, the dummies that never fall, the throwing boards and
## the board of the next fight; missions counted from a fight and paid; ranks from reputation.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_missions_and_ranks() -> void:
	var ms := Yard.roll_missions(7)
	t.eq(ms.size(), 3, "three missions for the next fight")
	var ids := ms.map(func(x): return x.id)
	t.check(ids.size() == 3 and ids[0] != ids[1] and ids[1] != ids[2], "all different")
	var mine := [{"id": "kill2", "n": 0}, {"id": "head", "n": 0}, {"id": "survive", "n": 0}]
	var done := Yard.apply_counts(mine, {"kill": 3, "head": 2, "survive": 1})
	t.check(done.has("kill2") and done.has("survive") and not done.has("head"), "two done, the head shots are 2 of 5")
	t.eq(int(mine[1].n), 2, "progress is kept")
	var pay := Yard.payout(done, 0)
	t.eq(int(pay.coins), 55, "they pay their denarii")
	t.eq(String(Yard.rank_of(0).name), "Tiro", "a recruit")
	t.eq(String(Yard.rank_of(950).name), "Champion", "a champion")
	t.check(Yard.mission_pay(950) > 1.0, "whose missions pay more")
	t.eq(Yard.station_at(Vector3(0, 0, 11.4)), "gate", "the gate")
	t.eq(Yard.target_score(0.1), 10, "a bullseye")

func test_the_yard_plays() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "roundShield"}})
	t.check(m.yard != null and m.yard.dummies.size() == 2, "two dummies")
	var nx := Data.stage(int(Save.get_value("stage", 1)))
	var first: Dictionary = (nx.get("rounds", [[{}]]) as Array)[0][0]
	t.check(m.yard.next_text.contains(YardPlay.foe_label(first)), "the stele by the gate names the next foe (%s)" % m.yard.next_text.replace("\n", " / "))
	t.check(m.yard.next_text.contains("PVGNA " + YardPlay.roman(int(Save.get_value("stage", 1)))), "and the bout, in numerals")
	t.check(m.find_children("*", "Fighter", true, false).all(func(f): return f.display_name != "Ring champion"), "no shoving ring any more")
	var opened := []
	m.station.connect(func(id): opened.append(id))
	m.me.f.teleport(Yard.STATIONS.market.p)
	await _steps(5)
	m.yard.update(0.01, {"talk": true})
	t.check(opened.has("market"), "E by the trader opens the market")
	# The gate is walked into and then E (walking in no longer sends him off to fight).
	m.me.f.teleport(Yard.STATIONS.gate.p + Vector3(0, 0, -0.8))
	await _steps(5)
	m.yard.update(0.01, {})
	m.yard.update(0.01, {})
	t.check(not opened.has("gate"), "standing in the gateway does not start the fight by itself")
	m.yard.update(0.01, {"talk": true})
	t.check(opened.has("gate"), "E in the gateway does")
	var solid := 0
	for n in m.find_children("*", "StaticBody3D", true, false):
		if n.get_parent() != m and n.get_parent().get_parent() == m:
			solid += 1
	t.check(solid >= 3 or VoxelArt.make("smithy") == null, "the stalls stand solid (%d)" % solid)
	var d = m.yard.dummies[0]
	d.blood = 1.0
	await _steps(2)
	t.check(d.alive and d.blood >= 99.0, "the dummy never falls")
	var w := m.spawn_loose_weapon(Data.preset("javelin"), Yard.TARGETS[0] + Vector3(0.05, 0, 0))
	w.linear_velocity = Vector3(6, 0, 0)
	await _steps(1)
	t.check(m.yard.best_throw >= 5, "a throw on the board scores")
	await _steps(240)
	t.check(not m.over, "the yard never ends")
	m.queue_free()

## Training offers the campaign's foes too: the giant comes as he does in the campaign.
func test_training_brings_the_giant() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "foe:giant", "count": 1}, "decrees": [], "hazards": [], "headless": true})
	await _steps(30)
	var en: Array = m.enemies()
	t.check(en.size() == 1 and en[0].f.boss and en[0].f.S > 3.0, "the giant stands in the training ring (%s)" % [en[0].f.display_name if en.size() else "nobody"])
	m.queue_free()

## Those who only stand in the yard rest (user: the lobby's frame rate drops sharply for
## nothing): six men stand in it beside the players, each as dear a step as a man in a fight. One
## who only stands (a dummy, the smith, the trainer) rests while no player is near him: his parts
## sleep as he stands and he is not driven. One who moves at his work (the trader, the physician)
## rests only where no player may see him at it. A player near him, a player's eyes on him at his
## work, or anything that touches him, and he is at once the man he was.
func test_those_who_only_stand_in_the_yard_rest() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": [{"id": 77, "name": "Friend", "loadout": {"main": "axe"}}]})
	var of := func(f): return m.entities.filter(func(e): return e.f == f)[0]
	var dummy = of.call(m.yard.dummies[0])
	var trader = null
	var physician = null
	var still := [dummy, of.call(m.yard.dummies[1])]
	for k in m.yard.keepers:
		var e = of.call(k)
		if not e.get("works", false):
			still.append(e)
		elif k.torso.global_position.x > 0.0:
			trader = e
		else:
			physician = e
	t.check(still.size() == 4 and trader != null and physician != null, "two dummies, two keepers who only stand, two at their work")
	# The friend stands by the gate's far side looking up the yard, the trader before him, the
	# physician behind him (no screen here: the host's own eyes see nothing).
	await _steps(420)
	var resting := func(e) -> bool: return e.get("idle", false) and e.f.parts.all(func(p): return p.severed or p.sleeping)
	t.check(still.all(resting), "nobody near them, those who only stand rest, every part of them asleep (%d of 4)" % still.filter(resting).size())
	t.check(resting.call(physician), "and one at his work behind every player's back")
	t.check(not trader.get("idle", false), "one at his work before a player's eyes is at it")
	var y0 := still.map(func(e): return e.f.torso.global_position.y)
	await _steps(240)
	var stood := true
	for i in still.size():
		var f: Fighter = still[i].f
		if not f.alive or f.state != "stand" or absf(f.torso.global_position.y - float(y0[i])) > 0.005:
			stood = false
	t.check(stood and still.all(resting), "they stand as they stood, two seconds on")
	# The friend turns round: the physician is at his work, the trader rests.
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"look": {"yaw": PI, "pitch": 0.0}}))
	await _steps(60)
	t.check(not physician.get("idle", false), "looked at, the physician is at his work at once")
	await _steps(300)
	t.check(resting.call(trader), "and the trader, nobody looking his way any more, rests")
	Net.inputs.erase(77)
	# A player walks up to a dummy: it is awake, and stands.
	m.me.f.teleport(m.yard.dummies[0].torso.global_position + Vector3(1.6, 0.0, 0.0))
	await _steps(3)
	t.check(not dummy.get("idle", false) and dummy.f.parts.all(func(p): return p.severed or (not p.sleeping and not p.can_sleep)), "a player near it, a dummy is awake")
	await _steps(120)
	t.check(dummy.f.alive and dummy.f.state == "stand" and absf(dummy.f.torso.global_position.y - float(y0[0])) < 0.05, "and stands as it stood")
	# He walks off: it rests again; a javelin thrown into it wakes it.
	m.me.f.teleport(Vector3(0.0, 0.0, -6.0))
	await _steps(300)
	t.check(resting.call(dummy), "he goes, and it rests again")
	var w := m.spawn_loose_weapon(Data.preset("javelin"), dummy.f.torso.global_position + Vector3(1.2, 0.15, 0.0))
	w.linear_velocity = Vector3(-9.0, 0.0, 0.0)
	var woke := false
	for i in 60:
		await get_tree().physics_frame
		if not dummy.get("idle", false):
			woke = true
	t.check(woke, "struck, it is awake")
	# What a camera has in its sight (the host's own screen).
	var cam := Transform3D(Basis.looking_at(Vector3(0, 0, 1)), Vector3(0, 1.5, 0))
	t.check(Match.sees(cam, 59.0, 16.0 / 9.0, Vector3(3, 1, 12)), "what stands before a camera is in its sight")
	t.check(Match.sees(cam, 59.0, 16.0 / 9.0, Vector3(12, 1, 10)) and not Match.sees(cam, 59.0, 16.0 / 9.0, Vector3(17, 1, 10)), "and what stands just off the screen's edge, not what stands well off it")
	t.check(not Match.sees(cam, 59.0, 16.0 / 9.0, Vector3(3, 1, -12)), "nor what stands behind it")
	m.queue_free()

## Killed in the yard (by a friend, as like as not), a player is back three seconds later.
func test_a_man_killed_in_the_yard_is_back_in_three_seconds() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "headless": true, "seed": 2, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "inventory": {"bread": 2}})
	await _steps(30)
	var old: Fighter = m.me.f
	var id: int = m.me.id
	old.head.hp = 0.0
	old.die("test")
	await _steps(int(2.5 * 120))
	t.check(m.me.f == old, "still down at two and a half seconds")
	await _steps(int(1.0 * 120))
	t.check(m.me.f != old and is_instance_valid(m.me.f) and m.me.f.alive, "up again by three and a half")
	t.eq(m.me.id, id, "the same player")
	t.eq(int(m.me.get("inventory", {}).get("bread", 0)), 2, "with his kit")
	t.eq(m.humans().size(), 1, "and only once")
	m.queue_free()

## The stele names every foe of the next bout, the second wave through the other gate too (user:
## it said two hyenas, and three came out).
func test_the_board_counts_the_second_wave() -> void:
	var was = Save.get_value("stage", 1)
	var n := -1
	for i in range(1, 70):
		var st: Dictionary = Data.stage(i, 1)
		var first: Array = (st.get("rounds", [[]]) as Array)[0] if not (st.get("rounds", []) as Array).is_empty() else []
		var late: Array = st.get("late", [])
		if first.size() == 2 and late.size() == 1 and late[0].get("beast", "") == "hyena" and first.all(func(f): return f.get("beast", "") == "hyena"):
			n = i
			break
	t.check(n > 0, "a bout of two hyenas and a third later (stage %d)" % n)
	if n > 0:
		Save.set_value("stage", n)
		var text := YardPlay.next_fight(1)
		t.check(text.contains("×3"), "the stele says three: %s" % text.replace("\n", " | "))
	Save.set_value("stage", was)

## The chips a bout took out of his weapons come back with him into the yard (user: the weapons'
## damage from the last bout did not come back with him), and stay when he buys something else at
## the smith: a shield bought did not mend the sword.
func test_the_weapons_come_back_to_the_yard_as_the_bout_left_them() -> void:
	var was = Save.get_value("arms", {})
	var a := Arms.sanitize({})
	a.main = Data.preset("gladius").duplicate(true)
	a.off = null
	var chips := []
	for i in a.main.voxels.size():
		if a.main.voxels[i][4] != "grip" and chips.size() < 9:
			chips.append(i)
	a = Arms.add_wear(a, {"R": chips})
	Save.set_value("arms", a)
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.enter_yard()
	await _steps(20)
	var w: Weapon = menu.match_.me.f.weapons.R
	t.check(w != null, "his sword in hand in the yard")
	if w:
		t.eq(w.vox.size() - w.alive_count(), chips.size(), "with the chips the bout took out of it")
	var a2 := Arms.sanitize(Save.get_value("arms", {}))
	a2.off = Data.preset("roundShield").duplicate(true)
	menu.set_arms(a2)
	await _steps(10)
	var w2: Weapon = menu.match_.me.f.weapons.R
	t.check(w2 != null and menu.match_.me.f.weapons.L != null, "a shield bought at the smith, in the other hand at once")
	if w2:
		t.eq(w2.vox.size() - w2.alive_count(), chips.size(), "and the sword keeps its chips")
	# A guest's chips, as the host takes them: whole numbers only, never a flood.
	var cw := Match.clean_worn({"R": [3, 4.0, "x", -1, INF], "L": range(6000), "Q": [1]})
	t.eq(str(cw.get("R")), str([3, 4]), "a guest's chips: only real indices")
	t.eq((cw.get("L", []) as Array).size(), 4096, "and never more than a weapon could have")
	t.check(not cw.has("Q"), "only the two hands")
	menu._end_match()
	menu.queue_free()
	Save.set_value("arms", was)
	await _steps(2)
