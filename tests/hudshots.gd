extends Node
## The HUD on show (`-- --probe hudshots`, needs a display): a fight with a man hurt (voxels
## knocked out of him, an arm off, a burning shin, low blood and breath), a sword lying by
## his hand for the prompt, the enemy plate, the feed and a banner; at the window's size and
## at 1280x720. PNGs go to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "gladiator", "weapon": "axe", "difficulty": 0.0, "behaviour": "still"}, "decrees": [], "hazards": []})
	var hud := Hud.new(m)
	add_child(hud)
	var f: Fighter = m.me.f
	for i in 30:
		await get_tree().physics_frame
	# Hurt him: a cut across the chest, a hole in the thigh, the left arm off, a hand burning.
	var res := {"removed": [], "severed": [], "dmg": 0.0}
	f.apply_hit(f.torso, {"impulse": 40.0, "type": "edge", "hardness": 0.9, "sharpness": 1.0, "point": f.torso.global_position + Vector3(0.1, 0.15, 0.14), "dir": Vector3(0, -1, 0), "axis": Vector3.RIGHT, "edge": Vector3.DOWN, "wsz": 1.0})
	f.apply_hit(f.by_name.thighR, {"impulse": 30.0, "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "point": f.by_name.thighR.global_position + Vector3(0, 0, 0.08), "dir": Vector3(0, 0, -1), "crush": 0.09})
	f.detach_limb(f.arm.L.fore, res)
	m.add_spot(f, f.by_name.shinL, "fire", 6.0, null, f.by_name.shinL.global_position)
	f.blood = 22.0
	f.stamina = 18.0
	# A sword by his hand.
	m.spawn_loose_weapon(Data.preset("gladius"), f.hand_world("R") + Vector3(0.25, -0.5, 0.2))
	m.feed.emit("Sparring partner cuts you across the chest")
	m.feed.emit("FIRST BLOOD!")
	m.feed.emit("You lose the left forearm!")
	for i in 40:
		f.blood = 22.0
		f.stamina = 18.0
		await get_tree().physics_frame
	m.banner.emit("Bout 7: the pair", "One on one: Two recruits")
	for i in 20:
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("hud_1080.png"))
	get_window().size = Vector2i(1280, 720)
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("hud_720.png"))
	get_tree().quit()
