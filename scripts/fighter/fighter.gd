class_name Fighter
extends Node3D
## A voxel gladiator: ten physical body parts on ball joints, held up and moved by forces the
## way character.js does it (a support spring on the torso, an upright balance torque, legs that
## plant their feet and step with a two-bone solver, hands that follow the mouse on a pane in
## front of the body with a weapon welded in line with the forearm), wounded voxel by voxel.

const V := 0.055
const LEG := 16 * V
const TORSO_H := 11 * V
const TORSO_Y := LEG + TORSO_H / 2.0
const HAND_POINT := Vector3(0, -3.3 * V, 0)
const UPPER_LEN := 7 * V
const FORE_LEN := 6.8 * V
const SHOULDER_R := Vector3(-5.5 * V, 0.2725, 0)
const SHOULDER_L := Vector3(5.5 * V, 0.2725, 0)
const ARM_REACH := 0.68
const HIT_SCALE := 0.8
const BLEED_RATE := 0.6
const JAB_TIME := 0.32
const LEG_MASS := 0.5
## How hard the body is pulled back over its planted feet (14 in the web game, whose legs are
## stiff joint motors; torque-driven legs lag their targets, so less here).
const ANCHOR_K := 4.0
const LEG_WN := 80.0
## How much of the leg drive pushes back on the torso (Rapier's joint motors are solved with the
## joints; a torque drive's full reaction fights the balance when the body lies on its side).
const LEG_REACT := 0.35
const GRAVITY := 9.81
const UP := Vector3.UP
const GRIP_Q := Quaternion(Vector3(1, 0, 0), PI)
const SKINS := [0xe0b48c, 0xc68e5e, 0x9a6440, 0x6e4529, 0xf1c9a5]

signal died(fighter: Fighter, cause: String)
signal hit_taken(fighter: Fighter, info: Dictionary)

var display_name := "Gladiator"
var slot := 0
var team := 0
var team_color := Color(0.627, 0.125, 0.125)
var skin := Color(0.878, 0.706, 0.549)
var is_bot := false
var kind := "fighter"
var mods := {"bodyScale": 1.0, "strength": 1.0, "speed": 1.0, "toughness": 1.0, "bleed": 1.0, "accel": 1.0, "unstoppable": false, "drunk": 0.0}
var S := 1.0
var MS := 1.0
var boss := false

var yaw := 0.0
var state := "stand"           # stand | down | rising | dead
var alive: bool:
	get:
		return state != "dead"
var down_timer := 0.0
var rise_t := 1.0
var rise_q0 = null
var tilt_t := 0.0
var stood_at := -99.0
var blood := 100.0
var stamina := 100.0
var stagger := 0.0
var concussion := 0.0
var pain := 0.0
var time := 0.0
var gait_phase := 0.0
var kick_timer := 0.0
var push_t := 0.0
var kills := 0
var last_attacker: Node = null
var injury := 0.0
var gravity := 9.81              # the Emperor may decree otherwise
# Wrestling and showing off (social.gd).
var holding = null              # {side, target (entity), part, joint, t, extra, limb}
var grabbed_by: Node = null
var pinned_arm := ""
var thrown_t := 0.0
var thrown_by: Node = null
var shove_cool := 0.0
var shove_t := 0.0
var taunt_t := 0.0
var taunt_pose := 0.0
var limp := false
var played_dead := 0.0
var carrying := 0.0
var emote_t := 0.0
var emote_kind := -1
# What pots, nets and arrows do to a man (throwables.gd).
var slow_timer := 0.0
var slow_factor := 1.0
var net_timer := 0.0
var bee_timer := 0.0
var wine_timer := 0.0
var held_item = null             # {"type", "id", "node"}: a pot readied in the free hand
var net_mesh: MeshInstance3D = null

var parts: Array = []
var by_name := {}
var torso: VoxelPart
var head: VoxelPart
var arm := {}
var weapons := {"R": null, "L": null}
var weapon_joints := {"R": null, "L": null}
var two_handed := false
var feet := {"L": null, "R": null}
var v_smooth := Vector3.ZERO
var hand_lead := {"R": null, "L": null}
var lead_vel := {"R": Vector3.ZERO, "L": Vector3.ZERO}
var prev_target := {"R": Vector3.ZERO, "L": Vector3.ZERO}
var target_vel := {"R": Vector3.ZERO, "L": Vector3.ZERO}
var aim_q := {"R": null, "L": null}
var hand_input := {"R": {"x": 0.1, "y": 0.1}, "L": {"x": -0.35, "y": 0.1}}
var handling := {"R": 1.0, "L": 1.0}
var jab_t := {"R": 0.0, "L": 0.0}
var low_hand := 0.0
var shoulder := {"R": SHOULDER_R, "L": SHOULDER_L}
var hand_point := HAND_POINT
var torso_y := TORSO_Y
var arm_reach := ARM_REACH
var gaze = null                 # a world point the head turns to (bots)
var space: PhysicsDirectSpaceState3D

# ---------- Building ----------

func build(spawn: Vector3, yaw_: float, loadout: Dictionary, opts := {}) -> void:
	display_name = opts.get("name", display_name)
	slot = int(opts.get("slot", 0))
	team = int(opts.get("team", slot))
	is_bot = bool(opts.get("bot", false))
	boss = bool(opts.get("boss", false))
	if opts.has("team_color"):
		team_color = opts.team_color
	skin = Color.hex(int(opts.get("skin", SKINS[slot % SKINS.size()])) << 8 | 0xff)
	for k in opts.get("mods", {}):
		mods[k] = opts.mods[k]
	S = float(mods.bodyScale)
	MS = pow(S, 2.5)
	hand_point = HAND_POINT * S
	shoulder = {"R": SHOULDER_R * S, "L": SHOULDER_L * S}
	arm_reach = ARM_REACH * S
	torso_y = TORSO_Y * S
	yaw = yaw_
	name = display_name.replace(" ", "_")
	var yaw_q := Quaternion(UP, yaw)
	var sk_lin := skin.srgb_to_linear()
	var tm_lin := team_color.srgb_to_linear()
	for d in Data.body_parts:
		var voxels := []
		for v in d.voxels:
			var c: Color
			match int(v[3]):
				1: c = (sk_lin * float(v[4])).linear_to_srgb()
				2: c = (tm_lin * float(v[4])).linear_to_srgb()
				_: c = Color.hex(int(v[4]) << 8 | 0xff)
			c.a = 1.0
			voxels.append([v[0], v[1], v[2], c, v[5]])
		var p := VoxelPart.new()
		var m: float = float(d.mass) * MS * (LEG_MASS if d.leg else 1.0)
		p.setup(self, d, voxels, S, m)
		p.linear_damp = 0.1
		p.angular_damp = 1.5 if d.name == "torso" else (3.0 if d.name == "head" else 0.6)
		p.collision_layer = VoxelPart.LAYER_BODY
		p.collision_mask = VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS | (0 if d.leg else VoxelPart.LAYER_WORLD)
		add_child(p)
		var pos := Vector3(float(d.pos[0]), float(d.pos[1]), float(d.pos[2])) * S
		p.global_transform = Transform3D(Basis(yaw_q), spawn + yaw_q * pos)
		parts.append(p)
		by_name[d.name] = p
		if d.parent != null:
			p.parent_part = by_name[d.parent]
			p.parent_part.child_parts.append(p)
	torso = by_name.torso
	head = by_name.head
	arm = {"R": {"upper": by_name.upperArmR, "fore": by_name.forearmR}, "L": {"upper": by_name.upperArmL, "fore": by_name.forearmL}}
	for a in parts:
		for b in parts:
			if a != b:
				a.add_collision_exception_with(b)
	for p in parts:
		if p.parent_part:
			_make_pin(p)
	for p in parts:
		for id in loadout.get("armor", []):
			_add_armor(p, id)
	var main = loadout.get("main")
	var off = loadout.get("off")
	if main is String:
		main = Data.preset(main)
	if off is String:
		off = Data.preset(off)
	if main is Dictionary and not main.is_empty():
		equip("R", main)
		if main.get("twoHanded", false):
			two_handed = true
			_attach_off_hand(weapons.R)
	if off is Dictionary and not off.is_empty() and not two_handed:
		equip("L", off)

func _make_pin(p: VoxelPart) -> void:
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = p.parent_part.global_transform * p.pa
	j.node_a = p.parent_part.get_path()
	j.node_b = p.get_path()
	p.joint = j

