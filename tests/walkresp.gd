extends Node
## How a man's torso answers a step in the walking keys (`-- --probe walkresp`, with `--fixed-fps 120`): from rest, a key pressed
## and held, then let go. Prints the steady speed reached and the time the velocity takes to come 63 % of the way, and the
## time to the first 2 cm, for walking, sprinting, strafing, backing and a diagonal; so the guest's own-man model (MovePredictor)
## can be fitted to what the host's physics really does.

var m: Match

func _ready() -> void:
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -10))
	_run.call_deferred()

func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func _case(label: String, inp: Dictionary) -> void:
	var e = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
	e.erase("bot")
	var go := {"on": false}
	e.drive = func(_e): return inp.duplicate(true) if go.on else {}
	var f: Fighter = e.f
	for i in 150:
		await get_tree().physics_frame
	var p0 := _xz(f.torso.global_position)
	var dir := Vector2.ZERO
	go.on = true
	var series := []
	var t_press := 0
	for i in 150:
		await get_tree().physics_frame
		series.append([_xz(f.torso.global_position) - p0, _xz(f.torso.linear_velocity)])
	var p_rel := _xz(f.torso.global_position) - p0
	dir = p_rel.normalized()
	# The steady speed: the mean over the last 40 steps along the way he went.
	var vss := 0.0
	for i in range(110, 150):
		vss += (series[i][1] as Vector2).dot(dir)
	vss /= 40.0
	var t63 := -1.0
	var t2cm := -1.0
	for i in series.size():
		var v: float = (series[i][1] as Vector2).dot(dir)
		if t63 < 0.0 and v >= 0.632 * vss:
			t63 = (i + 1) / 120.0
		if t2cm < 0.0 and (series[i][0] as Vector2).dot(dir) >= 0.02:
			t2cm = (i + 1) / 120.0
	# And the first velocities, every step for a tenth of a second.
	var first := []
	for i in 14:
		first.append("%.2f" % (series[i][1] as Vector2).dot(dir))
	print("RESP %-10s steady %.2f m/s  63%% at %3.0f ms  2 cm at %3.0f ms  yaw %.2f  v: %s" % [label, vss, t63 * 1000.0, t2cm * 1000.0, f.yaw, " ".join(first)])
	# Let go: how long he takes to stop.
	go.on = false
	var stop_t := -1.0
	var d0 := _xz(f.torso.global_position)
	var travel := 0.0
	for i in 120:
		await get_tree().physics_frame
		var v := _xz(f.torso.linear_velocity).length()
		if stop_t < 0.0 and v < 0.1 * vss:
			stop_t = (i + 1) / 120.0
	travel = (_xz(f.torso.global_position) - d0).length()
	print("RESP %-10s let go: 10%% of speed left after %3.0f ms, slid %.3f m on" % [label, stop_t * 1000.0, travel])
	m._remove_entity(e)
	await get_tree().physics_frame

func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	await _case("walk", {"mz": 1.0})
	await _case("sprint", {"mz": 1.0, "sprint": true})
	await _case("strafe", {"mx": 1.0})
	await _case("back", {"mz": -1.0})
	await _case("diagonal", {"mx": 1.0, "mz": 1.0})
	await _case("half walk", {"mz": 0.5})
	get_tree().quit(0)
