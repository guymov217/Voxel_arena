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
var clear_k := 0.0   # 0..1: how far the camera has slid out over the shoulder to see past its own fighter
func follow(f, yaw: float, pitch: float, dt: float, aiming := false, foe = null) -> void:
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
		var want := base + Vector3(0, lerpf(0.75, 0.95, aim_k) * S - sin(pitch) * 1.6 * S, 0) - fwd * back + right * lerpf(0.55, 1.05, aim_k) * S
		want.y = maxf(0.3, want.y)
		# The foe is never behind your own back: when the line from the camera to him runs
		# through your head or shoulders, the camera slides further out over the right shoulder
		# and a little up until he is in the clear.
		var blocked := false
		if foe is Vector3 and f.alive:
			for body in [f.head, f.torso]:
				var c: Vector3 = body.get_global_transform_interpolated().origin
				var to: Vector3 = (foe as Vector3) - want
				var k := clampf((c - want).dot(to) / maxf(1e-4, to.length_squared()), 0.0, 1.0)
				if k > 0.0 and k < 1.0 and (want + to * k).distance_to(c) < 0.42 * S:
					blocked = true
		clear_k = move_toward(clear_k, 1.0 if blocked else 0.0, dt * (2.5 if blocked else 0.8))
		want += (right * 0.55 + Vector3(0, 0.3, 0)) * S * clear_k * (1.0 - aim_k)
		pos = pos.lerp(want, minf(1.0, dt * 10.0))
		# The view looks where the mouse points: all the way down at the sand at your feet,
		# or up at the stands (it used to look at a point two strides ahead, and looking down
		# hardly tilted it).
		var vp := clampf(pitch - 0.12, -1.45, 1.4)
		look = pos + (fwd * cos(vp) + Vector3(0, sin(vp), 0)) * 6.0 * S
	global_position = pos
	if pos.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
