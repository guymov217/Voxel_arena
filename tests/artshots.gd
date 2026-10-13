extends Node
## The arena's art from set places (`-- --probe artshots`, needs a display): a training bout, then
## the camera taken off the player and put where each part of the bowl shows best; then the yard
## with its stations. PNGs go to SHOT_DIR, named SHOT_TAG_<view>. SHOT_ONLY=arena|yard.

const VIEWS := [
	["wide", Vector3(0, 6.5, -13.5), Vector3(0, 2.0, 6)],
	["low", Vector3(2.5, 0.7, -3.5), Vector3(-1.0, 1.6, 8.0)],
	["gate", Vector3(8.5, 1.7, -4.5), Vector3(15.0, 2.0, 0.0)],
	["box", Vector3(-2.5, 2.0, 7.5), Vector3(0.0, 4.0, 17.0)],
	["stands", Vector3(-6.0, 1.6, -6.0), Vector3(-13.0, 5.0, 10.0)],
	["wall", Vector3(4.0, 1.2, -10.5), Vector3(10.5, 1.0, -10.5)],
	["arcade", Vector3(0, 2.0, 0), Vector3(-10.0, 9.5, -21.0)],
]

func _save(name_: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("%s_%s.png" % [OS.get_environment("SHOT_TAG"), name_]))
	print("saved ", name_)

func _ready() -> void:
	var only := OS.get_environment("SHOT_ONLY")
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	if only == "" or only == "title":
		for i in 120 * 4:
			await get_tree().physics_frame
		await _save("title")
	if only == "" or only == "arena":
		menu.start({"mode": "training", "training": {"enemy": "gladiator", "behaviour": "moves", "weapon": "axe"}})
		var m: Match = menu.match_
		for i in 120 * 2:
			await get_tree().physics_frame
		await _save("player")
		m.set_process(false)
		var cam: Camera3D = m.cam
		cam.set_process(false)
		for v in VIEWS:
			cam.global_position = v[1]
			cam.look_at(v[2], Vector3.UP)
			await _save(v[0])
		# Close on the fighters, to see the bodies, armour and weapons.
		var t: Vector3 = m.me.f.torso.global_position
		cam.global_position = t + Vector3(1.3, 0.25, 1.6)
		cam.look_at(t + Vector3(0, 0.1, 0), Vector3.UP)
		await _save("fighter")
		for e in m.entities:
			if e != m.me and e.f and is_instance_valid(e.f.torso):
				var et: Vector3 = e.f.torso.global_position
				cam.global_position = et + Vector3(-1.2, 0.3, -1.5)
				cam.look_at(et + Vector3(0, 0.1, 0), Vector3.UP)
				await _save("enemy")
				break
		m.set_process(true)
		cam.set_process(true)
	if only == "" or only == "yard":
		menu.enter_yard()
		var y: Match = menu.match_
		for i in 120 * 2:
			await get_tree().physics_frame
		await _save("yard_player")
		y.set_process(false)
		var yc: Camera3D = y.cam
		yc.set_process(false)
		for v in [["yard_smith", Vector3(-4.5, 2.2, 1.5), Vector3(-11.5, 1.0, 6.5)], ["yard_market", Vector3(4.5, 2.2, 1.5), Vector3(11.5, 1.0, 6.5)],
				["yard_board", Vector3(2.5, 2.0, -5.0), Vector3(-2.0, 1.2, -12.5)], ["yard_targets", Vector3(5.0, 2.0, -2.0), Vector3(11.5, 1.4, -6.5)]]:
			yc.global_position = v[1]
			yc.look_at(v[2], Vector3.UP)
			await _save(v[0])
	get_tree().quit()
