class_name Match
extends Node3D
## One match (game.js): the arena, the fighters, the rounds. Modes: "campaign" (a stage of
## three rounds from the campaign tables, then back to the yard), "training" (a sparring
## partner that comes back) and "duel". The host runs the physics; guests draw snapshots.

signal feed(text: String)
signal banner(text: String, sub: String)
signal finished(result: Dictionary)

const ENEMY_TEAM := 1
const TICK := 1.0 / 120.0
const SNAP_EVERY := 5           # snapshots at 24 Hz

var mode := "campaign"
var stage := 1
var round := 0
var role := "local"             # local | host | guest
var arena: Arena
var combat: Combat
var cam: CameraRig
var input: PlayerInput
var entities: Array = []        # {id, f, kind, team, bot, peer, boss, spec}
var me = null
var over := false
var between := 0.0
var time := 0.0
var tick := 0
var stage_info: Dictionary = {}
var players_count := 1
var round_pay := 0
var kills := {}
var rng := RandomNumberGenerator.new()
var next_id := 1
var training: Dictionary = {}
var headless := false
var social: Social
var items: Items
var throwables: Throwables
var spectacle: Spectacle
var hazards: Hazards
var decrees: Array = []
var dec: Dictionary = Decrees.combine([])
var lion_t := -1.0
var loose_ids := {}              # net id -> loose weapon (host and guests alike)
var next_wid := 1
var hazard_specs: Array = []
var modes: Modes = null
var fx: Fx
var drip_t := 0.0
var attract := false            # the menu backdrop: bots only, an orbiting camera
var hero: Fighter = null        # the menu's champion, posing in front of the fight
var hero_inp := {}
var hero_cam := {}              # {pos, look}: a fixed shot instead of the orbit
var rules: BoutRules = null     # Bread & Circuses: the bout's special rules
var killcam: KillCam = null
var tut: Tutorial = null
var last_local_inp := {}
var last_hit_of := {}           # fighter -> the last hit it took (for the kill cam)
var circus := {}                # {bout, day, bout_index, mods, fortune}

## The menu's champion: a fighter outside the fight (no bot, not a target) who just stands.
func add_hero(pos: Vector3, yaw_: float, lo: Dictionary, color: Color, skin = null) -> Fighter:
	if hero and is_instance_valid(hero):
		hero.queue_free()
	hero = Fighter.new()
	add_child(hero)
	var o := {"name": "Champion", "slot": 7, "team": 9, "team_color": color}
	if skin != null:
		o["skin"] = int(skin)
	hero.build(pos, yaw_, _resolve_loadout(lo), o)
	hero.set_meta("anchor", hero.torso.global_position)
	return hero

func setup(opts: Dictionary) -> void:
	mode = opts.get("mode", "campaign")
	stage = int(opts.get("stage", 1))
	role = opts.get("role", "local")
	training = opts.get("training", {})
	circus = opts.get("circus", {})
	headless = opts.get("headless", false)
	rng.seed = int(opts.get("seed", stage * 1009 + 7))
	fx = Fx.new(headless)
	add_child(fx)
	arena = Arena.new()
	add_child(arena)
	arena.build(opts.get("arena", "colosseum"), not headless)
	combat = Combat.new()
	add_child(combat)
	social = Social.new(self)
	items = Items.new()
	items.headless = headless
	add_child(items)
	throwables = Throwables.new(self)
	add_child(throwables)
	items.on_event = throwables.on_item
	spectacle = Spectacle.new(self)
	if (not headless or opts.get("killcam", false)) and role != "guest" and not opts.get("autopilot", false) and not attract:
		killcam = KillCam.new(self)
		add_child(killcam)
	hazards = Hazards.new()
	add_child(hazards)
	# The Emperor's decrees: chosen by the host (or the test), told to the guests with "start".
	var ids: Array = opts.get("decrees", [])
	if not opts.has("decrees") and role != "guest" and (mode == "duel" or mode == "chaos") and opts.get("decree_setting", "sometimes") != "off":
		ids = Decrees.roll(1.0 if mode == "chaos" or opts.get("decree_setting") == "always" else 0.6, 3 if mode == "chaos" else 1, rng).map(func(d): return d.id)
	decrees = ids.map(func(i): return Decrees.by_id(str(i))).filter(func(d): return not d.is_empty())
	dec = Decrees.combine(decrees)
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, dec.gravity)
	if dec.timeScale != 1.0:
		Engine.time_scale = dec.timeScale
	combat.chip_mult = dec.chip
	var hspecs: Array = opts.get("hazards", [])
	if not opts.has("hazards") and not dec.hazards.is_empty():
		hspecs = Hazards.random_specs(dec.hazards, rng)
	hazards.build(hspecs)
	hazard_specs = hspecs
	lion_t = 5.0 if dec.lions else -1.0
	spectacle.drops_on = role != "guest" and (mode == "duel" or mode == "chaos")
	combat.hit.connect(_on_hit)
	combat.chip.connect(func(c): if role == "host": _send_weapon_vox(c.weapon, c.indices))
	combat.clang.connect(_on_clang)
	if not headless:
		input = PlayerInput.new()
		add_child(input)
		cam = CameraRig.new()
		add_child(cam)
	if role == "guest":
		combat.enabled = false
		return
	if Modes.handles(mode):
		modes = Modes.new(self, mode)
		modes.setup(opts)
		if not decrees.is_empty():
			_banner("The Emperor decrees", ", ".join(dec.names))
		spectacle.on_round_start()
		return
	# Players: the local one, then a fighter for every friend in the room.
	var lo: Dictionary = opts.get("loadout", {"main": "gladius", "off": "roundShield"})
	me = spawn_fighter({"kind": "local", "name": opts.get("name", "Gladiator"), "loadout": lo, "team": 0, "pos": Vector3(0, 0, -6), "yaw": 0.0, "worn": opts.get("worn", {}), "skin": opts.get("skin"), "color": opts.get("color"), "mods": opts.get("mods", {})})
	me.inventory = opts.get("inventory", {})
	for p in opts.get("peers", []):
		var pe = spawn_fighter({"kind": "remote", "peer": p.id, "name": p.name, "loadout": p.get("loadout", {"main": "gladius"}), "team": 0, "pos": Vector3(1.2 * (entities.size()), 0, -6), "yaw": 0.0, "skin": p.get("skin")})
		pe.inventory = Net.sanitize_kit(p.get("kit", {}))
	players_count = 1 + opts.get("peers", []).size()
	# Tests and attract mode: the player's fighter fights by itself.
	if opts.get("autopilot", false):
		me.bot = Bot.new(me.f, float(opts.get("autopilot_diff", 0.9)), "standard", 99)
	if mode == "campaign":
		stage_info = Data.stage(stage, players_count)
		_spawn_round(0)
		_banner(stage_info.get("title", "Stage %d" % stage), "Round 1 of 3")
	elif mode == "training":
		_spawn_training()
		if opts.get("tutorial", false):
			tut = Tutorial.new(self)
			tut.setup()
	elif mode == "circus":
		_setup_circus(opts)
	if not decrees.is_empty():
		_banner("The Emperor decrees", ", ".join(dec.names))
	spectacle.on_round_start()

