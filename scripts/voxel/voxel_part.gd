class_name VoxelPart
extends RigidBody3D
## One body part (a forearm, a head, a beast's leg): a rigid body made of fine voxels that can
## be knocked out, cut through and burnt. Its weight sits on its own box; once a blow opens a
## hole in it, boxes over the flesh that is left take over the collisions, so a blade can sink
## into the wound it cut (as in the web game's character.js).

const LAYER_WORLD := 1
const LAYER_BODY := 2
const LAYER_WEAPON := 4
const LAYER_DEBRIS := 8
## The dead: a body lying in the arena. Everything that meets a body meets it too, except a
## standing man: he walks on over it (the ground under his feet is its top), where his legs
## caught on it, he stalled against it and fell over it (user).
const LAYER_CORPSE := 16

## A body that has died, put on the dead's layer: it meets the sand, weapons, pieces, other dead
## and the living who look for it (beasts, a man down), not a man on his feet.
static func to_corpse(ps: Array) -> void:
	for p in ps:
		if is_instance_valid(p) and not p.severed and p.collision_layer == LAYER_BODY:
			p.collision_layer = LAYER_CORPSE
			p.collision_mask = LAYER_WORLD | LAYER_WEAPON | LAYER_DEBRIS | LAYER_CORPSE

const SMEAR := Color(0.306, 0.039, 0.039)
const BRUISE := Color(0.29, 0.157, 0.282)

var fighter: Node = null          # the Fighter or Beast it belongs to
var def: Dictionary = {}
var part_name := ""
var label := ""
var dims := Vector3i.ONE          # body voxels
var grid := Vector3i.ONE          # fine voxels
var vf := 0.0275                  # fine voxel size, unscaled
var part_scale := 1.0
var mult := 1.0
var nominal_mass := 1.0

var fx := PackedInt32Array()
var fy := PackedInt32Array()
var fz := PackedInt32Array()
var colors := PackedColorArray()
var alive := PackedByteArray()
var jaw_pivot: Node3D = null     # a biting head's hinged lower jaw (drawing only)
var jaw_mesh: MultiMeshInstance3D = null

## Made and put in place in one go (a fighter built, a beast spawned), or moved there at once
## (snap_drawing): for its first steps it is drawn where it is, not swept there from where it
## was made (a new champion on the dressing screen showed first at the arena's middle). Only
## the drawing: resetting the body's own interpolation nudged the physics.
var _snap_until := 0
func _ready() -> void:
	snap_drawing()

func snap_drawing() -> void:
	_snap_until = Engine.get_physics_frames() + 2

## The drawing follows the body where the physics' interpolation has it this frame (see
## _build_mesh): the voxels, the skin and the jaw.
func _process(_dt: float) -> void:
	if mmi == null and skin == null:
		return
	if dangle_mesh:
		swing_now(_dt)
	_draw_at(global_transform if Engine.get_physics_frames() < _snap_until else get_global_transform_interpolated())

## Drawn where the body is now, with the game paused (the kill cam puts the bodies back where
## they were and plays them forward while nothing else runs: _process with it).
func draw_now() -> void:
	_draw_at(global_transform)
	snap_drawing()

## Drawn this much off where the physics has it (world): the fighter closes each joint on
## screen, the limb set against the part it hangs from (Fighter._seat_drawing).
var draw_shift := Vector3.ZERO
## Drawn turned by this (world) first: a limb below a broken bone is drawn swinging with the
## piece past the break it hangs from (Fighter._seat_drawing).
var draw_turn := Transform3D()
## Drawn wherever the part is drawn (its armour): top-level nodes set to its drawing each frame.
var draw_with: Array = []
## A finer look drawn over the part (FineHead: a man's head; FineBody: the rest of him in the new
## look), kept in step with its voxels: shown and coloured with the one each lies over. Drawing only.
var fine := {}
var draw_scale := Vector3.ONE   # drawn this much fuller or smaller about its middle (a breath: Physique.live)
func _draw_at(t: Transform3D) -> void:
	t = draw_turn * t
	t.origin += draw_shift
	if draw_scale != Vector3.ONE:
		t.basis = t.basis * Basis.from_scale(draw_scale)
	if mmi:
		mmi.global_transform = t
	if skin:
		skin.global_transform = t
	if jaw_mesh and jaw_pivot:
		jaw_mesh.global_transform = t * jaw_pivot.transform
		var fj = fine.get("jaw_mi")
		if fj != null:
			fj.global_transform = jaw_mesh.global_transform
	if bone_out:
		bone_out.global_transform = t * bone_xf
	if dangle_mesh:
		_lay_bend()
		dangle_mesh.global_transform = t * _bend_x
		var far = fine.get("far_mi")
		if far != null:
			far.global_transform = t * _bend_x
	for n in draw_with:
		if is_instance_valid(n):
			n.global_transform = t

## Seen through, `a` from 0 (solid) to 1 (gone), with all that is drawn with it (its armour): the
## fight camera fades its own fighter's part that stands between it and the blow (CameraRig).
var see_through := 0.0
func set_see_through(a: float) -> void:
	see_through = a
	for gi in [mmi, skin, jaw_mesh, bone_out, dangle_mesh, fine.get("far_mi"), fine.get("jaw_mi")] + draw_with:
		if gi != null and is_instance_valid(gi) and gi is GeometryInstance3D:
			(gi as GeometryInstance3D).transparency = a

## An open break: the broken end of the bone stands out through the torn skin (user: it has to
## look like bone, very real, the break the most real thing in the game), and like everything
## else it is voxels and it breaks (user): a shaft of bone cubes as thick as that limb's bone,
## ivory, snapped at a slant into a jagged end with the red marrow in it, a sliver split off beside
## it, blood up it in streaks; round it the torn flesh in cubes on the skin (OpenFracture). It is
## as solid as the rest of him (bone_shape: a box round what is left of it) and a blow that meets
## it knocks its cubes off, a hard one snaps its end off (break_bone_out, Fighter.apply_hit).
## `at` part-local on the bone, `out` the way out through the skin (part-local; zero: the way the
## break is bent, the same on every screen).
var bone_out: MultiMeshInstance3D = null   # its cubes drawn (none without a screen)
var bone_xf := Transform3D()
var bone_at := Vector3.ZERO     # part-local: the middle of the bone standing out, and its way
var bone_dir := Vector3.UP
var bone_wound := Vector3.ZERO  # part-local: the hole in the skin it came out of, and its facing
var bone_wound_n := Vector3.UP
var bo_pos := PackedVector3Array()   # its cubes (OpenFracture.Cubes): part-local centres,
var bo_col := PackedColorArray()     # colours, kinds, turned with the bone (1) or not,
var bo_kind := PackedByteArray()     # the shaft's layer each is in (-1: not the shaft),
var bo_frame := PackedByteArray()    # and which are still there
var bo_layer := PackedInt32Array()
var bo_alive := PackedByteArray()
var bo_basis := Basis()              # the bone's frame (its y the way it stands out)
var bo_s := 0.0                      # a cube's size
var bo_origin := Vector3.ZERO        # where the shaft starts, on the bone at the break
var bo_skin := 0.0                   # how far up the shaft the skin is
var bo_r := 0.0                      # the shaft's radius
var bo_top := 0.0                    # how far up the shaft its end (and spikes) can reach
var bone_shape: CollisionShape3D = null
func show_bone(at: Vector3, out := Vector3.ZERO) -> void:
	# At the break, on the outside of the bend (where it is bent; else where it was given).
	var ex := break_exit()
	if not ex.is_empty():
		at = ex[0]
		out = ex[1]
	var ac := _across()
	var along: Vector3 = ac[2]
	if out.length_squared() < 1e-6:
		out = kink_push(absi(hash(String(part_name))) % 256) * -1.0
	out = (out - along * out.dot(along)).normalized()
	if out.length_squared() < 0.5:
		return
	# Never out toward the body (into the trunk, between the legs): a blow from that side drives the
	# broken end out of the other (user: only where it makes sense).
	var trunk = fighter.get("torso") if fighter else null
	if trunk is Node3D and trunk != self and is_instance_valid(trunk):
		var tb: Vector3 = global_transform.affine_inverse() * (trunk as Node3D).global_position - at
		tb -= along * tb.dot(along)
		if tb.length_squared() > 1e-6 and out.dot(tb.normalized()) > 0.25:
			out = -out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(part_name)) + int(at.x * 1000.0) * 31 + int(at.z * 1000.0)
	# The near piece's snapped end, driven out through the skin and on toward the far end.
	var y := (out + along * 0.45).normalized()
	var x := y.cross(along if absf(y.dot(along)) < 0.95 else Vector3.UP).normalized()
	var z := x.cross(y).normalized()
	var ax: int = _root_axis()[0]
	var thick := absf(half_ext[(ax + 1) % 3]) + absf(half_ext[(ax + 2) % 3])
	# The bone's radius: as a limb's bone is, a quarter of its width across, never thinner than
	# most of a voxel (user: no huge bone).
	var r := maxf(thick * 0.13, vf * part_scale * 0.7)
	# Where its line meets the skin.
	var t_skin := INF
	var nrm := out
	for k in 3:
		if absf(y[k]) > 1e-4:
			var tk: float = ((half_ext[k] if y[k] > 0.0 else -half_ext[k]) - at[k]) / y[k]
			if tk > 0.0 and tk < t_skin:
				t_skin = tk
				nrm = Vector3.ZERO
				nrm[k] = signf(y[k])
	if t_skin == INF:
		t_skin = thick * 0.5
	var h_out := maxf(r * 2.8, thick * 0.45)          # how far it stands out of the skin
	var wc := at + y * t_skin
	# The limb's own colour round the hole (its skin, or the cloth over it), for the torn edge:
	# from a voxel of the face just past the blood the wound has smeared round it.
	var skin := Color(0.85, 0.66, 0.52)
	var ring := vf * part_scale * 3.0
	var face_k := 0
	for k in 3:
		if absf(nrm[k]) > 0.5:
			face_k = k
	var bd := INF
	for i in fx.size():
		if not alive[i] or bone[i] or organ[i] != 0:
			continue
		var q := local_of(i)
		if absf(absf(q[face_k]) - half_ext[face_k]) > vf * part_scale * 1.1:
			continue   # (not on the face it comes out of)
		var d := q.distance_to(wc)
		if d > ring * 1.05 and d < bd:
			bd = d
			skin = colors[i]
	var cb := OpenFracture.voxels({"at": at, "y": y, "x": x, "z": z, "along": along, "nrm": nrm,
		"t_skin": t_skin, "r": r, "h_out": h_out, "half": half_ext, "skin": skin, "seed": rng.randi(), "vox": vf * part_scale,
		"skin_h": skin_over.bind(face_k, signf(nrm[face_k]))})
	bo_pos = cb.pos
	bo_col = cb.color
	bo_kind = cb.kind
	bo_frame = cb.frame
	bo_layer = cb.layer
	bo_alive = PackedByteArray()
	bo_alive.resize(bo_pos.size())
	bo_alive.fill(1)
	bo_basis = cb.basis
	bo_s = cb.s
	bo_origin = at
	bo_skin = t_skin
	bo_r = r
	bo_top = t_skin + h_out + r * 2.0
	# (The near piece: it stays with the part; the far one swings.)
	bone_xf = Transform3D()
	bone_at = at + y * (t_skin + h_out * 0.5)
	bone_dir = y
	bone_wound = wc
	bone_wound_n = nrm
	_fit_bone_shape()
	if DisplayServer.get_name() == "headless" or mmi == null:
		return
	if bone_out == null:
		bone_out = MultiMeshInstance3D.new()
		bone_out.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		bone_out.top_level = true
		add_child(bone_out)
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.use_custom_data = true
	m.mesh = mm.mesh
	m.instance_count = bo_pos.size()
	var box := AABB(bone_at, Vector3.ZERO)
	for n in bo_pos.size():
		m.set_instance_transform(n, _bo_xf(n))
		m.set_instance_color(n, bo_col[n])
		m.set_instance_custom_data(n, kind_data(bo_kind[n]))
		box = box.expand(bo_pos[n])
	bone_out.multimesh = m
	bone_out.material_override = mmi.material_override
	bone_out.custom_aabb = box.grow(bo_s * 2.0)
	bone_out.visible = true
	_draw_at(global_transform)

## Cube n of the open break as drawn: half a voxel, turned with the bone or square with the part,
## nothing once it is knocked off.
func _bo_xf(n: int) -> Transform3D:
	var k := bo_s / (vf * part_scale) if bo_alive[n] else 0.0
	var b := bo_basis if bo_frame[n] == 1 else Basis()
	return Transform3D(b.scaled(Vector3.ONE * k), bo_pos[n])

## How many of the bone's own cubes (the shaft, the sliver, the chips) are still there.
func bone_out_left() -> int:
	var n := 0
	for i in bo_pos.size():
		if bo_alive[i] and bo_kind[i] == OpenFracture.BONE:
			n += 1
	return n

## A blow at `lp` (part-local) on an open break: the cubes within `rad` of it knocked out, and the
## shaft past them with them when not a third of it is left standing where it was struck (the
## end snapped off). What came off: [{p (world), color, kind, b (turned how, part-local), s (its
## size, of a voxel)}], for the pieces to fly (Chunk); empty when it met none of them.
func break_bone_out(lp: Vector3, rad: float) -> Array:
	var out := []
	if bo_pos.is_empty():
		return out
	var lost := {}
	for n in bo_pos.size():
		if bo_alive[n] and bo_pos[n].distance_to(lp) <= rad:
			lost[n] = true
	if lost.is_empty():
		return out
	# Snapped: where a layer of the shaft struck has not a third of itself left, all above it goes.
	var count := {}   # layer -> [cubes there, cubes left]
	for n in bo_pos.size():
		var j: int = bo_layer[n]
		if j >= 0 and bo_alive[n]:
			var c: Array = count.get(j, [0, 0])
			c[0] += 1
			if not lost.has(n):
				c[1] += 1
			count[j] = c
	var snap := 1 << 30
	for j in count:
		var c: Array = count[j]
		if int(c[1]) * 3 < int(c[0]) and int(j) < snap:
			snap = int(j)
	if snap < (1 << 30):
		for n in bo_pos.size():
			if bo_alive[n] and bo_layer[n] > snap:
				lost[n] = true
	var k := bo_s / (vf * part_scale)
	for n in lost:
		bo_alive[n] = 0
		out.append({"p": global_transform * bo_pos[n], "color": bo_col[n], "kind": int(bo_kind[n]), "b": bo_basis if bo_frame[n] == 1 else Basis(), "s": k})
		if bone_out and bone_out.multimesh:
			bone_out.multimesh.set_instance_transform(n, _bo_xf(n))
	_fit_bone_shape()
	if bone_out and not bo_alive.has(1):
		bone_out.visible = false
	return out

## The bone standing out as solid as the rest of him: a box round what is left of it out of the
## skin, so a blade or a club meets it there (and knocks its cubes off); gone with it.
func _fit_bone_shape() -> void:
	var hi := -INF
	for n in bo_pos.size():
		if bo_alive[n] and bo_frame[n] == 1:
			hi = maxf(hi, (bo_pos[n] - bo_origin).dot(bone_dir))
	var len := hi + bo_s * 0.5 - bo_skin
	if len < bo_s or bo_pos.is_empty():
		if bone_shape:
			bone_shape.set_deferred("disabled", true)
			bone_shape.queue_free()
			bone_shape = null
		return
	if bone_shape == null:
		bone_shape = CollisionShape3D.new()
		bone_shape.shape = BoxShape3D.new()
		add_child(bone_shape)
	(bone_shape.shape as BoxShape3D).size = Vector3(bo_r * 2.0, len, bo_r * 2.0)
	bone_shape.transform = Transform3D(bo_basis, bo_origin + bone_dir * (bo_skin + len * 0.5))

func hide_bone() -> void:
	if bone_out:
		bone_out.visible = false
	bo_pos = PackedVector3Array()
	bo_col = PackedColorArray()
	bo_kind = PackedByteArray()
	bo_frame = PackedByteArray()
	bo_layer = PackedInt32Array()
	bo_alive = PackedByteArray()
	_fit_bone_shape()

## How far out from the part's middle its skin is over the part-local point p, along axis k on
## the side sg (+1 or -1): the outer face of the last living voxel of the column there, eased
## between the four columns round p. NAN where none of them has a voxel.
func skin_over(p: Vector3, k: int, sg: float) -> float:
	var s := vf * part_scale
	var a1 := (k + 1) % 3
	var a2 := (k + 2) % 3
	var g1: float = p[a1] / s + (grid[a1] - 1) * 0.5
	var g2: float = p[a2] / s + (grid[a2] - 1) * 0.5
	var i1 := floori(g1)
	var i2 := floori(g2)
	var sum := 0.0
	var wsum := 0.0
	for d1 in 2:
		for d2 in 2:
			var h := _column_top(i1 + d1, i2 + d2, k, sg)
			if is_nan(h):
				continue
			var w := absf(1.0 - d1 - (g1 - i1)) * absf(1.0 - d2 - (g2 - i2))
			sum += h * w
			wsum += w
	return sum / wsum if wsum > 1e-6 else NAN

func _column_top(c1: int, c2: int, k: int, sg: float) -> float:
	var q := Vector3i.ZERO
	q[(k + 1) % 3] = c1
	q[(k + 2) % 3] = c2
	var n: int = grid[k]
	for st in n:
		q[k] = n - 1 - st if sg > 0.0 else st
		var i := _cell(q.x, q.y, q.z)
		if i >= 0 and alive[i] == 1:
			return sg * local_of(i)[k] + vf * part_scale * 0.5
	return NAN

# ---------- A limb broken through: the far end swings from the break ----------
# (user: a broken limb swinging free from the broken angle) Drawn on its own, like a jaw: the
# voxels past the break in a multimesh of their own, hung from the break and swung by the limb's
# own movement and its weight; the break's bend is where it rests. Drawing only: the collider
# and every blow are the part's as they were.
var dangle_slot := {}
var dangle_mm: MultiMesh = null
var dangle_mesh: MultiMeshInstance3D = null
var _sw_q := Quaternion()           # the swing, part-local, about the break
var _sw_w := Vector3.ZERO           # its angular velocity
var _sw_lv := Vector3.ZERO          # the part's velocity (world) last frame
var _sw_av := Vector3.ZERO
var _sw_frame := -1                 # the frame it last swung
var _band: Array = []                # [slot, voxel, base, s, off, off x tip, laid straight]: the voxels over the break, laid round the bend
var _hang_r := 0.0                   # how far from the break anything that hangs from it can reach
var _band_rows := PackedFloat32Array()   # _band's terms for VoxelCore.lay_band: 19 floats a voxel
var _band_ix := PackedInt32Array()       # and [slot, voxel] a voxel
var _band_was := INF                     # how long the bend was when last laid out (INF: lay all)
var _band_native := false                # last laid by the C++ core (else row by row here)
var _bend_q := Quaternion(0, 0, 0, 0)   # the swing the bend was last laid out for
## The piece past the bend as it is drawn (part-local): turned by the swing and set on the end of
## the bend (_lay_bend). What hangs from it (the leg below a broken thigh) is drawn with it.
var _bend_x := Transform3D()

