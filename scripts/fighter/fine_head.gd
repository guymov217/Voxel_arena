class_name FineHead
extends RefCounted
## The fine head (the strong look; drawing only): a man's head sculpted in voxels three to each of
## the body's (tools/gen_fine_head.py -> data/fine_head.json), so his face is a face, not a box: a
## rounded skull, the brow over sockets with lidded eyes in them, a nose, cheekbones, lips, a jaw
## narrowing to the chin, ears (user: the faces looked like the block game's; voxels still, but a
## man's). Every fine voxel lies over one of the head's own: it is drawn while that one is alive,
## in its own colour (his skin, his hair, an eye's white, a lip) unless that one was marked after
## the look was made (blood, a burn, a scar: then in that one's colour, so a wound shows as it
## would). The head's own voxels under the shell are not drawn while it is on; those wholly inside
## it still are, and show through a wound. The face's pieces he chose (Physique.FACES), a bot's
## stubble and scars, a blink, a grimace and a mouth that talks are drawn on it fine.

const FILE := "res://data/fine_head.json"
static var _tpl := {}
static var _giants := {}   # a giant's own head (tools/gen_fine_giant_heads.py): kind -> template

## A giant's head (the Cyclops', the Minotaur's...), read the first time one is drawn; empty if
## there is none.
static func giant_template(kind: String) -> Dictionary:
	if not _giants.has(kind):
		var t := {}
		var path := "res://data/fine_head_%s.json" % kind
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				t = d
		_giants[kind] = t
	return _giants[kind]
static var _mesh := {}   # fine voxel size -> its box

static func template() -> Dictionary:
	if _tpl.is_empty() and FileAccess.file_exists(FILE):
		var fl := FileAccess.open(FILE, FileAccess.READ)
		if fl:
			var d = JSON.parse_string(fl.get_as_text())
			if d is Dictionary:
				_tpl = d
	return _tpl

# The template's feature codes (gen_fine_head.FEAT) and what may cover a cell.
enum {SKIN, WHITE, IRIS, PUPIL, LID, BROW, LIP, LIP_LINE, NOSTRIL, SHADE, BLUSH, LIGHT, EAR_IN, LID_LOW, HAIR}
const CAP := 1
const CAP_RECEDE_OFF := 2
const NAPE := 4
const LONG := 8
const SIDE := 16
const JAW := 32
const CHIN := 64
const LIP_TOP := 128
const GOATEE := 256
const HAIR_EXTRA := 512   # (a hair cell of a knot, a braid, a fall: kept on a receding man)

## The man bald and each hairstyle of the arena's day sitting on him (user): their hair is the
## template's own cells for it ("hairs", tools/gen_fine_head.py), round his scalp as his head is
## shaped. One he wears (a "hair_" piece) drawn so; one no longer offered taken as the nearest of
## these (an old save's). A bot one of them by his name, now and then none (shaved).
const STYLES := ["hair_crop", "hair_curls_top", "hair_curly", "hair_long", "hair_braids", "hair_suebian", "hair_topknot", "hair_bun"]
const RETIRED := {"hair_mohawk": "hair_crop", "hair_spikes": "hair_curls_top", "hair_ponytail": "hair_long"}
const BOT_STYLES := ["hair_crop", "hair_crop", "hair_crop", "hair_curls_top", "hair_curls_top", "hair_curls_top", "hair_curly", "hair_long", "hair_braids", "hair_suebian", "hair_topknot", "hair_bun"]

const DARK := Color(0.07, 0.05, 0.05)
const MOUTH := Color(0.16, 0.05, 0.05)
const TEETH := Color(0.93, 0.91, 0.84)
const TONGUE := Color(0.86, 0.36, 0.42)
const LIP_C := Color(0.6, 0.33, 0.3)
const WHITE_C := Color(0.96, 0.95, 0.9)
const IRIS_C := Color(0.3, 0.19, 0.11)
const PUPIL_C := Color(0.05, 0.04, 0.04)
const GOLD := Color(0.95, 0.75, 0.25)
const HAIR_KIND := 2

## The body's voxel material for voxels a third its size: each box's rim and corners shaded less
## (at the body's strength every small box's dark rim drew a grid over the face). Follows the
## corner shading option (VoxelPart.set_ao) as the body's does.
const EDGE_DARK := 0.0
const AO_K := 0.35
static var _mat: ShaderMaterial
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = VoxelPart.body_material().duplicate()
		_mat.set_shader_parameter("edge_dark", EDGE_DARK)
		# (Nor the rim of light round every small box: it drew bright lines down the face.)
		_mat.set_shader_parameter("rim_amount", 0.03)
	_mat.set_shader_parameter("ao_strength", VoxelPart.ao_strength * AO_K)
	return _mat

