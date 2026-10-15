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
var keepers: Array = []
var last_at := "gate"   # where the player stood last tick (he starts by the gate: no walk-in then)   # the stall keepers (smith, trader, physician)

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
	# The smith, the trader and the physician, each dressed for his trade, beside his stall's
	# sign (not inside its post) between it and his workplace, at work: the smith stands by
	# his hearth, the trader sorts his wares, the physician bends over his table; whoever comes
	# up to the stall, he turns to.
	for id in Yard.stations():
		var s: Dictionary = Yard.STATIONS[id]
		if not s.has("npc"):
			continue
		var out := Vector3(s.p.x, 0, s.p.z).normalized()
		var side := Vector3(-out.z, 0, out.x)
		var p: Vector3 = s.p + out * 1.5 + side * 0.9
		var work_yaw := atan2(out.x, out.z) + 0.5
		var face_yaw := atan2(-p.x, -p.z)
		var n = m.spawn_fighter({"kind": "npc", "name": s.npc.name, "loadout": {"main": s.npc.main, "off": "", "armor": s.npc.get("armor", [])}, "team": Match.ENEMY_TEAM,
			"pos": p + Vector3(0, 0.02, 0), "yaw": face_yaw, "mods": {"toughness": 5.0}, "color": s.npc.color})
		n.drive = _keeper_input.bind(String(s.npc.get("work", "")), p, work_yaw, randf() * TAU)
		n.harmless = true
		keepers.append(n.f)
	if m.headless:
		return
	for id in Yard.stations():
		var s: Dictionary = Yard.STATIONS[id]
		# A stall is kept by someone you talk to; only the gate is a place to walk into.
		if not s.has("npc"):
			_ring(s.p, float(s.r), Color(1.0, 0.8, 0.35, 0.8))
		_sign(s.p + Vector3(0, 2.6, 0), String(s.label))
	_ring(Yard.RING.p, float(Yard.RING.r), Color(0.75, 0.3, 0.95, 0.85))
	_sign(Yard.RING.p + Vector3(0, 2.2, 0), "The shoving ring")
	for p in Yard.TARGETS:
		_board(p)
	_dress_stations()
	_sign(Yard.TARGETS[1] + Vector3(-0.8, 1.3, 0), "Throwing boards")

## A stall keeper at his work, facing his workplace (`work_yaw`), or turned to a man who comes up.
func _keeper_input(e, work: String, home: Vector3, work_yaw: float, ph: float) -> Dictionary:
	var f: Fighter = e.f
	var t := Time.get_ticks_msec() / 1000.0 + ph
	var yaw := work_yaw
	for h in m.humans():
		if is_instance_valid(h.f) and h.f.alive and Vector2(h.f.torso.global_position.x - home.x, h.f.torso.global_position.z - home.z).length() < 3.2:
			var to: Vector3 = h.f.torso.global_position - f.torso.global_position
			yaw = atan2(to.x, to.z)
			return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.25, "y": -0.2}, "off": {"x": -0.35, "y": -0.1}}
	var inp := {"look": {"yaw": yaw, "pitch": -0.35}}
	match work:
		"hammer":
			# Up over the shoulder, then down on the anvil, about once a second.
			var k := fposmod(t, 1.1) / 1.1
			inp.main = {"x": 0.15, "y": 1.3 if k < 0.55 else -1.1}
			inp.power = k >= 0.55 and k < 0.7
			inp.off = {"x": -0.3, "y": -0.7}
		"wares":
			# Reaching along the stall, picking things up and setting them down.
			inp.main = {"x": 0.2 + 0.6 * sin(t * 1.3), "y": -0.55 + 0.25 * sin(t * 2.6)}
			inp.off = {"x": -0.3 + 0.4 * sin(t * 0.9 + 1.0), "y": -0.5 + 0.2 * cos(t * 2.1)}
		"stitch":
			# Bent over the table, both hands close together, the needle hand at work.
			inp.look.pitch = -0.6
			inp.main = {"x": 0.05 + 0.12 * sin(t * 5.0), "y": -0.75 + 0.1 * sin(t * 3.0)}
			inp.off = {"x": -0.12, "y": -0.8}
	return inp

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

## The stations' furniture, just behind each station's ring (toward the wall), facing the
## middle: the smith's hearth and anvil, the market stall, the mission board, the physician's
## table. Each stands solid: nobody walks through the smith's hearth.
const STATION_PROPS := {"smith": "smithy", "market": "market_stall", "board": "notice_board", "physician": "physician"}

func _dress_stations() -> void:
	for id in STATION_PROPS:
		var sp: Vector3 = Yard.STATIONS[id].p
		var out := Vector3(sp.x, 0, sp.z).normalized()
		var p := sp + out * (float(Yard.STATIONS[id].r) + 0.9)
		var n := VoxelArt.place(m, STATION_PROPS[id], p, VoxelArt.facing_centre(p))
		VoxelArt.solid(n)
		if n and id == "smith":
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.5, 0.2)
			l.light_energy = 2.0
			l.omni_range = 3.5
			n.add_child(l)
			l.position = Vector3(-0.8, 1.1, 0.0)

func _sign(p: Vector3, text: String) -> void:
	if VoxelArt.place(m, "sign_post", Vector3(p.x, 0, p.z), VoxelArt.facing_centre(p)) != null:
		p.y = maxf(p.y, 2.45)
		_label(p, text)
		return
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, p.y - 0.2, 0.08)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.27, 0.15)
	bm.material = wood
	post.mesh = bm
	m.add_child(post)
	post.global_position = Vector3(p.x, (p.y - 0.2) * 0.5, p.z)
	_label(p, text)

func _label(p: Vector3, text: String) -> void:
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
	# The voxel target faces -z, as look_at turns it: toward the middle.
	if VoxelArt.place(root, "target", Vector3.ZERO) != null:
		return
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
	for d in dummies + keepers:
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
		hint = ("%s · %s" % [Yard.STATIONS[at].label, Yard.STATIONS[at].hint]) if at != "" else "The Ludus yard · E to talk to the smith, the trader or the physician · the gate leads to the arena"
		# E talks to a stall's keeper; the gate is walked into (G there as well).
		var walked_in: bool = at == "gate" and last_at != "gate"
		last_at = at
		if at != "" and (walked_in or local_inp.get("talk", false) or (local_inp.get("grab", false) and not Yard.STATIONS[at].has("npc"))):
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
