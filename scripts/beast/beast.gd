class_name Beast
extends Fighter
## A voxel animal or monster (beast.js): a stiff body held at its height by a spring and
## steered by setting its spin, legs on motorised hips and knees that trot, a biting head (or
## several), horns, tails and wings bolted on. Every part can be chipped and cut off. Behaviour
## by species: hunters stalk, crouch and pounce; chargers paw the ground and run you down; the
## bear hugs; the goat wanders; elephants walk their circle and stomp.

const JAW_T := 0.55

var species := "lion"
var sp: Dictionary = {}
var legs: Array = []
var heads: Array = []
var wings: Array = []
var gait := 0.0
var ai := {}
var target: Node3D = null
var height := 0.8
var bite_power := 45.0
var hug = null
var down_t := 0.0
var flying := false
var rng := RandomNumberGenerator.new()
var on_breath: Callable
var on_stomp: Callable

func build_beast(species_: String, spawn: Vector3, yaw_: float, opts := {}) -> void:
	kind = "beast"
	species = species_
	sp = Data.beasts.get(species, Data.beasts.lion)
	display_name = opts.get("name", sp.name)
	name = display_name.replace(" ", "_")
	slot = int(opts.get("slot", 9))
	team = int(opts.get("team", 1))
	boss = bool(opts.get("boss", false))
	rng.seed = int(opts.get("seed", randi()))
	var base_s: float = float(sp.scale)
	S = float(opts.get("scale", base_s))
	var k := S / base_s
	MS = pow(S, 2.5)
	mods.bodyScale = S
	mods.toughness = 1.0
	yaw = yaw_
	height = float(sp.height) * S
	bite_power = float(sp.get("bite", 45.0))
	var yaw_q := Quaternion(UP, yaw)
	for d in sp.parts:
		var voxels := []
		for v in d.voxels:
			voxels.append([v[0], v[1], v[2], Color.hex(int(v[3]) << 8 | 0xff), v[4]])
		var p := VoxelPart.new()
		var dd: Dictionary = d.duplicate()
		dd.erase("voxels")
		p.setup(self, dd, voxels, float(d.scale) * k, float(d.mass) * MS)
		p.linear_damp = 0.3
		p.angular_damp = 2.0
		p.collision_layer = VoxelPart.LAYER_BODY
		var no_ground: bool = d.leg and not d.lower
		p.collision_mask = VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS | (0 if no_ground else VoxelPart.LAYER_WORLD)
		var pm := PhysicsMaterial.new()
		pm.friction = 1.1 if d.lower else 0.8
		p.physics_material_override = pm
		add_child(p)
		var r: Array = d.rot
		var local := Transform3D(Basis(Quaternion(r[0], r[1], r[2], r[3])), Vector3(d.pos[0], d.pos[1], d.pos[2]) * k)
		p.global_transform = Transform3D(Basis(yaw_q), spawn) * local
		parts.append(p)
		by_name[d.name] = p
		if d.parent != null and by_name.has(d.parent):
			p.parent_part = by_name[d.parent]
			p.parent_part.child_parts.append(p)
	torso = by_name.beastBody
	head = by_name.beastHead
	for a in parts:
		for b in parts:
			if a != b:
				a.add_collision_exception_with(b)
	for p in parts:
		if p.parent_part:
			var at: Vector3 = p.parent_part.global_transform * p.pa
			p.joint = _joint_at(p.parent_part, p, at, not p.def.get("leg", false))
	for p in parts:
		if p.def.get("leg", false) and not p.def.get("lower", false):
			legs.append(p)
		if p == head or p.def.get("head", false):
			heads.append(p)
		if float(p.def.get("wing", 0)) != 0.0:
			wings.append(p)
	ai = {"mode": "aim" if sp.ai == "charger" else "stalk", "t": 1.5 + rng.randf() * 1.5, "circle": 1.0 if rng.randf() < 0.5 else -1.0, "bite_cool": 2.5, "roar_cool": 4.0, "dodge_cool": 0.0, "breath_cool": 3.0, "fly_cool": 6.0, "alt": 0.0}

