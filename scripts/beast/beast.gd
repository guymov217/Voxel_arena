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
var ride_adj := 0.0   # how far the body is let down so the feet stand on the sand
var bite_power := 45.0
var hug = null
var down_t := 0.0
var flying := false
var rng := RandomNumberGenerator.new()
var on_breath: Callable
var on_venom: Callable               # (beast, victim, part, point): poison where it struck
const VENOMOUS := {"scorpion": "sting", "manticore": "sting", "spider": "bite", "python": "bite", "basilisk": "bite"}
var coil_cool := 0.0
var on_stomp: Callable
var on_roar: Callable
# Animation: the parts that move on their own joints (necks, heads, tails, wings, trunks,
# pincers, the coils of a snake), their rest pose against their parent and how far they bend.
var anim: Array = []                 # [{part, role, rest: Quaternion, lim, i}]
var strikes := {}                    # part -> seconds left of its strike (a bite, a sting, a swipe)
var strike_cool := {}                # part -> seconds until it may strike again
var regrown := {}                    # hydra: part -> voxels regrown so far
var base_bite := 45.0
var jaw_t := 0.0                     # counts down from JAW_T through a bite
var breath_t := 0.0                  # the mouth held wide while fire or venom pours out
const ROLE_LIM := {"tail": 0.7, "coil": 0.9, "neck": 0.55, "head": 0.6, "wing": 1.1, "trunk": 0.8, "arm": 0.6, "claw": 0.5}
const ROLE_WN := {"tail": 16.0, "coil": 14.0, "neck": 24.0, "head": 26.0, "wing": 20.0, "trunk": 14.0, "arm": 22.0, "claw": 26.0}

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
	base_bite = bite_power
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
			if p.def.get("leg", false):
				# A leg swings fore and aft at the hip or the knee, a little out to the side,
				# and hardly twists: on a free ball joint the elephant's legs spun round on
				# their own length.
				_make_limited(p, [[-1.4, 1.4], [-0.12, 0.12], [-0.35, 0.35]])
			else:
				p.joint = _joint_at(p.parent_part, p, at, true)
	for p in parts:
		if p.def.get("leg", false) and not p.def.get("lower", false):
			legs.append(p)
		if p == head or p.def.get("head", false):
			heads.append(p)
		if float(p.def.get("wing", 0)) != 0.0:
			wings.append(p)
	_setup_anim()
	for p in parts:
		if p.def.get("bite", false) and p.def.get("jaw") is Dictionary:
			p.build_jaw(p.def.jaw)
	ai = {"mode": "aim" if sp.ai == "charger" else "stalk", "t": 1.5 + rng.randf() * 1.5, "circle": 1.0 if rng.randf() < 0.5 else -1.0, "bite_cool": 2.5, "roar_cool": 4.0, "dodge_cool": 0.0, "breath_cool": 3.0, "fly_cool": 6.0, "alt": 0.0}

func heads_left() -> Array:
	return heads.filter(func(h): return not h.severed and h.hp > 0.0)

func _box_low(p: VoxelPart) -> float:
	var b := p.global_transform
	var h := p.half_ext
	return b.origin.y - absf(b.basis.x.y) * h.x - absf(b.basis.y.y) * h.y - absf(b.basis.z.y) * h.z

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

func vitality() -> float:
	if not alive:
		return 0.0
	var h := head.hp
	if sp.get("multiHead", false):
		h = 0.0
		for hh in heads_left():
			h = maxf(h, hh.hp)
	return clampf(minf(minf(h, torso.hp), blood) / 100.0, 0.0, 1.0)