# ---------- Spawning ----------

## spec: {kind, name, loadout, team, pos, yaw, mods, personality, diff, color, boss, worn}
func spawn_fighter(spec: Dictionary):
	# A decree on the weapons or the bodies goes into the spec, so guests build the same man.
	if role != "guest" and not decrees.is_empty():
		var lo_k: String = dec.get("loadout", "")
		if lo_k != "":
			var lo2 := Decrees.loadout(lo_k, rng)
			spec.loadout = {"main": lo2.main, "off": lo2.off, "armor": spec.loadout.get("armor", []) if spec.loadout is Dictionary else []}
			spec.erase("worn")
		var mods: Dictionary = spec.get("mods", {}).duplicate()
		for k in dec.mods:
			mods[k] = dec.mods[k]
		spec.mods = mods
	var f := Fighter.new()
	add_child(f)
	var opts := {"name": spec.name, "slot": entities.size(), "team": spec.team, "mods": spec.get("mods", {}), "boss": spec.get("boss", false), "bot": spec.kind == "bot"}
	if spec.get("skin") != null:
		opts["skin"] = int(spec.skin)
	if spec.get("color") != null:
		opts["team_color"] = Color.hex(int(spec.color) << 8 | 0xff)
	elif spec.team == ENEMY_TEAM:
		opts["team_color"] = Color(0.19, 0.19, 0.19)
	f.build(spec.pos, spec.get("yaw", 0.0), _resolve_loadout(spec.loadout), opts)
	# Chips the weapons came in with (the campaign's arms, unmended).
	for side in spec.get("worn", {}):
		if f.weapons.get(side):
			f.weapons[side].remove_voxels(spec.worn[side])
	if role == "guest":
		f.make_puppet()
	var e := {"id": spec.get("id", next_id), "f": f, "kind": spec.kind, "team": spec.team, "peer": spec.get("peer", -1), "boss": spec.get("boss", false), "spec": spec}
	next_id = maxi(next_id, e.id) + 1
	if spec.kind == "bot":
		e.bot = Bot.new(f, clampf(float(spec.get("diff", 0.7)), 0.1, 1.0), spec.get("personality", "standard"), rng.randi())
	f.gravity = dec.gravity
	_register(e)
	return e

func spawn_beast(spec: Dictionary):
	var b := Beast.new()
	add_child(b)
	b.build_beast(spec.beast, spec.pos, spec.get("yaw", 0.0), {"name": spec.get("name", Data.beasts.get(spec.beast, {}).get("name", spec.beast)), "scale": spec.scale if spec.get("scale") != null else Data.beasts.get(spec.beast, {}).get("scale", 1.0), "boss": spec.get("boss", false), "team": spec.team, "seed": rng.randi()})
	b.gravity = dec.gravity
	b.on_breath = _breath
	b.on_stomp = _stomp
	if role == "guest":
		b.make_puppet()
	var e := {"id": spec.get("id", next_id), "f": b, "kind": "beast", "team": spec.team, "peer": -1, "boss": spec.get("boss", false), "spec": spec, "harmless": spec.get("harmless", false)}
	next_id = maxi(next_id, e.id) + 1
	_register(e)
	return e

func _register(e: Dictionary) -> void:
	entities.append(e)
	combat.fighters.append(e.f)
	e.f.died.connect(_on_death)
	e.f.voxels_lost.connect(_on_voxels_lost)
	if role == "host":
		Net.send_all("spawn", _spawn_msg(e))

func _spawn_msg(e: Dictionary) -> Dictionary:
	var s: Dictionary = e.spec.duplicate(true)
	s["id"] = e.id
	s["pos"] = [e.f.torso.global_position.x, 0.0, e.f.torso.global_position.z]
	if s.kind == "local":
		s["kind"] = "remote"
		s["peer"] = 1
	return s

func _resolve_loadout(lo: Dictionary) -> Dictionary:
	var out := {}
	for k in ["main", "off"]:
		var v = lo.get(k)
		if v is String and v != "":
			out[k] = Data.preset(v)
		elif v is Dictionary:
			out[k] = v
	out["armor"] = lo.get("armor", [])
	return out

## Blades of better metal as the stages go on (stages.js temperDesign).
static func temper(design: Dictionary, t) -> Dictionary:
	if design.is_empty() or t == null:
		return design
	var up := {"bronze": "steel", "iron": "steel"} if t == "steel" else {"bronze": "iron"}
	var d := design.duplicate(true)
	var vox := []
	for v in d.voxels:
		vox.append([v[0], v[1], v[2], up.get(v[3], v[3]) if v[4] != "grip" else v[3], v[4]])
	d.voxels = vox
	return d

