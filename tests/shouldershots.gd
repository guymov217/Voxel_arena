extends Node
## One fighter's rise through the arena, for the rise trailer (`-- --probe shouldershots`, needs a
## display; run through tools/make_rise_trailer.py). SHOT picks the bout: who he faces and what he
## carries, from a slave with a stick to a champion in steel. He fights on autopilot and does not
## die (the foe does).
##
## Two cameras, cut between by the kill (CLIP_KILL, the frame the dry run saw the foe die on):
## - his helmet's: strapped to the right side of it like a GoPro (user), it moves and turns with
##   his head, a wide lens that takes in the blade in his fist and the man in front of him, and it
##   jolts at every hard blow given or taken;
## - for the kill of the big ones (the lion, the cyclops, the minotaur, the troll, the hydra), a
##   film camera: low on the sand off to one side, a long lens that stacks him and the beast
##   together, drifting slowly round them, the background melting away in its depth of field. The
##   editor plays this part in slow motion; after it the helmet again, looking down at what fell.
##
## CLIP_CAM=film (the crowd trailer): no helmet. The film camera all through the bout, wide (as
## far again, a little higher) until the kill, then cut in close on the same side of them for it,
## and wide again after. CLIP_CLOSE=<frame>,<frame>...: cut in close for those blows too (the
## montage's: seen wide they were specks in the sand, user).
##
## Recorded at a frame for every physics step (--fixed-fps 120), so the editor has frames for
## motion blur and for a smooth slow motion. Drawn at the best the game can: MSAA, the voxels'
## corner shading, and supersampled (TRAILER_SSAA, the 3D drawn that much larger and scaled down).
##
## Two passes: CLIP_DRY=1 draws nothing and prints where the blows and deaths fall ("DEATH <frame>
## <kind> <s>", the foe's kind not "local"; "HIT <frame> <J>"); then CLIP_FROM=<frame> draws from
## there on, the frames before it black (cut afterwards).

const SHOTS := {
	"slave": {"enemy": "foe:drunk", "main": "stick", "off": "", "armor": [], "strength": 2.4},
	"recruit": {"enemy": "foe:recruit", "count": 2, "main": "gladius", "off": "roundShield", "armor": []},
	"lion": {"seed": 3, "enemy": "lion", "main": "gladius", "off": "scutum", "armor": ["manica"], "strength": 2.6, "cine": true},
	"cyclops": {"enemy": "foe:cyclops", "main": "spear", "off": "scutum", "armor": ["helmet", "manica"], "cine": true},
	"minotaur": {"seed": 21, "enemy": "foe:minotaur", "main": "axe", "off": "roundShield", "armor": ["helmet", "manica", "greaves"], "strength": 2.8, "cine": true},
	"titan": {"enemy": "foe:titan", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0, "cine": true},
	"troll": {"enemy": "foe:troll", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0, "cine": true},
	"giant": {"enemy": "foe:giant", "main": "warhammer", "off": "", "armor": ["helmet", "manica", "greaves", "lorica"], "strength": 3.0, "cine": true},
	# (Begun in the middle of the sand with his back to the south wall, the hydra before him with the
	# whole arena behind it: from the training's places it backed off its lunges into the north
	# wall and fought the bout out against it, stuck there to the eye: user. As strong and as hard
	# to bring down as a champion who wins it, his face behind a murmillo's grille: in a galea, at
	# 2.6 and 14, the hydra's bites took his face away in every seed tried.)
	"hydra": {"enemy": "hydra", "main": "zweihander", "off": "", "armor": ["murmilloHelm", "manica", "greaves", "steelLorica"], "strength": 3.2, "toughness": 30.0, "cine": true, "at": [0.0, 6.5, PI, 0.0, -1.5, 0.0], "precut": 2},
	"duel": {"seed": 3, "enemy": "gladiator", "weapon": "axe", "main": "gladius", "off": "roundShield", "armor": ["helmet", "manica"], "strength": 2.2, "cine": true},
	# Blade on blade, fast: longsword against longsword, the foe as good as they come, each fighting
	# from where his blade's outer part meets the other. (A gladius and a dagger are short blades,
	# fought chest to chest: the two of them hugged each other through the scene, user. A spatha is
	# a forge's blank, not a weapon in the rack: named here, it left both men bare-handed.)
	"exchange": {"seed": 5, "enemy": "gladiator", "weapon": "longsword", "difficulty": 1.0, "main": "longsword", "off": "", "armor": ["manica", "greaves"], "strength": 2.0, "cine": true, "ideal": 1.1},
}

## The director's plan of each bout (CLIP_DIRECT=1, the crowd trailer): [second, what it strikes
## at, the stroke, "kill" on the last]. Between the beats the two fight it out; on each the
## champion steps in and strikes there with all he has, and the last one ends it. "fell": a giant
## brought down by it (onto his knees, his head in reach for the next).
const PLANS := {
	"exchange": [[2.4, "arm", "slashR"], [4.0, "leg", "low"], [5.6, "arm", "slashL"], [7.2, "head", "chop", "kill"]],
	"lion": [[2.6, "head", "slashL"], [4.6, "head", "slashR"], [6.4, "neck", "chop", "kill"]],   # (its forelegs are behind its head: a sweep at them met the head every time)
	"duel": [[2.4, "arm", "slashR"], [4.2, "leg", "low"], [6.0, "head", "chop", "kill"]],
	"cyclops": [[2.6, "leg", "thrust"], [4.4, "leg", "thrust", "fell"], [6.4, "torso", "thrust", "kill"]],   # (his head, beyond his body as he lay, was out of the spear's reach whichever way round)
	"troll": [[2.6, "leg", "low"], [4.4, "leg", "slashL", "fell"], [6.4, "head", "chop", "kill"]],
	"hydra": [[2.6, "neck", "slashR"], [4.6, "neck", "slashL"], [6.8, "neck", "slashR", "kill"]],
	# (The rise trailer's others.)
	"slave": [[2.4, "arm", "slashR"], [4.0, "leg", "low"], [5.6, "head", "chop", "kill"]],
	"recruit": [[2.4, "arm", "slashR"], [4.2, "leg", "low"], [6.0, "head", "chop", "kill"]],
	"minotaur": [[2.6, "leg", "low"], [4.4, "leg", "slashL", "fell"], [6.4, "head", "chop", "kill"]],
}
## A beat's parts: how long before its moment he steps in (and at most, should the foe give
## ground), how long he holds the blow drawn back; a blow that does not land is struck again
## (TRIES), then put home.
const APPROACH := 0.85
const APPROACH_MAX := 1.9
const WIND := 0.4
const TRIES := 3
const SETTLE := 1.2        # a giant brought down is let come to rest before the next beat
## The strokes, as a man's bot strikes them (Bot.ATTACKS: drawn back, then the mark thrown across
## with a little of the arm's drive behind it), tuned on a man: [the wind's mark x and y, the
## blow's mark x and y, the drive, how long the blow takes, the height (of his own size, from the
## middle of his trunk) a man's part it is struck at stands]. At a part higher or lower than that
## the marks go up or down by as much.
## How far out along the blade each stroke meets the part best (of its reach): a sweep at the
## legs from a little further off, a thrust at the length of it.
const REACH_K := {"slashR": 0.55, "slashL": 0.55, "low": 0.66, "chop": 0.68, "thrust": 0.75}
const STROKES := {
	"slashR": [0.85, 0.8, -0.85, -0.35, 0.2, 0.28, 0.15],
	"slashL": [-0.85, 0.75, 0.85, -0.3, 0.2, 0.28, 0.15],
	"low": [0.9, 0.1, -0.8, -0.8, 0.2, 0.3, -0.5],
	"chop": [-0.25, 1.2, -0.3, -0.6, 0.3, 0.3, 0.55],   # (brought down across to his middle, the blade's line through the mark: the stageshots cut's)
	"thrust": [0.05, 0.25, 0.0, 0.3, 1.0, 0.22, 0.1],
}

