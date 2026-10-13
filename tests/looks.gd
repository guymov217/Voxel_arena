extends Node
## The gladiator's looks side by side (`-- --probe looks`, needs a display): every skin tone,
## cloth colour, hair, beard, hat, the cape and the armour, on men standing in a row; and one
## face close up. PNGs go to SHOT_DIR as looks_<row>.png.

const SKINS := [0xe0b48c, 0xc68e5e, 0x9a6440, 0x6e4529, 0xf1c9a5]
const CLOTH := [0x8a1c14, 0x1f4f8f, 0x2f6b2a, 0x6b2a7a, 0xc89a2a, 0x2a2a2a, 0xe8e0d0, 0xb4541e]
const ROWS := {
	"hair": [["hair_long"], ["hair_mohawk", "beard_braided"], ["hair_curly"], ["hair_topknot", "beard_braided"], ["hair_ponytail"]],
	"hats": [["hat_laurel", "hair_curly"], ["hat_crest"], ["hat_straw", "beard_braided"], ["hat_horns", "hair_long"], ["hat_crown", "hair_curly"], ["hat_feather", "hair_ponytail"], ["hat_bandana", "beard_braided"]],
	"armour": [["helmet", "lorica", "manica", "greaves"], ["goldHelmet", "goldLorica", "manica", "greaves"], ["hat_bucket", "lorica", "cape"], ["skullPlate", "ironJaw", "greaves"], ["cape", "hair_long", "beard_braided"]],
}

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.me.f.visible = false
	m.me.f.global_position = Vector3(0, 0, -14)
	m.set_process(false)
	var cam: Camera3D = m.cam
	cam.set_process(false)
	var i := 0
	for row in ROWS:
		var looks: Array = ROWS[row]
		var men := []
		var n := looks.size()
		for k in n:
			var x := (float(k) - (n - 1) * 0.5) * 0.95
			var e = m.spawn_fighter({"kind": "npc", "name": "Look %d" % k, "loadout": {"main": "", "off": "", "armor": looks[k]}, "team": Match.ENEMY_TEAM,
				"pos": Vector3(x, 0.02, 2.0), "yaw": PI, "skin": SKINS[(k + i) % SKINS.size()], "color": CLOTH[(k * 3 + i) % CLOTH.size()]})
			e.drive = func(_e): return {}
			e.harmless = true
			men.append(e)
		for t in 150:
			await get_tree().physics_frame
		cam.fov = 40.0
		cam.global_position = Vector3(0, 1.35, 2.0 - 1.15 * n - 0.6)
		cam.look_at(Vector3(0, 1.05, 2.0), Vector3.UP)
		for f in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("looks_%s.png" % row))
		print("saved ", row)
		# Each head close, three quarters from the front.
		for k in men.size():
			var hp: Vector3 = men[k].f.head.global_position
			cam.fov = 40.0
			cam.global_position = hp + Vector3(0.35, 0.12, -0.75)
			cam.look_at(hp + Vector3(0, 0.03, 0), Vector3.UP)
			for f in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("looks_%s_%d.png" % [row, k]))
		if row == "hair":
			var h: Vector3 = men[1].f.head.global_position
			cam.global_position = h + Vector3(0.25, 0.05, -0.75)
			cam.look_at(h, Vector3.UP)
			for f in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("looks_face.png"))
			print("saved face")
		for e in men:
			m.entities.erase(e)
			m.combat.fighters.erase(e.f)
			e.f.queue_free()
		await get_tree().physics_frame
		i += 1
	get_tree().quit()
