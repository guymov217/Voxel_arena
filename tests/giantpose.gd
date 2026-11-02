extends Node
## Tries the giant's guard for the capsule art (CapsuleArt.squared_up): the champion and the
## Cyclops brought face to face before the first blow, each pose held a few seconds, then how
## squarely they stand (turned and looking, the feet, the trunk, the weapon up, the face clear).
## `-- --probe giantpose`. POSES ("x:y,x:y"), GAP (the stand-off, metres).

const CapsuleArt := preload("res://tests/capsuleart.gd")

func _ready() -> void:
	var poses: Array = Array((OS.get_environment("POSES") if OS.get_environment("POSES") != "" else "0.45:0.95,0.6:0.6,0.8:0.8,0.3:0.4,-0.3:0.7").split(",", false))
	var gap := float(OS.get_environment("GAP")) if OS.get_environment("GAP") != "" else 4.0
	for ps in poses:
		var xy: Array = Array(String(ps).split(":"))
		seed(7)
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "foe:cyclops", "immortal": true, "respawn": false, "difficulty": 0.7}, "autopilot": true, "headless": true, "seed": 3, "decrees": [], "hazards": [],
			"loadout": {"main": CapsuleArt.AXE, "off": "", "armor": CapsuleArt.GILT}})
		var g = m.enemies()[0]
		var gf: Fighter = g.f
		var hero: Fighter = m.me.f
		var t0 := 0
		while t0 < 120 * 20:
			await get_tree().physics_frame
			t0 += 1
			var d: Vector3 = gf.torso.global_position - hero.torso.global_position
			if Vector2(d.x, d.z).length() < gap + 3.0:
				break
		g.drive = CapsuleArt.pose_drive(gf, hero, {"x": float(xy[0]), "y": float(xy[1])}, 0.0, gap)
		m.me.drive = CapsuleArt.pose_drive(hero, gf, {"x": -0.25, "y": 0.5}, 2.6, 99.0)
		var best := {}
		for i in 120 * 5:
			await get_tree().physics_frame
			var r: Dictionary = CapsuleArt.squared_up(gf, hero)
			if i % 120 == 119 and r.has("gap"):
				print("  %s t%.0f gap %.1f face %.0f look %.0f over %.0f across %.2f along %.2f bow %.0f up %.2f clear %.2f hero %.0f v %.2f ok %s" % [ps, (i + 1) / 120.0, r.gap, r.face, r.look, r.over, r.across, r.along, r.bow, r.up, r.clear, r.hero, r.v, str(r.ok)])
		print("pose %s after %.1f s of bout" % [ps, t0 / 120.0])
		m.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()