func die(cause := "") -> void:
	if state == "dead":
		return
	state = "dead"
	_release_coil()
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
		p.update_drips()
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
	if strikes.has(head) and head.parent_part != torso:
		crouching = 0.8   # a long-necked beast drops its forequarters into a downward strike
	var h_want: float = float(sp.parts[0].dims[1]) * V * S * 0.5 if collapsed else height * (0.8 if legs_left < 4 else 1.0) * crouching
	h_want *= 1.0 + 0.008 * sin(time * 1.7 / sqrt(S) + slot)   # breathing
	var dist_g: float = pos.y - hit.position.y if hit else 99.0
	# The feet on the sand, never over it: the body rides lower until the legs it stands on
	# reach the ground (a species' height a little over its legs' reach held it hovering).
	# (Not while it strikes or charges: let down in mid-attack, its head came in under a man
	# and threw him high.)
	var attacking: bool = not strikes.is_empty() or ai.mode == "charge"
	if attacking:
		ride_adj = move_toward(ride_adj, 0.0, dt * 0.3)
	if hit and not flying and not collapsed and legs.size() > 0 and not attacking:
		var gap := 0.0
		var nf := 0
		for l in legs:
			if leg_gone(l) or strikes.has(l):
				continue
			var ft: VoxelPart = lower_of(l) if lower_of(l) else l
			gap += _box_low(ft) - hit.position.y
			nf += 1
		if nf > 0:
			ride_adj = clampf(ride_adj + (gap / nf) * minf(1.0, dt * 6.0), -0.04 * S, 0.35 * height)
	h_want -= ride_adj
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
	ai.rear_cool = float(ai.get("rear_cool", 0.0)) - dt
	coil_cool -= dt
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
		elif float(ai.get("rear", 0.0)) > 0.0:
			# Rearing: nose to the sky on the hind legs, then pitching forward onto the prey.
			pitch = -0.95 if float(ai.rear) > 0.4 else 0.35
			K = 6.0
		elif flying:
			var wfl := wing_fns()
			roll = -yaw_rate * 0.25 + (wfl.y - wfl.x) * 0.6   # a hurt wing drops that side
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
	# A bite is only as strong as the best head left to bite with; with no working head the beast
	# can neither see its prey nor attack it.
	var biters := biting_heads()
	var best_head := 0.0
	for h in biters:
		best_head = maxf(best_head, h.function())
	bite_power = base_bite * best_head
	if by_name.has("stinger") or by_name.has("clawL"):
		bite_power = maxf(bite_power, base_bite * 0.8 * maxf(fn_of(["stinger"]), fn_of(["claw"])))
	if species == "python" or species == "basilisk":
		hurt *= 0.35 + 0.65 * fn_of(["coil", "tailTip", "neck"])   # a cut-up body slithers badly
	elif species == "crocodile":
		hurt *= 0.6 + 0.4 * fn_of(["tail"])                       # the tail drives it through the water and the sand
	var t := target if heads_left().size() > 0 and (sp.get("multiHead", false) or part_ok(head, 0.1)) else null
	var to := Vector3.ZERO
	var dist := INF
	if t and t.alive:
		to = t.torso.global_position - pos
		to.y = 0
		dist = to.length()
		to = to.normalized()
	var coiling: bool = hug != null and hug.get("coil", false) and is_instance_valid(hug.target)
	if coiling:
		_coil(dt)
	match "" if coiling else String(sp.ai):
		"hunter":
			want = _hunt(dt, t, to, dist, hurt, collapsed, legs_left, grounded, h_want, dist_g, mass)
			# A python that gets close throws its coils round the man even without a bite.
			if species == "python" and t and hug == null and coil_cool <= 0.0 and dist < 1.3 * S + 0.6 and fn_of(["coil"]) > 0.3 and rng.randf() < dt * 1.5:
				_start_coil(t)
		"charger":
			if t:
				if ai.mode == "aim":
					if ai.t <= 0.0:
						# Broken horns shorten the run; hurt forelegs make it slower and wobblier.
						ai.mode = "charge"; ai.t = 1.6 * (0.55 + 0.45 * horn_fn()); ai.charge_yaw = atan2(to.x, to.z) + (1.0 - front_fn()) * rng.randf_range(-0.35, 0.35)
					yaw = atan2(to.x, to.z)
				elif ai.mode == "charge":
					want = Vector3(sin(ai.charge_yaw), 0, cos(ai.charge_yaw)) * float(sp.speed) * hurt * (0.3 + 0.7 * front_fn())
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
				elif float(ai.get("rear", 0.0)) > 0.0:
					# Up on the hind legs, forepaws raised over the man; then down on him, both
					# paws raking as the weight comes down.
					ai.rear = float(ai.rear) - dt
					want = to * 1.2 * hurt
					if ai.rear < 0.4 and not ai.get("slammed", false):
						ai.slammed = true
						for n in ["legFL", "legFR"]:
							if by_name.has(n) and not leg_gone(by_name[n]):
								_strike(by_name[n], 0.45, 0.0)
								var lo := lower_of(by_name[n])
								if lo:
									lo.apply_central_impulse(((t.torso.global_position - lo.global_position).normalized() + Vector3(0, -0.6, 0)) * 26.0 * S)
						torso.apply_central_impulse((to + Vector3(0, -0.4, 0)) * mass * 2.2)
					if ai.rear <= 0.0:
						ai.mode = "stalk"
						ai.bite_cool = 1.2
				else:
					want = to * float(sp.speed) * hurt
					if species == "bear" and dist < 2.4 * S and float(ai.get("rear_cool", 0.0)) <= 0.0 and hind_fn() > 0.5 and front_fn() > 0.35:
						ai.rear = 1.15
						ai.rear_cool = 4.0 + rng.randf() * 2.0
						ai.slammed = false
						for n in ["legFL", "legFR"]:
							if by_name.has(n) and not leg_gone(by_name[n]):
								_strike(by_name[n], 0.7, 0.0)
					elif dist < 1.5 * S and ai.bite_cool <= 0.0 and front_fn() > 0.35 and part_ok(head, 0.15):
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
			# A mammoth does not keep to its circle: it goes for whoever is in the arena with it,
			# and now and then charges, trumpeting, tusks first.
			if species == "mammoth" and t and dist < 18.0 * S:
				ai.charge_t = float(ai.get("charge_t", 0.0)) - dt
				if float(ai.charge_t) < -5.0 and dist > 3.0 * S:
					ai.charge_t = 1.8
					if on_roar.is_valid():
						on_roar.call(self)
				var spd := float(sp.speed) * (2.6 if float(ai.charge_t) > 0.0 else 1.5)
				want = to * spd * hurt
				yaw = atan2(to.x, to.z)
			if t and dist < 3.2 * S * 0.6 and ai.bite_cool <= 0.0 and Vector3(sin(cur), 0, cos(cur)).dot(to) > 0.3 and leg_power() > 0.4:
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
	_abilities(dt, t, to, dist, cur)
	_animate(dt, moving, yaw_rate, to, dist, cur)
	if species == "hydra":
		_regrow(dt)
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
		if not collapsed and legs_left == legs.size() and can_fly() and (ai.mode == "stalk" or ai.mode == "recover") and ai.fly_cool <= 0.0:
			flying = true
			ai.mode = "fly"; ai.t = 2.0; ai.alt = 2.4 * S; ai.fly_t = 9.0 + rng.randf() * 5.0
			return want
	if flying:
		ai.fly_t -= dt
		var wfl := wing_fns()
		if minf(wfl.x, wfl.y) < 0.35:
			# Not enough wing left to stay up: down it comes, and fights on the ground.
			flying = false
			ai.mode = "stalk"; ai.t = 1.0; ai.fly_cool = 999.0 if wings.any(func(w): return w.severed) else 12.0
			return want
		if ai.mode == "fly":
			var r := 4.5 * S
			var tangent := Vector3(-to.z, 0, to.x) * float(ai.circle)
			want = tangent * spd * 0.9 + to * (3.0 if dist > r * 1.3 else (-3.0 if dist < r * 0.8 else 0.0))
			ai.alt = 2.4 * S * minf(1.0, 0.4 + minf(wfl.x, wfl.y))
			if ai.t <= 0.0 and dist < r * 1.5:
				ai.mode = "swoop"; ai.t = 2.2
				ai.swoop_kind = "fire" if sp.breath != null and ai.breath_cool <= 0.0 and can_breathe() else "dive"
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
			elif sp.breath != null and ai.breath_cool <= 0.0 and can_breathe() and dist < float(sp.breathRange) * S * 0.8 and dist > 0.7 * S:
				ai.mode = "breathe"; ai.t = 0.7
			elif ai.t <= 0.0:
				var roll := rng.randf()
				if roll < 0.25:
					ai.mode = "feint"; ai.t = 0.3
				elif roll < 0.4:
					ai.mode = "snarl"; ai.t = 0.5
				elif hind_fn() < 0.45 or injury > 0.6:
					ai.mode = "feint"; ai.t = 0.4   # too hurt to pounce: it rushes in on the ground
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
				ai.mode = "recover"; ai.t = 1.1 * (1.0 + injury * 1.5)   # a hurt hunter backs off longer
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
	var k: float = float(sp.lunge) * (0.15 if collapsed else 1.0) * (1.0 - 0.5 * injury) * (0.35 + 0.65 * hind_fn())
	torso.apply_central_impulse(Vector3(to.x * mass * k, mass * (0.2 if collapsed else 1.2), to.z * mass * k))
	for h in biting_heads():
		_strike(h, 0.35, 0.0)
		if true:
			h.apply_central_impulse(Vector3(to.x * 40.0 * S, 15.0 * float(sp.get("lungeUp", 1.0) if sp.get("lungeUp", 0) else 1.0), to.z * 40.0 * S))
	ai.bite_cool = float(sp.cooldown) * (1.0 + injury)

