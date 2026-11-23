class_name YardPlay
extends RefCounted
## The Ludus yard as a place to walk around in (game.js yard mode). The arena becomes the yard:
## a sign and a glowing ring at each station (G there opens it), two training dummies that
## never fall, three throwing boards that score a thrown weapon by how close to the middle it
## struck, and the gate to the arena, where the fights on offer are chosen (GateScreen). Nobody
## bleeds to death here.

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
	if m.stage_start():
		_setup_staged()   # (not waited for: the first of them is begun, the rest follow over the frames)
		return
	for p in Yard.DUMMIES:
		_dummy_in(m.spawn_fighter(_dummy_spec(p)))
	for id in Yard.stations():
		var k := _keeper_spec(id)
		if not k.is_empty():
			_keeper_in(m.spawn_fighter(k.spec), k)
	set_boards(board_texts(m.humans().size()))
	scenery()

## With a screen the dummies and the keepers are built apart, one after another, over the frames that
## follow the yard's start (Match.stage_start), not all six before its first frame: a man is a fifth
## of a second of work (twice that the first time a look is seen), and the six were a stop of a second
## and more before anyone could move (the yard's start in the friends' game). The yard is up at once,
## the dummies and the stall keepers come in one after another within the first seconds, and a
## guest sees each as the host brings him in (Match._register).
func _setup_staged() -> void:
	set_boards(board_texts(m.humans().size()))
	scenery()
	for p in Yard.DUMMIES:
		var e = await m.spawn_fighter_staged(_dummy_spec(p))
		if e == null:
			return
		_dummy_in(e)
	for id in Yard.stations():
		var k := _keeper_spec(id)
		if k.is_empty():
			continue
		var n = await m.spawn_fighter_staged(k.spec)
		if n == null:
			return
		_keeper_in(n, k)

func _dummy_spec(p: Vector3) -> Dictionary:
	return {"kind": "npc", "name": Loc.t("Training dummy"), "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM,
		"pos": p + Vector3(0, 0.02, 0), "yaw": 0.0, "mods": {"toughness": 3.0}, "color": 0xb08a5a}

func _dummy_in(e) -> void:
	e.drive = func(_e): return {}
	e.harmless = true
	dummies.append(e.f)

## The smith, the trader and the physician, each dressed for his trade, beside his stall's
## sign (not inside its post) between it and his workplace, at work: the smith stands by
## his hearth, the trader sorts his wares, the physician bends over his table; whoever comes
## up to the stall, he turns to. `spec` for the man, `p`, `work_yaw` where and how he works (empty
## for a station without a keeper).
func _keeper_spec(id: String) -> Dictionary:
	var s: Dictionary = Yard.STATIONS[id]
	if not s.has("npc"):
		return {}
	var out := Vector3(s.p.x, 0, s.p.z).normalized()
	var side := Vector3(-out.z, 0, out.x)
	var p: Vector3 = s.p + out * 1.5 + side * 0.9
	var work_yaw := atan2(out.x, out.z) + 0.5
	var face_yaw := atan2(-p.x, -p.z)
	return {"p": p, "work_yaw": work_yaw, "work": String(s.npc.get("work", "")), "spec": {"kind": "npc", "name": s.npc.name, "loadout": {"main": s.npc.main, "off": "", "armor": s.npc.get("armor", [])}, "team": Match.ENEMY_TEAM,
		"pos": p + Vector3(0, 0.02, 0), "yaw": face_yaw, "mods": {"toughness": 5.0}, "color": s.npc.color}}

func _keeper_in(n, k: Dictionary) -> void:
	n.drive = _keeper_input.bind(String(k.work), k.p, k.work_yaw, randf() * TAU)
	n.harmless = true
	n.works = String(k.work) != ""   # (he moves at it: while he may be seen, he is at it, Match._stands_idle)
	# A keeper is at his work, not there to be fenced with: a visitor's blades pass through
	# him, his body does not (swords held out at the physician lay on his working arms, cut
	# him and shook in the man's hands, user video 1135).
	for kp in n.f.parts:
		kp.collision_layer = KEEPER_LAYER
		kp.collision_mask &= ~VoxelPart.LAYER_WEAPON
	keepers.append(n.f)

## What stands in the yard for the eye (on the host and on every guest alike): the stations'
## signs, rings and furniture, and the throwing boards.
func scenery() -> void:
	if m.headless:
		return
	# No signs over the stations: each is what it looks like (the smithy, the stall, the
	# physician's table), and the way to the arena is a gateway to walk into.
	_gate()
	for p in Yard.TARGETS:
		_board(p)
	_dress_stations()

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
## of the fights on offer (board_texts), the one the gate itself leads to.
static func next_fight(players: int) -> String:
	return String(board_texts(players)[0])

