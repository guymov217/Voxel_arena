class_name FineBody
extends RefCounted
## The new look's body (Physique "human"; drawing only): a man as he is built, in voxels half the
## size of the body's own (tools/gen_fine_body.py -> data/fine_body.json), drawn over the game's
## own parts and joints: the deltoid round the shoulder, the chest over a narrower waist, the
## muscles of the arms and legs, a fist, a foot. Three builds (the hero, the champion, the brute).
## The parts, their colliders and every voxel that is hit, cut and bled are the game's: each fine
## voxel lies over one of the part's own and is drawn while that one is alive, in the man's skin
## (or the colour that one has, his loincloth, a strap; or blood, a burn, a scar when that one is
## marked after the look was made). The part's own voxels under the skin are not drawn; those
## wholly inside him are, and a wound opens on them. Each voxel a wound bares is drawn as its
## eight half-size cells, as deep in him as they are: the skin, the fat under it, then the
## voxel's own flesh, organ or bone. A bone broken through bends the skin with the limb.

const FineSmooth := preload("res://scripts/fighter/fine_smooth.gd")
const FILE := "res://data/fine_body.json"
const CELL := 9   # a cell's numbers: ix, iy, iz (from the grid's corner), its voxel's x, y, z, shade, ao, paint
## A sculpted beast's fine voxel (tools/gen_fine_beasts.py) carries its own colour and kind in its
## paint: this bit, the kind in bits 24..29, the colour 0xRRGGBB.
const OWN_COLOUR := 1 << 30
const DEEP := 0xFFFF   # a voxel's eight cells all deep in him (drawn as it is, under the skin)
const SKIN_K := 0.86   # the skin's light (as the body's own skin voxels are lit, on average)
const FAT := Color(0.92, 0.72, 0.46)       # (yellower, and the flesh redder: a cut reads skin, fat,
const MUSCLE := Color(0.72, 0.08, 0.065)   # flesh, where it read as one brown: user)
## The lips of a cut: fresh blood along them, darker in spots where it has begun to clot.
const FRESH := Color(0.78, 0.04, 0.035)
const CLOT := Color(0.36, 0.015, 0.02)
## How wet what a wound bares looks (the shader's gloss, -status.x), by its depth: the skin's torn
## edge, the fat, the flesh and the organs; a bone less.
const WET := [0.0, 0.55, 0.7, 0.9]
const WET_BONE := 0.45
## Fresh blood on the skin: as glossy as there is blood on it.
const WET_SMEAR := 0.6
const BONE := Color(0.93, 0.89, 0.8)
## Blood as the new look draws it, over the skin and in a cut: a brighter red than the body's own
## mark (VoxelPart.SMEAR), which the fine voxels' shading took down to a brown that read as shadow
## on the new men's muscles (user: the damage did not show on the new gladiators as it had).
const BLOOD := Color(0.6, 0.04, 0.035)
const BUILDS := ["hero", "champion", "brute"]
## The giants' builds: their skin smooth and their limbs' joints run on as a man's are (user: what
## was done for the gladiators on every monster and beast).
const GIANTS := ["cyclops", "polyphemus", "minotaur", "troll", "titan"]

static var _tpl := {}
static var _parsed := {}
static var _mesh := {}

static func template() -> Dictionary:
	if _tpl.is_empty() and FileAccess.file_exists(FILE):
		var fl := FileAccess.open(FILE, FileAccess.READ)
		if fl:
			var d = JSON.parse_string(fl.get_as_text())
			if d is Dictionary:
				_tpl = d
	return _tpl

## The build's part as packed arrays (worked out once): cells, sub (each voxel's eight cells, two
## bits each: 0 not his, 1 skin, 2 fat, 3 deep), k (how the part's box is drawn mapped onto him,
## by fine row and way round its line: a voxel at radius r drawn at r * k).
static func part_data(bn: String, part: String) -> Dictionary:
	var key := bn + "|" + part
	if _parsed.has(key):
		return _parsed[key]
	var out := {}
	var b = template().get("builds", {}).get(bn)
	if b is Dictionary:
		var pd = b.get("parts", {}).get(part)
		if pd is Dictionary:
			var k := PackedFloat32Array()
			for row in pd.k:
				for v in row:
					k.append(float(v))
			out = {"cells": PackedInt32Array(pd.cells), "sub": PackedInt32Array(pd.sub), "k": k, "rows": (pd.k as Array).size(), "na": int(template().get("na", 32)),
				"palette": b.get("palette", []), "cloth": b.get("cloth", []), "lines": PackedInt32Array(pd.get("lines", [])),
				"fit": PackedInt32Array(pd.get("fit", []))}
	_parsed[key] = out
	return out

## A beast's part (tools/gen_fine_beasts.py -> data/fine_beasts/<species>.json): the beast as it
## is sculpted, laid on its own voxels, read the first time one of its kind is drawn (a beast not yet
## sculpted is drawn as its voxels).
const BEAST_DIR := "res://data/fine_beasts/"
static var _beasts := {}
static func beast_data(species: String, part: String) -> Dictionary:
	var key := "beast:" + species + "|" + part
	if _parsed.has(key):
		return _parsed[key]
	if not _beasts.has(species):
		var tpl := {}
		var path := BEAST_DIR + species + ".json"
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				tpl = d
		_beasts[species] = tpl
	var out := {}
	var pd = (_beasts[species] as Dictionary).get("parts", {}).get(part)
	if pd is Dictionary:
		out = {"cells": PackedInt32Array(pd.cells), "sub": PackedInt32Array(pd.sub), "beast": true}
		# (Its smooth skin, worked out with its sculpt: tools/gen_fine_beasts.py, _beast_smooth.)
		if pd.get("sw") is String and pd.get("sn") is String and pd.get("sv") is String:
			out["sw"] = Marshalls.base64_to_raw(pd.sw)
			out["sn"] = Marshalls.base64_to_raw(pd.sn)
			out["sv"] = Marshalls.base64_to_raw(pd.sv)
			# (And its shape drawn on its hide under it, a tone a fine voxel: form_tones there.)
			if pd.get("st") is String:
				out["st"] = Marshalls.base64_to_raw(pd.st)
		# (What its sculpt says of how the part is drawn: its joints not as one skin, "stiff":
		# Beast._bend_drawing.)
		if pd.has("stiff"):
			out["stiff"] = true
	_parsed[key] = out
	return out

## A beast drawn in the new look (`on`), or as its own voxels again.
static func dress_beast(b, on := true) -> void:
	for p in b.parts:
		if on:
			build(b, p, "beast:" + String(b.species))
		else:
			clear(p)

## How much smaller than the game's head the build's fine head is drawn.
static func head_scale(bn: String) -> float:
	var b = template().get("builds", {}).get(bn)
	return float(b.get("head", 1.0)) if b is Dictionary else 1.0

static func _box(fsz: float) -> BoxMesh:
	var key := snappedf(fsz, 0.00001)
	if not _mesh.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * fsz * 1.04
		bm.material = FineHead.material()
		_mesh[key] = bm
	return _mesh[key]

static func _drawing() -> bool:
	return DisplayServer.get_name() != "headless"

## The map's factor at a point of the part's box (part-local): bilinear in the fine row (by its
## height) and the way round the part's line, as tools/gen_fine_body.py _k_at.
static func k_at(p: VoxelPart, d: Dictionary, q: Vector3) -> float:
	if not d.has("k"):
		return 1.0   # (a beast's: drawn where its voxels are)
	var kt: PackedFloat32Array = d.k
	var rows: int = d.rows
	var na: int = d.na
	var vox := p.vf * p.part_scale
	var fsz := vox / float(int(template().get("res", 2)))
	var ylo := -float(p.grid.y) * vox * 0.5 - float(int(template().get("margin", 10))) * fsz
	var fr := clampf((q.y - ylo) / fsz - 0.5, 0.0, float(rows - 1))
	var r0 := int(floorf(fr))
	var r1 := mini(r0 + 1, rows - 1)
	var wr := fr - float(r0)
	var fa := (atan2(q.z, q.x) + PI) / TAU * float(na) - 0.5
	var a0f := floorf(fa)
	var wa := fa - a0f
	var a0 := posmod(int(a0f), na)
	var a1 := (a0 + 1) % na
	var k0 := kt[r0 * na + a0] * (1.0 - wa) + kt[r0 * na + a1] * wa
	var k1 := kt[r1 * na + a0] * (1.0 - wa) + kt[r1 * na + a1] * wa
	return k0 * (1.0 - wr) + k1 * wr

