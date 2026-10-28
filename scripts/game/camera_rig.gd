class_name CameraRig
extends Camera3D
## Third-person camera behind the fighter, turning with the mouse look (game.js updateCamera).

var pos := Vector3(0, 3, -9)   # where it wants to be (eased toward its place behind him)
var eye := pos                  # where it is: that, kept clear of the walls
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

## The camera kept on the fighter's side of the arena wall (and of the yard's walls and props):
## backed against the wall, it comes in toward him only as far as the wall makes it, at once,
## and lets out again slowly; what it gives up behind him it takes in height, rising over his
## head to look down past it (pulled in on the line to him it sat in the back of his head).
## (It used to be pulled in to the wall and then eased on from there toward the place behind
## the wall, through it and back every other frame: a quarter-metre shake.)
var wall_k := 1.0   # how much of its reach back from him the walls leave it (1: all of it)
func _clear_of_walls(from: Vector3, to: Vector3, S: float, dt: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var k := _clear_k(from, from + flat)
	wall_k = k if k < wall_k else move_toward(wall_k, k, dt * 1.5)
	var e := from + flat * wall_k + Vector3(0.0, to.y - from.y + (1.0 - wall_k) * 1.1 * S, 0.0)
	# Nothing over him either (a beam, a stall's roof in the yard): there it stops short.
	return from + (e - from) * _clear_k(from, e)

## How far along from `from` to `to` the camera may go before the first wall, a hand's width
## short of it so the near plane never cuts into it (0..1).
func _clear_k(from: Vector3, to: Vector3) -> float:
	var len := from.distance_to(to)
	if not is_inside_tree() or len < 1e-4:
		return 1.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, VoxelPart.LAYER_WORLD))
	if hit.is_empty():
		return 1.0
	return clampf((from.distance_to(hit.position) - 0.25) / len, 0.02, 1.0)

## The camera's place `want` (behind the fighter at `base`) turned round him by `sp.x` and raised by `sp.y`.
static func _spot(base: Vector3, want: Vector3, sp: Vector2, S: float) -> Vector3:
	return base + Basis(Vector3.UP, sp.x) * (want - base) + Vector3(0, sp.y * S, 0)

## How much of the foe your own body hides from `eye`: his middle and head count one each, the
## spot just struck two (pts: middle, head, feet, then the blow and the blade's point, if any).
## Not the point of your own blade: it is at your own hand, behind your own arm half the time,
## and the camera bobbed up and down with every move of the weapon (user: it runs off as I aim).
static func _blocked(f, eye: Vector3, pts: Array, tip := -1) -> float:
	var n := 0.0
	for i in pts.size():
		if i == 2 or i == tip:
			continue   # (the feet: the sand at his feet is no matter)
		var to: Vector3 = pts[i]
		var hidden := false
		for p in f.parts:
			if p.severed:
				continue
			var inv: Transform3D = p.global_transform.affine_inverse()
			var e: Vector3 = p.half_ext * 1.1
			var a: Vector3 = inv * eye
			var b: Vector3 = inv * to
			# The segment against the part's box (slab test).
			var t0 := 0.0
			var t1 := 1.0
			var d := b - a
			var miss := false
			for ax in 3:
				if absf(d[ax]) < 1e-6:
					if absf(a[ax]) > e[ax]:
						miss = true
						break
				else:
					var ta := (-e[ax] - a[ax]) / d[ax]
					var tb := (e[ax] - a[ax]) / d[ax]
					t0 = maxf(t0, minf(ta, tb))
					t1 = minf(t1, maxf(ta, tb))
					if t0 > t1:
						miss = true
						break
			if not miss and t1 < 0.97:
				hidden = true
				break
		if hidden:
			n += 2.0 if i >= 3 else 1.0
	return n

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
var shift := Vector2.ZERO   # (turn round him in radians, up in body heights): where the camera has gone to see past its own fighter
var scan_t := 0.0
var hide_k := 0.0            # how much of the foe your own body hid, last looked
## How far round him the camera turns in close fighting (radians), and how fast it goes round
## as the foe comes and goes: turned further (0.9) and quicker (1.5 a second), the view went
## round and back with every step he took in or out while you aimed (user: the camera runs off).
const ORBIT := 0.6
const NEAR_RATE := 0.6
var near_k := 0.0    # 0..1: how far it has drawn back for a foe close in
var assist := Vector2.ZERO   # the turn (yaw, pitch) it adds to keep the foe in the frame
var jolt := Vector3.ZERO     # a landed blow's jolt to the camera (world, decays)
var fov_jolt := 0.0          # and its punch in (degrees)