## The film camera's part round the kill (seconds of the game's own time before and after it).
const CINE_BEFORE := 1.1
const CINE_AFTER := 1.3
## The close framing round a montage blow (CLIP_CLOSE): from a moment before it to after it lands.
const CLOSE_BEFORE := 0.55
const CLOSE_AFTER := 1.45

var menu
var m
var seconds := 50.0
var started := false
var rec0 := 0
var from := 0
var kill := -1          # the frame of the kill (CLIP_KILL), or -1 in the dry run
var blow := -1          # CLIP_BLOW: the blow that felled him, when it came before he fell
var close := []         # CLIP_CLOSE: blows the film camera cuts in close on
var cine := false
var film := false      # CLIP_CAM=film: the film camera all through, wide, and close on the kill
var film_fresh := false
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_up := Vector3.UP
var trauma := 0.0      # the jolt of the last hard blow, dying away
var t_cam := 0.0
var mode := "pov"
var foe = null          # the one the film camera frames
var cine_side := 1.0
var cine_t := 0.0
var cine_pos := Vector3.ZERO
var attrs: CameraAttributesPractical
# The director (CLIP_DIRECT): the plan, the beat at hand and where it is in it.
var direct := false
var plan: Array = []
var beat := 0
var phase := "free"        # free, approach, wind, stroke, follow, done
var phase_t := 0.0
var tries := 0
var landed := -1           # the frame the beat's blow landed on (-1: not yet)
var landed_on := ""        # and the part it landed on
var strike_part: VoxelPart = null
var foe_e = null           # the foe's entity
var hero_str := 1.0
var killed := false
var hero_arms := {}        # the weapon in each of his hands as the bout began
var close_until := -1.0    # (seconds) the film camera in close until then
var cine_until := -1.0     # (seconds) the helmet's bouts: the film camera on the kill until then
var t_now := 0.0
var settle_until := -1.0   # (seconds) a giant brought down: the next beat not begun until he is down
var felled := false        # and kept down from then on
var foe_top := 0.0         # the highest his trunk went (CLIP_DEBUG: FOE_TOP at the end)
var spot_side := Vector3.ZERO   # (the way out from the line of a giant down on the sand, to his stand by its head)