func _skin_skip() -> Dictionary:
	if dangle_slot.is_empty():
		return jaw_slot
	var d := jaw_slot.duplicate()
	d.merge(dangle_slot)
	return d

func _dangle_pivot() -> Vector3:
	var p := Vector3.ZERO
	if not kink.is_empty():
		p[int(kink[0])] = float(kink[1])
	return p

## How a voxel past the break is drawn, unbent (its look's shape, or a plain cube).
func _dangle_base(i: int) -> Transform3D:
	return shape_xf[i] if i < shape_xf.size() else Transform3D(Basis(), local_of(i))

## The piece past the break as it is drawn now (part-local), for what hangs from it: nothing
## turned where `lp` is not past the break, or while nothing swings there.
func bend_of(lp: Vector3) -> Transform3D:
	if dangle_mm == null or kink.is_empty():
		return Transform3D()
	var c: float = lp[int(kink[0])] - float(kink[1])
	if (c < 0.0) if bool(kink[3]) else (c > 0.0):
		return _bend_x
	return Transform3D()

## How far the bone runs on past the break, to its far end.
func _far_len() -> float:
	var ax: int = kink[0]
	var tip: Vector3 = _across()[2]
	return maxf(0.0, half_ext[ax] - float(kink[1]) * tip[ax])

## How long the bend at the break runs along the bone: the sharper it is bent, the longer, so
## that no two neighbouring layers of voxels turn far apart (cubes gaping on the outside).
func _band_len(theta: float) -> float:
	var v := vf * part_scale
	return clampf(maxf(v * 3.0, theta * v * 4.5), v * 2.0, maxf(v * 2.0, _far_len() * 0.9))

## The centre line of the bend, `s` along it from the break (part-local): the bone's own line
## turned round in an arc, `s` of `b` of the way to the whole swing (`n`, `theta`).
static func _arc_at(s: float, b: float, n: Vector3, theta: float, tip: Vector3, pv: Vector3) -> Vector3:
	if theta < 1e-4:
		return pv + tip * s
	var ph := theta * s / b
	return pv + (b / theta) * (tip * sin(ph) + n.cross(tip) * (1.0 - cos(ph)) + n * n.dot(tip) * (ph - sin(ph)))

## The swing as an angle in [0, PI] about a unit axis.
static func _swing_of(q: Quaternion) -> Array:
	q = q.normalized()
	if q.w < 0.0:
		q = -q
	var theta := q.get_angle()
	return [q, theta, q.get_axis() if theta > 1e-5 else Vector3.UP]

## Where the piece past the bend is drawn for swing `q` (part-local).
func _bend_for(q: Quaternion) -> Transform3D:
	var sw := _swing_of(q)
	var theta: float = sw[1]
	var pv := _dangle_pivot()
	var tip: Vector3 = _across()[2]
	var b := _band_len(theta)
	var r := Basis(sw[0])
	return Transform3D(r, _arc_at(b, b, sw[2], theta, tip, pv) - r * (pv + tip * b))

## The limb bent at the break as the swing has it (user: a break is not a gap, nothing missing
## between the two pieces): the piece past the bend turned whole, and the voxels over the break
## laid round the bend between, each turned its share, stretched along the bone on the outside of
## the bend and pressed together on the inside, the flesh one, bent. Armour on it goes with it.
func _lay_bend() -> void:
	if dangle_mm == null or kink.is_empty():
		return
	if absf(_bend_q.dot(_sw_q)) > 0.9999995:
		return
	_bend_q = _sw_q
	_bend_x = _bend_for(_sw_q)
	var g := _bend_geom()
	var inv := _bend_x.affine_inverse()
	var b: float = g[6]
	var nc := Greedy.core() if dangle_mm.instance_count > 0 else null
	if nc and not nc.has_method("lay_band"):
		nc = null   # (a core built before it could)
	if (nc != null) != _band_native:
		# Laid the other way last time: what that way left straight, this one does not know of.
		_band_native = nc != null
		_band_was = INF
		for row in _band:
			row[6] = false
	if nc:
		# The C++ core lays the band, voxel by voxel, in one call.
		nc.lay_band(dangle_mm, _band_rows, _band_ix, alive, veil, g[0], g[2], g[1], b, _band_was, g[7], g[5], g[3], g[4], inv)
		_band_was = b
		if fine.has("far_mm"):
			FineBody.lay(self, g, inv, b, nc)
	else:
		var q: Quaternion = g[0]
		var n: Vector3 = g[2]
		var theta: float = g[1]
		var k: float = g[7]
		var ax: int = g[5]
		var pv: Vector3 = g[3]
		var tip: Vector3 = g[4]
		# Each layer of voxels along the bone is turned and placed on the arc alike: worked out
		# once a layer (with the far piece's inverse folded in), then each voxel stretched and set.
		var lay_of := {}
		for row in _band:
			var i: int = row[1]
			if not alive[i] or veiled(i):
				continue
			var sb: float = row[3]
			if sb >= b:
				# Past the bend: turned whole with the far piece, its own place in that piece's mesh.
				if not row[6]:
					row[6] = true
					dangle_mm.set_instance_transform(int(row[0]), row[2])
				continue
			row[6] = false
			var lay = lay_of.get(sb)
			if lay == null:
				lay = [inv.basis * Basis(Quaternion().slerp(q, sb / b)), inv * _arc_at(sb, b, n, theta, tip, pv)]
				lay_of[sb] = lay
			var m: Basis = lay[0]
			var ms := m
			ms[ax] = m[ax] * clampf(1.0 + k * n.dot(row[5]), 0.35, 2.6)
			dangle_mm.set_instance_transform(int(row[0]), Transform3D(ms * (row[2] as Transform3D).basis, (lay[1] as Vector3) + m * (row[4] as Vector3)))
		if fine.has("far_mm"):
			FineBody.lay(self, g, inv, b, null)
	var layers := {}
	for ad in get_meta("armor", []):
		var n = ad.get("node")
		if n == null or not is_instance_valid(n):
			continue
		var m: MultiMesh = n.multimesh
		var base: Array = _plate_bases(ad)
		for ci in mini(base.size(), m.instance_count):
			if ad.on[ci] == 0 or (ad.has("clip") and (ad.clip as PackedByteArray)[ci] == 1):
				continue
			var bxf := _bent(base[ci], g, layers)
			m.set_instance_transform(ci, bxf)
			FineArmor.sync(ad, ci, bxf)

## The plates' own places (part-local), straight: kept from before the limb was ever bent.
func _plate_bases(ad: Dictionary) -> Array:
	if ad.has("xf"):
		return ad.xf
	if not ad.has("flat"):
		var out := []
		var m: MultiMesh = ad.node.multimesh
		for ci in m.instance_count:
			out.append(m.get_instance_transform(ci))
		ad["flat"] = out
	return ad.flat

## A plate drawn where the limb under it is drawn (straight, or bent at the break).
func drawn_plate(base: Transform3D) -> Transform3D:
	if dangle_mm == null or kink.is_empty():
		return base
	return _bent(base, _bend_geom())

## The bend as it is now: [swing, angle, axis, pivot, the far end's way, bone axis, band, angle a metre].
func _bend_geom() -> Array:
	var sw := _swing_of(_sw_q)
	var theta: float = sw[1]
	var b := _band_len(theta)
	return [sw[0], theta, sw[2], _dangle_pivot(), _across()[2], int(kink[0]), b, theta / b]

## Where something drawn at `base` (part-local, unbent) is drawn bent: past the bend turned with
## the far piece; over the break, laid round the bend.
func _bent(base: Transform3D, g: Array, layers := {}) -> Transform3D:
	var pv: Vector3 = g[3]
	var tip: Vector3 = g[4]
	var b: float = g[6]
	var s := (base.origin - pv).dot(tip)
	if s <= 0.0:
		return base
	if s >= b:
		return _bend_x * base
	var off := base.origin - pv - tip * s
	return _bent_layer(base, s, off, off.cross(tip), g, layers)

## _bent for a voxel `s` along the bend, `off` across it (`cr` = off x tip): the layer's turn
## and its place on the arc are the same for every voxel in it, worked out once (`layers`, s ->).
func _bent_layer(base: Transform3D, s: float, off: Vector3, cr: Vector3, g: Array, layers: Dictionary) -> Transform3D:
	var b: float = g[6]
	var n: Vector3 = g[2]
	var lay = layers.get(s)
	if lay == null:
		lay = [Basis(Quaternion().slerp(g[0] as Quaternion, s / b)), _arc_at(s, b, n, float(g[1]), g[4], g[3])]
		layers[s] = lay
	var rs: Basis = lay[0]
	var sc := Vector3.ONE
	sc[int(g[5])] = clampf(1.0 + float(g[7]) * n.dot(cr), 0.35, 2.6)
	return Transform3D(rs * Basis.from_scale(sc) * base.basis, (lay[1] as Vector3) + rs * off)

func _start_dangle() -> void:
	if mm == null or DisplayServer.get_name() == "headless" or kink.is_empty():
		return
	_stop_dangle()
	var idx := []
	for i in fx.size():
		if _past_break(i):
			idx.append(i)
	if idx.is_empty():
		return
	dangle_mm = MultiMesh.new()
	dangle_mm.transform_format = MultiMesh.TRANSFORM_3D
	dangle_mm.use_colors = true
	dangle_mm.use_custom_data = true
	dangle_mm.mesh = mm.mesh
	dangle_mm.instance_count = idx.size()
	for s in idx.size():
		var i: int = idx[s]
		dangle_slot[i] = s
		var k := 1.0 if alive[i] and not veiled(i) else 0.0
		var base := _dangle_base(i)
		dangle_mm.set_instance_transform(s, Transform3D(base.basis.scaled(Vector3.ONE * k), base.origin))
		dangle_mm.set_instance_color(s, colors[i])
		dangle_mm.set_instance_custom_data(s, _custom(i))
	dangle_mm.custom_aabb = mmi.custom_aabb
	# The voxels over the break: laid round the bend as it swings (_lay_bend).
	var pv := _dangle_pivot()
	var tip: Vector3 = _across()[2]
	var reach := _band_len(PI)
	_band = []
	for i in idx:
		if (local_of(i) - pv).dot(tip) < reach:
			_band.append([dangle_slot[i], i])
	_band_terms()
	_hang_r = _hang_reach()
	_bend_q = Quaternion(0, 0, 0, 0)
	dangle_mesh = MultiMeshInstance3D.new()
	dangle_mesh.multimesh = dangle_mm
	dangle_mesh.material_override = mmi.material_override
	dangle_mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	dangle_mesh.top_level = true
	dangle_mesh.custom_aabb = mmi.custom_aabb
	add_child(dangle_mesh)
	# It starts where the blow left it: bent at the break.
	_sw_q = Quaternion((kink[2] as Transform3D).basis.orthonormalized())
	_sw_w = Vector3.ZERO
	_sw_lv = linear_velocity
	_sw_av = angular_velocity
	if fine.has("body"):
		FineBody.dangle_on(self)
		dangle_mesh.visible = false   # (its voxels drawn as the fine ones over them)
	_lay_bend()
	_mark_skin()

## How far from the break anything _hang_points has can be drawn, however it swings (for
## _keep_off_ground: one well clear of the sand is passed). The far end's corners, and each part
## below joint by joint (its joint on the one above, then its corner furthest from that joint);
## the bend at most twice its length further (the arc, and the piece set on its end), and a little
## over for the give in the joints.
func _hang_reach() -> float:
	var pv := _dangle_pivot()
	var ax: int = kink[0]
	var r := Vector3(_far_len(), half_ext[(ax + 1) % 3], half_ext[(ax + 2) % 3]).length()
	var below: Array = []
	for c in child_parts:
		if is_instance_valid(c):
			below.append([c, (c.pa as Vector3).distance_to(pv)])
	while not below.is_empty():
		var e: Array = below.pop_back()
		var c = e[0]
		var ca: Vector3 = c.ca
		var h: Vector3 = c.half_ext
		r = maxf(r, float(e[1]) + (ca.abs() + h).length())
		for gc in c.child_parts:
			if is_instance_valid(gc):
				below.append([gc, float(e[1]) + (gc.pa as Vector3).distance_to(ca)])
	return 1.1 * (r + 2.0 * _band_len(PI)) + 0.05

## What the bend does not change, for each voxel over it, worked out once (_bent's own terms):
## its place unbent, how far along the bone past the break, and its offset across the bone.
func _band_terms() -> void:
	var pv := _dangle_pivot()
	var tip: Vector3 = _across()[2]
	for k in _band.size():
		var i: int = _band[k][1]
		var base := _dangle_base(i)
		var sb := (base.origin - pv).dot(tip)
		var off := base.origin - pv - tip * sb
		_band[k] = [_band[k][0], i, base, sb, off, off.cross(tip), false]
	# The same, packed for the C++ core: the place as a MultiMesh buffer has it (by rows, each
	# row's origin after it), then s, off and off x tip.
	_band_rows = PackedFloat32Array()
	_band_ix = PackedInt32Array()
	for row in _band:
		var t: Transform3D = row[2]
		var bx := t.basis
		var o: Vector3 = row[4]
		var c: Vector3 = row[5]
		_band_rows.append_array([bx.x.x, bx.y.x, bx.z.x, t.origin.x, bx.x.y, bx.y.y, bx.z.y, t.origin.y, bx.x.z, bx.y.z, bx.z.z, t.origin.z, row[3], o.x, o.y, o.z, c.x, c.y, c.z])
		_band_ix.append_array([int(row[0]), int(row[1])])
	_band_was = INF
	_bend_q = Quaternion(0, 0, 0, 0)

func _stop_dangle() -> void:
	if fine.has("body"):
		FineBody.dangle_off(self)
	if dangle_mm:
		for ad in get_meta("armor", []):
			var n = ad.get("node")
			if n == null or not is_instance_valid(n):
				continue
			var base: Array = _plate_bases(ad)
			for ci in mini(base.size(), n.multimesh.instance_count):
				if ad.on[ci] == 1 and not (ad.has("clip") and (ad.clip as PackedByteArray)[ci] == 1):
					n.multimesh.set_instance_transform(ci, base[ci])
					FineArmor.sync(ad, ci, base[ci])
	if dangle_mesh:
		dangle_mesh.queue_free()
	dangle_mesh = null
	dangle_mm = null
	_bend_x = Transform3D()
	_band = []
	if not dangle_slot.is_empty():
		dangle_slot = {}
		_mark_skin()

## Swung once a frame: by its fighter first, before what hangs from it is drawn with it
## (Fighter._seat_drawing), else on its own.
func swing_now(dt: float) -> void:
	if dangle_mm == null or kink.is_empty():
		return
	var fr := Engine.get_process_frames()
	if fr == _sw_frame:
		return
	_sw_frame = fr
	_swing(dt)
	_lay_bend()

## The far end, hung from the break by the muscle round it (user: like rubber at the break,
## swinging from the broken piece): its weight swings it down, the limb's jerks and turns throw
## it about, and the torn muscle holds it a little toward where it broke.
func _swing(dt: float) -> void:
	if dt <= 0.0 or kink.is_empty():
		return
	dt = minf(dt, 1.0 / 30.0)
	var inv := global_transform.basis.orthonormalized().inverse()
	var tip: Vector3 = _across()[2] * maxf(_far_len(), half_ext[int(kink[0])] * 0.5)
	var d := _sw_q * tip
	var len2 := maxf(1e-4, d.length_squared())
	# Gravity, and the part's own acceleration felt the other way (it is left behind).
	var acc_w := (linear_velocity - _sw_lv) / dt
	_sw_lv = linear_velocity
	var g_l := inv * (Vector3(0, -9.8, 0) - acc_w.limit_length(60.0))
	var alpha := d.cross(g_l) / len2
	# The part turning under it: it lags behind the turn.
	var dav := inv * (angular_velocity - _sw_av)
	_sw_av = angular_velocity
	_sw_w -= dav * 0.7
	# The torn muscle pulls it a little toward its bent rest, and damps the swing.
	var rest := Quaternion((kink[2] as Transform3D).basis.orthonormalized())
	var err := (_sw_q * rest.inverse()).normalized()
	var ang := err.get_angle()
	var eax := err.get_axis() if ang > 1e-4 else Vector3.ZERO
	if ang > PI:
		ang -= TAU
	alpha -= eax * ang * 2.5
	_sw_w += alpha * dt
	_sw_w *= exp(-dt * 1.4)
	var wl := _sw_w.length()
	if wl > 1e-5:
		_sw_q = (Quaternion(_sw_w / wl, wl * dt) * _sw_q).normalized()
	# Never round further than the torn flesh lets it: so far from where it broke, and never
	# folded back on itself.
	var off := (_sw_q * rest.inverse()).normalized()
	if off.get_angle() > 1.3 and off.get_angle() < TAU - 1.3:
		_sw_q = (Quaternion(off.get_axis(), 1.3) * rest).normalized()
		_sw_w *= 0.3
	var sw := _swing_of(_sw_q)
	if float(sw[1]) > 1.9:
		_sw_q = Quaternion(sw[2], 1.9)
		_sw_w *= 0.3
	_keep_off_ground()

## Never through the sand: the piece past the break and the limb hanging below it are drawn above
## the ground, laid back toward straight (where the body itself is, on the ground at worst) as far
## as they must be.
func _keep_off_ground() -> void:
	var t := draw_turn * get_global_transform_interpolated()
	t.origin += draw_shift
	# Whatever hangs from the break is within _hang_r of it, however it swings (_hang_reach): well
	# clear of the sand, nothing to do.
	if (t * _dangle_pivot()).y - _hang_r > GROUND_CLEAR:
		return
	var pts := _hang_points()
	if _lowest(t, pts, _sw_q) >= GROUND_CLEAR:
		return
	var lo := 0.0
	var hi := 1.0
	for k in 7:
		var mid := (lo + hi) * 0.5
		if _lowest(t, pts, _sw_q.slerp(Quaternion(), mid)) >= GROUND_CLEAR:
			hi = mid
		else:
			lo = mid
	_sw_q = _sw_q.slerp(Quaternion(), hi).normalized()
	_sw_w *= 0.4

const GROUND_CLEAR := 0.01