## A blow that lands jolts the view the way it went and punches in a little (k 0..1).
func kick(dir: Vector3, k: float) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)).normalized()
	jolt += d * 0.14 * k + Vector3(0, -0.05 * k, 0)
	fov_jolt = maxf(fov_jolt, 5.0 * k)
var base_y := NAN   # his height as the camera takes it: a stoop or a bob of the swing is let pass
var focus_s := -1.0  # how far ahead of him the view looks when turned round him (eased)
var reaim_k := 1.0   # how much the view is turned onto the place ahead of him (none while aiming)

## The look (yaw, pitch) that would have the view where it is now: given to the aim when a throw
## or a draw begins, so that the view, now along the aim, does not jump.
func view_angles() -> Vector2:
	var d := (look - eye).normalized()
	return Vector2(atan2(d.x, d.z), asin(clampf(d.y, -1.0, 1.0)) + 0.12 + 0.45 * (1.0 - wall_k))
func follow(f, yaw: float, pitch: float, dt: float, aiming := false, foe = null, tip := -1) -> void:
	aim_k = move_toward(aim_k, 1.0 if aiming else 0.0, dt * 4.0)
	fov = lerpf(65.0, 50.0, aim_k)
	if f == null or not is_instance_valid(f):
		var a := Time.get_ticks_msec() / 1000.0 * 0.15
		pos = pos.lerp(Vector3(sin(a) * 9.0, 3.5, cos(a) * 9.0), minf(1.0, dt * 2.0))
		eye = pos
		look = look.lerp(Vector3(0, 1.0, 0), minf(1.0, dt * 2.0))
	else:
		var S: float = f.S
		var base: Vector3 = (f.torso if f.alive else f.head).get_global_transform_interpolated().origin
		# The camera rises and sinks with him slowly: he stoops to a low blow and comes up again a
		# moment later (the view bobbed with every one), but a fall or a jump it follows.
		if is_nan(base_y) or absf(base.y - base_y) > 1.2 * S:
			base_y = base.y
		base_y = lerpf(base_y, base.y, minf(1.0, dt * 2.5))
		base.y = base_y
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
		near_k = move_toward(near_k, close, dt * NEAR_RATE)
		var back := lerpf(2.6, 2.0, aim_k) * S * cos(pitch * 0.6) + 0.8 * S * near_k
		var want := base + Vector3(0, lerpf(0.75, 0.95, aim_k) * S - sin(pitch) * 1.6 * S + 0.35 * S * near_k, 0) - fwd * back + right * lerpf(0.55, 1.05, aim_k) * S
		want.y = maxf(0.3, want.y)
		# Close in, the camera turns part way round him, off the side his weapon arm is on: a
		# blow lands an arm's length in front of the chest, and from straight behind the
		# striking arm, the shoulder and the head were on the line to it (a third of the blows
		# landed out of sight: user; measured in bot duels, from straight behind 71% of the
		# blows that landed could be seen, turned 0.9 round about 80%: ORBIT). And when even so your
		# own body is between the camera and his middle or head, it rises a little.
		var turn := ORBIT * near_k * (1.0 - aim_k)
		var lift := 0.0
		if f.alive and not pts.is_empty() and aim_k < 0.5:
			scan_t -= dt
			if scan_t <= 0.0:
				scan_t = 0.1
				hide_k = _blocked(f, _spot(base, want, Vector2(turn, 0.0), S), pts, tip)
			lift = 0.3 if hide_k > 0.0 else 0.0
		shift = shift.lerp(Vector2(turn, lift * (1.0 - aim_k)), minf(1.0, dt * 2.0))
		want = _spot(base, want, shift, S)
		pos = pos.lerp(want, minf(1.0, dt * 10.0))
		eye = _clear_of_walls(base + Vector3(0, 0.5 * S, 0), pos, S, dt)
		# The view looks where the mouse points: all the way down at the sand at your feet,
		# or up at the stands (it used to look at a point two strides ahead, and looking down
		# hardly tilted it).
		# (Risen over his head off a wall at his back, it looks down past him a little more.)
		var vp := clampf(pitch - 0.12 - 0.45 * (1.0 - wall_k), -1.45, 1.4)
		# Turned round him, the view still looks where he faces: at the place a stride or so
		# ahead of him that it looked at from behind (the foe's distance), so the fight is in the
		# middle of the picture and the crosshair still lands on the foe, not off at the side.
		# (Taken from where the camera is meant to be off him, not where it has got to, and to a
		# place that moves only as the foe comes and goes: from where it trailed his sway, at a
		# place as far off as the foe was that instant, the view swung with every stroke of his
		# weapon, seven degrees a second of a turn nobody asked for: user, it runs off as I aim.)
		var focus := 4.0 * S
		if fc is Vector3:
			focus = clampf(Vector2((fc as Vector3).x - base.x, (fc as Vector3).z - base.z).length(), 1.5 * S, 5.0 * S)
		focus_s = focus if focus_s < 0.0 else lerpf(focus_s, focus, minf(1.0, dt * 1.5))
		var to_f: Vector3 = fwd * focus_s - (want - base)
		# A throw or a draw being aimed looks along the aim itself from its first moment (and
		# comes back to this slowly after): the view easing off a turn round him, or off keeping
		# the foe in frame, through the wind-up, a quick throw and a slow one at the same mark
		# went at different angles (user).
		reaim_k = 0.0 if aiming else move_toward(reaim_k, 1.0, dt * 2.0)
		var yv := yaw
		if absf(shift.x) > 1e-3 and Vector2(to_f.x, to_f.z).length() > 0.3:
			yv = yaw + wrapf(atan2(to_f.x, to_f.z) - yaw, -PI, PI) * reaim_k
		var fwd_v := Vector3(sin(yv), 0, cos(yv))
		# The foe stays in the picture: when his head, his feet or the spot just struck would
		# leave the frame, the view turns just far enough to keep them in (the mouse still
		# steers; the crosshair, the middle of the view, goes where the view goes).
		var want_as := Vector2.ZERO
		if not pts.is_empty() and f.alive and aim_k < 0.5:
			var f0 := fwd_v * cos(vp) + Vector3(0, sin(vp), 0)
			var r0 := f0.cross(Vector3.UP).normalized()
			var u0 := r0.cross(f0)
			var tv := tan(deg_to_rad(fov) * 0.5)
			var vsz := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
			var lim_v := atan(0.72 * tv)
			var lim_h := atan(0.78 * tv * vsz.x / maxf(1.0, vsz.y))
			var hmin := INF; var hmax := -INF; var vmin := INF; var vmax := -INF
			for p in pts:
				var rel: Vector3 = (p as Vector3) - eye
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
		assist = Vector2.ZERO if aiming else assist.lerp(want_as, minf(1.0, dt * 5.0))
		var vy := yv - assist.x
		var vpp := clampf(vp + assist.y, -1.5, 1.45)
		look = eye + Vector3(sin(vy) * cos(vpp), sin(vpp), cos(vy) * cos(vpp)) * 6.0 * S
	jolt = jolt.lerp(Vector3.ZERO, minf(1.0, dt * 14.0))
	fov_jolt = move_toward(fov_jolt, 0.0, dt * 40.0)
	fov -= fov_jolt
	global_position = eye + jolt
	if global_position.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