func _add_armor(p: VoxelPart, id: String) -> void:
	var a: Dictionary = Data.armor.get(id, {})
	var cells: Array = a.get("parts", {}).get(p.part_name, [])
	if cells.is_empty():
		return
	var col := Weapon.voxel_color(a.get("mat", "iron"), "blunt")
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * V * S * 0.98
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.6
	mat.roughness = 0.35
	mesh.material = mat
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.mesh = mesh
	mmesh.instance_count = cells.size()
	for i in cells.size():
		var c: Array = cells[i]
		mmesh.set_instance_transform(i, Transform3D(Basis(), Vector3(c[0] - (p.dims.x - 1) * 0.5, c[1] - (p.dims.y - 1) * 0.5, c[2] - (p.dims.z - 1) * 0.5) * V * S))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mmesh
	inst.name = "Armor_" + id
	p.add_child(inst)
	p.set_meta("armor", p.get_meta("armor", []) + [{"id": id, "mat": a.get("mat", "iron"), "cells": cells, "alive": cells.size(), "node": inst}])

func hand_world(side: String) -> Vector3:
	return arm[side].fore.global_transform * hand_point

func equip(side: String, design: Dictionary) -> void:
	var fore: VoxelPart = arm[side].fore
	if fore.missing:
		return
	var w := Weapon.new()
	w.setup(design, S * float(mods.get("weaponScale", 1.0)))
	get_parent().add_child(w)
	var rot: Quaternion
	if w.is_shield:
		rot = Quaternion(UP, yaw)
	else:
		rot = PD.quat_of(fore) * GRIP_Q
	var hand := hand_world(side)
	w.global_transform = Transform3D(Basis(rot), hand - rot * w.grip_main)
	w.build_chain()
	_exempt(w)
	w.set_held_by(self)
	weapons[side] = w
	weapon_joints[side] = _joint_at(fore, w, hand, not w.is_shield)
	w.welded = not w.is_shield

## A weapon in your hands does not collide with your own body or your other weapon.
func _exempt(w: Weapon) -> void:
	for b in w.bodies():
		for p in parts:
			b.add_collision_exception_with(p)
		for o in weapons.values():
			if o and o != w:
				for ob in o.bodies():
					b.add_collision_exception_with(ob)

func _joint_at(a: RigidBody3D, b: RigidBody3D, at: Vector3, fixed: bool) -> Joint3D:
	var j: Joint3D
	if fixed:
		j = Generic6DOFJoint3D.new()
	else:
		j = PinJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = a.get_path()
	j.node_b = b.get_path()
	return j

func _attach_off_hand(w: Weapon) -> void:
	if not w:
		return
	var fore: VoxelPart = arm.L.fore
	var at := w.global_transform * w.grip_off
	fore.global_position += at - hand_world("L")
	weapon_joints.L = _joint_at(fore, w, at, false)

func release(side: String) -> Weapon:
	var w: Weapon = weapons[side]
	if not w:
		return null
	if weapon_joints[side]:
		weapon_joints[side].queue_free()
		weapon_joints[side] = null
	if side == "R" and two_handed and weapon_joints.L:
		weapon_joints.L.queue_free()
		weapon_joints.L = null
	two_handed = false if side == "R" else two_handed
	weapons[side] = null
	w.holder = null
	w.welded = false
	# Loose: for a moment more it ignores the body that let it go, then it hits anyone.
	w.last_side = side
	w.own_by = self
	w.own_t = 0.35
	if Combat.current and not Combat.current.loose_weapons.has(w):
		Combat.current.loose_weapons.append(w)
	return w

## Slowed for `seconds` to `factor` of the pace (ice, honey, poison); a weaker slow does not
## replace a stronger one.
func slow(seconds: float, factor: float) -> void:
	if slow_timer > 0.0 and slow_factor < factor:
		slow_timer = maxf(slow_timer, seconds * 0.5)
		return
	slow_timer = seconds
	slow_factor = factor

## Caught in a net (bola, weighted net): a quarter of the pace until it is off.
func set_net(on: bool, seconds := 4.0) -> void:
	net_timer = seconds if on else 0.0
	if on and net_mesh == null and DisplayServer.get_name() != "headless":
		net_mesh = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(12, 14, 8) * V * S
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.54, 0.42, 0.23, 0.6)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.material = m
		net_mesh.mesh = bm
		torso.add_child(net_mesh)
	if net_mesh:
		net_mesh.visible = on

## G next to a weapon lying loose: the nearest free hand closes on its grip.
func grab_nearest(list: Array) -> Weapon:
	if not alive:
		return null
	for side in ["R", "L"]:
		if weapons[side] or arm[side].fore.severed or arm[side].fore.hanging or (side == "L" and two_handed) or (holding != null and holding.side == side):
			continue
		var hand := hand_world(side)
		var best: Weapon = null
		var bd := 0.75
		for w in list:
			if not is_instance_valid(w) or w.holder != null or w.alive_count() == 0:
				continue
			var g: Vector3 = w.grip_world()
			# Reaching down counts for little: a weapon on the sand by your feet is in reach.
			var dx := Vector2(g.x - hand.x, g.z - hand.z).length()
			var dy := hand.y - g.y
			if dy < -0.5 or dy > 1.7 * S:
				continue
			var d := dx + maxf(0.0, dy - 0.4) * 0.15
			if d < bd:
				bd = d
				best = w
		if best and pick_up(side, best):
			return best
	return null

## Takes `w` into the hand on `side`: the grip moved into the palm and welded there.
func pick_up(side: String, w: Weapon) -> bool:
	var fore: VoxelPart = arm[side].fore
	if weapons[side] or fore.severed or fore.missing:
		return false
	if w.own_by and is_instance_valid(w.own_by) and w.own_by != self:
		w.forget_owner()
	var rot: Quaternion = Quaternion(UP, yaw) if w.is_shield else PD.quat_of(fore) * GRIP_Q
	var hand := hand_world(side)
	w.global_transform = Transform3D(Basis(rot), hand - rot * w.grip_main)
	w.linear_velocity = fore.linear_velocity
	w.angular_velocity = Vector3.ZERO
	_exempt(w)
	w.set_held_by(self)
	w.thrown_t = 0.0
	w.thrower = null
	w.own_t = 0.0
	weapons[side] = w
	weapon_joints[side] = _joint_at(fore, w, hand, not w.is_shield)
	w.welded = not w.is_shield
	aim_q[side] = null
	if Combat.current:
		Combat.current.loose_weapons.erase(w)
	if side == "R" and w.design.get("twoHanded", false) and not weapons.L:
		two_handed = true
		_attach_off_hand(w)
	return true

## The arm model of any throw (launchVelocity): how fast the hand can send `mass` off, and the
## elevation that lands it on `aim_at` (the lower of the two arcs), with a little scatter.
func launch_velocity(from: Vector3, aim_at: Vector3, mass_: float, power := 0.8, javelin := false, scatter := 0.0, arm_f := 1.0) -> Vector3:
	var m_arm := 2.5 * pow(S, 2.5)
	var tired := 0.65 + 0.35 * minf(1.0, stamina / 100.0)
	var v_hand := (26.0 if javelin else 20.0) * sqrt(S) * float(mods.strength) * (0.5 + 0.5 * arm_f) * (1.0 - 0.5 * injury) * (0.4 + 0.6 * power) * tired
	var v := minf(32.0, v_hand * sqrt(m_arm / (m_arm + maxf(0.05, mass_))))
	var d := aim_at - from
	var dx := maxf(0.01, Vector2(d.x, d.z).length())
	var dy := d.y
	var g := gravity
	var disc := pow(v, 4) - g * (g * dx * dx + 2.0 * dy * v * v)
	var theta := atan2(v * v - sqrt(disc), g * dx) if disc >= 0.0 else PI / 4.0
	var yaw_ := atan2(d.x, d.z)
	var pitch := theta
	if scatter > 0.0:
		var a := randf() * TAU
		var r := sqrt(randf()) * scatter
		yaw_ += cos(a) * r
		pitch += sin(a) * r
	return Vector3(sin(yaw_) * cos(pitch) * v, sin(pitch) * v, cos(yaw_) * cos(pitch) * v)