## The far end's corners, and the corners of every part hanging below it (part-local, unbent).
func _hang_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	var ax: int = kink[0]
	var ac := _across()
	var far: Vector3 = (ac[2] as Vector3) * half_ext[ax]
	var h1: float = half_ext[(ax + 1) % 3]
	var h2: float = half_ext[(ax + 2) % 3]
	for a in [-1.0, 1.0]:
		for b in [-1.0, 1.0]:
			out.append(far + (ac[0] as Vector3) * h1 * a + (ac[1] as Vector3) * h2 * b)
	var inv := get_global_transform_interpolated().affine_inverse()
	var stack: Array = child_parts.duplicate()
	while not stack.is_empty():
		var c = stack.pop_back()
		if not is_instance_valid(c) or c.severed or c.missing or c.hanging:
			continue
		var tc: Transform3D = inv * c.get_global_transform_interpolated()
		var h: Vector3 = c.half_ext
		for k in 8:
			out.append(tc * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
		stack.append_array(c.child_parts)
	return out

func _lowest(t: Transform3D, pts: PackedVector3Array, q: Quaternion) -> float:
	var x := t * _bend_for(q)
	var lo := INF
	for p in pts:
		lo = minf(lo, (x * p).y)
	return lo
var jaw_mouth: Node3D = null
var jaw_mm: MultiMesh = null
var jaw_slot := {}               # voxel index -> its slot in jaw_mm
var jaw_angle := 0.0
var jaw_teeth := true          # the teeth still there (a jaw hacked mostly away loses them)
var bone := PackedByteArray()
var organ := PackedByteArray()     # per voxel, the organ it is part of (Anatomy; 0 none)
var alive_count := 0
## Each grid cell's living voxel (its index + 1; 0 none, or gone) and each collider cell's count
## of living voxels (of total_coarse whole), kept up as voxels go and come back: worked out voxel
## by voxel for every blow (loose_lumps, fit_collider), they were most of what a nail of a pot's
## hail cost.
var live_cell := PackedInt32Array()
var live_coarse := PackedInt32Array()
var total_coarse := PackedInt32Array()

var hp := 100.0
var bleed := 0.0
var severed := false
var hanging := false
var fractured := false        # the bone broken right through: the limb is held on by its muscle only
## How badly its bone is broken: 0 whole, 1 cracked (it holds, and hurts), 2 broken through under
## whole skin (closed), 3 broken through and out of the skin (open). `fractured` is 2 and over.
var fracture := 0
## Where the bone broke, drawn bent there: [axis, at (local, along the bone), the transform the
## far end is drawn with]; empty for a straight bone. Drawing only (the collider stays straight).
var kink: Array = []
var stump := false
var drips: Array = []   # {node: GPUParticles3D, lp: Vector3}: where blood runs from its wounds
var stump_t := 0.0
var flinch_t := 0.0
var missing := false
var prosthetic := ""               # "peg", "hook", "blade": what the physician fitted in its place
var pro_level := 0                 # the smith's steps on it (Body.PRO_STEPS)
var pro_full := 0                  # its voxels as fitted: whole, it works as well as it can
var thin_layer = null              # [axis, layer]: where thin_ratio found it thinnest
var hang_t := 0.0
var spots: Array = []           # fire and acid where they struck (fire.gd)
var spot_clock := -1.0          # the part's own time in the spots' work (Fire.tick; below 0: not yet set)
var heat := {}                   # voxel -> how charred (or melted) it is
var flames: GPUParticles3D = null
var poison_fx: GPUParticles3D = null   # green voxels rising off where acid or venom eats in
var stuck: Array = []            # arrows and darts in it
var wielder: Node = null         # a severed limb someone picked up to hit people with
var thrown_t := 0.0
var thrown_by: Node = null
var parent_part: VoxelPart = null
var child_parts: Array = []
var joint: Joint3D = null
var pa := Vector3.ZERO           # joint point on the parent (parent frame)
var ca := Vector3.ZERO           # joint point on this part (own frame)

var mm: MultiMesh
var mmi: MultiMeshInstance3D
var main_shape: CollisionShape3D
var boxes: Array = []            # CollisionShape3D, while the part has holes (or is fitted)
var split := false
var half_ext := Vector3.ONE
## What is drawn of the part, as boxes laid along it (own frame; none: the part's whole box): its
## collider is kept to them, whole or cut (fit_collider). A giant of myth is drawn slimmer than
## his boxes (FineBody.fit_giant): a shin's box a hand wider than the shin drawn in it, a forearm's
## swung through the air beside the arm on screen, knocked a man down with nothing drawn touching
## him (user). The weight, the inertia and the joints stay the box's.
var fit_slabs: Array = []

func fit_to(slabs: Array) -> void:
	fit_slabs = slabs
	if main_shape != null:
		fit_collider()

static var _box_mesh_cache := {}
static var _material: StandardMaterial3D
## The voxel boxes' look (shaders/voxel_body.gdshader): each voxel's kind of stuff in its
## instance data (skin, cloth, leather, metal...; see the shader).
static var _body_material: ShaderMaterial
var kinds := PackedByteArray()   # per voxel, what it is made of (only how it is drawn)
## Per voxel, which corners of its six faces are shut in by a neighbour (ao_bits): drawn darker
## there, the creases of a body and the gaps between blocks in shadow. Only how it is drawn.
var ao := PackedInt32Array()
var cellmap := PackedInt32Array()   # grid cell -> voxel index + 1 (0: never a voxel there)
## A gladiator's look (Physique), drawing only: `veil` 1 where a voxel is there for every blow,
## organ, bone and joint but not drawn (the shell a style pares away over plain flesh), and
## `bevel` on to draw the body's outer edges chamfered (`bev`: each voxel's open faces).
var veil := PackedByteArray()
var bevel := false
var bev := PackedInt32Array()
## Bodies drawn as a smooth skin over their voxels (VoxelSkin) instead of the voxel boxes; the
## voxels are still what is hit, cut and simulated. Set from the settings ("bodies"). Off for
## now (kept for later: SMOOTH_BODIES_DEFAULT in match.gd and the menu's Bodies row).
static var smooth_skin := false
static var _skin_material: StandardMaterial3D
var skin: MeshInstance3D = null
var _skin_dirty := false

## `voxels`: [[fx, fy, fz, Color, bone, kind, organ], ...] on the fine grid (kind and organ optional).
func setup(owner_node: Node, d: Dictionary, voxels: Array, scale_: float, mass_: float) -> void:
	fighter = owner_node
	def = d.duplicate()   # its own: what one creature sets on its part (a fist, a bite) is not every one's after it
	part_name = d.get("name", "part")
	label = d.get("label", part_name)
	name = part_name
	var dd: Array = d.get("dims", [1, 1, 1])
	dims = Vector3i(int(dd[0]), int(dd[1]), int(dd[2]))
	var g: Array = d.get("grid", [dims.x * Data.body_res, dims.y * Data.body_res, dims.z * Data.body_res])
	grid = Vector3i(int(g[0]), int(g[1]), int(g[2]))
	vf = Data.body_voxel / Data.body_res
	part_scale = scale_
	_lpos = PackedVector3Array()
	_offs27 = PackedInt32Array()
	mult = float(d.get("mult", 1.0))
	nominal_mass = mass_
	if d.get("pa") != null:
		pa = _v3(d.pa) * scale_
	if d.get("ca") != null:
		ca = _v3(d.ca) * scale_
	var n := voxels.size()
	fx.resize(n); fy.resize(n); fz.resize(n); colors.resize(n); alive.resize(n); bone.resize(n); kinds.resize(n); organ.resize(n)
	for i in n:
		var v: Array = voxels[i]
		fx[i] = int(v[0]); fy[i] = int(v[1]); fz[i] = int(v[2])
		# A little grain voxel to voxel (skin, cloth and fur are never one flat colour).
		var c: Color = v[3]
		var k := grain(i)
		colors[i] = Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), 1.0)
		bone[i] = 1 if v[4] else 0
		kinds[i] = int(v[5]) if v.size() > 5 else 8
		organ[i] = int(v[6]) if v.size() > 6 else 0
		alive[i] = 1
	alive_count = n
	_index_cells()
	# Physics: the box carries the weight; inertia from the whole box, centred, so a dent never
	# changes how the part swings.
	mass = maxf(0.05, mass_)
	half_ext = Vector3(dims.x, dims.y, dims.z) * Data.body_voxel * scale_ * 0.5 * 0.95
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	var s := half_ext * 2.0
	inertia = Vector3(s.y * s.y + s.z * s.z, s.x * s.x + s.z * s.z, s.x * s.x + s.y * s.y) * mass / 12.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	main_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half_ext * 2.0
	main_shape.shape = box
	add_child(main_shape)
	_build_mesh()

## The little brightness grain voxel to voxel (skin, cloth and fur are never one flat colour on
## blocks); the smooth skin takes it back out.
func grain(i: int) -> float:
	return 1.0 + (float(hash(Vector3i(fx[i], fy[i], fz[i]) + Vector3i(dims.x, dims.y, dims.z) * 131) % 1000) / 1000.0 - 0.5) * 0.09

## The shared material of every voxel box (bodies, armour, weapons), or one with every box
## drawn as `force` (an armour plate's metal...).
static var _forced := {}
static func body_material(force := -1) -> ShaderMaterial:
	if force < 0:
		if _body_material == null:
			_body_material = ShaderMaterial.new()
			_body_material.shader = load("res://shaders/voxel_body.gdshader")
			_body_material.set_shader_parameter("ao_strength", ao_strength)
		return _body_material
	if not _forced.has(force):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/voxel_body.gdshader")
		m.set_shader_parameter("force_kind", force)
		m.set_shader_parameter("ao_strength", ao_strength)
		_forced[force] = m
	return _forced[force]

## The body material for a gladiator's look (Physique): his edges bevelled (the code over each
## voxel's kind is then its open faces, not a blade's taper), the skin oiled or not. Only the look.
static var _looks := {}
static func look_material(oiled: bool) -> ShaderMaterial:
	if not _looks.has(oiled):
		var m: ShaderMaterial = body_material().duplicate()
		m.set_shader_parameter("bevel_mode", true)
		m.set_shader_parameter("oil", 1.0 if oiled else 0.0)
		m.set_shader_parameter("ao_strength", ao_strength)
		_looks[oiled] = m
	return _looks[oiled]

## How dark the corners of the voxels go (Options, "Voxel shading"): 0 off. Every voxel body,
## armour plate and weapon drawn with body_material() follows at once.
const AO_ON := 0.55
static var ao_strength := AO_ON

static func set_ao(on: bool) -> void:
	ao_strength = AO_ON if on else 0.0
	for mat in [_body_material] + _looks.values() + _forced.values():
		if mat:
			mat.set_shader_parameter("ao_strength", ao_strength)
	FineHead.material()   # (the fine head's, a shade less, follows too)
	FineArmor.material()  # (and the new look's armour)

## A voxel kind as MultiMesh custom data (the shader reads r * 16; a >= 1 marks it set, and
## what a carries over 1 is the voxel's corner shading, `ao`, see ao_bits). A sharp weapon
## voxel's taper (taper_code) rides in r over the kind, in sixteens: r holds the kind and the
## taper's low 16 bits exactly (a float carries 24). The spike bits over them (16..23, a point's
## place along a run of points) ride in a's fraction, under the corner bits.
static func kind_data(k: int, ao_ := 0, taper := 0) -> Color:
	return Color(float(k + 16 * (taper & 0xFFFF)) / 16.0, 0.0, 0.0, 1.0 + float(ao_) + float(taper >> 16) / 1024.0)

const TAPER_AXES := [Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK]
## How a sharp voxel of a weapon is drawn (only the look: it still hits and weighs as a cube).
## An edge voxel narrows to a wedge toward its open sides, thin across the blade's thickness and
## full along it: a triangle seen end on. A point voxel narrows both ways to a tip. Which way is
## the thickness goes by the weapon's volume round it: the way it is thinnest. A blade two voxels
## thick narrows in each of its two halves toward the face they share.
## `cells`: the weapon's voxels, Vector3i -> its job ("edge", "point", ...). 0 for a voxel not
## tapered; else bits 0..5 the open sides it narrows toward (+x -x +y -y +z -z), 6..8 the axes it
## is pinched along, 9 a point, 10..15 an axis pinched toward its + or - face (2a + 10 for +,
## 2a + 11 for -) instead of its middle. The rows behind an edge and thick blocks stay blocks.
## `face` (0..5: +x -x +y -y +z -z), when the smith set it at the forge: the way the edge or the
## point faces, whatever is round it; -1 to read it off the weapon's shape. `faces`: the faces
## the smith set on the other sharp voxels (Vector3i -> 0..5), for a run of points.
## A point on a run of points (one stab block on another, up to the tip) is a length of one
## spike: bits 16..19 its place along the run from the base, 20..23 the run's length, and it is
## drawn narrowing from its base's width to its tip's, so the spike tapers unbroken to the end.
## Not a point, bits 16..19 are corners thin on their own (see _edge_code): an edge where it turns
## a step of the outline, and the block behind the step (any job, a blunt one too), so the edge
## of a blade cut round in steps runs on unbroken round its corners. `memo`: shared by the calls
## of one pass over a weapon, so each voxel's thickness is worked out once.
static func taper_code(cells: Dictionary, p: Vector3i, face := -1, faces: Dictionary = {}, memo: Dictionary = {}) -> int:
	var job := str(cells.get(p, ""))
	if job != "edge" and job != "point":
		return _step_corners(cells, p, faces, memo) if cells.has(p) else 0
	if job == "point":
		var run := _spike(cells, faces, p, face)
		if not run.is_empty():
			var ra: int = run[0]
			var code := 512 | (1 << (2 * ra + (0 if run[1] > 0 else 1)))
			for b in 3:
				if b == ra:
					continue
				code |= 1 << (6 + b)
				# Half of a spike two thick narrows toward the face it shares with its other half:
				# a point on one side only (the haft, or nothing, on the other).
				var d: Vector3i = TAPER_AXES[b]
				var halves := []
				for sg: int in [1, -1]:
					if str(cells.get(p + d * sg, "")) == "point":
						halves.append(sg)
				if halves.size() == 1:
					code |= 1 << (2 * b + (10 if halves[0] > 0 else 11))
			return code | (mini(run[2], 14) << 16) | (mini(run[3], 15) << 20)
	if face >= 0 and face < 6:
		var fa := face / 2
		var others: Array = [0, 1, 2].filter(func(a): return a != fa)
		var pinched: Array = others
		if job == "edge":
			# Thin across the blade: the way the weapon is thinnest round it (a tie: the forge's depth).
			pinched = [others[0] if _span(cells, p, others[0]) + (0.0 if others[0] == 2 else 0.1) <= _span(cells, p, others[1]) + (0.0 if others[1] == 2 else 0.1) else others[1]]
		var c := 512 if job == "point" else 0
		for a in pinched:
			c |= 1 << (6 + int(a))
		return c | (1 << face)
	if job == "edge":
		return _edge_code(cells, p, faces, memo)
	var both := []    # open on both sides: the thickness, pinched on the middle
	var half := {}    # half of a blade two thick: axis -> the side its other half is on (+1/-1)
	var one := []     # open on one side: where it faces
	for a in 3:
		var d: Vector3i = TAPER_AXES[a]
		var up := not cells.has(p + d)
		var down := not cells.has(p - d)
		if up and down:
			both.append(a)
		elif up or down:
			var s := -1 if up else 1
			var q := p + d * s
			if (str(cells.get(q, "")) == "edge" or str(cells.get(q, "")) == "point") and not cells.has(q + d * s):
				half[a] = s
			else:
				one.append(a)
	var pinch: Array = both + half.keys()
	if pinch.is_empty() or one.is_empty():
		return 0
	var code := 512
	for a in pinch:
		code |= 1 << (6 + a)
		if half.has(a):
			code |= 1 << (2 * a + (10 if half[a] > 0 else 11))
	for a in one:
		if half.has(a):
			code |= 1 << (2 * a + (1 if half[a] > 0 else 0))
		else:
			code |= 1 << (2 * a + (0 if not cells.has(p + TAPER_AXES[a]) else 1))
	return code

## The run of points `p` is on: [axis, sign (toward the tip), its place from the base, length],
## or [] when it stands alone. The run goes the way the smith turned it (`face`), else the way
## the longest line of points through it ends in the open, the one its tip was turned to first;
## a point turned to face another way is not part of it.
static func _spike(cells: Dictionary, faces: Dictionary, p: Vector3i, face: int) -> Array:
	var dirs := []
	if face >= 0 and face < 6:
		dirs = [[face / 2, 1 if face % 2 == 0 else -1]]
	else:
		for a in 3:
			dirs.append([a, 1])
			dirs.append([a, -1])
	var best := []
	for d in dirs:
		var want: int = 2 * d[0] + (0 if d[1] > 0 else 1)
		var step: Vector3i = TAPER_AXES[d[0]] * d[1]
		var ahead := 0
		var q := p + step
		while str(cells.get(q, "")) == "point" and int(faces.get(q, -1)) in [-1, want]:
			ahead += 1
			q += step
		if cells.has(q):
			continue   # it ends in the weapon's body, not the open: no tip that way
		var behind := 0
		q = p - step
		while str(cells.get(q, "")) == "point" and int(faces.get(q, -1)) in [-1, want]:
			behind += 1
			q -= step
		var n := ahead + behind + 1
		if n < 2:
			continue
		var score := n * 10 + (5 if int(faces.get(p + step * ahead, -1)) == want else 0)
		if best.is_empty() or score > best[4]:
			best = [d[0], d[1], behind, n, score]
	return best

## An edge voxel's taper (no face set by the smith), drawn so the edge runs on unbroken from
## voxel to voxel round the blade's outline: each corner of it across the blade is thin when
## every voxel at that corner that meets the open air there is an edge facing that way, full when
## one is not (a blunt block, a point's broad base, the back of a horn). So the top block of an
## axe's edge, a blunt block beside it open above as well, faces out and not up (not roofed over,
## cut off from the wedge below it), and where a blade is cut round in steps the edge turns each
## step with the outline (user: the blade's corners did not join). Its open sides thin at both
## corners are the sides it narrows toward (honed); a corner thin alone is a corner bit.
static func _edge_code(cells: Dictionary, p: Vector3i, faces: Dictionary, memo: Dictionary) -> int:
	var th := _edge_axis(cells, p, memo)
	if th.is_empty():
		return 0
	var c: int = th[0]
	var thin := _thin_corners(cells, p, c, faces, memo)
	if thin == 0:
		return 0
	var code := (1 << (6 + c)) | _anchor_bit(c, int(th[1]))
	# Across the blade: axes a1 < a2 (the shader reads them so). Corner i: + or - on a1 (bit 0),
	# on a2 (bit 1).
	var a1 := 1 if c == 0 else 0
	var a2 := 1 if c == 2 else 2
	var left := thin
	for side in [[a1, 1, 5], [a1, -1, 10], [a2, 1, 3], [a2, -1, 12]]:
		var m: int = side[2]
		if thin & m == m and not cells.has(p + TAPER_AXES[side[0]] * int(side[1])):
			code |= 1 << (2 * int(side[0]) + (0 if int(side[1]) > 0 else 1))
			left &= ~m
	return code | (left << 16)

## A block behind a step of an edge (a blade cut round in steps: the edge's two voxels either
## side of the gap, this one behind the corner they meet at): thin at that corner with them, or it
## stands out full between their thin ends and the honed line breaks at every step. Bits 16..19,
## the corners (see _edge_code), with the blade's thickness pinched as theirs is.
static func _step_corners(cells: Dictionary, p: Vector3i, faces: Dictionary, memo: Dictionary) -> int:
	for c in 3:
		var d: Vector3i = TAPER_AXES[c]
		var up := cells.has(p + d)
		var down := cells.has(p - d)
		if up and down:
			continue
		var anchor := 0
		if up or down:
			anchor = 1 if up else -1
			if cells.has(p + d * 2 * anchor):
				continue   # three or more thick: a block
		var thin := _thin_corners(cells, p, c, faces, memo)
		if thin != 0:
			return (thin << 16) | (1 << (6 + c)) | _anchor_bit(c, anchor)
	return 0

