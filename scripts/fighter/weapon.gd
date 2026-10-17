class_name Weapon
extends RigidBody3D
## A weapon (or shield) built from a voxel design: each voxel has a material and a job (edge,
## point, blunt, grip). Voxels of the same material and job are merged into boxes, the body's
## weight and inertia come from the voxels, and hard knocks chip voxels off (weapon.js and
## durability.js in the web game).

const CHIP_THRESHOLDS := [20.0, 38.0, 60.0]

var design: Dictionary = {}
var stats: Dictionary = {}
var vs := 0.04                     # voxel size (scaled)
var vox: Array = []                # [x, y, z, mat, type]
var alive := PackedByteArray()
var box_of: Array = []             # voxel index -> box dict
var holder: Node = null            # the Fighter holding it
var thrower: Node = null
var thrown_t := 0.0
var own_by: Node = null            # the fighter it just left, ignored for `own_t` more
var own_t := 0.0
var is_shield := false
var welded := false
var chain_cap := 17.0   # the speed the chain's links are held under this step (guard_chain)
var grip_t := 0.0
var grip_main := Vector3.ZERO      # local
var grip_off := Vector3.ZERO
var reach := 0.6
var mm: MultiMesh
var net_id := -1
var _next_box := 0
# A head on a chain (flail, nunchaku, meteor hammer, whip): links and a head of their own,
# swinging on ball joints from the top of the handle.
const CHAIN_LINK := 0.07
const MAX_LINKS := 10.0

## How many links a chain design is built with (a long one gets fewer, longer links).
## Which way the cutting edge faces across the blade, along the weapon's local x: +1 or -1
## for an axe's single edge, 0 for a blade sharp on both sides (or none at all).
func edge_side() -> float:
	if has_meta("edge_side"):
		return float(get_meta("edge_side"))
	var sx := 0.0
	var n := 0
	for v in vox:
		if str(v[4]) == "edge":
			sx += float(v[0])
			n += 1
	var side := 0.0 if n == 0 or absf(sx / n) < 0.5 else signf(sx)
	set_meta("edge_side", side)
	return side

static func links_of(d: Dictionary) -> int:
	var c = d.get("chain")
	if not (c is Dictionary):
		return 0
	return int(round(float(c.links) / ceili(float(c.links) / MAX_LINKS)))
var chain_links: Array = []
var chain_head: Weapon = null
var chain_parent: Weapon = null
var chain_len := 0.07
var chain_anchor := Vector3.ZERO
var head_anchor := Vector3.ZERO
var mass_scale := 1.0
var is_hazard := false             # a trap: a weapon nobody holds, moved by the arena
var hazard_vel := Vector3.ZERO
var hazard_spin := Vector3.ZERO
var last_side := ""
var wscale := 1.0


func setup(d: Dictionary, scale_ := 1.0) -> void:
	design = d.duplicate(true)
	wscale = scale_
	mass_scale = float(d.get("massScale", 1.0))
	name = "Weapon_" + str(d.get("name", "weapon")).replace(" ", "_")
	is_shield = d.get("kind", "weapon") == "shield"
	vs = Data.weapon_voxel * scale_
	vox = d.get("voxels", [])
	alive.resize(vox.size())
	alive.fill(1)
	box_of.resize(vox.size())
	# Weight, centre and inertia from the voxels.
	var m := 0.0
	var com := Vector3.ZERO
	for v in vox:
		var mv: float = Data.material(v[3]).get("mass", 0.02) * scale_ * scale_ * mass_scale
		m += mv
		com += Vector3(v[0], v[1], v[2]) * vs * mv
	m = maxf(0.05, m)
	com /= m
	var ix := 0.0; var iy := 0.0; var iz := 0.0
	for v in vox:
		var mv: float = Data.material(v[3]).get("mass", 0.02) * scale_ * scale_ * mass_scale
		var r := Vector3(v[0], v[1], v[2]) * vs - com
		ix += mv * (r.y * r.y + r.z * r.z + vs * vs / 6.0)
		iy += mv * (r.x * r.x + r.z * r.z + vs * vs / 6.0)
		iz += mv * (r.x * r.x + r.y * r.y + vs * vs / 6.0)
	mass = m
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com
	inertia = Vector3(maxf(ix, 1e-4), maxf(iy, 1e-4), maxf(iz, 1e-4))
	stats = d.get("stats", {}).duplicate()
	if stats.is_empty() and not vox.is_empty():
		stats = ForgeLib.compute_stats(d)   # a forged weapon: its reach, speed and edges from its voxels
	stats["mass"] = m
	reach = float(stats.get("reach", 0.6)) * scale_
	var grips := _grip_points()
	grip_main = grips[0] * vs
	grip_off = grips[1] * vs
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	collision_layer = VoxelPart.LAYER_WEAPON
	collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS
	var all := []
	for i in vox.size():
		all.append(i)
	for b in _build_boxes(all):
		_add_box(b)
	_build_mesh()
	_coat()

