extends Node
## Vertical clips for short-video sites (`-- --probe clipshots`, needs a display and a portrait
## window: run it through tools/make_clips.sh, which also cuts and titles the clips). CLIP picks
## the scene.
## Two passes keep it affordable: without --write-movie (and with CLIP_DRY=1) nothing is drawn and
## the fight runs fast, printing where its blows and deaths fall; then CLIP_FROM=<frame> draws only
## from that frame on (the frames before it are black, cut afterwards).
## Every fighter is on autopilot, the HUD is hidden and a cinematic camera frames the player and
## his foe over his shoulder, close enough for the blows to read on a phone. It prints a line for every
## hard blow ("HIT <frame> <J>") and every death ("DEATH <frame>") so the best seconds can be cut
## from the recording afterwards.

const SCENES := {
	"gorilla": {"mode": "training", "training": {"enemy": "gorilla", "immortal": false, "respawn": false}, "loadout_override": {"main": "gladius", "off": "roundShield"}},
	"cyclops": {"mode": "training", "training": {"enemy": "foe:cyclops", "immortal": false, "respawn": false}, "loadout_override": {"main": "spear", "off": "scutum"}},
	"elephant": {"mode": "training", "training": {"enemy": "elephant", "immortal": false, "respawn": false}, "loadout_override": {"main": "warhammer", "off": ""}},
	"bear": {"mode": "training", "training": {"enemy": "bear", "immortal": false, "respawn": false}, "loadout_override": {"main": "axe", "off": ""}},
	"duel": {"mode": "training", "training": {"enemy": "gladiator", "weapon": "axe", "difficulty": 0.9, "immortal": false, "respawn": false}, "loadout_override": {"main": "gladius", "off": "roundShield"}},
	"zweihander": {"mode": "training", "training": {"enemy": "gladiator", "weapon": "mace", "difficulty": 0.9, "immortal": false, "respawn": false}, "loadout_override": {"main": "zweihander", "off": ""}},
	"chicken": {"mode": "training", "training": {"enemy": "gladiator", "weapon": "gladius", "difficulty": 0.7, "immortal": false, "respawn": false}, "loadout_override": {"main": "chicken", "off": "goose"}},
	"ffa": {"mode": "ffa"},
}

var menu
var m
var seconds := 40.0
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_side := 0.0
var started := false
var rec0 := 0
var from := 0

func _ready() -> void:
	process_priority = 1000   # after the match: this camera has the last word
	var key := OS.get_environment("CLIP")
	if key == "":
		key = "duel"
	seconds = float(OS.get_environment("CLIP_SECONDS")) if OS.get_environment("CLIP_SECONDS") != "" else seconds
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	var o: Dictionary = SCENES[key].duplicate(true)
	o["autopilot"] = true
	o["autopilot_diff"] = 1.0
	o["decrees"] = []
	o["hazards"] = []
	o["seed"] = int(OS.get_environment("CLIP_SEED")) if OS.get_environment("CLIP_SEED") != "" else 7
	seed(int(o.seed))   # the global randf too: both runs must play the same fight
	menu.start(o)
	m = menu.match_
	m.combat.hit.connect(_on_hit)
	if menu.hud:
		menu.hud.visible = false
	m.cam.set_process(false)
	rec0 = Engine.get_frames_drawn()
	from = int(OS.get_environment("CLIP_FROM")) if OS.get_environment("CLIP_FROM") != "" else 0
	get_viewport().disable_3d = OS.get_environment("CLIP_DRY") == "1" or from > 0
	_tag("REC_START %d" % rec0)
	started = true
	var dead := {}
	var t := 0.0
	var after := -1.0
	while t < seconds:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if from > 0 and _frame() >= from and get_viewport().disable_3d:
			get_viewport().disable_3d = false
		for e in m.entities:
			if is_instance_valid(e.f) and not e.f.alive and not dead.has(e.f):
				dead[e.f] = true
				_tag("DEATH %d %s" % [_frame(), str(e.kind)])
				if after < 0.0:
					after = t
		# Someone is down: a few seconds of the aftermath, then stop.
		if after >= 0.0 and t - after > 4.0:
			break
	_tag("REC_END %d" % _frame())
	get_tree().quit()

