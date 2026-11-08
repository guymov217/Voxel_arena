extends Node
## The 75-second trailer's shots (`-- --probe trailer75`, needs a display; tools/make_trailer75.py
## records each with the movie maker). SHOT names the shot of the script, 1 to 32 (24b and 24c:
## the other giants cut into 24). Each is staged in the game as it is played: the scene puts the
## men where they stand and drives each of them the way a player's mouse and keys drive him (his
## look, his hand's mark, the button for a blow, a thrust, a kick, a grab, a throw, his steps).
## The game does the rest as in a bout: a blow lands where the blade really meets the man, its
## harm is the game's, every fall is his body's own. Nothing is added to it: no push, no blow made
## where none landed, nothing passing through anything, no man stronger or harder than the game
## makes him (the champion is a gladiator the trainer has taught all he can, as a player's can be;
## his foes are the campaign's men as they come). A take that does not go as the plan has it is
## filmed again from another start (SHOT_SEED), as a crew films another take.
##
## Some shots are one scene seen by different cameras (the hook: 1-3; the duel: 4-6; the leg:
## 9-10; the cyclops: 21-24; the head: 30-32): the scene goes the same way every time it is run
## (Combat.canonical, one thread, the same dice), so a cut from one camera to the next is the same
## moment.
##
## Tags (stdout, and TAG_LOG when set): REC_START <frame>; KEY <frame> at the shot's moment (the
## blow it cuts on); MARK <frame> <what> (lodged, free, severed, down); HIT <frame> <J> <part>
## <limbs off> <kind> <by the champion> <plates>; REC_END <frame>. SHOT_PEEK=t1,t2,...: no
## movie, a frame saved at each of those scene times to SHOT_DIR (peek_<shot>_<k>.png).

## The trainer's sessions, all of them (Training.ABILITIES at their limits): the champion's mods.
const TRAINED := {"vis": 30, "ictus": 30, "spiritus": 36, "corium": 45, "sanguis": 45, "firmitas": 45}
## The champion's own look, the same in every shot: gilded, his face open under the helmet.
const KIT := ["goldHelmet", "goldLorica", "greaves", "cape"]
const CapsArt := preload("res://tests/capsuleart.gd")

const SHOTS := {
	"1": "hook", "2": "hook", "3": "hook",
	"4": "duel", "5": "duel", "6": "duel",
	"7": "hammer", "8": "mace", "9": "leg", "10": "fall",
	"11": "grab", "12": "kick", "13": "lodge",
	"14": "smith", "14f": "forge", "15": "forge", "16": "forge", "17": "forged",
	"20": "struck",
	"21": "cyclops", "22": "cyclops", "23": "giantlegs", "24": "cyclops", "24b": "lion", "24c": "minotaur",
	"25": "yard", "26": "smith", "27": "physician", "28": "training",
	"29": "melee", "30": "head", "31": "head", "32": "head",
}

var shot := ""
var menu
var m: Match
var rec0 := 0
var rolling := false
var t := 0.0              # seconds since REC_START
var dur := 6.0
var cam_fn: Callable      # t -> [eye, at, fov, focus distance (0: none), roll (radians; optional)]
var tick_fn: Callable     # t -> void, every physics step while rolling
var attrs: CameraAttributesPractical
var keyed := false
var hero: Fighter
var hero_inp := {}
var replay := false       # the kill cam is playing: its camera, not ours
var take := 11            # the take's dice (SHOT_SEED)
var step := 0             # physics steps since the scene began

func _ready() -> void:
	process_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	shot = OS.get_environment("SHOT")
	var peek_at: Array = []
	for v in OS.get_environment("SHOT_PEEK").split(",", false):
		peek_at.append(float(v))
	if not peek_at.is_empty():
		RenderingServer.render_loop_enabled = false
	Combat.canonical = true
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	take = int(OS.get_environment("SHOT_SEED")) if OS.get_environment("SHOT_SEED") != "" else 11
	_dice()
	var scene: String = SHOTS.get(shot, "")
	match scene:
		"hook":
			await _hook()
		"duel":
			await _duel()
		"hammer":
			await _hammer()
		"mace":
			await _mace()
		"leg":
			await _leg()
		"fall":
			await _fall()
		"grab":
			await _grab()
		"kick":
			await _kick()
		"lodge":
			await _lodge()
		"smith":
			await _smith()
		"forge":
			await _forge()
		"forged":
			await _forged()
		"struck":
			await _struck()
		"yard":
			await _yard()
		"physician":
			await _physician()
		"cyclops":
			await _cyclops()
		"giantlegs":
			await _giant_legs()
		"lion":
			await _big_lion()
		"minotaur":
			await _minotaur()
		"training":
			await _training()
		"melee":
			await _melee()
		"head":
			await _head()
		_:
			print("SHOT: one of %s" % ", ".join(SHOTS.keys()))
			get_tree().quit(1)
			return
	if OS.get_environment("SHOT_SECONDS") != "":
		dur = float(OS.get_environment("SHOT_SECONDS"))
	get_viewport().disable_3d = not peek_at.is_empty()
	rec0 = Engine.get_frames_drawn()
	_tag("REC_START %d" % rec0)
	rolling = true
	var peeked := 0
	var warm := 5.0 / 120.0
	while t < dur:
		await get_tree().physics_frame
		_dice()
		t += 1.0 / 120.0
		if m and m.arena:
			m.arena.set_excitement(1.0)
		if tick_fn.is_valid():
			tick_fn.call(t)
		if OS.get_environment("SHOT_DEBUG") == "1" and m and fmod(t, 0.25) < 1.0 / 120.0:
			_debug()
		if peeked < peek_at.size():
			# Drawn for a few frames before the one saved (the light and the eye's exposure take a
			# while to come back after frames undrawn), the scene going on as it does.
			var at_t: float = peek_at[peeked]
			if t >= at_t - warm and get_viewport().disable_3d:
				get_viewport().disable_3d = false
				RenderingServer.render_loop_enabled = true
			if t >= at_t:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("peek_%s_%d.png" % [shot, peeked]))
				peeked += 1
				if peeked >= peek_at.size():
					break
				if float(peek_at[peeked]) - warm > t + 1.0 / 120.0:
					get_viewport().disable_3d = true
					RenderingServer.render_loop_enabled = false
	_tag("REC_END %d" % _frame())
	get_tree().quit()

## SHOT_DEBUG=1: where everyone is, four times a second (to stage a scene by).
func _debug() -> void:
	var bits := []
	for e in m.entities:
		var f = e.f
		if not is_instance_valid(f):
			continue
		var line := "%s %s %s" % [String(f.name).left(10), str(f.torso.global_position.snapped(Vector3.ONE * 0.01)), f.state]
		if f is Fighter:
			var w = f.weapons.get("R")
			if w and is_instance_valid(w):
				line += " w%s" % str(w.global_position.snapped(Vector3.ONE * 0.01))
			line += " h%s" % str(f.hand_world("R").snapped(Vector3.ONE * 0.01))
		bits.append(line)
	print("DBG t=%.2f | %s" % [t, " | ".join(bits)])

# ---------- the stage ----------

## The bout a scene is staged in (the training ground: the arena, its crowd and its light, nobody
## but the scene's own in it): the game's own picture at its best, its music off (the trailer
## lays its own under the game's sound), no HUD, the camera ours, the kill cam only where a shot
## is of it.
func _start(o: Dictionary, killcam := false) -> void:
	o.merge({"decrees": [], "hazards": [], "seed": int(OS.get_environment("SHOT_SEED")) if OS.get_environment("SHOT_SEED") != "" else 5, "killcam": killcam}, false)
	menu.start(o)
	m = menu.match_
	m.combat.hit.connect(_on_hit)
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true)
	if menu.hud:
		menu.hud.visible = false
	m.cam.set_process(false)
	if m.killcam and not killcam:
		m.killcam.queue_free()
		m.killcam = null
	_best_picture()

func _best_picture() -> void:
	menu.apply_picture({"aa": OS.get_environment("TRAILER_AA") if OS.get_environment("TRAILER_AA") != "" else "msaa4", "voxelAO": true})
	var vp := get_viewport()
	var ss := float(OS.get_environment("TRAILER_SSAA")) if OS.get_environment("TRAILER_SSAA") != "" else 1.5
	if ss > 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = ss
	attrs = CameraAttributesPractical.new()

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		_dice()
		if m and m.arena:
			m.arena.set_excitement(1.0)

## The game's dice for this physics step, from the take and the step alone: the global ones (a
## blade's lodging, a beast's choices) and the match's. Drawn frames draw from them too (the
## crowd, the sparks), and they came out a different number of times a step drawn to a window, to
## a movie or to nothing (headless): the same take went another way in each. Set again before the
## step's physics (physics_frame comes before _physics_process), the take is the same however it
## is drawn.
func _dice() -> void:
	step += 1
	seed(hash([take, step]))
	if m and is_instance_valid(m) and m.rng:
		m.rng.seed = hash([take, step, 7])

func _frame() -> int:
	return Engine.get_frames_drawn() - rec0

func _key() -> void:
	if not keyed and rolling:
		keyed = true
		_tag("KEY %d %.3f" % [_frame(), t])

func _mark(what: String) -> void:
	if rolling:
		_tag("MARK %d %.3f %s" % [_frame(), t, what])

