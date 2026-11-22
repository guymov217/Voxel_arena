// A man's arms kept out of his own body, in C++ (Fighter._keep_arm_out, _keep_hand_front, _keep_elbow_low): the same
// impulses as the GDScript, bit for bit. They were a seventh of a man's step in a fight (#298): a dozen points an arm,
// each carried through the script's boxes and dictionaries. As in drive.cpp, each line does what the script's line does,
// in the same types and in the same order: scalars in double (so a vector's component taken into a sum is a double
// there), vectors in float, a vector times a scalar taking the scalar as a float. The bodies are the script's own
// (VoxelParts: RigidBody3Ds); what the script knows of them (their half extents, masses, whether they are severed...)
// comes in as arguments, and the impulses go to them in the order the script gives them.

#include "voxel_core.h"
#include "engine_math.h"
#include "sculpt_common.h"

#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

using namespace godot;
using namespace vc;

namespace {

// VoxelPart.velocity_at: linear_velocity + angular_velocity.cross(p - (global_position if center_of_mass == Vector3.ZERO
// else global_transform * center_of_mass))
Vector3 velocity_at(RigidBody3D *b, const Vector3 &p) {
	const Vector3 com = b->get_center_of_mass();
	const Vector3 c = (com == Vector3()) ? b->get_global_position() : b->get_global_transform().xform(com);
	return b->get_linear_velocity() + b->get_angular_velocity().cross(p - c);
}

struct Point {
	RigidBody3D *part;
	Vector3 pos;
	double y; // where along the part it is (its frame's y: how thick it is there)
	double r; // how thick the limb is drawn there (Fighter._limb_r)
	Vector3 seat; // how far it is drawn off its joint (Fighter._seat_drawing)
	bool is_up;
};

// Fighter._limb_r_now: how thick (a ball's radius) a limb is drawn at `y` along it, its plates on: the sculpt's own outline there, the
// mean of the ways round (0 where the part has no outline, a point as before).
struct Limb {
	PackedFloat32Array mean;
	const float *mf = nullptr;
	int64_t r1i = 0;
	double ylo = 0, fsz = 1, r0 = 0, r1 = 0;
	double plate = 0; // what its plates add (Fighter.LIMB_PLATE * fsz where it is armoured)
	bool on = false;
};

Limb read_limb(const Dictionary &o, bool armored, double limb_plate) {
	static const StringName k_mean("mean"), k_ylo("ylo"), k_fsz("fsz"), k_r0("r0"), k_r1("r1");
	Limb l;
	if (o.is_empty()) {
		return l;
	}
	l.mean = o[k_mean];
	l.mf = l.mean.ptr();
	l.ylo = o[k_ylo];
	l.fsz = o[k_fsz];
	l.r0 = (double)(int64_t)o[k_r0];
	l.r1i = o[k_r1];
	l.r1 = (double)l.r1i;
	l.plate = armored ? limb_plate * l.fsz : 0.0;
	l.on = l.mf != nullptr && l.r0 >= 0.0 && l.mean.size() > l.r1i;
	return l;
}

double limb_r(const Limb &l, double y) {
	if (!l.on) {
		return 0.0;
	}
	double fr = (y - l.ylo) / l.fsz - 0.5; // _sculpt_row
	fr = fr < l.r0 ? l.r0 : (fr > l.r1 ? l.r1 : fr);
	const int64_t r0 = (int64_t)fr;
	const int64_t r1 = (r0 + 1) < l.r1i ? (r0 + 1) : l.r1i;
	const double a = (double)l.mf[r0];
	const double b = (double)l.mf[r1];
	return (a + (b - a) * (fr - (double)r0)) + l.plate;
}

} // namespace