func _ready() -> void:
	# After the match's own _process, which moves its camera every frame (cam.follow).
	process_priority = 1000
	var key := OS.get_environment("SHOT")
	if key == "" or not SHOTS.has(key):
		key = "recruit"
	var sh: Dictionary = SHOTS[key]
	seconds = float(OS.get_environment("CLIP_SECONDS")) if OS.get_environment("CLIP_SECONDS") != "" else seconds
	kill = int(OS.get_environment("CLIP_KILL")) if OS.get_environment("CLIP_KILL") != "" else -1
	blow = int(OS.get_environment("CLIP_BLOW")) if OS.get_environment("CLIP_BLOW") != "" else -1
	for c in OS.get_environment("CLIP_CLOSE").split(",", false):
		close.append(int(c))
	cine = bool(sh.get("cine", false)) and OS.get_environment("CLIP_CINE") != "0"
	film = OS.get_environment("CLIP_CAM") == "film"
	# The blows dealt in an order of their own, not the physics engine's: the undrawn pass and the
	# drawn one (its film camera's depth of field drawn too) then fight the same bout.
	Combat.canonical = true
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	var main = Data.shop.get("stick", {}).duplicate(true) if sh.main == "stick" else sh.main
	var o := {"mode": "training", "training": {"enemy": sh.enemy, "count": int(sh.get("count", 1)), "difficulty": 0.85, "immortal": true, "respawn": false},
		"loadout_override": {"main": main, "off": sh.off, "armor": sh.armor}}
	if sh.has("weapon"):
		o.training.weapon = sh.weapon
	if sh.has("difficulty"):
		o.training.difficulty = float(sh.difficulty)
	o["autopilot"] = true
	o["autopilot_diff"] = 1.0
	o["decrees"] = []
	o["hazards"] = []
	# The hero of the piece: hard to bring down and strong in the arm, so every bout is his.
	o["mods"] = {"toughness": float(sh.get("toughness", 6.0)), "strength": float(sh.get("strength", 1.8))}
	o["seed"] = int(OS.get_environment("CLIP_SEED")) if OS.get_environment("CLIP_SEED") != "" else int(sh.get("seed", 7))
	seed(int(o.seed))
	menu.start(o)
	m = menu.match_
	m.combat.hit.connect(_on_hit)
	if OS.get_environment("CLIP_DIST") == "1":
		m.me.f.died.connect(func(_f, cause): _tag("HERO_DIED %s blood %.0f" % [cause, m.me.f.blood]))
	# (Both held off at their blades' length when not striking, stepping in to strike and out
	# again: left to close to their sweet spot, the two spathas met chest to chest, three quarters
	# of the bout under a yard apart, and they looked to be hugging, user. At 1.1 they fight a yard
	# apart and land a blow every two seconds or so; much further off they only fenced.)
	var ideal_k := float(OS.get_environment("CLIP_IDEAL")) if OS.get_environment("CLIP_IDEAL") != "" else float(sh.get("ideal", 0.0))
	if ideal_k > 0.0:
		for e in m.entities:
			if e.has("bot") and e.bot != null:
				e.bot.p = (e.bot.p as Dictionary).duplicate()
				e.bot.p["ideal"] = ideal_k
		if m.me.has("bot") and m.me.bot != null:
			m.me.bot.p = (m.me.bot.p as Dictionary).duplicate()
			m.me.bot.p["ideal"] = ideal_k
	# A hydra come in already short of heads (PRECUT: how many of its necks are off at the start):
	# with all five it brought down every champion in every seed tried, his face bitten away,
	# however strong; the trailer shows only the last seconds before its fall, when most are off.
	var precut := int(OS.get_environment("CLIP_PRECUT")) if OS.get_environment("CLIP_PRECUT") != "" else int(sh.get("precut", 0))
	if precut > 0:
		for e in m.entities:
			if e != m.me and is_instance_valid(e.f) and e.f is Beast:
				var cut := 0
				for n in ["neck1", "neck2", "neck3", "neck4"]:
					if cut < precut and e.f.by_name.has(n) and not e.f.by_name[n].severed:
						e.f.detach_limb(e.f.by_name[n], {"removed": [], "severed": []})
						cut += 1
	# Where the bout begins, when the shot says (him: x, z, yaw; then the foe's).
	if sh.has("at"):
		var at: Array = sh.at
		m.me.f.teleport(Vector3(float(at[0]), 0.0, float(at[1])))
		m.me.f.yaw = float(at[2])
		for e in m.entities:
			if e != m.me and is_instance_valid(e.f):
				e.f.teleport(Vector3(float(at[3]), 0.1, float(at[4])))
				e.f.yaw = float(at[5])
				break
	direct = OS.get_environment("CLIP_DIRECT") == "1" and PLANS.has(key)
	if direct:
		_direct_setup(key, sh)
	# The game's own music off: the trailer lays its score over the fight's sounds (the blows,
	# the cries, the crowd), which are kept.
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		AudioServer.set_bus_mute(mb, true)
	if menu.hud:
		menu.hud.visible = false
	m.cam.set_process(false)
	_best_picture()
	rec0 = Engine.get_frames_drawn()
	from = int(OS.get_environment("CLIP_FROM")) if OS.get_environment("CLIP_FROM") != "" else (from if direct else 0)
	get_viewport().disable_3d = OS.get_environment("CLIP_DRY") == "1" or from > 0
	_tag("REC_START %d" % rec0)
	if direct:
		_tag("FROM %d" % from)
	started = true
	# A war cry as he goes in.
	get_tree().create_timer(0.6).timeout.connect(func(): if m and m.me and is_instance_valid(m.me.f): m.say(m.me.f, "grunt", 1.0, "effort"))
	var dead := {}
	var t := 0.0
	var after := -1.0
	# CLIP_DIST=1: how far apart he and his foe stood through the bout (the fight scene's two
	# hugged each other: user), printed at the end.
	var dist_log := OS.get_environment("CLIP_DIST") == "1"
	var gaps := []
	var rads := []      # (and how far out from the middle of the sand the foe was: on the wall?)
	while t < seconds:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if direct:
			_direct_tick(t)
		if dist_log and int(t * 120.0) % 12 == 0:
			var ne = m.nearest_enemy(m.me)
			if ne and is_instance_valid(ne.f) and ne.f.alive and m.me.f.alive:
				var dd: Vector3 = ne.f.torso.global_position - m.me.f.torso.global_position
				gaps.append(Vector2(dd.x, dd.z).length())
				rads.append(Vector2(ne.f.torso.global_position.x, ne.f.torso.global_position.z).length())
		if from > 0 and _frame() >= from and get_viewport().disable_3d:
			get_viewport().disable_3d = false
		for e in m.entities:
			if is_instance_valid(e.f) and not e.f.alive and not dead.has(e.f):
				dead[e.f] = true
				_tag("DEATH %d %s %.1f" % [_frame(), str(e.kind), t])
				if after < 0.0 and e != m.me:
					after = t
		if after >= 0.0 and t - after > 3.0:
			break
	if dist_log and not gaps.is_empty():
		gaps.sort()
		var n_close := 0
		for g in gaps:
			if float(g) < 0.9:
				n_close += 1
		_tag("DIST median %.2f p10 %.2f p90 %.2f under0.9 %d%%" % [float(gaps[gaps.size() / 2]), float(gaps[gaps.size() / 10]), float(gaps[gaps.size() * 9 / 10]), 100 * n_close / gaps.size()])
		rads.sort()
		var walled := rads.filter(func(r): return float(r) > Arena.RADIUS - 2.5).size()
		_tag("FOE_R median %.2f p90 %.2f max %.2f near the wall %d%%" % [float(rads[rads.size() / 2]), float(rads[rads.size() * 9 / 10]), float(rads[rads.size() - 1]), 100 * walled / rads.size()])
	if direct and OS.get_environment("CLIP_DEBUG") == "1":
		_tag("FOE_TOP %.2f" % foe_top)
	_tag("REC_END %d" % _frame())
	get_tree().quit()

## ---------- the director (CLIP_DIRECT=1) ----------
## The bout goes by its plan (PLANS), not by the dice: it is filmed the first time, every time
## (user: the trailer's log, seed after seed tried, a cyclops filmed on no clean kill, the hydra
## never falling). Between the beats the two fight it out, the champion on his autopilot and the
## foe by his own lights, the foe kept on his feet; on each beat the champion steps in to his
## weapon's reach of the part the plan names, draws back and strikes through it with everything
## he has, the foe held still for it (caught between his own blows), the film camera in close.
## A blow that does not land is struck again; the last beat's ends it, on its blow. The bout is
## drawn from a little before the first beat (FROM), the kill and the blows tagged as they land:
## no dry run to find them, nothing to go another way when drawn.

func _direct_setup(key: String, sh: Dictionary) -> void:
	plan = PLANS[key]
	for e in m.entities:
		if e != m.me and is_instance_valid(e.f):
			foe_e = e
			break
	if foe_e == null:
		direct = false
		return
	foe = foe_e.f
	hero_arms = {"R": m.me.f.weapons.R, "L": m.me.f.weapons.L}
	hero_str = float(sh.get("strength", 1.8))
	# Between the beats he fights as a good man does, not a champion: the plan's blows are his
	# hardest, and none of his own ends it before the plan does.
	m.me.f.mods.strength = minf(hero_str, 1.4)
	var me = m.me
	me.drive = func(_e): return _hero_input()
	if foe_e.has("bot") and foe_e.bot != null:
		var fe = foe_e
		fe.drive = func(_e): return _foe_input()
	# Drawn from a little before the first beat.
	if OS.get_environment("CLIP_FROM") == "":
		from = maxi(1, int((float(plan[0][0]) - APPROACH - 1.6) * 120.0))
	# (Ended 3 s after the kill. Its blows struck again, a bout ran out of time with its kill to come.)
	seconds = float(plan.back()[0]) + 30.0