func _on_hit(h: Dictionary) -> void:
	var J := float(h.get("J", 0.0))
	if rolling and J >= 8.0:
		var res: Dictionary = h.get("res", {}) if h.get("res") is Dictionary else {}
		var pt = h.get("part")
		_tag("HIT %d %.3f %d %s %d %s %d %d %s" % [_frame(), t, int(J), String(pt.part_name) if pt is VoxelPart else "-", (res.get("severed", []) as Array).size(), str(h.get("type", "-")), 1 if h.get("attacker") == hero else 0, int(res.get("armor_hit", 0)), String(h.char.name) if h.get("char") is Node else "-"])

## A camera's aim that follows `p` smoothly (a moving part jolts the picture about): `s` holds it
## from frame to frame (an array of the camera's own), `k` how much of the way it closes in a frame.
static func _follow(s: Array, p: Vector3, k := 0.08) -> Vector3:
	if s.is_empty():
		s.append(p)
	else:
		s[0] = (s[0] as Vector3).lerp(p, k)
	return s[0]

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _process(_dt: float) -> void:
	if not rolling or m == null or replay or not cam_fn.is_valid():
		return
	var c: Array = cam_fn.call(t)
	var cam: Camera3D = m.cam
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.fov = float(c[2])
	cam.global_position = c[0]
	var fwd: Vector3 = (c[1] as Vector3) - (c[0] as Vector3)
	cam.look_at(c[1], Vector3.UP if absf(fwd.normalized().y) < 0.98 else Vector3.FORWARD)
	if c.size() > 4 and absf(float(c[4])) > 1e-4:
		cam.rotate_object_local(Vector3(0, 0, 1), float(c[4]))
	cam.reset_physics_interpolation()
	var focus := float(c[3]) if c.size() > 3 else 0.0
	if attrs and focus > 0.0:
		# A long lens: what is far beyond the subject melts away.
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = focus + 2.5
		attrs.dof_blur_far_transition = 6.0
		attrs.dof_blur_near_enabled = false
		attrs.dof_blur_amount = 0.05
		cam.attributes = attrs
	else:
		cam.attributes = null

## A camera that does not move: [eye, at, fov] from where `fn` puts it the first time it is asked.
func _still(fn: Callable) -> Callable:
	var held := []
	return func(tt: float) -> Array:
		if held.is_empty():
			held.append(fn.call(tt))
		return held[0]

# ---------- the cast ----------

## The champion: `main` (and `off`) in his hands, in his gilded kit, trained by the trainer as far
## as he teaches. The player's own gladiator in the training ground, at `pos` facing `yaw`.
func _champion(main, pos: Vector3, yaw: float, off := "", armor: Array = KIT, killcam := false) -> Fighter:
	_start({"mode": "training", "training": {"enemy": "none", "respawn": false},
		"loadout_override": {"main": main, "off": off, "armor": armor}}, killcam)
	hero = m.me.f
	for k in Training.mods_of(TRAINED):
		hero.mods[k] = float(hero.mods.get(k, 1.0)) * float(Training.mods_of(TRAINED)[k])
	hero.teleport(pos)
	hero.yaw = yaw
	hero_inp = {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.2, "y": 0.3}}
	m.me.drive = func(_e): return hero_inp
	return hero

## One of the campaign's men (`kind`: Data's enemy types), as the game makes him, with `loadout`
## when given (the weapons a man of his kind comes with), at `pos` facing `yaw`, doing only what
## the scene drives him to do (no mind of his own): his entity.
func _foe(kind: String, pos: Vector3, yaw: float, loadout = null, team := Match.ENEMY_TEAM):
	var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
	if loadout is Dictionary:
		spec.loadout = {"main": Data.preset(loadout.get("main", "")) if loadout.get("main", "") != "" else {}, "off": Data.preset(loadout.get("off", "")) if loadout.get("off", "") != "" else {}, "armor": loadout.get("armor", [])}
	spec.pos = pos
	spec.yaw = yaw
	spec.team = team
	var e = m.spawn_fighter(spec)
	e.erase("bot")
	e.drive = func(_e): return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.3, "y": 0.4}}
	return e

## A giant of the campaign's (the cyclops, the minotaur...) as it comes, driven by the scene.
func _giant(kind: String, pos: Vector3, yaw: float):
	var spec: Dictionary = m.enemy_spec({"e": kind, "boss": true}, 0, 1)
	spec.pos = pos
	spec.yaw = yaw
	var e = m.spawn_fighter(spec)
	e.erase("bot")
	e.drive = func(_e): return {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.3, "y": 0.6}}
	return e

## Where a man's hand mark is at `tt` along `strokes`: each [start, secs, from, to, thrust (0/1)]
## is drawn back to `from` a moment before its start and thrown across to `to` over `secs`, the
## button down while it goes (a player's swing); between them the mark rests at `rest`. Returns
## [mark, power, thrust].
static func _stroke_at(tt: float, strokes: Array, rest: Vector2) -> Array:
	var mk := rest
	var power := false
	var thrust := 0.0
	for k in strokes.size():
		var s: Array = strokes[k]
		var st := float(s[0])
		var nxt: float = float(strokes[k + 1][0]) if k + 1 < strokes.size() else 99.0
		var back := minf(0.45, (st - (float(strokes[k - 1][0]) + float(strokes[k - 1][1]) if k > 0 else -1.0)) * 0.6)
		if tt >= st - back and tt < st:
			mk = (s[2] as Vector2) if k == 0 or tt >= st - back * 0.6 else (strokes[k - 1][3] as Vector2).lerp(s[2] as Vector2, _ease((tt - (st - back)) / (back * 0.4)))
		elif tt >= st and tt < minf(nxt - back, st + float(s[1]) + 0.35):
			var u := _ease((tt - st) / float(s[1]))
			mk = (s[2] as Vector2).lerp(s[3] as Vector2, u)
			power = tt < st + float(s[1]) + 0.1
			thrust = float(s[4]) if s.size() > 4 and tt < st + float(s[1]) + 0.25 else 0.0
		elif tt >= st + float(s[1]) + 0.35 and tt < nxt - back:
			mk = (s[3] as Vector2).lerp(rest, _ease((tt - st - float(s[1]) - 0.35) / 0.4))
	return [mk, power, thrust]

## Watches `a`'s blows on `f` from `from_t` on: the first that lands by `a`'s own weapon or body
## (J at least `min_j`) is the shot's moment (KEY), and calls `done` with it. Only watches: the
## blow is the game's, where the blade met him.
func _on_blow(a: Fighter, f: Fighter, from_t := 0.0, min_j := 15.0, done := Callable()) -> void:
	var seen := [false]
	m.combat.hit.connect(func(h: Dictionary) -> void:
		if seen[0] or not rolling or t < from_t or h.get("char") != f or h.get("attacker") != a or float(h.get("J", 0.0)) < min_j:
			return
		seen[0] = true
		_key()
		if done.is_valid():
			done.call(h))

## Tags the first blow of `a`'s that lands on `f` from `from_t` on (MARK `what`), only watching.
func _mark_blow(a: Fighter, f: Fighter, what: String, from_t := 0.0, min_j := 8.0) -> void:
	var seen := [false]
	m.combat.hit.connect(func(h: Dictionary) -> void:
		if seen[0] or not rolling or t < from_t or h.get("char") != f or h.get("attacker") != a or float(h.get("J", 0.0)) < min_j:
			return
		seen[0] = true
		_mark(what))

## Tags a man's fall (MARK down) and a limb of his coming off (MARK severed <part>).
func _watch_man(f: Fighter, who: String) -> void:
	var was := [f.state]
	var off := {}
	var alive := [f.alive]
	var fn := func(_tt: float) -> void:
		if not is_instance_valid(f):
			return
		if alive[0] and not f.alive:
			alive[0] = false
			_mark("dead %s" % who)
		if f.state != was[0]:
			if f.state == "down" or f.state == "dead":
				_mark("down %s" % who)
			was[0] = f.state
		for p in f.parts:
			if is_instance_valid(p) and p.severed and not off.has(p.part_name):
				if off.is_empty():
					_mark("severed %s" % who)
				off[p.part_name] = true
				_mark("severed %s %s" % [who, p.part_name])
	_also(fn)

## Runs `fn` every physics step with the scene's own tick.
var _ticks: Array = []
func _also(fn: Callable) -> void:
	_ticks.append(fn)
	if not tick_fn.is_valid() or tick_fn != _run_ticks:
		var own := tick_fn
		if own.is_valid():
			_ticks.push_front(own)
		tick_fn = _run_ticks

func _run_ticks(tt: float) -> void:
	for fn in _ticks:
		(fn as Callable).call(tt)

# ---------- the scenes ----------

