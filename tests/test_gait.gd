extends Node
## Every beast walks on its own: let into the arena a way off from a man, each must close the
## distance on its legs with its body held up off the sand the whole way (the legs carry it;
## the trunk is not held up by anything else).

var t

const LEGLESS := ["python", "basilisk"]

func test_every_beast_walks_to_its_prey_on_its_legs() -> void:
	seed(3)
	for sp in Data.beasts.keys():
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 4})
		var man: Fighter = m.me.f
		man.teleport(Vector3(0, 0, 0))
		var e = m.spawn_beast({"beast": sp, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 10.0), "yaw": PI})
		var b: Beast = e.f
		var d0 := 10.0
		var best := d0
		var low_frames := 0
		var frames := 0
		var ground := 0.0
		for i in int(9.0 * 120):
			man.blood = 100.0
			for p in man.parts:
				p.hp = maxf(p.hp, 30.0)
			b.target = man
			await get_tree().physics_frame
			if i < 60:
				continue   # let it land and stand
			frames += 1
			var tp: Vector3 = b.torso.global_position
			best = minf(best, Vector2(tp.x, tp.z).length())
			ground = b.ground_y if b.ground_ok else 0.0
			# The trunk stays up: its underside clear of the sand (a body on its belly has sagged).
			if tp.y - b.torso.half_ext.y < ground + 0.05 and not LEGLESS.has(sp) and not b.flying:
				low_frames += 1
		var closed := d0 - best
		var sag := float(low_frames) / maxf(1.0, frames)
		var msg := "%s walks to the man on its own (closed %.1f m of %.0f, trunk on the sand %.0f%% of the way)" % [sp, closed, d0, sag * 100.0]
		printerr("   : " + msg)
		t.check(closed >= 4.0, msg)
		if not LEGLESS.has(sp) and sp != "crocodile":
			t.check(sag < 0.1, "%s: its legs carry it (sagged %.0f%%)" % [sp, sag * 100.0])
		m.queue_free()
		await get_tree().process_frame
