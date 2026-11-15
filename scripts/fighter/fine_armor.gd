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

const FineSmooth := preload("res://scripts/fighter/fine_smooth.gd")
const THICK := 2.0          # the shell, fine voxels thick
## A piece of armour's shell in voxels this many times the fine ones each way, fewer and bigger, and
## closer on him (user): laid on a fine shell COARSE_THICK fine voxels thick, each of its voxels
## kept where its middle lies in that (_coarse). A hairstyle or a hat the fine voxels' own.
const COARSE := 1.5
const COARSE_THICK := 1.5
## The fine look's smooth light on a piece of armour's shell (FineSmooth, as on his body: each of
## its voxels lit by the way the shell faces there, the shape as a whole, not by the cube's own
## faces. The light alone: its voxels stay the cubes they are, user, the game's voxels are to stay
## voxels; with their corners moved onto the shape a helmet was a smooth bowl). LIGHT_REACH: how
## far the shell's shape is blurred for it (its voxels). LIGHT_LEAN: the furthest a voxel's way
## may lean off its own plate's way out of him (the cosine): at a piece's free edge the shape
## turns in under it, and the voxels there were lit as from below, black, holes in the piece.
const LIGHT_REACH := 2
const LIGHT_LEAN := 0.5
const LIGHT_GAP := 3        # how far under a plate the gap between it and him is taken as filled (the shell's voxels)
const LIGHT_EDGE := 0.3     # a voxel with less of the piece round it than this is at its edge (the piece blurred a voxel each way: a third in a sheet of it one voxel thick, two ninths at its straight edge)
const LIGHT_EDGE_W := 0.1   # and by this much less, all at its edge
const LIGHT_ROUGH := 0.56   # the least roughness of its metal under the smooth light (material)
const LIGHT_OWN := 0.04     # a voxel's own way's weight beside those round it, as they are evened out (their blur, its own a twenty-seventh of it)
const LIGHT_SKY := 0.95     # how far a piece's top takes the light of what is round it as its sides do (lit_material: in the shade its top was the sky's blue)
const BAND_KEEP := 24       # parts' grounds kept (a build, a part, a size each)
const SHELL_KEEP := 24      # shells kept (a piece on a build's part)
static var _bands := {}
static var _shells := {}
static var _unit: BoxMesh = null
static var _unit_lit: BoxMesh = null   # (a piece lit by its shape: lit_material)

## Whether the piece is drawn as a shell on `p` as it is drawn now.
static func wanted(p: VoxelPart, id: String) -> bool:
	if p.fine.is_empty():
		return false
	if Fighter._cosmetic(id):
		return hair_or_hat(p, id)
	if p.fine.has("wtab"):
		return true
	return p.fine.has("body") and not bool(p.fine.get("beast", false)) and (p.fine.get("d", {}) as Dictionary).has("k")

## A hat on a man's fine head (not a giant's: his head has its own): drawn as a shell round the
## head as a helmet is, the pieces that stand out from it as the fine voxels they hold (drawn as
## the head's cubes, a hat's piece the size of a voxel of his body, they stood off the fine head
## like blocks: user, the hats did not fit the new heads). (A hairstyle is the fine head's own
## hair: FineHead "hairs".)
static func hair_or_hat(p: VoxelPart, id: String) -> bool:
	return p.fine.has("wtab") and String(p.fine.get("giant", "")) == "" and id.begins_with("hat_")

## The shell of `ad` (a piece on `p`) drawn, or drawn again as the plates lie now; the plates'
## own tiles hidden. Not wanted (the classic looks): the shell gone, the tiles shown. `staged`: a
## man built while the fight goes on (Fighter.build): a shell not laid out before is worked out a
## little a frame (_pace), not all in one.
static func build(f, p: VoxelPart, ad: Dictionary, staged := false) -> void:
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
	var id := String(ad.id)
	var skin: Color = f.skin if f is Fighter else Color(0.6, 0.4, 0.3)
	var bare := ArmorStyle.base_color(id, Data.armor.get(id, {}), skin)
	if id.begins_with("hair_") and f is Fighter:
		var hc = Physique.hair_choice(f)
		if hc != null:
			bare = hc
	# (A helmet over a hairstyle not seen yet, laid out in one frame, was a tenth to a quarter of
	# a second's hitch as training's next foe came in.)
	var pace := {"t": Time.get_ticks_usec(), "fine": p.fine} if staged else {}
	var L: Dictionary = await _layout(p, ad, id, bare, pace)
	# (Gone while it was worked out, or drawn anew: whoever drew him anew laid his armour again,
	# and that is not to be taken off him.)
	if staged and (not is_instance_valid(p) or not is_instance_valid(node) or not is_same(p.fine, pace.fine)):
		return
	clear(ad)
	if L.is_empty():
		return
	# Drawn: each fine voxel a plate's, kept as where it lies on its plate's tile (a bend, a hide,
	# a knock that moves the tile moves it). The piece laid out once a build (_layout): a man is
	# dressed in a copy of it, the plates already knocked off him not drawn.
	if _unit == null:
		_unit = BoxMesh.new()
		_unit.size = Vector3.ONE
		_unit.material = material()
	var lit := FineSmooth.live() and not Fighter._cosmetic(id)
	if lit and _unit_lit == null:
		_unit_lit = BoxMesh.new()
		_unit_lit.size = Vector3.ONE
		_unit_lit.material = lit_material()
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
	mm.mesh = _unit_lit if lit else _unit
	mm.instance_count = cnt
	FineBody._keep_in_memory(mm)
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.name = "shell_" + id
	mi.top_level = true
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.custom_aabb = (node as MultiMeshInstance3D).custom_aabb
	mm.custom_aabb = mi.custom_aabb
	mi.transparency = p.see_through
	if p.fine.has("wtab"):
		# (A helmet's or a hat's small voxels, stepped round his head, shadowed one another in the
		# sun in dark blots that read as holes in it: user. It casts none; his head under it does.)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	mi.global_transform = p.global_transform
	p.draw_with.append(mi)
	ad["shell"] = {"key": key, "mi": mi, "mm": mm, "rel": L.rel, "of": of, "plate": L.plate, "now": now, "xk": L.xk, "cover": L.get("cover", {})}
	(node as Node3D).visible = false

