class_name Match
extends Node3D
## One match (game.js): the arena, the fighters, the rounds. Modes: "campaign" (a stage of
## three rounds from the campaign tables, then back to the yard), "training" (a sparring
## partner that comes back) and "duel". The host runs the physics; guests draw snapshots.

signal feed(text: String)
signal banner(text: String, sub: String)
signal finished(result: Dictionary)
@warning_ignore("unused_signal")   # sent by the yard (YardPlay)
signal station(id: String)
## The campaign's physician: a player lost a limb or an eye this round (Body). The menu shows
## the local one; the host asks a guest over the network.
signal doctor(e: Dictionary, body: Dictionary, news: Array)

const ENEMY_TEAM := 1
const TICK := 1.0 / 120.0
const SNAP_EVERY := 3           # snapshots at 40 Hz (the guest draws between them)

var mode := "campaign"
var stage := 1
var coop := false   # the co-op ladder: a campaign of its own for a party, saved apart
var round := 0
var role := "local"             # local | host | guest
var arena: Arena
var combat: Combat
var cam: CameraRig
var input: PlayerInput
var my_hit := {}               # where the player last struck a foe: {p, f, t}
var entities: Array = []        # {id, f, kind, team, bot, peer, boss, spec}
var me = null
var over := false
var between := 0.0
var doctor_wait := {}            # entity id -> true while that player is at the physician
var doctor_t := 0.0
var time := 0.0
var tick := 0
var stage_info: Dictionary = {}
var players_count := 1
var round_pay := 0
var mind_aim_until := -1.0   # while the local player may hold a man in the Hand of Jupiter
## Denarii are scarce: a bout pays well under half of the web game's tables, so a new sword
## is saved for over several fights, not bought after the first.
const PAY_SCALE := 0.5
## The crowd's purse: up to this share of the stage's pay more for a lively bout (Spectacle.heat),
## nothing for a dull one. Small, so it spurs a man on without paying for the campaign.
const CROWD_BONUS := 0.25
const PLAYER_BLEED := 0.75
## The campaign won and begun again (the rudis in hand): each time round the foes are tougher
## by LAP_TOUGH and the beasts bigger by LAP_SCALE.
const LAP_TOUGH := 0.3
const LAP_SCALE := 0.1
var lap := 1
## A boss's second coming (after every boss has come once): the steel set in place of the
## bronze and iron, and a coating on his weapon.
const RETURN_ARMOR := ["steelLorica", "murmilloHelm", "steelGreaves", "manica"]
const RETURN_ARMOR_OFF := ["helmet", "lorica", "greaves", "manica"]
const RETURN_COAT := {"cyclops": "fire", "minotaur": "venom", "giant": "frost", "titan": "fire"}
var kills := {}
var rng := RandomNumberGenerator.new()
var next_id := 1
var training: Dictionary = {}
var headless := false
var guest_bot_on := false
var input_acc := 0.0
var puppets := {}           # guest: body -> [from, to, t0, length]: drawn between the host's snapshots
var snap_t := -1.0
var snap_gap := SNAP_EVERY / 120.0
var guest_bot: Bot
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
var breaths: Array = []
var attract := false            # the menu backdrop: bots only, an orbiting camera
var hero: Fighter = null        # the menu's champion, posing in front of the fight
var hero_inp := {}
var hero_cam := {}              # {pos, look}: a fixed shot instead of the orbit
var tags := {}                  # fighter -> Label3D: a player's name over his head
var rules: BoutRules = null     # Bread & Circuses: the bout's special rules
var killcam: KillCam = null
var tut: Tutorial = null
var yard: YardPlay = null
var mcount := {}                # mission events by the local player this fight
var hit_by_me := {}
var last_local_inp := {}
var last_hit_of := {}           # fighter -> the last hit it took (for the kill cam)
var circus := {}                # {bout, day, bout_index, mods, fortune}

## The menu's champion: a fighter outside the fight (no bot, not a target) who just stands.
## `still`: a mannequin for the dressing screen. He settles once, then stands frozen; dressed
## again, the new body takes the old one's exact pose (parts and weapons) and stays frozen, so
## nothing jitters, falls or flings its weapons when a choice changes.
func add_hero(pos: Vector3, yaw_: float, lo: Dictionary, color: Color, skin = null, still := false) -> Fighter:
	var pose := {}
	var old = hero if hero and is_instance_valid(hero) else null
	if old and still and old.get_meta("frozen", false):
		for p in old.parts:
			pose[p.part_name] = p.global_transform
		for side in old.weapons:
			if old.weapons[side]:
				pose["w" + side] = old.weapons[side].global_transform
	if old:
		# His arms are not his children (they lie in the world beside him): put away with him,
		# or every change on the dressing screen left a sword and a shield on the sand.
		for w in old.weapons.values():
			if w and is_instance_valid(w):
				for l in w.chain_links:
					if is_instance_valid(l):
						l.queue_free()
				if w.chain_head and is_instance_valid(w.chain_head):
					w.chain_head.queue_free()
				w.queue_free()
		old.queue_free()
	hero = Fighter.new()
	add_child(hero)
	var o := {"name": "Champion", "slot": 7, "team": 9, "team_color": color}
	if skin != null:
		o["skin"] = int(skin)
	hero.build(pos, yaw_, _resolve_loadout(lo), o)
	hero.set_meta("anchor", hero.torso.global_position)
	hero.set_meta("still", still)
	hero_still_t = 1.6 if still else -1.0
	if not pose.is_empty():
		for p in hero.parts:
			if pose.has(p.part_name):
				p.global_transform = pose[p.part_name]
		for side in hero.weapons:
			if hero.weapons[side] and pose.has("w" + side):
				hero.weapons[side].global_transform = pose["w" + side]
		for p in hero.parts:
			p.snap_drawing()
		for side in hero.weapons:
			if hero.weapons[side]:
				hero.weapons[side].snap_drawing()
		_freeze_hero(true)
	return hero

var hero_still_t := -1.0

## The fight behind the menus begins again in place: the fighters (and what they dropped, cut
## off or threw) are cleared away and a fresh lot come in; the arena, the camera and the
## champion stay as they are.
func restart_attract(opts: Dictionary) -> void:
	for e in entities.duplicate():
		_remove_entity(e)
	me = null
	for n in get_children():
		if (n is Weapon or n is VoxelPart) and not _is_hero_body(n):
			n.queue_free()
	over = false
	if Modes.handles(mode):
		modes = Modes.new(self, mode)
		modes.setup(opts)
	spectacle.on_round_start()

func _is_hero_body(n: Node) -> bool:
	if hero == null or not is_instance_valid(hero):
		return false
	return hero.parts.has(n) or hero.weapons.values().has(n)

func _freeze_hero(on: bool) -> void:
	var bodies: Array = hero.parts.duplicate()
	for side in hero.weapons:
		if hero.weapons[side]:
			bodies.append(hero.weapons[side])
	for b in bodies:
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = on
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	hero.set_meta("frozen", on)

## The smooth skin over the bodies (VoxelSkin) is set aside for now: bodies are drawn as plain
## voxels whatever the saved setting. True brings back the menu option and the smooth default.
const SMOOTH_BODIES_OFFERED := false

func setup(opts: Dictionary) -> void:
	# Bodies smooth-skinned or as plain voxels (Settings, Graphics; VA_BODIES overrides).
	var bodies := OS.get_environment("VA_BODIES") if OS.has_environment("VA_BODIES") else (str(Save.get_value("settings", {}).get("bodies", "smooth")) if SMOOTH_BODIES_OFFERED else "blocky")
	VoxelPart.smooth_skin = bodies == "smooth"
	mode = opts.get("mode", "campaign")
	stage = int(opts.get("stage", 1))
	coop = bool(opts.get("coop", false))
	lap = maxi(1, int(opts.get("lap", Save.get_value("coop_lap" if coop else "lap", 1)))) if mode == "campaign" else 1
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
	# The kill cam, if the player wants it (Settings): alone, the host and every guest each tape
	# the fight as they see it and replay the best kill at its end.
	if (opts.get("killcam", false) or (not headless and bool(Save.get_value("settings", {}).get("killcam", true)))) and not opts.get("autopilot", false) and not attract:
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
		guest_bot_on = bool(opts.get("autopilot", false))
		if mode == "yard":
			yard = YardPlay.new(self)   # the stalls and their prompts; the host spawns the keepers
			yard.scenery()              # (the board by the gate reads what the host sends: yard_next)
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
	var campaign := mode == "campaign"
	me = spawn_fighter({"kind": "local", "name": opts.get("name", "Gladiator"), "loadout": lo, "team": 0, "pos": Vector3(0, 0, -6), "yaw": 0.0, "worn": opts.get("worn", {}), "skin": opts.get("skin"), "color": opts.get("color"), "mods": opts.get("mods", {}), "body": Body.sanitize(opts.get("body", {})) if campaign or mode == "yard" else null})
	me.inventory = opts.get("inventory", {})
	for p in opts.get("peers", []):
		var pe = spawn_fighter({"kind": "remote", "peer": p.id, "name": p.name, "loadout": p.get("loadout", {"main": "gladius"}), "team": 0, "pos": Vector3(1.2 * (entities.size()), 0, -6), "yaw": 0.0, "skin": p.get("skin"), "body": Body.sanitize(p.get("body", {})) if campaign or mode == "yard" else null})
		pe.inventory = Net.sanitize_kit(p.get("kit", {}))
	players_count = 1 + opts.get("peers", []).size()
	# Tests and attract mode: the player's fighter fights by itself.
	if opts.get("autopilot", false):
		me.bot = Bot.new(me.f, float(opts.get("autopilot_diff", 0.9)), "standard", 99)
	if mode == "campaign":
		stage_info = Data.stage(stage, players_count)
		_spawn_round(0)
		if stage_info.get("duel", false):
			_banner(stage_info.get("title", "Bout %d" % stage), "One on one: %s" % stage_info.get("foe_name", "your opponent"))
		else:
			_banner(stage_info.get("title", "Stage %d" % stage), "Round 1 of 3")
	elif mode == "training":
		_spawn_training()
		if opts.get("tutorial", false):
			tut = Tutorial.new(self)
			tut.setup()
	elif mode == "circus":
		_setup_circus(opts)
	elif mode == "yard":
		yard = YardPlay.new(self)
		yard.setup()
		_send_yard_next()
		_banner("The Ludus yard", "Walk to a station and press G · dummies and throwing boards to play · the board by the gate names your next fight")
	if not decrees.is_empty():
		_banner("The Emperor decrees", ", ".join(dec.names))
	spectacle.on_round_start()

# ---------- Spawning ----------

## spec: {kind, name, loadout, team, pos, yaw, mods, personality, diff, color, boss, worn}
func spawn_fighter(spec: Dictionary):
	# Pieces designed at the armourer's bench come with the spec (a guest has never seen them).
	if spec.get("loadout") is Dictionary and spec.loadout.get("armor_defs") is Dictionary:
		Armory.register(spec.loadout.armor_defs)
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
	if spec.get("body") is Dictionary:
		opts["body"] = Body.sanitize(spec.body)
	f.build(spec.pos, spec.get("yaw", 0.0), _resolve_loadout(spec.loadout), opts)
	# Chips the weapons came in with (the campaign's arms, unmended).
	for side in spec.get("worn", {}):
		if f.weapons.get(side):
			f.weapons[side].remove_voxels(spec.worn[side])
	# And the plates his armour came in without.
	if spec.get("loadout") is Dictionary and spec.loadout.get("armor_wear") is Dictionary:
		f.apply_armor_wear(spec.loadout.armor_wear)
	if role == "guest":
		f.make_puppet()
	elif spec.kind == "remote" or spec.kind == "local":
		# A player bleeds slower than the bots, time enough to see the wound and answer it.
		f.mods.bleed = float(f.mods.get("bleed", 1.0)) * PLAYER_BLEED
		f.spare = _may_spare
	var e := {"id": spec.get("id", next_id), "f": f, "kind": spec.kind, "team": spec.team, "peer": spec.get("peer", -1), "boss": spec.get("boss", false), "spec": spec}
	next_id = maxi(next_id, e.id) + 1
	if spec.kind == "bot":
		e.bot = Bot.new(f, clampf(float(spec.get("diff", 0.7)), 0.1, 1.0), spec.get("personality", "standard"), rng.randi())
	f.gravity = dec.gravity
	_register(e)
	if (spec.kind == "remote" or spec.kind == "local") and not headless:
		_name_tag(f, String(spec.get("name", "")))
	return e

