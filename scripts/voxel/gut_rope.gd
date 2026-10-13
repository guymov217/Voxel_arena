class_name GutRope
extends Node
## Guts spilled from a belly opened wide (Fighter._check_belly): they come out as a long tube,
## a chain of links, each a short length of gut (2 x 2 voxels across, a few long, laid along the
## chain) made of the guts' own voxels taken out of the torso, a free body on a ball joint to the
## one before; the first hangs from the wound. They uncoil, swing, drag and heap on the sand, and
## a blade through a link cuts the chain there. Pulled taut (he walks off from where they lie)
## another length slides out of the wound, until the belly is empty. Once the body is gone the
## whole chain falls loose and ages away like any other piece.

const FIRST_LINKS := 16    # out at once when the belly opens (long enough to heap on the sand)
const MAX_LINKS := 28      # all a belly holds
const LINK_VOX := 12       # voxels of gut a link is made of (2 x 2 x 3)
const LINK_MASS := 0.1
const CUT_SPEED := 2.2
const GUT := Color(0.83, 0.6, 0.56)
static var ropes: Array = []

var fighter: Node = null
var torso: VoxelPart = null
var anchor := Vector3.ZERO     # the wound, in the torso's frame
var axis := Vector3(0, 0, 1)   # the torso's axis nearest the way out of the wound
var links: Array = []          # Chunk, from the wound outward
var _seed := 0

## Out through the wound at `at` (world), heading `out`: one link per group of the torso's gut
## voxels (each group taken out of the torso). Null with nothing to show it on.
static func spill(f: Node, groups: Array, at: Vector3, out: Vector3) -> GutRope:
	var tor: VoxelPart = f.torso
	if tor == null or not tor.is_inside_tree() or tor.mm == null:
		return null
	var rope := GutRope.new()
	rope.fighter = f
	rope.torso = tor
	rope.anchor = tor.global_transform.affine_inverse() * at
	# The tube is laid along the torso's own axis nearest the way out (its boxes stay tight).
	var lo := tor.global_transform.basis.orthonormalized().inverse() * out
	var best := Vector3(0, 0, 1)
	for a in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if a.dot(lo) > best.dot(lo):
			best = a
	rope.axis = best
	f.get_parent().add_child(rope)
	for g in groups:
		rope._add_link(g, false)
	if rope.links.is_empty():
		rope.queue_free()
		return null
	ropes.append(rope)
	while ropes.size() > 4:
		var old = ropes.pop_front()
		if is_instance_valid(old):
			old.release()
	return rope

