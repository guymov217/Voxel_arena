extends Node
## Two-process network test, guest side: joins, draws what the host sends, walks forward.

var m: Match
var snaps := 0
var vox := 0
var spawns := 0

func _ready() -> void:
	var port := int(OS.get_environment("NET_PORT")) if OS.get_environment("NET_PORT") != "" else 17777
	Net.my_name = "Guest"
	print("GUEST join ", Net.join_enet("127.0.0.1", port))
	Net.message.connect(_on)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
		if m and Net.active():
			var inp := {"mz": 1.0, "main": {"x": 0.1, "y": 0.2}, "look": {"yaw": 0.0, "pitch": 0.0}}
			Net.send_host("input", PlayerInput.pack(inp), false)
	print("GUEST timeout")
	get_tree().quit(1)

func _on(type: String, data, _from: int) -> void:
	match type:
		"start":
			m = Match.new()
			add_child(m)
			m.setup({"mode": data.mode, "stage": data.stage, "role": "guest", "headless": true})
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
			print("GUEST spawns ", spawns, " entities ", m.entities.size() if m else 0, " snaps ", snaps, " vox ", vox, " me ", me_found)
			get_tree().quit(0)