## Where a box `size` big at `q` of the part's box (part-local) is drawn on him.
static func mapped(p: VoxelPart, d: Dictionary, q: Vector3, size := 1.0) -> Transform3D:
	var k := k_at(p, d, q)
	return Transform3D(Basis.from_scale(Vector3(k, 1.0, k) * size), Vector3(q.x * k, q.y, q.z * k))

## Drawn on `p` (any of his parts but the head) in build `bn`, or taken off (`on` false).
## Built over a few frames with `staged` (a man built while the fight goes on, Match.spawn_fighter_
## staged: his trunk's thousands of fine voxels in one frame were a hitch of their own).
const STAGE_CELLS := 3000
static func build(f, p: VoxelPart, bn: String, on := true, staged := false) -> void:
	clear(p)
	if not on or p.missing or p.prosthetic != "" or String(p.part_name) == "head":
		return
	var beast := bn.begins_with("beast:")
	var d := beast_data(bn.substr(6), String(p.part_name)) if beast else part_data(bn, String(p.part_name))
	if d.is_empty():
		return
	var g := p.grid
	var sub: PackedInt32Array = d.sub
	if sub.size() != g.x * g.y * g.z:
		return
	var vox := p.vf * p.part_scale
	# (A man's skin smooth, FineSmooth: a layout of its own; a giant's as a man's.)
	# (And a beast's, which comes with its sculpt: _beast_smooth.)
	var man := BUILDS.has(bn) or GIANTS.has(bn) or (beast and d.has("sw") and (d.sw as PackedByteArray).size() == (d.cells as PackedInt32Array).size() / CELL * 2)
	var L := _layout(p, d, bn + "|" + String(p.part_name) + "|" + str(snappedf(vox, 0.00001)) + ("|smooth" if man and FineSmooth.live() else "") + ("|geo" if man and FineSmooth.skinned() else ""), beast)
	var cells: PackedInt32Array = d.cells
	var fsz: float = L.fsz
	var n: int = L.n
	var par: PackedInt32Array = L.par
	var shade: PackedFloat32Array = L.shade
	var of: Dictionary = L.of
	# The part's own voxels: those wholly inside him drawn mapped onto him, under the skin; the rest
	# not (a copy: a wound changes them, man by man).
	p.set_shape((L.vxf as Array).duplicate())
	var sk_lin: Color = (f.skin as Color).srgb_to_linear() if f is Fighter else Color(0.4, 0.2, 0.12)
	var own := PackedColorArray()
	own.resize(n)
	for s in n:
		var j := par[s]
		if j >= 0:
			own[s] = _own(p, j, shade[s], sk_lin, beast, cells[s * CELL + 8], d)
		if staged and s % STAGE_CELLS == STAGE_CELLS - 1:
			if not await Physique._frame(p):
				return
	var base := {}
	for j in of:
		base[j] = p.colors[j]
	var na: PackedFloat32Array = L.na
	var fine := {"body": true, "build": bn, "par": par, "own": own, "shade": shade, "xf": L.xf, "of": of, "base": base, "na": na,
		"hid": L.hid, "code": L.code, "sub": d.sub, "fsz": fsz, "sk": sk_lin, "wound": {}, "wfree": [], "wn": 0, "cells": cells, "d": d, "beast": beast,
		"smooth": L.skin != null, "jaw_corners": L.jaw_corners}
	p.fine = fine
	if _drawing():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _box(fsz)
		mm.instance_count = n
		# One buffer for all of them (the places and the kinds the build's; the colours his own).
		var buf: PackedFloat32Array = (L.buf as PackedFloat32Array).duplicate()
		for s in n:
			var j := par[s]
			var o := s * 20
			if j < 0 or p.alive[j] == 0:
				for q in 12:
					buf[o + q] = 0.0
			var c := _color(p, s, j)
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = na[s] if na.size() == n else 1.0
			if staged and s % STAGE_CELLS == STAGE_CELLS - 1:
				if not await Physique._frame(p) or not is_same(p.fine, fine):
					return
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mi.top_level = true
		# (As far round the part as its fine voxels lie: drawn further off its box than a fixed
		# band round it, they went out of sight when the box itself was out of the view.)
		var ext := Vector3(p.grid) * vox * 0.5 + Vector3.ONE * fsz * maxf(12.0, float(L.get("far_out", 0)) + 2.0)
		mi.custom_aabb = AABB(-ext, ext * 2.0)
		mm.custom_aabb = mi.custom_aabb
		p.add_child(mi)
		fine.mm = mm
		fine.mi = mi
		for j in p.glowing:
			status(p, j, p.glowing[j])   # (burning, or eaten by acid, as he was drawn)
		p.draw_with.append(mi)
		mi.global_transform = p.global_transform
		mi.transparency = p.see_through
		if L.skin != null:
			mi.material_override = L.skin
		# The part's own voxels are not drawn at all under the fine ones (what a wound bares is drawn
		# as the wound's cells): half the boxes a man is drawn with.
		if p.mmi:
			p.mmi.visible = false
	if p.jaw_pivot != null and not p.jaw_slot.is_empty() and fine.has("mm"):
		_jaw_on(p)
	# The wounds he came in with (old ones healed into dents, Body): bared as any other.
	var bare := []
	for i in p.fx.size():
		if p.alive[i] == 1 and _open(p, i):
			bare.append(i)
	for i in bare:
		_expose(p, i)
	if p.dangle_mm != null:
		dangle_on(p)
		if p.dangle_mesh:
			p.dangle_mesh.visible = false

## A giant of myth is drawn slimmer than his boxes (his build's sculpt): each part's collider is
## kept to it (VoxelPart.fit_to), layer by layer along the part, so that what strikes and is struck
## is what is drawn (user: a giant knocked a man down with nothing on screen touching him). In any
## look: the same fight in every look (the classic giant drawn as his voxels, a little fuller).
static func fit_giant(f) -> void:
	var bn := Physique.giant_of(f)
	if bn == "":
		return
	for p: VoxelPart in f.parts:
		if p == f.head or p.missing or p.prosthetic != "":
			continue
		var d := part_data(bn, String(p.part_name))
		if d.is_empty() or (d.sub as PackedInt32Array).size() != p.grid.x * p.grid.y * p.grid.z:
			continue
		var vox := p.vf * p.part_scale
		# (By the fit kept in his build, tools/gen_fine_body.py "fit": the boxes of the giant as he
		# was first sculpted. His skin sculpted anew since, smooth, a fighter's feet, is drawing
		# only: he strikes and is struck by the boxes he always had, to the last bit.)
		var kept := slabs_kept(p, d.get("fit", PackedInt32Array()), vox)
		p.fit_to(kept if not kept.is_empty() else slabs(p, _layout(p, d, bn + "|" + String(p.part_name) + "|" + str(snappedf(vox, 0.00001)), false)))

## What is drawn of a part (its fine voxels that lie over a voxel of it), as boxes laid along it
## (own frame): one to each layer of its box along the line it hangs by, round what is drawn in
## that layer and never past the box, layers alike taken as one.
static func slabs(p: VoxelPart, L: Dictionary) -> Array:
	var ax: int = p._root_axis()[0]
	var n: int = p.dims[ax]
	var he := p.half_ext
	var cell: float = he[ax] * 2.0 / float(n)
	var lo := []
	var hi := []
	for k in n:
		lo.append(Vector3.INF)
		hi.append(-Vector3.INF)
	var par: PackedInt32Array = L.par
	var xf: Array = L.xf
	var h := Vector3.ONE * float(L.fsz) * 0.5
	for s in par.size():
		if par[s] < 0:
			continue
		var c: Vector3 = (xf[s] as Transform3D).origin
		if absf(c[ax]) > he[ax]:
			continue   # (over the joint, on the part beside it: drawn with that one)
		var k := clampi(int(floor((c[ax] + he[ax]) / cell)), 0, n - 1)
		lo[k] = (lo[k] as Vector3).min(c - h)
		hi[k] = (hi[k] as Vector3).max(c + h)
	return _slab_boxes(p, lo, hi)

