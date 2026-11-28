// The drawn turns of the two arms of a man with both hands on one weapon (Fighter._off_clear_drawing, and the guard arm's _swivel_drawing): searches over a few turns of an arm about the line
// from its shoulder to its fist, each scored by how deep the arm lies in his chest and in the other arm. Drawing only, nothing here is read back by the physics; as the script works them out, in
// the engine's own floats (docs/PERF_RESEARCH.md, section 31).

#include "voxel_core.h"

#include "engine_math.h"

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

using namespace godot;
using namespace vc;

namespace {

// Geometry3D.get_closest_points_between_segments as the engine has it (core/math/geometry_3d.h, David Eberly's way of it; the engine's floats).
void da_closest(const Vector3 &p0, const Vector3 &p1, const Vector3 &q0, const Vector3 &q1, Vector3 &ps, Vector3 &qt) {
	const Vector3 p = p1 - p0;
	const Vector3 q = q1 - q0;
	const Vector3 r = p0 - q0;
	const real_t a = p.dot(p);
	const real_t b = p.dot(q);
	const real_t c = q.dot(q);
	const real_t d = p.dot(r);
	const real_t e = q.dot(r);
	real_t s = 0.0f;
	real_t t = 0.0f;
	const real_t det = a * c - b * b;
	if (det > (real_t)0.00001) {
		// Non-parallel segments.
		const real_t bte = b * e;
		const real_t ctd = c * d;
		if (bte <= ctd) {
			// s <= 0
			if (e <= 0.0f) {
				// t <= 0
				s = (-d >= a ? 1 : (-d > 0.0f ? -d / a : 0.0f));
				t = 0.0f;
			} else if (e < c) {
				// 0 < t < 1
				s = 0.0f;
				t = e / c;
			} else {
				// t >= 1
				s = (b - d >= a ? 1 : (b - d > 0.0f ? (b - d) / a : 0.0f));
				t = 1;
			}
		} else {
			// s > 0
			s = bte - ctd;
			if (s >= det) {
				// s >= 1
				if (b + e <= 0.0f) {
					// t <= 0
					s = (-d <= 0.0f ? 0.0f : (-d < a ? -d / a : 1));
					t = 0.0f;
				} else if (b + e < c) {
					// 0 < t < 1
					s = 1;
					t = (b + e) / c;
				} else {
					// t >= 1
					s = (b - d <= 0.0f ? 0.0f : (b - d < a ? (b - d) / a : 1));
					t = 1;
				}
			} else {
				// 0 < s < 1
				const real_t ate = a * e;
				const real_t btd = b * d;
				if (ate <= btd) {
					// t <= 0
					s = (-d <= 0.0f ? 0.0f : (-d >= a ? 1 : -d / a));
					t = 0.0f;
				} else {
					// t > 0
					t = ate - btd;
					if (t >= det) {
						// t >= 1
						s = (b - d <= 0.0f ? 0.0f : (b - d >= a ? 1 : (b - d) / a));
						t = 1;
					} else {
						// 0 < t < 1
						s /= det;
						t /= det;
					}
				}
			}
		}
	} else {
		// Parallel segments.
		if (e <= 0.0f) {
			s = (-d <= 0.0f ? 0.0f : (-d >= a ? 1 : -d / a));
			t = 0.0f;
		} else if (e >= c) {
			s = (b - d <= 0.0f ? 0.0f : (b - d >= a ? 1 : (b - d) / a));
			t = 1;
		} else {
			s = 0.0f;
			t = e / c;
		}
	}
	ps = p0 * (1 - s) + p1 * s;
	qt = q0 * (1 - t) + q1 * t;
}

// Fighter._arms_sunk: how far an arm drawn with its shoulder, elbow and fist at s, e, h lies sunk in the arm `other` ([shoulder, elbow, fist], or none): the two forearms and each forearm against
// the other's upper arm, as far as their middle lines are nearer than two arms' thickness lets them be. The wrists are left out (`wrist` of a forearm from its elbow).
double da_arms_sunk(const Vector3 &s, const Vector3 &e, const Vector3 &h, const Vector3 *other, double S, double room_k, double wrist) {
	if (other == nullptr) {
		return 0.0;
	}
	const Vector3 os = other[0];
	const Vector3 oe = other[1];
	const Vector3 ow = oe.lerp(other[2], (real_t)wrist);
	const Vector3 w = e.lerp(h, (real_t)wrist);
	const double room = room_k * S;
	double sunk = 0.0;
	const Vector3 pairs[3][4] = { { e, w, oe, ow }, { e, w, os, oe }, { s, e, oe, ow } };
	for (int i = 0; i < 3; i++) {
		Vector3 c1, c2;
		da_closest(pairs[i][0], pairs[i][1], pairs[i][2], pairs[i][3], c1, c2);
		sunk += gd_maxf(0.0, room - (double)c1.distance_to(c2));
	}
	return sunk;
}

// GDScript's wrapf (the 4.7.2 engine's, in doubles) and angle_difference.
double da_wrapf(double value, double min, double max) {
	const double range = max - min;
	if (std::fabs(range) < 0.00001) {
		return min;
	}
	const double result = value - (range * std::floor((value - min) / range));
	if (result == max) {
		return min;
	}
	double tolerance = 0.00001 * std::fabs(result);
	if (tolerance < 0.00001) {
		tolerance = 0.00001;
	}
	return std::fabs(result - max) < tolerance ? min : result;
}

double da_angle_difference(double from, double to) {
	const double difference = std::fmod(to - from, 6.2831853071795864769252867666);
	return std::fmod(2.0 * difference, 6.2831853071795864769252867666) - difference;
}

double da_clampf(double x, double lo, double hi) {
	return x < lo ? lo : (x > hi ? hi : x);
}

} // namespace