## The champion's hands: his autopilot between the beats, the plan's stroke on them.
func _hero_input() -> Dictionary:
	var hero: Fighter = m.me.f
	var fo = foe_e.f if foe_e != null and is_instance_valid(foe_e.f) else null
	if fo == null or not fo.alive or phase == "free" or phase == "done" or strike_part == null or not is_instance_valid(strike_part):
		var tl = fo if fo != null and fo.alive else null
		if tl:
			var dl: Vector3 = tl.torso.global_position - hero.torso.global_position
			hero.yaw = atan2(dl.x, dl.z)
		return m.me.bot.update(1.0 / 120.0, tl, m._world_of(m.me)) if m.me.has("bot") and m.me.bot else {}
	var b: Array = plan[beat]
	var at: Vector3 = strike_part.global_position
	var to: Vector3 = at - hero.torso.global_position
	var yaw := atan2(to.x, to.z)
	var stroke: String = b[2]
	var sk: Array = STROKES.get(stroke, STROKES.slashR)
	# The marks raised or lowered by how far the part stands above or below a man's (a giant's
	# knee, a lion's neck, a hydra's raised head; a giant brought down onto the sand).
	var off := clampf((at.y - hero.torso.global_position.y - float(sk[6]) * hero.S) / (0.45 * hero.S), -0.6, 1.0)
	# (A slash at a man's arm no higher than at his chest: raised to his shoulder, the stroke came
	# down through his head first.)
	if String(b[1]) == "arm":
		off = minf(off, 0.0)
	var inp := {"look": {"yaw": yaw, "pitch": clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.6, 0.6)}}
	var mz := 0.0
	if phase == "approach" or phase == "wind":
		var spot = _stand_spot()
		if spot != null:
			# (Round to it, facing the part all the way: first out from the body to the spot's own
			# distance from it, then along it. Straight at it, he walked into the giant's arm lying at
			# its side and pushed against it to the end.)
			var to_s: Vector3 = (spot as Vector3) - hero.torso.global_position
			to_s.y = 0.0
			var out: Vector3 = spot_side * spot_side.dot(to_s)
			if out.length() > 0.25 and spot_side.dot(to_s) > 0.0:
				to_s = out
			if to_s.length() > 0.08:
				var loc: Vector3 = Quaternion(Vector3.UP, yaw).inverse() * to_s.normalized() * clampf(to_s.length() / 0.4, 0.35, 1.0)
				inp["mx"] = loc.x
				mz = loc.z
		else:
			var flat := _part_flat()
			var want := _strike_reach()
			if flat > want + 0.04:
				mz = 1.0 if flat > want + 0.5 else 0.6
			elif flat < want - 0.14:
				mz = -0.8 if flat < want - 0.35 else -0.5
	inp["mz"] = mz
	var striking := phase == "stroke" or phase == "follow"
	# A thrust at a part below him is drawn back high and driven down into it (drawn back low, the
	# spear's point lay on the fallen cyclops' chest as he came in, held him off it, and each of
	# his thrusts only pushed on it).
	var wind_off := off if stroke != "thrust" or off >= 0.0 else -0.9 * off
	inp["main"] = {"x": float(sk[2]) if striking else float(sk[0]), "y": clampf((float(sk[3]) + off) if striking else (float(sk[1]) + wind_off), -1.6, 1.6)}
	if striking:
		inp["thrust"] = float(sk[4])
		if stroke == "thrust":
			inp["aimAt"] = at
	inp["power"] = striking
	return inp

## Where he stands for a blow at a giant down on the sand: beside the part, square to the line of
## the body, on his own side of it (gone straight at it, the cyclops' head beyond its body, he was
## stopped by the body two yards short of his blow, three times). Null when the foe is on his feet.
func _stand_spot():
	var fo = foe_e.f
	if not felled or not (fo is Fighter) or fo.state != "down" or strike_part == null or not is_instance_valid(strike_part):
		return null
	var at: Vector3 = strike_part.global_position
	var axis: Vector3 = at - fo.torso.global_position
	axis.y = 0.0
	if axis.length_squared() < 1e-4:
		return null
	axis = axis.normalized()
	var side := Vector3(-axis.z, 0.0, axis.x)
	if side.dot(m.me.f.torso.global_position - at) < 0.0:
		side = -side
	spot_side = side
	return at + side * (_strike_reach() + minf(strike_part.half_ext.x, strike_part.half_ext.z)) + axis * 0.15 * fo.S

## How far (flat) the part struck at is from his trunk, beyond its own half-width; and how far it
## should be for his blow: where the outer part of the blade, the fast one, meets it.
func _part_flat() -> float:
	var hero: Fighter = m.me.f
	var to: Vector3 = strike_part.global_position - hero.torso.global_position
	return Vector2(to.x, to.z).length() - minf(strike_part.half_ext.x, strike_part.half_ext.z)

func _strike_reach() -> float:
	var hero: Fighter = m.me.f
	var w: Weapon = hero.weapons.R
	var reach: float = float(w.reach) if w else 0.8
	var stroke: String = plan[beat][2] if beat < plan.size() else "slashR"
	return 0.35 * hero.S + reach * float(REACH_K.get(stroke, 0.55))

## The foe on a beat: still where he stands, facing the champion, his guard down (caught between
## his own blows); his own mind the rest of the time.
func _foe_input() -> Dictionary:
	var fo = foe_e.f
	var hero: Fighter = m.me.f
	var d: Vector3 = hero.torso.global_position - fo.torso.global_position
	var yaw := atan2(d.x, d.z)
	# A giant brought down lies where he fell for the blow to come (turned to face the champion
	# each moment, he swung round on the sand as the champion went round him to his head, and took
	# his head with him).
	if felled and fo.state != "stand":
		return {}
	if _held():
		fo.yaw = yaw
		# Caught as he draws back for a blow of his own: his blade down and out to his side (held on
		# his guard, it took the blow every time); for a blow at his leg, his hands up over him (the
		# hand hanging at his side took the sweep, twice in three); for one at an arm, that arm out
		# from his side.
		var inp := {"look": {"yaw": yaw, "pitch": 0.0}, "main": {"x": 0.9, "y": -0.9}}
		match String(plan[beat][1]) if beat < plan.size() else "":
			"leg":
				inp.main = {"x": 0.35, "y": 1.1}
				inp["off"] = {"x": -0.35, "y": 1.0}
			"arm":
				if strike_part != null and is_instance_valid(strike_part):
					if String(strike_part.part_name).ends_with(String(fo.two_side)):
						inp.main = {"x": 0.95, "y": 0.55}
					else:
						inp["off"] = {"x": -0.95, "y": 0.55}
		return inp
	fo.yaw = yaw
	fo.gaze = hero.head.global_position
	return foe_e.bot.update(1.0 / 120.0, hero, m._world_of(foe_e))