## THE HOOK (1-3): a swordsman, his sword raised over his head to strike; the champion's
## executioner's axe comes down across his raised forearm. Shot 1 low at the side, at the height
## of their waists, close on the arm and still until the blow (cut on it); 2 under his chest,
## three-quarters, the wound and his reaction; 3 wide and a little high, going with them as the
## champion presses on and the man gives ground.
func _hook() -> void:
	_champion("executionerAxe", Vector3(-0.95, 0, 0.0), PI * 0.5)
	var foe = _foe("murmillo", Vector3(0.75, 0, 0.1), -PI * 0.5, {"main": "gladius", "armor": ["helmet"]})
	var ff: Fighter = foe.f
	var back := [0.0]
	# His sword out before him at the height of his chest, to come in at the champion.
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.2, "y": 0.62}, "off": {"x": -0.4, "y": 0.1}, "mz": back[0]}
	# The axe already up over his head as the shot opens (raised in it, it swept through the man's
	# raised arm on its way up).
	hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": -0.1, "y": 1.6}}
	await _steps(100)
	dur = 5.2
	# The axe down across the raised forearm; drawn back, and again across him.
	var strokes := [[0.75, 0.24, Vector2(-0.1, 1.6), Vector2(-0.35, -0.7)], [2.9, 0.3, Vector2(0.9, 0.9), Vector2(-0.8, -0.1)]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(-0.1, 1.6) if tt < 0.75 else Vector2(0.05, 0.6))
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "power": s[1], "mz": 0.5 if tt > 2.3 and tt < 3.2 else 0.0}
		back[0] = -0.6 if tt > 1.6 and tt < 3.8 else 0.0
	_on_blow(hero, ff, 0.5)
	_watch_man(ff, "foe")
	_lodges()
	match shot:
		"1":
			cam_fn = _still(func(_tt: float) -> Array:
				# (On the sun's side of them, +z: from the other, the men were black against the sky.)
				# (Square to the arm and back from it: closer, his body filled half the picture.)
				var arm: Vector3 = ff.by_name.forearmR.global_position
				var eye := Vector3(arm.x - 0.4, 1.0, arm.z + 1.55)
				return [eye, arm + Vector3(-0.15, -0.05, 0), 40.0, 0.0])
		"2":
			cam_fn = func(tt: float) -> Array:
				# Before him, three-quarters, past the champion's shoulder: his face, the arm and the axe
				# in it (from behind him, it was his back).
				var c: Vector3 = ff.torso.global_position
				var eye := c + Vector3(-0.85, -0.4, 1.45).rotated(Vector3.UP, 0.06 * _ease(tt / dur))
				return [eye, c + Vector3(-0.2, 0.15, 0), 46.0, eye.distance_to(c)]
		_:
			var fol := []
			cam_fn = func(tt: float) -> Array:
				var mid: Vector3 = _follow(fol, (hero.torso.global_position + ff.torso.global_position) * 0.5, 0.12)
				var u := _ease((tt - 2.4) / 2.6)
				var eye := mid + Vector3(lerpf(2.0, 1.0, u), 1.85, lerpf(3.7, 4.1, u))
				return [eye, mid + Vector3(0, -0.1, 0), 48.0, 0.0]

## Tags any blade of the champion's stuck in a man (MARK lodged) and wrenched out (MARK free).
func _lodges() -> void:
	hero.lodged.connect(func(_f, _w, what: String, _at): _mark("lodged" if what == "in" else "free"))

## THE DUEL (4-6): a shieldbearer stands looking off across the sand; the champion comes at him
## from behind his shoulder and he turns to face him (5, low and going along with the champion);
## they trade blows, sword on shield and back (6, side on, going with the fight); and the two of
## them in the middle of the arena from high over the stands (4).
func _duel() -> void:
	_champion("gladius", Vector3(-3.6, 0, -1.0), PI * 0.42, "roundShield")
	var foe = _foe("shieldbearer", Vector3(0.6, 0, 0.2), PI * 0.05, {"main": "gladius", "off": "scutum", "armor": ["helmet", "greaves"]})
	var ff: Fighter = foe.f
	var face := [PI * 0.05]
	var guard := [Vector2(-0.25, 0.3)]
	var his := [Vector2(0.4, 0.5), false, 0.0]
	foe.drive = func(_e): return {"look": {"yaw": face[0], "pitch": 0.0}, "main": {"x": (his[0] as Vector2).x, "y": (his[0] as Vector2).y}, "off": {"x": guard[0].x, "y": guard[0].y}, "power": his[1], "thrust": his[2]}
	await _steps(60)
	dur = 7.0
	var mine := [[3.2, 0.28, Vector2(0.95, 1.05), Vector2(-0.85, -0.35)], [4.75, 0.3, Vector2(-0.95, 0.85), Vector2(0.85, -0.3)], [6.0, 0.26, Vector2(0.9, 1.2), Vector2(-0.7, -0.2)]]
	var theirs := [[3.95, 0.3, Vector2(0.9, 1.1), Vector2(-0.6, -0.3)], [5.4, 0.25, Vector2(0.2, 0.3), Vector2(0.05, 0.1), 1.0]]
	tick_fn = func(tt: float) -> void:
		var to: Vector3 = hero.torso.global_position - ff.torso.global_position
		var at_him := atan2(to.x, to.z)
		# He hears him coming and turns to face him.
		if tt > 0.9:
			face[0] = lerp_angle(face[0], at_him, 0.06)
		var s := _stroke_at(tt, mine, Vector2(0.3, 0.5))
		var to_f: Vector3 = ff.torso.global_position - hero.torso.global_position
		var gap := Vector2(to_f.x, to_f.z).length()
		var walk := 0.0 if gap < 1.2 else (0.75 if gap > 1.8 else 0.35)
		var yaw := atan2(to_f.x, to_f.z)
		hero_inp = {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "off": {"x": -0.35, "y": 0.45 if tt > 3.6 else 0.2}, "power": s[1], "mz": walk}
		var r := _stroke_at(tt, theirs, Vector2(0.4, 0.5))
		his[0] = r[0]
		his[1] = r[1]
		his[2] = r[2]
		# His shield goes where the champion's blow is coming.
		for b in mine:
			if tt >= float(b[0]) - 0.35 and tt < float(b[0]) + 0.4:
				guard[0] = Vector2(-0.05, 0.75) if (b[2] as Vector2).y > 1.0 else Vector2(0.15, 0.45)
	_on_blow(hero, ff, 3.0, 8.0)
	_watch_man(ff, "foe")
	match shot:
		"5":
			cam_fn = func(tt: float) -> Array:
				var h: Vector3 = hero.torso.global_position
				var f: Vector3 = ff.torso.global_position
				var mid := h.lerp(f, 0.4)
				var u := _ease(tt / 3.4)
				var eye := mid + Vector3(lerpf(-1.4, -0.4, u), -0.65, lerpf(3.6, 3.4, u))
				return [eye, mid + Vector3(0, 0.25, 0), 48.0, eye.distance_to(mid)]
		"6":
			var fol := []
			cam_fn = func(tt: float) -> Array:
				var mid: Vector3 = _follow(fol, (hero.torso.global_position + ff.torso.global_position) * 0.5, 0.1)
				var across := (ff.torso.global_position - hero.torso.global_position)
				across.y = 0.0
				var side := across.normalized().cross(Vector3.UP)
				var eye := mid + side * 3.6 + Vector3(0, -0.05, 0)
				return [eye, mid + Vector3(0, -0.05, 0), 46.0, eye.distance_to(mid)]
		_:
			cam_fn = func(tt: float) -> Array:
				var mid: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
				var u := _ease((tt - 3.0) / 4.0)
				# (High and diagonal across the arena, but in to them: from twice as far they were
				# specks in the middle of the sand.)
				var eye := mid + Vector3(5.6, 5.4, 7.4).lerp(Vector3(4.1, 4.0, 5.5), u)
				return [eye, Vector3(mid.x, 0.7, mid.z), 44.0, 0.0]

## A HEAVY BLOW (7): a man in a helmet and a cuirass, his sword drawn back; the champion's
## warhammer comes down on him from over his own head. Low before the champion, to his left,
## going a little with the swing.
func _hammer() -> void:
	_champion("warhammer", Vector3(-1.0, 0, 0.0), PI * 0.5)
	var foe = _foe("praetorian", Vector3(0.45, 0, 0.0), -PI * 0.5, {"main": "gladius", "armor": ["helmet", "lorica"]})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.95, "y": 1.2}, "off": {"x": -0.6, "y": 0.0}}
	await _steps(90)
	dur = 3.4
	var strokes := [[1.2, 0.3, Vector2(0.2, 1.7), Vector2(-0.2, -0.6)]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(0.15, 0.9))
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": -0.1}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "power": s[1]}
	_on_blow(hero, ff, 0.9)
	_watch_man(ff, "foe")
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = hero.torso.global_position
		var u := _ease((tt - 0.9) / 1.2)
		var eye := h + Vector3(lerpf(1.25, 1.35, u), -0.55, lerpf(1.75, 1.5, u))
		var at := h.lerp(ff.torso.global_position, 0.55) + Vector3(0, 0.15, 0)
		return [eye, at, 50.0, eye.distance_to(at)]