## A player's name floats over his head, in the yard and in the fight alike (not over your own,
## which the camera rides behind; the host's and the guests' over theirs).
func _name_tag(f, text: String) -> void:
	if text == "" or tags.has(f):
		return
	var l := Label3D.new()
	l.text = text
	l.font = UIStyle.serif(2)
	l.font_size = 48
	l.pixel_size = 0.004
	l.outline_size = 12
	l.modulate = Color(0.96, 0.9, 0.72)
	l.outline_modulate = Color(0.1, 0.06, 0.03, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 2
	l.visible = false   # shown once it has a head to float over (_update_tags)
	add_child(l)
	tags[f] = l

func _update_tags() -> void:
	for f in tags.keys():
		var l: Label3D = tags[f]
		if not is_instance_valid(f):
			if is_instance_valid(l):
				l.queue_free()
			tags.erase(f)
			continue
		var own: bool = me != null and me.f == f and not attract
		l.visible = f.alive and not own
		if not l.visible:
			continue
		var top: VoxelPart = f.head if f.get("head") and is_instance_valid(f.head) and not f.head.severed else f.torso
		l.global_position = top.global_position + Vector3(0, top.half_ext.y + 0.3 * float(f.S), 0)

## The body turns after the eyes, not in jumps with every twitch of the mouse: it closes most
## of the gap in a few steps, never faster than a fighter can wheel round, and the arms and the
## blade (aimed in the body's frame) come round with it.
static func ease_yaw(cur: float, to: float, dt: float) -> float:
	var d := wrapf(to - cur, -PI, PI)
	return cur + clampf(d * minf(1.0, dt * 16.0), -11.0 * dt, 11.0 * dt)

func spawn_beast(spec: Dictionary):
	var b := Beast.new()
	add_child(b)
	b.build_beast(spec.beast, spec.pos, spec.get("yaw", 0.0), {"name": spec.get("name", Data.beasts.get(spec.beast, {}).get("name", spec.beast)), "scale": spec.scale if spec.get("scale") != null else Data.beasts.get(spec.beast, {}).get("scale", 1.0), "boss": spec.get("boss", false), "team": spec.team, "seed": rng.randi()})
	b.gravity = dec.gravity
	b.on_breath = _breath
	b.on_stomp = _stomp
	b.on_venom = _venom
	b.on_strike = func(bb, p):
		sfx("whoosh", p.global_position, 0.6)
		# (A quick pecker like the ostrich is not to cry out at every peck.)
		if time - float(bb.get_meta("voice_t", -9.0)) > (3.0 if bb.species == "ostrich" else 0.9):
			bb.set_meta("voice_t", time)
			say(bb, Voices.beast_call(bb.species), 0.9, "call")
	b.on_roar = func(bb):
		bb.set_meta("voice_t", time)
		say(bb, Voices.beast_call(bb.species), 1.2, "call")
		feed.emit(("%s beats its chest and roars!" if bb.species == "gorilla" else "%s trumpets and charges!") % bb.display_name)
	b.on_thump = func(bb):
		sfx("thump", bb.torso.global_position, 1.0)
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
	e.f.guts_spilled.connect(_on_guts_spilled)
	if e.f.has_signal("note"):
		e.f.note.connect(func(f, text):
			if me and f == me.f:
				feed.emit(text))
	if e.f.has_signal("raged"):
		e.f.raged.connect(func(f):
			feed.emit("%s's eye is put out: he goes berserk!" % f.display_name)
			say(f, "scream", 1.6, "rage"))
	e.f.guts_pulled.connect(func(f, g):
		var en = entity_of(f)
		if role == "host" and en:
			Net.send_all("gutp", {"id": en.id, "g": g}))
	if role == "host":
		Net.send_all("spawn", _spawn_msg(e))

## A guest who joins the room while it is in the yard: he gets the world as it stands, then a
## fighter of his own by the gate (its spawn reaches everyone, him included).
func add_peer(id: int, p: Dictionary) -> void:
	if role != "host":
		return
	Net.send_to(id, "start", {"mode": mode, "stage": stage, "coop": coop, "decrees": decrees.map(func(d): return d.id), "hazards": hazard_specs})
	for e in entities:
		if is_instance_valid(e.f):
			Net.send_to(id, "spawn", _spawn_msg(e))
	var pe = spawn_fighter({"kind": "remote", "peer": id, "name": p.name, "loadout": p.get("loadout", {"main": "gladius"}), "team": 0, "pos": Vector3(1.2 * entities.size() - 3.0, 0, -6), "yaw": 0.0, "skin": p.get("skin"), "body": Body.sanitize(p.get("body", {})) if mode == "yard" or mode == "campaign" else null})
	pe.inventory = Net.sanitize_kit(p.get("kit", {}))
	players_count = humans().size()
	feed.emit("%s came into the yard" % p.name)
	_send_yard_next()

## The board by the gate: the next fight, as many as the party is now (a friend more, a friend
## less, the bout is sized again), on the host and on every guest's board.
func _send_yard_next() -> void:
	if yard == null or role != "host":
		return
	yard.set_next(YardPlay.next_fight(humans().size()))
	if Net.active():
		Net.send_all("yard_next", {"t": yard.next_text})

## A guest who left: his fighter goes, here and on every guest's screen.
func drop_peer(id: int) -> void:
	for e in entities.duplicate():
		if e.kind == "remote" and int(e.get("peer", -1)) == id and is_instance_valid(e.f):
			feed.emit("%s left" % e.f.display_name)
			_remove_entity(e)
			if role == "host":
				Net.send_all("despawn", {"id": e.id})
	players_count = humans().size()
	_send_yard_next()

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
## They come in through the gates (east and west, by turns), never out of thin air at your
## back: each a little way inside the gate it came through, the ones after it behind it.
## The campaign's foes come up the ladder by what they carry: each bout a weapon picked at
## random from those its stage can afford (by what it can do in a fight, Arms.power_price), from
## a dagger or a fish at the first bout to a warhammer late on; their skill, and their armour,
## grow with the bouts too. The stage's own men keep their loadout once it is within the budget.
const LADDER_WEAPONS := ["dagger", "fish", "chicken", "javelin", "plank", "gladius", "hammer", "axe", "spear", "trident", "chair", "longsword", "mace", "executionerAxe", "zweihander", "warhammer"]
static var _ladder_power := {}
static func weapon_budget(st: int) -> float:
	return 90.0 + 25.0 * float(maxi(1, st) - 1)

static func ladder_power(key: String) -> int:
	if not _ladder_power.has(key):
		_ladder_power[key] = Arms.power_price(Data.preset(key))
	return int(_ladder_power[key])

## A foe's main weapon for campaign bout `st`: from its own loadouts if one is within the bout's
## budget, else at random from the ladder's weapons that are (and not far below it, so later
## foes do not come with daggers).
static func ladder_weapon(st: int, own: Array, rng_: RandomNumberGenerator) -> String:
	var cap := weapon_budget(st)
	var fit := own.filter(func(k): return k != "" and ladder_power(k) <= cap)
	if not fit.is_empty() and rng_.randf() < 0.5:
		return fit[rng_.randi_range(0, fit.size() - 1)]
	var pool := LADDER_WEAPONS.filter(func(k): return ladder_power(k) <= cap and ladder_power(k) >= cap * 0.4)
	if pool.is_empty():
		# Past the dearest weapon's worth (late in the campaign) the budget buys anything: the
		# strongest few, never back down to a dagger.
		var by := LADDER_WEAPONS.duplicate()
		by.sort_custom(func(a, b): return ladder_power(a) > ladder_power(b))
		pool = by.filter(func(k): return ladder_power(k) <= cap).slice(0, 4)
		if pool.is_empty():
			pool = ["dagger"]
	return pool[rng_.randi_range(0, pool.size() - 1)]

## How much of a foe's skill (and how far up its armour) the campaign's bout `st` brings out.
static func ladder_skill(st: int) -> float:
	# A slow climb: the foes fight at their best from the 24th bout, not the ninth (their
	# toughness and weapons keep rising the whole way).
	return clampf(0.6 + 0.4 * float(st - 1) / 23.0, 0.6, 1.0)

func enemy_spec(en: Dictionary, i: int, total: int) -> Dictionary:
	var gx := 1.0 if i % 2 == 0 else -1.0
	var row := i / 2
	var big: bool = en.has("beast") or en.get("boss", false)
	var depth := (3.2 if big else 1.6) + row * 1.1
	var pos := Vector3(gx * (Arena.RADIUS - depth), 0.1, (0.6 if row % 2 else -0.6) if total > 2 else 0.0)
	if en.has("beast"):
		var sc: float = float(en.scale) if en.get("scale") != null else float(Data.beasts.get(en.beast, {}).get("scale", 1.0))
		return {"kind": "beast", "beast": en.beast, "scale": sc * (1.0 + LAP_SCALE * (lap - 1)), "name": en.get("name", Data.beasts.get(en.beast, {}).get("name", en.beast)), "boss": en.get("boss", false), "team": ENEMY_TEAM, "pos": pos, "yaw": atan2(-pos.x, -pos.z)}
	var t := Data.enemy_type(en.get("e", "recruit"))
	var g: Dictionary = en.get("gear", {}) if en.get("gear") else {}
	var los: Array = t.get("loadouts", [{"main": "gladius"}])
	var lo: Dictionary = los[rng.randi_range(0, los.size() - 1)]
	var main: Dictionary = temper(Data.preset(lo.main), g.get("temper")) if lo.get("main") else {}
	var off: Dictionary = temper(Data.preset(lo.off), g.get("temper")) if lo.get("off") else {}
	# Later in the campaign foes come with coated weapons; the fire-thrower's always burns.
	var coat := "fire" if en.get("e", "") == "pyro" else ""
	if coat == "" and mode == "campaign" and stage >= 12 and rng.randf() < clampf((stage - 10) * 0.025, 0.0, 0.45):
		coat = Arms.COATINGS[rng.randi_range(0, Arms.COATINGS.size() - 1)]
	# A boss come round again (the tables' second time through) is not the same man again:
	# steel on him where the first time was bronze and iron, and his weapon coated.
	var returning: bool = en.get("boss", false) and mode == "campaign" and stage > int(Data.campaign.get("bosses", []).size()) * int(Data.campaign.get("bossEvery", 4))
	if returning:
		coat = RETURN_COAT.get(String(en.get("e", "")), "fire")
	# (Coatings are no longer sold at the smith, so Arms.can_upgrade says no to one; a foe's
	# weapon is coated straight, as a weapon coated before keeps its coating.)
	if coat != "" and not main.is_empty() and main.get("kind", "weapon") != "shield":
		main = main.duplicate(true)
		main.imbue = coat
	if en.get("loadout") is String and en.loadout != "":
		main = Data.preset(en.loadout)
		off = {}
	var ladder: bool = mode == "campaign" and not en.get("boss", false) and not (en.get("loadout") is String and en.loadout != "")
	if ladder and not main.is_empty() and lo.get("main"):
		var own: Array = los.map(func(x): return String(x.get("main", "")))
		var key := ladder_weapon(stage, own, rng)
		if key != String(lo.main):
			main = temper(Data.preset(key), g.get("temper"))
			# (A shield goes with its own man's loadout; from the fourth bout on.)
			if stage < 4 or key not in own:
				off = {}
		elif stage < 4:
			off = {}
	var armor: Array = lo.get("armor", []).duplicate()
	for x in g.get("armor", []):
		if not armor.has(x):
			armor.append(x)
	if ladder and stage <= 2:
		armor.clear()   # the first bouts' men fight in their tunics
	if returning:
		armor = armor.filter(func(x): return not RETURN_ARMOR_OFF.has(x)) + RETURN_ARMOR
	var names: Array = t.get("names", ["Gladiator"])
	var nm: String = en.get("name", names[rng.randi_range(0, names.size() - 1)])
	if g.get("rank") and not en.get("boss", false):
		nm = "%s %s" % [g.rank, nm]
	var mods: Dictionary = t.get("mods", {}).duplicate()
	for k in g.get("mods", {}):
		mods[k] = g.mods[k]
	for k in en.get("mods", {}):
		mods[k] = en.mods[k]
	if lap > 1:
		mods["toughness"] = float(mods.get("toughness", 1.0)) * (1.0 + LAP_TOUGH * (lap - 1))
		mods["strength"] = float(mods.get("strength", 1.0)) * (1.0 + 0.1 * (lap - 1))
	var spec := {"kind": "bot", "name": nm, "loadout": {"main": main, "off": off, "armor": armor}, "team": ENEMY_TEAM, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "mods": mods,
		"personality": t.get("personality", "standard"), "diff": float(t.get("diff", 0.8)) * float(g.get("diff", 1.0)) * (ladder_skill(stage) if ladder else 1.0), "color": t.get("color"), "boss": en.get("boss", false)}
	# The giants of myth look the part (MonsterLook): one eye, a bull's head, tusks, a crown.
	var look := MonsterLook.look_of(String(en.get("e", "")))
	if look != "":
		mods["look"] = look
		mods["voice"] = String(en.e)
		spec["skin"] = MonsterLook.SKIN[look]
		for id in MonsterLook.WEARS[look]:
			if not armor.has(id):
				armor.append(id)
	return spec

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
	_open_gates(list.size())

## The gates swing open as a wave comes in, with a blast of the horn.
func _open_gates(n: int) -> void:
	if arena and arena.has_method("open_gate"):
		arena.open_gate(1)
		if n > 1:
			arena.open_gate(-1)
	if n > 0:
		sfx("horn", Vector3(Arena.RADIUS, 2.0, 0), 0.6)

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
	_open_gates(list.size())
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

## Something the local player did that a mission may count (yard.js missionEvent).
func mission_event(kind: String, n := 1) -> void:
	if mode == "yard" or mode == "training" or role == "guest":
		return
	mcount[kind] = int(mcount.get(kind, 0)) + n

func circus_status() -> String:
	var head := "Day %s · bout %d" % [["I", "II", "III", "IV", "V", "VI", "VII"][clampi(int(circus.get("day", 0)), 0, 6)], int(circus.get("bout_index", 0)) + 1]
	var s := rules.status() if rules else ""
	return head + ((" · " + s) if s != "" else "")

## A sparring partner told not to fight (game.js trainingBehaviour): a dummy stands and faces
## you, a walker moves about without ever swinging, a defender keeps the shield up, sword still.
func _training_calm(e: Dictionary, inp: Dictionary, tgt) -> Dictionary:
	var calm := inp.duplicate()
	for k in ["power", "kick", "shove", "throw", "grab", "jump", "trip"]:
		calm[k] = false
	calm.thrust = 0.0
	calm.offThrust = 0.0
	calm.main = {"x": 0.1, "y": 0.25}
	if tgt:
		calm.faceAt = tgt.f.torso.global_position
	match String(e.training):
		"still":
			calm.mx = 0.0; calm.mz = 0.0; calm.sprint = false
		"defends":
			calm.off = {"x": -0.2, "y": 0.35}
	return calm

## In training you cannot die if you chose so: blood refills and nothing bleeds (game.js trainingTick).
func _training_tick(dt: float) -> void:
	if not training.get("immortal", true) or me == null or not is_instance_valid(me.f):
		return
	var f: Fighter = me.f
	f.blood = minf(100.0, f.blood + 40.0 * dt)
	for p in f.parts:
		p.bleed = 0.0
		p.artery = 0.0

const TRAINING_BOSSES := ["cyclops", "giant", "minotaur", "titan"]
func _spawn_training() -> void:
	var who: String = training.get("enemy", "gladiator")
	for i in int(training.get("count", 1)):
		var pos := Vector3(i * 1.5, 0.1, 5.0)
		if who == "none":
			break
		var e
		var skill := float(training.get("difficulty", 0.5))
		if Data.beasts.has(who):
			e = spawn_beast({"beast": who, "team": ENEMY_TEAM, "pos": pos, "yaw": PI})
			e.f.skill = skill
		elif who.begins_with("foe:"):
			# A campaign foe as he comes in the campaign, his own arms and size: the giant, the
			# Cyclops, a troll, an archer.
			var key := who.trim_prefix("foe:")
			var spec := enemy_spec({"e": key, "boss": TRAINING_BOSSES.has(key)}, 0, 1)
			spec.pos = Vector3(i * 3.0, 0.1, 6.0 if TRAINING_BOSSES.has(key) else 5.0)
			spec.yaw = PI
			spec.diff = skill   # the slider, not the campaign's stage
			e = spawn_fighter(spec)
		else:
			var w: String = training.get("weapon", "gladius")
			if w == "random":
				w = ["gladius", "axe", "spear", "mace"][rng.randi_range(0, 3)]
			e = spawn_fighter({"kind": "bot", "name": "Sparring partner", "loadout": {"main": "" if w == "fists" else w, "off": ""}, "team": ENEMY_TEAM, "pos": pos, "yaw": PI, "diff": skill, "personality": "archer" if w == "bow" or w == "crossbow" else "standard"})
		if e:
			e.training = String(training.get("behaviour", "fights"))

# ---------- The loop ----------

func _physics_process(dt: float) -> void:
	if social == null:
		return   # not set up (a Match made only to read its tables)
	time += dt
	tick += 1
	if hero and is_instance_valid(hero) and hero.get_meta("frozen", false):
		pass
	elif hero and is_instance_valid(hero):
		if hero_still_t > 0.0:
			hero_still_t -= dt
			if hero_still_t <= 0.0:
				_freeze_hero(true)
		hero.control(dt, hero_inp)
		# He holds his mark: a soft spring on the torso, so the balance never walks him off.
		var d: Vector3 = hero.get_meta("anchor") - hero.torso.global_position
		var v: Vector3 = hero.torso.linear_velocity
		hero.torso.apply_central_force(Vector3(d.x * 600.0 - v.x * 60.0, 0, d.z * 600.0 - v.z * 60.0) * hero.torso.mass)
	if role == "guest":
		_update_streams(dt)
		throwables.update(dt)
		for e in entities:
			if is_instance_valid(e.f) and e.f.parts.any(func(p): return not p.spots.is_empty()):
				Fire.tick(e.f, dt, false)
		_drive_puppets()
		if yard:
			yard.update(dt, last_local_inp)
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
					inp = _player_input(f, dt)
					if inp.has("look"):
						f.yaw = ease_yaw(f.yaw, float(inp.look.yaw), dt)
			"remote":
				inp = Net.input_of(e.peer)
				if inp.has("look"):
					f.yaw = ease_yaw(f.yaw, float(inp.look.yaw), dt)
					# A guest sends his own crosshair; an older guest without one thrusts along his eyes.
					if not (inp.get("aimAt") is Vector3) and (float(inp.get("thrust", 0.0)) > 0.0 or float(inp.get("offThrust", 0.0)) > 0.0):
						var lk: Dictionary = inp.look
						inp.aimAt = f.head.global_position + Vector3(sin(float(lk.yaw)) * cos(float(lk.pitch)), sin(float(lk.pitch)), cos(float(lk.yaw)) * cos(float(lk.pitch))) * 6.0
			"bot" when not f.alive:
				pass   # the dead think no more (whatever a bot chose, his body takes no orders now)
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
				if e.get("training", "fights") != "fights":
					inp = _training_calm(e, inp, tgt)
			"beast":
				var tb = nearest_enemy(e)
				f.target = tb.f if tb else null
				if e.get("training", "fights") != "fights":
					f.target = null   # a beast told not to fight stands its ground
				# A beast on the hunt gives voice now and then, between its strikes.
				elif f.target and f.alive and time - float(f.get_meta("voice_t", -9.0)) > float(f.get_meta("voice_gap", 6.0)):
					f.set_meta("voice_t", time)
					# A pack does not all give voice at once: each of them the rarer the more of
					# its kind are about (a run of rats screeching was a din).
					var kin := entities.filter(func(o): return o.kind == "beast" and is_instance_valid(o.f) and o.f.alive and o.f.get("species") == f.species).size()
					f.set_meta("voice_gap", rng.randf_range(6.0, 14.0) * maxf(1.0, kin))
					say(f, Voices.beast_call(f.species), 0.7, "call")
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
			e.last_aim = inp.get("aimAt")
			e.last_aim_from = inp.get("aimFrom")
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
	if yard:
		yard.update(dt, last_local_inp)
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
	_update_streams(dt)
	throwables.update(dt)
	throwables.update_shooters(dt)
	_materials_tick(dt)
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
		# One fighter to a message: each fits in one packet (a whole snapshot was split into
		# fragments, and one lost fragment lost all of it).
		# A full room (many guests or many fighters): the players' fighters at the full rate, the
		# enemies every other time, which halves what goes up the host's line.
		var full := Net.peers.size() >= 4 or entities.size() > 10
		var odd := (tick / SNAP_EVERY) % 2 == 1
		for row in snapshot(false):
			if full and odd:
				var re = entity_by_id(int(row[0]))
				if re != null and re.kind != "remote" and re.kind != "local":
					continue
			Net.send_all("snap", [row], false)
	_check_round(dt)

## The player's own hands on his fighter: the same for the host's player and for a guest on his
## own machine (whose input then goes to the host): the bow's aim mode and sway, E by a keeper,
## and the crosshair his camera looks along for a bow, a thrust, a throw or a pot.
var faced_for = null

func _player_input(f, dt: float) -> Dictionary:
	var shooter := _shooter_of(f)
	# A new fighter of ours (a bout starting, a respawn): the camera starts where he faces,
	# not at a fixed angle that would turn him round with his back to the foe.
	if input and f != faced_for:
		faced_for = f
		input.look_yaw = f.yaw
		input.look_pitch = 0.0
	if input:
		input.aiming = shooter != null or input.held("throw")
		_bow_sway(f, shooter, dt)
	var inp: Dictionary = input.sample(dt) if input else {}
	if yard and inp.get("kick", false) and Yard.station_at(f.torso.global_position) != "":
		inp.kick = false
		inp.talk = true
	# (A man held in the Hand of Jupiter hangs where the crosshair points: the aim goes every
	# step for as long as the grip can last, from the host's own player and a guest alike.)
	if int(inp.get("useItem", -1)) >= 0 and me and Throwables.hotbar_of(me.get("inventory", {})).slice(int(inp.useItem), int(inp.useItem) + 1).has("telekinesis"):
		mind_aim_until = time + Social.MIND_T + 0.5
	if input:
		input.wheel_to_grip = time < mind_aim_until   # the wheel draws the held man in and out, not the blade round
	if cam and (shooter != null or int(inp.get("useItem", -1)) >= 0 or float(inp.get("charging", 0.0)) > 0.0 or inp.get("throw", false) or float(inp.get("thrust", 0.0)) > 0.0 or float(inp.get("offThrust", 0.0)) > 0.0 or time < mind_aim_until):
		inp.aimAt = aim_point(f)
		inp.aimFrom = aim_from
	last_local_inp = inp
	return inp

## A guest's fighter played by a bot on the guest's side: it reads the host's snapshots like a
## player would and sends inputs back, so two windows (or two processes) fight without hands.
func _guest_bot_input(dt: float) -> Dictionary:
	if me == null or not is_instance_valid(me.f):
		return {}
	if guest_bot == null or guest_bot.c != me.f:
		guest_bot = Bot.new(me.f, 0.9, "standard", 99)
	var tgt = nearest_enemy(me)
	var inp: Dictionary = guest_bot.update(dt, tgt.f if tgt else null, _world_of(me))
	var yaw: float = me.f.yaw
	if tgt:
		var d: Vector3 = tgt.f.torso.global_position - me.f.torso.global_position
		yaw = atan2(d.x, d.z)
	inp.look = {"yaw": yaw, "pitch": 0.0}
	return inp

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
			p.artery = 0.0
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
	# What breathes fire does not burn (nor what spits venom melt in it): a dragon walking through
	# its own burning trail was set alight, and stood in a cloud of its own flames.
	if c is Beast and c.sp.get("breath") == ("venom" if kind == "acid" else kind):
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
	if not was and kind != "frost":   # (frostbite is told by the sapphire that brings it)
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
## A kill (or a man beaten senseless, out of the fight) for the kill cam; the host tells his
## guests, who tape it on their own kill cams.
func _tape_kill(f, cause: String) -> void:
	var lh: Dictionary = last_hit_of.get(f, {})
	if killcam and role != "guest":   # (a guest tapes the host's word on it: "kc")
		killcam.on_death(f, cause, lh)
	if role == "host":
		var ve = _entity_of(f)
		var ke = _entity_of(f.last_attacker) if f.get("last_attacker") else null
		var w = lh.get("weapon")
		if ve != null:
			Net.send_all("kc", {"v": ve.id, "k": ke.id if ke != null else -1, "cause": cause, "J": float(lh.get("J", 0.0)),
				"w": String(w.design.get("name", "")) if w != null and is_instance_valid(w) else "", "th": w != null and is_instance_valid(w) and w.holder == null,
				"ago": time - float(lh.get("at", time))})

func _entity_of(f) -> Variant:
	for e in entities:
		if e.f == f:
			return e
	return null

## After every round won and before the next: the best kill of that round, the same on every
## screen online (the host names it: "kcr"), then a fresh tape for the next round.
func _round_replay() -> void:
	if killcam == null or role == "guest":
		return
	var left := killcam.tape_left()
	if left > 0.0:
		await get_tree().create_timer(left + 0.05).timeout
	var show := killcam.has_clip()
	if role == "host":
		var ve = _entity_of(killcam.best.get("victim")) if show else null
		Net.send_all("kcr", {"kc_v": ve.id if ve != null else -1})
	if show:
		await killcam.play(func(): pass, true)
	killcam.reset()

func _guest_round_replay(data: Dictionary) -> void:
	if killcam == null:
		return
	var left := killcam.tape_left()
	if left > 0.0:
		await get_tree().create_timer(left + 0.05).timeout
	killcam.has_clip()
	var ve = entity_by_id(int(data.get("kc_v", -1)))
	if ve != null and is_instance_valid(ve.f) and killcam.choose(ve.f):
		await killcam.play(func(): pass, true)
	killcam.reset()

## The end of the fight on a guest: his own kill cam's best kill, then the result.
func guest_end(data: Dictionary) -> void:
	if over:
		return
	over = true
	banner.emit(str(data.get("text", "")), str(data.get("sub", "")))
	if killcam:
		var left := killcam.tape_left()
		if left > 0.0:
			await get_tree().create_timer(left + 0.05).timeout
		var show := killcam.has_clip()
		if data.has("kc_v"):
			# The host's pick, the same kill for everyone (none, if his tape had none worth it).
			var ve = entity_by_id(int(data.kc_v))
			show = ve != null and is_instance_valid(ve.f) and killcam.choose(ve.f)
		if show:
			await killcam.play(func(): pass)
	finished.emit({"won": bool(data.get("won", false)), "stage": stage, "pay": int(data.get("pay", 0))})

func guest_message(type: String, data) -> void:
	match type:
		"yard_next":
			if yard and data is Dictionary:
				yard.set_next(str(data.get("t", "")))
		"kcr":
			if data is Dictionary:
				_guest_round_replay(data)
		"kc":
			if killcam and data is Dictionary:
				var ve = entity_by_id(int(data.get("v", -1)))
				var ke = entity_by_id(int(data.get("k", -1)))
				if ve != null and is_instance_valid(ve.f):
					killcam.on_death(ve.f, str(data.get("cause", "")).left(16), {"J": clampf(float(data.get("J", 0.0)), 0.0, 500.0), "at": time - clampf(float(data.get("ago", 0.0)), 0.0, 10.0)},
						ke.f if ke != null and is_instance_valid(ke.f) else null, str(data.get("w", "")).left(32).to_lower(), bool(data.get("th", false)))
		"gutp":
			# Another length pulled out of a belly already open (sanitized like "guts").
			var e = entity_by_id(int(data.get("id", -1))) if data is Dictionary else null
			if e == null or not (e.f is Fighter) or not e.f.guts_out or not (data.get("g") is Array):
				return
			var n: int = e.f.torso.fx.size()
			var g: Array = (data.g as Array).slice(0, GutRope.LINK_VOX).map(func(i): return clampi(int(i), 0, n - 1))
			if e.f.gut_rope and is_instance_valid(e.f.gut_rope):
				e.f.gut_rope.pull(g)
			else:
				e.f.torso.remove_voxels(g, true, false)
		"guts":
			# Sanitized: a known fighter, at most the chain's links of the torso's own voxels.
			var e = entity_by_id(int(data.get("id", -1))) if data is Dictionary else null
			if e == null or not (e.f is Fighter) or e.f.guts_out or not (data.get("g") is Array) or not (data.get("p") is Array) or not (data.get("o") is Array) or data.p.size() != 3 or data.o.size() != 3:
				return
			var n: int = e.f.torso.fx.size()
			var groups := []
			for g in (data.g as Array).slice(0, GutRope.FIRST_LINKS):
				if g is Array:
					groups.append((g as Array).slice(0, GutRope.LINK_VOX).map(func(i): return clampi(int(i), 0, n - 1)))
			var o := Vector3(float(data.o[0]), float(data.o[1]), float(data.o[2]))
			e.f.spill_guts(groups, Vector3(float(data.p[0]), float(data.p[1]), float(data.p[2])), o.normalized() if o.length_squared() > 1e-6 else Vector3.FORWARD)
		"wloose":
			var e = entity_by_id(int(data.get("id", -1))) if data is Dictionary else null
			if e and (data.side == "R" or data.side == "L") and e.f.weapons.get(data.side):
				var w: Weapon = e.f.release(data.side)
				if w:
					w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					w.freeze = true   # the host flies it; here it is drawn where he says
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
						_puppet_to(lw, _xf(r, 1))
				hazards.apply_snapshot(data.get("h", []))
		"isnap":
			if data is Array:
				items.apply_snapshot(data)
		"zone":
			if data is Dictionary and Throwables.ZONE_COLORS.has(str(data.get("type"))) and data.get("p") is Array:
				throwables.add_zone(str(data.type), Vector3(data.p[0], data.p[1], data.p[2]), clampf(float(data.r), 0.1, 5.0), clampf(float(data.t), 0.0, 30.0))
		"splash":
			# The host's firebomb: the same drops fly here (for the eye; the host's burn).
			if data is Dictionary and data.get("p") is Array and (data.p as Array).size() == 3 and data.get("d") is Array and (data.d as Array).size() == 3:
				throwables.splash_burning(Vector3(float(data.p[0]), float(data.p[1]), float(data.p[2])), Vector3(float(data.d[0]), float(data.d[1]), float(data.d[2])), clampi(int(data.get("n", 48)), 1, 80), null, null, null, "acid" if str(data.get("k")) == "acid" else "fire", int(data.get("s", 0)), true)
		"wet":
			if data is Dictionary and data.get("c") is Array:
				throwables.set_wet(data.c)
		"breath":
			if data is Dictionary and data.get("d") is Array and (data.d as Array).size() == 3:
				var eb = entity_by_id(int(data.get("id", -1)))
				var bd := Vector3(float(data.d[0]), float(data.d[1]), float(data.d[2]))
				if eb and eb.f is Beast and bd.length_squared() > 0.01:
					breath_at(eb.f, "venom" if data.get("kind") == "venom" else "fire", bd.normalized(), clampf(float(data.get("r", 6.0)), 1.0, 30.0), 0.9)
					var mk: Vector3 = eb.f.mouth_point() + bd.normalized() * 4.0
					if data.get("m") is Array and (data.m as Array).size() == 3:
						mk = Vector3(float(data.m[0]), float(data.m[1]), float(data.m[2]))
					stream(eb.f, "venom" if data.get("kind") == "venom" else "fire", mk, clampf(float(data.get("r", 6.0)), 1.0, 30.0), 0.9)
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
						hit_fx(fp, fd, clampf(float(data.get("J", 5.0)), 0.0, 80.0), str(data.get("t", "blunt")), bool(data.get("s", false)), bool(data.get("a", false)))
					"clang":
						fx.burst("sparks", fp, int(clampf(float(data.get("J", 5.0)) * 3.0, 6.0, 90.0)))
					"pool":
						fx.pool(fp, 1.4 * clampf(float(data.get("s", 1.0)), 0.3, 4.0), 8.0)
					"boom":
						_boom_fx(fp, clampi(int(data.get("n", 4)), 1, 60))
					"boing":
						sfx("boing", fp, 0.8)
					"stomp":
						_stomp_fx(fp, clampf(float(data.get("n", 27)) / 10.0, 0.5, 5.0))
					"voice":
						if Sfx and not headless and Voices.KINDS.has(str(data.get("v"))):
							var vf := str(data.get("f", ""))
							if not vf.is_valid_identifier():
								vf = ""
							Sfx.voice(str(data.v), fp, clampf(float(data.get("g", 1.0)), 0.0, 1.5), clampf(float(data.get("h", 1.0)), 0.3, 3.0), vf)

func nearest_enemy(e: Dictionary):
	var best = null
	var bd := INF
	var p: Vector3 = e.f.torso.global_position
	var cands := []
	for o in entities:
		if o.team != e.team and o.f.alive and not (o.kind == "beast" and e.kind == "beast" and not o.get("harmless", false)) and not (o.get("harmless", false) and e.kind != "beast"):
			cands.append(o)
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

## A character's voice from his mouth (Voices): heard here, and by the guests.
func say(f, kind: String, gain := 1.0, event := "") -> void:
	if kind == "" or f == null or not is_instance_valid(f):
		return
	var at: Vector3 = f.head.global_position if f.get("head") and not f.head.severed else f.torso.global_position
	var pitch := Voices.pitch_of(f)
	var file := Voices.file_key(f, event) if event != "" else ""
	# A rendered voice is already the animal's own depth; only the odd-sized get a shift.
	var fp := clampf(pitch / Voices.pitch_of_species(f), 0.7, 1.4) if file != "" else pitch
	if Sfx and not headless:
		Sfx.voice(kind, at, gain, fp, file)
	if role == "host":
		Net.send_all("fx", {"k": "voice", "p": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)], "v": kind, "g": snappedf(gain, 0.01), "h": snappedf(fp, 0.01), "f": file}, false)