## A python round a man (character.js has no constrictor; this is new): its coils wrap the
## body and close on it. The squeeze is a force, the snake's weight and the pull of its muscle,
## on the chest it is wrapped round: the pressure that makes crushes ribs, stops the breath and
## pins the arms, and grows as the coils tighten. He can wrench free while he still has the
## strength (his stamina and his blows on the coils).
func _start_coil(c) -> void:
	hug = {"target": c, "t": 7.0, "tick": 0.25, "stagger0": stagger, "coil": true, "tight": 0.0}
	if c.has_method("fall") and c.state == "stand":
		c.stagger = minf(1.0, c.stagger + 0.5)

func _coil(dt: float) -> void:
	var tgt = hug.target
	hug.t -= dt
	hug.tick -= dt
	hug.tight = minf(1.0, float(hug.tight) + dt / 2.5)
	var tc: Vector3 = tgt.torso.global_position
	var r: float = tgt.torso.half_ext.x * 1.25 + 0.06 * S
	var coils: Array = parts.filter(func(p): return (String(p.part_name).begins_with("coil") or p.part_name == "tailTip" or p == torso) and not p.severed)
	var i := 0
	for p in coils:
		# Each segment is pulled onto its turn of a spiral round his chest.
		var a: float = time * 0.6 + i * 2.1
		var at: Vector3 = tc + Vector3(cos(a) * r, -0.25 * tgt.S + i * 0.16 * tgt.S, sin(a) * r)
		var err: Vector3 = at - p.global_position
		p.apply_central_impulse((err * 60.0 - p.linear_velocity * 8.0) * p.mass * dt)
		i += 1
	# The squeeze: weight and muscle on the area of chest the coils cover.
	var m_snake := 0.0
	for p in parts:
		if not p.severed:
			m_snake += p.mass
	var muscle := fn_of(["coil"]) * (0.4 + 0.6 * float(hug.tight))
	var force := m_snake * gravity * 2.5 * muscle
	var area: float = 2.0 * PI * r * (0.16 * tgt.S * coils.size())
	var pressure := force / maxf(0.05, area)          # N/m^2
	# He is held: no breath, arms pinned to his sides.
	tgt.stamina = maxf(0.0, tgt.stamina - pressure * 0.004 * dt)
	tgt.stagger = maxf(tgt.stagger, 0.6)
	if tgt.state == "stand" and float(hug.tight) > 0.5:
		tgt.fall(2.0, true)
	if hug.tick <= 0.0 and tgt.alive:
		hug.tick = 0.45
		var J := clampf(pressure / 220.0, 3.0, 45.0)
		var parts_hit := [tgt.torso]
		for n in ["upperArmR", "upperArmL"]:
			var q = tgt.by_name.get(n)
			if q and not q.severed:
				parts_hit.append(q)
		var part: VoxelPart = parts_hit[rng.randi() % parts_hit.size()]
		var at2: Vector3 = part.global_position + (part.global_position - tc).normalized() * part.half_ext.x
		var res: Dictionary = tgt.apply_hit(part, {"impulse": J, "type": "blunt", "hardness": 0.4, "sharpness": 0.0, "point": at2, "dir": (tc - at2).normalized(), "crush": minf(0.09, 0.02 + J * 0.0015) if J > 18.0 else 0.0})
		tgt.last_attacker = self
		if Combat.current:
			Combat.current.hit.emit({"kind": "hit", "p": at2, "dir": (tc - at2).normalized(), "J": J, "type": "blunt", "char": tgt, "part": part, "attacker": self, "res": res, "killed": not tgt.alive})
	# Wrenched free: his struggle (what breath he has left), blows that stagger the snake, or
	# coils too cut up to hold.
	var escape: float = tgt.stamina / 100.0 * float(tgt.mods.get("strength", 1.0)) * 0.04 * dt * 60.0 / maxf(0.3, muscle)
	# (A snake just wrapped round him is not shaken off by the first knock: only after a second.)
	if hug.t <= 0.0 or not tgt.alive or (hug.t < 6.0 and stagger > float(hug.stagger0) + 0.45) or fn_of(["coil"]) < 0.25 or rng.randf() < escape * dt:
		_release_coil()

