class_name Thumbs
extends Node
## Shop pictures (thumbs.js): each product's own model, the same one that flies in the arena,
## rendered once in a little studio of its own to a transparent image, three-quarter view, and
## cached. Pictures are made one per frame; a TextureRect asked for one gets it when it is ready.

const SIZE := 160
const FILL := 1.6           # of the frame's 2 (-1 to 1) the thing may span: a margin all round
static var cache := {}
static var _studio: Thumbs = null

var vp: SubViewport
var cam: Camera3D
var queue: Array = []        # [{key, build: Callable, rects: [TextureRect]}]
var busy := false
var warm := false

## Puts the picture for `key` on `rect` (now if it is made, else when it is). `build` returns
## a Node3D with the model. Nothing is drawn without a renderer (headless).
static func put(rect: TextureRect, key: String, build: Callable) -> void:
	if cache.has(key):
		rect.texture = cache[key]
		return
	if DisplayServer.get_name() == "headless" or not rect.is_inside_tree():
		return
	if _studio == null or not is_instance_valid(_studio):
		_studio = Thumbs.new()
		rect.get_tree().root.add_child.call_deferred(_studio)
	for q in _studio.queue:
		if q.key == key:
			q.rects.append(rect)
			return
	_studio.queue.append({"key": key, "build": build, "rects": [rect]})

## The picture of a market item (its thrown or held model), by kit id.
static func item(rect: TextureRect, id: String) -> void:
	var type = item_type(id)
	if type == null:
		return
	put(rect, "item:" + id, func():
		var g := Items.visual(type)
		lay_across(g)
		return g)

## A long thin thing modelled nose along +z (a dart, a bolt, an arrow) came out end-on to the
## three-quarter camera, a dot in the middle of its slot: lay it across the view at a slant.
static func lay_across(g: Node3D) -> void:
	var box := AABB()
	var first := true
	for c in g.get_children():
		if c is MeshInstance3D and c.mesh:
			var b: AABB = c.transform * c.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	if not first and box.size.z > 1.8 * maxf(box.size.x, box.size.y):
		g.rotation = Vector3(-0.45, 2.2, 0.0)

## The picture of a weapon design (the smith's wares, your own arms as they are now), laid at
## a slant like a blade on the counter. `key` names it in the cache (a design that changes,
## a chipped blade, an upgrade, needs its own key).
static func weapon(rect: TextureRect, d: Dictionary, key: String) -> void:
	if not (d.get("voxels") is Array) or d.voxels.is_empty():
		return
	put(rect, "weapon:" + key, func():
		var root := model(d)
		var mi: Node3D = root.get_child(0)
		mi.rotation = Vector3(0.0, 0.5, -0.75)
		return root)