## The crowd's favour (filled in by the crowd module when there is one).
func crowd_add(f, n: float, why: String) -> void:
	if spectacle and role != "guest":
		spectacle.add(f, n, why)

func has_gadget(e: Dictionary, id: String) -> bool:
	return e.get("gadgets", []).has(id)

## Blood, sparks and marks for a blow at `p` (host and guests alike): a cut sprays, a thrust
## spurts, a blunt blow bruises with little blood; a limb coming off opens the floodgates.
func hit_fx(p: Vector3, dir: Vector3, J: float, type: String, severed := false, artery := false) -> void:
	if headless:
		return
	if artery and not dec.confetti:
		# A cut artery sprays: a jet of blood back out of the wound, and a splash on the sand.
		fx.burst("spurt", p, 90, (-dir + Vector3(0, 0.5, 0)).normalized(), 1.3)
		fx.mark("blood", Vector3(p.x - dir.x * 0.6, 0, p.z - dir.z * 0.6), 0.6)
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
	if not doctor_wait.is_empty():
		# Nobody fights on while a man is at the physician (a guest who never answers is let go).
		doctor_t += dt
		if doctor_t < 150.0:
			return
		doctor_wait.clear()
	if between > 0.0:
		between -= dt
		if between <= 0.0:
			_spawn_round(round + 1)
			_banner("Round %d of 3" % (round + 1), "")
		return
	# Beaten is beaten: dead, or out cold on the sand and never getting up again, or down on
	# the sand unable to stand (crawling at most) for UNFIT_OUT seconds.
	var alive_h := humans().filter(func(x): return not x.f.is_beaten() and x.f.dying <= 0.0 and not _unfit(x, dt))
	_lift_tick(dt)
	var alive_e := enemies().filter(func(x): return not x.get("beaten", false) and not x.f.is_beaten() and not _unfit(x, dt))
	# Once the round is called (every foe dead or out of it), a foe it counted beaten stays
	# beaten: he does not get up and fight on after its kill cam. (Before that, a man who comes
	# round gets up and fights again.)
	for x in (enemies() if alive_e.is_empty() and mode != "training" and mode != "yard" else []):
		if not x.get("beaten", false) and is_instance_valid(x.f) and x.f.alive:
			x.beaten = true
			x.erase("bot")
			x.drive = func(_e): return {"limp": true}
	# Beaten without dying (out cold, or down for good): on the kill cam's tape as a kill.
	for x in entities:
		if x.f.alive and not x.get("taped", false) and not alive_h.has(x) and not alive_e.has(x) and (x.team == ENEMY_TEAM or humans().has(x)):
			x.taped = true
			_tape_kill(x.f, "out")
	if mode == "training":
		for e in enemies():
			if not e.f.alive and not e.get("respawned", false) and training.get("respawn", true):
				e.respawned = true
				var spec: Dictionary = e.spec.duplicate()
				spec.erase("id")
				var ne = spawn_beast(spec) if e.kind == "beast" else spawn_fighter(spec)
				if ne:
					ne.training = e.get("training", "fights")
		_training_tick(dt)
		return
	if mode == "yard":
		# Nobody stays dead in the yard: a man killed there (a friend's blade, a bad fall) is
		# back on his feet by the gate three seconds later, whole, with his kit.
		for e in humans():
			if not e.f.alive:
				e.dead_t = float(e.get("dead_t", 0.0)) + dt
				if e.dead_t >= YARD_RESPAWN:
					respawn_player(e)
		return
	if mode == "circus":
		_check_circus(alive_h, alive_e)
		return
	if alive_h.is_empty():
		var crawled := humans().any(func(x): return x.f.alive)
		_end(false, "You can fight no more" if crawled else "You fall", ("None of you can stand. " if crawled else "") + ("The crowd moves on. Your campaign ends here: the next begins at the first bout." if mode == "campaign" else "The crowd moves on."))
		return
	if alive_e.is_empty():
		if mode == "campaign":
			round_pay += int(round(float(stage_info.get("roundPay", 10)) * PAY_SCALE))
			if round + 1 < int(stage_info.get("rounds", []).size()):
				between = 2.5
				feed.emit("Round %d won" % (round + 1))
				if role != "guest":
					_round_wounds()
				_round_replay()
				return
			var base := int(round(float(stage_info.get("stagePay", 30)) * PAY_SCALE))
			var crowd := int(round(base * CROWD_BONUS * spectacle.heat(humans())))
			var pay := base + round_pay + crowd
			var purse := ("%d denarii to the party's purse" if players_count > 1 else "%d denarii") % pay
			if crowd > 0:
				purse += ", %d of them the crowd's" % crowd
			_end(true, ("Bout %d won" if stage_info.get("duel", false) else "Stage %d cleared") % stage, purse + ". Back to the yard: spend, mend, gear up.", pay)
		else:
			_end(true, "Victory", "")

