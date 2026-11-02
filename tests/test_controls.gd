extends Node
## Controls (bindings.js): keys rebind, the codes read back the same, a gamepad is mapped.

var t

func test_keys_rebind_and_the_gamepad_is_mapped() -> void:
	for code in ["KeyW", "Space", "ShiftLeft", "Digit3", "Tab", "F5", "ArrowUp"]:
		t.eq(PlayerInput.code_of(PlayerInput._keycode(code)), code, "%s reads back" % code)
	t.eq(PlayerInput.label_of("KeyQ"), "Q", "a button shows Q")
	var pin := PlayerInput.new()
	add_child(pin)
	pin.setup_actions({"jump": "KeyJ"})
	var keys := InputMap.action_get_events("va_jump").filter(func(e): return e is InputEventKey).map(func(e): return e.physical_keycode)
	t.check(keys.has(KEY_J) and not keys.has(KEY_SPACE), "jump is on J now")
	var pads := InputMap.action_get_events("va_jump").filter(func(e): return e is InputEventJoypadButton).map(func(e): return e.button_index)
	t.check(pads.has(JOY_BUTTON_A), "and on the gamepad's A")
	var inp := pin.sample(1.0 / 120.0)
	t.check(inp.has("mx") and inp.has("main") and not inp.power, "no pad, no keys: standing still")
	pin.setup_actions({})
	pin.queue_free()

