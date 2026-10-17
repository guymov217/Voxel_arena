class_name KillCam
extends Node
## The kill cam (killcam.js). The match is recorded all the time: 30 times a second, where every
## body part and weapon is, kept for seven seconds. Each kill is scored for how fine or how
## funny it was (a head off, a throw, a punch, a giant brought down, a friend killed by mistake)
## and cut into a clip, from three seconds before the blow to a second and a half after. When
## the match ends the best clip is shown: time stops, the bodies are put back where they were and
## played forward, slowing right down around the blow, the camera circling the killer and the
## victim, black bars and a caption on screen. The voxels keep the damage they ended with.

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

func _init(match_: Node) -> void:
	m = match_
	name = "KillCam"
	process_mode = Node.PROCESS_MODE_ALWAYS

## How good a kill was, and the line under the replay.
static func score_kill(k: Dictionary) -> Dictionary:
	var v: String = k.get("victim", "someone")
	var a = k.get("killer")
	var score := 10.0
	var caption: String = ("%s killed %s" % [a, v]) if a else ("%s died" % v)
	var best_pts := 0.0
	var picks := []
	if k.get("out", false): picks.append([12.0, ("%s beat %s senseless" % [a, v]) if a else ("%s is out of the fight" % v)])
	if k.get("big", false): picks.append([30.0, "%s brought down the mighty %s" % [a if a else "The arena", v]])
	if k.get("burning", false): picks.append([20.0, ("%s burned, courtesy of %s" % [v, a]) if a else ("%s burned" % v)])
	if k.get("unarmed", false) and a: picks.append([25.0, "%s punched %s to death" % [a, v]])
	if k.get("thrown", false) and a: picks.append([30.0, "%s threw %s right into %s" % [a, ("a " + String(k.weapon)) if k.get("weapon") else "something", v]])
	if k.get("friendly", false) and a: picks.append([28.0, "%s killed %s. They were on the same side" % [a, v]])
	if k.get("self", false): picks.append([32.0, "%s managed to kill themselves" % v])
	if k.get("decap", false): picks.append([40.0, ("%s took %s's head off%s" % [a, v, (" with a " + String(k.weapon)) if k.get("weapon") else ""]) if a else ("%s lost their head" % v)])
	if int(k.get("multi", 1)) > 1: picks.append([18.0 * (int(k.multi) - 1), "%s: %s kills in a breath" % [a, "two" if int(k.multi) == 2 else ("three" if int(k.multi) == 3 else "a heap of")]])
	for p in picks:
		score += p[0]
		if p[0] >= best_pts:
			best_pts = p[0]
			caption = p[1]
	score += minf(30.0, float(k.get("severed", 0)) * 12.0)
	if float(k.get("J", 0.0)) > 30.0:
		score += minf(15.0, (float(k.J) - 30.0) * 0.5)
	return {"score": score, "caption": caption}

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
	return out

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
	for k in pending.duplicate():
		if m.time - float(k.t) >= AFTER:
			pending.erase(k)
			_cut(k)

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
	var wn = String(w.design.get("name", "")).to_lower() if w != null and is_instance_valid(w) else (wname if wname != "" else null)
	var k := {"t": float(last_hit.get("at", m.time)) if cause == "out" else m.time, "out": cause == "out", "victim": f.display_name, "killer": kname, "decap": cause == "decap" or (f.head and f.head.severed),
		"big": f.S >= 1.8 or f.boss, "burning": f.parts.any(func(p): return not p.spots.is_empty()),
		"unarmed": killer is Fighter and is_instance_valid(killer) and killer.weapons.get("R") == null and killer.weapons.get("L") == null,
		"thrown": thrown or (w != null and is_instance_valid(w) and w.holder == null), "weapon": wn,
		"self": killer == f, "friendly": killer is Fighter and is_instance_valid(killer) and killer != f and killer.team == f.team,
		"severed": severed, "J": float(last_hit.get("J", 0.0)),
		"killer_node": killer, "victim_node": f}
	pending.append(k)
	# On the Steam recording's timeline, so the moment is easy to find and clip.
	var sc := score_kill(k)
	Net.timeline_event("Kill", String(sc.caption), 2 if float(sc.score) >= 40.0 else 1)

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

## Plays the best clip, then calls `done`. Between rounds (`restore`) the fight goes on after
## it: every body is put back where it is now, moving as it was.
func play(done: Callable, restore := false) -> void:
	if best.is_empty() or m.headless:
		done.call()
		return
	playing = true
	var tree := m.get_tree()
	tree.paused = true
	var ids := {}
	var now := {}
	for b in _bodies():
		ids[b.get_instance_id()] = b
		if restore:
			now[b] = [b.global_transform, b.linear_velocity, b.angular_velocity]
	var fov0: float = m.cam.fov if m.cam else 0.0
	_overlay(String(best.caption))
	var fr: Array = best.frames
	var t0: float = fr[0].t
	var t1: float = fr[fr.size() - 1].t
	var tb: float = best.t_blow
	var t := t0
	var orbit := 0.0
	var cam: Camera3D = m.cam
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
		for id in a.xf:
			var body = ids.get(id)
			if body == null or not is_instance_valid(body):
				continue
			var xa: Transform3D = a.xf[id]
			var xb: Transform3D = b2.xf.get(id, xa)
			body.global_transform = xa.interpolate_with(xb, u)
		# The camera circles the pair, close, a little low.
		var pk = best.killer
		var pv = best.victim
		var c := Vector3(0, 1, 0)
		if pv and is_instance_valid(pv):
			c = pv.torso.global_position
			if pk and is_instance_valid(pk) and pk != pv:
				c = (c + pk.torso.global_position) * 0.5
		# Any key or a click skips it.
		if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_ENTER) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			break
		orbit += dt * speed * 0.35
		if cam:
			cam.fov = 45.0
			cam.global_position = c + Vector3(sin(orbit) * 3.2, 0.7, cos(orbit) * 3.2)
			cam.look_at(c, Vector3.UP)
		await tree.process_frame
	await tree.create_timer(0.3, true).timeout
	if overlay:
		overlay.queue_free()
		overlay = null
	for b in now:
		if is_instance_valid(b):
			b.global_transform = now[b][0]
			b.linear_velocity = now[b][1]
			b.angular_velocity = now[b][2]
	if restore and m.cam:
		m.cam.fov = fov0
	tree.paused = false
	playing = false
	done.call()

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
