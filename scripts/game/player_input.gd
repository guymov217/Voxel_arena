class_name PlayerInput
extends Node
## The local player's controls (input.js): with no mouse button held the mouse looks round
## (and turns the fighter); holding the left button the mouse IS the main hand, sliding it
## across a pane in front of the body and up and down; the right button moves the shield or off
## hand; both move both. Keys from the web game's bindings (controls.json), rebindable.
## A gamepad works too: the left stick walks, the right stick looks; holding the right trigger
## the right stick IS the main hand, the left trigger the off hand, both triggers both.

var main := {"x": 0.1, "y": 0.15}
var off := {"x": -0.35, "y": 0.1}
var look_yaw := 0.0
var look_pitch := 0.0
var lmb := false
var rmb := false
var thrust := 0.0
var twist := 0.0
var aiming := false   # a bow, a crossbow or a throw in hand: the mouse turns the view, whatever is held
var twist_l := 0.0   # the off hand's edge turn: the wheel turns whichever hand is held
var jab_r := false
var jab_l := false
var enabled := true
var sensitivity := 1.0
var sens_x := 1.0
var sens_y := 1.0
var invert_y := false
var left_handed := false
var _edges := {}
var bindings := {}
var throw_charge := 0.0
var _digits_held := {}
## Presses that act once (a jump, a grab): latched between frames until the input is sampled,
## and sent to the host reliably.
const ONE_SHOT := ["jump", "kick", "jabR", "jabL", "grab", "throw", "taunt", "shove", "emote", "grip", "swap"]
const LATCHED := ["jump", "kick", "grab", "taunt", "shove", "emote", "grip", "swap"]
const PAD := {"jump": JOY_BUTTON_A, "kick": JOY_BUTTON_B, "grab": JOY_BUTTON_X, "throw": JOY_BUTTON_Y, "shove": JOY_BUTTON_LEFT_SHOULDER,
	"thrust": JOY_BUTTON_RIGHT_SHOULDER, "sprint": JOY_BUTTON_LEFT_STICK, "crouch": JOY_BUTTON_RIGHT_STICK, "taunt": JOY_BUTTON_BACK}
const PAD_ITEMS := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]
var pad_move := Vector2.ZERO
var pad_r := false
var pad_l := false
var _pad_items_held := {}

func _ready() -> void:
	setup_actions()

## Input actions from the binding table (key codes like "KeyW", "ShiftLeft", "Space").
func setup_actions(custom := {}) -> void:
	bindings = Data.controls.get("defaults", {}).duplicate()
	for k in custom:
		bindings[k] = custom[k]
	for id in bindings:
		var act := "va_" + str(id)
		if InputMap.has_action(act):
			InputMap.erase_action(act)
		InputMap.add_action(act)
		var key := _keycode(str(bindings[id]))
		if key != KEY_NONE:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(act, ev)
		if PAD.has(id):
			var jb := InputEventJoypadButton.new()
			jb.button_index = PAD[id]
			InputMap.action_add_event(act, jb)

static func _keycode(code: String) -> Key:
	if code.begins_with("Key") and code.length() == 4:
		return OS.find_keycode_from_string(code.right(1))
	if code.begins_with("Digit"):
		return OS.find_keycode_from_string(code.right(1))
	match code:
		"Space": return KEY_SPACE
		"ShiftLeft", "ShiftRight": return KEY_SHIFT
		"ControlLeft", "ControlRight": return KEY_CTRL
		"AltLeft", "AltRight": return KEY_ALT
		"Tab": return KEY_TAB
		"Enter": return KEY_ENTER
		"Backquote": return KEY_QUOTELEFT
		"ArrowUp": return KEY_UP
		"ArrowDown": return KEY_DOWN
		"ArrowLeft": return KEY_LEFT
		"ArrowRight": return KEY_RIGHT
	if code.begins_with("F") and code.length() <= 3:
		return OS.find_keycode_from_string(code)
	return KEY_NONE

## The binding code for a key pressed now ("KeyW", "Space", "ShiftLeft"...), or "" if none.
static func code_of(key: Key) -> String:
	match key:
		KEY_SPACE: return "Space"
		KEY_SHIFT: return "ShiftLeft"
		KEY_CTRL: return "ControlLeft"
		KEY_ALT: return "AltLeft"
		KEY_TAB: return "Tab"
		KEY_ENTER: return "Enter"
		KEY_QUOTELEFT: return "Backquote"
		KEY_UP: return "ArrowUp"
		KEY_DOWN: return "ArrowDown"
		KEY_LEFT: return "ArrowLeft"
		KEY_RIGHT: return "ArrowRight"
	if key >= KEY_A and key <= KEY_Z:
		return "Key" + OS.get_keycode_string(key)
	if key >= KEY_0 and key <= KEY_9:
		return "Digit" + OS.get_keycode_string(key)
	if key >= KEY_F1 and key <= KEY_F12:
		return OS.get_keycode_string(key)
	return ""