## A piece's shell on a part as the part is drawn (its build, its size), the same for every man of
## it, worked out once: each plate's tile, which fine voxels of the ground round him are which
## plate's, each voxel's place on its plate's tile, and the drawing's buffer (the places with every
## plate on, the colours, the shading). Shared: read, never changed. `pace` not empty: worked out
## a little a frame (build `staged`), and nothing kept if he is gone or drawn anew meanwhile.
static func _layout(p: VoxelPart, ad: Dictionary, id: String, bare: Color, pace := {}) -> Dictionary:
	var n: int = ad.cells.size()
	var lkey := "%s|%s|%d|%d|%d|%d|%s|%d" % [_key(p), id, n, hash(ad.cells), hash(ad.pts), hash(ad.get("kinds", [])), bare.to_html(), hash(ad.get("cols", []))]
	var lit := FineSmooth.live() and not Fighter._cosmetic(id)
	if lit:
		lkey += "|lit"
	if _shells.has(lkey):
		var kept: Dictionary = _shells[lkey]
		_shells.erase(lkey)   # (the last used kept the longest: a helmet a hairstyle, more of them)
		_shells[lkey] = kept
		return kept
	var staged := pace.has("t")
	var ground: Dictionary = await _ground(p, 1.0 if Fighter._cosmetic(id) else COARSE, pace)
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
		if staged and (s & 127) == 127 and not await _pace(p, pace):
			return {}
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
			if staged and (s & 127) == 127 and not await _pace(p, pace):
				return {}
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
		if staged and not await _pace(p, pace):
			return {}
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
	if staged and not await _pace(p, pace):
		return {}
	# The piece as the gladiators wore it (only the look; see _style): a galea's crest with its
	# plume and its brim at the brow, a greave's knee.
	var style := _style(id, p)
	var extra := {}
	# His eyes left open (user: what bothered him in the helmets was that they covered his eyes).
	if style.has("face") and p.fine.has("eyes") and p.fine.has("wc"):
		if style.get("closed", false):
			_close_face(p, owner, ground, org, first, o, sp)
		if style.has("down_to_brow"):
			_down_to_brow(p, owner, ground, org, first, sp, float(style.down_to_brow))
		_open_face(p, owner, o, sp, String(style.face), float(style.get("eye_r", 1.3)))
	if style.get("crest", false) and p.fine.has("wc"):
		_crest(p.fine.wc, owner, extra, o, sp, float(style.get("crest_h", 1.0)), float(style.get("plume_h", 2.0)) if style.has("plume") else 0.0, style.get("griffin", false))
	if style.get("brim", false) and p.fine.has("wc"):
		var at_y := INF
		if style.get("brim_at", "") == "brow" and p.fine.has("brow_y"):
			at_y = float(p.fine.brow_y) + sp.y * 1.5
		_brim(p.fine.wc, owner, extra, o, sp, float(style.get("brim_w", 2.0)) / kf, at_y, float(style.get("brim_arc", -2.0)))
	if style.has("neck") and p.fine.has("wc"):
		_neck(p.fine.wc, owner, extra, o, sp, float(style.neck) / kf)
	if style.get("boss", false):
		_boss(org, first, owner, extra, o, sp, cube)
	if style.get("cap", false) and p.fine.has("wc"):
		_iron_cap(p.fine.wc, owner, extra, o, sp, ground.within)
	if style.get("curls", false) and p.fine.has("wc"):
		_curls(p.fine.wc, owner, o, sp)
	if staged and not await _pace(p, pace):
		return {}
	if p.fine.has("wtab"):
		_fill_pinholes(owner, ground.within)
	else:
		await _tidy(owner, extra, ground.within, skin_test(ground), pace, p)
		if staged and not _still(p, pace):
			return {}
		_rim_round_limbs(owner, extra, rest_cones(p), o, sp)
		if staged and not await _pace(p, pace):
			return {}
	if style.has("face"):
		_keep_whole(owner, extra)
	if staged and not await _pace(p, pace):
		return {}
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
	# (The piece on a grid of numbers, 1 where a voxel of it lies: its rim and its voxels' corner
	# shading are read off it, _ao_at.)
	var alo: Vector3i = keys[0]
	var ahi := alo
	for kc: Vector3i in keys:
		alo = alo.min(kc)
		ahi = ahi.max(kc)
	alo -= Vector3i.ONE * 2
	ahi += Vector3i.ONE * 2
	var ady := ahi.y - alo.y + 1
	var adz := ahi.z - alo.z + 1
	var ag := PackedByteArray()
	ag.resize((ahi.x - alo.x + 1) * ady * adz)
	for kc: Vector3i in keys:
		ag[((kc.x - alo.x) * ady + (kc.y - alo.y)) * adz + (kc.z - alo.z)] = 1
	var aof := _ao_steps(PackedInt32Array([ady * adz, adz, 1]))
	var a6 := PackedInt32Array([ady * adz, -ady * adz, adz, -adz, 1, -1])
	var d6 := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	# The way the shell faces at each of its voxels (the smooth light). Its shape: the shell and him
	# under it, his own fine voxels on the shell's lattice.
	var na := PackedFloat32Array()
	if lit:
		# (Each plate's way out of him: its tile's thin side, turned to point away from his middle.)
		var mid: Vector3 = p.fine.get("wc", Vector3.ZERO)
		var outs := PackedVector3Array()
		outs.resize(n)
		for ci in n:
			outs[ci] = nrm[ci] if nrm[ci].dot(org[ci] - mid) >= 0.0 else -nrm[ci]
		var under := {}
		var done := 0
		for t in p.fine.get("xf", []):
			var j := Vector3i((((t as Transform3D).origin - o) / sp).floor())
			if not owner.has(j):
				under[j] = true
			done += 1
			if staged and (done & 1023) == 0 and not await _pace(p, pace):
				return {}
		# (And the parts jointed on to this one, where they hang at rest: a cuirass's shoulder
		# guards lie over the tops of his arms, which are not his trunk's fine voxels.)
		var who = p.fighter
		if p.fine.has("body") and who != null and "parts" in who:
			var bn := String(p.fine.get("build", ""))
			for q: VoxelPart in who.parts:
				if q == p or String(q.part_name) == "head" or not (q.parent_part == p or p.parent_part == q):
					continue
				var qd := FineBody.part_data(bn, String(q.part_name))
				if qd.is_empty():
					continue
				var qf := q.vf * q.part_scale * 0.5
				var q_lo: Vector3 = -Vector3(q.grid) * qf + ((q.pa - q.ca) if q.parent_part == p else (p.ca - p.pa))
				var qc: PackedInt32Array = qd.cells
				for i in qc.size() / FineBody.CELL:
					var j := Vector3i(((q_lo + (Vector3(qc[i * FineBody.CELL], qc[i * FineBody.CELL + 1], qc[i * FineBody.CELL + 2]) + Vector3.ONE * 0.5) * qf - o) / sp).floor())
					if not owner.has(j):
						under[j] = true
					done += 1
					if staged and (done & 1023) == 0 and not await _pace(p, pace):
						return {}
		# (And what lies between a plate and him: where a piece stands off him, a shoulder guard's
		# rim over his arm, the shell's shape turned in under it, into the gap.)
		var gap := {}
		for kc: Vector3i in keys:
			var way_out: Vector3 = outs[owner[kc]]
			for deep in range(1, LIGHT_GAP + 1):
				var below := Vector3i((Vector3(kc) + Vector3.ONE * 0.5 - way_out * float(deep)).floor())
				if under.has(below):
					break
				if not owner.has(below):
					gap[below] = true
			done += 1
			if staged and (done & 511) == 0 and not await _pace(p, pace):
				return {}
		under.merge(gap)
		var at := FineSmooth.triples(keys)
		var sol := FineSmooth.solid(at, FineSmooth.triples(under.keys()), 1, true, not p.fine.has("wtab"))
		na = FineSmooth.ways(at, FineSmooth.blurred(sol, LIGHT_REACH))
		if staged and not await _pace(p, pace):
			return {}
		# On the shape's own grid (FineSmooth.solid): how much of the piece lies round each of its
		# voxels, and each voxel's way evened with those round it, by the core's blur. (Asked of
		# the dictionary of places voxel by voxel, 26 round each, these were a tenth of a second.)
		var fsy: int = sol.sy
		var fsz: int = sol.sz
		var flo: Vector3i = sol.lo
		var fpad: int = sol.pad
		var total: int = (sol.f as PackedFloat32Array).size()
		var cell := PackedInt32Array()
		cell.resize(cnt)
		var occ := PackedFloat32Array()
		occ.resize(total)
		for s in cnt:
			var kc: Vector3i = keys[s]
			var i := ((kc.x - flo.x + fpad) * fsy + kc.y - flo.y + fpad) * fsz + kc.z - flo.z + fpad
			cell[s] = i
			occ[i] = 1.0
		var grid := {"sx": sol.sx, "sy": fsy, "sz": fsz, "lo": flo, "pad": fpad}
		grid["f"] = occ
		var dens: PackedFloat32Array = FineSmooth.blurred(grid, 1).f
		# (At the piece's free edge its voxels are lit as their own plate faces, more so the less
		# of the piece lies round them: the edge of a plate catching the light, as it did.)
		var dec := _decoded()
		var wx := PackedFloat32Array()
		var wy := PackedFloat32Array()
		var wz := PackedFloat32Array()
		wx.resize(total)
		wy.resize(total)
		wz.resize(total)
		var ws := PackedVector3Array()
		ws.resize(cnt)
		for s in cnt:
			var way_out: Vector3 = outs[owner[keys[s]]]
			var w: Vector3 = dec[int(na[s]) - 2] if na[s] > 1.5 else way_out
			var i := cell[s]
			var edge := clampf((LIGHT_EDGE - dens[i]) / LIGHT_EDGE_W, 0.0, 1.0)
			if edge > 0.0:
				w = w.lerp(way_out, edge).normalized()
			ws[s] = w
			wx[i] = w.x
			wy[i] = w.y
			wz[i] = w.z
		if staged and not await _pace(p, pace):
			return {}
		# (And each as those round it: one voxel of a guard's corner, turned to the sun where the
		# rest were not, was a white square on the piece, user, stray pieces in the armour.)
		grid["f"] = wx
		wx = FineSmooth.blurred(grid, 1).f
		grid["f"] = wy
		wy = FineSmooth.blurred(grid, 1).f
		grid["f"] = wz
		wz = FineSmooth.blurred(grid, 1).f
		var lim := sqrt(1.0 - LIGHT_LEAN * LIGHT_LEAN)
		for s in cnt:
			var i := cell[s]
			var w := Vector3(wx[i], wy[i], wz[i]) + ws[s] * LIGHT_OWN
			var l := w.length()
			w = w / l if l > 0.0001 else ws[s]
			# (Held within LIGHT_LEAN of its plate's way out of him: lean.)
			var way_out: Vector3 = outs[owner[keys[s]]]
			var d := w.dot(way_out)
			if d < LIGHT_LEAN:
				var side := w - way_out * d
				var sl := side.length()
				w = way_out if sl < 0.001 else side / sl * lim + way_out * LIGHT_LEAN
			na[s] = FineSmooth.encode(w)
	# (What is the same for every voxel of a plate, or of the piece, is worked out once: a voxel's
	# share of the work was most of the time a piece took to lay out.)
	var cosmetic := Fighter._cosmetic(id)
	var hair := cosmetic and id.begins_with("hair_")
	var kinds: Array = ad.kinds if ad.has("kinds") else []
	var cols: Array = ad.cols if cosmetic and ad.has("cols") else []
	var within: Dictionary = ground.within
	var dark := float(style.get("dark", 1.0))
	var inv := []                      # each plate's tile, the other way
	inv.resize(n)
	var pcol := PackedColorArray()     # each plate's own colour
	pcol.resize(n)
	var pkind := PackedByteArray()     # 1: worked out; 2: of metal
	pkind.resize(n)
	var bx := box.x.x
	var by := box.y.y
	var bz := box.z.z
	for s in cnt:
		if staged and (s & 127) == 127 and not await _pace(p, pace):
			return {}
		var kc: Vector3i = keys[s]
		var ci: int = owner[kc]
		plate[s] = ci
		# (An Array, not a packed one: a packed array read out of the dictionary is a copy.)
		if not of.has(ci):
			of[ci] = []
		(of[ci] as Array).append(s)
		if pkind[ci] == 0:
			var c: Array = ad.cells[ci]
			pcol[ci] = cols[ci] if ci < cols.size() else (Color.hex((int(c[3]) << 8) | 0xff) if c.size() > 3 else bare)
			pkind[ci] = 3 if ci >= kinds.size() or int(kinds[ci]) == 3 or int(kinds[ci]) == 4 else 1
			inv[ci] = (base[ci] as Transform3D).affine_inverse()
		var mid := o + (Vector3(kc) + Vector3.ONE * 0.5) * sp
		rel[s] = (inv[ci] as Transform3D) * Transform3D(box, mid)
		var b := s * 20
		buf[b] = bx
		buf[b + 3] = mid.x
		buf[b + 5] = by
		buf[b + 7] = mid.y
		buf[b + 10] = bz
		buf[b + 11] = mid.z
		var kd: int = int(kinds[ci]) if ci < kinds.size() else 3
		# (Its rim: where the shell ends on him, not its inside or its outside face.)
		var at := ((kc.x - alo.x) * ady + (kc.y - alo.y)) * adz + (kc.z - alo.z)
		var rim := false
		for f in 6:
			if ag[at + a6[f]] == 0 and within.has(kc + (d6[f] as Vector3i)):
				rim = true
				break
		var col := _shade(pcol[ci], pkind[ci] == 3, rim, hair, kc, dark, bands)
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
			BAND:
				col = _lit(col, 1.18)
			RIVET, KNOB:
				col = BRASS
		buf[b + 12] = col.r
		buf[b + 13] = col.g
		buf[b + 14] = col.b
		buf[b + 15] = na[s] if na.size() == cnt else col.a
		var cu := VoxelPart.kind_data(kd, _ao_at(ag, at, aof), 0)
		buf[b + 16] = cu.r
		buf[b + 17] = cu.g
		buf[b + 18] = cu.b
		buf[b + 19] = cu.a
	var out := {"cnt": cnt, "base": base, "rel": rel, "of": of, "plate": plate, "buf": buf, "xk": xk}
	if p.fine.has("wc"):
		out["cover"] = _cover(p.fine.wc, keys, plate, first, xk, o, sp)
	if staged and not await _pace(p, pace):
		return {}
	if _shells.size() >= SHELL_KEEP:
		_shells.erase(_shells.keys()[0])
	_shells[lkey] = out
	return out