## The same boxes from a build's kept fit (`fit`: the axis of the part's line, then for each row
## of fine voxels along it its place and the least and the greatest places, the other two ways,
## of the fine voxels the giant was first sculpted in): each place made as _layout makes a fine
## voxel's and laid in its layer as slabs() lays it, so the boxes are the ones slabs() made of
## those fine voxels, to the last bit. Empty if the build keeps none (or for another line).
static func slabs_kept(p: VoxelPart, fit: PackedInt32Array, vox: float) -> Array:
	var ax: int = p._root_axis()[0]
	var n: int = p.dims[ax]
	if fit.size() < 6 or (fit.size() - 1) % 5 != 0 or fit[0] != ax:
		return []
	var he := p.half_ext
	var cell: float = he[ax] * 2.0 / float(n)
	var fsz := vox / 2.0
	var lo_p := -Vector3(p.grid) * vox * 0.5
	var h := Vector3.ONE * float(fsz) * 0.5
	var oa := 1 if ax == 0 else 0
	var ob := 1 if ax == 2 else 2
	var lo := []
	var hi := []
	for k in n:
		lo.append(Vector3.INF)
		hi.append(-Vector3.INF)
	for r in range(1, fit.size(), 5):
		var q0 := Vector3.ZERO
		var q1 := Vector3.ZERO
		q0[ax] = fit[r]
		q1[ax] = fit[r]
		q0[oa] = fit[r + 1]
		q0[ob] = fit[r + 2]
		q1[oa] = fit[r + 3]
		q1[ob] = fit[r + 4]
		var c0 := lo_p + (q0 + Vector3(0.5, 0.5, 0.5)) * fsz
		var c1 := lo_p + (q1 + Vector3(0.5, 0.5, 0.5)) * fsz
		if absf(c0[ax]) > he[ax]:
			continue   # (over the joint, on the part beside it)
		var k := clampi(int(floor((c0[ax] + he[ax]) / cell)), 0, n - 1)
		lo[k] = (lo[k] as Vector3).min(c0 - h)
		hi[k] = (hi[k] as Vector3).max(c1 + h)
	return _slab_boxes(p, lo, hi)

static func _slab_boxes(p: VoxelPart, lo: Array, hi: Array) -> Array:
	var ax: int = p._root_axis()[0]
	var n: int = p.dims[ax]
	var he := p.half_ext
	var cell: float = he[ax] * 2.0 / float(n)
	var whole := AABB(-he, he * 2.0)
	var out := []
	for k in n:
		var layer := whole
		layer.position[ax] = -he[ax] + cell * k
		layer.size[ax] = cell
		var b := layer
		if (lo[k] as Vector3).x <= (hi[k] as Vector3).x:
			var cut := layer.intersection(AABB(lo[k], hi[k] - lo[k]))
			if cut.has_volume():
				cut.position[ax] = layer.position[ax]
				cut.size[ax] = cell
				b = cut
		# (The layer before it as good as the same across: the two one box.)
		if not out.is_empty():
			var last: AABB = out[out.size() - 1]
			var same := true
			for a in 3:
				if a != ax and (absf(last.position[a] - b.position[a]) > 0.012 * p.part_scale or absf(last.end[a] - b.end[a]) > 0.012 * p.part_scale):
					same = false
			if same:
				out[out.size() - 1] = last.merge(b)
				continue
		out.append(b)
	return out

## What a part of a build (or of a beast) is drawn with that is the same for every man of it,
## worked out once a build, a part and a size: each fine voxel's place, the voxel it lies over,
## its shade, the voxels' own map and which are drawn, and the drawing's buffer (the places and
## the kinds; the colours are each man's own). A man spawned in a tenth of the time.
static var _layouts := {}
static func _layout(p: VoxelPart, d: Dictionary, key: String, beast: bool) -> Dictionary:
	if _layouts.has(key):
		return _layouts[key]
	var g := p.grid
	var sub: PackedInt32Array = d.sub
	var res := 2
	var vox := p.vf * p.part_scale
	var fsz := vox / float(res)
	var lo := -Vector3(g) * vox * 0.5
	var cells: PackedInt32Array = d.cells
	var n := cells.size() / CELL
	var lps := p.local_positions()
	var hid := PackedByteArray()
	hid.resize(p.fx.size())
	var vxf := []
	vxf.resize(p.fx.size())
	var code := PackedInt32Array()
	code.resize(p.fx.size())
	for i in p.fx.size():
		var c := sub[(p.fx[i] * g.y + p.fy[i]) * g.z + p.fz[i]]
		code[i] = c
		if c == DEEP:
			vxf[i] = mapped(p, d, lps[i])
		else:
			hid[i] = 1
			vxf[i] = Transform3D(Basis().scaled(Vector3.ZERO), lps[i])
	var par := PackedInt32Array()
	par.resize(n)
	var shade := PackedFloat32Array()
	shade.resize(n)
	var cxf: Array = []
	cxf.resize(n)
	var of := {}
	var buf := PackedFloat32Array()
	buf.resize(n * 20)
	var far_out := 0    # how far out of the part's own grid its fine voxels lie, the furthest of them
	for s in n:
		for a in 3:
			var c := cells[s * CELL + a]
			far_out = maxi(far_out, maxi(-c, c - g[a] * res + 1))
	var pal: Array = d.get("palette", [])
	var cloth: Array = d.get("cloth", [])
	var smooth := key.contains("|smooth")
	var skinned := key.contains("|geo")
	var grain_k := FineSmooth.GRAIN if skinned else 1.0
	for s in n:
		var o := s * CELL
		var j := p._cell(cells[o + 3], cells[o + 4], cells[o + 5])
		par[s] = j
		var lp := lo + (Vector3(cells[o], cells[o + 1], cells[o + 2]) + Vector3(0.5, 0.5, 0.5)) * fsz
		cxf[s] = Transform3D(Basis(), lp)
		var grain := 1.0 + (float(absi(hash(Vector3i(cells[o], cells[o + 1], cells[o + 2]))) % 1000) / 1000.0 - 0.5) * 0.05 * grain_k
		shade[s] = float(cells[o + 6]) / 200.0 * grain
		# (An Array, not a packed one: a packed array read out of the dictionary is a copy, and
		# what was appended to it never reached the dictionary.)
		if j >= 0:
			if not of.has(j):
				of[j] = []
			(of[j] as Array).append(s)
		var b := s * 20
		buf[b] = 1.0
		buf[b + 3] = lp.x
		buf[b + 5] = 1.0
		buf[b + 7] = lp.y
		buf[b + 10] = 1.0
		buf[b + 11] = lp.z
		# Its kind: the voxel's, or what the build paints there (VoxelPart.kind_data).
		var k: int = p.kinds[j] if j >= 0 else 0
		var paint := cells[o + 8]
		if paint & OWN_COLOUR:
			k = (paint >> 24) & 63
		elif paint > 0 and paint <= pal.size():
			k = int(pal[paint - 1][3])
		elif k == 1 and cloth.size() >= 4:
			k = int(cloth[3])
		elif not beast and k >= 6:
			k = 0
		var cu := VoxelPart.kind_data(0 if k == 1 else k, cells[o + 7], 0)
		buf[b + 16] = cu.r
		buf[b + 17] = cu.g
		buf[b + 18] = cu.b
		buf[b + 19] = cu.a
	# The way a man's body faces at each fine voxel (FineSmooth: the smooth light), its ends at a
	# joint taken to run on: an upper arm's and a thigh's low end, the trunk's (the hips), a
	# forearm's, a shin's and a thigh's high one.
	var na := PackedFloat32Array()
	var skin: ShaderMaterial = null
	var jaw_corners := PackedFloat32Array()
	if smooth and beast:
		var made := _beast_smooth(d, cells, n, skinned)
		na = made[0]
		# Under the smooth skin its shape is drawn on its hide (as a man's body's lines are, below):
		# each fine voxel a tile of the tone the sculpt gave it, where it gave it one.
		var st: PackedByteArray = d.get("st", PackedByteArray())
		if skinned and st.size() == n:
			for s in n:
				if st[s] != 0:
					var grain := 1.0 + (float(absi(hash(Vector3i(cells[s * CELL], cells[s * CELL + 1], cells[s * CELL + 2]))) % 1000) / 1000.0 - 0.5) * 0.05 * grain_k
					shade[s] = maxf(0.3, 1.0 + (float(st[s]) / 200.0 - 1.0) * FineSmooth.LINES) * grain
		if skinned and not (made[1] as PackedFloat32Array).is_empty():
			skin = FineSmooth.skin(made[1], FineHead.material())
			# (A head's jaw is a drawing of its own, _jaw_on: its corners are picked out of these.)
			if not p.jaw_slot.is_empty():
				jaw_corners = made[1]
	elif smooth:
		var at := _fine_at(cells)
		# Under the smooth skin his body's lines are drawn on it (tools/gen_fine_body.py _details:
		# [fine voxel, its shade] by turns), each fine voxel a tile a shade darker or lighter.
		if skinned:
			var lines: PackedInt32Array = d.get("lines", PackedInt32Array())
			for li in range(0, lines.size() - 1, 2):
				var s: int = lines[li]
				if s >= 0 and s < n:
					var grain := 1.0 + (float(absi(hash(Vector3i(cells[s * CELL], cells[s * CELL + 1], cells[s * CELL + 2]))) % 1000) / 1000.0 - 0.5) * 0.05 * grain_k
					shade[s] = maxf(0.3, 1.0 + (float(lines[li + 1]) / 200.0 - 1.0) * FineSmooth.LINES) * grain
		var bn := key.get_slice("|", 0)
		var own := _smooth_solid(p, d, bn, vox)
		var sol := _smooth_joined(p, d, bn, vox)
		var reach := FineSmooth.REACH_TRUNK if String(p.part_name) == "torso" else FineSmooth.REACH
		var light := FineSmooth.blurred(sol, reach)
		# (The part's own ends, under the parts beside it, by its own shape: FineSmooth.corners.)
		var alone := is_same(own, sol)
		var own_light := light if alone else FineSmooth.blurred(own, reach)
		na = FineSmooth.ways(at, light, sol, own_light)
		if skinned:
			var shape := FineSmooth.blurred(sol, FineSmooth.GEO_REACH)
			skin = FineSmooth.skin(FineSmooth.corners(at, sol, shape, light, own, shape if alone else FineSmooth.blurred(own, FineSmooth.GEO_REACH), own_light), FineHead.material())
	var L := {"n": n, "fsz": fsz, "par": par, "shade": shade, "xf": cxf, "of": of, "buf": buf, "hid": hid, "vxf": vxf, "code": code, "na": na, "skin": skin, "jaw_corners": jaw_corners, "far_out": far_out}
	_layouts[key] = L
	return L