func _button(pin: PlayerInput, b: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	pin._mouse(e)

func _move(pin: PlayerInput, d: Vector2) -> void:
	pin._motion(d)

func test_both_hands_on_a_haft_any_button_swings_it() -> void:
	var pin := PlayerInput.new()
	add_child(pin)
	pin.setup_actions({})
	pin.set_two_handed(true)
	var off0: Dictionary = pin.off.duplicate()
	_button(pin, MOUSE_BUTTON_RIGHT, true)
	var main0: Dictionary = pin.main.duplicate()
	_move(pin, Vector2(0, -300))
	t.check(float(pin.main.y) > float(main0.y) + 0.5, "the right button alone lifts the haft")
	_button(pin, MOUSE_BUTTON_LEFT, true)
	_move(pin, Vector2(0, -300))
	t.eq(pin.off, off0, "with both buttons down the off hand's own mark stays where it was")
	_button(pin, MOUSE_BUTTON_LEFT, false)
	_button(pin, MOUSE_BUTTON_RIGHT, false)
	pin.off = {"x": 1.5, "y": 1.6}
	pin.set_two_handed(false)
	t.check(float(pin.off.y) < 0.5, "the grip let go, the off hand's mark is back at its guard, not up by the head")
	pin.queue_free()

## A pad counts only once it is used: a stick or a trigger resting off centre (a worn stick, a
## wheel or a virtual pad read as a gamepad) does not walk the man off sideways by himself with
## his hand up (user video 1029: "the strange drift to the left when I do nothing").
func test_a_pad_resting_off_centre_does_not_move_him() -> void:
	var rest := {JOY_AXIS_LEFT_X: 0.3, JOY_AXIS_LEFT_Y: -0.05, JOY_AXIS_TRIGGER_RIGHT: 0.45}
	var r := PlayerInput.pad_reading(rest.duplicate(), rest, false, false)
	t.check(not r.live, "untouched, a pad with its stick and trigger resting off centre is not in use")
	t.check(absf(float(r.rel[JOY_AXIS_LEFT_X])) < 1e-6 and absf(float(r.rel[JOY_AXIS_TRIGGER_RIGHT])) < 1e-6, "where they rest reads as nothing")
	var pushed := rest.duplicate()
	pushed[JOY_AXIS_LEFT_X] = -0.6
	var r2 := PlayerInput.pad_reading(pushed, rest, false, false)
	t.check(r2.live and float(r2.rel[JOY_AXIS_LEFT_X]) < -0.8, "pushed well over, it is taken up")
	t.check(PlayerInput.pad_reading(rest.duplicate(), rest, false, true).live, "and so is a pad whose button is pressed")
	t.check(PlayerInput.pad_reading(rest.duplicate(), rest, true, false).live, "once taken up it stays in use")

## The thrust key switches the thrust on and off (user: a toggle, not a key to hold). On, the
## mouse alone turns the view both ways, to aim the stab (the held key took the mouse's push for
## the depth, and the view could not look up or down); with a hand's button held, pushed forward
## the point goes in, drawn back it comes out, the hand's height is not what moves, and it goes to
## the host as it is; the button let go, the blade comes back; pressed again, the thrust is off.
func test_the_thrust_key_switches_the_thrust_on_and_off() -> void:
	var pin := PlayerInput.new()
	add_child(pin)
	pin.main = {"x": 0.2, "y": 0.3}
	var press := func() -> void:
		pin._edges["thrust"] = true   # (the key going down, as _process latches it for the next sample)
	press.call()
	var inp: Dictionary = pin.sample(1.0 / 60.0)
	t.check(inp.depthOn and float(inp.thrust) > 0.3, "pressed once, the thrust is on")
	for i in 10:
		inp = pin.sample(1.0 / 60.0)
	t.check(inp.depthOn and float(inp.thrust) > 0.99, "and stays on, the key let go")
	var pitch0 := pin.look_pitch
	var yaw0 := pin.look_yaw
	pin._motion(Vector2(40, -120))
	inp = pin.sample(1.0 / 60.0)
	t.check(pin.look_pitch > pitch0 + 0.02 and pin.look_yaw < yaw0 - 0.01, "no button held, the mouse turns the view, up and aside (%.3f, %.3f)" % [pin.look_pitch - pitch0, pin.look_yaw - yaw0])
	t.check(float(inp.depth) == 0.0, "and the blade is not driven")
	pin.lmb = true
	var pitch1 := pin.look_pitch
	pin._motion(Vector2(30, -0.5 * PlayerInput.DEPTH_PX))   # the button held: pushed forward half way
	t.check(absf(pin.depth - 0.5) < 0.01, "a button held and pushed half way, the point half way in (%.2f)" % pin.depth)
	t.check(absf(pin.look_pitch - pitch1) < 1e-6 and pin.look_yaw < yaw0 - 0.02, "the push is the stab's, not the view's; aside, the view still turns")
	pin.lmb = true
	inp = pin.sample(1.0 / 60.0)
	t.check(inp.depthOn and float(inp.depth) > 0.4, "so it goes into the input (%.2f)" % float(inp.depth))
	t.check(absf(float(inp.main.y) - 0.3) < 1e-6, "the hand's height is not what moved")
	var back := PlayerInput.unpack(PlayerInput.pack(inp))
	t.check(back.get("depthOn", false) and absf(float(back.get("depth", 0.0)) - float(inp.depth)) < 0.01, "it goes to the host so")
	var aimed := inp.duplicate()
	aimed.aimAt = Vector3(1, 2, 3)
	aimed.aimFrom = Vector3(0, 1, 0)
	aimed.wheel = 2.0
	var back2 := PlayerInput.unpack(PlayerInput.pack(aimed))
	t.check(absf(float(back2.get("depth", 0.0)) - float(inp.depth)) < 0.01 and back2.get("aimAt") == Vector3(1, 2, 3) and float(back2.get("wheel", 0.0)) == 2.0, "with an aim and a wheel turn along with it too")
	pin.lmb = true
	pin._motion(Vector2(0, 3.0 * PlayerInput.DEPTH_PX))    # drawn right back
	t.check(pin.depth <= -0.99, "drawn back, it comes out toward the chest (%.2f)" % pin.depth)
	pin.lmb = false
	for i in 40:
		inp = pin.sample(1.0 / 60.0)
	t.check(inp.depthOn and float(inp.depth) == 0.0, "the button let go, the blade back at its guard, the thrust still on")
	press.call()
	inp = pin.sample(1.0 / 60.0)
	t.check(not inp.depthOn and float(inp.depth) == 0.0, "pressed again, the thrust is off: the mouse is the hand's again")
	for i in 10:
		inp = pin.sample(1.0 / 60.0)
	t.check(float(inp.thrust) < 0.01, "and the blade is back to its blows")
	t.check(not PlayerInput.unpack(PlayerInput.pack(inp)).has("depthOn"), "nothing of it goes to the host")
	press.call()
	t.check(pin.sample(1.0 / 60.0).depthOn, "on again")
	pin.reset_hands()
	t.check(not pin.sample(1.0 / 60.0).depthOn, "a new fighter (a bout, a respawn) starts with it off")
	pin.queue_free()

## In the fight: held, the point goes as deep along its line as the mouse has pushed it (from
## where the hand was, out to the full lunge, back toward the chest).
func test_the_point_goes_as_deep_as_the_mouse_pushes_it() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var f: Fighter = m.me.f
	var st := {"th": 0.0, "d": 0.0}
	m.me.drive = func(_e): return {"main": {"x": 0.1, "y": 0.3}, "off": {"x": -0.35, "y": 0.1}, "power": true, "thrust": st.th, "depthOn": st.th > 0.0, "depth": st.d, "look": {"yaw": f.yaw, "pitch": 0.0}}
	for i in 120:
		await get_tree().physics_frame
	st.th = 1.0
	for i in 30:
		await get_tree().physics_frame
	var tl = f.thrust_line.R
	t.check(tl != null, "the thrust's line is taken")
	if tl == null:
		m.queue_free()
		return
	var o: Vector3 = tl.o_w
	var dir: Vector3 = (tl.dir_w as Vector3).normalized()
	var a0: float = (f.hand_world("R") - o).dot(dir)
	t.check(absf(a0) < 0.08, "held and not pushed, the hand stays where it was (%.2f m)" % a0)
	st.d = 1.0
	for i in 60:
		await get_tree().physics_frame
	var a1: float = (f.hand_world("R") - o).dot(dir)
	t.check(a1 > 0.2, "pushed all the way, the point goes right in (%.2f m)" % a1)
	st.d = 0.4
	for i in 60:
		await get_tree().physics_frame
	var a2: float = (f.hand_world("R") - o).dot(dir)
	t.check(a2 < a1 - 0.08 and a2 > 0.0, "drawn part way back, part way out (%.2f m)" % a2)
	st.d = -1.0
	for i in 60:
		await get_tree().physics_frame
	var a3: float = (f.hand_world("R") - o).dot(dir)
	t.check(a3 < a2 - 0.05, "drawn right back, back toward the chest (%.2f m)" % a3)
	m.queue_free()
	await get_tree().physics_frame

## Switched on and no button held, the blade is laid on the line to the crosshair (user: how does
## a player aim the stab somewhere else? he looks there); pushed, the point goes in along it, to
## the mark. Low to one side, high to the other.
func test_the_thrust_on_the_blade_points_at_the_crosshair() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var f: Fighter = m.me.f
	var st := {"th": 0.0, "d": 0.0, "at": null, "power": false}
	m.me.drive = func(_e):
		var inp := {"main": {"x": 0.1, "y": 0.3}, "off": {"x": -0.35, "y": 0.1}, "power": st.power, "thrust": st.th, "depthOn": st.th > 0.0, "depth": st.d, "look": {"yaw": f.yaw, "pitch": 0.0}}
		if st.at != null:
			inp.aimAt = st.at
		return inp
	for i in 120:
		await get_tree().physics_frame
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var aside := fwd.cross(Vector3.UP).normalized()
	for mk in [{"name": "low to one side", "off": aside * 0.45 + Vector3(0, -0.35, 0)}, {"name": "high to the other", "off": -aside * 0.35 + Vector3(0, 0.45, 0)}]:
		var at: Vector3 = f.torso.global_position + fwd * 1.7 + (mk.off as Vector3)
		st.at = at
		st.th = 1.0
		for i in 70:
			await get_tree().physics_frame
		var tl = f.thrust_line.R
		var w: Weapon = f.weapons.R
		var rest: Vector3 = f.hand_world("R")
		var to_mark: Vector3 = (at - rest).normalized()
		var blade: Vector3 = PD.quat_of(w) * Vector3.UP
		t.check(tl != null and (tl.dir_w as Vector3).normalized().dot(to_mark) > cos(deg_to_rad(6.0)), "%s: the thrust's line is on the crosshair" % mk.name)
		t.check(blade.dot(to_mark) > cos(deg_to_rad(8.0)), "%s: and the blade points there (%.0f degrees off)" % [mk.name, rad_to_deg(acos(clampf(blade.dot(to_mark), -1.0, 1.0)))])
		st.power = true
		st.d = 1.0
		for i in 60:
			await get_tree().physics_frame
		var went: Vector3 = f.hand_world("R") - rest
		var along := went.dot(to_mark)
		var off_line := (went - to_mark * along).length()
		t.check(along > 0.3 and off_line < 0.35 * along, "%s: pushed, the point goes in toward the mark (%.2f m along, %.2f m off it)" % [mk.name, along, off_line])
		st.power = false
		st.d = 0.0
		st.th = 0.0
		st.at = null
		for i in 60:
			await get_tree().physics_frame
	m.queue_free()
	await get_tree().physics_frame