## Drawn on the head of `f` (his look as it is painted now: his skin, his hair, his beard, the face
## pieces he chose), or taken off again (`on` false, or a head the template does not fit). `hs`:
## drawn this much smaller, down onto his neck (the new look's builds, FineBody.head_scale).
static func build(f, p: VoxelPart, on := true, hs := 1.0, giant := "") -> void:
	clear(p)
	var t := giant_template(giant) if giant != "" else template()
	if not on or t.is_empty() or p.missing or p.severed:
		return
	var g: Array = t.grid
	if p.grid != Vector3i(int(g[0]), int(g[1]), int(g[2])):
		return
	var res := int(t.res)
	var vox := p.vf * p.part_scale
	var fsz := vox / float(res)
	var look := _look(f, p)
	# The head's own voxels: those wholly inside the fine head drawn as they are, the rest not.
	var keep := {}
	for k in t.keep:
		keep[Vector3i(int(k[0]), int(k[1]), int(k[2]))] = true
	var xf: Array = p.shape_xf.duplicate() if p.shape_xf.size() == p.fx.size() else []
	if xf.is_empty():
		var lps := p.local_positions()
		xf.resize(p.fx.size())
		for i in p.fx.size():
			xf[i] = Transform3D(Basis(), lps[i])
	var hid := PackedByteArray()
	hid.resize(p.fx.size())
	var half := Vector3(p.grid) * vox * 0.5
	# (Smaller about the crown, which stays where it is: the chin comes up off the shoulders and
	# his neck shows under it. About the bottom of the head the chin sat on his trapezius: no neck.)
	var pivot := Vector3(0.0, half.y, 0.0)
	for i in p.fx.size():
		if hs != 1.0:
			var o0: Transform3D = xf[i]
			xf[i] = Transform3D(o0.basis.scaled(Vector3.ONE * hs), pivot + (o0.origin - pivot) * hs)
		if not keep.has(Vector3i(p.fx[i], p.fy[i], p.fz[i])):
			# (The neck the strong look draws down into the shoulders stays as it is drawn: the
			# fine head ends at the jaw.)
			var o: Transform3D = xf[i]
			if o.origin.y - o.basis.get_scale().y * vox * 0.5 < -p.half_ext.y:
				continue
			hid[i] = 1
			xf[i] = Transform3D(Basis().scaled(Vector3.ZERO), (xf[i] as Transform3D).origin)
	p.set_shape(xf)
	# The fine voxels (the face with the nose he chose).
	var cells: Array = t.cells if giant != "" else _cells_for(t, look.ids, String(look.get("style", "")))
	var n := cells.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var key := snappedf(fsz, 0.00001)
	if not _mesh.has(key):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * fsz * 1.04
		bm.material = material()
		_mesh[key] = bm
	mm.mesh = _mesh[key]
	mm.instance_count = n
	# A shade fuller than the box, as the strong look draws the head.
	var sc := Vector3(1.06, 1.04, 1.04)
	var par := PackedInt32Array()
	par.resize(n)
	var own := PackedColorArray()
	own.resize(n)
	var cxf: Array = []
	cxf.resize(n)
	var of := {}
	var front := {}
	for s in n:
		var c: Array = cells[s]
		var lp := (Vector3(float(c[0]), float(c[1]), float(c[2])) + Vector3(0.5, 0.5, 0.5)) * fsz - half
		var tr := Transform3D(Basis().scaled(sc * hs), pivot + (lp * sc - pivot) * hs)
		cxf[s] = tr
		var j := p._cell(int(c[6]), int(c[7]), int(c[8]))
		par[s] = j
		if j >= 0:
			if not of.has(j):
				of[j] = []
			of[j].append(s)
		own[s] = _color(c, look) if c.size() < 12 else _giant_color(c)
		# (The face's own cells, by where they sit on it: what the pieces and the moods draw on. Not
		# his hair's, over his brow.)
		if int(c[3]) != HAIR and (int(c[3]) != SKIN or float(c[2]) > 25.0):
			front[Vector2i(int(c[0]), int(c[1]))] = s
	var fine := {"mm": mm, "par": par, "own": own, "xf": cxf, "of": of, "front": front, "look": look, "cells": cells, "hid": hid, "hs": hs, "pivot": pivot, "giant": giant}
	# (His head's outline without his hair: a helmet or a hat sits on his head, the hair under it
	# tucked, tuck.)
	var head_xf := []
	for s in n:
		if int((cells[s] as Array)[3]) != HAIR:
			head_xf.append(cxf[s])
	var ol := _outline(head_xf, fsz * sc.x * hs)
	fine.wc = ol[0]
	fine.wtab = ol[1]
	# What each of the head's voxels is now: a later change to it (blood) shows through.
	var base := {}
	for j in of:
		base[j] = p.colors[j]
	fine.base = base
	for s in n:
		var j: int = par[s]
		var alive: bool = j >= 0 and p.alive[j] == 1
		mm.set_instance_transform(s, cxf[s] if alive else Transform3D(Basis().scaled(Vector3.ZERO), (cxf[s] as Transform3D).origin))
		mm.set_instance_color(s, own[s])
		var c: Array = cells[s]
		var kd := (HAIR_KIND if _hairy(c, look) else 0) if c.size() < 12 else int(c[11])
		mm.set_instance_custom_data(s, VoxelPart.kind_data(kd, int(c[9]), 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.top_level = true
	mi.custom_aabb = AABB(-half * 1.4, half * 2.8)
	mm.custom_aabb = mi.custom_aabb
	p.add_child(mi)
	fine.mi = mi
	p.draw_with.append(mi)
	p.fine = fine
	_paint(p)
	mi.global_transform = p.global_transform

## The face's cells with the nose he chose (Your gladiator: a "nose_" piece; the template's own
## nose, a broad one, without), each worked out once from what that nose changes of the face.
static var _nose_cells := {}
static var _hair_cells := {}
static func _cells_for(t: Dictionary, ids: Array, style := "") -> Array:
	var face := _nose_for(t, ids)
	var hairs: Dictionary = t.get("hairs", {})
	if style == "" or not hairs.has(style):
		return face
	# His hair over it (a receding man's temples bare: the cells over them not his).
	var rec := ids.has("hair_receding")
	var key := "%d|%s|%s" % [face.size(), style, rec]
	if _hair_cells.has(key) and (_hair_cells[key] as Array)[0] == face:
		return (_hair_cells[key] as Array)[1]
	var out := face.duplicate()
	for c in hairs[style]:
		if rec and (int(c[4]) & CAP_RECEDE_OFF) != 0 and (int(c[4]) & HAIR_EXTRA) == 0:
			continue
		out.append(c)
	_hair_cells[key] = [face, out]
	return out

static func _nose_for(t: Dictionary, ids: Array) -> Array:
	var nose := ""
	for id in ids:
		if String(id).begins_with("nose_"):
			nose = String(id).trim_prefix("nose_")
	var noses: Dictionary = t.get("noses", {})
	if nose == "" or not noses.has(nose):
		return t.cells
	if _nose_cells.has(nose):
		return _nose_cells[nose]
	var d: Dictionary = noses[nose]
	var drop := {}
	for k in d.drop:
		drop[Vector3i(int(k[0]), int(k[1]), int(k[2]))] = true
	var out := []
	for c in t.cells:
		if not drop.has(Vector3i(int(c[0]), int(c[1]), int(c[2]))):
			out.append(c)
	out.append_array(d.add)
	_nose_cells[nose] = out
	return out

## His head's outline seen from its middle, for what is worn on it (wrap): the farthest of its
## fine voxels out each way, SPH_AZ round by SPH_EL from under the chin to the crown.
const SPH_AZ := 32
const SPH_EL := 16
static func _outline(cxf: Array, cell: float) -> Array:
	var c := Vector3.ZERO
	for t in cxf:
		c += (t as Transform3D).origin
	c /= maxf(1.0, float(cxf.size()))
	var tab := PackedFloat32Array()
	tab.resize(SPH_AZ * SPH_EL)
	for t in cxf:
		var v: Vector3 = (t as Transform3D).origin - c
		var r := v.length()
		if r < 0.0001:
			continue
		var k := _bin(v / r)
		tab[k] = maxf(tab[k], r + cell * 0.5)
	# The ways no voxel lies (into the neck under the jaw): as far as the nearest way that has one.
	for pass_ in 8:
		var empty := false
		var nt := tab.duplicate()
		for el in SPH_EL:
			for az in SPH_AZ:
				var k := el * SPH_AZ + az
				if tab[k] > 0.0:
					continue
				var best := 0.0
				for d in [[0, 1], [0, -1], [1, 0], [-1, 0]]:
					var e2: int = el + int(d[0])
					if e2 < 0 or e2 >= SPH_EL:
						continue
					best = maxf(best, tab[e2 * SPH_AZ + posmod(az + int(d[1]), SPH_AZ)])
				nt[k] = best
				empty = empty or best <= 0.0
		tab = nt
		if not empty:
			break
	return [c, tab]

static func _bin(d: Vector3) -> int:
	var az := posmod(int(floorf((atan2(d.z, d.x) + PI) / TAU * SPH_AZ)), SPH_AZ)
	var el := clampi(int(floorf((asin(clampf(d.y, -1.0, 1.0)) + PI * 0.5) / PI * SPH_EL)), 0, SPH_EL - 1)
	return el * SPH_AZ + az

## Where a piece worn on the head laid at `at` (part-local, on the head's box) is drawn: moved in
## (or out) along the line from the head's middle to sit as far off the fine head as it was off the
## box: [place, size]. A helmet hugs the skull, a wreath the brow.
static func wrap(p: VoxelPart, at: Vector3) -> Array:
	var c: Vector3 = p.fine.wc
	var tab: PackedFloat32Array = p.fine.wtab
	var v := at - c
	var r := v.length()
	if r < 0.0001:
		return [at, 1.0]
	var d := v / r
	var rh := outline(p, d)
	var h := Vector3(p.grid) * p.vf * p.part_scale * 0.5
	var rb := INF
	for ax in 3:
		if absf(d[ax]) > 0.0001:
			var t := ((h[ax] if d[ax] > 0.0 else -h[ax]) - c[ax]) / d[ax]
			if t > 0.0:
				rb = minf(rb, t)
	if rh <= 0.0 or rb == INF:
		return [at, 1.0]
	var off := r - rb
	var nr := rh + off if off > -0.005 else r * rh / rb
	return [c + d * nr, clampf(nr / r, 0.75, 1.1)]

## How far out the fine head reaches along `d` from its middle: the farthest of the way's bin and
## those round it (a plate laid on it never sinks into the head between two).
static func outline(p: VoxelPart, d: Vector3) -> float:
	var tab: PackedFloat32Array = p.fine.wtab
	var k := _bin(d)
	var el := k / SPH_AZ
	var az := k % SPH_AZ
	var rh := 0.0
	for e2 in range(maxi(0, el - 1), mini(SPH_EL, el + 2)):
		for a2 in [az - 1, az, az + 1]:
			rh = maxf(rh, tab[e2 * SPH_AZ + posmod(a2, SPH_AZ)])
	return rh

## Taken off (the look that drew it puts the head's own voxels back: Physique.dress).
static func clear(p: VoxelPart) -> void:
	if p.fine.is_empty():
		return
	var mi = p.fine.get("mi")
	if mi != null and is_instance_valid(mi):
		p.draw_with.erase(mi)
		mi.queue_free()
	p.fine = {}

## `xf` (the part's voxels as a look draws them) with those under the fine shell not drawn.
static func masked(p: VoxelPart, xf: Array) -> Array:
	var hid: PackedByteArray = p.fine.get("hid", PackedByteArray())
	if xf.size() != hid.size():
		return xf
	var out := xf.duplicate()
	for i in hid.size():
		if hid[i] == 1:
			out[i] = Transform3D(Basis().scaled(Vector3.ZERO), (out[i] as Transform3D).origin)
	return out

## His colours and his kind of hair and beard, read off the head as the look painted it.
static func _look(f, p: VoxelPart) -> Dictionary:
	var at := Physique._face_at(p)
	var skin := Color(0.62, 0.42, 0.3)
	if at.has(Vector2i(0, 5)):
		skin = p.colors[at[Vector2i(0, 5)]]
	var crown := -1
	var g := p.grid
	for i in p.fx.size():
		if p.fy[i] == g.y - 1 and p.fx[i] == g.x / 2 and p.fz[i] == g.z / 2:
			crown = i
	var hair := Color(0.2, 0.13, 0.08)
	var bald := false
	if crown >= 0:
		hair = p.colors[crown]
		# A crown in his skin's own colour (or near it) is shaved.
		bald = _near(hair, skin, 0.16)
	var beard := 0
	var beard_c := hair
	# The hairstyle he wears, or none: bald.
	var style := Physique.hair_worn(p)
	style = String(RETIRED.get(style, style))
	if not STYLES.has(style):
		style = ""
	if f is Fighter and f.get("is_bot") and String(f.mods.get("look", "")) == "":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(f.display_name)) ^ int(f.slot) * 7919
		var hc: Color = Physique.HAIRS[rng.randi() % Physique.HAIRS.size()]
		var shaved := rng.randf() < 0.2
		beard = rng.randi() % 5
		hair = hc
		beard_c = hc
		bald = shaved
		if style == "" and not shaved:
			style = BOT_STYLES[rng.randi() % BOT_STYLES.size()]
	# The colour of hair he chose: on his crown, his brows and his beard (never read as a shaved
	# crown, a blond on a fair skin).
	var hc = Physique.hair_choice(f)
	if hc != null:
		hair = hc
		beard_c = hc
		bald = false
	var worn := Physique.beard_worn(p)
	if worn != "":
		beard = int(Physique.BEARD_PAINT.get(worn, 2))
		beard_c = hc if hc != null else (ArmorStyle.base_color(worn, {}, f.skin) if f is Fighter else hair)
	var ids: Array = (f.face_ids if f is Fighter else []).duplicate()
	if f is Fighter and f.is_bot and ids.is_empty():
		ids = _bot_ids(f)
	if beard == 0 and ids.has("face_stubble"):
		beard = 7
	var iris := IRIS_C
	if ids.has("eyes_blue"):
		iris = Physique.BLUE
	elif ids.has("eyes_green"):
		iris = Physique.GREEN
	elif ids.has("eyes_brown"):
		iris = Physique.BROWN
	var chosen = Physique.iris_choice(ids)
	if chosen != null:
		iris = chosen
	return {"skin": skin, "hair": hair, "bald": bald, "beard": beard, "beard_c": beard_c, "ids": ids, "iris": iris, "brow": hair.darkened(0.42) if not bald else skin.darkened(0.55), "style": style}

const BOT_EYES := ["eyes_angry", "eyes_tired", "eyes_scar", "eyes_blue", "eyes_green", "eyes_brown"]
const BOT_MOUTHS := ["mouth_stern", "mouth_snarl", "mouth_frown", "mouth_grimace", "mouth_gap", "mouth_smirk", "mouth_gold"]
## A bot's face pieces, as Physique._faces draws them (from his name and his place).
static func _bot_ids(f) -> Array:
	var ids := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(f.display_name)) ^ int(f.slot) * 104729
	# A fighter's looks only (a tongue out, buck teeth or crossed eyes on half the men he faced
	# made a joke of them: user, the faces should be a gladiator's).
	var eyes := BOT_EYES
	var mouths := BOT_MOUTHS
	if rng.randf() < 0.45:
		ids.append(eyes[rng.randi() % eyes.size()])
	if rng.randf() < 0.55:
		ids.append(mouths[rng.randi() % mouths.size()])
	if rng.randf() < 0.4:
		ids.append("bot_stubble")
	if rng.randf() < 0.22:
		ids.append("bot_scar_cheek" if rng.randf() < 0.5 else "bot_scar_lip")
	if rng.randf() < 0.3:
		ids.append("bot_brows_thick" if rng.randf() < 0.7 else "bot_unibrow")
	# A nose of his own, now and then (the broad one the rest).
	if rng.randf() < 0.55:
		ids.append(["nose_straight", "nose_roman", "nose_broken", "nose_small"][rng.randi() % 4])
	return ids

