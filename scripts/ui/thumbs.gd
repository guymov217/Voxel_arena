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
		rect.get_tree().root.add_child(_studio)
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

## The model a kit item is drawn with (throwables.js kitItemType).
static func item_type(id: String) -> Variant:
	if Throwables.POTS.has(id):
		return Throwables.POTS[id]
	return {"darts": "pot_dart", "boomerang": "boomerang", "bananas": "banana", "cheese": "cheese", "bread": "bread", "wine": "wine", "bandage": "bandage"}.get(id)

func _ready() -> void:
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
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.rotation = Vector3(-0.9, 0.6, 0)
	vp.add_child(sun)
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
		if n is MeshInstance3D:
			var b: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
	var c := box.get_center()
	var r := maxf(0.05, box.size.length() * 0.5)
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 1.02
	cam.position = c + Vector3(0.75, 0.55, 1.0).normalized() * dist
	cam.look_at(c, Vector3.UP)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
	cache[q.key] = tex
	for rect in q.rects:
		if is_instance_valid(rect):
			rect.texture = tex
	obj.queue_free()
	busy = false