## F: the weapon in `side`'s hand flies at `target` (or along `dir`): point first if it is a
## javelin, end over end if it is a throwing axe, tumbling otherwise.
func throw_weapon(side: String, target = null, power := 0.8, dir = null) -> Weapon:
	if not alive or arm_func(side) < 0.2:
		return null
	var w: Weapon = weapons[side]
	if not w or w.is_shield or (side == "L" and two_handed):
		return null
	var from := w.global_transform * w.center_of_mass
	var arm_f := arm_func(side)
	release(side)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var aim_at: Vector3 = target if target != null else from + (dir if dir != null else fwd) * 20.0
	var scatter := 0.006 + 0.03 * (1.0 - power) + 0.004 * minf(6.0, w.mass) + 0.02 * (1.0 - arm_f)
	var point_first := Weapon.flies_point_first(w.design)
	var vel := launch_velocity(from, aim_at, w.mass, power, point_first, scatter, arm_f)
	w.linear_velocity = vel
	if point_first:
		var q := Quaternion(UP, vel.normalized())
		w.global_transform = Transform3D(Basis(q), from - q * w.center_of_mass)
		w.angular_velocity = Vector3.ZERO
	elif Weapon.spins_in_flight(w.design):
		var sd := vel.cross(UP)
		sd = Vector3(1, 0, 0) if sd.length_squared() < 1e-6 else sd.normalized()
		var fw := Vector3(vel.x, 0, vel.z).normalized()
		var q := PD.quat_from_axes(UP.cross(sd).normalized(), UP, sd)
		if (q * Vector3(1, 0, 0)).dot(fw) < 0.0:
			q = q * Quaternion(UP, PI)
		w.global_transform = Transform3D(Basis(q), from - q * w.center_of_mass)
		w.angular_damp = 0.03
		w.angular_velocity = sd * -15.5
	else:
		var spin := vel.cross(UP).normalized() * -minf(16.0, 4.0 + 10.0 / sqrt(maxf(0.3, w.mass)))
		w.angular_velocity = spin
	w.thrower = self
	w.thrown_t = 3.0
	stamina = maxf(0.0, stamina - (6.0 + 8.0 * power) * (0.6 + 0.15 * minf(6.0, w.mass)))
	return w

# ---------- Function of limbs ----------

func leg_func(side: String) -> float:
	var t: VoxelPart = by_name["thigh" + side]
	var s: VoxelPart = by_name["shin" + side]
	if t.severed or s.severed:
		return 0.0
	return minf(t.function(), s.function())

func arm_func(side: String) -> float:
	var a: Dictionary = arm[side]
	if a.upper.severed or a.fore.severed:
		return 0.0
	return minf(a.upper.function(), a.fore.function())

func can_stand() -> bool:
	return leg_func("L") > 0.05 or leg_func("R") > 0.05

func is_active() -> bool:
	return state != "dead"

# ---------- PD drives ----------

func pd_axis(part: VoxelPart, local_axis: Vector3, des: Vector3, wn: float, zeta: float, max_t: float, dt: float, scale := 1.0) -> void:
	if part.severed or wn <= 0.0 or max_t <= 0.0:
		return
	var kp := wn * wn
	var kd := 2.0 * zeta * wn
	var cur := PD.quat_of(part) * local_axis
	var err := PD.dir_error(cur, des.normalized())
	var alpha := err * kp - part.angular_velocity * kd
	var tq: Vector3
	if scale != 1.0:
		var tw := cur * alpha.dot(cur)
		tq = PD.torque_for(part, alpha - tw, scale) + PD.torque_for(part, tw, 1.0)
	else:
		tq = PD.torque_for(part, alpha, 1.0)
	part.apply_torque_impulse(PD.clamp_len(tq, max_t) * dt)

func pd_relative(part: VoxelPart, parent: VoxelPart, rel_q: Quaternion, wn: float, zeta: float, max_t: float, dt: float, boost := 1.0, react := 1.0) -> void:
	if part.severed or wn <= 0.0:
		return
	var ic := PD.inertia_of(part)
	var ip := PD.inertia_of(parent)
	var desired := PD.quat_of(parent) * rel_q
	var err := PD.rot_error(desired, PD.quat_of(part))
	var rel := part.angular_velocity - parent.angular_velocity
	var tq := PD.torque_for(part, err * (wn * wn) - rel * (2.0 * zeta * wn), boost * ip / (ic + ip))
	tq = PD.clamp_len(tq, max_t)
	part.apply_torque_impulse(tq * dt)
	parent.apply_torque_impulse(-tq * dt * react)

func pd_twist(part: VoxelPart, ref: RigidBody3D, kp: float, kd: float, max_t: float, dt: float) -> void:
	if part.severed:
		return
	var q := PD.quat_of(part)
	var axis := q * Vector3(0, -1, 0)
	var rq := PD.quat_of(ref)
	var f := q * Vector3(0, 0, 1)
	f -= axis * axis.dot(f)
	var rf := rq * Vector3(0, 0, 1)
	rf -= axis * axis.dot(rf)
	if f.length_squared() < 1e-6 or rf.length_squared() < 1e-6:
		return
	f = f.normalized(); rf = rf.normalized()
	var ang := atan2(f.cross(rf).dot(axis), f.dot(rf))
	var spin := (part.angular_velocity - ref.angular_velocity).dot(axis)
	var t := clampf(kp * ang - kd * spin, -max_t, max_t)
	part.apply_torque_impulse(axis * t * dt)

# ---------- Control ----------