## An enemy from a campaign entry: the type's kit plus the stage's armour, temper and skill.
func enemy_spec(en: Dictionary, i: int, total: int) -> Dictionary:
	var a := (i - (total - 1) / 2.0) * 0.55 + PI
	var rad := 8.0 if en.get("boss", false) else 7.0
	var pos := Vector3(sin(a) * rad, 0.1, cos(a) * rad)
	if en.has("beast"):
		return {"kind": "beast", "beast": en.beast, "scale": en.get("scale"), "name": en.get("name", Data.beasts.get(en.beast, {}).get("name", en.beast)), "boss": en.get("boss", false), "team": ENEMY_TEAM, "pos": pos, "yaw": atan2(-pos.x, -pos.z)}
	var t := Data.enemy_type(en.get("e", "recruit"))
	var g: Dictionary = en.get("gear", {}) if en.get("gear") else {}
	var los: Array = t.get("loadouts", [{"main": "gladius"}])
	var lo: Dictionary = los[rng.randi_range(0, los.size() - 1)]
	var main: Dictionary = temper(Data.preset(lo.main), g.get("temper")) if lo.get("main") else {}
	var off: Dictionary = temper(Data.preset(lo.off), g.get("temper")) if lo.get("off") else {}
	if en.get("loadout") is String and en.loadout != "":
		main = Data.preset(en.loadout)
		off = {}
	var armor: Array = lo.get("armor", []).duplicate()
	for x in g.get("armor", []):
		if not armor.has(x):
			armor.append(x)
	var names: Array = t.get("names", ["Gladiator"])
	var nm: String = en.get("name", names[rng.randi_range(0, names.size() - 1)])
	if g.get("rank") and not en.get("boss", false):
		nm = "%s %s" % [g.rank, nm]
	var mods: Dictionary = t.get("mods", {}).duplicate()
	for k in g.get("mods", {}):
		mods[k] = g.mods[k]
	for k in en.get("mods", {}):
		mods[k] = en.mods[k]
	return {"kind": "bot", "name": nm, "loadout": {"main": main, "off": off, "armor": armor}, "team": ENEMY_TEAM, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "mods": mods,
		"personality": t.get("personality", "standard"), "diff": float(t.get("diff", 0.8)) * float(g.get("diff", 1.0)), "color": t.get("color"), "boss": en.get("boss", false)}

func _spawn_round(r: int) -> void:
	round = r
	var rounds: Array = stage_info.get("rounds", [])
	if r >= rounds.size():
		return
	var list: Array = rounds[r]
	for i in list.size():
		var spec := enemy_spec(list[i], i, list.size())
		if spec.kind == "beast":
			spawn_beast(spec)
		else:
			spawn_fighter(spec)

## A Bread & Circuses bout: its enemies (one more for every extra player), its rules, its intro.
func _setup_circus(opts: Dictionary) -> void:
	circus = opts.get("circus", {})
	var bout: Dictionary = circus.get("bout", {})
	var list := Circus.scaled_enemies(bout, players_count)
	for i in list.size():
		var spec := enemy_spec(list[i], i, list.size())
		if spec.kind == "beast":
			spawn_beast(spec)
		else:
			spawn_fighter(spec)
	rules = BoutRules.new(self, bout)
	rules.setup()
	_banner(String(bout.get("name", "Bout")), String(bout.get("intro", "")))
	if circus.get("fortune"):
		feed.emit(String(circus.fortune.get("text", "")))

## A decree in the middle of a bout (the Emperor's Whims).
func apply_decree(d: Dictionary) -> void:
	if d.is_empty():
		return
	decrees.append(d)
	dec = Decrees.combine(decrees)
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, dec.gravity)
	Engine.time_scale = dec.timeScale
	combat.chip_mult = dec.chip
	for e in entities:
		if is_instance_valid(e.f):
			e.f.gravity = dec.gravity
			for k in d.get("mods", {}):
				if k != "weaponScale" and k != "bodyScale":
					e.f.mods[k] = d.mods[k]
	_banner(String(d.get("name", "")), String(d.get("desc", "")))
	sfx("horn", Vector3.ZERO, 1.0)

func circus_status() -> String:
	var head := "Day %s · bout %d" % [["I", "II", "III", "IV", "V", "VI", "VII"][clampi(int(circus.get("day", 0)), 0, 6)], int(circus.get("bout_index", 0)) + 1]
	var s := rules.status() if rules else ""
	return head + ((" · " + s) if s != "" else "")

func _spawn_training() -> void:
	var who: String = training.get("enemy", "gladiator")
	for i in int(training.get("count", 1)):
		var pos := Vector3(i * 1.5, 0.1, 5.0)
		if who == "none":
			break
		if Data.beasts.has(who):
			spawn_beast({"beast": who, "team": ENEMY_TEAM, "pos": pos, "yaw": PI})
		else:
			var w: String = training.get("weapon", "gladius")
			spawn_fighter({"kind": "bot", "name": "Sparring partner", "loadout": {"main": w if w != "random" else ["gladius", "axe", "spear", "mace"][rng.randi_range(0, 3)]}, "team": ENEMY_TEAM, "pos": pos, "yaw": PI, "diff": float(training.get("difficulty", 0.5)), "personality": "standard"})

# ---------- The loop ----------