static func _near(a: Color, b: Color, d: float) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < d * 3.0

static func _hairy(c: Array, look: Dictionary) -> bool:
	if int(c[3]) == HAIR:
		return true
	return _beard_on(int(c[4]), int(look.beard))

static func _beard_on(bits: int, beard: int) -> bool:
	match beard:
		1, 7:
			return (bits & (JAW | CHIN | LIP_TOP)) != 0
		2:
			return (bits & (JAW | CHIN | LIP_TOP)) != 0
		3:
			return (bits & (GOATEE | LIP_TOP)) != 0
		4:
			return (bits & LIP_TOP) != 0
		5:
			return (bits & JAW) != 0 and (bits & CHIN) == 0
		6:
			return (bits & (JAW | CHIN)) != 0 and (bits & LIP_TOP) == 0
	return false

## A giant's fine voxel: its own colour, a shade of its own.
static func _giant_color(c: Array) -> Color:
	var rgb := int(c[10])
	var grain := 1.0 + (float(hash(Vector3i(int(c[0]), int(c[1]), int(c[2]))) % 1000) / 1000.0 - 0.5) * 0.06
	return Color(clampf(float((rgb >> 16) & 255) / 255.0 * grain, 0.0, 1.0), clampf(float((rgb >> 8) & 255) / 255.0 * grain, 0.0, 1.0), clampf(float(rgb & 255) / 255.0 * grain, 0.0, 1.0))