static func _anchor_bit(c: int, anchor: int) -> int:
	return 0 if anchor == 0 else 1 << (2 * c + (10 if anchor > 0 else 11))

## Which of `p`'s four corners across a blade `c` thick are thin (bit i: corner i, see _edge_code).
static func _thin_corners(cells: Dictionary, p: Vector3i, c: int, faces: Dictionary, memo: Dictionary) -> int:
	var a1 := 1 if c == 0 else 0
	var a2 := 1 if c == 2 else 2
	var thin := 0
	for i in 4:
		var s1 := 1 if i & 1 == 0 else -1
		var s2 := 1 if i & 2 == 0 else -1
		if _corner_thin(cells, p, c, a1, s1, a2, s2, faces, memo):
			thin |= 1 << i
	return thin

## The corner of `p` toward s1 on a1 and s2 on a2: the four voxels round it across the blade, and
## for each one there that meets the open air at it, which way it faces it. Thin when one at least
## is an edge facing the air there and none is not (one voxel across, facing neither way, leaves
## it to the rest).
static func _corner_thin(cells: Dictionary, p: Vector3i, c: int, a1: int, s1: int, a2: int, s2: int, faces: Dictionary, memo: Dictionary) -> bool:
	var e1: Vector3i = TAPER_AXES[a1] * s1
	var e2: Vector3i = TAPER_AXES[a2] * s2
	var quad := [p, p + e1, p + e2, p + e1 + e2]
	# [from, to, axis, way]: the neighbours round the corner, each way.
	var sharp := false
	for pr in [[0, 1, a1, s1], [1, 0, a1, -s1], [0, 2, a2, s2], [2, 0, a2, -s2], [1, 3, a2, s2], [3, 1, a2, -s2], [2, 3, a1, s1], [3, 2, a1, -s1]]:
		var q: Vector3i = quad[pr[0]]
		if not cells.has(q) or cells.has(quad[pr[1]]):
			continue
		var st := _faces_air(cells, q, int(pr[2]), int(pr[3]), c, faces, memo)
		if st < 0:
			return false
		if st > 0:
			sharp = true
	return sharp

## Whether edge voxel `q` (a blade `c` thick) is sharp toward the open air on its side `s` along
## `d`: 1 it faces it, -1 it is no edge there (not an edge at all, a blade another way), 0 one
## voxel across, not facing that way. Open on that side only, it faces it. Open both ways (a horn
## of an axe, a dagger's blade): it faces the way the edge it runs in faces, or the gap where the
## edge turns round a step of the outline (the next voxel of the edge across the gap from it).
static func _faces_air(cells: Dictionary, q: Vector3i, d: int, s: int, c: int, faces: Dictionary, memo: Dictionary) -> int:
	if str(cells.get(q, "")) != "edge":
		return -1
	var th := _edge_axis(cells, q, memo)
	if th.is_empty() or int(th[0]) != c:
		return -1
	var f := int(faces.get(q, -1))
	if f >= 0 and f < 6:
		return 1 if f == 2 * d + (0 if s > 0 else 1) else -1
	var dv: Vector3i = TAPER_AXES[d]
	if cells.has(q - dv * s):
		return 1
	var e := 3 - c - d
	var ev: Vector3i = TAPER_AXES[e]
	for t: int in [1, -1]:
		if str(cells.get(q + dv * s + ev * t, "")) == "edge" and cells.has(q + ev * t):
			return 1
	# (Its back, the way the run does not face, is left to the rest: not sharp there, it does not
	# hold the corner full either, so a horn of an axe comes to a point at its end.)
	return 1 if _run_facing(cells, q, d, e, memo) == s else 0

## The way the edge `q` runs in (along `e`) faces across `d`: the nearest edge voxel of the run
## open on one side of `d` only; 0 when there is none (or the nearest two disagree).
static func _run_facing(cells: Dictionary, q: Vector3i, d: int, e: int, memo: Dictionary) -> int:
	var key := Vector4i(q.x, q.y, q.z, d)
	if memo.has(key):
		return memo[key]
	var dv: Vector3i = TAPER_AXES[d]
	var ev: Vector3i = TAPER_AXES[e]
	var found := 0
	var at := 99
	for t: int in [1, -1]:
		var r := q
		for i in range(1, 13):
			r += ev * t
			if str(cells.get(r, "")) != "edge":
				break
			var up := not cells.has(r + dv)
			var down := not cells.has(r - dv)
			if up != down:
				var f := 1 if up else -1
				if i < at:
					found = f
					at = i
				elif i == at and f != found:
					found = 0
				break
	memo[key] = found
	return found

## An edge voxel's thickness across the blade: [the axis it is thin along, the side its other
## half is on when the blade is two thick (+1/-1), else 0], or [] for a thick edge (a block). The
## way the weapon is thinnest round it, where it is open more than one way (a tie: the forge's
## depth).
static func _edge_axis(cells: Dictionary, p: Vector3i, memo: Dictionary) -> Array:
	if memo.has(p):
		return memo[p]
	var pinch := []
	var half := {}
	for a in 3:
		var d: Vector3i = TAPER_AXES[a]
		var up := not cells.has(p + d)
		var down := not cells.has(p - d)
		if up and down:
			pinch.append(a)
		elif up or down:
			var s := -1 if up else 1
			var q := p + d * s
			var j := str(cells.get(q, ""))
			if (j == "edge" or j == "point") and not cells.has(q + d * s):
				half[a] = s
	pinch.append_array(half.keys())
	var out := []
	if not pinch.is_empty():
		var best: int = pinch[0]
		if pinch.size() > 1:
			var span := INF
			for a in pinch:
				var w := _span(cells, p, a) + (0.0 if a == 2 else 0.1)
				if w < span:
					span = w
					best = a
		out = [best, int(half.get(best, 0))]
	memo[p] = out
	return out

## How far the weapon spans along axis `a` within a few voxels of `p` (its local thickness).
static func _span(cells: Dictionary, p: Vector3i, a: int) -> float:
	var lo := 0
	var hi := 0
	for x in range(-3, 4):
		for y in range(-3, 4):
			for z in range(-3, 4):
				var o := Vector3i(x, y, z)
				if cells.has(p + o):
					var k: int = o[a]
					lo = mini(lo, k)
					hi = maxi(hi, k)
	return float(hi - lo)

## What a material (data/materials.json) is drawn as: see shaders/voxel_body.gdshader.
static func kind_of_material(mat: String) -> int:
	match mat:
		"steel", "iron", "lead", "magnet", "spring": return 3
		"gold", "bronze": return 4
		"wood": return 5
		"bone", "stone": return 6
		"ruby", "emerald", "sapphire", "ice", "glue": return 7
		"leather", "rubber", "feather", "fish": return 2
	return 2

## What a fixed body colour is (data/body.json): red flesh under the skin, pale bone, the rest
## (eyes, mouth, belt, sandals) leather-like.
static func kind_of_body_color(c: Color) -> int:
	if c.r > 0.3 and c.r > c.g * 2.2 and c.r > c.b * 2.2:
		return 9
	if c.get_luminance() > 0.75:
		return 6
	return 2

static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

# ---------- Drawing ----------

func local_of(i: int) -> Vector3:
	return Vector3((fx[i] - (grid.x - 1) * 0.5) * vf, (fy[i] - (grid.y - 1) * 0.5) * vf, (fz[i] - (grid.z - 1) * 0.5) * vf) * part_scale

## Every voxel's local_of, worked out once (a voxel never moves in its part): a cut's passes over a
## big creature's limb read a thousand of them each.
var _lpos := PackedVector3Array()
var _lpos_s := -1.0   # (the voxel size they were worked out for: a part scaled anew has them anew)
func local_positions() -> PackedVector3Array:
	if _lpos.size() != fx.size() or _lpos_s != vf * part_scale:
		var lp := PackedVector3Array()
		lp.resize(fx.size())
		for i in fx.size():
			lp[i] = local_of(i)
		_lpos = lp
		_lpos_s = vf * part_scale
	return _lpos

## The living voxels whose local_of lies nearer than `r` to `p`, in index order (at most
## `limit` of them when it is above 0). VoxelCore does it when the extension is loaded.
func voxels_within(p: Vector3, r: float, limit := 0) -> PackedInt32Array:
	var nc := Greedy.core()
	if nc:
		return nc.within(fx, fy, fz, alive, grid, vf, part_scale, p, r, limit)
	return _within_script(p, r, limit)

func _within_script(p: Vector3, r: float, limit := 0) -> PackedInt32Array:
	# Without the extension (a player's own copy on Windows) only the grid's cells round the point
	# are gone over, not every voxel of the part: a lion's trunk has eleven thousand, and every spot
	# of fire on it asked two or three times a fifth of a second, 10 to 20 ms each time in script
	# (user: the frames drop when an enemy starts to burn or is poisoned). The same test on each
	# voxel, and the same ones in the same order as going over them all.
	var out := PackedInt32Array()
	var lps := local_positions()
	var n := fx.size()
	var s := vf * part_scale
	var lo := Vector3i.ZERO
	var hi := Vector3i(-1, -1, -1)
	if s > 0.0 and r > 0.0:
		var c := Vector3((grid.x - 1) * 0.5, (grid.y - 1) * 0.5, (grid.z - 1) * 0.5)
		var a := (p - Vector3(r, r, r)) / s + c
		var b := (p + Vector3(r, r, r)) / s + c
		lo = Vector3i(maxi(0, floori(a.x) - 1), maxi(0, floori(a.y) - 1), maxi(0, floori(a.z) - 1))
		hi = Vector3i(mini(grid.x - 1, ceili(b.x) + 1), mini(grid.y - 1, ceili(b.y) + 1), mini(grid.z - 1, ceili(b.z) + 1))
		if hi.x < lo.x or hi.y < lo.y or hi.z < lo.z:
			return out
	if s <= 0.0 or r <= 0.0 or (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1) >= n or not _cells_single():
		for i in n:
			if alive[i] and lps[i].distance_to(p) < r:
				out.append(i)
				if limit > 0 and out.size() >= limit:
					break
		return out
	var cm := cell_map()
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var row := (x * grid.y + y) * grid.z
			for z in range(lo.z, hi.z + 1):
				var i := cm[row + z] - 1
				if i >= 0 and alive[i] and lps[i].distance_to(p) < r:
					out.append(i)
	out.sort()
	if limit > 0 and out.size() > limit:
		out.resize(limit)
	return out

## Whether no two voxels share a cell of the grid (the cell map holds one each): then the cells round
## a point are all the voxels there. Worked out once.
var _single := -1
func _cells_single() -> bool:
	if _single < 0:
		var cm := cell_map()
		var n := 0
		for v in cm:
			if v > 0:
				n += 1
		var inside := 0
		for i in fx.size():
			if fx[i] >= 0 and fy[i] >= 0 and fz[i] >= 0 and fx[i] < grid.x and fy[i] < grid.y and fz[i] < grid.z:
				inside += 1
		_single = 1 if n == fx.size() and inside == fx.size() else 0
	return _single == 1

func world_of(i: int) -> Vector3:
	return global_transform * local_of(i)

func _build_mesh() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.8
		_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_material.rim_enabled = true
		_material.rim = 0.25
		_material.rim_tint = 0.6
	var key := snappedf(vf * part_scale, 0.0001)
	if not _box_mesh_cache.has(key):
		var bm := BoxMesh.new()
		# Full size: a hair smaller, the background showed through the seams between the voxels
		# of a body close to the camera (the menu's champion). The shader's darker edges still
		# mark out the blocks.
		bm.size = Vector3.ONE * vf * part_scale
		bm.material = body_material()
		_box_mesh_cache[key] = bm
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _box_mesh_cache[key]
	mm.instance_count = fx.size()
	_build_ao()
	for i in fx.size():
		mm.set_instance_transform(i, drawn_xf(i))
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, _custom(i))
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Not interpolated on its own: an interpolated multimesh kept drawing the voxels it was
	# built with, so every hole, cut and knocked-off piece stayed invisible. It is placed each
	# frame where the physics' interpolation has the body (_process), as the camera sees it: left
	# at the body's raw step-by-step place, every body juddered against the smoothly moving camera.
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.top_level = true
	# A fixed box the size of the whole part: knocking voxels out (scaling them to nothing) makes
	# Godot shrink the multimesh's own box to a sliver, and the part was then culled off screen.
	var ext := Vector3(grid.x, grid.y, grid.z) * vf * part_scale * 0.5 + Vector3.ONE * vf * part_scale
	mmi.custom_aabb = AABB(-ext, ext * 2.0)
	mm.custom_aabb = AABB(-ext, ext * 2.0)
	add_child(mmi)
	if smooth_skin and DisplayServer.get_name() != "headless":
		make_skin()

## Draws the part as a smooth skin (the voxel boxes hidden), built now and again whenever its
## voxels change.
func make_skin() -> void:
	if _skin_material == null:
		_skin_material = _material.duplicate()
		_skin_material.roughness = 0.72
	skin = MeshInstance3D.new()
	skin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	skin.top_level = true
	skin.material_override = _skin_material
	skin.custom_aabb = mmi.custom_aabb
	add_child(skin)
	mmi.visible = false
	rebuild_skin()

func rebuild_skin() -> void:
	_skin_dirty = false
	if skin == null:
		return
	skin.mesh = VoxelSkin.build(self, _skin_skip())

func _mark_skin() -> void:
	if skin != null and not _skin_dirty:
		_skin_dirty = true
		_rebuild_skin_soon()

func _rebuild_skin_soon() -> void:
	if not is_inside_tree():
		return
	# Once a frame at most, however many voxels a blow knocked out.
	await get_tree().process_frame
	if is_instance_valid(self) and _skin_dirty:
		rebuild_skin()

func refresh_colors(indices: Array = []) -> void:
	# Through the buffer, like set_shown: per-instance writes made the part vanish.
	var list: Array = indices if not indices.is_empty() else range(fx.size())
	var main := []
	var jaw := []
	var dang := []
	for i in list:
		if jaw_slot.has(i):
			jaw.append([jaw_slot[i], colors[i]])
		else:
			main.append([i, colors[i]])
			if dangle_slot.has(i):
				dang.append([dangle_slot[i], colors[i]])
	_write_colors(mm, main)
	if fine.has("body"):
		FineBody.colored(self, list)
	elif not fine.is_empty():
		FineHead.colored(self, list)
	if jaw_mm:
		_write_colors(jaw_mm, jaw)
	if dangle_mm:
		_write_colors(dangle_mm, dang)
	_write_glow(list)
	_mark_skin()

# ---------- Fire and poison on the voxels themselves (only how they look) ----------

var glowing := {}   # voxel -> Vector2(fire, poison) last written to its instance data
var _glow_n := Vector2i.ZERO   # how many of them glow with fire (x) and with poison (y)
const GLOW_STEP := 1.0 / 16.0  # how finely a glow's strength is written (_write_glow)

## Lights the voxels that fire or poison is working on (see Fire.tick, which heats them):
## burning ones glow and flicker orange in the shader, poisoned ones glow a sickly green. The
## nearest live spot says which; how hot (Fire's `heat`) says how much.
func _write_glow(list: Array) -> void:
	if mm == null or not mm.use_custom_data:
		return
	var live := spots.filter(func(s): return s.t > 0.0)
	if live.is_empty() and glowing.is_empty():
		return
	var reach := vf * part_scale * 8.0
	for i in list:
		var h: float = heat.get(i, 0.0)
		var g := Vector2.ZERO
		if h > 0.0 and alive[i] and not live.is_empty():
			var best = null
			var bd := INF
			var lp := local_of(i)
			for s in live:
				var d: float = lp.distance_to(s.lp)
				if d < bd:
					bd = d
					best = s
			if best != null and bd < reach:
				# (In sixteenths, and written again only when it moves one: the heat changes a
				# little every tick of the fire, and every burning voxel's fine cells were written
				# again each time, a frame's hitch for a few limbs alight. The flame's flicker is
				# the shader's own.)
				if best.kind == "fire":
					g.x = snappedf(clampf(h / 1.2, 0.15, 1.0), GLOW_STEP)
				else:
					g.y = snappedf(clampf(h / 0.8, 0.2, 1.0), GLOW_STEP)
		if g == glowing.get(i, Vector2.ZERO):
			continue
		_set_status(i, g)

func _set_status(i: int, g: Vector2) -> void:
	var c := _custom(i, g)
	if jaw_slot.has(i):
		if jaw_mm:
			jaw_mm.set_instance_custom_data(jaw_slot[i], c)
	else:
		mm.set_instance_custom_data(i, c)
	var was: Vector2 = glowing.get(i, Vector2.ZERO)
	_glow_n += Vector2i(int(g.x > 0.0) - int(was.x > 0.0), int(g.y > 0.0) - int(was.y > 0.0))
	if g == Vector2.ZERO:
		glowing.erase(i)
	else:
		glowing[i] = g
	# (Set before the fine look is told: the wound drawn over a voxel the fire ate reads its glow
	# from `glowing`. Told first, it read the fire still on it as it went out, and the burn's
	# wound flickered as if alight for good, user: the fire never went out.)
	if fine.has("body"):
		FineBody.status(self, i, g)

## What the part is made of where the first live spot of `kind` is: the nearest living voxel's
## kind of stuff (skin, cloth, fur...), as a BurnFx surface.
func _surface_at_spot(kind: String) -> String:
	for s in spots:
		if s.kind == kind and s.t > 0.0:
			# (The nearest among those round the spot, the reach widened until there are some, as
			# Fire._spot_on finds it: every voxel of the part gone over for each flame made, a
			# lion's trunk's eleven thousand, was a hitch as a beast caught fire, user.)
			var lp: Vector3 = s.lp
			var r := vf * part_scale * 2.0
			var far := half_ext.length() * 2.0 + r
			var found := PackedInt32Array()
			while r < far and found.is_empty():
				found = voxels_within(lp, r)
				r *= 2.0
			if found.is_empty():
				found = voxels_within(lp, far)
			var lps := local_positions()
			var best := -1
			var bd := INF
			for i in found:
				var d := lps[i].distance_squared_to(lp)
				if d < bd:
					bd = d
					best = i
			if best >= 0:
				return BurnFx.surface_of_kind(kinds[best])
	return "flesh"

## Whether any voxel glows with one kind (1 fire, 2 poison). (Counted as they are written: asked
## every frame of every part that burns, going over its glowing voxels was a cost of its own.)
func _has_glow(channel: int) -> bool:
	return (_glow_n.x if channel == 1 else _glow_n.y) > 0

## Puts out one kind of glow (1 fire, 2 poison) on every voxel that has it.
func _clear_glow(channel: int) -> void:
	if mm == null:
		return
	for i in glowing.keys():
		var g: Vector2 = glowing[i]
		if channel == 1:
			g.x = 0.0
		else:
			g.y = 0.0
		_set_status(i, g)

