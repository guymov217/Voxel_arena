extends Node
## A frame from the kill cam (`-- --probe killcamshot`, needs a display): a duel where the
## player beheads his man; the replay is caught halfway. PNG to SHOT_DIR.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var out := OS.get_environment("SHOT_DIR")
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	menu.start({"mode": "duel", "decrees": [], "hazards": []})
	var m: Match = menu.match_
	m.me.bot = Bot.new(m.me.f, 0.9, "standard", 1)
	for i in 120 * 5:
		await get_tree().physics_frame
	var foe = m.enemies()[0].f
	foe.last_attacker = m.me.f
	foe.head.severed = true
	foe.die("decap")
	# The duel ends by itself; the kill cam starts a moment later.
	while not m.killcam.playing:
		await get_tree().process_frame
	for i in 75:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("killcam.png"))
	print("saved killcam")
	get_tree().quit()