func _physics_process(dt: float) -> void:
	time += dt
	tick += 1
	if hero and is_instance_valid(hero):
		hero.control(dt, hero_inp)
		# He holds his mark: a soft spring on the torso, so the balance never walks him off.
		var d: Vector3 = hero.get_meta("anchor") - hero.torso.global_position
		var v: Vector3 = hero.torso.linear_velocity
		hero.torso.apply_central_force(Vector3(d.x * 600.0 - v.x * 60.0, 0, d.z * 600.0 - v.z * 60.0) * hero.torso.mass)
	if role == "guest":
		throwables.update(dt)
		for e in entities:
			if is_instance_valid(e.f) and e.f.parts.any(func(p): return not p.spots.is_empty()):
				Fire.tick(e.f, dt, false)
		return
	var local_inp := {}
	if modes and me == null and input:
		local_inp = input.sample(dt)
	for e in entities:
		var f = e.f
		if not is_instance_valid(f):
			continue
		var inp := {}
		# Tests (and the tutorial) can drive any fighter by hand.
		var kind_: String = "drive" if e.has("drive") else String(e.kind)
		if kind_ == "drive":
			inp = e.drive.call(e)
			if inp.has("look"):
				f.yaw = float(inp.look.yaw)
		match kind_:
			"local":
				if e.has("bot"):
					var tl = nearest_enemy(e)
					if tl:
						var dl: Vector3 = tl.f.torso.global_position - f.torso.global_position
						f.yaw = atan2(dl.x, dl.z)
					inp = e.bot.update(dt, tl.f if tl else null, _world_of(e))
				else:
					inp = input.sample(dt) if input else {}
					last_local_inp = inp
					if inp.has("look"):
						f.yaw = float(inp.look.yaw)
			"remote":
				inp = Net.input_of(e.peer)
				if inp.has("look"):
					f.yaw = float(inp.look.yaw)
			"bot":
				var tgt = nearest_enemy(e)
				var mt = e.get("manual_target")
				if mt != null and mt.f.alive and mt.team != e.team:
					tgt = mt
				if tgt:
					var d: Vector3 = tgt.f.torso.global_position - f.torso.global_position
					f.yaw = atan2(d.x, d.z)
					f.gaze = tgt.f.head.global_position
				inp = e.bot.update(dt, tgt.f if tgt else null, _world_of(e))
			"beast":
				var tb = nearest_enemy(e)
				f.target = tb.f if tb else null
		if e.kind == "bot" and e.get("ball_target") is Vector3:
			var bt: Vector3 = e.ball_target
			var bd := Vector2(bt.x - f.torso.global_position.x, bt.z - f.torso.global_position.z).length()
			inp.faceAt = bt
			inp.mz = 1.0 if bd > 0.9 else 0.2
			inp.mx = 0.0
			inp.sprint = bd > 2.0
			inp.kick = bd < 1.1 and rng.randf() < 0.25
		if modes and modes.frozen():
			inp = {"main": inp.get("main", {"x": 0.1, "y": 0.15}), "off": inp.get("off", {"x": -0.35, "y": 0.1}), "look": inp.get("look"), "throw": inp.get("throw", false), "charging": inp.get("charging", 0.0)}
			if inp.look == null:
				inp.erase("look")
		if e.kind == "local":
			local_inp = inp
		if inp.get("ability") is Dictionary:
			use_ability(f, inp.ability)
		if int(inp.get("useItem", -1)) >= 0:
			throwables.use_item(e, int(inp.useItem))
		if inp.get("faceAt") is Vector3:
			var fd: Vector3 = inp.faceAt - f.torso.global_position
			f.yaw = atan2(fd.x, fd.z)
		if e.kind == "beast":
			f.control(dt)
		else:
			e.input = inp
			inp = social.before(e, inp, dt)
			f.control(dt, inp)
	social.after(dt)
	if modes:
		modes.update(dt, local_inp)
	spectacle.update(dt)
	if rules and not over:
		rules.update(dt)
	if tut and not over:
		tut.update(dt, last_local_inp)
		if tut.finished:
			_end(true, "You are ready", "That is all there is to it. The campaign waits at the gate.")
	hazards.update(dt)
	if lion_t > 0.0:
		lion_t -= dt
		if lion_t <= 0.0:
			spawn_beast({"beast": "lion", "team": ENEMY_TEAM, "pos": Vector3(0, 0.1, 12), "yaw": PI})
			feed.emit("Lions' Den! Here comes the Emperor's pet.")
	if role == "host":
		_sync_loose()
	var chars := entities.map(func(x): return x.f).filter(func(x): return is_instance_valid(x))
	items.update(dt, chars)
	throwables.update(dt)
	throwables.update_shooters(dt)
	for e in entities:
		if is_instance_valid(e.f) and e.f.parts.any(func(p): return not p.spots.is_empty()):
			Fire.tick(e.f, dt, true)
	if role == "host" and tick % SNAP_EVERY == 2:
		Net.send_all("isnap", items.snapshot(), false)
		var ls := []
		for id in loose_ids:
			var lw: Weapon = loose_ids[id]
			if is_instance_valid(lw):
				var lq := lw.global_transform.basis.get_rotation_quaternion()
				ls.append([id, snappedf(lw.global_position.x, 0.001), snappedf(lw.global_position.y, 0.001), snappedf(lw.global_position.z, 0.001), snappedf(lq.x, 0.001), snappedf(lq.y, 0.001), snappedf(lq.z, 0.001), snappedf(lq.w, 0.001)])
		Net.send_all("lsnap", {"w": ls, "h": hazards.snapshot()}, false)
	if role == "host" and tick % SNAP_EVERY == 0:
		Net.send_all("snap", snapshot(), false)
	_check_round(dt)

func _world_of(e: Dictionary) -> Dictionary:
	return {"loose": combat.loose_weapons, "allies": entities.filter(func(o): return o.team == e.team and o != e).map(func(o): return o.f)}

