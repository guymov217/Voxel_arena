class_name KillCam
extends Node
## The kill cam (killcam.js). The match is recorded all the time: 30 times a second, where every
## body part and weapon is, kept for seven seconds. Each kill is scored for how fine or how
## funny it was (a head off, a throw, a punch, a giant brought down, a friend killed by mistake)
## and cut into a clip, from three seconds before the blow to a second and a half after. When
## the match ends the best clip is shown: time stops, the bodies are put back where they were and
## played forward, slowing right down around the blow, the camera circling the killer and the
## victim, black bars and a caption on screen. The voxels keep the damage they ended with. The
## blasts, flashes and sprays of the clip are on tape too and are made again as it plays (a pot's
## blast went unseen in it: user). The clip shown is the cleanest kill: the one whose killing blow
## took the biggest piece off the man (user: the blow of the kill, nothing before it).

const RATE := 1.0 / 30.0
const KEEP := 7.0
const BEFORE := 3.0
const AFTER := 1.5

var m: Node
var frames: Array = []          # {t, xf: {instance_id: Transform3D}}
var acc := 0.0
var pending: Array = []         # kills waiting for their AFTER seconds
var best: Dictionary = {}       # {score, caption, frames, t_blow, killer, victim}
var clips: Array = []           # the best few clips cut so far (online the host names the one shown)
var playing := false
var overlay: CanvasLayer = null
var vox_log: Array = []         # {t, part, idx}: every voxel lost while on tape, to put back and take again
var fx_log: Array = []          # {t, fn, args}: every burst and flash while on tape (Fx.tape), made again in the replay
var _heard := {}                # fighters whose voxel losses are on tape
## A blow this long before the death is the killing blow (a leg taken off, the man down and dead
## of it a moment later); one longer before it is not (he bled out of it, or died of another).
const KILL_BLOW_S := 1.0

func _init(match_: Node) -> void:
	m = match_
	name = "KillCam"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	if m.get("fx") != null and m.fx:
		m.fx.tape = _on_fx

## A burst or a flash as it is made (Fx.tape): on tape with its time.
func _on_fx(fn: String, args: Array) -> void:
	if playing:
		return
	fx_log.append({"t": m.time, "fn": fn, "args": args})

## How good a kill was, and the line under the replay.
static func score_kill(k: Dictionary) -> Dictionary:
	var v: String = k.get("victim", "someone")
	var a = k.get("killer")
	var score := 10.0
	var caption: String = (Loc.t("%s killed %s") % [a, v]) if a else (Loc.t("%s died") % v)
	var best_pts := 0.0
	var picks := []
	if k.get("out", false): picks.append([12.0, (Loc.t("%s beat %s senseless") % [a, v]) if a else (Loc.t("%s is out of the fight") % v)])
	if k.get("big", false): picks.append([30.0, Loc.t("%s brought down the mighty %s") % [a if a else Loc.t("The arena"), v]])
	if k.get("burning", false): picks.append([20.0, (Loc.t("%s burned, courtesy of %s") % [v, a]) if a else (Loc.t("%s burned") % v)])
	if k.get("unarmed", false) and a: picks.append([25.0, Loc.t("%s punched %s to death") % [a, v]])
	if k.get("thrown", false) and a: picks.append([30.0, (Loc.t("%s threw a %s right into %s") % [a, String(k.weapon), v]) if k.get("weapon") else (Loc.t("%s threw something right into %s") % [a, v])])
	if k.get("friendly", false) and a: picks.append([28.0, Loc.t("%s killed %s. They were on the same side") % [a, v]])
	if k.get("self", false): picks.append([32.0, Loc.t("%s managed to kill themselves") % v])
	if k.get("decap", false): picks.append([40.0, ((Loc.t("%s took %s's head off with a %s") % [a, v, String(k.weapon)]) if k.get("weapon") else (Loc.t("%s took %s's head off") % [a, v])) if a else (Loc.t("%s lost their head") % v)])
	if int(k.get("multi", 1)) > 1: picks.append([18.0 * (int(k.multi) - 1), Loc.t("%s: two kills in a breath" if int(k.multi) == 2 else ("%s: three kills in a breath" if int(k.multi) == 3 else "%s: a heap of kills in a breath")) % a])
	for p in picks:
		score += p[0]
		if p[0] >= best_pts:
			best_pts = p[0]
			caption = p[1]
	score += minf(30.0, float(k.get("severed", 0)) * 12.0)
	if float(k.get("J", 0.0)) > 30.0:
		score += minf(15.0, (float(k.J) - 30.0) * 0.5)
	# The cleanest kill first, whatever else the others had: a piece taken off by the killing blow
	# itself puts a kill above every kill without one, and the bigger the piece (of the whole man)
	# the higher (user).
	var piece := float(k.get("piece", 0.0))
	if piece > 0.0:
		score += PIECE_FIRST + PIECE_FIRST * piece
	return {"score": score, "caption": caption}