void VoxelCore::keep_arm_out(RigidBody3D *up, RigidBody3D *fo, RigidBody3D *torso, RigidBody3D *head, const Vector3 &up_half, const Vector3 &torso_half, const Vector3 &head_half, const Vector3 &hand_point, double out_x, double S, double dt, bool two_handed, bool fo_severed, bool torso_severed, bool head_severed, double up_mass, double fo_mass, double weapon_mass, double out_k, double upper_out, bool drawn_on, const Dictionary &sculpt, double band_lo, double band_hi, double band_pad, const Dictionary &o_up, bool armored_up, const Dictionary &o_fo, bool armored_fo, double limb_plate, bool up_joint, bool fo_joint, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca) const {
	if (up == nullptr || fo == nullptr || torso == nullptr || head == nullptr) {
		return;
	}
	const Transform3D up_t = up->get_global_transform();
	// How thick each limb is drawn where the points are (Fighter._limb_r), asked only where the trunk is drawn.
	Limb lup, lfo;
	if (drawn_on) {
		lup = read_limb(o_up, armored_up, limb_plate);
		lfo = read_limb(o_fo, armored_fo, limb_plate);
	}
	const double r_end = drawn_on ? limb_r(lup, (double)(-up_half.y)) : 0.0;
	const double r_mid = drawn_on && !two_handed ? limb_r(lup, 0.0) : 0.0;
	const double r_quarter = drawn_on && !two_handed ? limb_r(lup, -0.5 * (double)up_half.y) : 0.0;
	const double r_fo = drawn_on && !fo_severed ? limb_r(lfo, 0.0) : 0.0;
	const double r_hand = drawn_on && !fo_severed ? limb_r(lfo, (double)hand_point.y) : 0.0;
	Point pts[5];
	int n = 0;
	// [the part, the point, where along the part it is (its frame's y: how thick it is there)]
	pts[n++] = { up, up_t.xform(Vector3(0, -up_half.y, 0)), (double)(-up_half.y), r_end, Vector3(), true };
	// The middle of the upper arm too, but not with both hands on a haft (see the script).
	if (!two_handed) {
		pts[n++] = { up, up->get_global_position(), 0.0, r_mid, Vector3(), true };
		if (drawn_on) {
			pts[n++] = { up, up_t.xform(Vector3(0, (real_t)(-0.5 * (double)up_half.y), 0)), -0.5 * (double)up_half.y, r_quarter, Vector3(), true };
		}
	}
	if (!fo_severed) {
		pts[n++] = { fo, fo->get_global_position(), 0.0, r_fo, Vector3(), false };
		pts[n++] = { fo, fo->get_global_transform().xform(hand_point), (double)hand_point.y, r_hand, Vector3(), false };
	}
	// Each limb is drawn seated on its joint (_seat_drawing): by as much as the joint has given, toward the socket.
	Vector3 seat_up, seat_fo;
	if (drawn_on && up_joint) {
		seat_up = torso->get_global_transform().xform(up_pa) - up_t.xform(up_ca);
		if (fo_joint && !fo_severed) {
			seat_fo = seat_up + up_t.xform(fo_pa) - fo->get_global_transform().xform(fo_ca);
		}
	}
	for (int i = 0; i < n; i++) {
		pts[i].seat = pts[i].is_up ? seat_up : seat_fo;
	}
	Sculpt sc;
	if (drawn_on) {
		sc = read_sculpt(sculpt);
	}
	RigidBody3D *bodies[2] = { torso, head };
	const bool severed[2] = { torso_severed, head_severed };
	const Vector3 halves[2] = { torso_half, head_half };
	const double m_eff = (fo_severed ? 0.0 : fo_mass) + up_mass * 0.5 + weapon_mass;
	for (int bn = 0; bn < 2; bn++) {
		if (severed[bn]) {
			continue;
		}
		RigidBody3D *body = bodies[bn];
		const Transform3D bt = body->get_global_transform();
		const Transform3D bi = bt.affine_inverse();
		bool have_q = false;
		Quaternion bq;
		const Vector3 e = halves[bn] + Vector3(0.02, 0.0, 0.02) * (real_t)S;
		const bool drawn = bn == 0 && drawn_on;
		for (int i = 0; i < n; i++) {
			const Point &pp = pts[i];
			Vector3 l = bi.xform(pp.pos);
			Vector3 push;
			if (drawn) {
				// Out of the trunk as it is drawn, the limb as thick as it is drawn there (_outline).
				l = bi.xform(pp.pos + pp.seat);
				if (sc.ok) {
					push = out_of_trunk(sc, l, pp.r + plate_pad((double)l.y, band_lo, band_hi, band_pad));
				}
				if (push == Vector3()) {
					continue;
				}
			} else {
				if (std::fabs((double)l.x) >= (double)e.x || std::fabs((double)l.y) >= (double)e.y || std::fabs((double)l.z) >= (double)e.z) {
					continue;
				}
				const double front = (double)e.z - (double)l.z;
				const double aside = (double)e.x - (double)l.x * out_x;
				push = (front < aside || (double)l.z > 0.0) ? Vector3(0, 0, (real_t)front) : Vector3((real_t)(out_x * aside), 0, 0);
			}
			if (!have_q) {
				bq = pd_quat_of(body);
				have_q = true;
			}
			const Vector3 pn = eng_normalized(push);
			const double v_out = (double)bq.xform(pn).dot(velocity_at(pp.part, pp.pos) - velocity_at(body, pp.pos));
			const double k_out = out_k * (drawn && pp.is_up && pp.y > -0.75 * (double)up_half.y ? upper_out : 1.0);
			const double acc = (double)push.length() * k_out - gd_minf(0.0, v_out) * 2.0 * std::sqrt(k_out);
			const Vector3 jo = ((bq.xform(pn) * (real_t)acc) * (real_t)m_eff) * (real_t)dt;
			pp.part->apply_impulse(jo, pp.pos - pp.part->get_global_position());
			body->apply_central_impulse(-jo); // (the arm pushes off his own body, not off the air)
		}
	}
}

