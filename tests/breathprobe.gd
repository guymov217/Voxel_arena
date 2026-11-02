extends Node
## How many swings a man has in him (user: three swings and his breath is gone, then he stands
## there waiting to be killed). A wide stroke every SWING_S seconds (a sweep across and back with
## the button down, then the button let go), for each weapon and with and without armour: his
## breath after each of the first strokes, how many he gets in before it is under a fifth, and
## how long it takes to come back from there standing still. `-- --probe breathprobe`.

func _ready() -> void:
	var every := float(OS.get_environment("SWING_S")) if OS.get_environment("SWING_S") != "" else 1.2
	for arm in [[], ["helmet", "manica", "greaves", "lorica"]]:
		for wpn in ["gladius", "longsword", "axe", "warhammer", ""]:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": wpn, "off": "", "armor": arm}})
			var f: Fighter = m.me.f
			var st := {"t": 0.0, "on": false}
			m.me.drive = func(_e):
				# A hard stroke as a player flicks the mouse: across in a quarter second and back.
				var ph := fmod(float(st.t), every)
				var swinging := bool(st.on) and (ph < 0.5 or OS.get_environment("FLAIL") != "")
				var u := clampf(ph / 0.25, 0.0, 1.0) if ph < 0.25 else clampf(1.0 - (ph - 0.25) / 0.25, 0.0, 1.0)
				var x := -1.8 + 3.6 * u if swinging else -1.0
				return {"main": {"x": x, "y": 0.3 + 0.5 * sin(u * PI)}, "off": {"x": -0.35, "y": 0.1}, "power": swinging, "jabR": swinging and ph < 0.01 and wpn == "", "look": {"yaw": f.yaw, "pitch": 0.0}}
			for i in 240:
				await get_tree().physics_frame
			var full := f.stamina
			st.on = true
			var after := []
			var swings := 0
			var spent_at := -1
			for i in int(every * 20 * 120):
				await get_tree().physics_frame
				st.t = float(st.t) + 1.0 / 120.0
				if int((float(st.t) - 1.0 / 120.0) / every) != int(float(st.t) / every):
					swings += 1
					if after.size() < 6:
						after.append(int(round(f.stamina)))
					if spent_at < 0 and f.stamina < full * 0.2:
						spent_at = swings
			st.on = false
			var low := f.stamina
			var back := 0.0
			for i in 120 * 20:
				await get_tree().physics_frame
				if f.stamina >= full * 0.9:
					break
				back += 1.0 / 120.0
			print("%-10s %-7s full %3.0f; after each stroke %s; under a fifth after %s strokes (of 20); %.0f left after 20; back to 90%% in %.1f s" % [
				wpn if wpn != "" else "fists", "armour" if not arm.is_empty() else "bare", full, str(after), str(spent_at) if spent_at >= 0 else "never", low, back])
			m.queue_free()
			await get_tree().physics_frame
	get_tree().quit()
