extends Node
## The thrust on screen (`-- --probe thrustshots`, needs a display): a man facing a still foe, the
## crosshair on him; the plain crosshair, then a stab of the thrust key on its way out at the
## crosshair, then the point held out (the key held). PNGs go to SHOT_DIR.

var m: Match
var hold := false   # the thrust key held down

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "gladiator", "weapon": "axe", "difficulty": 0.0, "behaviour": "still"}, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var hud := Hud.new(m)
	add_child(hud)
	for i in 90:
		await get_tree().physics_frame
	var me: Fighter = m.me.f
	var ne = m.nearest_enemy(m.me)
	var to: Vector3 = ne.f.torso.global_position - me.torso.global_position
	m.input.look_yaw = atan2(to.x, to.z)
	m.input.look_pitch = -0.12
	for i in 120:
		await get_tree().physics_frame
	await _save(out, "thrust_off.png")
	m.input.stab_left = PlayerInput.STAB_MIN   # (a tap of the key: the stab on its way)
	for i in 30:
		await get_tree().physics_frame
	await _save(out, "thrust_stab.png")
	hold = true
	for i in 90:
		await get_tree().physics_frame
	await _save(out, "thrust_held.png")
	get_tree().quit()

func _physics_process(_dt: float) -> void:
	# (The key held: what holding it does, set before the match reads the input this step.)
	if hold and m and m.input:
		m.input.stab_left = PlayerInput.STAB_MIN

func _save(out: String, name_: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name_))
	print("saved ", name_)
