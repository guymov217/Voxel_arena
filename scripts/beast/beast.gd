class_name Beast
extends Fighter
## A voxel animal or monster (beast.js): a stiff body held at its height by a spring and
## steered by setting its spin, legs on motorised hips and knees that trot, a biting head (or
## several), horns, tails and wings bolted on. Every part can be chipped and cut off. Behaviour
## by species: hunters stalk, crouch and pounce; chargers paw the ground and run you down; the
## bear hugs; the goat wanders; elephants walk their circle and stomp.

const JAW_T := 0.55
const ROLL_SPIN := 7.5   # a crocodile's death roll, rad/s (slowed by the man fighting it)
const PRY_RATE := 0.55   # how fast pulling away prises its jaws open (1 is free)

var species := "lion"
var skill := 0.7   # how keen it is (training's difficulty slider): how soon it strikes again
var sp: Dictionary = {}
var legs: Array = []
var heads: Array = []
var wings: Array = []
var gait := 0.0
const LEG_MOTOR_SIGN := -1.0   # Jolt's joint motor turns the child the other way round the axis
var gait_rate := 0.0     # how fast the stride turns over (rad/s)
var ground_y := 0.0      # the sand under the body, for where the feet go
var ground_ok := false
var ai := {}
var target: Node3D = null
var height := 0.8
var ride_adj := 0.0   # how far the body is let down so the feet stand on the sand
var want_y := 0.0     # where the trunk should ride (world y): the legs are driven to hold it there
var ik_legs := 0      # legs that stand on their feet (a lower part, not splayed): they carry the body
var bite_power := 45.0
var hug = null
var holds: Array = []                # the joints of a hold: jaws on a limb, fists on a man (freed with it)
var down_t := 0.0
var flying := false
var rng := RandomNumberGenerator.new()
var on_breath: Callable
var on_venom: Callable               # (beast, victim, part, point): poison where it struck
const VENOMOUS := {"scorpion": "sting", "manticore": "sting", "spider": "bite", "python": "bite", "basilisk": "bite"}
var coil_cool := 0.0
var on_stomp: Callable
var on_roar: Callable
var on_thump: Callable   # a fist on its own chest (the gorilla's display): the drum is heard
# Animation: the parts that move on their own joints (necks, heads, tails, wings, trunks,
# pincers, the coils of a snake), their rest pose against their parent and how far they bend.
var anim: Array = []                 # [{part, role, rest: Quaternion, lim, i}]
var strikes := {}                    # part -> seconds left of its strike (a bite, a sting, a swipe)
var strike_cool := {}                # part -> seconds until it may strike again
var wind := {}                       # part -> seconds of wind-up left before its strike goes
var pending := {}                    # part -> [body, impulse] given when the wind-up ends
var on_strike: Callable              # (beast, part): a strike goes (a sound for the victim)
## The wind-up before each kind of strike: the head drawn back, the paw raised, the tail cocked,
## so a man sees the blow coming and knows what hit him. By the part's role (or a leg).
const WINDUP := {"neck": 0.3, "head": 0.28, "tail": 0.32, "claw": 0.22, "arm": 0.25, "leg": 0.3}
## Thick hide, scales or shell: an edge or a point gets in only a fraction of its sharpness and
## some of its force skids off. A committed thrust (the man's weight behind the point) finds its
## way through more than a slash.
const HIDE := {"elephant": 0.4, "mammoth": 0.45, "rhino": 0.5, "crocodile": 0.6, "dragon": 0.5, "basilisk": 0.65, "scorpion": 0.55}
var regrown := {}                    # hydra: part -> voxels regrown so far
var base_bite := 45.0
var jaw_t := 0.0                     # counts down from JAW_T through a bite
var breath_mark = null   # where a breath being poured is meant to land: it turns to it (Match)
var breath_t := 0.0                  # the mouth held wide while fire or venom pours out
var collapsed_now := false           # down on its belly this step (legs gone or bled out)
var breath_pitch := 0.0              # the head tipped so the jaws point at the breath mark
const NECK_DIP := 2.0
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
	# A beast is harder to kill than a man: thicker bone and more of it under the skin.
	mods.toughness = float(sp.get("toughness", 1.7)) * (1.3 if boss else 1.0)
	yaw = yaw_
	height = float(sp.height) * S
	bite_power = float(sp.get("bite", 45.0))
	base_bite = bite_power
	var yaw_q := Quaternion(UP, yaw)
	for d in sp.parts:
		var voxels := []
		for v in d.voxels:
			voxels.append([v[0], v[1], v[2], Color.hex(int(v[3]) << 8 | 0xff), v[4]])
		# Only how it looks: fur, scales or shell, markings, bone, eyes (BeastStyle).
		voxels = BeastStyle.style_part(species, str(d.name), d.get("grid", [1, 1, 1]), voxels)
		# The organs inside (Anatomy.dress_beasts): wet flesh, their id carried with each voxel.
		var plain := Anatomy.gore() == "reduced"
		for i in voxels.size():
			var organ: int = int(d.voxels[i][5]) if d.voxels[i].size() > 5 else 0
			if organ != Anatomy.NONE:
				voxels[i][5] = 9
				if plain:
					voxels[i][3] = BeastStyle.FLESH_A
			voxels[i].append(organ)
		var p := VoxelPart.new()
		var dd: Dictionary = d.duplicate()
		dd.erase("voxels")
		# A leg weighs its share of the body (a thigh 7%, a shin 5%): legs modelled far too
		# light for the body on them gave at the joints under its weight (the ostrich's folded
		# sideways through their limits and it sat on the sand).
		var m_part := float(d.mass)
		if d.leg:
			var n_legs: int = maxi(2, sp.parts.filter(func(q): return q.get("leg", false) and not q.get("lower", false)).size())
			m_part = maxf(m_part, float(sp.parts[0].mass) * (0.14 if d.lower else 0.2) / float(n_legs))
		p.setup(self, dd, voxels, float(d.scale) * k, m_part * MS)
		p.linear_damp = 0.3
		p.angular_damp = 2.0
		p.collision_layer = VoxelPart.LAYER_BODY
		var no_ground: bool = d.leg and not d.lower
		p.collision_mask = VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS | (0 if no_ground else VoxelPart.LAYER_WORLD)
		var pm := PhysicsMaterial.new()
		# A paw grips, but on four legs a mistimed step slides rather than folding the leg back
		# under; a two-legged runner (the ostrich) needs all the grip it can get.
		var bipedal: bool = sp.parts.filter(func(q): return q.get("leg", false) and q.get("lower", false)).size() <= 2
		pm.friction = (1.1 if bipedal else 0.7) if d.lower else 0.8
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
	_count_organs()
	for a in parts:
		for b in parts:
			if a != b:
				a.add_collision_exception_with(b)
	# A head on a long neck (an ostrich's, a dragon's) meets its own body: folded down, it rested
	# inside its chest. (Its neck, jointed on there, still passes.)
	for p in parts:
		if (p == head or String(p.part_name).begins_with("neck")) and p.parent_part != null and p.parent_part != torso:
			p.remove_collision_exception_with(torso)
			torso.remove_collision_exception_with(p)
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
			if lower_of(p) != null and absf(float(p.def.get("splay", 0.0))) < 0.3:
				ik_legs += 1
		if p == head or p.def.get("head", false):
			heads.append(p)
		if float(p.def.get("wing", 0)) != 0.0:
			wings.append(p)
	_setup_anim()
	for p in parts:
		if p.def.get("bite", false) and p.def.get("jaw") is Dictionary:
			p.build_jaw(p.def.jaw)
	ai = {"mode": "aim" if sp.ai == "charger" else "stalk", "t": 1.5 + rng.randf() * 1.5, "circle": 1.0 if rng.randf() < 0.5 else -1.0, "bite_cool": 2.5, "roar_cool": 4.0, "dodge_cool": 0.0, "breath_cool": 3.0, "fly_cool": 6.0, "alt": 0.0}

## Hide first: the blow is softened by what it has to get through (HIDE), then lands as on any body.
func apply_hit(part: VoxelPart, hit: Dictionary) -> Dictionary:
	# Coils wrapped round a man knock against him as they close: that is the hold itself, not a
	# blow that shakes the snake off him (his blows and kicks still do).
	if hug != null and hug.get("coil", false) and hit.get("bump", false):
		var keep := stagger
		var r := apply_hit_inner(part, hit)
		stagger = keep
		return r
	return apply_hit_inner(part, hit)

func apply_hit_inner(part: VoxelPart, hit: Dictionary) -> Dictionary:
	var k: float = float(HIDE.get(species, 1.0))
	var typ: String = hit.get("type", "blunt")
	if k < 1.0 and not part.severed and (typ == "edge" or typ == "point"):
		var th := clampf(float(hit.get("thrust", 0.0)), 0.0, 1.0)
		var kk := lerpf(k, 1.0, 0.6 * th)
		hit = hit.duplicate()
		hit.sharpness = float(hit.get("sharpness", 0.0)) * kk
		hit.impulse = float(hit.get("impulse", 0.0)) * (0.55 + 0.45 * kk)
		var res := super.apply_hit(part, hit)
		res.hide = true
		_break_by_damage(part, res)
		return res
	var res2 := super.apply_hit(part, hit)
	_break_by_damage(part, res2)
	return res2

## Parts that carry weight or other parts: beaten past what they can take they hang broken
## first, and only more harm tears them away.
const HANG_FIRST := ["neck", "goatNeck", "arm", "coil", "wing", "trunk", "abdomen"]
const TEAR_OVER := 40.0   # harm past nothing left that tears a broken part away

## Every part breaks on its own by the harm it took, whatever the blow (a club breaks a horn
## too): with no hp left a horn, a tusk, a tail, a pincer or a crest snaps off; a leg, a neck,
## a wing or a coil hangs broken and tears away under more. The trunk and the head end the
## beast instead.
func _break_by_damage(part: VoxelPart, res: Dictionary) -> void:
	if part == torso or part.severed or part.missing or part.hp > 0.0 or torso.freeze:
		return
	if part == head and not sp.get("multiHead", false):
		return
	var n := String(part.part_name)
	var hangs: bool = part.def.get("leg", false) or heads.has(part) or HANG_FIRST.any(func(h): return n.begins_with(h))
	if hangs and not part.hanging:
		hang(part, res)
		return
	if hangs:
		var over: float = float(part.get_meta("over", 0.0)) + float(res.get("dmg", 0.0))
		part.set_meta("over", over)
		if over < TEAR_OVER:
			return
	detach_limb(part, res)

func live_mass() -> float:
	var m := 0.0
	for p in parts:
		if not p.severed:
			m += p.mass
	return m

func heads_left() -> Array:
	return heads.filter(func(h): return not h.severed and h.hp > 0.0)

func _box_low(p: VoxelPart) -> float:
	var b := p.global_transform
	var h := p.half_ext
	return b.origin.y - absf(b.basis.x.y) * h.x - absf(b.basis.y.y) * h.y - absf(b.basis.z.y) * h.z

## How far a leg swings fore and aft at a speed (radians), wider the faster it goes.
func stride_amp(speed: float) -> float:
	return 0.42 * minf(1.0, 0.35 + speed / (2.5 * S)) + 0.2 * clampf((speed - 2.5 * S) / (4.0 * S), 0.0, 1.0)

## Hip to sole of a leg, the upper and the lower part together.
func leg_len() -> float:
	if _leg_len > 0.0:
		return _leg_len
	for l in legs:
		var lo := lower_of(l)
		_leg_len = l.half_ext.y * 2.0 + (lo.half_ext.y * 2.0 if lo else 0.0)
		break
	if _leg_len <= 0.0:
		_leg_len = 0.5 * S
	return _leg_len