## On a head: the ways out of it (FineHead.tuck_bin, seen from its middle `wc`) each plate's voxels
## lying on him cover, not a crest's, a brim's or a hat's piece standing out from him: what is tied
## up on his hair under them (a topknot, a bun) goes under the piece (FineHead.tuck), as far as the
## shell is drawn and no further. Plate -> its ways.
static func _cover(wc: Vector3, keys: Array, plate: PackedInt32Array, first: PackedByteArray, xk: PackedByteArray, o: Vector3, sp: Vector3) -> Dictionary:
	var by := {}
	var h := sp * 0.5
	for s in keys.size():
		var ci := plate[s]
		if first[ci] == 0 or xk[s] != 0:
			continue
		if not by.has(ci):
			by[ci] = {}
		var q: Vector3 = o + (Vector3(keys[s]) + Vector3.ONE * 0.5) * sp - wc
		# (Its middle's way and those of points round it short of its corners: never past the
		# shell's own edge, or his scalp showed bare along it.)
		(by[ci] as Dictionary)[FineHead.tuck_bin(q)] = true
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					(by[ci] as Dictionary)[FineHead.tuck_bin(q + Vector3(cx, cy, cz) * h * 0.6)] = true
	var out := {}
	for ci in by:
		out[ci] = PackedInt32Array((by[ci] as Dictionary).keys())
	return out

## The ways out of his head the shell of `ad` covers with the plates still on him, into `bins`.
static func cover(ad: Dictionary, bins: Dictionary) -> void:
	var sh = ad.get("shell")
	if not (sh is Dictionary) or not is_instance_valid(sh.mi):
		return
	var cv: Dictionary = sh.get("cover", {})
	for ci in cv:
		if int(ci) < ad.on.size() and ad.on[int(ci)] == 1:
			for b in (cv[ci] as PackedInt32Array):
				bins[b] = true

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

## Every way a voxel can carry (FineSmooth.decode of 2 + its number), worked out once.
static var _dec := PackedVector3Array()
static func _decoded() -> PackedVector3Array:
	if _dec.is_empty():
		_dec.resize(1024)
		for c in 1024:
			_dec[c] = FineSmooth.decode(2.0 + float(c))
	return _dec

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

## The stuff of a piece lit by its shape (the smooth light; not a hat's, not the classic looks'):
## the shells' own (material), with the shader's ARMOUR_LIGHT set. Under the smooth light a voxel
## is lit as the shell faces there, all of it one way: polished as the cubes were, the few that
## faced the sun were white squares on the piece (user: stray pieces in the armour), so a broader,
## softer sheen (metal_rough); and the light of what is round it taken on its top as on its sides
## (sky_hold: voxel_body.gdshader, env_n).
static var _lit_mat: ShaderMaterial = null
static func lit_material() -> ShaderMaterial:
	if _lit_mat == null:
		_lit_mat = material().duplicate()
		var sh := Shader.new()
		sh.code = (_lit_mat.shader as Shader).code.replace("shader_type spatial;", "shader_type spatial;\n#define ARMOUR_LIGHT")
		_lit_mat.shader = sh
	_lit_mat.set_shader_parameter("ao_strength", VoxelPart.ao_strength * FineHead.AO_K)
	_lit_mat.set_shader_parameter("smooth_shade", FineSmooth.k)
	_lit_mat.set_shader_parameter("metal_rough", LIGHT_ROUGH)
	_lit_mat.set_shader_parameter("sky_hold", LIGHT_SKY)
	return _lit_mat

## The shell of plate `ci` drawn as its tile is drawn now (`xf`: where the tile is, or nothing).
static func sync(ad: Dictionary, ci: int, xf: Transform3D) -> void:
	var sh = ad.get("shell")
	if not (sh is Dictionary) or not is_instance_valid(sh.mi):
		return
	var mm: MultiMesh = sh.mm
	var rel: Array = sh.rel
	(sh.now as Dictionary)[ci] = xf   # (where each plate's tile is drawn now: read back, never off the drawing)
	# (A fine voxel under a raised arm's armour stays hidden: Fighter._clip_shoulder_guards.)
	var vc: PackedByteArray = sh.get("vclip", PackedByteArray())
	for s in (sh.of as Dictionary).get(ci, []):
		var hide := int(s) < vc.size() and vc[int(s)] == 1
		mm.set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO) if hide else xf * (rel[s] as Transform3D))

