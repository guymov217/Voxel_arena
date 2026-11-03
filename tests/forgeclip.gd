extends Node
## The forge at work, for the trailer (`-- --probe forgeclip`, needs a display; run through
## tools/make_trailer.sh with the movie maker on). A weapon goes up on the anvil voxel by voxel,
## from the grip to the tip, while the camera turns slowly round it. FORGE_DESIGN names the
## ready-made weapon to build (default the executioner's axe); FORGE_SECONDS how long it takes.
## FORGE_CINE=1 (the crowd trailer): the anvil's view alone over the whole screen, the editor's
## panels and its marks on the work put away, the camera drawing back and round as the weapon
## grows, holding on it whole at the end (the cut goes from it to the same axe in the arena).

func _ready() -> void:
	var key := OS.get_environment("FORGE_DESIGN") if OS.get_environment("FORGE_DESIGN") != "" else "executionerAxe"
	var seconds := float(OS.get_environment("FORGE_SECONDS")) if OS.get_environment("FORGE_SECONDS") != "" else 5.0
	var cine := OS.get_environment("FORGE_CINE") == "1"
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	for i in 20:
		await get_tree().process_frame
	var d: Dictionary = Data.preset(key).duplicate(true)
	var f = load("res://scripts/ui/forge.gd").new()
	f.free_build = true
	f.workshop = true
	menu.add_child(f)
	f.open(d, 0, func(_d, _c): pass)
	await get_tree().process_frame
	if cine:
		_full_view(f)
		_clean(f)
		await get_tree().process_frame
	# The whole weapon framed first, for the film's camera to end on (framed on the grip alone, the
	# head grew up out of the picture).
	f._rebuild()
	f._frame()
	var dist1: float = f.dist
	var focus1: Vector3 = f.focus
	var pitch1: float = f.orbit.y
	# Every voxel of it, lowest first: the grip, then the haft, then the head.
	var all: Array = f.cells.keys()
	all.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var full: Dictionary = f.cells.duplicate(true)
	f.cells.clear()
	for k in all.slice(0, 3):
		f.cells[k] = full[k]
	f._rebuild()
	if not cine:
		f._frame()
	f.moved = true
	_tag("REC_START %d" % Engine.get_frames_drawn())
	var frames := int(seconds * 30.0)
	var per := ceili(float(all.size()) / frames)
	var i := 3
	var n := 0
	while i < all.size():
		for k in all.slice(i, i + per):
			f.cells[k] = full[k]
		i += per
		f._rebuild()
		n += 1
		if cine:
			_clean(f)
			_cine_camera(f, clampf(float(n) / frames, 0.0, 1.0), dist1, focus1, pitch1)
		else:
			f.orbit.x += 0.012
			f._place_camera()
		await get_tree().process_frame
	for j in (30 if not cine else 45):
		if cine:
			_clean(f)
			f.orbit.x += 0.004
			f._place_camera()
		else:
			f.orbit.x += 0.012
			f._place_camera()
		await get_tree().process_frame
	_tag("REC_END %d" % Engine.get_frames_drawn())
	get_tree().quit()

## The anvil's view alone, the whole screen: the editor's panel, its tool bar and its badges put
## away (the crowd trailer's forge is a shot of the anvil, not of the editor).
func _full_view(f) -> void:
	var box: Control = f.view_box
	var row = box.get_parent()
	for c in row.get_children():
		if c != box and c is Control:
			c.visible = false
	for c in box.get_children():
		if c is Control and not (c is SubViewportContainer):
			c.visible = false

## What the editor lays over the work (the price, the hands' rings and their tags, the balance
## mark), put away again after each rebuild brings it back: the film's anvil carries the weapon
## and nothing else.
func _clean(f) -> void:
	if f.price_badge and is_instance_valid(f.price_badge):
		# (Shown again by the editor as the price changes: see-through, it stays out of sight.)
		(f.price_badge.get_parent() as Control).modulate = Color(1, 1, 1, 0)
	for nd in f.ring_nodes:
		if is_instance_valid(nd):
			nd.visible = false
	if f.com_mark and is_instance_valid(f.com_mark):
		# (Its showing is set again every frame by the editor: shrunk to nothing, it stays unseen.)
		f.com_mark.scale = Vector3.ZERO

## The film's move round the anvil, `u` from 0 to 1 as the weapon goes up: a little closer than
## the whole weapon's framing and a little lower at first, drawing back and up to it, turning
## slowly the while. (Closer and lower still, the anvil's top filled the screen.)
func _cine_camera(f, u: float, dist1: float, focus1: Vector3, pitch1: float) -> void:
	var e := u * u * (3.0 - 2.0 * u)
	f.dist = lerpf(dist1 * 0.52, dist1 * 0.7, e)
	# The editor aims above the weapon to keep it clear of its tool bar; the film has none: the
	# weapon in the middle of the picture.
	f.focus = focus1 - Vector3(0, f.AIM_RISE * f.dist, 0)
	f.orbit.y = lerpf(pitch1 * 0.6, pitch1 * 0.9, e)
	f.orbit.x += 0.009
	f._place_camera()

## Each timing tag goes to stdout and, when TAG_LOG names a file, there too: the window build of
## Godot on Windows (not the *_console.exe) prints nothing to a pipe, and the trailer kit reads
## the shots' frames from these lines.
var _tags := PackedStringArray()
func _tag(line: String) -> void:
	print(line)
	var path := OS.get_environment("TAG_LOG")
	if path == "":
		return
	_tags.append(line)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_tags) + "\n")
