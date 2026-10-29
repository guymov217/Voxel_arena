class_name FlyCam
## The forges' camera flown on the walking keys (as bound in Controls): W toward what the mouse
## points at (the middle of the view with the mouse off it), S back the same way, A and D across,
## Space and Ctrl (jump, crouch) up and down, Shift (run) faster. The forge moves what its camera
## looks at by the step, so the camera flies on with it (W only drew it in toward the weapon's
## middle and stuck a hand's breadth short of it: user).

const KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE, "crouch": KEY_CTRL, "sprint": KEY_SHIFT}

static func held(id: String) -> bool:
	if InputMap.has_action("va_" + id):
		return Input.is_action_pressed("va_" + id)
	# Not yet bound (no fight started since the game opened): the default keys.
	return Input.is_physical_key_pressed(KEYS[id])

## Whether the keys are the camera's now: not while a name is typed in. (A number box keeps the
## keyboard after a click on it, and W went to it instead: the camera "sometimes" stood still.)
static func keys_free(node: Control) -> bool:
	var fo := node.get_viewport().gui_get_focus_owner()
	if fo is TextEdit:
		return false
	return not (fo is LineEdit and not (fo.get_parent() is SpinBox))

## This frame's move for the camera, `aim` the way the mouse points (ZERO: the way it looks).
static func step(node: Control, cam: Camera3D, aim: Vector3, speed: float, dt: float) -> Vector3:
	if cam == null or not node.is_visible_in_tree() or not keys_free(node):
		return Vector3.ZERO
	var v := Vector3.ZERO
	if held("forward"): v.z += 1.0
	if held("back"): v.z -= 1.0
	if held("left"): v.x -= 1.0
	if held("right"): v.x += 1.0
	if held("jump"): v.y += 1.0
	if held("crouch"): v.y -= 1.0
	if v == Vector3.ZERO:
		return Vector3.ZERO
	var b := cam.global_transform.basis
	var fwd := aim.normalized() if aim.length_squared() > 1e-6 else -b.z
	var right := fwd.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 1e-6 else b.x
	var mv := fwd * v.z + right * v.x + Vector3.UP * v.y
	return mv.normalized() * speed * (2.5 if held("sprint") else 1.0) * dt
