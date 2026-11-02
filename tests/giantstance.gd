extends Node
## How a giant stands through a bout (the capsule art, the user: the cyclops stood with its legs
## spread like a split): every quarter second, how far apart its soles are (across and along its
## facing, times its scale), how far each thigh is swung out from under the hip, its state and
## what its bot is doing; and the moment the capsule would freeze (the champion's hard blow).
## `-- --probe giantstance`. FOE (foe:cyclops), BOUT_S (30), SEED (7).

const CapsuleArt := preload("res://tests/capsuleart.gd")

func _sole(f: Fighter, side: String) -> Vector3:
	return f.by_name["shin" + side].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)

## How far the thigh points out sideways from straight down (degrees, + away from the body),
## and how far forward (+) or back, in its facing's frame (the world's vertical, its yaw).
func _splay(f: Fighter, side: String) -> Vector2:
	var th: VoxelPart = f.by_name["thigh" + side]
	var down: Vector3 = -(th.global_transform.basis.y).normalized()
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var right := fwd.cross(Vector3.UP)
	var out := down.dot(right) * (-1.0 if side == "L" else 1.0)
	return Vector2(rad_to_deg(atan2(out, -down.y)), rad_to_deg(atan2(down.dot(fwd), -down.y)))

## Where a foot is planted against where it would stand under the hip (out +, forward +, x S),
## and whether it is stepping.
func _plant(f: Fighter, side: String) -> String:
	var ft = f.feet[side]
	if ft == null:
		return "%s -" % side
	var th: VoxelPart = f.by_name["thigh" + side]
	var yq := Quaternion(Vector3.UP, f.yaw)
	var neutral: Vector3 = f.torso.global_position + yq * Vector3(th.pa.x * 1.15, 0, 0)
	var off: Vector3 = yq.inverse() * ((ft.anchor as Vector3) - neutral)
	return "%s[%+.2f %+.2f%s]" % [side, off.x * signf(th.pa.x) / f.S, off.z / f.S, " sw" if ft.swing else ""]

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "foe:cyclops"
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 30.0
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": foe, "immortal": true, "respawn": false, "difficulty": 0.7}, "autopilot": true, "headless": true, "seed": 3, "decrees": [], "hazards": [],
		"loadout": {"main": CapsuleArt.AXE, "off": "", "armor": CapsuleArt.GILT}})
	var g = m.enemies()[0]
	var f: Fighter = g.f
	var big := [false]
	m.combat.hit.connect(func(h):
		if big[0] or h.get("attacker") != m.me.f or h.get("char") != f or float(h.get("J", 0.0)) < 14.0:
			return
		var res = h.get("res", {})
		if res is Dictionary and (res.get("removed", []) as Array).size() >= 2:
			big[0] = true
			print("  >>> %.2f the capsule's blow (J %.0f on %s)" % [m.time, float(h.J), String(h.part.part_name) if h.get("part") else "?"]))
	var worst := 0.0
	var wide_t := 0.0
	var ready_t := 0.0
	var first_ready := -1.0
	for i in int(secs * 120):
		await get_tree().physics_frame
		if not is_instance_valid(f) or f.torso == null:
			break
		var a := _sole(f, "L")
		var b := _sole(f, "R")
		var d := b - a
		d.y = 0.0
		var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
		var across := absf(d.dot(fwd.cross(Vector3.UP))) / f.S
		var along := absf(d.dot(fwd)) / f.S
		worst = maxf(worst, across)
		if across > 0.6:
			wide_t += 1.0 / 120.0
		var sq: Dictionary = CapsuleArt.squared_up(f, m.me.f)
		if sq.ok:
			ready_t += 1.0 / 120.0
			if first_ready < 0.0:
				first_ready = m.time
				print("  >>> %.2f squared up: %s" % [m.time, str(sq)])
		if i % 30 == 0 and sq.has("gap"):
			print("      ready? gap %.1f face %.0f look %.0f over %.0f across %.2f along %.2f bow %.0f up %.2f hero %.0f v %.2f" % [sq.gap, sq.face, sq.look, sq.over, sq.across, sq.along, sq.bow, sq.up, sq.hero, sq.v])
		if i % 30 == 0:
			var bot = g.get("bot")
			var sl := _splay(f, "L")
			var sr := _splay(f, "R")
			var pitch := rad_to_deg(f.torso.global_transform.basis.y.normalized().angle_to(Vector3.UP))
			print("%5.2f %-6s soles across %.2f along %.2f (x S)  thighs out L %3.0f R %3.0f fwd L %3.0f R %3.0f  trunk bowed %3.0f y %.2f  bot %s/%s  %s %s v %.2f" % [m.time, f.state, across, along, sl.x, sr.x, sl.y, sr.y, pitch, f.torso.global_position.y / f.S, String(bot.state) if bot else "-", String(bot.giant_kind) if bot else "-", _plant(f, "L"), _plant(f, "R"), Vector2(f.v_smooth.x, f.v_smooth.z).length()])
	print("widest across %.2f (x S); %.1f s wider than 0.6; squared up %.1f s, first at %.1f" % [worst, wide_t, ready_t, first_ready])
	get_tree().quit()