func heads_left() -> Array:
	return heads.filter(func(h): return not h.severed and h.hp > 0.0)

func lower_of(leg: VoxelPart) -> VoxelPart:
	return by_name.get(leg.part_name + "Lo")

func leg_gone(leg: VoxelPart) -> bool:
	var lo := lower_of(leg)
	return leg.severed or leg.hanging or (lo != null and (lo.severed or lo.hanging))

func leg_power() -> float:
	if legs.is_empty():
		return 1.0
	var s := 0.0
	for l in legs:
		if not leg_gone(l):
			s += l.function()
	return s / legs.size()

func can_stand() -> bool:
	return state != "dead"

func fall(_duration: float, _force := false) -> void:
	stagger = 1.0

func set_standing(_on: bool) -> void:
	pass

func on_severed(part: VoxelPart) -> void:
	if part == head and not sp.get("multiHead", false):
		die("decap")

func die(cause := "") -> void:
	if state == "dead":
		return
	state = "dead"
	hug = null
	flying = false
	# Tip it over on its side instead of leaving it standing.
	var fwd := PD.quat_of(torso) * Vector3(0, 0, 1)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	torso.apply_torque_impulse(Vector3(fwd.x, 0, fwd.z) * torso.mass * side * 0.55 * S)
	torso.angular_damp = 1.2
	died.emit(self, cause)