## A bot's ranged trick (ai.js abilities): a rock or a net at the head, a pot at the feet, or a
## medicus patching up a friend.
func use_ability(c, ab: Dictionary) -> void:
	if not c.alive or ab.get("target") == null or not is_instance_valid(ab.target):
		return
	var t = ab.target
	var type: String = ab.type
	if type == "rock" or type == "net" or type.begins_with("pot_"):
		var from: Vector3 = c.hand_world("R") + Vector3(0, 0.3, 0)
		var aim: Vector3
		if type.begins_with("pot_"):
			aim = Vector3(t.torso.global_position.x + randf_range(-0.4, 0.4), 0.1, t.torso.global_position.z + randf_range(-0.4, 0.4))
		else:
			aim = t.head.global_position + Vector3(0, -0.15, 0)
		items.throw_at(type, from, aim, c, 9.0 if type == "net" else (10.0 if type.begins_with("pot_") else 13.0))
		sfx("whoosh", from)
	elif type == "heal" and t.alive:
		t.blood = minf(100.0, t.blood + 25.0)
		for p in t.parts:
			p.bleed = 0.0
			if not p.severed:
				p.hp = minf(100.0, p.hp + 20.0)
		t.stagger = 0.0
		feed.emit("%s patched up %s" % [c.display_name, t.display_name])

## A decree in the middle of a fight (the Emperor's whims): gravity, bodies, traps change now.
func add_runtime_decree(d: Dictionary) -> void:
	decrees = decrees.filter(func(x): return x.id != d.id and not (x.has("hazards") and d.has("hazards"))) + [d]
	dec = Decrees.combine(decrees)
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, dec.gravity)
	Engine.time_scale = dec.timeScale
	combat.chip_mult = dec.chip
	for e in entities:
		e.f.gravity = dec.gravity
		for k in d.get("mods", {}):
			e.f.mods[k] = d.mods[k]
	if d.has("hazards"):
		hazard_specs = Hazards.random_specs(d.hazards, rng)
		hazards.build(hazard_specs)
	if d.get("lions", false):
		lion_t = 1.0
	_banner(d.name, d.desc)
	sfx("horn", Vector3.ZERO)

## Sets `part` of `c` alight (or lets acid eat it) where it struck, and tells the guests.
func add_spot(c, part: VoxelPart, kind: String, seconds: float, by = null, point = null) -> void:
	if c == null or not c.alive or part == null or role == "guest":
		return
	var was: bool = Fire.is_burning(c) if kind == "fire" else c.parts.any(func(p): return p.spots.any(func(s): return s.kind == "acid" and s.t > 0.0))
	var s := Fire.add_spot(part, kind, seconds, point)
	if s.is_empty():
		return
	if by and by != c:
		c.last_attacker = by
	var e = entity_of(c)
	if role == "host" and e:
		Net.send_all("spot", {"id": e.id, "part": c.parts.find(part), "kind": kind, "lp": [s.lp.x, s.lp.y, s.lp.z], "t": s.t})
	if not was:
		feed.emit(("%s is on fire!" if kind == "fire" else "The poison eats into %s!") % c.display_name)

## A weapon lying loose in the arena (a crowd's gift, chickens out of a crate).
func spawn_loose_weapon(design: Dictionary, pos: Vector3) -> Weapon:
	if design.is_empty():
		return null
	var w := Weapon.new()
	w.setup(design, 1.0)
	add_child(w)
	w.global_position = pos
	w.build_chain()
	combat.loose_weapons.append(w)
	return w

## A coin picked up off the sand (the crowd module pays it).
func on_coin(c) -> void:
	if rules:
		rules.on_coin(c)

## Host: loose weapons get a number and the guests are told when one is dropped, thrown,
## spawned or picked up.
func _sync_loose() -> void:
	for w in combat.loose_weapons:
		if not is_instance_valid(w) or w.net_id >= 0:
			continue
		w.net_id = next_wid
		next_wid += 1
		loose_ids[w.net_id] = w
		var owner_e = entity_of(w.own_by) if w.own_by else null
		if owner_e and w.last_side != "":
			Net.send_all("wloose", {"w": w.net_id, "id": owner_e.id, "side": w.last_side})
		else:
			Net.send_all("wspawn", {"w": w.net_id, "key": Combat._preset_key(w.design), "p": [w.global_position.x, w.global_position.y, w.global_position.z]})
	for id in loose_ids.keys():
		var w: Weapon = loose_ids[id]
		if not is_instance_valid(w):
			loose_ids.erase(id)
			continue
		if w.holder != null:
			var he = entity_of(w.holder)
			if he:
				Net.send_all("wpick", {"w": id, "id": he.id, "side": "R" if he.f.weapons.R == w else "L"})
			loose_ids.erase(id)
			w.net_id = -1