## Places as a MultiMesh holds them, twelve numbers each (the basis by rows, each with its
## origin after it), for the C++ core.
static func place_rows(places: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	rows.resize(places.size() * 12)
	for s in places.size():
		if not (places[s] is Transform3D):
			continue
		var t: Transform3D = places[s]
		var bx := t.basis
		var o := s * 12
		rows[o] = bx.x.x
		rows[o + 1] = bx.y.x
		rows[o + 2] = bx.z.x
		rows[o + 3] = t.origin.x
		rows[o + 4] = bx.x.y
		rows[o + 5] = bx.y.y
		rows[o + 6] = bx.z.y
		rows[o + 7] = t.origin.y
		rows[o + 8] = bx.x.z
		rows[o + 9] = bx.y.z
		rows[o + 10] = bx.z.z
		rows[o + 11] = t.origin.z
	return rows

## A shell's fine voxels by plate (`of_at`: where each plate's begin in `of`) and their places in
## their plates (`rel`, place_rows), for the C++ core (VoxelCore.lay_plates: a limb in armour
## bent at a break). Made once a shell.
static func bend_pack(sh: Dictionary, plates: int) -> Dictionary:
	var pk = sh.get("bend_pack")
	if pk is Dictionary and int(pk.plates) == plates:
		return pk
	var of: Dictionary = sh.of
	var at := PackedInt32Array([0])
	var flat := PackedInt32Array()
	for ci in plates:
		for s in of.get(ci, []):
			flat.append(int(s))
		at.append(flat.size())
	pk = {"plates": plates, "of_at": at, "of": flat, "rel": place_rows(sh.rel)}
	sh["bend_pack"] = pk
	return pk

## What the shell drew of plate `ci` as it lies now, its voxels in the part's frame, 20 numbers
## each as a MultiMesh holds them: a plate knocked off flies off as these (Fighter._knock_plate),
## the very plate, in the shape it lay on him (user: every piece that falls from a character is a
## piece that is literally his).
static func taken(ad: Dictionary, ci: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var sh = ad.get("shell")
	if not (sh is Dictionary) or not is_instance_valid(sh.mi):
		return out
	var at = (sh.now as Dictionary).get(ci)
	if not (at is Transform3D) or (at as Transform3D).basis.x.length_squared() < 1e-10:
		return out
	var mm: MultiMesh = sh.mm
	var rel: Array = sh.rel
	for s in (sh.of as Dictionary).get(ci, []):
		# (Each lit as the cube it is, not as the shell faced there: a plate tumbles and lies any
		# way up, and its voxels' other sides were lit as the one that faced out of him.)
		var col := mm.get_instance_color(int(s))
		col.a = FineSmooth.NONE
		FineBody.put_cell(out, (at as Transform3D) * (rel[int(s)] as Transform3D), col, mm.get_instance_custom_data(int(s)))
	return out

## What a voxel of a shell is drawn with.
static func cell_mesh() -> Mesh:
	return _unit

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

## A shell worked out a little a frame (build `staged`): this frame's share spent (pace_us, in
## microseconds; a test sets none, a frame's wait at every turn), a frame's wait; and whether it
## goes on, the part still there and drawn as it was (`pace.fine`).
static var pace_us := 4000
static func _pace(p, pace: Dictionary) -> bool:
	if Time.get_ticks_usec() - int(pace.t) < pace_us:
		return true
	if not await Physique._frame(p) or not _still(p, pace):
		return false
	pace.t = Time.get_ticks_usec()
	return true

static func _still(p, pace: Dictionary) -> bool:
	return is_instance_valid(p) and (p as Node).is_inside_tree() and is_same(p.fine, pace.get("fine"))

# ---------- The ground the shell lies on ----------

static func _key(p: VoxelPart) -> String:
	if p.fine.has("wtab"):
		# (And his hair: a helmet is laid over his head as his hair shapes it, sitting on his hair.)
		var look: Dictionary = p.fine.get("look", {})
		var hair := "%s%s" % [String(look.get("style", "")), "-" if (look.get("ids", []) as Array).has("hair_receding") else ""]
		return "h|%s|%s|%s|%.5f|%s" % [String(p.fine.get("giant", "")), str(p.grid), str(snappedf(float(p.fine.get("hs", 1.0)), 0.0001)), p.vf * p.part_scale, hair]
	return "b|%s|%s|%.5f" % [String(p.fine.get("build", "")), String(p.part_name), p.vf * p.part_scale]

## The fine voxels just outside him there, THICK deep, on the lattice he is drawn on:
## {o, sp (the lattice: a voxel's middle at o + (i + 0.5) * sp), pts (their middles), idx (their i)};
## `k` over 1, the voxels that many times bigger (_coarse). `pace`: a little a frame (_layout).
static func _ground(p: VoxelPart, k := 1.0, pace := {}) -> Dictionary:
	var key := _key(p) + ("|%.2f" % k)
	if _bands.has(key):
		var kept: Dictionary = _bands[key]
		_bands.erase(key)   # (the last used kept the longest)
		_bands[key] = kept
		return kept
	var thick := THICK if k <= 1.0 else COARSE_THICK
	var out: Dictionary
	if p.fine.has("wtab"):
		out = await _ground_head(p, thick, pace)
	else:
		out = await _ground_body(p, thick, pace)
	if k > 1.0 and not out.is_empty():
		out = await _coarse(out, k, p, pace)
	if pace.has("t") and not _still(p, pace):
		return {}   # (he is gone, or drawn anew while it was worked out: not his, nothing kept)
	if _bands.size() >= BAND_KEEP:
		_bands.erase(_bands.keys()[0])
	_bands[key] = out
	return out

## The fine shell `g` on a lattice `k` times as big: each of its voxels kept where its middle lies in
## one of the fine shell's (not every one a fine voxel only touches: kept, the shell stood a voxel
## off him, bulky, its edges ragged). The line down his middle (x = 0) between two of its voxels,
## as the fine lattice's: the same on his left as on his right.
static func _coarse(g: Dictionary, k: float, p = null, pace := {}) -> Dictionary:
	var o: Vector3 = g.o
	var sp: Vector3 = g.sp
	var cs := sp * k
	var oc := Vector3(-ceilf(-o.x / cs.x - 0.0001) * cs.x, o.y, o.z)
	var fi: PackedInt32Array = g.idx
	var seen := {}
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	var staged := pace.has("t")
	for s in fi.size() / 3:
		if staged and (s & 1023) == 1023 and not await _pace(p, pace):
			return {}
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
	var out := {"o": oc, "sp": cs, "pts": pts, "idx": idx, "within": seen, "k": k}
	for kept in ["skin", "outline"]:
		if g.has(kept):
			out[kept] = g[kept]
	return out

## Round the fine head, seen from its middle: the farthest of its fine voxels each way (finer than
## FineHead's own outline, smoothed), the shell from there out.
const H_AZ := 96
const H_EL := 48
static func _ground_head(p: VoxelPart, thick := THICK, pace := {}) -> Dictionary:
	var fine := p.fine
	var cxf: Array = fine.xf
	if cxf.is_empty():
		return {}
	var staged := pace.has("t")
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
	# (His head as his hair shapes it, the piece on his hair: not on a knot or a bun tied up on it,
	# which goes under the piece instead, FineHead.tuck; a helmet stood up over a topknot.)
	var cells: Array = fine.get("cells", [])
	for s in cxf.size():
		if staged and (s & 1023) == 1023 and not await _pace(p, pace):
			return {}
		if s < cells.size() and FineHead.extra_hair(cells[s]):
			continue
		var v: Vector3 = (cxf[s] as Transform3D).origin - c
		var r := v.length()
		if r < 0.0001:
			continue
		var k := _hbin(v / r)
		tab[k] = maxf(tab[k], r + cell * 0.5)
	for pass_ in 12:
		if staged and not await _pace(p, pace):
			return {}
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
		if staged and (el & 7) == 7 and not await _pace(p, pace):
			return {}
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
		if staged and not await _pace(p, pace):
			return {}
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
static func _ground_body(p: VoxelPart, thick := THICK, pace := {}) -> Dictionary:
	var d: Dictionary = p.fine.get("d", {})
	if d.is_empty():
		return {}
	var staged := pace.has("t")
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
	# (And his skin's fine voxels themselves as a grid of the fine lattice, 1 where one lies: _skin_in.)
	var fdim := p.grid * 2 + Vector3i.ONE * margin * 2
	var occ := PackedByteArray()
	occ.resize(fdim.x * fdim.y * fdim.z)
	for s in n:
		if staged and (s & 1023) == 1023 and not await _pace(p, pace):
			return {}
		var ix := cells[s * FineBody.CELL]
		var iy := cells[s * FineBody.CELL + 1]
		var iz := cells[s * FineBody.CELL + 2]
		var fx := ix + margin
		var fz := iz + margin
		if fx >= 0 and fx < fdim.x and iy + margin >= 0 and iy + margin < fdim.y and fz >= 0 and fz < fdim.z:
			occ[(fx * fdim.y + iy + margin) * fdim.z + fz] = 1
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
		if staged and (r & 7) == 7 and not await _pace(p, pace):
			return {}
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
		if staged and not await _pace(p, pace):
			return {}
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
		if staged and (s & 1023) == 1023 and not await _pace(p, pace):
			return {}
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
	return {"o": o, "sp": sp, "pts": pts, "idx": idx, "within": seen, "skin": {"occ": occ, "dim": fdim, "o": o, "fsz": fsz},
		"outline": {"tab": tab, "rows": rows, "margin": margin, "fsz": fsz, "h": h, "thick": T}}

## The outline of a part of his body under its armour (_ground_body: how far out of his middle
## he reaches, row by row and way by way round him), as the shell over him was laid out: empty
## where none was laid on it yet. For in_outline.
static func outline(p: VoxelPart) -> Dictionary:
	for k in [COARSE, 1.0]:
		var g = _bands.get(_key(p) + ("|%.2f" % k))
		if g is Dictionary and (g as Dictionary).has("outline"):
			return g.outline
	return {}

## Whether point `q` (the part's frame) lies within his outline there (`ol`: outline), the shell
## laid over it and `pad` more taken in: under his armour, not out past it.
static func in_outline(ol: Dictionary, q: Vector3, pad: float) -> bool:
	var fsz: float = ol.fsz
	var h: Vector3 = ol.h
	var rows: int = ol.rows
	var fr := (q.y + h.y) / fsz - 0.5 + float(int(ol.margin))
	if fr < 0.0 or fr > float(rows - 1):
		return false
	var r0 := int(floorf(fr))
	var r1 := mini(r0 + 1, rows - 1)
	var wr := fr - float(r0)
	var fa := (atan2(q.z, q.x) + PI) / TAU * float(B_ANG) - 0.5
	var a0 := posmod(int(floorf(fa)), B_ANG)
	var a1 := (a0 + 1) % B_ANG
	var wa := fa - floorf(fa)
	var tab: PackedFloat32Array = ol.tab
	var e0 := tab[r0 * B_ANG + a0] * (1.0 - wa) + tab[r0 * B_ANG + a1] * wa
	var e1 := tab[r1 * B_ANG + a0] * (1.0 - wa) + tab[r1 * B_ANG + a1] * wa
	# (A row with none of him in it reaches nowhere: no shell is laid there.)
	if e0 <= 0.0 or e1 <= 0.0:
		return false
	return Vector2(q.x, q.z).length() < e0 * (1.0 - wr) + e1 * wr + float(ol.thick) + pad

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
static func _shade(col: Color, metal: bool, rim: bool, hair: bool, kc: Vector3i, dark: float, bands := {}) -> Color:
	if hair:
		# Hair in strands: lighter and darker voxel to voxel down its fall, its edge in shadow.
		var hk := 0.86 + 0.26 * _hash(kc) * (0.7 + 0.3 * _hash(Vector3i(kc.x, 0, kc.z)))
		return _lit(col, hk * (0.82 if rim else 1.0))
	if bands.is_empty():
		# One moulded piece: a hair's difference from voxel to voxel.
		var k := 0.985 + 0.03 * _hash(kc)
		if rim:
			k = 1.16 if metal else 0.8
		return _lit(col, k * dark)
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
	# (The row and its height at this voxel's height on him: read once a height.)
	var at_y: Dictionary = bands.at_y
	if not at_y.has(kc.y):
		at_y[kc.y] = PackedFloat64Array([_row_at(q.y, bands), _row_h(q.y, bands)])
	var ry: PackedFloat64Array = at_y[kc.y]
	var row := ry[0]
	var k := 1.0
	var f1 := fposmod(row + 0.5, 1.0)   # (0 at a hoop's lower edge, 1 at its top)
	# (A line a voxel wide at the least, or on big voxels a hoop's groove, a rivet, came and went
	# hoop to hoop as its voxels' middles fell.)
	var rh := ry[1]
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
		"hb": Vector3(p.grid) * p.vf * p.part_scale * 0.5, "at_y": {}}

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
const BAND := 5
const RIVET := 6
const KNOB := 7
const BRASS := Color(0.8, 0.6, 0.3)

## How a piece is drawn on the new look, as the arena saw it in its day (only the look: its plates,
## what they stop and weigh are the piece's own), every helmet with his eyes left open (user: what
## bothered him in the helmets was that they covered his eyes): the galea a bowl of bronze with a
## peak at the brow, a guard flaring over the nape and a crest with a plume of dyed horsehair, his
## face open between its cheeks; the gold one a thraex's parade helm, its broad brim above his
## brows, its crest hooked forward as a griffin's head, a white plume; the murmillo's helm its broad
## brim, a tall crest and a visor grilled over the face, round holes at his eyes; the secutor's (the
## smooth egg the net cannot catch) round holes at his eyes and a low fin; a leather cap or an iron
## skull plate on the crown above his brows; a lorica and a manica in iron bands; greaves one
## moulded piece, the knee raised; a gold lorica moulded smooth. A piece made at the bench: smooth
## on the head and the shins, in bands on the trunk and the arms.
static func _style(id: String, p: VoxelPart) -> Dictionary:
	if id.begins_with("hair_") or id.begins_with("hat_"):
		match id:
			"hat_straw":
				return {"seams": false, "brim": true, "brim_w": 4.5}
			"hat_bucket":
				return {"seams": false, "face": "eyes", "eye_r": 2.4, "closed": true, "crest": true, "crest_h": 1.5}
			"hair_curly", "hair_curls_top":
				return {"seams": false, "curls": true}
		return {"seams": false}
	match id:
		"helmet":
			return {"seams": false, "crest": true, "plume": Color(0.62, 0.07, 0.05), "brim": true, "brim_w": 1.0, "brim_arc": 0.45, "neck": 2.5, "face": "open"}
		"goldHelmet":
			return {"seams": false, "crest": true, "crest_h": 1.5, "plume_h": 1.5, "griffin": true, "brim": true, "brim_w": 2.5, "plume": Color(0.93, 0.9, 0.84), "face": "open"}
		"murmilloHelm":
			return {"seams": false, "crest": true, "crest_h": 3.0, "brim": true, "brim_w": 2.5, "brim_at": "brow", "face": "visor"}
		"skullPlate":
			return {"seams": false, "face": "open", "cap": true, "dark": 0.8, "down_to_brow": 2.0}
		"leatherCap":
			return {"seams": false, "face": "open"}
		"ironJaw", "goldLorica", "cape_short":
			return {"seams": false}
		"lorica", "manica":
			return {"seams": true}
		"greaves":
			return {"seams": false, "boss": true}
	var pn := String(p.part_name)
	if pn == "head" or pn.begins_with("shin"):
		return {"seams": false}
	return {"seams": true}

## An iron cap as a smith rivets one over the skull: round its edge a band standing a voxel off
## the bowl with brass rivets in it all the way round, the same on his left as on his right, and a
## brass knob on the crown. (Its smooth bowl alone, all of a grey, read as a woollen cap or as grey
## curls: user, it looked bad and silly.)
static func _iron_cap(wc: Vector3, owner: Dictionary, extra: Dictionary, o: Vector3, sp: Vector3, within: Dictionary) -> void:
	var cell := sp.x
	var add := {}
	var fx := (wc.x - o.x) / sp.x - 0.5
	var cols := []
	for ix in [int(floorf(fx)), int(ceilf(fx))]:
		if absf(float(ix) - fx) < 0.75 and not cols.has(ix):
			cols.append(ix)
	var fz := (wc.z - o.z) / sp.z - 0.5
	var step := TAU / 14.0
	for kc in owner:
		if extra.has(kc):
			continue
		var q := _mid(kc, o, sp)
		var d := q - wc
		if d.length() < 0.0001:
			continue
		var out := _at(q + d.normalized() * cell, o, sp)
		if owner.has(out) or add.has(out):
			continue   # (from the bowl's outside)
		var edge := false
		for dv in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if owner.get(kc + dv) == null and within.has(kc + dv):
				edge = true
		if edge:
			var a := absf(atan2(d.x, d.z))   # (0 in front, PI behind: the same either side)
			add[out] = [owner[kc], RIVET if fposmod(a + step * 0.5, step) < step * 0.3 else BAND]
	# The knob on the crown: over the bowl's top in the middle.
	var top := Vector3i.ZERO
	var best := -INF
	for kc in owner:
		if cols.has(kc.x) and not extra.has(kc) and absf(float(kc.z) - fz) < 1.0 and kc.y > best:
			best = kc.y
			top = kc
	if best > -INF:
		for kk in [top + Vector3i(0, 1, 0), top + Vector3i(0, 2, 0)]:
			add[kk] = [owner[top], KNOB]
	for kk in add:
		if not owner.has(kk):
			owner[kk] = add[kk][0]
			extra[kk] = add[kk][1]

## A cap brought down all round his head to a level line `gap` of its voxels over his brows (over
## his ears at the sides), where its own plates stop higher: each voxel of the ground over that line
## the nearest plate's (the iron cap sat back on his crown, his whole forehead bare: user, it
## should take in more of his head). Only its drawing: what the plates stop is theirs.
static func _down_to_brow(p: VoxelPart, owner: Dictionary, ground: Dictionary, org: PackedVector3Array, first: PackedByteArray, sp: Vector3, gap: float) -> void:
	var lo := float(p.fine.brow_y) + sp.y * gap
	var pts: PackedVector3Array = ground.pts
	var idx: PackedInt32Array = ground.idx
	for s in pts.size():
		var kc := Vector3i(idx[s * 3], idx[s * 3 + 1], idx[s * 3 + 2])
		if owner.has(kc):
			continue
		var q := pts[s]
		if q.y < lo:
			continue
		var best := INF
		var who := -1
		for ci in org.size():
			if first[ci] == 1:
				var dd := q.distance_squared_to(org[ci])
				if dd < best:
					best = dd
					who = ci
		if who >= 0:
			owner[kc] = who

## A fine voxel's place on the shell's lattice, and the middle of one.
static func _at(q: Vector3, o: Vector3, sp: Vector3) -> Vector3i:
	return Vector3i(((q - o) / sp).floor())

static func _mid(kc: Vector3i, o: Vector3, sp: Vector3) -> Vector3:
	return o + (Vector3(kc) + Vector3.ONE * 0.5) * sp

## A crest along the top of a helmet, from the brow to the nape, on the head's middle (one row of
## voxels, or the two either side of the middle: as wide each side), standing `high` voxels off the
## bowl, and on it the plume, `plume` more: each the plate's under it. `hook`: its front end
## curled forward and down over the brow, a thraex's griffin's head.
static func _crest(wc: Vector3, owner: Dictionary, extra: Dictionary, o: Vector3, sp: Vector3, high := 1.0, plume := 2.0, hook := false) -> void:
	var cell := sp.x
	var fx := (wc.x - o.x) / sp.x - 0.5
	var cols := []
	for ix in [int(floorf(fx)), int(ceilf(fx))]:
		if absf(float(ix) - fx) < 0.75 and not cols.has(ix):
			cols.append(ix)
	var add := {}
	var front := -INF
	var tip := Vector3.ZERO
	var tip_k := Vector3i.ZERO
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
		while t <= cell * (high + plume):
			var kk := _at(q + dir * t, o, sp)
			kk.x = kc.x
			if not owner.has(kk) and not add.has(kk):
				add[kk] = [owner[kc], CREST if t <= cell * high else PLUME]
			t += cell * 0.5
		if d.z > front:
			front = d.z
			tip = q + dir * cell * high
			tip_k = kc
	if hook and front > -INF:
		# Forward off the crest's front end and curled a little down: the beak (well above his brow:
		# hung lower it shaded his face), drawn whole, half a voxel at a time along it (laid in steps,
		# its tip hung on its own in the air in front of him).
		var fwd := Vector3(0.0, 0.0, 1.0)
		var bend := tip + fwd * cell * 1.8
		var end := tip + (fwd + Vector3.DOWN * 0.6).normalized() * cell * 2.4
		for seg in [[tip, bend], [bend, end]]:
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			var n := maxi(1, ceili(a.distance_to(b) / (cell * 0.5)))
			for i in range(1, n + 1):
				var kk := _at(a.lerp(b, float(i) / float(n)), o, sp)
				for ix in cols:
					kk.x = ix
					if not owner.has(kk) and not add.has(kk):
						add[kk] = [owner[tip_k], CREST]
	for kk in add:
		owner[kk] = add[kk][0]
		extra[kk] = add[kk][1]

## A brim round the helmet, `wide` voxels, out from the bowl all round: at the brow (where the bowl
## ends over his face), or at the height `at_y` (a visor's helm: over his eyes). `arc`: only as far
## round as faces that much forward (-1 all round; a galea's peak, the front only): each the plate's
## it stands out from.
static func _brim(wc: Vector3, owner: Dictionary, extra: Dictionary, o: Vector3, sp: Vector3, wide := 2.0, at_y := INF, arc := -2.0) -> void:
	var cell := sp.x
	var row := 1 << 30
	if at_y < INF:
		row = int(floorf((at_y - o.y) / sp.y))
	else:
		for kc in owner:
			var d := _mid(kc, o, sp) - wc
			if d.z > 0.75 * d.length():
				row = mini(row, kc.y)   # (the bowl's lowest over his face: the brow)
	if row == 1 << 30:
		return
	var add := {}
	for kc in owner:
		if kc.y != row or extra.has(kc):
			continue   # (out of the bowl itself: not off a crest's hook come down to the brow)
		var q := _mid(kc, o, sp)
		var h := Vector3(q.x - wc.x, 0.0, q.z - wc.z)
		if h.length() < 0.0001:
			continue
		var dir := h.normalized()
		if dir.z < arc:
			continue
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

## A galea's guard over the nape: from the bowl's lowest row at the back, `wide` voxels out and
## sloping down, flared round the back of the neck.
static func _neck(wc: Vector3, owner: Dictionary, extra: Dictionary, o: Vector3, sp: Vector3, wide := 2.5) -> void:
	var cell := sp.x
	var row := 1 << 30
	for kc in owner:
		var d := _mid(kc, o, sp) - wc
		if d.z < -0.6 * d.length():
			row = mini(row, kc.y)   # (the bowl's lowest at the back: over the nape)
	if row == 1 << 30:
		return
	var add := {}
	for kc in owner:
		if kc.y > row + 1:
			continue
		var q := _mid(kc, o, sp)
		var h := Vector3(q.x - wc.x, 0.0, q.z - wc.z)
		if h.length() < 0.0001:
			continue
		var dir := h.normalized()
		if dir.z > -0.35:
			continue   # (round the back only: his cheeks are open)
		if owner.has(_at(q + dir * cell, o, sp)):
			continue
		var way := (dir + Vector3.DOWN * 0.45).normalized()
		var t := cell * 0.5
		while t <= cell * wide:
			var kk := _at(q + way * t, o, sp)
			if not owner.has(kk) and not add.has(kk):
				add[kk] = owner[kc]
			t += cell * 0.5
	for kk in add:
		owner[kk] = add[kk]
		extra[kk] = BRIM

## His eyes left open in a helmet's shell (the head's eyes and brows: FineHead.build). "open": the
## shell no lower over his face than his brows, between his cheeks (the cheek guards and the sides
## as they are); "eyes": a round hole at each eye (a secutor's, the visor's); "visor": those, and a
## grille over the rest of his face under them (square holes between bars a voxel wide). Only how
## it is drawn: the plates stop what they stopped.
static func _open_face(p: VoxelPart, owner: Dictionary, o: Vector3, sp: Vector3, how: String, eye_r := 1.3) -> void:
	var fine: Dictionary = p.fine
	var wc: Vector3 = fine.wc
	var cell := sp.x
	var el: AABB = fine.eyes[0]
	var er: AABB = fine.eyes[1]
	var brow: float = fine.brow_y
	var half_w := 0.0
	for e: AABB in [el, er]:
		half_w = maxf(half_w, maxf(absf(e.position.x - wc.x), absf(e.end.x - wc.x)))
	var cut := {}
	for kc in owner:
		var q := _mid(kc, o, sp)
		var d := q - wc
		if d.z <= 0.0 or d.z < 0.3 * d.length():
			continue   # (his face only: the back and the sides of his head stay)
		if how == "open":
			if q.y < brow + cell * 0.6 and absf(q.x - wc.x) < half_w + cell * 1.6:
				cut[kc] = true
			continue
		var hole := false
		for e: AABB in [el, er]:
			var c3 := e.get_center()
			var r := maxf(e.size.x, e.size.y) * 0.5 + cell * eye_r
			if Vector2(q.x - c3.x, (q.y - c3.y) * 1.3).length() < r:
				hole = true
		if hole:
			cut[kc] = true
		elif how == "visor" and q.y < brow - cell * 0.5 and d.z > 0.55 * d.length() and posmod(kc.x, 3) != 0 and posmod(kc.y, 3) != 0:
			cut[kc] = true
	for kc in cut:
		owner.erase(kc)

## Pinholes in a shell round a head: a cell of its ground left out with the shell drawn round it on
## four faces of the six or more, filled, each the plate most of those round it are (user: holes
## in the helmets). Its edge, drawn on fewer sides, stays where it is.
static func _fill_pinholes(owner: Dictionary, within: Dictionary) -> void:
	for pass_ in 2:
		var add := {}
		for kc in within:
			if owner.has(kc):
				continue
			var n := 0
			var votes := {}
			for dv in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var w = owner.get(kc + dv)
				if w != null:
					n += 1
					votes[w] = int(votes.get(w, 0)) + 1
			if n < 4:
				continue
			var best = null
			for w in votes:
				if best == null or int(votes[w]) > int(votes[best]):
					best = w
			add[kc] = best
		if add.is_empty():
			return
		owner.merge(add)

## The edge of a piece on his trunk round an arm that hangs through it (user: stray voxels in the
## armour, teeth hanging under a shoulder guard's edge). What of the piece lies in the arm is not
## drawn while the arm is there (Fighter._limbs_in_armor: the arm as a round cone, the same one
## here, as he stands). What that leaves of a row the arm takes most of, a few voxels side by side
## hanging under the guard's edge with none of the piece drawn under them, is left out of the
## piece, row by row up to the first that runs on round the arm: its edge there is whole rows.
## Never the last of a plate's voxels, nor what stands out of the piece on purpose (`extra`).
const RIM_NEAR := 3.0   # how far from the arm (the piece's voxels) its edge is looked at
const RIM_RUN := 8      # fewer voxels than this side by side in a row, with none under them, hang
static func _rim_round_limbs(owner: Dictionary, extra: Dictionary, cones: Array, o: Vector3, sp: Vector3) -> void:
	if cones.is_empty() or owner.is_empty():
		return
	# (Only what lies in the box round the arms is measured against them.)
	var reach := sp.x * RIM_NEAR
	var box := AABB()
	var ca := PackedVector3Array()
	var cab := PackedVector3Array()
	var cinv := PackedFloat32Array()
	for k in cones.size():
		for e in 2:
			var r := float(cones[k][2 + e]) + reach
			var b := AABB((cones[k][e] as Vector3) - Vector3.ONE * r, Vector3.ONE * r * 2.0)
			box = b if k == 0 and e == 0 else box.merge(b)
		ca.append(cones[k][0])
		cab.append((cones[k][1] as Vector3) - (cones[k][0] as Vector3))
		cinv.append(1.0 / maxf(cab[k].length_squared(), 1e-8))
	# The piece on a grid of numbers: 1 a voxel of it that is drawn, 2 one in an arm (not drawn
	# while the arm is there), and 4 more on one near an arm. (Asked of the dictionary of places
	# voxel by voxel, a cuirass's rim was a fiftieth of a second and more.)
	var lo: Vector3i = owner.keys()[0]
	var hi := lo
	for kc: Vector3i in owner:
		lo = lo.min(kc)
		hi = hi.max(kc)
	lo -= Vector3i.ONE * 2
	hi += Vector3i.ONE * 2
	var dy := hi.y - lo.y + 1
	var dz := hi.z - lo.z + 1
	var sx := dy * dz
	var gr := PackedByteArray()
	gr.resize((hi.x - lo.x + 1) * sx)
	var seeds := PackedInt32Array()
	for kc: Vector3i in owner:
		var q := o + (Vector3(kc) + Vector3.ONE * 0.5) * sp
		var v := 1
		if box.has_point(q):
			var d := INF
			for k in ca.size():
				var t := clampf((q - ca[k]).dot(cab[k]) * cinv[k], 0.0, 1.0)
				d = minf(d, q.distance_to(ca[k] + cab[k] * t) - lerpf(float(cones[k][2]), float(cones[k][3]), t))
			if d < 0.0:
				v = 2
			elif d < reach:
				v = 5
		var at := ((kc.x - lo.x) * dy + (kc.y - lo.y)) * dz + (kc.z - lo.z)
		gr[at] = v
		if v == 5:
			seeds.append(at)
	if seeds.is_empty():
		return
	var o8 := PackedInt32Array([sx, -sx, 1, -1, sx + 1, sx - 1, -sx + 1, -sx - 1])   # round a place in its row
	var seen := PackedByteArray()
	seen.resize(gr.size())
	var left := {}   # plate -> how many voxels it has
	for pass_ in 6:
		var drop := PackedInt32Array()
		var marked := PackedInt32Array()
		for at0 in seeds:
			if seen[at0] != 0 or gr[at0] != 5:
				continue
			# (The voxels drawn side by side with it in its row, as far as RIM_RUN of them.)
			var run := PackedInt32Array([at0])
			seen[at0] = 1
			marked.append(at0)
			var i := 0
			while i < run.size() and run.size() < RIM_RUN:
				var c := run[i]
				i += 1
				for d in o8:
					var nb := c + d
					if (gr[nb] & 3) == 1 and not run.has(nb):
						run.append(nb)
						seen[nb] = 1
						marked.append(nb)
			if run.size() >= RIM_RUN:
				continue
			var held := false
			for c in run:
				if (gr[c - dz] & 3) == 1 or (gr[c] & 4) == 0:
					held = true
					break
			if not held:
				if left.is_empty():
					for kc in owner:
						left[owner[kc]] = int(left.get(owner[kc], 0)) + 1
				for c in run:
					var kc := lo + Vector3i(c / sx, (c / dz) % dy, c % dz)
					if extra.has(kc) or int(left[owner[kc]]) <= 1:
						held = true
						break
			if not held:
				drop.append_array(run)
		if drop.is_empty():
			break
		for c in marked:
			seen[c] = 0
		# (A row left out bares the one over it: only what stood on these is looked at again.)
		seeds = PackedInt32Array()
		for c in drop:
			if gr[c] == 0:
				continue
			var kc := lo + Vector3i(c / sx, (c / dz) % dy, c % dz)
			left[owner[kc]] = int(left[owner[kc]]) - 1
			owner.erase(kc)
			gr[c] = 0
			if gr[c + dz] == 5:
				seeds.append(c + dz)

## The arms that hang beside trunk `p`, each as a round cone as he stands, in the trunk's frame:
## [its upper end's middle, its lower end's, how far out it reaches round each] (Fighter.
## _limb_cone). None: not a trunk, or no arms.
static var _arm_cones := {}   # a build's arm at a size -> its cone (Fighter.limb_cone)
static func rest_cones(p: VoxelPart) -> Array:
	var out := []
	var who = p.fighter
	if who == null or not (who is Fighter) or String(p.part_name) != "torso" or not p.fine.has("body"):
		return out
	# (From the build's own drawing of his arms, not from the arms as they are drawn now: his
	# trunk's armour may be laid before his arms are drawn.)
	var bn := String(p.fine.get("build", ""))
	for q: VoxelPart in (who as Fighter).parts:
		if q.parent_part != p or not String(q.part_name).begins_with("upperArm"):
			continue
		var key := "%s|%s|%.5f|%s" % [bn, q.part_name, q.vf * q.part_scale, str(q.grid)]
		if not _arm_cones.has(key):
			var qd := FineBody.part_data(bn, String(q.part_name))
			_arm_cones[key] = {} if qd.is_empty() else Fighter.limb_cone(qd.cells, -Vector3(q.grid) * q.vf * q.part_scale * 0.5, q.vf * q.part_scale / float(Data.body_res))
		var c: Dictionary = _arm_cones[key]
		if c.is_empty():
			continue
		var off: Vector3 = q.pa - q.ca
		out.append([off + Vector3(0.0, float(c.top), 0.0), off + Vector3(0.0, float(c.end), 0.0), float(c.r_top), float(c.r_end)])
	return out

## How far outside the nearest of `cones` point `q` lies (under 0: inside one), as the shader
## reads them (voxel_body.gdshader, in_limb).
static func cone_gap(cones: Array, q: Vector3) -> float:
	var best := INF
	for c in cones:
		var a: Vector3 = c[0]
		var ab: Vector3 = (c[1] as Vector3) - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t) - lerpf(float(c[2]), float(c[3]), t))
	return best

