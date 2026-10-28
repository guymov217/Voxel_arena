class_name PD
## Rotation and torque helpers shared by fighters and beasts (the same maths as character.js).

## Rotation vector (axis * angle) that takes rotation `from` to rotation `to`.
static func rot_error(to: Quaternion, from: Quaternion) -> Vector3:
	var q := (to * from.inverse()).normalized()
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	var s := sqrt(maxf(1e-9, 1.0 - q.w * q.w))
	var angle := 2.0 * acos(minf(1.0, q.w))
	return Vector3(q.x / s * angle, q.y / s * angle, q.z / s * angle)

## Rotation vector that turns direction `cur` onto direction `des`.
static func dir_error(cur: Vector3, des: Vector3) -> Vector3:
	var c := cur.cross(des)
	var sn := c.length()
	if sn < 1e-6:
		return Vector3.ZERO
	return c * (atan2(sn, cur.dot(des)) / sn)

static func clamp_len(v: Vector3, mx: float) -> Vector3:
	var l := v.length()
	return v * (mx / l) if l > mx and l > 0.0 else v

## Torque that gives `alpha` (rad/s^2) on `body`, honouring its inertia (set on every body).
static func torque_for(body: RigidBody3D, alpha: Vector3, scale := 1.0) -> Vector3:
	var b := body.global_transform.basis.orthonormalized()
	var l := b.inverse() * alpha
	var i := body.inertia
	if i == Vector3.ZERO:
		i = Vector3.ONE * body.mass * 0.01
	return b * Vector3(l.x * i.x, l.y * i.y, l.z * i.z) * scale

## The point-mass matrix of `body` at world point `p` (how the point's velocity answers an
## impulse there: dv = K * J), from its mass and its inertia: what a constraint solver uses.
static func point_k(body: RigidBody3D, p: Vector3) -> Basis:
	var r := p - body.global_transform * body.center_of_mass
	var i := body.inertia
	if i == Vector3.ZERO:
		i = Vector3.ONE * body.mass * 0.01
	var rb := body.global_transform.basis.orthonormalized()
	var i_inv := rb * Basis.from_scale(Vector3(1.0 / i.x, 1.0 / i.y, 1.0 / i.z)) * rb.transposed()
	var x := Basis(Vector3(0, r.z, -r.y), Vector3(-r.z, 0, r.x), Vector3(r.y, -r.x, 0))
	var rot := x * i_inv * x
	var im := 1.0 / maxf(1e-4, body.mass)
	return Basis(Vector3(im, 0, 0) - rot.x, Vector3(0, im, 0) - rot.y, Vector3(0, 0, im) - rot.z)

## Adds two point-mass matrices.
static func k_add(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)

static func inertia_of(body: RigidBody3D) -> float:
	var i := body.inertia
	return maxf(1e-4, (i.x + i.y + i.z) / 3.0)

static func quat_of(body: Node3D) -> Quaternion:
	return body.global_transform.basis.orthonormalized().get_rotation_quaternion()

## A rotation from a basis given by its x, y and z axes.
static func quat_from_axes(x: Vector3, y: Vector3, z: Vector3) -> Quaternion:
	return Basis(x, y, z).orthonormalized().get_rotation_quaternion()

static func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
