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
var jaw_mouth: Node3D = null
var jaw_mm: MultiMesh = null
var jaw_slot := {}               # voxel index -> its slot in jaw_mm
var jaw_angle := 0.0
var bone := PackedByteArray()
var organ := PackedByteArray()     # per voxel, the organ it is part of (Anatomy; 0 none)
var alive_count := 0

var hp := 100.0
var bleed := 0.0
var severed := false
var hanging := false
var fractured := false
var stump := false
var drips: Array = []   # {node: GPUParticles3D, lp: Vector3}: where blood runs from its wounds
var stump_t := 0.0
var flinch_t := 0.0
var missing := false
var prosthetic := ""               # "peg", "hook", "blade": what the physician fitted in its place
var thin_layer = null              # [axis, layer]: where thin_ratio found it thinnest
var hang_t := 0.0
var spots: Array = []           # fire and acid where they struck (fire.gd)
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
var boxes: Array = []            # CollisionShape3D, while the part has holes
var split := false
var half_ext := Vector3.ONE

static var _box_mesh_cache := {}
static var _material: StandardMaterial3D
## The voxel boxes' look (shaders/voxel_body.gdshader): each voxel's kind of stuff in its
## instance data (skin, cloth, leather, metal...; see the shader).
static var _body_material: ShaderMaterial
var kinds := PackedByteArray()   # per voxel, what it is made of (only how it is drawn)
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
	def = d
	part_name = d.get("name", "part")
	label = d.get("label", part_name)
	name = part_name
	var dd: Array = d.get("dims", [1, 1, 1])
	dims = Vector3i(int(dd[0]), int(dd[1]), int(dd[2]))
	var g: Array = d.get("grid", [dims.x * Data.body_res, dims.y * Data.body_res, dims.z * Data.body_res])
	grid = Vector3i(int(g[0]), int(g[1]), int(g[2]))
	vf = Data.body_voxel / Data.body_res
	part_scale = scale_
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
		return _body_material
	if not _forced.has(force):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/voxel_body.gdshader")
		m.set_shader_parameter("force_kind", force)
		_forced[force] = m
	return _forced[force]

## A voxel kind as MultiMesh custom data (the shader reads r * 16; a = 1 marks it set).
static func kind_data(k: int) -> Color:
	return Color(float(k) / 16.0, 0.0, 0.0, 1.0)

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
		bm.size = Vector3.ONE * vf * part_scale * 0.98
		bm.material = body_material()
		_box_mesh_cache[key] = bm
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _box_mesh_cache[key]
	mm.instance_count = fx.size()
	for i in fx.size():
		mm.set_instance_transform(i, Transform3D(Basis(), local_of(i)))
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, kind_data(kinds[i]))
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Not interpolated on its own: an interpolated multimesh kept drawing the voxels it was
	# built with, so every hole, cut and knocked-off piece stayed invisible. The part's body
	# moves it at the physics rate.
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	skin.material_override = _skin_material
	skin.custom_aabb = mmi.custom_aabb
	add_child(skin)
	mmi.visible = false
	rebuild_skin()

func rebuild_skin() -> void:
	_skin_dirty = false
	if skin == null:
		return
	skin.mesh = VoxelSkin.build(self, jaw_slot)

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
	for i in list:
		if jaw_slot.has(i):
			jaw.append([jaw_slot[i], colors[i]])
		else:
			main.append([i, colors[i]])
	_write_colors(mm, main)
	if jaw_mm:
		_write_colors(jaw_mm, jaw)
	_write_glow(list)
	_mark_skin()

# ---------- Fire and poison on the voxels themselves (only how they look) ----------

var glowing := {}   # voxel -> Vector2(fire, poison) last written to its instance data

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
				if best.kind == "fire":
					g.x = clampf(h / 1.2, 0.15, 1.0)
				else:
					g.y = clampf(h / 0.8, 0.2, 1.0)
		if g == Vector2.ZERO and not glowing.has(i):
			continue
		_set_status(i, g)

func _set_status(i: int, g: Vector2) -> void:
	var c := Color(float(kinds[i]) / 16.0, g.x, g.y, 1.0)
	if jaw_slot.has(i):
		if jaw_mm:
			jaw_mm.set_instance_custom_data(jaw_slot[i], c)
	else:
		mm.set_instance_custom_data(i, c)
	if g == Vector2.ZERO:
		glowing.erase(i)
	else:
		glowing[i] = g