## A coated weapon looks it: the edge tinted, and flames, drips of venom or a breath of frost
## along it as it moves (left behind in the air by a swing).
const COAT_TINT := {"venom": Color(0.42, 0.85, 0.22), "fire": Color(1.0, 0.32, 0.04), "frost": Color(0.62, 0.86, 1.0)}
const COAT_FX := {"venom": ["venom", 6], "fire": ["blade_fire", 28], "frost": ["frost", 8]}
func _coat() -> void:
	var c: String = design.get("imbue", "")
	if not COAT_TINT.has(c) or vox.is_empty():
		return
	var pts := []
	for i in vox.size():
		if vox[i][4] == "edge" or vox[i][4] == "point":
			pts.append(i)
	if pts.is_empty():
		for i in vox.size():
			if vox[i][4] != "grip":
				pts.append(i)
	if pts.is_empty():
		return
	for i in pts:
		mm.set_instance_color(i, voxel_color(vox[i][3], vox[i][4]).lerp(COAT_TINT[c], 0.55 if c == "fire" else 0.4))
	if Fx.current == null:
		return
	if c == "fire" and Fx.current.quality != "low":
		# The burning head lights what is round it.
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.55, 0.2)
		glow.light_energy = 1.2
		glow.omni_range = 1.6
		glow.shadow_enabled = false
		var mid: int = pts[pts.size() / 2]
		glow.position = Vector3(vox[mid][0], vox[mid][1], vox[mid][2]) * vs
		add_child(glow)
	var g := grip_main
	pts.sort_custom(func(a, b): return (Vector3(vox[a][0], vox[a][1], vox[a][2]) * vs).distance_squared_to(g) < (Vector3(vox[b][0], vox[b][1], vox[b][2]) * vs).distance_squared_to(g))
	for q in [0.3, 0.65, 1.0]:
		var i: int = pts[int(q * (pts.size() - 1))]
		var ps := Fx.current.emitter(COAT_FX[c][0], self, COAT_FX[c][1], vs * 2.0)
		if ps:
			ps.position = Vector3(vox[i][0], vox[i][1], vox[i][2]) * vs
		# Burning pitch smokes: a thin trail of it off the blade.
		if c == "fire" and q > 0.5:
			var sm := Fx.current.emitter("fire_smoke", self, 10, vs * 2.0)
			if sm:
				sm.position = Vector3(vox[i][0], vox[i][1], vox[i][2]) * vs

func _grip_points() -> Array:
	# Where the builder put the hands (the forge's Hand tool), while there is grip there still.
	if design.get("grips") is Dictionary:
		var g = ForgeLib.grip_points({"voxels": vox, "twoHanded": design.get("twoHanded", false), "grips": design.grips})
		if g != null:
			return [g.main, g.off]
	var grips := []
	for v in vox:
		if v[4] == "grip":
			grips.append(v)
	if grips.is_empty():
		var c := Vector3(0, 0, 0)
		return [c, c + Vector3(0, -2, 0)]
	grips.sort_custom(func(a, b): return a[1] < b[1])
	var avg := func(list: Array) -> Vector3:
		var p := Vector3.ZERO
		for g in list:
			p += Vector3(g[0], g[1], g[2])
		return p / float(maxi(1, list.size()))
	if not design.get("twoHanded", false) or grips.size() < 2:
		var mid: Vector3 = avg.call(grips)
		return [mid, mid + Vector3(0, -2, 0)]
	var top := grips.slice(int(grips.size() / 2))
	var bottom := grips.slice(0, maxi(1, int(grips.size() / 3)))
	return [avg.call(top), avg.call(bottom)]

# ---------- Boxes ----------

func _kind(i: int) -> String:
	return "%s|%s" % [vox[i][3], vox[i][4]]

func _build_boxes(indices: Array) -> Array:
	var at := {}
	for i in indices:
		at[Vector3i(vox[i][0], vox[i][1], vox[i][2])] = i
	var used := {}
	var out := []
	var list := indices.duplicate()
	list.sort_custom(func(a, b):
		var va: Array = vox[a]; var vb: Array = vox[b]
		if va[2] != vb[2]: return va[2] < vb[2]
		if va[1] != vb[1]: return va[1] < vb[1]
		return va[0] < vb[0])
	for i in list:
		if used.has(i):
			continue
		var k := _kind(i)
		var x0: int = vox[i][0]; var y0: int = vox[i][1]; var z0: int = vox[i][2]
		var ok := func(x: int, y: int, z: int) -> bool:
			var j = at.get(Vector3i(x, y, z), -1)
			return j >= 0 and not used.has(j) and _kind(j) == k
		var x1 := x0
		while ok.call(x1 + 1, y0, z0):
			x1 += 1
		var row := func(y: int, z: int) -> bool:
			for x in range(x0, x1 + 1):
				if not ok.call(x, y, z):
					return false
			return true
		var y1 := y0
		while row.call(y1 + 1, z0):
			y1 += 1
		var slab := func(z: int) -> bool:
			for y in range(y0, y1 + 1):
				if not row.call(y, z):
					return false
			return true
		var z1 := z0
		while slab.call(z1 + 1):
			z1 += 1
		var members := []
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var j: int = at[Vector3i(x, y, z)]
					used[j] = true
					members.append(j)
		_next_box += 1
		out.append({"id": _next_box, "min": Vector3i(x0, y0, z0), "max": Vector3i(x1, y1, z1), "indices": members, "mat": vox[i][3], "type": vox[i][4], "shape": null})
	return out