## A beast's smooth skin (user: the gladiators' smooth skin on every monster and beast), which is
## worked out with its sculpt on the whole beast at rest (tools/gen_fine_beasts.py smooth_skin: a
## beast's parts are its skin shared out among them, no shut solids to work it out from here, and
## its skin has to run on across its joints): [the way each fine voxel faces (FineSmooth.ways), its
## corners' moves and ways (FineSmooth.corners; none unless `skinned`)]. `sw`: two bytes a fine
## voxel, its way (0xFFFF none). The corners of its fine voxels, each once in the order of their
## places: `sn` a bit each, whether it is on the skin; `sv` five bytes for each that is, its move's
## three (steps of 1/160 of a fine voxel about 128), its way's low eight bits, the high two (128:
## none). A corner under the skin is drawn where it is, lit as its cube.
static func _beast_smooth(d: Dictionary, cells: PackedInt32Array, n: int, skinned: bool) -> Array:
	var sw: PackedByteArray = d.sw
	var na := PackedFloat32Array()
	na.resize(n)
	for s in n:
		var c := sw[s * 2] | (sw[s * 2 + 1] << 8)
		na[s] = FineSmooth.NONE if c == 0xFFFF else 2.0 + float(c)
	var cd := PackedFloat32Array()
	if not skinned:
		return [na, cd]
	var keys := PackedInt64Array()
	keys.resize(n * 8)
	for s in n:
		var base := ((cells[s * CELL] + 64) * 1024 + cells[s * CELL + 1] + 64) * 1024 + cells[s * CELL + 2] + 64
		for c in 8:
			keys[s * 8 + c] = base + (c & 1) * 1048576 + ((c >> 1) & 1) * 1024 + ((c >> 2) & 1)
	var sorted := keys.duplicate()
	sorted.sort()
	var sn: PackedByteArray = d.sn
	var sv: PackedByteArray = d.sv
	# Each corner once, and where the five bytes of those on the skin are (-1: under it).
	var uniq := PackedInt64Array()
	var slot := PackedInt32Array()
	var last := -1
	var lit := 0
	for k in sorted:
		if k == last:
			continue
		last = k
		var i := uniq.size()
		uniq.append(k)
		if (i >> 3) < sn.size() and (sn[i >> 3] & (1 << (i & 7))) != 0:
			slot.append(lit)
			lit += 1
		else:
			slot.append(-1)
	if lit * 5 != sv.size():
		return [na, cd]   # (not this sculpt's: drawn as cubes, lit smooth)
	cd.resize(n * 32)
	for q in n * 8:
		var j := slot[uniq.bsearch(keys[q])]
		var o := q * 4
		if j < 0:
			cd[o + 3] = FineSmooth.NONE
			continue
		var b := j * 5
		cd[o] = float(sv[b] - 128) / 160.0
		cd[o + 1] = float(sv[b + 1] - 128) / 160.0
		cd[o + 2] = float(sv[b + 2] - 128) / 160.0
		cd[o + 3] = FineSmooth.NONE if (sv[b + 4] & 128) != 0 else 2.0 + float(sv[b + 3] | ((sv[b + 4] & 3) << 8))
	return [na, cd]

## A part's fine voxels (its cells' places), x y z by turns, as FineSmooth takes them.
static func _fine_at(cells: PackedInt32Array) -> PackedInt32Array:
	var n := cells.size() / CELL
	var at := PackedInt32Array()
	at.resize(n * 3)
	for s in n:
		at[s * 3] = cells[s * CELL]
		at[s * 3 + 1] = cells[s * CELL + 1]
		at[s * 3 + 2] = cells[s * CELL + 2]
	return at

## A part's own solid for the smooth skin (FineSmooth.solid: its fine voxels and what they close
## in), worked out once a build, a part and a size; and that with what is jointed onto the part
## beside it, by the joint (its thighs' tops under the trunk, the trunk over a thigh: FineSmooth.
## joined), each where it hangs at rest.
static var _solids := {}
static func _smooth_solid(p: VoxelPart, d: Dictionary, bn: String, vox: float) -> Dictionary:
	var key := "%s|%s|%s" % [bn, p.part_name, snappedf(vox, 0.00001)]
	if _solids.has(key):
		return _solids[key]
	var g := p.grid
	var sub: PackedInt32Array = d.sub
	var inner := PackedInt32Array()
	for i in p.fx.size():
		if sub[(p.fx[i] * g.y + p.fy[i]) * g.z + p.fz[i]] == DEEP:
			inner.append(p.fx[i])
			inner.append(p.fy[i])
			inner.append(p.fz[i])
	var pn := String(p.part_name)
	var sol := FineSmooth.solid(_fine_at(d.cells), inner, 2, pn.begins_with("upperArm") or pn.begins_with("thigh") or pn == "torso", pn.begins_with("forearm") or pn.begins_with("shin") or pn.begins_with("thigh"))
	_solids[key] = sol
	return sol

static func _smooth_joined(p: VoxelPart, d: Dictionary, bn: String, vox: float) -> Dictionary:
	var own := _smooth_solid(p, d, bn, vox)
	var f = p.fighter
	if f == null or not ("parts" in f):
		return own
	var fsz := vox / 2.0
	var lo_p := -Vector3(p.grid) * vox * 0.5
	var beside := []
	for q: VoxelPart in f.parts:
		if q == p or String(q.part_name) == "head":
			continue
		var child := q.parent_part == p
		if not child and p.parent_part != q:
			continue
		if not is_equal_approx(q.vf * q.part_scale, vox):
			continue
		var qd := part_data(bn, String(q.part_name))
		if qd.is_empty() or (qd.sub as PackedInt32Array).size() != q.grid.x * q.grid.y * q.grid.z:
			continue
		# (Where the other's own frame lies in this part's, at rest: its joint's two points one.)
		var off: Vector3 = (q.pa - q.ca) if child else (p.ca - p.pa)
		var joint: Vector3 = q.pa if child else p.ca
		var sh: Vector3 = (-Vector3(q.grid) * vox * 0.5 + off - lo_p) / fsz
		var limb: VoxelPart = q if child else p
		var r := maxf(limb.half_ext.x, limb.half_ext.z) / fsz * 1.3 + 3.0
		beside.append([_smooth_solid(q, qd, bn, vox), Vector3i(roundi(sh.x), roundi(sh.y), roundi(sh.z)), (joint - lo_p) / fsz, r])
	return FineSmooth.joined(own, beside)

