extends Node
## The forge at work, for the trailer (`-- --probe forgeclip`, needs a display; run through
## tools/make_trailer.sh with the movie maker on). A weapon goes up on the anvil voxel by voxel,
## from the grip to the tip, while the camera turns slowly round it. FORGE_DESIGN names the
## ready-made weapon to build (default the executioner's axe); FORGE_SECONDS how long it takes.

func _ready() -> void:
	var key := OS.get_environment("FORGE_DESIGN") if OS.get_environment("FORGE_DESIGN") != "" else "executionerAxe"
	var seconds := float(OS.get_environment("FORGE_SECONDS")) if OS.get_environment("FORGE_SECONDS") != "" else 5.0
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
	# Every voxel of it, lowest first: the grip, then the haft, then the head.
	var all: Array = f.cells.keys()
	all.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var full: Dictionary = f.cells.duplicate(true)
	f.cells.clear()
	for k in all.slice(0, 3):
		f.cells[k] = full[k]
	f._rebuild()
	f._frame()
	f.moved = true
	print("REC_START ", Engine.get_frames_drawn())
	var frames := int(seconds * 30.0)
	var per := ceili(float(all.size()) / frames)
	var i := 3
	while i < all.size():
		for k in all.slice(i, i + per):
			f.cells[k] = full[k]
		i += per
		f._rebuild()
		f.orbit.x += 0.012
		f._place_camera()
		await get_tree().process_frame
	for j in 30:
		f.orbit.x += 0.012
		f._place_camera()
		await get_tree().process_frame
	print("REC_END ", Engine.get_frames_drawn())
	get_tree().quit()