func _release_coil() -> void:
	if hug != null and hug.get("coil", false):
		hug = null
		coil_cool = 4.0
		ai.mode = "recover"
		ai.t = 1.2

func _squeeze(dt: float) -> void:
	hug.t -= dt
	hug.tick -= dt
	var tgt = hug.target
	if hug.tick <= 0.0 and tgt.alive:
		hug.tick = 0.5
		var p: Vector3 = tgt.torso.global_position
		tgt.apply_hit(tgt.torso, {"impulse": 7.0, "type": "blunt", "hardness": 0.5, "sharpness": 0.0, "point": p, "dir": Vector3.DOWN})
		tgt.last_attacker = self
	if hug.t <= 0.0 or not tgt.alive or stagger > hug.stagger0 + 0.35 or front_fn() < 0.3 or not part_ok(head, 0.1):
		hug = null
		ai.bite_cool = 3.0
		ai.mode = "recover"
		ai.t = 1.5

## Fire (or venom) in a cone in front of the head.
func _breathe() -> void:
	if on_breath.is_valid() and can_breathe():
		breath_t = 1.0
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
		# A hurt leg steps short; a struck one buckles for a moment; a swiping one lashes forward.
		var lf := fn_of([leg.part_name])
		hip *= 0.35 + 0.65 * lf
		var lo0 := lower_of(leg)
		var fl: float = maxf(leg.flinch_t, lo0.flinch_t if lo0 else 0.0)
		if fl > 0.0:
			hip += fl * 0.6; knee += fl * 0.8
		if strikes.has(leg):
			hip = -1.1 * (0.5 + 0.5 * lf); knee = 0.25; wn = 60.0
		var splay: float = float(leg.def.get("splay", 0.0))
		if leg.hanging:
			continue
		pd_relative(leg, torso, Quaternion.from_euler(Vector3(hip, 0, splay)), wn, 0.9, max_t, dt, 3.0, LEG_REACT)
		var lo := lower_of(leg)
		if lo and not lo.severed and not lo.hanging:
			pd_relative(lo, leg, Quaternion.from_euler(Vector3(knee, 0, float(lo.def.get("splay", 0.0)))), wn, 0.9, max_t * 0.7, dt, 3.0, LEG_REACT)

# ---------- What still works ----------
# Behaviour follows the voxels that are left: every group of parts is judged by how well its
# parts still work (VoxelPart.function: hp, the voxels it still has, whether it hangs or is off),
# never by a single chipped voxel.

## How well the parts whose names start with one of `prefixes` work together, 0..1 (a severed
## one counts as 0). 1 when the species has no such parts.
func fn_of(prefixes: Array) -> float:
	var n := 0
	var s := 0.0
	for p in parts:
		for pre in prefixes:
			if String(p.part_name).begins_with(pre):
				n += 1
				s += 0.0 if p.severed else p.function()
				break
	return s / n if n > 0 else 1.0

func front_fn() -> float:
	return fn_of(["legFL", "legFR"])

func hind_fn() -> float:
	return fn_of(["legBL", "legBR"]) if by_name.has("legBL") else front_fn()

func part_ok(p: VoxelPart, need := 0.25) -> bool:
	return p != null and not p.severed and not p.hanging and p.hp > 0.0 and p.function() > need

## The heads that can still bite, and how well the best of them does.
func biting_heads() -> Array:
	return heads.filter(func(h): return h.def.get("bite", false) and part_ok(h, 0.15))

func horn_fn() -> float:
	return fn_of(["horn", "tusk"])

