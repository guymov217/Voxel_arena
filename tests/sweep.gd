extends Node
## The combat sweep (user: play the fights through and make sure nothing goes wrong, nothing
## happens that should not): training bouts headless, the player on autopilot with a weapon in
## turn against every kind of foe (a gladiator with each weapon, every campaign foe, every beast),
## and every step checked for what must never happen:
##  - a body part at NaN, under the sand, or flung faster than any blow throws it;
##  - a man going down with nothing to have put him there (no blow, shove or blast just before);
##  - a man off the sand on his feet, not thrown and not held;
##  - a weapon in hand away from the hand, a joint pulled apart;
##  - the dead (man or beast) still on their feet; a severed piece resting in the air;
##  - a foe close by for a long while without a blow; a bout with no blow landed at all;
##  - a physics step long enough to hitch the frame.
## `-- --probe sweep`. FOES: comma list ("bot:<weapon>", "foe:<campaign foe>", a beast's
## species) instead of all; MINE: the player's weapons in turn ("gladius+roundShield,axe");
## BOUT_S (45); SEED (3); DIFF (0.7).

const ARMS := ["gladius+roundShield", "axe", "spear", "warhammer", "longsword", "mace+dagger", "zweihander", "trident", "executionerAxe", "flail"]
const BOT_ARMS := ["gladius", "longsword", "zweihander", "axe", "executionerAxe", "mace", "warhammer", "spear", "trident", "dagger", "bow", "flail", "whip", "meteorHammer"]
const STEP := 1.0 / 120.0
const GAP := 0.08        # a joint this far apart (times the body's scale) is pulled open
const FLUNG := 25.0      # m/s: no blow throws a part this fast (times the root of the body's scale)
const HITCH_MS := 50.0   # a step this long shows as a hitch

var found: Array = []    # [bout, kind, who, t, info]
var bout_lines: Array = []

func _foes() -> Array:
	var env := OS.get_environment("FOES")
	if env != "":
		return Array(env.split(",", false))
	var out := []
	for w in BOT_ARMS:
		out.append("bot:" + w)
	for k in Data.campaign.enemies.keys():
		out.append("foe:" + String(k))
	for k in Data.beasts.keys():
		out.append(String(k))
	return out

func _flag(n: int, kind: String, f, t: float, info: String) -> void:
	var who := "?"
	if f != null and is_instance_valid(f):
		who = String(f.display_name) if not (f is Beast) else String(f.get("species") if f.get("species") != null else f.display_name)
	found.append([n, kind, who, t, info])
	print("  ! %5.1f s  %-28s %-16s %s" % [t, kind, who, info])

func _ready() -> void:
	var foes := _foes()
	var mine := Array(OS.get_environment("MINE").split(",", false)) if OS.get_environment("MINE") != "" else ARMS
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 45.0
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3
	var diff := float(OS.get_environment("DIFF")) if OS.get_environment("DIFF") != "" else 0.7
	var t0 := Time.get_ticks_msec()
	for i in foes.size():
		await _bout(i + 1, String(foes[i]), String(mine[i % mine.size()]), secs, sd + i, diff)
	print("\n==== SWEEP: %d bouts in %.0f s, %d findings" % [foes.size(), (Time.get_ticks_msec() - t0) / 1000.0, found.size()])
	for l in bout_lines:
		print(l)
	var by := {}
	for x in found:
		by[x[1]] = int(by.get(x[1], 0)) + 1
	print("by kind: %s" % str(by))
	get_tree().quit()

