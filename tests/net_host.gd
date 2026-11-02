extends Node
## Two-process network test, host side (`-- --probe net_host`): opens a room, waits for the
## guest's hello, starts a campaign stage with an autopilot and the guest as a second fighter.

var m: Match

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	print("HOST listen ", Net.host_enet(port))
	Net.my_name = "Host"
	var t0 := Time.get_ticks_msec()
	while Net.peers.is_empty() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	print("HOST peers ", Net.peers.size())
	if Net.peers.is_empty():
		get_tree().quit(1)
		return
	# KICK=1: the host turns the guest out; he tries to come back in and is turned away again.
	if OS.get_environment("KICK") != "":
		await get_tree().create_timer(2.0).timeout
		var gid: int = Net.peers.keys()[0]
		Net.kick(gid)
		var seen := 0
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 12000:
			await get_tree().process_frame
			seen = maxi(seen, Net.peers.size())
			if Time.get_ticks_msec() - t1 > 1000 and not Net.peers.is_empty():
				break
		print("HOST kicked ", gid, ", in the room after: ", Net.peers.keys(), " banned ", Net._banned.keys())
		get_tree().quit(0 if Net.peers.is_empty() else 1)
		return
	var peers := []
	for id in Net.peers:
		peers.append({"id": id, "name": Net.peers[id].name, "loadout": {"main": "axe"}})
	Net.send_all("start", {"mode": "campaign", "stage": 1})
	m = Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "autopilot": true, "peers": peers, "seed": 9})
	var cut := [0]
	m.combat.hit.connect(func(h): cut[0] += h.res.removed.size())
	for i in 120 * 12:
		await get_tree().physics_frame
		# A pot readied mid-bout and put away again: the hand that takes it puts its weapon out of
		# sight on the guest's screen too, and back after ("held").
		if i == 120 * 5 and m.me:
			m.throwables.hold_item(m.me, "pot_fire", "firePot")
			print("HOST readied a pot in the ", m.me.f.held_item.side if m.me.f.held_item else "-", " hand, stowed ", m.me.f.stowed.R != null, " ", m.me.f.stowed.L != null)
		if i == 120 * 8 and m.me:
			m.throwables.put_away(m.me)
	var guest_moved := 0.0
	for e in m.entities:
		if e.kind == "remote":
			guest_moved = e.f.torso.global_position.distance_to(Vector3(e.spec.pos))
	print("HOST entities ", m.entities.size(), " cuts ", cut[0], " guest moved ", snappedf(guest_moved, 0.01))
	Net.send_all("bye", {})
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