## The picture of a prosthetic on the smith's counter, as the physician made it and the smith
## has worked it (`level`, Body.PRO_STEPS): built from the very cells it is fitted with
## (Fighter.prosthetic_cell over the part it takes the place of), a blade arm with its blade.
static func prosthetic(rect: TextureRect, kind: String, part: String, level: int) -> void:
	put(rect, "pro:%s:%s:%d" % [kind, part, level], func():
		var root := Node3D.new()
		var g := Node3D.new()
		root.add_child(g)
		var metal := []
		var matte := []
		var vf: float = Data.body_voxel / Data.body_res
		for d in Data.body_parts:
			if d.name != part:
				continue
			var dd: Array = d.get("dims", [1, 1, 1])
			var ga: Array = d.get("grid", [int(dd[0]) * Data.body_res, int(dd[1]) * Data.body_res, int(dd[2]) * Data.body_res])
			var grid := Vector3i(int(ga[0]), int(ga[1]), int(ga[2]))
			for v in d.voxels:
				var cell = Fighter.prosthetic_cell(kind, int(v[0]), int(v[1]), int(v[2]), grid, level)
				if cell == null:
					continue
				var at := Vector3(float(v[0]) - (grid.x - 1) * 0.5, float(v[1]), float(v[2]) - (grid.z - 1) * 0.5) * vf
				(metal if int(cell[1]) in [3, 4, 13] else matte).append([at, vf, cell[0]])
		if kind == "blade":
			# The blade below the socket, its tang (the grip) hidden in it.
			var wv: float = Data.weapon_voxel
			for v in Fighter.blade_arm(level).voxels:
				if String(v[4]) == "grip":
					continue
				metal.append([Vector3(float(v[0]), 2.0 - float(v[1]), float(v[2])) * wv, wv, Weapon.voxel_color(str(v[3]), str(v[4]))])
		for set_ in [[metal, 0.4, 0.45], [matte, 0.0, 0.85]]:
			var cells: Array = set_[0]
			if cells.is_empty():
				continue
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.metallic = set_[1]
			mat.roughness = set_[2]
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.98
			bm.material = mat
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = bm
			mm.instance_count = cells.size()
			var lo := Vector3.INF
			var hi := -Vector3.INF
			for i in cells.size():
				var c: Array = cells[i]
				var s := float(c[1])
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), c[0]))
				mm.set_instance_color(i, c[2])
				lo = lo.min(c[0] - Vector3.ONE * s * 0.5)
				hi = hi.max(c[0] + Vector3.ONE * s * 0.5)
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.custom_aabb = AABB(lo, hi - lo)
			g.add_child(mi)
		# Laid on the counter at a slant: an arm with its end toward the viewer, a peg upright.
		g.rotation = Vector3(0.0, 0.6, 0.0) if kind == "peg" else Vector3(0.0, 0.5, -2.2)
		return root)

## The weapon's model as the shop draws it (the voxels, a chain's links and head hung on above
## the handle): a Node3D with one MultiMeshInstance3D, the grip at the origin.
static func model(d: Dictionary) -> Node3D:
	var root := Node3D.new()
	var vs: float = Data.weapon_voxel
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.35
	mat.metallic = 0.35
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * vs * 0.98
	bm.material = mat
	# A chain weapon: its links and head hang on above the handle, as it is carried.
	var all: Array = d.voxels.duplicate()
	var c = d.get("chain")
	if c is Dictionary and c.get("head") is Dictionary:
		var top := -INF
		for v in d.voxels:
			top = maxf(top, float(v[1]))
		var links := int(c.get("links", 4))
		var gap := mini(links, 8) * 1.6
		for k in mini(links, 8):
			all.append([0, top + 1.0 + k * 1.6, 0, "iron", "blunt"])
		var hlo := INF
		for v in c.head.voxels:
			hlo = minf(hlo, float(v[1]))
		for v in c.head.voxels:
			all.append([v[0], float(v[1]) - hlo + top + 1.0 + gap, v[2], v[3], v[4]])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	mm.instance_count = all.size()
	for i in all.size():
		var v: Array = all[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(float(v[0]), float(v[1]), float(v[2])) * vs))
		mm.set_instance_color(i, Weapon.voxel_color(str(v[3]), str(v[4])))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	# Its box from the voxels themselves (the renderer's own is filled in late, and a picture
	# framed by it cut the end off a long weapon).
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in all:
		var q := Vector3(float(v[0]), float(v[1]), float(v[2])) * vs
		lo = lo.min(q)
		hi = hi.max(q)
	if not all.is_empty():
		mi.custom_aabb = AABB(lo - Vector3.ONE * vs * 0.5, hi - lo + Vector3.ONE * vs)
	root.add_child(mi)
	return root