## Guests: what the host sends besides spawns and snapshots.
func guest_message(type: String, data) -> void:
	match type:
		"wloose":
			var e = entity_by_id(int(data.get("id", -1))) if data is Dictionary else null
			if e and (data.side == "R" or data.side == "L") and e.f.weapons.get(data.side):
				var w: Weapon = e.f.release(data.side)
				loose_ids[int(data.w)] = w
		"wspawn":
			if data is Dictionary and data.get("p") is Array and not loose_ids.has(int(data.get("w", -1))):
				var w := spawn_loose_weapon(Data.preset(str(data.get("key", ""))), Vector3(data.p[0], data.p[1], data.p[2]))
				if w:
					w.freeze = true
					w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					loose_ids[int(data.w)] = w
		"wpick":
			var e2 = entity_by_id(int(data.get("id", -1))) if data is Dictionary else null
			var w2 = loose_ids.get(int(data.get("w", -1)) if data is Dictionary else -1)
			if e2 and w2 and (data.side == "R" or data.side == "L"):
				e2.f.weapons[data.side] = w2
				w2.holder = e2.f
				loose_ids.erase(int(data.w))
		"lsnap":
			if data is Dictionary:
				for r in data.get("w", []):
					var lw = loose_ids.get(int(r[0])) if r is Array and r.size() >= 8 else null
					if lw and is_instance_valid(lw):
						lw.global_transform = Transform3D(Basis(Quaternion(r[4], r[5], r[6], r[7]).normalized()), Vector3(r[1], r[2], r[3]))
				hazards.apply_snapshot(data.get("h", []))
		"isnap":
			if data is Array:
				items.apply_snapshot(data)
		"zone":
			if data is Dictionary and Throwables.ZONE_COLORS.has(str(data.get("type"))) and data.get("p") is Array:
				throwables.add_zone(str(data.type), Vector3(data.p[0], data.p[1], data.p[2]), clampf(float(data.r), 0.1, 5.0), clampf(float(data.t), 0.0, 30.0))
		"spot":
			if data is Dictionary:
				var e = entity_by_id(int(data.get("id", -1)))
				var pi := int(data.get("part", -1))
				if e and pi >= 0 and pi < e.f.parts.size() and data.get("lp") is Array:
					var part: VoxelPart = e.f.parts[pi]
					Fire.add_spot(part, "acid" if data.get("kind") == "acid" else "fire", clampf(float(data.get("t", 1.0)), 0.0, 12.0), part.global_transform * Vector3(data.lp[0], data.lp[1], data.lp[2]))
		"feed":
			if data is String:
				feed.emit(data.left(160))
		"fx":
			if data is Dictionary and data.get("p") is Array and (data.p as Array).size() == 3:
				var fp := Vector3(data.p[0], data.p[1], data.p[2])
				match str(data.get("k")):
					"hit":
						var fd := Vector3(data.d[0], data.d[1], data.d[2]) if data.get("d") is Array and (data.d as Array).size() == 3 else Vector3.UP
						hit_fx(fp, fd, clampf(float(data.get("J", 5.0)), 0.0, 80.0), str(data.get("t", "blunt")), bool(data.get("s", false)))
					"clang":
						fx.burst("sparks", fp, int(clampf(float(data.get("J", 5.0)) * 3.0, 6.0, 90.0)))
					"pool":
						fx.pool(fp, 1.4 * clampf(float(data.get("s", 1.0)), 0.3, 4.0), 8.0)

func nearest_enemy(e: Dictionary):
	var best = null
	var bd := INF
	var p: Vector3 = e.f.torso.global_position
	var cands := entities.filter(func(o): return o.team != e.team and o.f.alive and not (o.kind == "beast" and e.kind == "beast" and not o.get("harmless", false)) and not (o.get("harmless", false) and e.kind != "beast"))
	# Predators cannot resist a goat.
	if e.kind == "beast":
		for o in cands:
			if o.get("harmless", false) and o.f.torso.global_position.distance_to(p) < 12.0:
				return o
	var st = social.target_for(e, cands) if social else null
	if st is Dictionary and st.has("only"):
		cands = st.only
	elif st != null:
		return st
	for o in cands:
		var d := p.distance_to(o.f.torso.global_position)
		if d < bd:
			bd = d
			best = o
	return best

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if is_inside_tree():
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.81)

func sfx(kind: String, at: Vector3, gain := 1.0) -> void:
	if Sfx and not headless:
		Sfx.play(kind, at, gain)

## The crowd's favour (filled in by the crowd module when there is one).
func crowd_add(f, n: float, why: String) -> void:
	if spectacle and role != "guest":
		spectacle.add(f, n, why)

func has_gadget(e: Dictionary, id: String) -> bool:
	return e.get("gadgets", []).has(id)

## Blood, sparks and marks for a blow at `p` (host and guests alike): a cut sprays, a thrust
## spurts, a blunt blow bruises with little blood; a limb coming off opens the floodgates.
func hit_fx(p: Vector3, dir: Vector3, J: float, type: String, severed := false) -> void:
	if headless:
		return
	arena.set_excitement(maxf(arena.excitement, minf(1.0, J / 45.0 + (0.6 if severed else 0.0))))
	var n := int(clampf(J * (1.6 if type == "edge" else (1.2 if type == "point" else 0.5)), 4.0, 140.0)) + (120 if severed else 0)
	fx.burst("confetti" if dec.confetti else "blood", p, n, (dir + Vector3(0, 0.6, 0)).normalized(), 0.8 + J / 40.0)
	if J > 8.0 and not dec.confetti and type != "blunt":
		fx.burst("bloodmist", p, int(clampf(J * 0.5, 4.0, 40.0)), (dir + Vector3(0, 0.3, 0)).normalized())
	if J > 12.0 and not dec.confetti:
		fx.mark("blood", Vector3(p.x + dir.x * 0.4, 0, p.z + dir.z * 0.4), clampf(0.15 + J * 0.012, 0.2, 0.9) * (1.8 if severed else 1.0))

func _on_clang(c: Dictionary) -> void:
	if Sfx:
		Sfx.play("clang", c.p, minf(1.0, c.J / 8.0))
	if c.J > 2.0:
		fx.burst("sparks", c.p, int(clampf(c.J * 3.0, 6.0, 90.0)), Vector3.UP, 0.8 + c.J / 30.0)
		if role == "host":
			Net.send_all("fx", {"k": "clang", "p": [snappedf(c.p.x, 0.01), snappedf(c.p.y, 0.01), snappedf(c.p.z, 0.01)], "J": snappedf(c.J, 0.1)}, false)

## A blow that did not come through the physics contacts (a slam, a man landing on another).
func report_hit(h: Dictionary) -> void:
	combat.hit.emit(h)

func humans() -> Array:
	return entities.filter(func(x): return x.kind == "local" or x.kind == "remote")

func enemies() -> Array:
	return entities.filter(func(x): return x.team == ENEMY_TEAM)