## A piece on his body drawn whole and clean (user: no stray voxels in the armour that belong to
## nothing; its edges were ragged, a voxel hanging under them here and there, and a voxel or two
## lay apart from it on his skin). A gap in it is shut where the piece is drawn most of the way
## round it: a pinhole his skin showed through, a notch in its edge; and a pit in it that his own
## flesh comes out through (`skin`: the places his flesh lies in, a dictionary of them or a test
## of one; the ledge of a chest's muscle between two of a cuirass's rows, the piece on three sides
## of it or more: an orange hole under the collar). A voxel with little of the piece round it, a
## tooth on its edge, is left out, unless all its plate's are such (a strip one plate wide stays
## whole). And what lies apart from the piece, a voxel or two past its edge, is left out where
## its plates are drawn in the piece itself. Never the last of a plate's voxels (every plate is
## drawn), nor what stands out of the piece on purpose (`extra`: a boss, a rivet).
## (On a grid of numbers of its own, a place's plate + 1: its 26 neighbours are 26 numbers off
## it. Asked of the dictionary of places one by one, a cuirass was a fifth of a second.)
const STRAY := 6      # the most voxels lying apart that are left out
const TOOTH := 4      # a voxel with no more of the piece round it than this (of 26) is a tooth on its edge
const NOTCH := 5      # a gap with this many of the piece round it (of 26), two of them face to face with it, is shut
const SEEN := 6       # how far straight out of a pit nothing of the piece or of him lies, for his flesh in it to show
const TIDY_PAD := SEEN + 2   # the grid's margin round the piece (a place as far out of it as a pit's flesh is looked for is looked at, and what lies round it read)
static func _tidy(owner: Dictionary, extra: Dictionary, within: Dictionary, skin = null, pace := {}, p = null) -> void:
	if owner.is_empty():
		return
	var lo: Vector3i = owner.keys()[0]
	var hi := lo
	for kc: Vector3i in owner:
		lo = lo.min(kc)
		hi = hi.max(kc)
	lo -= Vector3i.ONE * TIDY_PAD
	hi += Vector3i.ONE * TIDY_PAD
	var dy := hi.y - lo.y + 1
	var dz := hi.z - lo.z + 1
	var sx := dy * dz
	var g := PackedInt32Array()
	g.resize((hi.x - lo.x + 1) * sx)
	for kc: Vector3i in owner:
		g[((kc.x - lo.x) * dy + (kc.y - lo.y)) * dz + (kc.z - lo.z)] = int(owner[kc]) + 1
	var o6 := PackedInt32Array([sx, -sx, dz, -dz, 1, -1])
	var d6 := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var o26 := PackedInt32Array()
	for ax in [-1, 0, 1]:
		for ay in [-1, 0, 1]:
			for az in [-1, 0, 1]:
				if ax != 0 or ay != 0 or az != 0:
					o26.append(ax * sx + ay * dz + az)
	var paced := not pace.is_empty()
	# Each voxel as it was last counted: a tooth (1) or sound (2). The first pass looks at all of
	# the piece; each pass after it only where the one before changed it (all of it again, pass
	# after pass, was three quarters of the work).
	var state := PackedByteArray()
	state.resize(g.size())
	var flag := PackedByteArray()   # (a place already listed in this pass)
	flag.resize(g.size())
	var few := {}       # its voxels with fewer than STRAY of it round them
	var sound := {}     # plate (+ 1) -> how many of its voxels are not teeth
	var teeth := {}     # plate (+ 1) -> its voxels that are
	var shut_before := PackedInt32Array()    # the gaps shut in the pass before
	var off_before := PackedInt32Array()     # the teeth taken off in it
	for pass_ in 4:
		var changed := false
		var n := 0
		var shut := PackedInt32Array()
		if pass_ < 3:
			# Its gaps shut: the places with none of it that two of its voxels or more lie face to face with.
			var cands := PackedInt32Array()
			if pass_ == 0:
				var faces := PackedByteArray()
				faces.resize(g.size())
				for kc: Vector3i in owner:
					var at := ((kc.x - lo.x) * dy + (kc.y - lo.y)) * dz + (kc.z - lo.z)
					for d in o6:
						var j := at + d
						if g[j] == 0:
							faces[j] += 1
							if faces[j] == 2:
								cands.append(j)
					n += 1
					if paced and (n & 255) == 0 and not await _pace(p, pace):
						return
			else:
				# (Round a gap shut and a tooth taken off; and straight out from the tooth as far as
				# a pit's flesh is looked for, _bare: it stood in the way.)
				for at in shut_before:
					for d in o26:
						var j := at + d
						if g[j] == 0 and flag[j] == 0:
							flag[j] = 1
							cands.append(j)
				for at in off_before:
					if g[at] == 0 and flag[at] == 0:
						flag[at] = 1
						cands.append(at)
					for d in o26:
						var j := at + d
						if g[j] == 0 and flag[j] == 0:
							flag[j] = 1
							cands.append(j)
					if skin != null:
						for d in o6:
							for t in range(2, SEEN + 1):
								var j := at + d * t
								if g[j] == 0 and flag[j] == 0:
									flag[j] = 1
									cands.append(j)
				for j in cands:
					flag[j] = 0
			var add := []
			for at in cands:
				n += 1
				if paced and (n & 127) == 0 and not await _pace(p, pace):
					return
				var by_face := 0
				for d in o6:
					if g[at + d] != 0:
						by_face += 1
				if by_face < 2:
					continue
				var round_ := 0
				for d in o26:
					if g[at + d] != 0:
						round_ += 1
						if round_ >= NOTCH:
							break
				if round_ < NOTCH:
					continue
				var kc := lo + Vector3i(at / sx, (at / dz) % dy, at % dz)
				if not within.has(kc) and (by_face < 3 or skin == null or not _in(skin, kc) or not _bare(g, at, o6, d6, skin, kc)):
					continue
				# (The plate most of its neighbours face to face are.)
				var best := 0
				var most := 0
				for d in o6:
					var w := g[at + d]
					if w == 0:
						continue
					var c := 0
					for e in o6:
						if g[at + e] == w:
							c += 1
					if c > most:
						most = c
						best = w
				add.append([at, kc, best])
			for e in add:
				g[int(e[0])] = int(e[2])
				owner[e[1]] = int(e[2]) - 1
				shut.append(int(e[0]))
				changed = true
		# Its teeth off (not after the last pass: only counted then). Counted: all of it the first
		# time, then those with a gap shut or a tooth taken off beside them.
		var again := PackedInt32Array()
		if pass_ == 0:
			for kc: Vector3i in owner:
				again.append(((kc.x - lo.x) * dy + (kc.y - lo.y)) * dz + (kc.z - lo.z))
		else:
			for at in shut:
				if flag[at] == 0:
					flag[at] = 1
					again.append(at)
			for at in shut + off_before:
				for d in o26:
					var j := at + d
					if g[j] != 0 and flag[j] == 0:
						flag[j] = 1
						again.append(j)
			for j in again:
				flag[j] = 0
		var touched := {}   # the plates with a voxel that is now a tooth, or now is not
		for at in again:
			n += 1
			if paced and (n & 255) == 0 and not await _pace(p, pace):
				return
			var c := 0
			for d in o26:
				if g[at + d] != 0:
					c += 1
					if c >= STRAY:
						break
			if c < STRAY:
				few[at] = true
			elif pass_ > 0:
				few.erase(at)
			var now := 2
			if c <= TOOTH and not extra.has(lo + Vector3i(at / sx, (at / dz) % dy, at % dz)):
				now = 1
			var was := state[at]
			if was == now:
				continue
			var w := g[at]
			if was == 2:
				sound[w] = int(sound[w]) - 1
			elif was == 1:
				(teeth[w] as Dictionary).erase(at)
			if now == 2:
				sound[w] = int(sound.get(w, 0)) + 1
			else:
				if not teeth.has(w):
					teeth[w] = {}
				(teeth[w] as Dictionary)[at] = true
			state[at] = now
			touched[w] = true
		var off := PackedInt32Array()
		if pass_ < 3:
			for w in touched:
				if int(sound.get(w, 0)) <= 0 or not teeth.has(w):
					continue
				var tw: Dictionary = teeth[w]
				for at: int in tw:
					owner.erase(lo + Vector3i(at / sx, (at / dz) % dy, at % dz))
					g[at] = 0
					state[at] = 0
					few.erase(at)
					off.append(at)
					changed = true
				tw.clear()
		shut_before = shut
		off_before = off
		if not changed:
			break
	# What lies apart from the piece: a few of its voxels touching one another (by a corner at
	# least) and nothing else of it. (Looked for from the voxels with little of it round them:
	# each of such a few has.)
	var seen := {}
	var strays := []
	var apart := {}   # plate (+ 1) -> how many of its voxels lie so
	for at0: int in few:
		if seen.has(at0) or g[at0] == 0:
			continue
		var grp := PackedInt32Array([at0])
		var i := 0
		while i < grp.size() and grp.size() <= STRAY:
			var at := grp[i]
			i += 1
			for d in o26:
				var j := at + d
				if g[j] != 0 and not grp.has(j):
					grp.append(j)
		for at in grp:
			seen[at] = true
		if grp.size() <= STRAY:
			strays.append(grp)
			for at in grp:
				apart[g[at]] = int(apart.get(g[at], 0)) + 1
	if strays.is_empty():
		return
	var total := {}   # plate (+ 1) -> how many voxels it has
	for kc in owner:
		total[int(owner[kc]) + 1] = int(total.get(int(owner[kc]) + 1, 0)) + 1
	for grp: PackedInt32Array in strays:
		# (Left out only where each of its plates is drawn in the piece itself, and none of it
		# stands out on purpose.)
		var kept := false
		for at in grp:
			if extra.has(lo + Vector3i(at / sx, (at / dz) % dy, at % dz)) or int(total[g[at]]) <= int(apart.get(g[at], 0)):
				kept = true
				break
		if kept:
			continue
		for at in grp:
			owner.erase(lo + Vector3i(at / sx, (at / dz) % dy, at % dz))