## ANOTHER WEAPON (8): a mace swung low into a man's shin, side on and close: its flanged head,
## the leg knocked from under him.
func _mace() -> void:
	_champion("mace", Vector3(-1.0, 0, 0.0), PI * 0.5)
	var foe = _foe("recruit", Vector3(0.15, 0, 0.0), -PI * 0.5, {"main": "gladius", "armor": ["helmet"]})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.1}, "main": {"x": 0.25, "y": 1.5}, "off": {"x": -0.45, "y": 0.0}}
	await _steps(90)
	dur = 3.0
	var strokes := [[1.0, 0.26, Vector2(0.9, 0.15), Vector2(-0.8, -1.3)]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(0.6, 0.5))
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": -0.2}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "off": {"x": -0.55, "y": -0.25}, "power": s[1], "crouch": tt > 0.55 and tt < 1.6}
	_on_blow(hero, ff, 0.7)
	_watch_man(ff, "foe")
	cam_fn = func(tt: float) -> Array:
		var shin: Vector3 = ff.by_name.shinR.global_position if is_instance_valid(ff.by_name.get("shinR")) else ff.torso.global_position
		var eye := Vector3(shin.x - 0.55, 0.45, shin.z + 1.6)
		return [eye, Vector3(shin.x - 0.4, 0.55, shin.z), 44.0, 1.6]

## AN ARM OFF (9): a swordsman with his sword raised over his head to strike; the champion's
## executioner's axe chops into his raised arm, and again into the same wound: it comes off at the
## shoulder. Close and a little high, side on, the arm and his face. (The champion turns to him and
## steps in after each blow, as a player follows his man: stood still, the second chop met the
## forearm of a man who had reeled back, or nothing, and no take of five took the arm off.)
func _leg() -> void:
	_champion(OS.get_environment("LIMB_WEAPON") if OS.get_environment("LIMB_WEAPON") != "" else "executionerAxe", Vector3(-0.95, 0, 0.0), PI * 0.5)
	var fx := float(OS.get_environment("LIMB_X")) if OS.get_environment("LIMB_X") != "" else 0.9
	var fy := float(OS.get_environment("LIMB_Y")) if OS.get_environment("LIMB_Y") != "" else 1.35
	var foe = _foe("recruit", Vector3(fx, 0, 0.1), -PI * 0.5, {"main": "gladius", "armor": ["helmet"]})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.25, "y": fy}, "off": {"x": -0.4, "y": 0.1}}
	hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": -0.1, "y": 1.6}}
	await _steps(100)
	dur = 6.0
	var chops := []
	# (Five: where the axe lodges and is wrenched out the next chop is lost; four were not always enough.)
	var n := int(OS.get_environment("LIMB_CHOPS")) if OS.get_environment("LIMB_CHOPS") != "" else 5
	# (LIMB_STROKE "a,b,c,d": the chop's mark from (a, b) to (c, d), tried other ways.)
	var sk: Array = Array(OS.get_environment("LIMB_STROKE").split(",", false)).map(func(v): return float(v))
	var c_from := Vector2(sk[0], sk[1]) if sk.size() == 4 else Vector2(-0.1, 1.6)
	var c_to := Vector2(sk[2], sk[3]) if sk.size() == 4 else Vector2(-0.35, -0.7)
	for k in n:
		chops.append([0.75 + 1.05 * k, 0.24, c_from, c_to])
	var off := [-1.0]
	_also(func(tt: float) -> void:
		if off[0] >= 0.0:
			return
		for pn in ["forearmR", "upperArmR", "forearmL", "upperArmL"]:
			if is_instance_valid(ff.by_name.get(pn)) and ff.by_name[pn].severed:
				off[0] = tt
				_key()
				return)
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, chops, c_from)
		var cut_off: bool = float(off[0]) >= 0.0
		# Turned to him, and a step in when a blow has sent him out of reach (as a player follows
		# his man to strike the same place again).
		var to: Vector3 = ff.torso.global_position - hero.torso.global_position
		to.y = 0.0
		var step := 0.6 if to.length() > 1.55 and not cut_off else 0.0
		# Once it is off: no more chops, and the shove (Q) as he reels.
		# (The axe held up out of his way after it.)
		hero_inp = {"look": {"yaw": atan2(to.x, to.z), "pitch": 0.0}, "main": {"x": (s[0] as Vector2).x if not cut_off else 0.15, "y": (s[0] as Vector2).y if not cut_off else 1.5}, "power": s[1] and not cut_off, "mz": step}
	_watch_man(ff, "foe")
	_lodges()
	if shot == "9":
		cam_fn = func(tt: float) -> Array:
			var c: Vector3 = ff.torso.global_position
			var eye := Vector3(c.x - 0.35, 1.95, c.z + 1.75)
			return [eye, Vector3(c.x - 0.2, 1.45, c.z), 46.0, eye.distance_to(c)]
	else:
		var fol := []
		cam_fn = func(tt: float) -> Array:
			var c: Vector3 = _follow(fol, ff.torso.global_position, 0.08)
			var eye := Vector3(c.x - 0.6, 0.95, c.z + 4.3)
			return [eye, Vector3(c.x - 0.45, 0.8, c.z), 44.0, eye.distance_to(c)]

## KNOCKED DOWN (10): a man with a big shield, side on to the champion; the warhammer swung low
## and hard into his legs from the side takes them from under him. The whole of him, side on,
## going with him as he goes down.
func _fall() -> void:
	_champion("warhammer", Vector3(-1.0, 0, 0.0), PI * 0.5)
	var foe = _foe("shieldbearer", Vector3(0.45, 0, 0.0), -PI * 0.5, {"main": "gladius", "off": "scutum", "armor": ["helmet", "greaves"]})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.5, "y": 0.9}, "off": {"x": -0.2, "y": 0.55}}
	var v := (OS.get_environment("FALL_STROKE") if OS.get_environment("FALL_STROKE") != "" else "1.2,-0.3,-1.1,-1.2,0.3").split(",")
	hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": float(v[0]), "y": float(v[1])}}
	await _steps(90)
	dur = 3.6
	var strokes := [[1.0, float(v[4]), Vector2(float(v[0]), float(v[1])), Vector2(float(v[2]), float(v[3]))]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(float(v[0]), float(v[1])) if tt < 1.0 else Vector2(0.3, 0.6))
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": -0.15}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "power": s[1]}
	_on_blow(hero, ff, 0.8)
	_watch_man(ff, "foe")
	var fol := []
	cam_fn = func(tt: float) -> Array:
		var c: Vector3 = _follow(fol, ff.torso.global_position, 0.08)
		var eye := Vector3(c.x - 0.7, 0.95, c.z + 4.2)
		return [eye, Vector3(c.x - 0.45, 0.75, c.z), 44.0, eye.distance_to(c)]

## THE GRAB (11): the champion, his sword in his right hand and his left empty, takes the axeman
## by his sword arm as it comes down, and throws him. A little above them, three-quarters.
func _grab() -> void:
	_champion("gladius", Vector3(-0.75, 0, 0.0), PI * 0.5, "")
	var foe = _foe("berserker", Vector3(0.2, 0, 0.0), -PI * 0.5, {"main": "axe", "armor": []})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.3}, "off": {"x": -0.4, "y": 0.2}}
	hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": 0.45, "y": 0.4}, "off": {"x": 0.05, "y": 0.75}}
	await _steps(90)
	dur = 3.6
	tick_fn = func(tt: float) -> void:
		# G pressed with the left hand out at him (a press, not held: held on, it lets go again),
		# then F: he throws him.
		var grab := tt > 0.9 and tt < 0.93
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": 0.45, "y": 0.4}, "off": {"x": 0.05, "y": 0.75}, "grab": grab, "grabHands": "L" if grab else null, "throw": tt > 1.65 and tt < 1.68, "throwPower": 1.0}
	m.feed.connect(func(line: String) -> void:
		if "grabbed" in line:
			_key()
			_mark("grab"))
	_watch_man(ff, "foe")
	cam_fn = func(tt: float) -> Array:
		var mid: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
		var eye := mid + Vector3(-1.4, 1.35, 2.3)
		return [eye, mid + Vector3(0, -0.1, 0), 46.0, eye.distance_to(mid)]

## THE KICK (12): a man comes in with his blade up; the champion's foot in his chest, side on and
## close, the man knocked back.
func _kick() -> void:
	_champion("gladius", Vector3(-0.8, 0, 0.0), PI * 0.5, "roundShield")
	var foe = _foe("recruit", Vector3(0.15, 0, 0.0), -PI * 0.5, {"main": "gladius", "armor": ["helmet"]})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.3}, "off": {"x": -0.4, "y": 0.2}}
	await _steps(90)
	dur = 2.8
	tick_fn = func(tt: float) -> void:
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": 0.4, "y": 0.6}, "off": {"x": -0.3, "y": 0.4}, "kick": tt > 0.8 and tt < 0.86}
	_on_blow(hero, ff, 0.6, 5.0)
	_watch_man(ff, "foe")
	cam_fn = func(tt: float) -> Array:
		var mid: Vector3 = (hero.torso.global_position + Vector3(0.35, 0, 0)) * 0.5 + Vector3(0.18, 0, 0)
		# (Their heads in it too, his face as the foot goes in: at the height of the kick, they were
		# cut off at the shoulders.)
		var eye := Vector3(mid.x, 1.05, mid.z + 2.75)
		return [eye, Vector3(mid.x, 1.0, mid.z), 48.0, 2.75]