var _leg_len := 0.0

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
	_free_holds()
	flying = false
	# Dead, a neck does not fold back in through the body it is jointed on (its bend forward,
	# opened wide for its strikes, is left as it is).
	for p in parts:
		if p.parent_part == torso and String(p.part_name).begins_with("neck") and p.joint is Generic6DOFJoint3D:
			(p.joint as Generic6DOFJoint3D).set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.5)
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
	var beat := 0.5 + 0.5 * sin(time * TAU * 1.1) if alive and blood > 5.0 and heart_t < 0.0 else 0.0
	for p in parts:
		bleed += p.bleed + p.artery
		p.bleed = maxf(0.0, p.bleed - dt * 0.1)
		p.update_drips()
		p.update_blood(dt, beat)
		if p.flinch_t > 0.0:
			p.flinch_t -= dt
	if torso.stump:
		bleed += 2.5
	blood = maxf(0.0, blood - bleed * 0.3 / (S * S) * dt)
	_organs_tick(dt)
	stagger = maxf(0.0, stagger - dt * 1.5)
	if push_t > 0.0:
		push_t -= dt
	if alive and (blood <= 0.0 or torso.hp <= 0.0 or (heads_left().is_empty() if sp.get("multiHead", false) else head.hp <= 0.0)):
		die("wounds")
	if alive and neck_broken():
		die("neck")
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
	collapsed_now = collapsed
	var missing := legs.size() - legs_left
	var crouching := 0.93 if ai.mode == "crouch" else ((1.08 if float(ai.t) > 0.4 else 0.96) if ai.mode == "breathe" else 1.0)
	if strikes.has(head) and head.parent_part != torso:
		crouching = 0.8   # a long-necked beast drops its forequarters into a downward strike
	var h_want: float = float(sp.parts[0].dims[1]) * V * S * 0.5 if collapsed else height * (0.8 if legs_left < 4 else 1.0) * crouching
	h_want *= 1.0 + 0.008 * sin(time * 1.7 / sqrt(S) + slot)   # breathing
	var dist_g: float = pos.y - hit.position.y if hit else 99.0
	ground_ok = not hit.is_empty() and dist_g < height * 2.0
	if ground_ok:
		ground_y = hit.position.y
	# The feet on the sand, never over it: the body rides lower until the legs it stands on
	# reach the ground (a species' height a little over its legs' reach held it hovering).
	# (Not while it strikes or charges: let down in mid-attack, its head came in under a man
	# and threw him high.)
	# A runner's charge is a run like any other: held up at full height it ran with its feet
	# off the sand, paddling the air.
	var attacking: bool = not strikes.is_empty() or (ai.mode == "charge" and sp.ai == "charger")
	if attacking:
		ride_adj = move_toward(ride_adj, 0.0, dt * 0.3)
	var carried: bool = ik_legs >= maxi(1, int(ceil(legs.size() * 0.5))) and not collapsed and not down_t > 0.0
	if carried and not attacking:
		# Carried on its legs the body rides as high as they hold it; nothing lets it down.
		ride_adj = move_toward(ride_adj, 0.0, dt * 0.6)
	elif hit and not flying and not collapsed and legs.size() > 0 and not attacking:
		var gap := 0.0
		var nf := 0
		for li in legs.size():
			var l: VoxelPart = legs[li]
			if leg_gone(l) or strikes.has(l):
				continue
			if gait_rate > 0.0 and fposmod(_leg_phase(li) + PI * 0.5, TAU) >= PI:
				continue   # a foot in the air, being carried forward
			var ft: VoxelPart = lower_of(l) if lower_of(l) else l
			gap += _box_low(ft) - hit.position.y
			nf += 1
		if nf > 0:
			ride_adj = clampf(ride_adj + (gap / nf) * minf(1.0, dt * 6.0), -0.04 * S, 0.35 * height)
	h_want -= ride_adj
	var grounded: bool = hit and dist_g < maxf(h_want, height) + 0.25 * S
	if hit and not grounded and not flying:
		# Reared up on legs that hold it, the body is high over the sand but the feet are on it.
		for l in legs:
			var ft: VoxelPart = lower_of(l) if lower_of(l) else l
			if not leg_gone(l) and _box_low(ft) - hit.position.y < 0.08 * S:
				grounded = true
				break
	if flying:
		var want_y: float = float(ai.alt) * (1.0 - 0.5 * injury)
		torso.apply_central_impulse(Vector3(0, mass * (gravity + 6.0 * (want_y - pos.y) - 3.0 * lv.y) * dt, 0))
	elif grounded:
		want_y = hit.position.y + h_want
		var legs_carry: bool = ik_legs >= maxi(1, int(ceil(legs.size() * 0.5))) and not collapsed and not down_t > 0.0 and not float(ai.get("rear", 0.0)) > 0.0 and legs_left >= maxi(1, int(ceil(legs.size() * 0.5)))
		if legs.size() <= 2 and legs.any(func(l): return strikes.has(l)):
			legs_carry = false   # a two-legged runner kicking: the one leg under it gets help
		if legs_carry:
			# The body's whole weight rests on its legs: the leg motors drive each foot onto the
			# sand under where the hip should ride (_leg_ik), and the feet, stopped by the sand,
			# push the body up to its height. The trunk only damps the bounce of the stride, and
			# a body thrown up over its height (a charge into a man, a leg vaulting off him) is
			# pulled back down onto its legs: a ton of beast does not leap.
			var over := maxf(0.0, dist_g - h_want - 0.12 * S)
			torso.apply_central_impulse(Vector3(0, -(6.0 * lv.y + 50.0 * over) * mass * dt, 0))
		else:
			# No legs to carry it (a snake, a sprawling crocodile or spider, one collapsed or
			# down): the body is held by its own strength over the sand.
			var f := mass * (gravity + 120.0 * (h_want - dist_g) - 15.0 * lv.y)
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
	if breath_mark is Vector3:
		# Pouring fire it turns to where it pours, so the stream leaves the jaws onto the mark.
		yaw = atan2((breath_mark as Vector3).x - pos.x, (breath_mark as Vector3).z - pos.z)
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
			if float(ai.get("stomp", 0.0)) > STOMP_DOWN:
				# Reared up on the hind legs, the forefeet in the air.
				pitch = -0.55 * clampf((STOMP_T - float(ai.stomp)) / 0.35, 0.0, 1.0)
				K = 5.0
			elif float(ai.get("stomp", 0.0)) > 0.0:
				pitch = 0.16   # and down, the front pitched onto the forefeet
				K = 10.0
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
	var rolling: bool = hug != null and hug.get("roll", false) and is_instance_valid(hug.target)
	if rolling:
		_death_roll(dt)
	match "" if coiling or rolling else String(sp.ai):
		"hunter":
			want = _hunt(dt, t, to, dist, hurt, collapsed, legs_left, grounded, h_want, dist_g, mass)
			# A python that gets close throws its coils round the man even without a bite.
			if species == "python" and t and hug == null and coil_cool <= 0.0 and dist < 1.3 * S + 0.6 and fn_of(["coil"]) > 0.3 and rng.randf() < dt * 1.5 and _touching(t):
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
					want = to * (2.6 if dist > 1.0 * S else 1.2) * hurt   # it comes on at him on its hind legs
					if ai.rear < 0.4 and not ai.get("slammed", false):
						ai.slammed = true
						for n in ["legFL", "legFR"]:
							if by_name.has(n) and not leg_gone(by_name[n]):
								_strike(by_name[n], 0.45, 0.0, [], 0.0)
								var lo := lower_of(by_name[n])
								if lo:
									lo.apply_central_impulse(((t.torso.global_position - lo.global_position).normalized() + Vector3(0, -0.6, 0)) * 26.0 * S)
						torso.apply_central_impulse((to + Vector3(0, -0.4, 0)) * mass * 2.2)
					if ai.rear <= 0.0:
						ai.mode = "stalk"
						ai.bite_cool = 1.2
				else:
					want = to * float(sp.speed) * hurt
					if (species == "bear" or species == "gorilla") and dist < 1.4 * S and float(ai.get("rear_cool", 0.0)) <= 0.0 and hind_fn() > 0.5 and front_fn() > 0.35:
						ai.rear = 1.15
						ai.rear_cool = 4.0 + rng.randf() * 2.0
						ai.slammed = false
						for n in ["legFL", "legFR"]:
							if by_name.has(n) and not leg_gone(by_name[n]):
								_strike(by_name[n], 0.7, 0.0, [], 0.0)
					elif dist < 1.5 * S and ai.bite_cool <= 0.0 and front_fn() > 0.35 and part_ok(head, 0.15) and not _paws_on(t, 0.05).is_empty():
						hug = {"target": t, "t": 3.0, "tick": 0.3, "stagger0": stagger}   # a hand on him: the hold
						for n in ["legFLLo", "legFRLo"]:
							var fist: VoxelPart = by_name.get(n)
							if fist and not fist.severed:
								# Only a fist that is on him now takes hold (one in the air holds nothing:
								# a joint made from a fist a stride off his arm wrenched the elbow apart).
								var on: VoxelPart = Combat.current.touch_by(fist, t, 0.02) if Combat.current else null
								if on and Social.box_distance(on, fist.global_position) < maxf(fist.half_ext.x, maxf(fist.half_ext.y, fist.half_ext.z)) + 0.05:
									_hold(fist, on, fist.global_position)
									fist.set_meta("gripped", true)
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
			if (species == "mammoth" or species == "elephant") and t and dist < 18.0 * S:
				ai.charge_t = float(ai.get("charge_t", 0.0)) - dt
				if float(ai.charge_t) < -3.5 and dist > 0.8 * S:
					ai.charge_t = 2.2
					if on_roar.is_valid():
						on_roar.call(self)
				var spd := float(sp.speed) * (2.5 if float(ai.charge_t) > 0.0 else 1.5)
				want = to * spd * hurt
				yaw = atan2(to.x, to.z)
			# Close enough that the forefeet, coming down ahead of the chest, land on him.
			if t and float(ai.get("charge_t", 0.0)) <= 0.0 and dist < torso.half_ext.z * 1.5 + 0.9 * S * 0.5 and ai.bite_cool <= 0.0 and Vector3(sin(cur), 0, cos(cur)).dot(to) > 0.3 and leg_power() > 0.4:
				ai.bite_cool = 4.5
				ai.stomp = STOMP_T   # up on the hind legs, forefeet and trunk raised: then it comes down
				ai.stomped = false
				if on_strike.is_valid():
					on_strike.call(self, head)
			if ai.get("stomp", 0.0) > 0.0:
				ai.stomp -= dt
				# It walks up on him on its hind legs, as fast as brings the forefeet (ahead of the
				# chest) over him by the time they come down: at a walk they fell yards short.
				var reach := maxf(0.0, dist - torso.half_ext.z * 1.2)
				want = to * minf(3.0 * S, reach / maxf(0.15, float(ai.stomp) - STOMP_DOWN)) * hurt if float(ai.stomp) > STOMP_DOWN else Vector3.ZERO
				if float(ai.stomp) <= STOMP_HIT and not ai.get("stomped", false):
					ai.stomped = true
					torso.apply_central_impulse(Vector3(0, -1.0, 0) * mass * 2.5)   # the whole weight brought down
					_stomp()
			_trample(dt, lv)
	# Every beast that runs can run a man down, and one that has no bite, sting or fire left
	# still has its weight: it charges and rams him with it.
	if sp.ai != "path" and legs.size() > 0 and disarmed():
		_trample(dt, lv)
	_ram(dt)
	var moving := want.length_squared() > 0.05
	if grounded and stagger < 0.5 and not down:
		var kk := ((6.5 if float(ai.get("charge_t", 0.0)) > 0.0 else 3.0) if sp.ai == "path" else 6.0) * (0.6 if legs.size() > 0 and not collapsed else 1.0)
		torso.apply_central_impulse(Vector3(want.x - lv.x, 0, want.z - lv.z) * mass * kk * dt)
	_abilities(dt, t, to, dist, cur)
	_animate(dt, moving, yaw_rate, to, dist, cur)
	if species == "hydra":
		_regrow(dt)
	_drive_legs(dt, Vector2(lv.x, lv.z).length(), collapsed, down, moving)
	# The legs step as fast as the ground goes by: each foot down covers the ground the body
	# travels in that half stride, so it stands while the body goes over it (at a fixed pace
	# per speed the long-bodied, short-legged ones dragged their feet along the sand).
	var spd := Vector2(lv.x, lv.z).length()
	var sweep := 2.0 * leg_len() * sin(stride_amp(spd))
	gait_rate = maxf(maxf(1.2, spd) * 4.6 / S, PI * spd / maxf(0.08, sweep)) if moving else 0.0
	gait += dt * gait_rate

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
			ai.mode = "fly"; ai.t = 2.0; ai.alt = 2.4 * S; ai.fly_t = 6.0 + rng.randf() * 3.0   # a short flight: it is down on him again soon
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
				ai.mode = "stalk"; ai.t = 1.0; ai.fly_cool = 14.0 + rng.randf() * 6.0
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
			if disarmed():
				# Nothing to bite with: no circling at a distance, it comes straight on and
				# throws its weight at him as soon as it is close.
				want = to * spd * hurt * 0.8
				if dist < 2.5 * S and ai.t > 0.2:
					ai.t = 0.2
			if swing > 4.5 and dist < 2.8 * S and ai.dodge_cool <= 0.0:
				ai.mode = "dodge"; ai.t = 0.35; ai.dodge_cool = 1.4
			elif sp.breath != null and ai.breath_cool <= 0.0 and can_breathe() and dist < float(sp.breathRange) * S * 0.8 and dist > 1.5 * S:
				ai.mode = "breathe"; ai.t = 0.7
				if species == "dragon" and on_roar.is_valid():
					on_roar.call(self)   # the roar before the fire: the warning to run
			elif ai.t <= 0.0:
				var roll := rng.randf()
				# A dragon does not dance about: it comes on (a feint only now and then, no snarling
				# from a distance), and every charge is told by the crouch and the roar before it.
				var feint_k := 0.1 if species == "dragon" else 0.25
				var snarl_k := 0.1 if species == "dragon" else 0.4
				if roll < feint_k:
					ai.mode = "feint"; ai.t = 0.3
				elif roll < snarl_k:
					ai.mode = "snarl"; ai.t = 0.5
				elif disarmed():
					# Jaws broken, fire gone: all it has left is its weight, so it charges.
					ai.mode = "crouch"; ai.t = 0.45
					if on_roar.is_valid() and rng.randf() < 0.5:
						on_roar.call(self)
				elif hind_fn() < 0.45 or injury > 0.6:
					ai.mode = "feint"; ai.t = 0.4   # too hurt to pounce: it rushes in on the ground
				else:
					ai.mode = "crouch"; ai.t = 0.45
		"feint":
			want = to * spd * hurt * 0.8
			if ai.t <= 0.0:
				ai.mode = "recover"; ai.t = 0.5
		"breathe":
			# It fills its chest standing, then comes on a step with the fire, head out at the prey.
			# It fills its chest standing, then comes on a step with the fire; close in it stands
			# and pours (over a man at its feet it would only fold its neck under itself).
			want = to * spd * hurt * (0.0 if ai.t > 0.4 or dist < 2.2 * S else 0.5)
			if ai.t <= 0.0:
				ai.mode = "stalk"; ai.t = (0.5 + rng.randf() * 0.5) if species == "dragon" else (1.0 + rng.randf()); ai.breath_cool = 4.5 if species == "dragon" else 7.0
				_breathe()
		"snarl":
			if ai.t <= 0.0:
				ai.mode = "stalk"; ai.t = 1.0 + rng.randf() * 1.5
		"crouch":
			if ai.t <= 0.0:
				ai.mode = "charge"; ai.t = 2.5
				if species == "dragon" and on_roar.is_valid() and rng.randf() < 0.6:
					on_roar.call(self)
		"dodge":
			want = side * spd * hurt
			if ai.t <= 0.0:
				ai.mode = "stalk"; ai.t = 0.6 + rng.randf()
		"charge":
			want = to * spd * hurt
			if t.state != "stand" and t.alive:
				ai.mode = "stalk"; ai.t = 1.0 + rng.randf(); ai.bite_cool = maxf(ai.bite_cool, 1.2); ai.circle = -ai.circle
			elif _in_bite_reach(t, dist) and ai.bite_cool <= 0.0:
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

