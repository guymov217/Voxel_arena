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
var mmb := false                   # the wheel held down: the mouse turns the camera alone
var free_look := Vector2.ZERO      # (yaw, pitch) the camera is turned off the fighter's line by it
var thrust := 0.0
## The thrust key switches the thrust on and off (user: a toggle, not a key to hold): in it the
## blade points where the crosshair is, the mouse alone turns the view to aim it (up and down as
## well: the old held key took the mouse's push for the depth, and the view could not look up or
## down while it was held), and with the hand's button held the mouse drives the blade along its
## own line, in depth: pushed forward the point goes in, drawn back it comes out again, as fast as
## the mouse goes (side to side the view turns on, to follow the mark). Let go of the button and
## the blade comes back to its guard. From a pad (no mouse) a held thrust drives itself out.
var thrust_on := false    # the thrust switched on from the keyboard
var depth := 0.0          # -1 drawn back toward the chest .. 0 where the hand was .. 1 the full lunge
var depth_key := false    # the thrust on from the keyboard: the mouse has the depth
const DEPTH_PX := 240.0   # mouse travel (pixels, at sensitivity 1) from where the hand was to the full stab
var twist := 0.0
var aiming := false   # a bow, a crossbow or a throw in hand: the mouse turns the view, whatever is held
var two_handed := false   # both hands on one haft: either button swings it (set_two_handed)
var twist_l := 0.0   # the off hand's edge turn: the wheel turns whichever hand is held
var wheel := 0.0     # wheel steps since the last sample, when the Match wants them (a man held in the grip)
var wheel_to_grip := false
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
const LATCHED := ["jump", "kick", "grab", "taunt", "shove", "emote", "grip", "swap", "thrust"]
const PAD := {"jump": JOY_BUTTON_A, "kick": JOY_BUTTON_B, "grab": JOY_BUTTON_X, "throw": JOY_BUTTON_Y, "shove": JOY_BUTTON_LEFT_SHOULDER,
	"thrust": JOY_BUTTON_RIGHT_SHOULDER, "sprint": JOY_BUTTON_LEFT_STICK, "crouch": JOY_BUTTON_RIGHT_STICK, "taunt": JOY_BUTTON_BACK}
const PAD_ITEMS := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]
var pad_move := Vector2.ZERO
var pad_r := false
var pad_l := false
var _pad_items_held := {}

func _ready() -> void:
	setup_actions()
	# A pad plugged in (again) is measured afresh where its sticks lie.
	Input.joy_connection_changed.connect(func(dev: int, _on: bool):
		_pad_rest.erase(dev)
		_pad_live.erase(dev))

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

## What the keys that are not a letter or a digit read on a button (the words in the player's
## language; the arrows were blank before, their names cut off with the Left/Right of the side keys).
const KEY_LABELS := {"Space": "Space", "ShiftLeft": "Shift", "ShiftRight": "Shift", "ControlLeft": "Ctrl", "ControlRight": "Ctrl", "AltLeft": "Alt", "AltRight": "Alt", "Tab": "Tab", "Enter": "Enter", "Backquote": "`", "ArrowUp": "↑", "ArrowDown": "↓", "ArrowLeft": "←", "ArrowRight": "→"}

## How a binding reads on a button: "W", "Space", "Shift".
static func label_of(code: String) -> String:
	if code.begins_with("Key") or code.begins_with("Digit"):
		return code.trim_prefix("Key").trim_prefix("Digit")
	return Loc.t(String(KEY_LABELS.get(code, code)))

func held(id: String) -> bool:
	var act := "va_" + id
	return InputMap.has_action(act) and Input.is_action_pressed(act)

## Whether a pad's own button for `id` is down (a thrust held on a pad, which has no mouse to
## drive it in depth, drives itself out).
func _pad_holds(id: String) -> bool:
	if not PAD.has(id):
		return false
	for p in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(p, PAD[id]):
			return true
	return false

func pressed(id: String) -> bool:
	return _edges.get(id, false)