void VoxelCore::keep_hand_front(RigidBody3D *up, RigidBody3D *fo, RigidBody3D *torso, const Vector3 &up_half, const Vector3 &torso_half, const Vector3 &hand_point, double out_x, double S, double dt, bool fo_severed, double up_mass, double fo_mass, double side_weapon_mass, double haft_half_mass, double out_k) const {
	if (up == nullptr || fo == nullptr || torso == nullptr) {
		return;
	}
	const Transform3D bt = torso->get_global_transform();
	const Transform3D inv = bt.affine_inverse();
	const Quaternion bq = pd_quat_of(torso);
	const Vector3 e = torso_half;
	RigidBody3D *parts[2] = { up, fo };
	Vector3 pos[2] = { up->get_global_transform().xform(Vector3(0, -up_half.y, 0)), Vector3() };
	int n = 1;
	if (!fo_severed) {
		pos[n] = fo->get_global_transform().xform(hand_point);
		n++;
	}
	const double m_eff = (fo_severed ? 0.0 : fo_mass) + up_mass * 0.5 + side_weapon_mass + haft_half_mass;
	for (int i = 0; i < n; i++) {
		const Vector3 l = inv.xform(pos[i]);
		if ((double)l.z > -(double)e.z || std::fabs((double)l.x) > (double)e.x + 0.12 * S || (double)l.y < -(double)e.y - 0.1 * S || (double)l.y > (double)e.y + 0.25 * S) {
			continue;
		}
		// Out past the hip or the flank on the side it is on, and on forward.
		const double lx = (double)l.x;
		const double sx = std::fabs(lx) > 0.3 * (double)e.x ? (lx > 0.0 ? 1.0 : (lx < 0.0 ? -1.0 : 0.0)) : out_x;
		const Vector3 push = Vector3((real_t)(sx * gd_maxf(0.0, (double)e.x + 0.16 * S - lx * sx)), 0.0f, (real_t)gd_maxf(0.0, -0.3 * (double)e.z - (double)l.z));
		if ((double)push.length_squared() < 1e-8) {
			continue;
		}
		RigidBody3D *part = parts[i];
		const Vector3 dir = bq.xform(eng_normalized(push));
		const double v_out = (double)dir.dot(velocity_at(part, pos[i]) - velocity_at(torso, pos[i]));
		const double acc = gd_minf((double)push.length(), 0.3 * S) * out_k - gd_minf(0.0, v_out) * 2.0 * std::sqrt(out_k);
		const Vector3 jo = ((dir * (real_t)acc) * (real_t)m_eff) * (real_t)dt;
		part->apply_impulse(jo, pos[i] - part->get_global_position());
		torso->apply_central_impulse(-jo);
	}
}

