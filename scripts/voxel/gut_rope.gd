class_name GutRope
extends Node
## Guts spilled from a belly opened wide (Fighter._check_belly): the coils come out as a chain of
## little voxel bodies, each a Chunk of the guts' own voxels on a ball joint to the one before,
## the first hung on the torso at the wound. They swing as he moves and drag on the sand; a blade
## through a link cuts the chain there. Once the body is gone the whole chain falls loose and
## ages away like any other piece.

const MAX_SEGS := 10
const SEG_VOX := 6
const SEG_MASS := 0.12
const CUT_SPEED := 2.2
static var ropes: Array = []

var torso: VoxelPart = null
var segs: Array = []      # Chunk, from the wound outward
var free_t := 0.0

## Pulls `groups` (voxel indices of the torso's guts, one group a link, from the wound outward)
## out through the wound at `at` (world), heading `out`. Returns the rope, or null with no screen
## or nothing to pull.
static func spill(f: Node, groups: Array, at: Vector3, out: Vector3) -> GutRope:
	var tor: VoxelPart = f.torso
	if tor == null or not tor.is_inside_tree() or tor.mm == null:
		return null
	var rope := GutRope.new()
	rope.torso = tor
	f.get_parent().add_child(rope)
	var prev: PhysicsBody3D = tor
	var prev_at := at
	var k := 0
	for g in groups:
		var voxels: Array = tor.remove_voxels(g, false, false)
		if voxels.is_empty():
			continue
		var ch: Chunk = Chunk.spawn(tor, voxels, out)
		if ch == null:
			continue
		ch.mass = SEG_MASS * pow(tor.part_scale, 3.0)
		# Out of the belly and down: each link a little further out than the last.
		var p := at + out * (0.05 + 0.045 * k) + Vector3(0, -0.035 * k, 0)
		ch.global_position = p
		ch.linear_velocity = tor.linear_velocity + out * 1.2 + Vector3(0, -0.4, 0)
		ch.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_WEAPON
		ch.contact_monitor = true
		ch.max_contacts_reported = 2
		var j := PinJoint3D.new()
		rope.add_child(j)
		j.global_position = (prev_at + p) * 0.5
		j.node_a = prev.get_path()
		j.node_b = ch.get_path()
		if prev is Chunk:
			ch.add_collision_exception_with(prev)
		ch.flap_of = prev
		ch.flap_joint = j
		rope.segs.append(ch)
		prev = ch
		prev_at = p
		k += 1
	if rope.segs.is_empty():
		rope.queue_free()
		return null
	ropes.append(rope)
	while ropes.size() > 6:
		var old = ropes.pop_front()
		if is_instance_valid(old):
			old.release()
	return rope

## Everything falls loose (the body is gone, or too many ropes lie about).
func release() -> void:
	for ch in segs:
		if is_instance_valid(ch):
			ch.let_go()
	segs = []
	queue_free()

func _physics_process(_dt: float) -> void:
	if not is_instance_valid(torso) or not torso.is_inside_tree():
		release()
		return
	for i in segs.size():
		var ch: Chunk = segs[i]
		if not is_instance_valid(ch) or ch.flap_of == null:
			continue
		for b in ch.get_colliding_bodies():
			if b is Weapon and (b.holder != null or b.thrown_t > 0.0) and (b.linear_velocity - ch.linear_velocity).length() > CUT_SPEED:
				ch.let_go()
				break

func _exit_tree() -> void:
	ropes.erase(self)