## What the part is made of where the first live spot of `kind` is: the nearest living voxel's
## kind of stuff (skin, cloth, fur...), as a BurnFx surface.
func _surface_at_spot(kind: String) -> String:
	for s in spots:
		if s.kind == kind and s.t > 0.0:
			var best := -1
			var bd := INF
			for i in fx.size():
				if alive[i]:
					var d := local_of(i).distance_squared_to(s.lp)
					if d < bd:
						bd = d
						best = i
			if best >= 0:
				return BurnFx.surface_of_kind(kinds[best])
	return "flesh"

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
	var main_on := []
	var main_off := []
	var cols := []
	for i in fx.size():
		if jaw_slot.has(i):
			continue
		(main_on if alive[i] else main_off).append([i, local_of(i)])
		cols.append([i, colors[i]])
	_write_shown(mm, main_on, true)
	_write_shown(mm, main_off, false)
	_write_colors(mm, cols)
	_mark_skin()

func resync_later() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(self):
		resync()

## Old wounds (Body): the voxels a fight took stay gone, the hole healed over into a dent the
## shape of the blow, its rim the pale, shiny pink of scar tissue. No blood, no smear.
const SCAR := Color(0.78, 0.5, 0.47)
func scar(indices: Array) -> void:
	var gone := {}
	for i in indices:
		if i >= 0 and i < fx.size():
			gone[Vector3i(fx[i], fy[i], fz[i])] = true
	if gone.is_empty():
		return
	remove_voxels(indices, false)
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

## The drips follow how hard the part bleeds: heavier while it pours, gone once it has closed.
func update_drips() -> void:
	if drips.is_empty():
		return
	var flow := clampf((bleed + (2.0 if stump else 0.0)) / 1.2, 0.0, 1.0)
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

## Paint a wound: blood soaks in around cuts, bruises darken under blunt blows.
func wound(lp: Vector3, r: float, kind := "blood") -> int:
	var target := BRUISE if kind == "bruise" else SMEAR
	var mx := 0.55 if kind == "bruise" else 0.9
	var touched := []
	for i in fx.size():
		if alive[i] == 0:
			continue
		var d := local_of(i).distance_to(lp)
		if d >= r:
			continue
		var k := mx * pow(1.0 - d / r, 0.6)
		if k < 0.08:
			continue
		colors[i] = colors[i].lerp(target, k)
		touched.append(i)
	refresh_colors(touched)
	return touched.size()

# ---------- Losing voxels ----------

var integrity: float:
	get:
		return float(alive_count) / maxf(1, fx.size())

## How well it still works, 0..1 (0 when severed).
func function() -> float:
	if severed:
		return 0.0
	if hanging:
		return 0.03
	if fractured:
		return 0.1
	var fn := clampf(hp / 100.0, 0.0, 1.0) * (0.4 + 0.6 * integrity)
	if prosthetic != "":
		fn = minf(fn, float(Body.PROSTHETIC_FN.get(prosthetic, 0.7)))
	return fn

## Knocks out voxels; returns [{p: world position, color}].
func remove_voxels(indices: Array, smear := true, notify := true) -> Array:
	var out := []
	var done := []
	var centre := Vector3.ZERO
	for i in indices:
		if i < 0 or i >= fx.size() or alive[i] == 0:
			continue
		alive[i] = 0
		alive_count -= 1
		done.append(i)
		out.append({"p": world_of(i), "color": colors[i]})
		centre += local_of(i)
	if out.is_empty():
		return out
	set_shown(done, false)
	if smear:
		centre /= out.size()
		wound(centre, vf * part_scale * (2.2 + pow(out.size(), 1.0 / 3.0) * 0.8), "blood")
	fit_collider()
	if notify and fighter and fighter.has_method("on_part_voxels_lost"):
		fighter.on_part_voxels_lost(self, done, out)
	return out

## Shows or hides voxels by writing the multimesh's instance buffer in one go (12 transform
## floats then 4 colour floats per voxel). Setting a single instance's transform after the first
## frame made Godot drop the whole part from the screen, which hid every wounded body part.
func set_shown(indices: Array, on: bool) -> void:
	var main := []
	var jaw := []
	for i in indices:
		if i < 0 or i >= fx.size():
			continue
		if jaw_slot.has(i):
			jaw.append([jaw_slot[i], local_of(i) - jaw_pivot.position])
		else:
			main.append([i, local_of(i)])
	_write_shown(mm, main, on)
	_mark_skin()
	if jaw_mm:
		_write_shown(jaw_mm, jaw, on)
		if not jaw.is_empty():
			# The teeth and the gullet go with the jaw: hacked mostly away, nothing floats there.
			var left := 0
			for i in jaw_slot:
				left += alive[i]
			var keep := left > jaw_slot.size() * 0.35
			for c in jaw_pivot.get_children():
				if c is MeshInstance3D:
					c.visible = keep
			if jaw_mouth:
				for c in jaw_mouth.get_children():
					c.visible = keep