func _add_box(b: Dictionary) -> void:
	for i in b.indices:
		box_of[i] = b
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var mn: Vector3i = b.min; var mx: Vector3i = b.max
	shape.size = Vector3(mx.x - mn.x + 1, mx.y - mn.y + 1, mx.z - mn.z + 1) * vs
	cs.shape = shape
	cs.position = Vector3(mn.x + mx.x, mn.y + mx.y, mn.z + mx.z) * 0.5 * vs
	cs.set_meta("box", b)
	add_child(cs)
	b.shape = cs

func _drop_box(b: Dictionary) -> void:
	if b.shape:
		b.shape.queue_free()
		remove_child(b.shape)
		b.shape = null

## The box a contact touched (from a shape index on this body).
func box_for_shape(shape_idx: int) -> Dictionary:
	var owner_id := shape_find_owner(shape_idx)
	var node = shape_owner_get_owner(owner_id)
	if node and node.has_meta("box"):
		return node.get_meta("box")
	return {}

## The voxel of a box nearest a world point (which one a blow chipped).
func voxel_near(b: Dictionary, p: Vector3) -> int:
	var lp := global_transform.affine_inverse() * p / vs
	var best := -1
	var bd := INF
	for i in b.get("indices", []):
		if alive[i] == 0:
			continue
		var v: Array = vox[i]
		var d := Vector3(v[0], v[1], v[2]).distance_squared_to(lp)
		if d < bd:
			bd = d
			best = i
	return best

# ---------- Drawing ----------

static func voxel_color(mat: String, type: String) -> Color:
	var c := Color.hex(int(Data.material(mat).get("color", 0xffffff)) << 8 | 0xff)
	if type == "edge":
		c = c.lightened(0.12)
	elif type == "point":
		c = c.lightened(0.18)
	return c

func _build_mesh() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * vs * 0.98
	bm.material = VoxelPart.body_material()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = bm
	mm.instance_count = vox.size()
	for i in vox.size():
		var v: Array = vox[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(v[0], v[1], v[2]) * vs))
		mm.set_instance_color(i, voxel_color(v[3], v[4]))
		mm.set_instance_custom_data(i, VoxelPart.kind_data(VoxelPart.kind_of_material(str(v[3]))))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # see VoxelPart
	# Fixed box: chipped voxels are scaled to nothing, which would shrink the auto box (see VoxelPart).
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in vox:
		var q := Vector3(v[0], v[1], v[2]) * vs
		lo = lo.min(q); hi = hi.max(q)
	if not vox.is_empty():
		mmi.custom_aabb = AABB(lo - Vector3.ONE * vs, hi - lo + Vector3.ONE * vs * 2.0)
		mm.custom_aabb = mmi.custom_aabb
	add_child(mmi)

## The box the voxels still on it fill, in its own frame (a shield's cover, see Fighter).
## The gems set in it that are still there: {"ruby": n, ...} (Match._gems).
const GEMS := ["ruby", "sapphire", "emerald"]
func gem_counts() -> Dictionary:
	var out := {}
	for i in vox.size():
		if alive[i] and GEMS.has(vox[i][3]):
			out[vox[i][3]] = int(out.get(vox[i][3], 0)) + 1
	return out

## The voxels of `mat` still on it within `r` voxels of world point `p` (Match._materials).
func voxels_near(p: Vector3, r: float, mat: String) -> Array:
	var q := to_local(p) / vs
	var out := []
	for i in vox.size():
		if alive[i] and vox[i][3] == mat and Vector3(vox[i][0], vox[i][1], vox[i][2]).distance_to(q) <= r:
			out.append(i)
	return out

func material_count(mats: Array) -> int:
	var n := 0
	for i in vox.size():
		if alive[i] and mats.has(vox[i][3]):
			n += 1
	return n

## Where the voxels of `mat` are, in the world (the middle of them).
func material_centre(mat: String) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for i in vox.size():
		if alive[i] and vox[i][3] == mat:
			sum += Vector3(vox[i][0], vox[i][1], vox[i][2])
			n += 1
	return global_transform * (sum / maxf(1.0, n) * vs)

func local_box() -> AABB:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in vox.size():
		if alive[i] == 0:
			continue
		var q := Vector3(vox[i][0], vox[i][1], vox[i][2]) * vs
		lo = lo.min(q)
		hi = hi.max(q)
	return AABB() if lo == Vector3.INF else AABB(lo, hi - lo)

# ---------- Burning and poisoned (only the look) ----------

var _burn := Vector2i.ZERO          # what is shown now: x fire, y poison
var _burn_fx: GPUParticles3D = null
var _poison_fx: GPUParticles3D = null

