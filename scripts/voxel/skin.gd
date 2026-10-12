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
						(nb[p0] as PackedInt32Array).append(p1)
						(nb[p1] as PackedInt32Array).append(p0)
	if idx.is_empty():
		return null
	# Relax: rounds the steps off, the shape stays (a pass moves each vertex half way to the mean
	# of its neighbours).
	for _r in RELAX:
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
			# The quad's two triangles keep their winding; its four corners are copied.
			var local := {}
			for j in 6:
				var o: int = idx[t + j]
				if not local.has(o):
					var nv := qi * 4 + local.size()
					local[o] = nv
					v2[nv] = verts[o]
					n2[nv] = norms[o]
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
