class_name Thumbs
extends Node
## Shop pictures (thumbs.js): each product's own model, the same one that flies in the arena,
## rendered once in a little studio of its own to a transparent image, three-quarter view, and
## cached. Pictures are made one per frame; a TextureRect asked for one gets it when it is ready.

const SIZE := 160
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
	put(rect, "item:" + id, func(): return Items.visual(type))

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
	return {"darts": "pot_dart", "boomerang": "boomerang", "bananas": "banana", "cheese": "cheese", "bread": "bread", "wine": "wine", "bandage": "bandage"}.get(id)

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
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 1.15   # with a margin: nothing at the edge is cut
	cam.position = c + Vector3(0.75, 0.55, 1.0).normalized() * dist
	cam.look_at(c, Vector3.UP)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not warm:
		# The studio's first frame comes out before its world is set up: shoot it again.
		warm = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
	var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
	cache[q.key] = tex
	for rect in q.rects:
		if is_instance_valid(rect):
			rect.texture = tex
	obj.queue_free()
	busy = false