## A party: a player whose wounds would kill him is spared at death's door while a friend still
## stands to lift him (Fighter.dying). Alone, or the last one up, he dies as he always did.
func _may_spare(f: Fighter, _cause: String) -> bool:
	if role == "guest" or mode == "yard" or mode == "training":
		return false
	return humans().any(func(x): return x.f != f and x.f is Fighter and x.f.alive and x.f.dying <= 0.0 and not x.f.is_beaten())

## A friend beside a man at death's door holds the revive key LIFT_T seconds to lift him.
func _lift_tick(dt: float) -> void:
	if role == "guest":
		return
	for e in humans():
		var f = e.f
		if not (f is Fighter) or not f.alive or f.state != "stand" or not bool(e.get("input", {}).get("revive", false)):
			e.lift_t = 0.0
			continue
		var who = dying_friend_of(e)
		if who == null:
			e.lift_t = 0.0
			continue
		e.lift_t = float(e.get("lift_t", 0.0)) + dt
		if float(e.lift_t) >= Fighter.LIFT_T:
			e.lift_t = 0.0
			who.f.lift()
			feed.emit("%s lifts %s" % [f.display_name, who.f.display_name])

## The nearest friend at death's door within reach of `e`, if any.
func dying_friend_of(e: Dictionary):
	var p: Vector3 = e.f.torso.global_position
	var best = null
	var bd := 1.8 * float(e.f.S)
	for o in humans():
		if o == e or not (o.f is Fighter) or not o.f.alive or o.f.dying <= 0.0:
			continue
		var d: float = o.f.torso.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = o
	return best