func wing_fns() -> Vector2:
	var l := 1.0
	var r := 1.0
	for w in wings:
		var f: float = 0.0 if w.severed else w.function()
		if float(w.def.wing) < 0.0:
			l = f
		else:
			r = f
	return Vector2(l, r)

func can_fly() -> bool:
	var w := wing_fns()
	return not wings.is_empty() and minf(w.x, w.y) > 0.5

## Where fire or venom comes from: the chimera breathes through its goat head.
func breath_part() -> VoxelPart:
	if by_name.has("goatHead"):
		return by_name.goatHead
	return head

func can_breathe() -> bool:
	var b := breath_part()
	var neck_ok := not by_name.has("neck") or part_ok(by_name.neck, 0.2)
	return part_ok(b, 0.3) and neck_ok

# ---------- Animation ----------

## The jaws, drawing only (host and guests alike): they gape on the lunge and snap shut on the
## bite, hang wide while it breathes, open a little in a snarl or a hold, and hang open dead.
func _process(dt: float) -> void:
	jaw_t = maxf(0.0, jaw_t - dt)
	breath_t = maxf(0.0, breath_t - dt)
	var k := jaw_t / JAW_T
	var gape := 0.0
	if not alive:
		gape = 0.35
	elif breath_t > 0.0:
		gape = 0.85
	elif hug != null:
		gape = 0.3 + 0.25 * maxf(0.0, sin(time * 6.0))
	elif jaw_t > 0.0:
		gape = 0.75 * minf(1.0, (1.0 - k) / 0.35) if k > 0.3 else 0.75 * (k / 0.3)
	elif ai.get("mode", "") == "snarl" or ai.get("mode", "") == "breathe" or ai.get("mode", "") == "crouch":
		gape = 0.35 if ai.mode != "breathe" else 0.6
	for p in heads:
		if not p.severed:
			p.set_gape(gape, dt)

## A bite landed (combat): the jaws snap shut on it, and what the teeth tore out hangs from
## them a while, or falls.
func bit(att: VoxelPart, vic: VoxelPart, res: Dictionary, dir: Vector3) -> void:
	jaw_t = minf(jaw_t, 0.14)
	# Venom: a scorpion's (or a manticore's) sting, a spider's or a snake's fangs.
	var kind: String = VENOMOUS.get(species, "")
	var c = vic.fighter
	if c and not vic.severed and kind != "" and ((kind == "sting" and att.part_name == "stinger") or (kind == "bite" and heads.has(att))):
		if on_venom.is_valid():
			on_venom.call(self, c, vic, vic.global_position)
	# A python that has its fangs in a man throws its coils round him.
	if species == "python" and heads.has(att) and c and c.alive and hug == null and coil_cool <= 0.0 and fn_of(["coil"]) > 0.3:
		_start_coil(c)
	var torn := []
	for r in res.get("removed", []):
		if not r.get("chunk", false) and r.part == vic:
			torn.append_array(r.voxels)
	if torn.size() < 3 or vic.severed or vic.freeze:
		return
	var hold: Node3D = att.jaw_pivot if att.jaw_pivot and rng.randf() < 0.6 else null
	var at := Vector3.ZERO
	if hold:
		var gz: int = att.grid.z
		var z0 := int(floor(gz * float(att.def.jaw.get("from", 0.6))))
		at = Vector3(0, att.vf * att.part_scale * 1.2, (gz - z0) * att.vf * att.part_scale * 0.7)
	if Chunk.spawn(vic, torn, dir, hold, at, 1.5 + rng.randf() * 2.0):
		for r in res.removed:
			if r.part == vic:
				r.chunk = true
		res.torn = torn.size()
		res.mouthful = hold != null

func status() -> Dictionary:
	var s := super.status()
	s.jaw = snappedf(maxf(jaw_t, breath_t), 0.01)
	return s

func apply_status(s: Dictionary) -> void:
	super.apply_status(s)
	var j := float(s.get("jaw", 0.0))
	if j > jaw_t and j <= 1.0:
		jaw_t = minf(JAW_T, j)

func _setup_anim() -> void:
	for p in parts:
		if p == torso or p.parent_part == null or p.def.get("leg", false):
			continue
		var n: String = p.part_name
		var role := ""
		if float(p.def.get("wing", 0)) != 0.0 or n.begins_with("wing"):
			role = "wing"
		elif n.begins_with("coil") or ((species == "python" or species == "basilisk") and n == "tailTip"):
			role = "coil"
		elif n.begins_with("tail") and n != "tailFin":
			role = "tail"
		elif n.begins_with("neck") or n == "goatNeck":
			role = "neck"
		elif p == head or p.def.get("head", false):
			role = "head"
		elif n.begins_with("trunk"):
			role = "trunk"
		elif n.begins_with("arm"):
			role = "arm"
		elif n.begins_with("claw"):
			role = "claw"
		if role == "":
			continue
		var lim: float = ROLE_LIM[role]
		# Necks and heads may bend much further when they strike than when they idle; a
		# scorpion's tail curls right up over its back.
		var jlim := 1.25 if role == "neck" or role == "head" else (1.35 if role == "tail" and by_name.has("stinger") else lim)
		if p.joint is Generic6DOFJoint3D:
			var j: Generic6DOFJoint3D = p.joint
			for ax in ["x", "y", "z"]:
				j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -jlim)
				j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, jlim)
		# Strong enough to hold up everything hanging off it (a neck carries its head).
		var carried := 0.0
		var stack := [p]
		while not stack.is_empty():
			var c: VoxelPart = stack.pop_back()
			carried += c.mass
			stack.append_array(c.child_parts)
		var reach := maxf(p.half_ext.x, maxf(p.half_ext.y, p.half_ext.z)) * 2.0
		var mt := 60.0 * carried * reach + 20.0
		if role == "tail" and by_name.has("stinger"):
			mt *= 5.0   # it holds the whole arched tail and the sting up over the back
		anim.append({"part": p, "role": role, "rest": PD.quat_of(p.parent_part).inverse() * PD.quat_of(p), "i": anim.size(), "max_t": mt})

