extends Node
## A kick at a man lying on the sand (`-- --probe stompprobe`): the player stands before a man
## put down at STOMP_Z (0.9 m by default; STOMP_X across, STOMP_YAW his facing) and kicks; every
## 1/40 s the kicking foot's height and how far it is ahead, and the blows that land on the man.
## STOMP_UP=1 leaves the man standing; STOMP_OFF=1 kicks out at hip height instead of stamping.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(5)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me: Fighter = m.me.f
	me.teleport(Vector3(0, 0, 0))
	var z := float(OS.get_environment("STOMP_Z")) if OS.get_environment("STOMP_Z") != "" else 0.9
	var up := OS.get_environment("STOMP_UP") == "1"
	var mx := float(OS.get_environment("STOMP_X")) if OS.get_environment("STOMP_X") != "" else 0.0
	var myaw := float(OS.get_environment("STOMP_YAW")) if OS.get_environment("STOMP_YAW") != "" else PI
	var man = m.spawn_fighter({"kind": "npc", "name": "Man", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(mx, 0.02, z), "yaw": myaw})
	man.drive = func(_e): return {}
	var st := {"kick": false}
	m.me.drive = func(_e):
		var o := {"look": {"yaw": 0.0, "pitch": -0.5 if not up else 0.0}, "kick": st.kick}
		st.kick = false
		return o
	var hits := []
	m.combat.hit.connect(func(h): if h.get("char") == man.f and h.get("attacker") == me: hits.append([float(h.get("J", 0.0)), bool(h.get("kick", false)), String((h.part as VoxelPart).part_name) if h.get("part") is VoxelPart else ""]))
	for i in 60:
		await get_tree().physics_frame
	if not up:
		man.f.fall(30.0, true)
	for i in 240:
		await get_tree().physics_frame
	var mt: Vector3 = man.f.torso.global_position
	print("the man: torso at (%.2f, %.2f, %.2f), state %s" % [mt.x, mt.y, mt.z, man.f.state])
	st.kick = true
	await get_tree().physics_frame
	if OS.get_environment("STOMP_OFF") == "1":
		me.stomp_at = null   # (the kick as it was: out at hip height)
	print("   the stamp's mark: %s" % str(me.stomp_at))
	var shin: VoxelPart = me.by_name["shinR"]
	var low := 9.0
	for f in 70:
		await get_tree().physics_frame
		var sole: Vector3 = shin.global_transform * Vector3(0, -4 * Fighter.V * me.S, 0)
		low = minf(low, sole.y) if f > 6 else low
		if f % 3 == 0:
			print("%2d  kick_t %.2f  sole y %.2f  ahead %.2f  speed %.1f" % [f, me.kick_timer, sole.y, sole.z - me.torso.global_position.z, shin.velocity_at(sole).length()])
	print("   lowest sole %.2f m; %d blows: %s" % [low, hits.size(), str(hits)])
	print("   he stands: %s" % me.state)
	get_tree().quit()