## A fine voxel's own colour in his look (before the face's pieces and his moods).
static func _color(c: Array, look: Dictionary) -> Color:
	var feat := int(c[3])
	var bits := int(c[4])
	var k := float(c[5])
	var skin: Color = look.skin
	var grain := 1.0 + (float(hash(Vector3i(int(c[0]), int(c[1]), int(c[2]))) % 1000) / 1000.0 - 0.5) * 0.06
	match feat:
		WHITE:
			return WHITE_C
		IRIS:
			return look.iris
		PUPIL:
			return PUPIL_C
		LID:
			return skin.darkened(0.34)
		LID_LOW:
			return skin.darkened(0.2)
		BROW:
			return look.brow
		LIP:
			return skin.lerp(LIP_C, 0.55)
		LIP_LINE:
			return skin.lerp(LIP_C, 0.5).darkened(0.58)
		NOSTRIL:
			return skin.darkened(0.55)
		SHADE:
			return skin.darkened(0.28)
		EAR_IN:
			return skin.darkened(0.12)
		HAIR:
			# His hair: its strands lighter and darker as the template combs it (a curl's top lit).
			var hc: Color = look.hair
			var hk := k * (1.0 + (grain - 1.0) * 2.0)
			return Color(clampf(hc.r * hk, 0.0, 1.0), clampf(hc.g * hk, 0.0, 1.0), clampf(hc.b * hk, 0.0, 1.0), 1.0)
	var col := skin
	if feat == BLUSH:
		col = Color(skin.r * 1.02, skin.g * 0.97, skin.b * 0.96)
	elif feat == LIGHT:
		col = skin.lightened(0.06)
	# (His scalp bare: the hair is his hairstyle's own cells over it.) A beard.
	var beard := int(look.beard)
	if beard > 0 and _beard_on(bits, beard):
		var kb := 0.35 if beard == 1 else (0.3 if beard == 7 else 0.88)
		col = col.lerp(look.beard_c, kb)
	return Color(clampf(col.r * k * grain, 0.0, 1.0), clampf(col.g * k * grain, 0.0, 1.0), clampf(col.b * k * grain, 0.0, 1.0), 1.0)