static func _write_shown(m: MultiMesh, rows: Array, on: bool) -> void:
	var k := 1.0 if on else 0.0
	for r in rows:
		m.set_instance_transform(r[0], Transform3D(Basis().scaled(Vector3.ONE * k), r[1] * k))

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
		y1 = best_row
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
		var k := 1.0 if alive[i] else 0.0
		jaw_mm.set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ONE * k), (local_of(i) - jaw_pivot.position) * k))
		jaw_mm.set_instance_color(s, colors[i])
		jaw_mm.set_instance_custom_data(s, kind_data(kinds[i]))
	var ext := Vector3(grid.x, grid.y, grid.z) * sc + Vector3.ONE * sc
	jaw_mm.custom_aabb = AABB(-ext, ext * 2.0)
	var jm := MultiMeshInstance3D.new()
	jm.multimesh = jaw_mm
	jm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color8(0x4a, 0x0e, 0x0e)
	gm.roughness = 0.9
	var gullet := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(wide, sc * 1.0, length)
	gb.material = gm
	gullet.mesh = gb
	gullet.position = Vector3(((xlo + xhi) * 0.5 - (grid.x - 1) * 0.5) * sc, sc * 0.5, length * 0.5)
	jaw_mouth.add_child(gullet)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color8(0xf2, 0xec, 0xdc)
	tm.roughness = 0.5
	var tb := BoxMesh.new()
	tb.size = Vector3(sc * 0.5, sc * 0.9, sc * 0.5)
	tb.material = tm
	for n in 4:
		var x := (n / 3.0 - 0.5) * wide * 0.8
		var up := MeshInstance3D.new()
		up.mesh = tb
		up.position = Vector3(x, sc * 0.7, length - sc * 0.4)
		jaw_mouth.add_child(up)
		var lo := MeshInstance3D.new()
		lo.mesh = tb
		lo.position = Vector3(x, sc * 0.4, length - sc * 0.5)
		jaw_pivot.add_child(lo)

## Opens the jaw toward `gape` radians (smoothly).
func set_gape(gape: float, dt: float) -> void:
	if jaw_pivot == null:
		return
	jaw_angle += (gape - jaw_angle) * minf(1.0, dt * 18.0)
	jaw_pivot.basis = Basis(Vector3.RIGHT, jaw_angle)
	jaw_mouth.visible = jaw_angle > 0.08

## Puts voxels back (a mended limb in a replay, a net message out of order).
func restore_voxels(indices: Array) -> void:
	for i in indices:
		if i >= 0 and i < fx.size() and alive[i] == 0:
			alive[i] = 1
			alive_count += 1
	set_shown(indices, true)
	fit_collider()

## The collision shape follows the flesh once the part has a hole (see the class comment).
func fit_collider() -> void:
	var w := dims.x; var h := dims.y; var d := dims.z
	var n := w * h * d
	var res := Data.body_res
	var total := PackedInt32Array(); total.resize(n)
	var live := PackedInt32Array(); live.resize(n)
	for i in fx.size():
		var c := int(fx[i] / res) + w * (int(fy[i] / res) + h * int(fz[i] / res))
		if c < 0 or c >= n:
			continue
		total[c] += 1
		if alive[i]:
			live[c] += 1
	var solid := PackedByteArray(); solid.resize(n)
	var holes := 0
	var any := 0
	for c in n:
		solid[c] = 1 if (total[c] > 0 and live[c] * 2 >= total[c]) else 0
		if total[c] > 0 and solid[c] == 0:
			holes += 1
		any += solid[c]
	if holes == 0:
		if split:
			_drop_boxes(true)
		return
	if any == 0:
		for c in n:
			solid[c] = 1 if live[c] > 0 else 0
	var fleshy := solid.duplicate()
	for z in d:
		for y in h:
			for x in w:
				var c := x + w * (y + h * z)
				if total[c] > 0:
					continue
				solid[c] = 1 if (_nb(fleshy, w, h, d, x - 1, y, z) or _nb(fleshy, w, h, d, x + 1, y, z) or _nb(fleshy, w, h, d, x, y - 1, z) or _nb(fleshy, w, h, d, x, y + 1, z) or _nb(fleshy, w, h, d, x, y, z - 1) or _nb(fleshy, w, h, d, x, y, z + 1)) else 0
	_drop_boxes(false)
	split = true
	main_shape.disabled = true
	var k := half_ext * 2.0 / Vector3(w, h, d)
	for b in Greedy.boxes(w, h, d, solid):
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(b[3] - b[0] + 1, b[4] - b[1] + 1, b[5] - b[2] + 1) * k
		cs.shape = shape
		cs.position = Vector3((b[0] + b[3] + 1) * 0.5 - w * 0.5, (b[1] + b[4] + 1) * 0.5 - h * 0.5, (b[2] + b[5] + 1) * 0.5 - d * 0.5) * k
		add_child(cs)
		boxes.append(cs)