## Whether the foe is held still for the blow coming: only for the last moments of the champion's
## step in and his blow (held from the start of it, he stood a second and more waiting to be
## struck). A beast stands its ground for it (Match: a beast not told to fight).
func _held() -> bool:
	if phase == "wind" or phase == "stroke" or phase == "follow":
		return true
	return phase == "approach" and strike_part != null and is_instance_valid(strike_part) and _part_flat() <= _strike_reach() + 0.45

## Whether a blow on this part is the beat's: the part it struck at, or one of a piece with it
## (the neck or the jaw by a head, the forearm by an arm, the shin by a thigh). A blow that met
## another first is not it (the troll's last, a chop at its head on the sand, took its thigh on
## the way down and it died of that).
func _part_ok(p, J := 0.0) -> bool:
	if not (p is VoxelPart) or beat >= plan.size():
		return false
	if p == strike_part:
		return true
	var fo = foe_e.f
	var n := String(p.part_name).to_lower()
	var b: Array = plan[beat]
	var what := String(b[1])
	var at_head: bool = p == fo.head or n.contains("head") or n.begins_with("neck") or n.contains("jaw")
	if what == "head" or what == "neck":
		if at_head:
			return true
	elif what == "torso":
		return p == fo.torso
	elif not b.has("kill"):
		# A blow at a limb lands on whatever of him it meets first but his head, which is the
		# kill's (struck at the limb alone, a sweep at a man's leg met the hand hanging at his side
		# three times running, and was put home).
		return not at_head
	# His trunk does for a blow at the head that is not the kill; for the kill when the blow is a
	# hard one or the head has been missed once, or on a giant down on the sand. (A chop at the
	# head that came down on the chest, or the hammer on the troll's chest as he lay, three times
	# over, was not his death until it was put home.)
	return p == fo.torso and (not b.has("kill") or J >= 30.0 or tries >= 1 or felled)

## The part of the foe a beat strikes at: of its kind still on him, the nearest on the side the
## stroke comes in from (a slash in from his right, at the arm on his left, met the man's chest or
## his head on its way across and stopped there).
func _part_for(what: String, stroke := "") -> VoxelPart:
	var fo = foe_e.f
	var hero: Fighter = m.me.f
	var best: VoxelPart = null
	var bd := INF
	var hp: Vector3 = hero.torso.global_position
	var left := Vector3(cos(hero.yaw), 0.0, -sin(hero.yaw))   # (his right hand is on his -x)
	var from := 0.0
	match stroke:
		"slashR", "low":
			from = -1.0
		"slashL":
			from = 1.0
	for q in fo.parts:
		var p: VoxelPart = q
		if p.severed or p.missing:
			continue
		var n := String(p.part_name).to_lower()
		var ok := false
		match what:
			"arm":
				# (The upper arm: the forearm, held out on his guard, is behind his own blade.)
				ok = n.begins_with("upperarm") or (n.begins_with("arm") and not fo.by_name.has("upperArmR"))
			"leg":
				ok = n.begins_with("thigh") or (n.begins_with("leg") and not n.ends_with("lo"))
			"neck":
				ok = n.begins_with("neck") or (p == fo.head and not fo.by_name.has("neck"))
			"head":
				ok = p == fo.head or n.begins_with("head")
			"torso":
				ok = p == fo.torso
		if not ok:
			continue
		var dd: float = p.global_position.distance_to(hp)
		if from != 0.0:
			dd += 0.6 * clampf(-from * (p.global_position - hp).dot(left) / (0.15 * maxf(1.0, fo.S)), 0.0, 1.0)
		if dd < bd:
			bd = dd
			best = p
	if best == null:
		best = fo.head if not fo.head.severed else fo.torso
	return best

func _direct_tick(tt: float) -> void:
	t_now = tt
	if foe_e == null or not is_instance_valid(foe_e.f):
		return
	var fo = foe_e.f
	var hero: Fighter = m.me.f
	if not fo.alive:
		if not killed:
			killed = true
			if beat < plan.size():
				if landed >= 0:
					_end_beat(tt)
				else:
					_tag("DIRECT the foe died at %.2f s, on beat %d of %d before its blow" % [tt, beat, plan.size()])
			phase = "done"
			close_until = tt + CINE_AFTER
			cine_until = tt + CINE_AFTER
		return
	# Kept on his feet until the plan ends it: his blood and his life held up (the plan's blows
	# still cut and break and take limbs off).
	fo.blood = maxf(fo.blood, 55.0)
	fo.torso.hp = maxf(fo.torso.hp, 35.0)
	for hh in ([fo.head] + (fo.heads if fo.get("heads") is Array else [])):
		if is_instance_valid(hh) and not hh.severed:
			hh.hp = maxf(hh.hp, 35.0)
	if fo.get("heart_t") != null:
		fo.heart_t = -1.0
	if fo.get("dying") != null:
		fo.dying = 0.0
	if fo is Beast:
		foe_e["training"] = "stand" if _held() else "fights"
	foe_top = maxf(foe_top, fo.torso.global_position.y)
	# A giant brought down stays down for the blows after it (a man who can stand lies two seconds
	# at most: the cyclops was up again and his head out of reach when the kill came).
	if felled and fo is Fighter and fo.state == "down":
		fo.down_timer = maxf(fo.down_timer, 0.5)
	if beat >= plan.size():
		return
	var b: Array = plan[beat]
	var t0: float = float(b[0])
	phase_t += 1.0 / 120.0
	if OS.get_environment("CLIP_DEBUG") == "1" and phase != "free" and int(tt * 120.0) % 6 == 0 and strike_part != null and is_instance_valid(strike_part):
		print("DBG t=%.2f %s %.2f: %s %.2f off (wants %.2f), hand mark %s, blade gap %.2f, part at %+.2f of his trunk's height; he %s at %s moving %.2f m/s (mz %.2f mx %.2f), the foe %s, spot %s" % [tt, phase, phase_t, strike_part.part_name, _part_flat(), _strike_reach(), str(_hero_input().get("main", {})), _blade_gap(), strike_part.global_position.y - hero.torso.global_position.y, hero.state, str(hero.torso.global_position.snapped(Vector3.ONE * 0.01)), Vector2(hero.torso.linear_velocity.x, hero.torso.linear_velocity.z).length(), float(_hero_input().get("mz", 0.0)), float(_hero_input().get("mx", 0.0)), fo.state if fo is Fighter else "-", str(_stand_spot())])
	match phase:
		"free":
			# (A giant brought down is let come to rest first: he went down onto his knees and slumped
			# on over the next two seconds, the minotaur, and the blow at his head met his body.)
			var settling: bool = felled and fo is Fighter and tt < settle_until + 2.0 and (fo.head.linear_velocity.length() > 0.4 or fo.torso.linear_velocity.length() > 0.4)
			# A man knocked down by a blow that was not to bring him down is helped up and fought on
			# his feet (struck at as he lay, the exchange's head on the sand, the chop met his arm).
			var rising: bool = not felled and fo is Fighter and fo.state != "stand" and tt < t0 + 3.0
			if rising and fo.state == "down":
				fo.help_up()
			if tt >= t0 - APPROACH and tt >= settle_until and not settling and not rising:
				_rearm()
				strike_part = _part_for(String(b[1]), String(b[2]))
				phase = "approach"
				phase_t = 0.0
				landed = -1
				landed_on = ""
				tries = 0
				hero.mods.strength = hero_str
				close_until = maxf(close_until, tt + APPROACH + WIND + 0.3 + CLOSE_AFTER + (CINE_AFTER if b.has("kill") else 0.0))
				if b.has("kill"):
					cine_until = tt + 60.0   # (until he falls)
		"approach":
			# (Gone down as he came in, the beat waits for him to be up again.)
			if not felled and fo is Fighter and fo.state != "stand" and tt < t0 + 3.0:
				phase = "free"
				phase_t = 0.0
				return
			# (His weapon knocked from his hand or his arm broken as he went in, the minotaur's: the
			# rest of the beat was struck at it with an empty hand, three times, and put home.)
			if hero.weapons.R == null or hero.arm_broken("R"):
				_rearm()
			# Stepped into his blow's reach (or as near as the time lets him): the blow drawn back.
			if hero.state == "stand" and ((phase_t >= 0.25 and absf(_part_flat() - _strike_reach()) <= 0.14) or phase_t > APPROACH_MAX):
				phase = "wind"
				phase_t = 0.0
				close_until = maxf(close_until, tt + WIND + 0.3 + CLOSE_AFTER + (CINE_AFTER if b.has("kill") else 0.0))
		"wind":
			if phase_t >= WIND:
				phase = "stroke"
				phase_t = 0.0
		"stroke":
			if phase_t >= float((STROKES.get(String(b[2]), STROKES.slashR) as Array)[5]):
				phase = "follow"
				phase_t = 0.0
		"follow":
			if landed >= 0 and phase_t >= 0.25:
				_end_beat(tt)
			elif landed < 0 and phase_t >= 0.35:
				tries += 1
				if tries < TRIES:
					# Struck again: in to reach once more and drawn back.
					_rearm()
					strike_part = _part_for(String(b[1]), String(b[2]))
					phase = "approach"
					phase_t = 0.0
				else:
					_put_home(b)
					_end_beat(tt)

