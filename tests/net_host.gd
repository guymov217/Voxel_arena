extends Node
## Two-process network test, host side (`-- --probe net_host`): opens a room, waits for the
## guest's hello, starts a campaign stage with an autopilot and the guest as a second fighter.

var m: Match
# The proximity voice: the guest's tone heard here from his gladiator's head, the host's own sent back.
var vc: VoiceChat
var vc_heard := 0
var _tone_ph := 0.0
var thr_min := 32
var mouth_max := 0

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	print("HOST listen ", Net.host_enet(port))
	# (Headless, the voice node leaves the wire alone: joined to it by hand here.)
	vc = VoiceChat.new()
	add_child(vc)
	Net.message.connect(vc._on_net)
	Net.message.connect(func(type, data, _from):
		if type == "vc" and data is PackedByteArray:
			vc_heard += 1)
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
	var gear_in: Array = Net.peers.values()[0].loadout.get("gear", [])
	print("HOST the guest's armour from his hello ", gear_in, " his teaching ", Net.peers.values()[0].loadout.get("stats", {}))
	var peers := []
	for id in Net.peers:
		peers.append({"id": id, "name": Net.peers[id].name, "loadout": {"main": "axe"}})
	Net.send_all("start", {"mode": "campaign", "stage": 1})
	m = Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "autopilot": true, "peers": peers, "seed": 9})
	vc.menu = {"match_": m}
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
		if i % 12 == 0 and multiplayer.multiplayer_peer is ENetMultiplayerPeer and not Net.peers.is_empty():
			var gp: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(Net.peers.keys()[0])
			if gp:
				thr_min = mini(thr_min, int(gp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)))
		if i >= 120 * 3 and i < 120 * 3 + 250 and i % 5 == 0:
			Net.send_all("vc", VoiceChat.encode(_tone(), 4), false)
		# (Headless the voice node does not run itself: its mouths moved by hand.)
		vc.animate(1.0 / 120.0)
		for e in m.entities:
			if e.kind == "remote" and is_instance_valid(e.f):
				mouth_max = maxi(mouth_max, int(e.f.head.get_meta("talk_state", 0)))
	var guest_moved := 0.0
	for e in m.entities:
		if e.kind == "remote":
			guest_moved = e.f.torso.global_position.distance_to(Vector3(e.spec.pos))
	print("HOST entities ", m.entities.size(), " cuts ", cut[0], " guest moved ", snappedf(guest_moved, 0.01))
	# The guest's voice: heard, from his gladiator's head.
	vc._place()
	var gid: int = Net.peers.keys()[0]
	var from_head := -1.0
	for e in m.entities:
		if int(e.get("peer", -1)) == gid and vc.players.has(gid):
			var mouth: Vector3 = e.f.head.global_position if not e.f.head.severed else e.f.torso.global_position
			from_head = (vc.players[gid] as AudioStreamPlayer3D).global_position.distance_to(mouth)
	print("HOST voice heard ", vc_heard, " speakers ", vc.players.keys(), " from his head ", snappedf(from_head, 0.01), " his mouth opened to ", mouth_max)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(gid)
		if pp:
			print("HOST lowest throttle on the way ", thr_min)
			print("HOST line to the guest: throttle %d/%d loss %.3f rtt %d ms" % [pp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE), ENetPacketPeer.PACKET_THROTTLE_SCALE, pp.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE), pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)])
	# What the guest told of himself since his hello ("me"): the forearm he lost.
	var told: Array = (Net.peers[gid].get("body", {}) as Dictionary).get("missing", [])
	print("HOST the guest as he is now: missing ", told)
	Net.send_all("bye", {})
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if vc_heard >= 40 and from_head >= 0.0 and from_head < 0.05 and mouth_max >= 2 and gear_in == ["helmet"] and told.has("forearmL") else 1)

## 40 ms of a 300 Hz tone at half scale, as the microphone's capture would hand it over.
func _tone() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in VoiceChat.PACKET_FRAMES * 4:
		var v := 0.5 * sin(_tone_ph)
		_tone_ph += TAU * 300.0 / 44100.0
		out.append(Vector2(v, v))
	return out