## Frames since the fight began (the movie's frame number, less the frames before REC_START).
func _frame() -> int:
	return Engine.get_frames_drawn() - rec0

func _on_hit(h: Dictionary) -> void:
	if float(h.get("J", 0.0)) >= 20.0:
		_tag("HIT %d %d" % [_frame(), int(h.J)])

func _process(dt: float) -> void:
	if not started or m == null or m.me == null or not is_instance_valid(m.me.f):
		return
	var a: Fighter = m.me.f
	var b = null
	var ne = m.nearest_enemy(m.me)
	if ne and is_instance_valid(ne.f):
		b = ne.f
	var pa: Vector3 = a.torso.global_position
	var pb: Vector3 = b.torso.global_position if b else pa + Vector3(0, 0, 2)
	var across := pb - pa
	across.y = 0
	if across.length() < 0.3:
		across = Vector3(0, 0, 1)
	across = across.normalized()
	var side := across.cross(Vector3.UP)
	# Over the player's shoulder, 40 degrees off the line of the fight: in a tall frame the two
	# stand one behind the other instead of at its edges. Keep to one shoulder; change only when
	# the camera has drifted well round the other way.
	if cam_side == 0.0:
		cam_side = 1.0 if (pa + side).length() < (pa - side).length() else -1.0
	elif cam_pos != Vector3.ZERO and side.dot(cam_pos - pa) * cam_side < -1.0:
		cam_side = -cam_side
	var ang := deg_to_rad(40.0)
	var back := (-across * cos(ang) + side * cam_side * sin(ang)).normalized()
	var pts := []
	for f in [a, b]:
		if f == null:
			continue
		for p in f.parts:
			if not p.severed:
				pts.append(p.global_position)
	var lo_y := 0.0
	var hi_y := 0.0
	for q in pts:
		hi_y = maxf(hi_y, q.y)
	var look := (pa * 0.45 + pb * 0.55)
	look.y = hi_y * 0.45
	var vt := tan(deg_to_rad(31.0))
	var ht := vt * get_viewport().get_visible_rect().size.aspect()
	# The nearest distance that keeps every part of both bodies in the frame, with a margin.
	var lo := 2.0
	var hi := 18.0
	for i in 14:
		var d := (lo + hi) * 0.5
		# Aimed a little above the fight, so the bodies sit low in the frame, under the text.
		if _fits(look + back * d + Vector3.UP * (0.5 + d * 0.22), look + Vector3.UP * d * 0.12, pts, ht * 0.86, vt * 0.86):
			hi = d
		else:
			lo = d
	var want := look + back * hi + Vector3.UP * (0.5 + hi * 0.22)
	look += Vector3.UP * hi * 0.12
	if cam_pos == Vector3.ZERO:
		cam_pos = want
		cam_look = look
	cam_pos = cam_pos.lerp(want, minf(1.0, dt * 2.0))
	cam_look = cam_look.lerp(look, minf(1.0, dt * 3.0))
	var cam: Camera3D = m.cam
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 62.0
	cam.global_position = cam_pos
	cam.look_at(cam_look, Vector3.UP)
	cam.reset_physics_interpolation()

func _fits(eye: Vector3, at: Vector3, pts: Array, ht: float, vt: float) -> bool:
	var fwd := (at - eye).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	for q in pts:
		var v: Vector3 = q - eye
		var z := v.dot(fwd)
		if z < 0.5:
			return false
		# The top fifth of the frame is left for the hook text over it.
		var yv := v.dot(up)
		if (absf(v.dot(right)) + 0.35) / z > ht or (yv + 0.35) / z > vt * 0.6 or (-yv + 0.35) / z > vt:
			return false
	return true

## Each timing tag goes to stdout and, when TAG_LOG names a file, there too: the window build of
## Godot on Windows (not the *_console.exe) prints nothing to a pipe, and the trailer kit reads
## the shots' frames from these lines.
var _tags := PackedStringArray()
func _tag(line: String) -> void:
	print(line)
	var path := OS.get_environment("TAG_LOG")
	if path == "":
		return
	_tags.append(line)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_tags) + "\n")
