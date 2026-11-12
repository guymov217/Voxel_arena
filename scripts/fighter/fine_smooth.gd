extends RefCounted
## The fine look's smooth skin (drawing only; user: the bodies were hard to read for all their
## cubes and bumps, and only the outer layer should be smooth, the inside cubes as ever).
##
## The smooth light (k): every fine voxel of a man's skin (FineBody, FineHead) carries the way his
## body faces there, the shape as a whole and not the cube's own face, and the shader lights the
## cube's faces by it (voxel_body.gdshader, smooth_shade): a round arm is lit as a round arm, not as
## a stair of terraces each catching the sun on its own.
##
## The smooth skin (geo): the corners of the fine voxels on his skin are drawn moved onto his shape,
## so the stairs are gone from his outline too; every fine voxel is still a tile of his skin, its
## own colour, and what a wound bares under the skin is cubes as before.
##
## His shape: how full of him the space round a point is (his fine voxels and all they close in, a
## field, blurred). Down its slope is the way he faces; where it is half full is his skin. A part is
## worked out with what is jointed onto it beside it (the trunk with the tops of his thighs and
## arms), so that it does not end at the joint: ended there, the trunk's foot was rounded off like
## a ball and stood on his thighs with a crease between (user: the hips drawn narrow, the trunk not
## joined to the legs).

## How far a face's light follows the body's shape (0: each cube lit as a cube, as it was).
static var k := 1.0
## How far the corners of his skin's fine voxels are drawn moved onto his shape (0: cubes).
static var geo := 1.0

## Whether the men are drawn so. With the C++ core only (Greedy.core: its smooth_* do in a blink
## what follows here; the script's own, the same to the bit, are seconds a man and are what the
## tests hold the core to): without it the men are cubes, as they were.
static func live() -> bool:
	return k > 0.0 and Greedy.core() != null

## The smooth skin itself (the corners moved), with the smooth light.
static func skinned() -> bool:
	return geo > 0.0 and live()
## How far the shape is blurred for the light: the trunk (its back's muscles are terraces a dozen
## fine voxels long), the limbs, the head (a face's features are a few fine voxels across).
static var REACH_TRUNK := 4
static var REACH := 3
static var HEAD_REACH := 2
## And for where the skin is drawn (less: what is blurred away is not drawn at all).
static var GEO_REACH := 2
static var HEAD_GEO_REACH := 1
## The corner shading (the creases between the terraces drawn dark: rings round every muscle of
## his back) under the smooth skin, of what the cubes have.
static var AO := 0.2
const PAD := 5
const NONE := 1.0   # a colour's alpha that carries no way (the shader leaves the cube's own)
## No corner is drawn further than this from where it is (fine voxels): out, and in (less: the two
## faces of a thing one fine voxel thick, an ear, never pass each other).
static var HELD_OUT := 0.7
static var HELD_IN := 0.45
## What all the corners round a place are moved by alike is not his skin made smooth but his limb
## made thinner (a blurred shape shrinks where it is round): taken off again, over this many fine
## voxels round each.
static var EVEN_R := 4
## His skin's fine voxels still read as voxels under the smooth skin (user: the most important
## thing, the game's and the characters' voxel look is not to be lost): each tile's rim a shade
## darker (the fine look has none on its cubes, whose own edges show them), and its grain, the
## tone each tile is lighter or darker by, this many times the cubes'.
static var EDGE := 0.08
static var GRAIN := 1.5
## How strongly his body's lines are drawn on the smooth skin (FineBody: the build's own, times this).
static var LINES := 1.0