## THE BLADE STUCK (13): the champion's axe chopped into a man's shoulder, from behind the man,
## stays in the bone; he pulls it out, the man dragged with it.
func _lodge() -> void:
	_champion("axe", Vector3(-0.8, 0, 0.0), PI * 0.5, "")
	var foe = _foe("recruit", Vector3(0.4, 0, 0.0), -PI * 0.5, {"main": "gladius", "armor": []})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.35, "y": 1.1}, "off": {"x": -0.4, "y": 0.1}}
	await _steps(90)
	dur = 3.4
	var stuck := [-1.0]
	hero.lodged.connect(func(_f, _w, what: String, _at):
		if what == "in" and stuck[0] < 0.0:
			stuck[0] = t
			_key())
	_lodges()
	var strokes := [[0.9, 0.24, Vector2(0.75, 1.5), Vector2(-0.3, -0.2)]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(0.3, 0.6))
		var mk: Vector2 = s[0]
		var pull: bool = float(stuck[0]) >= 0.0 and tt > float(stuck[0]) + 0.55
		if pull:
			mk = Vector2(0.65, 0.2)
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": mk.x, "y": mk.y}, "power": s[1] and stuck[0] < 0.0, "mz": -0.7 if pull else 0.0}
	_watch_man(ff, "foe")
	cam_fn = func(tt: float) -> Array:
		var c: Vector3 = ff.by_name.upperArmR.global_position if is_instance_valid(ff.by_name.get("upperArmR")) else ff.torso.global_position
		var eye := c + Vector3(1.25, 0.1, 0.95)
		return [eye, c + Vector3(-0.35, -0.1, 0), 42.0, eye.distance_to(c)]

## THE ARMOUR STRUCK (20): the champion in his armour stands to a brute's hammer; two blows land on
## his cuirass, one each way, its plates knocked off. Low, three-quarters.
func _struck() -> void:
	_champion("gladius", Vector3(0.0, 0, 0.0), PI * 0.5, "", ["goldHelmet", "lorica", "greaves", "manica"])
	var foe = _foe("brute", Vector3(1.25, 0, 0.0), -PI * 0.5, {"main": "warhammer", "armor": ["helmet"]})
	var ff: Fighter = foe.f
	var his := [Vector2(0.3, 0.6), false]
	# (He steps in again when the last blow has sent the champion out of reach.)
	foe.drive = func(_e):
		var gap: float = Vector2(hero.torso.global_position.x - ff.torso.global_position.x, hero.torso.global_position.z - ff.torso.global_position.z).length()
		return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": (his[0] as Vector2).x, "y": (his[0] as Vector2).y}, "power": his[1], "mz": 0.6 if gap > 1.35 else 0.0}
	await _steps(90)
	dur = 6.2
	# Down from over his head onto the champion's helmet and shoulders, twice (swung across at his
	# chest, the blows landed on the arm that hung over the cuirass, and no plate came off).
	var strokes := [[1.1, 0.35, Vector2(0.35, 1.5), Vector2(0.15, -0.5)], [4.4, 0.35, Vector2(0.5, 1.5), Vector2(0.2, -0.5)]]   # (the second once he is up again)
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(0.35, 1.5) if tt < 1.1 else Vector2(0.4, 0.9))
		his[0] = s[0]
		his[1] = s[1]
		# His own blade kept low at his side (held out at the brute it cut his forearm before a blow).
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": 0.6, "y": -0.8}}
	_on_blow(ff, hero, 0.8)
	# Low, three-quarters, from a fixed place: the champion under the blows, the brute over him (it
	# went with his trunk, and when he went down it went under the sand).
	var at0: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = hero.torso.global_position
		var at := at0.lerp(Vector3(h.x, maxf(0.75, h.y), h.z), 0.55) + Vector3(0, 0.05, 0)
		var eye := Vector3(at0.x - 1.8, 0.45, at0.z + 2.8)
		return [eye, at, 46.0, eye.distance_to(at)]

## THE CYCLOPS (21, 22, 24): the cyclops comes across the sand at the champion with his hammer (21:
## from very low behind the champion, rising up the giant); his blow comes down and the champion
## is thrown (22: low, side on); the giant comes down (24: low, three-quarters, close).
func _cyclops() -> void:
	_champion("executionerAxe", Vector3(0.0, 0, 2.0), PI)
	var g = _giant("cyclops", Vector3(-0.3, 0.1, -4.2), 0.0)
	var gf: Fighter = g.f
	var gi := {"look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.3, "y": 0.6}, "mz": 0.0}
	g.drive = func(_e): return gi
	await _steps(40)
	dur = 13.0
	var his := [[2.8, 0.45, Vector2(0.4, 1.7), Vector2(-0.2, -0.9)]]
	var mine := [[8.2, 0.28, Vector2(0.95, 0.4), Vector2(-0.8, -1.0)], [9.5, 0.28, Vector2(0.95, 0.4), Vector2(-0.8, -1.0)], [10.9, 0.3, Vector2(0.2, 1.7), Vector2(-0.2, -0.8)]]
	tick_fn = func(tt: float) -> void:
		var to: Vector3 = hero.torso.global_position - gf.torso.global_position
		to.y = 0.0
		var dist := to.length()
		gi.look = {"yaw": atan2(to.x, to.z), "pitch": -0.25}
		gi.mz = 0.6 if dist > 2.6 and tt < 2.7 else 0.0
		var s := _stroke_at(tt, his, Vector2(0.3, 0.9))
		gi.main = {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}
		gi.power = s[1]
		var to_g := -to
		var hs := _stroke_at(tt, mine, Vector2(0.3, 0.7))
		# Up again, he limps in to the giant's legs and cuts at the knee.
		hero_inp = {"look": {"yaw": atan2(to_g.x, to_g.z), "pitch": 0.2}, "main": {"x": (hs[0] as Vector2).x, "y": (hs[0] as Vector2).y}, "power": hs[1], "mz": 0.8 if tt > 5.0 and tt < 8.0 and dist > 1.45 else 0.0}
	_on_blow(gf, hero, 3.0)
	_mark_blow(hero, gf, "cut giant", 5.0)
	_watch_man(gf, "giant")
	_watch_man(hero, "hero")
	match shot:
		"21":
			cam_fn = func(tt: float) -> Array:
				var h: Vector3 = hero.torso.global_position
				var gp: Vector3 = gf.torso.global_position
				var u := _ease(tt / 3.4)
				var eye := h + Vector3(-0.9, -0.85, 2.3)
				var at := Vector3(gp.x * 0.5, lerpf(1.6, gp.y + 0.6, u), gp.z + 1.0)
				return [eye, at, 56.0, 0.0]
		"22":
			var fol := []
			cam_fn = func(tt: float) -> Array:
				var mid: Vector3 = _follow(fol, hero.torso.global_position.lerp(gf.torso.global_position, 0.4), 0.08)
				var eye := Vector3(mid.x + 6.2, 0.55, mid.z + 0.4)
				return [eye, Vector3(mid.x, 1.9, mid.z), 50.0, 6.0]
		_:
			cam_fn = func(tt: float) -> Array:
				var gp: Vector3 = gf.torso.global_position
				var h: Vector3 = hero.torso.global_position
				var eye := gp.lerp(h, 0.5) + Vector3(2.2, -0.4 - gp.y * 0.5, 0.6)
				return [eye, gp + Vector3(0, -0.2, 0), 50.0, eye.distance_to(gp)]

## THE GIANT'S LEGS (23): up again, the champion at the cyclops's legs, his axe into the knee, seen
## from behind his own shoulder. A take of its own: in the one take with 21-22 the giant's blow
## fell on his head as often as not, and he was still down when the shot was over. The giant
## stands over him with his hammer up.
func _giant_legs() -> void:
	_champion("executionerAxe", Vector3(0.25, 0, -2.6), PI)
	var g = _giant("cyclops", Vector3(-0.3, 0.1, -4.2), 0.0)
	var gf: Fighter = g.f
	var gi := {"look": {"yaw": 0.0, "pitch": -0.25}, "main": {"x": 0.4, "y": 1.7}, "mz": 0.0}
	g.drive = func(_e): return gi
	await _steps(40)
	dur = 5.0
	var mine := [[0.9, 0.28, Vector2(0.95, 0.4), Vector2(-0.8, -1.0)], [2.2, 0.28, Vector2(0.95, 0.4), Vector2(-0.8, -1.0)], [3.6, 0.3, Vector2(0.2, 1.7), Vector2(-0.2, -0.8)]]
	tick_fn = func(tt: float) -> void:
		var to_g: Vector3 = gf.torso.global_position - hero.torso.global_position
		to_g.y = 0.0
		gi.look = {"yaw": atan2(-to_g.x, -to_g.z), "pitch": -0.25}
		var hs := _stroke_at(tt, mine, Vector2(0.3, 0.7))
		hero_inp = {"look": {"yaw": atan2(to_g.x, to_g.z), "pitch": 0.2}, "main": {"x": (hs[0] as Vector2).x, "y": (hs[0] as Vector2).y}, "power": hs[1], "mz": 0.5 if to_g.length() > 1.45 else 0.0}
	# (The cut itself: the axe at rest knocking his leg on the way in is not it.)
	_mark_blow(hero, gf, "cut giant", 0.5, 20.0)
	_watch_man(gf, "giant")
	_watch_man(hero, "hero")
	var fol := []
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = _follow(fol, hero.torso.global_position, 0.1)
		var gp: Vector3 = gf.torso.global_position
		var away := (h - gp)
		away.y = 0.0
		away = away.normalized()
		# (Lower and further back than at first: the champion's head and shoulders were all of him
		# at the bottom of the frame, under the giant.)
		var eye := h + away * 2.8 + away.cross(Vector3.UP) * 1.0 + Vector3(0, 0.45, 0)
		return [eye, gp.lerp(h, 0.5) + Vector3(0, 0.25, 0), 56.0, eye.distance_to(gp)]

## THE BIG LION (24b): the campaign's lion boss, half as big again as a lion, comes at a man with
## a spear and a shield; low on the sand. Its own mind: the take is the one it went for him in.
func _big_lion() -> void:
	_champion("spear", Vector3(0.0, 0, 2.0), PI, "roundShield")
	var lion = m.spawn_beast({"beast": "lion", "scale": 1.9, "team": Match.ENEMY_TEAM, "pos": Vector3(0.0, 0.1, -4.5), "yaw": 0.0, "name": "The Big Lion", "boss": true})
	var lf = lion.f
	await _steps(30)
	dur = 10.0
	tick_fn = func(tt: float) -> void:
		var to: Vector3 = lf.torso.global_position - hero.torso.global_position
		hero_inp = {"look": {"yaw": atan2(to.x, to.z), "pitch": 0.0}, "main": {"x": 0.25, "y": 0.35}, "off": {"x": -0.4, "y": 0.6}}
	_on_blow(lf, hero, 0.0, 5.0)
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = hero.torso.global_position
		var lp: Vector3 = lf.torso.global_position
		var mid := h.lerp(lp, 0.5)
		var eye := mid + Vector3(3.2, -0.6, 1.4)
		return [eye, mid + Vector3(0, 0.1, 0), 48.0, eye.distance_to(mid)]

## THE MINOTAUR (24c): its axe comes down on the champion's raised shield, low before them.
func _minotaur() -> void:
	_champion("gladius", Vector3(0.0, 0, 0.6), PI, "scutum")
	var g = _giant("minotaur", Vector3(0.0, 0.1, -1.9), 0.0)
	var gf: Fighter = g.f
	var gi := {"look": {"yaw": 0.0, "pitch": -0.2}, "main": {"x": 0.35, "y": 1.5}}
	g.drive = func(_e): return gi
	await _steps(60)
	dur = 3.0
	var his := [[1.0, 0.32, Vector2(0.3, 1.7), Vector2(-0.2, -0.6)]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, his, Vector2(0.35, 1.5))
		gi.main = {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}
		gi.power = s[1]
		hero_inp = {"look": {"yaw": PI, "pitch": 0.35}, "main": {"x": 0.4, "y": 0.4}, "off": {"x": -0.05, "y": 1.0}}
	_on_blow(gf, hero, 0.6, 5.0)
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = hero.torso.global_position
		var eye := h + Vector3(1.6, -0.75, 1.6)
		return [eye, h.lerp(gf.torso.global_position, 0.6) + Vector3(0, 0.5, 0), 52.0, eye.distance_to(h)]

## TRAINING (28): the training ground's sparring partner set to stand still (a dummy, as the
## Training screen offers), the champion working blows on him. Low, before them.
func _training() -> void:
	# (In his own gilded kit, as in every other shot: the same man throughout.)
	_champion("gladius", Vector3(-0.8, 0, 0.0), PI * 0.5, "roundShield", KIT)
	var foe = _foe("recruit", Vector3(0.45, 0, 0.0), -PI * 0.5, {"main": "", "armor": ["helmet", "lorica"]})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.1, "y": 0.25}}
	await _steps(60)
	dur = 3.0
	var strokes := [[0.6, 0.26, Vector2(0.95, 1.0), Vector2(-0.8, -0.3)], [1.45, 0.26, Vector2(-0.9, 0.8), Vector2(0.85, -0.35)], [2.3, 0.24, Vector2(0.9, 0.2), Vector2(-0.85, 0.1)]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(0.3, 0.5))
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "off": {"x": -0.35, "y": 0.3}, "power": s[1]}
	_on_blow(hero, ff, 0.4, 5.0)
	cam_fn = func(tt: float) -> Array:
		var mid: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
		var eye := mid + Vector3(0.6, -0.55, 2.9)
		return [eye, mid + Vector3(0, 0.15, 0), 50.0, eye.distance_to(mid)]