// The two bodies' places the other segments' closest points have (as the engine's Geometry3D answers them: for the test that holds this port to it).
PackedVector3Array VoxelCore::segments_closest(const Vector3 &p0, const Vector3 &p1, const Vector3 &q0, const Vector3 &q1) const {
	Vector3 a, b;
	da_closest(p0, p1, q0, q1, a, b);
	PackedVector3Array out;
	out.push_back(a);
	out.push_back(b);
	return out;
}

// Fighter._off_clear_drawing's search. With both hands on one haft the other hand's arm is drawn turned about the line from its shoulder to its fist, as far as keeps its forearm and its elbow out
// of his chest and the guard arm: the least turn that does it, kept unless another is better by more than a little, never one that stands the elbow up over his shoulder or lays the arm across his face.
// `tu`, `tf`, `tt` the upper arm's, the forearm's and the trunk's places as they are drawn (shifted), `up_ca` the shoulder in the upper arm's frame, `fo_pa` the elbow in the forearm's, `head_at` where his head is
// (`k[9]` 0: he has none: a place above the shoulder instead), `guard` the guard arm as it is drawn ([shoulder, elbow, fist], or none), `up_shift`, `fo_shift` the two parts' seats' shifts; `k`: S, the turn it has,
// dt, and the script's constants (OFF_CLEAR, OFF_STAY, ARMS_DEPTH, ARMS_ROOM, ARMS_WRIST, SWIVEL_FACE), head 0/1.
// Returns [the turn it has now] and, where it is turned (not under 0.001), the two parts' drawn turns after it.
Array VoxelCore::off_clear(const Transform3D &tu, const Transform3D &tf, const Transform3D &tt, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_at,
		const PackedVector3Array &guard, const Vector3 &up_shift, const Vector3 &fo_shift, const PackedFloat64Array &k) const {
	Array out;
	if (k.size() < 10) {
		out.append(0.0);
		return out;
	}
	const double S = k[0];
	double off_turn_a = k[1];
	const double dt = k[2];
	const double off_clear = k[3];
	const double off_stay = k[4];
	const double arms_depth = k[5];
	const double arms_room = k[6];
	const double arms_wrist = k[7];
	const double swivel_face = k[8];
	const Vector3 s0 = tu.xform(up_ca);
	const Vector3 e0 = tu.xform(fo_pa);
	const Vector3 h0 = tf.xform(hand_point);
	const Vector3 v = h0 - s0;
	double want = 0.0;
	if (!((double)v.length() > 0.05 * S)) {
		out.append(0.0);
		return out;
	}
	const Vector3 a = eng_normalized(v);
	const Vector3 u = e0 - s0;
	const Transform3D tinv = tt.affine_inverse();
	const Vector3 ext = torso_half + Vector3(1, 1, 1) * (real_t)off_clear * (real_t)S;
	const Vector3 hd = k[9] != 0.0 ? head_at : s0 + Vector3(0, (real_t)(0.3 * S), 0);
	const Vector3 *other = guard.size() >= 3 ? guard.ptr() : nullptr;
	const Vector3 up_b = eng_normalized(tt.basis.get_column(1));
	// How deep the arm lies in him turned by c: the forearm, and the upper arm's lower half; and how far into the guard arm.
	auto depth = [&](double c) -> double {
		const Vector3 e1 = s0 + Basis(a, (real_t)c).xform(u);
		double dsum = arms_depth * da_arms_sunk(s0, e1, h0, other, S, arms_room, arms_wrist);
		for (int i = 0; i < 5; i++) {
			const double t = ((double)i + 0.5) / 5.0;
			const Vector3 qs[2] = { e1.lerp(h0, (real_t)t), s0.lerp(e1, (real_t)(0.5 + 0.5 * t)) };
			for (int j = 0; j < 2; j++) {
				const Vector3 l = tinv.xform(qs[j]);
				const double dx = (double)ext.x - std::fabs((double)l.x);
				const double dy = (double)ext.y - std::fabs((double)l.y);
				const double dz = (double)ext.z - std::fabs((double)l.z);
				if (dx > 0.0 && dy > 0.0 && dz > 0.0) {
					dsum += gd_minf(dx, gd_minf(dy, dz));
				}
			}
		}
		// (Never up over his shoulder or across his face, whatever else it would clear.)
		if (c != 0.0 && ((double)(e1 - s0).dot(up_b) > 0.08 * S || gd_minf((double)e1.distance_to(hd), (double)((e1 + h0) * (real_t)0.5).distance_to(hd)) < swivel_face * S)) {
			dsum += 100.0;
		}
		return dsum;
	};
	const double stay = dt > 0.0 ? off_stay : 0.0;
	double best = depth(0.0) + stay * std::fabs(off_turn_a);
	if (best > 0.0) {
		bool shut[2] = { false, false };
		bool found = false;
		const double mags[5] = { 0.25, 0.5, 0.75, 1.0, 1.3 };
		for (int m = 0; m < 5; m++) {
			for (int i = 0; i < 2; i++) {
				if (shut[i] || found) {
					continue;
				}
				const double c = i == 0 ? mags[m] : -mags[m];
				double dd = depth(c);
				if (dd >= 100.0) {
					shut[i] = true;
					continue;
				}
				dd += stay * std::fabs(c - off_turn_a);
				if (dd < best - 1e-4) {
					best = dd;
					want = c;
					found = dd <= 0.0;
				}
			}
		}
	}
	off_turn_a = dt <= 0.0 ? want : Math::lerp_angle(off_turn_a, want, gd_minf(1.0, dt * 12.0));
	out.append(off_turn_a);
	if (std::fabs(off_turn_a) < 0.001) {
		return out;
	}
	const Basis turn(a, (real_t)off_turn_a);
	for (int i = 0; i < 2; i++) {
		const Vector3 q2 = s0 - (i == 0 ? up_shift : fo_shift);
		// (The part's own drawn turn is none: the script lets go of an arm that has one before it asks.)
		out.append(Transform3D(Basis(), q2) * Transform3D(turn, Vector3()) * Transform3D(Basis(), -q2) * Transform3D());
	}
	return out;
}