## One more length of gut: out at the end of the chain (spilling), or at the wound with the rest
## pushed on ahead of it (pulled out later).
func _add_link(group: Array, at_wound: bool) -> void:
	var tor := torso
	var colors := []
	for i in group:
		if i >= 0 and i < tor.fx.size() and tor.alive[i]:
			colors.append(tor.colors[i])
	tor.remove_voxels(group, false, false)
	if colors.is_empty():
		return
	var vs := tor.vf * tor.part_scale
	var along: Vector3 = axis
	var b1 := Vector3(0, 1, 0) if absf(along.y) < 0.5 else Vector3(1, 0, 0)
	var b2 := along.cross(b1)
	var n := colors.size()
	var length := ceili(n / 4.0)
	var k := 0 if at_wound else links.size()
	var start := anchor + along * vs * (0.5 + float(k * length))
	var voxels := []
	var gt := tor.global_transform
	for i in n:
		var a: int = i / 4
		var q := start + along * vs * float(a) + b1 * vs * (float(i % 2) - 0.5) + b2 * vs * (float((i / 2) % 2) - 0.5)
		# Gut: pinkish grey and wet, a ring darker at each end, the blood only near the wound.
		_seed += 1
		var c := GUT.lerp(Color(0.7, 0.42, 0.4), 0.35 if a == length - 1 else 0.0)
		c = c * (0.92 + 0.08 * float(hash(_seed) % 100) / 100.0)
		if k == 0:
			c = c.lerp(colors[i % colors.size()], 0.5)
		c.a = 1.0
		voxels.append({"p": gt * q, "color": c, "kind": 9})
	var out_w := (gt.basis.orthonormalized() * along).normalized()
	var ch: Chunk = Chunk.spawn(tor, voxels, out_w)
	if ch == null:
		return
	ch.mass = LINK_MASS * pow(tor.part_scale, 3.0)
	# Each length tumbles out its own way, so they fall in loops, not a straight drop.
	var side := Vector3(float(hash(_seed * 7) % 200) / 100.0 - 1.0, 0.0, float(hash(_seed * 13) % 200) / 100.0 - 1.0)
	ch.linear_velocity = tor.linear_velocity + out_w * 0.8 + side * 0.9
	ch.angular_velocity = Vector3.ZERO
	# They heap on the sand and on each other, hang over his legs (not through them), and a blade
	# passing through is felt. Only the trunk they come out of is let through.
	ch.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS | VoxelPart.LAYER_BODY
	if fighter and fighter.get("parts"):
		for p in fighter.parts:
			if p != tor and is_instance_valid(p):
				ch.remove_collision_exception_with(p)
	ch.contact_monitor = true
	ch.max_contacts_reported = 2
	ch.angular_damp = 2.0
	if at_wound and not links.is_empty():
		var first: Chunk = links[0]
		if is_instance_valid(first) and first.flap_of == tor:
			# The new length goes in between the wound and the rest.
			if first.flap_joint and is_instance_valid(first.flap_joint):
				first.flap_joint.queue_free()
			first.flap_joint = _join(ch, first, (ch.global_position + first.global_position) * 0.5)
			first.flap_of = ch
			first.add_collision_exception_with(ch)
		ch.flap_joint = _join(tor, ch, gt * anchor)
		ch.flap_of = tor
		links.push_front(ch)
	else:
		var prev: PhysicsBody3D = links.back() if not links.is_empty() else tor
		ch.flap_joint = _join(prev, ch, gt * start)
		ch.flap_of = prev
		if prev is Chunk:
			ch.add_collision_exception_with(prev)
		links.append(ch)

func _join(a: PhysicsBody3D, b: PhysicsBody3D, at: Vector3) -> Joint3D:
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = a.get_path()
	j.node_b = b.get_path()
	return j

## Another length pulled out of the wound (Fighter.pull_guts on the host; the guests are told).
func pull(group: Array) -> void:
	if links.size() < MAX_LINKS and is_instance_valid(torso):
		_add_link(group, true)

## Everything falls loose (the body is gone, or too many ropes lie about).
func release() -> void:
	for ch in links:
		if is_instance_valid(ch):
			ch.let_go()
	links = []
	queue_free()

func _physics_process(dt: float) -> void:
	if not is_instance_valid(torso) or not torso.is_inside_tree():
		release()
		return
	var attached := 0
	for ch in links:
		if not is_instance_valid(ch) or ch.flap_of == null:
			break
		attached += 1
		for b in ch.get_colliding_bodies():
			if b is Weapon and (b.holder != null or b.thrown_t > 0.0) and (b.linear_velocity - ch.linear_velocity).length() > CUT_SPEED:
				ch.let_go()
				break
	# Pulled taut: the end of what still hangs on him lies far from the wound.
	if attached >= 2 and links.size() < MAX_LINKS and fighter and fighter.has_method("pull_guts"):
		var tail: Chunk = links[attached - 1]
		var reach := torso.vf * torso.part_scale * 3.0 * float(attached)
		# (Or thrown about, a fall or a lunge: the weight of what hangs drags more out.)
		if tail.global_position.distance_to(torso.global_transform * anchor) > reach * 0.92 or (torso.linear_velocity.length() > 2.5 and randf() < dt * 1.5):
			fighter.pull_guts()

func _exit_tree() -> void:
	ropes.erase(self)