## How a binding reads on a button: "W", "Space", "Shift".
static func label_of(code: String) -> String:
	if code.begins_with("Key") or code.begins_with("Digit"):
		return code.trim_prefix("Key").trim_prefix("Digit")
	return code.trim_suffix("Left").trim_suffix("Right").replace("Arrow", "↑ " if code == "ArrowUp" else "").replace("Control", "Ctrl")

func held(id: String) -> bool:
	var act := "va_" + id
	return InputMap.has_action(act) and Input.is_action_pressed(act)

func pressed(id: String) -> bool:
	return _edges.get(id, false)

var use_item := -1

func _process(_dt: float) -> void:
	for n in 9:
		if Input.is_physical_key_pressed(KEY_1 + n) and not _edges.get("digit%d" % n, false) and not _digits_held.get(n, false):
			use_item = n
		_digits_held[n] = Input.is_physical_key_pressed(KEY_1 + n)
	for id in LATCHED:
		var act: String = "va_" + id
		if InputMap.has_action(act) and Input.is_action_just_pressed(act):
			_edges[id] = true

## A click on the game (no menu took it) catches the mouse for the fight.
func _unhandled_input(e: InputEvent) -> void:
	if enabled and e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse(e)

## Once the mouse is caught the hands read it before anything on screen can: the cursor sits
## at the middle of the view, and a HUD panel there once swallowed a button's release or the
## motion, and the hand on it stopped answering.
func _input(e: InputEvent) -> void:
	if enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse(e)

func _mouse(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		var main_btn := MOUSE_BUTTON_RIGHT if left_handed else MOUSE_BUTTON_LEFT
		var off_btn := MOUSE_BUTTON_LEFT if left_handed else MOUSE_BUTTON_RIGHT
		if b.button_index == main_btn:
			lmb = b.pressed
			if b.pressed:
				jab_r = true
		elif b.button_index == off_btn:
			rmb = b.pressed
			if b.pressed:
				jab_l = true
		elif (b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN) and b.pressed:
			var dw := 0.25 if b.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25
			# Round and round, like the web game: past half a turn it comes back the other way.
			if rmb and not lmb:
				twist_l = wrapf(twist_l - dw, -PI, PI)
			else:
				twist = wrapf(twist + dw, -PI, PI)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		var both := lmb and rmb
		var h = main if lmb else (off if rmb else null)
		if h == null or aiming:
			look_yaw -= m.relative.x * 0.001 * sensitivity * sens_x
			look_pitch = clampf(look_pitch - m.relative.y * 0.00085 * sensitivity * sens_y * (-1.0 if invert_y else 1.0), -1.45, 1.35)
			return
		var s := 0.0024 * sensitivity
		for hh in ([main, off] if both else [h]):
			var lim := 2.0
			hh.x = clampf(hh.x + m.relative.x * s, -lim, lim)
			hh.y = clampf(hh.y - m.relative.y * s, -1.6, 1.6)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## The gamepad, read once a step: sticks and triggers (buttons come through the input actions).
func _pad(dt: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		pad_move = Vector2.ZERO
		pad_r = false
		pad_l = false
		return
	var d: int = pads[0]
	var dz := func(v: float) -> float: return 0.0 if absf(v) < 0.18 else (v - signf(v) * 0.18) / 0.82
	pad_move = Vector2(dz.call(Input.get_joy_axis(d, JOY_AXIS_LEFT_X)), dz.call(Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)))
	var rt := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.3
	var lt := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > 0.3
	if left_handed:
		var sw := rt
		rt = lt
		lt = sw
	if rt and not pad_r:
		jab_r = true
	if lt and not pad_l:
		jab_l = true
	pad_r = rt
	pad_l = lt
	var rs := Vector2(dz.call(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X)), dz.call(Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y)))
	if not (pad_r or pad_l):
		look_yaw -= rs.x * dt * 2.1 * sensitivity * sens_x
		look_pitch = clampf(look_pitch - rs.y * dt * 1.45 * sensitivity * sens_y * (-1.0 if invert_y else 1.0), -1.45, 1.35)
	else:
		for hh in ([main] if pad_r else []) + ([off] if pad_l else []):
			var lim := 2.0
			hh.x = clampf(hh.x + rs.x * dt * 3.2 * sensitivity, -lim, lim)
			hh.y = clampf(hh.y - rs.y * dt * 3.2 * sensitivity, -1.6, 1.6)
	for i in PAD_ITEMS.size():
		var down := Input.is_joy_button_pressed(d, PAD_ITEMS[i])
		if down and not _pad_items_held.get(i, false):
			use_item = i
		_pad_items_held[i] = down