## Close enough to bite: a head on a long neck (a dragon's) is judged by where the head is,
## not the body: from the body's distance it snapped at the air two metres short of the man.
func _in_bite_reach(t, dist: float) -> bool:
	if by_name.has("neck") and not sp.get("multiHead", false) and t.get("torso") and not head.severed:
		# Over the ground: the head is held high and strikes down onto him.
		var d: Vector3 = t.torso.global_position - head.global_position
		return Vector2(d.x, d.z).length() < 0.7 + 0.25 * S
	return dist < 1.1 + 0.6 * S

func _lunge(to: Vector3, mass: float, collapsed: bool) -> void:
	var k: float = float(sp.lunge) * (0.15 if collapsed else 1.0) * (1.0 - 0.5 * injury) * (0.35 + 0.65 * hind_fn())
	torso.apply_central_impulse(Vector3(to.x * mass * k, mass * (0.2 if collapsed else 1.2), to.z * mass * k))
	if disarmed():
		ai.ram_t = 0.8   # nothing to bite with: the body itself is the blow
	for h in biting_heads():
		_strike(h, 0.35, 0.0, [h, Vector3(to.x * 40.0 * S, 15.0 * float(sp.get("lungeUp", 1.0) if sp.get("lungeUp", 0) else 1.0), to.z * 40.0 * S)], 0.0)
	ai.bite_cool = float(sp.cooldown) * (1.0 + injury)