## What a piece off the man in the killing blow puts a kill above (more than every other point
## of a kill together).
const PIECE_FIRST := 1000.0

## The share of the man (by his voxels' volume) the biggest piece his killing blow took off made:
## a part cut off, with whatever hung from it (an arm with its hand, a leg with its foot). 0 when
## the blow took nothing off.
static func piece_of(f, hit: Dictionary) -> float:
	var res = hit.get("res")
	if not (res is Dictionary) or not (res.get("severed") is Array) or (res.severed as Array).is_empty():
		return 0.0
	var vol := func(p) -> float:
		var e: float = float(p.vf) * float(p.part_scale)
		return float(p.alive_count) * e * e * e
	var whole := 0.0
	for p in f.parts:
		if is_instance_valid(p):
			whole += vol.call(p)
	if whole <= 0.0:
		return 0.0
	var best := 0.0
	for cut in res.severed:
		if not is_instance_valid(cut):
			continue
		var v: float = vol.call(cut)
		for p in f.parts:
			if not is_instance_valid(p) or p == cut:
				continue
			var up = p.parent_part
			while up != null and up != cut:
				up = up.parent_part
			if up == cut and (not p.severed or (res.severed as Array).has(p)):
				v += vol.call(p)
		best = maxf(best, v)
	return clampf(best / whole, 0.0, 1.0)

func _bodies() -> Array:
	var out := []
	for e in m.entities:
		if not is_instance_valid(e.f):
			continue
		for p in e.f.parts:
			if is_instance_valid(p):
				out.append(p)
		for side in e.f.weapons:
			if e.f.weapons[side] and is_instance_valid(e.f.weapons[side]):
				out.append(e.f.weapons[side])
	for w in m.combat.loose_weapons:
		if is_instance_valid(w):
			out.append(w)
	# The lumps knocked off them (and the chips off a blade), flying as they flew.
	for c in Chunk.all:
		if is_instance_valid(c) and c.is_inside_tree():
			out.append(c)
	# The pots, darts and every thing thrown, in the air or on the sand.
	if m.get("items") != null:
		for it in m.items.list:
			if it.node and is_instance_valid(it.node):
				out.append(it.node)
	return out

## Shown only where the tape has it (a lump not yet knocked off, a pot not yet thrown or already
## in pieces is not there at that moment of the clip).
static func _comes_and_goes(b) -> bool:
	return b is Chunk or (b is Node3D and b.is_in_group("kc_item"))

func _physics_process(dt: float) -> void:
	if playing:
		return
	acc += dt
	if acc < RATE:
		return
	acc = 0.0
	var xf := {}
	for b in _bodies():
		xf[b.get_instance_id()] = b.global_transform
	frames.append({"t": m.time, "xf": xf})
	while not frames.is_empty() and m.time - float(frames[0].t) > KEEP:
		frames.pop_front()
	while not vox_log.is_empty() and m.time - float(vox_log[0].t) > KEEP + 1.0:
		vox_log.pop_front()
	while not fx_log.is_empty() and m.time - float(fx_log[0].t) > KEEP + 1.0:
		fx_log.pop_front()
	for e in m.entities:
		if is_instance_valid(e.f) and not _heard.has(e.f.get_instance_id()) and e.f.has_signal("voxels_lost"):
			_heard[e.f.get_instance_id()] = true
			e.f.voxels_lost.connect(_on_voxels_lost)
	for k in pending.duplicate():
		if m.time - float(k.t) >= AFTER:
			pending.erase(k)
			_cut(k)