## Drives every animated joint: breathing, looking at the prey, tails swaying and lashing,
## snakes' bodies travelling in waves, wings beating or flaring, trunks swinging, and the
## strikes on top. Each part moves on its own surviving voxels; a part that hangs or is off
## is left to the physics, and a damaged one moves less.
func _animate(dt: float, moving: bool, yaw_rate: float, to: Vector3, dist: float, cur: float) -> void:
	var breath := sin(time * 1.7 / sqrt(S) + slot)
	var track := 0.0
	if dist < INF:
		var dy := atan2(to.x, to.z) - cur
		track = clampf(atan2(sin(dy), cos(dy)), -0.9, 0.9)
	var wf := wing_fns()
	var threat: bool = ai.mode == "crouch" or ai.mode == "snarl" or ai.mode == "breathe" or ai.mode == "aim"
	for a in anim:
		var p: VoxelPart = a.part
		if p.severed or p.hanging or p.parent_part.severed:
			continue
		var role: String = a.role
		var i: int = a.i
		var off := Vector3.ZERO
		match role:
			"tail":
				if by_name.has("stinger"):
					# Arched up over the back, the sting poised above the head, swaying.
					off.x = 1.0 + 0.05 * sin(time * 1.3 + i)
					off.y = sin(time * 0.9 - i * 0.6) * 0.12 + track * 0.25
				else:
					var k := 0.18 + (0.22 if moving else 0.0) + (0.3 if threat or ai.mode == "charge" else 0.0)
					off.y = sin(time * (2.4 if moving else 1.1) - i * 0.8) * k - yaw_rate * 0.12
					off.x = 0.04 * breath
			"coil":
				off.y = sin(gait * 1.3 - i * 1.5) * (0.6 if moving else 0.1) + sin(time * 0.5 + i) * 0.05
			"neck":
				off.y = track * 0.45 + sin(time * 0.9 + i * 1.7) * 0.08 + yaw_rate * 0.08
				off.x = -0.04 * breath + (0.25 if ai.mode == "aim" else 0.0)
			"head":
				off.y = track * (0.4 if p.parent_part == torso else 0.25) + sin(time * 0.7 + i * 2.1) * 0.06
				off.x = 0.03 * breath + (0.35 if ai.mode == "aim" or ai.mode == "charge" and sp.ai == "charger" else 0.0)
			"wing":
				var side := signf(float(p.def.get("wing", 0))) if float(p.def.get("wing", 0)) != 0.0 else signf(p.pa.x)
				var wfn: float = wf.x if side < 0.0 else wf.y
				if flying:
					off.z = side * sin(time * 6.5) * 0.8 * wfn
				elif species == "ostrich":
					off.z = side * (sin(gait * 2.0) * 0.3 if moving else 0.05 * breath)
				elif threat:
					off.z = -side * 0.35
				else:
					off.z = side * (0.2 + 0.03 * breath)
			"trunk":
				off.x = sin(time * 0.8 + i) * 0.22 - (0.7 if ai.get("stomp", 0.0) > 0.0 else 0.0)
				off.y = sin(time * 0.55 + i) * 0.25
			"arm":
				off.y = -track * 0.3 * signf(p.pa.x)
				off.x = -0.25 if dist < 2.5 * S else 0.0
			"claw":
				off.y = signf(p.pa.x) * (0.15 + 0.15 * sin(time * 3.0 + i))
		var lim: float = ROLE_LIM[role]
		if role == "tail" and by_name.has("stinger"):
			lim = 1.3
		var wn: float = ROLE_WN[role]
		var st: float = strikes.get(p, 0.0)
		if st > 0.0:
			off += _strike_pose(p, role, st, track, dist)
			if role == "neck" or role == "head":
				lim = 1.2
		if p.flinch_t > 0.0:
			off.x -= p.flinch_t * 0.9
		off = off.clamp(Vector3(-lim, -lim, -lim), Vector3(lim, lim, lim)) * (0.3 + 0.7 * p.function())
		if role == "tail" and by_name.has("stinger"):
			# The arched tail carries the whole chain and the sting: held like a leg, not swung.
			motor_rel(p, p.parent_part, Quaternion.from_euler(off) * a.rest, 14.0, a.max_t, dt, 0.5)
		else:
			pd_relative(p, p.parent_part, Quaternion.from_euler(off) * a.rest, wn, 0.9, a.max_t, dt, 1.0, 0.5)