var use_item := -1
var throw_cancelled := false   # the right button while F is held: the hand keeps its grip until F is let go
var throw_other := false       # the left button tapped while F is held: the other hand throws

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
		# Winding up a throw (F held) the buttons mean something else: the left one picks the
		# other hand, the right one calls the throw off. Neither swings an arm.
		if held("throw") and b.pressed and (b.button_index == main_btn or b.button_index == off_btn):
			if b.button_index == main_btn:
				throw_other = not throw_other
			else:
				throw_cancelled = true
				throw_charge = 0.0
			return
		if b.button_index == main_btn:
			lmb = b.pressed
			if b.pressed:
				jab_r = true
		elif b.button_index == off_btn:
			rmb = b.pressed
			if b.pressed:
				jab_l = true
		elif b.button_index == MOUSE_BUTTON_MIDDLE:
			mmb = b.pressed
		elif (b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN) and b.pressed:
			var dw := 0.25 if b.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25
			# Round and round, like the web game: past half a turn it comes back the other way.
			if wheel_to_grip:
				wheel += 1.0 if b.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			elif rmb and not lmb and not two_handed:
				twist_l = wrapf(twist_l - dw, -PI, PI)
			else:
				twist = wrapf(twist + dw, -PI, PI)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		if mmb:
			# A look round: the camera orbits the fighter any way the mouse goes, and neither
			# he nor his hands move for it. Let go and it swings back behind him.
			free_look.x -= m.relative.x * 0.0022 * sensitivity * sens_x
			free_look.y = clampf(free_look.y - m.relative.y * 0.0018 * sensitivity * sens_y * (-1.0 if invert_y else 1.0), -1.3, 1.3)
			return
		_motion(m.relative)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## The mouse moved (caught): the hand whose button is down goes with it, or the view turns.
func _motion(rel: Vector2) -> void:
	# The thrust on and a hand's button held: the mouse's push on and back is the blade's depth,
	# and side to side it turns the view (the blade follows the crosshair). Without a button the
	# mouse turns the view both ways, as always: that is how the stab is aimed.
	if depth_key and not aiming and (lmb or rmb):
		depth = clampf(depth - rel.y * sensitivity * sens_y / DEPTH_PX, -1.0, 1.0)
		look_yaw -= rel.x * 0.001 * sensitivity * sens_x
		return
	var both := lmb and rmb and not two_handed
	var h = main if lmb or (rmb and two_handed) else (off if rmb else null)
	if h == null or aiming:
		look_yaw -= rel.x * 0.001 * sensitivity * sens_x
		look_pitch = clampf(look_pitch - rel.y * 0.00085 * sensitivity * sens_y * (-1.0 if invert_y else 1.0), -1.45, 1.35)
		return
	var s := 0.0024 * sensitivity
	for hh in ([main, off] if both else [h]):
		var lim := 2.0
		hh.x = clampf(hh.x + rel.x * s, -lim, lim)
		hh.y = clampf(hh.y - rel.y * s, -1.6, 1.6)

## Both hands back at their guard (a new fighter of ours: a bout, the yard, a respawn).
func reset_hands() -> void:
	main = {"x": 0.1, "y": 0.15}
	off = {"x": -0.35, "y": 0.1}
	thrust = 0.0
	depth = 0.0
	thrust_on = false

## Both hands on one haft, the off hand's mark is not its own: either button (or both) swings
## the weapon with the main hand's. Moved along unseen under the grip, the off hand's mark was
## left wherever the mouse had gone (up by the head), and when the grip ended (H, the weapon
## knocked away) the left arm went up there and stayed (user). So it is set back to its guard.
func set_two_handed(on: bool) -> void:
	if two_handed and not on:
		off = {"x": -0.35, "y": 0.1}
	two_handed = on

## Each pad's sticks and triggers as they lie untouched, and whether it has been taken up yet.
var _pad_rest := {}
var _pad_live := {}
const PAD_AXES := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]

