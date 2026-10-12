class_name CameraRig
extends Camera3D
## Third-person camera behind the fighter, turning with the mouse look (game.js updateCamera).

var pos := Vector3(0, 3, -9)
var look := Vector3(0, 1, 0)

func _ready() -> void:
	# Moved every frame, after the bodies' interpolated positions: not by the physics.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = 65.0
	near = 0.05
	current = true
	global_position = pos

## The menu's attract mode: a slow orbit around the action.
var orbit_a := 0.0
func orbit(center: Vector3, dt: float) -> void:
	orbit_a += dt * 0.09
	var want := center + Vector3(sin(orbit_a) * 6.5, 2.2, cos(orbit_a) * 6.5)
	pos = pos.lerp(want, minf(1.0, dt * 1.5))
	look = look.lerp(center + Vector3(0, 0.7, 0), minf(1.0, dt * 2.0))
	global_position = pos
	look_at(look, Vector3.UP)

## While a throw is wound up the camera closes in over the right shoulder and narrows, so the
## mark sits under the crosshair and the arc is easy to judge.
var aim_k := 0.0
func follow(f, yaw: float, pitch: float, dt: float, aiming := false) -> void:
	aim_k = move_toward(aim_k, 1.0 if aiming else 0.0, dt * 4.0)
	fov = lerpf(65.0, 50.0, aim_k)
	if f == null or not is_instance_valid(f):
		var a := Time.get_ticks_msec() / 1000.0 * 0.15
		pos = pos.lerp(Vector3(sin(a) * 9.0, 3.5, cos(a) * 9.0), minf(1.0, dt * 2.0))
		look = look.lerp(Vector3(0, 1.0, 0), minf(1.0, dt * 2.0))
	else:
		var S: float = f.S
		var base: Vector3 = (f.torso if f.alive else f.head).get_global_transform_interpolated().origin
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		var back := lerpf(2.6, 2.0, aim_k) * S * cos(pitch * 0.6)
		var want := base + Vector3(0, lerpf(0.75, 0.95, aim_k) * S - sin(pitch) * 1.6 * S, 0) - fwd * back + right * lerpf(0.35, 1.05, aim_k) * S
		want.y = maxf(0.3, want.y)
		pos = pos.lerp(want, minf(1.0, dt * 10.0))
		look = base + fwd * 2.0 * S + Vector3(0, 0.35 * S + sin(pitch) * 2.0 * S, 0)
	global_position = pos
	if pos.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