## (CLIP_DEBUG) How near his blade comes to the part struck at: its nearest cube to the part's box.
func _blade_gap() -> float:
	var w: Weapon = m.me.f.weapons.R
	if w == null or strike_part == null or not is_instance_valid(strike_part):
		return -1.0
	var xf: Transform3D = w.global_transform
	var inv: Transform3D = strike_part.global_transform.affine_inverse()
	var he: Vector3 = strike_part.half_ext
	var best := INF
	for i in w.vox.size():
		if not w.alive[i]:
			continue
		var lp: Vector3 = inv * (xf * (Vector3(w.vox[i][0], w.vox[i][1], w.vox[i][2]) * w.vs))
		best = minf(best, Vector3(maxf(absf(lp.x) - he.x, 0.0), maxf(absf(lp.y) - he.y, 0.0), maxf(absf(lp.z) - he.z, 0.0)).length())
	return best

## The champion is the champion to the end of it: an arm broken under the foe's blows, and the
## sword fallen from it, are made good as the camera cuts in for his next blow (the sword lay on
## the sand and the last blow of the plan was struck with an empty hand).
func _rearm() -> void:
	var hero: Fighter = m.me.f
	# A blade driven into him and stuck there is pulled out for the next blow (the spear left in the
	# cyclops' chest held the champion off him, and three thrusts after it went nowhere).
	for side in ["R", "L"]:
		var sw = hero.weapons[side]
		if sw != null and is_instance_valid(sw) and sw.stuck != null:
			sw.unstick()
	var lost := false
	var broke := false
	for side in ["R", "L"]:
		var w = hero_arms.get(side)
		if (w != null and hero.weapons[side] != w) or hero.arm_broken(side):
			lost = true
		var h = hero.weapons[side]
		if h != null and is_instance_valid(h) and not h.is_shield and h.reach < h.reach_full * 0.85:
			broke = true
	if lost or broke:
		_tag("REARM%s%s" % [" (a weapon lost or an arm broken)" if lost else "", " (a weapon broken)" if broke else ""])
	if lost:
		hero.bind_wounds()
		for side in ["R", "L"]:
			var w = hero_arms.get(side)
			if w != null and is_instance_valid(w) and hero.weapons[side] == null and (w.holder == null or w.holder == hero):
				hero.pick_up(side, w)
	# A weapon broken under the blows is had afresh, as it was made (the troll's: the hammer's head
	# broke off at the haft, and the last blows were struck with the stump).
	if broke:
		var was_two := hero.two_handed
		var d := {}
		for side in ["R", "L"]:
			var w = hero_arms.get(side)
			d[side] = (w.design as Dictionary).duplicate(true) if w != null and is_instance_valid(w) else {}
		hero.rearm(d.R, d.L)
		if was_two and not hero.two_handed:
			hero.toggle_grip()
		hero_arms = {"R": hero.weapons.R, "L": hero.weapons.L}

## The beat's blow has landed: what it is to do beyond the blow itself.
func _landed(h: Dictionary) -> void:
	var b: Array = plan[beat]
	_tag("CLOSE %d" % landed)
	var fo = foe_e.f
	if b.has("fell") and fo.has_method("fall"):
		fo.fall(3.5, true)
		felled = true
	if b.has("kill"):
		_tag("BLOW %d" % landed)
		if fo.alive:
			fo.spared = true
			fo.die("trailer")

## A blow that would not land, three times over: put home where the plan says (rare: a beast that
## would not stand, a giant's swing in the way), as hard as his own.
func _put_home(b: Array) -> void:
	var fo = foe_e.f
	var hero: Fighter = m.me.f
	var p: VoxelPart = strike_part if is_instance_valid(strike_part) and not strike_part.severed else fo.torso
	var from_h: Vector3 = hero.torso.global_position
	var dir: Vector3 = (p.global_position - from_h)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3(0, 0, 1)
	var at: Vector3 = p.global_position - dir * minf(p.half_ext.x, p.half_ext.z)
	var w: Weapon = hero.weapons.R
	var blunt: bool = w != null and not w.bites()
	var hit := {"point": at, "dir": dir, "type": "blunt" if blunt else "edge", "hardness": 0.9, "sharpness": 0.0 if blunt else 0.9, "impulse": 45.0, "heavy": 0.6, "axis": Vector3.UP, "edge": dir, "weapon": true, "mass": w.mass if w else 1.5}
	var res: Dictionary = fo.apply_hit(p, hit)
	if Combat.current:
		Combat.current.hit.emit({"kind": "hit", "p": at, "dir": dir, "J": 45.0, "type": hit.type, "char": fo, "part": p, "attacker": hero, "res": res, "killed": not fo.alive})
	if landed < 0:
		landed = _frame()
		landed_on = String(p.name)
		_landed({})

