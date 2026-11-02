extends Node
## A man left alone with his hands where they were last aimed (user video 1029: he walked off to
## the left by himself, the sword raised by his head, the empty fist forward). For each guard in
## GUARDS and each loadout, how far the trunk wanders in DRIFT_S seconds with no input at all, the
## steps taken, and which way. `-- --probe idledrift`. DRIFT_S (10).

const GUARDS := {
	"rest": [{"x": 0.1, "y": 0.15}, {"x": -0.35, "y": 0.1}],
	"video": [{"x": 0.35, "y": 0.95}, {"x": -0.25, "y": 0.55}],
	"high": [{"x": 0.2, "y": 1.3}, {"x": -0.35, "y": 0.1}],
	"right": [{"x": 1.0, "y": 0.3}, {"x": -0.35, "y": 0.1}],
	"left": [{"x": -0.8, "y": 0.4}, {"x": -0.35, "y": 0.1}],
	"both_up": [{"x": 0.3, "y": 1.0}, {"x": -0.3, "y": 1.0}],
}

func _ready() -> void:
	var secs := float(OS.get_environment("DRIFT_S")) if OS.get_environment("DRIFT_S") != "" else 10.0
	var loads := [["gladius", ""], ["", ""], ["gladius", "roundShield"], ["longsword", ""]]
	for lo in loads:
		for g in GUARDS:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": lo[0], "off": lo[1]}})
			var f: Fighter = m.me.f
			var yaw0 := f.yaw
			var guard: Array = GUARDS[g]
			m.me.drive = func(_e): return {"main": guard[0], "off": guard[1], "look": {"yaw": yaw0, "pitch": 0.0}}
			for i in 240:
				await get_tree().physics_frame
			var p0: Vector3 = f.torso.global_position
			var steps := 0
			var was := {"L": false, "R": false}
			for i in int(secs * 120):
				await get_tree().physics_frame
				for sd in ["L", "R"]:
					var ft = f.feet[sd]
					var sw: bool = ft != null and ft.swing
					if sw and not was[sd]:
						steps += 1
					was[sd] = sw
			var d: Vector3 = f.torso.global_position - p0
			var yq := Quaternion(Vector3.UP, yaw0)
			var loc: Vector3 = yq.inverse() * d   # x: his left (+) / right, z: ahead (+)
			print("%-22s %-8s moved %.2f m (left %+.2f, ahead %+.2f) in %.0f s, %d steps, turned %+.1f deg, state %s" % [
				"%s+%s" % [lo[0] if lo[0] != "" else "-", lo[1] if lo[1] != "" else "-"], g, Vector2(d.x, d.z).length(), loc.x, loc.z, secs, steps, rad_to_deg(wrapf(f.yaw - yaw0, -PI, PI)), f.state])
			m.queue_free()
			await get_tree().physics_frame
	get_tree().quit()