## The test of a place of a ground's lattice for _tidy's `skin`: whether one of his skin's fine
## voxels reaches a quarter of the way into it or more (_skin_in). None where the ground keeps no
## grid of them.
static func skin_test(ground: Dictionary):
	if not ground.has("skin"):
		return null
	var sk: Dictionary = ground.skin
	var fsz: float = sk.fsz
	# (A fine voxel reaches a quarter of the way into a place when its middle lies in the place
	# widened by a quarter of a fine voxel each way: the first of them along each line, as a
	# number of the place's own.)
	var a: Vector3 = ((ground.o as Vector3) - (sk.o as Vector3)) / fsz - Vector3.ONE * 0.75
	var b: Vector3 = (ground.sp as Vector3) / fsz
	return _skin_in.bind(sk.occ, sk.dim, a, b)

## Whether one of his skin's fine voxels (`occ`: the fine lattice as a grid `dim` big, 1 where one
## lies) has its middle in place `kc` of a piece's lattice widened by a quarter of a fine voxel
## each way: along each line the fine voxels from ceil(a + kc * b), as far as b and a half on.
static func _skin_in(kc: Vector3i, occ: PackedByteArray, dim: Vector3i, a: Vector3, b: Vector3) -> bool:
	var at := a + Vector3(kc) * b
	var i0 := Vector3i(at.ceil()).max(Vector3i.ZERO)
	var i1 := Vector3i((at + b + Vector3.ONE * 0.5).ceil()).min(dim)
	for x in range(i0.x, i1.x):
		for y in range(i0.y, i1.y):
			var row := (x * dim.y + y) * dim.z
			for z in range(i0.z, i1.z):
				if occ[row + z] != 0:
					return true
	return false