## THE MELEE (29): the champion and two men of his against three; he cuts into the nearest as
## the others close. Low, three-quarters, wide.
func _melee() -> void:
	_champion("axe", Vector3(-0.9, 0, 0.0), PI * 0.5, "roundShield")
	var friends := []
	var foes := []
	var plan := [
		[Vector3(-1.0, 0, 1.6), {"main": "spear", "off": "roundShield", "armor": ["helmet"]}, 0],
		[Vector3(-1.1, 0, -1.7), {"main": "gladius", "off": "scutum", "armor": ["helmet", "greaves"]}, 0],
		[Vector3(0.45, 0, 0.05), {"main": "gladius", "off": "", "armor": ["helmet"]}, Match.ENEMY_TEAM],
		[Vector3(0.6, 0, 1.75), {"main": "mace", "off": "roundShield", "armor": []}, Match.ENEMY_TEAM],
		[Vector3(0.7, 0, -1.6), {"main": "axe", "off": "", "armor": ["helmet"]}, Match.ENEMY_TEAM],
	]
	var men := []
	for pl in plan:
		var e = _foe("recruit", pl[0], PI * 0.5 if int(pl[2]) == 0 else -PI * 0.5, pl[1], int(pl[2]))
		men.append(e)
		(friends if int(pl[2]) == 0 else foes).append(e.f)
	await _steps(60)
	dur = 3.4
	# Each man swings at the one before him, on his own time.
	for i in men.size():
		var e = men[i]
		var f: Fighter = e.f
		var off := float(i) * 0.37
		var opp: Array = foes if friends.has(f) else (friends + [hero])
		e.drive = func(_e):
			var near: Fighter = opp[0]
			for o in opp:
				if is_instance_valid(o) and o.torso.global_position.distance_to(f.torso.global_position) < near.torso.global_position.distance_to(f.torso.global_position):
					near = o
			var to: Vector3 = near.torso.global_position - f.torso.global_position
			var s := _stroke_at(fmod(t + off, 1.4), [[0.5, 0.3, Vector2(0.9, 1.1), Vector2(-0.7, -0.3)]], Vector2(0.3, 0.7))
			return {"look": {"yaw": atan2(to.x, to.z), "pitch": 0.0}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "power": s[1], "mz": 0.35 if to.length() > 1.3 else 0.0, "off": {"x": -0.3, "y": 0.5}}
	var ff: Fighter = foes[0]
	var strokes := [[0.7, 0.26, Vector2(0.95, 1.1), Vector2(-0.8, -0.3)], [1.9, 0.28, Vector2(-0.95, 0.9), Vector2(0.85, -0.4)]]
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, Vector2(0.3, 0.6))
		var to: Vector3 = ff.torso.global_position - hero.torso.global_position
		hero_inp = {"look": {"yaw": atan2(to.x, to.z), "pitch": 0.0}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "off": {"x": -0.4, "y": 0.45}, "power": s[1]}
	_on_blow(hero, ff, 0.5)
	cam_fn = func(tt: float) -> Array:
		var mid: Vector3 = hero.torso.global_position.lerp(ff.torso.global_position, 0.5)
		var u := _ease(tt / dur)
		var eye := mid + Vector3(lerpf(-1.8, -1.2, u), -0.35, 4.6)
		return [eye, mid + Vector3(0, 0.25, 0), 56.0, eye.distance_to(mid)]