func control(dt: float, _inp: Dictionary = {}) -> void:
	time += dt
	space = get_world_3d().direct_space_state
	var bleed := 0.0
	for p in parts:
		bleed += p.bleed
		p.bleed = maxf(0.0, p.bleed - dt * 0.1)
		if p.flinch_t > 0.0:
			p.flinch_t -= dt
	if torso.stump:
		bleed += 2.5
	blood = maxf(0.0, blood - bleed * 0.3 / (S * S) * dt)
	stagger = maxf(0.0, stagger - dt * 1.5)
	if push_t > 0.0:
		push_t -= dt
	if alive and (blood <= 0.0 or torso.hp <= 0.0 or (heads_left().is_empty() if sp.get("multiHead", false) else head.hp <= 0.0)):
		die("wounds")
	if not alive:
		for l in legs:
			for p in [l, lower_of(l)]:
				if p and not p.severed:
					p.angular_damp = 1.5
		return
	var pos := torso.global_position
	var lv := torso.linear_velocity
	var mass := 0.0
	for p in parts:
		if not p.severed:
			mass += p.mass
	var ray := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, -3.0 * S, 0), VoxelPart.LAYER_WORLD)
	var hit := space.intersect_ray(ray)
	var lp := leg_power()
	var legs_left := legs.filter(func(l): return not leg_gone(l)).size()
	injury = clampf(0.6 * (1.0 - blood / 100.0) + 0.4 * (1.0 - minf(torso.function(), lp)), 0.0, 1.0)
	var heavy := 1.0 - 0.5 * injury
	var collapsed: bool = (legs.size() > 0 and legs_left <= legs.size() / 2.0) or (legs.size() > 0 and blood < 22.0)
	var missing := legs.size() - legs_left
	var crouching := 0.78 if ai.mode == "crouch" else (1.15 if ai.mode == "breathe" else 1.0)
	var h_want: float = float(sp.parts[0].dims[1]) * V * S * 0.5 if collapsed else height * (0.8 if legs_left < 4 else 1.0) * crouching
	var dist_g: float = pos.y - hit.position.y if hit else 99.0
	var grounded: bool = hit and dist_g < maxf(h_want, height) + 0.25 * S
	if flying:
		var want_y: float = float(ai.alt) * (1.0 - 0.5 * injury)
		torso.apply_central_impulse(Vector3(0, mass * (gravity + 6.0 * (want_y - pos.y) - 3.0 * lv.y) * dt, 0))
	elif grounded:
		var support := 0.4 if legs.size() > 0 and not collapsed and not down_t > 0.0 else 1.0
		var f := mass * (gravity * support + (70.0 if support < 1.0 else 120.0) * (h_want - dist_g) - 15.0 * lv.y)
		torso.apply_central_impulse(Vector3(0, maxf(0.0, f) * dt, 0))
	var q := PD.quat_of(torso)
	var fwd_v := q * Vector3(0, 0, 1)
	var cur := atan2(fwd_v.x, fwd_v.z)
	ai.t -= dt
	ai.bite_cool -= dt
	ai.dodge_cool -= dt
	ai.roar_cool -= dt
	ai.breath_cool -= dt
	if ai.mode == "charge" and sp.ai == "charger":
		yaw = ai.charge_yaw
	var turn := 1.2 if sp.ai == "path" else (2.5 if flying else 6.0)
	var dy := atan2(sin(yaw - cur), cos(yaw - cur))
	var yaw_rate := clampf(dy * turn, -3.0, 3.0)
	# Balance: the body rests on the legs that are left; down or collapsed it lies over.
	var roll := 0.0
	var pitch := 0.0
	var K := 7.0
	if legs.size() > 0 and hug == null:
		var up := (q * UP).rotated(UP, -cur)
		var cur_pitch := atan2(up.z, up.y)
		var cur_roll := atan2(-up.x, up.y)
		if missing > 0 and not collapsed and stagger > 0.75 and not down_t > 0.0:
			down_t = 1.2 + missing * 0.6
		if down_t > 0.0:
			down_t -= dt
			roll = 1.25
			pitch = 0.1
			K = 5.0
		elif collapsed:
			roll = sin(gait * 0.8) * 0.08
			pitch = 0.12 + sin(gait * 1.6) * 0.1
			K = 4.0
		elif flying:
			roll = -yaw_rate * 0.25
			pitch = 0.35 if ai.mode == "swoop" else -0.08
			K = 5.0
		else:
			if stagger > 0.3:
				roll += sin(time * 9.0) * stagger * 0.2
			if Vector2(lv.x, lv.z).length() / S < 0.4:
				roll += 0.025 * sin(time * 0.7 + slot)
				pitch += 0.02 * sin(time * 0.5 + slot * 2)
		var rate_p := clampf((pitch - cur_pitch) * K, -6.0, 6.0)
		var rate_r := clampf((roll - cur_roll) * K, -6.0, 6.0)
		var right_w := Vector3(cos(cur), 0, -sin(cur))
		var fwd_w := Vector3(sin(cur), 0, cos(cur))
		torso.angular_velocity = Vector3(right_w.x * rate_p + fwd_w.x * rate_r, yaw_rate, right_w.z * rate_p + fwd_w.z * rate_r)
	else:
		torso.angular_velocity = Vector3(0, yaw_rate, 0)
	for p in parts:
		if p != torso and not p.severed and not p.def.get("leg", false) and p.angular_velocity.length() > 9.0:
			p.angular_velocity = p.angular_velocity.normalized() * 9.0
	var down := down_t > 0.0
	var want := Vector3.ZERO
	var hurt: float = 0.0 if down else heavy * (0.5 + 0.5 * torso.function()) * (0.18 if collapsed else (maxf(0.25, pow(float(legs_left) / maxf(1.0, legs.size()), 1.5)) if missing > 0 else 0.4 + 0.6 * lp))
	var t := target
	var to := Vector3.ZERO
	var dist := INF
	if t and t.alive:
		to = t.torso.global_position - pos
		to.y = 0
		dist = to.length()
		to = to.normalized()
	match String(sp.ai):
		"hunter":
			want = _hunt(dt, t, to, dist, hurt, collapsed, legs_left, grounded, h_want, dist_g, mass)
		"charger":
			if t:
				if ai.mode == "aim":
					if ai.t <= 0.0:
						ai.mode = "charge"; ai.t = 1.6; ai.charge_yaw = atan2(to.x, to.z)
					yaw = atan2(to.x, to.z)
				elif ai.mode == "charge":
					want = Vector3(sin(ai.charge_yaw), 0, cos(ai.charge_yaw)) * float(sp.speed) * hurt
					if ai.t <= 0.0:
						ai.mode = "recover"; ai.t = 1.4
				else:
					want = -to
					yaw = atan2(to.x, to.z)
					if ai.t <= 0.0:
						ai.mode = "aim"; ai.t = 0.8 + rng.randf()
		"hugger":
			if hug != null:
				_squeeze(dt)
			elif t:
				yaw = atan2(to.x, to.z)
				if ai.mode == "recover":
					want = -to * 1.5
					if ai.t <= 0.0:
						ai.mode = "stalk"
				else:
					want = to * float(sp.speed) * hurt
					if dist < 1.5 * S and ai.bite_cool <= 0.0:
						hug = {"target": t, "t": 3.0, "tick": 0.3, "stagger0": stagger}
		"wanderer":
			if not ai.has("goal") or ai.t <= 0.0 or Vector2(ai.goal.x - pos.x, ai.goal.z - pos.z).length() < 0.6:
				var a := rng.randf() * TAU
				var r := 2.0 + rng.randf() * 7.0
				ai.goal = Vector3(sin(a) * r, 0, cos(a) * r)
				ai.t = 3.0 + rng.randf() * 3.0
			want = Vector3(ai.goal.x - pos.x, 0, ai.goal.z - pos.z).normalized() * float(sp.speed)
			yaw = atan2(want.x, want.z)
		"path":
			var ang := atan2(pos.x, pos.z) + 0.25
			want = (Vector3(sin(ang) * 6.0, 0, cos(ang) * 6.0) - Vector3(pos.x, 0, pos.z)).normalized() * float(sp.speed) * hurt
			yaw = atan2(want.x, want.z)
			if t and dist < 3.2 * S * 0.6 and ai.bite_cool <= 0.0 and Vector3(sin(cur), 0, cos(cur)).dot(to) > 0.3:
				ai.bite_cool = 4.0
				ai.stomp = 0.7
			if ai.get("stomp", 0.0) > 0.0:
				ai.stomp -= dt
				want = Vector3.ZERO
				if ai.stomp <= 0.0:
					_stomp()
	var moving := want.length_squared() > 0.05
	if grounded and stagger < 0.5 and not down:
		var kk := (3.0 if sp.ai == "path" else 6.0) * (0.45 if legs.size() > 0 and not collapsed else 1.0)
		torso.apply_central_impulse(Vector3(want.x - lv.x, 0, want.z - lv.z) * mass * kk * dt)
	_drive_legs(dt, Vector2(lv.x, lv.z).length(), collapsed, down, moving)
	gait += dt * (maxf(1.2, Vector2(lv.x, lv.z).length()) if moving else 0.0) * 4.6 / S

