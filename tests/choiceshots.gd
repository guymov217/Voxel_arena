extends Node
## Every choice Your gladiator has, on the new look (`-- --probe choiceshots`, needs a display):
## rows of five men, each with one choice (his eyes and their colour, his mouth, his face's paint
## and scars, his hair and its colour, his beard, his hat; the skins), close, from in front. ONLY: a
## comma list of the rows (eyes, eye_colour, mouth, face, hair, hair_colour, beard, hat, skin);
## STYLE: the look (human). PNGs to SHOT_DIR, the choices of each picture in the log (CHOICEROW).

var m
var cam: Camera3D
var _warmed := false

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 24.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	# (The first picture waits for the shaders; after it a few frames bring the scene up to date.)
	var warm := 4 if RenderingServer.render_loop_enabled else (5 if _warmed else 40)
	RenderingServer.render_loop_enabled = true
	for i in warm:
		await get_tree().process_frame
	_warmed = true
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("ONLY")
	Physique.forced = OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3})
	m.me.f.teleport(Vector3(0, 0, 30))
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	RenderingServer.render_loop_enabled = false
	var slots: Dictionary = load("res://scripts/ui/menu.gd").LOOK_SLOTS
	var rows := []
	for k in ["eyes", "eye_colour", "mouth", "face", "hair", "hair_colour", "beard", "hat"]:
		if slots.has(k):
			rows.append([k, slots[k]])
	rows.append(["skin", Fighter.SKINS])
	for row in rows:
		var kind: String = row[0]
		if only != "" and not only.split(",").has(kind):
			continue
		var items: Array = row[1]
		var at := 0
		var n := 0
		while at < items.size():
			var men := []
			var names := []
			for j in range(at, mini(at + 5, items.size())):
				var it = items[j]
				var arm := []
				var faces := ["none"]   # (a plain face: no eyes nor mouth chosen, nor a bot's own)
				var skin := 0xc68a5a
				match kind:
					"eyes", "mouth", "face", "eye_colour":
						if String(it) != "":
							faces = [String(it)]
					"hair_colour":
						# (shown on long hair and a full beard)
						arm = ["hair_long", "beard_full"]
						if String(it) != "":
							faces = [String(it)]
					"hair", "beard", "hat":
						if String(it) != "":
							arm = [String(it)]
					"skin":
						skin = int(it)
				var e = m.spawn_fighter({"kind": "bot", "name": "Look %s %d" % [kind, j], "loadout": {"main": "", "off": "", "armor": arm},
					"team": 1, "pos": Vector3((float(j - at) - 2.0) * 0.66, 0.1, 0.0), "yaw": 0.0, "skin": skin, "build": "hero"})
				e.erase("bot")
				e.drive = func(_e): return {"main": {"x": 0.1, "y": -0.7}, "off": {"x": -0.1, "y": -0.7}}
				var f: Fighter = e.f
				f.face_ids = faces
				f.build_pref = "hero"
				Physique.dress(f)
				men.append(e)
				names.append(str(it) if kind != "skin" else "%06x" % int(it))
			get_tree().paused = false
			RenderingServer.render_loop_enabled = false   # (the men settle undrawn: a drawn frame is slow)
			for i in 90:
				await get_tree().physics_frame
			get_tree().paused = true
			var hy := 0.0
			for e in men:
				hy += (e.f as Fighter).head.global_position.y
			hy /= float(men.size())
			var nm := "choice_%s_%d.png" % [kind, n]
			print("CHOICEROW ", nm, " ", ",".join(names))
			await _snap(out, nm, Vector3(0.0, hy + 0.06, 4.6), Vector3(0.0, hy - 0.04, 0.0), 26.0)
			for e in men:
				m.entities.erase(e)
				(e.f as Node).queue_free()
			await get_tree().process_frame
			at += 5
			n += 1
	get_tree().quit()