## A fighter who can no longer stand (legs gone, too little blood, his head ringing) and has lain
## or crawled about on the sand that way for UNFIT_OUT seconds can fight no more: he counts as
## beaten, so a bout where no one on a side can stand is over. So does one who has lain there
## DOWN_OUT seconds on end for whatever reason, never getting up (a ruin of a man the numbers
## still let stand): a bout never hangs on men who cannot fight.
const UNFIT_OUT := 5.0
const DOWN_OUT := 12.0
func _unfit(e: Dictionary, dt: float) -> bool:
	var f = e.f
	var down: bool = f is Fighter and f.alive and f.state != "stand"
	# Only standing a while counts as being up again: one who keeps half rising and falling
	# back is still down.
	e.stand_t = 0.0 if down else float(e.get("stand_t", 0.0)) + dt
	if down:
		e.down_t = float(e.get("down_t", 0.0)) + dt
	elif float(e.stand_t) > 2.0:
		e.down_t = 0.0
	if down and not f.can_stand():
		e.unfit_t = float(e.get("unfit_t", 0.0)) + dt
	else:
		e.unfit_t = 0.0
	if float(e.get("down_t", 0.0)) >= DOWN_OUT:
		e.unfit_t = maxf(float(e.unfit_t), UNFIT_OUT)
	return float(e.unfit_t) >= UNFIT_OUT

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

## What the fight did to my arms, for the smith: the voxels knocked off each weapon in hand, or
## "lost" for one that went with the arm holding it.
func my_wear() -> Dictionary:
	return wear_of(me) if me else {}

## What a bout left of a man's gear: the chips in his weapons (R, L: indices, or "lost" with
## the arm) and the plates off his armour ("armor": Armory wear).
func wear_of(e: Dictionary) -> Dictionary:
	var wear := {}
	if e and e.get("f") != null and is_instance_valid(e.f) and e.f is Fighter:
		for side in ["R", "L"]:
			var w = e.f.weapons.get(side)
			if w and is_instance_valid(w):
				var lost := []
				for i in w.alive.size():
					if w.alive[i] == 0:
						lost.append(i)
				wear[side] = lost
			elif e.f.arm[side].fore.severed:
				wear[side] = "lost"
		wear["armor"] = e.f.armor_wear()
	return wear

func _end(won: bool, text: String, sub: String, pay := 0, _linger := false) -> void:
	over = true
	if Sfx.music and not headless and not attract:
		Sfx.music.set_state("victory" if won else "off")
		music_hot = false
	_banner(text, sub)
	var wear := my_wear()
	var result := {"won": won, "stage": stage, "coop": coop, "pay": pay, "checkpoint": stage_info.get("checkpoint"), "wear": wear, "kills": kills.duplicate(), "boss": stage_info.get("boss", false)}
	if mode == "campaign" and role != "guest":
		# A fall sends everyone back to the checkpoint whole; a cleared stage, as they are.
		var bodies := final_bodies() if won else {}
		result["body"] = bodies.get(me.id, Body.empty()) if me else Body.empty()
		if role == "host":
			for e in humans():
				if e.kind == "remote":
					Net.send_to(int(e.peer), "body", bodies.get(e.id, Body.empty()))
					# His armour as the bout left it: the plates off it stay off until he mends it.
					Net.send_to(int(e.peer), "armor_wear", wear_of(e).get("armor", {}))
	if me and is_instance_valid(me.f) and me.f.alive:
		mission_event("survive")
		if won and me.f.blood > 66.0:
			mission_event("clean")
	result["missions"] = mcount.duplicate()
	if mode == "circus":
		result["circus"] = true
		result["coins"] = rules.coins if rules else 0
		result["favor"] = spectacle.get_favor(me.f) if me and is_instance_valid(me.f) else 0.0
		result["time"] = time
	var show := false
	if killcam:
		# Let the last blow play out on tape (only as long as it still needs), then show the
		# best kill of the match; with nothing to show, straight on (a dead pause of near two
		# seconds after every round felt like the game had hung).
		var left := killcam.tape_left()
		if left > 0.0:
			await get_tree().create_timer(left + 0.05).timeout
		show = killcam.has_clip()
	if role == "host":
		# Online one kill is shown, the fight's best of all, on every screen: the host names it.
		var msg := {"won": won, "text": text, "sub": sub, "pay": pay}
		if killcam:
			var ve = _entity_of(killcam.best.get("victim")) if show else null
			msg["kc_v"] = ve.id if ve != null else -1
		Net.send_all("end", msg)
	if show:
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
		h["at"] = time
		last_hit_of[h.char] = h
	if tut:
		tut.on_hit(h)
	if me and h.get("attacker") == me.f and h.get("char") is Fighter and h.char.team != me.f.team:
		hit_by_me[h.char] = true
		if h.get("p") is Vector3:
			my_hit = {"p": h.p, "f": h.char, "t": time}
		if h.get("punch", false):
			mission_event("punch")
		if h.get("part") == h.char.head:
			mission_event("head")
		var res = h.get("res")
		if res is Dictionary and not res.get("severed", []).is_empty():
			mission_event("sever", res.severed.size())
	if role != "guest":
		spectacle.on_hit(h)
	# Blood where it struck (a party of colours under Confetti Blood), and on the sand below.
	var jn: float = h.get("J", 0.0)
	if jn > 6.0 and h.get("p") is Vector3:
		var dir: Vector3 = h.get("dir", Vector3.UP) if h.get("dir") is Vector3 else Vector3.UP
		var art: bool = h.res.get("artery", false)
		hit_fx(h.p, dir, jn, String(h.get("type", "blunt")), not h.res.get("severed", []).is_empty(), art)
		if role == "host":
			Net.send_all("fx", {"k": "hit", "p": [snappedf(h.p.x, 0.01), snappedf(h.p.y, 0.01), snappedf(h.p.z, 0.01)], "d": [snappedf(dir.x, 0.01), snappedf(dir.y, 0.01), snappedf(dir.z, 0.01)], "J": snappedf(jn, 0.1), "t": h.get("type", "blunt"), "s": not h.res.get("severed", []).is_empty(), "a": art}, false)
	if role != "guest" and h.get("weapon") and String(h.weapon.design.get("imbue", "")) != "":
		_coating(h)
	if role != "guest" and h.get("weapon") and is_instance_valid(h.weapon):
		_gems(h)
		_gold(h)
		_materials(h)
	if h.killed and h.attacker:
		kills[h.attacker.display_name] = kills.get(h.attacker.display_name, 0) + 1
		feed.emit("%s kills %s" % [h.attacker.display_name, h.char.display_name])
	elif h.get("rend", false):
		feed.emit("%s TEARS %s APART!" % [h.attacker.display_name, h.char.display_name])
	elif h.res.get("severed", []).size() > 0:
		feed.emit("%s loses the %s!" % [h.char.display_name, String(h.res.severed[0].label).to_lower()])
	if Sfx:
		Sfx.play("slash" if h.type == "edge" else ("stab" if h.type == "point" else "thud"), h.p, minf(1.0, h.J / 30.0))
	if role != "guest":
		_voices_on_hit(h)
	_music_tick()
	if role == "host" and h.get("chip", {}).get("indices", []).size() > 0:
		_send_weapon_vox(h.weapon, h.chip.indices)

## Who cries out at a blow: the one struck (a grunt of pain, a scream for a limb lost or a
## death blow, a beast's own call), and the one who dealt a heavy one (the effort).
## The music rises to the end of a fight: when the last foe or you are near the end, the boss
## loop (faster, the horn on top) takes over the fight's.
var music_hot := false
func _music_tick() -> void:
	if Sfx.music == null or headless or attract or over or mode == "yard" or mode == "training":
		return
	var foes := enemies().filter(func(e): return e.f.alive and not e.get("harmless", false))
	var hot := false
	if foes.size() == 1 and foes[0].f.vitality() < 0.35:
		hot = true
	if me and is_instance_valid(me.f) and me.f.alive and me.f.blood < 30.0:
		hot = true
	if hot and not music_hot:
		music_hot = true
		Sfx.music.set_state("boss")

func _voices_on_hit(h: Dictionary) -> void:
	var c = h.get("char")
	var J := float(h.get("J", 0.0))
	# A man cries out for a blow that hurts, not for every touch: a quiet grunt for a light one,
	# a short cry for a heavy one, and not again for a couple of seconds unless it is a limb or
	# his life. Quiet, and seldom: the fight is heard in the blows, not in the men.
	if c is Fighter and is_instance_valid(c) and J > 9.0:
		var severed: bool = not h.res.get("severed", []).is_empty()
		var grave: bool = severed or bool(h.get("killed", false))
		var since: float = time - float(c.get_meta("voice_t", -9.0))
		var recent: bool = since < (1.8 if J > 14.0 else 2.4)
		if (c.alive or h.get("killed", false)) and (not recent or grave):
			c.set_meta("voice_t", time)
			var gain := 0.7 if grave else clampf(0.2 + J / 80.0, 0.25, 0.5)
			say(c, Voices.hurt_call(c, J, grave), gain, "grave" if grave else ("hurt" if J > 14.0 else "grunt"))
	var a = h.get("attacker")
	if a is Fighter and is_instance_valid(a) and a.alive and a.kind != "beast" and J > 18.0 and time - float(a.get_meta("effort_t", -9.0)) > 2.5:
		a.set_meta("effort_t", time)
		say(a, "grunt", 0.3, "effort")

## A coated weapon's blow: a burning one sets alight what it strikes, venom poisons (only a cut
## or a stab lets it in), frost slows and saps the breath. Not more than twice a second on a man.
func _coating(h: Dictionary) -> void:
	var c = h.get("char")
	var part = h.get("part")
	if not (c is Fighter) or not c.alive or not (part is VoxelPart) or part.severed or c == h.get("attacker") or float(h.get("J", 0.0)) < 4.0:
		return
	if time - float(c.get_meta("coat_t", -9.0)) < 0.5:
		return
	c.set_meta("coat_t", time)
	var kind: String = h.weapon.design.imbue
	var p: Vector3 = h.p if h.get("p") is Vector3 else part.global_position
	var say := time - float(c.get_meta("coat_say", -9.0)) > 4.0
	match kind:
		"fire":
			add_spot(c, part, "fire", 3.0, h.get("attacker"), p)
			if fx:
				fx.flash(p, Color(1.0, 0.5, 0.15), 3.0, 3.0)
			if say:
				feed.emit("%s is set alight!" % c.display_name)
		"venom":
			if h.get("type", "blunt") == "blunt":
				return
			part.bleed += 0.6
			c.slow(3.5, 0.75)
			c.pain = minf(1.0, c.pain + 0.12)
			c.stamina = maxf(0.0, c.stamina - 6.0)
			if fx:
				fx.burst("venom", p, 14, h.get("dir", Vector3.UP), 1.5)
			if say:
				feed.emit("%s is poisoned!" % c.display_name)
		"frost":
			c.slow(3.0, 0.5)
			c.stamina = maxf(0.0, c.stamina - 10.0)
			if fx:
				fx.burst("frost", p, 22, Vector3.UP, 1.5)
			if say:
				feed.emit("%s is chilled to the bone!" % c.display_name)
	if say:
		c.set_meta("coat_say", time)

## Gems set in a weapon (forge voxels of ruby, sapphire, emerald): every blow that lands has a
## chance, more the more of the stone there is, of setting the part it struck alight (ruby),
## freezing the man or the beast stiff (sapphire), or poisoning the wound so that it festers and
## eats into the flesh (emerald).
const GEM_CHANCE := 0.1     # per voxel of the stone, to a cap
const GEM_CAP := 0.7
func _gems(h: Dictionary) -> void:
	var c = h.get("char")
	var part = h.get("part")
	if not (c is Fighter) or not c.alive or not (part is VoxelPart) or part.severed or c == h.get("attacker") or float(h.get("J", 0.0)) < 4.0:
		return
	var counts: Dictionary = h.weapon.gem_counts()
	if counts.is_empty():
		return
	var p: Vector3 = h.p if h.get("p") is Vector3 else part.global_position
	var say := time - float(c.get_meta("gem_say", -9.0)) > 4.0
	for gem in counts:
		var key := "gem_t_" + String(gem)
		if time - float(c.get_meta(key, -9.0)) < 0.6:
			continue
		if rng.randf() > minf(GEM_CAP, 1.0 - pow(1.0 - GEM_CHANCE, float(counts[gem]))):
			continue
		c.set_meta(key, time)
		# Each stone more makes it surer and fiercer: longer flames, a deeper frost, more venom.
		var k := minf(3.0, 1.0 + 0.2 * float(int(counts[gem]) - 1))
		match gem:
			"ruby":
				add_spot(c, part, "fire", 3.5 * k, h.get("attacker"), p)
				if fx:
					fx.flash(p, Color(1.0, 0.35, 0.1), 3.0, 3.0)
				if say:
					feed.emit("The ruby flares: %s's %s catches fire!" % [c.display_name, _part_word(part)])
			"sapphire":
				# Frozen stiff, and frostbitten: the flesh at the blow dies over the next seconds
				# (Fire.tick "frost": white, then black, then it falls away; no blood from it).
				part.frozen_until = Time.get_ticks_msec() * 0.001 + 2.5 * k
				add_spot(c, part, "frost", 4.0 * k, h.get("attacker"), p)
				c.slow(2.5 * k, maxf(0.15, 0.45 - 0.08 * k))
				c.stamina = maxf(0.0, c.stamina - 10.0 * k)
				c.stagger = minf(1.0, c.stagger + 0.25 * k)
				if fx:
					fx.burst("frost", p, 30, Vector3.UP, 1.8)
				if say:
					feed.emit("The sapphire bites cold: frostbite in %s's %s!" % [c.display_name, _part_word(part)])
			"emerald":
				part.bleed += 0.5 * k
				c.slow(4.0 * k, 0.7)
				c.pain = minf(1.0, c.pain + 0.15 * k)
				c.stamina = maxf(0.0, c.stamina - 8.0 * k)
				add_spot(c, part, "acid", 2.5 * k, h.get("attacker"), p)
				if fx:
					fx.burst("venom", p, 18, h.get("dir", Vector3.UP), 1.5)
				if say:
					feed.emit("The emerald's poison eats into %s's %s!" % [c.display_name, _part_word(part)])
		if say:
			c.set_meta("gem_say", time)
			say = false

