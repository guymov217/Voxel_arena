extends Node
## The thrust on screen (`-- --probe thrustshots`, needs a display): a man facing a still foe, the
## crosshair on him; the plain crosshair, then the thrust switched on (the spear's point over a
## ring, the depth bar empty, THRUST and how to stab under it), then the blade pushed most of the
## way in (the bar filled). PNGs go to SHOT_DIR.

var m: Match
var push := -1.0   # the depth held each step while pushing (the button down), -1 for none

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
	m.input.thrust_on = true
	for i in 120:
		await get_tree().physics_frame
	await _save(out, "thrust_on.png")
	push = 0.75
	for i in 60:
		await get_tree().physics_frame
	await _save(out, "thrust_push.png")
	get_tree().quit()

func _physics_process(_dt: float) -> void:
	# (The button held and the mouse pushed: what the mouse would do, set before the match reads
	# the input this step.)
	if push >= 0.0 and m and m.input:
		m.input.lmb = true
		m.input.depth = push

func _save(out: String, name_: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name_))
	print("saved ", name_)
