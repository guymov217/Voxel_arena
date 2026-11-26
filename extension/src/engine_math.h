#pragma once
// The engine's own Vector3 / Basis maths as the 4.7 engine does it (as the scripts' floats come out of it), shared by
// the natives that stand in for scripts: drive.cpp (the PD drives) and arm.cpp (the arms kept out of the body). GDScript
// keeps its scalars in double and its vectors in float; a vector times a scalar takes the scalar as a float.

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

namespace vc {

using namespace godot;

// GDScript's maxf / minf are the engine's MAX / MIN macros: the first argument is kept when they tie (or compare false).
inline double gd_maxf(double a, double b) { return a > b ? a : b; }
inline double gd_minf(double a, double b) { return a < b ? a : b; }

inline Vector3 eng_normalized(Vector3 v) {
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

inline Basis eng_orthonormalized(const Basis &b) {
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
inline Quaternion eng_rotation_quaternion(const Basis &b) {
	Basis m = eng_orthonormalized(b);
	real_t det = m.determinant();
	if (det < 0) {
		m.scale(Vector3(-1, -1, -1));
	}
	return m.get_quaternion();
}

// Quaternion(arc_from, arc_to), the shortest turn from one to the other, by the running engine's own constructor: this library's copy of it (godot-cpp's, a 4.4 one)
// is another version's and comes out a bit off in a few cases of a hundred.
inline Quaternion eng_quat_arc(const Vector3 &from, const Vector3 &to) {
	static const GDExtensionPtrConstructor make = internal::gdextension_interface_variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_QUATERNION, 4);
	Quaternion q;
	const GDExtensionConstTypePtr args[2] = { &from, &to };
	make(&q, args);
	return q;
}

// PD.quat_of: body.global_transform.basis.orthonormalized().get_rotation_quaternion()
inline Quaternion pd_quat_of(Node3D *body) {
	return eng_rotation_quaternion(eng_orthonormalized(body->get_global_transform().basis));
}

} // namespace vc