## The face's pieces and his mood drawn on its fine voxels: `mood` 1 his eyes shut (a blink), 2
## his face screwed up (hurt), 4 with it crying out, and `talk` 0..3 his mouth open as he speaks.
static func _paint(p: VoxelPart, mood := 0, talk := 0) -> void:
	var fine: Dictionary = p.fine
	if fine.is_empty() or String(fine.get("giant", "")) != "":
		return   # (a giant's face is its own: no man's eyes and mouth drawn on it)
	var look: Dictionary = fine.look
	var ids: Array = look.ids
	var cells: Array = fine.cells
	var own: PackedColorArray = fine.own
	var paint := {}
	var t := template()
	var res := int(t.res)
	var cx := float(p.grid.x * res) * 0.5
	var cy := float(p.grid.y * res) * 0.5
	var ex := float(t.eye[0])
	var ey := float(t.eye[1])
	var skin: Color = look.skin
	for key in fine.front:
		var s: int = fine.front[key]
		var c: Array = cells[s]
		var feat := int(c[3])
		var x := float(key.x) + 0.5 - cx
		var y := float(key.y) + 0.5 - cy
		var col = _mark(feat, x, y, ex, ey, ids, mood, talk, look)
		if col != null:
			paint[s] = col
	var mm: MultiMesh = fine.mm
	var par: PackedInt32Array = fine.par
	var base: Dictionary = fine.base
	fine.paint = paint
	for s in own.size():
		var j := par[s]
		var col: Color = paint.get(s, own[s])
		# (Marked since: blood, a burn, a scar on the voxel it lies on.)
		if j >= 0 and base.has(j) and p.colors[j] != base[j] and not p.get_meta("expr_saved", {}).has(j) and not p.get_meta("talk_saved", {}).has(j):
			col = p.colors[j]
		mm.set_instance_color(s, col)