## A voxel lost (cut, crushed, burnt away): on tape with its time, so the replay shows the body
## whole until the blow and the wound opening as it did.
func _on_voxels_lost(f, part_index: int, indices: Array, _voxels: Array) -> void:
	if playing or not is_instance_valid(f) or part_index < 0 or part_index >= f.parts.size() or indices.is_empty():
		return
	vox_log.append({"t": m.time, "part": f.parts[part_index], "idx": indices.duplicate()})

## A death: what kind of kill it was, scored; cut once the aftermath is on tape.
## (On a guest the host names the killer, the weapon and whether it was thrown: `by`, `wname`,
## `thrown`.) `last_hit.at`, when the blow came: a man beaten senseless is put on tape from it.
func on_death(f, cause: String, last_hit: Dictionary, by = null, wname := "", thrown := false) -> void:
	if playing:
		return
	var killer = by if by != null else f.get("last_attacker")
	var kname = killer.display_name if killer and is_instance_valid(killer) and killer != f else null
	var severed := 0
	for p in f.parts:
		if p.severed:
			severed += 1
	var w = last_hit.get("weapon")
	var wn = Loc.lower(String(w.design.get("name", ""))) if w != null and is_instance_valid(w) else (wname if wname != "" else null)
	# The killing blow: the last one, if it came at the death (not a wound he bled out of later).
	# A clip of a piece taken off is cut round the blow, its slow motion on the cut itself.
	var at := float(last_hit.get("at", m.time))
	var piece := piece_of(f, last_hit) if m.time - at <= KILL_BLOW_S else 0.0
	var k := {"t": at if cause == "out" or piece > 0.0 else m.time, "out": cause == "out", "victim": f.display_name, "killer": kname, "decap": cause == "decap" or (f.head and f.head.severed), "piece": piece,
		"big": f.S >= 1.8 or f.boss, "burning": f.parts.any(func(p): return not p.spots.is_empty()),
		"unarmed": killer is Fighter and is_instance_valid(killer) and killer.weapons.get("R") == null and killer.weapons.get("L") == null,
		"thrown": thrown or (w != null and is_instance_valid(w) and w.holder == null), "weapon": wn,
		"self": killer == f, "friendly": killer is Fighter and is_instance_valid(killer) and killer != f and killer.team == f.team,
		"severed": severed, "J": float(last_hit.get("J", 0.0)),
		"killer_node": killer, "victim_node": f}
	pending.append(k)
	# On the Steam recording's timeline, so the moment is easy to find and clip.
	var sc := score_kill(k)
	Net.timeline_event(Loc.t("Kill"), String(sc.caption), 2 if float(sc.score) >= 40.0 else 1)

func _cut(k: Dictionary) -> void:
	var sc := score_kill(k)
	var clip: Array = frames.filter(func(fr): return float(fr.t) >= float(k.t) - BEFORE and float(fr.t) <= float(k.t) + AFTER)
	if clip.size() < 10:
		return
	clips.append({"score": sc.score, "caption": sc.caption, "frames": clip, "t_blow": k.t, "killer": k.killer_node, "victim": k.victim_node})
	clips.sort_custom(func(a, b): return float(a.score) > float(b.score))
	clips = clips.slice(0, 6)
	best = clips[0]

## Online: the one kill the host named as the fight's best (its victim), the same on every
## screen; false (and nothing to show) if it is not on this tape.
func choose(victim) -> bool:
	for c in clips:
		if c.victim == victim:
			best = c
			return true
	best = {}
	return false

## How long the last kill still needs on tape before it can be cut (0 when nothing waits).
func tape_left() -> float:
	var left := 0.0
	for k in pending:
		left = maxf(left, AFTER - (m.time - float(k.t)))
	return maxf(0.0, left)

## Whether there is a clip worth showing; the kill must have been on tape long enough.
func has_clip(min_score := 10.0) -> bool:
	for k in pending.duplicate():
		pending.erase(k)
		_cut(k)
	return not best.is_empty() and float(best.score) >= min_score

## A fresh tape for the next round: its best kill is its own.
func reset() -> void:
	clips.clear()
	best = {}
	pending.clear()