## One physics step of a fighter driven by `inp` (the same input dictionary as the web game:
## mx, mz, main{x,y}, off{x,y}, thrust, power, sprint, jump, crouch, kick, look{yaw,pitch}...).
func control(dt: float, inp_in: Dictionary) -> void:
	time += dt
	space = get_world_3d().direct_space_state
	for p in parts:
		if p.flinch_t > 0.0:
			p.flinch_t -= dt
	if push_t > 0.0:
		push_t -= dt
	var live := state != "dead"
	shove_t = maxf(0.0, shove_t - dt)
	slow_timer = maxf(0.0, slow_timer - dt)
	if net_timer > 0.0:
		net_timer -= dt
		if net_timer <= 0.0:
			set_net(false)
	if wine_timer > 0.0:
		wine_timer -= dt
		if wine_timer <= 0.0:
			mods.drunk = 0.0
	# Playing dead: a standing fighter goes fully limp until the key is let go.
	if limp and live:
		if state == "stand":
			set_standing(false)
			state = "down"
			down_timer = 0.4
		elif state == "down":
			down_timer = maxf(down_timer, 0.4)
	var inp: Dictionary = inp_in if live and not limp else {}
	var t_pos: Vector3 = torso.global_position
	var t_rot: Quaternion = PD.quat_of(torso)
	var yaw_q := Quaternion(UP, yaw)
	var leg_l := leg_func("L")
	var leg_r := leg_func("R")
	var leg_avg := (leg_l + leg_r) * 0.5
	var blood_f: float = minf(1.0, 0.35 + blood / 100.0)
	pain = maxf(0.0, pain - dt * 0.2)
	var heavy := 1.0 - 0.5 * injury
	var stam_f := (0.45 + 0.55 * stamina / 100.0) * (0.6 + 0.4 * heavy)
	var conc_f := 1.0 - concussion * 0.6

	# Bleeding, recovery.
	var bleed := 0.0
	for p in parts:
		bleed += p.bleed
		p.bleed = maxf(0.0, p.bleed - dt * 0.08)
		if p.stump:
			p.stump_t += dt
			bleed += 2.5 * maxf(0.0, 1.0 - p.stump_t / 12.0)
	blood = maxf(0.0, blood - bleed * BLEED_RATE * float(mods.bleed) / (S * S) * dt)
	stagger = maxf(0.0, stagger - dt * 1.6)
	concussion = maxf(float(mods.drunk), concussion - dt * 0.05)
	if live and (blood <= 0.0 or head.hp <= 0.0 or head.severed or torso.hp <= 0.0):
		die("decap" if head.severed else ("bleed" if blood <= 0.0 else "wounds"))
		live = false
		inp = {}

	var stamina_use := 0.0
	# ----- Stance -----
	var up_w := t_rot * UP
	var tilt := acos(clampf(up_w.y, -1.0, 1.0))
	tilt_t = tilt_t + dt if tilt > 1.15 else 0.0
	var fresh := time - stood_at < 5.0
	if state == "stand" and (tilt_t > (0.45 if fresh else 0.2) or (tilt > 1.5 and (not fresh or tilt_t > 0.25)) or not can_stand()):
		fall(1.8 if can_stand() else 99.0, true)
	if state == "down":
		down_timer -= dt
		if down_timer <= 0.0 and can_stand():
			state = "rising"
			rise_t = 0.0
			rise_q0 = null
			_legs_touch_ground(false)
	if state == "rising":
		rise_t = minf(1.0, rise_t + dt / (1.5 * (1.0 + injury)))
		if rise_q0 == null:
			rise_q0 = t_rot
		if rise_t >= 1.0 and tilt < 0.5:
			set_standing(true)
		if not can_stand():
			fall(99.0)
	var rising := state == "rising"
	var e1 := PD.smooth(0.0, 0.45, rise_t) if rising else 1.0
	var e2 := PD.smooth(0.35, 1.0, rise_t) if rising else 1.0
	var standing := state == "stand" or rising
	var stand_f := 0.6 + 0.4 * e1 if rising else 1.0

	# ----- Support spring -----
	var total_mass := 0.0
	for p in parts:
		if not p.severed:
			total_mass += p.nominal_mass / (LEG_MASS if p.def.get("leg", false) else 1.0)
	for w in weapons.values():
		if w:
			total_mass += w.mass
	var ray := PhysicsRayQueryParameters3D.create(t_pos, t_pos + Vector3(0, -2.2 * S, 0), VoxelPart.LAYER_WORLD)
	var hit := space.intersect_ray(ray)
	var crouch := 1.0 - e2 if rising else (1.0 if inp.get("crouch", false) else minf(1.0, low_hand * 0.9))
	var one_leg: bool = minf(leg_l, leg_r) < 0.1
	var leg_flinch := 1.0
	for n in ["thighL", "thighR", "shinL", "shinR"]:
		if by_name[n].flinch_t > 0.0:
			leg_flinch = 0.6
	var support: float = minf(1.0, leg_avg * 1.6) * (0.75 if one_leg else 1.0) * stand_f * leg_flinch if standing else 0.0
	var lv0 := torso.linear_velocity
	var walk_amt: float = minf(1.0, Vector2(lv0.x, lv0.z).length() / 2.5)
	var bob := 0.035 * S * walk_amt * (0.5 - 0.5 * cos(2.0 * gait_phase)) if standing else 0.0
	var grounded := false
	var ground_y := 0.0
	if hit:
		var dist = t_pos.y - hit.position.y
		ground_y = hit.position.y
		var run_low := 0.06 * minf(1.0, walk_amt * 2.5 / 3.5)
		var desired := torso_y * (0.95 - run_low) * (1.0 - crouch * 0.22 - (0.12 if one_leg else 0.0)) * (0.7 + 0.3 * support) * (0.55 + 0.45 * e2 if rising else 1.0) + bob
		grounded = dist < desired + 0.25
		if grounded and support > 0.0:
			var vy := torso.linear_velocity.y
			var f = total_mass * (gravity * minf(1.0, support * 1.1) + 140.0 * (desired - dist) * support - 22.0 * vy * support)
			f = clampf(f, 0.0, total_mass * 30.0)
			torso.apply_central_impulse(Vector3(0, f * dt, 0))

	# ----- Locomotion -----
	var lv := torso.linear_velocity
	var move_local := Vector3.ZERO if rising else Vector3(inp.get("mx", 0.0), 0, inp.get("mz", 0.0))
	if move_local.length_squared() > 1.0:
		move_local = move_local.normalized()
	var sprint: bool = inp.get("sprint", false) and stamina > 5.0 and move_local.z > 0.3
	var speed := (3.8 if sprint else 2.1) * sqrt(S) * float(mods.speed) * (0.3 if one_leg else 0.4 + 0.6 * leg_avg) * blood_f * heavy * (1.0 - crouch * 0.45) / (1.0 + carrying * 0.9) * (slow_factor if slow_timer > 0.0 else 1.0) * (0.25 if net_timer > 0.0 else 1.0)
	var dir_f = (1.0 + 0.35 * move_local.z if move_local.z < 0.0 else 1.0) * (1.0 - 0.15 * abs(move_local.x))
	var move_world = yaw_q * move_local * speed * dir_f
	var planted := 0
	var anchor_v := Vector3.ZERO
	if standing and grounded:
		for side in ["L", "R"]:
			var ft = feet[side]
			var shin: VoxelPart = by_name["shin" + side]
			if ft == null or ft.swing or shin.severed:
				continue
			var foot := shin.global_transform * Vector3(0, -4 * V * S, 0)
			ft.slip = Vector2(ft.anchor.x - foot.x, ft.anchor.z - foot.z).length()
			anchor_v.x += (ft.anchor.x - foot.x) * ANCHOR_K
			anchor_v.z += (ft.anchor.z - foot.z) * ANCHOR_K
			planted += 1
		if planted > 0:
			move_world += PD.clamp_len(anchor_v / planted, 1.5)
	if grounded and standing:
		var accel := (9.0 + 12.0 * minf(1, planted)) * stand_f * float(mods.accel) * (0.55 + 0.45 * heavy)
		var ix := Vector2(move_world.x - lv.x, move_world.z - lv.z).limit_length(6.0) * accel * total_mass * dt
		torso.apply_central_impulse(Vector3(ix.x, 0, ix.y))
		if sprint:
			stamina_use += 10.0 * dt
		if inp.get("jump", false) and stamina > 15.0:
			torso.apply_central_impulse(Vector3(0, total_mass * 4.2 * maxf(0.3, leg_avg), 0))
			stamina -= 15.0
	v_smooth = v_smooth.lerp(Vector3(lv.x, 0, lv.z), minf(1.0, dt * 10.0))
	var h_speed := Vector2(v_smooth.x, v_smooth.z).length()
	var step_len: float = minf(0.66, 0.28 + 0.12 * h_speed) * S
	if h_speed > 0.25:
		gait_phase += dt * h_speed * PI / step_len

	# ----- Upright balance -----
	if standing:
		var balance: float = minf(1.0, (0.25 + 0.75 * minf(1.0, leg_avg * 1.3)) * (1.0 - stagger * 0.85) * conc_f) * stand_f
		var low_lean := low_hand * 0.42 / sqrt(maxf(1.0, S))
		low_hand = 0.0
		var kneel_lean := 0.75 * (1.0 - e2) if rising else 0.0
		var lean := Quaternion(Vector3(1, 0, 0), (0.2 if sprint else 0.1) * move_local.z + crouch * 0.25 / sqrt(maxf(1.0, S)) + (0.12 if one_leg else 0.0) + low_lean + kneel_lean)
		if h_speed < 0.4 and live:
			lean = Quaternion(Vector3(0, 0, 1), 0.01 * sin(time * 0.6 + slot * 2)) * Quaternion(Vector3(1, 0, 0), 0.012 * sin(time * 0.9 + slot)) * lean
		var twist := 0.0
		for s in ["R", "L"]:
			var t: float = jab_t[s]
			if t > 0.0:
				var k := 1.0 - t / JAB_TIME
				twist += (1.0 if s == "R" else -1.0) * 0.5 * (k / 0.15 if k < 0.15 else (1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4))
		var desired_q := yaw_q * Quaternion(UP, twist) * lean
		if rising and rise_q0 != null:
			desired_q = (rise_q0 as Quaternion).normalized().slerp(desired_q.normalized(), e1)
		var err := PD.rot_error(desired_q, t_rot)
		var I := 4.0 * MS * S * S
		var wn := (8.0 if rising else 12.0) * sqrt(balance)
		var tq := (err * (wn * wn) - torso.angular_velocity * (2.0 * wn)) * I
		torso.apply_torque_impulse(PD.clamp_len(tq, 1400.0 * balance * MS * S) * dt)

	# ----- Head -----
	if not head.severed:
		var neck := (0.45 + 0.55 * conc_f if live else 0.18) * (0.22 if head.hanging else 1.0)
		var ly := 0.0
		var lp := 0.0
		if live and inp.has("look"):
			ly = float(inp.look.yaw) - yaw
			lp = float(inp.look.pitch) * 0.7
		elif live and gaze != null:
			var d: Vector3 = gaze - t_pos - Vector3(0, 0.6 * S, 0)
			ly = atan2(d.x, d.z) - yaw
			lp = atan2(d.y, Vector2(d.x, d.z).length())
		elif live:
			ly = 0.3 * sin(time * 0.37 + slot)
		ly = atan2(sin(ly), cos(ly))
		ly = clampf(ly, -1.1, 1.1)
		lp = clampf(lp, -0.4, 0.45)
		var look_q := Quaternion(UP, ly) * Quaternion(Vector3(1, 0, 0), -lp)
		pd_relative(head, torso, look_q, 20.0 * neck, 0.95, 90.0 * neck * MS * S, dt)

	# ----- Legs -----
	kick_timer = maxf(0.0, kick_timer - dt)
	if inp.get("kick", false) and kick_timer <= 0.0 and stamina > 12.0 and standing:
		kick_timer = 0.42
		stamina -= 12.0
	var move_amt: float = minf(1.0, h_speed / 2.5)
	var t_inv := t_rot.inverse()
	var move_dir := v_smooth.normalized() if v_smooth.length_squared() >= 0.04 else Vector3.ZERO
	for side in ["L", "R"]:
		var thigh: VoxelPart = by_name["thigh" + side]
		var shin: VoxelPart = by_name["shin" + side]
		if thigh.severed:
			continue
		var f := maxf(0.15, leg_func(side)) * (0.12 + 0.88 * e1 if rising else 1.0) if standing else 0.03
		var kicking = side == "R" and kick_timer > 0.0
		var l1 := 8 * V * S
		var l2 := 8 * V * S
		var hip := t_pos + t_rot * (thigh.pa)
		var thigh_q := Quaternion.IDENTITY
		var bend := 0.2
		if kicking:
			var chamber := kick_timer > 0.3
			thigh_q = Quaternion(Vector3(-1, 0, 0), 1.1 if chamber else 1.45)
			bend = 1.7 if chamber else 0.05
			if feet[side]:
				feet[side].swing = true
		elif standing and grounded:
			var neutral := t_pos + yaw_q * Vector3(thigh.pa.x * 1.15, 0, 0)
			neutral.y = ground_y
			var ft = feet[side]
			if ft == null:
				ft = {"anchor": neutral, "from": neutral, "swing": false, "s": 0.0, "land": neutral, "half": -1, "slip": 0.0}
				feet[side] = ft
			var half := int(floor(gait_phase / PI))
			var my_swing = (half % 2 == 0) == (side == "L")
			var moving := h_speed > 0.25
			if moving and my_swing and not ft.swing and ft.half != half:
				ft.half = half
				ft.swing = true
				ft.from = ft.anchor
				ft.s = 0.0
			if ft.swing:
				ft.land = neutral + move_dir * step_len * 0.5
				var rate: float = h_speed / step_len if moving else 4.0
				ft.s = minf(1.0, ft.s + dt * rate)
				if ft.s >= 1.0 or (moving and not my_swing):
					ft.swing = false
					ft.anchor = ft.land
			elif ft.slip > (0.3 if moving else 0.18) * S:
				ft.swing = true
				ft.from = ft.anchor
				ft.s = 0.0
				ft.half = half
				ft.land = neutral + Vector3(v_smooth.x, 0, v_smooth.z).normalized() * 0.25 * S
			elif not moving and (ft.anchor as Vector3).distance_to(neutral) > 0.3 * S:
				ft.swing = true
				ft.from = ft.anchor
				ft.s = 0.0
				ft.land = neutral
			var ease: float = ft.s * ft.s * (3.0 - 2.0 * ft.s)
			var target: Vector3 = (ft.from as Vector3).lerp(ft.land, ease) + Vector3(0, sin(PI * ft.s) * (0.08 + 0.06 * move_amt) * S, 0) if ft.swing else ft.anchor
			var hf := t_inv * (target - hip)
			var d := hf.length()
			var max_d := (l1 + l2) * 0.985
			if d > max_d:
				hf *= max_d / d
				d = max_d
			if d < 0.05:
				hf = Vector3(0, -0.05, 0)
				d = 0.05
			var dirv := hf / d
			var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
			bend = PI - acos(clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0))
			var axis := dirv.cross(Vector3(0, 0, 1))
			axis = Vector3(-1, 0, 0) if axis.length_squared() < 1e-6 else axis.normalized()
			thigh_q = Quaternion(Vector3(0, -1, 0), dirv.rotated(axis, a))
		else:
			bend = 0.9 if state == "down" and live else 0.2
			if feet[side]:
				feet[side].swing = true
		if rising:
			var k := PD.smooth(0.3, 0.9, rise_t)
			thigh_q = Quaternion(Vector3(1, 0, 0), -0.75).slerp(thigh_q, k)
			bend = 1.6 * (1.0 - k) + bend * k
		var snap: bool = kicking
		pd_relative(thigh, torso, thigh_q, LEG_WN * sqrt(f), 0.9, (1400.0 if snap else 900.0) * f * MS * S, dt, 3.0, LEG_REACT)
		if not shin.severed and not shin.hanging:
			pd_relative(shin, thigh, Quaternion(Vector3(1, 0, 0), bend), LEG_WN * sqrt(f), 0.9, (700.0 if snap else 600.0) * f * MS * S, dt, 3.0)

	# ----- Arms and weapons -----
	var power: bool = inp.get("power", false) and stamina > 3.0
	if power:
		stamina_use += 9.0 * dt
	for side in ["R", "L"]:
		_drive_arm(side, inp, live and not limp, power, stam_f, blood_f, t_pos, t_rot, yaw_q, dt)

	var sw: Weapon = weapons.R
	if sw and not sw.is_shield:
		var tip := sw.angular_velocity.length() * sw.reach
		stamina_use += 0.6 * maxf(0.0, tip - 3.0) * (0.6 + 0.25 * minf(6.0, sw.mass)) * dt
	var still := Vector2(v_smooth.x, v_smooth.z).length() < 0.4
	var regen := 3.0 if stamina_use > 0.02 * dt * 60.0 else (18.0 if still else 9.0)
	stamina = clampf(stamina - stamina_use + regen * heavy * dt, 0.0, 100.0)