## The input for this step, in the same shape as the web game's.
func sample(dt: float) -> Dictionary:
	_pad(dt)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		lmb = false   # let go of the mouse with a button down: its release never reaches us
		rmb = false
	var hand_r := lmb or pad_r
	var hand_l := rmb or pad_l
	if not hand_r:
		main.x += (0.1 - main.x) * minf(1.0, dt * 2.5)
		main.y += (0.15 - main.y) * minf(1.0, dt * 2.5)
	if not hand_l:
		off.x += (-0.35 - off.x) * minf(1.0, dt * 2.0)
		off.y += (0.1 - off.y) * minf(1.0, dt * 2.0)
	var want := 1.0 if held("thrust") else 0.0
	thrust += (want - thrust) * minf(1.0, dt * 10.0)
	var inp := {
		"mx": clampf((1.0 if held("left") else 0.0) - (1.0 if held("right") else 0.0) - pad_move.x, -1.0, 1.0),
		"mz": clampf((1.0 if held("forward") else 0.0) - (1.0 if held("back") else 0.0) - pad_move.y, -1.0, 1.0),
		"main": main.duplicate(),
		"off": off.duplicate(),
		"thrust": 0.0 if hand_l and not hand_r else thrust,
		"offThrust": thrust if hand_l else 0.0,
		"power": hand_r or hand_l,
		"jabR": jab_r,
		"jabL": jab_l,
		"twist": twist,
		"offTwist": twist_l,
		"look": {"yaw": look_yaw, "pitch": look_pitch},
		"sprint": held("sprint"),
		"crouch": held("crouch"),
		"jump": pressed("jump"),
		"kick": pressed("kick"),
		"grab": pressed("grab"),
		# G with a mouse button held grabs with that hand (both buttons: both hands).
		"grabHands": "both" if hand_r and hand_l else ("R" if hand_r else ("L" if hand_l else null)),
		"taunt": pressed("taunt"),
		"shove": pressed("shove"),
		"emote": pressed("emote"),
		"grip": pressed("grip"),
		"swap": pressed("swap"),
		"limp": held("limp"),
		"useItem": use_item,
	}
	use_item = -1
	# F: hold to wind up a throw, let go to throw. A quick tap is a lob.
	if held("throw"):
		throw_charge = minf(1.0, throw_charge + dt / 1.1)
		inp.charging = throw_charge
	elif throw_charge > 0.0:
		inp.throw = true
		inp.throwPower = maxf(0.3, throw_charge)
		throw_charge = 0.0
	_edges.clear()
	jab_r = false
	jab_l = false
	if not enabled:
		return {"main": main.duplicate(), "look": {"yaw": look_yaw, "pitch": look_pitch}}
	return inp

## Inputs travel over the network as small arrays.
static func pack(inp: Dictionary) -> Array:
	var m: Dictionary = inp.get("main", {"x": 0, "y": 0})
	var o: Dictionary = inp.get("off", {"x": 0, "y": 0})
	var lk: Dictionary = inp.get("look", {"yaw": 0, "pitch": 0})
	var bits := 0
	for i in BITS.size():
		if inp.get(BITS[i], false):
			bits |= 1 << i
	var gh = inp.get("grabHands")
	bits |= (1 if gh == "R" else (2 if gh == "L" else (3 if gh == "both" else 0))) << 14
	return [snappedf(inp.get("mx", 0.0), 0.01), snappedf(inp.get("mz", 0.0), 0.01), snappedf(m.x, 0.001), snappedf(m.y, 0.001), snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(inp.get("thrust", 0.0), 0.01), snappedf(inp.get("offThrust", 0.0), 0.01), snappedf(inp.get("twist", 0.0), 0.01), snappedf(lk.yaw, 0.001), snappedf(lk.pitch, 0.001), bits, snappedf(inp.get("throwPower", 0.0), 0.01), int(inp.get("useItem", -1)), snappedf(inp.get("offTwist", 0.0), 0.01)]

const BITS := ["power", "sprint", "crouch", "jump", "kick", "jabR", "jabL", "grab", "throw", "taunt", "shove", "emote", "limp", "swap"]

static func has_one_shot(inp: Dictionary) -> bool:
	if int(inp.get("useItem", -1)) >= 0:
		return true
	for k in ONE_SHOT:
		if inp.get(k, false):
			return true
	return false

static func unpack(a: Array) -> Dictionary:
	if a.size() < 12:
		return {}
	var bits := int(a[11])
	var out := {"mx": clampf(a[0], -1, 1), "mz": clampf(a[1], -1, 1), "main": {"x": clampf(a[2], -2, 2), "y": clampf(a[3], -1.6, 1.6)}, "off": {"x": clampf(a[4], -2, 2), "y": clampf(a[5], -1.6, 1.6)},
		"thrust": clampf(a[6], -1.5, 1.5), "offThrust": clampf(a[7], -1.5, 1.5), "twist": clampf(a[8], -PI, PI), "look": {"yaw": float(a[9]), "pitch": clampf(a[10], -1.35, 1.35)}}
	for i in BITS.size():
		out[BITS[i]] = bits & (1 << i) != 0
	out.grabHands = [null, "R", "L", "both"][(bits >> 14) & 3]
	out.throwPower = clampf(float(a[12]), 0.0, 1.0) if a.size() > 12 else 0.8
	out.useItem = clampi(int(a[13]), -1, 8) if a.size() > 13 else -1
	out.offTwist = clampf(float(a[14]), -PI, PI) if a.size() > 14 else 0.0
	return out