func _strike_pose(p: VoxelPart, role: String, st: float, track: float, dist: float) -> Vector3:
	match role:
		"neck":
			# Dip the neck as far as it takes to bring the head down to the prey.
			var drop := 0.0
			if target and is_instance_valid(target):
				var hd: VoxelPart = p.child_parts[0] if not p.child_parts.is_empty() else p
				drop = clampf((hd.global_position.y - target.torso.global_position.y) / maxf(0.5, p.half_ext.y * 2.0 + 0.3), 0.0, 1.2)
			return Vector3(0.3 + drop, track * 0.3, 0)
		"head":
			if species == "boar" or species == "elephant" or species == "mammoth":
				return Vector3(0.1, signf(float(ai.get("sweep", 1.0))) * (0.6 - st), 0)   # a tusk sweep
			if species == "rhino":
				return Vector3(0.12, track * 0.3, 0)                                   # a forward horn thrust, low
			if species == "bull" or species == "goat":
				return Vector3(-0.3, 0, 0)                                              # the horn toss
			return Vector3(0.45, track * 0.3, 0)                                        # a bite
		"tail":
			return Vector3(0.3, track * 0.3, 0)                                        # the sting driven forward over the back
		"claw":
			return Vector3(0, -signf(p.pa.x) * 0.45, 0)                                # the pincer snaps shut
		"arm":
			return Vector3(-0.4, 0, 0)
	return Vector3.ZERO

func _strike(p: VoxelPart, t_: float, cool: float) -> void:
	strikes[p] = t_
	p.set_meta("stung", false)
	strike_cool[p] = cool
	if p.jaw_pivot:
		jaw_t = JAW_T
	# A head on a neck strikes with the neck: it dips and drives forward with it.
	var nk := p.parent_part
	if nk and not nk.severed and String(nk.part_name).begins_with("neck"):
		strikes[nk] = t_
	# A paw or a foot only hurts while it swings.
	if p.def.get("leg", false):
		var lo := lower_of(p)
		if lo:
			lo.def["bite"] = true
			lo.def["claw"] = SWIPERS.has(species)

## The sting's tip is a needle: its little collider rarely meets a body square on, so while the
## sting is driving, the tip reaching flesh is the blow (a point, as hard as the scorpion's
## strike), once per sting.
func _sting_reach() -> void:
	if not by_name.has("stinger") or not strikes.has(by_name.stinger) or target == null or not is_instance_valid(target) or not target.alive:
		return
	var stg: VoxelPart = by_name.stinger
	if stg.get_meta("stung", false):
		return
	var tip: Vector3 = stg.global_transform * Vector3(0, -stg.half_ext.y, stg.half_ext.z)
	for q in target.parts:
		if q.severed:
			continue
		var lp: Vector3 = q.global_transform.affine_inverse() * tip
		var e: Vector3 = q.half_ext + Vector3.ONE * 0.06 * S
		if absf(lp.x) < e.x and absf(lp.y) < e.y and absf(lp.z) < e.z:
			stg.set_meta("stung", true)
			var dir: Vector3 = (q.global_position - tip).normalized()
			var J := bite_power * 0.8
			var was: bool = target.alive
			var res: Dictionary = target.apply_hit(q, {"impulse": J, "type": "point", "hardness": 0.9, "sharpness": 1.0, "point": tip, "dir": dir, "axis": dir})
			target.last_attacker = self
			if Combat.current:
				Combat.current.hit.emit({"kind": "hit", "att_part": stg, "p": tip, "dir": dir, "J": J, "type": "point", "char": target, "part": q, "attacker": self, "res": res, "killed": was and not target.alive, "bite": true})
			bit(stg, q, res, dir)
			return

func _tick_strikes(dt: float) -> void:
	_sting_reach()
	for p in strike_cool.keys():
		strike_cool[p] -= dt
	for p in strikes.keys():
		strikes[p] -= dt
		if strikes[p] <= 0.0 or not is_instance_valid(p) or p.severed:
			strikes.erase(p)
			if is_instance_valid(p) and p.def.get("leg", false):
				var lo := lower_of(p)
				if lo:
					lo.def["bite"] = false
					lo.def["claw"] = false

func _ready_to_strike(p: VoxelPart) -> bool:
	return strike_cool.get(p, 0.0) <= 0.0 and not strikes.has(p)

const SWIPERS := ["lion", "tiger", "bear", "griffin", "cerberus", "chimera", "manticore", "ostrich"]

