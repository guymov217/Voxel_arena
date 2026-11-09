extends Node
## Two-process network test, guest side: joins, draws what the host sends, and a bot fights with its fighter.

var m: Match
var snaps := 0
var vox := 0
var spawns := 0
var helds := []
var frames := 0
var moved := 0
var last_p := Vector3.ZERO
# The proximity voice both ways (a tone stands in for the microphone, which a headless game has not).
var vc_sent := 0
var vc_heard := 0
var vc_peak := 0.0
var _tone_ph := 0.0
var _steps := 0
var thr_min := 32

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	Net.my_name = "Guest"
	# His own gladiator: the armour he wears and his look reach the host with his hello; a wound
	# taken after it, with "me" (Net.push_me).
	Net.my_loadout = {"main": "gladius", "gear": ["helmet"], "look": ["hair_crop"], "stats": {"vis": 2}}
	Net.my_body = Body.empty()
	# NO_DTLS=1: a guest that does not speak the host's encryption (it must not get in).
	if OS.get_environment("NO_DTLS") != "":
		Net.dtls = false
	print("GUEST join ", Net.join_enet("127.0.0.1", port))
	Net.message.connect(_on)
	# KICK=1: turned out by the host, he knocks again and is turned away again.
	if OS.get_environment("KICK") != "":
		var kicks := [0]
		Net.disconnected.connect(func():
			kicks[0] += 1
			print("GUEST left (", kicks[0], "): ", Net.leave_reason)
			var why := Net.leave_reason
			Net.leave_reason = ""
			if kicks[0] == 1:
				await get_tree().create_timer(1.0).timeout
				print("GUEST joins again ", Net.join_enet("127.0.0.1", port))
			else:
				get_tree().quit(0 if why != "" else 1))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
		_steps += 1
		if _steps % 12 == 0 and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			var hp: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(1)
			if hp:
				thr_min = mini(thr_min, int(hp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)))
		if m and snaps > 10 and vc_sent < 50 and _steps % 5 == 0:
			Net.send_all("vc", VoiceChat.encode(_tone(), 4), false)
			vc_sent += 1
		# Drawn between snapshots: the fighters move every physics step, not only when a
		# snapshot comes in (which looked like a game at 24 frames a second).
		if m and m.me and is_instance_valid(m.me.f) and snaps > 10:
			var p: Vector3 = m.me.f.torso.global_position
			frames += 1
			if p.distance_squared_to(last_p) > 1e-10:
				moved += 1
			last_p = p
	print("GUEST timeout")
	get_tree().quit(1)

func _on(type: String, data, _from: int) -> void:
	match type:
		"start":
			m = Match.new()
			add_child(m)
			m.setup({"mode": data.mode, "stage": data.stage, "role": "guest", "headless": true, "autopilot": true})
			Net.my_body = {"missing": ["forearmL"]}
			Net.push_me()
		"spawn":
			spawns += 1
			if m: m.guest_spawn(data)
		"snap":
			snaps += 1
			if m: m.apply_snapshot(data)
		"vox":
			vox += 1
			if m: m.guest_vox(data)
		"held":
			helds.append("%s/%s" % [str(data.get("t", "")), str(data.get("st", []))])
			if m: m.guest_message(type, data)
		"vc":
			var b = data.get("d") if data is Dictionary else data
			if b is PackedByteArray:
				vc_heard += 1
				for f in VoiceChat.decode(b):
					vc_peak = maxf(vc_peak, absf(f.x))
		"bye":
			var me_found: bool = m != null and m.me != null
			print("GUEST ping ", Net.ping_ms, " ms host steps ", Net.host_rate, " snaps/s ", Net.snap_rate)
			print("GUEST held ", helds)
			print("GUEST voice sent ", vc_sent, " heard ", vc_heard, " peak ", snappedf(vc_peak, 0.01))
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				var pp: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(1)
				if pp:
					print("GUEST lowest throttle on the way ", thr_min)
					print("GUEST line to the host: throttle %d/%d loss %.3f rtt %d ms" % [pp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE), ENetPacketPeer.PACKET_THROTTLE_SCALE, pp.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE), pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)])
			print("GUEST spawns ", spawns, " entities ", m.entities.size() if m else 0, " snaps ", snaps, " vox ", vox, " me ", me_found, " smooth ", moved, "/", frames)
			# Moving at least on most steps (the bout keeps him busy): not stepping at snapshot rate.
			# The meter's round trip came back: the guest knows its ping and how the host keeps up.
			# The host's voice came through (a little loss allowed: it rides the unreliable channel).
			var voice_ok := vc_heard >= 40 and vc_peak > 0.3
			get_tree().quit(0 if frames > 0 and float(moved) / frames > 0.5 and Net.ping_ms >= 0.0 and Net.host_rate > 0.0 and voice_ok else 1)

## 40 ms of a 300 Hz tone at half scale, as the microphone's capture would hand it over (stereo, 44.1 kHz).
func _tone() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in VoiceChat.PACKET_FRAMES * 4:
		var v := 0.5 * sin(_tone_ph)
		_tone_ph += TAU * 300.0 / 44100.0
		out.append(Vector2(v, v))
	return out
