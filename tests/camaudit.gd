extends Node
## The fight camera put through what a fight does to it (user: the player's camera must work as
## well as it can, nothing in its way, no bugs): for each case, a player driven about by script
## (walking round the foe, looking about, swinging) and the camera followed as the match does it;
## what went wrong, frame by frame: a jump or a jerk of the view, the camera inside a body (his
## own, the foe's, a giant's, a beast's) or behind a wall, the foe hidden behind his own body or
## out of the frame, the view swinging while the mouse is still. `-- --probe camaudit`; CASES.

const CASES := ["duel", "giant", "elephant_behind", "down", "look_extremes", "yard", "wall_pinned", "dead"]

func _inside_any(m: Match, eye: Vector3, pad: float) -> String:
	for e in m.entities:
		var f = e.f
		if not is_instance_valid(f):
			continue
		for p in f.parts:
			if p.severed or p.missing:
				continue
			var a: Vector3 = p.global_transform.affine_inverse() * eye
			var h: Vector3 = p.half_ext + Vector3.ONE * pad
			if absf(a.x) < h.x and absf(a.y) < h.y and absf(a.z) < h.z:
				return "%s %s" % [f.display_name, p.part_name]
	return ""

## Which of his own parts stands between the camera and a point ("" if none): the same slab test
## the camera makes (CameraRig._blocked), part by part.
func _occluder(f, eye: Vector3, to: Vector3) -> String:
	for p in f.parts:
		if p.severed:
			continue
		var inv: Transform3D = p.global_transform.affine_inverse()
		var e: Vector3 = p.half_ext * 1.1
		var a: Vector3 = inv * eye
		var d: Vector3 = inv * to - a
		var t0 := 0.0
		var t1 := 1.0
		var miss := false
		for ax in 3:
			if absf(d[ax]) < 1e-6:
				if absf(a[ax]) > e[ax]:
					miss = true
					break
			else:
				var ta := (-e[ax] - a[ax]) / d[ax]
				var tb := (e[ax] - a[ax]) / d[ax]
				t0 = maxf(t0, minf(ta, tb))
				t1 = minf(t1, maxf(ta, tb))
				if t0 > t1:
					miss = true
					break
		if not miss and t1 < 0.97:
			return p.part_name
	return ""

func _ready() -> void:
	var only := OS.get_environment("CASES").split(",", false)
	for case in CASES:
		if not only.is_empty() and not only.has(case):
			continue
		await _run(case)
	get_tree().quit()

