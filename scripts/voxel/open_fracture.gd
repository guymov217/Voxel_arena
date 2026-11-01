class_name OpenFracture
extends RefCounted
## The look of an open fracture (VoxelPart.show_bone), in voxels like everything else (user:
## everything is made of voxels, and everything breaks, the open break too): the broken end of the
## bone standing out of the torn skin and the torn flesh round it, as small cubes that blows knock
## off and snap (VoxelPart.break_bone_out).
##
## The bone: a shaft of cubes half a body voxel across, in a grid of its own laid along the bone
## (it comes out at a slant), round and a little flattened, ivory, never quite even; snapped across
## at a slant into a jagged end, one long spike and a shorter one, the marrow red and wet in a
## hollow inside the rim of hard bone; a sliver split off beside it. Blood up it from the wound in
## streaks.
## The wound: the skin torn open round it; on the skin, square with the limb's own voxels, cubes of
## red muscle and dark blood heaped unevenly round the shaft, a thin band of yellow fat under the
## ragged torn edge, chips of the bone lying in it.

const BONE := 6    # kinds, for the body shader (VoxelPart.kind_data): bone
const FLESH := 9   # wet flesh

const IVORY := Color(0.93, 0.88, 0.74)
const IVORY_OLD := Color(0.82, 0.73, 0.55)
const BREAK := Color(0.86, 0.78, 0.62)
const BLOOD := Color(0.42, 0.02, 0.02)
const BLOOD_DARK := Color(0.2, 0.01, 0.01)
const MARROW := Color(0.5, 0.09, 0.06)
const MARROW_DEEP := Color(0.26, 0.03, 0.02)
const MUSCLE := Color(0.48, 0.04, 0.045)
const MUSCLE_DARK := Color(0.2, 0.012, 0.016)
const FAT := Color(0.85, 0.7, 0.4)

## The cubes of an open break: each one's centre (part-local), colour, kind, whether it is turned
## with the bone (1) or square with the part (0), and for the shaft's own its layer along the bone
## (-1 for the rest). `s` their size, `basis` the bone's frame, `origin` where the shaft starts.
class Cubes:
	var pos := PackedVector3Array()
	var color := PackedColorArray()
	var kind := PackedByteArray()
	var frame := PackedByteArray()
	var layer := PackedInt32Array()
	var s := 0.01
	var basis := Basis()
	var origin := Vector3.ZERO

	func add(p: Vector3, c: Color, k: int, f: int, j := -1) -> void:
		pos.append(p)
		color.append(c)
		kind.append(k)
		frame.append(f)
		layer.append(j)

## `o`: at (on the bone at the break), y (the way the end stands out), x and z (across it), along
## (the limb's way to its far end), nrm (the skin's facing where it comes out), t_skin (from `at`
## along y to the skin), r (the bone's radius), h_out (how far it stands out of the skin), half
## (the part's half extents), skin (its colour there), seed, vox (the part's voxel size), skin_h
## (how far out the skin is over a point of the face: VoxelPart.skin_over).
static func voxels(o: Dictionary) -> Cubes:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o.seed)
	var cb := Cubes.new()
	cb.s = float(o.get("vox", 0.02)) * 0.5
	cb.basis = Basis(o.x, o.y, o.z)
	cb.origin = o.at
	_bone(cb, rng, o)
	_wound(cb, rng, o)
	return cb

## A smooth noise round a circle: `a` in radians, the same at a and a + TAU.
static func _ring_noise(a: float, k: Array) -> float:
	return (sin(a * 2.0 + k[0]) * 0.5 + sin(a * 3.0 + k[1]) * 0.3 + sin(a * 5.0 + k[2]) * 0.2) * 0.5 + 0.5

static func _ang_dist(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))

# ---------- the bone ----------

