class_name Chunk
extends RigidBody3D
## A lump of flesh cut loose from a part (character.js looseChunk): its own voxels on a little
## body of its own, tumbling off the way the blow sent it. It lies on the sand for half a minute
## and then sinks away. Held in a mouth (`hold`), it rides on the jaw first and drops after a while.

const LIFE := 26.0
static var all: Array = []

var t := 0.0
var held_for := 0.0
var held_on: Node3D = null
var half := Vector3.ONE * 0.02
var flap_of: Node3D = null      # still hanging off this part by a strip of flesh
var flap_joint: Joint3D = null

## `voxels` are what VoxelPart.remove_voxels returned ({p: world position, color}).
## `part` may also be a Weapon: a piece that broke off it.
static func spawn(part: Node3D, voxels: Array, dir: Vector3, hold: Node3D = null, hold_at := Vector3.ZERO, hold_for := 2.0) -> Chunk:
	if voxels.is_empty() or not is_instance_valid(part) or not part.is_inside_tree() or part.mm == null:
		return null
	var wpn := part is Weapon
	var host: Node = (part.get_parent() if wpn else part.get_parent().get_parent()) if part.get_parent() else null
	if host == null:
		return null
	var c := Vector3.ZERO
	for v in voxels:
		c += v.p as Vector3
	c /= float(voxels.size())
	var q := PD.quat_of(part)
	var inv := q.inverse()
	var ch := Chunk.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	# What each voxel is made of, for the shader (wet flesh, bone, skin...), when it is known.
	mm.use_custom_data = voxels[0].has("kind")
	mm.mesh = part.mm.mesh
	mm.instance_count = voxels.size()
	var lo := Vector3.ONE * 1e9
	var hi := -Vector3.ONE * 1e9
	for i in voxels.size():
		var d: Vector3 = inv * ((voxels[i].p as Vector3) - c)
		lo = lo.min(d)
		hi = hi.max(d)
		# A voxel a gladiator's look kept out of sight (Physique) stays out of sight on the
		# piece too; it is still part of the piece and its weight.
		var shown := 0.0 if voxels[i].get("veil", false) else 1.0
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * shown), d))
		mm.set_instance_color(i, voxels[i].color)
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, VoxelPart.kind_data(int(voxels[i].get("kind", 8))))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	ch.add_child(mmi)
	var vs: float = part.vs if wpn else part.vf * part.part_scale
	ch.half = ((hi - lo) * 0.5 + Vector3.ONE * vs * 0.5).max(Vector3.ONE * 0.01)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ch.half * 2.0
	shape.shape = box
	shape.position = (hi + lo) * 0.5
	ch.add_child(shape)
	if wpn:
		ch.mass = maxf(0.05, part.mass * float(voxels.size()) / maxf(1.0, float(part.alive_count() + voxels.size())))
	else:
		ch.mass = maxf(0.05, voxels.size() * 0.0004 * pow(part.part_scale, 3.0) * float(part.fighter.MS if part.fighter else 1.0))
	ch.collision_layer = VoxelPart.LAYER_DEBRIS
	ch.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_DEBRIS
	# A piece starts inside what it came off: never against that body (or the blade it chipped
	# from and the hands holding it), or the push out of it threw a fighter off his feet at
	# every voxel a blow took.
	var own: Array = []
	if wpn:
		own.append_array(part.bodies())
		if part.holder and part.holder.get("parts"):
			own.append_array(part.holder.parts)
	elif part.get("fighter") and part.fighter.get("parts"):
		own.append_array(part.fighter.parts)
	else:
		own.append(part)
	for b in own:
		if b is PhysicsBody3D and is_instance_valid(b):
			ch.add_collision_exception_with(b)
	ch.linear_damp = 0.2
	ch.angular_damp = 0.8
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.1
	ch.physics_material_override = pm
	if hold and is_instance_valid(hold):
		# In the mouth: drawn hanging from the jaw until it is let go.
		ch.freeze = true
		ch.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		ch.collision_layer = 0
		ch.collision_mask = 0
		hold.add_child(ch)
		ch.position = hold_at
		ch.held_on = hold
		ch.held_for = hold_for
	else:
		host.add_child(ch)
		ch.global_transform = Transform3D(Basis(q), c)
		ch.linear_velocity = part.velocity_at(c) + dir * 1.5 + Vector3(0, 0.8, 0)
		ch.angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 8.0
	all.append(ch)
	var cap := 40 if Fx.current and Fx.current.quality == "low" else 160
	while all.size() > cap:
		# The oldest that lies on the sand goes first; a flap still hanging on a body stays.
		var k := 0
		while k < all.size() - 1 and is_instance_valid(all[k]) and all[k].flap_of != null:
			k += 1
		var old = all.pop_at(k)
		if is_instance_valid(old):
			old.queue_free()
	return ch

## The strip it hung by is cut (or the body is gone): it falls away as a piece like any other.
func let_go() -> void:
	if flap_joint and is_instance_valid(flap_joint):
		flap_joint.queue_free()
	flap_joint = null
	if flap_of and is_instance_valid(flap_of):
		add_collision_exception_with(flap_of)
	collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_DEBRIS
	flap_of = null
	t = 0.0

func _physics_process(dt: float) -> void:
	if flap_of != null:
		if not is_instance_valid(flap_of) or not flap_of.is_inside_tree():
			let_go()
		else:
			return   # hanging on: it swings and does not age
	t += dt
	if held_on:
		held_for -= dt
		if held_for > 0.0 and is_instance_valid(held_on) and get_parent() == held_on:
			return
		# Let go: it drops out of the mouth into the world.
		var gt := global_transform
		var world: Node = held_on.get_parent()
		while world and (world is VoxelPart or world is Fighter or world is Node3D and world.get_parent() is VoxelPart):
			world = world.get_parent()
		held_on = null
		if world == null:
			queue_free()
			return
		get_parent().remove_child(self)
		world.add_child(self)
		global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
		freeze = false
		collision_layer = VoxelPart.LAYER_DEBRIS
		collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_DEBRIS
		linear_velocity = Vector3(0, -0.5, 0)
		t = 0.0
		return
	if t > LIFE - 2.0:
		freeze = true
		position.y -= dt * 0.15
	if t > LIFE:
		queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		all.erase(self)