## Whether his flesh lies in place `kc` (`skin`: the places it lies in, or a test of one).
static func _in(skin, kc: Vector3i) -> bool:
	return bool((skin as Callable).call(kc)) if skin is Callable else (skin as Dictionary).has(kc)

## Whether his flesh at place `kc` (number `at` on grid `g`) shows: some way straight out from it
## there is none of the piece, and none of him, as far as SEEN places.
static func _bare(g: PackedInt32Array, at: int, o6: PackedInt32Array, d6: Array, skin, kc: Vector3i) -> bool:
	for f in 6:
		var free := true
		for t in range(1, SEEN + 1):
			var j := at + o6[f] * t
			if j < 0 or j >= g.size():
				break   # (off the grid: past the piece)
			if g[j] != 0 or _in(skin, kc + (d6[f] as Vector3i) * t):
				free = false
				break
		if free:
			return true
	return false

## A helmet hangs together: what its face's cut left on its own (a voxel or two of a visor's grille
## where the cheek turns) is left out of it (user: no armour voxels in the air).
static func _keep_whole(owner: Dictionary, extra: Dictionary) -> void:
	var seen := {}
	var groups := []
	var big := 0
	for kc in owner:
		if seen.has(kc):
			continue
		seen[kc] = true
		var g := [kc]
		var i := 0
		while i < g.size():
			var c: Vector3i = g[i]
			i += 1
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var nb := c + Vector3i(dx, dy, dz)
						if owner.has(nb) and not seen.has(nb):
							seen[nb] = true
							g.append(nb)
		groups.append(g)
		big = maxi(big, g.size())
	if groups.size() < 2:
		return
	var kept := false
	for g in groups:
		if (g as Array).size() == big and not kept:
			kept = true
			continue
		for kc in g:
			owner.erase(kc)
			extra.erase(kc)

