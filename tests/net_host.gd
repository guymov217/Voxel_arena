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
	var guest_moved := 0.0
	for e in m.entities:
		if e.kind == "remote":
			guest_moved = e.f.torso.global_position.distance_to(Vector3(e.spec.pos))
	print("HOST entities ", m.entities.size(), " cuts ", cut[0], " guest moved ", snappedf(guest_moved, 0.01))
	Net.send_all("bye", {})
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