func _end_beat(tt: float) -> void:
	var b: Array = plan[beat]
	_tag("DIRECT beat %d at %.2f s (planned %.1f): %s %s, landed on the %s on frame %d after %d tries%s, the foe %s" % [beat, tt, float(b[0]), b[1], b[2], landed_on, landed, mini(tries + 1, TRIES), " (put home)" if tries >= TRIES else "", "alive" if foe_e.f.alive else "dead"])
	beat += 1
	phase = "free" if beat < plan.size() else "done"
	phase_t = 0.0
	strike_part = null
	m.me.f.mods.strength = minf(hero_str, 1.4)
	if b.has("kill"):
		close_until = maxf(close_until, tt + CINE_AFTER)
	# (Struck at while he was still going down, the troll's head was a yard further off by the
	# time the blow fell, and it fell on nothing.)
	if b.has("fell"):
		settle_until = tt + SETTLE

## The best the game draws: MSAA, the voxels' corner shading, the 3D supersampled.
func _best_picture() -> void:
	if OS.get_environment("CLIP_DRY") == "1":
		return
	menu.apply_picture({"aa": OS.get_environment("TRAILER_AA") if OS.get_environment("TRAILER_AA") != "" else "msaa4", "voxelAO": true})
	var vp := get_viewport()
	var ss := float(OS.get_environment("TRAILER_SSAA")) if OS.get_environment("TRAILER_SSAA") != "" else 1.5
	if ss > 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = ss
	attrs = CameraAttributesPractical.new()

func _frame() -> int:
	return Engine.get_frames_drawn() - rec0

var cry_t := {}
func _on_hit(h: Dictionary) -> void:
	var J := float(h.get("J", 0.0))
	if m and m.me and (h.get("attacker") == m.me.f or h.get("char") == m.me.f):
		trauma = minf(1.0, trauma + clampf(J / 60.0, 0.0, 0.8))
	if J >= 20.0:
		# HIT <frame> <J> <the hero's blow: 1> <limbs it took off> <the part struck>: the editor
		# picks the hero's own clean blows, and those that take a limb off first.
		var sev: Array = (h.get("res", {}) as Dictionary).get("severed", []) if h.get("res") is Dictionary else []
		var pt = h.get("part")
		_tag("HIT %d %d %d %d %s" % [_frame(), int(J), 1 if (m and m.me and h.get("attacker") == m.me.f) else 0, sev.size(), String(pt.name) if pt is Node else "-"])
	if direct and landed < 0 and (phase == "stroke" or phase == "follow") and m and m.me and h.get("attacker") == m.me.f and foe_e != null and h.get("char") == foe_e.f and J >= 14.0 and _part_ok(h.get("part"), J):
		landed = _frame()
		landed_on = String(h.part.name)
		_landed(h)
	# The trailer is loud with the fight: the hero roars into his blows, and whoever is struck
	# cries out (men, giants and beasts in their own voices), more often and louder than in play.
	# (The game's own clock, not the wall's: the dry pass and the drawn one must cry out alike.)
	var now := float(Engine.get_physics_frames()) / 120.0
	var a = h.get("attacker")
	var c = h.get("char")
	if a == m.me.f and J > 12.0 and now - float(cry_t.get(a, -9.0)) > 1.1:
		cry_t[a] = now
		m.say(a, "grunt", 0.85, "effort")
	if c != null and is_instance_valid(c) and J > 8.0 and now - float(cry_t.get(c, -9.0)) > 0.8:
		cry_t[c] = now
		var grave: bool = bool(h.get("killed", false)) or not (h.get("res", {}) as Dictionary).get("severed", []).is_empty()
		m.say(c, Voices.hurt_call(c, J, grave), 0.9 if grave else 0.7, "grave" if grave else ("hurt" if J > 14.0 else "grunt"))

func _process(dt: float) -> void:
	if not started or m == null or m.me == null or not is_instance_valid(m.me.f):
		return
	t_cam += dt
	var f := _frame()
	# (From a little before the blow that felled him, when that came before he fell, through his fall.)
	var k0 := blow if blow > 0 and blow < kill else kill
	var in_kill := kill > 0 and f >= k0 - int(CINE_BEFORE * 120.0) and f < kill + int(CINE_AFTER * 120.0)
	for c in close:
		if f >= int(c) - int(CLOSE_BEFORE * 120.0) and f < int(c) + int(CLOSE_AFTER * 120.0):
			in_kill = true
	if direct:
		# (Through the film camera every beat is seen close; from the helmet, only the kill is
		# cut to the film camera, as it was.)
		in_kill = t_now < (close_until if film else cine_until)
	var want := "pov"
	if film:
		want = "cine" if in_kill else "wide"
		# The wide framing set afresh where the drawing starts (the bout before it is unseen).
		if from > 0 and f >= from and not film_fresh:
			film_fresh = true
			mode = ""
	elif cine and in_kill:
		want = "cine"
	if want != mode:
		var was := mode
		mode = want
		if mode == "cine" or mode == "wide":
			# A cut between the film camera's two framings keeps to the same side of the line
			# between them (crossing it would turn the fight round on the screen).
			_start_cine(was == "wide" or was == "cine")
		else:
			cam_pos = Vector3.ZERO   # (the helmet's camera starts clean where it is)
			m.cam.attributes = null
	if mode == "cine" or mode == "wide":
		_cine(dt)
	else:
		_pov(dt)