## What a face piece or a mood draws on the face's fine voxel at (x, y) (fine voxels from the
## middle of the face; `feat` what it is), or null.
static func _mark(feat: int, x: float, y: float, ex: float, ey: float, ids: Array, mood: int, talk: int, look: Dictionary):
	var skin: Color = look.skin
	var eye: bool = feat == WHITE or feat == IRIS or feat == PUPIL or feat == LID or feat == LID_LOW
	var sx := 1.0 if x > 0.0 else -1.0
	var dx := x - sx * ex   # across the eye (+ toward his left)
	var dy := y - ey
	# His mood first: shut, or screwed up.
	if eye and (mood & 1 or mood & 2):
		if mood & 2 and dy > 0.6:
			return DARK
		return skin.darkened(0.25) if absf(dy) > 0.4 else skin.darkened(0.4)
	if mood & 2:
		if feat == BROW or (absf(absf(x) - ex) < 3.5 and dy > 1.6 and dy < 2.8):
			return DARK
		if talk == 0 and mood & 4:
			# Crying out: the mouth wide open, the upper teeth bared.
			if absf(x) < 3.0 and y < -7.6 and y > -12.0:
				return TEETH if y > -8.6 and absf(x) < 2.7 else MOUTH
		elif talk == 0 and (feat == LIP_LINE or feat == LIP) and y < -7.6 and y > -10.4:
			return TEETH if absf(x) < 2.6 and fposmod(x, 2.0) < 1.6 else MOUTH
	# His mouth as he talks.
	if talk > 0 and absf(x) < 3.0:
		if talk == 1 and feat == LIP_LINE and absf(x) < 1.6:
			return MOUTH
		if talk >= 2 and y < -8.0 and y > (-10.6 if talk == 2 else -11.4) and absf(x) < (2.2 if talk == 2 else 2.8):
			if talk == 3 and y > -8.8:
				return TEETH
			if talk == 3 and y < -10.4 and absf(x) < 1.6:
				return TONGUE
			return MOUTH
	for id in ids:
		match String(id):
			"eyes_wide":
				if feat == LID or feat == LID_LOW:
					return WHITE_C
			"eyes_side":
				if eye and feat != LID and feat != LID_LOW:
					var ax := dx - 0.9
					return PUPIL_C if absf(ax) < 0.55 and absf(dy) < 0.6 else (look.iris if absf(ax) < 1.25 and absf(dy) < 1.15 else WHITE_C)
			"eyes_cross":
				if eye and feat != LID and feat != LID_LOW:
					var ax2 := dx + 0.9 * sx
					return PUPIL_C if absf(ax2) < 0.55 and absf(dy) < 0.6 else (look.iris if absf(ax2) < 1.25 and absf(dy) < 1.15 else WHITE_C)
			"eyes_angry":
				# The brows down toward the nose.
				if feat == BROW and absf(x) > ex:
					return skin
				if absf(x) < ex + 0.5 and absf(x) > 1.6 and dy > 1.2 and dy < 2.6 - (absf(x) - 1.6) * 0.35:
					return look.brow
				if eye and dy > 0.7:
					return skin.darkened(0.22)
			"eyes_sleepy":
				if eye and dy > -0.1:
					return skin.darkened(0.22)
			"eyes_mad":
				if x < 0.0 and (feat == LID or feat == LID_LOW):
					return WHITE_C
				if x > 0.0 and eye and dy > -0.3:
					return skin.darkened(0.25)
			"eyes_wink":
				if x > 0.0 and eye:
					return skin.darkened(0.3) if absf(dy) < 0.6 else skin.darkened(0.12)
			"eyes_scar":
				if absf(x + ex - 1.0) < 0.6 and dy > -3.4 and dy < 3.6:
					return VoxelPart.SCAR
			"eyes_tired":
				if feat == LID_LOW or (eye and dy < -1.0):
					return skin.darkened(0.3)
			"mouth_gap":
				if feat == LIP_LINE and absf(x) < 2.6:
					return MOUTH if absf(x - 0.5) < 0.6 else TEETH
			"mouth_grin", "mouth_gold":
				if (feat == LIP_LINE or feat == SHADE) and y > -10.4 and y < -8.6 and absf(x) < 3.2:
					return (GOLD if String(id) == "mouth_gold" and absf(x - 1.5) < 0.6 else TEETH) if absf(x) < 2.8 else MOUTH
			"mouth_snarl":
				if (feat == LIP_LINE or feat == LIP) and y > -10.4 and y < -8.0 and absf(x) < 2.8:
					return TEETH if fposmod(x + 0.5, 2.0) < 1.2 else MOUTH
			"mouth_stern":
				if feat == LIP:
					return skin.lerp(LIP_C, 0.25).darkened(0.08)
				if feat == LIP_LINE:
					return skin.darkened(0.5)
			"mouth_shout":
				if absf(x) < 2.8 and y < -7.6 and y > -11.6:
					if y > -8.6:
						return TEETH
					return TONGUE if y < -10.6 and absf(x) < 1.6 else MOUTH
			"mouth_tongue":
				if absf(x) < 1.4 and y < -9.6 and y > -12.6:
					return TONGUE
			"mouth_toothless":
				if feat == LIP_LINE or (absf(x) < 2.6 and y < -8.6 and y > -10.6):
					return TEETH if absf(x - 1.0) < 0.5 and y > -9.6 else MOUTH
			"mouth_smirk":
				if feat == LIP_LINE and x < -0.5:
					return skin.lerp(LIP_C, 0.5)
				if x > 1.5 and x < 3.4 and y > -9.0 and y < -8.0:
					return skin.lerp(LIP_C, 0.5).darkened(0.45)
			"mouth_buck":
				if absf(x) < 1.1 and y > -10.4 and y < -9.0:
					return TEETH
			"mouth_frown":
				if (feat == SHADE or feat == LIP_LINE) and absf(x) > 2.0:
					return skin.lerp(LIP_C, 0.5).darkened(0.45)
				if absf(x) > 2.4 and absf(x) < 3.6 and y > -11.0 and y < -10.0:
					return skin.lerp(LIP_C, 0.5).darkened(0.45)
			"mouth_grimace":
				if absf(x) < 3.2 and y > -10.4 and y < -8.0:
					return TEETH if fposmod(x + 0.5, 2.0) < 1.3 else MOUTH
			"bot_scar_cheek", "face_scar_cheek":
				if x < -6.0 and x > -9.0 and absf(y - (-2.0 - (x + 6.0) * 1.2)) < 0.7:
					return VoxelPart.SCAR
			"bot_scar_lip", "face_scar_lip":
				if absf(x + 1.5) < 0.6 and y > -12.0 and y < -6.0:
					return VoxelPart.SCAR
			"bot_brows_thick", "face_brows_thick":
				if absf(absf(x) - ex) < 3.6 and dy > 1.6 and dy < 3.2:
					return look.brow
			"bot_unibrow", "face_unibrow":
				if absf(x) < ex and dy > 2.0 and dy < 3.0:
					return look.brow
			"face_scar_brow":
				# Down through his brow, over the lid and on under the eye.
				if absf(x - (ex + 0.6) - (dy - 1.0) * 0.18) < 0.55 and dy > -4.0 and dy < 4.2 and not (feat == WHITE or feat == IRIS or feat == PUPIL):
					return VoxelPart.SCAR
			"face_freckles":
				if not eye and absf(x) < ex + 3.5 and dy < -1.6 and dy > -7.5 and _speck(x, y) < 0.16:
					return skin.lerp(Physique.FRECKLE, 0.75)
			"face_woad":
				# The Britons' blue over his eyes and his brow.
				if not (feat == WHITE or feat == IRIS or feat == PUPIL) and dy > -2.6 and dy < 4.0:
					return Physique.WOAD.lerp(Physique.WOAD.lightened(0.2), 0.3 * _speck(x, y))
			"face_warpaint":
				# Black stripes down his cheeks from under the eyes.
				var ax3 := absf(absf(x) - ex)
				if not eye and ax3 < 2.6 and dy < -1.4 and dy > -7.5 and fposmod(ax3 + 2.6, 1.7) < 0.75:
					return DARK
			"face_ochre":
				if not (feat == WHITE or feat == IRIS or feat == PUPIL) and absf(dy) < 2.0:
					return Physique.OCHRE
			"face_tattoo":
				var tx := x - (ex + 4.2)
				if not eye and absf(tx) < 2.6 and dy > -8.0 and dy < 5.0 and fposmod(y + tx * 0.9, 2.4) < 0.8:
					return Physique.TATTOO
			"face_blush":
				if not eye and Vector2(absf(x) - (ex + 1.5), dy + 4.4).length() < 2.1:
					return skin.lerp(Physique.PINK, 0.55)
			"face_skull":
				# Bone white, the eyes in black sockets, a black nose, the mouth sewn shut.
				if Vector2(dx, dy * 1.15).length() < 2.7:
					return DARK
				if absf(x) < 1.5 and dy < -3.4 and dy > -6.6:
					return DARK
				if y > -10.4 and y < -8.0 and absf(x) < 4.0:
					return DARK if fposmod(x + 0.4, 1.6) < 0.6 or absf(y + 9.2) < 0.4 else Physique.BONE_PAINT
				return Physique.BONE_PAINT
			"face_clown":
				if eye:
					continue
				if Vector2(x, y - (ey - 5.0)).length() < 2.3:
					return Physique.CLOWN_RED
				if y > -10.8 and y < -7.6 and absf(x) < 5.2 - maxf(0.0, -9.2 - y) * 1.4:
					return Physique.CLOWN_RED
				if absf(dx) + absf(dy - 3.4) < 1.5:
					return Physique.BLUE
				if Vector2(absf(x) - (ex + 2.0), dy + 4.8).length() < 1.8:
					return Physique.PINK
				return Physique.CLOWN_WHITE
	return null

