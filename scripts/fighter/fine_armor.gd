class_name FineArmor
extends RefCounted
## Armour on a man of the new look (Physique "human") drawn as one shell of fine voxels lying on
## him, as small as those he is drawn in, the way a helmet or a cuirass lies on a man: not each of
## the piece's plates drawn as a tile of its own (round a head the tiles lay over one another like
## scales: user). Every fine voxel of the shell is one plate's: a plate knocked off takes its own
## with it, a limb bent at a break carries them as it carries the plate, an arm's plates hidden in
## the chest's armour hide them. A plate standing out from him (a crest, a brim) is drawn as the
## fine voxels its tile holds. Each piece as the arena saw it in its day (_style, user): a galea a
## smooth bowl with a brim and a plumed crest, a lorica in iron bands, greaves moulded
## with the knee raised; a bright rim round the shell's edge with rivets on it. Only the drawing:
## the plates, where they stop a blow and what they weigh are the piece's own (Fighter._add_armor),
## and the plates are still worked out (hidden).

const THICK := 2.0          # the shell, fine voxels thick
## A piece of armour's shell in voxels this many times the fine ones each way, fewer and bigger, and
## closer on him (user): laid on a fine shell COARSE_THICK fine voxels thick, each of its voxels
## kept where its middle lies in that (_coarse). A hairstyle or a hat the fine voxels' own.
const COARSE := 1.5
const COARSE_THICK := 1.5
const BAND_KEEP := 24       # parts' grounds kept (a build, a part, a size each)
const SHELL_KEEP := 24      # shells kept (a piece on a build's part)
static var _bands := {}
static var _shells := {}
static var _unit: BoxMesh = null

## Whether the piece is drawn as a shell on `p` as it is drawn now.
static func wanted(p: VoxelPart, id: String) -> bool:
	if p.fine.is_empty():
		return false
	if Fighter._cosmetic(id):
		return hair_or_hat(p, id)
	if p.fine.has("wtab"):
		return true
	return p.fine.has("body") and not bool(p.fine.get("beast", false)) and (p.fine.get("d", {}) as Dictionary).has("k")

## A hairstyle or a hat on a man's fine head (not a giant's: his head has its own): drawn as a
## shell round the head as a helmet is, the locks and the pieces that stand out from it as the
## fine voxels they hold (drawn as the head's cubes, a lock or a hat's piece the size of a
## voxel of his body, they stood off the fine head like blocks: user, the hair and the hats did
## not fit the new heads).
static func hair_or_hat(p: VoxelPart, id: String) -> bool:
	return p.fine.has("wtab") and String(p.fine.get("giant", "")) == "" and (id.begins_with("hair_") or id.begins_with("hat_"))

## The shell of `ad` (a piece on `p`) drawn, or drawn again as the plates lie now; the plates'
## own tiles hidden. Not wanted (the classic looks): the shell gone, the tiles shown.
static func build(f, p: VoxelPart, ad: Dictionary) -> void:
	var node = ad.get("node")
	if node == null or not is_instance_valid(node):
		return
	if not wanted(p, String(ad.id)):
		if ad.has("shell"):
			clear(ad)
		return
	var key := _key(p)
	var sh = ad.get("shell")
	if sh is Dictionary and String(sh.key) == key and is_instance_valid(sh.mi):
		sync_all(p, ad)
		return
	clear(ad)
	var id := String(ad.id)
	var skin: Color = f.skin if f is Fighter else Color(0.6, 0.4, 0.3)
	var bare := ArmorStyle.base_color(id, Data.armor.get(id, {}), skin)
	if id.begins_with("hair_") and f is Fighter:
		var hc = Physique.hair_choice(f)
		if hc != null:
			bare = hc
	var L := _layout(p, ad, id, bare)
	if L.is_empty():
		return
	# Drawn: each fine voxel a plate's, kept as where it lies on its plate's tile (a bend, a hide,
	# a knock that moves the tile moves it). The piece laid out once a build (_layout): a man is
	# dressed in a copy of it, the plates already knocked off him not drawn.
	if _unit == null:
		_unit = BoxMesh.new()
		_unit.size = Vector3.ONE
		_unit.material = material()
	var cnt: int = L.cnt
	var of: Dictionary = L.of
	var base: Array = L.base
	var buf: PackedFloat32Array = (L.buf as PackedFloat32Array).duplicate()
	var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	var now := {}
	for ci in ad.cells.size():
		if ad.on[ci] == 1:
			now[ci] = base[ci]
			continue
		now[ci] = none
		for sc in of.get(ci, []):
			for q in 12:
				buf[int(sc) * 20 + q] = 0.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _unit
	mm.instance_count = cnt
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.name = "shell_" + id
	mi.top_level = true
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.custom_aabb = (node as MultiMeshInstance3D).custom_aabb
	mm.custom_aabb = mi.custom_aabb
	mi.transparency = p.see_through
	p.add_child(mi)
	mi.global_transform = p.global_transform
	p.draw_with.append(mi)
	ad["shell"] = {"key": key, "mi": mi, "mm": mm, "rel": L.rel, "of": of, "plate": L.plate, "now": now, "xk": L.xk}
	(node as Node3D).visible = false