## A camera strapped to the right side of his helmet, as a GoPro is (user): it sits on the head
## and turns with it, looking where he looks, a wide lens that takes in the blade in his fist and
## the man in front of him.
func _pov(dt: float) -> void:
	var a: Fighter = m.me.f
	var hp: VoxelPart = a.head if not a.head.severed else a.torso
	var head: Vector3 = hp.global_position
	# (His right is the head's -x, his front +z.)
	var hb: Basis = hp.global_basis.orthonormalized()
	var hfwd: Vector3 = hb * Vector3(0, 0, 1)
	var body_fwd := Vector3(sin(a.yaw), 0, cos(a.yaw))
	if hfwd.dot(body_fwd) < 0.2:
		hfwd = body_fwd   # (the head knocked about or down: the body's line until it comes back)
	# A head thrown back by a blow had the lens on the sky: it keeps nearer his line and the
	# horizon than the head itself does.
	hfwd = (hfwd * 0.6 + body_fwd * 0.4).normalized()
	var ne = m.nearest_enemy(m.me)
	if ne and is_instance_valid(ne.f) and ne.f.alive:
		# His eyes are on the man: the lens leans a little his way.
		var to_f: Vector3 = (ne.f.torso.global_position - head).normalized()
		hfwd = hfwd.lerp(to_f, 0.2).normalized()
	elif kill > 0 and _frame() >= kill and foe != null and is_instance_valid(foe):
		# The foe down: he looks down at what he felled.
		var to_d: Vector3 = (foe.torso.global_position - head).normalized()
		hfwd = hfwd.lerp(to_d, 0.45).normalized()
	var hup: Vector3 = hb * Vector3(0, 1, 0)
	# Out from the side of the helmet on its mount and a little forward, so the helmet's edge
	# is only the rim of the frame.
	var side: float = hp.half_ext.x + (0.14 if a.armor_kg > 0.0 else 0.11)
	var mount: Vector3 = hp.global_transform * Vector3(-side, hp.half_ext.y * 0.7, hp.half_ext.z * 0.4)
	# The jolt of a blow given or taken, dying away.
	trauma = maxf(0.0, trauma - dt * 1.6)
	var j := trauma * trauma
	var jolt := Vector3(sin(t_cam * 37.0), sin(t_cam * 43.0 + 1.0), sin(t_cam * 29.0 + 2.0)) * 0.05 * j
	if cam_pos == Vector3.ZERO:
		cam_pos = mount
		cam_look = hfwd
		cam_up = hup
	# Rigid on the head: the position follows at once, the turn a little smoothed (a head jitters
	# more than a camera on it shows).
	cam_pos = cam_pos.lerp(mount, minf(1.0, dt * 30.0))
	cam_look = cam_look.lerp(hfwd, minf(1.0, dt * 12.0)).normalized()
	cam_up = cam_up.lerp(hup.lerp(Vector3.UP, 0.6), minf(1.0, dt * 10.0)).normalized()
	var cam: Camera3D = m.cam
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 80.0
	cam.near = 0.03
	cam.global_position = cam_pos + jolt
	var look_at_p: Vector3 = cam_pos + cam_look * 4.0 + Vector3(sin(t_cam * 31.0), sin(t_cam * 41.0), 0) * 0.15 * j
	cam.look_at(look_at_p, cam_up if absf(cam_look.dot(cam_up)) < 0.95 else Vector3.UP)
	cam.reset_physics_interpolation()

## The film camera comes in: on the side of the line between them that has the arena's middle
## behind it (the stands, not the wall, in the lens), low, as far off as a long lens wants.
func _start_cine(keep_side := false) -> void:
	var ne = m.nearest_enemy(m.me)
	foe = ne.f if ne and is_instance_valid(ne.f) else foe
	cine_t = 0.0
	cine_pos = Vector3.ZERO
	var a: Fighter = m.me.f
	if foe == null or keep_side:
		return
	var d: Vector3 = foe.torso.global_position - a.torso.global_position
	d.y = 0.0
	var s := Vector3.UP.cross(d.normalized())
	cine_side = 1.0 if s.dot(-a.torso.global_position) >= 0.0 else -1.0

func _cine(dt: float) -> void:
	var a: Fighter = m.me.f
	if foe == null or not is_instance_valid(foe):
		_pov(dt)
		return
	cine_t += dt
	var ha: Vector3 = a.torso.global_position
	var hf: Vector3 = foe.torso.global_position
	var fs: float = maxf(1.0, float(foe.S))
	var d := hf - ha
	d.y = 0.0
	var dist := maxf(0.6, d.length())
	d = d.normalized() if d.length_squared() > 1e-6 else Vector3(0, 0, 1)
	var s := Vector3.UP.cross(d) * cine_side
	# What it looks at: between them, nearer the foe, at the height of a man's chest (a giant's
	# belly); how far off it stands: far enough for both in a long lens.
	var mid: Vector3 = ha.lerp(hf, 0.58)
	mid.y = maxf(0.9, lerpf(ha.y, hf.y, 0.5) * 0.85)
	var span := dist + 1.2 * fs
	# (The wide framing of the crowd trailer's film camera: as far again, a little higher, a
	# little wider, drifting more slowly.)
	var wide := mode == "wide"
	var fov := 34.0 + 6.0 * clampf(fs - 1.0, 0.0, 2.0) + (8.0 if wide else 0.0)
	var back := span * 0.5 / tan(deg_to_rad(fov) * 0.5) * (1.6 if wide else 1.15)
	# Drifting round them, slowly, and in a little: a dolly on a curved track.
	var turn := -0.2 + cine_t * (0.07 if wide else 0.12)
	var off := (s * cos(turn) - d * sin(turn)).normalized() * back * (1.0 - 0.06 * minf(1.0, cine_t / 2.0))
	var want := mid + off + Vector3(0, -0.35 + 0.25 * fs + (0.6 if wide else 0.0), 0)
	want.y = maxf(0.35, want.y)
	# Inside the ring's wall.
	var flat := Vector2(want.x, want.z)
	if flat.length() > 13.5:
		flat = flat.normalized() * 13.5
		want = Vector3(flat.x, want.y, flat.y)
	if cine_pos == Vector3.ZERO:
		cine_pos = want
	cine_pos = cine_pos.lerp(want, minf(1.0, dt * 4.0))
	# A hand on the camera: a slow breath of drift.
	var breathe := Vector3(sin(cine_t * 1.3), sin(cine_t * 1.7 + 1.0) * 0.6, sin(cine_t * 1.1 + 2.0)) * 0.025
	# The film camera of the crowd trailer takes the hardest blows too: a short jolt, dying away
	# (an operator's camera on the sand, not a locked-off one).
	var shake := Vector3.ZERO
	if film:
		trauma = maxf(0.0, trauma - dt * 2.4)
		var j := trauma * trauma
		shake = Vector3(sin(t_cam * 41.0), sin(t_cam * 47.0 + 1.0), sin(t_cam * 37.0 + 2.0)) * 0.04 * j
	var cam: Camera3D = m.cam
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = fov
	cam.near = 0.05
	cam.global_position = cine_pos + breathe + shake
	cam.look_at(mid + Vector3(0, 0.1 * fs, 0), Vector3.UP)
	cam.reset_physics_interpolation()
	# The depth of a long lens: what is beyond them melts away.
	if attrs:
		var focus := cine_pos.distance_to(mid)
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = focus + 1.5 * fs
		attrs.dof_blur_far_transition = 4.0 * fs
		attrs.dof_blur_near_enabled = true
		attrs.dof_blur_near_distance = maxf(0.3, focus - 2.5 * fs)
		attrs.dof_blur_near_transition = 1.0
		attrs.dof_blur_amount = 0.08
		cam.attributes = attrs

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