static func _bone(cb: Cubes, rng: RandomNumberGenerator, o: Dictionary) -> void:
	var at: Vector3 = o.at
	var X: Vector3 = o.x
	var Y: Vector3 = o.y
	var Z: Vector3 = o.z
	var r: float = o.r
	var t_skin: float = o.t_skin
	var h_out: float = o.h_out
	var s := cb.s
	var R := r / s
	var shape := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var streak := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var flat := rng.randf_range(0.82, 0.92)
	# Where it snaps: a slant across the shaft (high on one side), a long spike and a shorter one
	# standing above it, the rim a little ragged.
	var cut := rng.randf() * TAU
	var s1 := cut + rng.randf_range(-0.5, 0.5)
	var s2 := s1 + PI * rng.randf_range(0.6, 1.1)
	var base_top := (t_skin + h_out - r * 1.3) / s
	var j0 := int(floor(t_skin * 0.45 / s))
	var n := int(ceil(R * 1.15)) + 1
	for i in range(-n, n + 1):
		for k in range(-n, n + 1):
			var a := atan2(float(k), float(i))
			var rr := sqrt(float(i * i) + pow(float(k) / flat, 2.0))
			var edge := R * (0.9 + 0.2 * _ring_noise(a, shape))
			if rr > edge:
				continue
			var inner := rr < edge * 0.55
			var rim := rr / maxf(edge, 1e-3)
			var top := base_top + R * (0.15 + 0.9 * (0.5 + 0.5 * cos(a - cut)))
			top += R * 1.9 * pow(maxf(0.0, 1.0 - _ang_dist(a, s1) / 0.55), 1.6) * rim
			top += R * 0.9 * pow(maxf(0.0, 1.0 - _ang_dist(a, s2) / 0.4), 1.6) * rim
			top += rng.randf() * 0.8
			if inner:
				top -= rng.randf_range(1.0, 2.2)   # the marrow, sunk in a hollow
			var jt := int(floor(top))
			for j in range(j0, jt + 1):
				var p := at + (X * float(i) + Y * float(j) + Z * float(k)) * s
				var h := float(j) * s
				var c: Color
				var kind := BONE
				if inner:
					c = MARROW.lerp(MARROW_DEEP, rng.randf() * 0.6) if j >= jt - 1 else MARROW_DEEP
					kind = FLESH
				else:
					var u := (h - t_skin) / h_out
					if u < 0.0:
						c = BLOOD_DARK.lerp(BLOOD, clampf(1.0 + u * 3.0, 0.0, 1.0))
					else:
						c = IVORY.lerp(IVORY_OLD, clampf(u * u * 0.5 + 0.12 * _ring_noise(a * 3.0, shape), 0.0, 1.0))
						# Blood up the shaft from the wound, further on some sides, in streaks.
						var reach := 0.12 + 0.55 * pow(_ring_noise(a, streak), 2.0)
						c = c.lerp(BLOOD, (1.0 - smoothstep(reach * 0.55, reach, u)) * 0.92)
						if j == jt:
							c = BREAK.lerp(BLOOD, rng.randf() * 0.3)   # the broken face
					c = c * rng.randf_range(0.94, 1.04)
				c.a = 1.0
				cb.add(p, c, kind, 1, j)
	# A sliver split off the shaft beside it, leaning out: a thin blade of bone to a point.
	var sa := s2 + PI * 0.5 + rng.randf_range(-0.4, 0.4)
	var radial := (X * cos(sa) + Z * sin(sa) * flat).normalized()
	var p0 := at + Y * (t_skin + h_out * 0.05) + radial * r * 1.05
	var dir := (Y + radial * 0.42).normalized()
	var steps := int(h_out * rng.randf_range(0.42, 0.55) / s)
	for q in steps:
		var c := BLOOD.lerp(IVORY, minf(1.0, 0.25 + float(q) / maxf(1.0, steps * 0.5)))
		c.a = 1.0
		cb.add(p0 + dir * float(q) * s, c, BONE, 1, -1)

# ---------- the wound ----------