## Plays the best clip, then calls `done`. After it every body is put back where it is now,
## moving as it was, whether the fight goes on (between rounds) or is over: left as the clip's
## last moment had them, the dead stood up again behind the result (user: a hyena killed before
## the kill cam was on its feet after it). `force` plays it in a headless match (the tests).
func play(done: Callable, force := false) -> void:
	if best.is_empty() or (m.headless and not force):
		done.call()
		return
	playing = true
	if m.cam:
		m.cam.clear_fade()   # (the replay shows him whole, not seen through as the fight camera had him)
	var tree := m.get_tree()
	tree.paused = true
	var ids := {}
	var now := {}
	for b in _bodies():
		ids[b.get_instance_id()] = b
		now[b] = [b.global_transform, b.linear_velocity, b.angular_velocity] if b is RigidBody3D else [b.global_transform]
	# The things thrown that are gone now (a pot in pieces) still fly in the replay.
	if m.get("items") != null:
		for g in m.items.ghosts:
			if is_instance_valid(g[0]):
				ids[g[0].get_instance_id()] = g[0]
	var fov0: float = m.cam.fov if m.cam else 0.0
	_overlay(String(best.caption))
	var fr: Array = best.frames
	var t0: float = fr[0].t
	var t1: float = fr[fr.size() - 1].t
	# The wounds as they were when the clip begins: every voxel lost since put back (last lost
	# first), then taken again at its moment as the clip plays.
	var redo: Array = vox_log.filter(func(ev): return float(ev.t) > t0 and is_instance_valid(ev.part))
	for k in range(redo.size() - 1, -1, -1):
		redo[k].part.restore_voxels(redo[k].idx)
	var next_ev := 0
	# The blasts, flashes and sprays of the clip, made again at their moments, in slow motion with
	# the rest (the game is paused round them: they run on their own).
	var fx_ev: Array = fx_log.filter(func(ev): return float(ev.t) > t0 and float(ev.t) <= t1)
	var next_fx := 0
	var live_fx: Array = []   # [node, its moment, its own speed (a burst) or strength (a flash)]
	var tb: float = best.t_blow
	var t := t0
	var orbit := 0.0
	var cam: Camera3D = m.cam
	# A skip is a fresh press: the key held down as the clip begins (the kick that killed) does
	# not skip it unseen.
	var armed := not _skip_held()
	while t < t1 and is_instance_valid(m):
		var dt := m.get_process_delta_time() if m.get_process_delta_time() > 0.0 else 1.0 / 60.0
		# Slow right down around the blow.
		var near := absf(t - tb)
		var speed := 0.22 if near < 0.5 else (0.6 if near < 1.0 else 1.0)
		t += dt * speed
		var i := 0
		while i < fr.size() - 2 and float(fr[i + 1].t) < t:
			i += 1
		var a: Dictionary = fr[i]
		var b2: Dictionary = fr[mini(i + 1, fr.size() - 1)]
		var span := maxf(0.0001, float(b2.t) - float(a.t))
		var u := clampf((t - float(a.t)) / span, 0.0, 1.0)
		while next_ev < redo.size() and float(redo[next_ev].t) <= t:
			if is_instance_valid(redo[next_ev].part):
				redo[next_ev].part.remove_voxels(redo[next_ev].idx, false, false)
			next_ev += 1
		while next_fx < fx_ev.size() and float(fx_ev[next_fx].t) <= t:
			live_fx.append_array(_fx_again(fx_ev[next_fx]))
			next_fx += 1
		for lf in live_fx:
			var nd = lf[0]
			if not is_instance_valid(nd):
				continue
			if nd is GPUParticles3D:
				nd.speed_scale = float(lf[2]) * speed
			elif nd is OmniLight3D:
				nd.light_energy = float(lf[2]) * maxf(0.0, 1.0 - (t - float(lf[1])) / Fx.FLASH_FADE)
		for id in ids:
			var body = ids[id]
			if not is_instance_valid(body):
				continue
			# A piece not yet knocked off at this moment of the clip is not there yet.
			if not a.xf.has(id) and not b2.xf.has(id):
				if _comes_and_goes(body):
					body.visible = false
				continue
			if _comes_and_goes(body):
				body.visible = true
			var xa: Transform3D = a.xf.get(id, b2.xf.get(id))
			var xb: Transform3D = b2.xf.get(id, xa)
			body.global_transform = xa.interpolate_with(xb, u)
			# (Drawn here: with the game paused the bodies' own drawing does not follow them.)
			if body.has_method("draw_now"):
				body.draw_now()
			elif _comes_and_goes(body):
				body.reset_physics_interpolation()
		# The camera circles the pair, close, a little low.
		var pk = best.killer
		var pv = best.victim
		var c := Vector3(0, 1, 0)
		if pv and is_instance_valid(pv):
			c = pv.torso.global_position
			if pk and is_instance_valid(pk) and pk != pv:
				c = (c + pk.torso.global_position) * 0.5
		# E (the use key, as bound) or Esc skips it. (Space, Enter and a click did too: held in the
		# fight's last blow, they skipped the clip before it was seen.)
		if armed and _skip_held():
			break
		armed = armed or not _skip_held()
		orbit += dt * speed * 0.35
		if cam:
			cam.fov = 45.0
			cam.global_position = c + Vector3(sin(orbit) * 3.2, 0.7, cos(orbit) * 3.2)
			cam.look_at(c, Vector3.UP)
		await tree.process_frame
	# The skip key let go before the game goes on (E held into the yard walked him out through
	# the gate, Esc into the fight opened the pause menu).
	var hold := 0.0
	while _skip_held() and hold < 1.5:
		hold += 1.0 / 60.0
		await tree.process_frame
	for lf in live_fx:
		if is_instance_valid(lf[0]):
			lf[0].queue_free()
	# (Skipped or played through: every wound back as it is now.)
	while next_ev < redo.size():
		if is_instance_valid(redo[next_ev].part):
			redo[next_ev].part.remove_voxels(redo[next_ev].idx, false, false)
		next_ev += 1
	await tree.create_timer(0.3, true).timeout
	if overlay:
		overlay.queue_free()
		overlay = null
	for id in ids:
		if is_instance_valid(ids[id]) and _comes_and_goes(ids[id]):
			# (A thing thrown that is gone stays gone; the rest as they are now.)
			ids[id].visible = ids[id] is Chunk or not (m.get("items") != null and m.items.ghosts.any(func(g): return g[0] == ids[id]))
	for b in now:
		if is_instance_valid(b):
			b.global_transform = now[b][0]
			if b is RigidBody3D:
				b.linear_velocity = now[b][1]
				b.angular_velocity = now[b][2]
			if b.has_method("draw_now"):
				b.draw_now()
	if m.cam:
		m.cam.fov = fov0
	tree.paused = false
	playing = false
	done.call()