// Fighter._swivel_drawing's search. With both hands on one haft the guard hand's arm is drawn turned about the line from its shoulder to its fist, as far as stands the forearm SWIVEL_BEND off the
// blade's line, the fist where it is and the elbow down and out to its own side: the candidate turns (the two that bend the wrist so, and none), each scored (the elbow low and out, not into his chest,
// up over his shoulder or across his face, clear of the other arm, near the elbow as it was drawn last), the best eased to over the frames. `tu`, `tf` the upper arm's and the forearm's places as drawn
// (shifted), `tw` the weapon's, `torso_xf` the trunk's own (not shifted), `other` the other arm as it is drawn ([shoulder, elbow, fist], or none), `swivel_e` the elbow as last drawn from the shoulder (or
// nothing); `k`: S, the turn it has, dt, whether he holds a weapon in both hands (`ok`), the side's sign (-1 the right), whether he has a head, and the script's constants (SWIVEL_BEND, NONE, FACE, ARMS, STICK,
// RATE; ARMS_ROOM, ARMS_WRIST). Returns [the turn it has now, the elbow as it is drawn now (or nothing)] and, where it is turned (not under 0.001), the two parts' drawn turns after it.
Array VoxelCore::swivel(const Transform3D &tu, const Transform3D &tf, const Transform3D &tw, const Transform3D &torso_xf, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &hand_point, const Vector3 &torso_half,
		const Vector3 &head_at, const PackedVector3Array &other_arm, const Vector3 &up_shift, const Vector3 &fo_shift, const Variant &swivel_e_in, const PackedFloat64Array &k) const {
	Array out;
	if (k.size() < 14) {
		out.append(0.0);
		out.append(Variant());
		return out;
	}
	const double S = k[0];
	double swivel_a = k[1];
	const double dt = k[2];
	const bool ok = k[3] != 0.0;
	const double side_sign = k[4];
	const bool has_head = k[5] != 0.0;
	const double swivel_bend = k[6];
	const double swivel_none = k[7];
	const double swivel_face = k[8];
	const double swivel_arms = k[9];
	const double swivel_stick = k[10];
	const double swivel_rate = k[11];
	const double arms_room = k[12];
	const double arms_wrist = k[13];
	const double PI_ = 3.1415926535897932384626433833;
	const Vector3 s0 = tu.xform(up_ca);
	const Vector3 e0 = tu.xform(fo_pa);
	const Vector3 h0 = tf.xform(hand_point);
	const Vector3 v = h0 - s0;
	const Vector3 u = e0 - s0;
	const bool long_enough = (double)v.length() > 0.05 * S;
	double want = 0.0;
	if (ok && long_enough) {
		const Vector3 a = eng_normalized(v);
		const Vector3 u_perp = u - a * u.dot(a);
		const Vector3 b = eng_normalized(tw.basis.xform(Vector3(0, 1, 0)));
		const double l2 = (double)(h0 - e0).length();
		// The forearm turned by p about the line: its cosine to the blade is (A - B cos p - C sin p) / l2.
		const double big_a = (double)(v - a * u.dot(a)).dot(b);
		const double big_b = (double)u_perp.dot(b);
		const double big_c = (double)a.cross(u_perp).dot(b);
		const double r = std::sqrt(big_b * big_b + big_c * big_c);
		if ((double)u_perp.length() > 0.01 * S && r > 1e-5 && l2 > 1e-4) {
			const double psi = std::atan2(big_c, big_b);
			const double kk = big_a - l2 * std::cos(swivel_bend);
			double cands[3];
			int n = 0;
			if (kk < r) {
				const double d = std::acos(da_clampf(kk / r, -1.0, 1.0));
				cands[n++] = psi + d;
				cands[n++] = psi - d;
			} else {
				cands[n++] = psi;
			}
			cands[n++] = 0.0;
			const Vector3 out_x = eng_normalized(torso_xf.basis.get_column(0)) * (real_t)side_sign;
			const Transform3D tinv = torso_xf.affine_inverse();
			const Vector3 hd = has_head ? head_at : s0 + Vector3(0, (real_t)(0.3 * S), 0);
			const Vector3 *other = other_arm.size() >= 3 ? other_arm.ptr() : nullptr;
			const Vector3 torso_up = eng_normalized(torso_xf.basis.get_column(1));
			const bool stick = swivel_e_in.get_type() == Variant::VECTOR3 && dt > 0.0;
			const Vector3 swivel_e = stick ? (Vector3)swivel_e_in : Vector3();
			double best = -INFINITY;
			for (int i = 0; i < n; i++) {
				const double c = cands[i];
				const Vector3 e1 = s0 + Basis(a, (real_t)c).xform(u);
				double sc = -(double)e1.y + 0.5 * (double)(e1 - s0).dot(out_x) - swivel_arms * da_arms_sunk(s0, e1, h0, other, S, arms_room, arms_wrist) / S;
				if (c == 0.0) {
					sc -= swivel_none;
				} else {
					const Vector3 le = tinv.xform(e1);
					if (std::fabs((double)le.x) < (double)torso_half.x + 0.03 * S && std::fabs((double)le.y) < (double)torso_half.y && std::fabs((double)le.z) < (double)torso_half.z + 0.03 * S) {
						sc -= 10.0;
					}
					if ((double)(e1 - s0).dot(torso_up) > 0.08 * S) {
						sc -= 10.0;
					}
					const double near_face = gd_minf((double)e1.distance_to(hd), gd_minf((double)((s0 + e1) * (real_t)0.5).distance_to(hd), (double)((e1 + h0) * (real_t)0.5).distance_to(hd)));
					if (near_face < swivel_face * S) {
						sc -= 10.0;
					}
				}
				if (stick) {
					sc -= swivel_stick * (double)(e1 - s0).distance_to(swivel_e) / S;
				}
				if (sc > best) {
					best = sc;
					want = da_wrapf(c, -PI_, PI_);
				}
			}
		}
	}
	if (dt <= 0.0) {
		swivel_a = want;
	} else {
		const double step = da_angle_difference(swivel_a, want) * gd_minf(1.0, dt * 12.0);
		swivel_a = da_wrapf(swivel_a + da_clampf(step, -swivel_rate * dt, swivel_rate * dt), -PI_, PI_);
	}
	out.append(swivel_a);
	if (long_enough) {
		out.append(Basis(eng_normalized(v), (real_t)swivel_a).xform(u));
	} else {
		out.append(Variant());
	}
	if (std::fabs(swivel_a) < 0.001 || (double)v.length() < 0.05 * S) {
		return out;
	}
	const Basis turn(eng_normalized(v), (real_t)swivel_a);
	for (int i = 0; i < 2; i++) {
		const Vector3 q = s0 - (i == 0 ? up_shift : fo_shift);
		out.append(Transform3D(Basis(), q) * Transform3D(turn, Vector3()) * Transform3D(Basis(), -q) * Transform3D());
	}
	return out;
}
