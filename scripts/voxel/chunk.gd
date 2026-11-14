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
var boxes := 0                  # how many of its voxels are drawn as the part's own boxes
var cells := 0                  # and how many cells of a finer look it is drawn of (spawn)
var flap_joint: Joint3D = null
## What it was set to pass through, kept here: asked of the physics server instead (its
## collision exceptions), every one of them freed since printed an error, a dozen at a time
## (user: chunk.gd _in_a_body(): Parameter "body" is null).
var passes: Array = []

func pass_through(b: PhysicsBody3D) -> void:
	add_collision_exception_with(b)
	passes.append(b)

func stop_passing(b: PhysicsBody3D) -> void:
	remove_collision_exception_with(b)
	passes.erase(b)

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
	# What a finer look drew of them (a man's fine skin, his face, the flesh under them: VoxelPart.
	# piece_cells; a shell of armour's own voxels, given with the piece): the piece is drawn of
	# that, and the part's own boxes of it are not drawn (user: the piece that fell from him was
	# a piece of a square character that had nothing to do with him).
	var fine := PackedFloat32Array()
	var cell_mesh: Mesh = null
	if not wpn and part.has_method("piece_cells"):
		var pc: Dictionary = part.piece_cells(voxels)
		if not pc.is_empty():
			fine = pc.buf
			cell_mesh = pc.mesh
	for v in voxels:
		if v.has("cells") and v.get("cm") is Mesh:
			fine.append_array(v.cells)
			cell_mesh = v.cm
	var as_cells := cell_mesh != null and fine.size() >= 20
	var lo := Vector3.ONE * 1e9
	var hi := -Vector3.ONE * 1e9
	for i in voxels.size():
		var d: Vector3 = inv * ((voxels[i].p as Vector3) - c)
		lo = lo.min(d)
		hi = hi.max(d)
		# A voxel a gladiator's look kept out of sight (Physique) stays out of sight on the
		# piece too; it is still part of the piece and its weight.
		var shown := 0.0 if voxels[i].get("veil", false) or (as_cells and (voxels[i].has("i") or voxels[i].has("cells"))) else 1.0
		# (A cube of an open break is smaller than a voxel, and turned with the bone it came off:
		# VoxelPart.break_bone_out.)
		var vb: Basis = voxels[i].get("b", Basis())
		ch.boxes += 1 if shown > 0.0 else 0
		mm.set_instance_transform(i, Transform3D(vb.scaled(Vector3.ONE * shown * float(voxels[i].get("s", 1.0))), d))
		mm.set_instance_color(i, voxels[i].color)
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, VoxelPart.kind_data(int(voxels[i].get("kind", 8))))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	ch.add_child(mmi)
	if as_cells:
		# (The cells lie in the part's frame: drawn under the piece where the part was.)
		var fmm := MultiMesh.new()
		fmm.transform_format = MultiMesh.TRANSFORM_3D
		fmm.use_colors = true
		fmm.use_custom_data = true
		fmm.mesh = cell_mesh
		fmm.instance_count = fine.size() / 20
		# (Kept in memory from the start: the engine reads a drawing it draws in between the
		# physics steps when the piece comes into the scene, and one given whole it read back
		# from the graphics card, the frames in hand waited for: every piece cut off was a stall.)
		FineBody._keep_in_memory(fmm)
		fmm.buffer = fine
		ch.cells = fmm.instance_count
		var fmi := MultiMeshInstance3D.new()
		fmi.name = "cells"
		fmi.multimesh = fmm
		fmi.transform = Transform3D(Basis(q), c).affine_inverse() * part.global_transform
		ch.add_child(fmi)
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
			ch.pass_through(b)
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
		ch.collision_layer = 0
		ch._come_clear(0)
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

## Born inside what it came off and, as often, inside whoever the blow struck, a piece passes
## through bodies (no layer of its own: only the sand and the other pieces stop it) until it is
## clear of them; then it is a thing they knock against. (Wedged between a man's head and his
## shoulder, a chip off a giant's blade drove him into the sand at 20 m/s.) One still in a body
## after three seconds stays passing through: it lies in a corpse, it does not burst out of it.
func _come_clear(tries: int) -> void:
	if not is_inside_tree():
		return
	var me := weakref(self)
	get_tree().create_timer(0.2, false, true).timeout.connect(func():
		var c = me.get_ref()
		if c == null or not c.is_inside_tree() or c.held_on != null or c.collision_layer != 0:
			return
		if not c._in_a_body():
			c.collision_layer = VoxelPart.LAYER_DEBRIS
		elif tries < 15:
			c._come_clear(tries + 1))

func _in_a_body() -> bool:
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = [get_rid()]
	for b in passes:
		if is_instance_valid(b):
			skip.append(b.get_rid())
	for s in get_children():
		if s is CollisionShape3D and s.shape != null:
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = s.shape
			q.transform = s.global_transform
			q.collision_mask = VoxelPart.LAYER_BODY | VoxelPart.LAYER_CORPSE | VoxelPart.LAYER_WEAPON
			q.exclude = skip
			if not space.intersect_shape(q, 1).is_empty():
				return true
	return false

## The strip it hung by is cut (or the body is gone): it falls away as a piece like any other.
func let_go() -> void:
	if flap_joint and is_instance_valid(flap_joint):
		flap_joint.queue_free()
	flap_joint = null
	if flap_of and is_instance_valid(flap_of) and flap_of is PhysicsBody3D:
		pass_through(flap_of)
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
