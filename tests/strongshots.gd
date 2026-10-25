extends Node
## The strong man's look in the game's own drawing (`-- --probe strongshots`, needs a display):
## men in the "strong" look holding their weapons in different poses (arms up, out to the side,
## forward, down and behind, a two-handed weapon), so the shoulders, elbows and fists can be seen
## joined in every one. PNGs go to SHOT_DIR.

const POSES := [
	{"name": "UP", "main": "gladius", "off": "scutum", "d": {"main": {"x": 0.1, "y": 1.0}, "off": {"x": -0.1, "y": 1.0}}},
	{"name": "WIDE", "main": "spear", "off": "", "d": {"main": {"x": 1.0, "y": 0.1}, "off": {"x": -1.0, "y": 0.1}}},
	{"name": "FORWARD", "main": "axe", "off": "roundShield", "d": {"main": {"x": 0.3, "y": 0.35}, "off": {"x": -0.35, "y": 0.25}}},
	{"name": "LOW", "main": "dagger", "off": "", "d": {"main": {"x": 0.5, "y": -1.0}, "off": {"x": -0.6, "y": -0.8}}},
	{"name": "TWO HANDS", "main": "warhammer", "off": "", "two": true, "d": {"main": {"x": -0.4, "y": 0.9}, "off": {"x": -0.4, "y": 0.9}}},
]

var m
var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 42.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	for i in 24:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	OS.set_environment("VA_BODIES", "blocky")
	Physique.forced = OS.get_environment("LOOK") if OS.get_environment("LOOK") != "" else "strong"
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
	var skins := [0xc68a5a, 0xa8714a, 0xd9a57a, 0x8d5a3b, 0xc08050]
	# HAIR=1: each man in one of the hairstyles (and a beard), the heads seen close.
	# HAIRS="hair_crop+beard_full,hair_bun,...": one man's pieces each, in order (empty: bare).
	var hair := OS.get_environment("HAIR") == "1" or OS.get_environment("HAIRS") != ""
	var styles := [["hair_mohawk"], ["hair_long", "beard_braided"], ["hair_curly"], ["hair_topknot"], ["hair_ponytail"]]
	if OS.get_environment("HAIRS") != "":
		styles = []
		for one in OS.get_environment("HAIRS").split(","):
			styles.append(Array(one.split("+", false)))
	for i in POSES.size():
		var ps: Dictionary = POSES[i]
		var e = m.spawn_fighter({"kind": "bot", "name": ps.name, "loadout": {"main": ps.main, "off": ps.off, "armor": ((styles[i] if i < styles.size() else []) + ([OS.get_environment("HELM")] if OS.get_environment("HELM") != "" else [])) if hair else (["manica"] if i == 2 else [])}, "team": 1, "pos": Vector3((i - 2) * 1.6, 0.1, 0.0), "yaw": PI, "skin": skins[i]})
		e.erase("bot")
		var d: Dictionary = ps.d
		if hair:
			# (Standing easy, the heads level: the hair is what is being looked at.)
			d = {"main": {"x": 0.25, "y": 0.1}, "off": {"x": -0.3, "y": 0.05}}
		e.drive = func(_e): return d
		if not hair and ps.get("two", false) and e.f.has_method("toggle_grip"):
			e.f.toggle_grip()
	for i in 90:
		await get_tree().physics_frame
	# BREAK=n: n plates of each man's helmet knocked off over his hair (it bursts out there).
	var brk := int(OS.get_environment("BREAK")) if OS.get_environment("BREAK") != "" else 0
	if brk > 0:
		var k := 0
		for e in m.entities:
			if not e.has("f") or e.f == m.me.f:
				continue
			var ads: Array = e.f.head.get_meta("armor", [])
			var cells := {}
			for ad in ads:
				if String(ad.id).begins_with("hair_"):
					for c in ad.cells:
						cells[str(c)] = true
			for ad in ads:
				if String(ad.id) != "helmet":
					continue
				var n := 0
				for ci in ad.cells.size():
					if n < brk + k and cells.has(str(ad.cells[ci])) and (ci + k) % 2 == 0:
						e.f._knock_plate(e.f.head, ad, ci, Vector3.UP, 20.0)
						n += 1
			k += 1
		for i in 40:
			await get_tree().physics_frame
	if hair:
		await _snap(out, "hair_front.png", Vector3(0, 1.75, -4.2), Vector3(0, 1.55, 0), 52.0)
		await _snap(out, "hair_close_a.png", Vector3(-2.4, 1.75, -2.2), Vector3(-2.4, 1.6, 0), 40.0)
		await _snap(out, "hair_close_b.png", Vector3(0.8, 1.75, -2.2), Vector3(0.8, 1.6, 0), 40.0)
		await _snap(out, "hair_close_c.png", Vector3(3.2, 1.75, -1.6), Vector3(3.2, 1.6, 0), 34.0)
		await _snap(out, "hair_side.png", Vector3(4.4, 1.8, -1.6), Vector3(0.8, 1.55, 0), 44.0)
		await _snap(out, "hair_back.png", Vector3(-1.0, 1.9, 3.6), Vector3(0, 1.55, 0), 52.0)
		get_tree().quit()
		return
	await _snap(out, "strong_front.png", Vector3(0, 1.5, -6.2), Vector3(0, 1.1, 0), 48.0)
	await _snap(out, "strong_close.png", Vector3(-1.6, 1.7, -2.6), Vector3(-1.6, 1.35, 0), 46.0)
	await _snap(out, "strong_side.png", Vector3(5.2, 1.5, -2.4), Vector3(1.6, 1.1, 0), 42.0)
	await _snap(out, "strong_back.png", Vector3(-2.5, 1.8, 4.0), Vector3(0, 1.1, 0), 46.0)
	get_tree().quit()