## A fleck now and then over the face (freckles, the woad's grain): the same each time.
static func _speck(x: float, y: float) -> float:
	return float(posmod(hash(Vector2i(int(floorf(x * 2.0)), int(floorf(y * 2.0))) + Vector2i(7, 13)), 1000)) / 1000.0

## The head's voxels shown or hidden (a blow knocking some out): the fine voxels over them with them
## (his hair tucked under a helmet or a hat stays so).
static func shown(p: VoxelPart, indices: Array, on: bool) -> void:
	var fine: Dictionary = p.fine
	var of: Dictionary = fine.of
	var mm: MultiMesh = fine.mm
	var cxf: Array = fine.xf
	var tucked: Dictionary = fine.get("tucked", {})
	for i in indices:
		if not of.has(i):
			continue
		for s in of[i]:
			mm.set_instance_transform(s, cxf[s] if on and p.alive[i] == 1 and not tucked.has(s) else Transform3D(Basis().scaled(Vector3.ZERO), (cxf[s] as Transform3D).origin))

## His hair under a helmet or a hat not drawn: a cell of it whose head voxel has a plate of one on it
## or next to it (`covered`: the plates' cells on him); what hangs out below (a fall, braids) stays,
## and as a helmet's plates are knocked off what they covered shows again. Drawing only.
static func tuck(p: VoxelPart, covered: Dictionary) -> void:
	var fine: Dictionary = p.fine
	if fine.is_empty() or not fine.has("mm") or String(fine.get("giant", "")) != "":
		return
	var cells: Array = fine.cells
	var par: PackedInt32Array = fine.par
	var mm: MultiMesh = fine.mm
	var cxf: Array = fine.xf
	var was: Dictionary = fine.get("tucked", {})
	var now := {}
	if not covered.is_empty():
		for s in cells.size():
			var c: Array = cells[s]
			if int(c[3]) != HAIR:
				continue
			# (The head voxel it lies over, in the helmet's cells: the plates are laid on the part's
			# own voxels, the fine head's cells over its fine ones.)
			var v := Vector3i(int(c[6]) * p.dims.x / p.grid.x, int(c[7]) * p.dims.y / p.grid.y, int(c[8]) * p.dims.z / p.grid.z)
			var under := false
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						if covered.has(v + Vector3i(dx, dy, dz)):
							under = true
			if under:
				now[s] = true
	fine["tucked"] = now
	for s in cells.size():
		if not (now.has(s) or was.has(s)):
			continue
		var j: int = par[s]
		var alive: bool = j >= 0 and p.alive[j] == 1
		mm.set_instance_transform(s, cxf[s] if alive and not now.has(s) else Transform3D(Basis().scaled(Vector3.ZERO), (cxf[s] as Transform3D).origin))

## The head's voxels coloured again (blood, a burn, the look): the fine voxels over them follow a
## change that is not the look's own.
static func colored(p: VoxelPart, indices: Array) -> void:
	var fine: Dictionary = p.fine
	var of: Dictionary = fine.of
	var mm: MultiMesh = fine.mm
	var own: PackedColorArray = fine.own
	var paint: Dictionary = fine.get("paint", {})
	var base: Dictionary = fine.base
	var expr: Dictionary = p.get_meta("expr_saved", {})
	var talking: Dictionary = p.get_meta("talk_saved", {})
	for i in indices:
		if not of.has(i):
			continue
		var marked: bool = base.has(i) and p.colors[i] != base[i] and not expr.has(i) and not talking.has(i)
		for s in of[i]:
			mm.set_instance_color(s, p.colors[i] if marked else paint.get(s, own[s]))

## His mood and his talking mouth drawn on the fine face (Physique.express and talk).
static func mood(p: VoxelPart, shut: bool, hurt: bool, talk: int, cry := false) -> void:
	if p.fine.is_empty():
		return
	_paint(p, (1 if shut else 0) + (2 if hurt else 0) + (4 if cry and hurt else 0), talk)