func _nb(f: PackedByteArray, w: int, h: int, d: int, x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < w and y < h and z < d and f[x + w * (y + h * z)] != 0

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
	var cell := PackedInt32Array(); cell.resize(n)
	var mark := PackedByteArray(); mark.resize(n)
	var count := 0
	var skip := PackedByteArray()
	if not ignore.is_empty():
		skip.resize(fx.size())
		for i in ignore:
			skip[i] = 1
	for i in fx.size():
		if alive[i] and (skip.is_empty() or skip[i] == 0):
			cell[(fx[i] * hf + fy[i]) * df + fz[i]] = i + 1
			count += 1
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
	var nc := Greedy.core() if head_c == null else null
	if nc:
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
func anchor_point(child: VoxelPart) -> Vector3:
	var p := child.pa
	var hx := half_ext / 0.95
	return Vector3(clampf(p.x, -hx.x, hx.x), clampf(p.y, -hx.y, hx.y), clampf(p.z, -hx.z, hx.z))

## Whether a lump holds the root of `child` (its joint point is inside it).
func lump_holds(lump: PackedInt32Array, child: VoxelPart) -> bool:
	var pt := anchor_point(child)
	var r := vf * part_scale * 2.2
	for i in lump:
		if local_of(i).distance_to(pt) < r:
			return true
	return false

func near_child_anchor(lump: PackedInt32Array) -> bool:
	var pts := []
	for c in child_parts:
		if not c.severed:
			pts.append(anchor_point(c))
	if pts.is_empty():
		return false
	var r := vf * part_scale * 2.2
	for i in lump:
		var lp := local_of(i)
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
	if Fx.current == null or Fx.current.headless:
		return
	if on and flames == null:
		flames = BurnFx.make(self, _surface_at_spot("fire"), true, part_scale)
	if flames:
		if flames.emitting and not on:
			_clear_glow(1)
		BurnFx.set_on(flames, on)
		for s in spots:
			if s.kind == "fire" and s.t > 0.0:
				flames.position = s.lp
				break

## Green bubbles of poison rising off the part while acid or venom eats into it (only how it
## looks; Fire.tick does the harm).
func set_poison(on: bool) -> void:
	if Fx.current == null or Fx.current.headless:
		return
	if on and poison_fx == null:
		poison_fx = BurnFx.make(self, _surface_at_spot("acid"), false, part_scale)
	if poison_fx:
		if poison_fx.emitting and not on:
			_clear_glow(2)
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
	add_child(vis)
	var lp: Vector3 = global_transform.affine_inverse() * world_p
	var ld: Vector3 = (global_transform.basis.orthonormalized().inverse() * dir).normalized()
	# Where it entered: back along its line to the surface of the part's box.
	var back := 0.3
	for k in 3:
		var v := -ld[k]
		if absf(v) > 1e-4:
			back = minf(back, maxf(0.0, ((half_ext[k] if v > 0.0 else -half_ext[k]) - lp[k]) / v))
	var entry := lp - ld * back
	# The models' points are at +z: laid along the way it flew (in the part's own frame), point
	# first into the wound, the head, fletching or butt standing out.
	var out := 0.025 if nail else (0.24 if type.begins_with("pot_arrow") else (0.1 if type == "pot_bolt" else 0.12))
	var up := Vector3.UP if absf(ld.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	vis.transform = Transform3D(Basis.looking_at(-ld, up), entry - ld * out)
	stuck.append(vis)

func velocity_at(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - global_position)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Combat.current and state.get_contact_count() > 0:
		Combat.current.report(self, state)