## The ram: a beast with no bite left throws its weight at him; what it hits, it hits as hard as
## the contact (the impulse the engine put through him), and he goes down under it.
func _ram(dt: float) -> void:
	ai.ram_t = float(ai.get("ram_t", 0.0)) - dt
	if ai.ram_t <= 0.0 or Combat.current == null:
		return
	var t = target
	if t == null or not is_instance_valid(t) or not t.alive or not _touching(t, 0.25):
		return
	var part: VoxelPart = Combat.current.touch_part(self, t, 0.25)
	if part == null or part.severed:
		return
	ai.ram_t = 0.0
	var J := clampf(_touch_force(t) * 0.005, 8.0, 28.0)
	var dir: Vector3 = (t.torso.global_position - torso.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	var at: Vector3 = part.global_position - dir * part.half_ext.z
	var was: bool = t.alive
	var res: Dictionary = t.apply_hit(part, {"impulse": J, "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "point": at, "dir": dir, "heavy": 0.8})
	t.last_attacker = self
	if t.has_method("fall") and t.state == "stand":
		t.fall(1.2, true)
	Combat.current.hit.emit({"kind": "hit", "p": at, "dir": dir, "J": J, "type": "blunt", "char": t, "part": part, "attacker": self, "res": res, "killed": was and not t.alive, "ram": true})
	ai.bite_cool = maxf(float(ai.bite_cool), 1.0)

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
	# The squeeze: what the coils actually bear on him, read off the physics (the impulse their
	# contacts put through him each step, the muscle pulling them tight on top of their weight),
	# over the area of chest they cover.
	var muscle := fn_of(["coil"]) * (0.4 + 0.6 * float(hug.tight))
	var force := _touch_force(tgt) * (0.6 + 1.4 * muscle)
	var area: float = 2.0 * PI * r * (0.16 * tgt.S * coils.size())
	var pressure := force / maxf(0.05, area)          # N/m^2
	# He is held: no breath, arms pinned to his sides.
	tgt.stamina = maxf(0.0, tgt.stamina - pressure * 0.004 * dt)
	# He is not nailed to the spot: with breath left he keeps his feet and can tear away (the
	# coils drag on him); only tight coils on a winded man bring him down.
	var fresh: bool = tgt.stamina >= 35.0
	tgt.stagger = minf(tgt.stagger, 0.5) if fresh else maxf(tgt.stagger, 0.6)
	if tgt.state == "stand" and float(hug.tight) > 0.5 and not fresh:
		tgt.fall(2.0, true)
	if hug.tick <= 0.0 and tgt.alive and _touching(tgt, 0.6):
		hug.tick = 0.45
		var J := clampf(pressure / 220.0, 3.0, 45.0)
		# Where the coils bear on him hardest (the physics' contact), of the chest and the arms
		# pinned to it that they are wound round; not a part picked at random.
		var part: VoxelPart = Combat.current.touch_part(self, tgt, 0.6)
		if part == null or part.severed or not (part == tgt.torso or part == tgt.by_name.get("upperArmR") or part == tgt.by_name.get("upperArmL")):
			part = tgt.torso
		var at2: Vector3 = part.global_position + (part.global_position - tc).normalized() * part.half_ext.x
		var res: Dictionary = tgt.apply_hit(part, {"impulse": J, "type": "blunt", "hardness": 0.4, "sharpness": 0.0, "point": at2, "dir": (tc - at2).normalized(), "crush": minf(0.09, 0.02 + J * 0.0015) if J > 18.0 else 0.0})
		tgt.last_attacker = self
		if Combat.current:
			Combat.current.hit.emit({"kind": "hit", "p": at2, "dir": (tc - at2).normalized(), "J": J, "type": "blunt", "char": tgt, "part": part, "attacker": self, "res": res, "killed": not tgt.alive})
	# Wrenched free: his struggle (what breath he has left), blows that stagger the snake, or
	# coils too cut up to hold.
	var escape: float = tgt.stamina / 100.0 * float(tgt.mods.get("strength", 1.0)) * 0.04 * dt * 60.0 / maxf(0.3, muscle)
	# Running (or crawling, or just straining) away pulls the coils off him: the harder he
	# pulls away, the sooner, and the coils slacken as he does.
	var away: Vector3 = tgt.torso.global_position - torso.global_position
	away.y = 0.0
	var run_off := 0.0
	if away.length_squared() > 0.01:
		var tv: Vector3 = tgt.torso.linear_velocity - torso.linear_velocity
		var lm: Vector3 = tgt.get("last_move") if tgt.get("last_move") is Vector3 else Vector3.ZERO
		run_off = maxf(0.0, Vector3(tv.x, 0, tv.z).dot(away.normalized()) / 1.5) + maxf(0.0, lm.dot(away.normalized()))
	escape *= 1.0 + 6.0 * minf(1.5, run_off) * (0.4 + 0.6 * tgt.stamina / 100.0)
	if run_off > 0.5:
		hug.tight = maxf(0.0, float(hug.tight) - dt * 0.8 * minf(1.5, run_off))
	# (A snake just wrapped round him is not shaken off by the first knock: only after a second.)
	if hug.t <= 0.0 or not tgt.alive or (hug.t < 6.0 and stagger > float(hug.stagger0) + 0.45) or fn_of(["coil"]) < 0.25 or rng.randf() < escape * dt or (hug.t < 6.0 and not _touching(tgt, 1.0)):
		_release_coil()   # (the coils off him, he is out of them)

func _release_coil() -> void:
	if hug != null and hug.get("coil", false):
		hug = null
		_free_holds()
		coil_cool = 4.0
		ai.mode = "recover"
		ai.t = 1.2

func _squeeze(dt: float) -> void:
	hug.t -= dt
	hug.tick -= dt
	var tgt = hug.target
	# Only the arms hold and crush: a paw or a fist on him (its belly against him is no squeeze).
	var paws := _paws_on(tgt, 0.5)
	var held := not paws.is_empty()
	if hug.tick <= 0.0 and tgt.alive and held:
		hug.tick = 0.5
		# The arms' force on him, read off the physics of their contacts.
		var on: VoxelPart = Combat.current.touch_by(paws[0], tgt, 0.5) if Combat.current else tgt.torso
		var J := clampf(_touch_force(tgt) * 0.004, 3.0, 20.0)
		var p: Vector3 = on.global_position
		tgt.apply_hit(on, {"impulse": J, "type": "blunt", "hardness": 0.5, "sharpness": 0.0, "point": p, "dir": (torso.global_position - p).normalized()})
		tgt.last_attacker = self
	if not held and hug.t < 2.6:
		# He got out of its arms: nothing in them, the hold is over.
		hug = null
		_free_holds()
		ai.bite_cool = 2.0
		ai.mode = "recover"
		ai.t = 1.0
		return
	# The gorilla does not squeeze for long: a hand on an arm, a hand on a leg, and the man is
	# torn in two. The hand not yet on him reaches for him (the arm's pull, like a blow's, only
	# slower) and takes hold where it lands.
	if species == "gorilla":
		_ape_reach(tgt)
	var fists := _fists_on(tgt) if species == "gorilla" else []
	if fists.size() >= 2 and hug.t < 1.6 and not hug.get("rent", false) and tgt.alive and not (tgt is Beast):
		hug.rent = true
		_rend(tgt, fists)
		hug = null
		_free_holds()
		ai.bite_cool = 4.0
		ai.mode = "recover"
		ai.t = 2.0
		return
	if hug.t <= 0.0 or not tgt.alive or stagger > hug.stagger0 + 0.35 or front_fn() < 0.3 or not part_ok(head, 0.1):
		hug = null
		_free_holds()
		ai.bite_cool = 3.0
		ai.mode = "recover"
		ai.t = 1.5

## Torn in two: the held arm and the leg across from it come away, the trunk is wrenched open
## between them, and what is left is flung down.
## The forepaws (a bear's paws, the ape's fists) on him within `within` seconds: the arms a
## hold is made with.
func _paws_on(tgt, within: float) -> Array:
	var out := []
	for n in ["legFLLo", "legFRLo"]:
		var paw: VoxelPart = by_name.get(n)
		if paw and not paw.severed and Combat.current and Combat.current.touch_by(paw, tgt, within) != null:
			out.append(paw)
	return out

## In the hug, each of the ape's fists not yet on him is driven at the limb it will tear (the
## right fist at his left leg, the left at his right arm, or the other way about), and holds fast
## once it touches.
func _ape_reach(tgt) -> void:
	var tv: Vector3 = torso.linear_velocity
	for n in ["legFLLo", "legFRLo"]:
		var fist: VoxelPart = by_name.get(n)
		if fist == null or fist.severed:
			continue
		var on: VoxelPart = Combat.current.touch_by(fist, tgt, 0.05) if Combat.current else null
		if on:
			if not fist.get_meta("gripped", false) and Social.box_distance(on, fist.global_position) < maxf(fist.half_ext.x, maxf(fist.half_ext.y, fist.half_ext.z)) + 0.05:
				fist.set_meta("gripped", true)
				_hold(fist, on, fist.global_position)
			continue
		var want_part = tgt.by_name.get("thighL" if n == "legFRLo" else "upperArmR")
		if want_part == null or want_part.severed:
			want_part = tgt.torso
		var dir: Vector3 = (want_part.global_position - fist.global_position).normalized()
		var dv: Vector3 = dir * 3.5 * sqrt(S) - (fist.linear_velocity - tv)
		var acc := (dv / maxf(0.02, get_physics_process_delta_time() * 4.0)).limit_length(APE_PULL * 0.6 * sqrt(S))
		fist.apply_central_force(acc * fist.mass)
		torso.apply_central_force(-acc * fist.mass * 0.5)

## The gorilla's fists that are on him now (the physics' contacts), for the tearing.
func _fists_on(tgt) -> Array:
	var out := []
	for n in ["legFLLo", "legFRLo"]:
		var fist: VoxelPart = by_name.get(n)
		if fist and not fist.severed and Combat.current and Combat.current.touch_by(fist, tgt, 0.3) != null:
			out.append(fist)
	return out

func _rend(tgt, fists: Array) -> void:
	var was: bool = tgt.alive
	var res := {"removed": [], "severed": [], "dmg": 0.0}
	var torn := []
	# The arm in one fist, the leg across from it in the other: each torn where the hand is.
	var f0: Vector3 = fists[0].global_position
	var side := "R" if tgt.arm.R.upper.global_position.distance_to(f0) < tgt.arm.L.upper.global_position.distance_to(f0) else "L"
	var arm: VoxelPart = tgt.arm[side].upper
	if not arm.severed:
		tgt.detach_limb(arm, res)
		torn.append(arm)
	var leg: VoxelPart = tgt.by_name.get("thighL" if side == "R" else "thighR")
	if leg and not leg.severed:
		tgt.detach_limb(leg, res)
		torn.append(leg)
	var fwd := PD.quat_of(torso) * Vector3(0, 0, 1)
	for p in torn:
		var s := 1.0 if p == arm else -1.0
		p.linear_velocity = Vector3(fwd.z, 0, -fwd.x) * s * 5.0 + Vector3(0, 3.0, 0)
		p.angular_velocity = Vector3(6, 2, 4) * s
	var J := 40.0
	var point: Vector3 = tgt.torso.global_position
	var r2: Dictionary = tgt.apply_hit(tgt.torso, {"impulse": J, "type": "edge", "hardness": 0.9, "sharpness": 0.8, "point": point, "dir": Vector3.DOWN, "axis": Vector3.RIGHT, "edge": Vector3.DOWN, "heavy": 1.0, "wsz": 2.0})
	for k in ["removed", "severed"]:
		r2[k] = r2.get(k, []) + res[k]
	tgt.last_attacker = self
	tgt.fall(4.0, true)
	tgt.stagger = 1.0
	for p in tgt.parts:
		if not p.severed:
			p.linear_velocity = fwd * 4.0 + Vector3(0, -2.0, 0)
	if Combat.current:
		Combat.current.hit.emit({"kind": "hit", "att_part": head, "p": point, "dir": Vector3.DOWN, "J": J, "type": "edge", "char": tgt, "part": tgt.torso, "attacker": self, "res": r2, "killed": was and not tgt.alive, "rend": true})
	if on_strike.is_valid():
		on_strike.call(self, head)

## A crocodile's jaws close on a limb and do not let go: it rolls on its length with the limb
## held, wrenching it round until it comes away. He is dragged down and held while it rolls;
## he fights it: pulling away prises the jaws open and slows the roll (the more breath he has,
## the sooner), and a knock on the crocodile, or the limb coming off, ends it.
func _death_roll(dt: float) -> void:
	var tgt = hug.target
	var part: VoxelPart = hug.part
	hug.t -= dt
	hug.tick -= dt
	var mp := mouth_point()
	# The bitten place on the limb, where the teeth are in it: it stays in the mouth.
	var bite: Vector3 = part.global_transform * (hug.bite_at as Vector3) if is_instance_valid(part) else mp
	var gap := bite.distance_to(mp)
	# His struggle: any pull (crawling, straining) counts, most of all straight away from the jaws.
	var away: Vector3 = tgt.torso.global_position - head.global_position
	away.y = 0.0
	var lm: Vector3 = tgt.get("last_move") if tgt.get("last_move") is Vector3 else Vector3.ZERO
	var pull := minf(1.0, lm.length()) * (0.5 + 0.5 * maxf(0.0, lm.normalized().dot(away.normalized()))) if lm.length_squared() > 0.01 and away.length_squared() > 0.0001 else 0.0
	var breath := clampf(tgt.stamina / 100.0, 0.0, 1.0)
	hug.pry = float(hug.get("pry", 0.0)) + dt * pull * (0.25 + 0.75 * breath) * float(tgt.mods.get("strength", 1.0)) * PRY_RATE
	tgt.stamina = maxf(0.0, tgt.stamina - dt * 12.0 * pull)
	if not is_instance_valid(part) or part.severed or not tgt.alive or hug.t <= 0.0 or stagger > float(hug.stagger0) + 0.3 or float(hug.pry) >= 1.0 or not part_ok(head, 0.15) or gap > 0.25 * S:
		_release_roll()   # (the limb out of its jaws, the roll is over)
		return
	# Whatever the joint gives under the wrench is taken back up: teeth to the bitten place.
	var err: Vector3 = mp - bite
	part.apply_impulse((err * 60.0 - (part.linear_velocity - head.linear_velocity) * 8.0) * part.mass * dt, bite - part.global_position)
	if tgt.state == "stand":
		tgt.fall(1.0, true)
	tgt.stagger = maxf(tgt.stagger, 0.7)
	jaw_t = minf(jaw_t, 0.1)
	var fwd := PD.quat_of(torso) * Vector3(0, 0, 1)
	var spin := ROLL_SPIN * (1.0 - 0.45 * pull) * float(hug.spin)   # (his weight dragging against it)
	torso.angular_velocity = fwd * spin
	hug.turned = float(hug.turned) + absf(spin) * dt
	# The man goes round with it: the limb is locked in the jaws, and his trunk is wrenched over
	# after it (most of the way, his own weight dragging behind).
	var tw: Vector3 = tgt.torso.angular_velocity
	var about := tw.dot(fwd)
	tgt.torso.angular_velocity = tw + fwd * (spin * 0.75 - about) * minf(1.0, dt * 12.0)
	if hug.tick <= 0.0 and gap < 0.12 * S:
		hug.tick = 0.45
		hug.bites = int(hug.bites) + 1
		var J := bite_power * 0.7
		var dir: Vector3 = (part.global_position - mp).normalized()
		var was: bool = tgt.alive
		var res: Dictionary = tgt.apply_hit(part, {"impulse": J, "type": "point", "hardness": 0.9, "sharpness": 1.0, "point": mp, "dir": dir, "axis": dir, "crush": 0.07, "wsz": S})
		tgt.last_attacker = self
		# Two full turns and three wrenches twist a limb (never the trunk or the head) clean off.
		if int(hug.bites) >= 3 and float(hug.turned) >= TAU * 2.0 and part != tgt.torso and part != tgt.head and not part.severed:
			tgt.detach_limb(part, res)
			res.rolled = true
		if Combat.current:
			Combat.current.hit.emit({"kind": "hit", "att_part": head, "p": mp, "dir": dir, "J": J, "type": "point", "char": tgt, "part": part, "attacker": self, "res": res, "killed": was and not tgt.alive, "bite": true, "roll": true})
		if part.severed:
			_release_roll()

func _release_roll() -> void:
	if hug != null and hug.get("roll", false):
		if is_instance_valid(hug.target):
			hug.target.remove_meta("rolled_by")
		hug = null
		_free_holds()
		coil_cool = 5.0
		ai.mode = "recover"
		ai.t = 1.5
		ai.bite_cool = 2.0

## Trampled: a man under the body of a running elephant (or mammoth) is knocked flat and the part
## of him under the feet crushed, again and again while it goes over him.
func _trample(dt: float, lv: Vector3) -> void:
	ai.trample_t = float(ai.get("trample_t", 0.0)) - dt
	if Vector2(lv.x, lv.z).length() < 1.2 or Combat.current == null:
		return
	var inv := torso.global_transform.affine_inverse()
	for f in Combat.current.fighters:
		if f == self or f is Beast or not is_instance_valid(f) or not f.alive or f.get("torso") == null:
			continue
		var l: Vector3 = inv * f.torso.global_position
		if absf(l.x) > torso.half_ext.x * 1.4 or absf(l.z) > torso.half_ext.z * 1.15 or l.y > 0.0:
			continue
		if not _touching(f, 0.3):
			continue   # over him but not on him (a leap, a step past): nothing crushed
		if f.state == "stand":
			f.fall(1.5, true)
		if ai.trample_t > 0.0:
			continue
		ai.trample_t = 0.4
		# The part it is on, and the weight it bears on him, both from the physics.
		var part: VoxelPart = Combat.current.touch_part(self, f, 0.3)
		if part == null or part.severed:
			continue
		var J := clampf(_touch_force(f) * 0.006, 8.0, 30.0)
		var at: Vector3 = part.global_position + Vector3(0, part.half_ext.y * 0.5, 0)
		var was: bool = f.alive
		var res: Dictionary = f.apply_hit(part, {"impulse": J, "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "point": at, "dir": Vector3.DOWN, "crush": minf(0.1, 0.003 * J * sqrt(S)), "heavy": 0.9})
		f.last_attacker = self
		f.fall(1.5, true)
		Combat.current.hit.emit({"kind": "hit", "p": at, "dir": Vector3.DOWN, "J": J, "type": "blunt", "char": f, "part": part, "attacker": self, "res": res, "killed": was and not f.alive, "trample": true})

## Fire (or venom) in a cone in front of the head.
func _breathe() -> void:
	if on_breath.is_valid() and can_breathe():
		breath_t = 1.0
		on_breath.call(self, String(sp.breath), float(sp.breathRange) * S)

## The elephant's stomp (s): it rears for the first part, then comes down; the blow lands at
## STOMP_HIT before the end.
const STOMP_T := 1.3
const STOMP_DOWN := 0.45
const STOMP_HIT := 0.3

func _stomping() -> bool:
	return float(ai.get("stomp", 0.0)) > 0.0

static func _foreleg(leg: VoxelPart) -> bool:
	return leg.part_name == "legFL" or leg.part_name == "legFR"

func _stomp() -> void:
	if on_stomp.is_valid():
		on_stomp.call(self)

func _drive_legs(dt: float, speed: float, collapsed: bool, down: bool, moving: bool) -> void:
	var n := legs.size()
	# The legs carry the whole body: each is driven with the strength to hold its share of the
	# weight (two legs hold twice what four do).
	var max_t := 120.0 * maxf(2.0, float(sp.parts[0].mass) * 0.05) * MS * (4.0 / maxf(2.0, float(n))) + 40.0
	for i in n:
		var leg: VoxelPart = legs[i]
		if leg.severed:
			continue
		var off := _leg_phase(i) - gait
		var phase := gait + off
		var hip := 0.0
		var knee := 0.06
		var hip_v := 0.0    # how fast the stride moves each joint, followed as well as the angle
		var knee_v := 0.0
		var wn := 70.0
		var planted := false
		if flying:
			hip = 0.55; knee = 0.7; wn = 40.0
		elif down:
			wn = 25.0; hip = sin(time * 3.0 + i) * 0.3; knee = 0.4
		elif collapsed:
			hip = sin(gait * 2.2 + off) * 0.55; knee = 0.35 + cos(gait * 2.2 + off) * 0.3; wn = 45.0
		elif lower_of(leg) != null and ground_ok and absf(float(leg.def.get("splay", 0.0))) < 0.3 and not float(ai.get("rear", 0.0)) > 0.0 and not (_stomping() and _foreleg(leg)):
			# Stepping on the sand: the foot is put down ahead and stays where it is put while
			# the body goes over it, then is lifted and carried forward; the hip and knee are
			# worked out from where the foot must be (a fixed swing of the joints dragged the
			# feet along under a body held up by its spring, as if it glided).
			var a0 := _leg_ik(leg, phase, speed)
			var a1 := _leg_ik(leg, phase + gait_rate * dt, speed)
			hip = a0.x; knee = a0.y
			hip_v = (a1.x - a0.x) / dt; knee_v = (a1.y - a0.y) / dt
			if ai.mode == "crouch":
				hip += 0.08
			planted = true
		elif moving:
			var amp := stride_amp(speed)
			hip = sin(phase) * amp
			knee = 0.06 + maxf(0.0, -cos(phase)) * amp * 1.9
			hip_v = cos(phase) * amp * gait_rate
			knee_v = sin(phase) * amp * 1.9 * gait_rate if cos(phase) < 0.0 else 0.0
			planted = true
			if ai.mode == "crouch":
				# Stalking low: the legs bent, hip forward over the knee, still stepping (it
				# folded its legs back under it and slid along the sand on them).
				hip += 0.1
				knee += 0.12
		else:
			hip = 0.03 * sin(time * 1.1 + i * 1.7) + (0.1 if ai.mode == "crouch" else 0.0)
			knee = 0.06 + (0.12 if ai.mode == "crouch" else 0.0)
			planted = true
		# A hurt leg steps short; a struck one buckles for a moment; a swiping one lashes forward.
		var lf := fn_of([leg.part_name])
		hip *= 0.35 + 0.65 * lf
		hip_v *= 0.35 + 0.65 * lf
		var lo0 := lower_of(leg)
		var fl: float = maxf(leg.flinch_t, lo0.flinch_t if lo0 else 0.0)
		if fl > 0.0:
			hip += fl * 0.6; knee += fl * 0.8
		var sp_off := 0.0   # the arm swung out to the side (a hook) and back across
		if strikes.has(leg) and String(leg.get_meta("ape", "")) != "":
			# The ape's blows, each its own swing of the arm (APE_BLOWS).
			var side := -signf(leg.pa.x)
			var winding := float(wind.get(leg, 0.0)) > 0.0
			match String(leg.get_meta("ape")):
				"jab":      # the fist drawn back to the shoulder, then driven straight out
					if winding: hip = 0.5; knee = 1.1
					else: hip = -1.35; knee = 0.1
				"hook":     # the arm swung out wide, then across in front
					if winding: hip = -0.3; knee = 0.7; sp_off = side * 1.0
					else: hip = -0.9; knee = 0.35; sp_off = -side * 0.5
				"slam":     # both fists raised high over the head, then brought down together
					if winding: hip = -2.3; knee = 0.6
					else: hip = 0.5; knee = 0.25
			wn = 55.0 if winding else 70.0
			planted = false
		elif strikes.has(leg):
			# Drawn up and back first, then lashed forward.
			if float(wind.get(leg, 0.0)) > 0.0:
				hip = 0.75; knee = 0.9; wn = 50.0
			else:
				hip = -1.1 * (0.5 + 0.5 * lf); knee = 0.25; wn = 60.0
			planted = false
		elif float(ai.get("beat", 0.0)) > 0.0 and leg.def.get("splay", 0.0) != 0.0 and species == "gorilla":
			# The chest beat: the fists drummed on the chest, one after the other.
			var k := int(float(ai.beat) * 9.0) + i
			hip = -1.05 + (0.25 if k % 2 == 0 else -0.1); knee = 1.45; wn = 60.0
			planted = false
		elif _stomping() and _foreleg(leg):
			if float(ai.stomp) > STOMP_DOWN:
				# Both forelegs drawn up and folded at the knee, one a little higher than the other.
				hip = 1.05 + (0.15 if leg.part_name == "legFL" else 0.0); knee = 1.2; wn = 45.0
			else:
				# Driven down hard, straight, a little ahead: the forefeet come down like columns.
				hip = -0.3; knee = 0.02; wn = 95.0
			planted = false
		if fl > 0.0:
			planted = false
		var splay: float = float(leg.def.get("splay", 0.0))
		if leg.hanging:
			continue
		var lo := lower_of(leg)
		var lo_ok: bool = lo != null and not lo.severed and not lo.hanging
		if planted:
			# Walking and standing the leg is driven stiff, angle and pace both: a soft spring on so
			# light a limb gave way to the sand's friction, the foot was dragged along under the
			# body and the beast seemed to glide with its legs paddling the air.
			_leg_motor(leg, torso, Quaternion.from_euler(Vector3(hip, 0, splay)), Vector3(hip_v, 0, 0), max_t, dt)
			if lo_ok:
				_leg_motor(lo, leg, Quaternion.from_euler(Vector3(knee, 0, float(lo.def.get("splay", 0.0)))), Vector3(knee_v, 0, 0), max_t, dt)
			continue
		_leg_motor_off(leg)
		pd_relative(leg, torso, Quaternion.from_euler(Vector3(hip, 0, splay + sp_off)), wn, 0.9, max_t, dt, 3.0, LEG_REACT)
		if lo_ok:
			_leg_motor_off(lo)
			pd_relative(lo, leg, Quaternion.from_euler(Vector3(knee, 0, float(lo.def.get("splay", 0.0)))), wn, 0.9, max_t * 0.7, dt, 3.0, LEG_REACT)

## A leg joint steered by its relative spin: toward the angle it should have, plus the pace the
## stride moves it at (`ff`, in the parent's frame), most of the gap closed each step.
func _leg_motor(part: VoxelPart, parent: VoxelPart, rel_q: Quaternion, ff: Vector3, max_t: float, dt: float) -> void:
	var pq := PD.quat_of(parent)
	var err := PD.rot_error(pq * rel_q, PD.quat_of(part))
	var rel := part.angular_velocity - parent.angular_velocity
	# What turns at the joint is the whole limb below it, about the joint, not the one part
	# about its own centre (ten times less on a hyena's leg, so the drive never caught up).
	var at: Vector3 = parent.global_transform * part.pa
	var inert := 0.0
	for q in [part] + part.child_parts:
		if not q.severed:
			inert += PD.inertia_of(q) + q.mass * (q.global_position - at).length_squared()
	# Fore and aft by the joint's own motor, which the solver holds against the body's weight
	# (a torque worked out from here gave under it: the knees folded and the feet dragged);
	# out to the side by a torque. The joint holds the twist.
	var ax: Vector3 = pq * Vector3.RIGHT
	var v := clampf(err.dot(ax) * 40.0, -14.0, 14.0) + ff.x
	var j := part.joint as Generic6DOFJoint3D
	if j:
		j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, v * LEG_MOTOR_SIGN)
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, max_t)
	var az: Vector3 = pq * Vector3.BACK
	var vz := clampf(err.dot(az) * 40.0, -14.0, 14.0) + ff.z
	if j and absf(float(part.def.get("splay", 0.0))) < 0.3:
		# Sideways too by the joint's motor, which the solver holds against the body's weight
		# (a torque gave: a two-legged runner's thighs folded out sideways through their limits
		# and it sat on the sand). A splayed leg (a scorpion's, a spider's) keeps its torque.
		j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, vz * LEG_MOTOR_SIGN)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, max_t)
	else:
		var tq := az * clampf((vz - rel.dot(az)) / dt * inert * 0.6, -max_t, max_t)
		part.apply_torque_impulse(tq * dt)
		parent.apply_torque_impulse(-tq * dt * LEG_REACT)

## Where leg `i` is in its stride: diagonal pairs step together.
func _leg_phase(i: int) -> float:
	var n := legs.size()
	var row := int(i / 2) if n == 8 or n == 4 else 0
	return gait + (PI if ((i % 2) + row) % 2 else 0.0)

## Hip and knee angles (relative, about the joints' fore-and-aft axis) that put this leg's foot
## where it belongs at this point of its stride: in stance on the sand, moving back under the
## body exactly as fast as the body goes forward; in the swing lifted and brought forward.
func _leg_ik(leg: VoxelPart, phase: float, speed: float) -> Vector2:
	var lo := lower_of(leg)
	var l1: float = maxf(0.02, leg.ca.y - lo.pa.y)
	var l2: float = maxf(0.02, lo.ca.y + lo.half_ext.y)
	var reach := l1 + l2
	var tf := torso.global_transform.orthonormalized()
	var hip_w: Vector3 = tf * leg.pa
	var dir := Vector3(torso.linear_velocity.x, 0, torso.linear_velocity.z)
	var off := Vector3.ZERO
	var lift := 0.0
	if gait_rate > 0.0 and dir.length() > 0.05:
		dir = dir.normalized()
		# Half a stride: what the ground covers in half a turn of the gait.
		var half := minf(reach * 0.55, PI * speed / (2.0 * gait_rate))
		var ph := fposmod(phase + PI * 0.5, TAU)
		if ph < PI:
			off = dir * half * (1.0 - 2.0 * ph / PI)
		else:
			var u := (ph - PI) / PI
			off = dir * (-half * cos(PI * u))
			lift = sin(PI * u) * reach * 0.22 * clampf(speed / (2.0 * S), 0.1, 1.0)   # a slow walk shuffles
	var target := Vector3(hip_w.x, ground_y + lift, hip_w.z) + off
	# From the hip as it should ride (want_y), not as it has sagged: a body that sinks asks
	# more extension of its legs, and the feet, stopped by the sand, push it back up.
	var hip_des := hip_w + Vector3(0, want_y - torso.global_position.y, 0) if want_y > 0.0 else hip_w
	var tl := tf.basis.inverse() * (target - hip_des)
	var d := clampf(Vector2(tl.z, tl.y).length(), absf(l1 - l2) + 0.01, reach * 0.995)
	var knee := acos(clampf((d * d - l1 * l1 - l2 * l2) / (2.0 * l1 * l2), -1.0, 1.0))
	var hip := atan2(-tl.z, -tl.y) - atan2(l2 * sin(knee), l1 + l2 * cos(knee))
	return Vector2(clampf(hip, -1.3, 1.3), clampf(knee, 0.0, 1.35))

## Lets a leg's joint go slack again when it is posed by torques instead (down, struck, flying).
func _leg_motor_off(part: VoxelPart) -> void:
	var j := part.joint as Generic6DOFJoint3D
	if j and j.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0.0)
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, 0.0)
		j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
	if j and j.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR):
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, 0.0)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, 0.0)
		j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)

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