## Fine voxels (Vector3i) as these take them: x y z by turns.
static func triples(at: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(at.size() * 3)
	var i := 0
	for q: Vector3i in at:
		out[i] = q.x
		out[i + 1] = q.y
		out[i + 2] = q.z
		i += 3
	return out

## A way as a colour's alpha: 2 and up, an octahedron's 32 by 32 (whole numbers, held exactly even
## where the instance colours are kept as half floats).
static func encode(n: Vector3) -> float:
	var s := absf(n.x) + absf(n.y) + absf(n.z)
	if s < 1e-6:
		return NONE
	var o := Vector2(n.x, n.y) / s
	if n.z < 0.0:
		o = Vector2((1.0 - absf(o.y)) * (1.0 if o.x >= 0.0 else -1.0), (1.0 - absf(o.x)) * (1.0 if o.y >= 0.0 else -1.0))
	var u := clampi(roundi((o.x * 0.5 + 0.5) * 31.0), 0, 31)
	var v := clampi(roundi((o.y * 0.5 + 0.5) * 31.0), 0, 31)
	return 2.0 + float(u * 32 + v)

static func decode(a: float) -> Vector3:
	if a < 1.5:
		return Vector3.ZERO
	var code := roundi(a - 2.0)
	var e := Vector2(float(code / 32), float(code % 32)) / 31.0 * 2.0 - Vector2.ONE
	var n := Vector3(e.x, e.y, 1.0 - absf(e.x) - absf(e.y))
	var t := clampf(-n.z, 0.0, 1.0)
	n.x += -t if n.x >= 0.0 else t
	n.y += -t if n.y >= 0.0 else t
	return n.normalized()

## What of the space is a part, fine voxel by fine voxel (1 him, 0 not): the fine voxels at `at`
## (whole numbers on the fine grid, any origin). They are his skin and no more, a shell: what they
## close in is filled, and `inner` are voxels known to lie inside, each `res` fine ones across.
## `seal_lo`, `seal_hi`: the shell is open at that end along y (a joint there, a neck): shut for the
## filling.
## {f, sx, sy, sz, lo, pad}: the cell of fine voxel q is
## ((q.x - lo.x + pad) * sy + q.y - lo.y + pad) * sz + q.z - lo.z + pad.
static func solid(at: PackedInt32Array, inner := PackedInt32Array(), res := 1, seal_lo := false, seal_hi := false, pad := PAD) -> Dictionary:
	var nc := Greedy.core()
	if nc:
		return nc.smooth_solid(at, inner, res, seal_lo, seal_hi, pad)
	var lo := Vector3i(at[0], at[1], at[2])
	var hi := lo
	for s in at.size() / 3:
		var q := Vector3i(at[s * 3], at[s * 3 + 1], at[s * 3 + 2])
		lo = Vector3i(mini(lo.x, q.x), mini(lo.y, q.y), mini(lo.z, q.z))
		hi = Vector3i(maxi(hi.x, q.x), maxi(hi.y, q.y), maxi(hi.z, q.z))
	var sx := hi.x - lo.x + 1 + 2 * pad
	var sy := hi.y - lo.y + 1 + 2 * pad
	var sz := hi.z - lo.z + 1 + 2 * pad
	var syz := sy * sz
	var total := sx * syz
	var f := PackedFloat32Array()
	f.resize(total)
	for s in at.size() / 3:
		f[((at[s * 3] - lo.x + pad) * sy + (at[s * 3 + 1] - lo.y + pad)) * sz + (at[s * 3 + 2] - lo.z + pad)] = 1.0
	for k in inner.size() / 3:
		for a in res:
			var x := inner[k * 3] * res + a - lo.x + pad
			if x < pad or x >= sx - pad:
				continue
			for b in res:
				var y := inner[k * 3 + 1] * res + b - lo.y + pad
				if y < pad or y >= sy - pad:
					continue
				for c in res:
					var z := inner[k * 3 + 2] * res + c - lo.z + pad
					if z >= pad and z < sz - pad:
						f[(x * sy + y) * sz + z] = 1.0
	# What is outside him: all that can be reached from a corner without going through him, and not
	# in by an end that is shut. The rest is him.
	var shut_a := pad if seal_lo else -1
	var shut_b := sy - pad if seal_hi else -1
	var outside := PackedByteArray()
	outside.resize(total)
	var stack := PackedInt32Array()
	stack.resize(total)
	var top := 1
	stack[0] = pad * sz
	outside[pad * sz] = 1
	while top > 0:
		top -= 1
		var i := stack[top]
		var z := i % sz
		var y := (i / sz) % sy
		var x := i / syz
		if x > 0 and outside[i - syz] == 0 and f[i - syz] == 0.0:
			outside[i - syz] = 1
			stack[top] = i - syz
			top += 1
		if x < sx - 1 and outside[i + syz] == 0 and f[i + syz] == 0.0:
			outside[i + syz] = 1
			stack[top] = i + syz
			top += 1
		if y > 0 and y != shut_a and y != shut_b and outside[i - sz] == 0 and f[i - sz] == 0.0:
			outside[i - sz] = 1
			stack[top] = i - sz
			top += 1
		if y < sy - 1 and y + 1 != shut_a and y + 1 != shut_b and outside[i + sz] == 0 and f[i + sz] == 0.0:
			outside[i + sz] = 1
			stack[top] = i + sz
			top += 1
		if z > 0 and outside[i - 1] == 0 and f[i - 1] == 0.0:
			outside[i - 1] = 1
			stack[top] = i - 1
			top += 1
		if z < sz - 1 and outside[i + 1] == 0 and f[i + 1] == 0.0:
			outside[i + 1] = 1
			stack[top] = i + 1
			top += 1
	for x in sx:
		for y in range(pad, sy - pad):
			var b := (x * sy + y) * sz
			for z in sz:
				if outside[b + z] == 0:
					f[b + z] = 1.0
	return {"f": f, "sx": sx, "sy": sy, "sz": sz, "lo": lo, "pad": pad}

## `sol` with what is jointed onto the part beside it: each of `beside` is [its own solid, where its
## fine grid's origin lies on this part's (fine voxels, whole), the joint (this part's fine grid),
## how far round the joint it is taken (fine voxels)]. Only by the joint: an arm hanging by his side
## is not one with his flank.
static func joined(sol: Dictionary, beside: Array) -> Dictionary:
	if beside.is_empty():
		return sol
	var nc := Greedy.core()
	if nc:
		return nc.smooth_joined(sol, beside)
	var out := sol.duplicate()
	var f: PackedFloat32Array = (sol.f as PackedFloat32Array).duplicate()
	var added := PackedInt32Array()   # the cells that are the parts' beside it, not its own
	var sx: int = sol.sx
	var sy: int = sol.sy
	var sz: int = sol.sz
	var lo: Vector3i = sol.lo
	var pad: int = sol.pad
	for b in beside:
		var o: Dictionary = b[0]
		var shift: Vector3i = b[1]
		var joint: Vector3 = b[2]
		var r2: float = float(b[3]) * float(b[3])
		var of: PackedFloat32Array = o.f
		var osx: int = o.sx
		var osy: int = o.sy
		var osz: int = o.sz
		var olo: Vector3i = o.lo
		var opad: int = o.pad
		# (This part's whole grid, each cell looked up in the other's.)
		for x in sx:
			var qx := x - pad + lo.x          # this part's fine voxel
			var ox := qx - shift.x - olo.x + opad
			if ox < 0 or ox >= osx:
				continue
			var dx := float(qx) + 0.5 - joint.x
			for y in sy:
				var qy := y - pad + lo.y
				var oy := qy - shift.y - olo.y + opad
				if oy < 0 or oy >= osy:
					continue
				var dy := float(qy) + 0.5 - joint.y
				if dx * dx + dy * dy > r2:
					continue
				var row := (x * sy + y) * sz
				var orow := (ox * osy + oy) * osz
				for z in sz:
					var qz := z - pad + lo.z
					var oz := qz - shift.z - olo.z + opad
					if oz < 0 or oz >= osz:
						continue
					var dz := float(qz) + 0.5 - joint.z
					if dx * dx + dy * dy + dz * dz <= r2 and of[orow + oz] > 0.5 and f[row + z] <= 0.5:
						f[row + z] = 1.0
						added.append(row + z)
	out.f = f
	out.added = added
	return out

## `sol` blurred over `reach` fine voxels (a box each way, twice over: near enough a bell): how
## full of him the space round each fine voxel is.
static func blurred(sol: Dictionary, reach := REACH) -> Dictionary:
	var out := sol.duplicate()
	var f: PackedFloat32Array = sol.f
	var nc := Greedy.core()
	if nc:
		out.f = nc.smooth_blur(f, sol.sx, sol.sy, sol.sz, mini(reach, int(sol.pad) - 1))
		return out
	for axis in 3:
		for pass_i in 2:
			f = _box(f, sol.sx, sol.sy, sol.sz, axis, mini(reach, int(sol.pad) - 1))
	out.f = f
	return out

## The way each of the fine voxels at `at` faces, as alphas (encode): down the slope of `fld`
## (blurred, of the same voxels).
## A fine voxel shut in on every side in `sol` (the part with what is jointed onto it) is the
## part's own end under the part beside it (the round of a knee inside the shin): its way is down
## the slope of `own_fld`, the part's own shape blurred, so that it is lit as that round when the
## joint turns it out, or the limb beside it is cut off.
static func ways(at: PackedInt32Array, fld: Dictionary, sol := {}, own_fld := {}) -> PackedFloat32Array:
	var n := at.size() / 3
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(NONE)
	var f: PackedFloat32Array = fld.f
	var sy: int = fld.sy
	var sz: int = fld.sz
	var syz := sy * sz
	var lo: Vector3i = fld.lo
	var pad: int = fld.pad
	var ends := not sol.is_empty() and not own_fld.is_empty()
	var nc := Greedy.core()
	if nc:
		return nc.smooth_ways(at, fld, sol if ends else {}, own_fld if ends else {})
	var sf: PackedFloat32Array = sol.f if ends else PackedFloat32Array()
	var of: PackedFloat32Array = own_fld.f if ends else PackedFloat32Array()
	for s in n:
		var i := ((at[s * 3] - lo.x + pad) * sy + (at[s * 3 + 1] - lo.y + pad)) * sz + (at[s * 3 + 2] - lo.z + pad)
		var g := Vector3(f[i + syz] - f[i - syz], f[i + sz] - f[i - sz], f[i + 1] - f[i - 1])
		if ends and sf[i + syz] > 0.5 and sf[i - syz] > 0.5 and sf[i + sz] > 0.5 and sf[i - sz] > 0.5 and sf[i + 1] > 0.5 and sf[i - 1] > 0.5:
			g = Vector3(of[i + syz] - of[i - syz], of[i + sz] - of[i - sz], of[i + 1] - of[i - 1])
		if g.length_squared() > 1e-8:
			out[s] = encode(-g.normalized())
	return out

## The smooth skin: where each fine voxel's eight corners are drawn, and the way he faces at each
## (down the slope of `light`). A corner on his skin (`sol`: a corner of a face with nothing of him
## beyond it) is moved along the way he faces there to where `shape` (blurred a little) is half
## full, less what all the corners round it are moved alike (EVEN_R: that is the blur's own
## shrinking, not his skin's stairs), and never more than HELD_OUT or HELD_IN from where it was. A
## corner is a corner of all the fine voxels that meet at it and is moved the same for each: his
## skin stays shut, every fine voxel a tile of it. Corners under his skin stay: what a wound bares
## is cubes.
## The part's own end under the part beside it (`own`: the part's solid alone, where `sol` has
## what is jointed onto it too; a corner of a face with nothing of the part beyond it, but the
## other part) is moved onto the part's own shape (`own_shape`, `own_light`: `own` blurred as
## `shape` and `light` are): the round of a knee, drawn smooth when the joint turns it out.
## For each fine voxel its corners in the order x + 2y + 4z (0 the low side), four numbers each: the
## move in fine voxels, and the way as encode().
static func corners(at: PackedInt32Array, sol: Dictionary, shape: Dictionary, light: Dictionary, own := {}, own_shape := {}, own_light := {}) -> PackedFloat32Array:
	var nc := Greedy.core()
	if nc:
		var both := not own.is_empty() and not own_shape.is_empty() and not own_light.is_empty() and not is_same(own, sol)
		return nc.smooth_corners(at, sol, shape, light, own if both else {}, own_shape if both else {}, own_light if both else {}, HELD_IN, HELD_OUT, EVEN_R)
	var n := at.size() / 3
	var out := PackedFloat32Array()
	out.resize(n * 32)
	var f: PackedFloat32Array = sol.f
	var sx: int = sol.sx
	var sy: int = sol.sy
	var sz: int = sol.sz
	var syz := sy * sz
	var lo: Vector3i = sol.lo
	var pad: int = sol.pad
	var step := [syz, -syz, sz, -sz, 1, -1]
	var total := sx * syz
	var gf: PackedFloat32Array = shape.f
	var lf: PackedFloat32Array = light.f
	# The corners on his skin (each by the cell it is the low corner of), how far out along his way
	# each lies from where the shape is half full, and that way.
	var on := PackedByteArray()
	on.resize(total)
	var out_by := PackedFloat32Array()   # how far the corner is to be moved out (in: under 0)
	out_by.resize(total)
	var wsum := PackedFloat32Array()     # 1 at a corner on his skin with a way of its own
	wsum.resize(total)
	var way := PackedVector3Array()
	way.resize(total)
	var list := PackedInt32Array()
	# (His skin first, then the part's own ends: a corner of both is his skin's.)
	var ends := not own.is_empty() and not own_shape.is_empty() and not own_light.is_empty() and not is_same(own, sol)
	var fo: PackedFloat32Array = own.f if ends else f
	var gfo: PackedFloat32Array = own_shape.f if ends else gf
	var lfo: PackedFloat32Array = own_light.f if ends else lf
	for round_i in (2 if ends else 1):
		for s in n:
			var ci := ((at[s * 3] - lo.x + pad) * sy + (at[s * 3 + 1] - lo.y + pad)) * sz + (at[s * 3 + 2] - lo.z + pad)
			for d in 6:
				if round_i == 0:
					if f[ci + step[d]] > 0.5:
						continue
				elif fo[ci + step[d]] > 0.5 or f[ci + step[d]] <= 0.5:
					continue
				for c4 in 4:
					var o: Vector3i = FACES[d][c4]
					var li := ci + o.x * syz + o.y * sz + o.z
					if on[li] != 0:
						continue
					on[li] = round_i + 1
					list.append(li)
					var g := _slope(gf if round_i == 0 else gfo, li, syz, sz)
					var gv := Vector3(g.x, g.y, g.z)
					var gl := gv.length()
					if gl > 0.02:
						# (Out is down the slope; inside, over half full, the skin is further out.)
						way[li] = -gv / gl
						out_by[li] = clampf((g.w - 0.5) / gl, -2.5, 2.5)
						wsum[li] = 1.0
	# What the corners round each place are moved alike (the mean of them, EVEN_R round it). By a
	# joint the skin of the part beside it is in that mean too (joined: its cells), as this part's is
	# in its own: the corner the two share is moved the same by both, and their skins meet (each
	# with its own half of the mean, the last row of the one stood a hair out of the other's first,
	# a slit along the knee).
	var beside: PackedInt32Array = sol.get("added", PackedInt32Array())
	for ci in beside:
		var bz := ci % sz
		var by := (ci / sz) % sy
		var bx := ci / syz
		if bx < 1 or by < 1 or bz < 1 or bx > sx - 3 or by > sy - 3 or bz > sz - 3:
			continue   # (at the grid's rim: no slope to read there)
		for d in 6:
			if f[ci + step[d]] > 0.5:
				continue
			for c4 in 4:
				var o: Vector3i = FACES[d][c4]
				var li := ci + o.x * syz + o.y * sz + o.z
				if on[li] != 0 or wsum[li] != 0.0:
					continue
				var g := _slope(gf, li, syz, sz)
				var gv := Vector3(g.x, g.y, g.z)
				var gl := gv.length()
				if gl > 0.02:
					out_by[li] = clampf((g.w - 0.5) / gl, -2.5, 2.5)
					wsum[li] = 1.0
	var even := out_by.duplicate()
	var cover := wsum.duplicate()
	for axis in 3:
		for pass_i in 2:
			even = _box(even, sx, sy, sz, axis, mini(EVEN_R, pad - 1))
			cover = _box(cover, sx, sy, sz, axis, mini(EVEN_R, pad - 1))
	var move := PackedVector3Array()
	move.resize(total)
	for li in list:
		if wsum[li] == 0.0 or cover[li] < 1e-6:
			continue
		var a := out_by[li] - even[li] / cover[li]
		move[li] = way[li] * clampf(a, -HELD_IN, HELD_OUT)
	for s in n:
		var ci := ((at[s * 3] - lo.x + pad) * sy + (at[s * 3 + 1] - lo.y + pad)) * sz + (at[s * 3 + 2] - lo.z + pad)
		for c in 8:
			var li := ci + (c & 1) * syz + ((c >> 1) & 1) * sz + ((c >> 2) & 1)
			var o := (s * 8 + c) * 4
			if on[li] != 0:
				var d: Vector3 = move[li]
				out[o] = d.x
				out[o + 1] = d.y
				out[o + 2] = d.z
			var lg := _slope(lfo if on[li] == 2 else lf, li, syz, sz)
			var lw := Vector3(lg.x, lg.y, lg.z)
			out[o + 3] = encode(-lw.normalized()) if lw.length_squared() > 1e-8 else NONE
	return out

const FACES := [
	[Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1), Vector3i(1, 0, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(0, 1, 0)],
	[Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0)],
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(1, 0, 0)],
]

