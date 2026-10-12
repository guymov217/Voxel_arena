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
const CENTER_K := 3.0
const STANCE_K := 2.5   # how hard the hips are drawn over the foot that bears the weight
const FOOT_HOLD := 900.0  # a planted foot's grip on the sand
const LEG_WN := 30.0
## How much of the leg drive pushes back on the torso (Rapier's joint motors are solved with the
## joints; a torque drive's full reaction fights the balance when the body lies on its side).
const LEG_REACT := 0.35
const GRAVITY := 9.81
const UP := Vector3.UP
const GRIP_Q := Quaternion(Vector3(1, 0, 0), PI)
## A bow is not a blade (character.js BOW_Q): its arrow direction (+x) runs along the forearm
## toward the target and the stave (+y) stands across it.
const BOW_Q := Quaternion(Vector3(1, 0, 0), PI) * Quaternion(Vector3(0, 0, 1), PI / 2.0)

static func grip_q(w) -> Quaternion:
	return BOW_Q if w and str(w.design.get("shoots", "")) == "arrow" else GRIP_Q

static func is_bow(w) -> bool:
	return w != null and str(w.design.get("shoots", "")) == "arrow"
var behind_t := {"R": 0.0, "L": 0.0}
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
var body := {}                    # Body: old wounds, lost limbs, prosthetics, eyes (the campaign)
var fixed_hand := {"R": false, "L": false}   # a blade arm: the weapon cannot leave that hand
var eye_floor := 0.0
var stuck_load := 0.0              # the weight of the blades stuck in him               # an eye lost: the aim never quite steadies
var crawling := false
var eye_hurt := 0.0
var strip_clock := 0.0
var crawl_phase := 0.0
var stance_h := 0.0     # the hip height the planted leg gives (world y of the torso)
var hop_phase := 0.0   # on one leg he hops: 0..1 through each hop
var cut_force := 99.0   # how hard the blow being dealt with cut (J x hardness x sharpness)
var thrust_aim := {"R": null, "L": null}   # {dir, k}: a thrust's point toward the crosshair
var throw_anim = null            # {side, phase: "wind" | "follow", t}: the throwing arm's swing
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
var off_goal = null             # a world point the free off hand reaches for: a bow's string, a crossbow's to cock
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
	# A body does not pass through itself: only parts joined to each other (they overlap at the
	# joint) ignore one another, and the two legs while he is up (a stride brushes one past the
	# other). The joints have a body's limits, so a joined part cannot fold into its neighbour.
	for a in parts:
		for b in parts:
			if a != b and (a.parent_part == b or b.parent_part == a or (_is_leg(a) and _is_leg(b))):
				a.add_collision_exception_with(b)
	for p in parts:
		if p.parent_part:
			_make_pin(p)
	for p in parts:
		for id in loadout.get("armor", []):
			_add_armor(p, id)
	if opts.get("body") is Dictionary:
		apply_body(opts.body)
	var main = loadout.get("main")
	var off = loadout.get("off")
	# A blade arm carries its own blade; a hook carries nothing.
	for side in ["R", "L"]:
		var fore: VoxelPart = arm[side].fore
		if fore.prosthetic == "blade":
			equip(side, BLADE_ARM)
			fixed_hand[side] = true
		if fore.prosthetic != "":
			if side == "R":
				main = null
			else:
				off = null
	if main is String:
		main = Data.preset(main)
	if off is String:
		off = Data.preset(off)
	if main is Dictionary and not main.is_empty():
		equip("R", main)
		if main.get("twoHanded", false) and arm.L.fore.prosthetic == "" and not arm.L.fore.missing:
			two_handed = true
			_attach_off_hand(weapons.R)
	if off is Dictionary and not off.is_empty() and not two_handed and not weapons.L:
		equip("L", off)

## The blade the physician rivets to a stump: a short, broad iron blade on a socket.
const BLADE_ARM := {"name": "Blade arm", "kind": "weapon", "sharpness": 0.85, "voxels": [
	[0, 0, 0, "iron", "grip"], [0, 1, 0, "iron", "grip"], [0, 2, 0, "iron", "grip"], [-1, 3, 0, "iron", "blunt"], [0, 3, 0, "iron", "blunt"], [1, 3, 0, "iron", "blunt"],
	[0, 4, 0, "steel", "edge"], [0, 5, 0, "steel", "edge"], [0, 6, 0, "steel", "edge"], [0, 7, 0, "steel", "edge"], [0, 8, 0, "steel", "edge"], [0, 9, 0, "steel", "edge"],
	[0, 10, 0, "steel", "edge"], [0, 11, 0, "steel", "edge"], [0, 12, 0, "steel", "edge"], [0, 13, 0, "steel", "edge"], [0, 14, 0, "steel", "edge"], [0, 15, 0, "steel", "edge"],
	[0, 16, 0, "steel", "edge"], [0, 17, 0, "steel", "edge"], [0, 18, 0, "steel", "point"]]}

## The body a campaign has left him (Body): old wounds as healed dents, lost limbs gone with
## their stumps closed, prosthetics where the physician fitted them, a lost or a glass eye.
func apply_body(b: Dictionary) -> void:
	body = Body.sanitize(b)
	for n in body.scars:
		var p: VoxelPart = by_name.get(n)
		if p:
			p.scar(body.scars[n])
	for n in body.missing:
		var p: VoxelPart = by_name.get(n)
		if p and not p.missing:
			_make_missing(p)
	for n in body.prosthetics:
		var p: VoxelPart = by_name.get(n)
		if p:
			_fit_prosthetic(p, String(body.prosthetics[n]))
	for s in body.eyes:
		var ev := Body.eye_voxels(head, s)
		if body.eyes[s] == "glass":
			for i in ev:
				head.colors[i] = Color(0.86, 0.9, 0.95) if head.fy[i] % 2 == 1 else Color(0.25, 0.42, 0.6)
			head.refresh_colors(ev)
			eye_floor += 0.08
		else:
			head.scar(ev)
			eye_floor += 0.3
	for p in parts:
		if p.alive_count < p.fx.size() or p.prosthetic != "":
			p.resync_later()

## A limb lost in an earlier fight: not there at all, and the stump long since healed.
func _make_missing(part: VoxelPart) -> void:
	var stack := [part]
	while not stack.is_empty():
		var p: VoxelPart = stack.pop_back()
		p.missing = true
		p.severed = true
		p.hp = 0.0
		p.visible = false
		p.freeze = true
		p.collision_layer = 0
		p.collision_mask = 0
		if p.joint:
			p.joint.queue_free()
			p.joint = null
		stack.append_array(p.child_parts)
	var par: VoxelPart = part.parent_part
	if par and not par.missing:
		var pt := par.anchor_point(part)
		var r := par.vf * par.part_scale * 2.6
		var near := []
		for i in par.fx.size():
			if par.alive[i] and par.local_of(i).distance_to(pt) < r:
				par.colors[i] = par.colors[i].lerp(VoxelPart.SCAR, 0.6)
				near.append(i)
		par.refresh_colors(near)

## A prosthetic in the part's place: the part is reshaped (wood or iron, thinner) and works
## only so well (VoxelPart.function), and it does not bleed.
func _fit_prosthetic(p: VoxelPart, kind: String) -> void:
	p.prosthetic = kind
	p.missing = false
	var cx := (p.grid.x - 1) * 0.5
	var cz := (p.grid.z - 1) * 0.5
	var top := p.grid.y - 1
	var cuff_from := int(top * 0.72)
	var drop := []
	var paint := []
	for i in p.fx.size():
		var dx := absf(p.fx[i] - cx)
		var dz := absf(p.fz[i] - cz)
		var y: int = p.fy[i]
		if y >= cuff_from:
			# The leather cuff strapped over the stump, an iron band round it.
			p.colors[i] = Color(0.33, 0.21, 0.11) if y != cuff_from else Color(0.45, 0.47, 0.5)
			paint.append(i)
			continue
		var keep := false
		match kind:
			"peg":
				keep = dx < 1.3 and dz < 1.3 or (y > cuff_from - 3 and dx < 2.2 and dz < 2.2)
				if keep:
					p.colors[i] = Color(0.55, 0.38, 0.2) if (y / 2) % 2 == 0 else Color(0.48, 0.32, 0.17)
			"hook":
				var rod := dx < 0.8 and dz < 0.8 and y > 3
				var curve := y <= 3 and dx < 0.8 and p.fz[i] >= cz and p.fz[i] - cz < 3.0 - absf(y - 1.5)
				keep = rod or curve
				if keep:
					p.colors[i] = Color(0.5, 0.52, 0.56)
			"blade":
				keep = dx < 1.3 and dz < 1.3 and y > top * 0.35
				if keep:
					p.colors[i] = Color(0.42, 0.44, 0.48)
		if keep:
			paint.append(i)
		else:
			drop.append(i)
	p.refresh_colors(paint)
	p.remove_voxels(drop, false)
	p.bleed = 0.0