func _hunt(dt: float, t, to: Vector3, dist: float, hurt: float, collapsed: bool, legs_left: int, grounded: bool, h_want: float, dist_g: float, mass: float) -> Vector3:
	var want := Vector3.ZERO
	if t == null:
		return want
	yaw = atan2(to.x, to.z)
	var spd: float = float(sp.speed)
	if sp.get("flies", false) and not flying:
		ai.fly_cool -= dt
		if not collapsed and legs_left == legs.size() and wings.all(func(w): return not w.severed) and (ai.mode == "stalk" or ai.mode == "recover") and ai.fly_cool <= 0.0:
			flying = true
			ai.mode = "fly"; ai.t = 2.0; ai.alt = 2.4 * S; ai.fly_t = 9.0 + rng.randf() * 5.0
			return want
	if flying:
		ai.fly_t -= dt
		if wings.any(func(w): return w.severed):
			flying = false
			return want
		if ai.mode == "fly":
			var r := 4.5 * S
			var tangent := Vector3(-to.z, 0, to.x) * float(ai.circle)
			want = tangent * spd * 0.9 + to * (3.0 if dist > r * 1.3 else (-3.0 if dist < r * 0.8 else 0.0))
			ai.alt = 2.4 * S
			if ai.t <= 0.0 and dist < r * 1.5:
				ai.mode = "swoop"; ai.t = 2.2
				ai.swoop_kind = "fire" if sp.breath != null and ai.breath_cool <= 0.0 else "dive"
			if ai.fly_t <= 0.0:
				ai.mode = "landing"; ai.alt = 0.3; ai.t = 2.0
		elif ai.mode == "swoop":
			want = to * spd * 1.4
			ai.alt = (1.6 if ai.swoop_kind == "fire" else 0.75) * S
			if ai.swoop_kind == "fire" and dist < float(sp.breathRange) * S * 0.7:
				ai.breath_cool = 6.0
				_breathe()
				ai.mode = "fly"; ai.t = 2.0 + rng.randf() * 2.0; ai.circle = -ai.circle
			elif ai.t <= 0.0:
				ai.mode = "fly"; ai.t = 2.0 + rng.randf() * 2.0; ai.circle = -ai.circle
		elif ai.mode == "landing":
			want = -to * spd * 0.4
			if (grounded and dist_g < h_want + 0.1) or ai.t <= 0.0:
				flying = false
				ai.mode = "stalk"; ai.t = 1.0; ai.fly_cool = 10.0 + rng.randf() * 6.0
		return want
	var side := Vector3(-to.z, 0, to.x) * float(ai.circle)
	var tw = t.weapons.get("R") if t.get("weapons") else null
	var swing: float = tw.linear_velocity.length() if tw else 0.0
	if (ai.mode == "charge" or ai.mode == "crouch" or ai.mode == "feint") and stagger > 0.3:
		ai.mode = "recover"; ai.t = 0.7 + rng.randf() * 0.6; ai.circle = -ai.circle
	match String(ai.mode):
		"stalk":
			var r: float = float(sp.stalkRadius) * S
			want = side * 2.2 + to * (2.0 if dist > r * 2.0 else (-1.5 if dist < r * 1.4 else 0.0))
			if swing > 4.5 and dist < 2.8 * S and ai.dodge_cool <= 0.0:
				ai.mode = "dodge"; ai.t = 0.35; ai.dodge_cool = 1.4
			elif sp.breath != null and ai.breath_cool <= 0.0 and dist < float(sp.breathRange) * S * 0.8 and dist > 0.7 * S:
				ai.mode = "breathe"; ai.t = 0.7
			elif ai.t <= 0.0:
				var roll := rng.randf()
				if roll < 0.25:
					ai.mode = "feint"; ai.t = 0.3
				elif roll < 0.4:
					ai.mode = "snarl"; ai.t = 0.5
				else:
					ai.mode = "crouch"; ai.t = 0.45
		"feint":
			want = to * spd * hurt * 0.8
			if ai.t <= 0.0:
				ai.mode = "recover"; ai.t = 0.5
		"breathe":
			if ai.t <= 0.0:
				ai.mode = "stalk"; ai.t = 1.0 + rng.randf(); ai.breath_cool = 7.0
				_breathe()
		"snarl":
			if ai.t <= 0.0:
				ai.mode = "stalk"; ai.t = 1.0 + rng.randf() * 1.5
		"crouch":
			if ai.t <= 0.0:
				ai.mode = "charge"; ai.t = 2.5
		"dodge":
			want = side * spd * hurt
			if ai.t <= 0.0:
				ai.mode = "stalk"; ai.t = 0.6 + rng.randf()
		"charge":
			want = to * spd * hurt
			if t.state != "stand" and t.alive:
				ai.mode = "stalk"; ai.t = 1.0 + rng.randf(); ai.bite_cool = maxf(ai.bite_cool, 1.2); ai.circle = -ai.circle
			elif dist < 1.1 + 0.6 * S and ai.bite_cool <= 0.0:
				_lunge(to, mass, collapsed)
				ai.mode = "recover"; ai.t = 1.1
			elif ai.t <= 0.0:
				ai.mode = "stalk"; ai.t = 1.0 + rng.randf() * 1.5
		_:
			want = to * spd * hurt * 0.6 if ai.t > 0.7 else to * -2.0 + side * 1.2
			if ai.t <= 0.0:
				ai.mode = "crouch" if rng.randf() < 0.4 else "stalk"
				ai.t = 0.45 if ai.mode == "crouch" else 1.0 + rng.randf() * 1.5
				ai.circle = -ai.circle
	return want

