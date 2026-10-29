class_name VoxelSkin
## A smooth skin over a part's voxels (Surface Nets): the voxels stay what the game is made of
## (hits, cuts, physics, every lost voxel), only the drawing is a continuous surface instead of
## a heap of little boxes. One vertex per 2x2x2 cell the surface passes through, at the mean of
## where the surface crosses that cell's edges, relaxed toward its neighbours a couple of times;
## a quad across every voxel face between solid and empty; colours from the voxels around.

const RELAX := 1          # smoothing passes (one keeps the shape crisp, more turns it to soap)
const RELAX_K := 0.55     # how far each pass pulls a vertex toward its neighbours' mean
const CRISP := true       # each face in the colour of the voxel under it: sharp colour borders

## The skin of `part`'s living voxels, leaving out the ones `skip` holds (a hinged jaw drawn on
## its own). Null when nothing is left to draw.
static func build(part: VoxelPart, skip := {}) -> ArrayMesh:
	var nc := Greedy.core()
	if nc != null and CRISP and nc.has_method("skin_crisp"):   # (a library built before the skin was in it: the script)
		return _build_native(part, skip, nc)
	var g: Vector3i = part.grid
	var sx := g.x + 2
	var sxy := sx * (g.y + 2)
	var occ := PackedByteArray()
	occ.resize(sxy * (g.z + 2))
	var who := PackedInt32Array()
	who.resize(occ.size())
	who.fill(-1)
	var any := false
	for i in part.fx.size():
		if part.alive[i] and not skip.has(i):
			var k := (part.fx[i] + 1) + (part.fy[i] + 1) * sx + (part.fz[i] + 1) * sxy
			occ[k] = 1
			who[k] = i
			any = true
	if not any:
		return null
	# Cells: corner (x, y, z) in padded coords, a cell spans corners x..x+1 (voxel centres).
	var cx := g.x + 1
	var cxy := cx * (g.y + 1)
	var vid := PackedInt32Array()
	vid.resize(cxy * (g.z + 1))
	vid.fill(-1)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var cell := PackedInt32Array()   # each vertex's cell (padded index of its low corner)
	var corner := [0, 1, sx, sx + 1, sxy, sxy + 1, sxy + sx, sxy + sx + 1]
	var cofs := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var centre := Vector3(g.x - 1, g.y - 1, g.z - 1) * 0.5
	var vs: float = part.vf * part.part_scale
	for z in g.z + 1:
		for y in g.y + 1:
			for x in g.x + 1:
				var base := x + y * sx + z * sxy
				var mask := 0
				for d in 8:
					if occ[base + corner[d]]:
						mask |= 1 << d
				if mask == 0 or mask == 255:
					continue
				var sum := Vector3.ZERO
				var n := 0
				for e in edges:
					var a: int = e[0]
					var b: int = e[1]
					if ((mask >> a) & 1) != ((mask >> b) & 1):
						sum += (cofs[a] + cofs[b]) * 0.5
						n += 1
				var p: Vector3 = Vector3(x, y, z) + sum / float(n) - Vector3.ONE   # voxel coords
				vid[x + y * cx + z * cxy] = verts.size()
				verts.append((p - centre) * vs)
				cell.append(base)
	# Quads: a solid voxel next to an empty one across +x, +y or +z.
	var idx := PackedInt32Array()
	var qcol := PackedInt32Array()   # the solid voxel each quad covers
	var nb := []
	nb.resize(verts.size())
	for i in nb.size():
		nb[i] = PackedInt32Array()
	for z in g.z + 1:
		for y in g.y + 1:
			for x in g.x + 1:
				var k := x + y * sx + z * sxy
				var a := occ[k]
				for ax in 3:
					var k2: int = k + (1 if ax == 0 else (sx if ax == 1 else sxy))
					var b := occ[k2]
					if a == b:
						continue
					# The four cells around this face (cell coords = voxel coords - 1 + {0,1}).
					var q := PackedInt32Array()
					var c0 := Vector3i(x, y, z)
					var u := Vector3i(0, 1, 0) if ax == 0 else (Vector3i(0, 0, 1) if ax == 1 else Vector3i(1, 0, 0))
					var v := Vector3i(0, 0, 1) if ax == 0 else (Vector3i(1, 0, 0) if ax == 1 else Vector3i(0, 1, 0))
					var ok := true
					for o in [Vector3i.ZERO, u, u + v, v]:
						# The four cells sharing this face: the same along its axis, one back or
						# not along the other two.
						var cc: Vector3i = c0 - u - v + o
						if cc.x < 0 or cc.y < 0 or cc.z < 0 or cc.x > g.x or cc.y > g.y or cc.z > g.z:
							ok = false
							break
						var id := vid[cc.x + cc.y * cx + cc.z * cxy]
						if id < 0:
							ok = false
							break
						q.append(id)
					if not ok:
						continue
					if a:
						idx.append_array([q[0], q[2], q[1], q[0], q[3], q[2]])
					else:
						idx.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
					qcol.append(who[k] if a else who[k2])
					for s in 4:
						var p0: int = q[s]
						var p1: int = q[(s + 1) % 4]
						# (A packed array is a value: appended through a cast, the copy took it.)
						var l0: PackedInt32Array = nb[p0]
						l0.append(p1)
						nb[p0] = l0
						var l1: PackedInt32Array = nb[p1]
						l1.append(p0)
						nb[p1] = l1
	if idx.is_empty():
		return null
	# Relax: rounds the steps off, the shape stays (a pass moves each vertex half way to the mean
	# of its neighbours).
	var tune: Dictionary = part.get_meta("tune", {})
	for _r in int(tune.get("relax", RELAX)):
		var out := verts.duplicate()
		for i in verts.size():
			var list: PackedInt32Array = nb[i]
			if list.is_empty():
				continue
			var s := Vector3.ZERO
			for j in list:
				s += verts[j]
			out[i] = verts[i].lerp(s / float(list.size()), RELAX_K)
		verts = out
	var warp := not part.shape_xf.is_empty() and bool(tune.get("skin_shape", false))
	var shaped := PackedVector3Array()
	if warp:
		# (A trial: the skin laid over the look's shape, the limbs tapered and rounded as the
		# boxes are drawn; the colours are still read where the skin lies over the voxels.)
		shaped = Physique.warp_skin(part, verts)
	# Colour: the voxel nearest where the vertex ended up (not an average, which smeared an
	# eye or a belt a voxel wide into mud).
	cols.resize(verts.size())
	for i in verts.size():
		var p: Vector3 = verts[i] / vs + centre + Vector3.ONE
		var base: int = cell[i]
		var bx := base % sx
		var by := (base / sx) % (g.y + 2)
		var bz := base / sxy
		var best := -1
		var bd := INF
		for d in 8:
			var wi: int = who[base + corner[d]]
			if wi < 0:
				continue
			var dd := p.distance_squared_to(Vector3(bx, by, bz) + cofs[d])
			if dd < bd:
				bd = dd
				best = wi
		cols[i] = part.colors[best] if best >= 0 else Color(0.5, 0.5, 0.5)
	if warp:
		verts = shaped
	# Smooth normals from the faces round each vertex.
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var fn := (verts[idx[t + 2]] - a).cross(verts[idx[t + 1]] - a)
		norms[idx[t]] += fn
		norms[idx[t + 1]] += fn
		norms[idx[t + 2]] += fn
	for i in norms.size():
		norms[i] = norms[i].normalized() if norms[i].length_squared() > 1e-12 else Vector3.UP
	if CRISP:
		# Every quad its own four corners, in its voxel's colour (the shape and the shading
		# stay smooth, shared normals; only the colour no longer runs from voxel to voxel).
		var v2 := PackedVector3Array()
		var n2 := PackedVector3Array()
		var c2 := PackedColorArray()
		var i2 := PackedInt32Array()
		v2.resize(qcol.size() * 4)
		n2.resize(qcol.size() * 4)
		c2.resize(qcol.size() * 4)
		i2.resize(idx.size())
		for qi in qcol.size():
			var vi: int = qcol[qi]
			var col: Color = part.colors[vi] / part.grain(vi)
			col.a = 1.0
			var t := qi * 6
			var fnq := Vector3.ZERO
			if bool(tune.get("flat", false)):
				var a0 := verts[idx[t]]
				fnq = (verts[idx[t + 2]] - a0).cross(verts[idx[t + 1]] - a0) + (verts[idx[t + 5]] - verts[idx[t + 3]]).cross(verts[idx[t + 4]] - verts[idx[t + 3]])
				fnq = fnq.normalized() if fnq.length_squared() > 1e-12 else Vector3.UP
			# The quad's two triangles keep their winding; its four corners are copied.
			var local := {}
			for j in 6:
				var o: int = idx[t + j]
				if not local.has(o):
					var nv := qi * 4 + local.size()
					local[o] = nv
					v2[nv] = verts[o]
					n2[nv] = fnq if fnq != Vector3.ZERO else norms[o]
					c2[nv] = col
				i2[t + j] = local[o]
		verts = v2
		norms = n2
		cols = c2
		idx = i2
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