static func _write_colors(m: MultiMesh, rows: Array) -> void:
	# Per instance: with physics interpolation on, a whole-buffer write did not always reach the
	# screen (the part's box is fixed by custom_aabb, so single writes no longer cull it).
	for r in rows:
		m.set_instance_color(r[0], r[1])

## Draws every voxel again from `alive` and `colors`. Changes made before the part's first
## frame on screen were lost when the interpolated multimesh first drew (an old wound, a
## prosthetic fitted at spawn): they are put back with this once it has been drawn.
func resync() -> void:
	if mm == null:
		return
	# (Each voxel written as it is gone over: a list of them all built first, then written, was
	# most of the hitch when a big creature's bone broke and its limb was drawn bent.)
	var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	var jaw := not jaw_slot.is_empty()
	for i in fx.size():
		if jaw and jaw_slot.has(i):
			continue
		mm.set_instance_transform(i, drawn_xf(i) if alive[i] and not veiled(i) else none)
		mm.set_instance_color(i, colors[i])
	if dangle_mm:
		var d_on := []
		var d_off := []
		var d_col := []
		for i in dangle_slot:
			(d_on if alive[i] and not veiled(i) else d_off).append([dangle_slot[i], _dangle_base(i)])
			d_col.append([dangle_slot[i], colors[i]])
		_write_shown(dangle_mm, d_on, true)
		_write_shown(dangle_mm, d_off, false)
		_write_colors(dangle_mm, d_col)
		_bend_q = Quaternion(0, 0, 0, 0)
	if veil.size() > 0 or bevel:
		for i in fx.size():
			if not jaw_slot.has(i):
				mm.set_instance_custom_data(i, _custom(i, glowing.get(i, Vector2.ZERO)))
	_mark_skin()

func resync_later() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(self):
		resync()

## Old wounds (Body): the voxels a fight took stay gone, the hole healed over into a dent the
## shape of the blow, its rim the pale, shiny pink of scar tissue. No blood, no smear; and not a
## wound dealt now (the fighter is not told): a scar over the heart or the liver re-tore them at
## every spawn, and a man won his bout and bled to death in the yard (user).
const SCAR := Color(0.78, 0.5, 0.47)
const DUST := Color(0.78, 0.66, 0.48)   # the arena's sand, on a body that went down in it
var scarred := {}   # voxel -> true: the rim of an old wound, healed (drawn so by a finer look)
func scar(indices: Array) -> void:
	var gone := {}
	for i in indices:
		if i >= 0 and i < fx.size():
			gone[Vector3i(fx[i], fy[i], fz[i])] = true
	if gone.is_empty():
		return
	remove_voxels(indices, false, false)
	var touched := []
	for i in fx.size():
		if alive[i] == 0:
			continue
		var c := Vector3i(fx[i], fy[i], fz[i])
		var near := 0
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if gone.has(c + d):
				near += 1
		if near > 0:
			colors[i] = colors[i].lerp(SCAR, 0.45 + 0.1 * minf(3.0, near))
			scarred[i] = true
			touched.append(i)
	refresh_colors(touched)

## Blood runs from a wound at `lp` (part-local) for as long as the part bleeds: a dripping
## emitter there, at most a few per part (a new wound near an old one shares its drip).
const MAX_DRIPS := 4
func add_drip(lp: Vector3) -> void:
	if Fx.current == null or Fx.current.headless or freeze or severed:
		return
	for d in drips:
		if is_instance_valid(d.node) and (d.lp as Vector3).distance_to(lp) < vf * part_scale * 3.0:
			return
	if drips.size() >= MAX_DRIPS:
		var old = drips.pop_front()
		if is_instance_valid(old.node):
			old.node.queue_free()
	var ps: GPUParticles3D = Fx.current.emitter("drip", self, 26, vf * part_scale * 0.8)
	if ps == null:
		return
	ps.position = lp
	drips.append({"node": ps, "lp": lp})

## A limb cut off: for the first seconds the stump pours out along where the limb was, in gushes
## with the beat, and the blood comes down on the sand under it. Drawing only (what he loses is the
## stump's bleeding: Fighter); the drip it leaves after is add_drip's.
const STREAM_T := 3.2
func add_stream(lp: Vector3) -> void:
	var fx_ := Fx.current
	if fx_ == null or fx_.headless or freeze or severed:
		return
	var ps: GPUParticles3D = fx_.emitter("stream", self, 70, vf * part_scale * 0.9)
	if ps == null:
		return
	ps.position = lp
	var o := lp.normalized() if lp.length_squared() > 1e-8 else Vector3.DOWN
	var axis := Vector3.UP.cross(o)
	if axis.length_squared() > 1e-6:
		ps.basis = Basis(axis.normalized(), Vector3.UP.angle_to(o))
	elif o.y < 0.0:
		ps.basis = Basis(Vector3.RIGHT, PI)
	ps.emitting = true
	var pulse := func(t: float) -> void:
		var beat := pow(0.5 + 0.5 * cos(t * TAU * 1.4), 2.0)
		ps.amount_ratio = clampf(0.2 + 0.8 * beat * (1.0 - t / STREAM_T), 0.05, 1.0)
	var tw := ps.create_tween()
	tw.tween_method(pulse, 0.0, STREAM_T, STREAM_T)
	tw.tween_callback(func() -> void: ps.emitting = false)
	tw.tween_interval(1.2)
	tw.tween_callback(ps.queue_free)
	# (Where it comes down it pools, a little out from the stump the way it pours.)
	var me := weakref(self)
	for k in 10:
		get_tree().create_timer(0.35 + 0.3 * k, false).timeout.connect(func() -> void:
			var pt = me.get_ref()
			if pt != null and is_instance_valid(fx_) and not pt.severed:
				var at: Vector3 = pt.to_global(lp)
				var out: Vector3 = pt.global_transform.basis.orthonormalized() * o
				fx_.blood_at(Vector3(at.x + out.x * 0.3, 0.0, at.z + out.z * 0.3), 0.28 * (1.0 - 0.05 * k)))

## The drips follow how hard the part bleeds: heavier while it pours, gone once it has closed.
## What they let fall pools on the sand under them (a man who stands bleeding stands in his blood;
## one who walks leaves a trail).
var _pool_at := 0.0
func update_drips() -> void:
	if drips.is_empty():
		return
	var flow := clampf((bleed + (2.0 if stump else 0.0)) / 1.2, 0.0, 1.0)
	var pool_now := false
	if flow > 0.03 and Fx.current != null and not Fx.current.headless and clock() >= _pool_at:
		_pool_at = clock() + 0.5
		pool_now = true
	for i in range(drips.size() - 1, -1, -1):
		var d = drips[i]
		if not is_instance_valid(d.node) or severed:
			if is_instance_valid(d.node):
				d.node.queue_free()
			drips.remove_at(i)
			continue
		var ps: GPUParticles3D = d.node
		ps.emitting = flow > 0.03
		ps.amount_ratio = clampf(0.15 + flow, 0.15, 1.0)
		if pool_now and ps.emitting:
			var at := ps.global_position
			Fx.current.blood_at(Vector3(at.x, 0.0, at.z), 0.06 + 0.14 * flow)

# ---------- Blood on the body ----------
# Every open wound bleeds where it is: blood runs down the skin from it the way gravity takes it
# now (a fighter lying down bleeds sideways), voxel by voxel, while it still bleeds. A cut artery
# (the throat, the groin, the armpit, the heart) bleeds hard for long and spurts with each beat.

const MAX_RUNS := 6
var artery := 0.0              # how hard a cut artery bleeds (adds to the bleeding; slow to close)
const ARTERY_CLOSE := 0.03      # how fast a cut artery closes of itself (a second)
var runs: Array = []           # {lp, len, t}: blood running down from a wound
var spurts: Array = []         # {node, lp, out}: arterial jets
var _blood_t := 0.0
var _run_k := 0

## A wound opens at `lp` (local), the blood coming out along `out` (local): it runs from there,
## and an artery spurts.
func open_wound(lp: Vector3, out: Vector3, cut_artery: bool, rate := 6.0) -> void:
	if severed:
		return
	var near := false
	for r in runs:
		if (r.lp as Vector3).distance_to(lp) < vf * part_scale * 3.0:
			near = true
			break
	if not near:
		if runs.size() >= MAX_RUNS:
			runs.pop_front()
		runs.append({"lp": lp, "len": 0.0, "t": 0.0})
	if cut_artery:
		artery = maxf(artery, rate)
		if Fx.current and not Fx.current.headless and spurts.size() < 2:
			var ps: GPUParticles3D = Fx.current.emitter("spurt", self, 60, vf * part_scale * 0.6)
			if ps:
				ps.position = lp
				var o := out.normalized() if out.length_squared() > 1e-6 else Vector3.UP
				var axis := Vector3.UP.cross(o)
				if axis.length_squared() > 1e-6:
					ps.basis = Basis(axis.normalized(), Vector3.UP.angle_to(o))
				spurts.append({"node": ps, "lp": lp})

## Each tick: the blood runs further down while the part bleeds; the jets pulse with the heart
## (`beat` 0..1, 0 when it has stopped). Painting is a few voxels a tick at most.
func update_blood(dt: float, beat: float) -> void:
	artery = maxf(0.0, artery - dt * ARTERY_CLOSE)
	var flow := bleed + artery
	for s in spurts:
		if is_instance_valid(s.node):
			(s.node as GPUParticles3D).emitting = artery > 0.3 and beat > 0.55 and not severed
	if runs.is_empty() or flow < 0.05:
		return
	_blood_t += dt
	if _blood_t < 0.18:
		return
	_blood_t = 0.0
	var down := (global_transform.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
	var step := vf * part_scale
	var painted := []
	# Two runs a tick at most, in turn (each one looks over the part's voxels).
	for kk in mini(2, runs.size()):
		_run_k = (_run_k + 1) % runs.size()
		var r: Dictionary = runs[_run_k]
		var reach := minf(half_ext.length() * 2.2, 0.03 + flow * 0.06 + r.t * 0.02)
		if r.len >= reach:
			continue
		r.len += step
		r.t += 0.18
		var want: Vector3 = (r.lp as Vector3) + down * r.len
		var best := -1
		var bd := INF
		var nc := Greedy.core()
		if nc:
			var got: PackedFloat64Array = nc.skin_nearest(fx, fy, fz, alive, grid, vf, part_scale, half_ext, step * 1.6, want)
			best = int(got[0])
			bd = got[1]
		else:
			for i in fx.size():
				if alive[i] == 0:
					continue
				var q := local_of(i)
				# Only the skin shows it: a voxel near one of the part's faces.
				var depth := minf(minf(half_ext.x - absf(q.x), half_ext.y - absf(q.y)), half_ext.z - absf(q.z))
				if depth > step * 1.6:
					continue
				var d := q.distance_squared_to(want)
				if d < bd:
					bd = d
					best = i
		if best >= 0 and bd < pow(step * 2.5, 2.0):
			colors[best] = colors[best].lerp(SMEAR, 0.75)
			painted.append(best)
	if not painted.is_empty():
		refresh_colors(painted)

## Paint a wound: blood soaks in around cuts, bruises darken under blunt blows (and swell, unless
## `swell` is false: round a hole, where the hole is what shows).
func wound(lp: Vector3, r: float, kind := "blood", swell := true) -> int:
	var target := BRUISE if kind == "bruise" else (DUST if kind == "dust" else SMEAR)
	var mx := 0.55 if kind == "bruise" else (0.5 if kind == "dust" else 0.9)
	var touched := []
	var lps := local_positions()
	for i in voxels_within(lp, r):
		var d := lps[i].distance_to(lp)
		var k := mx * pow(1.0 - d / r, 0.6)
		if k < 0.08:
			continue
		colors[i] = colors[i].lerp(target, k)
		touched.append(i)
	refresh_colors(touched)
	# A bruise swells (only how the skin is drawn: FineBody.swell).
	if kind == "bruise" and swell and fine.has("body") and not touched.is_empty():
		FineBody.swell(self, lp, r * 1.2, clampf(r / (vf * part_scale) * 0.24, 0.2, 0.6))
	return touched.size()

# ---------- Losing voxels ----------

var integrity: float:
	get:
		return float(alive_count) / maxf(1, fx.size())

## How well it still works, 0..1 (0 when severed).
var frozen_until := 0.0   # seconds (physics clock, VoxelPart.clock()) until a sapphire's frost lets go of it

## The physics' own clock, seconds: the same however fast the frames come (a frost timed on
## the wall clock thawed sooner or later with the machine's load).
static func clock() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)

func function() -> float:
	if severed:
		return 0.0
	if hanging:
		return 0.03
	if fractured:
		return 0.04   # broken through: the muscle cannot move what the bone no longer holds
	# (A prosthetic is whole as the physician made it, not as the limb it took the place of: a
	# smaller thing, it is measured against what it was when fitted.)
	var whole := integrity if prosthetic == "" or pro_full <= 0 else minf(1.0, float(alive_count) / float(pro_full))
	var fn := clampf(hp / 100.0, 0.0, 1.0) * (0.4 + 0.6 * whole)
	if fracture == 1:
		fn *= 0.75    # cracked: it holds, and every move of it hurts (at 0.6, with the blow's harm, one
		              # blow left an arm no use: user)
	if prosthetic != "":
		fn = minf(fn, Body.pro_fn(prosthetic, pro_level))
	if frozen_until > 0.0 and clock() < frozen_until:
		fn *= 0.2   # frozen stiff by a sapphire: it hardly moves until it thaws
	return fn

## Knocks out voxels; returns [{p: world position, color}].
# ---------- corner shading (ambient occlusion) ----------

## The faces in the order of ao_bits, each with the two axes across it: +x -x +y -y +z -z.
const AO_FACES := [[Vector3i(1, 0, 0), 1, 2], [Vector3i(-1, 0, 0), 1, 2], [Vector3i(0, 1, 0), 0, 2], [Vector3i(0, -1, 0), 0, 2], [Vector3i(0, 0, 1), 0, 1], [Vector3i(0, 0, -1), 0, 1]]

