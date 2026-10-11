class_name PlayerInput
extends Node
## The local player's controls (input.js): with no mouse button held the mouse looks round
## (and turns the fighter); holding the left button the mouse IS the main hand, sliding it
## across a pane in front of the body and up and down; the right button moves the shield or off
## hand; both move both. Keys from the web game's bindings (controls.json), rebindable.

var main := {"x": 0.1, "y": 0.15}
var off := {"x": -0.35, "y": 0.1}
var look_yaw := 0.0
var look_pitch := 0.0
var lmb := false
var rmb := false
var thrust := 0.0
var twist := 0.0
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
const ONE_SHOT := ["jump", "kick", "jabR", "jabL", "grab", "throw", "taunt", "shove", "emote"]
const LATCHED := ["jump", "kick", "grab", "taunt", "shove", "emote"]

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

func held(id: String) -> bool:
	var act := "va_" + id
	return InputMap.has_action(act) and Input.is_action_pressed(act)

func pressed(id: String) -> bool:
	return _edges.get(id, false)

var use_item := -1

func _process(_dt: float) -> void:
	for n in 8:
		if Input.is_physical_key_pressed(KEY_1 + n) and not _edges.get("digit%d" % n, false) and not _digits_held.get(n, false):
			use_item = n
		_digits_held[n] = Input.is_physical_key_pressed(KEY_1 + n)
	for id in LATCHED:
		var act: String = "va_" + id
		if InputMap.has_action(act) and Input.is_action_just_pressed(act):
			_edges[id] = true

func _unhandled_input(e: InputEvent) -> void:
	if not enabled:
		return
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
		elif b.button_index == MOUSE_BUTTON_WHEEL_UP and b.pressed:
			twist = clampf(twist + 0.25, -PI, PI)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN and b.pressed:
			twist = clampf(twist - 0.25, -PI, PI)
		if b.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		var both := lmb and rmb
		var h = main if lmb else (off if rmb else null)
		if h == null:
			look_yaw -= m.relative.x * 0.0013 * sensitivity * sens_x
			look_pitch = clampf(look_pitch - m.relative.y * 0.0011 * sensitivity * sens_y * (-1.0 if invert_y else 1.0), -1.35, 1.35)
			return
		var s := 0.0024 * sensitivity
		for hh in ([main, off] if both else [h]):
			var lim := 2.0 if hh == main else 1.2
			hh.x = clampf(hh.x + m.relative.x * s, -lim, lim)
			hh.y = clampf(hh.y - m.relative.y * s, -1.6, 1.6)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## The input for this step, in the same shape as the web game's.
func sample(dt: float) -> Dictionary:
	if not lmb:
		main.x += (0.1 - main.x) * minf(1.0, dt * 2.5)
		main.y += (0.15 - main.y) * minf(1.0, dt * 2.5)
	if not rmb:
		off.x += (-0.35 - off.x) * minf(1.0, dt * 2.0)
		off.y += (0.1 - off.y) * minf(1.0, dt * 2.0)
	var want := 1.0 if held("thrust") else 0.0
	thrust += (want - thrust) * minf(1.0, dt * 10.0)
	var inp := {
		"mx": clampf((1.0 if held("left") else 0.0) - (1.0 if held("right") else 0.0), -1.0, 1.0),
		"mz": clampf((1.0 if held("forward") else 0.0) - (1.0 if held("back") else 0.0), -1.0, 1.0),
		"main": main.duplicate(),
		"off": off.duplicate(),
		"thrust": 0.0 if rmb and not lmb else thrust,
		"offThrust": thrust if rmb else 0.0,
		"power": lmb or rmb,
		"jabR": jab_r,
		"jabL": jab_l,
		"twist": twist,
		"look": {"yaw": look_yaw, "pitch": look_pitch},
		"sprint": held("sprint"),
		"crouch": held("crouch"),
		"jump": pressed("jump"),
		"kick": pressed("kick"),
		"grab": pressed("grab"),
		# G with a mouse button held grabs with that hand (both buttons: both hands).
		"grabHands": "both" if lmb and rmb else ("R" if lmb else ("L" if rmb else null)),
		"taunt": pressed("taunt"),
		"shove": pressed("shove"),
		"emote": pressed("emote"),
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
	return [snappedf(inp.get("mx", 0.0), 0.01), snappedf(inp.get("mz", 0.0), 0.01), snappedf(m.x, 0.001), snappedf(m.y, 0.001), snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(inp.get("thrust", 0.0), 0.01), snappedf(inp.get("offThrust", 0.0), 0.01), snappedf(inp.get("twist", 0.0), 0.01), snappedf(lk.yaw, 0.001), snappedf(lk.pitch, 0.001), bits, snappedf(inp.get("throwPower", 0.0), 0.01), int(inp.get("useItem", -1))]

const BITS := ["power", "sprint", "crouch", "jump", "kick", "jabR", "jabL", "grab", "throw", "taunt", "shove", "emote", "limp"]

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
	out.useItem = clampi(int(a[13]), -1, 7) if a.size() > 13 else -1
	return out
