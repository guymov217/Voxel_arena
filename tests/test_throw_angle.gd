extends Node
## A throw leaves at the same angle for the same mark, however long it was wound up: the wind-up
## says how far, not which way (user: the angle changed from throw to throw).

var t

func test_the_wind_up_changes_the_speed_not_the_line() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var f: Fighter = m.me.f
	await get_tree().physics_frame
	var from := f.hand_world("R")
	for mark in [from + Vector3(0, -1.0, 6.0), from + Vector3(2.0, 0.5, 12.0), from + Vector3(0, 3.0, 30.0)]:
		var a := f.launch_velocity(from, mark, 1.0, 0.35)
		var b := f.launch_velocity(from, mark, 1.0, 1.0)
		t.check(a.normalized().angle_to(b.normalized()) < 0.01, "a flick and a full throw at %s leave along one line (%.1f deg apart)" % [mark - from, rad_to_deg(a.normalized().angle_to(b.normalized()))])
		t.check(a.length() < b.length() * 0.7, "the flick is the slower")
	var full := Items.flat_shot(Vector3(0, -1, 8), 14.5 * Throwables.throw_speed_k(1.0)).normalized()
	t.check(full.y > -0.2 and full.y < 0.3, "a pot's line to a mark ahead is near level (%.2f)" % full.y)
	m.queue_free()
