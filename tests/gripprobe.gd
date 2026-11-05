extends Node
## Where the hands are on a two-handed haft (`-- --probe gripprobe`, headless): a longsword, a
## zweihander and a war hammer held in both hands in the poses of twohandshots; for each, how far
## the off hand is from its place on the grip, how far from the main forearm (a hand on the haft
## is not on the other arm), and the angle between the main forearm and the blade.

const POSES := [
	{"name": "guard", "x": 0.2, "y": 0.2},
	{"name": "right", "x": 2.0, "y": 0.3},
	{"name": "left", "x": -2.0, "y": 0.3},
	{"name": "high", "x": 0.0, "y": 1.6},
	{"name": "low", "x": 0.6, "y": -1.0},
]

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "decrees": [], "hazards": [], "seed": 3})
	m.me.f.teleport(Vector3(0, 0, 30))
	var pose := {"main": {"x": 0.2, "y": 0.2}, "power": true}
	var men := []
	for i in 3:
		var wk: String = ["longsword", "zweihander", "warhammer"][i]
		var e = m.spawn_fighter({"kind": "bot", "name": wk, "loadout": {"main": wk, "off": ""}, "team": 1, "pos": Vector3((i - 1) * 2.4, 0.1, 0.0), "yaw": PI})
		e.erase("bot")
		e.drive = func(_e): return pose
		men.append(e.f)
	for i in 120:
		await get_tree().physics_frame
	for ps in POSES:
		pose.main = {"x": ps.x, "y": ps.y}
		for i in 150:
			await get_tree().physics_frame
		for f in men:
			var w: Weapon = f.weapons.R
			if w == null:
				print("GRIP %s %s: no weapon" % [ps.name, f.display_name])
				continue
			var fore: VoxelPart = f.arm.R.fore
			var el: Vector3 = f.arm.R.upper.global_transform * fore.pa
			var hr: Vector3 = f.hand_world("R")
			var hl: Vector3 = f.hand_world("L")
			var g_off: Vector3 = w.global_transform * w.grip_off
			var blade: Vector3 = PD.quat_of(w) * Vector3.UP
			var farm: Vector3 = (hr - el).normalized()
			print("GRIP %s %-11s two=%s offhand-to-grip %.2f  offhand-to-main-forearm %.2f  hands apart %.2f  forearm-blade %3.0f deg" % [ps.name, f.display_name, str(f.two_handed), hl.distance_to(g_off), _seg_dist(hl, el, hr), hl.distance_to(hr), rad_to_deg(farm.angle_to(blade))])
	get_tree().quit()