## Gold in a weapon: the crowd loves every blow it lands, the more gold the more.
func _gold(h: Dictionary) -> void:
	var att = h.get("attacker")
	var c = h.get("char")
	if att == null or not (c is Fighter) or c == att or float(h.get("J", 0.0)) < 4.0:
		return
	var n := 0
	var w: Weapon = h.weapon
	for i in w.vox.size():
		if w.alive[i] and w.vox[i][3] == "gold":
			n += 1
	if n == 0 or time - float(att.get_meta("gold_t", -9.0)) < 1.5:
		return
	att.set_meta("gold_t", time)
	crowd_add(att, minf(8.0, 1.0 + n * 0.15), "a golden blow")

## The odd stuff of the forge does what the smith was told it does. Explosive powder goes off on
## a hard blow, once: a blast round the place it struck that hurts everyone close, the man who
## swung it as well, and the powder is gone from the weapon. A spring throws the man it hits
## away (boing). Glue holds the weapon where it struck for a moment, a thrown one longer. Ice
## chills, a feather makes him laugh and drop his guard, and each has its sound.
const BOOM_J := 8.0
const GLUE_T := 1.4
const GLUE_THROWN_T := 5.0
var glued: Array = []   # [{"j": joint, "t": until, "w": weapon}]
func _materials(h: Dictionary) -> void:
	var c = h.get("char")
	var w: Weapon = h.weapon
	if not (c is Fighter) or c == h.get("attacker") or not (h.get("p") is Vector3):
		return
	var J := float(h.get("J", 0.0))
	var p: Vector3 = h.p
	var mat := String(h.get("mat", ""))
	var dir: Vector3 = h.get("dir", Vector3.FORWARD) if h.get("dir") is Vector3 else Vector3.FORWARD
	var att = h.get("attacker")
	var sound := String(Data.material(mat).get("sound", ""))
	if sound != "" and sound != "boing":
		sfx(sound, p, minf(1.0, 0.4 + J / 30.0))
	if J >= BOOM_J:
		var powder := w.voxels_near(p, 4.0, "explosive")
		if not powder.is_empty():
			_boom(w, powder, p, att)
	if (mat == "spring" or not w.voxels_near(p, 2.5, "spring").is_empty()) and J >= 3.0 and c.alive:
		var out: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else (c.torso.global_position - p).normalized()
		var k := minf(1.0, J / 25.0)
		c.torso.apply_central_impulse((out * 140.0 + Vector3.UP * 55.0) * k * maxf(1.0, c.torso.mass / 20.0))
		c.stagger = minf(1.0, c.stagger + 0.35 * k)
		w.apply_central_impulse(-out * w.mass * 3.0 * k)
		sfx("boing", p, 0.5 + 0.5 * k)
		_send_fx("boing", p)
		if time - float(c.get_meta("spring_say", -9.0)) > 4.0:
			c.set_meta("spring_say", time)
			feed.emit("BOING! %s goes flying!" % c.display_name)
	var part = h.get("part")
	if (mat == "glue" or not w.voxels_near(p, 2.0, "glue").is_empty()) and J >= 4.0 and part is VoxelPart and not part.severed and not w.freeze and time - float(w.get_meta("glue_t", -9.0)) > GLUE_T + 0.8:
		w.set_meta("glue_t", time)
		var j := PinJoint3D.new()
		add_child(j)
		j.global_position = p
		j.node_a = w.get_path()
		j.node_b = part.get_path()
		glued.append({"j": j, "t": time + (GLUE_T if w.holder else GLUE_THROWN_T)})
		if time - float(c.get_meta("glue_say", -9.0)) > 4.0:
			c.set_meta("glue_say", time)
			feed.emit("Stuck! The glue holds %s fast." % c.display_name)
	if Data.material(mat).get("chill", false) and J >= 4.0 and c.alive:
		c.slow(1.5, 0.7)
		c.stamina = maxf(0.0, c.stamina - 5.0)
		if fx:
			fx.burst("frost", p, 12, Vector3.UP, 1.2)
	if Data.material(mat).get("tickle", false) and c.alive and c.kind != "beast":
		# He laughs: out of breath, off balance, the guard down a moment.
		c.stamina = maxf(0.0, c.stamina - 6.0)
		c.stagger = minf(1.0, c.stagger + 0.2)
		c.slow(1.0, 0.8)
		if time - float(c.get_meta("tickle_say", -9.0)) > 5.0:
			c.set_meta("tickle_say", time)
			feed.emit("%s giggles helplessly!" % c.display_name)

## Explosive powder going off: the voxels at `powder` are spent (what they held falls off), and a
## blast the bigger the more of it there was.
func _boom(w: Weapon, powder: Array, p: Vector3, owner_) -> void:
	var n := powder.size()
	var gone := w.spend(powder)
	if role == "host":
		_send_weapon_vox(w, gone)
		_send_fx("boom", p, n)
	_boom_fx(p, n)
	var r := minf(3.2, 1.3 + 0.12 * n)
	throwables.blast(p, r, minf(42.0, 14.0 + 2.2 * n), owner_)
	for e in entities:
		var c = e.f
		if not is_instance_valid(c) or not c.alive:
			continue
		var d: float = c.torso.global_position.distance_to(p)
		if d > r:
			continue
		var f := 1.0 - d / r
		c.concussion = minf(1.0, c.concussion + 0.4 * f)
		var out: Vector3 = c.torso.global_position - p
		out.y = 0.0
		out = (out.normalized() if out.length() > 0.01 else Vector3.FORWARD) + Vector3.UP * 0.4
		c.torso.apply_central_impulse(out * 120.0 * f * maxf(1.0, c.torso.mass / 20.0))
		if f > 0.5 and not c.mods.get("unstoppable", false):
			c.fall(1.2, true)
		if owner_ and owner_ != c:
			c.last_attacker = owner_
	feed.emit("BOOM!")

func _boom_fx(p: Vector3, n: int) -> void:
	sfx("thud", p, 1.0)
	if fx:
		var k := clampf(0.4 + n * 0.06, 0.4, 1.0)
		fx.flash(p, Color(1.0, 0.8, 0.55), 12.0 * k, 8.0 * k)
		fx.burst("blastfire", p, int(60 * k), Vector3.UP)
		fx.burst("smoke", p + Vector3(0, 0.3, 0), int(40 * k), Vector3.UP, 1.4)
		fx.burst("sparks", p, int(90 * k), Vector3.UP, 2.0)
		fx.mark("scorch", Vector3(p.x, 0.0, p.z), 1.8 * k)