func _drive_arm(side: String, inp: Dictionary, live: bool, power: bool, stam_f: float, blood_f: float, t_pos: Vector3, t_rot: Quaternion, yaw_q: Quaternion, dt: float) -> void:
	var a: Dictionary = arm[side]
	var upper: VoxelPart = a.upper
	var fore: VoxelPart = a.fore
	if upper.severed or fore.severed or upper.hanging or fore.hanging or not live:
		return
	var af := arm_func(side)
	if fore.flinch_t > 0.0 or upper.flinch_t > 0.0:
		af *= 0.35
	# Caught by that arm: it cannot swing until it is wrenched free.
	if pinned_arm == side and is_instance_valid(grabbed_by):
		af *= 0.12
	if side == "L" and two_handed:
		var hand_l := hand_world("L")
		var sh_l = t_pos + t_rot * shoulder.L
		var dir_l = (hand_l - sh_l).normalized()
		pd_axis(upper, Vector3(0, -1, 0), (dir_l + Vector3(0, -0.3, 0)).normalized(), 10.0, 0.8, 50.0 * af * MS * S, dt)
		pd_axis(fore, Vector3(0, -1, 0), dir_l, 8.0, 0.8, 30.0 * af * MS * S, dt)
		var m_arm := (fore.nominal_mass + upper.nominal_mass * 0.5)
		fore.apply_impulse(Vector3(0, m_arm * gravity * minf(1.0, af * 1.2) * dt, 0), hand_l - fore.global_position)
		return
	var w: Weapon = weapons[side]
	var strength := af * stam_f * blood_f * (1.45 if power else 1.0) * (1.6 if two_handed else 1.0) * (1.0 if state == "stand" else 0.3)
	var hp: Dictionary = inp.get("main" if side == "R" else "off", {"x": 0.1 if side == "R" else -0.35, "y": 0.1})
	if not w and inp.get("jabR" if side == "R" else "jabL", false) and jab_t[side] <= 0.0 and state == "stand" and stamina > 4.0:
		jab_t[side] = JAB_TIME
		stamina -= 5.0
	jab_t[side] = maxf(0.0, jab_t[side] - dt)
	var jk: float = 1.0 - jab_t[side] / JAB_TIME if jab_t[side] > 0.0 else -1.0
	var jab = null
	if jk >= 0.0:
		jab = -0.9 * jk / 0.12 if jk < 0.12 else (1.8 if jk < 0.6 else 1.8 * (1.0 - (jk - 0.6) / 0.4))
	var thrust: float = 1.0 if shove_t > 0.0 else (jab if jab != null else float(inp.get("thrust", 0.0) if side == "R" else inp.get("offThrust", 0.0)))
	var down_hp = {"x": 0.4 if side == "R" else -0.4, "y": -0.5} if state != "stand" else ({"x": 0.25 if side == "R" else -0.25, "y": 0.35} if shove_t > 0.0 else null)
	var hp_used: Dictionary = down_hp if down_hp != null else hp
	# A bow is held out at the shoulder, stave upright, whatever the mouse does.
	if down_hp == null and side == "R" and w and str(w.design.get("shoots", "")) == "arrow":
		hp_used = {"x": 0.3, "y": 0.45}
	hand_input[side] = hp_used
	var target := hand_target_local(side, hp_used, thrust)
	if concussion > 0.1:
		target.x += sin(time * 3.1 + slot) * concussion * 0.25
		target.y += cos(time * 2.3) * concussion * 0.2
	var target_w := t_pos + yaw_q * target
	# The hand moves like an arm: limited speed and acceleration toward the mouse's mark.
	var lead = hand_lead[side]
	if lead != null and (lead as Vector3).distance_to(target_w) < 2.5 * S:
		var h: float = handling[side]
		var vmax := 11.0 * S * (2.0 if jab_t[side] > 0.0 else 1.0) * (0.55 + 0.45 * h) * (0.5 + 0.5 * minf(1.0, arm_func(side) / 0.85)) * (0.6 + 0.4 * minf(1.0, stamina / 50.0))
		var amax := 95.0 * S * (0.4 + 0.6 * h) * (1.3 if power else 1.0) * (4.0 if jab_t[side] > 0.0 else 1.0)
		var to_t: Vector3 = target_w - lead
		var dist := to_t.length()
		var v_des := to_t * (minf(minf(vmax, sqrt(2.0 * amax * dist)), dist / dt) / dist) if dist > 1e-5 else Vector3.ZERO
		var acc := PD.clamp_len((v_des - lead_vel[side]) / dt, amax)
		lead_vel[side] += acc * dt
		lead = lead + lead_vel[side] * dt
		hand_lead[side] = lead
		target_w = lead
	else:
		hand_lead[side] = target_w
		lead_vel[side] = Vector3.ZERO
	target_vel[side] = (target_w - prev_target[side]) / dt
	if target_vel[side].length_squared() > 2500.0:
		target_vel[side] = Vector3.ZERO
	prev_target[side] = target_w

	var hand_w := hand_world(side)
	var hand_vel := fore.velocity_at(hand_w)
	var m_eff := (fore.nominal_mass + upper.nominal_mass * 0.5) + (w.mass if w else 0.0)
	var load := (w.mass * 0.22 + float(w.stats.get("inertia", 0.0)) * 0.9) / (float(mods.strength) * sqrt(S) * (1.7 if two_handed else 1.0)) if w else 0.0
	var hnd := 1.0 / (1.0 + load)
	handling[side] = hnd
	var hand_goal := target_w
	var shoulder_w = t_pos + t_rot * shoulder[side]
	var dir = (target_w - shoulder_w).normalized()
	if w and not w.is_shield and weapon_joints[side]:
		var fore_q := weapon_aim(side, w, target_w, t_pos, yaw_q, inp, dt) * GRIP_Q.inverse()
		var fore_dir := fore_q * Vector3(0, -1, 0)
		var lu := UPPER_LEN * S
		var lf := FORE_LEN * S
		var side_sign := -1.0 if side == "R" else 1.0
		var e_local = t_rot.inverse() * (target_w - fore_dir * lf - shoulder_w)
		if e_local.length_squared() < 1e-6:
			e_local = Vector3(side_sign * 0.3, -1, -0.3)
		e_local = e_local.normalized().lerp(Vector3(side_sign * 0.5, -0.7, -0.5).normalized(), 0.06 if two_handed else 0.18).normalized()
		e_local.y = minf(e_local.y, 0.12 * S / lu)
		if side_sign < 0.0:
			e_local.x = minf(e_local.x, 0.22 * S / lu) if false else e_local.x
		var elbow_dir = (t_rot * e_local).normalized()
		var elbow = shoulder_w + elbow_dir * lu
		hand_goal = elbow + fore_dir * lf
		var m_load := (fore.nominal_mass + w.mass) * lu * lu
		var k_up := 1.0 + m_load / PD.inertia_of(upper)
		pd_axis(upper, Vector3(0, -1, 0), elbow_dir, 16.0, 1.0, 260.0 * af * MS * S, dt, minf(5.0 if two_handed else 12.0, k_up))
		pd_twist(upper, torso, 1.5 * MS, 0.25 * MS, 12.0 * MS, dt)
		_drive_forearm(side, w, fore_q, strength, dt)
		var wmax := 30.0
		if w.angular_velocity.length() > wmax:
			var k := wmax / w.angular_velocity.length()
			w.angular_velocity *= k
			fore.angular_velocity *= k
	elif not w and (jab_t[side] > 0.0):
		var jk2 = 1.0 - jab_t[side] / JAB_TIME
		var out = jk2 > 0.1 and jk2 < 0.6
		pd_axis(upper, Vector3(0, -1, 0), dir if out else (dir + Vector3(0, -0.35, 0)).normalized(), 30.0 if out else 14.0, 0.8, (320.0 if out else 90.0) * af * MS * S, dt)
		pd_axis(fore, Vector3(0, -1, 0), dir, 26.0 if out else 10.0, 0.8, (220.0 if out else 60.0) * af * MS * S, dt)
		pd_twist(upper, torso, 4.0 * MS, 0.6 * MS, 30.0 * MS, dt)
	else:
		pd_axis(upper, Vector3(0, -1, 0), (dir + Vector3(0, -0.35, 0)).normalized(), 14.0, 0.8, 90.0 * af * MS * S, dt)
		pd_axis(fore, Vector3(0, -1, 0), dir, 10.0, 0.8, 60.0 * af * MS * S, dt)
		pd_twist(upper, torso, 1.5 * MS, 0.25 * MS, 12.0 * MS, dt)
		pd_twist(fore, upper, 1.0 * MS, 0.2 * MS, 8.0 * MS, dt)
		if w and w.is_shield:
			_orient_shield(w, target_w, t_pos, yaw_q, strength, dt)
	var kd := (40.0 if power else 32.0) * (0.85 + 0.15 * hnd) * minf(1.0, 3.0 / m_eff)
	var F = ((hand_goal - hand_w) * (300.0 * (0.5 + 0.5 * hnd)) + (target_vel[side] - hand_vel) * kd) * m_eff
	F.y += m_eff * gravity * minf(1.0, af * 1.2)
	F = PD.clamp_len(F, 1150.0 * strength * MS * float(mods.strength) * (0.55 + 0.45 * hnd) * (1.0 + 0.35 * (1.0 - hnd)) * (2.2 if not w and jab_t[side] > 0.0 else 1.0))
	fore.apply_impulse(F * dt, hand_w - fore.global_position)
	torso.apply_central_impulse(Vector3(-F.x * dt * 0.35, 0, -F.z * dt * 0.35))