## The fights on offer at the gate (GateChoice: the ladder's bout, the crowd's fight, another of
## the stretch; on a boss's day one), each as fight_text words it. The demo's end: one.
static func board_texts(players: int) -> Array:
	var coop := Net.active()
	var st := int(Save.get_value("coop_stage" if coop else "stage", 1))
	if Edition.demo_over(st):
		return ["B|FINIS\nF|" + Loc.t("The demo ends here")]
	var out := []
	for o in GateChoice.now(coop):
		out.append(fight_text(st, players, int(o.bout), String(o.kind) == "crowd"))
	return out

## A fight in a few lines, each tagged with what it is: B the bout (its number, written as every
## number in the game is: user), K the crowd's fight, F a foe (by name, the same ones counted:
## "Veles ×2"; three at most, two on the crowd's, then "+N"), P the prize. (An untagged line, from
## an older host, is read as a foe.)
static func fight_text(st: int, players: int, bout := 0, crowd := false) -> String:
	var nx: Dictionary = Data.stage(st, clampi(players, 1, Net.CAMPAIGN_PLAYERS), bout, crowd)   # (four at most fight it)
	var lines := [Loc.t("B|PVGNA %s") % str(st)]
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

## The next fight's text (an older host's word: one fight).
func set_next(text: String) -> void:
	set_boards([text])

## The fights on offer (the host's own, or what the host sent: three at most, six lines each at
## most); the first, the one the gate itself leads to, is next_text.
func set_boards(texts: Array) -> void:
	var clean := []
	for t in texts.slice(0, MOST_FIGHTS):
		clean.append("\n".join(Array(str(t).split("\n")).slice(0, 6).map(func(l): return String(l).left(48))))
	if clean.is_empty():
		clean = [""]
	board_texts_now = clean
	next_text = String(clean[0])

const MOST_FIGHTS := 3            # fights on offer at the gate at most
var board_texts_now: Array = []   # the fights on offer as they read (the host's own, or what he sent)
# The party's picks of the gate's fights (GateScreen): each one's the card he picked last on his
# screen (the host's; his own under 1).
var picks := {}                   # peer id -> fight
var _picks_sent := []             # what the guests were told of them last
var _picks_t := 0.0
var _picks_age := 0.0             # (said again now and then: a guest who came in later hears it)
var gate_info := {}               # (a guest's) the fights on offer, as the host sent them (clean_gate)
var picks_seen := {}              # (a guest's) the party's picks, as the host sent them (clean_picks)

## What is under a man's feet: a station ("": none).
func station_here(p: Vector3) -> String:
	return Yard.station_at(p)

## The fight each of the party is for now (-1: none), the host first (GateChoice.majority): the
## card he picked last on his gate screen.
func stands() -> Array:
	var out := []
	for e in m.humans():
		out.append(int(picks.get(_peer_of(e), -1)))
	return out

func _peer_of(e: Dictionary) -> int:
	return 1 if e.kind == "local" else int(e.get("peer", -1))

## A pick at the gate's cards (the host's own, or a guest's over the wire: a card's number,
## anything else none).
func take_pick(peer: int, v) -> void:
	if (v is int or v is float) and is_finite(float(v)) and int(v) >= 0 and int(v) < board_texts_now.size():
		picks[peer] = int(v)
	else:
		picks.erase(peer)

## The names of those for each fight ([[names] a fight]), the host first.
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

## The party's picks told to the guests when they change (their cards show them).
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
## and [bout, kind] a fight, made safe; {} when there is nothing to choose (the demo's end).
static func clean_gate(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("b") is Array):
		return {}
	var n := Ladder.BOUTS.size()
	var b := []
	for x in (v.b as Array).slice(0, MOST_FIGHTS):
		if x is Array and (x as Array).size() == 2 and (x[0] is int or x[0] is float) and is_finite(float(x[0])) and ["ladder", "crowd", "other", "boss"].has(str(x[1])):
			b.append({"bout": clampi(int(x[0]), 1, n), "kind": str(x[1])})
	if b.is_empty():
		return {}
	var s = v.get("s", 1)
	var l = v.get("l", 1)
	return {"s": clampi(int(s), 1, n) if (s is int or s is float) and is_finite(float(s)) else 1, "l": clampi(int(l), 1, 99) if (l is int or l is float) and is_finite(float(l)) else 1, "b": b}

## The party's picks as a guest is told them, made safe: names a fight (names as names, four at
## most), and the fight most of them are for.
static func clean_picks(v) -> Dictionary:
	if not (v is Dictionary) or not (v.get("v") is Array):
		return {}
	var by := []
	for x in (v.v as Array).slice(0, MOST_FIGHTS):
		by.append((x as Array).slice(0, Net.CAMPAIGN_PLAYERS).map(func(n): return Net.clean_name(n)) if x is Array else [])
	var l = v.get("l", -1)
	return {"v": by, "l": clampi(int(l), -1, MOST_FIGHTS - 1) if (l is int or l is float) and is_finite(float(l)) else -1}

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

func _ring(p: Vector3, r: float, color: Color) -> MeshInstance3D:
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
	return mi

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