## A biting head's lower jaw (VoxelPart.build_jaw): the fine voxels over its voxels drawn with it,
## turning on its hinge as it opens; its own voxels not drawn.
static func _jaw_on(p: VoxelPart) -> void:
	var fine: Dictionary = p.fine
	var mm: MultiMesh = fine.mm
	var par: PackedInt32Array = fine.par
	var cxf: Array = fine.xf
	var n := par.size()
	var jc := PackedInt32Array()
	jc.resize(n)
	var idx := []
	for s in n:
		jc[s] = -1
		if par[s] >= 0 and p.jaw_slot.has(par[s]):
			jc[s] = idx.size()
			idx.append(s)
	if idx.is_empty():
		# (No fine voxel over the jaw's own voxels: they are still not drawn in this look. Left
		# shown, they were a box of the classic head under a slender snout.)
		if p.jaw_mesh:
			p.jaw_mesh.visible = false
		return
	var off: Vector3 = p.jaw_pivot.position
	var jm := MultiMesh.new()
	jm.transform_format = MultiMesh.TRANSFORM_3D
	jm.use_colors = true
	jm.use_custom_data = true
	jm.mesh = mm.mesh
	jm.instance_count = idx.size()
	var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for k in idx.size():
		var s: int = idx[k]
		var j := par[s]
		var t: Transform3D = cxf[s]
		jm.set_instance_transform(k, Transform3D(t.basis, t.origin - off) if p.alive[j] == 1 else none)
		jm.set_instance_color(k, mm.get_instance_color(s))
		jm.set_instance_custom_data(k, mm.get_instance_custom_data(s))
		mm.set_instance_transform(s, none)
	jm.custom_aabb = mm.custom_aabb
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = jm
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.top_level = true
	mi.custom_aabb = mm.custom_aabb
	mi.transparency = p.see_through
	p.add_child(mi)
	# Under the smooth skin the jaw's fine voxels have their corners as the head's have (a skin of
	# their own: the corners are read by each fine voxel's place in its drawing).
	var hc: PackedFloat32Array = fine.get("jaw_corners", PackedFloat32Array())
	if hc.size() == n * 32:
		var jcd := PackedFloat32Array()
		jcd.resize(idx.size() * 32)
		for k in idx.size():
			var s: int = idx[k]
			for q in 32:
				jcd[k * 32 + q] = hc[s * 32 + q]
		mi.material_override = FineSmooth.skin(jcd, FineHead.material())
	fine.jaw_mm = jm
	fine.jaw_mi = mi
	fine.jaw_cell = jc
	fine.jaw_off = off
	if p.jaw_mesh:
		p.jaw_mesh.visible = false

## Where fine voxel `s` is drawn: [its multimesh, its slot there, its place in it when shown].
static func _slot(fine: Dictionary, s: int) -> Array:
	var cxf: Array = fine.xf
	var jc: PackedInt32Array = fine.get("jaw_cell", PackedInt32Array())
	if jc.size() > s and jc[s] >= 0:
		var t: Transform3D = cxf[s]
		return [fine.jaw_mm, jc[s], Transform3D(t.basis, t.origin - (fine.jaw_off as Vector3))]
	var fs: PackedInt32Array = fine.get("far_slot", PackedInt32Array())
	if fs.size() > s and fs[s] >= 0:
		return [fine.far_mm, fs[s], cxf[s]]
	return [fine.mm, s, cxf[s]]

## Taken off (the look that drew it puts the part's own voxels back: Physique.dress).
static func clear(p: VoxelPart) -> void:
	if p.fine.is_empty() or not p.fine.has("body"):
		return
	dangle_off(p)
	if p.mmi:
		p.mmi.visible = true
	if p.dangle_mesh:
		p.dangle_mesh.visible = true
	if p.jaw_mesh:
		p.jaw_mesh.visible = true
	for k in ["mi", "wmi", "jaw_mi"]:
		var mi = p.fine.get(k)
		if mi != null and is_instance_valid(mi):
			p.draw_with.erase(mi)
			mi.queue_free()
	p.fine = {}

## A fine voxel's colour in the look: his skin (lit as the muscles under it shade it), or the
## colour of the voxel it lies on where that is not skin (his loincloth, a strap).
static func _own(p: VoxelPart, j: int, k: float, sk_lin: Color, beast := false, paint := 0, d := {}) -> Color:
	var kd: int = p.kinds[j]
	# (A man's skin his own, lit the same all over; a beast's hide, scales or shell as it is
	# marked, voxel by voxel, BeastStyle; what a giant has on him his build's, Physique.)
	var c := sk_lin * SKIN_K if not beast and (kd == 0 or kd >= 6) else p.colors[j].srgb_to_linear()
	var pal: Array = d.get("palette", [])
	var cloth: Array = d.get("cloth", [])
	if paint & OWN_COLOUR:
		c = Color8((paint >> 16) & 255, (paint >> 8) & 255, paint & 255).srgb_to_linear()
	elif paint > 0 and paint <= pal.size():
		var e: Array = pal[paint - 1]
		var rgb := Color(float(e[0]), float(e[1]), float(e[2]))
		c = Color(sk_lin.r * rgb.r, sk_lin.g * rgb.g, sk_lin.b * rgb.b) * SKIN_K if int(e[4]) == 1 else rgb.srgb_to_linear()
	elif kd == 1 and cloth.size() >= 4:
		c = Color(float(cloth[0]), float(cloth[1]), float(cloth[2])).srgb_to_linear()
	return Color(c.r * k, c.g * k, c.b * k).linear_to_srgb()

## As it is drawn now: marked since the look was made (blood, a burn, a scar, the sand), the mark.
static func _color(p: VoxelPart, s: int, j: int) -> Color:
	var fine: Dictionary = p.fine
	if j < 0:
		return (fine.own as PackedColorArray)[s]
	var base: Dictionary = fine.base
	if base.has(j) and p.colors[j] != base[j]:
		var k: float = (fine.shade as PackedFloat32Array)[s]
		# Blood and nothing else on it: his own skin under the blood, as much of it as there is.
		var b0: Color = base[j]
		var t := _toward(b0, p.colors[j], VoxelPart.SMEAR)
		if t > 0.0 and _near(b0.lerp(VoxelPart.SMEAR, t), p.colors[j]):
			var bl := BLOOD.srgb_to_linear()
			var own: Color = (fine.own as PackedColorArray)[s]
			return own.lerp(Color(bl.r * k, bl.g * k, bl.b * k).linear_to_srgb(), t)
		var c := p.colors[j].srgb_to_linear()
		return Color(c.r * k, c.g * k, c.b * k).linear_to_srgb()
	return (fine.own as PackedColorArray)[s]

static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.03

static func _custom(p: VoxelPart, s: int, j: int, g: Vector2) -> Color:
	var cells: PackedInt32Array = p.fine.cells
	var k: int = p.kinds[j] if j >= 0 else 0
	var d: Dictionary = p.fine.get("d", {})
	var paint := cells[s * CELL + 8]
	var pal: Array = d.get("palette", [])
	var cloth: Array = d.get("cloth", [])
	if paint & OWN_COLOUR:
		k = (paint >> 24) & 63
	elif paint > 0 and paint <= pal.size():
		k = int(pal[paint - 1][3])
	elif k == 1 and cloth.size() >= 4:
		k = int(cloth[3])
	elif not p.fine.get("beast", false) and k >= 6:
		k = 0   # (a man's skin, over a voxel inside him)
	var c := VoxelPart.kind_data(0 if k == 1 else k, cells[s * CELL + 7], 0)
	c.g = g.x
	c.b = g.y
	# Fresh blood on it (and nothing else): wet, as much as there is blood, unless it burns.
	if g.x <= 0.0 and j >= 0:
		var b0 = (p.fine.base as Dictionary).get(j)
		if b0 != null and p.colors[j] != b0:
			var t := _toward(b0, p.colors[j], VoxelPart.SMEAR)
			if t > 0.12 and _near((b0 as Color).lerp(VoxelPart.SMEAR, t), p.colors[j]):
				c.g = -WET_SMEAR * t
	return c

