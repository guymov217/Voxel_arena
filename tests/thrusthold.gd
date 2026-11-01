extends Node
## A thrust held out (tremor.gd THRUST=1: the tip shook by centimetres, step to step): the tip in
## the arena and against the trunk, every step of it, with the line's mark, so a jerk can be laid
## at the arm's door or the body's. `-- --probe thrusthold`. WEAPON (gladius), OFF (the off
## hand's weapon, none), HURT (1: arms hurt as tremor.gd hurts them), AIM (low: the mouse's y),
## FRAMES (120), FROM (the first step printed, 0), EVERY (print every n-th step, 1).

func _tip(w: Weapon) -> Vector3:
	return w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)

func _ready() -> void:
	var wk := OS.get_environment("WEAPON") if OS.get_environment("WEAPON") != "" else "gladius"
	var ay := float(OS.get_environment("AIM")) if OS.get_environment("AIM") != "" else -0.9
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 120
	var from := int(OS.get_environment("FROM")) if OS.get_environment("FROM") != "" else 0
	var every := maxi(1, int(OS.get_environment("EVERY")) if OS.get_environment("EVERY") != "" else 1)
	var off := OS.get_environment("OFF")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "loadout": {"main": wk, "off": off}})
	var f: Fighter = m.me.f
	var st := {"thrust": 0.0}
	m.me.drive = func(_e): return {"main": {"x": 0.2, "y": ay}, "off": {"x": -0.2, "y": ay}, "power": true, "thrust": st.thrust, "look": {"yaw": 0.0, "pitch": 0.0}}
	if OS.get_environment("HURT") == "1":
		for sd in ["R", "L"]:
			f.arm[sd].fore.hp *= 0.45
			f.arm[sd].upper.hp *= 0.6
	for i in 240:
		await get_tree().physics_frame
	st.thrust = 1.0
	var w: Weapon = f.weapons.R
	var wl: Weapon = f.weapons.L
	var prev := _tip(w)
	var prev_rel := prev - f.torso.global_position
	var prev_l := (_tip(wl) - f.torso.global_position) if wl else Vector3.ZERO
	for i in frames:
		await get_tree().physics_frame
		var tp := _tip(w)
		var rel := tp - f.torso.global_position
		var rel_l := (_tip(wl) - f.torso.global_position) if wl else Vector3.ZERO
		var l_step := (rel_l - prev_l).length() * 1000.0
		prev_l = rel_l
		if i < from or i % every != 0:
			prev = tp
			prev_rel = rel
			continue
		var tl = f.thrust_line.R
		var mark := Vector3.ZERO
		if tl != null and tl.has("o_w"):
			mark = (tl.o_w as Vector3) + (tl.dir_w as Vector3) * float(f.thrust_ext.R)
		print("HOLD %3d ext %.2f tip step %4.0f mm (in the arena) %4.0f mm (against the trunk)  off hand's tip %4.0f mm  hand off its mark %.2f m  trunk y %.3f  trunk speed %.2f  state %s" % [i, float(f.thrust_ext.R), (tp - prev).length() * 1000.0, (rel - prev_rel).length() * 1000.0, l_step, f.hand_world("R").distance_to(mark) if mark != Vector3.ZERO else -1.0, f.torso.global_position.y, Vector2(f.torso.linear_velocity.x, f.torso.linear_velocity.z).length(), f.state])
		prev = tp
		prev_rel = rel
	get_tree().quit()