## The attacks each body can still make, each needing the parts it is made with.
func _abilities(dt: float, t, to: Vector3, dist: float, cur: float) -> void:
	_tick_strikes(dt)
	if t == null or not t.alive or flying or hug != null or down_t > 0.0:
		return
	var facing := Vector3(sin(cur), 0, cos(cur)).dot(to)
	var reach: float = torso.half_ext.z + head.half_ext.z * 2.0 + 0.5
	var tp: Vector3 = t.torso.global_position
	# Many heads: each snaps on its own, when it is in reach and ready, so the bites come staggered.
	if sp.get("multiHead", false):
		for h in heads:
			var reach_h: float = (h.parent_part.half_ext.y * 2.0 if h.parent_part != torso else 0.0) + h.half_ext.z * 2.0 + 0.4
			if h.def.get("bite", false) and part_ok(h, 0.2) and _ready_to_strike(h) and Vector2(h.global_position.x - tp.x, h.global_position.z - tp.z).length() < reach_h:
				_strike(h, 0.5, 1.0 + rng.randf() * 1.2)
				h.apply_central_impulse((tp - h.global_position).normalized() * 28.0 * S + Vector3(0, 6.0, 0))
	# A head on a long neck (a dragon's, an ostrich's, a rearing snake's) strikes down at the
	# prey on its own when it is in reach of the neck, without the whole body lunging.
	if not sp.get("multiHead", false) and head.parent_part != torso and part_ok(head, 0.2) and _ready_to_strike(head):
		var nk: VoxelPart = head.parent_part
		var hp := head.global_position
		var flat := Vector2(hp.x - tp.x, hp.z - tp.z).length()
		if flat < (nk.half_ext.y * 2.0 + head.half_ext.z * 2.0) * 1.1 and part_ok(nk, 0.2):
			_strike(head, 0.6, 1.3 + rng.randf() * 0.8)
			head.apply_central_impulse((tp - hp).normalized() * 25.0 * S)
	# The sting: the tail arches forward over the back and the stinger drives at the prey.
	if by_name.has("stinger"):
		var stg: VoxelPart = by_name.stinger
		var chain_ok := fn_of(["tail"]) > 0.3
		if part_ok(stg, 0.2) and chain_ok and _ready_to_strike(stg) and dist < reach * 1.3 and facing > 0.3:
			_strike(stg, 0.45, 2.2 + rng.randf())
			for n in ["tail", "tail2", "tail3"]:
				if by_name.has(n) and part_ok(by_name[n], 0.1):
					strikes[by_name[n]] = 0.45
			stg.apply_central_impulse((tp + Vector3(0, 0.3, 0) - stg.global_position).normalized() * 30.0 * S)
	# Pincers snap at whatever is in front of them.
	for n in ["clawL", "clawR"]:
		if by_name.has(n):
			var c: VoxelPart = by_name[n]
			if part_ok(c, 0.2) and _ready_to_strike(c) and c.global_position.distance_to(tp) < 0.9 * S:
				_strike(c, 0.25, 0.9 + rng.randf() * 0.6)
				c.apply_central_impulse((tp - c.global_position).normalized() * 18.0 * S)
	# A forepaw swipe (or the ostrich's kick): a working front leg lashes out.
	if SWIPERS.has(species) and dist < reach * 1.1 and facing > 0.5:
		var best: VoxelPart = null
		var best_f := 0.35
		for n in ["legFL", "legFR"]:
			if by_name.has(n):
				var l: VoxelPart = by_name[n]
				var f := fn_of([n])
				if not leg_gone(l) and f > best_f and _ready_to_strike(l):
					best = l
					best_f = f
		if best and rng.randf() < dt * 2.0:
			_strike(best, 0.35, 1.6 + rng.randf())
			var lo := lower_of(best)
			if lo:
				lo.apply_central_impulse((tp - lo.global_position).normalized() * 20.0 * S * best_f)
	# Tusks sweep sideways, horns toss upward, both only with something left of them.
	if (species == "boar" or species == "elephant" or species == "mammoth") and horn_fn() > 0.2 and part_ok(head) and _ready_to_strike(head) and dist < reach * 1.2 and facing > 0.4:
		ai.sweep = -1.0 if rng.randf() < 0.5 else 1.0
		_strike(head, 0.5, 2.0 + rng.randf())
	if (species == "bull" or species == "rhino" or species == "goat") and horn_fn() > 0.2 and part_ok(head) and _ready_to_strike(head) and dist < reach and facing > 0.6:
		# The toss is the head's own swing (see _strike_pose); only a small lift on top of it, so a
		# man is thrown about like by a bull, not launched into the air.
		_strike(head, 0.25 if species == "rhino" else 0.35, 1.8 + rng.randf())
		if species != "rhino":
			head.apply_central_impulse(Vector3(0, 4.0 * S * horn_fn(), 0))

## The hydra's wounds close: voxels grow back, a few at a time, on necks and heads that are still
## on, next to flesh that is still there, never on burnt flesh and never more than half of what
## was lost. A head cut off stays off: no new heads.
func _regrow(dt: float) -> void:
	ai.regrow_t = float(ai.get("regrow_t", 0.6)) - dt
	if ai.regrow_t > 0.0:
		return
	ai.regrow_t = 0.6
	for p in parts:
		var n: String = p.part_name
		if p.severed or p.hanging or not (n.begins_with("neck") or n.begins_with("head") or p == head) or not p.spots.is_empty():
			continue
		var lost: int = p.fx.size() - p.alive_count
		var done: int = regrown.get(p, 0)
		if lost <= 0 or done >= int(p.fx.size() * 0.5):
			continue
		var live := {}
		for i in p.fx.size():
			if p.alive[i]:
				live[Vector3i(p.fx[i], p.fy[i], p.fz[i])] = true
		var back := PackedInt32Array()
		for i in p.fx.size():
			if p.alive[i]:
				continue
			var c := Vector3i(p.fx[i], p.fy[i], p.fz[i])
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if live.has(c + d):
					back.append(i)
					break
			if back.size() >= 4:
				break
		if not back.is_empty():
			p.restore_voxels(back)
			regrown[p] = done + back.size()
			p.hp = minf(100.0, p.hp + 2.0)