## A pad's axes against where they lie untouched, and whether it is in use: a pad counts only
## once a button of it is pressed or a stick or trigger is moved well off where it lay when it
## was first seen. A stick that rests off centre, or a wheel, pedals or a virtual pad that reads
## as a gamepad with an axis held over, walked the man off sideways by himself with the sword hand
## up (user video 1029: "the strange drift to the left when I do nothing"). `raw` axis -> value.
static func pad_reading(raw: Dictionary, rest: Dictionary, live: bool, buttons: bool) -> Dictionary:
	var rel := {}
	var moved := false
	for ax in raw:
		var r := float(rest.get(ax, raw[ax]))
		rel[ax] = float(raw[ax]) - r
		if absf(float(rel[ax])) > 0.5:
			moved = true
	return {"rel": rel, "live": live or buttons or moved}

## The gamepad, read once a step: sticks and triggers (buttons come through the input actions).
func _pad(dt: float) -> void:
	var d := -1
	for p in Input.get_connected_joypads():
		# Only a pad the game knows for one (not a wheel, pedals or a flight stick).
		if Input.is_joy_known(p):
			d = p
			break
	if d < 0:
		pad_move = Vector2.ZERO
		pad_r = false
		pad_l = false
		return
	var raw := {}
	for ax in PAD_AXES:
		raw[ax] = Input.get_joy_axis(d, ax)
	if not _pad_rest.has(d):
		_pad_rest[d] = raw.duplicate()
	var any_button := false
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START] + PAD_ITEMS:
		if Input.is_joy_button_pressed(d, b):
			any_button = true
	var rd := pad_reading(raw, _pad_rest[d], bool(_pad_live.get(d, false)), any_button)
	_pad_live[d] = rd.live
	if not rd.live:
		pad_move = Vector2.ZERO
		pad_r = false
		pad_l = false
		return
	var rel: Dictionary = rd.rel
	var dz := func(v: float) -> float: return 0.0 if absf(v) < 0.18 else (v - signf(v) * 0.18) / 0.82
	pad_move = Vector2(dz.call(rel[JOY_AXIS_LEFT_X]), dz.call(rel[JOY_AXIS_LEFT_Y]))
	var rt: bool = float(rel[JOY_AXIS_TRIGGER_RIGHT]) > 0.3
	var lt: bool = float(rel[JOY_AXIS_TRIGGER_LEFT]) > 0.3
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
	var rs := Vector2(dz.call(rel[JOY_AXIS_RIGHT_X]), dz.call(rel[JOY_AXIS_RIGHT_Y]))
	if not (pad_r or pad_l):
		look_yaw -= rs.x * dt * 2.1 * sensitivity * sens_x
		look_pitch = clampf(look_pitch - rs.y * dt * 1.45 * sensitivity * sens_y * (-1.0 if invert_y else 1.0), -1.45, 1.35)
	else:
		for hh in ([main] if pad_r or (pad_l and two_handed) else []) + ([off] if pad_l and not two_handed else []):
			var lim := 2.0
			hh.x = clampf(hh.x + rs.x * dt * 3.2 * sensitivity, -lim, lim)
			hh.y = clampf(hh.y - rs.y * dt * 3.2 * sensitivity, -1.6, 1.6)
	for i in PAD_ITEMS.size():
		var down := Input.is_joy_button_pressed(d, PAD_ITEMS[i])
		if down and not _pad_items_held.get(i, false):
			use_item = i
		_pad_items_held[i] = down

## Which hands are empty (a boxer's: no weapon, nothing readied in it), set by the match.
var unarmed_r := false
var unarmed_l := false
func set_unarmed(r: bool, l: bool) -> void:
	unarmed_r = r
	unarmed_l = l

## A boxer's guard: both fists up before the chin, the lead (left) one a little higher and out.
const GUARD_MAIN := {"x": 0.1, "y": 1.0}
const GUARD_OFF := {"x": -0.2, "y": 1.05}

static func _ease_to(h: Dictionary, to: Dictionary, k: float) -> void:
	h.x = lerpf(float(h.x), float(to.x), k)
	h.y = lerpf(float(h.y), float(to.y), k)

