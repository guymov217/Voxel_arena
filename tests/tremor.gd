extends Node
## The hands held still (user video 1135: small tremors in the hands, a sword in each, both arms
## out in front): how much each blade's tip shakes about where it is going, in millimetres (the
## part of its motion faster than a quarter of a second), and the most it moves in one step.
## `-- --probe tremor`. HOLDS: which holds (all).

const HOLDS := {
	"guard": [{"x": 0.1, "y": 0.15}, {"x": -0.35, "y": 0.1}],
	"forward": [{"x": 0.0, "y": 0.35}, {"x": 0.0, "y": 0.3}],
	"high": [{"x": 0.2, "y": 1.1}, {"x": -0.2, "y": 1.0}],
	"wide": [{"x": 1.6, "y": 0.3}, {"x": -1.6, "y": 0.3}],
	"low": [{"x": 0.2, "y": -0.9}, {"x": -0.2, "y": -0.9}],
}
const LOADS := {
	"gladius+gladius": {"main": "gladius", "off": "gladius"},
	"gladius": {"main": "gladius"},
	"axe+shield": {"main": "axe", "off": "roundShield"},
	"warhammer": {"main": "warhammer"},
}

func _tip(w: Weapon) -> Vector3:
	return w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)

func _ready() -> void:
	var want := OS.get_environment("HOLDS").split(",", false)
	for ln in LOADS:
		for hn in HOLDS:
			if not want.is_empty() and not want.has(hn):
				continue
			for hurt in [false, true]:
				var m := Match.new()
				add_child(m)
				var lo: Dictionary = LOADS[ln]
				# PLAYER=1: the player's own fighter (no bot's ways with the blade), as in the user's video.
				var as_player := OS.get_environment("PLAYER") == "1"
				m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "loadout": {"main": lo.main, "off": lo.get("off", "")}})
				var e = m.me
				if not as_player:
					m.me.f.teleport(Vector3(-12, 0, 0))
					e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": lo.main, "off": lo.get("off", "")}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
					e.erase("bot")
				var f: Fighter = e.f
				var h: Array = HOLDS[hn]
				e.drive = func(_e): return {"main": h[0], "off": h[1], "power": true, "look": {"yaw": 0.0, "pitch": 0.0}}
				if hurt:
					for s in ["R", "L"]:
						f.arm[s].fore.hp *= 0.45
						f.arm[s].upper.hp *= 0.6
				for i in 240:
					await get_tree().physics_frame
				var tips := {"R": [], "L": []}
				for i in 360:
					await get_tree().physics_frame
					for s in ["R", "L"]:
						var w = f.weapons[s]
						if w:
							tips[s].append(_tip(w) - f.torso.global_position)
				var out := []
				for s in ["R", "L"]:
					var a: Array = tips[s]
					if a.size() < 60:
						continue
					var hf := 0.0
					var step := 0.0
					var k := 15
					for i in range(k, a.size() - k):
						var avg := Vector3.ZERO
						for j in range(i - k, i + k + 1):
							avg += a[j]
						avg /= float(2 * k + 1)
						hf += (a[i] - avg).length_squared()
						step = maxf(step, (a[i] - a[i - 1]).length())
					hf = sqrt(hf / float(a.size() - 2 * k))
					out.append("%s shake %.1f mm step %.1f mm" % [s, hf * 1000.0, step * 1000.0])
				print("TREMOR %-16s %-8s %-5s %s" % [ln, hn, "hurt" if hurt else "whole", "  ".join(out)])
				m.queue_free()
				await get_tree().physics_frame
	get_tree().quit()