func _cell(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= grid.x or y >= grid.y or z >= grid.z:
		return -1
	return cellmap[(x * grid.y + y) * grid.z + z] - 1

func _solid(c: Vector3i) -> bool:
	var i := _cell(c.x, c.y, c.z)
	return i >= 0 and alive[i] == 1 and not veiled(i)

func veiled(i: int) -> bool:
	return i < veil.size() and veil[i] == 1

## Voxel i's open faces as bevel bits for the shader (0 when the part is not bevelled).
func bevel_bits(i: int) -> int:
	if not bevel:
		return 0
	var p := Vector3i(fx[i], fy[i], fz[i])
	var m := 0
	for f in 6:
		if not _solid(p + (AO_FACES[f][0] as Vector3i)):
			m |= 1 << f
	return m

## What the listed voxels are made of has changed (a prosthetic fitted): their instance data
## written again, so the shader draws them as what they now are.
func refresh_kinds(indices: Array) -> void:
	if mm == null or not mm.use_custom_data:
		return
	for i in indices:
		if not jaw_slot.has(i):
			mm.set_instance_custom_data(i, _custom(i, glowing.get(i, Vector2.ZERO)))

## The instance data of voxel i as it is drawn now: its kind, corner shade, bevel and glow.
func _custom(i: int, g := Vector2.ZERO) -> Color:
	var c := kind_data(kinds[i], ao[i] if i < ao.size() else 0, bev[i] if i < bev.size() else 0)
	c.g = g.x
	c.b = g.y
	return c

## Voxel i's 24 corner bits, 4 per face (face * 4 + corner; corner bit 0 the low end of the
## face's first axis, bit 1 the high end of its second). A corner is shut in when a voxel sits
## beside the face toward it, either way along the face or across the corner.
func ao_bits(i: int) -> int:
	var bits := 0
	var p := Vector3i(fx[i], fy[i], fz[i])
	for f in 6:
		var fd: Array = AO_FACES[f]
		var n: Vector3i = p + (fd[0] as Vector3i)
		if _solid(n):
			continue   # a face against a voxel is never seen
		var ua := Vector3i.ZERO
		ua[int(fd[1])] = 1
		var va := Vector3i.ZERO
		va[int(fd[2])] = 1
		for c in 4:
			var su := 1 if c & 1 else -1
			var sv := 1 if c & 2 else -1
			if _solid(n + ua * su) or _solid(n + va * sv) or _solid(n + ua * su + va * sv):
				bits |= 1 << (f * 4 + c)
	return bits

## One face's ao_bits from the 3x3 cells beside it (cell (u+1)*3 + v+1, u and v across the face
## as AO_FACES gives them, the middle one against the face): 0 when that one is solid.
static var _face_ao := PackedInt32Array()

static func _face_ao_table() -> PackedInt32Array:
	if _face_ao.is_empty():
		var t := PackedInt32Array()
		t.resize(512)
		for p in 512:
			var bits := 0
			if (p & 16) == 0:
				for c in 4:
					var u := 2 if c & 1 else 0
					var v := 2 if c & 2 else 0
					if p & (1 << (u * 3 + 1)) or p & (1 << (3 + v)) or p & (1 << (u * 3 + v)):
						bits |= 1 << c
			t[p] = bits
		_face_ao = t
	return _face_ao

## The grid steps to a cell's 27 (itself and the 26 round it), in shade_bits' order: x, then y,
## then z, each -1 to 1.
var _offs27 := PackedInt32Array()
func _offsets27() -> PackedInt32Array:
	if _offs27.size() != 27:
		var o := PackedInt32Array()
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					o.append((dx * grid.y + dy) * grid.z + dz)
		_offs27 = o
	return _offs27

## ao_bits (bits 0-23) and bevel_bits (24-29) of voxel i together, each of the 27 cells round it
## read once: the two read a cell up to 28 times over, and a cut on a big creature's limb
## reshades a thousand voxels (a hitch of 3-8 ms on a gorilla's leg). The same bits (tested).
func shade_bits(i: int) -> int:
	var gx := grid.x
	var gy := grid.y
	var gz := grid.z
	var vs := veil.size()
	var x := fx[i]
	var y := fy[i]
	var z := fz[i]
	var occ := 0   # bit a*9 + b*3 + c: the cell (x+a-1, y+b-1, z+c-1) is solid
	if x > 0 and y > 0 and z > 0 and x < gx - 1 and y < gy - 1 and z < gz - 1:
		var base := (x * gy + y) * gz + z
		var offs := _offsets27()
		for k in 27:
			var q := cellmap[base + offs[k]] - 1
			if q >= 0 and alive[q] == 1 and (q >= vs or veil[q] == 0):
				occ |= 1 << k
	else:
		var c0 := maxi(0, 1 - z)
		var c1 := mini(3, gz + 1 - z)
		for a in range(maxi(0, 1 - x), mini(3, gx + 1 - x)):
			for b in range(maxi(0, 1 - y), mini(3, gy + 1 - y)):
				var row := ((x + a - 1) * gy + y + b - 1) * gz + z - 1
				var bit := a * 9 + b * 3
				for c in range(c0, c1):
					var q := cellmap[row + c] - 1
					if q >= 0 and alive[q] == 1 and (q >= vs or veil[q] == 0):
						occ |= 1 << (bit + c)
	# The 3x3 beside each face, in the table's order: +x -x +y -y, then +z and -z (every third bit).
	var t := _face_ao_table()
	var pz := (occ >> 2) & 0x1249249
	pz = (pz ^ (pz >> 2)) & 0x30c30c3
	pz = (pz ^ (pz >> 4)) & 0x300f00f
	pz = (pz ^ (pz >> 8)) & 0xff0000ff
	pz = (pz ^ (pz >> 16)) & 0x3ff
	var mz := occ & 0x1249249
	mz = (mz ^ (mz >> 2)) & 0x30c30c3
	mz = (mz ^ (mz >> 4)) & 0x300f00f
	mz = (mz ^ (mz >> 8)) & 0xff0000ff
	mz = (mz ^ (mz >> 16)) & 0x3ff
	var bits := t[(occ >> 18) & 511] | (t[occ & 511] << 4) \
		| (t[((occ >> 6) & 7) | ((occ >> 12) & 56) | ((occ >> 18) & 448)] << 8) \
		| (t[(occ & 7) | ((occ >> 6) & 56) | ((occ >> 12) & 448)] << 12) \
		| (t[pz] << 16) | (t[mz] << 20)
	if not bevel:
		return bits
	var shut := ((occ >> 22) & 1) | ((occ >> 3) & 2) | ((occ >> 14) & 4) | ((occ >> 7) & 8) | ((occ >> 10) & 16) | ((occ >> 7) & 32)
	return bits | ((63 ^ shut) << 24)

func _build_ao() -> void:
	cellmap.resize(grid.x * grid.y * grid.z)
	cellmap.fill(0)
	for i in fx.size():
		if fx[i] >= 0 and fy[i] >= 0 and fz[i] >= 0 and fx[i] < grid.x and fy[i] < grid.y and fz[i] < grid.z:
			cellmap[(fx[i] * grid.y + fy[i]) * grid.z + fz[i]] = i + 1
	ao.resize(fx.size())
	bev.resize(fx.size())
	for i in fx.size():
		var s := shade_bits(i)
		ao[i] = s & 0xffffff
		bev[i] = s >> 24

## Voxels gone or back: the shading of the ones round them follows (a cut opens its edges to
## the light, a hole's walls lie in its shadow).
func _reshade(changed: Array) -> void:
	if mm == null or ao.size() != fx.size():
		return
	var gx := grid.x
	var gy := grid.y
	var gz := grid.z
	var n := fx.size()
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	var todo := PackedInt32Array()
	var offs := _offsets27()
	for i in changed:
		if i < 0 or i >= n:
			continue
		var x := fx[i]
		var y := fy[i]
		var z := fz[i]
		if x > 0 and y > 0 and z > 0 and x < gx - 1 and y < gy - 1 and z < gz - 1:
			var base := (x * gy + y) * gz + z
			for o in offs:
				var j := cellmap[base + o] - 1
				if j >= 0 and seen[j] == 0 and alive[j] == 1:
					seen[j] = 1
					todo.append(j)
			continue
		for ax in range(maxi(x - 1, 0), mini(x + 2, gx)):
			for ay in range(maxi(y - 1, 0), mini(y + 2, gy)):
				var row := (ax * gy + ay) * gz
				for az in range(maxi(z - 1, 0), mini(z + 2, gz)):
					var j := cellmap[row + az] - 1
					if j >= 0 and seen[j] == 0 and alive[j] == 1:
						seen[j] = 1
						todo.append(j)
	var nb := bev.size()
	for j in todo:
		var s := shade_bits(j)
		var b := s & 0xffffff
		var bb := s >> 24
		if b == ao[j] and (j >= nb or bb == bev[j]):
			continue
		ao[j] = b
		if j < nb:
			bev[j] = bb
		_set_status(j, glowing.get(j, Vector2.ZERO))

func remove_voxels(indices: Array, smear := true, notify := true) -> Array:
	var out := []
	var done := []
	var centre := Vector3.ZERO
	var lps := local_positions()
	var gt := global_transform
	for i in indices:
		if i < 0 or i >= fx.size() or alive[i] == 0:
			continue
		alive[i] = 0
		alive_count -= 1
		_cell_out(i)
		done.append(i)
		out.append({"p": gt * lps[i], "color": colors[i], "kind": kinds[i], "veil": veiled(i)})
		centre += lps[i]
	if out.is_empty():
		return out
	set_shown(done, false)
	_reshade(done)
	if smear:
		centre /= out.size()
		wound(centre, vf * part_scale * (2.2 + pow(out.size(), 1.0 / 3.0) * 0.8), "blood")
	fit_collider()
	if notify and fighter and fighter.has_method("on_part_voxels_lost"):
		fighter.on_part_voxels_lost(self, done, out)
	return out

## Cut through below where it hangs: what of it the blade did not take (`indices`, the side the
## part it hangs from is on) stays on him as the limb's stump, not on the falling piece. All it is
## drawn with there (its skin, the plates of its armour, the cut across it) is drawn on that part
## from now on, where it was, and moves with it; the piece no longer draws it. Drawing only: what a
## blade meets there is that part, as at any stump; the voxels go from the piece as they always did.
## (They went and were drawn nowhere: a forearm cut below the elbow came off at the elbow, the length
## of it between gone, user: every falling piece must be the very piece cut off him.)
## Returns the middle of the cut across the stump in that part's frame (null: nothing was drawn).
func leave_on_stump(indices: Array):
	var host = parent_part
	if host == null or not is_instance_valid(host) or not is_inside_tree() or mm == null:
		return null
	if DisplayServer.get_name() == "headless" or (Fx.current != null and Fx.current.headless):
		return null
	var mine := {}
	for i in indices:
		if (i is int or i is float) and int(i) >= 0 and int(i) < fx.size() and alive[int(i)] == 1:
			mine[int(i)] = true
	if mine.is_empty():
		return null
	var lps := local_positions()
	# Where it sat on the part it hangs from, its joint closed (a blow had pulled it off a little).
	var rel: Transform3D = (host as VoxelPart).global_transform.affine_inverse() * global_transform
	rel.basis = rel.basis.orthonormalized()
	rel.origin = pa - rel.basis * ca   # (pa: its joint's point on the part it hangs from)
	var made := 0
	for src in [mmi] + draw_with:
		if not (src is MultiMeshInstance3D) or not is_instance_valid(src) or not (src as MultiMeshInstance3D).visible:
			continue
		var smm: MultiMesh = (src as MultiMeshInstance3D).multimesh
		if smm == null or smm.mesh == null:
			continue
		var n := smm.instance_count if smm.visible_instance_count < 0 else smm.visible_instance_count
		# (Read off its buffer at once, 12 floats of its place a voxel then its colour and its data:
		# asked one at a time, a limb's few thousand fine voxels were a hitch of their own.)
		var buf := smm.buffer
		var stride := 12 + (4 if smm.use_colors else 0) + (4 if smm.use_custom_data else 0)
		var take := []
		for k in mini(n, buf.size() / stride):
			var o := k * stride
			if buf[o] * buf[o] + buf[o + 4] * buf[o + 4] + buf[o + 8] * buf[o + 8] < 1e-12:
				continue   # (not drawn)
			if _side_of(Vector3(buf[o + 3], buf[o + 7], buf[o + 11]), mine, lps) == 1:
				take.append(k)
		if take.is_empty():
			continue
		var cm := MultiMesh.new()
		cm.transform_format = MultiMesh.TRANSFORM_3D
		cm.use_colors = smm.use_colors
		cm.use_custom_data = smm.use_custom_data
		cm.mesh = smm.mesh
		cm.instance_count = take.size()
		var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
		var box := AABB()
		for q in take.size():
			var k: int = take[q]
			var t := rel * smm.get_instance_transform(k)
			cm.set_instance_transform(q, t)
			box = AABB(t.origin, Vector3.ZERO) if q == 0 else box.expand(t.origin)
			if smm.use_colors:
				cm.set_instance_color(q, smm.get_instance_color(k))
			if smm.use_custom_data:
				cm.set_instance_custom_data(q, smm.get_instance_custom_data(k))
			smm.set_instance_transform(k, none)   # (the piece no longer has it)
		box = box.grow(vf * part_scale * 2.0)
		cm.custom_aabb = box
		var mi := MultiMeshInstance3D.new()
		mi.name = "stump_end"
		mi.multimesh = cm
		mi.material_override = (src as MultiMeshInstance3D).material_override
		mi.top_level = true
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mi.custom_aabb = box
		mi.transparency = (host as VoxelPart).see_through
		host.add_child(mi)
		mi.global_transform = (host as VoxelPart).global_transform
		(host as VoxelPart).draw_with.append(mi)
		made += 1
	if made == 0:
		return null
	# The cut across it: those of its voxels the blade bared (beside a voxel it took).
	var face := Vector3.ZERO
	var nf := 0
	var gy := grid.y
	var gz := grid.z
	for i in mine:
		var x := fx[i]
		var y := fy[i]
		var z := fz[i]
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			var nz: int = z + d.z
			if nx < 0 or ny < 0 or nz < 0 or nx >= grid.x or ny >= gy or nz >= gz:
				continue
			var j := cellmap[(nx * gy + ny) * gz + nz] - 1
			if j >= 0 and alive[j] == 0 and not mine.has(j):
				face += lps[i]
				nf += 1
				break
	if nf == 0:
		var far := -1.0
		for i in mine:
			var dd := lps[i].distance_squared_to(ca)
			if dd > far:
				far = dd
				face = lps[i]
		nf = 1
	return rel * (face / float(nf))

## Which side of a cut a point of the part lies on (its own frame): 1 that of `mine`, 2 the rest
## of the living voxels, 0 none near: the side of the voxel nearest it, looked for a few voxels
## round it at most (the plates of armour lie a voxel or two out from him).
func _side_of(o: Vector3, mine: Dictionary, lps: PackedVector3Array) -> int:
	var vox := vf * part_scale
	var g := o / vox + Vector3((grid.x - 1) * 0.5, (grid.y - 1) * 0.5, (grid.z - 1) * 0.5)
	var gx := roundi(g.x)
	var gyy := roundi(g.y)
	var gzz := roundi(g.z)
	for r in 4:
		var best := 0
		var bd := INF
		for dx in range(-r, r + 1):
			var x := gx + dx
			if x < 0 or x >= grid.x:
				continue
			for dy in range(-r, r + 1):
				var y := gyy + dy
				if y < 0 or y >= grid.y:
					continue
				for dz in range(-r, r + 1):
					if maxi(absi(dx), maxi(absi(dy), absi(dz))) != r:
						continue
					var z := gzz + dz
					if z < 0 or z >= grid.z:
						continue
					var j := cellmap[(x * grid.y + y) * grid.z + z] - 1
					if j < 0 or alive[j] == 0:
						continue
					var d := lps[j].distance_squared_to(o)
					if d < bd:
						bd = d
						best = 1 if mine.has(j) else 2
		if best != 0:
			return best
	return 0

## Shows or hides voxels by writing the multimesh's instance buffer in one go (12 transform
## floats then 4 colour floats per voxel). Setting a single instance's transform after the first
## frame made Godot drop the whole part from the screen, which hid every wounded body part.
func set_shown(indices: Array, on: bool) -> void:
	var main := []
	var jaw := []
	var dang := []
	# (Hidden, a voxel is drawn at no size wherever it was: where it would be drawn is not worked
	# out for each one a limb cut off leaves behind.)
	for i in indices:
		if i < 0 or i >= fx.size() or (on and veiled(i)):
			continue
		if jaw_slot.has(i):
			jaw.append([jaw_slot[i], (local_of(i) - jaw_pivot.position) if on else Vector3.ZERO])
		else:
			main.append([i, drawn_xf(i) if on else Transform3D()])
			if dangle_slot.has(i):
				dang.append([dangle_slot[i], _dangle_base(i) if on else Transform3D()])
	_write_shown(mm, main, on)
	if fine.has("body"):
		FineBody.shown(self, indices, on)
	elif not fine.is_empty():
		FineHead.shown(self, indices, on)
	if dangle_mm:
		_write_shown(dangle_mm, dang, on)
		_bend_q = Quaternion(0, 0, 0, 0)
	_mark_skin()
	if jaw_mm:
		_write_shown(jaw_mm, jaw, on)
		if not jaw.is_empty():
			# The teeth and the gullet go with the jaw: hacked mostly away, nothing floats there.
			var left := 0
			for i in jaw_slot:
				left += alive[i]
			var keep := left > jaw_slot.size() * 0.35
			jaw_teeth = keep
			for c in jaw_pivot.get_children():
				if c is MeshInstance3D:
					c.visible = keep and (not c.name.begins_with("Tooth") or jaw_angle > 0.08)
			if jaw_mouth:
				for c in jaw_mouth.get_children():
					c.visible = keep

static func _write_shown(m: MultiMesh, rows: Array, on: bool) -> void:
	if not on:
		var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
		for r in rows:
			m.set_instance_transform(r[0], none)
		return
	for r in rows:
		if r[1] is Transform3D:
			m.set_instance_transform(r[0], r[1])
		else:
			m.set_instance_transform(r[0], Transform3D(Basis(), r[1]))

## How voxel i is drawn in a look that reshapes the man (Physique, "strong"): moved and sized
## within the part. Drawing only: local_of, every blow, cut and collider keep the cube.
var shape_xf: Array = []
func drawn_xf(i: int) -> Transform3D:
	var t: Transform3D = shape_xf[i] if i < shape_xf.size() else Transform3D(Basis(), local_positions()[i])
	if dangle_slot.has(i):
		return Transform3D(Basis().scaled(Vector3.ZERO), t.origin)   # (drawn swinging, below)
	if not kink.is_empty() and _past_break(i):
		t = (kink[2] as Transform3D) * t
	return t

## The voxel lies on the far side of the break, away from the joint the part hangs by.
func _past_break(i: int) -> bool:
	var ax: int = kink[0]
	var c: float = local_positions()[i][ax] - float(kink[1])
	return c < 0.0 if bool(kink[3]) else c > 0.0

## The broken bone drawn bent at `at` (part-local, on the bone): the far end turned `angle` about a
## line across the bone, the one `code` names (0..3: which line across and which way round, the
## same on every screen). 0 straightens it.
func set_kink(at: Vector3, angle: float, code: int) -> void:
	if angle == 0.0:
		hide_bone()
		_stop_dangle()
		if not kink.is_empty():
			kink = []
			resync()
		return
	var kb := _kink_basis(at, angle, code)
	var ra := _root_axis()
	kink = [int(ra[0]), float(kb[1]), kb[0], bool(ra[1]), code, angle]
	_start_dangle()
	resync()

## The two unit lines across the bone, and the far end's way along it (from the break out to the
## end the part does not hang by).
func _across() -> Array:
	var ra := _root_axis()
	var ax: int = ra[0]
	var e1 := Vector3.ZERO
	e1[(ax + 1) % 3] = 1.0
	var e2 := Vector3.ZERO
	e2[(ax + 2) % 3] = 1.0
	var tip := Vector3.ZERO
	tip[ax] = -1.0 if bool(ra[1]) else 1.0
	return [e1, e2, tip]

## The way the far end was pushed, across the bone: `code` 0..255 is its angle round the bone (any
## way at all, as the blow came in).
func kink_push(code: int) -> Vector3:
	var ac := _across()
	var th := TAU * float(code) / 256.0
	return ((ac[0] as Vector3) * cos(th) + (ac[1] as Vector3) * sin(th)).normalized()

## How far from its middle a bone breaks, of its half length: in the middle of the shaft only, two
## fifths of the bone or more from either joint (user: open breaks only mid-limb; at 0.45 of the
## part a shin struck low broke out by the ankle, at 0.3 still low on it). The bone's own middle
## and length, not the part's: a shin's part takes in the foot, a forearm's the hand.
const BREAK_MID := 0.2

## Where along the part's bone it can break (part-local, along its length): [low, high].
func break_range() -> Vector2:
	var ax: int = _root_axis()[0]
	var lo := INF
	var hi := -INF
	for i in fx.size():
		if bone[i]:
			var q: float = local_of(i)[ax]
			lo = minf(lo, q)
			hi = maxf(hi, q)
	if lo > hi:
		lo = -half_ext[ax]
		hi = half_ext[ax]
	# A man's shin takes in his foot, his forearm his hand: the shaft of the bone stops short of
	# them (a fifth of the part), so its middle is higher up (a shin broke out by the ankle).
	var n := String(part_name)
	if n.begins_with("shin") or n.begins_with("forearm"):
		var trim := (hi - lo) * 0.22
		if float((_across()[2] as Vector3)[ax]) < 0.0:
			lo += trim
		else:
			hi -= trim
	var mid := (lo + hi) * 0.5
	var h := (hi - lo) * 0.5 * BREAK_MID
	return Vector2(mid - h, mid + h)

func _kink_basis(at: Vector3, angle: float, code: int) -> Array:
	var ax: int = _root_axis()[0]
	var tip: Vector3 = _across()[2]
	var push := kink_push(code)
	# The far end turned toward where the blow drove it, about the line across the bone at right
	# angles to both.
	var across := tip.cross(push).normalized()
	var pivot := Vector3.ZERO
	if not has_meta("break_range"):
		set_meta("break_range", break_range())
	var br: Vector2 = get_meta("break_range")
	pivot[ax] = clampf(at[ax], br.x, br.y)
	var b := Basis(across, angle)
	return [Transform3D(b, pivot - b * pivot), pivot[ax]]

## Which way it is bent: the far end pushed along `ld` (part-local, the blow's own way, at any
## angle round the bone), or with no blow one way the part's name picks. 0..255.
func kink_code(_at: Vector3, ld: Vector3, angle: float) -> int:
	var ac := _across()
	var lp := ld - (ac[2] as Vector3) * ld.dot(ac[2])
	if lp.length_squared() < 1e-6 or angle == 0.0:
		return absi(hash(String(part_name))) % 256
	var th := atan2(lp.dot(ac[1]), lp.dot(ac[0]))
	return posmod(roundi(th / TAU * 256.0), 256)

## Where the bone breaks out of an open fracture: on the bone at the break, and out through the
## skin on the outside of the bend (the side the blow came from, where the broken ends of the shaft
## are driven out). [point on the bone, way out], part-local; empty when it is not bent.
func break_exit() -> Array:
	if kink.is_empty():
		return []
	var ax: int = kink[0]
	var c := float(kink[1])
	var sum := Vector3.ZERO
	var n := 0
	var slab := vf * part_scale * 1.5
	for i in fx.size():
		if bone[i]:
			var q := local_of(i)
			if absf(q[ax] - c) < slab:
				sum += q
				n += 1
	var at := Vector3.ZERO
	at[ax] = c
	if n > 0:
		at = sum / n
		at[ax] = c
	return [at, -kink_push(int(kink[4]))]

## Draws the part in shape `xf` (one Transform3D per voxel), or as plain cubes when empty; only
## the voxels in `only` drawn again when it is given.
func set_shape(xf: Array, only: Array = []) -> void:
	# (Under a fine look its own voxels there stay undrawn, whatever shape it is given.)
	if fine.has("body"):
		xf = FineBody.masked(self, xf)
	elif not fine.is_empty():
		xf = FineHead.masked(self, xf)
	shape_xf = xf
	if not _band.is_empty():
		_band_terms()   # (a limb bent at a break: laid round it in its new shape)
	if mm == null:
		return
	var on := []
	for i in (only if not only.is_empty() else range(fx.size())):
		if alive[i] and not veiled(i) and not jaw_slot.has(i):
			on.append([i, drawn_xf(i)])
	_write_shown(mm, on, true)

## Whether this head has jaws to bite with: its lower jaw still on it, not hacked mostly away (the
## teeth went with it then, jaw_teeth) nor cut from the skull (jaw_off). A head drawn with no jaw
## of its own bites as it is.
func can_bite() -> bool:
	return jaw_pivot == null or (jaw_teeth and not jaw_off)

var jaw_off := false   # the lower jaw cut away from the head and fallen (drop_jaw)

## Whether the lower jaw still hangs from the skull: by its hinge, the back third of it, where a
## live voxel of it has live flesh of the head over it, across the mouth's line. (The flesh behind
## and under it is the throat's, which holds no jaw on: counted, a jaw cut along the mouth from ear
## to ear hung on by the back of it. And the front of it only lies under the snout: a crocodile's,
## its jaw the whole length of its snout, was cut free along all of it before it fell, user.)
var _jaw_hinge_z := -1
func jaw_held() -> bool:
	if jaw_pivot == null or jaw_slot.is_empty():
		return true
	if _jaw_hinge_z < 0:
		var z0 := 1 << 30
		var z1 := -1
		for i in jaw_slot:
			z0 = mini(z0, fz[i])
			z1 = maxi(z1, fz[i])
		_jaw_hinge_z = z0 + maxi(2, (z1 - z0) / 3)
	var cm := cell_map()
	for i in jaw_slot:
		if not alive[i] or fz[i] > _jaw_hinge_z:
			continue
		var y := fy[i]
		if y + 1 >= grid.y:
			continue
		var k := cm[(fx[i] * grid.y + y + 1) * grid.z + fz[i]]
		if k > 0 and alive[k - 1] and not jaw_slot.has(k - 1):
			return true
	return false

## The lower jaw comes off: cut from the skull (jaw_held), or hacked mostly away (what is left
## of it, held by nothing, fell: it hung in the air under the head). What is left of it falls as
## a piece; the teeth and the gullet go with it, and the head bites no more (can_bite).
## Returns the voxels it lost, or [] if the jaw is still on.
func drop_jaw(dir: Vector3) -> Dictionary:
	if jaw_off or jaw_pivot == null or severed:
		return {}
	var left := []
	for i in jaw_slot:
		if alive[i]:
			left.append(i)
	if not left.is_empty() and jaw_teeth and jaw_held():
		return {}
	jaw_off = true
	jaw_teeth = false
	var vox := remove_voxels(left, false) if not left.is_empty() else []
	var piece = Chunk.spawn(self, vox, dir) if not freeze and vox.size() > 2 else null
	for c in jaw_pivot.get_children():
		if c is MeshInstance3D:
			c.visible = false
	if jaw_mouth:
		for c in jaw_mouth.get_children():
			c.visible = false
	return {"part": self, "indices": left, "voxels": vox, "chunk": piece != null}

## A biting head's lower jaw on a hinge at the back of the mouth (`jw` gives where, as fractions
## of the head's depth and height): its voxels are drawn in their own multimesh under a pivot,
## with a dark gullet and teeth on the skull that show when it opens. Drawing only: the head's
## voxels, wounds and collider are untouched.
func build_jaw(jw: Dictionary) -> void:
	if jaw_pivot != null or jw.is_empty():
		return
	# The lower jaw is the bottom of the snout: the voxels in front of `from` (of the depth), in
	# the lower 40% of the height they span there (the heads were remodelled after the web's
	# fixed jaw heights were set, so the cut follows each head's own snout).
	var z0 := int(floor(grid.z * float(jw.get("from", 0.6))))
	var ylo := 1 << 30
	var yhi := -1
	for i in fx.size():
		if fz[i] >= z0:
			ylo = mini(ylo, fy[i])
			yhi = maxi(yhi, fy[i])
	if yhi < 0:
		return
	var y1 := ylo + maxi(1, int(ceil((yhi - ylo + 1) * 0.4)))
	# The jaw opens on the mouth painted on the face (a dark line across the front of the snout),
	# so there is one mouth, where it was drawn: the row with the most dark voxels at the front.
	var front_z := -1
	for i in fx.size():
		front_z = maxi(front_z, fz[i])
	var dark := {}
	for i in fx.size():
		if fz[i] >= front_z - 1 and fy[i] < (ylo + yhi) / 2 + 2:
			var c: Color = colors[i]
			if c.get_luminance() < 0.16:
				dark[fy[i]] = int(dark.get(fy[i], 0)) + 1
	var best_row := -1
	for y in dark:
		if dark[y] >= 3 and (best_row < 0 or dark[y] > dark[best_row]):
			best_row = y
	if best_row > ylo:
		# Never thinner than three rows on a tall snout: a two-row slab swung wide still
		# read as a shut mouth from any distance (the dragon pouring fire through its teeth).
		y1 = maxi(best_row, mini(y1, ylo + 3))
	# The skull keeps two rows over the jaw at least: with less, a thin snout (the crocodile's)
	# had its gullet and teeth standing out of the top of its head.
	var tip_hi := -1
	for i in fx.size():
		if fz[i] >= front_z - 2:
			tip_hi = maxi(tip_hi, fy[i])
	y1 = mini(y1, mini(yhi, tip_hi if tip_hi >= 0 else yhi) - 1)
	var idx := []
	for i in fx.size():
		if fz[i] >= z0 and fy[i] < y1:
			idx.append(i)
	if idx.size() < 4:
		return
	var sc := vf * part_scale
	jaw_pivot = Node3D.new()
	jaw_pivot.name = "Jaw"
	jaw_pivot.position = Vector3(0, (y1 - (grid.y - 1) * 0.5) * sc, (z0 - (grid.z - 1) * 0.5) * sc)
	add_child(jaw_pivot)
	var main := []
	for i in idx:
		main.append([i, local_of(i)])
	_write_shown(mm, main, false)
	jaw_mm = MultiMesh.new()
	jaw_mm.transform_format = MultiMesh.TRANSFORM_3D
	jaw_mm.use_colors = true
	jaw_mm.use_custom_data = true
	jaw_mm.mesh = mm.mesh
	jaw_mm.instance_count = idx.size()
	for s in idx.size():
		var i: int = idx[s]
		jaw_slot[i] = s
		var k := 1.0 if alive[i] and not veiled(i) else 0.0
		jaw_mm.set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ONE * k), (local_of(i) - jaw_pivot.position) * k))
		jaw_mm.set_instance_color(s, colors[i])
		jaw_mm.set_instance_custom_data(s, _custom(i))
	var ext := Vector3(grid.x, grid.y, grid.z) * sc + Vector3.ONE * sc
	jaw_mm.custom_aabb = AABB(-ext, ext * 2.0)
	var jm := MultiMeshInstance3D.new()
	jm.multimesh = jaw_mm
	jm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	jm.top_level = true
	jaw_mesh = jm
	jm.custom_aabb = jaw_mm.custom_aabb
	jaw_pivot.add_child(jm)
	_mark_skin()   # the jaw is drawn on its own now
	# The gullet and the upper teeth sit on the skull; the lower teeth ride on the jaw.
	# Sized to the jaw itself, so nothing pokes out of a narrow snout.
	var xlo := 1 << 30
	var xhi := -1
	var zhi := -1
	for i in idx:
		xlo = mini(xlo, fx[i])
		xhi = maxi(xhi, fx[i])
		zhi = maxi(zhi, fz[i])
	var length := (zhi - z0) * sc * 0.85
	var wide := (xhi - xlo + 1) * sc * 0.6
	jaw_mouth = Node3D.new()
	jaw_mouth.position = jaw_pivot.position
	jaw_mouth.visible = false
	add_child(jaw_mouth)
	# The inside of the mouth is the head's own voxels: the bottom row of the skull over the jaw
	# its roof, the top row of the jaw its tongue, dark red (inside, out of sight while shut).
	# (A box laid in for a gullet stood out of the top of a thin snout.)
	var roof := []
	var zup := -1
	for i in fx.size():
		if fz[i] >= z0 and fy[i] == y1:
			zup = maxi(zup, fz[i])
			if fx[i] > xlo and fx[i] < xhi and fz[i] < zhi:
				roof.append(i)
	for i in idx:
		if fy[i] == y1 - 1 and fx[i] > xlo and fx[i] < xhi and fz[i] < zhi:
			roof.append(i)
	for i in roof:
		colors[i] = Color8(0x5a, 0x14, 0x14).lerp(Color8(0x7a, 0x24, 0x22), fmod(float(i) * 0.37, 1.0))
	refresh_colors(roof)
	if zup < 0:
		zup = zhi
	var up_len := (zup - z0) * sc
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color8(0xf2, 0xec, 0xdc)
	tm.roughness = 0.5
	# The teeth inside the mouth: the upper ones hang from its roof, the lower stand on the jaw,
	# and they show only while it is open (shut, they are in the closed mouth).
	var tb := BoxMesh.new()
	tb.size = Vector3(sc * 0.45, sc * 0.6, sc * 0.45)
	tb.material = tm
	for n in 4:
		var x := (n / 3.0 - 0.5) * wide * 0.8
		var up := MeshInstance3D.new()
		up.mesh = tb
		up.position = Vector3(x, -sc * 0.2, up_len - sc * 0.4)
		jaw_mouth.add_child(up)
		var lo := MeshInstance3D.new()
		lo.name = "Tooth"
		lo.mesh = tb
		lo.position = Vector3(x, sc * 0.1, length - sc * 0.5)
		lo.visible = false
		jaw_pivot.add_child(lo)