static func _wound(cb: Cubes, rng: RandomNumberGenerator, o: Dictionary) -> void:
	var at: Vector3 = o.at
	var Y: Vector3 = o.y
	var N: Vector3 = o.nrm
	var r: float = o.r
	var half: Vector3 = o.half
	var skin: Color = o.skin
	var along: Vector3 = o.along
	var s := cb.s
	var S: Vector3 = at + Y * float(o.t_skin)
	# The skin's plane: U along the limb, V across it.
	var U := along - N * along.dot(N)
	if U.length_squared() < 1e-6:
		U = N.cross(Vector3.UP if absf(N.y) < 0.9 else Vector3.RIGHT)
	U = U.normalized()
	var V := N.cross(U).normalized()
	# The face's axis, and how far out the skin is over a point of it (the limb is round, and the
	# hole the bone tore is sunk).
	var ka := 0
	for kk in 3:
		if absf(N[kk]) > absf(N[ka]):
			ka = kk
	var sg := signf(N[ka])
	var a1 := (ka + 1) % 3
	var a2 := (ka + 2) % 3
	var skin_h: Callable = o.get("skin_h", Callable())
	var face := absf(S[ka])
	var lift := func(p: Vector3) -> float:
		return skin_h.call(p) if skin_h.is_valid() else face
	var h0: float = lift.call(S)
	if is_nan(h0):
		h0 = face
	# Kept a voxel in from the face's edges: over them it would stand out past the limb.
	var lim_in := Vector3(absf(half.x), absf(half.y), absf(half.z)) - Vector3.ONE * float(o.get("vox", 0.0)) * 0.9
	# The bone's footprint on the skin: an ellipse, long the way it leans.
	var P := Y - N * Y.dot(N)
	var psi := atan2(P.dot(V), P.dot(U)) if P.length_squared() > 1e-8 else 0.0
	var cos_t := clampf(absf(Y.dot(N)), 0.35, 1.0)
	var noise := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var bruised := skin.lerp(Color(0.42, 0.18, 0.26), 0.55)
	var torn := skin.lerp(BLOOD, 0.55)
	var span := int(ceil(r * 3.4 / s)) + 1
	var inner_cells: Array = []
	for u in range(-span, span + 1):
		for v in range(-span, span + 1):
			var p := S
			p[a1] = (roundf(S[a1] / s) + float(u)) * s
			p[a2] = (roundf(S[a2] / s) + float(v)) * s
			if absf(p[a1]) > lim_in[a1] or absf(p[a2]) > lim_in[a2]:
				continue
			var d := p - S
			d[ka] = 0.0
			var dist := d.length()
			var ang := atan2(d.dot(V), d.dot(U))
			var foot := r / sqrt(pow(cos(ang - psi) * cos_t, 2.0) + pow(sin(ang - psi), 2.0))
			var ro := (r * 1.55 + r * 0.75 * _ring_noise(ang, noise)) * (1.0 + 0.35 * absf(cos(ang))) * rng.randf_range(0.88, 1.12)
			ro = maxf(ro, foot * 1.35)
			if dist < foot * 0.9 or dist > ro:
				continue
			var h: float = lift.call(p)
			if is_nan(h) or h < h0 - r * 1.2:
				continue
			var f := (dist - foot) / maxf(1e-4, ro - foot)   # 0 at the bone, 1 at the torn edge
			if f > 0.72 and rng.randf() < 0.45:
				continue   # the torn edge ragged
			var c: Color
			var stack := 1
			if f < 0.3:
				c = BLOOD_DARK.lerp(MUSCLE_DARK, rng.randf())
				stack = 2 if rng.randf() < 0.35 else 1
				inner_cells.append(p)
			elif f < 0.62:
				c = MUSCLE.lerp(MUSCLE_DARK, rng.randf() * 0.5)
				stack = 2 if rng.randf() < 0.25 else 1
			elif f < 0.84:
				c = FAT.lerp(BLOOD, rng.randf() * 0.4) if rng.randf() < 0.55 else MUSCLE.lerp(BLOOD, 0.5)
			else:
				c = torn.lerp(bruised, rng.randf() * 0.5)
			for q in stack:
				var pp := p
				pp[ka] = sg * (h + s * (0.15 + float(q)))
				var cc := c * rng.randf_range(0.9, 1.05)
				cc.a = 1.0
				cb.add(pp, cc, FLESH, 0, -1)
	# Chips of the bone broken loose with it, lying in the wound.
	for ci in mini(rng.randi_range(2, 3), inner_cells.size()):
		var p: Vector3 = inner_cells[rng.randi() % inner_cells.size()]
		var h: float = lift.call(p)
		if is_nan(h):
			continue
		p[ka] = sg * (h + s * 1.15)
		var cc := IVORY.lerp(BLOOD, rng.randf_range(0.15, 0.45))
		cc.a = 1.0
		cb.add(p, cc, BONE, 0, -1)