## A closed face (a secutor's): every fine voxel round his face from his chin to his brow drawn as
## the shell, the nearest plate's (a hat's plates leave the middle of his face open).
static func _close_face(p: VoxelPart, owner: Dictionary, ground: Dictionary, org: PackedVector3Array, first: PackedByteArray, o: Vector3, sp: Vector3) -> void:
	var wc: Vector3 = p.fine.wc
	var pts: PackedVector3Array = ground.pts
	var idx: PackedInt32Array = ground.idx
	var top := float(p.fine.brow_y) + sp.y
	for s in pts.size():
		var kc := Vector3i(idx[s * 3], idx[s * 3 + 1], idx[s * 3 + 2])
		if owner.has(kc):
			continue
		var q := pts[s]
		var d := q - wc
		if d.z <= 0.0 or d.z < 0.3 * d.length() or q.y > top:
			continue
		var best := INF
		var who := -1
		for ci in org.size():
			if first[ci] == 1:
				var dd := q.distance_squared_to(org[ci])
				if dd < best:
					best = dd
					who = ci
		if who >= 0:
			owner[kc] = who

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

## A voxel's corners shaded by the shell's own voxels round it (VoxelPart.ao_bits), read off the
## piece as a grid of numbers `g` (1: of the piece), the voxel's place in it `at`. `steps`: the
## places looked at, from _ao_steps. (Asked of the dictionary of places, with the faces' own
## tables read voxel by voxel, it was a third of the time a piece took to lay out.)
static func _ao_at(g: PackedByteArray, at: int, steps: PackedInt32Array) -> int:
	var bits := 0
	var k := 0
	for f in 6:
		var nb := at + steps[k]
		if g[nb] == 0:
			for cc in 4:
				var j := k + 1 + cc * 3
				if g[nb + steps[j]] != 0 or g[nb + steps[j + 1]] != 0 or g[nb + steps[j + 2]] != 0:
					bits |= 1 << (f * 4 + cc)
		k += 13
	return bits

## For _ao_at, on a grid where a step along x, y, z is `step` places: face by face (VoxelPart.
## AO_FACES), the place the face looks on, then for each of its four corners the three places
## round that one that shade the corner.
static func _ao_steps(step: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for f in 6:
		var fd: Array = VoxelPart.AO_FACES[f]
		var dir: Vector3i = fd[0]
		out.append(dir.x * step[0] + dir.y * step[1] + dir.z * step[2])
		var ua := step[int(fd[1])]
		var va := step[int(fd[2])]
		for cc in 4:
			var su := ua if cc & 1 else -ua
			var sv := va if cc & 2 else -va
			out.append(su)
			out.append(sv)
			out.append(su + sv)
	return out

static func _hash(v: Vector3i) -> float:
	return float(posmod(hash(v + Vector3i(31, 17, 5)), 1000)) / 1000.0