## Opens the jaw toward `gape` radians (smoothly).
func set_gape(gape: float, dt: float) -> void:
	if jaw_pivot == null:
		return
	jaw_angle += (gape - jaw_angle) * minf(1.0, dt * 18.0)
	jaw_pivot.basis = Basis(Vector3.RIGHT, jaw_angle)
	jaw_mouth.visible = jaw_angle > 0.08
	for c in jaw_pivot.get_children():
		if c is MeshInstance3D and c.name.begins_with("Tooth"):
			c.visible = jaw_mouth.visible and jaw_teeth

## A look's veil and bevel (Physique), drawing only: `v` per voxel 1 to hide it though it is
## there, or empty for none. The shading round them follows.
func set_look(v: PackedByteArray, bevel_on: bool) -> void:
	var was := veil
	# The same look again (a plain body made plain, every man at his spawn): nothing to redraw.
	# (It went over every voxel's corners anyway, a seventh of a second a man.)
	if v == was and bevel_on == bevel:
		return
	veil = v
	bevel = bevel_on
	var show := []
	var hide := []
	for i in fx.size():
		var now := veiled(i)
		var before := i < was.size() and was[i] == 1
		if alive[i] == 1 and now != before:
			(hide if now else show).append(i)
	set_shown(hide, false)
	set_shown(show, true)
	if mm == null or ao.size() != fx.size():
		return
	for i in fx.size():
		var s := shade_bits(i)
		ao[i] = s & 0xffffff
		bev[i] = s >> 24
		_set_status(i, glowing.get(i, Vector2.ZERO))

## live_cell, live_coarse, total_coarse and the dead from the voxels as they are.
func _index_cells() -> void:
	live_cell = PackedInt32Array()
	live_cell.resize(grid.x * grid.y * grid.z)
	_air_n = -1
	_dead = PackedInt32Array()
	var nc := dims.x * dims.y * dims.z
	live_coarse = PackedInt32Array()
	live_coarse.resize(nc)
	total_coarse = PackedInt32Array()
	total_coarse.resize(nc)
	_cell_map = PackedInt32Array()
	_cell_map.resize(live_cell.size())
	for i in fx.size():
		_cell_map[_cell_of(i)] = i + 1
		if alive[i]:
			live_cell[_cell_of(i)] = i + 1
		else:
			_dead.append(i)
		var c := _coarse_of(i)
		if c >= 0 and c < nc:
			total_coarse[c] += 1
			if alive[i]:
				live_coarse[c] += 1

func _cell_of(i: int) -> int:
	return (fx[i] * grid.y + fy[i]) * grid.z + fz[i]

## Every grid cell's voxel (its index + 1; 0 none), dead or alive: the part's layout, which never
## changes once it is built.
var _cell_map := PackedInt32Array()
func cell_map() -> PackedInt32Array:
	if _cell_map.size() != grid.x * grid.y * grid.z:
		_cell_map = PackedInt32Array()
		_cell_map.resize(grid.x * grid.y * grid.z)
		for i in fx.size():
			_cell_map[_cell_of(i)] = i + 1
	return _cell_map

func _coarse_of(i: int) -> int:
	var res := Data.body_res
	return int(fx[i] / res) + dims.x * (int(fy[i] / res) + dims.y * int(fz[i] / res))

## The voxels gone from the part, in no order (what is under a blow is looked for among them,
## not among the whole part's).
var _dead := PackedInt32Array()
func dead_voxels() -> PackedInt32Array:
	if live_cell.size() != grid.x * grid.y * grid.z:
		_index_cells()
	return _dead

func _cell_out(i: int) -> void:
	if live_cell.size() != grid.x * grid.y * grid.z:
		return   # (worked out from the voxels when first wanted)
	_dead.append(i)
	var c := _cell_of(i)
	if live_cell[c] == i + 1:
		live_cell[c] = 0
	var k := _coarse_of(i)
	if k >= 0 and k < live_coarse.size():
		live_coarse[k] -= 1

func _cell_in(i: int) -> void:
	if live_cell.size() != grid.x * grid.y * grid.z:
		return
	var at := _dead.find(i)
	if at >= 0:
		_dead.remove_at(at)
	live_cell[_cell_of(i)] = i + 1
	var k := _coarse_of(i)
	if k >= 0 and k < live_coarse.size():
		live_coarse[k] += 1

## Puts voxels back (a mended limb in a replay, a net message out of order).
func restore_voxels(indices: Array) -> void:
	for i in indices:
		if i >= 0 and i < fx.size() and alive[i] == 0:
			alive[i] = 1
			alive_count += 1
			_cell_in(i)
	set_shown(indices, true)
	_reshade(indices)
	fit_collider()

## The collision shape follows the flesh once the part has a hole (see the class comment).
func fit_collider() -> void:
	var w := dims.x; var h := dims.y; var d := dims.z
	var n := w * h * d
	if live_coarse.size() != n or live_cell.size() != grid.x * grid.y * grid.z:
		_index_cells()
	var total := total_coarse
	var live := live_coarse
	var solid := PackedByteArray(); solid.resize(n)
	var holes := 0
	var any := 0
	# A cell stops a blade until most of it is gone (a quarter left): at half, a cell that still
	# looked whole (a few fine voxels out of its eight) let a blade in through an unbroken face.
	for c in n:
		solid[c] = 1 if (total[c] > 0 and live[c] * 4 >= total[c]) else 0
		if total[c] > 0 and solid[c] == 0:
			holes += 1
		any += solid[c]
	if holes == 0:
		if not fit_slabs.is_empty():
			_set_boxes(fit_slabs)   # (whole: as it is drawn)
		elif split:
			_drop_boxes(true)
		return
	if any == 0:
		for c in n:
			solid[c] = 1 if live[c] > 0 else 0
	# An empty cell of the box beside a solid one is solid too. (Only one beside a cell with flesh
	# as built can be: those pairs are worked out once, not all the box's cells gone over again.)
	if _air_n != n:
		_index_air(w, h, d)
	var fleshy := solid.duplicate()
	for j in _air_of.size():
		if fleshy[_air_by[j]] != 0:
			solid[_air_of[j]] = 1
	var k := half_ext * 2.0 / Vector3(w, h, d)
	var bl: Array = Greedy.boxes(w, h, d, solid)
	var list := []
	for b in bl:
		var box := AABB(Vector3(b[0] - w * 0.5, b[1] - h * 0.5, b[2] - d * 0.5) * k, Vector3(b[3] - b[0] + 1, b[4] - b[1] + 1, b[5] - b[2] + 1) * k)
		# (Kept to what is drawn of it, fit_slabs: the rest is air on screen.)
		for sl in fit_slabs:
			var cut := box.intersection(sl)
			if cut.size.x > 0.0001 and cut.size.y > 0.0001 and cut.size.z > 0.0001:
				list.append(cut)
		if fit_slabs.is_empty():
			list.append(box)
	if list.is_empty():
		for b in bl:
			list.append(AABB(Vector3(b[0] - w * 0.5, b[1] - h * 0.5, b[2] - d * 0.5) * k, Vector3(b[3] - b[0] + 1, b[4] - b[1] + 1, b[5] - b[2] + 1) * k))
	_set_boxes(list)

## The collider as these boxes (own frame), the whole box laid aside. The shapes there already are
## moved and sized to the new boxes, and only the difference made or freed: all of them freed and
## made anew at every cut (a hundred on a gorilla's trunk) was a hitch of more than a hundredth of
## a second.
func _set_boxes(list: Array) -> void:
	split = true
	main_shape.disabled = true
	while boxes.size() > list.size():
		var gone: CollisionShape3D = boxes.pop_back()
		gone.queue_free()
		remove_child(gone)
	for i in list.size():
		var size: Vector3 = (list[i] as AABB).size
		var at: Vector3 = (list[i] as AABB).get_center()
		if i < boxes.size():
			var cs: CollisionShape3D = boxes[i]
			var bs: BoxShape3D = cs.shape
			if bs.size != size:
				bs.size = size
			if cs.position != at:
				cs.position = at
			continue
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = at
		add_child(cs)
		boxes.append(cs)

## The empty cells of the coarse box (no voxel in them as the part was built), each paired with
## every cell beside it that had voxels: the layout, which changes only with it (_index_cells).
var _air_of := PackedInt32Array()
var _air_by := PackedInt32Array()
var _air_n := -1
func _index_air(w: int, h: int, d: int) -> void:
	_air_of = PackedInt32Array()
	_air_by = PackedInt32Array()
	_air_n = w * h * d
	var total := total_coarse
	for z in d:
		for y in h:
			for x in w:
				var c := x + w * (y + h * z)
				if total[c] > 0:
					continue
				for nb in [[x > 0, c - 1], [x < w - 1, c + 1], [y > 0, c - w], [y < h - 1, c + w], [z > 0, c - w * h], [z < d - 1, c + w * h]]:
					if nb[0] and total[nb[1]] > 0:
						_air_of.append(c)
						_air_by.append(nb[1])

func _drop_boxes(whole: bool) -> void:
	for cs in boxes:
		cs.queue_free()
		remove_child(cs)
	boxes.clear()
	if whole:
		split = false
		main_shape.disabled = false