## The input for this step, in the same shape as the web game's.
func sample(dt: float) -> Dictionary:
	_pad(dt)
	# Empty-handed, a fist that is not being thrown goes back up into the guard (user: with no
	# weapon he boxes, his hands in a boxer's guard); a weapon stays where it was last aimed.
	var gk := minf(1.0, dt * 10.0)
	if unarmed_r and not (lmb or pad_r or (two_handed and (rmb or pad_l))):
		_ease_to(main, GUARD_MAIN, gk)
	if unarmed_l and not (rmb or pad_l) and not two_handed:
		_ease_to(off, GUARD_OFF, gk)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		lmb = false   # let go of the mouse with a button down: its release never reaches us
		rmb = false
		mmb = false
	if not mmb:
		free_look = free_look.lerp(Vector2.ZERO, minf(1.0, dt * 6.0))
	var hand_r := lmb or pad_r or (two_handed and (rmb or pad_l))
	var hand_l := (rmb or pad_l) and not two_handed
	# Let go of the button and the hand stays where it was aimed: it no longer slides back to a
	# guard of its own (user: the weapon must hold the last place it was aimed at).
	var pad_thrust := _pad_holds("thrust")
	if pressed("thrust") and not pad_thrust:
		thrust_on = not thrust_on
	var want := 1.0 if thrust_on or pad_thrust else 0.0
	thrust += (want - thrust) * minf(1.0, dt * 30.0)
	depth_key = thrust_on and not pad_thrust
	if not depth_key:
		depth = 0.0
	elif not (lmb or rmb):
		depth = move_toward(depth, 0.0, dt * 3.0)   # (the button let go: back to the guard)
	var inp := {
		"mx": clampf((1.0 if held("left") else 0.0) - (1.0 if held("right") else 0.0) - pad_move.x, -1.0, 1.0),
		"mz": clampf((1.0 if held("forward") else 0.0) - (1.0 if held("back") else 0.0) - pad_move.y, -1.0, 1.0),
		"main": main.duplicate(),
		"off": off.duplicate(),
		"thrust": 0.0 if hand_l and not hand_r else thrust,
		"offThrust": thrust if hand_l else 0.0,
		"depthOn": depth_key,
		"depth": depth,
		"power": hand_r or hand_l,
		"jabR": jab_r,
		"jabL": jab_l,
		"twist": twist,
		"offTwist": twist_l,
		"wheel": wheel,
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
		"revive": held("revive"),
		"useItem": use_item,
	}
	use_item = -1
	# F: hold to wind up a throw, let go to throw. A quick tap is a lob. The right hand throws
	# first (the left once it is empty); a tap of the left button while F is held picks the
	# other hand, a tap of the right button calls the throw off: the hand keeps its grip.
	if held("throw"):
		if not throw_cancelled:
			throw_charge = minf(1.0, throw_charge + dt / 1.1)
			inp.charging = throw_charge
			inp.throwOther = throw_other
	else:
		if throw_charge > 0.0 and not throw_cancelled:
			inp.throw = true
			inp.throwPower = maxf(0.3, throw_charge)
			inp.throwOther = throw_other
		throw_charge = 0.0
		throw_cancelled = false
		throw_other = false
	_edges.clear()
	jab_r = false
	jab_l = false
	wheel = 0.0
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
	bits |= (1 if inp.get("throwOther", false) else 0) << 16
	bits |= (1 if inp.get("grip", false) else 0) << 17
	bits |= (1 if inp.get("revive", false) else 0) << 19
	bits |= (1 if inp.get("depthOn", false) else 0) << 20
	var aim = inp.get("aimAt")
	bits |= (1 if aim is Vector3 else 0) << 18
	var out := [snappedf(inp.get("mx", 0.0), 0.01), snappedf(inp.get("mz", 0.0), 0.01), snappedf(m.x, 0.001), snappedf(m.y, 0.001), snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(inp.get("thrust", 0.0), 0.01), snappedf(inp.get("offThrust", 0.0), 0.01), snappedf(inp.get("twist", 0.0), 0.01), snappedf(lk.yaw, 0.001), snappedf(lk.pitch, 0.001), bits, snappedf(inp.get("throwPower", 0.0), 0.01), int(inp.get("useItem", -1)), snappedf(inp.get("offTwist", 0.0), 0.01), snappedf(float(inp.get("charging", 0.0)), 0.01)]
	# Where his crosshair sits (his camera's ray into the world): the bow, the thrust, a throw
	# and a pot all go there, as they do for the host's own player.
	if aim is Vector3:
		out.append_array([snappedf(aim.x, 0.01), snappedf(aim.y, 0.01), snappedf(aim.z, 0.01)])
		var af = inp.get("aimFrom")
		if af is Vector3:
			out.append_array([snappedf(af.x, 0.01), snappedf(af.y, 0.01), snappedf(af.z, 0.01), clampf(float(inp.get("wheel", 0.0)), -6.0, 6.0)])
	# The thrust driven in depth by the mouse: how deep, last of all (bit 20 says it is there).
	if inp.get("depthOn", false):
		out.append(snappedf(clampf(float(inp.get("depth", 0.0)), -1.0, 1.0), 0.01))
	return out