func _check_round(dt: float) -> void:
	if over:
		return
	if modes:
		modes.check(dt)
		return
	if between > 0.0:
		between -= dt
		if between <= 0.0:
			_spawn_round(round + 1)
			_banner("Round %d of 3" % (round + 1), "")
		return
	var alive_h := humans().filter(func(x): return x.f.alive)
	var alive_e := enemies().filter(func(x): return x.f.alive)
	if mode == "training":
		for e in enemies():
			if not e.f.alive and not e.get("respawned", false) and training.get("respawn", true):
				e.respawned = true
				var spec: Dictionary = e.spec.duplicate()
				spec.erase("id")
				if e.kind == "beast":
					spawn_beast(spec)
				else:
					spawn_fighter(spec)
		return
	if mode == "circus":
		_check_circus(alive_h, alive_e)
		return
	if alive_h.is_empty():
		_end(false, "You fall", "The crowd moves on. A fall sends you back to the checkpoint.")
		return
	if alive_e.is_empty():
		if mode == "campaign":
			round_pay += int(stage_info.get("roundPay", 10))
			if round + 1 < int(stage_info.get("rounds", []).size()):
				between = 2.5
				feed.emit("Round %d won" % (round + 1))
				return
			var pay := int(stage_info.get("stagePay", 30)) + round_pay
			_end(true, "Stage %d cleared" % stage, "%d denarii each. Back to the yard: spend, mend, gear up." % pay, pay)
		else:
			_end(true, "Victory", "")

func _check_circus(alive_h: Array, alive_e: Array) -> void:
	if alive_h.is_empty():
		_end(false, "DEFEAT", "The Emperor turns his thumb down")
		return
	var r := rules.check() if rules else ""
	var won := r == "win" or (r == "" and rules != null and rules.default_rule() and alive_e.filter(func(e): return not e.get("harmless", false)).is_empty())
	if r == "lose":
		_end(false, "DEFEAT", "The Emperor turns his thumb down")
	elif won:
		_end(true, "VICTORY!", "The crowd roars your name")

func _end(won: bool, text: String, sub: String, pay := 0, _linger := false) -> void:
	over = true
	if Sfx.music and not headless and not attract:
		Sfx.music.set_state("victory" if won else "off")
	_banner(text, sub)
	var wear := {}
	if me:
		for side in ["R", "L"]:
			var w = me.f.weapons.get(side)
			if w:
				var lost := []
				for i in w.alive.size():
					if w.alive[i] == 0:
						lost.append(i)
				wear[side] = lost
			elif me.f.arm[side].fore.severed:
				wear[side] = "lost"
	var result := {"won": won, "stage": stage, "pay": pay, "checkpoint": stage_info.get("checkpoint"), "wear": wear, "kills": kills.duplicate(), "boss": stage_info.get("boss", false)}
	if mode == "circus":
		result["circus"] = true
		result["coins"] = rules.coins if rules else 0
		result["favor"] = spectacle.get_favor(me.f) if me and is_instance_valid(me.f) else 0.0
		result["time"] = time
	if role == "host":
		Net.send_all("end", {"won": won, "text": text, "sub": sub, "pay": pay})
	if killcam:
		# Let the last blow play out on tape, then show the best kill of the match.
		await get_tree().create_timer(KillCam.AFTER + 0.2).timeout
		if killcam.has_clip():
			await killcam.play(func(): pass)
	finished.emit(result)

# ---------- Events ----------

func _banner(text: String, sub: String) -> void:
	banner.emit(text, sub)
	if role == "host":
		Net.send_all("banner", {"text": text, "sub": sub})

func _on_hit(h: Dictionary) -> void:
	if rules and role != "guest":
		rules.on_hit(h)
	if h.get("char"):
		last_hit_of[h.char] = h
	if tut:
		tut.on_hit(h)
	if role != "guest":
		spectacle.on_hit(h)
	# Blood where it struck (a party of colours under Confetti Blood), and on the sand below.
	var jn: float = h.get("J", 0.0)
	if jn > 6.0 and h.get("p") is Vector3:
		var dir: Vector3 = h.get("dir", Vector3.UP) if h.get("dir") is Vector3 else Vector3.UP
		hit_fx(h.p, dir, jn, String(h.get("type", "blunt")), not h.res.get("severed", []).is_empty())
		if role == "host":
			Net.send_all("fx", {"k": "hit", "p": [snappedf(h.p.x, 0.01), snappedf(h.p.y, 0.01), snappedf(h.p.z, 0.01)], "d": [snappedf(dir.x, 0.01), snappedf(dir.y, 0.01), snappedf(dir.z, 0.01)], "J": snappedf(jn, 0.1), "t": h.get("type", "blunt"), "s": not h.res.get("severed", []).is_empty()}, false)
	if h.killed and h.attacker:
		kills[h.attacker.display_name] = kills.get(h.attacker.display_name, 0) + 1
		feed.emit("%s kills %s" % [h.attacker.display_name, h.char.display_name])
	elif h.res.get("severed", []).size() > 0:
		feed.emit("%s loses the %s!" % [h.char.display_name, String(h.res.severed[0].label).to_lower()])
	if Sfx:
		Sfx.play("slash" if h.type == "edge" else ("stab" if h.type == "point" else "thud"), h.p, minf(1.0, h.J / 30.0))
	if role == "host" and h.get("chip", {}).get("indices", []).size() > 0:
		_send_weapon_vox(h.weapon, h.chip.indices)

func _on_death(f: Fighter, cause: String) -> void:
	if role != "guest":
		spectacle.on_death(f)
	if killcam:
		killcam.on_death(f, cause, last_hit_of.get(f, {}))
	if f.kind != "beast" or not Data.beasts.get(f.get("species") if f.get("species") else "", {}).get("bloodless", false):
		fx.pool(f.torso.global_position, 1.4 * f.S, 8.0)
		arena.set_excitement(1.0)
		if role == "host":
			var tp := f.torso.global_position
			Net.send_all("fx", {"k": "pool", "p": [tp.x, tp.y, tp.z], "s": f.S})
	feed.emit("%s is %s" % [f.display_name, "dead" if cause != "decap" else "beheaded"])