## A single head on a neck (an ostrich's, a dragon's): the neck broken through, or hanging by
## a few voxels, or crushed, and the beast is dead (the many-headed only lose that head).
func neck_broken() -> bool:
	if sp.get("multiHead", false):
		return false
	for p in parts:
		if String(p.part_name).begins_with("neck") and (p.severed or p.hanging or p.hp <= 0.0):
			return true
	return false

func part_ok(p: VoxelPart, need := 0.25) -> bool:
	return p != null and not p.severed and not p.hanging and p.hp > 0.0 and p.function() > need

## The heads that can still bite, and how well the best of them does.
## Nothing left to fight with but its weight: no jaws that bite, no horns or tusks, no sting,
## no pincers, no fire.
func disarmed() -> bool:
	if not biting_heads().is_empty():
		return false
	if parts.any(func(p): return String(p.part_name).begins_with("horn") or String(p.part_name).begins_with("tusk")) and horn_fn() > 0.3:
		return false
	if by_name.has("stinger") and part_ok(by_name.stinger, 0.25):
		return false
	for n in ["clawL", "clawR"]:
		if by_name.has(n) and part_ok(by_name[n], 0.25):
			return false
	return sp.breath == null or not can_breathe()

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

## The front of the jaws, where a breath comes out, and the way the mouth points: followed every
## step, so the fire leaves the mouth however the head turns while it pours.
## With the jaws open the mouth is the gape between them: the breath leaves from the middle of
## the maw, along the line halfway between the snout and the hanging jaw, so a mouth opened
## and turned down pours its fire down.
func mouth_point() -> Vector3:
	var h := breath_part()
	if h.jaw_pivot != null:
		var hinge: Vector3 = h.jaw_pivot.position
		var along: Vector3 = Basis(Vector3.RIGHT, h.jaw_angle * 0.5) * Vector3(0, 0, 1)
		return h.global_transform * (hinge + along * (h.half_ext.z - hinge.z) * 0.7)
	return h.global_transform * Vector3(0, -0.3 * h.half_ext.y, h.half_ext.z * 1.05)