## THE KILL (30-32): the executioner's axe swept across at a man's neck: his head off. 30 side
## on and close, into the slowest motion; 31 the game's own kill cam of it, as it shows a kill
## when the bout ends; 32 after it, the champion over him, from a little high.
func _head() -> void:
	_champion("executionerAxe", Vector3(-0.85, 0, 0.0), PI * 0.5, "", KIT, shot == "31")
	var foe = _foe("dimachaerus", Vector3(0.45, 0, 0.0), -PI * 0.5, {"main": "gladius", "off": "dagger", "armor": []})
	var ff: Fighter = foe.f
	# His blades low and wide, coming in: his neck open to the axe.
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.6, "y": 0.35}, "off": {"x": -0.6, "y": 0.3}}
	hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": 0.3, "y": 1.6}}
	if OS.get_environment("HEAD_STROKE") != "":
		var v0 := OS.get_environment("HEAD_STROKE").split(",")
		hero_inp.main = {"x": float(v0[0]), "y": float(v0[1])}
	await _steps(90)
	dur = 4.5
	# The axe up and over from his right, down into the man's head; and again.
	var strokes := [[1.0, 0.26, Vector2(0.3, 1.6), Vector2(-0.5, -0.2)], [2.1, 0.26, Vector2(0.3, 1.6), Vector2(-0.5, -0.2)]]
	if OS.get_environment("HEAD_STROKE") != "":
		var v := OS.get_environment("HEAD_STROKE").split(",")
		strokes = []
		for k in int(OS.get_environment("HEAD_REPEAT")) if OS.get_environment("HEAD_REPEAT") != "" else 1:
			strokes.append([1.0 + 1.1 * k, float(v[4]), Vector2(float(v[0]), float(v[1])), Vector2(float(v[2]), float(v[3]))])
	tick_fn = func(tt: float) -> void:
		var s := _stroke_at(tt, strokes, (strokes[0][2] as Vector2) if tt < 1.0 else Vector2(0.2, 0.9))
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.05}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "power": s[1]}
	# The moment: the blow that puts him out of the fight (down, or dead: the kill cam tapes both;
	# it is seen the step after the blow).
	var last_blow := [-1.0]
	m.combat.hit.connect(func(h: Dictionary) -> void:
		if rolling and h.get("char") == ff and h.get("attacker") == hero and float(h.get("J", 0.0)) >= 15.0:
			last_blow[0] = t)
	_also(func(tt: float) -> void:
		if not keyed and ff.state != "stand" and float(last_blow[0]) > 0.0 and tt - float(last_blow[0]) < 0.3:
			_key())
	_watch_man(ff, "foe")
	match shot:
		"30":
			cam_fn = func(tt: float) -> Array:
				var c: Vector3 = ff.by_name.head.global_position if is_instance_valid(ff.by_name.get("head")) else ff.torso.global_position
				var eye := Vector3(-0.2, 1.45, 1.9)
				return [eye, Vector3(0.05, 1.35, 0.0), 40.0, 1.9]
		"31":
			# The game's own: when the man is dead and the tape has run on past the blow, the kill
			# cam plays it as it does at a bout's end (its camera, its bars, its caption).
			dur = 14.0
			cam_fn = func(tt: float) -> Array:
				var mid: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
				return [mid + Vector3(-1.5, 0.5, 3.2), mid, 48.0, 0.0]
			_also(func(tt: float) -> void:
				if not replay and tt > 3.4 and m.killcam and m.killcam.has_clip():
					replay = true
					_mark("killcam")
					_play_killcam())
		_:
			# Medium-wide, a little above, three-quarters (the script's): the champion over the man he
			# has put down, near enough to read both (from high and far off they were two small
			# figures on the sand).
			cam_fn = func(tt: float) -> Array:
				var h: Vector3 = hero.torso.global_position
				var u := _ease((tt - 1.6) / 2.6)
				var eye := h + Vector3(lerpf(-1.9, -1.6, u), lerpf(1.25, 1.05, u), lerpf(2.6, 2.2, u))
				return [eye, h.lerp(ff.torso.global_position, 0.5) + Vector3(0, -0.25, 0), 46.0, 0.0]

func _play_killcam() -> void:
	await m.killcam.play(func(): pass)
	_mark("killcam end")
	dur = minf(dur, t + 0.5)

# ---------- tags ----------

# ---------- the forge, the bench, the yard ----------

## The champion's axe (CapsArt's Wrecker, the key art's), block by block as a player builds it at
## the forge: [the cell, the block it is put on, its material, its job], the haft up from the
## grip, then the gold collar, the head, the ruby, its edge and its spikes; each on a block
## already there, the lowest first.
static func _axe_order() -> Array:
	var cells := {}
	for v in CapsArt.AXE.voxels:
		cells[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = [String(v[3]), String(v[4])]
	var stage_of := func(c: Vector3i) -> int:
		var mat: String = cells[c][0]
		var job: String = cells[c][1]
		if mat == "wood":
			return 0
		if mat == "gold":
			return 1
		if job == "edge":
			return 3
		if job == "point":
			return 4
		return 2
	var order := []
	var placed := {Vector3i.ZERO: true}
	var dirs := [Vector3i(0, -1, 0), Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]
	while placed.size() < cells.size():
		var best = null
		var on = null
		for c in cells:
			if placed.has(c):
				continue
			for d in dirs:
				if placed.has(c + d):
					var better: bool = best == null or int(stage_of.call(c)) < int(stage_of.call(best)) or (int(stage_of.call(c)) == int(stage_of.call(best)) and (c.y < best.y or (c.y == best.y and absi(c.x) < absi(best.x))))
					if better:
						best = c
						on = c + d
					break
		if best == null:
			break
		placed[best] = true
		order.append([best, on, cells[best][0], cells[best][1]])
	return order

## The axe as the forge makes it from those blocks (each clicked on the empty cell where it goes:
## its edge facing as the weapon's shape has it): the forge's own build, unseen, for the axe in
## the champion's hands (17).
func _forged_axe() -> Dictionary:
	var f = load("res://scripts/ui/forge.gd").new()
	f.free_build = true
	f.workshop = true
	add_child(f)
	f.visible = false
	f.open(CapsArt.AXE.duplicate(true), 0, func(_d, _c): pass)
	f._blank()
	for o in _axe_order():
		f.mat = o[2]
		f.job = o[3]
		f._place([o[0]], -1, o[0])
	f.name_edit.text = String(CapsArt.AXE.name)
	var d: Dictionary = f._design_now()
	f.queue_free()
	return d

## The forge's "Mirror ⟷" box (left and right alike) unticked: its own toggle sets the forge's
## mirror off.
static func _untick_mirror(f) -> void:
	for n in f.find_children("*", "CheckBox", true, false):
		var cb := n as CheckBox
		if cb.button_pressed and cb.tooltip_text == "Left and right alike":
			cb.button_pressed = false
	f.mirror = false

## The anvil's view alone over the whole screen: the editor's panel, its tool bar and its badges
## put away (the editor's own frame of the work, cropped to it).
static func _anvil_only(f) -> void:
	var box: Control = f.view_box
	var row = box.get_parent()
	for c in row.get_children():
		if c != box and c is Control:
			c.visible = false
	for c in box.get_children():
		if c is Control and not (c is SubViewportContainer):
			c.visible = false

## What the editor lays over the work (the price, the hands' rings and their tags, the balance
## mark), put away after every rebuild brings it back.
static func _clean(f) -> void:
	# (The tool bar comes back every time the forge draws its panel again: put away each frame.)
	if f.tool_bar and is_instance_valid(f.tool_bar):
		f.tool_bar.visible = false
	if f.price_badge and is_instance_valid(f.price_badge):
		(f.price_badge.get_parent() as Control).modulate = Color(1, 1, 1, 0)
	for nd in f.ring_nodes:
		if is_instance_valid(nd):
			nd.visible = false
	if f.com_mark and is_instance_valid(f.com_mark):
		f.com_mark.scale = Vector3.ZERO

## THE FORGE (14f, 15, 16): the workshop's forge, as the main menu opens it (design and keep,
## nothing paid), "Blank anvil · build from nothing" pressed, and the champion's axe built on it
## block by block as a player builds it: the material and the job picked for the block, the mouse
## put on the face of the block it goes on (its ghost shows where it will go), a click. 14f its
## screen whole, the editor round the anvil, the camera drawn in toward the anvil (the wheel); 15
## the anvil's view alone, from a little above, close on the work; 16 the axe done, the forge's
## camera turned round it (the middle button), side on.
func _forge() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	f.free_build = true
	f.workshop = true
	menu.add_child(f)
	f.open(CapsArt.AXE.duplicate(true), 0, func(_d, _c): pass)
	for i in 3:
		await get_tree().process_frame
	if shot != "14f":
		_anvil_only(f)
	# The axe framed whole first, for the camera to hold on it as it grows (framed on the grip
	# alone, the head grew up out of the picture).
	f._rebuild()
	f._frame()
	var dist1: float = f.dist
	var focus1: Vector3 = f.focus
	f._blank()
	f.name_edit.text = String(CapsArt.AXE.name)
	# "Mirror ⟷" unticked first, as a player building a one-sided axe does (ticked, as the forge
	# opens, each block went on the other side too: a double axe, not the one in his hand in 17).
	_untick_mirror(f)
	f.moved = true
	f.dist = dist1
	f.focus = focus1
	f._place_camera()
	await get_tree().process_frame
	var order := _axe_order()
	var every := 0.15
	var t0 := 0.4
	dur = t0 + every * order.size() + 2.6
	var next := [0]
	tick_fn = func(tt: float) -> void:
		var k: int = next[0]
		if k < order.size():
			var o: Array = order[k]
			var at_t := t0 + every * k
			if tt >= at_t - 0.08:
				# The material and the job picked (its buttons), the mouse on the empty cell where the
				# block goes, beside the one it holds on to (on the face of that one, the ray grazed
				# the block beside it and put the new one on its front).
				f.mat = o[2]
				f.job = o[3]
				var cell_w: Vector3 = f.weapon_root.global_transform * (Vector3(o[0]) * Data.weapon_voxel)
				var at: Vector2 = f.cam.unproject_position(cell_w)
				f._hover(at)
				if tt >= at_t:
					f.stroke = {"erase": false, "done": {}, "undo": false}
					f._click(at)
					f.stroke = {}
					if not f.cells.has(o[0]):
						_mark("missed %s" % str(o[0]))
					next[0] = k + 1
					if next[0] == order.size():
						_key()
						f.ghost.visible = false
		if shot != "14f":
			_clean(f)
		# The camera: 14f drawn in to the anvil from the smithy; 15 a little above, close on the
		# work; 16 turned round the axe done, side on.
		var done_t := t0 + every * order.size()
		match shot:
			"14f":
				f.orbit = Vector2(0.62, 0.32)
				f.dist = lerpf(dist1 * 2.6, dist1 * 1.25, _ease(tt / 3.0))
			"15":
				f.orbit = Vector2(0.55, 0.5)
				f.dist = lerpf(dist1 * 0.78, dist1 * 0.7, _ease(tt / done_t))
				f.focus = focus1 - Vector3(0, f.AIM_RISE * f.dist, 0)
			_:
				# (Turned on past 0.85 the gold head caught the light full on and burnt white.)
				f.orbit = Vector2(0.05 + 0.65 * _ease((tt - done_t + 0.3) / 2.6), 0.2)
				f.dist = dist1 * 0.85
				f.focus = focus1 - Vector3(0, f.AIM_RISE * f.dist, 0)
		f._place_camera()

## THE SAME AXE IN THE ARENA (17): the axe built at the forge in the champion's hand, close on
## its head as he raises it (the cut from the forge's last frame), then down into a man.
func _forged() -> void:
	var axe := _forged_axe()
	_champion(axe, Vector3(-0.8, 0, 0.0), PI * 0.5)
	var foe = _foe("recruit", Vector3(0.45, 0, 0.0), -PI * 0.5, {"main": "gladius", "off": "roundShield", "armor": ["helmet"]})
	var ff: Fighter = foe.f
	foe.drive = func(_e): return {"look": {"yaw": -PI * 0.5, "pitch": 0.0}, "main": {"x": 0.4, "y": 1.2}, "off": {"x": -0.5, "y": 0.2}}
	await _steps(90)
	dur = 5.4
	var strokes := [[2.0, 0.26, Vector2(0.85, 1.4), Vector2(-0.6, -0.4)]]
	tick_fn = func(tt: float) -> void:
		# (Held high over his head until the blow: lower, its head was behind the man's shield.)
		var s := _stroke_at(tt, strokes, Vector2(0.35, 1.45))
		hero_inp = {"look": {"yaw": PI * 0.5, "pitch": 0.0}, "main": {"x": (s[0] as Vector2).x, "y": (s[0] as Vector2).y}, "power": s[1]}
	_on_blow(hero, ff, 1.6)
	_watch_man(ff, "foe")
	cam_fn = func(tt: float) -> Array:
		var w: Weapon = hero.weapons.R
		# Close on the axe's head held up, against the sky, from behind his shoulder (the cut from
		# the forge), then back to the two of them for the blow. (Taken on its centre of mass, the
		# camera looked at his grip, and the man's shield behind it filled the frame.)
		var head: Vector3 = w.global_transform * (Vector3(2.0, 10.5, 0.0) * w.vs) if is_instance_valid(w) else hero.torso.global_position
		var mid: Vector3 = (hero.torso.global_position + ff.torso.global_position) * 0.5
		var u := _ease((tt - 0.9) / 1.0)
		var at := head.lerp(mid + Vector3(0, 0.1, 0), u)
		var eye := at + Vector3(lerpf(-0.55, -1.2, u), lerpf(-0.3, -0.45, u), lerpf(0.6, 2.7, u))
		return [eye, at, lerpf(40.0, 48.0, u), eye.distance_to(at)]

## THE LUDUS YARD (25; 14 and 26 at the smith; 27 the physician): the yard between fights, as the
## game has it (the campaign goes back to it after every bout), its keepers at their stalls turning
## to whoever walks up. The champion walks it as the player does (WASD and the mouse).
func _yard_start(body := {}) -> void:
	menu.start({"mode": "yard", "loadout_override": {"main": "gladius", "off": "", "armor": KIT}, "decrees": [], "hazards": [], "body": body})
	m = menu.match_
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true)
	if menu.hud:
		menu.hud.visible = false
	m.cam.set_process(false)
	_best_picture()
	hero = m.me.f
	hero_inp = {"look": {"yaw": 0.0, "pitch": 0.0}, "main": {"x": 0.25, "y": 0.3}}
	m.me.drive = func(_e): return hero_inp