void VoxelCore::keep_elbow_low(RigidBody3D *up, RigidBody3D *fo, RigidBody3D *torso, const Vector3 &up_pa, const Vector3 &fo_pa, const Vector3 &hand_point, bool right, double S, double dt, double up_mass, double fo_mass, double elbow_over, double elbow_over_hand, double elbow_soft, double low_k) const {
	if (up == nullptr || fo == nullptr || torso == nullptr) {
		return;
	}
	const Transform3D bt = torso->get_global_transform();
	const Vector3 up_b = eng_normalized(bt.basis.get_column(1));
	const Vector3 sh = bt.xform(up_pa);
	const Vector3 el = up->get_global_transform().xform(fo_pa);
	const Vector3 hd = fo->get_global_transform().xform(hand_point);
	const double over = (double)(el - sh).dot(up_b) - (gd_maxf(elbow_over * S, (double)(hd - sh).dot(up_b) + elbow_over_hand * S) - elbow_soft * S);
	if (over <= 0.0) {
		return;
	}
	Vector3 n = hd - sh;
	if ((double)n.length_squared() < 0.0025 * S * S) {
		return;
	}
	n = eng_normalized(n);
	// The circle's top, and the way round from it: out to the arm's own side, forward where the line itself runs out that way.
	Vector3 top = up_b - n * (real_t)(double)up_b.dot(n);
	const Vector3 r = (el - sh) - n * (real_t)(double)(el - sh).dot(n);
	if ((double)top.length_squared() < 0.0225 || (double)r.length_squared() < 0.0016 * S * S) {
		return;
	}
	top = eng_normalized(top);
	Vector3 way = n.cross(top);
	if ((double)way.dot(bt.basis.xform(Vector3(right ? -1.0 : 1.0, 0.0, 0.5))) < 0.0) {
		way = -way;
	}
	const Vector3 rh = eng_normalized(r);
	const Vector3 t = eng_normalized(way * (real_t)(double)rh.dot(top) - top * (real_t)(double)rh.dot(way));
	const double v_t = (double)t.dot(velocity_at(up, el) - velocity_at(torso, el));
	const double m_eff = (up_mass + fo_mass) * 0.5;
	const double acc = gd_minf(over, 0.25 * S) * low_k - gd_minf(0.0, v_t) * 2.0 * std::sqrt(low_k);
	const Vector3 j = ((t * (real_t)acc) * (real_t)m_eff) * (real_t)dt;
	up->apply_impulse(j, el - up->get_global_position());
	torso->apply_central_impulse(-j); // (the arm turns against his own body, not against the air)
}