func _send_fx(k: String, p: Vector3, n := 0) -> void:
	if role == "host":
		Net.send_all("fx", {"k": k, "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "n": n}, false)

## Glue lets go when its time is up; a magnet pulls iron and steel to it: loose blades slide in,
## and one held close enough by a weaker hand is torn out of it (host).
const MAGNET_R := 1.8
var _magnet_t := 0.0
func _materials_tick(dt: float) -> void:
	for g in glued.duplicate():
		if time >= g.t or not is_instance_valid(g.j) or not is_instance_valid(g.j.get_node_or_null(g.j.node_a)) or not is_instance_valid(g.j.get_node_or_null(g.j.node_b)):
			if is_instance_valid(g.j):
				g.j.queue_free()
			glued.erase(g)
	_magnet_t -= dt
	if _magnet_t > 0.0:
		return
	_magnet_t = 0.1
	var all := []
	for e in entities:
		if is_instance_valid(e.f):
			for side in ["R", "L"]:
				var hw = e.f.weapons.get(side)
				if hw and is_instance_valid(hw):
					all.append(hw)
	for lw in combat.loose_weapons:
		if is_instance_valid(lw) and not all.has(lw):
			all.append(lw)
	for m in all:
		var nm: int = m.material_count(["magnet"])
		if nm == 0:
			continue
		var mp: Vector3 = m.material_centre("magnet")
		for o in all:
			if o == m or o.freeze:
				continue
			var iron: int = o.material_count(["iron", "steel"])
			if iron == 0:
				continue
			var to: Vector3 = mp - o.global_position
			var d := to.length()
			if d > MAGNET_R or d < 0.05:
				continue
			var pull := minf(60.0, nm * minf(iron, 40) * 0.05 / maxf(0.09, d * d))
			o.apply_central_impulse(to / d * pull * 0.1)
			m.apply_central_impulse(-to / d * pull * 0.03)
			var hf = o.holder
			if hf and hf != m.holder and d < 0.6 and pull > 25.0 and not o.is_shield and rng.randf() < 0.15:
				for side in ["R", "L"]:
					if hf.weapons.get(side) == o:
						hf.release(side)
						feed.emit("The magnet tears the %s out of %s's hand!" % [String(o.design.get("name", "weapon")).to_lower(), hf.display_name])

static func _part_word(part: VoxelPart) -> String:
	var n := String(part.part_name).to_lower()
	for w in ["head", "torso", "arm", "leg", "tail", "wing", "neck", "body"]:
		if n.contains(w):
			return "body" if w == "torso" else w
	return "flesh"

func _on_death(f: Fighter, cause: String) -> void:
	if role != "guest":
		spectacle.on_death(f)
	_tape_kill(f, cause)
	if me and f != me.f and f.last_attacker == me.f:
		mission_event("kill")
		var lw = last_hit_of.get(f, {}).get("weapon")
		if lw != null and is_instance_valid(lw) and lw.holder == null:
			mission_event("throwKill")
	if me and (f.boss or f.S >= 1.8) and hit_by_me.has(f):
		mission_event("bigKill")
	if f.kind != "beast" or not Data.beasts.get(f.get("species") if f.get("species") else "", {}).get("bloodless", false):
		fx.pool(f.torso.global_position, 1.4 * f.S, 8.0)
		arena.set_excitement(1.0)
		if role == "host":
			var tp := f.torso.global_position
			Net.send_all("fx", {"k": "pool", "p": [tp.x, tp.y, tp.z], "s": f.S})
	feed.emit("%s is %s" % [f.display_name, "dead" if cause != "decap" else "beheaded"])
	if role != "guest" and cause != "decap" and time - float(f.get_meta("voice_t", -9.0)) > 0.2:
		f.set_meta("voice_t", time)
		say(f, Voices.death_call(f), 0.8 if f.kind != "beast" else 1.1, "death")

func _on_voxels_lost(f: Fighter, part_index: int, indices: Array, _voxels: Array) -> void:
	if role != "host":
		return
	var e = entity_of(f)
	if e:
		Net.send_all("vox", {"id": e.id, "part": part_index, "idx": indices})

## The host tells the guests whose guts came out, which voxels and where: each draws the chain.
func _on_guts_spilled(f: Fighter, groups: Array, at: Vector3, out: Vector3) -> void:
	if role != "host":
		return
	var e = entity_of(f)
	if e:
		Net.send_all("guts", {"id": e.id, "g": groups, "p": [snappedf(at.x, 0.001), snappedf(at.y, 0.001), snappedf(at.z, 0.001)], "o": [snappedf(out.x, 0.01), snappedf(out.y, 0.01), snappedf(out.z, 0.01)]})

func _send_weapon_vox(w: Weapon, idx: Array) -> void:
	for e in entities:
		for side in ["R", "L"]:
			if e.f.weapons.get(side) == w:
				Net.send_all("wvox", {"id": e.id, "side": side, "idx": idx})

## The point under the crosshair (game.js aimPoint): a ray from the camera through the middle
## of the screen, past the player's own body and weapons. Backed up against the wall the camera
## is outside it, so anything nearer than his own head is behind him: cast again from the head.
## The bow or crossbow in a fighter's hands, if any (the hand that shoots).
func _shooter_of(f) -> Weapon:
	if f == null or not is_instance_valid(f) or not f.alive:
		return null
	for side in ["R", "L"]:
		var w = f.weapons[side]
		if w and (str(w.design.get("shoots", "")) == "arrow" or str(w.design.get("shoots", "")) == "bolt"):
			return w
	return null

## A drawn bow is not a tripod (game.js): the view drifts while the string is back, a little on
## a fresh full draw, more the longer it is held, the more tired and hurt the archer is. A drift
## to fight with the mouse, not a jolt.
var bow_sway := {"y": 0.0, "p": 0.0, "a": 0.0}
func _bow_sway(f, w, dt: float) -> void:
	var want := 0.0
	if w and str(w.design.get("shoots", "")) == "arrow":
		var draw: float = w.get_meta("draw", 0.0)
		var hold: float = w.get_meta("hold_t", 0.0)
		if draw > 0.0:
			var tired: float = 1.0 - minf(1.0, f.stamina / 100.0)
			want = (0.007 + 0.012 * draw + 0.045 * minf(1.0, maxf(0.0, hold - 0.8) / 3.0) + 0.022 * tired) * (1.0 if f.state == "stand" else 2.0) * (1.0 + float(f.eye_hurt) + 0.6 * (1.0 - minf(1.0, f.arm_func("L"))))
	bow_sway.a += (want - bow_sway.a) * minf(1.0, dt * (2.5 if want > bow_sway.a else 6.0))
	var ny: float = bow_sway.a * (sin(time * 1.3) + 0.6 * sin(time * 3.1 + 1.0) + 0.25 * sin(time * 9.7))
	var np: float = bow_sway.a * 0.8 * (cos(time * 1.1) + 0.5 * sin(time * 2.7 + 2.0) + 0.25 * cos(time * 11.3))
	input.look_yaw += ny - bow_sway.y
	input.look_pitch += np - bow_sway.p
	bow_sway.y = ny
	bow_sway.p = np

var aim_from := Vector3.ZERO   # where the crosshair's line of sight starts (the last aim_point)
func aim_point(f: Fighter) -> Vector3:
	var dir := -cam.global_basis.z
	var o := cam.global_position
	var mine := []
	for p in f.parts:
		mine.append(p.get_rid())
	for w in f.weapons.values():
		if w:
			for b in w.bodies():
				mine.append(b.get_rid())
	var space := f.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * 80.0)
	q.exclude = mine
	var hit := space.intersect_ray(q)
	var head: Vector3 = f.head.global_position
	var to_head := maxf(0.0, (head - o).dot(dir))
	if not hit.is_empty() and (hit.position - o).dot(dir) < to_head + 0.1:
		var from := head + dir * 0.25
		q = PhysicsRayQueryParameters3D.create(from, from + dir * 80.0)
		q.exclude = mine
		hit = space.intersect_ray(q)
		o = from
	aim_from = o
	return hit.position if not hit.is_empty() else o + dir * 40.0

# ---------- The body between rounds (Body) ----------

## After a won round: what it left on every player. One who lost a limb or an eye goes to the
## physician before the next round (the local one in the menu, a guest on his own screen).
func _round_wounds() -> void:
	for e in humans():
		if not is_instance_valid(e.f) or not e.f.alive:
			continue
		var r := Body.merge(e.f.body, Body.snapshot(e.f))
		e.f.body = r.body
		for n in r.news:
			feed.emit("%s: %s" % [e.f.display_name, n])
		if r.doctor and not e.has("bot"):   # an autopilot has nobody to take it to the physician
			doctor_wait[e.id] = true
			doctor_t = 0.0
			if e.kind == "remote" and role == "host":
				Net.send_to(int(e.peer), "doctor", {"body": r.body, "news": r.news, "stage": stage})
			else:
				doctor.emit(e, r.body, r.news)

## Back from the physician with `body`: he goes into the next round rebuilt with it.
func doctor_done(id: int, body_: Dictionary) -> void:
	var e = entity_by_id(id)
	doctor_wait.erase(id)
	if e == null or not is_instance_valid(e.f):
		return
	rebuild(e, Body.sanitize(body_))

const YARD_RESPAWN := 3.0

## A fallen player up again where he first came in (the host's word; the guests are sent the
## despawn and the spawn): the body he came into the yard with, full of blood, his kit.
func respawn_player(e: Dictionary) -> Dictionary:
	var spec: Dictionary = e.spec.duplicate(true)
	spec.id = e.id
	_remove_entity(e)
	if role == "host":
		Net.send_all("despawn", {"id": e.id})
	var ne = spawn_fighter(spec)
	for k in ["inventory", "peer", "gadgets"]:
		if e.has(k):
			ne[k] = e[k]
	if me == e:
		me = ne
	feed.emit("%s is back on his feet" % ne.f.display_name)
	return ne

## The same man spawned again with another body (a prosthetic fitted between rounds): where he
## stood, with the blood he had (the physician stopped the bleeding).
func rebuild(e: Dictionary, body_: Dictionary) -> void:
	var old: Fighter = e.f
	var spec: Dictionary = e.spec.duplicate(true)
	spec.body = body_
	spec.id = e.id
	spec.pos = Vector3(old.torso.global_position.x, 0, old.torso.global_position.z)
	spec.yaw = old.yaw
	var blood := maxf(old.blood, 55.0)
	_remove_entity(e)
	if role == "host":
		Net.send_all("despawn", {"id": e.id})
	var ne = spawn_fighter(spec)
	ne.f.blood = blood
	for k in ["inventory", "peer", "bot", "gadgets"]:
		if e.has(k):
			ne[k] = e[k]
	if me == e:
		me = ne

func _remove_entity(e: Dictionary) -> void:
	entities.erase(e)
	if tags.has(e.f):
		if is_instance_valid(tags[e.f]):
			tags[e.f].queue_free()
		tags.erase(e.f)
	if is_instance_valid(e.f):
		combat.fighters.erase(e.f)
		for w in e.f.weapons.values():
			if w and is_instance_valid(w):
				w.queue_free()
		e.f.queue_free()

## A guest drops the fighter the host is about to send again.
func guest_despawn(id: int) -> void:
	var e = entity_by_id(id)
	if e:
		_remove_entity(e)
		if me == e:
			me = null

## Every player's body at the end of the stage: {entity id: body}, read off what is left of them.
func final_bodies() -> Dictionary:
	var out := {}
	for e in humans():
		if is_instance_valid(e.f):
			out[e.id] = Body.merge(e.f.body, Body.snapshot(e.f)).body if e.f.alive else Body.empty()
	return out

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

## Fire (or venom) breathed in a cone in front of the beast: a stream out of the jaws, burning
## patches on the sand, and everyone standing in it hit and set alight (or eaten by the venom).
func _breath(b: Beast, kind_: String, rng_: float) -> void:
	var mouth: Vector3 = b.mouth_point()
	var fwd := PD.quat_of(b.torso) * Vector3(0, 0, 1)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var aim := (fwd + Vector3(0, -0.12, 0)).normalized()
	if b.flying and is_instance_valid(b.target):
		aim = (Vector3(b.target.global_position.x, 0.3, b.target.global_position.z) - mouth).normalized()
	# Where it is meant to land: on the prey if it is in reach, else ahead on the sand.
	var mark := mouth + aim * rng_ * 0.8
	var prey = null
	if is_instance_valid(b.target) and b.target.get("torso") and (b.target.torso.global_position - mouth).length() < rng_ * 1.4:
		mark = b.target.torso.global_position
		prey = b.target
	aim = (b.mouth_dir() as Vector3)
	breath_at(b, kind_, aim, rng_, 0.9)
	stream(b, kind_, mark, rng_, 0.9, prey)
	if role == "host":
		var e0 = entity_of(b)
		if e0:
			Net.send_all("breath", {"id": e0.id, "kind": kind_, "d": [aim.x, aim.y, aim.z], "r": rng_, "m": [snappedf(mark.x, 0.01), snappedf(mark.y, 0.01), snappedf(mark.z, 0.01)]})
	sfx("whoosh", mouth, 1.5)
	feed.emit(("%s spits venom!" if kind_ == "venom" else "%s breathes FIRE!") % b.display_name)

## The breath itself: burning fuel (or venom) poured out of the mouth as globs for `secs`, each
## on its own flight (the way the head points, gravity, the air), so it is only where it lands
## that burns: the man it splashes, the shield he puts in the way, the wall behind him, a
## burning streak along the sand. On every screen; only the host's globs do harm.
var streams: Array = []
static func stream_speed(rng_: float) -> float:
	return clampf(rng_ * 1.7, 6.0, 16.0)

## Whether the jaws point within 15 degrees of `mark` in their turn, and near enough in their
## tilt (the head is still tipping onto it) for the fire to go where it is meant to.
static func mouth_faces(b: Beast, mark: Vector3) -> bool:
	var md := b.mouth_dir()
	var to := mark - b.mouth_point()
	var a := Vector2(md.x, md.z)
	var c := Vector2(to.x, to.z)
	if a.length() < 0.2 or c.length() < 0.3:
		return true
	return absf(a.angle_to(c)) < deg_to_rad(15.0) and absf(b.breath_err) < 0.35

func stream(b: Beast, kind_: String, mark: Vector3, rng_: float, secs: float, prey = null) -> void:
	streams.append({"b": b, "kind": "acid" if kind_ == "venom" else "fire", "mark": mark, "prey": prey, "speed": stream_speed(rng_), "t": secs, "acc": 0.0})

func _update_streams(dt: float) -> void:
	for st in streams.duplicate():
		var b = st.b
		# It turns to the mark first and pours once its jaws face it (at most a moment's wait).
		var facing: bool = is_instance_valid(b) and mouth_faces(b, st.mark)
		st.wait = float(st.get("wait", 0.0)) + (0.0 if facing else dt)
		if facing or st.wait > 1.2:
			st.t -= dt
		if st.t <= 0.0 or not is_instance_valid(b) or not b.alive or b.breath_part().severed:
			streams.erase(st)
			if is_instance_valid(b):
				b.breath_mark = null
			continue
		b.breath_mark = st.mark
		b.breath_t = maxf(b.breath_t, 0.15)   # the jaws stay wide as long as it pours
		var head: VoxelPart = b.breath_part()
		# It hoses the prey: the mark follows him (a beat behind, so a quick man can get out
		# from under it), and the head is tipped to aim the jaws at it (Beast).
		var prey = st.prey
		if prey != null and is_instance_valid(prey) and prey.alive:
			st.mark = (st.mark as Vector3).move_toward(prey.torso.global_position, dt * 3.5)
		if not facing and st.wait <= 1.2:
			continue
		# Out of the jaws, straight the way the mouth points: it is the head that aims the fire.
		var mouth: Vector3 = b.mouth_point()
		var dir: Vector3 = b.mouth_dir()
		st.acc += dt * 55.0
		while st.acc >= 1.0:
			st.acc -= 1.0
			var a := randf() * TAU
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
			var up := side.cross(dir)
			var off := (side * cos(a) + up * sin(a)) * randf() * 0.12
			throwables.spit(st.kind, mouth, (dir + off).normalized() * st.speed * randf_range(0.85, 1.1) + head.linear_velocity * 0.25, b, role == "guest")

## The stream itself, drawn on every screen: flames (or venom) poured out of the mouth along
## `dir` for `secs`, following the head as it moves.
func breath_at(b: Beast, kind_: String, dir: Vector3, rng_: float, secs: float) -> void:
	if headless or fx == null or fx.headless:
		return
	var fire := kind_ != "venom"
	var life := 0.55
	var pm: ParticleProcessMaterial = Fx._process_mat("blastfire" if fire else "acid").duplicate()
	pm.direction = dir
	pm.spread = 9.0
	pm.initial_velocity_min = rng_ / life * 0.75
	pm.initial_velocity_max = rng_ / life * 1.05
	pm.gravity = Vector3(0, 2.0 if fire else -6.0, 0)
	pm.damping_min = 0.0
	pm.damping_max = rng_ * 0.4
	pm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08 * b.S
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.25))
	grow.add_point(Vector2(0.6, 1.0))
	grow.add_point(Vector2(1, 0.7))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	pm.scale_min = 0.6 + rng_ * 0.08
	pm.scale_max = 1.0 + rng_ * 0.14
	var ps := GPUParticles3D.new()
	ps.amount = 260 if fx.quality != "low" else 90
	ps.lifetime = life
	ps.local_coords = false
	ps.process_material = pm
	ps.draw_pass_1 = Fx._draw_mesh("blastfire" if fire else "acid")
	ps.visibility_aabb = AABB(Vector3.ONE * -rng_ * 1.2, Vector3.ONE * rng_ * 2.4)
	fx.add_child(ps)
	ps.global_position = b.mouth_point()
	ps.emitting = true
	var light: OmniLight3D = null
	if fire:
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 6.0
		light.omni_range = rng_ * 0.9
		fx.add_child(light)
	breaths.append({"b": b, "ps": ps, "pm": pm, "light": light, "dir": dir, "dir0": dir, "t": secs, "range": rng_, "fire": fire})

func _update_breaths(dt: float) -> void:
	for br in breaths.duplicate():
		br.t -= dt
		var b = br.b
		var ok: bool = is_instance_valid(b) and not b.breath_part().severed
		if ok and br.t > 0.0:
			# Lit with the stream: none while it is still turning to the mark.
			var pouring := true
			for st in streams:
				if st.b == b and not mouth_faces(b, st.mark) and float(st.get("wait", 0.0)) <= 1.2:
					pouring = false
			br.ps.emitting = pouring
			if not pouring:
				br.t += dt
			var mouth: Vector3 = b.mouth_point()
			br.ps.global_position = mouth
			# The flames leave the way the mouth points now; those already out fly on.
			br.dir = b.mouth_dir()
			br.pm.direction = br.dir
			if br.light:
				br.light.global_position = mouth + br.dir * br.range * 0.4
				br.light.light_energy = 4.0 + randf() * 4.0
			if br.fire and randf() < 0.3:
				fx.burst("smoke", mouth + br.dir * br.range * randf_range(0.4, 1.0), 2, Vector3.UP)
			continue
		br.ps.emitting = false
		if br.light:
			br.light.queue_free()
		get_tree().create_timer(br.ps.lifetime + 0.3, false).timeout.connect(br.ps.queue_free)
		breaths.erase(br)