func mouth_dir() -> Vector3:
	var h := breath_part()
	var along := Vector3(0, 0, 1)
	if h.jaw_pivot != null:
		along = Basis(Vector3.RIGHT, h.jaw_angle * 0.5) * along
	return (PD.quat_of(h) * along).normalized()

## Out cold: collapsed with the head too far gone to use (and no other head), never to rise.
func is_out() -> bool:
	if not alive or not collapsed_now:
		return false
	return blood < 22.0 and heads.all(func(h): return h.severed or h.function() < 0.3)

func is_beaten() -> bool:
	return not alive or is_out()

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
		# The jaws flung wide for the fire; a head pointed steeply down opens less, so the
		# hanging jaw does not swing back through its own neck.
		var snout_y: float = (PD.quat_of(breath_part()) * Vector3(0, 0, 1)).y
		gape = 1.0 * clampf((snout_y + 0.75) / 0.45, 0.45, 1.0)
	elif hug != null and hug.get("roll", false):
		gape = 0.05   # clamped on the limb
	elif hug != null:
		gape = 0.3 + 0.25 * maxf(0.0, sin(time * 6.0))
	elif jaw_t > 0.0:
		gape = 0.75 * minf(1.0, (1.0 - k) / 0.35) if k > 0.3 else 0.75 * (k / 0.3)
	elif heads.any(func(h): return float(wind.get(h, 0.0)) > 0.0):
		gape = 0.6   # the jaws open as the head draws back
	elif ai.get("mode", "") == "snarl" or ai.get("mode", "") == "breathe" or ai.get("mode", "") == "crouch":
		gape = 0.35 if ai.mode != "breathe" else 0.6
	for p in heads:
		if not p.severed:
			p.set_gape(gape, dt)

## Breathing fire (or venom) the neck is driven forward at the prey and the head thrust out
## level with it, the jaws wide (a short draw back as it fills its chest, then the lunge),
## not reared up and back away from what it burns.
## The fire goes where the jaws point, so the jaws are pointed at the mark: the neck is dipped,
## a little more every step, until the mouth looks straight at where the breath is to land, and
## the head tips the rest of the way.
var breath_err := 0.0
var breath_yaw := 0.0
func _breath_mark_now() -> Variant:
	if breath_mark is Vector3:
		return breath_mark
	# Filling its chest, the jaws are already turned onto the prey, so the first of the fire goes
	# where the rest will.
	if ai.get("mode", "") == "breathe" and target and is_instance_valid(target) and target.get("torso"):
		return target.torso.global_position
	return null

func _breath_track(dt: float) -> void:
	var mark = _breath_mark_now()
	if _fire_lunge() <= 0.0 or not (mark is Vector3):
		breath_pitch = 0.0
		breath_err = 0.0
		breath_yaw = 0.0
		return
	# Lofted: the globs fall as they fly, so the jaws are held a little above the mark.
	var md := mouth_dir()
	var mouth := mouth_point()
	var speed := clampf(float(sp.breathRange) * S * 1.7, 6.0, 16.0)
	var t := mouth.distance_to(mark as Vector3) / maxf(1.0, speed * 0.92)
	var want := ((mark as Vector3) + Vector3(0, 0.5 * 9.81 * t * t, 0) - mouth).normalized()
	breath_err = asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(md.y, -1.0, 1.0))
	breath_pitch = clampf(breath_pitch - breath_err * dt * 6.0, -1.4, 0.9)
	var dy := atan2(want.x, want.z) - atan2(md.x, md.z)
	breath_yaw = atan2(sin(dy), cos(dy))

func _breath_aim(role: String) -> float:
	if _fire_lunge() <= 0.0 or not (_breath_mark_now() is Vector3):
		return 0.0
	if role == "neck":
		return 0.0   # the neck holds its thrust; it is the head that turns onto the mark
	return breath_pitch - clampf(breath_err * 0.8, -0.7, 0.7)   # (up to the joint's own limit)

## The jaws turned straight onto where the fire is to fall (lofted for the drop), in the world,
## whatever the neck under the head is doing: the fire goes the way the mouth points.
func _aim_jaws(p: VoxelPart, max_t: float, dt: float) -> void:
	var mark: Vector3 = _breath_mark_now()
	var mouth := mouth_point()
	var speed := clampf(float(sp.breathRange) * S * 1.7, 6.0, 16.0)
	var t := mouth.distance_to(mark) / maxf(1.0, speed * 0.92)
	var want := (mark + Vector3(0, 0.5 * 9.81 * t * t, 0) - mouth).normalized()
	var md := mouth_dir()
	var axis := md.cross(want)
	var ang := asin(clampf(axis.length(), 0.0, 1.0))
	if md.dot(want) < 0.0:
		ang = PI - ang
	var err := axis.normalized() * ang if axis.length_squared() > 1e-8 else Vector3.ZERO
	var wn := 14.0
	var inertia: float = p.mass * p.half_ext.length_squared() * 0.5
	for c in p.child_parts:
		if not c.severed:
			inertia += c.mass * (c.global_position - p.global_position).length_squared()
	var tq: Vector3 = (err * (wn * wn) - p.angular_velocity * (2.0 * 0.9 * wn)) * inertia
	tq = PD.clamp_len(tq, max_t)
	p.apply_torque_impulse(tq * dt)

func _fire_lunge() -> float:
	# From the moment it fills its chest the neck goes out at the prey, so it is already thrust
	# forward when the fire comes.
	if ai.get("mode", "") == "breathe":
		return 1.0
	return 1.0 if breath_t > 0.0 else 0.0

## The neck with the fire: thrust straight out at the prey, forward and a little down (never
## folded back over the body): the body's turn and the head's tilt do the aiming.
func _lunge_dip() -> float:
	return 0.8 * _fire_lunge()

## A bite landed (combat): the jaws snap shut on it, and what the teeth tore out hangs from
## them a while, or falls.
func bit(att: VoxelPart, vic: VoxelPart, res: Dictionary, dir: Vector3) -> void:
	jaw_t = minf(jaw_t, 0.14)
	# Teeth that met a shield, or armour that kept them out (nothing torn away): no venom in
	# him, no hold on him.
	if res.get("blocked", false) or (res.get("armor", false) and (res.get("removed", []) as Array).is_empty()):
		return
	# Venom: a scorpion's (or a manticore's) sting, a spider's or a snake's fangs.
	var kind: String = VENOMOUS.get(species, "")
	var c = vic.fighter
	if c and not vic.severed and kind != "" and ((kind == "sting" and att.part_name == "stinger") or (kind == "bite" and heads.has(att))):
		if on_venom.is_valid():
			on_venom.call(self, c, vic, vic.global_position)
	# A python that has its fangs in a man throws its coils round him.
	if species == "python" and heads.has(att) and c and c.alive and hug == null and coil_cool <= 0.0 and fn_of(["coil"]) > 0.3:
		_start_coil(c)
	# A crocodile's jaws close on the limb they got and it goes into its roll.
	if species == "crocodile" and heads.has(att) and c and c.alive and not (c is Beast) and hug == null and coil_cool <= 0.0 and not vic.severed and vic != c.torso and vic != c.head and part_ok(head, 0.2):
		var mp0 := mouth_point()
		hug = {"target": c, "part": vic, "t": 3.2, "tick": 0.45, "stagger0": stagger, "roll": true, "spin": 1.0 if rng.randf() < 0.5 else -1.0, "bites": 0,
			"bite_at": vic.to_local(mp0), "turned": 0.0}
		# Clamped, not hinged: the limb is locked in the jaws, so it turns as the head turns
		# (on a pin it only swivelled in the mouth while the crocodile spun round it).
		holds.append(_joint_at(head, vic, mp0, true))
		c.set_meta("rolled_by", self)   # (for his screen: how to fight it)
		c.fall(2.5, true)
		c.last_attacker = self
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
			if role == "head" and p == breath_part() and sp.breath != null:
				# The head that breathes fire is raised and tipped freely on its dipped neck, to
				# point the jaws at whatever the fire is to fall on.
				j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -NECK_DIP)
				j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, NECK_DIP)
			if role == "neck":
				# A neck bows far forward to bring the jaws down to the prey (the limit's sign is
				# the joint's own, so it is opened both ways: held to 0.3 one way, the hydra's
				# heads snapped at the air two yards over the man); it does not swing round
				# sideways into the body beside it (the cerberus's outer heads lolled in through
				# its middle one).
				j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -NECK_DIP)
				j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, NECK_DIP)
				j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.7)
				j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.7)
				j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.35)
				j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.35)
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
		var rest := PD.quat_of(p.parent_part).inverse() * PD.quat_of(p)
		# A neck modelled leaning far back over the spine is carried more upright.
		var up := rest * Vector3.UP
		var lean := maxf(0.0, atan2(-up.z, up.y) - 0.35) if role == "neck" else 0.0
		anim.append({"part": p, "role": role, "rest": rest, "i": anim.size(), "max_t": mt, "lean": lean})

