// The limbs' PD drives in C++ (Fighter.motor_rel, pd_relative, pd_axis, pd_twist and PD's helpers):
// the same results as the GDScript, bit for bit. GDScript keeps its scalars in double and its
// vectors in float, and a vector times a scalar takes the scalar as a float: each line below
// does what the script's line does, in the same types and order. The engine's own Vector3
// normalize (with its guard for numbers that are not finite) stands in for godot-cpp's.

#include "voxel_core.h"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <cmath>

using namespace godot;

namespace {

Vector3 eng_normalized(Vector3 v) {
	if (!v.is_finite()) {
		return Vector3();
	}
	real_t l = v.length_squared();
	if (l == 0) {
		return Vector3();
	}
	l = Math::sqrt(l);
	v.x /= l;
	v.y /= l;
	v.z /= l;
	return v;
}

Basis eng_orthonormalized(const Basis &b) {
	Vector3 x = b.get_column(0);
	Vector3 y = b.get_column(1);
	Vector3 z = b.get_column(2);
	x = eng_normalized(x);
	y = (y - x * (x.dot(y)));
	y = eng_normalized(y);
	z = (z - x * (x.dot(z)) - y * (y.dot(z)));
	z = eng_normalized(z);
	Basis c = b;
	c.set_column(0, x);
	c.set_column(1, y);
	c.set_column(2, z);
	return c;
}

// Basis.get_rotation_quaternion().
Quaternion eng_rotation_quaternion(const Basis &b) {
	Basis m = eng_orthonormalized(b);
	real_t det = m.determinant();
	if (det < 0) {
		m.scale(Vector3(-1, -1, -1));
	}
	return m.get_quaternion();
}

// PD.quat_of: body.global_transform.basis.orthonormalized().get_rotation_quaternion()
Quaternion pd_quat_of(Node3D *body) {
	return eng_rotation_quaternion(eng_orthonormalized(body->get_global_transform().basis));
}

// PD.rot_error
Vector3 pd_rot_error(const Quaternion &to, const Quaternion &from) {
	Quaternion q = (to * from.inverse()).normalized();
	if ((double)q.w < 0.0) {
		q = Quaternion(-q.x, -q.y, -q.z, -q.w);
	}
	const double w = q.w;
	const double s = std::sqrt(std::fmax(1e-9, 1.0 - w * w));
	const double angle = 2.0 * std::acos(std::fmin(1.0, w));
	return Vector3((real_t)((double)q.x / s * angle), (real_t)((double)q.y / s * angle), (real_t)((double)q.z / s * angle));
}

// PD.dir_error
Vector3 pd_dir_error(const Vector3 &cur, const Vector3 &des) {
	const Vector3 c = cur.cross(des);
	const double sn = c.length();
	if (sn < 1e-6) {
		return Vector3();
	}
	return c * (real_t)(std::atan2(sn, (double)cur.dot(des)) / sn);
}

// PD.clamp_len
Vector3 pd_clamp_len(const Vector3 &v, double mx) {
	const double l = v.length();
	return (l > mx && l > 0.0) ? v * (real_t)(mx / l) : v;
}

// PD.torque_for
Vector3 pd_torque_for(RigidBody3D *body, const Vector3 &alpha, double scale) {
	const Basis b = eng_orthonormalized(body->get_global_transform().basis);
	const Vector3 l = b.inverse().xform(alpha);
	Vector3 i = body->get_inertia();
	if (i == Vector3()) {
		i = Vector3(1, 1, 1) * (real_t)body->get_mass() * (real_t)0.01;
	}
	const Vector3 v((real_t)((double)l.x * (double)i.x), (real_t)((double)l.y * (double)i.y), (real_t)((double)l.z * (double)i.z));
	return b.xform(v) * (real_t)scale;
}

// PD.inertia_of
double pd_inertia_of(RigidBody3D *body) {
	const Vector3 i = body->get_inertia();
	return std::fmax(1e-4, ((double)i.x + (double)i.y + (double)i.z) / 3.0);
}

} // namespace

Quaternion VoxelCore::quat_of(Node3D *body) const {
	return body ? pd_quat_of(body) : Quaternion();
}

Vector3 VoxelCore::rot_error(const Quaternion &to, const Quaternion &from) const {
	return pd_rot_error(to, from);
}

Vector3 VoxelCore::dir_error(const Vector3 &cur, const Vector3 &des) const {
	return pd_dir_error(cur, des);
}