Vector3 VoxelCore::clear_body(const Vector3 &target_in, const Quaternion &yaw_q, const Vector3 &t_pos, RigidBody3D *torso, RigidBody3D *head, const Vector3 &torso_half, const Vector3 &head_half, double S, bool torso_severed, bool head_severed, bool fo_severed, bool drawn_on, const Dictionary &sculpt, double band_lo, double band_hi, double band_pad, const Dictionary &o_fo, bool armored_fo, double limb_plate, double hand_y) const {
	Vector3 target = target_in;
	if (torso == nullptr || head == nullptr) {
		return target;
	}
	const Vector3 th = torso_half;
	const double tz = (double)th.z + 0.09 * S;
	if ((double)target.y < (double)th.y && (double)target.y > -(double)th.y * 1.1 && std::fabs((double)target.x) < (double)th.x + 0.05 * S && (double)target.z < tz) {
		target.z = (real_t)tz;
	}
	// And out of the trunk as it is drawn, the hand as thick as the arm is drawn there (_outline).
	if (drawn_on && !torso_severed && !fo_severed) {
		const Transform3D bt = torso->get_global_transform();
		const Vector3 l = bt.affine_inverse().xform(t_pos + yaw_q.xform(target));
		const Sculpt s = read_sculpt(sculpt);
		Vector3 push;
		if (s.ok) {
			const Limb lf = read_limb(o_fo, armored_fo, limb_plate);
			push = out_of_trunk(s, l, limb_r(lf, hand_y) + plate_pad((double)l.y, band_lo, band_hi, band_pad));
		}
		if (push != Vector3()) {
			target += yaw_q.inverse().xform(bt.basis.xform(push));
		}
	}
	if (!head_severed) {
		const Vector3 hh = head_half;
		const Vector3 hl = yaw_q.inverse().xform(head->get_global_position() - t_pos);
		const double hz = (double)hl.z + (double)hh.z + 0.09 * S;
		if (std::fabs((double)target.x - (double)hl.x) < (double)hh.x + 0.05 * S && std::fabs((double)target.y - (double)hl.y) < (double)hh.y + 0.05 * S && (double)target.z < hz) {
			target.z = (real_t)hz;
		}
	}
	return target;
}

Vector3 VoxelCore::elbow_off(RigidBody3D *torso, const Dictionary &sculpt, const Dictionary &o_up, bool armored_up, const Vector3 &shoulder_w, const Vector3 &e_dir, double lu, double band_lo, double band_hi, double band_pad, double limb_plate) const {
	if (torso == nullptr) {
		return e_dir;
	}
	const Sculpt s = read_sculpt(sculpt);
	if (!s.ok) {
		return e_dir;
	}
	const Transform3D bt = torso->get_global_transform();
	const Transform3D bi = bt.affine_inverse();
	const Limb up = read_limb(o_up, armored_up, limb_plate);
	return elbow_loop(s, bt, bi, shoulder_w, e_dir, lu, limb_r(up, lu * (0.5 - 0.5)), limb_r(up, lu * (0.5 - 0.75)), limb_r(up, lu * (0.5 - 1.0)), band_lo, band_hi, band_pad);
}

Vector3 VoxelCore::hand_off(RigidBody3D *torso, const Dictionary &sculpt, const Dictionary &o_up, bool armored_up, const Dictionary &o_fo, bool armored_fo, const Vector3 &shoulder_w, const Vector3 &elbow_w, const Vector3 &goal, double lu, double lf, bool straight, bool fo_severed, double S, double band_lo, double band_hi, double band_pad, double limb_plate) const {
	if (torso == nullptr || fo_severed) {
		return goal;
	}
	const Sculpt s = read_sculpt(sculpt);
	if (!s.ok) {
		return goal;
	}
	const Transform3D bt = torso->get_global_transform();
	const Transform3D bi = bt.affine_inverse();
	const Vector3 from = straight ? shoulder_w : elbow_w;
	const Limb up = read_limb(o_up, armored_up, limb_plate);
	const Limb fo = read_limb(o_fo, armored_fo, limb_plate);
	double mk[8];
	int64_t n;
	if (straight) {
		// [how far along the line, how thick the limb is drawn there] a mark.
		mk[0] = lu * 0.5;
		mk[1] = limb_r(up, 0.0);
		mk[2] = lu * 0.75;
		mk[3] = limb_r(up, -0.25 * lu);
		mk[4] = lu;
		mk[5] = limb_r(up, -0.5 * lu);
		mk[6] = lu + lf * 0.5;
		mk[7] = limb_r(fo, 0.0);
		n = 4;
	} else {
		mk[0] = lf * 0.35;
		mk[1] = limb_r(fo, 0.15 * lf);
		mk[2] = lf * 0.7;
		mk[3] = limb_r(fo, -0.2 * lf);
		n = 2;
	}
	return hand_loop(s, bt, bi, from, goal, S, mk, n, band_lo, band_hi, band_pad);
}