## The hand moves on a flat pane in front of the body, Half Sword style.
func hand_target_local(side: String, hp: Dictionary, thrust: float) -> Vector3:
	var sh: Vector3 = shoulder[side]
	var x := -clampf(float(hp.get("x", 0.0)), -2.0, 2.0) * 0.36 * S
	var fist := 0.12 if not weapons[side] else 0.0
	var hy := clampf(float(hp.get("y", 0.0)), -1.6, 1.6)
	var y := (-0.08 + (hy * 0.36 if hy >= 0.0 else -0.3 * minf(0.4, -hy) - (0.6 if fist > 0.0 else 0.4) * maxf(0.0, -hy - 0.4))) * S
	var cross: float = maxf(0.0, -float(hp.get("x", 0.0))) if side == "R" else maxf(0.0, float(hp.get("x", 0.0)))
	var z := (0.40 + fist + thrust * 0.4 + 0.1 * minf(1.0, cross / 1.5)) * S
	var d := Vector3(x + (0.1 if side == "R" else -0.1) * S, y, z)
	d = PD.clamp_len(d, (UPPER_LEN + FORE_LEN) * 0.97 * S if fist > 0.0 and jab_t[side] > 0.0 else arm_reach)
	return d + sh

## Where the blade should point: elevation from the hand's height, yaw from a pivot behind the
## hand, the edge leading the stroke; slewed at the rate the weapon allows.
func weapon_aim(side: String, w: Weapon, target_w: Vector3, t_pos: Vector3, yaw_q: Quaternion, inp: Dictionary, dt: float) -> Quaternion:
	var local := (yaw_q.inverse() * (target_w - t_pos)) / S
	var hy := float(hand_input[side].get("y", 0.15))
	var elev := clampf((0.6 if hy >= 0.0 else 0.85) * hy, -1.45, 1.45)
	var shx: float = shoulder[side].x / S
	var pivot := Vector3(shx + (local.x - shx) * 0.3, local.y, local.z - 0.35)
	var flat := Vector3(local.x - pivot.x, 0, local.z - pivot.z)
	if flat.length_squared() < 1e-4:
		flat = Vector3(0, 0, 1)
	flat = flat.normalized()
	var axis := yaw_q * Vector3(flat.x * cos(elev), sin(elev), flat.z * cos(elev))
	low_hand = maxf(low_hand, maxf(0.0, -elev - 0.2))
	var raise_k := smoothstep(0.5, 1.2, elev)
	var ed := yaw_q * Vector3((1.0 if side == "R" else -1.0) * (1.0 - raise_k), 0, raise_k)
	ed -= axis * ed.dot(axis)
	if ed.length_squared() < 1e-4:
		var fz := yaw_q * Vector3(0, 0, 1)
		ed = fz - axis * axis.dot(fz)
	ed = ed.normalized()
	if side == "R":
		ed = ed.rotated(axis, float(inp.get("twist", 0.0)))
	var tv: Vector3 = target_vel[side] - axis * target_vel[side].dot(axis)
	var tvl := tv.length()
	if tvl > 0.7:
		var lean := atan2(ed.cross(tv).dot(axis), ed.dot(tv))
		ed = ed.rotated(axis, clampf(lean, -0.52, 0.52) * minf(1.0, tvl / 3.0))
	var z := ed.cross(axis).normalized()
	var e := axis.cross(z)
	var desired := PD.quat_from_axes(e, axis, z)
	var prev = aim_q[side]
	if prev != null:
		var step := PD.rot_error(desired, prev)
		var h: float = handling[side]
		var wmax := 26.0 * (0.45 + 0.55 * h) * (1.2 if inp.get("power", false) else 1.0)
		var rate := step.length() / dt
		if rate > wmax:
			step *= wmax / rate
			var ang := step.length()
			desired = Quaternion(step / ang, ang) * (prev as Quaternion)
	aim_q[side] = desired
	return desired