## Drives every animated joint: breathing, looking at the prey, tails swaying and lashing,
## snakes' bodies travelling in waves, wings beating or flaring, trunks swinging, and the
## strikes on top. Each part moves on its own surviving voxels; a part that hangs or is off
## is left to the physics, and a damaged one moves less.
func _animate(dt: float, moving: bool, yaw_rate: float, to: Vector3, dist: float, cur: float) -> void:
	var breath := sin(time * 1.7 / sqrt(S) + slot)
	var track := 0.0
	if breath_mark is Vector3:
		to = Vector3((breath_mark as Vector3).x - torso.global_position.x, 0, (breath_mark as Vector3).z - torso.global_position.z).normalized()
		dist = 1.0
	if dist < INF:
		var dy := atan2(to.x, to.z) - cur
		track = clampf(atan2(sin(dy), cos(dy)), -0.9, 0.9)
	var wf := wing_fns()
	_breath_track(dt)
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
				off.y = track * 0.45 + sin(time * 0.9 + i * 1.7) * 0.08 + yaw_rate * 0.08 + clampf(breath_yaw * 0.8, -0.6, 0.6)
				off.x = -0.04 * breath + (0.25 if ai.mode == "aim" else 0.0) + float(a.lean) + _lunge_dip() + _breath_aim("neck")
			"head":
				off.y = track * (0.4 if p.parent_part == torso else 0.25) + sin(time * 0.7 + i * 2.1) * 0.06
				if p == breath_part():
					off.y += clampf(breath_yaw * 0.6, -0.5, 0.5)   # the jaws turned onto the mark
				off.x = 0.03 * breath + (0.35 if ai.mode == "aim" or ai.mode == "charge" and sp.ai == "charger" else 0.0)
				if sp.ai == "path" and float(ai.get("charge_t", 0.0)) > 0.0:
					off.x += 0.4   # head down, tusks levelled at him
				elif _stomping():
					off.x -= 0.35 if float(ai.stomp) > STOMP_DOWN else -0.2   # the head thrown up, then down
				off.x -= 0.45 * _lunge_dip()
				if p == breath_part():
					off.x += _breath_aim("head")   # the jaws turned onto the mark
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
				off.x = sin(time * 0.8 + i) * 0.22
				off.y = sin(time * 0.55 + i) * 0.25
				if _stomping():
					off.x = -1.1 if float(ai.stomp) > STOMP_DOWN else 0.6   # raised high, trumpeting; then flung down
					off.y *= 0.3
				elif float(ai.get("charge_t", 0.0)) > 0.0:
					off.x = -0.8   # curled up out of the way of the tusks
					off.y *= 0.2
			"arm":
				off.y = -track * 0.3 * signf(p.pa.x)
				off.x = -0.25 if dist < 2.5 * S else 0.0
			"claw":
				off.y = signf(p.pa.x) * (0.15 + 0.15 * sin(time * 3.0 + i))
		var lim: float = ROLE_LIM[role]
		if role == "tail" and by_name.has("stinger"):
			lim = 1.3
		var st: float = strikes.get(p, 0.0)
		if role == "neck" or role == "head":
			# Struck with, the neck is let fall onto the prey rather than held up over it.
			var lunging := _fire_lunge() >= 1.0
			_hold_up(p, a.max_t * (0.25 if st > 0.0 and float(wind.get(p, 0.0)) <= 0.0 else 1.0), dt)
			if lunging:
				# Fire poured out with the neck thrust down and forward over the prey, the head level.
				lim = NECK_DIP
		var wn: float = ROLE_WN[role]
		if (role == "neck" or role == "head") and _fire_lunge() >= 1.0:
			wn *= 1.6   # the thrust is quick and hard, not a slow sway forward
		if st > 0.0:
			off += _strike_pose(p, role, st, track, dist)
			if role == "neck" or role == "head":
				lim = NECK_DIP if role == "neck" else 1.2
		if p.flinch_t > 0.0:
			off.x -= p.flinch_t * 0.9
		off = off.clamp(Vector3(-lim, -lim, -lim), Vector3(lim, lim, lim)) * (0.3 + 0.7 * p.function())
		if role == "tail" and by_name.has("stinger"):
			# The arched tail carries the whole chain and the sting: held like a leg, not swung.
			motor_rel(p, p.parent_part, Quaternion.from_euler(off) * a.rest, 14.0, a.max_t, dt, 0.5)
		elif p == breath_part() and _fire_lunge() >= 1.0 and _breath_mark_now() is Vector3:
			_aim_jaws(p, a.max_t, dt)   # breathing, the head is aimed in the world, not posed on the neck
		else:
			pd_relative(p, p.parent_part, Quaternion.from_euler(off) * a.rest, wn, 0.9, a.max_t, dt, 1.0, 0.5)

## A neck holds up its head against gravity: the drive alone only knows the neck's own weight,
## and a long neck under a heavy head sank back flat along the spine.
func _hold_up(p: VoxelPart, max_t: float, dt: float) -> void:
	var jp: Vector3 = p.parent_part.global_transform * p.pa
	var tq := Vector3.ZERO
	var stack := [p]
	while not stack.is_empty():
		var c: VoxelPart = stack.pop_back()
		if c.severed:
			continue
		tq += (c.global_position - jp).cross(Vector3(0.0, c.mass * gravity, 0.0))
		stack.append_array(c.child_parts)
	tq = PD.clamp_len(tq * (0.3 + 0.7 * p.function()), max_t)
	p.apply_torque_impulse(tq * dt)
	p.parent_part.apply_torque_impulse(-tq * dt)

func _strike_pose(p: VoxelPart, role: String, st: float, track: float, _dist: float) -> Vector3:
	# The wind-up: drawn back the opposite way to the blow that is coming.
	if float(wind.get(p, 0.0)) > 0.0:
		match role:
			"neck":
				return Vector3(-0.4, track * 0.3, 0)                                    # the neck rears up
			"head":
				if species == "boar" or species == "elephant" or species == "mammoth":
					return Vector3(-0.15, -signf(float(ai.get("sweep", 1.0))) * 0.45, 0)   # the tusks swung the other way
				if species == "bull" or species == "goat" or species == "rhino":
					return Vector3(0.35, 0, 0)                                           # the horns lowered
				return Vector3(-0.4, track * 0.3, 0)                                    # the jaws drawn back
			"tail":
				return Vector3(-0.3, track * 0.3, 0)                                    # the sting cocked higher
			"claw":
				return Vector3(0, signf(p.pa.x) * 0.35, 0)                              # the pincer opened wide
			"arm":
				return Vector3(0.35, 0, 0)
		return Vector3.ZERO
	match role:
		"neck":
			# Dip the neck as far as it takes to bring the head down to the prey.
			var drop := 0.0
			if target and is_instance_valid(target):
				var hd: VoxelPart = p.child_parts[0] if not p.child_parts.is_empty() else p
				drop = clampf((hd.global_position.y - target.torso.global_position.y) / maxf(0.5, p.half_ext.y * 2.0 + 0.3), 0.0, NECK_DIP - 0.3)
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

## A strike: `wind_s` seconds of wind-up (by WINDUP when < 0; 0 when something else, a crouch
## or a rearing, already showed it coming), then `t_` seconds of the blow itself. `imp` is
## [body, impulse] given when the blow goes.
func _strike(p: VoxelPart, t_: float, cool: float, imp: Array = [], wind_s := -1.0) -> void:
	var w: float = wind_s
	if w < 0.0:
		w = float(WINDUP.get("leg" if p.def.get("leg", false) else _role_of(p), 0.25))
	strikes[p] = t_ + w
	wind[p] = w
	p.set_meta("stung", false)
	p.set_meta("landed", false)
	p.set_meta("strike_lead", true)
	# Keener it comes again sooner (a quarter sooner at the top of the scale), slacker it waits
	# longer (half again at the bottom); as it is everywhere but training.
	strike_cool[p] = cool * (1.0 + (0.7 - clampf(skill, 0.0, 1.0)) * 0.85)
	if not imp.is_empty():
		pending[p] = imp
	# A head on a neck strikes with the neck: it dips and drives forward with it.
	var nk := p.parent_part
	if nk and not nk.severed and String(nk.part_name).begins_with("neck"):
		strikes[nk] = t_ + w
		wind[nk] = w
		nk.set_meta("strike_lead", false)
	if w <= 0.0:
		_strike_go(p)

## The wind-up is over: the blow goes.
func _strike_go(p: VoxelPart) -> void:
	wind.erase(p)
	if p.jaw_pivot:
		jaw_t = JAW_T
	if pending.has(p):
		var imp: Array = pending[p]
		pending.erase(p)
		if is_instance_valid(imp[0]) and not imp[0].severed:
			imp[0].apply_central_impulse(imp[1])
	# A paw or a foot only hurts while it swings.
	if p.def.get("leg", false):
		var lo := lower_of(p)
		if lo:
			lo.def["bite"] = true
			lo.def["claw"] = SWIPERS.has(species) and species != "gorilla"
			lo.def["fist"] = species == "gorilla"   # a punch, not a rake
		# The ostrich kicks with a hop: both feet off the sand for the blow.
		if species == "ostrich" and ground_ok:
			var m := live_mass()
			var to := Vector3.ZERO
			if target and is_instance_valid(target):
				to = target.torso.global_position - torso.global_position
				to.y = 0.0
				to = to.normalized()
			torso.apply_central_impulse(Vector3(0, 2.4, 0) * m + to * 1.4 * m)
	if on_strike.is_valid():
		on_strike.call(self, p)

func _role_of(p: VoxelPart) -> String:
	for a in anim:
		if a.part == p:
			return a.role
	return "head" if p == head or p.def.get("head", false) else ""

## The sting's tip is a needle: driven home it goes in point first, as hard as the scorpion's
## strike, however glancing the contact of its little collider. Only a sting that touched him
## (the physics' contact of the stinger on one of his parts) is a blow, once per sting.
func _sting_reach() -> void:
	if not by_name.has("stinger") or not strikes.has(by_name.stinger) or target == null or not is_instance_valid(target) or not target.alive or Combat.current == null:
		return
	var stg: VoxelPart = by_name.stinger
	if stg.get_meta("stung", false) or float(wind.get(stg, 0.0)) > 0.0:
		return
	# The sting is aimed all the way in, at his trunk as it is now (the blow's push was aimed
	# when the tail cocked, and he had moved by the time it came down): the tail's muscles steer
	# the tip onto him, as fast as a scorpion strikes and no faster.
	var aim: Vector3 = target.torso.global_position + Vector3(0, 0.1, 0)
	var to_aim: Vector3 = aim - stg.global_position
	if to_aim.length() < 1.6 * maxf(S, 0.6):
		var want: Vector3 = to_aim.normalized() * 5.0 * maxf(S, 0.6)
		stg.apply_central_impulse(PD.clamp_len((want - stg.linear_velocity) * stg.mass * 0.35, 40.0 * S * stg.mass))
	var q: VoxelPart = Combat.current.touch_by(stg, target, 0.05)
	if q == null or q.severed:
		return
	stg.set_meta("stung", true)
	var tip: Vector3 = stg.global_transform * Vector3(0, -stg.half_ext.y, stg.half_ext.z)
	var dir: Vector3 = (q.global_position - tip).normalized()
	var J := bite_power * 0.8
	var was: bool = target.alive
	var res: Dictionary = target.apply_hit(q, {"impulse": J, "type": "point", "hardness": 0.9, "sharpness": 1.0, "point": tip, "dir": dir, "axis": dir})
	target.last_attacker = self
	Combat.current.hit.emit({"kind": "hit", "att_part": stg, "p": tip, "dir": dir, "J": J, "type": "point", "char": target, "part": q, "attacker": self, "res": res, "killed": was and not target.alive, "bite": true})
	bit(stg, q, res, dir)

func _tick_strikes(dt: float) -> void:
	_sting_reach()
	if species == "gorilla":
		_ape_drive()
	_head_drive()
	for p in strike_cool.keys():
		strike_cool[p] -= dt
	for p in strikes.keys():
		strikes[p] -= dt
		if wind.has(p) and is_instance_valid(p):
			wind[p] -= dt
			if wind[p] <= 0.0:
				if p.get_meta("strike_lead", false):
					_strike_go(p)
				else:
					wind.erase(p)   # a neck or a tail segment carried along with the strike
		if strikes[p] <= 0.0 or not is_instance_valid(p) or p.severed:
			strikes.erase(p)
			wind.erase(p)
			pending.erase(p)
			if is_instance_valid(p) and p.def.get("leg", false):
				p.set_meta("ape", "")
				var lo := lower_of(p)
				if lo:
					lo.def["bite"] = false
					lo.def["claw"] = false
					lo.set_meta("power", 1.0)

## The ape's arms at work in a blow, the way a man's arm drives his hand: in the wind-up the
## fist is drawn back to the shoulder, then the arm drives it at the man (straight, swung round
## from the side, or brought down from above) at the blow's speed, as hard as its pull allows,
## the body taking the push back. Once the fist is on him the drive stops: the blow has landed.
func _ape_drive() -> void:
	if target == null or not is_instance_valid(target) or not target.get("torso"):
		return
	var tv: Vector3 = torso.linear_velocity
	for arm in strikes.keys():
		if not is_instance_valid(arm) or String(arm.get_meta("ape", "")) == "":
			continue
		var lo := lower_of(arm)
		if lo == null or lo.severed or lo.get_meta("landed", false):
			continue
		var kind := String(arm.get_meta("ape"))
		var b: Dictionary = APE_BLOWS[kind]
		var aim: Vector3 = target.head.global_position if target.get("head") and not target.head.severed else target.torso.global_position
		var to: Vector3 = aim - torso.global_position
		to.y = 0.0
		to = to.normalized()
		var side := Vector3(-to.z, 0, to.x) * signf(arm.pa.x)
		var want: Vector3
		if float(wind.get(arm, 0.0)) > 0.0:
			# Drawn back: the fist to the shoulder (a hook out to the side, a slam up over the head).
			var sh: Vector3 = arm.global_position
			var back := sh - to * 0.35 * S + Vector3.UP * 0.25 * S
			if kind == "hook":
				back += side * 0.4 * S
			elif kind == "slam":
				back = sh + Vector3.UP * 0.9 * S - to * 0.15 * S
			want = (back - lo.global_position) * 6.0
		else:
			var dir: Vector3 = (aim - lo.global_position).normalized()
			match kind:
				"hook":
					dir = (dir + side * 0.45).normalized()
				"slam":
					dir = (dir + Vector3(0, -0.7, 0)).normalized()
			want = dir * float(b.speed) * sqrt(S)
			if Combat.current and Combat.current.touch_by(lo, target, 0.02) != null:
				lo.set_meta("landed", true)
				continue
		var dv: Vector3 = want - (lo.linear_velocity - tv)
		var acc := dv / maxf(0.02, get_physics_process_delta_time() * 4.0)
		acc = acc.limit_length(APE_PULL * sqrt(S))
		var f := acc * lo.mass
		lo.apply_central_force(f)
		torso.apply_central_force(-f * 0.5)