func _run(case: String) -> void:
	var m := Match.new()
	add_child(m)
	var mode := "yard" if case == "yard" else "training"
	var enemy := "none"
	m.setup({"mode": mode, "training": {"enemy": enemy, "respawn": false}, "headless": false, "seed": 5, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var me: Fighter = m.me.f
	me.mods.toughness = 6.0
	var foe = null
	match case:
		"giant":
			var spec: Dictionary = m.enemy_spec({"e": "giant"}, 0, 1)
			spec.pos = Vector3(0, 0.1, 4.0)
			spec.diff = 0.5
			foe = m.spawn_fighter(spec)
		"elephant_behind":
			foe = m.spawn_fighter({"kind": "bot", "name": "Foe", "loadout": {"main": "gladius", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 3.0), "yaw": PI, "diff": 0.5})
			# A big beast of his own side right behind him, where the camera wants to be.
			m.spawn_beast({"kind": "beast", "beast": "elephant", "scale": 1.0, "name": "Elephant", "team": 0, "pos": Vector3(0, 0.1, -4.0), "yaw": 0.0, "harmless": true})
		"yard":
			pass
		_:
			if case != "look_extremes":
				foe = m.spawn_fighter({"kind": "bot", "name": "Foe", "loadout": {"main": "gladius", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 3.0), "yaw": PI, "diff": 0.5})
	if foe:
		foe.f.mods.toughness = 6.0
	if case == "wall_pinned":
		me.teleport(Vector3(0, 0.1, -Arena.RADIUS + 0.6))
	var st := {"t": 0.0, "yaw": 0.0, "pitch": 0.0}
	m.me.drive = func(_e):
		st.t += 1.0 / 120.0
		var inp := {"main": {"x": 0.3 * sin(st.t * 2.0), "y": 0.2 + 0.3 * sin(st.t * 1.3)}}
		match case:
			"look_extremes":
				st.pitch = -1.4 if fmod(st.t, 4.0) < 2.0 else 1.3
				st.yaw = st.t * 0.6
			"yard":
				st.yaw = st.t * 0.4
				inp.mz = 1.0
				inp.sprint = true
			_:
				# Circle the foe, facing him, now and then a swing.
				if foe and is_instance_valid(foe.f):
					var d: Vector3 = foe.f.torso.global_position - me.torso.global_position
					st.yaw = atan2(d.x, d.z)
				inp.mx = 0.7 if fmod(st.t, 6.0) < 3.0 else -0.7
				inp.power = fmod(st.t, 1.5) < 0.4
		inp.look = {"yaw": st.yaw, "pitch": st.pitch}
		return inp
	if m.input:
		m.input.look_yaw = 0.0
	for i in 60:
		await get_tree().physics_frame
	if case == "down":
		me.fall(3.0, true)
	if case == "dead":
		me.die("test")
	var n := 0
	var jumps := 0
	var jerks := 0
	var inside := {}
	var behind_wall := 0
	var hidden := 0
	var hid_by := {}
	var out_frame := 0
	var max_jump := 0.0
	var max_turn := 0.0
	var prev_p = null
	var prev_d = null
	var prev_look_yaw := 0.0
	var frames := 8 * 120
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame
		if m.input:
			m.input.look_yaw = st.yaw
			m.input.look_pitch = st.pitch
		var cam: CameraRig = m.cam
		if cam == null:
			break
		var cp := cam.global_position
		var cd := -cam.global_basis.z
		n += 1
		if prev_p != null:
			var jmp: float = cp.distance_to(prev_p)
			max_jump = maxf(max_jump, jmp)
			if jmp > 0.25:
				jumps += 1
				if OS.get_environment("TRACE") != "":
					print("   jump at frame %d: %s -> %s (him %s)" % [i, str(prev_p), str(cp), str(me.torso.global_position)])
			var turn: float = rad_to_deg(cd.angle_to(prev_d))
			# A turn the mouse did not ask for: the look's own change taken off.
			var asked: float = rad_to_deg(absf(wrapf(st.yaw - prev_look_yaw, -PI, PI)))
			var extra := maxf(0.0, turn - asked - 0.5)
			max_turn = maxf(max_turn, extra)
			if extra > 6.0:
				jerks += 1
		prev_p = cp
		prev_d = cd
		prev_look_yaw = st.yaw
		var who := _inside_any(m, cp, 0.04)
		if who != "":
			inside[who] = int(inside.get(who, 0)) + 1
		if case != "yard" and Vector2(cp.x, cp.z).length() > Arena.RADIUS:
			behind_wall += 1
		if foe and is_instance_valid(foe.f) and foe.f.alive and me.alive:
			var fp: Vector3 = foe.f.torso.global_position + Vector3(0, 0.25, 0)
			if CameraRig._blocked(me, cp, [fp, foe.f.head.global_position]) > 0.0:
				hidden += 1
				var by := _occluder(me, cp, fp)
				if by == "":
					by = _occluder(me, cp, foe.f.head.global_position) + " (head)"
				hid_by[by] = int(hid_by.get(by, 0)) + 1
			if not cam.is_position_in_frustum(fp):
				out_frame += 1
	print("CAMAUDIT %-16s frames %d  jumps>25cm %d (max %.2f m)  unasked turns>6deg %d (max %.1f)  inside a body %s  behind the wall %d  foe hidden by himself %d %s  foe out of frame %d" % [case, n, jumps, max_jump, jerks, max_turn, str(inside), behind_wall, hidden, str(hid_by), out_frame])
	m.queue_free()
	await get_tree().physics_frame