## `xf` (the part's voxels as a look draws them) with those under the skin not drawn, nor those a
## wound bared (drawn as their eight cells).
static func masked(p: VoxelPart, xf: Array) -> Array:
	var hid: PackedByteArray = p.fine.get("hid", PackedByteArray())
	if xf.size() != hid.size():
		return xf
	var out := xf.duplicate()
	var wound: Dictionary = p.fine.wound
	for i in hid.size():
		if hid[i] == 1 or wound.has(i):
			out[i] = Transform3D(Basis().scaled(Vector3.ZERO), (out[i] as Transform3D).origin)
	return out

## The part's voxels shown or hidden (a blow knocking some out, one put back): the fine voxels over
## them with them, and the wound's cells round them.
static func shown(p: VoxelPart, indices: Array, on: bool) -> void:
	var fine: Dictionary = p.fine
	var of: Dictionary = fine.of
	var mm: MultiMesh = fine.get("mm")
	var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	var near := {}
	for i in indices:
		if i < 0 or i >= p.fx.size():
			continue
		near[i] = true
		for dd in VoxelPart.AO_FACES:
			var q: Vector3i = Vector3i(p.fx[i], p.fy[i], p.fz[i]) + (dd[0] as Vector3i)
			var k := p._cell(q.x, q.y, q.z)
			if k >= 0:
				near[k] = true
		if mm == null or not of.has(i):
			continue
		var up: bool = on and p.alive[i] == 1
		for s in (of[i] as Array):
			var at := _slot(fine, s)
			(at[0] as MultiMesh).set_instance_transform(at[1], at[2] if up else none)
	if fine.has("far_mm"):
		fine.band_was = INF
	# What a wound bares (or a voxel put back covers again).
	# (Bared, a voxel wholly inside him is drawn as its cells, as any other.)
	for i in near:
		if p.alive[i] == 1 and _open(p, i):
			_expose(p, i)
		elif fine.wound.has(i):
			_cover(p, i)

## An alive voxel with a dead one of the part beside it (a face open on the wound).
static func _open(p: VoxelPart, i: int) -> bool:
	if int((p.fine.code as PackedInt32Array)[i]) == 0:
		return false
	var c := Vector3i(p.fx[i], p.fy[i], p.fz[i])
	for dd in VoxelPart.AO_FACES:
		var q: Vector3i = c + (dd[0] as Vector3i)
		var k := p._cell(q.x, q.y, q.z)
		if k >= 0 and p.alive[k] == 0:
			return true
	return false

## The wound's own drawing: each voxel it bares as its eight half-size cells (their slots in it).
static func _wound_mm(p: VoxelPart) -> MultiMesh:
	var fine: Dictionary = p.fine
	var wm = fine.get("wmm")
	if wm != null:
		return wm
	if not _drawing():
		return null
	wm = MultiMesh.new()
	wm.transform_format = MultiMesh.TRANSFORM_3D
	wm.use_colors = true
	wm.use_custom_data = true
	wm.mesh = _box(fine.fsz)
	wm.instance_count = 8 * clampi(p.fx.size() / 4, 16, 600)
	wm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = wm
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.top_level = true
	mi.custom_aabb = (fine.mi as MultiMeshInstance3D).custom_aabb if fine.has("mi") else AABB()
	wm.custom_aabb = mi.custom_aabb
	p.add_child(mi)
	p.draw_with.append(mi)
	mi.global_transform = p.global_transform
	mi.transparency = p.see_through
	fine.wmm = wm
	fine.wmi = mi
	return wm

## Voxel `i` bared by a wound: drawn as its cells as deep in him as they lie (skin, fat, flesh,
## organ or bone), the box it is drawn as (if any) put away.
static func _expose(p: VoxelPart, i: int) -> void:
	var fine: Dictionary = p.fine
	var wound: Dictionary = fine.wound
	if wound.has(i):
		return
	var slot := -1
	var free: Array = fine.wfree
	if not free.is_empty():
		slot = free.pop_back()
	else:
		slot = int(fine.wn)
		fine.wn = slot + 1
	wound[i] = slot
	if int((fine.hid as PackedByteArray)[i]) == 0:
		# A voxel drawn as it is (wholly inside him): drawn as its cells now.
		if p.shape_xf.size() > i:
			p.shape_xf[i] = Transform3D(Basis().scaled(Vector3.ZERO), (p.shape_xf[i] as Transform3D).origin)
		if p.mm != null:
			p.mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_write_wound(p, i)

## Voxel `i` no longer bared (put back, or gone itself): its cells taken away, its box as before.
static func _cover(p: VoxelPart, i: int) -> void:
	var fine: Dictionary = p.fine
	var wound: Dictionary = fine.wound
	if not wound.has(i):
		return
	var slot: int = wound[i]
	wound.erase(i)
	(fine.wfree as Array).append(slot)
	var wm: MultiMesh = fine.get("wmm")
	if wm != null and slot * 8 + 8 <= wm.instance_count:
		var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
		for k in 8:
			wm.set_instance_transform(slot * 8 + k, none)
	if int((fine.hid as PackedByteArray)[i]) == 0 and p.shape_xf.size() > i:
		p.shape_xf[i] = mapped(p, fine.d, p.local_positions()[i])
		if p.mm != null and p.alive[i] == 1:
			p.mm.set_instance_transform(i, p.drawn_xf(i))

## The colour of a bared voxel's cell `k` (0..7), `code` deep: the skin as the skin is drawn, the
## fat under it, then what the voxel is (flesh in fibres, an organ, bone), each cell a shade of its own.
static func wound_color(p: VoxelPart, i: int, k: int, code: int) -> Color:
	var fine: Dictionary = p.fine
	var h := float(absi(hash(Vector2i(i, k))) % 1000) / 1000.0
	# An old wound's rim, healed: the dent in the pink of the scar, no flesh open in it.
	if p.scarred.has(i):
		return p.colors[i].lightened(0.12).darkened(0.05 * h)   # (pale, shiny: healed long since)
	# Blood over the wound: on the skin as on the voxel, on the flesh cut open a little less (the
	# layers still show through it).
	var blood := 0.0
	var base = (fine.base as Dictionary).get(i)
	if base != null and p.colors[i] != base:
		blood = _toward(base, p.colors[i], VoxelPart.SMEAR)
	var c := _layer(p, i, k, code, h)
	# (Bone keeps its ivory under the blood: it shows in the cut.)
	c = c.lerp(BLOOD, blood * (1.0 if code == 1 else (0.2 if p.kinds[i] == 6 else 0.5)))
	# The lips of the cut (the skin it opened): fresh blood along them, darker in spots.
	if code == 1:
		c = c.lerp(FRESH if h > 0.3 else CLOT, 0.7 + 0.2 * h)
	return c