func _bout(n: int, foe: String, mine: String, secs: float, sd: int, diff: float) -> void:
	seed(sd)
	var arms := mine.split("+")
	var tr := {"immortal": false, "respawn": false, "difficulty": diff}
	if foe.begins_with("bot:"):
		tr.enemy = "gladiator"
		tr.weapon = foe.trim_prefix("bot:")
	else:
		tr.enemy = foe
	print("== %d  %s against %s" % [n, mine, foe])
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": tr, "autopilot": true, "headless": true, "seed": sd, "decrees": [], "hazards": [], "loadout": {"main": arms[0], "off": arms[1] if arms.size() > 1 else ""}})
	if m.me == null:
		_flag(n, "no player", null, 0.0, "the bout did not set up")
		m.queue_free()
		return
	var hits := {"me": 0, "foe": 0, "step": 0, "cut": 0}
	var struck_at := {}   # fighter id -> time of his last blow that landed
	m.combat.hit.connect(func(h):
		var att = h.get("attacker")
		var vic = h.get("char")
		if not (att is Fighter) or not (vic is Fighter) or att == vic:
			return
		if att == m.me.f:
			hits.me += 1
		elif vic == m.me.f:
			hits.foe += 1
		struck_at[att.get_instance_id()] = m.time
		hits.step += 1
		if not (h.get("res", {}) as Dictionary).get("severed", []).is_empty():
			hits.cut += 1)
	var ground: float = m.me.f.ground_level
	var fs := {}          # fighter id -> what is kept on him
	var t := 0.0
	var steps := 0
	var step_ms := 0.0
	var worst_ms := 0.0
	var hitches := 0
	var end_t := -1.0
	var prev_us := Time.get_ticks_usec()
	var nan := false
	while t < secs and not nan:
		await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		var ms := (now - prev_us) / 1000.0
		prev_us = now
		t += STEP
		steps += 1
		if steps > 120:
			step_ms += ms
			worst_ms = maxf(worst_ms, ms)
			if ms > HITCH_MS:
				hitches += 1
				if hitches <= 3:
					_flag(n, "hitch", null, t, "%.0f ms step (blows that step %d, of them severing %d, active bodies %d)" % [ms, int(hits.step), int(hits.cut), int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))])
		hits.step = 0
		hits.cut = 0
		var me_f: Fighter = m.me.f if m.me and is_instance_valid(m.me.f) else null
		var foes_alive := 0
		for e in m.entities:
			var f = e.f
			if f == null or not is_instance_valid(f):
				continue
			var id: int = f.get_instance_id()
			if not fs.has(id):
				fs[id] = {"state": f.state, "stand_h": -1.0, "dead_at": -1.0, "off": {"R": 0.0, "L": 0.0}, "gap_n": 0, "gap_max": 0.0, "air": 0.0, "idle": 0.0, "idle_max": 0.0, "floating": {}, "told": {}}
			var k: Dictionary = fs[id]
			if e.team != m.me.team and f.alive:
				foes_alive += 1
			# NaN, under the sand, flung.
			for p in f.parts:
				if not is_instance_valid(p) or not p.is_inside_tree():
					continue
				var pos: Vector3 = p.global_position
				var vel: Vector3 = p.linear_velocity
				if not pos.is_finite() or not vel.is_finite():
					_flag(n, "NaN", f, t, "part %s" % p.part_name)
					nan = true
					break
				if pos.y < ground - 0.4 and not k.told.has("under"):
					k.told.under = true
					_flag(n, "under the sand", f, t, "%s at y %.2f%s" % [p.part_name, pos.y, " (severed)" if p.severed else ""])
				# (Faster on a bigger body: a dragon's horn whipped round on its long neck at 25.)
				if vel.length() > FLUNG * sqrt(maxf(1.0, float(f.S))) and not k.told.has("flung"):
					k.told.flung = true
					_flag(n, "flung", f, t, "%s at %.0f m/s%s" % [p.part_name, vel.length(), " (severed)" if p.severed else ""])
				# A severed piece at rest in the air (nothing under it).
				if p.severed and not p.freeze and p.wielder == null and vel.length() < 0.05 and pos.y > ground + 0.5:
					var q := PhysicsRayQueryParameters3D.create(pos, pos - Vector3(0, 0.7, 0))
					q.exclude = [p.get_rid()]
					if p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
						k.floating[p.part_name] = float(k.floating.get(p.part_name, 0.0)) + STEP
						if float(k.floating[p.part_name]) > 1.0 and not k.told.has("float " + p.part_name):
							k.told["float " + p.part_name] = true
							_flag(n, "piece resting in the air", f, t, "%s at y %.2f" % [p.part_name, pos.y])
					else:
						k.floating[p.part_name] = 0.0
			if nan:
				break
			var torso_y: float = f.torso.global_position.y if is_instance_valid(f.torso) else 0.0
			if k.stand_h < 0.0 and t > 1.0 and f.state == "stand":
				k.stand_h = torso_y - ground
			# Going down: with a cause (a blow, a shove, a blast) only.
			var s: String = f.state
			if k.state == "stand" and s == "down" and f.alive and not (f is Beast) and f.can_stand() and float(k.get("could_stand_t", 0.0)) > 0.5:
				var age: float = f.time - f.jolt_t
				if age > Fighter.JOLT_GRACE:
					var cut := []
					for p in f.parts:
						if is_instance_valid(p) and p.severed:
							cut.append(p.part_name)
					var broke := []
					for p in f.parts:
						if is_instance_valid(p) and (p.fractured or p.fracture > 0):
							broke.append("%s%s" % [p.part_name, "" if p.fractured else "(cracked)"])
					var up: Vector3 = f.torso.global_transform.basis.y.normalized()
					_flag(n, "fell without a cause", f, t, "jolt %.1f s ago, blood %.0f, legs %.2f/%.2f, tilt %.0f deg for %.2f s, stoop %.2f, stagger %.2f, two hands %s, cut off %s, broken %s" % [age, f.blood, f.leg_func("L"), f.leg_func("R"), rad_to_deg(acos(clampf(up.y, -1.0, 1.0))), f.tilt_t, f.stoop, f.stagger, str(f.two_handed), str(cut), str(broke)])
			k.state = s
			k.could_stand_t = float(k.get("could_stand_t", 0.0)) + STEP if f.can_stand() else 0.0
			# The dead lie down.
			if not f.alive:
				if k.dead_at < 0.0:
					k.dead_at = t
				elif t - k.dead_at > 4.0 and k.stand_h > 0.0 and torso_y - ground > 0.7 * k.stand_h and not k.told.has("standing dead"):
					k.told["standing dead"] = true
					_flag(n, "dead but standing", f, t, "trunk %.2f m up, %.2f standing" % [torso_y - ground, k.stand_h])
				continue
			# Off the sand on his feet with nothing to put him there.
			if not (f is Beast):
				if s == "stand" and not f.on_ground and f.thrown_t <= 0.0 and f.grabbed_by == null:
					k.air += STEP
					if k.air > 1.0 and not k.told.has("air"):
						k.told.air = true
						_flag(n, "off the sand", f, t, "trunk %.2f m up" % (torso_y - ground))
				else:
					k.air = 0.0
				# A weapon in hand stays in the hand.
				for side in ["R", "L"]:
					var w = f.weapons.get(side)
					var fore = f.arm[side].fore if f.arm.has(side) else null
					if w == null or not is_instance_valid(w) or f.stowed.get(side) != null or fore == null or not is_instance_valid(fore) or fore.severed:
						k.off[side] = 0.0
						continue
					var d: float = w.grip_world().distance_to(f.hand_world(side))
					if d > 0.2 * f.S:
						k.off[side] += STEP
						if k.off[side] > 0.25 and not k.told.has("off " + side):
							k.told["off " + side] = true
							_flag(n, "weapon away from the hand", f, t, "%s hand, %s %.2f m off" % [side, String(w.design.get("name", "?")), d])
					else:
						k.off[side] = 0.0
			# Joints hold.
			for p in f.parts:
				if not is_instance_valid(p) or p.severed or p.parent_part == null or not is_instance_valid(p.parent_part) or p.parent_part.severed or p.joint == null or not is_instance_valid(p.joint):
					continue
				var a: Vector3 = p.parent_part.global_transform * p.pa
				var b: Vector3 = p.global_transform * p.ca
				var g: float = a.distance_to(b) / maxf(0.1, f.S)
				k.gap_max = maxf(k.gap_max, g)
				var gk: String = "gap " + p.part_name
				if g > GAP:
					k[gk] = float(k.get(gk, 0.0)) + STEP
					if float(k[gk]) > 0.25 and not k.told.has(gk):
						k.told[gk] = true
						_flag(n, "joint pulled apart", f, t, "%s from %s %.2f (x scale), %s" % [p.part_name, p.parent_part.part_name, g, "both hands on the haft" if f.two_handed else "one hand"])
				else:
					k[gk] = 0.0
			# A foe close by and not striking.
			if me_f and e.team != m.me.team and me_f.alive:
				var close: bool = f.torso.global_position.distance_to(me_f.torso.global_position) < 2.8 * f.S
				var last: float = float(struck_at.get(id, -99.0))
				if close and f.state == "stand" and m.time - last > 0.5:
					k.idle += STEP
					k.idle_max = maxf(k.idle_max, k.idle)
				else:
					k.idle = 0.0
		if nan:
			break
		var me_dead := me_f == null or not me_f.alive
		if (foes_alive == 0 or me_dead) and end_t < 0.0:
			end_t = t
		if end_t >= 0.0 and t - end_t > 4.5:
			break
	# The bout's line.
	var foe_f = null
	for e in m.entities:
		if e.team != m.me.team and is_instance_valid(e.f):
			foe_f = e.f
			var k2: Dictionary = fs.get(e.f.get_instance_id(), {})
			if float(k2.get("idle_max", 0.0)) > 12.0:
				_flag(n, "passive foe", e.f, t, "%.0f s close by without a blow" % float(k2.idle_max))
	if hits.me + hits.foe == 0:
		_flag(n, "no blow landed", foe_f, t, "in %.0f s" % t)
	var who_won := "draw"
	if m.me.f and is_instance_valid(m.me.f) and not m.me.f.alive:
		who_won = "foe"
	elif foe_f and not foe_f.alive:
		who_won = "me"
	var gaps := []
	for id in fs:
		gaps.append("%.2f" % float(fs[id].gap_max))
	var line := "%2d %-24s vs %-22s %-4s %4.0f s  blows %3d/%3d  step %.1f ms (worst %.0f, %d hitches)  joint gap max %s" % [n, mine, foe, who_won, t, hits.me, hits.foe, step_ms / maxf(1.0, steps - 120.0), worst_ms, hitches, ",".join(gaps)]
	print(line)
	bout_lines.append(line)
	m.queue_free()
	for i in 6:
		await get_tree().physics_frame
