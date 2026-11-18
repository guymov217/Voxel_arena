extends Node
## A giant bending down to take a man up (user: he smeared on the floor instead of bending like a
## man): his hips are let down at a pace his legs hold, his feet stay under him and his knees well clear
## of the sand, the trunk leans on out over a man lying there, and the hand comes down on the man and
## takes hold, on the giant's own feet to the end of it. (Dropped at the pace of a fall, the soles went
## through the sand and the knees onto it, seven metres a second at the worst, and he sprang up at the
## end.)

var t

## One giant before one man, the giant stood still till the reach is begun: Polyphemus (a colossus, who
## stoops to a man standing as to one on the sand), or a bot twice a man's size (who stoops only to one
## down on the sand).
func _scene(small: bool) -> Dictionary:
	seed(5)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false, "immortal": true}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "", "off": ""}})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	m.me.drive = func(_e): return {"look": {"yaw": 0.0, "pitch": 0.0}}
	var spec: Dictionary = m.enemy_spec({"e": "giant", "boss": true}, 0, 1)
	spec.pos = Vector3(0, 0.1, 2.13)
	spec.yaw = PI
	if small:
		spec = {"kind": "bot", "name": "Giant", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 1.6), "yaw": PI, "mods": {"bodyScale": 2.0, "strength": 2.0}, "diff": 0.9}
	var ge = m.spawn_fighter(spec)
	ge.drive = func(_e): return {}
	for i in 240:
		await get_tree().physics_frame
	ge.erase("drive")
	ge.bot.think = 99.0
	return {"m": m, "man": man, "g": ge.f, "bot": ge.bot}

## The reach at the man, watched from its start till half a second after the hand takes hold of him (or
## `limit` seconds): the steps he was off the sand, how fast his trunk fell at the most (m/s), the
## lowest a sole went under the sand and the lowest a knee was over it before he had hold of the man
## (m), how far the trunk leaned over at the most (degrees), and when he took hold (-1: not at all).
func _stoop(sc: Dictionary, down: bool, limit: float) -> Dictionary:
	var g: Fighter = sc.g
	var man: Fighter = sc.man
	var bot = sc.bot
	if down:
		man.fall(90.0, true)
		for i in 120:
			await get_tree().physics_frame
	bot.grab_cool = 0.0
	bot.grab_reach = Bot.GRAB_REACH * (Bot.GRAB_DOWN_REACH if down else 1.0)
	bot.hold_t = 0.0
	var V := Fighter.V * g.S
	var out := {"air": 0, "fall": 0.0, "sole": INF, "knee": INF, "lean": 0.0, "held_at": -1.0, "state": ""}
	var t0: float = sc.m.time
	var end := limit
	var steps := 0
	while steps < int(end * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		steps += 1
		if down and g.holding == null:
			man.fall(90.0, true)   # (kept down: the hand coming onto him is not to stand him up)
		if g.holding != null and out.held_at < 0.0:
			out.held_at = sc.m.time - t0
			end = minf(end, out.held_at + 0.5)
		if not g.on_ground:
			out.air += 1
		out.fall = maxf(out.fall, -g.torso.linear_velocity.y)
		out.lean = maxf(out.lean, rad_to_deg(acos(clampf((PD.quat_of(g.torso) * Vector3.UP).y, -1.0, 1.0))))
		for sd in ["L", "R"]:
			var shin: VoxelPart = g.by_name["shin" + sd]
			out.sole = minf(out.sole, (shin.global_transform * Vector3(0, -4 * V, 0)).y - g.ground_level)
			if out.held_at < 0.0:
				out.knee = minf(out.knee, (shin.global_transform * Vector3(0, 4 * V, 0)).y - g.ground_level)
	out.state = g.state
	return out

## What a stoop is held to, whatever his size: on the sand and not dropped, no sole sunk into it, no
## knee down on it, and the man taken.
func _check_bend(r: Dictionary, S: float, who: String) -> void:
	t.check(r.held_at > 0.0, "%s takes hold of the man" % who)
	t.check(r.air <= 2, "%s is on the sand the whole way (%d steps off it)" % [who, r.air])
	t.check(r.fall < 2.2, "%s lets his trunk down, he does not drop it (%.1f m/s)" % [who, r.fall])
	t.check(r.sole > -0.08 * S, "%s keeps his soles out of the sand (%.2f m under it)" % [who, -r.sole])
	t.check(r.knee > 0.08 * S, "%s keeps his knees up off it (%.2f m over it)" % [who, r.knee])
	t.eq(r.state, "stand", "%s is on his feet" % who)

func test_a_colossus_bends_down_to_a_man_standing_on_his_feet() -> void:
	var sc := await _scene(false)
	var r := await _stoop(sc, false, 3.0)
	_check_bend(r, sc.g.S, "he")
	t.check(r.lean > 15.0, "the trunk leans out over him (%.0f degrees)" % r.lean)
	sc.m.queue_free()

## A man lying on the sand is far below the hand even with the legs bent: the trunk leans on out to him,
## and the hand comes down on him (stopped short, the hand a metre over him, nobody was taken).
func test_a_colossus_bends_right_over_to_a_man_on_the_sand() -> void:
	var sc := await _scene(false)
	var r := await _stoop(sc, true, 4.0)
	_check_bend(r, sc.g.S, "he")
	t.check(r.lean > 35.0, "the trunk leans well out over him (%.0f degrees)" % r.lean)
	sc.m.queue_free()

func test_a_smaller_giant_bends_to_a_man_on_the_sand_the_same_way() -> void:
	var sc := await _scene(true)
	var r := await _stoop(sc, true, 4.0)
	_check_bend(r, sc.g.S, "he")
	sc.m.queue_free()
