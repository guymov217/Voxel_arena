extends Node
## Two-process network test, guest side: joins, draws what the host sends, and a bot fights with its fighter.

var m: Match
var snaps := 0
var vox := 0
var spawns := 0
var frames := 0
var moved := 0
var last_p := Vector3.ZERO

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	Net.my_name = "Guest"
	print("GUEST join ", Net.join_enet("127.0.0.1", port))
	Net.message.connect(_on)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
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
		"spawn":
			spawns += 1
			if m: m.guest_spawn(data)
		"snap":
			snaps += 1
			if m: m.apply_snapshot(data)
		"vox":
			vox += 1
			if m: m.guest_vox(data)
		"bye":
			var me_found: bool = m != null and m.me != null
			print("GUEST ping ", Net.ping_ms, " ms host steps ", Net.host_rate, " snaps/s ", Net.snap_rate)
			print("GUEST spawns ", spawns, " entities ", m.entities.size() if m else 0, " snaps ", snaps, " vox ", vox, " me ", me_found, " smooth ", moved, "/", frames)
			# Moving at least on most steps (the bout keeps him busy): not stepping at snapshot rate.
			# The meter's round trip came back: the guest knows its ping and how the host keeps up.
			get_tree().quit(0 if frames > 0 and float(moved) / frames > 0.5 and Net.ping_ms >= 0.0 and Net.host_rate > 0.0 else 1)