## How far colour `b` has gone from `a` toward `t` (0..1).
static func _toward(a: Color, b: Color, t: Color) -> float:
	var d := Vector3(t.r - a.r, t.g - a.g, t.b - a.b)
	var m := Vector3(b.r - a.r, b.g - a.g, b.b - a.b)
	var l2 := d.length_squared()
	return clampf(m.dot(d) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0

static func _layer(p: VoxelPart, i: int, k: int, code: int, h: float) -> Color:
	var fine: Dictionary = p.fine
	match code:
		1:
			var sk: Color = fine.sk
			var c := sk * SKIN_K * (0.94 + 0.06 * h) if p.kinds[i] == 0 and not fine.get("beast", false) else ((fine.base as Dictionary).get(i, p.colors[i]) as Color).srgb_to_linear()
			return c.linear_to_srgb()
		2:
			return FAT.darkened(0.12 * h)
	var kind: int = p.kinds[i]
	if kind == 0 or kind == 1 or kind == 2 or kind == 8 or kind == 10 or kind == 11:
		# Under the skin (a hide, scales, a shell) of a voxel that is skin: the muscle, in its fibres.
		var stripe := 0.86 if ((k & 1) + ((k >> 2) & 1)) % 2 == 0 else 1.05
		return Color(MUSCLE.r * stripe * (0.92 + 0.16 * h), MUSCLE.g * stripe * (0.9 + 0.2 * h), MUSCLE.b * stripe * (0.9 + 0.2 * h))
	var own := p.colors[i]
	if kind == 6:
		return BONE.darkened(0.08 * h)   # bone: ivory, whatever blood ran over the voxel
	if p.organ.size() > i and p.organ[i] != 0:
		return own.lightened(0.05 * h) if h > 0.5 else own.darkened(0.08 * h)
	var st := 0.88 if ((k & 1) + ((k >> 2) & 1)) % 2 == 0 else 1.04
	return Color(own.r * st * (0.92 + 0.12 * h), own.g * st * (0.92 + 0.12 * h), own.b * st * (0.92 + 0.12 * h), 1.0)

static func _write_wound(p: VoxelPart, i: int) -> void:
	var fine: Dictionary = p.fine
	var slot: int = fine.wound[i]
	var wm := _wound_mm(p)
	if wm == null:
		return
	if slot * 8 + 8 > wm.instance_count:
		_grow(p)
		wm = fine.wmm
	wm.visible_instance_count = maxi(wm.visible_instance_count, mini(wm.instance_count, int(fine.wn) * 8))
	var code: int = (fine.code as PackedInt32Array)[i]
	var fsz: float = fine.fsz
	var c := p.local_positions()[i]
	var g: Vector2 = p.glowing.get(i, Vector2.ZERO)
	var bent := _bent_of(p, i)
	var healed := p.scarred.has(i)
	for k in 8:
		var cc := (code >> (2 * k)) & 3
		var at := c + (Vector3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1)) - Vector3(0.5, 0.5, 0.5)) * fsz
		var t := mapped(p, fine.d, at, 0.97 if cc == 1 else 1.0)
		wm.set_instance_transform(slot * 8 + k, (bent * t) if cc != 0 else Transform3D(Basis().scaled(Vector3.ZERO), t.origin))
		wm.set_instance_color(slot * 8 + k, wound_color(p, i, k, cc))
		var kd := 0 if cc == 1 else (9 if cc == 2 or p.kinds[i] <= 2 else int(p.kinds[i]))
		var cu := VoxelPart.kind_data(kd, 0, 0)
		# Wet (unless it burns, or healed long since).
		cu.g = g.x if g.x > 0.0 or healed else -(WET_BONE if kd == 6 else float(WET[cc]))
		cu.b = g.y
		wm.set_instance_custom_data(slot * 8 + k, cu)

## The wound's drawing made larger (its cells written again).
static func _grow(p: VoxelPart) -> void:
	var fine: Dictionary = p.fine
	var wm: MultiMesh = fine.wmm
	var want := wm.instance_count * 2
	wm.instance_count = want
	wm.visible_instance_count = mini(want, int(fine.wn) * 8)
	for j in fine.wound:
		_write_wound_slot_only(p, j)

static func _write_wound_slot_only(p: VoxelPart, j: int) -> void:
	var fine: Dictionary = p.fine
	var wm: MultiMesh = fine.wmm
	if int(fine.wound[j]) * 8 + 8 <= wm.instance_count:
		_write_wound(p, j)

## Where a bared voxel's cells are drawn while the limb is bent at a break (part-local).
static func _bent_of(p: VoxelPart, i: int) -> Transform3D:
	if p.dangle_mm == null or p.kink.is_empty():
		return Transform3D()
	var lp := p.local_positions()[i]
	return p._bent(Transform3D(Basis(), lp), p._bend_geom()) * Transform3D(Basis(), -lp)

## The part's voxels coloured again (blood, a burn, the look): the fine voxels over them follow a
## change that is not the look's own, and the wound's cells too.
static func colored(p: VoxelPart, indices: Array) -> void:
	var fine: Dictionary = p.fine
	var mm: MultiMesh = fine.get("mm")
	if mm == null:
		return
	var of: Dictionary = fine.of
	var wound: Dictionary = fine.wound
	var na: PackedFloat32Array = fine.get("na", PackedFloat32Array())
	for i in indices:
		if of.has(i):
			var g: Vector2 = p.glowing.get(i, Vector2.ZERO)
			for s in (of[i] as Array):
				var at := _slot(fine, s)
				var col := _color(p, s, i)
				if s < na.size():
					col.a = na[s]   # (the way it faces: FineSmooth)
				(at[0] as MultiMesh).set_instance_color(at[1], col)
				(at[0] as MultiMesh).set_instance_custom_data(at[1], _custom(p, s, i, g))   # (wet with blood)
		if wound.has(i):
			_write_wound_glow(p, i, true)

## A bruising blow swells: the skin over it raised, out from the bone toward where the blow fell,
## and its fine voxels a little larger, as much as the blow was hard (`k`, of a voxel), up to a
## limit. Only how the skin is drawn: what is struck and what is cut is the part's voxels, as they
## were (a swollen thigh is cut off as easily as any other).
const SWELL_MAX := 1.1
static func swell(p: VoxelPart, lp: Vector3, r: float, k: float) -> void:
	var fine: Dictionary = p.fine
	if fine.get("mm") == null or fine.get("beast", false) or r <= 0.0:
		return
	if p.dangle_mm != null and not p.kink.is_empty():
		return   # (a limb drawn bent at a break: its skin is laid round the bend, not here)
	if not fine.has("xf0"):
		# (The layout's places are shared by every man of the build: his own copy, to swell.)
		fine.xf0 = fine.xf
		fine.xf = (fine.xf as Array).duplicate()
		fine.swell = {}
	var g := p.grid
	var ax := 0 if g.x >= g.y and g.x >= g.z else (1 if g.y >= g.z else 2)
	var n := lp
	n[ax] = 0.0
	if n.length_squared() < 1e-8:
		return
	n = n.normalized()
	var vox := p.vf * p.part_scale
	var x0s: Array = fine.xf0
	var xs: Array = fine.xf
	var sw: Dictionary = fine.swell
	var of: Dictionary = fine.of
	for i in p.voxels_within(lp, r):
		if not of.has(i):
			continue
		for s in (of[i] as Array):
			var x0: Transform3D = x0s[s]
			var f := clampf(1.0 - x0.origin.distance_to(lp) / r, 0.0, 1.0)
			if f <= 0.0:
				continue
			f = f * f * (3.0 - 2.0 * f)
			var w := minf(SWELL_MAX, float(sw.get(s, 0.0)) + k * f)
			sw[s] = w
			xs[s] = Transform3D(x0.basis.scaled(Vector3.ONE * (1.0 + 0.3 * w)), x0.origin + n * w * vox)
			if p.alive[i] == 1:
				var at := _slot(fine, s)
				(at[0] as MultiMesh).set_instance_transform(at[1], at[2])

## Fire or poison working on voxel `i` (VoxelPart._set_status): the fine voxels over it glow too.
static func status(p: VoxelPart, i: int, g: Vector2) -> void:
	var fine: Dictionary = p.fine
	var mm: MultiMesh = fine.get("mm")
	if mm == null:
		return
	var of: Dictionary = fine.of
	if of.has(i):
		for s in (of[i] as Array):
			var at := _slot(fine, s)
			(at[0] as MultiMesh).set_instance_custom_data(at[1], _custom(p, s, i, g))
	if fine.wound.has(i):
		_write_wound_glow(p, i)

## A wound's cells as the fire or the poison on it changes (`paint` false), or the colour of the
## voxel it bares (blood on it, a burn charring it: `paint`): their shading, and their colours with
## `paint`; where they lie as it was. (Written whole, each burning voxel's wound as the fire went
## out over a limb was a frame's hitch: user, the game stuttered with the fire.)
static func _write_wound_glow(p: VoxelPart, i: int, paint := false) -> void:
	var fine: Dictionary = p.fine
	var wm = fine.get("wmm")
	var slot: int = fine.wound[i]
	if wm == null or slot * 8 + 8 > (wm as MultiMesh).instance_count:
		_write_wound(p, i)
		return
	var code: int = (fine.code as PackedInt32Array)[i]
	var g: Vector2 = p.glowing.get(i, Vector2.ZERO)
	var healed := p.scarred.has(i)
	for k in 8:
		var cc := (code >> (2 * k)) & 3
		if paint:
			(wm as MultiMesh).set_instance_color(slot * 8 + k, wound_color(p, i, k, cc))
		var kd := 0 if cc == 1 else (9 if cc == 2 or p.kinds[i] <= 2 else int(p.kinds[i]))
		var cu := VoxelPart.kind_data(kd, 0, 0)
		cu.g = g.x if g.x > 0.0 or healed else -(WET_BONE if kd == 6 else float(WET[cc]))
		cu.b = g.y
		(wm as MultiMesh).set_instance_custom_data(slot * 8 + k, cu)

