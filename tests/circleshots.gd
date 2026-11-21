extends Node
## The team circles in the yard (`-- --probe circleshots`, needs a display): the yard of a friends' room with the two circles
## laid for a team fight, seen as the host sees it and from above, with a friend standing in the blue one. PNGs go to SHOT_DIR
## as circles_<name>.png.

func _snap(name: String, frames := 50) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("circles_%s.png" % name))
	print("saved ", name)

func _ready() -> void:
	var st: Dictionary = Save.get_value("settings", {})
	st["quality"] = "low"
	Save.set_value("settings", st)
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	for i in 30:
		await get_tree().process_frame
	Net.transport = "test"
	Net.room_kind = Net.KIND_ARENA
	Net.my_name = "Aulus"
	menu._box_on()
	menu.enter_yard()
	for i in 40:
		await get_tree().process_frame
	var m: Match = menu.match_
	m.input.enabled = false
	menu.visible = false
	# A friend in the yard too (a bot's body standing for him), the circles laid.
	var friend = m.spawn_fighter({"kind": "remote", "peer": 9, "name": "Brutus", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 0, "pos": Vector3(TeamSetup.CENTRES[1].x + 0.5, 0.02, TeamSetup.CENTRES[1].z), "yaw": 0.0})
	m.yard.begin_teams("teams", {"rounds": 3})
	m.me.f.teleport(Vector3(0, 0, -3))
	await _snap("host_view")
	m.me.f.teleport(Vector3(TeamSetup.CENTRES[0].x, 0, TeamSetup.CENTRES[0].z))
	await _snap("host_in_red", 70)
	# From above.
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.global_position = Vector3(0, 24, 7)
	cam.look_at(Vector3(0, 0, 1), Vector3.FORWARD)
	cam.fov = 55.0
	cam.current = true
	await _snap("from_above", 30)
	print("line: ", m.yard.team_line())
	Net.transport = ""
	menu._box_off()
	get_tree().quit()