const BITS := ["power", "sprint", "crouch", "jump", "kick", "jabR", "jabL", "grab", "throw", "taunt", "shove", "emote", "limp", "swap"]

static func has_one_shot(inp: Dictionary) -> bool:
	if int(inp.get("useItem", -1)) >= 0:
		return true
	for k in ONE_SHOT:
		if inp.get(k, false):
			return true
	return false

static func unpack(a: Array) -> Dictionary:
	if a.size() < 12 or a.size() > 32:
		return {}
	# (Every number made a real one first: a guest's NaN or infinity got through a clamp and into
	# the host's physics.)
	for i in a.size():
		if not (a[i] is float or a[i] is int):
			return {}
		if a[i] is float and not is_finite(a[i]):
			a[i] = 0.0
	var bits := int(a[11])
	var out := {"mx": clampf(a[0], -1, 1), "mz": clampf(a[1], -1, 1), "main": {"x": clampf(a[2], -2, 2), "y": clampf(a[3], -1.6, 1.6)}, "off": {"x": clampf(a[4], -2, 2), "y": clampf(a[5], -1.6, 1.6)},
		"thrust": clampf(a[6], -1.5, 1.5), "offThrust": clampf(a[7], -1.5, 1.5), "twist": clampf(a[8], -PI, PI), "look": {"yaw": clampf(float(a[9]), -1000.0, 1000.0), "pitch": clampf(a[10], -1.35, 1.35)}}
	for i in BITS.size():
		out[BITS[i]] = bits & (1 << i) != 0
	out.grabHands = [null, "R", "L", "both"][(bits >> 14) & 3]
	out.throwOther = bits & (1 << 16) != 0
	out.throwPower = clampf(float(a[12]), 0.0, 1.0) if a.size() > 12 else 0.8
	out.useItem = clampi(int(a[13]), -1, 8) if a.size() > 13 else -1
	out.offTwist = clampf(float(a[14]), -PI, PI) if a.size() > 14 else 0.0
	out.grip = bits & (1 << 17) != 0
	out.revive = bits & (1 << 19) != 0
	if a.size() > 15 and float(a[15]) > 0.0:
		out.charging = clampf(float(a[15]), 0.0, 1.0)
	if bits & (1 << 18) != 0 and a.size() > 18:
		out.aimAt = Vector3(clampf(float(a[16]), -300, 300), clampf(float(a[17]), -50, 200), clampf(float(a[18]), -300, 300))
		if a.size() > 21:
			out.aimFrom = Vector3(clampf(float(a[19]), -300, 300), clampf(float(a[20]), -50, 200), clampf(float(a[21]), -300, 300))
		if a.size() > 22 and float(a[22]) != 0.0:
			out.wheel = clampf(float(a[22]), -6.0, 6.0)
	if bits & (1 << 20) != 0 and a.size() > 16:
		out.depthOn = true
		out.depth = clampf(float(a[a.size() - 1]), -1.0, 1.0)
	return out
