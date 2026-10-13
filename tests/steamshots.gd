extends Node
## Store-page screenshots (`-- --probe steamshots`, needs a display; run the window at 1920x1080).
## The title screen and the gladiator editor, then fights caught at the moment of a hard blow:
## each scene starts a mode with every fighter on autopilot, waits for a hit strong enough to
## spray blood, and frames the two fighters side-on with the stands behind them (no HUD, except
## for one shot from the player's own camera). PNGs go to SHOT_DIR; SHOT_ONLY picks one scene.

var menu
var out := ""
var big: Dictionary = {}
var wanted := 30.0
var want_me := false

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("SHOT_ONLY")
	menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	if only == "" or only == "menu":
		for i in 120 * 5:
			await get_tree().physics_frame
		_save("01_title")
		menu.show_screen("gladiator")
		for i in 120 * 3:
			await get_tree().physics_frame
		_save("02_your_gladiator")
		menu.show_screen("main")
	var scenes := [
		{"name": "03_clash", "opts": {"mode": "duel"}, "J": 30.0, "cam": "close"},
		{"name": "04_bloodbath", "opts": {"mode": "ffa"}, "J": 40.0, "cam": "close"},
		{"name": "05_monster_hunt", "opts": {"mode": "hunt"}, "J": 25.0, "cam": "wide"},
		{"name": "06_chaos_decrees", "opts": {"mode": "chaos"}, "J": 30.0, "cam": "close"},
		{"name": "07_red_vs_blue", "opts": {"mode": "teams"}, "J": 30.0, "cam": "wide"},
		{"name": "08_in_the_fight", "opts": {"mode": "duel"}, "J": 20.0, "cam": "player"},
	]
	for i in 30:
		await get_tree().process_frame
	for sc in scenes:
		if only != "" and only != sc.name:
			continue
		await _scene(sc)
	get_tree().quit()

func _save(nm: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join(nm + ".png"))
	print("saved ", nm)

func _on_hit(h: Dictionary) -> void:
	if not big.is_empty() or float(h.get("J", 0.0)) < wanted or not (h.get("p") is Vector3):
		return
	if want_me and h.get("attacker") != menu.match_.me.f:
		return
	big = h

func _scene(sc: Dictionary) -> void:
	var o: Dictionary = sc.opts.duplicate()
	o["autopilot"] = true
	if o.mode != "chaos":
		o["decrees"] = []
		o["hazards"] = []
	menu.start(o)
	var m = menu.match_
	big = {}
	wanted = sc.J
	want_me = sc.cam == "player"
	# Warm up (spawning, the banner), then wait for a good blow; lower the bar if none comes.
	for i in 120 * 3:
		await get_tree().physics_frame
	m.combat.hit.connect(_on_hit)
	var waited := 0
	while big.is_empty() and waited < 120 * 40:
		await get_tree().physics_frame
		waited += 1
		if waited % 1200 == 0:
			wanted *= 0.75
	# Three more ticks: the blood is in the air.
	for i in 3:
		await get_tree().physics_frame
	var cam: Camera3D = m.cam
	if sc.cam != "player":
		menu.hud.visible = false
		cam.set_process(false)
		m.set_process(false)
		var p: Vector3 = big.p if not big.is_empty() else Vector3(0, 1, 0)
		var a = big.get("attacker")
		var v = big.get("char")
		var pa: Vector3 = a.torso.global_position if a is Fighter and is_instance_valid(a) else p
		var pv: Vector3 = v.torso.global_position if v is Fighter and is_instance_valid(v) else p
		var c := (pa + pv + p) / 3.0
		var across := pv - pa
		across.y = 0
		if across.length() < 0.2:
			across = Vector3(1, 0, 0)
		var side := across.normalized().cross(Vector3.UP)
		var dist := 2.4 + pa.distance_to(pv) * 0.7 + (2.5 if sc.cam == "wide" else 0.0)
		# Take the side with nobody standing between the camera and the fight; with both clear,
		# the arena's middle side, looking out at the crowd.
		var score := func(sd: Vector3) -> float:
			var eye: Vector3 = c + sd * dist
			var worst := 9.0
			for e in m.entities:
				if not is_instance_valid(e.f) or e.f == a or e.f == v:
					continue
				var q: Vector3 = e.f.torso.global_position
				var t := clampf((q - eye).dot(c - eye) / maxf(0.01, (c - eye).length_squared()), 0.0, 1.0)
				worst = minf(worst, q.distance_to(eye.lerp(c, t)))
			return worst - (c + sd).length() * 0.01
		if score.call(-side) > score.call(side):
			side = -side
		cam.fov = 48.0 if sc.cam == "close" else 56.0
		cam.global_position = c + side * dist + Vector3(0, 0.35 if sc.cam == "close" else 1.4, 0)
		cam.look_at(c + Vector3(0, 0.05, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	_save(sc.name)
	print("  J=%.0f waited %.1f s" % [float(big.get("J", 0.0)), waited / 120.0])
	if menu.hud:
		menu.hud.visible = true
	cam.set_process(true)
	m.set_process(true)
