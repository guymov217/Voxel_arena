class_name YardPlay
extends RefCounted
## The Ludus yard as a place to walk around in (game.js yard mode). The arena becomes the yard:
## a sign and a glowing ring at each station (G there opens it), two training dummies that
## never fall, three throwing boards that score a thrown weapon by how close to the middle it
## struck, and a shoving ring with its own champion to push out. Nobody bleeds to death here.

var m: Node
var dummies: Array = []
var champ = null
var champ_out_t := 0.0
var ring_outs := 0
var best_throw := 0
var hint := ""
var at := ""
var signs: Array = []

func _init(match_: Node) -> void:
	m = match_

func setup() -> void:
	for p in Yard.DUMMIES:
		var e = m.spawn_fighter({"kind": "npc", "name": "Training dummy", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM,
			"pos": p + Vector3(0, 0.02, 0), "yaw": 0.0, "mods": {"toughness": 3.0}, "color": 0xb08a5a})
		e.drive = func(_e): return {}
		e.harmless = true
		dummies.append(e.f)
	# The ring's champion walks back to the middle whenever he is pushed off it.
	var c = m.spawn_fighter({"kind": "npc", "name": "Ring champion", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM,
		"pos": Yard.RING.p + Vector3(0, 0.02, 0), "yaw": PI, "mods": {"toughness": 2.0}, "color": 0x7a2a8a})
	c.drive = _champ_input
	c.harmless = true
	champ = c.f
	if m.headless:
		return
	for id in Yard.STATIONS:
		var s: Dictionary = Yard.STATIONS[id]
		_ring(s.p, float(s.r), Color(1.0, 0.8, 0.35, 0.8))
		_sign(s.p + Vector3(0, 2.4, 0), String(s.label))
	_ring(Yard.RING.p, float(Yard.RING.r), Color(0.75, 0.3, 0.95, 0.85))
	_sign(Yard.RING.p + Vector3(0, 2.2, 0), "The shoving ring")
	for p in Yard.TARGETS:
		_board(p)
	_sign(Yard.TARGETS[1] + Vector3(-0.8, 1.3, 0), "Throwing boards")

func _champ_input(_e) -> Dictionary:
	var to: Vector3 = Yard.RING.p - champ.torso.global_position
	to.y = 0.0
	var far := to.length() > 0.6
	return {"mz": 0.5 if far else 0.0, "mx": 0.0, "faceAt": Yard.RING.p if far else champ.torso.global_position + Vector3(0, 0, 1)}

func _ring(p: Vector3, r: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.07
	tm.outer_radius = r
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 0.7
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = mat
	mi.mesh = tm
	m.add_child(mi)
	mi.global_position = p + Vector3(0, 0.03, 0)

func _sign(p: Vector3, text: String) -> void:
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, p.y - 0.2, 0.08)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.27, 0.15)
	bm.material = wood
	post.mesh = bm
	m.add_child(post)
	post.global_position = Vector3(p.x, (p.y - 0.2) * 0.5, p.z)
	var l := Label3D.new()
	l.text = text
	l.font = UIStyle.serif(2)
	l.font_size = 56
	l.pixel_size = 0.005
	l.outline_size = 10
	l.modulate = UIStyle.GOLD
	l.outline_modulate = Color(0.12, 0.07, 0.03)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.add_child(l)
	l.global_position = p
	signs.append(l)

func _board(p: Vector3) -> void:
	var root := Node3D.new()
	m.add_child(root)
	root.global_position = p
	root.look_at(Vector3(0, p.y, 0), Vector3.UP)
	var rings := [[0.5, Color(0.92, 0.88, 0.8)], [0.3, Color(0.7, 0.12, 0.1)], [0.15, Color(0.95, 0.85, 0.3)]]
	for i in rings.size():
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = rings[i][0]
		cm.bottom_radius = rings[i][0]
		cm.height = 0.05 + i * 0.01
		var mat := StandardMaterial3D.new()
		mat.albedo_color = rings[i][1]
		cm.material = mat
		mi.mesh = cm
		root.add_child(mi)
		mi.rotation.x = PI / 2
	var leg := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.1, p.y, 0.1)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.27, 0.15)
	lm.material = wood
	leg.mesh = lm
	m.add_child(leg)
	leg.global_position = Vector3(p.x, p.y * 0.5 - 0.3, p.z)

## Once a tick on the host: nobody bleeds out, the stations, the boards, the ring.
func update(_dt: float, local_inp: Dictionary) -> void:
	for d in dummies:
		if is_instance_valid(d):
			d.blood = 100.0
	for e in m.humans():
		if is_instance_valid(e.f):
			e.f.blood = maxf(e.f.blood, 50.0)
	if champ and is_instance_valid(champ):
		champ.blood = 100.0
		_ring_rule(_dt)
	_boards()
	if m.me and is_instance_valid(m.me.f):
		at = Yard.station_at(m.me.f.torso.global_position)
		hint = ("%s · %s" % [Yard.STATIONS[at].label, Yard.STATIONS[at].hint]) if at != "" else "The Ludus yard · walk to a station and press G · dummies, throwing boards and the shoving ring to play"
		if at != "" and local_inp.get("grab", false):
			m.station.emit(at)

func _ring_rule(dt: float) -> void:
	var inside := Yard.in_ring(champ.torso.global_position)
	if not inside and champ_out_t <= 0.0:
		champ_out_t = 2.0
		var who = champ.last_attacker
		if who and is_instance_valid(who) and who != champ:
			ring_outs += 1
			m.feed.emit("RING OUT! %s pushes the champion off the ring (%d)" % [who.display_name, ring_outs])
			m.sfx("cheer", champ.torso.global_position, 0.7)
	if champ_out_t > 0.0:
		champ_out_t -= dt
		if champ_out_t <= 0.0:
			champ.teleport(Yard.RING.p)
			champ.last_attacker = null

func _boards() -> void:
	for w in m.combat.loose_weapons:
		if not is_instance_valid(w) or w.has_meta("scored") or w.linear_velocity.length() < 3.0:
			continue
		for p in Yard.TARGETS:
			var d: float = w.global_position.distance_to(p)
			if d < 0.6:
				var pts := Yard.target_score(d)
				w.set_meta("scored", true)
				w.linear_velocity *= 0.1
				best_throw = maxi(best_throw, pts)
				m.feed.emit(("BULLSEYE! +%d" if pts == 10 else ("+%d" if pts > 0 else "Off the board")) % pts)
				m.sfx("thud", p, 1.0)
				break