Vector3 VoxelCore::clamp_len(const Vector3 &v, double mx) const {
	return pd_clamp_len(v, mx);
}

Vector3 VoxelCore::torque_for(RigidBody3D *body, const Vector3 &alpha, double scale) const {
	return body ? pd_torque_for(body, alpha, scale) : Vector3();
}

void VoxelCore::motor_rel(RigidBody3D *part, RigidBody3D *parent, const Quaternion &rel_q, double wn, double max_t, double dt, double react) const {
	if (part == nullptr || parent == nullptr) {
		return;
	}
	const Quaternion desired = pd_quat_of(parent) * rel_q;
	const Vector3 err = pd_rot_error(desired, pd_quat_of(part));
	const Vector3 rel = part->get_angular_velocity() - parent->get_angular_velocity();
	const Vector3 v_des = pd_clamp_len(err * (real_t)wn, 16.0);
	Vector3 tq = pd_torque_for(part, (v_des - rel) / (real_t)dt, 1.0) * (real_t)0.6;
	tq = pd_clamp_len(tq, max_t);
	part->apply_torque_impulse(tq * (real_t)dt);
	parent->apply_torque_impulse(-tq * (real_t)dt * (real_t)react);
}

void VoxelCore::pd_relative(RigidBody3D *part, RigidBody3D *parent, const Quaternion &rel_q, double wn, double zeta, double max_t, double dt, double boost, double react) const {
	if (part == nullptr || parent == nullptr) {
		return;
	}
	const double ic = pd_inertia_of(part);
	const double ip = pd_inertia_of(parent);
	const Quaternion desired = pd_quat_of(parent) * rel_q;
	const Vector3 err = pd_rot_error(desired, pd_quat_of(part));
	const Vector3 rel = part->get_angular_velocity() - parent->get_angular_velocity();
	Vector3 tq = pd_torque_for(part, err * (real_t)(wn * wn) - rel * (real_t)(2.0 * zeta * wn), boost * ip / (ic + ip));
	tq = pd_clamp_len(tq, max_t);
	part->apply_torque_impulse(tq * (real_t)dt);
	parent->apply_torque_impulse(-tq * (real_t)dt * (real_t)react);
}

void VoxelCore::pd_axis(RigidBody3D *part, const Vector3 &local_axis, const Vector3 &des, double wn, double zeta, double max_t, double dt, double scale, const Vector3 &w_des) const {
	if (part == nullptr) {
		return;
	}
	const double kp = wn * wn;
	const double kd = 2.0 * zeta * wn;
	const Vector3 cur = pd_quat_of(part).xform(local_axis);
	const Vector3 err = pd_dir_error(cur, eng_normalized(des));
	const Vector3 alpha = err * (real_t)kp - (part->get_angular_velocity() - w_des) * (real_t)kd;
	Vector3 tq;
	if (scale != 1.0) {
		const Vector3 tw = cur * (real_t)(double)alpha.dot(cur);
		tq = pd_torque_for(part, alpha - tw, scale) + pd_torque_for(part, tw, 1.0);
	} else {
		tq = pd_torque_for(part, alpha, 1.0);
	}
	part->apply_torque_impulse(pd_clamp_len(tq, max_t) * (real_t)dt);
}

void VoxelCore::pd_twist(RigidBody3D *part, RigidBody3D *ref, double kp, double kd, double max_t, double dt) const {
	if (part == nullptr || ref == nullptr) {
		return;
	}
	const Quaternion q = pd_quat_of(part);
	const Vector3 axis = q.xform(Vector3(0, -1, 0));
	const Quaternion rq = pd_quat_of(ref);
	Vector3 f = q.xform(Vector3(0, 0, 1));
	f -= axis * (real_t)(double)axis.dot(f);
	Vector3 rf = rq.xform(Vector3(0, 0, 1));
	rf -= axis * (real_t)(double)axis.dot(rf);
	if ((double)f.length_squared() < 1e-6 || (double)rf.length_squared() < 1e-6) {
		return;
	}
	f = eng_normalized(f);
	rf = eng_normalized(rf);
	const double ang = std::atan2((double)f.cross(rf).dot(axis), (double)f.dot(rf));
	const double spin = (part->get_angular_velocity() - ref->get_angular_velocity()).dot(axis);
	double t = kp * ang - kd * spin;
	t = t < -max_t ? -max_t : (t > max_t ? max_t : t);
	part->apply_torque_impulse(axis * (real_t)t * (real_t)dt);
}