static func _is_leg(p) -> bool:
	return String(p.part_name).begins_with("thigh") or String(p.part_name).begins_with("shin")

## Down or dead the legs are a ragdoll's: they knock against each other instead of passing.
func _legs_apart(on: bool) -> void:
	for a in parts:
		if not _is_leg(a) or a.severed:
			continue
		for b in parts:
			if b == a or not _is_leg(b) or b.severed or a.parent_part == b or b.parent_part == a:
				continue
			if String(a.part_name).right(1) == String(b.part_name).right(1):
				continue
			if on:
				a.remove_collision_exception_with(b)
			else:
				a.add_collision_exception_with(b)

## Joint limits, in the parent's frame at rest (everything hanging straight down), in the sense
## Godot's 6DOF joint measures them (the bend of an elbow is +x). [x, y, z] as [lo, hi].
const JOINT_LIMITS := {
	"head": [[-0.55, 0.65], [-1.25, 1.25], [-0.45, 0.45]],
	"thigh": [[-0.6, 2.2], [-0.7, 0.7], [-0.75, 0.75]],
	"shin": [[-2.5, 0.05], [-0.25, 0.25], [-0.06, 0.06]],
}

func _make_pin(p: VoxelPart) -> void:
	var n := String(p.part_name)
	if n.begins_with("forearm"):
		_make_elbow(p)
		return
	var key := "head" if n == "head" else ("thigh" if n.begins_with("thigh") else ("shin" if n.begins_with("shin") else ""))
	if key != "":
		_make_limited(p, JOINT_LIMITS[key])
		return
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = p.parent_part.global_transform * p.pa
	j.node_a = p.parent_part.get_path()
	j.node_b = p.get_path()
	p.joint = j

func _make_limited(p: VoxelPart, lim: Array) -> void:
	var j := Generic6DOFJoint3D.new()
	add_child(j)
	j.global_transform = Transform3D(p.parent_part.global_transform.basis.orthonormalized(), p.parent_part.global_transform * p.pa)
	j.node_a = p.parent_part.get_path()
	j.node_b = p.get_path()
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[0][0])
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[0][1])
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[1][0])
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[1][1])
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[2][0])
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[2][1])
	p.joint = j

func _lock_elbow_straight(side: String, on: bool) -> void:
	var fore: VoxelPart = arm[side].fore
	var upper: VoxelPart = arm[side].upper
	if not (fore.joint is Generic6DOFJoint3D) or fore.severed or upper.severed or fore.hanging or upper.hanging:
		return
	if bool(fore.get_meta("elbow_locked", false)) == on:
		return
	fore.set_meta("elbow_locked", on)
	var j: Generic6DOFJoint3D = fore.joint
	if on:
		# Snap it straight first, as the joint's frame is the straight arm.
		var uq := PD.quat_of(upper)
		var elbow: Vector3 = upper.global_transform * fore.pa
		fore.global_transform = Transform3D(Basis(uq), elbow - uq * fore.ca)
		fore.angular_velocity = upper.angular_velocity
		fore.linear_velocity = upper.velocity_at(elbow)
		for ax in ["x", "y", "z"]:
			j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.01)
			j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.01)
	else:
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.05)
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_BEND)
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -ELBOW_TURN)
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_TURN)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.06)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.06)

## The elbow is a hinge, not a ball: the forearm bends forward (up to ~150 degrees) and turns
## about its own length (the wrist, +-75), but it cannot swing sideways or spin round the upper
## arm. So a swung weapon is carried by the whole arm instead of flapping on a loose joint.
## The joint frame is the upper arm's at rest (arm straight down): x is the hinge.
const ELBOW_BEND := 2.6
const ELBOW_TURN := 1.3
func _make_elbow(p: VoxelPart) -> void:
	var j := Generic6DOFJoint3D.new()
	add_child(j)
	j.global_transform = Transform3D(p.parent_part.global_transform.basis.orthonormalized(), p.parent_part.global_transform * p.pa)
	j.node_a = p.parent_part.get_path()
	j.node_b = p.get_path()
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.05)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_BEND)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -ELBOW_TURN)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_TURN)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.06)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.06)
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
	# A fixed box: plates knocked off one by one must not shrink it and cull the rest.
	var ext := Vector3(p.dims.x + 2, p.dims.y + 2, p.dims.z + 2) * V * S * 0.5
	inst.custom_aabb = AABB(-ext, ext * 2.0)
	mmesh.custom_aabb = inst.custom_aabb
	inst.name = "Armor_" + id
	p.add_child(inst)
	var pts := []
	for c in cells:
		pts.append(Vector3(c[0] - (p.dims.x - 1) * 0.5, c[1] - (p.dims.y - 1) * 0.5, c[2] - (p.dims.z - 1) * 0.5) * V * S)
	var on := PackedByteArray()
	on.resize(cells.size())
	on.fill(1)
	p.set_meta("armor", p.get_meta("armor", []) + [{"id": id, "mat": a.get("mat", "iron"), "cells": cells, "pts": pts, "on": on, "alive": cells.size(), "node": inst}])

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
		rot = PD.quat_of(fore) * grip_q(w)
	var hand := hand_world(side)
	w.global_transform = Transform3D(Basis(rot), hand - rot * w.grip_main)
	w.build_chain()
	_exempt(w)
	w.set_held_by(self)
	weapons[side] = w
	weapon_joints[side] = _grip_joint(fore, w, hand)
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