## A burst or a flash off the tape made again: its nodes, running through the pause.
func _fx_again(ev: Dictionary) -> Array:
	var out := []
	if m.get("fx") == null or m.fx == null:
		return out
	var a: Array = ev.args
	if ev.fn == "burst":
		for ps in m.fx.make_burst(a[0], a[1], a[2], a[3], a[4], a[5]):
			ps.process_mode = Node.PROCESS_MODE_ALWAYS
			out.append([ps, float(ev.t), ps.speed_scale])
	elif ev.fn == "flash":
		var l: OmniLight3D = m.fx.make_light(a[0], a[1], a[2], a[3])
		l.process_mode = Node.PROCESS_MODE_ALWAYS
		out.append([l, float(ev.t), float(a[2])])
	return out

func _skip_held() -> bool:
	return (InputMap.has_action("va_kick") and Input.is_action_pressed("va_kick")) or Input.is_key_pressed(KEY_ESCAPE)

## The key that skips, as bound ("E" by default).
func skip_key() -> String:
	var code := str(Data.controls.get("defaults", {}).get("kick", "KeyE"))
	if m and m.get("input") and m.input.bindings.has("kick"):
		code = str(m.input.bindings.kick)
	return PlayerInput.label_of(code)

func _overlay(caption: String) -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 50
	add_child(overlay)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -110.0
		bar.offset_bottom = 110.0 if top else 0.0
		overlay.add_child(bar)
	var title := Label.new()
	title.text = "KILL CAM"
	title.add_theme_font_override("font", UIStyle.serif(6))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UIStyle.GOLD)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = 32
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(title)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_override("font", UIStyle.serif(1))
	cap.add_theme_font_size_override("font_size", 28)
	cap.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	cap.anchor_left = 0.0
	cap.anchor_right = 1.0
	cap.anchor_top = 1.0
	cap.anchor_bottom = 1.0
	cap.offset_top = -78
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(cap)
	var hint := Label.new()
	hint.text = Loc.t("%s  skip") % skip_key()
	hint.add_theme_font_override("font", UIStyle.serif(1))
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84, 0.6))
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = -220
	hint.offset_right = -36
	hint.offset_top = 44
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	overlay.add_child(hint)