func _lunge(to: Vector3, mass: float, collapsed: bool) -> void:
	var k: float = float(sp.lunge) * (0.15 if collapsed else 1.0) * (1.0 - 0.5 * injury)
	torso.apply_central_impulse(Vector3(to.x * mass * k, mass * (0.2 if collapsed else 1.2), to.z * mass * k))
	for h in heads:
		if not h.severed:
			h.apply_central_impulse(Vector3(to.x * 40.0 * S, 15.0 * float(sp.get("lungeUp", 1.0) if sp.get("lungeUp", 0) else 1.0), to.z * 40.0 * S))
	ai.bite_cool = float(sp.cooldown) * (1.0 + injury)

func _squeeze(dt: float) -> void:
	hug.t -= dt
	hug.tick -= dt
	var tgt = hug.target
	if hug.tick <= 0.0 and tgt.alive:
		hug.tick = 0.5
		var p: Vector3 = tgt.torso.global_position
		tgt.apply_hit(tgt.torso, {"impulse": 7.0, "type": "blunt", "hardness": 0.5, "sharpness": 0.0, "point": p, "dir": Vector3.DOWN})
		tgt.last_attacker = self
	if hug.t <= 0.0 or not tgt.alive or stagger > hug.stagger0 + 0.35:
		hug = null
		ai.bite_cool = 3.0
		ai.mode = "recover"
		ai.t = 1.5

