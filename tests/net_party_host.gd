extends Node
## Two-process test of the endless arena with a friend, host side (`-- --probe net_party_host`): the room's host runs the waves
## with the guest as a second fighter; each wave beaten holds out a reward to each of them (the guest's goes to him over the
## wire and his pick comes back), the fallen guest stands up again for the next wave, and the guest reads the host's state line.
## (The guest's pick is taken here as Menu takes it: Net "endless_pick" -> Endless.take_for.)
## The room is an Arena room: the guest is told so as he comes in, the host takes nothing of his campaign gladiator from his
## hello (he comes in plain), and the gladiator of his sandbox arrives as "me".

var m: Match
var en: Endless
var gid := 0

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17779
	Net.room_kind = Net.KIND_ARENA
	var plain := [false]
	Net.peer_joined.connect(func(_id, info): plain[0] = (info.loadout as Dictionary).is_empty() and (info.kit as Dictionary).is_empty())
	print("HOST listen ", Net.host_enet(port))
	Net.my_name = "Host"
	var t0 := Time.get_ticks_msec()
	while Net.peers.is_empty() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	print("HOST peers ", Net.peers.size())
	if Net.peers.is_empty():
		get_tree().quit(1)
		return
	gid = Net.peers.keys()[0]
	# His sandbox gladiator arrives as "me" (he swapped his campaign's arms for the Arena profile's).
	var me_ok := await _until(func(): return String(Net.peers[gid].get("loadout", {}).get("main", "")) == "axe", 6.0, "his sandbox gladiator")
	print("HOST the guest came in plain ", plain[0], "; his arena arms arrived ", me_ok, " (", Net.peers[gid].get("loadout", {}).get("main", ""), ")")
	# (What Menu does with a guest's pick.)
	var picks_taken := [0]
	Net.message.connect(func(type, data, from):
		if type == "endless_pick" and en != null and (data is int or data is float):
			picks_taken[0] += 1
			en.take_for(from, int(data)))
	var peers := []
	for id in Net.peers:
		peers.append({"id": id, "name": Net.peers[id].name, "loadout": {"main": "gladius", "off": ""}, "kit": {}})
	Net.send_all("start", {"mode": "endless", "stage": 1})
	m = Match.new()
	add_child(m)
	m.setup({"mode": "endless", "role": "host", "headless": true, "seed": 9, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": peers, "endless": {"seed": 11}})
	en = m.modes.endless
	en.corpse_linger = 1.5   # (a foe's body is carried off 1.5 s after he falls, here and on the guest's side: Endless._sweep)
	var ok: bool = plain[0] and me_ok
	# Wave 1: two foes for two; beaten.
	ok = await _until(func(): return en.wave >= 1 and en.phase == "fight", 12.0, "wave 1") and ok
	print("HOST wave 1 foes ", m.enemies().size(), " (plan ", en.plan(1, 2).size(), ")")
	ok = ok and m.enemies().size() == en.plan(1, 2).size()
	await get_tree().create_timer(1.0).timeout
	for e in m.enemies():
		e.f.die("wounds")
	ok = await _until(func(): return en.phase == "rest", 6.0, "rest 1") and ok
	print("HOST rest 1: offers ", en.offers.keys(), " time ", snappedf(en.rest_t, 0.1))
	# The two foes of the wave lie dead: carried off a moment later (the guest is sent the despawn of each), the players' bodies stay.
	var foes_left := await _until(func(): return m.entities.filter(func(x): return x.team == Match.ENEMY_TEAM).is_empty(), 6.0, "the foes carried off")
	print("HOST the wave's dead carried off: ", foes_left, "; both players still on the sand ", m.humans().size())
	ok = ok and foes_left and m.humans().size() == 2
	ok = ok and en.offers.has(1) and (en.offers.size() == 2 or picks_taken[0] > 0)   # (the guest may have picked already)
	# The guest picks within the time (his pick comes over the wire): his offer is taken, the host's still open.
	ok = await _until(func(): return not en.offers.has(gid), 10.0, "the guest's pick") and ok
	print("HOST the guest picked after ", snappedf(Endless.PICK_TIME - en.rest_t, 0.1), " s; picks heard ", picks_taken[0], "; the host's still open ", en.offers.has(1), "; phase ", en.phase)
	ok = ok and picks_taken[0] >= 1 and en.offers.has(1) and en.phase == "rest" and en.rest_t > 3.0
	en.take(0)
	ok = ok and en.phase == "next"
	# Wave 2: the guest's fighter is cut down (dead for good), the wave beaten: he is on his feet again for the rest.
	ok = await _until(func(): return en.wave >= 2 and en.phase == "fight", 12.0, "wave 2") and ok
	var guest_e = en.entity_of(gid)
	var guest_id: int = int(guest_e.id)
	await get_tree().create_timer(1.0).timeout
	guest_e.f.die("decap")
	await get_tree().create_timer(1.5).timeout
	print("HOST the guest's man down: alive ", guest_e.f.alive, " phase ", en.phase)
	ok = ok and en.phase == "fight"
	for e in m.enemies():
		e.f.die("wounds")
	ok = await _until(func(): return en.phase == "rest", 6.0, "rest 2") and ok
	var up = en.entity_of(gid)
	print("HOST rest 2: the guest's man alive ", up != null and up.f.alive, " same id ", up != null and int(up.id) == guest_id, " offers ", en.offers.keys())
	ok = ok and up != null and up.f.alive and int(up.id) == guest_id and en.offers.size() == 2
	# Nobody picks: the first of each is taken at the time's end, and the next horn.
	var t1 := Time.get_ticks_msec()
	ok = await _until(func(): return en.phase == "next", Endless.PICK_TIME + 8.0, "the time out") and ok
	print("HOST the time ran out after ", snappedf((Time.get_ticks_msec() - t1) / 1000.0, 0.1), " s: phase ", en.phase, " offers ", en.offers.size())
	ok = ok and en.offers.is_empty()
	await get_tree().create_timer(1.0).timeout
	Net.send_all("bye", {})
	await get_tree().create_timer(0.7).timeout
	print("HOST ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

## Frames until `cond` holds (or `secs` pass).
func _until(cond: Callable, secs: float, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		await get_tree().physics_frame
		if Time.get_ticks_msec() - t0 > int(secs * 1000.0):
			print("HOST timed out waiting for ", what)
			return false
	return true