func _drive_forearm(side: String, w: Weapon, fore_q: Quaternion, strength: float, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var rot := PD.quat_of(fore)
	var err := PD.rot_error(fore_q, rot)
	var wn := 16.0
	var alpha := PD.clamp_len(err * (wn * wn) - fore.angular_velocity * (2.0 * 0.8 * wn), 460.0 * (0.6 + 0.4 * strength) * float(mods.strength))
	var hand_w := hand_world(side)
	var com_w := w.global_transform * w.center_of_mass
	var lever := com_w - hand_w
	var i_fore := PD.inertia_of(fore) + fore.nominal_mass * pow(FORE_LEN * S * 0.5, 2)
	var i_wpn := PD.inertia_of(w) + w.mass * lever.length_squared()
	var i_asm := i_fore + i_wpn
	var along := rot * Vector3(0, -1, 0)
	var twist_a := along * alpha.dot(along)
	var tq := PD.torque_for(fore, alpha - twist_a, i_asm / PD.inertia_of(fore)) + PD.torque_for(fore, twist_a, 1.5)
	tq = PD.clamp_len(tq, 90.0 * strength * MS * S * float(mods.strength))
	var mg := w.mass * gravity * minf(1.0, strength * 2.0)
	tq += Vector3(-lever.z * mg, 0, lever.x * mg)
	var f := i_fore / i_asm
	fore.apply_torque_impulse(tq * dt * f)
	w.apply_torque_impulse(tq * dt * (1.0 - f))

func _orient_shield(w: Weapon, target_w: Vector3, t_pos: Vector3, yaw_q: Quaternion, strength: float, dt: float) -> void:
	var fwd := yaw_q * Vector3(0, 0, 1)
	var out := target_w - t_pos
	out.y = 0
	fwd = fwd.lerp(out.normalized(), 0.4).normalized()
	var desired := PD.quat_from_axes(UP.cross(fwd).normalized(), UP, fwd)
	var err := PD.rot_error(desired, PD.quat_of(w))
	var wn := 18.0
	var tq := PD.torque_for(w, err * (wn * wn) - w.angular_velocity * (2.0 * 0.9 * wn), 1.5)
	w.apply_torque_impulse(PD.clamp_len(tq, 70.0 * strength * MS * S * float(mods.strength)) * dt)

# ---------- Falling, standing, dying ----------

func set_standing(on: bool) -> void:
	if on:
		state = "stand"
		stood_at = time
	_legs_touch_ground(not on)

## Standing (and getting up) the legs are held by the support spring, not the sand; lying, they
## rest on it.
func _legs_touch_ground(on: bool) -> void:
	for side in ["L", "R"]:
		for n in ["thigh" + side, "shin" + side]:
			var p: VoxelPart = by_name[n]
			if not p.severed:
				p.collision_mask = VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS | (VoxelPart.LAYER_WORLD if on else 0)

func fall(duration: float, force := false) -> void:
	if state == "dead":
		return
	if bool(mods.get("unstoppable", false)) and not force and blood > 40.0:
		return
	state = "down"
	down_timer = duration
	set_standing(false)

## Moves the whole body (every part, its weapons) so the torso stands over `p`, at rest.
func teleport(p: Vector3) -> void:
	var off := Vector3(p.x, 0.0, p.z) - Vector3(torso.global_position.x, 0.0, torso.global_position.z)
	var bodies: Array = parts.duplicate()
	for side in weapons:
		if weapons[side]:
			bodies.append(weapons[side])
	for b in bodies:
		if is_instance_valid(b):
			b.global_position += off
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO

func die(cause := "") -> void:
	if state == "dead":
		return
	state = "dead"
	set_standing(false)
	for side in ["R", "L"]:
		release(side)
	died.emit(self, cause)

# ---------- Wounds ----------

## A blow lands on `part` (the same hit as the web game's applyHit: impulse, type, hardness,
## sharpness, point, dir, axis, edge, heavy...). Returns what it did.
func apply_hit(part: VoxelPart, hit: Dictionary) -> Dictionary:
	var res := {"removed": [], "severed": [], "dmg": 0.0}
	var detached := part.severed
	var keep_stagger := stagger
	var keep_conc := concussion
	var type: String = hit.get("type", "blunt")
	var hardness: float = hit.get("hardness", 0.3)
	var sharpness: float = hit.get("sharpness", 0.0)
	var heavy: float = clampf(hit.get("heavy", 0.0), 0.0, 1.0)
	var J: float = float(hit.get("impulse", 0.0)) * HIT_SCALE
	var inv := part.global_transform.affine_inverse()
	var lp: Vector3 = inv * (hit.point as Vector3)
	var basis_inv := part.global_transform.basis.orthonormalized().inverse()
	var ld: Vector3 = (basis_inv * (hit.dir as Vector3)).normalized()
	var la: Vector3 = (basis_inv * (hit.get("axis", hit.dir) as Vector3)).normalized()
	# Armour takes it first.
	var armor: Array = part.get_meta("armor", [])
	if not armor.is_empty() and not detached:
		var a: Dictionary = armor[0]
		var h: float = Data.material(a.mat).get("hardness", 0.6)
		var force := J * (0.6 if type == "blunt" else 1.0) * (1.0 + 0.6 * heavy)
		if force > 10.0 * h and a.alive > 0:
			a.alive = maxi(0, int(a.alive) - (1 + int(force / (12.0 * h))))
			if a.alive <= 0:
				a.node.queue_free()
				armor.remove_at(0)
				res.armor_off = true
		J *= 1.0 - minf(0.85, 0.3 + 0.55 * h) * (0.55 if type == "blunt" else 1.0)
		res.armor = true
	var dmg := 0.0
	var remove := []
	var vfs := part.vf * part.part_scale
	var hollow := 0.0 if detached else _hollow(part, lp, ld, V * S * 1.6)
	if type == "edge":
		var edge_v: Vector3 = hit.get("edge", Vector3.ZERO)
		var align := abs(ld.dot((basis_inv * edge_v).normalized())) if edge_v != Vector3.ZERO else 0.5
		var eff := hardness * sharpness * (0.12 + 0.88 * pow(align, 1.5))
		dmg = J * 2.4 * eff + (J * 0.6 if align < 0.35 else 0.0)
		if align < 0.35:
			stagger = minf(1.0, stagger + J * 0.01)
			res.slid = true
		part.bleed += dmg * 0.05 * (2.0 if hit.get("serrated", false) else 1.0)
		var big: float = maxf(1.0, S)
		var depth: float = minf(0.36 + 0.24 * heavy, 0.017 * J * eff * (1.0 + 0.8 * heavy)) * S / pow(big, 1.5)
		var width := vfs * (0.75 + 0.5 * heavy)
		if J * eff > 3.0 * big:
			var n := la.cross(ld)
			if n.length_squared() < 1e-4:
				n = Vector3(1, 0, 0)
			n = n.normalized()
			var span := (0.24 + 0.08 * heavy) * S
			for i in part.fx.size():
				if part.alive[i] == 0:
					continue
				var d := part.local_of(i) - lp
				if abs(d.dot(n)) < width and d.dot(ld) > -V * S and d.dot(ld) < depth + hollow and abs(d.dot(la)) < span:
					remove.append(i)
	elif type == "point":
		var eff := hardness * sharpness * maxf(0.15, la.dot(ld))
		dmg = J * 2.8 * eff
		part.bleed += dmg * 0.07
		var depth: float = minf(0.3 + 0.2 * heavy, 0.02 * J * eff * (1.0 + 0.8 * heavy)) * S
		if J * eff > 2.5:
			var r := vfs * (1.1 + 0.6 * heavy)
			for i in part.fx.size():
				if part.alive[i] == 0:
					continue
				var d := part.local_of(i) - lp
				var along := d.dot(la)
				if along > -V * S and along < depth + hollow and (d - la * along).length() < r:
					remove.append(i)
	else:
		dmg = J * 1.5
		stagger = minf(1.0, stagger + J * 0.018)
		if part == head:
			concussion = minf(1.0, concussion + J * 0.022)
		if part == torso and lp.y < 0.0 and J > 8.0 and not detached:
			stamina = maxf(0.0, stamina - J * 1.3)
			res.winded = true
		if not detached and J > 20.0 and not part.fractured and part != torso and part != head and randf() < (J - 18.0) * 0.05 * (1.0 + heavy) / float(mods.toughness):
			part.fractured = true
			part.bleed += 0.5
			part.wound(lp, minf(0.16, 0.08 + J * 0.002) * S, "bruise")
			res.fractured = part
		if J > 16.0 or (hollow > 0.0 and J > 10.0):
			var r: float = (minf(0.075 + 0.04 * heavy, 0.04 + maxf(0.0, J - 16.0) * 0.003 * (1.0 + heavy)) + minf(0.03, hollow * 0.3)) * S
			var at := lp + ld * hollow
			for i in part.fx.size():
				if part.alive[i] and part.local_of(i).distance_to(at) < r:
					remove.append(i)
			part.bleed += J * 0.02
	if hollow > 0.0 and not detached:
		dmg *= 1.0 + minf(1.0, hollow / 0.1)
	if part == torso or part == head:
		stagger = minf(1.0, stagger + J * 0.007)
	if not detached:
		stagger = minf(1.0, stagger + J * 0.0056 * (1.0 + injury) * (1.0 + 0.8 * (1.0 - minf(1.0, stamina / 40.0))))
		part.flinch_t = maxf(part.flinch_t, minf(0.45, 0.12 + J * 0.01))
		if push_t <= 0.0 and J > 4.0:
			push_t = 0.3
			var push: float = minf(90.0 if hit.get("thrown", false) else 55.0, J * (2.4 if hit.get("thrown", false) else 1.4)) * MS * S
			var dv: Vector3 = hit.dir
			torso.apply_central_impulse(Vector3(dv.x * push, 0, dv.z * push))
	var soak := pow(S, 1.5) * float(mods.toughness)
	dmg *= part.mult / soak * (0.75 if part == torso or part == head else 1.0)
	if boss:
		dmg *= 0.6
	if part == torso or part == head:
		dmg = minf(dmg, 28.0 * part.mult / float(mods.toughness) * (0.7 if boss else 1.0))
	if detached:
		stagger = keep_stagger
		concussion = keep_conc
		dmg = 0.0
	part.hp = maxf(0.0, part.hp - dmg)
	res.dmg = dmg
	pain = minf(1.0, pain + dmg / 70.0)
	var steady: bool = bool(mods.get("unstoppable", false)) and blood > 40.0
	if concussion > 0.85 and state == "stand" and not steady:
		fall(3.0)
	if stagger > 0.95 and J >= 10.0 and state == "stand" and not steady:
		fall(1.5)
	if remove.is_empty() and not detached and J > 3.0:
		var bruise := type == "blunt"
		part.wound(lp, (minf(0.13, 0.05 + J * 0.003) if bruise else V * 1.6) * S, "bruise" if bruise else "blood")
	if not remove.is_empty():
		if remove.size() > 80 * 8:
			remove.sort_custom(func(a, b): return part.local_of(a).distance_squared_to(lp) < part.local_of(b).distance_squared_to(lp))
			remove = remove.slice(0, 80 * 8)
		var voxels := part.remove_voxels(remove)
		res.removed.append({"part": part, "indices": remove, "voxels": voxels})
		break_loose(part, res, hit.dir, detached)
		if not part.severed and part.integrity < 0.4:
			part.hp = 0.0
	if part == head and part.hp <= 0.0:
		die("ko")
	if part == torso and part.hp <= 0.0:
		die("wounds")
	hit_taken.emit(self, res)
	return res

## How deep an open hole goes under a blow at `lp` heading `ld` (0 on whole skin).
func _hollow(part: VoxelPart, lp: Vector3, ld: Vector3, width: float) -> float:
	var seen := []
	for i in part.fx.size():
		if part.alive[i]:
			continue
		var d := part.local_of(i) - lp
		var along := d.dot(ld)
		if along <= 0.0 or (d - ld * along).length() >= width:
			continue
		seen.append(along)
	seen.sort()
	var deepest := 0.0
	var step: float = maxf(V * S * 2.0, part.vf * part.part_scale * 2.0)
	for a in seen:
		if a > deepest + step:
			break
		deepest = a
	return deepest

## After voxels are gone: a lump cut off falls away; a limb cut clean through comes off; a limb
## left on a thin strip hangs.
func break_loose(part: VoxelPart, res: Dictionary, dir: Vector3, detached := false) -> void:
	var before := part.alive_count
	var cut_off = null
	for lump in part.loose_lumps():
		var amputation: bool = not detached and part != torso and (part.near_child_anchor(lump) or lump.size() >= 0.4 * before or lump.size() == before)
		if amputation and (cut_off == null or lump.size() > cut_off.size()):
			cut_off = lump
		elif not amputation:
			var idx := Array(lump)
			res.removed.append({"part": part, "indices": idx, "voxels": part.remove_voxels(idx, false)})
	if cut_off == null and not detached and part != torso and part.alive_count == 0:
		cut_off = PackedInt32Array()
	if cut_off != null:
		sever(part, res, cut_off)
	elif not detached and part != torso and not part.hanging and part.thin_ratio() < float(mods.get("sever", 0.3)):
		hang(part, res)

func hang(part: VoxelPart, res: Dictionary) -> void:
	if part.hanging or part.severed:
		return
	part.hanging = true
	part.bleed += 3.0
	res.hanging = part
	for side in arm:
		if (part == arm[side].fore or part == arm[side].upper) and weapons[side]:
			release(side)
	if part == head:
		concussion = minf(1.0, concussion + 0.5)
	part.angular_damp = 2.0

## Cut through: the stump side stays on (removed from the falling piece), the piece with
## whatever hangs from it is no longer his.
func sever(part: VoxelPart, res: Dictionary, keep: PackedInt32Array) -> void:
	if part.severed:
		return
	var kept := {}
	for i in keep:
		kept[i] = true
	var stump_side := []
	for i in part.fx.size():
		if part.alive[i] and not kept.has(i):
			stump_side.append(i)
	if not stump_side.is_empty() and stump_side.size() < part.alive_count:
		res.removed.append({"part": part, "indices": stump_side, "voxels": part.remove_voxels(stump_side)})
	detach_limb(part, res)

func detach_limb(part: VoxelPart, res: Dictionary) -> void:
	var pieces := []
	var walk := func(p: VoxelPart, f: Callable) -> void:
		pieces.append(p)
		for c in p.child_parts:
			f.call(c, f)
	walk.call(part, walk)
	for p in pieces:
		p.severed = true
		p.hp = 0.0
		p.collision_layer = VoxelPart.LAYER_DEBRIS
		p.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS
		for o in parts:
			if not pieces.has(o):
				p.remove_collision_exception_with(o)
	if part.joint:
		part.joint.queue_free()
		part.joint = null
	if part.parent_part:
		part.parent_part.stump = true
		part.parent_part.stump_t = 0.0
	for side in arm:
		if pieces.has(arm[side].fore) and weapons[side]:
			release(side)
	res.severed.append(part)
	on_severed(part)

## What losing a part means (a man dies without his head; a hydra has others).
func on_severed(part: VoxelPart) -> void:
	if part == head:
		die("decap")

signal voxels_lost(fighter: Fighter, part_index: int, indices: Array, voxels: Array)

func on_part_voxels_lost(part: VoxelPart, indices: Array, out: Array) -> void:
	voxels_lost.emit(self, parts.find(part), indices, out)

## Freezes every body: a guest only draws what the host simulates.
func make_puppet() -> void:
	for p in parts:
		p.freeze = true
		p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	for w in weapons.values():
		if w:
			w.freeze = true
			w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

# ---------- Network ----------

## Positions and rotations of every part, for guests to draw.
func snapshot() -> Array:
	var out := []
	for p in parts:
		var t: Transform3D = p.global_transform
		var q := t.basis.get_rotation_quaternion()
		out.append([snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001), snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)])
	return out

func apply_snapshot(s: Array) -> void:
	for i in mini(s.size(), parts.size()):
		var a: Array = s[i]
		parts[i].global_transform = Transform3D(Basis(Quaternion(a[3], a[4], a[5], a[6])), Vector3(a[0], a[1], a[2]))

func status() -> Dictionary:
	return {"blood": snappedf(blood, 0.1), "stamina": snappedf(stamina, 0.1), "state": state, "hp": parts.map(func(p): return snappedf(p.hp, 0.1))}

func apply_status(s: Dictionary) -> void:
	blood = s.get("blood", blood)
	stamina = s.get("stamina", stamina)
	state = s.get("state", state)
	var hps: Array = s.get("hp", [])
	for i in mini(hps.size(), parts.size()):
		parts[i].hp = hps[i]

func total_hp() -> float:
	var t := 0.0
	for p in parts:
		t += p.hp
	return t