## A field at the corner the cell `i` and the seven before it meet at: its slope (x y z, a fine
## voxel) and how full it is there (w).
static func _slope(f: PackedFloat32Array, i: int, syz: int, sz: int) -> Vector4:
	var a000 := f[i - syz - sz - 1]
	var a001 := f[i - syz - sz]
	var a010 := f[i - syz - 1]
	var a011 := f[i - syz]
	var a100 := f[i - sz - 1]
	var a101 := f[i - sz]
	var a110 := f[i - 1]
	var a111 := f[i]
	return Vector4(
		((a100 + a101 + a110 + a111) - (a000 + a001 + a010 + a011)) * 0.25,
		((a010 + a011 + a110 + a111) - (a000 + a001 + a100 + a101)) * 0.25,
		((a001 + a011 + a101 + a111) - (a000 + a010 + a100 + a110)) * 0.25,
		(a000 + a001 + a010 + a011 + a100 + a101 + a110 + a111) * 0.125)

## What a part's fine voxels are drawn with under the smooth skin: the fine look's material
## (`shared`, FineHead.material) with the corners (corners) as a picture, eight to a fine voxel,
## 256 fine voxels a row.
static func skin(cd: PackedFloat32Array, shared: ShaderMaterial) -> ShaderMaterial:
	var n := cd.size() / 32
	var rows := maxi(1, (n + 255) / 256)
	var data := cd.duplicate()
	data.resize(2048 * rows * 4)   # (the rest of the last row: nought)
	var img := Image.create_from_data(2048, rows, false, Image.FORMAT_RGBAF, data.to_byte_array())
	var mat: ShaderMaterial = shared.duplicate()
	mat.set_shader_parameter("smooth_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("smooth_geo", geo)
	mat.set_shader_parameter("smooth_inset", 0.0)
	mat.set_shader_parameter("ao_strength", float(mat.get_shader_parameter("ao_strength")) * AO)
	mat.set_shader_parameter("edge_dark", EDGE)
	mat.set_shader_parameter("grain_k", GRAIN)
	_skins.append(weakref(mat))
	return mat

## The smooth skins drawn now (each its own copy of the fine look's material, for its corners):
## what an option changes of that material (the corner shading, VoxelPart.set_ao) they follow.
static var _skins: Array = []
static func follow(shared: ShaderMaterial) -> void:
	var kept := []
	for w: WeakRef in _skins:
		var mat = w.get_ref()
		if mat == null:
			continue
		kept.append(w)
		(mat as ShaderMaterial).set_shader_parameter("ao_strength", float(shared.get_shader_parameter("ao_strength")) * AO)
		(mat as ShaderMaterial).set_shader_parameter("smooth_shade", shared.get_shader_parameter("smooth_shade"))
	_skins = kept

## Whether `mat` is a smooth skin (its corners a picture read by each fine voxel's place in its own
## drawing: fine voxels copied into another drawing are drawn with the plain material).
static func is_skin(mat) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("smooth_tex") != null

## `f` blurred along one axis: each cell the mean of the 2r + 1 of them round it (a running sum).
static func _box(f: PackedFloat32Array, sx: int, sy: int, sz: int, axis: int, r: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(f.size())
	var len := sx if axis == 0 else (sy if axis == 1 else sz)
	var stride := sy * sz if axis == 0 else (sz if axis == 1 else 1)
	var na := sy if axis == 0 else sx
	var nb := sz if axis != 2 else sy
	var w := 1.0 / float(2 * r + 1)
	for a in na:
		for b in nb:
			var base := 0
			if axis == 0:
				base = a * sz + b
			elif axis == 1:
				base = a * sy * sz + b
			else:
				base = (a * sy + b) * sz
			var sum := 0.0
			for t in mini(r, len):
				sum += f[base + t * stride]
			for t in len:
				if t + r < len:
					sum += f[base + (t + r) * stride]
				if t - r - 1 >= 0:
					sum -= f[base + (t - r - 1) * stride]
				out[base + t * stride] = sum * w
	return out