## A piece's shell on a part as the part is drawn (its build, its size), the same for every man of
## it, worked out once: each plate's tile, which fine voxels of the ground round him are which
## plate's, each voxel's place on its plate's tile, and the drawing's buffer (the places with every
## plate on, the colours, the shading). Shared: read, never changed.
static func _layout(p: VoxelPart, ad: Dictionary, id: String, bare: Color) -> Dictionary:
	var n: int = ad.cells.size()
	var lkey := "%s|%s|%d|%d|%d|%d|%s|%d" % [_key(p), id, n, hash(ad.cells), hash(ad.pts), hash(ad.get("kinds", [])), bare.to_html(), hash(ad.get("cols", []))]
	if _shells.has(lkey):
		return _shells[lkey]
	var ground := _ground(p, 1.0 if Fighter._cosmetic(id) else COARSE)
	if ground.is_empty():
		return {}
	var kf := float(ground.get("k", 1.0))   # (its voxels', of the fine ones)
	# Each plate where the look lays it, straight (its tile), and how far out of the box it stands.
	var base := []
	base.resize(n)
	var org := PackedVector3Array()
	org.resize(n)
	var first := PackedByteArray()
	first.resize(n)
	var dims := p.dims
	for ci in n:
		var c: Array = ad.cells[ci]
		base[ci] = Physique.plate_xf(p, c, ad.pts[ci] as Vector3, id)
		org[ci] = (base[ci] as Transform3D).origin
		var lay := 0
		for ax in 3:
			var v := int(c[ax])
			var dm := dims[ax]
			lay = maxi(lay, -v if v < 0 else (v - dm + 1 if v >= dm else 0))
		first[ci] = 1 if lay <= 1 else 0
		if hair_or_hat(p, id):
			first[ci] = 0 if Physique.stands(p, c, id) else 1
	# Each plate's neighbours on the piece's own lattice (the 26 round it), as they lie on him: the
	# shell runs on from a plate to its neighbour's (their tiles meet there), and past the piece's
	# edge, where there is none, half a tile. (Its nearest neighbour's distance every way: where he
	# narrows the tiles bunch up side by side, and the rows above and below were left apart with
	# his skin between, user.)
	var o: Vector3 = ground.o
	var sp: Vector3 = ground.sp
	var cellv := sp.x
	var cube := p.vf * p.part_scale * float(Data.body_res)
	var at_cell := {}
	for ci in n:
		var c: Array = ad.cells[ci]
		at_cell[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = ci
	var nbv := []
	nbv.resize(n)
	for ci in n:
		var l := PackedVector3Array()
		if first[ci] == 1:
			var c: Array = ad.cells[ci]
			var k0 := Vector3i(int(c[0]), int(c[1]), int(c[2]))
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var cj = at_cell.get(k0 + Vector3i(dx, dy, dz))
						if cj == null or int(cj) == ci or first[int(cj)] == 0:
							continue
						var v := org[int(cj)] - org[ci]
						if v.length() > cellv * 0.5:
							l.append(v)
		nbv[ci] = l
	# Each plate's way out of him (its tile's thin side): the shell's reach is measured along him,
	# not out of him (where he bulges past his plates, his chest and his shoulders, the shell
	# lies further out than the plates, and was left in holes: user).
	var nrm := PackedVector3Array()
	nrm.resize(n)
	for ci in n:
		var bb: Basis = (base[ci] as Transform3D).basis
		var thin := bb.x
		for col in [bb.y, bb.z]:
			if (col as Vector3).length() < thin.length():
				thin = col
		nrm[ci] = thin.normalized() if thin.length() > 0.0001 else Vector3.UP
	var bucket := {}
	var bs := cube * 1.5
	for ci in n:
		if first[ci] == 1:
			var kb := Vector3i((org[ci] / bs).floor())
			if not bucket.has(kb):
				bucket[kb] = PackedInt32Array()
			bucket[kb] = (bucket[kb] as PackedInt32Array) + PackedInt32Array([ci])
	# (The plates in a bucket and the 26 round it, gathered once a bucket.)
	var near := {}
	# The shell's fine voxels: the ground's round him near a plate, each the nearest plate's.
	var owner := {}
	var pts: PackedVector3Array = ground.pts
	var idx: PackedInt32Array = ground.idx
	for s in pts.size():
		var q := pts[s]
		var best := INF
		var who := -1
		for cj in _near(near, bucket, Vector3i((q / bs).floor())):
			var dd := q.distance_squared_to(org[cj])
			if dd < best:
				best = dd
				who = cj
		if who < 0:
			continue
		var d := q - org[who]
		var dn := d.dot(nrm[who])
		var dt := d - nrm[who] * dn
		if absf(dn) < cube * 1.25 and dt.length() < _reach(dt, nbv[who], cube, cellv):
			owner[Vector3i(idx[s * 3], idx[s * 3 + 1], idx[s * 3 + 2])] = who
	# Over his shoulders: his trunk's own round them, out past the box over the tops of his arms,
	# lies past the plates' reach (they lie on the box's outline): the shell runs on over all of
	# it, each fine voxel its nearest plate's (it was left bare in holes there, the shell's edge
	# ragged over his arms like teeth: user, the lorica not as one was made).
	if _over_top(ad, p):
		var hb := Vector3(p.grid) * p.vf * p.part_scale * 0.5
		var far := cube * cube * 6.25
		# (its lower edge: level, half a plate under its lowest row round his sides)
		var ylo := INF
		for ci in n:
			if first[ci] == 1 and int((ad.cells[ci] as Array)[1]) < p.dims.y:
				ylo = minf(ylo, org[ci].y)
		ylo -= cube * 0.5
		var wide := {}   # (the plates in a bucket and the two rings of buckets round it: 3 cubes)
		for s in pts.size():
			var kc := Vector3i(idx[s * 3], idx[s * 3 + 1], idx[s * 3 + 2])
			if owner.has(kc) or pts[s].y < ylo or not _under_guard(pts[s], hb, cube):
				continue
			var kb := Vector3i((pts[s] / bs).floor())
			if not wide.has(kb):
				var l := PackedInt32Array()
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						for dz in range(-2, 3):
							l.append_array(bucket.get(kb + Vector3i(dx, dy, dz), PackedInt32Array()))
				wide[kb] = l
			var best := far
			var who := -1
			for cj in (wide[kb] as PackedInt32Array):
				var dd := pts[s].distance_squared_to(org[cj])
				if dd < best:
					best = dd
					who = cj
			if who >= 0:
				owner[kc] = who
		# (And out over the top of his arm, which rises there out of him at his side: the guard
		# stands off the round of his shoulder as far as the arm does, or the arm's top came up
		# through it.)
		var lift := {}
		for kc in owner.keys():
			var q: Vector3 = o + (Vector3(kc) + Vector3.ONE * 0.5) * sp
			var ax := absf(q.x)
			if ax < hb.x - cube * 2.0 or not _over_shoulder(q, hb, cube):
				continue
			var n3 := q - Vector3(signf(q.x) * (hb.x - cube * 0.5), hb.y - cube * 1.75, 0.0)
			if n3.length() < 0.0001:
				continue
			n3 = n3.normalized()
			var reach := LIFT / kf * clampf((ax - (hb.x - cube * 2.0)) / cube, 0.0, 1.0)
			var t := 0.5
			while t <= reach:
				var kc2 := Vector3i(((q + n3 * sp.x * t - o) / sp).floor())
				if not owner.has(kc2) and not lift.has(kc2):
					lift[kc2] = owner[kc]
				t += 0.5
		owner.merge(lift)
	# A plate standing out from him (a crest, a brim): the fine voxels its tile holds. (A horn's
	# narrowing to its point.)
	var taper := id == "hat_horns"
	for ci in n:
		if first[ci] == 1:
			continue
		var xf: Transform3D = base[ci]
		var inv := xf.affine_inverse()
		var half := p.vf * p.part_scale * float(Data.body_res) * 0.49
		var lo := Vector3.ONE * INF
		var hi := -Vector3.ONE * INF
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					var w := xf * (Vector3(cx, cy, cz) * half)
					lo = lo.min(w)
					hi = hi.max(w)
		var i0 := Vector3i(((lo - o) / sp - Vector3.ONE * 0.5).floor())
		var i1 := Vector3i(((hi - o) / sp - Vector3.ONE * 0.5).ceil())
		for ix in range(i0.x, i1.x + 1):
			for iy in range(i0.y, i1.y + 1):
				for iz in range(i0.z, i1.z + 1):
					var q := o + (Vector3(ix, iy, iz) + Vector3.ONE * 0.5) * sp
					var l := inv * q
					if absf(l.x) <= half and absf(l.y) <= half and absf(l.z) <= half:
						if taper and Vector2(l.x, l.y).length() > half * (1.05 - 0.85 * (l.z + half) / (2.0 * half)):
							continue
						var kc := Vector3i(ix, iy, iz)
						if not owner.has(kc):
							owner[kc] = ci
	if owner.is_empty():
		return {}
	# The piece as the gladiators wore it (only the look; see _style): a galea's crest with its
	# plume and its brim at the brow, a greave's knee.
	var style := _style(id, p)
	var extra := {}
	if style.get("crest", false) and p.fine.has("wc"):
		_crest(p.fine.wc, owner, extra, o, sp)
	if style.get("brim", false) and p.fine.has("wc"):
		_brim(p.fine.wc, owner, extra, o, sp, float(style.get("brim_w", 2.0)) / kf)
	if style.get("boss", false):
		_boss(org, first, owner, extra, o, sp, cube)
	if style.get("curls", false) and p.fine.has("wc"):
		_curls(p.fine.wc, owner, o, sp)
	# (A piece in bands: where each row of its plates lies on him, so the bands run straight and
	# level round him, the same on his left as on his right: user, the lorica was not symmetrical.)
	var bands := _band_rows(ad, org, o, sp, cube, p) if style.get("seams", true) else {}
	var cnt := owner.size()
	var rel := []
	rel.resize(cnt)
	var of := {}
	var plate := PackedInt32Array()
	plate.resize(cnt)
	var buf := PackedFloat32Array()
	buf.resize(cnt * 20)
	var xk := PackedByteArray()
	xk.resize(cnt)
	var keys := owner.keys()
	var box := Basis.from_scale(sp * 1.04)
	for s in cnt:
		var kc: Vector3i = keys[s]
		var ci: int = owner[kc]
		plate[s] = ci
		# (An Array, not a packed one: a packed array read out of the dictionary is a copy.)
		if not of.has(ci):
			of[ci] = []
		(of[ci] as Array).append(s)
		var cxf := Transform3D(box, o + (Vector3(kc) + Vector3.ONE * 0.5) * sp)
		rel[s] = (base[ci] as Transform3D).affine_inverse() * cxf
		var b := s * 20
		buf[b] = cxf.basis.x.x
		buf[b + 1] = cxf.basis.y.x
		buf[b + 2] = cxf.basis.z.x
		buf[b + 3] = cxf.origin.x
		buf[b + 4] = cxf.basis.x.y
		buf[b + 5] = cxf.basis.y.y
		buf[b + 6] = cxf.basis.z.y
		buf[b + 7] = cxf.origin.y
		buf[b + 8] = cxf.basis.x.z
		buf[b + 9] = cxf.basis.y.z
		buf[b + 10] = cxf.basis.z.z
		buf[b + 11] = cxf.origin.z
		var kd: int = int(ad.kinds[ci]) if ad.has("kinds") and ci < (ad.kinds as Array).size() else 3
		var col := _shade(ad, ci, kc, owner, bare, ground.within, style, p.dims, bands)
		xk[s] = int(extra.get(kc, 0))
		match int(xk[s]):
			CREST:
				col = _lit(col, 1.1)
			PLUME:
				# Dyed horsehair, in strands.
				var pc: Color = style.get("plume", Color(0.6, 0.07, 0.05))
				col = _lit(pc, (0.8 + 0.3 * _hash(kc)) * (0.86 if posmod(kc.z, 2) == 0 else 1.0))
				kd = 2
			BRIM:
				col = _lit(col, 1.06)
			BOSS:
				col = _lit(col, 1.16)
		buf[b + 12] = col.r
		buf[b + 13] = col.g
		buf[b + 14] = col.b
		buf[b + 15] = col.a
		var cu := VoxelPart.kind_data(kd, _ao(kc, owner), 0)
		buf[b + 16] = cu.r
		buf[b + 17] = cu.g
		buf[b + 18] = cu.b
		buf[b + 19] = cu.a
	var out := {"cnt": cnt, "base": base, "rel": rel, "of": of, "plate": plate, "buf": buf, "xk": xk}
	if _shells.size() >= SHELL_KEEP:
		_shells.erase(_shells.keys()[0])
	_shells[lkey] = out
	return out

## How far from its plate (`d`: from the plate to the fine voxel, along him) the plate's shell reaches
## that way: on to the neighbour that lies that way (`nb`: to each of its neighbours), else, past
## the piece's edge, half the tile (as far as the neighbour behind it lies, or a plate's cube).
static func _reach(d: Vector3, nb: PackedVector3Array, cube: float, cellv: float) -> float:
	var dl := d.length()
	if dl < 0.0001:
		return INF
	var u := d / dl
	var ahead := 0.0
	var back := 0.0
	var best_a := 0.5   # (within 60 degrees of the way)
	var best_b := -0.5
	for v in nb:
		var vl := v.length()
		var cs := u.dot(v / vl)
		if cs > best_a:
			best_a = cs
			ahead = vl
		if cs < best_b:
			best_b = cs
			back = vl
	if ahead > 0.0:
		return ahead * 0.8 + cellv * 0.5
	return (back if back > 0.0 else cube) * 0.5 + cellv * 0.6

## The plates in bucket `kb` and in the 26 round it (first-layer plates), gathered once a bucket.
static func _near(near: Dictionary, bucket: Dictionary, kb: Vector3i) -> PackedInt32Array:
	var got = near.get(kb)
	if got != null:
		return got
	var l := PackedInt32Array()
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var arr = bucket.get(kb + Vector3i(dx, dy, dz))
				if arr != null:
					l.append_array(arr)
	near[kb] = l
	return l

## The shell's material: the fine voxels' own, as his body's and his head's (the blocks' darkened
## each small voxel's edges), its bronze polished as the arena's was, never gone green in its
## corners and in spots (on thousands of small voxels the helmet was drawn as curly hair, user).
static var _mat: ShaderMaterial = null
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = FineHead.material().duplicate()
		_mat.set_shader_parameter("patina", 0.0)
		# (Polished metal in one piece: the small voxels' own edges barely shown, or the bands read
		# as knitted wool, user.)
		_mat.set_shader_parameter("edge_dark", 0.035)
		# (Iron that reads in the sun, its bands and its strips: as a mirror of the sky it was near
		# black, and each small voxel's scratch flecked it like granite.)
		_mat.set_shader_parameter("iron_metal", 0.5)
		_mat.set_shader_parameter("scratches", 0.3)
	_mat.set_shader_parameter("ao_strength", VoxelPart.ao_strength * FineHead.AO_K)
	return _mat

## The shell of plate `ci` drawn as its tile is drawn now (`xf`: where the tile is, or nothing).
static func sync(ad: Dictionary, ci: int, xf: Transform3D) -> void:
	var sh = ad.get("shell")
	if not (sh is Dictionary) or not is_instance_valid(sh.mi):
		return
	var mm: MultiMesh = sh.mm
	var rel: Array = sh.rel
	(sh.now as Dictionary)[ci] = xf   # (where each plate's tile is drawn now: read back, never off the drawing)
	for s in (sh.of as Dictionary).get(ci, []):
		mm.set_instance_transform(s, xf * (rel[s] as Transform3D))

## Every plate's shell as its tile is drawn now (laid again where it is still on him).
static func sync_all(p: VoxelPart, ad: Dictionary) -> void:
	var sh = ad.get("shell")
	if not (sh is Dictionary):
		return
	for ci in (sh.of as Dictionary):
		var c := int(ci)
		var on: bool = ad.on[c] == 1 and not (ad.has("clip") and c < (ad.clip as PackedByteArray).size() and (ad.clip as PackedByteArray)[c] == 1)
		sync(ad, c, Physique.plate_xf(p, ad.cells[c], ad.pts[c] as Vector3, String(ad.id)) if on else Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

## The shell taken off (the piece's tiles drawn again).
static func clear(ad: Dictionary) -> void:
	var sh = ad.get("shell")
	if sh is Dictionary:
		var mi = sh.get("mi")
		if mi != null and is_instance_valid(mi):
			var p = mi.get_parent()
			if p is VoxelPart:
				(p as VoxelPart).draw_with.erase(mi)
			mi.queue_free()
		ad.erase("shell")
	var node = ad.get("node")
	if node != null and is_instance_valid(node):
		(node as Node3D).visible = true

# ---------- The ground the shell lies on ----------

static func _key(p: VoxelPart) -> String:
	if p.fine.has("wtab"):
		return "h|%s|%s|%s|%.5f" % [String(p.fine.get("giant", "")), str(p.grid), str(snappedf(float(p.fine.get("hs", 1.0)), 0.0001)), p.vf * p.part_scale]
	return "b|%s|%s|%.5f" % [String(p.fine.get("build", "")), String(p.part_name), p.vf * p.part_scale]

## The fine voxels just outside him there, THICK deep, on the lattice he is drawn on:
## {o, sp (the lattice: a voxel's middle at o + (i + 0.5) * sp), pts (their middles), idx (their i)};
## `k` over 1, the voxels that many times bigger (_coarse).
static func _ground(p: VoxelPart, k := 1.0) -> Dictionary:
	var key := _key(p) + ("|%.2f" % k)
	if _bands.has(key):
		return _bands[key]
	var thick := THICK if k <= 1.0 else COARSE_THICK
	var out := _ground_head(p, thick) if p.fine.has("wtab") else _ground_body(p, thick)
	if k > 1.0 and not out.is_empty():
		out = _coarse(out, k)
	if _bands.size() >= BAND_KEEP:
		_bands.erase(_bands.keys()[0])
	_bands[key] = out
	return out

## The fine shell `g` on a lattice `k` times as big: each of its voxels kept where its middle lies in
## one of the fine shell's (not every one a fine voxel only touches: kept, the shell stood a voxel
## off him, bulky, its edges ragged). The line down his middle (x = 0) between two of its voxels,
## as the fine lattice's: the same on his left as on his right.
static func _coarse(g: Dictionary, k: float) -> Dictionary:
	var o: Vector3 = g.o
	var sp: Vector3 = g.sp
	var cs := sp * k
	var oc := Vector3(-ceilf(-o.x / cs.x - 0.0001) * cs.x, o.y, o.z)
	var fi: PackedInt32Array = g.idx
	var seen := {}
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	for s in fi.size() / 3:
		var lo := o + Vector3(fi[s * 3], fi[s * 3 + 1], fi[s * 3 + 2]) * sp
		# (A coarse voxel's middle in this fine one: at most one, the coarse lattice the wider.)
		var j := Vector3i(((lo - oc) / cs - Vector3.ONE * 0.5).ceil())
		var m := oc + (Vector3(j) + Vector3.ONE * 0.5) * cs
		if m.x >= lo.x + sp.x or m.y >= lo.y + sp.y or m.z >= lo.z + sp.z or seen.has(j):
			continue
		seen[j] = true
		pts.append(m)
		idx.append(j.x)
		idx.append(j.y)
		idx.append(j.z)
	return {"o": oc, "sp": cs, "pts": pts, "idx": idx, "within": seen, "k": k}

## Round the fine head, seen from its middle: the farthest of its fine voxels each way (finer than
## FineHead's own outline, smoothed), the shell from there out.
const H_AZ := 96
const H_EL := 48
static func _ground_head(p: VoxelPart, thick := THICK) -> Dictionary:
	var fine := p.fine
	var cxf: Array = fine.xf
	if cxf.is_empty():
		return {}
	var hs := float(fine.get("hs", 1.0))
	var t: Dictionary = FineHead.giant_template(String(fine.get("giant", ""))) if String(fine.get("giant", "")) != "" else FineHead.template()
	var res := int(t.get("res", 3))
	var vox := p.vf * p.part_scale
	var fsz := vox / float(res)
	var half := Vector3(p.grid) * vox * 0.5
	var pivot: Vector3 = fine.get("pivot", Vector3(0.0, half.y, 0.0))
	var sc := Vector3(1.06, 1.04, 1.04)
	var sp := fsz * sc * hs
	var o := pivot * (1.0 - hs) - half * sc * hs
	var c: Vector3 = fine.wc
	var cell := sp.x
	var tab := PackedFloat32Array()
	tab.resize(H_AZ * H_EL)
	for tr in cxf:
		var v: Vector3 = (tr as Transform3D).origin - c
		var r := v.length()
		if r < 0.0001:
			continue
		var k := _hbin(v / r)
		tab[k] = maxf(tab[k], r + cell * 0.5)
	for pass_ in 12:
		var empty := false
		var nt := tab.duplicate()
		for el in H_EL:
			for az in H_AZ:
				var k := el * H_AZ + az
				if tab[k] > 0.0:
					continue
				var best := 0.0
				for dd in [[0, 1], [0, -1], [1, 0], [-1, 0]]:
					var e2: int = el + int(dd[0])
					if e2 < 0 or e2 >= H_EL:
						continue
					best = maxf(best, tab[e2 * H_AZ + posmod(az + int(dd[1]), H_AZ)])
				nt[k] = best
				empty = empty or best <= 0.0
		tab = nt
		if not empty:
			break
	# Smoothed (a plate of it never shows the bins), never in under the farthest round it by more
	# than a third of a voxel.
	var sm := tab.duplicate()
	for el in H_EL:
		for az in H_AZ:
			var s := 0.0
			var mx := 0.0
			var cntn := 0.0
			for e2 in range(maxi(0, el - 1), mini(H_EL, el + 2)):
				for a2 in [az - 1, az, az + 1]:
					var r2 := tab[e2 * H_AZ + posmod(a2, H_AZ)]
					s += r2
					mx = maxf(mx, r2)
					cntn += 1.0
			sm[el * H_AZ + az] = maxf(s / cntn, mx - cell * 0.35)
	var T := thick * cell
	var seen := {}
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	var sub := 2
	for el in H_EL * sub:
		var e := (float(el) + 0.5) / float(H_EL * sub)
		var lat := e * PI - PI * 0.5
		for az in H_AZ * sub:
			var a := (float(az) + 0.5) / float(H_AZ * sub)
			var lon := a * TAU - PI
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var R := _hlook(sm, e * float(H_EL) - 0.5, a * float(H_AZ) - 0.5)
			if R <= 0.0:
				continue
			var r := R + cell * 0.25
			while r < R + T:
				var q := c + d * r
				var iv := Vector3i(((q - o) / sp).floor())
				if not seen.has(iv):
					seen[iv] = true
					pts.append(o + (Vector3(iv) + Vector3.ONE * 0.5) * sp)
					idx.append(iv.x)
					idx.append(iv.y)
					idx.append(iv.z)
				r += cell * 0.4
	return {"o": o, "sp": sp, "pts": pts, "idx": idx, "within": seen}

static func _hbin(d: Vector3) -> int:
	var az := posmod(int(floorf((atan2(d.z, d.x) + PI) / TAU * H_AZ)), H_AZ)
	var el := clampi(int(floorf((asin(clampf(d.y, -1.0, 1.0)) + PI * 0.5) / PI * H_EL)), 0, H_EL - 1)
	return el * H_AZ + az

static func _hlook(tab: PackedFloat32Array, fe: float, fa: float) -> float:
	var e0 := clampi(int(floorf(fe)), 0, H_EL - 1)
	var e1 := mini(e0 + 1, H_EL - 1)
	var we := clampf(fe - float(e0), 0.0, 1.0)
	var a0f := floorf(fa)
	var wa := fa - a0f
	var a0 := posmod(int(a0f), H_AZ)
	var a1 := (a0 + 1) % H_AZ
	var r0 := tab[e0 * H_AZ + a0] * (1.0 - wa) + tab[e0 * H_AZ + a1] * wa
	var r1 := tab[e1 * H_AZ + a0] * (1.0 - wa) + tab[e1 * H_AZ + a1] * wa
	return r0 * (1.0 - we) + r1 * we

## Round a limb or his trunk, row by row of his fine voxels: how far out he is each way round
## (his fine voxels' own), the shell from there out; where he narrows from one row to the next
## (his shoulders up to his neck) the step between filled; over his top and under his end a cap.
const B_ANG := 64
static func _ground_body(p: VoxelPart, thick := THICK) -> Dictionary:
	var d: Dictionary = p.fine.get("d", {})
	if d.is_empty():
		return {}
	var cells: PackedInt32Array = d.cells
	var tpl := FineBody.template()
	var margin := int(tpl.get("margin", 10))
	var vox := p.vf * p.part_scale
	var fsz := vox / 2.0
	var h := Vector3(p.grid) * vox * 0.5
	var o := -h - Vector3.ONE * float(margin) * fsz
	var sp := Vector3.ONE * fsz
	var rows := p.grid.y * 2 + margin * 2
	var tab := PackedFloat32Array()
	tab.resize(rows * B_ANG)
	var n := cells.size() / FineBody.CELL
	for s in n:
		var ix := cells[s * FineBody.CELL]
		var iy := cells[s * FineBody.CELL + 1]
		var iz := cells[s * FineBody.CELL + 2]
		var r := iy + margin
		if r < 0 or r >= rows:
			continue
		var x := -h.x + (float(ix) + 0.5) * fsz
		var z := -h.z + (float(iz) + 0.5) * fsz
		var rho := Vector2(x, z).length() + fsz * 0.5
		var a := posmod(int(floorf((atan2(z, x) + PI) / TAU * B_ANG)), B_ANG)
		tab[r * B_ANG + a] = maxf(tab[r * B_ANG + a], rho)
	# A row with him in it has him all the way round (a way between two of his voxels: theirs).
	for r in rows:
		var any := false
		for a in B_ANG:
			if tab[r * B_ANG + a] > 0.0:
				any = true
				break
		if not any:
			continue
		for pass_ in 8:
			var empty := false
			var nt := tab.slice(r * B_ANG, (r + 1) * B_ANG)
			for a in B_ANG:
				if nt[a] > 0.0:
					continue
				var b := maxf(tab[r * B_ANG + posmod(a - 1, B_ANG)], tab[r * B_ANG + posmod(a + 1, B_ANG)])
				nt[a] = b
				empty = empty or b <= 0.0
			for a in B_ANG:
				tab[r * B_ANG + a] = nt[a]
			if not empty:
				break
	var T := thick * fsz
	var seen := {}
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	var sub := 3
	var caps := int(ceilf(thick))
	for r in rows:
		for a in B_ANG * sub:
			var fa := (float(a) + 0.5) / float(sub) - 0.5
			var a0 := posmod(int(floorf(fa)), B_ANG)
			var a1 := (a0 + 1) % B_ANG
			var wa := fa - floorf(fa)
			var R := tab[r * B_ANG + a0] * (1.0 - wa) + tab[r * B_ANG + a1] * wa
			if R <= 0.0:
				continue
			var th := (fa + 0.5) / float(B_ANG) * TAU - PI
			var dx := cos(th)
			var dz := sin(th)
			var lo_r := R
			var hi_r := R + T
			for rn in [r - 1, r + 1]:
				if rn < 0 or rn >= rows:
					continue
				var Rn := tab[rn * B_ANG + a0] * (1.0 - wa) + tab[rn * B_ANG + a1] * wa
				if Rn > 0.0:
					lo_r = minf(lo_r, Rn)
			_ring(r, dx, dz, lo_r, hi_r, fsz, o, sp, seen, pts, idx)
			# Over his top, under his end: a cap.
			for side in [1, -1]:
				var rn: int = r + side
				var Rn := 0.0
				if rn >= 0 and rn < rows:
					Rn = tab[rn * B_ANG + a0] * (1.0 - wa) + tab[rn * B_ANG + a1] * wa
				if Rn > 0.0:
					continue
				for k in range(1, caps + 1):
					var rc: int = r + side * k
					if rc >= 0 and rc < rows:
						_ring(rc, dx, dz, 0.0, R + T * 0.5, fsz, o, sp, seen, pts, idx)
	# (And his front and his back, column by column, where the way round from his middle misses
	# them: between a shoulder's top and his neck he is hollow seen from his middle, and the shell
	# left him bare there.)
	var face := {}
	for s in n:
		var key2 := Vector2i(cells[s * FineBody.CELL], cells[s * FineBody.CELL + 1])
		var iz := cells[s * FineBody.CELL + 2]
		var cur: Vector2i = face.get(key2, Vector2i(iz, iz))
		face[key2] = Vector2i(mini(cur.x, iz), maxi(cur.y, iz))
	for key2 in face:
		var zr: Vector2i = face[key2]
		for k in range(1, caps + 1):
			for iz2 in [zr.y + k, zr.x - k]:
				var iv := Vector3i(key2.x + margin, key2.y + margin, int(iz2) + margin)
				if not seen.has(iv):
					seen[iv] = true
					pts.append(o + (Vector3(iv) + Vector3.ONE * 0.5) * sp)
					idx.append(iv.x)
					idx.append(iv.y)
					idx.append(iv.z)
	return {"o": o, "sp": sp, "pts": pts, "idx": idx, "within": seen}

static func _ring(r: int, dx: float, dz: float, lo_r: float, hi_r: float, fsz: float, o: Vector3, sp: Vector3, seen: Dictionary, pts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var rr := lo_r
	while rr < hi_r:
		var x := dx * rr
		var z := dz * rr
		var iv := Vector3i(int(floorf((x - o.x) / sp.x)), r, int(floorf((z - o.z) / sp.z)))
		if not seen.has(iv):
			seen[iv] = true
			pts.append(o + (Vector3(iv) + Vector3.ONE * 0.5) * sp)
			idx.append(iv.x)
			idx.append(iv.y)
			idx.append(iv.z)
		rr += fsz * 0.55

# ---------- Its look ----------

## A fine voxel's colour: its plate's stuff (or the paint the bench put on it), a bright rim where
## the shell ends with a rivet now and then, a dark line where one row of plates meets the next.
static func _shade(ad: Dictionary, ci: int, kc: Vector3i, owner: Dictionary, bare: Color, within: Dictionary, style: Dictionary, dims: Vector3i, bands := {}) -> Color:
	var c: Array = ad.cells[ci]
	var col := Color.hex((int(c[3]) << 8) | 0xff) if c.size() > 3 else bare
	var cosmetic := Fighter._cosmetic(String(ad.id))
	if cosmetic and ad.has("cols") and ci < (ad.cols as Array).size():
		col = ad.cols[ci]
	var metal := true
	if ad.has("kinds") and ci < (ad.kinds as Array).size():
		metal = int(ad.kinds[ci]) == 3 or int(ad.kinds[ci]) == 4
	var rim := false
	for dv in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if owner.get(kc + dv) == null and within.has(kc + dv):
			rim = true   # (its rim: where the shell ends on him, not its inside or its outside face)
	if cosmetic and String(ad.id).begins_with("hair_"):
		# Hair in strands: lighter and darker voxel to voxel down its fall, its edge in shadow.
		var hk := 0.86 + 0.26 * _hash(kc) * (0.7 + 0.3 * _hash(Vector3i(kc.x, 0, kc.z)))
		return _lit(col, hk * (0.82 if rim else 1.0))
	if bands.is_empty():
		# One moulded piece: a hair's difference from voxel to voxel.
		var k := 0.985 + 0.03 * _hash(kc)
		if rim:
			k = 1.16 if metal else 0.8
		return _lit(col, k)
	return _lit(col, _band_light(kc, bands, rim, metal))

## Iron in bands, as a lorica's hoops were (and a manica's lames): each of the piece's rows a hoop,
## a dark groove along its lower edge where the one under it laps it, lit up to its top edge. On the
## trunk (a lorica as the legions' smiths made it, user): the girth hoops from the waist up, meeting
## down the front at the closure with a rivet each side of it in every hoop; over them a breastplate
## in front and a back plate behind; a rolled rim round the neck; and over each shoulder a guard
## of curved strips, front to back, laid from the neck out and down over the arm, each lapping the
## next. The same on both sides.
static func _band_light(kc: Vector3i, bands: Dictionary, rim: bool, metal: bool) -> float:
	var q: Vector3 = (bands.o as Vector3) + (Vector3(kc) + Vector3.ONE * 0.5) * (bands.sp as Vector3)
	var cube: float = bands.cube
	var fs: float = (bands.sp as Vector3).x
	var row := _row_at(q.y, bands)
	var k := 1.0
	var f1 := fposmod(row + 0.5, 1.0)   # (0 at a hoop's lower edge, 1 at its top)
	# (A line a voxel wide at the least, or on big voxels a hoop's groove, a rivet, came and went
	# hoop to hoop as its voxels' middles fell.)
	var rh := _row_h(q.y, bands)
	var gw := maxf(0.2, fs / rh)
	if not bands.trunk:
		k = 0.64 if f1 < gw else 0.84 + 0.3 * f1
	else:
		var hb: Vector3 = bands.hb
		var ax := absf(q.x)
		var zone := _trunk_zone(q, hb, cube, row, float(bands.breast))
		if zone == COLLAR:
			k = 1.2   # the rim rolled over at the neck
		elif zone == SHOULDER:
			# The guard's strips run front to back over him, each a slice of the round of his
			# shoulder as seen from in front (round the joint under it): six, from the neck out
			# over the top and down over the arm.
			var c := Vector2(hb.x - cube * 0.5, hb.y - cube * 1.75)
			var phi := atan2(maxf(q.y - c.y, 0.0), ax - c.x)
			var p0 := atan2(hb.y + cube * 0.5 - c.y, hb.x * NECK - c.x)   # (at the neck)
			var f := fposmod((p0 - phi) / maxf(p0, 0.5) * 6.0, 1.0)   # (0 under the edge of the strip inside it, 1 at its own edge)
			var arc := Vector2(ax - c.x, q.y - c.y).length() * maxf(p0, 0.5) / 6.0
			var e := clampf(fs / maxf(arc, 1e-4), 0.16, 0.45)
			k = 0.62 if f < e else (1.16 if f > 1.0 - e else 0.88 + 0.22 * f)
		elif zone == BREAST:
			var bh := maxf(float(bands.top_side) + 0.5 - float(bands.breast), 0.5)
			var fb := (row - float(bands.breast)) / bh
			k = 0.62 if fb < maxf(0.12, fs / (rh * bh)) else 0.97 + 0.1 * fb
			if ax > hb.x - cube * 0.5 - fs * 1.5:
				k = 1.14   # its edge, beside the shoulder guard
			elif q.z > 0.0 and ax < 0.55 * fs:
				k = 0.66   # the two halves meeting down the front
			elif q.z > 0.0 and ax < 1.6 * fs and absf(fb - 0.5) < 0.14:
				k = 1.5    # a rivet each side
		else:
			k = 0.62 if f1 < gw else 0.84 + 0.3 * f1
			if q.z > 0.0 and ax < 0.55 * fs:
				k = 0.66   # the closure down the front
			elif q.z > 0.0 and ax < 1.6 * fs and absf(f1 - 0.6) < maxf(0.14, 0.5 * fs / rh):
				k = 1.5    # a rivet each side of it, polished
			elif q.z < 0.0 and ax < 0.55 * fs and f1 >= gw:
				k = 0.84   # where the halves meet down the back
	if rim:
		k = maxf(k, 1.12) if metal else 0.8
	return k

## Where on the trunk a point of a piece's shell is: its girth hoops, the plates over the chest and
## the back, a shoulder's guard (over its top and out over the arm), the rim round the neck.
const HOOPS := 0
const SHOULDER := 1
const COLLAR := 2
const BREAST := 3
const NECK := 0.45   # (the neck's side, of the box's half width)
const LIFT := 4.0    # (how far a shoulder's guard stands off him over the top of the arm, fine voxels)
static func _trunk_zone(q: Vector3, hb: Vector3, cube: float, row: float, breast: float) -> int:
	var ax := absf(q.x)
	if q.y > hb.y + cube * 0.25 and ax < hb.x * NECK:
		return COLLAR
	if _over_shoulder(q, hb, cube):
		return SHOULDER
	if row > breast:
		return BREAST
	return HOOPS

## Whether a point round the trunk lies under a cuirass (above its lower edge): round him up to
## the bottom of the neck (a low collar; the neck above it bare), and over the shoulders.
static func _under_guard(q: Vector3, hb: Vector3, cube: float) -> bool:
	return q.y < hb.y + cube * 0.6 or _over_shoulder(q, hb, cube)

## Whether a point round the trunk lies over a shoulder: above the box's top (but for the neck),
## or out past its side up where the arm hangs from it.
static func _over_shoulder(q: Vector3, hb: Vector3, cube: float) -> bool:
	var ax := absf(q.x)
	if q.y > hb.y - cube * 0.25:
		return ax >= hb.x * NECK
	return q.y > hb.y - cube * 1.75 and ax > hb.x - cube * 0.5

## The fractional row of the piece at height `y` on him (its rows as the plates lie: straight even
## where his shape bunches or spreads them).
static func _row_at(y: float, bands: Dictionary) -> float:
	var ys: PackedFloat32Array = bands.ys
	var r0: int = bands.r0
	var n := ys.size()
	if n == 1:
		return float(r0) + (y - ys[0]) / float(bands.cube)
	if y <= ys[0]:
		return float(r0) + (y - ys[0]) / maxf(ys[1] - ys[0], 1e-4)
	for i in n - 1:
		if y < ys[i + 1]:
			return float(r0 + i) + (y - ys[i]) / maxf(ys[i + 1] - ys[i], 1e-4)
	return float(r0 + n - 1) + (y - ys[n - 1]) / maxf(ys[n - 1] - ys[n - 2], 1e-4)

## The height of the piece's row at `y` (as _row_at reads them: its plates' spacing there).
static func _row_h(y: float, bands: Dictionary) -> float:
	var ys: PackedFloat32Array = bands.ys
	var n := ys.size()
	if n == 1:
		return float(bands.cube)
	var i := 0
	while i < n - 2 and y >= ys[i + 1]:
		i += 1
	return maxf(ys[i + 1] - ys[i], 1e-4)

## A piece in bands on part `pn`: its rows' heights (each the middle of its plates as they lie),
## where its lattice is, and whether it is the trunk's (the closure, the strips).
static func _band_rows(ad: Dictionary, org: PackedVector3Array, o: Vector3, sp: Vector3, cube: float, p: VoxelPart) -> Dictionary:
	var sum := {}
	var cnt := {}
	var top := -INF
	for ci in (ad.cells as Array).size():
		var c: Array = ad.cells[ci]
		var r := int(c[1])
		sum[r] = float(sum.get(r, 0.0)) + org[ci].y
		cnt[r] = int(cnt.get(r, 0)) + 1
	var rows := sum.keys()
	rows.sort()
	if rows.is_empty():
		return {}
	var ys := PackedFloat32Array()
	var r0: int = rows[0]
	var last := -INF
	for r in range(r0, int(rows[rows.size() - 1]) + 1):
		var y: float = float(sum[r]) / float(cnt[r]) if sum.has(r) else last + cube
		y = maxf(y, last + 0.25 * cube)   # (rising, row on row)
		ys.append(y)
		last = y
	# (The top row round his sides, under the shoulders: the two under it and it the chest's
	# plates, if the piece reaches so high; the hoops under them.)
	var top_side := -INF
	for ci in (ad.cells as Array).size():
		var c: Array = ad.cells[ci]
		if int(c[1]) < p.dims.y:
			top_side = maxf(top_side, float(c[1]))
	var breast := top_side - 1.5 if top_side - float(r0) >= 4.0 else INF
	return {"ys": ys, "r0": r0, "top_side": top_side, "breast": breast, "o": o, "sp": sp, "cube": cube, "trunk": _over_top(ad, p),
		"hb": Vector3(p.grid) * p.vf * p.part_scale * 0.5}

## Whether piece `ad` is a cuirass: on the trunk, over the shoulders too (a lorica; not a cape).
static func _over_top(ad: Dictionary, p: VoxelPart) -> bool:
	if String(p.part_name) != "torso":
		return false
	for c in ad.cells:
		if int(c[1]) >= p.dims.y:
			return true
	return false

## A colour lit by `k` (in light, not in the colour's own numbers).
static func _lit(col: Color, k: float) -> Color:
	var lin := col.srgb_to_linear()
	return Color(clampf(lin.r * k, 0.0, 1.0), clampf(lin.g * k, 0.0, 1.0), clampf(lin.b * k, 0.0, 1.0)).linear_to_srgb()

# ---------- As the gladiators wore it ----------

const CREST := 1
const PLUME := 2
const BRIM := 3
const BOSS := 4

## How a piece is drawn on the new look, as the arena saw it in its day (only the look: its plates,
## what they stop and weigh are the piece's own): a galea one smooth bowl of bronze with a broad
## brim at the brow and a crest along the top, a plume of dyed horsehair on it (the gold one's
## white); a lorica and a manica in iron bands; greaves one moulded piece,
## the knee raised; a gold lorica moulded smooth; a skull plate or a jaw guard one smooth piece. A
## piece made at the bench: smooth on the head and the shins, in bands on the trunk and the arms.
static func _style(id: String, p: VoxelPart) -> Dictionary:
	if id.begins_with("hair_") or id.begins_with("hat_"):
		match id:
			"hat_straw":
				return {"seams": false, "brim": true, "brim_w": 4.5}
			"hair_curly", "hair_curls_top":
				return {"seams": false, "curls": true}
		return {"seams": false}
	match id:
		"helmet":
			return {"seams": false, "crest": true, "brim": true, "plume": Color(0.62, 0.07, 0.05)}
		"goldHelmet":
			return {"seams": false, "crest": true, "brim": true, "plume": Color(0.93, 0.9, 0.84)}
		"skullPlate", "ironJaw", "goldLorica", "cape_short":
			return {"seams": false}
		"lorica", "manica":
			return {"seams": true}
		"greaves":
			return {"seams": false, "boss": true}
	var pn := String(p.part_name)
	if pn == "head" or pn.begins_with("shin"):
		return {"seams": false}
	return {"seams": true}

## A fine voxel's place on the shell's lattice, and the middle of one.
static func _at(q: Vector3, o: Vector3, sp: Vector3) -> Vector3i:
	return Vector3i(((q - o) / sp).floor())

static func _mid(kc: Vector3i, o: Vector3, sp: Vector3) -> Vector3:
	return o + (Vector3(kc) + Vector3.ONE * 0.5) * sp

## A crest along the top of a helmet, from the brow to the nape, on the head's middle (one row of
## voxels, or the two either side of the middle: as wide each side), standing a voxel off the bowl,
## and on it the plume, two more: each the plate's under it.
static func _crest(wc: Vector3, owner: Dictionary, extra: Dictionary, o: Vector3, sp: Vector3) -> void:
	var cell := sp.x
	var fx := (wc.x - o.x) / sp.x - 0.5
	var cols := []
	for ix in [int(floorf(fx)), int(ceilf(fx))]:
		if absf(float(ix) - fx) < 0.75 and not cols.has(ix):
			cols.append(ix)
	var add := {}
	for kc in owner:
		if not cols.has(kc.x):
			continue
		var q := _mid(kc, o, sp)
		var d := q - wc
		if d.y < 0.3 * d.length():
			continue   # (the top of the head: the crest runs over it, not down the face)
		var dir := d.normalized()
		if owner.has(_at(q + dir * cell, o, sp)):
			continue   # (from the bowl's outside)
		var t := cell * 0.5
		while t <= cell * 3.0:
			var kk := _at(q + dir * t, o, sp)
			kk.x = kc.x
			if not owner.has(kk) and not add.has(kk):
				add[kk] = [owner[kc], CREST if t <= cell * 1.0 else PLUME]
			t += cell * 0.5
	for kk in add:
		owner[kk] = add[kk][0]
		extra[kk] = add[kk][1]

## A brim round the helmet at the brow (where the bowl ends over his face), two voxels wide, out
## from the bowl all round: each the plate's it stands out from.
static func _brim(wc: Vector3, owner: Dictionary, extra: Dictionary, o: Vector3, sp: Vector3, wide := 2.0) -> void:
	var cell := sp.x
	var row := 1 << 30
	for kc in owner:
		var d := _mid(kc, o, sp) - wc
		if d.z > 0.75 * d.length():
			row = mini(row, kc.y)   # (the bowl's lowest over his face: the brow)
	if row == 1 << 30:
		return
	var add := {}
	for kc in owner:
		if kc.y != row:
			continue
		var q := _mid(kc, o, sp)
		var h := Vector3(q.x - wc.x, 0.0, q.z - wc.z)
		if h.length() < 0.0001:
			continue
		var dir := h.normalized()
		if owner.has(_at(q + dir * cell, o, sp)):
			continue   # (from the bowl's outside)
		var t := cell * 0.5
		while t <= cell * wide:
			var kk := _at(q + dir * t, o, sp)
			kk.y = row
			if not owner.has(kk) and not add.has(kk):
				add[kk] = owner[kc]
			t += cell * 0.5
	for kk in add:
		owner[kk] = add[kk]
		extra[kk] = BRIM

## Curls standing out of a head of hair: here and there a voxel over its outside, each the
## lock's it stands out of (a head of curls drawn as a smooth cap read as a crop).
static func _curls(wc: Vector3, owner: Dictionary, o: Vector3, sp: Vector3) -> void:
	var cell := sp.x
	var add := {}
	for kc in owner:
		var q := _mid(kc, o, sp)
		var dir := (q - wc).normalized()
		var kk := _at(q + dir * cell, o, sp)
		if owner.has(kk) or add.has(kk) or _hash(kc) < 0.55:
			continue
		add[kk] = owner[kc]
	for kk in add:
		owner[kk] = add[kk]

## A greave's knee raised a voxel off it (the moulded knee), over the knee in front: each the
## plate's under it.
static func _boss(org: PackedVector3Array, first: PackedByteArray, owner: Dictionary, extra: Dictionary, o: Vector3, sp: Vector3, cube: float) -> void:
	var cell := sp.x
	var top := -INF
	for ci in org.size():
		if first[ci] == 1:
			top = maxf(top, org[ci].y)
	if top == -INF:
		return
	var add := {}
	for kc in owner:
		var q := _mid(kc, o, sp)
		if q.y < top - cube * 1.1 or q.y > top + cube * 0.4:
			continue
		var hz := Vector2(q.x, q.z)
		if hz.length() < 0.0001 or absf(atan2(q.x, q.z)) > 0.55:
			continue   # (in front: the greave's front is the shin's)
		var dir := Vector3(q.x, 0.0, q.z).normalized()
		var kk := _at(q + dir * cell, o, sp)
		if owner.has(kk) or add.has(kk):
			continue
		add[kk] = owner[kc]
	for kk in add:
		owner[kk] = add[kk]
		extra[kk] = BOSS

## Its corners shaded by the shell's own voxels round it (VoxelPart.ao_bits).
static func _ao(kc: Vector3i, owner: Dictionary) -> int:
	var bits := 0
	for f in 6:
		var fd: Array = VoxelPart.AO_FACES[f]
		var nb: Vector3i = kc + (fd[0] as Vector3i)
		if owner.has(nb):
			continue
		var ua := Vector3i.ZERO
		ua[int(fd[1])] = 1
		var va := Vector3i.ZERO
		va[int(fd[2])] = 1
		for cc in 4:
			var su := 1 if cc & 1 else -1
			var sv := 1 if cc & 2 else -1
			if owner.has(nb + ua * su) or owner.has(nb + va * sv) or owner.has(nb + ua * su + va * sv):
				bits |= 1 << (f * 4 + cc)
	return bits

static func _hash(v: Vector3i) -> float:
	return float(posmod(hash(v + Vector3i(31, 17, 5)), 1000)) / 1000.0