## The same skin from the C++ core (VoxelCore.skin_net and skin_crisp): a few milliseconds a
## man instead of the script's hundred and more, so a part can be built again on every blow.
static func _build_native(part: VoxelPart, skip: Dictionary, nc: Object) -> ArrayMesh:
	var tune: Dictionary = part.get_meta("tune", {})
	if not part.skin_geo_ok:
		var alive := part.alive
		if not skip.is_empty():
			alive = alive.duplicate()
			for i in skip:
				alive[i] = 0
		var net: Array = nc.skin_net(part.fx, part.fy, part.fz, alive, part.grid, part.vf * part.part_scale, int(tune.get("relax", RELAX)), RELAX_K)
		if not net.is_empty() and not part.shape_xf.is_empty() and bool(tune.get("skin_shape", false)):
			net[0] = Physique.warp_skin(part, net[0])
		part.skin_geo = net
		part.skin_geo_ok = true
	var net: Array = part.skin_geo
	if net.is_empty():
		return null
	var gi := PackedInt32Array(part.glowing.keys())
	var gv := PackedVector2Array(part.glowing.values())
	var out: Array = nc.skin_crisp(net[0], net[1], net[2], part.colors, part.grains(), part.kinds, gi, gv, bool(tune.get("flat", false)))
	if out.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out[0]
	arr[Mesh.ARRAY_NORMAL] = out[1]
	arr[Mesh.ARRAY_COLOR] = out[2]
	arr[Mesh.ARRAY_INDEX] = out[3]
	arr[Mesh.ARRAY_CUSTOM0] = out[4]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return am