## The model a kit item is drawn with (throwables.js kitItemType).
static func item_type(id: String) -> Variant:
	if Throwables.POTS.has(id):
		return Throwables.POTS[id]
	return {"darts": "pot_dart", "boomerang": "boomerang", "bananas": "banana", "cheese": "cheese", "bread": "bread", "wine": "wine", "bandage": "bandage", "telekinesis": "gauntlet"}.get(id)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pictures come in behind a paused game too
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.93, 0.82)
	e.ambient_light_energy = 0.85
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.rotation = Vector3(-0.9, 0.6, 0)
	vp.add_child(sun)
	# A rim from behind and above: the outline of a dark thing (a purple thunder pot, a black
	# nail pot) stands out on the hotbar's dark iron instead of sinking into it.
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.1
	rim.light_color = Color(1.0, 0.95, 0.85)
	rim.rotation = Vector3(-0.5, PI + 0.6, 0)
	vp.add_child(rim)
	cam = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)

func _process(_dt: float) -> void:
	if busy or queue.is_empty():
		return
	_make(queue.pop_front())

func _make(q: Dictionary) -> void:
	busy = true
	var obj: Node3D = q.build.call()
	vp.add_child(obj)
	# Fit it in the frame, whatever its size: a dart or an anvil.
	var box := AABB()
	var first := true
	var stack: Array = [obj]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			var gi := n as GeometryInstance3D
			var own: AABB = gi.custom_aabb if gi.custom_aabb.size != Vector3.ZERO else (gi.multimesh.get_aabb() if gi is MultiMeshInstance3D else gi.get_aabb())
			var b: AABB = gi.global_transform * own
			box = b if first else box.merge(b)
			first = false
	var c := box.get_center()
	var r := maxf(0.05, box.size.length() * 0.5)
	var dir := Vector3(0.75, 0.55, 1.0).normalized()
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 1.15   # with a margin: nothing at the edge is cut
	cam.position = c + dir * dist
	cam.look_at(c, Vector3.UP)
	# Then framed on the picture itself: the box's corners as the camera sees them, centred and
	# filling at most FILL of the frame (a long blade on the slant was off to one side).
	var corners := []
	for i in 8:
		corners.append(box.get_endpoint(i))
	for k in 2:
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for p3 in corners:
			var p2 := _seen(p3)
			lo = lo.min(p2)
			hi = hi.max(p2)
		var mid := (lo + hi) * 0.5
		var span := maxf(hi.x - lo.x, hi.y - lo.y)
		# Move the aim to the middle of what is seen, and the camera in or out to fit.
		var right := cam.global_transform.basis.x
		var up := cam.global_transform.basis.y
		var half := tan(deg_to_rad(cam.fov * 0.5))
		c += (right * mid.x + up * mid.y) * dist * half
		dist *= maxf(0.2, span / FILL)
		cam.position = c + dir * dist
		cam.look_at(c, Vector3.UP)
	for tries in 4:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not warm:
			# The studio's first frame comes out before its world is set up: shoot it again.
			warm = true
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
		# Last of all the picture is looked at: anything touching its edge, and it is shot again
		# from further back.
		if not _touches_edge(vp.get_texture().get_image()):
			break
		dist *= 1.25
		cam.position = c + dir * dist
		cam.look_at(c, Vector3.UP)
	var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
	cache[q.key] = tex
	for rect in q.rects:
		if is_instance_valid(rect):
			rect.texture = tex
	obj.queue_free()
	busy = false

## Where the camera sees `p`, from -1 to 1 across and up the frame.
func _seen(p: Vector3) -> Vector2:
	var l := cam.global_transform.affine_inverse() * p
	var half := tan(deg_to_rad(cam.fov * 0.5))
	var z := maxf(0.001, -l.z)
	return Vector2(l.x / (z * half), l.y / (z * half))

## Something drawn in the outermost pixels of the picture (it would look cut off).
static func _touches_edge(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	for i in w:
		for y in [0, 1, h - 2, h - 1]:
			if img.get_pixel(i, y).a > 0.1:
				return true
	for j in h:
		for x in [0, 1, w - 2, w - 1]:
			if img.get_pixel(x, j).a > 0.1:
				return true
	return false
