extends Node
## Forge and Fight, the host's whole way through (`-- --probe ffprobe`, headless): the times set,
## the forges lit, a weapon on the anvil when the clock runs out (taken as it stands), the bench
## open when the armour's time is up (closed), the forges going cold, and the fight begun with
## what was made. Prints FF lines and "FF done"; any script error on the way shows in the log.

func _ready() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	for i in 10:
		await get_tree().process_frame
	var err: int = Net.host_enet()
	print("FF host ", err)
	menu.ff_setup()
	await _frames(5)
	print("FF setup screen: ", menu.screen)
	menu._ff_begin({"weapons": 1, "armour": 1, "fight": 2}, true)
	await _frames(5)
	print("FF phase ", menu.ff.get("phase"), " screen ", menu.screen)
	# A weapon on the anvil: a haft and a blade.
	menu._ff_forge("main")
	await _frames(20)
	var f = menu.ff_open
	if f and f.has_method("_design_now"):
		for y in range(1, 4):
			f.cells[Vector3i(0, y, 0)] = ["wood", "grip", -1]
		for y in range(4, 12):
			f.cells[Vector3i(0, y, 0)] = ["steel", "edge", -1]
	# The clock runs out with the forge open.
	menu._ff_phase("armour")
	await _frames(5)
	var main = menu.ff.kit.main if not menu.ff.is_empty() else null
	print("FF kept from the anvil: ", (main.voxels as Array).size() if main is Dictionary else main, " phase ", menu.ff.get("phase"))
	menu.bench_mode = "contest"
	menu._plate_bench(Armory.design_piece("torso", "iron", 0.3, 1.0, false, true, "Probe plate"), 0.0)
	await _frames(20)
	print("FF bench open: ", menu.ff_open != null)
	menu._ff_phase("fight")
	await _frames(5)
	print("FF closing: ", menu.ff.get("phase"))
	for i in 120 * 3:
		await get_tree().physics_frame
	var m = menu.match_
	print("FF fight: ", m != null and is_instance_valid(m), " mode ", m.mode if m else "-", " fighters ", m.entities.size() if m else 0)
	if m and m.me:
		var w = m.me.f.weapons.get("R")
		print("FF my weapon: ", w.design.get("name", "?") if w else "fists", " voxels ", (w.design.voxels as Array).size() if w else 0)
	print("FF ff state cleared: ", menu.ff.is_empty())
	Net.leave()
	print("FF done")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