## Walks the champion from where he is toward `to` (a player's keys: on, turned to it).
func _walk_to(to: Vector3, pace := 0.7, near := 0.3) -> void:
	var d: Vector3 = to - hero.torso.global_position
	d.y = 0.0
	var yaw := atan2(d.x, d.z)
	hero_inp = {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.25, "y": 0.3}, "mz": pace if d.length() > near else 0.0}

func _yard() -> void:
	_yard_start()
	hero.teleport(Vector3(6.5, 0, 7.0))
	await _steps(60)
	dur = 4.0
	tick_fn = func(tt: float) -> void:
		_walk_to(Vector3(-3.5, 0, -2.0), 0.75)
	# A little high, going back before him as he comes across the yard toward us, the gate, the
	# market and the stands behind him (from the far side of the yard he was a speck on a field of
	# empty sand).
	var fol := []
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = _follow(fol, hero.torso.global_position, 0.1)
		var u := _ease(tt / dur)
		var eye := h + Vector3(lerpf(2.4, 1.4, u), lerpf(2.6, 2.3, u), lerpf(-6.4, -5.6, u))
		return [eye, h.lerp(Vector3(0.0, 0.9, 11.5), 0.2) + Vector3(0, 0.45, 0), 50.0, 0.0]

## At the smith (14: walking up to his hearth and anvil, a slow push in; 26: over the champion's
## shoulder as Vulcanus turns to him, and his stall opened with G, its rack of arms).
func _smith() -> void:
	_yard_start()
	var st: Vector3 = Yard.STATIONS.smith.p
	hero.teleport(st + Vector3(4.2, 0, -2.6))
	await _steps(60)
	dur = 3.6
	var opened := [false]
	tick_fn = func(tt: float) -> void:
		_walk_to(st + Vector3(1.3, 0, -0.6), 0.6, 0.35)
		if shot == "26" and not opened[0] and tt > 2.4:
			opened[0] = true
			_key()
			menu._open_station("smith")
	if shot == "14":
		cam_fn = func(tt: float) -> Array:
			var u := _ease(tt / dur)
			var eye := st + Vector3(lerpf(5.6, 4.2, u), lerpf(2.3, 1.9, u), lerpf(-5.0, -3.8, u))
			return [eye, st + Vector3(0.6, 0.9, -0.2), 50.0, 0.0]
	else:
		cam_fn = func(tt: float) -> Array:
			var h: Vector3 = hero.torso.global_position
			var to := (st - h)
			to.y = 0.0
			to = to.normalized()
			# Off his shoulder and well to the side: the smith turning to him is seen past him (from
			# just behind his shoulder his head hid the smith).
			var eye := h - to * 1.15 + to.cross(Vector3.UP) * -1.15 + Vector3(0, 0.4, 0)
			return [eye, h.lerp(st, 0.6) + Vector3(0, 1.0, 0), 46.0, 0.0]

## At the physician (27): the champion, his left hand lost in a fight, walks up to Galen, who
## turns to him; his stall opened, a hook fitted to the stump there (the physician's own
## treatment, as the stall's button gives it: the man rebuilt with it, as the yard does); he
## stands with it.
func _physician() -> void:
	var body := Body.empty()
	# (The hand is the forearm's end: a body missing "handL", a part no man has, was made whole
	# again by Body.sanitize, and the physician said "whole, nothing to see to".)
	body.missing = ["forearmL"]
	# (His screen reads the body from the save. The trailer is made in a user folder of its own:
	# the player's save is never touched.)
	Save.set_value("body", body)
	_yard_start(body)
	var st: Vector3 = Yard.STATIONS.physician.p
	hero.teleport(st + Vector3(2.6, 0, 3.2))
	await _steps(60)
	dur = 3.6
	var stage := [0]
	tick_fn = func(tt: float) -> void:
		if stage[0] == 0:
			_walk_to(st + Vector3(0.9, 0, 1.2), 0.55, 0.3)
		if stage[0] == 0 and tt > 1.5:
			stage[0] = 1
			_mark("stall")
			menu._open_station("physician")
		elif stage[0] == 1 and tt > 2.2:
			stage[0] = 2
			_key()
			var offer := ""
			for o in Body.offers(body, 1):
				if String(o.id).begins_with("hook:"):
					offer = String(o.id)
			m.rebuild(m.me, Body.sanitize(Body.apply(body, offer)))
			hero = m.me.f
			hero_inp["off"] = {"x": -0.25, "y": 0.8}   # (he lifts the hook to look at it)
			menu._close_overlay()
			if menu.hud:
				menu.hud.visible = false
	cam_fn = func(tt: float) -> Array:
		var h: Vector3 = hero.torso.global_position
		var mid := h.lerp(st, 0.45)
		var eye := mid + Vector3(1.9, 0.35, -1.6)
		if stage[0] >= 2:
			# The hook fitted: close on his left forearm, the hook at its end, as he lifts it.
			var fore: VoxelPart = hero.arm.L.fore
			var hk: Vector3 = fore.global_position if not fore.severed else h
			return [hk + Vector3(0.55, 0.25, -0.5), hk, 40.0, 0.0]
		return [eye, mid + Vector3(0, 0.15, 0), 46.0, 0.0]

## Each timing tag goes to stdout and, when TAG_LOG names a file, there too (the window build of
## Godot on Windows prints nothing to a pipe).
var _tags := PackedStringArray()
func _tag(line: String) -> void:
	print(line)
	var path := OS.get_environment("TAG_LOG")
	if path == "":
		return
	_tags.append(line)
	var fl := FileAccess.open(path, FileAccess.WRITE)
	if fl:
		fl.store_string("\n".join(_tags) + "\n")