func _on_voxels_lost(f: Fighter, part_index: int, indices: Array, _voxels: Array) -> void:
	if role != "host":
		return
	var e = entity_of(f)
	if e:
		Net.send_all("vox", {"id": e.id, "part": part_index, "idx": indices})

func _send_weapon_vox(w: Weapon, idx: Array) -> void:
	for e in entities:
		for side in ["R", "L"]:
			if e.f.weapons.get(side) == w:
				Net.send_all("wvox", {"id": e.id, "side": side, "idx": idx})

func entity_of(f) -> Variant:
	for e in entities:
		if e.f == f:
			return e
	return null

func entity_by_id(id: int) -> Variant:
	for e in entities:
		if e.id == id:
			return e
	return null

## Fire or venom from a beast's head: everyone in a cone in front of it gets it.
func _breath(b: Beast, kind_: String, rng_: float) -> void:
	var hp: Vector3 = b.head.global_position
	var fwd := PD.quat_of(b.head) * Vector3(0, 0, 1)
	feed.emit("%s breathes %s!" % [b.display_name, kind_])
	for e in entities:
		if e.team == ENEMY_TEAM or not e.f.alive:
			continue
		var to: Vector3 = e.f.torso.global_position - hp
		if to.length() < rng_ and fwd.dot(to.normalized()) > 0.75:
			var part: VoxelPart = e.f.torso
			e.f.apply_hit(part, {"impulse": 14.0, "type": "blunt", "hardness": 0.3, "point": part.global_position, "dir": to.normalized()})
			part.bleed += 1.5
			part.wound(Vector3.ZERO, 0.12, "blood")

func _stomp(b: Beast) -> void:
	for e in entities:
		if e.team == ENEMY_TEAM or not e.f.alive:
			continue
		if e.f.torso.global_position.distance_to(b.torso.global_position) < 2.5 * b.S:
			e.f.fall(1.5, true)
			e.f.apply_hit(e.f.torso, {"impulse": 20.0, "type": "blunt", "point": e.f.torso.global_position, "dir": Vector3.DOWN})

# ---------- Network (host side snapshots, guest side drawing) ----------

func snapshot() -> Array:
	var out := []
	for e in entities:
		var f = e.f
		var w := []
		for side in ["R", "L"]:
			var wp = f.weapons.get(side)
			if wp:
				var q: Quaternion = wp.global_transform.basis.get_rotation_quaternion()
				w.append([side, wp.global_position.x, wp.global_position.y, wp.global_position.z, q.x, q.y, q.z, q.w])
		out.append([e.id, f.snapshot(), w, f.status()])
	return out

func apply_snapshot(s: Array) -> void:
	for row in s:
		var e = entity_by_id(int(row[0]))
		if e == null:
			continue
		e.f.apply_snapshot(row[1])
		for w in row[2]:
			var wp = e.f.weapons.get(w[0])
			if wp:
				wp.global_transform = Transform3D(Basis(Quaternion(w[4], w[5], w[6], w[7])), Vector3(w[1], w[2], w[3]))
		e.f.apply_status(row[3])

## A guest builds what the host spawned.
func guest_spawn(spec: Dictionary) -> void:
	if entity_by_id(int(spec.id)) != null:
		return
	spec.pos = Vector3(spec.pos[0], spec.pos[1], spec.pos[2]) if spec.pos is Array else spec.pos
	if spec.kind == "beast":
		spawn_beast(spec)
	else:
		var e = spawn_fighter(spec)
		if spec.kind == "remote" and int(spec.get("peer", -1)) == Net.my_id():
			me = e

func guest_vox(m: Dictionary) -> void:
	var e = entity_by_id(int(m.id))
	if e and int(m.part) >= 0 and int(m.part) < e.f.parts.size():
		e.f.parts[int(m.part)].remove_voxels(m.idx, false)

func guest_wvox(m: Dictionary) -> void:
	var e = entity_by_id(int(m.id))
	if e and e.f.weapons.get(m.side):
		e.f.weapons[m.side].remove_voxels(m.idx)

func _process(dt: float) -> void:
	# A bleeding man leaves a trail of drops on the sand.
	drip_t -= dt
	if drip_t <= 0.0 and not headless:
		drip_t = 0.35
		for e in entities:
			var f = e.f
			if not is_instance_valid(f) or not f.alive:
				continue
			var bleed := 0.0
			for prt in f.parts:
				bleed += prt.bleed
			if bleed > 0.6 and randf() < minf(1.0, bleed * 0.25):
				var tp: Vector3 = f.torso.global_position
				fx.mark("blood", Vector3(tp.x + randf_range(-0.2, 0.2), 0, tp.z + randf_range(-0.2, 0.2)), randf_range(0.08, 0.22) * f.S)
	if cam and attract and not hero_cam.is_empty():
		var sway := Vector3(sin(time * 0.23) * 0.12, sin(time * 0.31) * 0.05, 0)
		cam.global_position = cam.global_position.lerp(hero_cam.pos + sway, minf(1.0, dt * 3.0))
		cam.look_at(hero_cam.look, Vector3.UP)
	elif cam and attract:
		var c := Vector3.ZERO
		var n := 0
		for e in entities:
			if is_instance_valid(e.f) and e.f.alive:
				c += e.f.torso.global_position
				n += 1
		cam.orbit(Vector3(c.x / n, 0.4, c.z / n) if n > 0 else Vector3(0, 0.4, 0), dt)
	elif cam:
		var f = me.f if me else null
		var yaw := input.look_yaw if input else 0.0
		var pitch := input.look_pitch if input else 0.0
		cam.follow(f, yaw, pitch, dt)
	if role == "guest" and input and Net.active():
		if tick % 4 == 0:
			var gi := input.sample(dt * 4.0)
			Net.send_host("input", PlayerInput.pack(gi), PlayerInput.has_one_shot(gi))
	tick += 1 if role == "guest" else 0