## Fire (or venom) in a cone in front of the head.
func _breathe() -> void:
	if on_breath.is_valid():
		on_breath.call(self, String(sp.breath), float(sp.breathRange) * S)

func _stomp() -> void:
	if on_stomp.is_valid():
		on_stomp.call(self)

func _drive_legs(dt: float, speed: float, collapsed: bool, down: bool, moving: bool) -> void:
	var n := legs.size()
	var max_t := 120.0 * maxf(2.0, float(sp.parts[0].mass) * 0.04) * MS + 40.0
	for i in n:
		var leg: VoxelPart = legs[i]
		if leg.severed:
			continue
		var row := int(i / 2) if n == 8 or n == 4 else 0
		var off := PI if ((i % 2) + row) % 2 else 0.0
		var phase := gait + off
		var hip := 0.0
		var knee := 0.06
		var wn := 70.0
		if flying:
			hip = 0.55; knee = 0.7; wn = 40.0
		elif down:
			wn = 25.0; hip = sin(time * 3.0 + i) * 0.3; knee = 0.4
		elif collapsed:
			hip = sin(gait * 2.2 + off) * 0.55; knee = 0.35 + cos(gait * 2.2 + off) * 0.3; wn = 45.0
		elif moving:
			var amp := 0.42 * minf(1.0, 0.35 + speed / (2.5 * S))
			hip = sin(phase) * amp
			knee = 0.06 + maxf(0.0, -cos(phase)) * amp * 1.9
		else:
			hip = 0.03 * sin(time * 1.1 + i * 1.7)
		var splay: float = float(leg.def.get("splay", 0.0))
		if leg.hanging:
			continue
		pd_relative(leg, torso, Quaternion.from_euler(Vector3(hip, 0, splay)), wn, 0.9, max_t, dt, 3.0, LEG_REACT)
		var lo := lower_of(leg)
		if lo and not lo.severed and not lo.hanging:
			pd_relative(lo, leg, Quaternion.from_euler(Vector3(knee, 0, float(lo.def.get("splay", 0.0)))), wn, 0.9, max_t * 0.7, dt, 3.0, LEG_REACT)
