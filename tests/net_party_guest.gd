extends Node
## Two-process test of the endless arena with a friend, guest side: joins, draws the host's waves, is held out the rewards of each
## wave over the wire (made safe, Endless.clean_offer), picks the second on his first and leaves the second wave's to run out,
## is cut down and stands up again, and reads the host's state line.

var m: Match
var offers := []          # what he was held out: [wave, ids]
var dones := 0
var spawns_of_mine := 0
var despawns := 0
var stats := []           # the host's state line as it changed
var snaps := 0
var _fed := 0
var kind_seen := ""

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17779
	Net.my_name = "Guest"
	Net.my_loadout = {"main": "gladius"}
	Net.my_body = Body.empty()
	print("GUEST join ", Net.join_enet("127.0.0.1", port))
	Net.message.connect(_on)
	# Told what the room is for, he takes up the gladiator of the friends' sandbox (as Menu does): other arms, sent as "me".
	Net.room_kind_known.connect(func(kind):
		print("GUEST the room is for: ", kind)
		kind_seen = kind
		if kind == Net.KIND_ARENA:
			Net.my_loadout = {"main": "axe"}
			Net.push_me())
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 90000:
		await get_tree().physics_frame
		if m and m.over:
			break
		if m:
			var s := m.fight_status()
			if stats.is_empty() or stats.back() != s:
				stats.append(s)
	print("GUEST timeout")
	get_tree().quit(1)

func _on(type: String, data, _from: int) -> void:
	match type:
		"start":
			m = Match.new()
			add_child(m)
			m.stage_always = true
			m.setup({"mode": data.mode, "stage": data.stage, "role": "guest", "headless": true})
		"spawn":
			if m:
				if data is Dictionary and data.get("kind") == "remote" and int(data.get("peer", -1)) == Net.my_id():
					spawns_of_mine += 1
				m.guest_spawn(data)
		"despawn":
			if m and data is Dictionary:
				if m.me != null and int(data.get("id", -1)) == int(m.me.id):
					despawns += 1
				m.guest_despawn(int(data.get("id", -1)))
		"snap":
			snaps += 1
			if m:
				m.apply_snapshot(data)
		"vox":
			if m:
				m.guest_vox(data)
		"banner":
			if m:
				m.banner.emit(data.text, data.sub)
		"isnap", "zone", "spot", "feed", "wloose", "wspawn", "wpick", "lsnap", "fx", "guts", "gutp", "kc", "kcr", "bone", "held", "fstat":
			if m:
				if type == "feed":
					_fed += 1
				m.guest_message(type, data)
		"endless_offer":
			var rs := Endless.clean_offer(data.get("r") if data is Dictionary else null)
			offers.append([int(data.get("w", -1)) if data is Dictionary else -1, rs.map(func(c): return c.id)])
			print("GUEST offer ", offers.back(), " time ", data.get("t") if data is Dictionary else "-")
			# The first wave's: picks the second of the cards at once; the second wave's is left to run out.
			if offers.size() == 1 and rs.size() >= 2:
				Net.send_host("endless_pick", 1)
		"endless_done":
			dones += 1
			print("GUEST the host says every reward is taken")
		"bye":
			var me_ok: bool = m != null and m.me != null and is_instance_valid(m.me.f) and m.me.f.alive
			var waved := stats.any(func(s): return String(s).begins_with("Wave"))
			print("GUEST offers ", offers.size(), " dones ", dones, " my spawns ", spawns_of_mine, " my despawns ", despawns, " me alive ", me_ok, " feed lines ", _fed)
			print("GUEST state lines ", stats)
			var ok: bool = kind_seen == Net.KIND_ARENA and offers.size() >= 2 and dones >= 1 and spawns_of_mine >= 2 and despawns >= 1 and me_ok and waved and snaps > 10
			print("GUEST ", "ok" if ok else "FAIL")
			get_tree().quit(0 if ok else 1)
