class_name YardPlay
extends RefCounted
## The Ludus yard as a place to walk around in (game.js yard mode). The arena becomes the yard:
## a sign and a glowing ring at each station (G there opens it), two training dummies that
## never fall, three throwing boards that score a thrown weapon by how close to the middle it
## struck, and by the gate a board with the next fight on it. Nobody bleeds to death here.

var m: Node
var dummies: Array = []
var next_board: Label3D = null   # the foe's name; over it the band, under it the bout
var next_head: Label3D = null
var next_sub: Label3D = null
var next_text := ""
var next_t := 0.0   # (the host says it again now and then: a guest whose yard was not up yet hears it)
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
	set_next(next_fight(m.humans().size()))
	scenery()

## What stands in the yard for the eye (on the host and on every guest alike): the stations'
## signs, rings and furniture, the throwing boards and the board of the next fight.
func scenery() -> void:
	if m.headless:
		return
	# No signs over the stations: each is what it looks like (the smithy, the stall, the
	# physician's table), and the way to the arena is a gateway to walk into.
	_gate()
	for p in Yard.TARGETS:
		_board(p)
	_dress_stations()
	_next_board()

## The gateway to the arena where the gate is: a stone arch to walk in under (E there takes him
## to the next fight), solid at its piers and over the arch, open through the middle, braziers
## burning either side.
func _gate() -> void:
	var gp: Vector3 = Yard.STATIONS.gate.p
	var yaw := VoxelArt.facing_centre(gp)
	var n := VoxelArt.place(m, "ludus_gate", gp, yaw)
	if n == null:
		_ring(gp, float(Yard.STATIONS.gate.r), Color(1.0, 0.8, 0.35, 0.8))
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	n.add_child(body)
	for b in [[Vector3(-1.5, 2.2, 0.0), Vector3(0.8, 4.4, 1.0)], [Vector3(1.5, 2.2, 0.0), Vector3(0.8, 4.4, 1.0)], [Vector3(0, 4.0, 0.0), Vector3(3.8, 0.8, 1.0)], [Vector3(0, 1.5, -0.45), Vector3(2.2, 3.0, 0.1)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		body.add_child(cs)
	for sx in [-1.0, 1.0]:
		var at: Vector3 = gp + Basis(Vector3.UP, yaw) * Vector3(sx * 2.6, 0, 0.9)
		var br := VoxelArt.place(m, "brazier", at, yaw)
		VoxelArt.solid(br, 0.15)
		if br:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.3)
			l.light_energy = 1.6
			l.omni_range = 4.0
			br.add_child(l)
			l.position = Vector3(0, 1.8, 0)

## The next fight through the gate (the campaign's next bout; in a room, the party's), as the
## board beside the gate reads it.
static func next_fight(players: int) -> String:
	var coop := Net.active()
	var st := int(Save.get_value("coop_stage" if coop else "stage", 1))
	if Edition.demo_over(st):
		return "THE DEMO ENDS HERE"
	var nx: Dictionary = Data.stage(st, maxi(1, players))
	var title := String(nx.get("title", "Bout %d" % st))
	var foe := String(nx.get("foe_name", ""))
	# (A named foe is the bout's title too, "The Cyclops": once is enough.)
	if foe == "" or foe.to_lower() == title.to_lower():
		return "NEXT FIGHT\n%s\nBout %d" % [title, st]
	return "NEXT FIGHT\n%s\n%s" % [foe, title]

## The text on the board (the host's own, or what the host sent: kept short and to three lines:
## the band, the foe, the bout).
func set_next(text: String) -> void:
	var lines: Array = Array(text.split("\n")).slice(0, 3).map(func(l): return String(l).left(48))
	next_text = "\n".join(lines)
	if next_board and is_instance_valid(next_board):
		next_head.text = lines[0] if lines.size() > 0 else ""
		next_board.text = lines[1] if lines.size() > 1 else ""
		next_sub.text = lines[2] if lines.size() > 2 else ""

## A board on two posts beside the gate: a gilt frame, a red band over it that says what it is,
## the foe's name large and the bout under it, lit by a lamp of its own.
func _next_board() -> void:
	var gp: Vector3 = Yard.STATIONS.gate.p
	var at := gp + Vector3(4.2, 0, -0.9)
	var root := Node3D.new()
	m.add_child(root)
	root.global_position = at
	root.rotation.y = VoxelArt.facing_centre(at)
	var mat := func(c: Color, metal := 0.0) -> StandardMaterial3D:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = c
		sm.metallic = metal
		sm.roughness = 0.45 if metal > 0.0 else 0.85
		return sm
	var wood: StandardMaterial3D = mat.call(Color(0.33, 0.21, 0.11))
	var gilt: StandardMaterial3D = mat.call(Color(0.78, 0.58, 0.24), 0.8)
	var box := func(size: Vector3, pos: Vector3, sm: Material) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = sm
		mi.mesh = bm
		mi.position = pos
		root.add_child(mi)
	for x in [-0.95, 0.95]:
		box.call(Vector3(0.12, 2.75, 0.12), Vector3(x, 1.375, -0.02), wood)
		box.call(Vector3(0.18, 0.12, 0.18), Vector3(x, 2.8, -0.02), gilt)
	# The panel, its gilt frame a hair in front of it (no two faces in one plane).
	box.call(Vector3(1.9, 1.2, 0.06), Vector3(0, 1.8, 0.0), mat.call(Color(0.1, 0.05, 0.04)))
	for y in [1.2, 2.4]:
		box.call(Vector3(2.0, 0.07, 0.09), Vector3(0, y, 0.01), gilt)
	for x in [-0.98, 0.98]:
		box.call(Vector3(0.07, 1.27, 0.09), Vector3(x, 1.8, 0.01), gilt)
	box.call(Vector3(1.86, 0.26, 0.02), Vector3(0, 2.22, 0.04), mat.call(Color(0.5, 0.07, 0.05)))
	var label := func(size: int, pos: Vector3, c: Color) -> Label3D:
		var l := Label3D.new()
		l.font = UIStyle.serif(2)
		l.font_size = size
		l.pixel_size = 0.004
		l.outline_size = 6
		l.modulate = c
		l.outline_modulate = Color(0.08, 0.03, 0.02)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.width = 440.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.position = pos
		root.add_child(l)
		return l
	next_head = label.call(34, Vector3(0, 2.22, 0.06), Color(1.0, 0.86, 0.6))
	next_board = label.call(70, Vector3(0, 1.84, 0.05), UIStyle.GOLD)
	next_sub = label.call(34, Vector3(0, 1.43, 0.05), Color(0.86, 0.78, 0.66))
	set_next(next_text)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.7, 0.4)
	glow.light_energy = 0.9
	glow.omni_range = 2.8
	glow.position = Vector3(0, 2.3, 0.7)
	root.add_child(glow)