## Shows the weapon burning (lying in fire) and/or poisoned (in acid): its voxels glow as their
## stuff burns (wood and leather well, metal a dull red-hot), flames, embers or fumes of the kind
## its main material gives off. Nothing about the weapon itself changes.
func set_burn(fire: bool, poison: bool) -> void:
	var want := Vector2i(1 if fire else 0, 1 if poison else 0)
	if want == _burn or mm == null or not mm.use_custom_data:
		return
	_burn = want
	for i in vox.size():
		var mat := str(vox[i][3])
		var k := VoxelPart.kind_of_material(mat)
		var heat := 0.0
		if fire:
			match BurnFx.surface_of_kind(k):
				"wood", "cloth": heat = 0.9
				"metal": heat = 0.35
				_: heat = 0.2
		mm.set_instance_custom_data(i, Color(float(k) / 16.0, heat, 0.7 if poison else 0.0, 1.0))
	var surface := _main_surface()
	var size := clampf(reach * 1.6, 0.6, 3.0)
	if fire and _burn_fx == null:
		_burn_fx = BurnFx.make(self, surface, true, size)
	if poison and _poison_fx == null:
		_poison_fx = BurnFx.make(self, surface, false, size)
	BurnFx.set_on(_burn_fx, fire)
	BurnFx.set_on(_poison_fx, poison)

## What most of the weapon's living voxels are made of, as a BurnFx surface.
func _main_surface() -> String:
	var count := {}
	for i in vox.size():
		if alive[i]:
			var s := BurnFx.surface_of_material(str(vox[i][3]))
			count[s] = int(count.get(s, 0)) + 1
	var best := "metal"
	for s in count:
		if count[s] > int(count.get(best, 0)):
			best = s
	return best

## Hides (or shows again) the leather string voxels, while a crossbow's string is drawn by
## cords instead (being cocked). Only the picture: the voxels are still there.
var _string_hidden := false
func set_string_hidden(on: bool) -> void:
	if on == _string_hidden or mm == null:
		return
	_string_hidden = on
	for i in vox.size():
		if vox[i][3] == "leather" and alive[i]:
			var v: Array = vox[i]
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO) if on else Basis(), Vector3(v[0], v[1], v[2]) * vs))

# ---------- Wear ----------