## A head on a long neck (a dragon's, an ostrich's) strikes the way the ape's arm drives its
## fist: drawn back and up on the neck in the wind-up, then driven down at the man at the
## strike's speed, the body taking the push back, until the jaws are on him. A kick of an
## impulse alone was taken back by the neck's own spring before it got there.
const HEAD_SPEED := 5.5
const HEAD_PULL := 120.0
func _head_drive() -> void:
	if sp.get("multiHead", false) or head.severed or head.parent_part == torso or not strikes.has(head):
		return
	if target == null or not is_instance_valid(target) or not target.get("torso") or head.get_meta("landed", false):
		return
	# At his head and shoulders, high, where a long neck reaches down to (its root will not let
	# it fold down to his belly).
	var aim: Vector3 = target.head.global_position if target.get("head") and not target.head.severed else target.torso.global_position
	var tv: Vector3 = torso.linear_velocity
	var want: Vector3
	if float(wind.get(head, 0.0)) > 0.0:
		var to: Vector3 = aim - torso.global_position
		to.y = 0.0
		to = to.normalized()
		want = (head.parent_part.global_position + Vector3.UP * 0.3 * S - to * 0.2 * S - head.global_position) * 5.0
	else:
		want = (aim - head.global_position).normalized() * HEAD_SPEED * sqrt(S)
		if Combat.current and Combat.current.touch_by(head, target, 0.03) != null:
			head.set_meta("landed", true)
			return
	var acc := ((want - (head.linear_velocity - tv)) / maxf(0.02, get_physics_process_delta_time() * 4.0)).limit_length(HEAD_PULL * sqrt(S))
	var f := acc * head.mass
	head.apply_central_force(f)
	# The neck goes with it, its end most, the body taking the push back.
	var nk: VoxelPart = head.parent_part
	var fn := acc * nk.mass * 0.6
	nk.apply_force(fn, head.global_position - nk.global_position)
	torso.apply_central_force(-(f + fn) * 0.5)

func _ready_to_strike(p: VoxelPart) -> bool:
	return strike_cool.get(p, 0.0) <= 0.0 and not strikes.has(p)

const SWIPERS := ["lion", "tiger", "bear", "griffin", "cerberus", "chimera", "manticore", "ostrich", "gorilla"]

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
				_strike(h, 0.5, 1.0 + rng.randf() * 1.2, [h, ((tp - h.global_position).normalized() * 3.5 + Vector3(0, 0.6 if h.global_position.y < tp.y else 0.0, 0)) * h.mass])
				# The body comes on behind the striking head, so the next heads reach too (a hydra
				# backing off after its lunge snapped at the air a yard short).
				if dist > 0.8 * S and not strikes.has(torso):
					strikes[torso] = 0.5
					torso.apply_central_impulse(to * live_mass() * 1.0)
	# A head on a long neck (a dragon's, an ostrich's, a rearing snake's) strikes down at the
	# prey on its own when it is in reach of the neck, without the whole body lunging.
	if not sp.get("multiHead", false) and head.parent_part != torso and part_ok(head, 0.2) and _ready_to_strike(head):
		var nk: VoxelPart = head.parent_part
		var hp := head.global_position
		var flat := Vector2(hp.x - tp.x, hp.z - tp.z).length()
		if flat < (nk.half_ext.y * 2.0 + head.half_ext.z * 2.0) * 1.1 and part_ok(nk, 0.2):
			_strike(head, 0.6, 1.3 + rng.randf() * 0.8, [head, (tp - hp).normalized() * 3.2 * head.mass])
	# The sting: the tail arches forward over the back and the stinger drives at the prey.
	if by_name.has("stinger"):
		var stg: VoxelPart = by_name.stinger
		var chain_ok := fn_of(["tail"]) > 0.3
		if part_ok(stg, 0.2) and chain_ok and _ready_to_strike(stg) and dist < reach * 1.3 and facing > 0.3:
			_strike(stg, 0.7, 2.2 + rng.randf(), [stg, (tp + Vector3(0, 0.3, 0) - stg.global_position).normalized() * maxf(30.0 * S, 4.0 * stg.mass)])
			for n in ["tail", "tail2", "tail3"]:
				if by_name.has(n) and part_ok(by_name[n], 0.1):
					strikes[by_name[n]] = strikes[stg]
					wind[by_name[n]] = wind[stg]
					by_name[n].set_meta("strike_lead", false)
	# Pincers snap at whatever is in front of them.
	for n in ["clawL", "clawR"]:
		if by_name.has(n):
			var c: VoxelPart = by_name[n]
			if part_ok(c, 0.2) and _ready_to_strike(c) and c.global_position.distance_to(tp) < 0.9 * S:
				_strike(c, 0.25, 0.9 + rng.randf() * 0.6, [c, (tp - c.global_position).normalized() * maxf(18.0 * S, 3.5 * c.mass)])
	if species == "gorilla":
		_ape_blows(dt, t, to, dist, facing)
	# A forepaw swipe (or the ostrich's kick): a working front leg lashes out.
	if SWIPERS.has(species) and species != "gorilla" and dist < reach * 1.1 and facing > 0.5:
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
			var lo := lower_of(best)
			_strike(best, 0.35, 1.6 + rng.randf(), [lo, (tp - lo.global_position).normalized() * maxf(20.0 * S, 4.0 * lo.mass) * best_f] if lo else [])
	# Tusks sweep sideways, horns toss upward, both only with something left of them.
	if (species == "boar" or species == "elephant" or species == "mammoth") and horn_fn() > 0.2 and part_ok(head) and _ready_to_strike(head) and dist < reach * 1.2 and facing > 0.4:
		ai.sweep = -1.0 if rng.randf() < 0.5 else 1.0
		_strike(head, 0.5, 2.0 + rng.randf())
	if (species == "bull" or species == "rhino" or species == "goat") and horn_fn() > 0.2 and part_ok(head) and _ready_to_strike(head) and dist < reach and facing > 0.6:
		# The toss is the head's own swing (see _strike_pose); only a small lift on top of it, so a
		# man is thrown about like by a bull, not launched into the air.
		_strike(head, 0.25 if species == "rhino" else 0.35, 1.8 + rng.randf(), [head, Vector3(0, 4.0 * S * horn_fn(), 0)] if species != "rhino" else [])

## Whether any part of this body is in contact with `c` (Combat's touches): every hold, squeeze,
## roll and trample is real only while it is.
func _touching(c, within := 0.25) -> bool:
	return Combat.current != null and Combat.current.touching(self, c, within)

## The force (N) this body is bearing on `c` through its contacts, read off the physics: the
## contact impulse of the last step over the step.
func _touch_force(c) -> float:
	if Combat.current == null:
		return 0.0
	return Combat.current.touch_impulse(self, c, 0.3) / maxf(0.001, get_physics_process_delta_time())

## A hold made physical: a joint from this part to the other's at the point of contact, so the
## limb stays in the jaws and the man in the arms as long as the hold lasts (freed with it).
func _hold(a: VoxelPart, b: VoxelPart, at: Vector3) -> void:
	if a == null or b == null or a.severed or b.severed:
		return
	holds.append(_joint_at(a, b, at, false))

func _free_holds() -> void:
	for j in holds:
		if j and is_instance_valid(j):
			j.queue_free()
	holds.clear()
	for n in ["legFLLo", "legFRLo"]:
		if by_name.has(n):
			by_name[n].set_meta("gripped", false)

## The ape's blows, each a swing of its own and each as hard as the swing (APE_BLOWS: the wind-up,
## the blow, the rest after, how fast the arm drives the fist (m/s, for an ape of scale 1), and
## how hard the fist may land for it): a jab straight from the shoulder, a hook swung wide and
## across, and both fists raised and slammed down together. Out of reach it beats its chest and
## roars. The fist is driven like a man's hand (_ape_drive): the arm's pull, not a kick from
## nowhere, so it lands only where it gets to and as hard as it is going when it does.
const APE_BLOWS := {
	"jab": {"wind": 0.2, "t": 0.3, "cool": 1.1, "speed": 7.5, "power": 0.9},
	"hook": {"wind": 0.3, "t": 0.35, "cool": 1.6, "speed": 8.0, "power": 1.3},
	"slam": {"wind": 0.5, "t": 0.4, "cool": 3.2, "speed": 9.0, "power": 1.8},
}
const APE_PULL := 160.0   # the most the arm accelerates its fist, m/s² (a man's arm is near 100)

func _ape_blows(dt: float, t, to: Vector3, dist: float, facing: float) -> void:
	if float(ai.get("beat", 0.0)) > 0.0:
		ai.beat = float(ai.beat) - dt
		# A blow of the drum each time a fist comes in (the arms swap at the same count).
		var k := int(maxf(0.0, float(ai.beat)) * 9.0)
		if k != int(ai.get("beat_k", -1)) and ai.beat > 0.0:
			ai.beat_k = k
			if on_thump.is_valid():
				on_thump.call(self)
	var arms := []
	for n in ["legFL", "legFR"]:
		if by_name.has(n) and not leg_gone(by_name[n]) and fn_of([n]) > 0.35 and _ready_to_strike(by_name[n]):
			arms.append(by_name[n])
	var reach: float = torso.half_ext.z + 1.6 * S
	if arms.is_empty() or float(ai.get("rear", 0.0)) > 0.0:
		return
	if dist > reach * 1.6:
		# Out of reach: now and then it rears a little and drums its chest.
		if float(ai.get("beat", 0.0)) <= 0.0 and float(ai.get("beat_cool", 0.0)) <= 0.0 and arms.size() == 2 and rng.randf() < dt * 0.35:
			ai.beat = 1.3
			ai.beat_cool = 7.0 + rng.randf() * 5.0
			if on_roar.is_valid():
				on_roar.call(self)
		ai.beat_cool = float(ai.get("beat_cool", 0.0)) - dt
		return
	if float(ai.get("beat", 0.0)) > 0.0:
		ai.beat = 0.0   # a man in reach ends the display
	if dist > reach * 1.15 or facing < 0.5 or rng.randf() > dt * 2.2:
		return
	# Close in, a fist already on him and the hug ready, it grapples instead (control): the
	# blows are for the rest.
	if dist < 1.3 * S and ai.bite_cool <= 0.0 and front_fn() > 0.35 and part_ok(head, 0.15) and not _paws_on(t, 0.05).is_empty():
		return
	var kind := "jab"
	var r := rng.randf()
	if arms.size() == 2 and r < 0.25 and dist < reach:
		kind = "slam"
	elif r < 0.6:
		kind = "hook"
	var b: Dictionary = APE_BLOWS[kind]
	var swing := [arms[rng.randi() % arms.size()]] if kind != "slam" else arms
	for arm in swing:
		var lo := lower_of(arm)
		if lo == null:
			continue
		arm.set_meta("ape", kind)
		lo.set_meta("power", float(b.power))
		lo.set_meta("landed", false)
		_strike(arm, float(b.t), float(b.cool) + rng.randf() * 0.5, [], float(b.wind))
	if kind == "slam":
		# The body comes down behind the fists.
		torso.apply_central_impulse((to * 0.6 + Vector3(0, -0.3, 0)) * live_mass() * 0.8)

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
