class_name YardPlay
extends RefCounted
## The Ludus yard as a place to walk around in (game.js yard mode). The arena becomes the yard:
## a sign and a glowing ring at each station (G there opens it), two training dummies that
## never fall, three throwing boards that score a thrown weapon by how close to the middle it
## struck, and by the gate a board with the next fight on it. Nobody bleeds to death here.

## The layer the stalls' keepers stand on: bodies meet them (their masks take BODY), blades do not.
const KEEPER_LAYER := 32
var m: Node
var dummies: Array = []
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
		var e = m.spawn_fighter({"kind": "npc", "name": Loc.t("Training dummy"), "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM,
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
		n.works = String(s.npc.get("work", "")) != ""   # (he moves at it: while he may be seen, he is at it, Match._stands_idle)
		# A keeper is at his work, not there to be fenced with: a visitor's blades pass through
		# him, his body does not (swords held out at the physician lay on his working arms, cut
		# him and shook in the man's hands, user video 1135).
		for kp in n.f.parts:
			kp.collision_layer = KEEPER_LAYER
			kp.collision_mask &= ~VoxelPart.LAYER_WEAPON
		keepers.append(n.f)
	set_boards(board_texts(m.humans().size()))
	scenery()

## What stands in the yard for the eye (on the host and on every guest alike): the stations'
## signs, rings and furniture, the throwing boards and the boards of the fights on offer.
func scenery() -> void:
	if m.headless:
		return
	scenery_on = true
	# No signs over the stations: each is what it looks like (the smithy, the stall, the
	# physician's table), and the way to the arena is a gateway to walk into.
	_gate()
	for p in Yard.TARGETS:
		_board(p)
	_dress_stations()
	set_boards(board_texts_now if not board_texts_now.is_empty() else [next_text])

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

## The next fight through the gate (the campaign's next bout; in a room, the party's): the first
## of the boards' (board_texts), the one the gate itself leads to.
static func next_fight(players: int) -> String:
	return String(board_texts(players)[0])

## The boards by the gate, one a fight on offer there (GateChoice: the ladder's bout, the crowd's
## fight, another of the stretch; on a boss's day one), as each reads. The demo's end: one.
static func board_texts(players: int) -> Array:
	var coop := Net.active()
	var st := int(Save.get_value("coop_stage" if coop else "stage", 1))
	if Edition.demo_over(st):
		return ["B|FINIS\nF|" + Loc.t("The demo ends here")]
	var out := []
	for o in GateChoice.now(coop):
		out.append(fight_text(st, players, int(o.bout), String(o.kind) == "crowd"))
	return out

## A fight as a board reads it: a line a row, each tagged with what it is: B the bout (in
## numerals), K the crowd's fight, F a foe (by name, the same ones counted: "Veles ×2"; three at
## most, two on the crowd's, then "+N"), P the prize. (An untagged line, from an older host, is
## read as a foe.)
static func fight_text(st: int, players: int, bout := 0, crowd := false) -> String:
	var nx: Dictionary = Data.stage(st, clampi(players, 1, Net.CAMPAIGN_PLAYERS), bout, crowd)   # (four at most fight it)
	var lines := [Loc.t("B|PVGNA %s") % roman(st)]
	if crowd:
		lines.append(Loc.t("K|PRO POPVLO"))
	var foes: Array = ((nx.get("rounds", [[]]) as Array)[0] if not (nx.get("rounds", []) as Array).is_empty() else []).duplicate()
	# The second wave through the other gate is on the stele too (user: it said two hyenas, and
	# three came out).
	foes.append_array(nx.get("late", []))
	var names := []
	var count := {}
	for f in foes:
		var n := foe_label(f)
		if not count.has(n):
			names.append(n)
		count[n] = int(count.get(n, 0)) + 1
	var most := 2 if crowd else 3   # (six lines a board)
	for i in mini(most, names.size()):
		var n: String = names[i]
		lines.append("F|%s%s" % [n, (" ×%d" % count[n]) if int(count[n]) > 1 else ""])
	if names.size() > most:
		var rest := 0
		for i in range(most, names.size()):
			rest += int(count[names[i]])
		lines.append("F|" + Loc.t("and %d more") % rest)
	if names.is_empty():
		lines.append("F|%s" % String(nx.get("title", Loc.t("Bout %d") % st)))
	var pay := Body.bout_pay(st, crowd)
	if pay > 0:
		lines.append("P|PRAEMIVM · %d DENARII" % pay)
	return "\n".join(lines)

## A foe as the stele names him: his title, else what he is.
static func foe_label(f: Dictionary) -> String:
	var nm := String(f.get("title", f.get("name", "")))
	if nm != "":
		return Loc.t(nm)
	if f.has("beast"):
		return Loc.t(String(Data.beasts.get(f.beast, {}).get("name", f.beast)))
	return Loc.t(String(Data.enemy_type(String(f.get("e", ""))).get("label", String(f.get("e", "a gladiator")).capitalize())))

## Roman numerals, as cut in stone (the bouts run past fifty).
static func roman(n: int) -> String:
	var out := ""
	for pair in [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while n >= int(pair[0]):
			out += String(pair[1])
			n -= int(pair[0])
	return out

## The text on the board by the gate (an older host's word: one board).
func set_next(text: String) -> void:
	set_boards([text])

## The boards' texts (the host's own, or what the host sent: three boards, six lines each at most):
## as many boards stand by the gate as there are fights on offer, each painted with its own.
func set_boards(texts: Array) -> void:
	var clean := []
	for t in texts.slice(0, BOARD_AT.size()):
		clean.append("\n".join(Array(str(t).split("\n")).slice(0, 6).map(func(l): return String(l).left(48))))
	if clean.is_empty():
		clean = [""]
	board_texts_now = clean
	next_text = String(clean[0])
	if not scenery_on:
		return
	while boards.size() > clean.size():
		var gone: Dictionary = boards.pop_back()
		if is_instance_valid(gone.root):
			gone.root.queue_free()
	while boards.size() < clean.size():
		boards.append({"root": _stele(boards.size()), "lines": []})
	next_root = boards[0].root
	for i in clean.size():
		_paint_board(boards[i], String(clean[i]))

func _paint_board(b: Dictionary, text: String) -> void:
	var root: Node3D = b.root
	for c in b.lines:
		if is_instance_valid(c):
			c.queue_free()
	b.lines = []
	var bout := ""
	var kind := ""
	var foes := []
	var prize := ""
	for l in text.split("\n"):
		var tag: String = String(l).left(2)
		var body: String = String(l).substr(2) if tag.ends_with("|") else String(l)
		match tag:
			"B|": bout = body
			"K|": kind = body
			"P|": prize = body
			_:
				if body != "":
					foes.append(body)
	# Cut and painted in the Pompeian way: the bout big in red (the crowd's fight said under it),
	# a rule, the foes in black, the prize small at the foot.
	var y := 2.2
	if bout != "":
		b.lines.append(_paint(root, bout, 64, y, PAINT_RED))
		y -= 0.3
	if kind != "":
		b.lines.append(_paint(root, kind, 30, y + 0.04, PAINT_RED))
		y -= 0.16
	b.lines.append(_rule(root, y + 0.06))
	# The foes in the middle of the face between the rule and the prize.
	var step := 0.27 if foes.size() <= 2 else 0.21
	var fy := (y + 0.06 + 1.0) * 0.5 - 0.06 + step * (foes.size() - 1) * 0.5
	for f in foes:
		b.lines.append(_paint(root, f, 52 if foes.size() <= 2 else 38, fy, PAINT_BLACK))
		fy -= step
	b.lines.append(_rule(root, 1.0))
	if prize != "":
		b.lines.append(_paint(root, prize, 26, 0.86, PAINT_RED))

const PAINT_RED := Color(0.55, 0.09, 0.06)
const PAINT_BLACK := Color(0.13, 0.1, 0.09)
const STELE_PX := 300.0   # the face between the mouldings, 1.2 m, in the letters' pixels
## Where the boards stand, off the gate: the first (the gate's own fight) where the one board always
## stood, left of the gate as one faces it from the yard; the second right of it; the third further
## round on the left.
const BOARD_AT := [Vector3(4.2, 0, -0.9), Vector3(-4.2, 0, -0.9), Vector3(7.2, 0, -2.9)]
const BOARD_STAND := 1.3   # how far in front of its face one stands to choose a board (m)
const BOARD_R := 1.1       # and how near that spot
var board_texts_now: Array = []   # what each board reads (the host's own, or what he sent)
var boards: Array = []            # [{"root", "lines"}], built (on a screen) as many as there are texts
var scenery_on := false
var next_root: Node3D = null      # (the first board's: what the gate itself leads to)
# The party's picks of the gate's fights (GateScreen): each one's the card he lit on his screen, or
# the board he last walked up to, whichever came last (the host's; his own under 1).
var picks := {}                   # peer id -> board
var _stood := {}                  # peer id -> the board he stood by the tick before (-1: none)
var _picks_sent := []             # what the guests were told of them last
var _picks_t := 0.0
var _picks_age := 0.0             # (said again now and then: a guest who came in later hears it)
var gate_info := {}               # (a guest's) the fights on offer, as the host sent them (clean_gate)
var picks_seen := {}              # (a guest's) the party's picks, as the host sent them (clean_picks)

## Where one stands to choose board `i`: in front of its face, toward the middle of the yard.
static func board_spot(i: int) -> Vector3:
	var at: Vector3 = Yard.STATIONS.gate.p + BOARD_AT[i]
	return at - Vector3(at.x, 0, at.z).normalized() * BOARD_STAND

## The board whose spot `p` is on (-1: none).
func board_at(p: Vector3) -> int:
	for i in board_texts_now.size():
		var sp := board_spot(i)
		if Vector2(p.x - sp.x, p.z - sp.z).length() < BOARD_R:
			return i
	return -1

## What is under a man's feet: a board by the gate ("fight0", "fight1"...), else a station.
func station_here(p: Vector3) -> String:
	var b := board_at(p)
	return ("fight%d" % b) if b >= 0 else Yard.station_at(p)

## The board each of the party is for now (-1: none), the host first (GateChoice.majority): the
## one he picked on his gate screen or last walked up to, whichever came last.
func stands() -> Array:
	var out := []
	for e in m.humans():
		var peer := _peer_of(e)
		if picks.has(peer):
			out.append(int(picks[peer]))
		else:
			out.append(board_at(e.f.torso.global_position) if is_instance_valid(e.f) else -1)
	return out

func _peer_of(e: Dictionary) -> int:
	return 1 if e.kind == "local" else int(e.get("peer", -1))

## A board walked up to is his pick (until he picks another, here or on his screen).
func _follow_stands() -> void:
	for e in m.humans():
		var peer := _peer_of(e)
		var b := board_at(e.f.torso.global_position) if is_instance_valid(e.f) else -1
		if b != int(_stood.get(peer, -1)):
			_stood[peer] = b
			if b >= 0:
				picks[peer] = b

## A pick at the gate's cards (the host's own, or a guest's over the wire: a board's number,
## anything else none).
func take_pick(peer: int, v) -> void:
	if (v is int or v is float) and is_finite(float(v)) and int(v) >= 0 and int(v) < board_texts_now.size():
		picks[peer] = int(v)
	else:
		picks.erase(peer)

## The names of those for each board ([[names] a board]), the host first.
func pick_names() -> Array:
	var out := []
	for i in board_texts_now.size():
		out.append([])
	var st := stands()
	var hs: Array = m.humans()
	for j in hs.size():
		var b := int(st[j])
		if b >= 0 and b < out.size() and is_instance_valid(hs[j].f):
			(out[b] as Array).append(String(hs[j].f.display_name))
	return out

## The party's picks told to the guests when they change (their screens and boards show them).
func _send_picks(dt: float) -> void:
	_picks_t -= dt
	if _picks_t > 0.0 or not Net.active():
		return
	_picks_t = 0.5
	_picks_age += 0.5
	var now := [pick_names(), GateChoice.majority(stands(), board_texts_now.size())]
	if now != _picks_sent or _picks_age >= 4.0:
		_picks_sent = now
		_picks_age = 0.0
		Net.send_all("gate_picks", {"v": now[0], "l": now[1]})

## The fights on offer as a guest is told them (the host's yard_next): the stage, the time round
## and [bout, kind] a board, made safe; {} when there is nothing to choose (the demo's end).
static func clean_gate(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("b") is Array):
		return {}
	var n := Ladder.BOUTS.size()
	var b := []
	for x in (v.b as Array).slice(0, BOARD_AT.size()):
		if x is Array and (x as Array).size() == 2 and (x[0] is int or x[0] is float) and is_finite(float(x[0])) and ["ladder", "crowd", "other", "boss"].has(str(x[1])):
			b.append({"bout": clampi(int(x[0]), 1, n), "kind": str(x[1])})
	if b.is_empty():
		return {}
	var s = v.get("s", 1)
	var l = v.get("l", 1)
	return {"s": clampi(int(s), 1, n) if (s is int or s is float) and is_finite(float(s)) else 1, "l": clampi(int(l), 1, 99) if (l is int or l is float) and is_finite(float(l)) else 1, "b": b}

## The party's picks as a guest is told them, made safe: names a board (names as names, four at
## most), and the board most of them are for.
static func clean_picks(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("v") is Array):
		return {}
	var by := []
	for x in (v.v as Array).slice(0, BOARD_AT.size()):
		by.append((x as Array).slice(0, Net.CAMPAIGN_PLAYERS).map(func(n): return Net.clean_name(n)) if x is Array else [])
	var l = v.get("l", -1)
	return {"v": by, "l": clampi(int(l), -1, BOARD_AT.size() - 1) if (l is int or l is float) and is_finite(float(l)) else -1}

## What a board says to the one standing by it: its foes (the crowd's fight said so), in a room how
## many of the party stand there, and what E does.
func board_prompt(i: int) -> String:
	var text: String = String(board_texts_now[i]) if i >= 0 and i < board_texts_now.size() else ""
	var foes := []
	var crowd := false
	for l in text.split("\n"):
		if l.begins_with("F|"):
			foes.append(l.substr(2))
		elif l.begins_with("K|"):
			crowd = true
	var what := ", ".join(foes)
	if crowd:
		what += " · " + Loc.t("for the crowd: one more foe, double the prize")
	if Net.active():
		var n := stands().count(i)
		if not Net.is_host() and not picks_seen.is_empty():
			n = ((picks_seen.v as Array)[i] as Array).size() if i < (picks_seen.v as Array).size() else 0
		what += " · " + Loc.t("%d of %d for this fight") % [n, m.humans().size()]
		if not Net.is_host():
			return Loc.t("%s · you stand for this fight · E: the gate's fights") % what
	return Loc.t("%s · E: choose your fight") % what

## A line of letters painted on a board's face, made smaller until it fits.
func _paint(root: Node3D, text: String, size: int, y: float, c: Color) -> Label3D:
	var l := Label3D.new()
	l.font = UIStyle.serif(2)
	l.pixel_size = 0.004
	l.outline_size = 0
	l.modulate = c
	l.shaded = true
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.position = Vector3(0, y, 0.122)
	l.text = text
	while size > 14 and l.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > STELE_PX:
		size -= 2
	l.font_size = size
	root.add_child(l)
	return l

## A painted rule between the bout and the foes.
func _rule(root: Node3D, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.025, 0.004)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = PAINT_RED
	sm.roughness = 0.9
	bm.material = sm
	mi.mesh = bm
	mi.position = Vector3(0, y, 0.121)
	root.add_child(mi)
	return mi

## A stele of whitewashed stone on a plinth beside the gate, a pediment over it: a fight on offer,
## painted on it in red and black as the games were announced on the walls of Pompeii (board `i`
## of BOARD_AT). A torch on an iron bracket lights it at night.
func _stele(i: int) -> Node3D:
	var gp: Vector3 = Yard.STATIONS.gate.p
	var at: Vector3 = gp + BOARD_AT[i]
	var root := Node3D.new()
	m.add_child(root)
	root.global_position = at
	root.rotation.y = VoxelArt.facing_centre(at)
	var mat := func(c: Color, rough := 0.95, metal := 0.0) -> StandardMaterial3D:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = c
		sm.roughness = rough
		sm.metallic = metal
		return sm
	var stone: StandardMaterial3D = mat.call(Color(0.62, 0.57, 0.5))
	var lime: StandardMaterial3D = mat.call(Color(0.86, 0.82, 0.72))
	var iron: StandardMaterial3D = mat.call(Color(0.16, 0.15, 0.14), 0.6, 0.7)
	var piece := func(mesh: Mesh, pos: Vector3, sm: Material, rot := Vector3.ZERO) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = sm
		mi.position = pos
		mi.rotation = rot
		root.add_child(mi)
	var bx := func(size: Vector3) -> BoxMesh:
		var bm := BoxMesh.new()
		bm.size = size
		return bm
	# Plinth in two steps, the shaft, its mouldings, and the pediment on top.
	piece.call(bx.call(Vector3(1.75, 0.18, 0.6)), Vector3(0, 0.09, 0), stone)
	piece.call(bx.call(Vector3(1.6, 0.16, 0.48)), Vector3(0, 0.26, 0), stone)
	piece.call(bx.call(Vector3(1.4, 2.1, 0.24)), Vector3(0, 1.39, 0), lime)
	piece.call(bx.call(Vector3(1.52, 0.1, 0.3)), Vector3(0, 0.39, 0), stone)
	piece.call(bx.call(Vector3(1.56, 0.12, 0.32)), Vector3(0, 2.5, 0), stone)
	var pm := PrismMesh.new()
	pm.size = Vector3(1.6, 0.42, 0.3)
	piece.call(pm, Vector3(0, 2.77, 0), stone)
	# A laurel disc in the pediment.
	var cy := CylinderMesh.new()
	cy.top_radius = 0.1
	cy.bottom_radius = 0.1
	cy.height = 0.04
	piece.call(cy, Vector3(0, 2.72, 0.15), mat.call(Color(0.72, 0.55, 0.22), 0.45, 0.8), Vector3(PI / 2, 0, 0))
	# A torch on an iron bracket at the right-hand edge, burning.
	piece.call(bx.call(Vector3(0.04, 0.04, 0.32)), Vector3(0.78, 2.05, 0.1), iron)
	piece.call(bx.call(Vector3(0.07, 0.36, 0.07)), Vector3(0.78, 2.15, 0.26), mat.call(Color(0.3, 0.2, 0.1)))
	var flame := OmniLight3D.new()
	flame.light_color = Color(1.0, 0.62, 0.3)
	flame.light_energy = 1.1
	flame.omni_range = 3.2
	flame.position = Vector3(0.78, 2.45, 0.35)
	root.add_child(flame)
	var fire := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.06
	sp.height = 0.16
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.7, 0.3)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.55, 0.2)
	fm.emission_energy_multiplier = 2.0
	sp.material = fm
	fire.mesh = sp
	fire.position = Vector3(0.78, 2.38, 0.26)
	root.add_child(fire)
	return root

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
const STATION_PROPS := {"smith": "smithy", "market": "market_stall", "board": "notice_board", "physician": "physician", "trainer": "notice_board"}

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
		_follow_stands()
		_send_picks(_dt)
		next_t -= _dt
		if next_t <= 0.0:
			next_t = 4.0
			m._send_yard_next()
	if m.me and is_instance_valid(m.me.f):
		at = station_here(m.me.f.torso.global_position)
		if at.begins_with("fight"):
			hint = board_prompt(int(at.substr(5)))
		else:
			hint = ("%s · %s" % [Yard.STATIONS[at].label, Yard.STATIONS[at].hint]) if at != "" else "The Ludus yard · E to talk to the smith, the trader, the physician or the trainer · the gate leads to the arena"
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
				m.feed.emit(Loc.t("BULLSEYE! +%d") % pts if pts == 10 else ("+%d" % pts if pts > 0 else Loc.t("Off the board")))
				m.sfx("thud", p, 1.0)
				break