## A sting or a venomous bite: the poison eats into the flesh where it went in, the wound
## bleeds, and the limbs grow heavy for a while.
func _venom(b, c, part: VoxelPart, at: Vector3) -> void:
	if c == null or not c.alive or part == null or part.severed:
		return
	add_spot(c, part, "acid", 6.0, b, at)
	part.bleed += 1.5
	c.slow(5.0, 0.55)
	c.pain = minf(1.0, c.pain + 0.25)
	if not c.has_meta("venom_feed") or time - float(c.get_meta("venom_feed")) > 4.0:
		c.set_meta("venom_feed", time)
		feed.emit("%s is poisoned by the %s!" % [c.display_name, String(b.display_name).to_lower()])

## An elephant brings a forefoot down (character.js beastStomp): everyone near is knocked off
## his feet, and the part of him the foot lands on is crushed flat, a crater of voxels the
## size of the foot.
func _stomp(b: Beast) -> void:
	var fwd := PD.quat_of(b.torso) * Vector3(0, 0, 1)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var front: Vector3 = b.torso.global_position + fwd * (b.torso.half_ext.z * 1.2)
	front.y = 0.1
	_stomp_fx(front, b.S)
	_send_fx("stomp", front, int(b.S * 10.0))
	var shake := 2.4 * maxf(1.0, b.S * 0.6)
	for e in entities:
		if e.team == ENEMY_TEAM or not e.f.alive or e.f == b or e.f is Beast:
			continue
		var c = e.f
		var tp: Vector3 = c.torso.global_position
		var dd := Vector2(tp.x - front.x, tp.z - front.z).length()
		if dd > shake:
			continue
		# The part the foot comes down on takes it, as hard as the foot lands (the physics'
		# contact impulse); no touch, no stomp. Those close by only feel the ground jump: they
		# reel and stagger back from it.
		var part: VoxelPart = combat.touch_part(b, c, 0.3)
		if part == null or part.severed:
			var k := 1.0 - dd / shake
			c.stagger = minf(1.0, c.stagger + 0.45 * k)
			var away := Vector3(tp.x - front.x, 0.0, tp.z - front.z).normalized()
			c.torso.apply_central_impulse((away * 20.0 + Vector3.UP * 8.0) * k * c.MS)
			continue
		var J := clampf(combat.touch_impulse(b, c, 0.3) * 0.08, 10.0, 40.0)
		var at: Vector3 = part.global_position + Vector3(0, part.half_ext.y * 0.5, 0)
		var wasa: bool = c.alive
		var res: Dictionary = c.apply_hit(part, {"impulse": J, "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "point": at, "dir": Vector3.DOWN, "crush": minf(0.12, 0.003 * J * sqrt(b.S)), "heavy": 0.8})
		c.last_attacker = b
		c.fall(2.0, true)
		combat.hit.emit({"kind": "hit", "p": at, "dir": Vector3.DOWN, "J": J, "type": "blunt", "char": c, "part": part, "attacker": b, "res": res, "killed": wasa and not c.alive})

## The forefeet coming down: a boom, the sand thrown up all round in a ring, grit flying.
func _stomp_fx(p: Vector3, size: float) -> void:
	sfx("thud", p, 1.5)
	sfx("thump", p, 1.0)
	if fx:
		var k := clampf(size / 2.7, 0.6, 1.6)
		fx.burst("dust", p, int(90 * k), Vector3.UP, 2.4 * k)
		fx.burst("debris", p, int(30 * k), Vector3.UP, 1.6 * k)
		fx.burst("dust", p + Vector3(0, 0.3, 0), int(40 * k), Vector3.UP, 1.0)

# ---------- Network (host side snapshots, guest side drawing) ----------

## The snapshot on the wire, 40 times a second to every guest: each body's place and turn in 14
## bytes (int16s: 2 mm, and the quaternion to 1/32767) instead of 28 bytes of floats; the state
## of a fighter (blood, breath, each part's hp) 8 times a second or when he goes down or gets
## up; the dead, settled on the sand, once a second.
const POS_Q := 512.0
const STATUS_EVERY := 15      # physics ticks between a fighter's status (8 a second)
const STILL_EVERY := 120      # and between snapshots of one that has not moved (once a second)
const STILL_POS := 6          # how far a corpse may drift (int16 steps, 2 mm each) and still be still
const STILL_ROT := 400        # and turn (1/32767 of the quaternion: about 0.7 degree)

static func pack_xf(b: PackedByteArray, o: int, t: Transform3D) -> void:
	var q := t.basis.get_rotation_quaternion()
	b.encode_s16(o, clampi(roundi(t.origin.x * POS_Q), -32767, 32767))
	b.encode_s16(o + 2, clampi(roundi(t.origin.y * POS_Q), -32767, 32767))
	b.encode_s16(o + 4, clampi(roundi(t.origin.z * POS_Q), -32767, 32767))
	b.encode_s16(o + 6, roundi(q.x * 32767.0))
	b.encode_s16(o + 8, roundi(q.y * 32767.0))
	b.encode_s16(o + 10, roundi(q.z * 32767.0))
	b.encode_s16(o + 12, roundi(q.w * 32767.0))

static func unpack_xf(b: PackedByteArray, o: int) -> Transform3D:
	var q := Quaternion(b.decode_s16(o + 6), b.decode_s16(o + 8), b.decode_s16(o + 10), b.decode_s16(o + 12))
	if q.length_squared() < 1e-6:
		q = Quaternion.IDENTITY
	return Transform3D(Basis(q.normalized()), Vector3(b.decode_s16(o), b.decode_s16(o + 2), b.decode_s16(o + 4)) / POS_Q)

static func pack_parts(parts: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(parts.size() * 14)
	for i in parts.size():
		pack_xf(b, i * 14, (parts[i] as Node3D).global_transform)
	return b

static func _moved(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return true
	for o in range(0, a.size(), 2):
		if absi(a.decode_s16(o) - b.decode_s16(o)) > (STILL_POS if (o % 14) < 6 else STILL_ROT):
			return true
	return false

## Every fighter's row (`all`: none left out, for a guest who has just come in).
func snapshot(all := true) -> Array:
	var out := []
	for e in entities:
		var f = e.f
		if not is_instance_valid(f):
			continue
		var w := []
		var bows := []
		for side in ["R", "L"]:
			var wp = f.weapons.get(side)
			if wp:
				var wb := PackedByteArray()
				wb.resize(14)
				pack_xf(wb, 0, wp.global_transform)
				w.append([side, wb])
				# A drawn bow: the string, the arrow, the archer's sway and his camera go by it.
				if str(wp.design.get("shoots", "")) == "arrow":
					bows.append([side, snappedf(float(wp.get_meta("draw", 0.0)), 0.01), snappedf(float(wp.get_meta("hold_t", 0.0)), 0.01)])
		var pb := pack_parts(f.parts)
		var still: bool = not all and f.state == "dead" and e.has("snap_b") and not _moved(pb, e.snap_b) and tick - int(e.get("snap_tick", -9999)) < STILL_EVERY
		if still and bows.is_empty():
			continue
		e.snap_b = pb
		e.snap_tick = tick
		var st = null
		if all or tick - int(e.get("st_tick", -9999)) >= STATUS_EVERY or String(e.get("st_state", "")) != String(f.state):
			st = f.status_packed()
			e.st_tick = tick
			e.st_state = String(f.state)
		out.append([e.id, pb, w, st, bows])
	return out

## Guest: a body is moved to where the host had it over the time until the next snapshot is due,
## in the physics step (so the engine's own interpolation smooths every frame between): his
## screen moves as smoothly as the host's, a snapshot behind.
func _puppet_to(b: Node3D, to: Transform3D, gap := -1.0) -> void:
	if not is_instance_valid(b):
		return
	var from: Transform3D = b.global_transform
	if from.origin.distance_squared_to(to.origin) > 9.0:
		b.global_transform = to   # a jump (a spawn, a throw across the arena): straight there
		b.reset_physics_interpolation()
		puppets.erase(b)
		return
	puppets[b] = [from, to, time, snap_gap if gap <= 0.0 else gap]

func _drive_puppets() -> void:
	for b in puppets.keys():
		if not is_instance_valid(b):
			puppets.erase(b)
			continue
		var r: Array = puppets[b]
		var k := clampf((time - float(r[2])) / maxf(0.005, float(r[3])), 0.0, 1.0)
		b.global_transform = (r[0] as Transform3D).interpolate_with(r[1] as Transform3D, k)
		if k >= 1.0:
			puppets.erase(b)

static func _xf(a, o: int) -> Transform3D:
	return Transform3D(Basis(Quaternion(float(a[o + 3]), float(a[o + 4]), float(a[o + 5]), float(a[o + 6])).normalized()), Vector3(float(a[o]), float(a[o + 1]), float(a[o + 2])))

func apply_snapshot(s: Array) -> void:
	# How often they really come (the network decides): each move lasts until the next is due.
	# (The fighters of one snapshot come as separate messages in the same moment.)
	if snap_t < 0.0 or time - snap_t > 0.006:
		if snap_t >= 0.0:
			snap_gap = lerpf(snap_gap, clampf(time - snap_t, SNAP_EVERY / 120.0, 0.2), 0.25)
		snap_t = time
	for row in s:
		if not (row is Array) or row.size() < 4:
			continue
		var e = entity_by_id(int(row[0]))
		if e == null:
			continue
		# Each fighter moves over the time until his own next snapshot is due (in a full room the
		# host sends the enemies at half the rate of the players).
		var eg := snap_gap
		if e.has("snap_seen"):
			eg = clampf(time - float(e.snap_seen), SNAP_EVERY / 120.0, 0.25)
			e.snap_gap = lerpf(float(e.get("snap_gap", eg)), eg, 0.3)
			eg = float(e.snap_gap)
		e.snap_seen = time
		var a = row[1]
		if a is PackedByteArray:
			var bparts: Array = e.f.parts
			for i in mini(a.size() / 14, bparts.size()):
				_puppet_to(bparts[i], unpack_xf(a, i * 14), eg)
		elif a is PackedFloat32Array:
			var parts: Array = e.f.parts
			for i in mini(a.size() / 7, parts.size()):
				_puppet_to(parts[i], _xf(a, i * 7))
		else:
			e.f.apply_snapshot(a)
		for w in row[2]:
			var wp = e.f.weapons.get(w[0])
			if wp:
				if not wp.freeze:
					wp.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					wp.freeze = true
				_puppet_to(wp, unpack_xf(w[1], 0) if w.size() == 2 and w[1] is PackedByteArray else _xf(w, 1), eg)
		if row[3] is Dictionary or row[3] is Array:
			e.f.apply_status(row[3])
		if row.size() > 4:
			for bw in row[4]:
				var bwp = e.f.weapons.get(bw[0]) if bw is Array and bw.size() >= 3 else null
				if bwp:
					var d := clampf(float(bw[1]), 0.0, 1.0)
					bwp.set_meta("draw", d)
					bwp.set_meta("hold_t", maxf(0.0, float(bw[2])))
					throwables._show_draw(bwp, e.f, d)

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
	_update_breaths(dt)
	_update_tags()
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
				bleed += prt.bleed + prt.artery
				# A spurting artery throws its blood a pace off and pools under the wound.
				if prt.artery > 0.3 and not prt.severed and randf() < 0.7:
					var wp: Vector3 = prt.global_position
					fx.mark("blood", Vector3(wp.x + randf_range(-0.5, 0.5), 0, wp.z + randf_range(-0.5, 0.5)), randf_range(0.12, 0.3) * f.S)
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
		var yaw := input.look_yaw + input.free_look.x if input else 0.0
		var pitch := clampf(input.look_pitch + input.free_look.y, -1.45, 1.35) if input else 0.0
		var aiming: bool = f != null and is_instance_valid(f) and f.alive and last_local_inp is Dictionary and float(last_local_inp.get("charging", 0.0)) > 0.0
		var sh := _shooter_of(f)
		var sighting: bool = sh != null and (float(sh.get_meta("draw", 0.0)) > 0.0 or str(sh.design.get("shoots", "")) == "bolt")
		var foe = null
		if me and f != null and is_instance_valid(f) and f.alive:
			var ne = nearest_enemy(me)
			if ne and is_instance_valid(ne.f):
				# What the camera keeps in view: the foe from head to feet, and where you last
				# struck him (for a moment after the blow).
				var of: Fighter = ne.f
				var low := of.torso.global_position
				for p in of.parts:
					if not p.severed and p.global_position.y < low.y:
						low = p.global_position
				foe = [of.torso.global_position + Vector3(0, 0.25, 0), of.head.global_position + Vector3(0, 0.15 * of.S, 0) if not of.head.severed else of.torso.global_position, low]
				if not my_hit.is_empty() and time - float(my_hit.t) < 1.5 and my_hit.f == of:
					foe.append(my_hit.p)
		cam.follow(f, yaw, pitch, dt, aiming or sighting, foe)
	# A guest's hands go to the host 60 times a second whatever his frame rate (once every
	# fourth frame was 7 a second at 30 fps: his fighter answered late and in steps).
	if role == "guest" and Net.active():
		input_acc += dt
		if input_acc >= 1.0 / 60.0:
			var step := minf(input_acc, 0.1)
			input_acc = 0.0
			var gi := {}
			if guest_bot_on:
				gi = _guest_bot_input(step)
				last_local_inp = gi
			elif me and is_instance_valid(me.f):
				gi = _player_input(me.f, step)
			elif input:
				gi = input.sample(step)
			if not gi.is_empty():
				Net.send_host("input", PlayerInput.pack(gi), PlayerInput.has_one_shot(gi))
	tick += 1 if role == "guest" else 0
