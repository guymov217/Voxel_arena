extends Node
## A punch, frame by frame (`-- --probe punchprobe`): the player bare-handed in his guard before
## a man at arm's length, a right (a click: the button down a tenth of a second), then a left.
## Every 1/120 s: the elbow's bend, how far the fist is out from the shoulder, its speed, and
## the blows that land. With SHOT_DIR (on a display) the arm seen from the side at the guard, a
## little into the punch, halfway out, at full reach and on its way back (PUNCH_TAG goes after
## each name). PUNCH_FRAMES: how many frames each punch is watched (60; past 60, every tenth).

var out := ""
var tag := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out = OS.get_environment("SHOT_DIR")
	tag = OS.get_environment("PUNCH_TAG")
	seed(4)
	var m := Match.new()
	add_child(m)
	m.process_mode = Node.PROCESS_MODE_PAUSABLE
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": out == "", "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var me: Fighter = m.me.f
	me.teleport(Vector3(0, 0, 0))
	var bag = m.spawn_fighter({"kind": "npc", "name": "Bag", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.02, float(OS.get_environment("BAG_Z")) if OS.get_environment("BAG_Z") != "" else 1.15), "yaw": PI})
	bag.drive = func(_e): return {}
	var st := {"jab": "", "hold": 0}
	m.me.drive = func(_e):
		var o := {"look": {"yaw": 0.0, "pitch": 0.0}, "main": PlayerInput.GUARD_MAIN, "off": PlayerInput.GUARD_OFF, "power": int(st.hold) > 0}
		st.hold = maxi(0, int(st.hold) - 1)
		if st.jab != "":
			o["jab" + String(st.jab)] = true
			st.jab = ""
		return o
	var hits := []
	m.combat.hit.connect(func(h): if h.get("char") == bag.f and h.get("attacker") == me: hits.append([me.jab_t.R, me.jab_t.L, float(h.get("J", 0.0)), String((h.part as VoxelPart).part_name) if h.get("part") is VoxelPart else ""]))
	var cam: Camera3D = m.cam if "cam" in m else null
	if out != "":
		RenderingServer.render_loop_enabled = false
	for i in 150:
		await get_tree().physics_frame
	if out != "" and cam:
		cam.set_process(false)
		cam.set_physics_process(false)
	var frames := int(OS.get_environment("PUNCH_FRAMES")) if OS.get_environment("PUNCH_FRAMES") != "" else 60
	for side in ["R", "L"]:
		hits.clear()
		st.jab = side
		st.hold = 12
		var shots := {0: "guard", 5: "wind", 12: "out", 20: "reach", 34: "back"}
		print("== %s punch: frame, bend (deg), fist out from the shoulder (m), fist speed (m/s), elbow locked" % side)
		var best := [0.0, 0.0, 0.0]
		var out_best := [0.0, 0.0, 0.0, 180.0]   # fastest on the way out, its bend, reach, and the least bend
		var locked_at := -1
		for f in frames:
			var up: VoxelPart = me.arm[side].upper
			var fore: VoxelPart = me.arm[side].fore
			var bend := rad_to_deg((PD.quat_of(up) * Vector3.DOWN).angle_to(PD.quat_of(fore) * Vector3.DOWN))
			var sh: Vector3 = me.torso.global_position + PD.quat_of(me.torso) * (me.shoulder[side] as Vector3)
			var hw: Vector3 = me.hand_world(side)
			var spd: float = fore.velocity_at(hw).length()
			var reach := sh.distance_to(hw)
			if spd > best[0]:
				best = [spd, bend, reach]
			var jk: float = 1.0 - float(me.jab_t[side]) / Fighter.JAB_TIME if float(me.jab_t[side]) > 0.0 else -1.0
			if jk >= 0.12 and jk < 0.6:
				if spd > out_best[0]:
					out_best = [spd, bend, reach, out_best[3]]
				out_best[3] = minf(out_best[3], bend)
			if locked_at < 0 and fore.get_meta("elbow_locked", false):
				locked_at = f
			if (f % 2 == 0 and f < 60) or f % 10 == 0 or shots.has(f):
				var ua: Vector3 = PD.quat_of(up) * Vector3.DOWN
				var fa: Vector3 = PD.quat_of(fore) * Vector3.DOWN
				# The hinge's own angle (about the upper arm's x: bent forward is +) and where the
				# hinge's axis points (y up): a twisted upper arm bends its elbow the wrong way.
				var hx: Vector3 = PD.quat_of(up) * Vector3.RIGHT
				var hinge := rad_to_deg(atan2(ua.cross(fa).dot(hx), ua.dot(fa)))
				print("%2d  bend %5.1f  out %.3f  speed %5.2f  %s  upper pitch %5.1f yaw %5.1f  fore pitch %5.1f yaw %5.1f  hinge %6.1f axis %5.2f %5.2f %5.2f" % [f, bend, reach, spd, "locked" if fore.get_meta("elbow_locked", false) else "      ", rad_to_deg(asin(clampf(ua.y, -1, 1))), rad_to_deg(atan2(ua.x, ua.z)), rad_to_deg(asin(clampf(fa.y, -1, 1))), rad_to_deg(atan2(fa.x, fa.z)), hinge, hx.x, hx.y, hx.z])
			if out != "" and cam and shots.has(f):
				await _shot(cam, me, side, "punch%s_%s" % [side, shots[f]])
			await get_tree().physics_frame
		print("   fastest: %.2f m/s at a bend of %.1f deg, %.3f m out" % best)
		print("   on the way out: fastest %.2f m/s (bend %.1f deg, %.3f m out), least bend %.1f deg; elbow locked first at frame %d" % [out_best[0], out_best[1], out_best[2], out_best[3], locked_at])
		for h in hits:
			print("   landed: J %.1f on %s (jab_t R %.3f L %.3f)" % [h[2], h[3], h[0], h[1]])
		print("   %d blows landed" % hits.size())
		for i in 90:
			await get_tree().physics_frame
	get_tree().quit()

func _shot(cam: Camera3D, me: Fighter, side: String, name_: String) -> void:
	get_tree().paused = true
	RenderingServer.render_loop_enabled = true
	# (He faces +z: his right is -x. The arm that punches is seen from its own side.)
	var x := -2.0 if side == "R" else 2.0
	cam.fov = 40.0
	cam.global_position = me.torso.global_position + Vector3(x, 0.25, 0.45)
	cam.look_at(me.torso.global_position + Vector3(0, 0.25, 0.45), Vector3.UP)
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [name_, tag]))
	print("saved ", name_)
	RenderingServer.render_loop_enabled = false
	get_tree().paused = false
