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

## How far to turn so that the span [lo, hi] (angles from the middle of the view) lies within
## ±lim: nothing while it does, the least turn when it does not, its middle when it is too wide.
static func _shift(lo: float, hi: float, lim: float) -> float:
	if hi - lo > 2.0 * lim:
		return (lo + hi) * 0.5
	if hi > lim:
		return hi - lim
	if lo < -lim:
		return lo + lim
	return 0.0

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
var near_k := 0.0    # 0..1: how far it has drawn back for a foe close in
var assist := Vector2.ZERO   # the turn (yaw, pitch) it adds to keep the foe in the frame
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
		# The foe: a point to keep clear of your own head (his middle), and all the points to keep
		# in the frame (his head, middle, feet, where you just struck him).
		var pts: Array = foe if foe is Array else ([foe] if foe is Vector3 else [])
		var fc = pts[0] if not pts.is_empty() else null
		var close := 0.0
		if fc is Vector3:
			var dh := Vector2((fc as Vector3).x - base.x, (fc as Vector3).z - base.z).length()
			close = clampf((3.2 * S - dh) / (2.2 * S), 0.0, 1.0) * (1.0 - aim_k)
		near_k = move_toward(near_k, close, dt * 1.5)
		var back := lerpf(2.6, 2.0, aim_k) * S * cos(pitch * 0.6) + 0.8 * S * near_k
		var want := base + Vector3(0, lerpf(0.75, 0.95, aim_k) * S - sin(pitch) * 1.6 * S + 0.35 * S * near_k, 0) - fwd * back + right * lerpf(0.55, 1.05, aim_k) * S
		want.y = maxf(0.3, want.y)
		# The foe is never behind your own back: when the line from the camera to him runs
		# through your head or shoulders, the camera slides further out over the right shoulder
		# and a little up until he is in the clear.
		var blocked := false
		if fc is Vector3 and f.alive:
			for body in [f.head, f.torso]:
				var c: Vector3 = body.get_global_transform_interpolated().origin
				var to: Vector3 = (fc as Vector3) - want
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
		# The foe stays in the picture: when his head, his feet or the spot just struck would
		# leave the frame, the view turns just far enough to keep them in (the mouse still
		# steers; the crosshair, the middle of the view, goes where the view goes).
		var want_as := Vector2.ZERO
		if not pts.is_empty() and f.alive and aim_k < 0.5:
			var f0 := fwd * cos(vp) + Vector3(0, sin(vp), 0)
			var r0 := f0.cross(Vector3.UP).normalized()
			var u0 := r0.cross(f0)
			var tv := tan(deg_to_rad(fov) * 0.5)
			var vsz := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
			var lim_v := atan(0.72 * tv)
			var lim_h := atan(0.78 * tv * vsz.x / maxf(1.0, vsz.y))
			var hmin := INF; var hmax := -INF; var vmin := INF; var vmax := -INF
			for p in pts:
				var rel: Vector3 = (p as Vector3) - pos
				var z := rel.dot(f0)
				if z < 0.3:
					continue
				var x := rel.dot(r0)
				var y := rel.dot(u0)
				var ah := atan2(x, z)
				var av := atan2(y, sqrt(x * x + z * z))
				hmin = minf(hmin, ah); hmax = maxf(hmax, ah)
				vmin = minf(vmin, av); vmax = maxf(vmax, av)
			if hmax > -INF:
				want_as.x = _shift(hmin, hmax, lim_h)
				want_as.y = _shift(vmin, vmax, lim_v)
		want_as = Vector2(clampf(want_as.x, -0.5, 0.5), clampf(want_as.y, -0.6, 0.6))
		assist = assist.lerp(want_as, minf(1.0, dt * 5.0))
		var vy := yaw - assist.x
		var vpp := clampf(vp + assist.y, -1.5, 1.45)
		look = pos + Vector3(sin(vy) * cos(vpp), sin(vpp), cos(vy) * cos(vpp)) * 6.0 * S
	global_position = pos
	if pos.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