func shape_count() -> int:
	return boxes.size() if split else 1

# ---------- Coming apart ----------

## The axis the part hangs from (0 x, 1 y, 2 z) and whether its joint is at the high end.
func _root_axis() -> Array:
	var r: Vector3 = ca / maxf(0.0001, part_scale)
	var ax := 1
	if abs(r.x) > abs(r[ax]): ax = 0
	if abs(r.z) > abs(r[ax]): ax = 2
	return [ax, r[ax] > 0.0]

## Alive voxels no longer connected (face to face) to where the part is held on: the joint face,
## or for a part held by nothing (a torso, a beast's body, a limb already off) the biggest lump.
## `ignore`: voxels to count as gone for the test (the lips of a cut, to find what hangs by them).
func loose_lumps(ignore := PackedInt32Array()) -> Array:
	var wf := grid.x; var hf := grid.y; var df := grid.z
	var n := wf * hf * df
	if live_cell.size() != n:
		_index_cells()
	var cell := live_cell.duplicate()
	var mark := PackedByteArray(); mark.resize(n)
	var count := alive_count
	var skip := PackedByteArray()
	if not ignore.is_empty():
		skip.resize(fx.size())
		for i in ignore:
			if skip[i] == 0 and alive[i]:
				cell[(fx[i] * hf + fy[i]) * df + fz[i]] = 0
				count -= 1
			skip[i] = 1
	if count == 0:
		return []
	var held := 0
	var has_joint := def.get("ca") != null or def.get("root") != null
	# The torso is held by the neck (character.js looseLumps): the lump with the most flesh
	# round the head's joint is the body, whatever is bigger; a pelvis cut free is the piece.
	var head_c: VoxelPart = null
	if part_name == "torso":
		for ch in child_parts:
			if ch.part_name == "head" and not ch.severed:
				head_c = ch
	var nc := Greedy.core()
	if nc and head_c != null:
		# The trunk in the core too: the lumps cut loose from the biggest, then of all of them
		# the one with the most flesh round the neck stays (a tie: the biggest). Gone over voxel
		# by voxel here, twice, every blow on the trunk took a fiftieth of a second: a nail pot's
		# hail, nine nails in one step, was a fifth of a second's hitch.
		var others: Array = nc.loose_lumps(cell, wf, hf, df, -1, 0)
		if others.is_empty():
			return []
		var near_neck := PackedByteArray()
		near_neck.resize(fx.size())
		var total_near := 0
		for i in voxels_within(head_c.pa, vf * part_scale * 2.5):
			if skip.is_empty() or skip[i] == 0:
				near_neck[i] = 1
				total_near += 1
		var held_k := -1
		var held_near := total_near
		for k in others.size():
			var at := 0
			for i in others[k]:
				at += near_neck[i]
			held_near -= at
		var best_near := held_near   # (the biggest's, all the neck's flesh the others have not)
		for k in others.size():
			var at := 0
			for i in others[k]:
				at += near_neck[i]
			if at > best_near:
				best_near = at
				held_k = k
		if held_k < 0:
			return others
		var in_other := PackedByteArray()
		in_other.resize(fx.size())
		for lump in others:
			for i in lump:
				in_other[i] = 1
		var biggest := PackedInt32Array()
		for i in fx.size():
			if alive[i] and (skip.is_empty() or skip[i] == 0) and in_other[i] == 0:
				biggest.append(i)
		var out := []
		for k in others.size():
			if k != held_k:
				out.append(others[k])
		out.append(biggest)
		return out
	if nc and head_c == null:
		var nax := -1
		var nedge := 0
		if has_joint and not severed:
			var nra := _root_axis()
			nax = nra[0]
			nedge = [wf, hf, df][nax] - 1 if nra[1] else 0
		return nc.loose_lumps(cell, wf, hf, df, nax, nedge)
	if has_joint and not severed:
		var ra := _root_axis()
		var ax: int = ra[0]
		var dim: int = [wf, hf, df][ax]
		var edge: int = dim - 1 if ra[1] else 0
		var seeds := PackedInt32Array()
		for c in n:
			if cell[c] == 0:
				continue
			var k: int = int(c / (hf * df)) if ax == 0 else (int((c % (hf * df)) / df) if ax == 1 else c % df)
			if abs(k - edge) <= 1:
				seeds.append(c)
		held = _flood(cell, mark, seeds, 1, wf, hf, df).size()
	else:
		var best := -1
		var best_size := 0
		var tag := 2
		var neck := head_c.pa if head_c else Vector3.ZERO
		var best_neck := -1
		var best_neck_n := 0
		var rn := vf * part_scale * 2.5
		for c in n:
			if cell[c] == 0 or mark[c] != 0:
				continue
			var lump := _flood(cell, mark, PackedInt32Array([c]), tag, wf, hf, df)
			if lump.size() > best_size:
				best_size = lump.size()
				best = tag
			if head_c:
				var at := 0
				for i in lump:
					if local_of(i).distance_to(neck) < rn:
						at += 1
				if at > best_neck_n:
					best_neck_n = at
					best_neck = tag
			tag = 2 if tag == 255 else tag + 1
		if best_neck >= 0:
			best = best_neck
			best_size = 0
			for c in n:
				if mark[c] == best:
					best_size += 1
		for c in n:
			mark[c] = 1 if mark[c] == best else 0
		held = best_size
	if held == count:
		return []
	var lumps := []
	for c in n:
		if cell[c] != 0 and mark[c] == 0:
			lumps.append(_flood(cell, mark, PackedInt32Array([c]), 3, wf, hf, df))
	return lumps

func _flood(cell: PackedInt32Array, mark: PackedByteArray, starts: PackedInt32Array, tag: int, wf: int, hf: int, df: int) -> PackedInt32Array:
	var q := PackedInt32Array()
	for c in starts:
		if cell[c] != 0 and mark[c] == 0:
			mark[c] = tag
			q.append(c)
	var out := PackedInt32Array()
	var head := 0
	var sx := hf * df
	var sy := df
	while head < q.size():
		var c := q[head]
		head += 1
		out.append(cell[c] - 1)
		var x := int(c / sx)
		var y := int((c % sx) / sy)
		var z := c % sy
		for nb in [[x > 0, c - sx], [x < wf - 1, c + sx], [y > 0, c - sy], [y < hf - 1, c + sy], [z > 0, c - 1], [z < df - 1, c + 1]]:
			if nb[0]:
				var m: int = nb[1]
				if cell[m] != 0 and mark[m] == 0:
					mark[m] = tag
					q.append(m)
	return out

## Where a child is jointed on, pulled onto this part's flesh.
## Where `child` is rooted in this part: its joint point, kept inside the box, and moved onto the
## nearest flesh of the part as it was built if that point lies in the air (a gorilla's arms are
## jointed on the rounded corners of its chest: with no flesh there, any blow to the chest was
## taken for the shoulder being cut away, and both arms fell off).
var _anchors := {}
func anchor_point(child: VoxelPart) -> Vector3:
	if _anchors.has(child):
		return _anchors[child]
	var p := child.pa
	var hx := half_ext / 0.95
	var pt := Vector3(clampf(p.x, -hx.x, hx.x), clampf(p.y, -hx.y, hx.y), clampf(p.z, -hx.z, hx.z))
	var near := _nearest_built(pt)
	if near >= 0 and sqrt(local_of(near).distance_squared_to(pt)) > vf * part_scale * 2.2:
		pt = local_of(near)
	_anchors[child] = pt
	return pt

## The voxel of the part as it was built (dead or alive) nearest to `p` (local), the first in
## index order of those as near; -1 for none. Looked for ring by ring out from `p`'s cell: gone
## over voxel by voxel, once for each limb rooted in the part, a dragon's trunk (ten thousand of
## them) took a fiftieth of a second at its first wound.
func _nearest_built(p: Vector3) -> int:
	var cm := cell_map()
	var vs := vf * part_scale
	var q := Vector3(p.x / vs + (grid.x - 1) * 0.5, p.y / vs + (grid.y - 1) * 0.5, p.z / vs + (grid.z - 1) * 0.5)
	var c := Vector3i(clampi(roundi(q.x), 0, grid.x - 1), clampi(roundi(q.y), 0, grid.y - 1), clampi(roundi(q.z), 0, grid.z - 1))
	var e := maxf(absf(c.x - q.x), maxf(absf(c.y - q.y), absf(c.z - q.z)))
	var far := maxi(maxi(maxi(c.x, grid.x - 1 - c.x), maxi(c.y, grid.y - 1 - c.y)), maxi(c.z, grid.z - 1 - c.z))
	var best := INF
	var best_i := -1
	for r in far + 1:
		# Nothing in ring r (cells r out from c every way) is nearer than r - e cells.
		if best_i >= 0 and (r - e - 0.01) * vs > sqrt(best):
			break
		for x in range(maxi(0, c.x - r), mini(grid.x - 1, c.x + r) + 1):
			for y in range(maxi(0, c.y - r), mini(grid.y - 1, c.y + r) + 1):
				var shell := absi(x - c.x) == r or absi(y - c.y) == r
				for z in (range(maxi(0, c.z - r), mini(grid.z - 1, c.z + r) + 1) if shell else [c.z - r, c.z + r]):
					if z < 0 or z >= grid.z:
						continue
					var k := cm[(x * grid.y + y) * grid.z + z]
					if k == 0:
						continue
					var d := local_of(k - 1).distance_squared_to(p)
					if d < best or (d == best and k - 1 < best_i):
						best = d
						best_i = k - 1
	return best_i

## Whether a lump holds the root of `child` (its joint point is inside it).
func lump_holds(lump: PackedInt32Array, child: VoxelPart) -> bool:
	var pt := anchor_point(child)
	var r := vf * part_scale * 2.2
	for i in lump:
		if local_of(i).distance_to(pt) < r:
			return true
	return false

## Whether there is still flesh of this part where `child` is jointed on (an upper arm's end for
## the forearm, the neck for the head): with none, the child hangs on nothing and must fall.
## "Where it is jointed on" is as wide as the child is across its root (2.2 voxels at least):
## within 2.2 voxels only, one hard thrust into the base of the neck, its channel wider than
## that, took the head off, and a bout was over at a stab (user: the fights end too fast).
func holds_child(child: VoxelPart) -> bool:
	var pt := anchor_point(child)
	var r := vf * part_scale * 2.2
	if child.def.get("ca") != null:
		var ax: int = child._root_axis()[0]
		r = maxf(r, 1.1 * minf(child.half_ext[(ax + 1) % 3], child.half_ext[(ax + 2) % 3]))
	return not voxels_within(pt, r, 1).is_empty()

func near_child_anchor(lump: PackedInt32Array) -> bool:
	var pts := []
	for c in child_parts:
		if not c.severed:
			pts.append(anchor_point(c))
	if pts.is_empty():
		return false
	var r := vf * part_scale * 2.2
	var lps := local_positions()
	for i in lump:
		var lp := lps[i]
		for pt in pts:
			if lp.distance_to(pt) < r:
				return true
	return false

## How much is left of the thinnest cross-section between the joint and the far end (0..1).
func thin_ratio() -> float:
	if def.get("ca") == null:
		return 1.0
	var ra := _root_axis()
	var ax: int = ra[0]
	var n: int = [grid.x, grid.y, grid.z][ax]
	var full := PackedInt32Array(); full.resize(n)
	var live := PackedInt32Array(); live.resize(n)
	for i in fx.size():
		var k: int = fx[i] if ax == 0 else (fy[i] if ax == 1 else fz[i])
		full[k] += 1
		if alive[i]:
			live[k] += 1
	var order := range(n)
	if ra[1]:
		order.reverse()
	var last := -1
	for k in order.size():
		if live[order[k]] > 0:
			last = k
	var mn := 1.0
	for k in range(1, last):
		var i: int = order[k]
		if full[i] > 0 and float(live[i]) / full[i] < mn:
			mn = float(live[i]) / full[i]
			thin_layer = [ax, i]
	return mn

## Voxels whose centre is within `r` of a local point.
func voxels_near(lp: Vector3, r: float) -> Array:
	var out := []
	for i in fx.size():
		if alive[i] and local_of(i).distance_to(lp) < r:
			out.append(i)
	return out

## Velocity of a world point on this body.
## Tongues of flame over the burning spots (GPU particles, where there is a screen).
func set_flames(on: bool) -> void:
	# (Its glow goes out with the fire, whether or not the flames were showing: put out only
	# when they had been, a part that burned with none to show glowed on as if alight for good,
	# user: the fire never went out.)
	if not on and _has_glow(1):
		_clear_glow(1)
	if Fx.current == null or Fx.current.headless:
		return
	if on and flames == null and BurnFx.room() and BurnFx.may_make():
		flames = BurnFx.make(self, _surface_at_spot("fire"), true, part_scale)
	if flames:
		BurnFx.set_on(flames, on)
		for s in spots:
			if s.kind == "fire" and s.t > 0.0:
				flames.position = s.lp
				break

## Green bubbles of poison rising off the part while acid or venom eats into it (only how it
## looks; Fire.tick does the harm).
func set_poison(on: bool) -> void:
	if not on and _has_glow(2):
		_clear_glow(2)
	if Fx.current == null or Fx.current.headless:
		return
	if on and poison_fx == null and BurnFx.room() and BurnFx.may_make():
		poison_fx = BurnFx.make(self, _surface_at_spot("acid"), false, part_scale)
	if poison_fx:
		BurnFx.set_on(poison_fx, on)
		for s in spots:
			if s.kind == "acid" and s.t > 0.0:
				poison_fx.position = s.lp
				break

## An arrow (or a dart) left standing in the part where it went in.
## Something sharp left in the part where it went in, along the way it was going: an arrow
## stands well out of the wound, a nail is driven in up to its head.
func stick(type: String, world_p: Vector3, dir: Vector3) -> void:
	var nail := type == "nail"
	if stuck.size() >= (40 if nail else 12):
		return
	var vis := Items.visual(type)
	# Carried with the part as it is drawn (seated on its joint, turned with a bend, its breath),
	# not as the body has it: on the body itself, an arrow in a hydra's neck stood off the neck
	# and shook as the neck was drawn back onto its joint frame after frame (user).
	var hold := Node3D.new()
	hold.top_level = true
	hold.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(hold)
	hold.global_transform = global_transform
	hold.add_child(vis)
	draw_with.append(hold)
	var lp: Vector3 = global_transform.affine_inverse() * world_p
	var ld: Vector3 = (global_transform.basis.orthonormalized().inverse() * dir).normalized()
	# Where it entered: back along its line to the surface of the part's box, then on along it to
	# the flesh, past the box's empty corners to the first voxel there is (a neck is round in its
	# box: stuck where the box began, an arrow's point stood in the air short of it, user).
	var back := 0.3
	for k in 3:
		var v := -ld[k]
		if absf(v) > 1e-4:
			back = minf(back, maxf(0.0, ((half_ext[k] if v > 0.0 else -half_ext[k]) - lp[k]) / v))
	var entry := lp - ld * back
	var step := maxf(0.005, vf * part_scale)
	var went := 0.0
	while went + step <= back and voxels_within(entry, step * 0.9, 1).is_empty():
		entry += ld * step
		went += step
	# The models' points are at +z: laid along the way it flew (in the part's own frame), point
	# first into the wound, the head, fletching or butt standing out.
	var out := 0.025 if nail else (0.24 if type.begins_with("pot_arrow") else (0.1 if type == "pot_bolt" else 0.12))
	var up := Vector3.UP if absf(ld.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	vis.transform = Transform3D(Basis.looking_at(-ld, up), entry - ld * out)
	stuck.append(vis)

func velocity_at(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - global_position)

## A piece cut off and lying still on the sand is walked over, as the dead are (Weapon._lie: a
## man stepping on a lopped-off arm went down over it); it is a thing that hits again once it
## moves, or is in someone's hand.
var _lying := false
var _lie_t := 0.0
func _lie(dt: float) -> void:
	if not (collision_layer == LAYER_DEBRIS or collision_layer == LAYER_CORPSE):
		return
	var still := wielder == null and linear_velocity.length() < 0.6
	_lie_t = (_lie_t + dt) if still else 0.0
	var lie := _lie_t > 0.4 or (_lying and wielder == null and linear_velocity.length() < 1.5)
	if lie == _lying:
		return
	_lying = lie
	collision_layer = LAYER_CORPSE if lie else LAYER_DEBRIS
	collision_mask = (LAYER_WORLD | LAYER_WEAPON | LAYER_DEBRIS | LAYER_CORPSE) if lie else (LAYER_WORLD | LAYER_BODY | LAYER_WEAPON | LAYER_DEBRIS | LAYER_CORPSE)

## A piece cut off is nudged, never flung, by a living body going by (a foot, a leg, a trunk), and
## once it has come to rest on the sand by whatever brushes it, until it is in someone's hand
## again: along the sand and up no faster than a nudge, spinning no faster; falling as fast as it
## falls. (A bear's or a gorilla's stride kicked a severed leg across the arena at 9 m/s, again
## and again as it went by: user, a cut-off limb jumped about the arena for no reason.)
const CALM_V := 1.4
const CALM_W := 5.0
var _rested := false
func _calm(state: PhysicsDirectBodyState3D) -> void:
	if wielder != null:
		_rested = false
		return
	if _lying:
		_rested = true
	var trod := false
	if not _rested:
		for i in state.get_contact_count():
			var o = state.get_contact_collider_object(i)
			if o is VoxelPart and not o.severed and o.collision_layer == LAYER_BODY:
				trod = true
				break
	if not (_rested or trod):
		return
	var v := state.linear_velocity
	var flat := Vector2(v.x, v.z)
	if flat.length() > CALM_V or v.y > CALM_V:
		flat = flat.limit_length(CALM_V)
		state.linear_velocity = Vector3(flat.x, minf(v.y, CALM_V), flat.y)
	var w := state.angular_velocity
	if w.length() > CALM_W:
		state.angular_velocity = w.limit_length(CALM_W)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if severed:
		_lie(state.step)
	if Combat.current and state.get_contact_count() > 0:
		Combat.current.report(self, state)
		# Pressed on by someone else's weapon this step, or by a giant's body (Fighter.control
		# caps what that adds to his speed: a man's shins caught in a giant's striding legs were
		# flung at 25 m/s and sent him into the sky, user).
		if fighter and "struck_frame" in fighter:
			# (Most of what a part touches is the sand, or his own parts: let go at once.)
			for i in state.get_contact_count():
				var o = state.get_contact_collider_object(i)
				if o is Weapon:
					if o.holder != null and o.holder != fighter:
						fighter.struck_frame = Engine.get_physics_frames()
						break
				elif o is VoxelPart and o.fighter != null and o.fighter != fighter:
					if Fighter.is_giant_over(o, fighter):
						fighter.struck_frame = Engine.get_physics_frames()
						break
					if Fighter.is_beast_on(o, fighter):
						fighter.beast_frame = Engine.get_physics_frames()
	# (After the contacts are told: a blow it lands is as hard as it came.)
	if severed:
		_calm(state)
