// A man's arms kept out of his trunk as it is drawn (Fighter._out_of_trunk, _elbow_off_trunk,
// _hand_off_trunk): the same results as the GDScript, bit for bit. Asked a dozen times an arm
// every step of a fight, in the script they were a tenth of the step. As in drive.cpp, each line
// does what the script's line does, in the same types and order: scalars in double, vectors in
// float, a vector times a scalar taking the scalar as a float.

#include "voxel_core.h"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cmath>

using namespace godot;

namespace {

const double GD_PI = 3.1415926535897932384626433833;
const double GD_TAU = 6.2831853071795864769252867666;

// The trunk's outline (Fighter._outline): how far out it is drawn, by fine row and way round.
struct Sculpt {
	PackedFloat32Array prof;
	const float *pf = nullptr;
	int64_t na = 0;
	int64_t r1i = 0;
	double ylo = 0, fsz = 1, r0 = 0, r1 = 0, y0 = 0, y1 = 0;
	bool ok = false;
};

Sculpt read_sculpt(const Dictionary &o) {
	static const StringName k_prof("prof"), k_na("na"), k_ylo("ylo"), k_fsz("fsz"), k_r0("r0"), k_r1("r1"), k_y0("y0"), k_y1("y1");
	Sculpt s;
	s.prof = o[k_prof];
	s.pf = s.prof.ptr();
	s.na = o[k_na];
	s.ylo = o[k_ylo];
	s.fsz = o[k_fsz];
	s.r0 = (double)(int64_t)o[k_r0];
	s.r1i = o[k_r1];
	s.r1 = (double)s.r1i;
	s.y0 = o[k_y0];
	s.y1 = o[k_y1];
	s.ok = s.pf != nullptr && s.na > 0 && (s.r1i + 1) * s.na <= s.prof.size() && s.r0 >= 0.0;
	return s;
}

// Vector3.normalized() as the engine has it.
Vector3 sc_normalized(Vector3 v) {
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

// Fighter._sculpt_r
double sculpt_r(const Sculpt &s, double y, double ang) {
	double fr = (y - s.ylo) / s.fsz - 0.5;
	fr = fr < s.r0 ? s.r0 : (fr > s.r1 ? s.r1 : fr);
	const int64_t r0 = (int64_t)fr;
	const int64_t r1 = (r0 + 1) < s.r1i ? (r0 + 1) : s.r1i;
	const double wr = fr - (double)r0;
	const double fa = (ang + GD_PI) / GD_TAU * (double)s.na - 0.5;
	const double a0f = std::floor(fa);
	const double wa = fa - a0f;
	int64_t a0 = (int64_t)a0f % s.na;
	if (a0 < 0) {
		a0 += s.na;
	}
	const int64_t a1 = (a0 + 1) % s.na;
	const double p00 = s.pf[r0 * s.na + a0];
	const double p01 = s.pf[r0 * s.na + a1];
	const double p10 = s.pf[r1 * s.na + a0];
	const double p11 = s.pf[r1 * s.na + a1];
	const double low = p00 + (p01 - p00) * wa;
	const double high = p10 + (p11 - p10) * wa;
	return low + (high - low) * wr;
}

// Fighter._out_of_trunk
Vector3 out_of_trunk(const Sculpt &s, const Vector3 &l, double r) {
	if ((double)l.y < s.y0 - r || (double)l.y > s.y1 + r) {
		return Vector3();
	}
	const real_t d = Math::sqrt(l.x * l.x + l.z * l.z);
	const double pen = sculpt_r(s, (double)l.y, std::atan2((double)l.z, (double)l.x)) + r - (double)d;
	if (pen <= 0.0) {
		return Vector3();
	}
	const Vector3 out = (double)d > 1e-4 ? Vector3(l.x, 0.0f, l.z) / d : Vector3(0, 0, 1);
	return out * (real_t)pen;
}

// Fighter._plate_pad, of the band Fighter._plate_band gives.
inline double plate_pad(double y, double lo, double hi, double pad) {
	return (y < lo || y > hi) ? 0.0 : pad;
}

} // namespace

Vector3 VoxelCore::sculpt_out(const Dictionary &o, const Vector3 &l, double limb_r, double band_lo, double band_hi, double band_pad) const {
	const Sculpt s = read_sculpt(o);
	if (!s.ok) {
		return Vector3();
	}
	return out_of_trunk(s, l, limb_r + plate_pad((double)l.y, band_lo, band_hi, band_pad));
}

Vector3 VoxelCore::sculpt_elbow(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &shoulder_w, const Vector3 &e_dir, double lu, double r_half, double r_three, double r_whole, double band_lo, double band_hi, double band_pad) const {
	const Sculpt s = read_sculpt(o);
	if (!s.ok) {
		return e_dir;
	}
	const double ts[3] = { 0.5, 0.75, 1.0 };
	const double rs[3] = { r_half, r_three, r_whole };
	Vector3 d = e_dir;
	for (int i = 0; i < 3; i++) {
		Vector3 move;
		for (int k = 0; k < 3; k++) {
			const double t = ts[k];
			const Vector3 l = bi.xform(shoulder_w + d * (real_t)(lu * t));
			const Vector3 push = out_of_trunk(s, l, rs[k] + plate_pad((double)l.y, band_lo, band_hi, band_pad)) / (real_t)t;
			if (push.length_squared() > move.length_squared()) {
				move = push;
			}
		}
		if (move == Vector3()) {
			break;
		}
		const Vector3 nd = d * (real_t)lu + bt.basis.xform(move);
		if ((double)nd.length_squared() < 1e-8) {
			break;
		}
		d = sc_normalized(nd);
	}
	return d;
}

Vector3 VoxelCore::sculpt_hand(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &from, const Vector3 &goal, double size, const PackedFloat64Array &marks, double band_lo, double band_hi, double band_pad) const {
	const Sculpt s = read_sculpt(o);
	if (!s.ok) {
		return goal;
	}
	const int64_t n = marks.size() / 2;
	const double *mk = marks.ptr();
	Vector3 g = goal;
	for (int i = 0; i < 3; i++) {
		const double span = (g - from).length();
		if (span < 0.05 * size) {
			break;
		}
		const Vector3 dirv = (g - from) / (real_t)span;
		Vector3 move;
		for (int64_t k = 0; k < n; k++) {
			const double dist = mk[k * 2] < span ? mk[k * 2] : span;
			const Vector3 l = bi.xform(from + dirv * (real_t)dist);
			const Vector3 push = out_of_trunk(s, l, mk[k * 2 + 1] + plate_pad((double)l.y, band_lo, band_hi, band_pad)) * (real_t)(span / dist);
			if (push.length_squared() > move.length_squared()) {
				move = push;
			}
		}
		if (move == Vector3()) {
			break;
		}
		g += bt.basis.xform(move);
	}
	return g;
}