# ---------- A bone broken through: the skin bent with the limb ----------

## The limb is drawn bent at its break (VoxelPart._start_dangle): the fine voxels past the break
## drawn with the piece that swings, those over the bend laid round it as its own voxels are.
static func dangle_on(p: VoxelPart) -> void:
	var fine: Dictionary = p.fine
	var mm: MultiMesh = fine.get("mm")
	if mm == null or p.kink.is_empty() or fine.has("far_mm"):
		return
	var pv := p._dangle_pivot()
	var tip: Vector3 = p._across()[2]
	var cxf: Array = fine.xf
	var par: PackedInt32Array = fine.par
	var n := par.size()
	var fslot := PackedInt32Array()
	fslot.resize(n)
	var idx := []
	for s in n:
		fslot[s] = -1
		if ((cxf[s] as Transform3D).origin - pv).dot(tip) > 0.0:
			fslot[s] = idx.size()
			idx.append(s)
	if idx.is_empty():
		return
	var far := MultiMesh.new()
	far.transform_format = MultiMesh.TRANSFORM_3D
	far.use_colors = true
	far.use_custom_data = true
	far.mesh = mm.mesh
	far.instance_count = idx.size()
	var none := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	var rows := PackedFloat32Array()
	var ix := PackedInt32Array()
	for k in idx.size():
		var s: int = idx[k]
		var j: int = par[s]
		var t: Transform3D = cxf[s]
		far.set_instance_transform(k, t if j >= 0 and p.alive[j] == 1 else none)
		far.set_instance_color(k, mm.get_instance_color(s))
		far.set_instance_custom_data(k, mm.get_instance_custom_data(s))
		mm.set_instance_transform(s, none)
		var sb := (t.origin - pv).dot(tip)
		var off := t.origin - pv - tip * sb
		var cr := off.cross(tip)
		var bx := t.basis
		rows.append_array([bx.x.x, bx.y.x, bx.z.x, t.origin.x, bx.x.y, bx.y.y, bx.z.y, t.origin.y, bx.x.z, bx.y.z, bx.z.z, t.origin.z, sb, off.x, off.y, off.z, cr.x, cr.y, cr.z])
		ix.append_array([k, j])
	far.custom_aabb = mm.custom_aabb
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = far
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.top_level = true
	mi.custom_aabb = mm.custom_aabb
	mi.transparency = p.see_through
	p.add_child(mi)
	fine.far_mm = far
	fine.far_mi = mi
	fine.far_slot = fslot
	fine.rows = rows
	fine.ix = ix
	fine.band_was = INF

## Laid round the bend as the swing has it (VoxelPart._lay_bend): `g` the bend, `inv` the far
## piece's place undone, `nc` the C++ core (or null).
static func lay(p: VoxelPart, g: Array, inv: Transform3D, b: float, nc) -> void:
	var fine: Dictionary = p.fine
	var far: MultiMesh = fine.get("far_mm")
	if far == null:
		return
	var rows: PackedFloat32Array = fine.rows
	var ix: PackedInt32Array = fine.ix
	var was: float = fine.band_was
	if nc != null:
		nc.lay_band(far, rows, ix, p.alive, p.veil, g[0], g[2], g[1], b, was, g[7], g[5], g[3], g[4], inv)
	else:
		var layers := {}
		var cxf: Array = fine.xf
		var par: PackedInt32Array = fine.par
		var fslot: PackedInt32Array = fine.far_slot
		for s in par.size():
			var k := fslot[s]
			if k < 0:
				continue
			var j := par[s]
			if j < 0 or p.alive[j] == 0:
				continue
			var sb := rows[k * 19 + 12]
			if sb >= b and sb >= was:
				continue
			far.set_instance_transform(k, cxf[s] if sb >= b else inv * p._bent(cxf[s], g, layers))
	fine.band_was = b
	# The wound's cells past the break, bent with it.
	for i in fine.wound:
		_write_wound(p, i)

## The limb straight again (VoxelPart._stop_dangle): the fine voxels back in the part's own drawing.
static func dangle_off(p: VoxelPart) -> void:
	var fine: Dictionary = p.fine
	if not fine.has("far_mm"):
		return
	var mm: MultiMesh = fine.get("mm")
	var par: PackedInt32Array = fine.par
	var cxf: Array = fine.xf
	var fslot: PackedInt32Array = fine.far_slot
	if mm != null:
		for s in par.size():
			if fslot[s] >= 0:
				var j := par[s]
				mm.set_instance_transform(s, cxf[s] if j >= 0 and p.alive[j] == 1 else Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var mi = fine.get("far_mi")
	if mi != null and is_instance_valid(mi):
		mi.queue_free()
	for k in ["far_mm", "far_mi", "far_slot", "rows", "ix", "band_was"]:
		fine.erase(k)
	for i in fine.wound:
		_write_wound(p, i)

# ---------- Armour on him ----------

## Where a plate laid at `at` on the part's box (part-local) is drawn on the man of the build: the
## box under it mapped onto him (k_at), the plate turned to lie flat on him there, a tile as thick
## as armour (`thick` of a cube), as far off him as it was off the box. A cube cell of armour laid
## round a man of rounded muscle drew him a box of plates; tiles lie on him as a cuirass does.
const PLATE_THICK := 0.45
static func plate_at(p: VoxelPart, at: Vector3) -> Transform3D:
	var d: Dictionary = p.fine.get("d", {})
	var r := Vector2(at.x, at.z).length()
	if d.is_empty():
		return Transform3D(Basis(), at)
	var cell := p.vf * p.part_scale * float(Data.body_res)   # an armour plate's cube
	var h := Vector3(p.grid) * p.vf * p.part_scale * 0.5
	var ang := atan2(at.z, at.x)
	var cs := absf(cos(ang))
	var sn := absf(sin(ang))
	var rb := minf(h.x / cs if cs > 0.0001 else INF, h.z / sn if sn > 0.0001 else INF)
	var k := k_at(p, d, at)
	var tang := clampf(k * 1.12, 0.75, 1.5)
	# On the top of the part (the shoulders, the top of a limb) or under it: a tile lying flat on
	# it, over where he is there (turned round his line, plates on his shoulders stood up like teeth).
	var over := at.y - h.y
	var under := -h.y - at.y
	if (over > -cell * 0.25 or under > -cell * 0.25) and r < rb + maxf(over, under):
		var y := at.y - signf(at.y) * cell * (1.0 - PLATE_THICK) * 0.5
		return Transform3D(Basis.from_scale(Vector3(tang, PLATE_THICK, tang)), Vector3(at.x * k, y, at.z * k))
	if r < 0.0001:
		return Transform3D(Basis(), at)
	var dir := Vector3(at.x, 0.0, at.z) / r
	var b := Basis(Vector3.UP, atan2(dir.x, dir.z))
	if r <= rb - cell * 0.25:
		return Transform3D(b * Basis.from_scale(Vector3(tang, 1.04, PLATE_THICK)), Vector3(dir.x * r * k, at.y, dir.z * r * k))
	# (A plate a cube off the box: its inner face on the box; a layer further out stays further.)
	var off := maxf(0.0, r - rb - cell * 0.5)
	# Turned to his slope there: where he narrows (his shoulders up to his neck, his waist, a
	# forearm to the wrist) a tile stood straight up stood out of him like a tooth.
	var dy := cell * 0.5
	var s := rb * (k_at(p, d, at + Vector3(0.0, dy, 0.0)) - k_at(p, d, at - Vector3(0.0, dy, 0.0))) / (2.0 * dy)
	var al := clampf(atan(-s), -1.1, 1.1)
	var n := Vector3(dir.x * cos(al), sin(al), dir.z * cos(al))
	var on := Vector3(dir.x * rb * k, at.y, dir.z * rb * k) + n * (cell * PLATE_THICK * 0.5 + off)
	return Transform3D(b * Basis(Vector3.RIGHT, -al) * Basis.from_scale(Vector3(tang, 1.04 / cos(al), PLATE_THICK)), on)