func remove_voxels(indices: Array) -> Array:
	var out := []
	var touched := {}
	var hidden := []   # buffer slots to zero (see VoxelPart.set_shown: single-instance writes hid the mesh)
	for i in indices:
		if i < 0 or i >= vox.size() or alive[i] == 0:
			continue
		alive[i] = 0
		var v: Array = vox[i]
		out.append({"p": global_transform * (Vector3(v[0], v[1], v[2]) * vs), "color": voxel_color(v[3], v[4]), "kind": VoxelPart.kind_of_material(str(v[3]))})
		var b: int = i * 16
		var buf_i := [b, b + 1, b + 2, b + 3, b + 4, b + 5, b + 6, b + 7, b + 8, b + 9, b + 10, b + 11]
		hidden.append_array(buf_i)
		if box_of[i]:
			touched[box_of[i].id] = box_of[i]
	if not hidden.is_empty():
		# Per instance (a whole-buffer write did not reach the screen with physics interpolation
		# on; the fixed custom_aabb keeps single writes from culling the weapon).
		for k in range(0, hidden.size(), 12):
			mm.set_instance_transform(int(hidden[k] / 16), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	for b in touched.values():
		_drop_box(b)
		var left := []
		for i in b.indices:
			if box_of[i] != null and box_of[i].id == b.id:
				box_of[i] = null
			if alive[i]:
				left.append(i)
		for nb in _build_boxes(left):
			_add_box(nb)
	return out

func alive_count() -> int:
	var n := 0
	for a in alive:
		n += a
	return n

## Wear over a fight: every knock tires the metal around where it landed (`fatigue`), so the
## spot that takes the most blows is the one that chips and, in the end, breaks; an edge loses
## its keenness with every cut and every clang (`dull`, shown as a rusty dulling of the edge).
var fatigue := PackedFloat32Array()
var dull := 0.0
var _dull_shown := 0.0
const DULL_MAX := 0.65

## How keen the edge still is, as a share of the smith's: 1 fresh from the forge.
func keenness() -> float:
	return 1.0 - dull

func wear_edge(amount: float) -> void:
	if amount <= 0.0 or float(design.get("sharpness", 0.0)) <= 0.0:
		return
	dull = minf(DULL_MAX, dull + amount)
	if dull - _dull_shown >= 0.04 and mm:
		_dull_shown = dull
		var rust := Color(0.42, 0.3, 0.22)
		for i in vox.size():
			if alive[i] and (vox[i][4] == "edge" or vox[i][4] == "point"):
				mm.set_instance_color(i, voxel_color(vox[i][3], vox[i][4]).lerp(rust, dull * 0.75))

## A knock of `score` on voxel `index`: tires the metal round it, chips what gives way (the
## web game's sparing chip: a sound weapon keeps in one piece) and, once it is battered, breaks
## it where it is weakest, the piece away from the hand falling off. Returns the removed
## indices and their voxels ({} if nothing came off).
func knock(index: int, score: float) -> Dictionary:
	if index < 0 or index >= vox.size() or alive[index] == 0:
		return {}
	if fatigue.size() != vox.size():
		fatigue.resize(vox.size())
	var v0 := Vector3(vox[index][0], vox[index][1], vox[index][2])
	var eff := score + fatigue[index]
	var worn := []
	for i in vox.size():
		if alive[i]:
			var d := Vector3(vox[i][0], vox[i][1], vox[i][2]).distance_to(v0)
			if d <= 1.5:
				fatigue[i] += score * (FATIGUE_SPOT if d < 0.5 else FATIGUE_NEAR)
				if fatigue[i] >= wear_limit(i):
					worn.append(i)
	var idx := chip_indices(index, eff)
	# Worn out by use: the voxels round the place it is always struck with crumble away one by
	# one, even under blows too light to chip it (soft stuff sooner than steel).
	for i in worn:
		if not idx.has(i):
			idx.append(i)
	idx = sparing(idx)
	if idx.is_empty():
		return {}
	var voxels := remove_voxels(idx)
	Chunk.spawn(self, voxels.duplicate(), Vector3.UP)   # the chips fly off
	var pieces := split_plan()
	var fell := []
	for pc in pieces:
		var pv := remove_voxels(pc)
		idx.append_array(pc)
		voxels.append_array(pv)
		fell.append(pv)
	for pv in fell:
		Chunk.spawn(self, pv, Vector3.DOWN)
	return {"indices": idx, "voxels": voxels, "broke": not pieces.is_empty()}

## Voxels `idx` are spent (explosive powder gone off): they are gone, and what they held up falls
## off as its own piece. Returns every index removed.
func spend(idx: Array) -> Array:
	var voxels := remove_voxels(idx)
	Chunk.spawn(self, voxels, Vector3.UP)
	var out := idx.duplicate()
	for pc in split_plan():
		out.append_array(pc)
		Chunk.spawn(self, remove_voxels(pc), Vector3.DOWN)
	return out

## The 6-connected pieces of what is left.
func components() -> Array:
	var at := {}
	for i in vox.size():
		if alive[i]:
			at[Vector3i(vox[i][0], vox[i][1], vox[i][2])] = i
	var seen := {}
	var out := []
	for k in at:
		if seen.has(k):
			continue
		var comp := []
		var stack := [k]
		seen[k] = true
		while not stack.is_empty():
			var c: Vector3i = stack.pop_back()
			comp.append(at[c])
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var n: Vector3i = c + d
				if at.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		out.append(comp)
	return out

## durability.js sparingChip: while it has lost less than a quarter of itself, only the voxels
## whose loss leaves it in one piece come off, unless the metal there is worn out (knocked in
## that one place over and over): there it gives way, and the blade breaks at its worst spot.
const FATIGUE_BREAK := 60.0
const FATIGUE_SPOT := 0.5        # of a knock's score, into the voxel struck
const FATIGUE_NEAR := 0.2        # and into those round it
const WEAR_LIMIT := 7.0          # the fatigue a steel voxel takes before it crumbles

## How much use voxel `i` stands before it wears off: the harder the stuff the longer; a grip,
## wrapped and held, twice as long; a shield, made to take blows, half as long again.
func wear_limit(i: int) -> float:
	var h := float(Data.material(String(vox[i][3])).get("hardness", 0.5))
	return WEAR_LIMIT * (0.5 + h) / 1.5 * (2.0 if vox[i][4] == "grip" else 1.0) * (1.5 if design.get("kind", "") == "shield" else 1.0)
func sparing(idx: Array) -> Array:
	if idx.is_empty() or vox.size() - alive_count() >= vox.size() * 0.25:
		return idx
	var before := components().size()
	var ok := []
	for i in idx:
		if alive[i] == 0:
			continue
		alive[i] = 0
		if components().size() <= before or (fatigue.size() > i and fatigue[i] >= FATIGUE_BREAK):
			ok.append(i)
		else:
			alive[i] = 1
	for i in ok:
		alive[i] = 1
	return ok

## durability.js splitPlan: the piece with the grip (nearest the hand) stays, the rest fall off.
func split_plan() -> Array:
	var comps := components()
	if comps.size() <= 1:
		return []
	var gl := grip_main / vs
	var score := func(c: Array) -> float:
		var has_grip := c.any(func(i): return vox[i][4] == "grip")
		var near := INF
		for i in c:
			near = minf(near, Vector3(vox[i][0], vox[i][1], vox[i][2]).distance_to(gl))
		return (0.0 if has_grip else 1000.0) + near - c.size() * 0.001
	comps.sort_custom(func(a, b): return score.call(a) < score.call(b))
	return comps.slice(1)

## Voxels a knock of `score` takes off around voxel `index` (grip voxels are tougher).
func chip_indices(index: int, score: float) -> Array:
	if index < 0 or alive[index] == 0:
		return []
	var v: Array = vox[index]
	if v[4] == "grip":
		score *= 0.5
	if score < CHIP_THRESHOLDS[0]:
		return []
	var r := 1.5 if score >= CHIP_THRESHOLDS[2] else (1.0 if score >= CHIP_THRESHOLDS[1] else 0.0)
	var out := []
	for i in vox.size():
		if alive[i] and Vector3(vox[i][0], vox[i][1], vox[i][2]).distance_to(Vector3(v[0], v[1], v[2])) <= r:
			out.append(i)
	return out

static func chip_score(j: float, own_hardness: float, other_hardness: float) -> float:
	return (j * (0.4 + other_hardness)) / (own_hardness + 0.15)

## In a hand with the blade under the sand (put into a hanging arm, pressed down by its weight):
## it passes through the floor until the arm has it out, then meets the floor again, rather
## than jammed there with the hand stuck to it.
var _through_floor := false
func _out_of_the_floor() -> void:
	if freeze or vox.is_empty():
		return
	var low := INF
	var box := local_box()
	for i in 8:
		low = minf(low, (global_transform * box.get_endpoint(i)).y)
	var under := holder != null and low < -0.04
	if under != _through_floor and (under or low > 0.02 or holder == null):
		_through_floor = under
		for b in bodies():
			if b is CollisionObject3D:
				b.collision_mask = (b.collision_mask & ~VoxelPart.LAYER_WORLD) if under else (b.collision_mask | VoxelPart.LAYER_WORLD)

func grip_world() -> Vector3:
	return global_transform * grip_main

func velocity_at(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - global_transform * center_of_mass)

func set_held_by(f: Node) -> void:
	holder = f
	if f:
		collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS

## Put in a hand where it already runs through someone (bought at the smith, who stands in front
## of the buyer): it passes through those parts until it is clear of them, rather than wounding
## him and pinning the buyer to him.
var spawned_in: Array = []
var _spawn_check := 0

func clear_spawn(others: Array) -> void:
	for c in others:
		if c == holder or not is_instance_valid(c) or not ("parts" in c):
			continue
		for p in c.parts:
			if p is PhysicsBody3D and not spawned_in.has(p) and _runs_through(p, 0.3):
				for b in bodies():
					b.add_collision_exception_with(p)
				spawned_in.append(p)

func _runs_through(p: Node3D, margin: float) -> bool:
	return local_box().grow(margin).has_point(global_transform.affine_inverse() * p.global_position)

func _let_go_spawned() -> void:
	for p in spawned_in.duplicate():
		if not is_instance_valid(p) or not _runs_through(p, 0.4):
			if is_instance_valid(p):
				for b in bodies():
					b.remove_collision_exception_with(p)
			spawned_in.erase(p)

## Out of the hand long enough: it no longer passes through the body that let it go.
func forget_owner() -> void:
	if own_by and is_instance_valid(own_by):
		for b in bodies():
			if not (b is PhysicsBody3D):
				continue
			for p in own_by.parts:
				b.remove_collision_exception_with(p)
			for o in own_by.weapons.values():
				if o and o != self:
					b.remove_collision_exception_with(o)
	own_by = null
	own_t = 0.0

func _physics_process(dt: float) -> void:
	# Through the sand (a heavy thing pressed or thrown into it): back up on top, at rest, not
	# lost for good under the arena.
	if global_position.y < -1.0 and not freeze:
		global_position = Vector3(global_position.x, 0.6, global_position.z)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	_out_of_the_floor()
	if chain_head:
		# The head hits for whoever swings the handle.
		chain_head.holder = holder
		chain_head.thrower = thrower
		chain_head.thrown_t = thrown_t
		guard_chain()
	if thrown_t > 0.0:
		thrown_t -= dt
	if own_t > 0.0:
		own_t -= dt
		if own_t <= 0.0 and holder == null:
			forget_owner()
	if not spawned_in.is_empty():
		_spawn_check += 1
		if _spawn_check % 6 == 0:
			_let_go_spawned()

## How it flies when thrown (weaponDesign.js): a throwing axe spins, a javelin flies point first.
## A thrown blade or point that bit deep stays in the body it struck (weapon.js impale): welded
## to that part at the wound, its weight hanging off the limb, until someone pulls it out (G)
## or the part comes off.
var stuck = null   # {char, part, joint, mass}

func impale(c, part: VoxelPart, point: Vector3) -> bool:
	if stuck != null or holder != null or not chain_links.is_empty() or part == null or part.severed or not is_inside_tree():
		return false
	# Drive it a hand's width in along its flight before it sets: it sits in the wound.
	var sp := linear_velocity.length()
	if sp > 0.5:
		global_position += linear_velocity * (0.1 * float(c.S) / sp)
	linear_velocity = part.linear_velocity
	angular_velocity = part.angular_velocity
	for p in c.parts:
		add_collision_exception_with(p)
	var j := Generic6DOFJoint3D.new()
	c.add_child(j)
	j.global_position = point
	j.node_a = part.get_path()
	j.node_b = get_path()
	thrown_t = 0.0
	stuck = {"char": c, "part": part, "joint": j, "mass": mass}
	c.stuck_load += mass
	return true

func unstick() -> void:
	if stuck == null:
		return
	var st: Dictionary = stuck
	stuck = null
	if is_instance_valid(st.joint):
		st.joint.queue_free()
	if is_instance_valid(st.char):
		st.char.stuck_load = maxf(0.0, st.char.stuck_load - float(st.mass))
		var cc = st.char
		get_tree().create_timer(0.5, false, true).timeout.connect(func():
			if is_instance_valid(cc) and is_instance_valid(self) and holder != cc:
				for p in cc.parts:
					if is_instance_valid(p):
						remove_collision_exception_with(p))

static func spins_in_flight(d: Dictionary) -> bool:
	if not d.get("throwable", false) or d.get("voxels", []).is_empty():
		return false
	if d.get("spins", false):
		return true
	var xs := []; var zs := []
	for v in d.voxels:
		xs.append(v[0]); zs.append(v[2])
	return maxi(xs.max() - xs.min(), zs.max() - zs.min()) + 1 >= 4

static func flies_point_first(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	if d.get("throwable", false):
		return not spins_in_flight(d)
	if d.get("kind", "weapon") == "shield" or d.get("chain") or d.get("voxels", []).is_empty():
		return false
	var ys := []; var xs := []; var zs := []
	for v in d.voxels:
		ys.append(v[1]); xs.append(v[0]); zs.append(v[2])
	var top: int = ys.max()
	var length: int = top - int(ys.min()) + 1
	var wide: int = maxi(xs.max() - xs.min(), zs.max() - zs.min()) + 1
	if length < 30 or wide > 5:
		return false
	for v in d.voxels:
		if v[1] >= top - 1 and v[4] == "point":
			return true
	return false

# ---------- Chains ----------

## Every body of the weapon: the handle, and a chain weapon's links and head.
func bodies() -> Array:
	var out: Array = [self]
	out.append_array(chain_links)
	if chain_head:
		out.append(chain_head)
	return out

## Lays out the chain straight up from the handle as it stands now and joins it up. Called
## once the handle is placed (Fighter.equip, or a weapon spawned loose).
func build_chain() -> void:
	var c = design.get("chain")
	if not (c is Dictionary) or chain_head != null or not is_inside_tree():
		return
	var whip: bool = c.get("whip", false)
	# A long chain is laid as fewer, longer links (the same length in all): two dozen little
	# links on pins are more than the solver can hold together, and the whip thrashed.
	var per := ceili(float(c.links) / MAX_LINKS)
	var n_links := links_of(design)
	chain_len = CHAIN_LINK * wscale * per
	if c.get("anchor") is Array:
		chain_anchor = Vector3(c.anchor[0], c.anchor[1], c.anchor[2]) * vs
	else:
		var top: Array = vox[0]
		for v in vox:
			if v[1] > top[1]:
				top = v
		chain_anchor = Vector3(top[0], top[1] + 0.5, top[2]) * vs
	var hv: Array = c.head.voxels
	var bottom: Array = hv[0]
	for v in hv:
		if v[1] < bottom[1]:
			bottom = v
	head_anchor = Vector3(bottom[0], bottom[1] - 0.5, bottom[2]) * vs
	var head_mass := 0.0
	for v in hv:
		head_mass += float(Data.material(v[3]).get("mass", 0.02)) * wscale * wscale
	var link_mesh := SphereMesh.new()
	link_mesh.radius = vs * 0.45
	link_mesh.height = vs * 0.9
	link_mesh.radial_segments = 6
	link_mesh.rings = 3
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color.hex(0x5a3a22ff if whip else 0x8a8f96ff)
	lm.metallic = 0.0 if whip else 0.7
	lm.roughness = 0.5
	link_mesh.material = lm
	var q := global_transform.basis.get_rotation_quaternion()
	var up := q * Vector3.UP
	var start := global_transform * chain_anchor
	var prev: RigidBody3D = self
	for i in n_links:
		var b := RigidBody3D.new()
		b.name = "%s_link%d" % [name, i]
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = vs * 0.4
		cs.shape = sh
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = link_mesh
		b.add_child(mi)
		# Links much lighter than the head let the joints stretch: they get a share of its weight.
		b.mass = (0.1 if whip else maxf(0.2, 0.35 * head_mass)) * per
		b.linear_damp = 0.3
		b.angular_damp = 1.0
		b.continuous_cd = true
		b.can_sleep = false
		b.collision_layer = 0
		b.collision_mask = VoxelPart.LAYER_WORLD
		get_parent().add_child(b)
		b.global_transform = Transform3D(Basis(q), start + up * chain_len * (i + 0.5))
		_pin(prev, b, start + up * chain_len * i)
		chain_links.append(b)
		prev = b
	var head := Weapon.new()
	head.chain_parent = self
	head.setup({"name": design.get("name", "chain"), "voxels": hv, "sharpness": design.get("sharpness", 0.0), "serrated": design.get("serrated", false), "imbue": design.get("imbue", ""), "massScale": 0.3 if whip else 1.0, "dmgScale": design.get("dmgScale", Data.damage_tuning.get(Combat._preset_key(design), 1.0))}, wscale)
	head.linear_damp = 0.05
	head.angular_damp = 0.4
	get_parent().add_child(head)
	var end := start + up * chain_len * n_links
	head.global_transform = Transform3D(Basis(q), end - q * head_anchor)
	head.add_collision_exception_with(self)
	_pin(prev, head, end)
	chain_head = head
	tree_exiting.connect(_free_chain)

func _pin(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	b.add_child(j)
	j.global_position = at
	j.node_a = a.get_path()
	j.node_b = b.get_path()

func _free_chain() -> void:
	for b in chain_links:
		if is_instance_valid(b):
			b.queue_free()
	if chain_head and is_instance_valid(chain_head):
		chain_head.queue_free()
	chain_links = []
	chain_head = null

## A chain the solver has torn apart (stretched far past its length, or flung at absurd speed)
## is laid straight again from the handle; ordinary fast links are held under a limit.
func guard_chain() -> void:
	if chain_head == null:
		return
	var t := global_position
	var reach_ := chain_len * (chain_links.size() + 2) * 2.0 + 0.5
	var broken := false
	var whip: bool = design.chain.get("whip", false)
	# The chain goes no faster than the hand that whirls it can send it: a few times the
	# handle's own speed (a whip's tip more), and hardly at all from a handle lying still or
	# in the fist of a man on the sand. Left free it was whipped about by every knock, the
	# handle's jolt on a fall or a drop sent the head flying over his head, and the solver's
	# own jitter between links on the ground fed on itself.
	var hv := linear_velocity
	var hs := hv.length()
	# (Getting up counts as down for a moment: the arm hauled up with the body whipped it.)
	var standing: bool = holder == null or not is_instance_valid(holder) or (holder.get("state") == "stand" and float(holder.get("time")) - float(holder.get("stood_at")) > 0.6)
	var cap := 30.0 if whip else 13.0
	# Relative to the handle: what the hand adds to the chain each step is what whirls it.
	var cap_rel: float = (minf(16.0, 4.0 + hs * 7.0) if whip else minf(6.5, 2.0 + hs * 2.0)) if standing else (2.0 if whip else 1.5)
	var damp := lerpf(5.0, 0.3, clampf(hs / 1.5, 0.0, 1.0)) if standing else 6.0
	for b in chain_links + [chain_head]:
		var p: Vector3 = b.global_position
		var sp: float = b.linear_velocity.length()
		if not is_finite(sp) or not p.is_finite() or p.distance_to(t) > reach_:
			broken = true
			break
		if sp > cap:
			b.linear_velocity *= cap / sp
		var rel: Vector3 = b.linear_velocity - hv
		var rs := rel.length()
		if rs > cap_rel:
			b.linear_velocity = hv + rel * (cap_rel / rs)
		var av: float = b.angular_velocity.length()
		if av > 25.0:
			b.angular_velocity *= 25.0 / av
		b.linear_damp = damp
	chain_cap = cap
	if not broken:
		_rope()
		return
	var q := global_transform.basis.get_rotation_quaternion()
	var up := q * Vector3.UP
	var start := global_transform * chain_anchor
	for i in chain_links.size():
		var b: RigidBody3D = chain_links[i]
		b.global_transform = Transform3D(Basis(q), start + up * chain_len * (i + 0.5))
		b.linear_velocity = linear_velocity
		b.angular_velocity = Vector3.ZERO
	chain_head.global_transform = Transform3D(Basis(q), start + up * chain_len * chain_links.size() - q * head_anchor)
	chain_head.linear_velocity = linear_velocity
	chain_head.angular_velocity = Vector3.ZERO

## A chain is a rope, not elastic: the pin joints between light links and a heavy head stretch
## under a hard swing (and that is what let them come apart). So every step, from the handle
## out, a link drawn well past its length from the one before is brought back to it and its
## speed away from the chain is taken off. Only past some slack: the joints always give a few
## per cent, and held to their exact length every step the links fought the joints, buzzed at
## a hundred metres a second and the whip thrashed even hanging still.
const ROPE_SLACK := 1.15
func _rope() -> void:
	if chain_links.is_empty():
		return
	# From the first link out (the pin on the handle itself is left to the joint: it gives
	# a little more there, and pulled back each step the first link set the whole whip shaking).
	var prev_p: Vector3 = chain_links[0].global_position
	var prev_v: Vector3 = chain_links[0].linear_velocity
	var seg := chain_len
	for b in chain_links.slice(1):
		var p: Vector3 = b.global_position
		var d := p - prev_p
		var l := d.length()
		var mx := seg * ROPE_SLACK
		if l > mx and l > 1e-6:
			var n := d / l
			b.global_position = prev_p + n * mx
			var rv: Vector3 = b.linear_velocity - prev_v
			var away := rv.dot(n)
			if away > 0.0:
				b.linear_velocity -= n * away
		prev_p = b.global_position
		prev_v = b.linear_velocity
		seg = chain_len
	var hp := chain_head.global_transform * head_anchor
	var dh := hp - prev_p
	var lh := dh.length()
	var mxh := chain_len * 0.5 * ROPE_SLACK
	if lh > mxh and lh > 1e-6:
		var nh := dh / lh
		chain_head.global_position -= nh * (lh - mxh)
		var rvh: Vector3 = chain_head.linear_velocity - prev_v
		var awayh := rvh.dot(nh)
		if awayh > 0.0:
			chain_head.linear_velocity -= nh * awayh

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# A chain's head is held to its speed inside the step too, not only between steps.
	if chain_parent and is_instance_valid(chain_parent) and chain_parent.design.get("chain") is Dictionary:
		var cap: float = chain_parent.chain_cap
		var sp := state.linear_velocity.length()
		if sp > cap:
			state.linear_velocity *= cap / sp
	if Combat.current and state.get_contact_count() > 0:
		Combat.current.report(self, state)