# ---------- The teams of a team fight, chosen in the lobby ----------
# A circle on the sand for each team (TeamSetup), the host's and each guest's walk into the one he plays for; a sign over a circle
# says who is in it; when everybody stands in one the host may begin (E, as a stall is spoken to; Menu._team_go). The host reads
# who stands where, the guests are told what the host reads (the "teams" message) and see the same circles and signs.

var team_setup: TeamSetup = null   # (the host's) the teams being chosen
var team_seen := {}                # (a guest's) what the host said of them, made safe (TeamSetup.clean_state)
var _team_nodes: Array = []
var _team_signs: Array = []
var _team_sent := {}
var _team_t := 0.0
var _team_age := 0.0

func teams_on() -> bool:
	return team_setup != null or not team_seen.is_empty()

## The host: the teams are to be chosen (the guests are told, at once).
func begin_teams(mode: String, opts: Dictionary) -> void:
	if m.role == "guest":
		return
	end_teams(false)
	team_setup = TeamSetup.new(mode, opts)
	_team_scenery()
	_team_t = 0.0
	_team_sent = {}

## Over: the circles taken up, the guests told.
func end_teams(tell := true) -> void:
	var was := teams_on()
	for n in _team_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_team_nodes.clear()
	_team_signs.clear()
	team_setup = null
	team_seen = {}
	_team_sent = {}
	if tell and was and m.role == "host" and Net.active():
		Net.send_all("teams", {})

func _team_scenery() -> void:
	for i in TeamSetup.TEAMS:
		var c: Vector3 = TeamSetup.CENTRES[i]
		var col: Color = TeamSetup.COLORS[i]
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = TeamSetup.RADIUS
		cm.bottom_radius = TeamSetup.RADIUS
		cm.height = 0.02
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(col.r, col.g, col.b, 0.22)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.material = mat
		disc.mesh = cm
		m.add_child(disc)
		disc.global_position = c + Vector3(0, 0.02, 0)
		_team_nodes.append(disc)
		_team_nodes.append(_ring(c, TeamSetup.RADIUS, Color(col.r, col.g, col.b, 0.85)))
		_label(c + Vector3(0, 2.7, 0), TeamSetup.sign_text(i, []))
		var lab: Label3D = signs.pop_back()
		lab.modulate = col.lightened(0.35)
		_team_signs.append(lab)
		_team_nodes.append(lab)

func _team_signs_to(t: Array) -> void:
	for i in mini(_team_signs.size(), t.size()):
		(_team_signs[i] as Label3D).text = TeamSetup.sign_text(i, t[i])

## The host, once a tick: who stands where, the signs, and what the guests are told when it changes (and now and then, for one
## who came in later).
func _teams_tick(dt: float) -> void:
	_team_t -= dt
	if _team_t > 0.0:
		return
	_team_t = 0.1
	var here := {}
	for e in m.humans():
		if is_instance_valid(e.f):
			var who := _peer_of(e)
			var p: Vector3 = e.f.torso.global_position
			team_setup.set_place(who, String(e.f.display_name), p.x, p.z)
			here[who] = true
	for who in team_setup.places.keys():
		if not here.has(who):
			team_setup.forget(int(who))
	var st := team_setup.state()
	_team_signs_to(st.t)
	_team_age += 0.1
	if st != _team_sent or _team_age >= 4.0:
		_team_sent = st
		_team_age = 0.0
		if Net.active():
			Net.send_all("teams", st)

## A guest: what the host said of the teams (made safe); the circles are put on the sand when the first word comes.
func take_teams(v) -> void:
	var st := TeamSetup.clean_state(v)
	if st.is_empty():
		end_teams(false)
		return
	team_seen = st
	if _team_nodes.is_empty():
		_team_scenery()
	_team_signs_to(st.t)

## The line on the screen while the teams are chosen ("" when they are not).
func team_line() -> String:
	if team_setup != null:
		return team_setup.line(true)
	if not team_seen.is_empty():
		return TeamSetup.line_of(team_seen, false)
	return ""

## Once a tick on the host: nobody bleeds out, the stations, the throwing boards, the ring.
func update(_dt: float, local_inp: Dictionary) -> void:
	if team_setup != null and m.role != "guest":
		_teams_tick(_dt)
		if local_inp.get("talk", false) and team_setup.ready():
			m.station.emit("team_go")
	if m.role != "guest":   # (a guest only reads the stalls; the host keeps the yard's people)
		for d in dummies + keepers:
			if is_instance_valid(d):
				d.blood = 100.0
		for e in m.humans():
			if is_instance_valid(e.f):
				e.f.blood = maxf(e.f.blood, 50.0)
		_boards()
		_send_picks(_dt)
		next_t -= _dt
		if next_t <= 0.0:
			next_t = 4.0
			m._send_yard_next()
	if m.me and is_instance_valid(m.me.f):
		at = station_here(m.me.f.torso.global_position)
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