## A stall keeper at his work, facing his workplace (`work_yaw`), or turned to a man who comes up.
func _keeper_input(e, work: String, home: Vector3, work_yaw: float, ph: float) -> Dictionary:
	var f: Fighter = e.f
	var t := Time.get_ticks_msec() / 1000.0 + ph
	var yaw := work_yaw
	for h in m.humans():
		if is_instance_valid(h.f) and h.f.alive and Vector2(h.f.torso.global_position.x - home.x, h.f.torso.global_position.z - home.z).length() < 3.2:
			var to: Vector3 = h.f.torso.global_position - f.torso.global_position
			yaw = atan2(to.x, to.z)
			# Tools down at his side while he talks: nothing held across his belly for a visitor to walk into.
			return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.6, "y": -0.35}, "off": {"x": -0.5, "y": -0.3}}
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
	if m.role != "guest":   # (a guest only reads the stalls; the host keeps the yard's people)
		for d in dummies + keepers:
			if is_instance_valid(d):
				d.blood = 100.0
		for e in m.humans():
			if is_instance_valid(e.f):
				e.f.blood = maxf(e.f.blood, 50.0)
		_boards()
		next_t -= _dt
		if next_t <= 0.0:
			next_t = 4.0
			m._send_yard_next()
	if m.me and is_instance_valid(m.me.f):
		at = Yard.station_at(m.me.f.torso.global_position)
		hint = ("%s · %s" % [Yard.STATIONS[at].label, Yard.STATIONS[at].hint]) if at != "" else "The Ludus yard · E to talk to the smith, the trader or the physician · the gate leads to the arena"
		# E talks to a stall's keeper; the gate is walked into (G there as well).
		last_at = at
		if at != "" and local_inp.get("talk", false):
			m.station.emit(at)

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
