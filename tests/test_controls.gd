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