## The hand on a weapon: a shield hangs on a pin; a blade is held fast but for the wrist, which
## turns it about its own length (the wheel sets the edge, _drive_wrist turns it there). A
## bow, a crossbow or a chain weapon is simply held fast.
func _grip_joint(fore: VoxelPart, w: Weapon, hand: Vector3) -> Joint3D:
	if w.is_shield:
		return _joint_at(fore, w, hand, false)
	var j := Generic6DOFJoint3D.new()
	add_child(j)
	if has_wrist(w):
		var ax := PD.quat_of(w) * Vector3.UP
		var o := ax.cross(Vector3.FORWARD if absf(ax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		j.global_transform = Transform3D(Basis(ax, o, ax.cross(o)), hand)
		j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
	else:
		j.global_position = hand
	j.node_a = fore.get_path()
	j.node_b = w.get_path()
	return j

static func has_wrist(w) -> bool:
	return w != null and not w.is_shield and not w.design.has("shoots") and w.design.get("chain") == null

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
	if not w or is_bow(w):
		return   # the off hand of an archer draws the string; it does not hold the stave
	var fore: VoxelPart = arm.L.fore
	var at := w.global_transform * w.grip_off
	fore.global_position += at - hand_world("L")
	weapon_joints.L = _joint_at(fore, w, at, false)

func release(side: String) -> Weapon:
	var w: Weapon = weapons[side]
	if not w:
		return null
	if fixed_hand[side] and not arm[side].fore.severed:
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

## H: the off hand takes hold of the main weapon's haft too, or lets go of it (character.js
## toggleGrip). Two hands: more power and better control of a heavy weapon; one: the off hand
## is free. Returns "one", "two" or null.
func toggle_grip() -> Variant:
	var w: Weapon = weapons.R
	if not w or w.is_shield or not alive or w.design.get("chain") != null:
		return null
	if two_handed:
		if weapon_joints.L:
			weapon_joints.L.queue_free()
			weapon_joints.L = null
		two_handed = false
		return "one"
	var fore: VoxelPart = arm.L.fore
	if weapons.L or fore.severed or fore.hanging or fore.missing or fore.prosthetic != "" or arm.L.upper.severed or arm.L.upper.hanging or fixed_hand.R:
		return null
	two_handed = true
	_attach_off_hand(w)
	return "two"

## J: what is in each hand changes hands (a sword to the left, a shield to the right, or the
## one weapon across to the empty hand). Not with both hands on one haft, an arm gone or a
## weapon fixed to a stump. Returns true if anything moved.
func swap_hands() -> bool:
	if not alive or two_handed or held_item != null or (not weapons.R and not weapons.L):
		return false
	for side in ["R", "L"]:
		var fore: VoxelPart = arm[side].fore
		if fixed_hand[side] or fore.severed or fore.hanging or fore.missing or fore.prosthetic != "" or arm[side].upper.severed or arm[side].upper.hanging:
			return false
	var r := release("R")
	var l := release("L")
	for pair in [[r, "L"], [l, "R"]]:
		var w = pair[0]
		if w:
			w.own_t = 0.0
			if Combat.current:
				Combat.current.loose_weapons.erase(w)
			pick_up(pair[1], w)
	# A two-hander that crossed to the right takes the off hand back onto its haft.
	return true

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
	if weapons[side] or fore.severed or fore.missing or fore.prosthetic != "":
		return false
	if w.own_by and is_instance_valid(w.own_by) and w.own_by != self:
		w.forget_owner()
	if w.stuck != null:
		w.unstick()
	var rot: Quaternion = Quaternion(UP, yaw) if w.is_shield else PD.quat_of(fore) * grip_q(w)
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
	weapon_joints[side] = _grip_joint(fore, w, hand)
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
	var v_hand := (31.0 if javelin else 24.0) * sqrt(S) * float(mods.strength) * (0.5 + 0.5 * arm_f) * (1.0 - 0.5 * injury) * (0.4 + 0.6 * power) * tired
	var v := minf(38.0, v_hand * sqrt(m_arm / (m_arm + maxf(0.05, mass_))))
	var d := aim_at - from
	var dx := maxf(0.01, Vector2(d.x, d.z).length())
	var dy := d.y
	var g := gravity
	var disc := pow(v, 4) - g * (g * dx * dx + 2.0 * dy * v * v)
	# Out of reach (a mark on the far wall, the sky, a weak throw): it goes along the line it was
	# aimed, a little above it, never off on a 45-degree lob somewhere else.
	var theta := atan2(v * v - sqrt(disc), g * dx) if disc >= 0.0 else atan2(dy, dx) + 0.05
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
	if not w or w.is_shield or (side == "L" and two_handed) or fixed_hand[side]:
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
	else:
		# A spear flies straight; anything else (an axe, a sword, a chair) turns end over end in
		# the plane it flies in: blade up, spinning about the side axis, a heavy one slower.
		var sd := vel.cross(UP)
		sd = Vector3(1, 0, 0) if sd.length_squared() < 1e-6 else sd.normalized()
		var fw := Vector3(vel.x, 0, vel.z).normalized()
		var q := PD.quat_from_axes(UP.cross(sd).normalized(), UP, sd)
		if (q * Vector3(1, 0, 0)).dot(fw) < 0.0:
			q = q * Quaternion(UP, PI)
		w.global_transform = Transform3D(Basis(q), from - q * w.center_of_mass)
		w.angular_damp = 0.03
		var spin := 15.5 if Weapon.spins_in_flight(w.design) else clampf(5.0 + 9.0 / sqrt(maxf(0.3, w.mass)), 6.0, 15.5)
		# A thrower times the turns to the distance (axe throwing): whole turns over the flight,
		# so the blade comes round edge first at the mark. A hurried, weak throw misjudges it.
		var hs := Vector2(vel.x, vel.z).length()
		if hs > 0.5:
			# It lands when its head reaches the front of the man, not when it gets to his middle.
			var span: float = w.mm.get_aabb().size.y * 0.5 if w.mm else 0.3
			var tof := maxf(0.02, Vector2(aim_at.x - from.x, aim_at.z - from.z).length() - span - 0.12) / hs
			var turns := roundf(spin * tof / TAU)
			if turns >= 1.0:
				spin = clampf(TAU * turns / tof, 4.0, 20.0)
			elif tof > 0.05:
				spin = clampf(TAU * 0.04 / tof, 0.0, 4.0)   # too close for a turn: thrown flat, edge on
			spin *= 1.0 + randf_range(-1.0, 1.0) * (0.03 + 0.12 * (1.0 - power) + 0.1 * (1.0 - arm_f))
		w.angular_velocity = sd * -spin
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

## Whether the legs can hold him up: one good leg will do (he hops), two battered ones will
## not; neither will bleeding out or a head too rung to balance. Down, he crawls.
func can_stand() -> bool:
	var l := leg_func("L")
	var r := leg_func("R")
	if bool(mods.get("cyclops", false)) and (l <= 0.0 or r <= 0.0):
		return false
	return state != "dead" and (l > 0.15 or r > 0.15) and (l + r) * 0.5 > 0.3 and blood > 18.0 and concussion < 0.85

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

## The legs' joint drive (character.js motorRel, which used Rapier's implicit motors). A torque
## PD stepped at 120 Hz with the leg's gains chattered every frame (the knee's acceleration
## flipped sign at the step rate, so the legs shook and the feet skated). This one steers the
## joint's relative angular velocity toward a target set by the angle error and closes only part
## of the gap each step, so it can never overshoot and never chatters, however stiff.
func motor_rel(part: VoxelPart, parent: VoxelPart, rel_q: Quaternion, wn: float, max_t: float, dt: float, react := 1.0) -> void:
	if part.severed or wn <= 0.0:
		return
	var desired := PD.quat_of(parent) * rel_q
	var err := PD.rot_error(desired, PD.quat_of(part))
	var rel := part.angular_velocity - parent.angular_velocity
	var v_des := PD.clamp_len(err * wn, 16.0)
	var tq := PD.torque_for(part, (v_des - rel) / dt, 1.0) * 0.6
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
	if throw_anim != null:
		throw_anim.t -= dt
		if throw_anim.t <= 0.0:
			throw_anim = null
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
	if inp.get("grip", false) and state == "stand":
		toggle_grip()
	if inp.get("swap", false) and state == "stand":
		swap_hands()
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
	eye_hurt = maxf(eye_floor, eye_hurt - dt * 0.01)
	_tear_strips(dt)
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
	# On one leg he cannot walk: he hops, a push off the good leg and a short flight, and only
	# the push moves him on. Standing on it he sways, catching his balance.
	var hop_k := 0.0
	var wants_move := Vector2(float(inp.get("mx", 0.0)), float(inp.get("mz", 0.0))).length_squared() > 0.05
	if one_leg and standing and not rising and wants_move:
		hop_phase = fmod(hop_phase + dt * 2.3 * (0.6 + 0.4 * stamina / 100.0), 1.0)
		hop_k = maxf(0.0, sin(hop_phase * TAU))
		bob = 0.22 * S * hop_k
		stamina_use += 4.0 * dt
	else:
		hop_phase = 0.0
	var grounded := false
	var ground_y := 0.0
	if hit:
		var dist = t_pos.y - hit.position.y
		ground_y = hit.position.y
		var run_low := 0.06 * minf(1.0, walk_amt * 2.5 / 3.5)
		var desired := torso_y * (0.95 - run_low) * (1.0 - crouch * 0.22 - (0.12 if one_leg else 0.0)) * (0.7 + 0.3 * support) * (0.55 + 0.45 * e2 if rising else 1.0) + bob
		# The weight is on the leg that is down: the hips ride as high as that leg, a little bent,
		# reaches from the foot planted on the sand to the hip (an inverted pendulum: up as the body
		# passes over the foot, down as the stride opens). Never higher than the legs reach, so
		# a planted foot always stands on the sand.
		if state == "stand" and not one_leg and hop_phase <= 0.0:
			var pend := INF
			var reach_l := 16.0 * V * S * (0.965 - crouch * 0.12 - run_low * 0.5)
			for sd in ["L", "R"]:
				var ftp = feet[sd]
				if ftp == null or ftp.swing or by_name["shin" + sd].severed:
					continue
				var hip_w: Vector3 = t_pos + t_rot * by_name["thigh" + sd].pa
				var dxz := Vector2(hip_w.x - ftp.anchor.x, hip_w.z - ftp.anchor.z).length()
				var hh := sqrt(maxf(0.0, reach_l * reach_l - dxz * dxz))
				pend = minf(pend, ground_y + hh + (t_pos.y - hip_w.y))
			if pend < INF:
				stance_h = maxf(pend, ground_y + torso_y * (0.82 - crouch * 0.2))
			if stance_h > 0.0:
				desired = minf(desired, stance_h - ground_y) if pend < INF else desired
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
	var speed := (3.8 if sprint else 2.1) * sqrt(S) * float(mods.speed) * (0.3 if one_leg else 0.4 + 0.6 * leg_avg) * blood_f * heavy * (1.0 - crouch * 0.45) / (1.0 + carrying * 0.9 + 0.05 * stuck_load) * (slow_factor if slow_timer > 0.0 else 1.0) * (0.25 if net_timer > 0.0 else 1.0)
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
		# The weight sits over the feet: with both planted, the hips are drawn over the point
		# between them (standing still, every way; walking, only sideways, which also keeps the
		# walk straight). Godot's joint torques, unlike Rapier's motors, let the body creep off
		# its feet and glide as if it hovered.
		# On one foot the weight goes over it: the hips swing across to stand above it.
		if planted == 1 and move_local.length_squared() > 0.01:
			for sd in ["L", "R"]:
				var fs = feet[sd]
				if fs and not fs.swing and not by_name["shin" + sd].severed:
					var side_w2 := yaw_q * Vector3(1, 0, 0)
					var off1 := Vector3(fs.anchor.x - t_pos.x, 0, fs.anchor.z - t_pos.z)
					move_world += PD.clamp_len(side_w2 * off1.dot(side_w2) * 0.6 * STANCE_K, 0.25)
		if planted == 2 and feet.L and feet.R:
			var mid: Vector3 = ((feet.L.anchor as Vector3) + (feet.R.anchor as Vector3)) * 0.5
			var off := Vector3(mid.x - t_pos.x, 0, mid.z - t_pos.z)
			if move_local.length_squared() > 0.01:
				var side_w := yaw_q * Vector3(1, 0, 0)
				off = side_w * off.dot(side_w)
			move_world += PD.clamp_len(off * CENTER_K, 1.0)
	if grounded and standing:
		# He moves himself by pushing off the sand: with no foot down there is next to nothing to push on.
		var accel := (2.5 + 18.5 * minf(1, planted)) * stand_f * float(mods.accel) * (0.55 + 0.45 * heavy)
		if one_leg:
			accel *= (0.2 + 2.2 * hop_k) if hop_phase > 0.0 else 1.0
		var ix := Vector2(move_world.x - lv.x, move_world.z - lv.z).limit_length(6.0) * accel * total_mass * dt
		torso.apply_central_impulse(Vector3(ix.x, 0, ix.y))
		if sprint:
			stamina_use += 10.0 * dt
		if inp.get("jump", false) and stamina > 15.0:
			torso.apply_central_impulse(Vector3(0, total_mass * 4.2 * maxf(0.3, leg_avg), 0))
			stamina -= 15.0
	# Down but alive: drag yourself along on your arms, slowly, slower still the worse you are.
	crawling = false
	if live and state == "down" and grounded and move_local.length_squared() > 0.05 and net_timer <= 0.0:
		var crawl_speed := 0.75 * sqrt(S) * (0.35 + 0.65 * heavy) * (0.5 + 0.5 * (arm_func("L") + arm_func("R")) * 0.5)
		var cw: Vector3 = yaw_q * move_local * crawl_speed
		var ixc := Vector2(cw.x - lv.x, cw.z - lv.z).limit_length(3.0) * 26.0 * total_mass * dt
		torso.apply_central_impulse(Vector3(ixc.x, 0, ixc.y))
		crawl_phase += dt * 4.5
		crawling = true
		stamina_use += 3.0 * dt
	v_smooth = v_smooth.lerp(Vector3(lv.x, 0, lv.z), minf(1.0, dt * 10.0))
	var h_speed := Vector2(v_smooth.x, v_smooth.z).length()
	var step_len: float = (minf(1.0, 0.3 + 0.17 * h_speed) if sprint else minf(0.66, 0.28 + 0.12 * h_speed)) * S
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
			var sway := 7.0 if one_leg else 1.0
			lean = Quaternion(Vector3(0, 0, 1), 0.01 * sway * sin(time * 0.6 * sqrt(sway) + slot * 2)) * Quaternion(Vector3(1, 0, 0), 0.012 * sway * sin(time * 0.9 * sqrt(sway) + slot)) * lean
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
			if hop_phase > 0.0:
				# Hopping: the good foot stays under him, leaves the sand at the top of each hop
				# and lands a little ahead; the stump does not step.
				ft.swing = false
				ft.anchor = neutral + move_dir * step_len * 0.25
				if leg_func(side) < 0.1:
					ft.anchor = (ft.anchor as Vector3) + Vector3(0, 0.25 * S, 0)
				ft.from = ft.anchor
				ft.land = ft.anchor
			elif moving and my_swing and not ft.swing and ft.half != half:
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
			elif ft.slip > ((0.5 if sprint else 0.3) if moving else 0.18) * S:
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
			if hop_phase > 0.0 and hop_k > 0.6:
				target.y += (hop_k - 0.6) * 0.2 * S   # the foot tucks up at the top of the hop
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
		# A foot down holds the sand (friction): it stays where it was put while the body goes
		# over it, instead of skating along under it.
		if standing and grounded and not kicking and feet[side] and not feet[side].swing and not shin.severed and not shin.hanging and not rising:
			var sole := shin.global_transform * Vector3(0, -4 * V * S, 0)
			var goal: Vector3 = feet[side].anchor
			var sv := shin.velocity_at(sole)
			var fh := Vector3((goal.x - sole.x) * FOOT_HOLD - sv.x * 60.0, minf(0.0, (goal.y - sole.y) * FOOT_HOLD - sv.y * 60.0), (goal.z - sole.z) * FOOT_HOLD - sv.z * 60.0)
			fh = PD.clamp_len(fh * (shin.nominal_mass + thigh.nominal_mass * 0.5), 260.0 * f * MS * S)
			shin.apply_impulse(fh * dt, sole - shin.global_position)
		motor_rel(thigh, torso, thigh_q, LEG_WN * sqrt(f), (1400.0 if snap else 900.0) * f * MS * S, dt, LEG_REACT)
		if not shin.severed and not shin.hanging:
			motor_rel(shin, thigh, Quaternion(Vector3(1, 0, 0), bend), LEG_WN * sqrt(f), (700.0 if snap else 600.0) * f * MS * S, dt)

	# ----- Arms and weapons -----
	var power: bool = inp.get("power", false) and stamina > 3.0
	if power:
		stamina_use += 9.0 * dt
	for side in ["R", "L"]:
		_drive_arm(side, inp, live and not limp, power, stam_f, blood_f, t_pos, t_rot, yaw_q, dt)
		# Whatever the arm is doing (swinging, limp, hanging by a strip, on a corpse), it never
		# passes into its own chest or head.
		if not arm[side].upper.severed:
			_keep_arm_out(side, dt)

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
	if side == "L" and two_handed and not (off_goal != null and is_bow(weapons.R)):
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
	# A fist is thrown with a straight arm (character.js lockElbowOf): an empty hand with its
	# button held, or a jab, locks the elbow rigid, so the forearm goes where the upper arm
	# drives it and the punch lands with the whole arm behind it.
	_lock_elbow_straight(side, not w and state == "stand" and (power or jab_t[side] > 0.0) and af > 0.25 and held_item == null and not crawling)
	var down_hp = {"x": 0.4 if side == "R" else -0.4, "y": -0.5} if state != "stand" else ({"x": 0.25 if side == "R" else -0.25, "y": 0.35} if shove_t > 0.0 else null)
	if crawling:
		# The arms reach ahead and haul, one after the other.
		down_hp = {"x": 0.35 if side == "R" else -0.35, "y": 0.55 + 0.45 * sin(crawl_phase + (0.0 if side == "R" else PI))}
		thrust = 0.5
	# Throwing: drawn back high behind the shoulder while F is held (further the longer it is
	# held) or a bot winds up, then whipped forward and across in the follow-through.
	var t_side := ("L" if not weapons.L else "R") if held_item != null else ("R" if weapons.R and not weapons.R.is_shield else "L")
	var ta = throw_anim
	var charging := float(inp.get("charging", 0.0))
	var winding: bool = (ta != null and ta.side == side and ta.phase == "wind") or (ta == null and side == t_side and charging > 0.0 and state == "stand")
	var following: bool = ta != null and ta.side == side and ta.phase == "follow"
	if down_hp == null and (winding or following):
		down_hp = {"x": (0.55 if side == "R" else -0.55), "y": 1.5} if winding else {"x": (-0.7 if side == "R" else 0.7), "y": -0.25}
		thrust = -1.5 * maxf(0.5, charging if ta == null else 1.0 - ta.t / 0.45) if winding else 1.3
	var hp_used: Dictionary = down_hp if down_hp != null else hp
	# A bow is held out at the shoulder, stave upright, whatever the mouse does.
	if down_hp == null and side == "R" and w and w.design.has("shoots"):
		var ap := _shoot_pitch(inp)
		hp_used = {"x": 0.3 if is_bow(w) else 0.15, "y": clampf((0.45 if is_bow(w) else 0.38) + ap * 0.9, -0.4, 1.4)}
		thrust = 0.6 if is_bow(w) else 0.3
	hand_input[side] = hp_used
	var target := hand_target_local(side, hp_used, thrust)
	# A hurt arm trembles and wanders, more the worse it is; a hurt eye throws the aim off too.
	var arm_hurt := 1.0 - minf(1.0, arm_func(side) / 0.85)
	var shake := maxf(0.0, arm_hurt - 0.1) * 0.09 + eye_hurt * 0.04
	if shake > 0.002:
		target.x += (sin(time * 13.7 + slot * 3) + 0.5 * sin(time * 29.3)) * shake * S
		target.y += (cos(time * 11.1 + side.length()) + 0.5 * sin(time * 23.9)) * shake * S
	if concussion > 0.1:
		target.x += sin(time * 3.1 + slot) * concussion * 0.25
		target.y += cos(time * 2.3) * concussion * 0.2
	target = _clear_body(target, yaw_q, t_pos)
	var target_w := t_pos + yaw_q * target
	# A thrust goes where the crosshair is: the hand reaches out toward that point (in front of
	# the body, at most well up or down) and the point of the blade leads it there.
	thrust_aim[side] = null
	var aim_at = inp.get("aimAt")
	if aim_at is Vector3 and thrust > 0.05 and w and not w.is_shield and not w.design.has("shoots") and down_hp == null:
		var sh_w: Vector3 = t_pos + t_rot * shoulder[side]
		var td: Vector3 = yaw_q.inverse() * ((aim_at as Vector3) - sh_w)
		if td.length_squared() > 1e-4:
			td = td.normalized()
			td.z = maxf(td.z, 0.35)
			td.y = clampf(td.y, -0.75, 0.75)
			td = yaw_q * td.normalized()
			var k := clampf(thrust, 0.0, 1.0)
			target_w = target_w.lerp(sh_w + td * arm_reach, k)
			thrust_aim[side] = {"dir": ((aim_at as Vector3) - target_w).normalized().slerp(td, 0.3).normalized(), "k": k}
	# The off hand at work on a bow or a crossbow: on the string, wherever that is.
	if side == "L" and off_goal != null and not w and down_hp == null:
		target_w = off_goal
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
	if fixed_hand[side]:
		hnd *= 0.6   # no wrist, no fingers: the blade goes where the stump drags it
	handling[side] = hnd
	var hand_goal := target_w
	var shoulder_w = t_pos + t_rot * shoulder[side]
	var dir = (target_w - shoulder_w).normalized()
	if w and not w.is_shield and weapon_joints[side]:
		var w_aim := weapon_aim(side, w, target_w, t_pos, yaw_q, inp, dt)
		var fore_q := w_aim * grip_q(w).inverse()
		var fore_dir := fore_q * Vector3(0, -1, 0)
		var lu := UPPER_LEN * S
		var lf := FORE_LEN * S
		var side_sign := -1.0 if side == "R" else 1.0
		var e_local = t_rot.inverse() * (target_w - fore_dir * lf - shoulder_w)
		if e_local.length_squared() < 1e-6:
			e_local = Vector3(side_sign * 0.3, -1, -0.3)
		e_local = e_local.normalized().lerp(Vector3(side_sign * 0.5, -0.7, -0.5).normalized(), 0.06 if two_handed else 0.18).normalized()
		# The elbow never folds in through the chest: in the body's frame it stays on its own
		# side of the shoulder (at most 0.22 S across the shoulder line) and at most 0.12 S above it.
		var elbow_dir = _elbow_dir(side, e_local, lu, t_rot)
		var elbow = shoulder_w + elbow_dir * lu
		hand_goal = elbow + fore_dir * lf
		var m_load := (fore.nominal_mass + w.mass) * lu * lu
		var k_up := 1.0 + m_load / PD.inertia_of(upper)
		pd_axis(upper, Vector3(0, -1, 0), elbow_dir, 16.0, 1.0, 260.0 * af * MS * S, dt, minf(5.0 if two_handed else 12.0, k_up))
		pd_twist(upper, torso, 1.5 * MS, 0.25 * MS, 12.0 * MS, dt)
		_drive_forearm(side, w, fore_q, strength, dt)
		_lock_elbow(side, w, fore_q, strength, dt)
		if has_wrist(w):
			_drive_wrist(side, w, w_aim, strength, dt)
		_unjam_blade(side, w, fore_q, t_pos, t_rot, dt)
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
		# A shield or an empty hand: the same elbow as a weapon arm, mirrored for the left, so
		# the arm never folds in through the chest whichever hand it is.
		var lu := UPPER_LEN * S
		var e_dir := _elbow_dir(side, t_rot.inverse() * (dir + Vector3(0, -0.35, 0)).normalized(), lu, t_rot)
		var elbow = shoulder_w + e_dir * lu
		var f_dir = (target_w - elbow).normalized() if (target_w - elbow).length_squared() > 1e-6 else dir
		pd_axis(upper, Vector3(0, -1, 0), e_dir, 14.0, 0.8, 90.0 * af * MS * S, dt)
		pd_axis(fore, Vector3(0, -1, 0), f_dir, 10.0, 0.8, 60.0 * af * MS * S, dt)
		pd_twist(upper, torso, 1.5 * MS, 0.25 * MS, 12.0 * MS, dt)
		pd_twist(fore, upper, 1.0 * MS, 0.2 * MS, 8.0 * MS, dt)
		if w and w.is_shield:
			_orient_shield(w, target_w, t_pos, yaw_q, strength, dt)
	# Damped to the critical whatever the weapon weighs (a heavy head once got less damping and
	# the arm bounced it about like a whip): the hand settles on its mark instead of overshooting.
	var kd := 2.1 * sqrt(300.0 * (0.5 + 0.5 * hnd)) * (1.1 if power else 1.0)
	var F = ((hand_goal - hand_w) * (300.0 * (0.5 + 0.5 * hnd)) + (target_vel[side] - hand_vel) * kd) * m_eff
	F.y += m_eff * gravity * minf(1.0, af * 1.2)
	F = PD.clamp_len(F, 1150.0 * strength * MS * float(mods.strength) * (0.55 + 0.45 * hnd) * (1.0 + 0.35 * (1.0 - hnd)) * (2.2 if not w and jab_t[side] > 0.0 else 1.0))
	fore.apply_impulse(F * dt, hand_w - fore.global_position)
	torso.apply_central_impulse(Vector3(-F.x * dt * 0.35, 0, -F.z * dt * 0.35))
	if w and w.holder == self and not w.is_shield:
		_keep_weapon_out(w, dt)

## An arm never passes through its own chest or head (the body's parts do not collide with each
## other): the elbow, the forearm and the hand are pushed back out of the torso and the head,
## out the front, or out to the arm's own side if they are behind the middle.
const ARM_OUT_K := 900.0
func _keep_arm_out(side: String, dt: float) -> void:
	var up: VoxelPart = arm[side].upper
	var fo: VoxelPart = arm[side].fore
	var out_x := -1.0 if side == "R" else 1.0
	var pts := [[up, up.global_transform * Vector3(0, -up.half_ext.y, 0)], [up, up.global_position]]
	if not fo.severed:
		pts.append_array([[fo, fo.global_position], [fo, hand_world(side)]])
	for body in [torso, head]:
		if body.severed:
			continue
		var bt: Transform3D = body.global_transform
		var bq := PD.quat_of(body)
		var e: Vector3 = body.half_ext + Vector3(0.02, 0.0, 0.02) * S
		for pp in pts:
			var l: Vector3 = bt.affine_inverse() * (pp[1] as Vector3)
			if absf(l.x) >= e.x or absf(l.y) >= e.y or absf(l.z) >= e.z:
				continue
			var front := e.z - l.z
			var aside := e.x - l.x * out_x
			var push := Vector3(0, 0, front) if front < aside or l.z > 0.0 else Vector3(out_x * aside, 0, 0)
			var part: VoxelPart = pp[0]
			var v_out := (bq * push.normalized()).dot(part.velocity_at(pp[1]) - body.velocity_at(pp[1]))
			var m_eff: float = (0.0 if fo.severed else fo.nominal_mass) + up.nominal_mass * 0.5 + (weapons[side].mass if weapons[side] else 0.0)
			# A soft, critically damped push (a stiff one fought a two-handed grip and set the
			# hands buzzing at the hilt).
			var acc: float = push.length() * ARM_OUT_K - minf(0.0, v_out) * 2.0 * sqrt(ARM_OUT_K)
			part.apply_impulse(bq * push.normalized() * acc * m_eff * dt, (pp[1] as Vector3) - part.global_position)

## Where a bow or a crossbow points: at the player's crosshair (aimAt), a bot's target (gaze),
## or straight ahead. A bow lies with the arrow (+x) on that line and the stave upright; a
## crossbow's stock (+y) is on it. Slewed at the weapon's rate, like any held weapon.
func _shoot_point(inp: Dictionary) -> Vector3:
	if inp.get("aimAt") is Vector3:
		return inp.aimAt
	if gaze != null:
		return gaze
	return torso.global_position + Vector3(sin(yaw), 0.3, cos(yaw)) * 10.0

func _shoot_pitch(inp: Dictionary) -> float:
	var d := _shoot_point(inp) - (torso.global_position + Vector3(0, 0.3 * S, 0))
	return atan2(d.y, Vector2(d.x, d.z).length())

func _shooter_aim(side: String, w: Weapon, inp: Dictionary, yaw_q: Quaternion, dt: float) -> Quaternion:
	var from := hand_world(side)
	var dir := _shoot_point(inp) - from
	if dir.length_squared() < 1e-4:
		dir = yaw_q * Vector3(0, 0, 1)
	dir = dir.normalized()
	var side_v := dir.cross(UP)
	if side_v.length_squared() < 1e-4:
		side_v = yaw_q * Vector3(1, 0, 0)
	side_v = side_v.normalized()
	var up_v := side_v.cross(dir).normalized()
	var desired: Quaternion
	if is_bow(w):
		# x along the shot, y the stave (tipped a little, as archers cant it), z across.
		var stave := up_v.rotated(dir, -0.18)
		desired = PD.quat_from_axes(dir, stave, dir.cross(stave).normalized())
	else:
		desired = PD.quat_from_axes(side_v, dir, side_v.cross(dir).normalized())
	var prev = aim_q[side]
	if prev != null:
		var step := PD.rot_error(desired, prev)
		var wmax := 14.0 * (0.45 + 0.55 * float(handling[side]))
		var rate := step.length() / dt
		if rate > wmax:
			step *= wmax / rate
			var ang := step.length()
			desired = Quaternion(step / ang, ang) * (prev as Quaternion)
	aim_q[side] = desired
	return desired

## The elbow's direction from the shoulder (a direction in the body's frame): kept on its own
## side of the body (at most 0.22 S across the shoulder line) and at most 0.12 S above the
## shoulder, the same for both arms, mirrored.
func _elbow_dir(side: String, e_local: Vector3, lu: float, t_rot: Quaternion) -> Vector3:
	var flip := side == "L"
	if flip:
		e_local.x = -e_local.x
	e_local = _limit_dir(e_local.normalized(), 0, 0.22 * S / lu)
	if flip:
		e_local.x = -e_local.x
	e_local = _limit_dir(e_local, 1, 0.12 * S / lu)
	return (t_rot * e_local).normalized()

## A hand's mark (in the yaw frame, from the torso) moved out of the torso and the head to the
## front of them: neither hand is ever pulled in through its own body.
func _clear_body(target: Vector3, yaw_q: Quaternion, t_pos: Vector3) -> Vector3:
	var th: Vector3 = torso.half_ext
	var tz := th.z + 0.09 * S
	if target.y < th.y and target.y > -th.y * 1.1 and absf(target.x) < th.x + 0.05 * S and target.z < tz:
		target.z = tz
	if not head.severed:
		var hh: Vector3 = head.half_ext
		var hl := yaw_q.inverse() * (head.global_position - t_pos)
		var hz := hl.z + hh.z + 0.09 * S
		if absf(target.x - hl.x) < hh.x + 0.05 * S and absf(target.y - hl.y) < hh.y + 0.05 * S and target.z < hz:
			target.z = hz
	return target

func arm_of(w: Weapon) -> Dictionary:
	return arm.R if weapons.R == w else arm.L

## Caps one component (0 = x, 1 = y) of a unit direction, keeping it a unit direction: the
## other components take up the rest in their own proportion.
static func _limit_dir(e: Vector3, axis: int, mx: float) -> Vector3:
	if e[axis] <= mx:
		return e
	e[axis] = mx
	var rest := sqrt(maxf(0.0, 1.0 - mx * mx))
	var o: Array = [1, 2] if axis == 0 else [0, 2]
	var l := Vector2(e[o[0]], e[o[1]]).length()
	if l < 1e-4:
		e[o[0]] = -rest * 0.8 if axis == 0 else 0.0
		e[o[1]] = -rest * (0.6 if axis == 0 else 1.0)
	else:
		e[o[0]] *= rest / l
		e[o[1]] *= rest / l
	return e

## A held blade never passes through its owner: own parts do not collide with own weapons, so
## when the hand-to-tip line comes inside the torso or head it is pushed back out.
func _keep_weapon_out(w: Weapon, dt: float) -> void:
	var q := PD.quat_of(w)
	var from := w.global_position
	var tip := from + q * Vector3(0, w.reach, 0)
	var base := from + q * Vector3(0, -0.15, 0)
	var ab := tip - base
	for part in [torso, head]:
		if part.severed:
			continue
		var c: Vector3 = part.global_position
		var k := clampf((c - base).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
		var p := base + ab * k
		var d := p - c
		d.y *= 0.7
		var r := (0.2 if part == head else 0.22) * S
		var dist := d.length()
		if dist >= r or dist < 1e-4:
			continue
		# Welded in the hand, the blade only moves if the forearm goes with it.
		var push: Vector3 = d / dist * ((r - dist) / r * 900.0 * (w.mass + 0.8)) * dt
		w.apply_impulse(push, p - w.global_position)
		if w.welded:
			arm_of(w).fore.apply_impulse(push * 0.6, hand_world("R" if weapons.R == w else "L") - arm_of(w).fore.global_position)

## A big blade left behind its wielder's back, with the arm too weak to haul it round, is swung
## back over the shoulder after a moment (sooner the heavier it is).
func _unjam_blade(side: String, w: Weapon, fore_q: Quaternion, t_pos: Vector3, t_rot: Quaternion, dt: float) -> void:
	if not w.welded:
		behind_t[side] = 0.0
		return
	var inv := t_rot.inverse()
	var wrot := PD.quat_of(w)
	var tip := inv * (w.global_position + wrot * Vector3(0, w.reach * 0.85, 0) - t_pos)
	var want := (fore_q * grip_q(w)) * Vector3(0, 1, 0)
	var want_l := inv * want
	var heavy := clampf((w.mass - 2.0) / 5.0, 0.0, 1.0)
	var behind := tip.z < -(0.12 - 0.08 * heavy) * S
	behind_t[side] = behind_t[side] + dt if behind else 0.0
	var pulling := want_l.z > -0.2
	if behind_t[side] < ((0.6 - 0.35 * heavy) if pulling else (1.2 - 0.5 * heavy)):
		return
	if not pulling:
		want = t_rot * Vector3(0.15, 0.55, 1).normalized()
	var cur := wrot * Vector3(0, 1, 0)
	var axis := cur.cross(want)
	if axis.length_squared() < 1e-6:
		axis = t_rot * Vector3(0, 1, 0)
	var ang := acos(clampf(cur.dot(want), -1.0, 1.0))
	var av := axis.normalized() * minf(9.0, 5.0 * ang + 2.0) + torso.angular_velocity
	w.angular_velocity = av
	arm[side].fore.angular_velocity = av

## The hand moves on a flat pane in front of the body, Half Sword style.
func hand_target_local(side: String, hp: Dictionary, thrust: float) -> Vector3:
	var sh: Vector3 = shoulder[side]
	var x := -clampf(float(hp.get("x", 0.0)), -2.0, 2.0) * (0.3 if two_handed and side == "R" else 0.42) * S
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
	if w.design.has("shoots") and not w.design.get("chain"):
		return _shooter_aim(side, w, inp, yaw_q, dt)
	var local := (yaw_q.inverse() * (target_w - t_pos)) / S
	var hy := float(hand_input[side].get("y", 0.15))
	var elev := clampf((0.78 if hy >= 0.0 else 0.85) * hy, -1.45, 1.2 if two_handed else 1.45)
	# Both hands on the haft swing it about the middle of the chest, one about its own shoulder.
	var shx: float = 0.0 if two_handed else shoulder[side].x / S
	var pivot := Vector3(shx + (local.x - shx) * 0.2, local.y, local.z - 0.28)
	var flat := Vector3(local.x - pivot.x, 0, local.z - pivot.z)
	if flat.length_squared() < 1e-4:
		flat = Vector3(0, 0, 1)
	flat = flat.normalized()
	var axis := yaw_q * Vector3(flat.x * cos(elev), sin(elev), flat.z * cos(elev))
	var ta = thrust_aim[side]
	if ta != null:
		axis = axis.slerp(ta.dir, ta.k).normalized()
	low_hand = maxf(low_hand, maxf(0.0, -elev - 0.2))
	var raise_k := smoothstep(0.5, 1.2, elev)
	var ed := yaw_q * Vector3((1.0 if side == "R" else -1.0) * (1.0 - raise_k), 0, raise_k)
	ed -= axis * ed.dot(axis)
	if ed.length_squared() < 1e-4:
		var fz := yaw_q * Vector3(0, 0, 1)
		ed = fz - axis * axis.dot(fz)
	ed = ed.normalized()
	ed = ed.rotated(axis, float(inp.get("twist" if side == "R" else "offTwist", 0.0)))
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
	var tw := tq * (1.0 - f)
	if has_wrist(w):
		# The wrist turns freely about the blade's length (_drive_wrist sets the edge): none of
		# the arm's torque goes into that light roll, or it spins the blade in the hand.
		var bax := PD.quat_of(w) * Vector3.UP
		tw -= bax * tw.dot(bax)
	fore.apply_torque_impulse((tq - tw) * dt)
	w.apply_torque_impulse(tw * dt)

## A fighter's elbow is held, not left to flap: the forearm (and the weapon welded to it) is
## steered relative to the upper arm, its bend changing no faster than a trained arm would
## change it, the reaction going into the upper arm. So the arm swings as one lever from the
## shoulder, like real technique, and a heavy head cannot whip it about.
const ELBOW_DAMP := 45.0
const ELBOW_PULL := 40.0
func _lock_elbow(side: String, w: Weapon, fore_q: Quaternion, strength: float, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var upper: VoxelPart = arm[side].upper
	var ax := PD.quat_of(fore) * Vector3(0, -1, 0)
	# Only the bend: the twist about the forearm is the wrist's business (handled above).
	var err := PD.rot_error(fore_q, PD.quat_of(fore))
	err -= ax * err.dot(ax)
	var rel := fore.angular_velocity - upper.angular_velocity
	rel -= ax * rel.dot(ax)
	var hand_w := hand_world(side)
	var lever := (w.global_transform * w.center_of_mass) - hand_w
	var i_fore := PD.inertia_of(fore) + fore.nominal_mass * pow(FORE_LEN * S * 0.5, 2)
	var i_asm := i_fore + PD.inertia_of(w) + w.mass * lever.length_squared()
	# The bend is between two bodies: sized on their combined (reduced) inertia, the upper arm's
	# about its own middle (a torque turns it there; sized about the shoulder, the damper
	# overdrove it and the arm buzzed at full reach).
	var i_up := PD.inertia_of(upper)
	var i_red := i_asm * i_up / (i_asm + i_up)
	# A damper on the bend, with a gentle pull toward the bend the aim wants: the elbow does
	# not flex fast unless the fighter means it, so a swing is one lever from the shoulder.
	var tq := (err * ELBOW_PULL - rel * ELBOW_DAMP) * i_red
	tq = PD.clamp_len(tq, 260.0 * maxf(0.3, strength) * MS * S * float(mods.strength))
	fore.apply_torque_impulse(tq * dt)
	upper.apply_torque_impulse(-tq * dt)

## The wrist turns the blade about its own length to the edge the aim wants (the wheel's
## twist, the lean into the stroke), the reaction going into the forearm.
func _drive_wrist(side: String, w: Weapon, w_aim: Quaternion, strength: float, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var q := PD.quat_of(w)
	var ax := q * Vector3.UP
	var want := w_aim * Vector3.RIGHT
	want -= ax * want.dot(ax)
	if want.length_squared() < 1e-6:
		return
	var cur := q * Vector3.RIGHT
	var ang := atan2(cur.cross(want).dot(ax), cur.dot(want.normalized()))
	var spin := (w.angular_velocity - fore.angular_velocity).dot(ax)
	var b := w.global_transform.basis.orthonormalized()
	var la := b.inverse() * ax
	var i_ax := maxf(1e-4, la.x * la.x * w.inertia.x + la.y * la.y * w.inertia.y + la.z * la.z * w.inertia.z)
	var wn := 22.0
	var t := (ang * wn * wn - spin * 2.0 * wn) * i_ax
	t = clampf(t, -14.0 * maxf(0.3, strength) * MS * S, 14.0 * maxf(0.3, strength) * MS * S)
	w.apply_torque_impulse(ax * t * dt)
	fore.apply_torque_impulse(-ax * t * dt)

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
	_legs_apart(not on)

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
	# Armour takes it first, where there is armour (character.js armorNear): the blow knocks
	# off the plates nearest it, the harder the more, and a bare spot is not covered any more.
	var near := [] if detached else _armor_near(part, lp, V * S * 1.7)
	if not near.is_empty():
		var a0: Dictionary = near[0][0]
		var h: float = Data.material(a0.mat).get("hardness", 0.6)
		var force := J * (0.6 if type == "blunt" else 1.0) * (1.0 + 0.6 * heavy)
		var nk := mini(4 + roundi(3.0 * heavy), 1 + int(force / (12.0 * h))) if force > 10.0 * h else 0
		for k in mini(nk, near.size()):
			var ad: Dictionary = near[k][0]
			var ci: int = near[k][1]
			ad.on[ci] = 0
			ad.alive -= 1
			if ad.node and is_instance_valid(ad.node):
				ad.node.multimesh.set_instance_transform(ci, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		if nk > 0:
			res.armor_hit = nk
		var absorb := minf(0.85, 0.3 + 0.55 * h)
		J *= 1.0 - (absorb * 0.55 if type == "blunt" else absorb)
		res.armor = true
	var bleed_before := part.bleed
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
		# A light cut only opens the skin; the depth climbs faster than the blow (a full swing
		# of a keen blade still goes through a limb in one).
		var bite := J * eff * (1.0 + 0.8 * heavy)
		var depth: float = minf(0.36 + 0.24 * heavy, 0.017 * bite * clampf(bite / 22.0, 0.35, 1.0)) * S / pow(big, 1.5)
		var width := vfs * (0.75 + 0.5 * heavy)
		if J * eff > 3.0 * big:
			var n := la.cross(ld)
			if n.length_squared() < 1e-4:
				n = Vector3(1, 0, 0)
			n = n.normalized()
			var span := (0.24 + 0.08 * heavy) * S
			# A blade follows the wound: a second blow into an open cut starts where the first
			# one stopped, so a thick limb is chopped through blow by blow instead of each one
			# only scraping the same mouth of the wound.
			# A light touch only goes as far into the wound as its own weight carries it.
			var open := 0.0 if detached else _wound(part, lp, ld, n, width, la, span, depth) * minf(1.0, J * eff / 9.0)
			for i in part.fx.size():
				if part.alive[i] == 0:
					continue
				var d := part.local_of(i) - lp
				if abs(d.dot(n)) < width and d.dot(ld) > -V * S and d.dot(ld) < depth + open and abs(d.dot(la)) < span:
					remove.append(i)
	elif type == "point":
		var eff := hardness * sharpness * maxf(0.15, la.dot(ld))
		dmg = J * 2.8 * eff
		part.bleed += dmg * 0.07
		var depth: float = minf(0.3 + 0.2 * heavy, 0.02 * J * eff * (1.0 + 0.8 * heavy)) * S
		if J * eff > 2.5:
			var r := V * S * (1.2 + 0.5 * heavy)
			var open := 0.0 if detached else _wound(part, lp, la, Vector3.ZERO, r, Vector3.ZERO, 0.0, depth)
			for i in part.fx.size():
				if part.alive[i] == 0:
					continue
				var d := part.local_of(i) - lp
				var along := d.dot(la)
				if along > -V * S and along < depth + open and (d - la * along).length() < r:
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
	# A crushing bite (or weight) smashes a crater whatever kind of blow it is; what it breaks
	# loose falls away as pieces.
	var crush: float = float(hit.get("crush", 0.0))
	if crush > 0.0:
		for i in part.fx.size():
			if part.alive[i] and part.local_of(i).distance_to(lp) < crush:
				remove.append(i)
		part.bleed += J * 0.03
	# Every cut or stab that lands takes something with it: under the threshold for a real wound
	# it still nicks a few voxels out at the point it struck, more the harder it came in.
	if remove.is_empty() and not detached and type != "blunt" and J * hardness * sharpness > 1.0:
		var rn := vfs * (0.75 + minf(1.6, J * hardness * sharpness * 0.08))
		for i in part.fx.size():
			if part.alive[i] and part.local_of(i).distance_to(lp) < rn:
				remove.append(i)
	if hollow > 0.0 and not detached:
		dmg *= 1.0 + minf(1.0, hollow / 0.1)
	if part == torso or part == head:
		stagger = minf(1.0, stagger + J * 0.007)
	# A blow across the face near the eyes: the view closes in from the edges (players), the
	# aim wanders (everyone). It heals a little over the fight.
	if part == head and not detached and lp.z > V * S * 0.5 and absf(lp.y - V * S * 0.6) < V * S * 1.6 and J > 5.0:
		eye_hurt = minf(1.0, eye_hurt + J * (0.012 if type == "blunt" else 0.025))
	if not detached and part.parent_part and part.parent_part != torso:
		part.parent_part.flinch_t = maxf(part.parent_part.flinch_t, 0.1 + J * 0.005)
	if not detached:
		stagger = minf(1.0, stagger + J * 0.0056 * (1.0 + injury) * (1.0 + 0.8 * (1.0 - minf(1.0, stamina / 40.0))))
		part.flinch_t = maxf(part.flinch_t, minf(0.45, 0.12 + J * 0.01))
		if push_t <= 0.0 and J > 4.0:
			push_t = 0.3
			var push: float = minf(90.0 if hit.get("thrown", false) else 55.0, J * (2.4 if hit.get("thrown", false) else 1.4)) * MS * S
			var dv: Vector3 = hit.dir
			torso.apply_central_impulse(Vector3(dv.x * push, 0, dv.z * push))
	if part.prosthetic != "":
		part.bleed = bleed_before
		dmg *= 0.5
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
		cut_force = J * hardness * sharpness * (1.0 + heavy)
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

## The armour plates within `r` of a part-local point, nearest first: [[piece, cell index]].
func _armor_near(part: VoxelPart, lp: Vector3, r: float) -> Array:
	var out := []
	for ad in part.get_meta("armor", []):
		for i in ad.pts.size():
			if ad.on[i]:
				var d: float = (ad.pts[i] as Vector3).distance_to(lp)
				if d < r:
					out.append([ad, i, d])
	out.sort_custom(func(x, y): return x[2] < y[2])
	return out

## How deep a wound already goes in from `lp` along `ld` (character.js wound): the farthest dead
## voxel inside the blade's slab (or the point's bore, when `n` is zero), counted only while the
## hole is open all the way from the surface (a cavity deeper in, from another cut, is not reached).
func _wound(part: VoxelPart, lp: Vector3, ld: Vector3, n: Vector3, width: float, la: Vector3, span: float, step: float) -> float:
	var seen := []
	var slab := n != Vector3.ZERO
	for i in part.fx.size():
		if part.alive[i]:
			continue
		var d := part.local_of(i) - lp
		var along := d.dot(ld)
		if along <= 0.0:
			continue
		if slab:
			if absf(d.dot(n)) >= width or absf(d.dot(la)) >= span:
				continue
		elif (d - ld * along).length() >= width:
			continue
		seen.append(along)
	seen.sort()
	var deepest := 0.0
	var gap := maxf(step, part.vf * part.part_scale * 2.0)
	for a in seen:
		if a > deepest + gap:
			break
		deepest = a
	return deepest

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
		# The torso: a lump with limbs rooted in it (the pelvis with the legs, a shoulder with
		# its arm) comes away as a half, limbs and all; so does any big piece.
		# Only a real chop halves a man: a big lump, or one carrying a limb's root that a strong
		# blow cut free (a light nick by the shoulder once took the arm and half the chest).
		var big_lump: bool = lump.size() > 0.25 * before
		var root_cut: bool = part.near_child_anchor(lump) and lump.size() > 0.08 * before and cut_force > 14.0
		if part == torso and not detached and (big_lump or root_cut):
			_drop_half(part, lump, res, dir)
			continue
		var amputation: bool = not detached and part != torso and (part.near_child_anchor(lump) or lump.size() >= 0.4 * before or lump.size() == before)
		if amputation and (cut_off == null or lump.size() > cut_off.size()):
			cut_off = lump
		elif not amputation:
			# A lump cut loose falls as a real piece (a guest's puppet only loses the voxels).
			var idx := Array(lump)
			var vox := part.remove_voxels(idx, false)
			var piece = Chunk.spawn(part, vox, dir) if not part.freeze and idx.size() > 2 else null
			res.removed.append({"part": part, "indices": idx, "voxels": vox, "chunk": piece != null})
	if cut_off == null and not detached and part != torso and part.alive_count == 0:
		cut_off = PackedInt32Array()
	if cut_off != null:
		sever(part, res, cut_off)
	elif not detached and part != torso and not part.hanging and part.thin_ratio() < float(mods.get("sever", 0.3)):
		hang(part, res)

## A half: a lump of the torso cut clean away with the limbs rooted in it. The lump becomes a
## body of its own and the limbs are jointed onto it, so a man cut through at the waist leaves
## his legs standing (for a moment) on a pelvis and goes down on his hands; cut down the middle,
## a side with its arm and leg goes one way and he the other. It is the end of him, soon.
func _drop_half(part: VoxelPart, lump: PackedInt32Array, res: Dictionary, dir: Vector3) -> void:
	var carried := []
	for ch in part.child_parts:
		if ch != head and not ch.severed and not ch.missing and part.lump_holds(lump, ch):
			carried.append(ch)
	var fraction := float(lump.size()) / maxf(1.0, part.fx.size())
	var idx := Array(lump)
	var at := {}
	for ch in carried:
		at[ch] = part.global_transform * ch.pa
	var vox := part.remove_voxels(idx, false)
	res.removed.append({"part": part, "indices": idx, "voxels": vox, "chunk": true})
	var piece = Chunk.spawn(part, vox, dir) if not part.freeze else null
	if piece:
		piece.angular_velocity = Vector3.ZERO
		piece.mass = maxf(piece.mass, part.nominal_mass * fraction)
		piece.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_BODY | VoxelPart.LAYER_DEBRIS
		piece.angular_damp = 0.3
	var names := []
	for ch in carried:
		names.append(ch.part_name)
		detach_limb(ch, res)
		if piece:
			var pieces := [ch]
			var stack := [ch]
			while not stack.is_empty():
				var c: VoxelPart = stack.pop_back()
				for cc in c.child_parts:
					pieces.append(cc)
					stack.append(cc)
			for pc in pieces:
				piece.add_collision_exception_with(pc)
			var j := PinJoint3D.new()
			add_child(j)
			j.global_position = at[ch]
			j.node_a = piece.get_path()
			j.node_b = ch.get_path()
			ch.joint = j
	# Nothing holds a half up: the whole piece, limbs and all, topples with the blow as one,
	# turning about the ground under it, and the limbs on it go slack and slide.
	if piece:
		var d := Vector3(dir.x, 0, dir.z)
		d = Vector3(1, 0, 0) if d.length_squared() < 1e-4 else d.normalized()
		var wv := UP.cross(d) * 3.5
		var bodies: Array = [piece]
		for ch in carried:
			var stack2 := [ch]
			while not stack2.is_empty():
				var c: VoxelPart = stack2.pop_back()
				bodies.append(c)
				var pm := PhysicsMaterial.new()
				pm.friction = 0.3
				c.physics_material_override = pm
				stack2.append_array(c.child_parts)
		var pivot: Vector3 = piece.global_position
		for b in bodies:
			pivot.y = minf(pivot.y, b.global_position.y - 0.2 * S)
		pivot.y = maxf(0.0, pivot.y)
		for b in bodies:
			var r: Vector3 = b.global_position - pivot
			b.linear_velocity = wv.cross(r) + d * 0.6
			b.angular_velocity = Vector3(wv.x, 0, wv.z)
	res.halved = res.get("halved", []) + names
	blood = minf(blood, 40.0)
	part.bleed += 6.0
	pain = 1.0
	stagger = 1.0
	if state == "stand":
		fall(99.0, true)

## A limb left on a strip of a few voxels does not hold for long: the thinner the strip, the
## gentler the swing that tears it off (character.js tearStrips).
func _tear_strips(dt: float) -> void:
	strip_clock += dt
	if strip_clock < 0.15:
		return
	strip_clock = 0.0
	for p in parts:
		if not p.hanging or p.severed or p.parent_part == null or p.freeze:
			continue
		var thin: float = p.thin_ratio()
		var w: float = (p.angular_velocity - p.parent_part.angular_velocity).length()
		var lv: float = (p.linear_velocity - p.parent_part.linear_velocity).length() / sqrt(S)
		p.hang_t += 0.15
		if p.hang_t < 0.6:
			continue
		if (thin < 0.06 and (w > 5.0 or lv > 2.8)) or (thin < 0.15 and (w > 9.0 or lv > 4.5)) or (thin < 0.3 and (w > 16.0 or lv > 8.0)):
			_tear_off(p)

func _tear_off(part: VoxelPart) -> void:
	var tl = part.thin_layer
	if tl == null:
		return
	var strip := []
	for i in part.fx.size():
		if not part.alive[i]:
			continue
		var k: int = part.fx[i] if tl[0] == 0 else (part.fy[i] if tl[0] == 1 else part.fz[i])
		if k == tl[1]:
			strip.append(i)
	if strip.is_empty():
		return
	var res := {"removed": [], "severed": [], "dmg": 0.0}
	res.removed.append({"part": part, "indices": strip, "voxels": part.remove_voxels(strip)})
	var dir := part.linear_velocity.normalized() if part.linear_velocity.length_squared() > 1e-4 else Vector3.DOWN
	cut_force = 99.0
	break_loose(part, res, dir, false)
	hit_taken.emit(self, res)

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
	# The piece still overlaps the stump it came off: meeting its owner's body at once, the
	# solver flung it across the arena. It falls clear first, then it is a thing in the world.
	if is_inside_tree():
		get_tree().create_timer(0.7, false, true).timeout.connect(func():
			for p in pieces:
				if not is_instance_valid(p):
					continue
				for o in parts:
					if is_instance_valid(o) and not pieces.has(o):
						p.remove_collision_exception_with(o))
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

## How far from death he is, 0..1 (the enemy's health plate): what kills him is the head, the
## torso or the blood running out, whichever is nearest.
func vitality() -> float:
	if not alive:
		return 0.0
	return clampf(minf(minf(head.hp, torso.hp), blood) / 100.0, 0.0, 1.0)

func total_hp() -> float:
	var t := 0.0
	for p in parts:
		t += p.hp
	return t
