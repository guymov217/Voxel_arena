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
