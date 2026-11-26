// The arm's drive in C++ (docs/PERF_RESEARCH.md, section 20), a piece at a time, each the same as the script's to the bit.
// Here: the bones of a shield's or an empty hand's arm and the pull of the hand to its mark (Fighter._drive_arm's last
// branch and its tail, with _elbow_dir, _limit_dir, _twist_to and _orient_shield) in one call. As in drive.cpp and arm.cpp
// each line does what the script's line does, in the same types and order: scalars in double, vectors in float, a vector
// times a scalar taking the scalar as a float. The bodies are the script's own; what the script has worked out before
// (the mark, the hand's place and speed, the arm's strength) comes in as arguments.

#include "voxel_core.h"
#include "engine_math.h"

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cmath>

using namespace godot;
using namespace vc;

namespace {

// PD.inertia_of
double ad_inertia_of(RigidBody3D *body) {
	const Vector3 i = body->get_inertia();
	return gd_maxf(1e-4, ((double)i.x + (double)i.y + (double)i.z) / 3.0);
}

// Fighter._limit_dir
Vector3 ad_limit_dir(Vector3 e, int axis, double mx) {
	if ((double)e[axis] <= mx) {
		return e;
	}
	e[axis] = (real_t)mx;
	const double rest = std::sqrt(gd_maxf(0.0, 1.0 - mx * mx));
	const int o0 = axis == 0 ? 1 : 0;
	const int o1 = 2;
	const double l = Vector2(e[o0], e[o1]).length();
	if (l < 1e-4) {
		e[o0] = (real_t)(axis == 0 ? -rest * 0.8 : 0.0);
		e[o1] = (real_t)(-rest * (axis == 0 ? 0.6 : 1.0));
	} else {
		e[o0] = (real_t)((double)e[o0] * (rest / l));
		e[o1] = (real_t)((double)e[o1] * (rest / l));
	}
	return e;
}

// Fighter._elbow_dir. `level`: lerpf(0.28, ELBOW_LEVEL, smoothstep(...)) as the script has it (0.28 where no drop is given).
Vector3 ad_elbow_dir(bool flip, Vector3 e_local, double lu, const Quaternion &t_rot, double S, double level) {
	if (flip) {
		e_local.x = -e_local.x;
	}
	const double cx = 0.22 * S / lu;
	const double cy = level * S / lu;
	e_local = ad_limit_dir(eng_normalized(e_local), 0, cx);
	e_local = ad_limit_dir(e_local, 1, cy);
	if ((double)e_local.x > cx + 1e-4) {
		e_local.x = (real_t)cx;
		e_local.z = (real_t)(std::sqrt(gd_maxf(0.0, 1.0 - cx * cx - (double)e_local.y * (double)e_local.y)) * ((double)e_local.z < -0.05 ? -1.0 : 1.0));
	}
	if (flip) {
		e_local.x = -e_local.x;
	}
	return eng_normalized(t_rot.xform(e_local));
}

// Fighter._twist_to
void ad_twist_to(RigidBody3D *part, const Vector3 &want, double kp, double kd, double max_t, double dt) {
	const Quaternion q = pd_quat_of(part);
	const Vector3 axis = q.xform(Vector3(0, -1, 0));
	Vector3 f = q.xform(Vector3(0, 0, 1));
	f -= axis * (real_t)(double)axis.dot(f);
	Vector3 rf = want - axis * (real_t)(double)axis.dot(want);
	if ((double)f.length_squared() < 1e-6 || (double)rf.length_squared() < 1e-6) {
		return;
	}
	f = eng_normalized(f);
	rf = eng_normalized(rf);
	const double ang = std::atan2((double)f.cross(rf).dot(axis), (double)f.dot(rf));
	const double spin = part->get_angular_velocity().dot(axis);
	double t = kp * ang - kd * spin;
	t = t < -max_t ? -max_t : (t > max_t ? max_t : t);
	part->apply_torque_impulse(axis * (real_t)t * (real_t)dt);
}

// The engine's smoothstep where its two ends differ (GDScript's smoothstep).
double ad_smoothstep(double from, double to, double x) {
	double s = (x - from) / (to - from);
	s = s < 0.0 ? 0.0 : (s > 1.0 ? 1.0 : s);
	return s * s * (3.0 - 2.0 * s);
}

double ad_clampf(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

// Fighter._route_front (AIM_AHEAD 1.6)
Vector3 ad_route_front(const Vector3 &cur, const Vector3 &want, const Quaternion &frame, double out_x) {
	const double ahead = cur.angle_to(want);
	Vector3 go = want;
	if (ahead > 0.9) {
		Vector3 mid = frame.inverse().xform(cur + want);
		if ((double)mid.length_squared() < 0.0025) {
			mid = Vector3(0, 0, 1);
		}
		const bool aside = out_x != 0.0 && (double)eng_normalized(mid).x * out_x > 0.5;
		if ((double)eng_normalized(mid).z < 0.45 && !aside) {
			mid.z = (real_t)gd_maxf((double)mid.z, 1.2);
			go = frame.xform(eng_normalized(mid));
		}
	}
	if (ahead <= 1.6 && go == want) {
		return want;
	}
	const Vector3 ax = cur.cross(go);
	if ((double)ax.length_squared() < 1e-8) {
		return want;
	}
	return eng_normalized(cur.rotated(eng_normalized(ax), (real_t)gd_minf(1.6, (double)cur.angle_to(go))));
}

// VoxelPart.velocity_at
Vector3 ad_velocity_at(RigidBody3D *b, const Vector3 &p) {
	const Vector3 com = b->get_center_of_mass();
	const Vector3 c = (com == Vector3()) ? b->get_global_position() : b->get_global_transform().xform(com);
	return b->get_linear_velocity() + b->get_angular_velocity().cross(p - c);
}

// GDScript's move_toward
double ad_move_toward(double from, double to, double delta) {
	const double d = to - from;
	return std::fabs(d) <= delta ? to : from + (d == 0.0 ? 0.0 : (d < 0.0 ? -1.0 : 1.0)) * delta;
}

} // namespace

// k: 0 S, 1 MS, 2 af, 3 strength, 4 hnd (the hand's handling), 5 m_eff, 6 dt, 7 gravity, 8 body_mass, 9 mods.strength, 10 the left arm (1) or the
// right (0), 11 fist_home, 12 power (1/0), 13 on_ground (1/0), 14 jab_t, 15 a weapon in the hand (1/0), 16 its mass, 17 the upper arm's nominal
// mass, 18 the forearm's, 19 20 21 the cuirass's band (Fighter._plate_band_now), 22 the upper arm armoured (1/0), 23 lu (UPPER_LEN * S), 24 LIMB_PLATE,
// 25 the trunk's sculpt given (1/0). Returns the arm's strain (how far the hand is from its goal).
double VoxelCore::arm_plain(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *shield, const Vector3 &target_w, const Vector3 &shoulder_w, const Vector3 &dir, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &hand_w, const Vector3 &hand_vel, const Vector3 &target_vel, const Dictionary &sculpt, const Dictionary &o_up, const PackedFloat64Array &k) const {
	if (upper == nullptr || fore == nullptr || torso == nullptr || k.size() < 26) {
		return 0.0;
	}
	const double *kk = k.ptr();
	const double S = kk[0], MS = kk[1], af = kk[2], strength = kk[3], hnd = kk[4], m_eff = kk[5], dt = kk[6], gravity = kk[7], body_mass = kk[8], mods_strength = kk[9];
	const bool left = kk[10] != 0.0;
	const double fist_home = kk[11];
	const bool power = kk[12] != 0.0, on_ground = kk[13] != 0.0;
	const double jab_t = kk[14];
	const bool has_w = kk[15] != 0.0;
	const double w_mass = kk[16], up_nominal = kk[17], fo_nominal = kk[18];
	const double lu = kk[23];

	// A shield or an empty hand: the same elbow as a weapon arm, mirrored for the left.
	Vector3 e_dir = ad_elbow_dir(left, t_rot.inverse().xform(eng_normalized(dir + Vector3(0, (real_t)-0.35, 0))), lu, t_rot, S, 0.28);
	if (kk[25] != 0.0) {
		e_dir = elbow_off(torso, sculpt, o_up, kk[22] != 0.0, shoulder_w, e_dir, lu, kk[19], kk[20], kk[21], kk[24]);
	}
	const Vector3 elbow = shoulder_w + e_dir * (real_t)lu;
	const Vector3 f_dir = (double)(target_w - elbow).length_squared() > 1e-6 ? eng_normalized(target_w - elbow) : dir;
	const double home = fist_home > 0.0 ? 2.5 : 1.0;
	{
		const double wn = 14.0 * home;
		const double max_t = 90.0 * home * af * MS * S;
		if (wn > 0.0 && max_t > 0.0) {
			pd_axis(upper, Vector3(0, -1, 0), e_dir, wn, 0.8, max_t, dt, 1.0, Vector3());
		}
	}
	{
		const double wn = 10.0 * home;
		const double max_t = 60.0 * home * af * MS * S;
		if (wn > 0.0 && max_t > 0.0) {
			pd_axis(fore, Vector3(0, -1, 0), f_dir, wn, 0.8, max_t, dt, 1.0, Vector3());
		}
	}
	if (fist_home > 0.0) {
		ad_twist_to(upper, f_dir, 30.0 * MS, 1.4 * MS, 90.0 * MS, dt);
	} else {
		pd_twist(upper, torso, 1.5 * MS, 0.25 * MS, 12.0 * MS, dt);
	}
	pd_twist(fore, upper, 1.0 * MS, 0.2 * MS, 8.0 * MS, dt);
	if (shield != nullptr) {
		// Fighter._orient_shield
		Vector3 fwd = yaw_q.xform(Vector3(0, 0, 1));
		Vector3 out = target_w - t_pos;
		out.y = 0;
		fwd = eng_normalized(fwd.lerp(eng_normalized(out), (real_t)0.4));
		Basis b;
		b.set_column(0, eng_normalized(Vector3(0, 1, 0).cross(fwd)));
		b.set_column(1, Vector3(0, 1, 0));
		b.set_column(2, fwd);
		const Quaternion desired = eng_rotation_quaternion(eng_orthonormalized(b));
		const Vector3 err = rot_error(desired, pd_quat_of(shield));
		const double wn = 18.0;
		const Vector3 tq = torque_for(shield, err * (real_t)(wn * wn) - shield->get_angular_velocity() * (real_t)(2.0 * 0.9 * wn), 1.5);
		shield->apply_torque_impulse(clamp_len(tq, 70.0 * strength * MS * S * mods_strength) * (real_t)dt);
	}

	// The hand's pull to its mark (the tail of _drive_arm): damped to the critical whatever the weapon weighs.
	const Vector3 hand_goal = target_w;
	const double kp = 300.0 * (0.5 + 0.5 * hnd) * 1.0;
	const double kd = 2.1 * std::sqrt(kp) * (power ? 1.1 : 1.0);
	const Vector3 fore_pos = fore->get_global_position();
	const Vector3 r_h = hand_w - fore_pos;
	const double m_pt = 1.0 / (1.0 / gd_maxf(0.05, (double)fore->get_mass()) + (double)r_h.length_squared() / ad_inertia_of(fore));
	const double damp = gd_minf(kd * m_eff, 1.6 * m_pt / dt);
	const double strain = (hand_goal - hand_w).length();
	Vector3 F = (hand_goal - hand_w) * (real_t)kp * (real_t)m_eff + (target_vel - hand_vel) * (real_t)damp;
	F.y = (real_t)((double)F.y + m_eff * gravity * gd_minf(1.0, af * 1.2));
	if (fist_home > 0.0) {
		F *= (real_t)0.35;
	}
	F = clamp_len(F, 1150.0 * 1.0 * strength * MS * mods_strength * (0.55 + 0.45 * hnd) * (1.0 + 0.35 * (1.0 - hnd)) * ((!has_w && jab_t > 0.0) ? 2.2 : 1.0) * (1.0 + (has_w ? 0.08 * gd_minf(8.0, w_mass) : 0.0)));
	// The hands never press down harder than a share of the body's own weight, nor pull up harder than a man can lift.
	F.y = (real_t)gd_maxf((double)F.y, -0.35 * body_mass * gravity);
	F.y = (real_t)gd_minf((double)F.y, (fo_nominal + up_nominal * 0.5) * gravity + 0.45 * body_mass * gravity * mods_strength);
	fore->apply_impulse(F * (real_t)dt, hand_w - fore_pos);
	if (on_ground) {
		torso->apply_central_impulse(Vector3((real_t)(-(double)F.x * dt * 0.35), 0, (real_t)(-(double)F.z * dt * 0.35)));
	} else {
		torso->apply_central_impulse(-F * (real_t)dt);
	}
	return strain;
}

// The blade's arm from its forearm on (Fighter._drive_arm's weapon branch after the elbow is set: _drive_forearm, _lock_elbow, _unjam_blade,
// _keep_blade_front, the swing's cap, _drive_wrist, then the hand's pull and _keep_weapon_out), for the plain case the script asks it for: one hand
// on the weapon, no thrust line, the fist firm on it, no throw. (_free_wedged, which gives no push, stays the script's.) `k` as arm_plain's, and:
// 26 lf (FORE_LEN * S), 27 the weapon's reach, 28 welded (1/0), 29 its holder is this man (1/0), 30 the trunk severed (1/0), 31 the head (1/0),
// 32 behind_t as it stands. behind_t[side] and arm_strain[side] are written as the script writes them.
void VoxelCore::arm_blade(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, RigidBody3D *w, const Quaternion &fore_q, const Quaternion &aim_fore_q, const Quaternion &w_aim, const Quaternion &aim_q, const Quaternion &grip_q, const Vector3 &aim_w, const Vector3 &hand_goal, const Vector3 &hand_w, const Vector3 &hand_vel, const Vector3 &target_vel, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, Dictionary behind_t, Dictionary arm_strain, const String &side, const PackedFloat64Array &k) const {
	if (upper == nullptr || fore == nullptr || torso == nullptr || head == nullptr || w == nullptr || k.size() < 33) {
		return;
	}
	const double *kk = k.ptr();
	const double S = kk[0], MS = kk[1], af = kk[2], strength = kk[3], hnd = kk[4], m_eff = kk[5], dt = kk[6], gravity = kk[7], body_mass = kk[8], mods_strength = kk[9];
	const double fist_home = kk[11];
	const bool power = kk[12] != 0.0, on_ground = kk[13] != 0.0;
	const double up_nominal = kk[17], fo_nominal = kk[18];
	const double lf = kk[26], reach = kk[27];
	const bool welded = kk[28] != 0.0, holder_self = kk[29] != 0.0, torso_severed = kk[30] != 0.0, head_severed = kk[31] != 0.0;
	const double w_mass = w->get_mass();
	const Variant side_key = side;

	// --- Fighter._drive_forearm ---
	{
		const Quaternion rot = pd_quat_of(fore);
		Vector3 err = rot_error(fore_q, rot);
		{
			const double moving = gd_maxf((double)aim_w.length(), gd_maxf((double)fore->get_angular_velocity().length(), (double)w->get_angular_velocity().length()));
			const double low = ad_smoothstep(0.1, -0.3, (double)aim_q.xform(Vector3(0, 1, 0)).y);
			const Vector3 line = dir_error(rot.xform(Vector3(0, -1, 0)), fore_q.xform(Vector3(0, -1, 0)));
			err = err.lerp(line, (real_t)((1.0 - ad_smoothstep(1.0, 4.0, moving)) * low));
		}
		const double hold = 1.0;
		const double wn = 16.0 * hold;
		const Vector3 alpha = clamp_len(err * (real_t)(wn * wn) - (fore->get_angular_velocity() - aim_w) * (real_t)(2.0 * 0.8 * wn), 920.0 * hold * hold * (0.6 + 0.4 * strength) * mods_strength);
		const Vector3 com_w = w->get_global_transform().xform(w->get_center_of_mass());
		const Vector3 lever = com_w - hand_w;
		const double i_fore = ad_inertia_of(fore) + fo_nominal * std::pow(lf * 0.5, 2.0);
		const double welded_k = 1.0;
		const double i_wpn = (ad_inertia_of(w) + w_mass * (double)lever.length_squared()) * welded_k;
		const double i_asm = i_fore + i_wpn;
		const Vector3 along = rot.xform(Vector3(0, -1, 0));
		const Vector3 twist_a = along * (real_t)(double)alpha.dot(along);
		Vector3 tq = torque_for(fore, alpha - twist_a, i_asm / ad_inertia_of(fore)) + torque_for(fore, twist_a, 1.5);
		const double heft = ad_clampf(i_wpn / (MS * S * S * 0.6), 0.0, 6.0);
		tq = clamp_len(tq, 90.0 * hold * strength * MS * S * mods_strength * (1.0 + 0.45 * heft));
		const double mg = w_mass * gravity * gd_minf(1.0, strength * 2.0) * welded_k;
		tq += Vector3((real_t)(-(double)lever.z * mg), 0, (real_t)((double)lever.x * mg));
		const double f = i_fore / i_asm;
		Vector3 tw = tq * (real_t)(1.0 - f);
		{
			const Vector3 bax = pd_quat_of(w).xform(Vector3(0, 1, 0));
			tw -= bax * (real_t)(double)tw.dot(bax);
		}
		fore->apply_torque_impulse((tq - tw) * (real_t)dt);
		w->apply_torque_impulse(tw * (real_t)dt);
	}
	// --- Fighter._lock_elbow ---
	{
		const Vector3 ax = pd_quat_of(fore).xform(Vector3(0, -1, 0));
		Vector3 err = rot_error(fore_q, pd_quat_of(fore));
		err -= ax * (real_t)(double)err.dot(ax);
		Vector3 rel = fore->get_angular_velocity() - upper->get_angular_velocity();
		rel -= ax * (real_t)(double)rel.dot(ax);
		const Vector3 lever = w->get_global_transform().xform(w->get_center_of_mass()) - hand_w;
		const double i_fore = ad_inertia_of(fore) + fo_nominal * std::pow(lf * 0.5, 2.0);
		const double i_asm = i_fore + (ad_inertia_of(w) + w_mass * (double)lever.length_squared());
		const double i_up = ad_inertia_of(upper);
		const double i_red = i_asm * i_up / (i_asm + i_up);
		Vector3 tq = (err * (real_t)40.0 - rel * (real_t)45.0) * (real_t)i_red;
		const Vector3 au = pd_quat_of(upper).xform(Vector3(0, -1, 0));
		tq -= au * (real_t)(double)tq.dot(au);
		tq = clamp_len(tq, 260.0 * gd_maxf(0.3, strength) * MS * S * mods_strength);
		fore->apply_torque_impulse(tq * (real_t)dt);
		upper->apply_torque_impulse(-tq * (real_t)dt);
	}
	// --- Fighter._unjam_blade ---
	if (!welded) {
		behind_t[side_key] = 0.0;
	} else {
		const Quaternion inv = t_rot.inverse();
		const Quaternion wrot = pd_quat_of(w);
		const Vector3 tip = inv.xform(w->get_global_position() + wrot.xform(Vector3(0, (real_t)(reach * 0.85), 0)) - t_pos);
		Vector3 want = (aim_fore_q * grip_q).xform(Vector3(0, 1, 0));
		const Vector3 want_l = inv.xform(want);
		const double heavy = ad_clampf((w_mass - 2.0) / 5.0, 0.0, 1.0);
		const bool behind = (double)tip.z < -(0.12 - 0.08 * heavy) * S;
		const double bt = behind ? kk[32] + dt : 0.0;
		behind_t[side_key] = bt;
		const bool pulling = (double)want_l.z > -0.2;
		if (!(bt < (pulling ? (0.6 - 0.35 * heavy) : (1.2 - 0.5 * heavy)))) {
			if (!pulling) {
				want = t_rot.xform(eng_normalized(Vector3((real_t)0.15, (real_t)0.55, 1)));
			}
			const Vector3 cur = wrot.xform(Vector3(0, 1, 0));
			Vector3 axis = cur.cross(want);
			if ((double)axis.length_squared() < 1e-6) {
				axis = t_rot.xform(Vector3(0, 1, 0));
			}
			const double ang = std::acos(ad_clampf((double)cur.dot(want), -1.0, 1.0));
			const Vector3 av = eng_normalized(axis) * (real_t)gd_minf(9.0, 5.0 * ang + 2.0) + torso->get_angular_velocity();
			w->set_angular_velocity(av);
			fore->set_angular_velocity(av);
		}
	}
	// --- Fighter._keep_blade_front (the script asks for this call only while he is not throwing) ---
	{
		const Vector3 ax = pd_quat_of(w).xform(Vector3(0, 1, 0));
		const Vector3 la = yaw_q.inverse().xform(ax);
		if (!((double)la.z > -0.05)) {
			Vector3 tgt = Vector3(la.x, la.y, (real_t)0.05);
			tgt = yaw_q.xform(eng_normalized(tgt));
			const Vector3 turn = ax.cross(tgt);
			if (!((double)turn.length_squared() < 1e-8)) {
				const double ang = ax.angle_to(tgt);
				const Vector3 lever = w->get_global_transform().xform(w->get_center_of_mass()) - hand_w;
				const double i_asm = ad_inertia_of(fore) + ad_inertia_of(w) + w_mass * (double)lever.length_squared();
				const double wn = 18.0;
				const double spin = w->get_angular_velocity().dot(eng_normalized(turn));
				const Vector3 alpha = eng_normalized(turn) * (real_t)(ang * wn * wn - gd_minf(0.0, spin) * 2.0 * wn);
				const Vector3 tq = clamp_len(alpha * (real_t)i_asm, 400.0 * MS * S * (1.0 + 0.6 * gd_minf(6.0, w_mass)));
				const double f = ad_inertia_of(fore) / i_asm;
				fore->apply_torque_impulse(tq * (real_t)dt * (real_t)f);
				w->apply_torque_impulse(tq * (real_t)dt * (real_t)(1.0 - f));
			}
		}
	}
	// --- the swing's cap (Fighter.swing_cap) ---
	{
		const Vector3 lever = w->get_global_transform().xform(w->get_center_of_mass()) - hand_w;
		const double i_wpn = ad_inertia_of(w) + w_mass * (double)lever.length_squared();
		const double kq = std::pow(0.25 * S * S * mods_strength / gd_maxf(1e-4, i_wpn), 0.25);
		double cap = ad_clampf(38.0 * kq, 16.0, 38.0);
		if (reach > 1.55 * S) {
			cap = gd_minf(cap, 12.0 * S * std::sqrt(mods_strength) / reach);
		}
		const double wl = w->get_angular_velocity().length();
		if (wl > cap) {
			const double kc = cap / wl;
			w->set_angular_velocity(w->get_angular_velocity() * (real_t)kc);
			fore->set_angular_velocity(fore->get_angular_velocity() * (real_t)kc);
		}
	}
	// --- Fighter._drive_wrist ---
	{
		const Quaternion q = pd_quat_of(w);
		const Vector3 ax = q.xform(Vector3(0, 1, 0));
		Vector3 want = w_aim.xform(Vector3(1, 0, 0));
		want -= ax * (real_t)(double)want.dot(ax);
		if (!((double)want.length_squared() < 1e-6)) {
			const Vector3 cur = q.xform(Vector3(1, 0, 0));
			const double ang = std::atan2((double)cur.cross(want).dot(ax), (double)cur.dot(eng_normalized(want)));
			const Vector3 fw = fore->get_angular_velocity();
			const double spin = (double)(w->get_angular_velocity() - fw).dot(ax) - (double)(aim_w - fw).dot(ax);
			const Basis b = eng_orthonormalized(w->get_global_transform().basis);
			const Vector3 la = b.inverse().xform(ax);
			const Vector3 wi = w->get_inertia();
			const double i_ax = gd_maxf(1e-4, (double)la.x * (double)la.x * (double)wi.x + (double)la.y * (double)la.y * (double)wi.y + (double)la.z * (double)la.z * (double)wi.z);
			const double wn = 52.0;
			double t = (ang * wn * wn - spin * 2.0 * wn) * i_ax;
			const double grip_k = 1.0;
			const Vector3 lever = w->get_global_transform().xform(w->get_center_of_mass()) - w->get_global_position();
			t -= (double)lever.cross(Vector3(0, (real_t)(-w_mass * gravity), 0)).dot(ax);
			const double t_max = gd_maxf(70.0 * MS * S, i_ax * wn * wn * 2.5) * grip_k * gd_maxf(0.4, strength);
			t = ad_clampf(t, -t_max, t_max);
			w->apply_torque_impulse(ax * (real_t)t * (real_t)dt);
			fore->apply_torque_impulse(-ax * (real_t)t * (real_t)dt);
		}
	}
	// --- the hand's pull to its mark (the tail of _drive_arm) ---
	Vector3 F;
	{
		const double kp = 300.0 * (0.5 + 0.5 * hnd) * 1.0;
		const double kd = 2.1 * std::sqrt(kp) * (power ? 1.1 : 1.0);
		const Vector3 fore_pos = fore->get_global_position();
		const Vector3 r_h = hand_w - fore_pos;
		const double m_pt = 1.0 / (1.0 / gd_maxf(0.05, (double)fore->get_mass()) + (double)r_h.length_squared() / ad_inertia_of(fore));
		const double damp = gd_minf(kd * m_eff, 1.6 * m_pt / dt);
		arm_strain[side_key] = (double)(hand_goal - hand_w).length();
		F = (hand_goal - hand_w) * (real_t)kp * (real_t)m_eff + (target_vel - hand_vel) * (real_t)damp;
		F.y = (real_t)((double)F.y + m_eff * gravity * gd_minf(1.0, af * 1.2));
		if (fist_home > 0.0) {
			F *= (real_t)0.35;
		}
		F = clamp_len(F, 1150.0 * 1.0 * strength * MS * mods_strength * (0.55 + 0.45 * hnd) * (1.0 + 0.35 * (1.0 - hnd)) * 1.0 * (1.0 + 0.08 * gd_minf(8.0, w_mass)));
		F.y = (real_t)gd_maxf((double)F.y, -0.35 * body_mass * gravity);
		F.y = (real_t)gd_minf((double)F.y, (fo_nominal + up_nominal * 0.5) * gravity + 0.45 * body_mass * gravity * mods_strength);
		fore->apply_impulse(F * (real_t)dt, hand_w - fore_pos);
		if (on_ground) {
			torso->apply_central_impulse(Vector3((real_t)(-(double)F.x * dt * 0.35), 0, (real_t)(-(double)F.z * dt * 0.35)));
		} else {
			torso->apply_central_impulse(-F * (real_t)dt);
		}
	}
	// --- Fighter._keep_weapon_out ---
	if (holder_self) {
		const Quaternion q = pd_quat_of(w);
		const Vector3 from = w->get_global_position();
		const Vector3 tip = from + q.xform(Vector3(0, (real_t)reach, 0));
		const Vector3 base = from + q.xform(Vector3(0, (real_t)-0.15, 0));
		const Vector3 ab = tip - base;
		for (int pi = 0; pi < 2; pi++) {
			RigidBody3D *part = pi == 0 ? torso : head;
			if (pi == 0 ? torso_severed : head_severed) {
				continue;
			}
			const Vector3 c = part->get_global_position();
			const double kf = ad_clampf((double)(c - base).dot(ab) / gd_maxf(1e-6, (double)ab.length_squared()), 0.0, 1.0);
			const Vector3 p = base + ab * (real_t)kf;
			Vector3 d = p - c;
			d.y = (real_t)((double)d.y * 0.7);
			const double r = (pi == 1 ? 0.2 : 0.22) * S;
			const double dist = d.length();
			if (dist >= r || dist < 1e-4) {
				continue;
			}
			const Vector3 push = d / (real_t)dist * (real_t)((r - dist) / r * 900.0 * (w_mass + 0.8)) * (real_t)dt;
			w->apply_impulse(push, p - w->get_global_position());
			if (welded) {
				fore->apply_impulse(push * (real_t)0.6, hand_w - fore->get_global_position());
			}
			part->apply_central_impulse(-push * (real_t)(welded ? 1.6 : 1.0));
		}
	}
}

// The way a blade arm's elbow goes, and its upper arm driven there (Fighter._drive_arm's weapon branch from `e_local` to the upper arm's two drives:
// _elbow_dir with its drop, _route_front, the elbow off the drawn trunk, pd_axis with the load's scale and the elbow's own turn, pd_twist), for the
// plain case: one hand on the weapon, no throw. Returns the elbow's direction; the script sets elbow_prev by it and goes on.
// `k` as arm_plain's, and: 16 the weapon's mass, 25 the trunk's sculpt given (1; 0: the elbow is kept out of the trunk's box, `torso_half`, by the face
// `elbow_face` keeps), 33 elbow_low_on (1/0), 34 an elbow's line from the step before is given (`e_was`; 1/0).
// Fighter._elbow_clear where the trunk has no sculpt (bare, or he is off his feet): the elbow put out of the trunk's box by its front or its side, kept
// to the face it was put out by (elbow_face) till the other is clearly nearer.
static Vector3 ad_elbow_box(RigidBody3D *torso, const Vector3 &torso_half, bool left, Dictionary elbow_face, const Vector3 &shoulder_w, const Vector3 &e_dir, double lu, double S) {
	static const Variant k_R = String("R"), k_L = String("L");
	static const String s_none(""), s_front("front"), s_aside("aside");
	const Variant &side_key = left ? k_L : k_R;
	const Transform3D bt = torso->get_global_transform();
	const Transform3D bi = bt.affine_inverse();
	const Vector3 e = torso_half + Vector3((real_t)0.05, 0, (real_t)0.05) * (real_t)S;
	const double out_x = left ? 1.0 : -1.0;
	Vector3 d = e_dir;
	for (int i = 0; i < 2; i++) {
		Vector3 l = bi.xform(shoulder_w + d * (real_t)lu);
		if (std::fabs((double)l.x) >= (double)e.x || std::fabs((double)l.z) >= (double)e.z || std::fabs((double)l.y) >= (double)e.y) {
			if (i == 0) {
				elbow_face[side_key] = s_none;
			}
			break;
		}
		const double front = (double)e.z - (double)l.z;
		const double aside = (double)e.x - (double)l.x * out_x;
		String face = elbow_face[side_key];
		if (face == s_none || (face == s_front && aside < front - 0.06 * S) || (face == s_aside && front < aside - 0.06 * S)) {
			face = front < aside ? s_front : s_aside;
		}
		elbow_face[side_key] = face;
		if (face == s_front) {
			l.z = e.z;
		} else {
			l.x = (real_t)(out_x * (double)e.x);
		}
		const Vector3 nd = bt.xform(l) - shoulder_w;
		if ((double)nd.length_squared() < 1e-8) {
			break;
		}
		d = eng_normalized(nd);
	}
	return d;
}

Vector3 VoxelCore::arm_elbow(RigidBody3D *upper, RigidBody3D *torso, const Vector3 &target_w, const Vector3 &shoulder_w, const Vector3 &fore_dir, const Quaternion &t_rot, const Vector3 &e_was, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &elbow_face, const Vector3 &torso_half, const PackedFloat64Array &k) const {
	if (upper == nullptr || torso == nullptr || k.size() < 35) {
		return Vector3();
	}
	const double *kk = k.ptr();
	const double S = kk[0], MS = kk[1], af = kk[2], dt = kk[6];
	const bool left = kk[10] != 0.0;
	const double w_mass = kk[16], fo_nominal = kk[18];
	const double lu = kk[23], lf = kk[26];
	const double side_sign = left ? 1.0 : -1.0;
	Vector3 e_local = t_rot.inverse().xform(target_w - fore_dir * (real_t)lf - shoulder_w);
	if ((double)e_local.length_squared() < 1e-6) {
		e_local = Vector3((real_t)(side_sign * 0.3), -1, (real_t)-0.3);
	}
	e_local = eng_normalized(eng_normalized(e_local).lerp(eng_normalized(Vector3((real_t)(side_sign * 0.5), (real_t)-0.7, (real_t)-0.5)), (real_t)0.18));
	// (lerpf(0.28, ELBOW_LEVEL, smoothstep(-0.06 S, 0.02 S, drop)); with elbow_low_on off the drop is -INF, the smoothstep 0.)
	const double drop = -(double)t_rot.inverse().xform(fore_dir).y * lf;
	const double level = 0.28 + (0.02 - 0.28) * (kk[33] != 0.0 ? ad_smoothstep(-0.06 * S, 0.02 * S, drop) : 0.0);
	Vector3 elbow_dir = ad_route_front(pd_quat_of(upper).xform(Vector3(0, -1, 0)), ad_elbow_dir(left, e_local, lu, t_rot, S, level), t_rot, 0.0);
	// (Fighter._elbow_clear: out of the trunk as it is drawn where its sculpt is there, k[25], else out of its box.)
	if (kk[25] != 0.0) {
		elbow_dir = elbow_off(torso, sculpt, o_up, kk[22] != 0.0, shoulder_w, elbow_dir, lu, kk[19], kk[20], kk[21], kk[24]);
	} else {
		elbow_dir = ad_elbow_box(torso, torso_half, left, elbow_face, shoulder_w, elbow_dir, lu, S);
	}
	const double m_load = (fo_nominal + w_mass) * lu * lu;
	const double k_up = 1.0 + m_load / ad_inertia_of(upper);
	const Vector3 up_ff = kk[34] != 0.0 ? clamp_len(e_was.cross(elbow_dir) / (real_t)dt, 25.0) : Vector3();
	const double max_t = 260.0 * af * MS * S;
	if (max_t > 0.0) {
		pd_axis(upper, Vector3(0, -1, 0), elbow_dir, 16.0, 1.0, max_t, dt, gd_minf(12.0, k_up), up_ff);
	}
	pd_twist(upper, torso, 4.0 * MS, 0.6 * MS, 25.0 * MS, dt);
	return elbow_dir;
}

// The hand's mark of a plain arm worked out (Fighter._drive_arm from `var w` to where its bones are driven: the strength, the mark eased, the punch's
// and the throw's fields left as a step with neither leaves them, hand_target_local, the hurt arm's sag, the mark kept out of his body, the hand's
// lead toward it, its speed, the handling), for a shield's or an empty hand's arm (arm_free) and for a blade's (arm_armed). Returns false, having
// changed nothing, where the step is not a plain one (a punch asked for or on its way, a throw, a thrust's line, a frost on the arm, a hand caught
// behind the back, an elbow still set): the script's own drive runs then. What the script checks before it asks is in fighter.gd, where it asks.
// refs: the per-side dictionaries, in this order: 0 jab_t, 1 jab_next, 2 fist_home, 3 throwing, 4 thrust_amt, 5 throw_pose, 6 throw_hold, 7 throw_loose,
// 8 hand_input, 9 swing_reach, 10 mark_was, 11 fist_swing, 12 wedged, 13 thrust_aim, 14 thrust_ext, 15 thrust_line, 16 hand_lead, 17 lead_vel,
// 18 handling, 19 target_vel, 20 prev_target, 21 mark_eased, 22 arm_strain, 23 swing_hold.
// k: 0 S, 1 MS, 2 af, 3 af_now, 4 stam_f, 5 blood_f, 6 dt, 7 gravity, 8 body_mass, 9 mods.strength, 10 the left arm (1/0), 11 power (1/0),
// 12 enraged (1/0), 13 on_ground (1/0), 14 daze_t, 15 a weapon or a shield in the hand (1/0), 16 its mass, 17 the upper arm's nominal mass, 18 the
// forearm's, 19 20 21 the cuirass's band, 22 the upper arm armoured, 23 lu, 24 LIMB_PLATE, 25 the trunk's sculpt given, 26 the forearm armoured, 27 the
// thrust asked of this hand, 28 stamina, 29 concussion, 30 player (1/0), 31 time, 32 slot, 33 a punch asked of this hand (1/0), 34 charging, 35 the
// weapon's inertia (its stats'), 36 its joint is there (1/0), 37 arm_reach, 38 fixed_hand (1/0), 39 the forearm's pro_level, 40 the trunk severed
// (1/0), 41 the head (1/0), 42 on his feet (state "stand"; 1/0), 43 he fights from the ground (Fighter.fights_down; 1/0), 44 jab_twist_was,
// 45 the weapon's reach (a blade's).
struct godot::ArmMark {
	Vector3 target_w, hand_w, hand_vel, target_vel, shoulder_w, dir;
	double m_eff = 0, hnd = 0, strength = 0, thrust = 0, fist_home = 0;
};

bool VoxelCore::arm_mark_core(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, bool blade, const Dictionary &hp_in, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &shoulder_l, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_fo, const Array &refs, const String &side, const double *kk, ArmMark &out) const {
	static const Variant k_x = String("x"), k_y = String("y"), k_tuck = String("tuck"), k_R = String("R"), k_L = String("L");
	static const StringName m_elbow_set("elbow_set"), m_elbow_locked("elbow_locked");
	const double S = kk[0], af = kk[2], af_now = kk[3], stam_f = kk[4], blood_f = kk[5], dt = kk[6], mods_strength = kk[9];
	const bool left = kk[10] != 0.0, power = kk[11] != 0.0, enraged = kk[12] != 0.0;
	const double daze_t = kk[14];
	const bool has_w = kk[15] != 0.0;
	const double w_mass = kk[16], up_nominal = kk[17], fo_nominal = kk[18];
	const double th_in = kk[27], stamina = kk[28], concussion = kk[29];
	const bool player = kk[30] != 0.0;
	const bool jab_in = kk[33] != 0.0;
	const bool stand = kk[42] != 0.0, ground = kk[43] != 0.0;
	const double reach = kk[45];
	// (Down or getting up, and not fighting from the ground: the arm goes to the mark a fallen man's has, not the mouse's.)
	const bool is_down = !stand && !ground;
	const Variant side_key = side;
	const Variant &other_key = left ? k_R : k_L;
	Dictionary d_jab_t = refs[0], d_jab_next = refs[1], d_fist_home = refs[2], d_throwing = refs[3], d_thrust_amt = refs[4], d_throw_pose = refs[5], d_throw_hold = refs[6], d_throw_loose = refs[7];
	Dictionary d_hand_input = refs[8], d_swing_reach = refs[9], d_mark_was = refs[10], d_fist_swing = refs[11], d_wedged = refs[12], d_thrust_aim = refs[13], d_thrust_ext = refs[14], d_thrust_line = refs[15];
	Dictionary d_hand_lead = refs[16], d_lead_vel = refs[17], d_handling = refs[18], d_target_vel = refs[19], d_prev_target = refs[20], d_mark_eased = refs[21], d_swing_hold = refs[23];

	// --- is it a plain step? (nothing is written before this is known) ---
	if (af_now < 0.0 || kk[34] > 0.0) {
		return false; // a frost thawing on the arm; a throw being wound up
	}
	const double jab_t0 = d_jab_t[side_key];
	if (jab_t0 > 0.0) {
		return false;
	}
	if (!has_w) {
		if (stand && (jab_in || (bool)d_jab_next[side_key])) {
			return false; // a punch asked for
		}
		if (!is_down && (bool)d_throwing[other_key]) {
			return false; // the other arm throwing (this one keeps clear of it)
		}
		if (stand && power && af > 0.25) {
			// A fist with its button held: its elbow locks once the arm is all but straight (Fighter.elbow_bend under PUNCH_LOCK_BEND): the script's.
			const double bend = pd_quat_of(upper).xform(Vector3(0, -1, 0)).angle_to(pd_quat_of(fore).xform(Vector3(0, -1, 0)));
			if (bend < 0.25) {
				return false;
			}
		}
	}
	if (blade && th_in > 0.5 && !is_down) {
		return false; // a thrust along the blade's line
	}
	// (A blade's arm sets its elbow itself; any other lets a set elbow go: the script's, once.)
	if ((!blade && fore->has_meta(m_elbow_set)) || (bool)fore->get_meta(m_elbow_locked, false)) {
		return false;
	}
	const Vector3 hand_w = fore->get_global_transform().xform(hand_point);
	const double wedged0 = d_wedged[side_key];
	{
		// Fighter._unwedge, as far as it changes nothing but its own count.
		const Vector3 hl = yaw_q.inverse().xform(hand_w - t_pos);
		const bool behind = (double)hl.z < -0.7 * (double)torso_half.z && std::fabs((double)hl.x) < (double)torso_half.x + 0.15 * S && (double)hl.y > -(double)torso_half.y - 0.12 * S && (double)hl.y < (double)torso_half.y + 0.2 * S;
		const bool free_hand = stand && !has_w; // (nothing held, no throw: the script has seen to the rest)
		if (wedged0 < 0.0 || (behind && free_hand)) {
			return false;
		}
	}

	// --- the mark ---
	double strength = af * stam_f * blood_f * (power ? 1.45 : 1.0) * 1.0 * (stand ? 1.0 : (ground ? 0.75 : 0.3)) * (enraged ? 1.35 : 1.0) * (1.0 - 0.6 * gd_minf(1.0, daze_t / 0.3));
	if (blade && th_in > 0.3 && stand) {
		strength *= 1.0 + 0.6 * ad_clampf(th_in, 0.0, 1.0);
	}
	// Fighter._ease_mark
	Dictionary hp = hp_in;
	if (player) {
		double tx = hp_in.get(k_x, 0.0);
		double ty = hp_in.get(k_y, 0.0);
		const Variant was = d_mark_eased[side_key];
		if (was.get_type() == Variant::ARRAY) {
			const Array wa = was;
			const double ke = 1.0 - std::exp(-dt / 0.03);
			const double w0 = wa[0], w1 = wa[1];
			tx = w0 + (tx - w0) * ke;
			ty = w1 + (ty - w1) * ke;
		}
		Array eased;
		eased.push_back(tx);
		eased.push_back(ty);
		d_mark_eased[side_key] = eased;
		hp = hp_in.duplicate();
		hp[k_x] = tx;
		hp[k_y] = ty;
	}
	d_jab_next[side_key] = false;
	d_jab_t[side_key] = gd_maxf(0.0, jab_t0 - dt);
	const double fist_home = has_w ? 0.0 : gd_maxf(0.0, (double)d_fist_home[side_key] - dt);
	d_fist_home[side_key] = fist_home;
	const double thrust = th_in;
	d_throwing[side_key] = false;
	d_thrust_amt[side_key] = is_down ? 0.0 : ad_clampf(thrust, 0.0, 1.5);
	d_throw_pose[side_key] = false;
	// Fighter._throw_hold
	if (!has_w || kk[36] == 0.0) {
		d_throw_hold[side_key] = 0.0;
		d_throw_loose[side_key] = false;
	} else {
		d_throw_hold[side_key] = ad_move_toward((double)d_throw_hold[side_key], 0.0, dt / 0.12);
	}
	if (is_down) {
		// (The mark of a man down: out to his own side and low.)
		Dictionary down_hp;
		down_hp[k_x] = left ? -0.4 : 0.4;
		down_hp[k_y] = -0.5;
		hp = down_hp;
	}
	d_hand_input[side_key] = hp;
	// A swung weapon goes out to the end of the arm: out at once as the swing starts, back in after it no faster than a stroke is read.
	const bool reach_on = blade && std::fabs(thrust) < 0.05 && (power || (double)d_swing_hold[side_key] > 0.0);
	const double swing_reach = ad_move_toward((double)d_swing_reach[side_key], reach_on ? 1.0 : 0.0, (reach_on ? 12.0 : 2.5) * dt);
	d_swing_reach[side_key] = swing_reach;
	// Fighter.hand_target_local
	Vector3 target;
	{
		const double hx = hp.get(k_x, 0.0);
		const double x = -ad_clampf(hx, -2.0, 2.0) * 0.5 * S;
		const double fist = has_w ? 0.0 : 0.12;
		const double hy = ad_clampf((double)hp.get(k_y, 0.0), -1.6, 1.6);
		double y = (-0.08 + (hy >= 0.0 ? hy * 0.42 : -0.3 * gd_minf(0.4, -hy) - (fist > 0.0 ? 0.6 : 0.4) * gd_maxf(0.0, -hy - 0.4))) * S;
		const double cross = left ? gd_maxf(0.0, hx) : gd_maxf(0.0, -hx);
		const double low = fist == 0.0 ? ad_clampf((-hy - 0.5) / 0.9, 0.0, 1.0) : 0.0;
		const double shortk = blade ? ad_clampf((0.95 - reach) / 0.5, 0.0, 1.0) : 0.0;
		y -= 0.3 * low * shortk * S;
		const double z = (0.40 + fist + thrust * 0.4 + 0.1 * gd_minf(1.0, cross / 1.5) + 0.3 * low + 0.08 * low * shortk - 0.32 * ad_clampf((double)hp.get(k_tuck, 0.0), 0.0, 1.0)) * S;
		Vector3 d = Vector3((real_t)(x + (left ? -0.1 : 0.1) * S), (real_t)y, (real_t)z);
		if (thrust > -0.5) {
			d.z = (real_t)gd_maxf((double)d.z, 0.12 * S);
		}
		if (blade && std::fabs(thrust) < 0.05 && swing_reach > 0.0 && (double)d.length() > 1e-4) {
			const double dl = d.length();
			d = eng_normalized(d) * (real_t)(dl + (gd_maxf(dl, kk[37] * 0.92) - dl) * swing_reach);
		}
		d = clamp_len(d, kk[37]);
		target = d + shoulder_l;
	}
	{
		const Variant m_was = d_mark_was[side_key];
		d_mark_was[side_key] = target;
		if (m_was.get_type() != Variant::NIL && (double)(target - (Vector3)m_was).length() > 1.5 * S * dt && !has_w) {
			d_fist_swing[side_key] = 0.15;
		}
	}
	// A hurt arm sags; a bot's ringing head has its hand wander.
	{
		const double arm_hurt = 1.0 - gd_minf(1.0, af_now / 0.85);
		target.y = (real_t)((double)target.y - gd_maxf(0.0, arm_hurt - 0.1) * 0.08 * S);
		if (concussion > 0.1 && !player) {
			target.x = (real_t)((double)target.x + std::sin(kk[31] * 3.1 + kk[32]) * concussion * 0.25);
			target.y = (real_t)((double)target.y + std::cos(kk[31] * 2.3) * concussion * 0.2);
		}
	}
	d_wedged[side_key] = 0.0;
	{
		const bool clear_on = kk[25] != 0.0 && kk[40] == 0.0;
		target = clear_body(target, yaw_q, t_pos, torso, head, torso_half, head_half, S, kk[40] != 0.0, kk[41] != 0.0, false, clear_on, clear_on ? sculpt : Dictionary(), clear_on ? kk[19] : INFINITY, clear_on ? kk[20] : -INFINITY, clear_on ? kk[21] : 0.0, clear_on ? o_fo : Dictionary(), clear_on ? kk[26] != 0.0 : false, kk[24], (double)hand_point.y);
	}
	Vector3 target_w = t_pos + yaw_q.xform(target);
	if (!has_w && stand && kk[44] != 0.0) {
		// The other fist's punch turns the trunk: this hand goes round with its shoulder (carry 1: no punch of its own on its way).
		target_w = t_pos + yaw_q.xform(Quaternion(Vector3(0, 1, 0), (real_t)(kk[44] * 1.0)).xform(target));
	}
	d_thrust_aim[side_key] = Variant();
	d_thrust_ext[side_key] = 0.0;
	d_thrust_line[side_key] = Variant();
	// The hand moves like an arm: limited speed and acceleration toward its mark.
	{
		const Variant lead_v = d_hand_lead[side_key];
		if (lead_v.get_type() != Variant::NIL && (double)((Vector3)lead_v).distance_to(target_w) < 2.5 * S) {
			Vector3 lead = lead_v;
			const double h = d_handling[side_key];
			const double wind = 0.35 + 0.65 * gd_minf(1.0, stamina / 60.0);
			// (Fighter.long_k: a blade longer than a zweihander is slower to its mark.)
			const double long_k = (blade && thrust <= 0.3) ? std::pow(gd_minf(1.0, 1.55 * S / gd_maxf(0.1, reach)), 1.5) : 1.0;
			const double vmax = 15.0 * S * long_k * (thrust > 0.3 ? 2.2 : 1.0) * (0.55 + 0.45 * h) * (0.5 + 0.5 * gd_minf(1.0, af_now / 0.85)) * wind;
			const double amax = 140.0 * S * (0.4 + 0.6 * h) * (power ? 1.3 : 1.0) * (thrust > 0.3 ? 3.0 : 1.0) * (0.5 + 0.5 * wind);
			const Vector3 to_t = target_w - lead;
			const double dist = to_t.length();
			const Vector3 v_des = dist > 1e-5 ? to_t * (real_t)(gd_minf(gd_minf(vmax, std::sqrt(2.0 * amax * dist)), dist / dt) / dist) : Vector3();
			Vector3 lv = d_lead_vel[side_key];
			const Vector3 acc = clamp_len((v_des - lv) / (real_t)dt, amax);
			lv += acc * (real_t)dt;
			d_lead_vel[side_key] = lv;
			lead = lead + lv * (real_t)dt;
			d_hand_lead[side_key] = lead;
			target_w = lead;
		} else {
			d_hand_lead[side_key] = target_w;
			d_lead_vel[side_key] = Vector3();
		}
	}
	Vector3 target_vel = (target_w - (Vector3)d_prev_target[side_key]) / (real_t)dt;
	if ((double)target_vel.length_squared() > 2500.0) {
		target_vel = Vector3();
	}
	d_target_vel[side_key] = target_vel;
	d_prev_target[side_key] = target_w;

	out.hand_w = hand_w;
	out.hand_vel = ad_velocity_at(fore, hand_w);
	out.m_eff = (fo_nominal + up_nominal * 0.5) + (has_w ? w_mass : 0.0);
	const double load = has_w ? (w_mass * 0.22 + kk[35] * 0.9) / (mods_strength * std::sqrt(S) * 1.0) : 0.0;
	double hnd = 1.0 / (1.0 + load);
	if (kk[38] != 0.0) {
		hnd *= 0.6 + 0.1 * kk[39];
	}
	d_handling[side_key] = hnd;
	out.hnd = hnd;
	out.shoulder_w = t_pos + t_rot.xform(shoulder_l);
	out.dir = eng_normalized(target_w - out.shoulder_w);
	out.target_w = target_w;
	out.target_vel = target_vel;
	out.strength = strength;
	out.thrust = thrust;
	out.fist_home = fist_home;
	return true;
}

// The whole drive of a shield's or an empty hand's arm in the plain case: its mark (arm_mark_core), then its bones and the pull (arm_plain).
bool VoxelCore::arm_free(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, RigidBody3D *shield, const Dictionary &hp_in, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &shoulder_l, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &o_fo, const Array &refs, const String &side, const Vector3 &up_half, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca, const PackedFloat64Array &k) const {
	if (upper == nullptr || fore == nullptr || torso == nullptr || head == nullptr || k.size() < 67 || refs.size() < 24) {
		return false;
	}
	const double *kk = k.ptr();
	if ((kk[15] != 0.0) != (shield != nullptr)) {
		return false;
	}
	ArmMark m;
	if (!arm_mark_core(upper, fore, torso, head, false, hp_in, t_pos, t_rot, yaw_q, shoulder_l, hand_point, torso_half, head_half, sculpt, o_fo, refs, side, kk, m)) {
		return false;
	}
	const bool has_w = shield != nullptr;
	PackedFloat64Array k2;
	k2.resize(26);
	double *q = k2.ptrw();
	q[0] = kk[0]; q[1] = kk[1]; q[2] = kk[2]; q[3] = m.strength; q[4] = m.hnd; q[5] = m.m_eff; q[6] = kk[6]; q[7] = kk[7]; q[8] = kk[8]; q[9] = kk[9];
	q[10] = kk[10]; q[11] = m.fist_home; q[12] = kk[11]; q[13] = kk[13]; q[14] = 0.0; q[15] = has_w ? 1.0 : 0.0; q[16] = has_w ? kk[16] : 0.0;
	q[17] = kk[17]; q[18] = kk[18]; q[19] = kk[19]; q[20] = kk[20]; q[21] = kk[21]; q[22] = kk[22]; q[23] = kk[23]; q[24] = kk[24]; q[25] = kk[25];
	Dictionary d_arm_strain = refs[22];
	d_arm_strain[Variant(side)] = arm_plain(upper, fore, torso, shield, m.target_w, m.shoulder_w, m.dir, t_pos, t_rot, yaw_q, m.hand_w, m.hand_vel, m.target_vel, sculpt, o_up, k2);
	arm_keep(upper, fore, torso, head, hand_point, torso_half, head_half, sculpt, o_up, o_fo, up_half, up_pa, up_ca, fo_pa, fo_ca, kk);
	return true;
}

// The arm kept out of his own body after its drive, where the step asks it (k 64, the time since it was last kept; under 0: not this step), as
// Fighter.control does after _drive_arm: _keep_arm_out (its own push and _keep_hand_front's) and _keep_elbow_low, each under the script's own
// conditions. For an arm whole, one hand on what it holds, no throw. ARM_OUT_K 900, UPPER_OUT 4; ELBOW_OVER 0.06, ELBOW_OVER_HAND 0.04,
// ELBOW_SOFT 0.03, ELBOW_LOW_K 900.
// k as arm_mark_core's, and: 55 elbow_low_on (1/0), 60 on his feet or getting up and not staggering (state "stand" or "rising", and not "stand"
// with stagger over 0.35; 1/0), 61 this arm pinned by one who has hold of him (1/0), 62 a beast has him (Fighter._beast_has_me; 1/0), 63 alive
// and not limp (1/0), 64 the time since the arm was kept out, 65 the upper arm's joint is there (1/0), 66 the forearm's (1/0).
void VoxelCore::arm_keep(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &o_fo, const Vector3 &up_half, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca, const double *kk) const {
	const double dk = kk[64];
	if (dk < 0.0) {
		return;
	}
	const double S = kk[0];
	const bool left = kk[10] != 0.0, drawn = kk[25] != 0.0, torso_severed = kk[40] != 0.0, head_severed = kk[41] != 0.0;
	const double out_x = left ? 1.0 : -1.0;
	const double w_mass = kk[15] != 0.0 ? kk[16] : 0.0;
	keep_arm_out(upper, fore, torso, head, up_half, torso_half, head_half, hand_point, out_x, S, dk, false, false, torso_severed, head_severed, kk[17], kk[18], w_mass, 900.0, 4.0, drawn,
			sculpt, kk[19], kk[20], kk[21], o_up, kk[22] != 0.0, o_fo, kk[26] != 0.0, kk[24], kk[65] != 0.0, kk[66] != 0.0, up_pa, up_ca, fo_pa, fo_ca);
	// Only while he has his body to himself, on his feet or getting up.
	if (torso_severed || kk[60] == 0.0 || (double)torso->get_linear_velocity().length() > 3.0 || kk[61] != 0.0 || kk[62] != 0.0) {
		return;
	}
	keep_hand_front(upper, fore, torso, up_half, torso_half, hand_point, out_x, S, dk, false, kk[17], kk[18], w_mass, 0.0, 900.0);
	if (kk[55] != 0.0 && S < 1.6 && kk[63] != 0.0) {
		keep_elbow_low(upper, fore, torso, up_pa, fo_pa, hand_point, !left, S, dk, kk[17], kk[18], 0.06, 0.04, 0.03, 900.0);
	}
}

namespace {

// GDScript's wrapf (the engine's, in doubles).
double ad_wrapf(double value, double min, double max) {
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

// Quaternion(arc_from, arc_to) as the 4.7.2 engine makes it, for vectors that are not opposite (read off the engine itself, 4400 pairs: the library the
// core is built with makes it another way, a bit or two off, and calls two lines the same from far further apart): the two made unit ones; no turn at
// all where their dot is over 1 - 4 * 2^-24; else the half-way turn, itself made a unit one at the end (by its length's reciprocal).
Quaternion ad_arc(const Vector3 &p_v0, const Vector3 &p_v1) {
	const Vector3 n0 = eng_normalized(p_v0);
	const Vector3 n1 = eng_normalized(p_v1);
	const real_t d = n0.dot(n1);
	if (d > (real_t)0.99999976158142) {
		return Quaternion();
	}
	if (d < (real_t)-0.99999976158142) {
		return Quaternion(p_v0, p_v1); // (opposite lines: not asked of it here)
	}
	const Vector3 c = n0.cross(n1);
	const real_t s = Math::sqrt((1.0f + d) * 2.0f);
	const real_t rs = 1.0f / s;
	const Quaternion q(c.x * rs, c.y * rs, c.z * rs, s * 0.5f);
	const real_t rl = 1.0f / Math::sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
	return Quaternion(q.x * rl, q.y * rl, q.z * rl, q.w * rl);
}

// Fighter.weapon_aim for a blade's plain step (no bow, no throw, no thrust along its line; one hand on it): the turn the weapon is asked to lie at, and
// the fields it keeps (aim_q, aim_tw, chop_mem, a bot's stroke_dir and stroke_idle, a spear's spear_true). `low` is what the script raises low_hand to.
// k as arm_armed's.
Quaternion ad_weapon_aim(RigidBody3D *w, const Vector3 &hand_w, const Vector3 &target_w, const Vector3 &target_vel, const Quaternion &yaw_q, const Dictionary &hp, const Array &refs, const Variant &side_key, const double *kk, double hnd, double &low) {
	static const Variant k_x = String("x"), k_y = String("y");
	const double PI = 3.14159265358979323846;
	const double PANE_Y = (double)(real_t)1.6; // (Fighter.PANE is a Vector2: its 1.6 a float's)
	const double S = kk[0], dt = kk[6];
	const bool left = kk[10] != 0.0, stand = kk[42] != 0.0, spear = kk[46] != 0.0;
	const double w_mass = kk[16], reach = kk[45];
	Dictionary d_aim_q = refs[24], d_aim_tw = refs[26], d_chop = refs[27], d_stroke_dir = refs[28], d_stroke_idle = refs[29], d_spear_true = refs[30];
	const double hy = hp.get(k_y, 0.15);
	const double hx0 = hp.get(k_x, 0.0);
	// Fighter.aim_dir
	Vector3 axis_l(0, 0, 1);
	{
		const double r = Vector2((real_t)(hx0 / 2.0), (real_t)(hy / PANE_Y)).length();
		if (!(r < 1e-5)) {
			const double th = gd_minf(r, 1.0) * PI / 2.0;
			const Vector2 az = Vector2((real_t)hx0, (real_t)hy).normalized();
			axis_l = Vector3((real_t)(-(double)az.x * std::sin(th)), (real_t)((double)az.y * std::sin(th)), (real_t)std::cos(th));
		}
	}
	const double elev = std::asin(ad_clampf((double)axis_l.y, -1.0, 1.0));
	Vector3 axis = yaw_q.xform(axis_l);
	if (spear) {
		// A spear is held couched, its point on the line he looks along; the mouse moves the point about that line.
		Vector3 base = yaw_q.xform(Vector3(0, 0, 1));
		if (kk[47] != 0.0) {
			const double pt = ad_clampf(kk[48], -0.9, 0.9) * 0.8;
			base = Vector3((real_t)(std::sin(kk[49]) * std::cos(pt)), (real_t)std::sin(pt), (real_t)(std::cos(kk[49]) * std::cos(pt)));
		}
		const double hx = ad_clampf(hx0, -2.0, 2.0);
		axis = base.rotated(Vector3(0, 1, 0), (real_t)(-hx * 0.6));
		const Vector3 side_ax = eng_normalized(axis.cross(Vector3(0, 1, 0)));
		if ((double)side_ax.length_squared() > 1e-4) {
			axis = eng_normalized(axis.rotated(side_ax, (real_t)(ad_clampf(hy, -1.6, 1.6) * 0.55)));
		}
		// Fighter._spear_trued
		double fix = d_spear_true[side_key];
		const double a_yaw = std::atan2((double)axis.x, (double)axis.z);
		const double flat = Vector2(axis.x, axis.z).length();
		if (stand && flat > 0.75 && (double)w->get_angular_velocity().length() < 2.5) {
			const Vector3 now = pd_quat_of(w).xform(Vector3(0, 1, 0));
			const double e_yaw = ad_wrapf(a_yaw - std::atan2((double)now.x, (double)now.z), -PI, PI);
			if (std::fabs(e_yaw) < 0.6 && (double)Vector2(now.x, now.z).length() > 0.7) {
				fix = ad_clampf(fix + e_yaw * 2.0 * dt, -0.45, 0.45);
				d_spear_true[side_key] = fix;
			}
		}
		const double y2 = a_yaw + fix;
		axis = Vector3((real_t)(std::sin(y2) * flat), axis.y, (real_t)(std::cos(y2) * flat));
	}
	// Nor the blade: it never points back past the shoulders.
	{
		const Vector3 la = yaw_q.inverse().xform(axis);
		if ((double)la.z < -0.15) {
			Vector2 flat2(la.x, la.y);
			const double keep = std::sqrt(gd_maxf(0.0, 1.0 - 0.15 * 0.15));
			flat2 = (double)flat2.length() > 1e-4 ? flat2.normalized() * (real_t)keep : Vector2(0, (real_t)keep);
			axis = yaw_q.xform(Vector3(flat2.x, flat2.y, (real_t)-0.15));
		}
	}
	// The line asked for is never far ahead of where the blade really is, nor on a way through the body.
	axis = ad_route_front(pd_quat_of(w).xform(Vector3(0, 1, 0)), axis, yaw_q, 0.0);
	// A low blow comes down to the sand and skims it.
	{
		const double hand_low = gd_minf((double)hand_w.y, (double)target_w.y);
		const double chop = gd_maxf(ad_clampf(-(double)target_vel.y / (1.5 * S), 0.0, 1.0), (double)d_chop[side_key] - dt / 0.6);
		d_chop[side_key] = chop;
		const double m_far = 0.13 + 0.035 * gd_minf(4.0, w_mass);
		double margin = m_far + ((0.025 + 0.008 * gd_minf(4.0, w_mass)) - m_far) * chop;
		if (spear) {
			margin = 0.05 + 0.008 * gd_minf(4.0, w_mass);
		}
		const double floor_gap = hand_low - (kk[50] + margin * S);
		const double reach_w = gd_maxf(0.2, reach + 0.04 * S);
		if ((double)axis.y < 0.0 && (double)axis.y * reach_w < -floor_gap) {
			const double ny = ad_clampf(-floor_gap / reach_w, -1.0, 0.0);
			if (spear) {
				Vector3 hz(axis.x, 0, axis.z);
				hz = (double)hz.length_squared() > 1e-6 ? eng_normalized(hz) : yaw_q.xform(Vector3(0, 0, 1));
				axis = hz * (real_t)std::sqrt(1.0 - ny * ny) + Vector3(0, (real_t)ny, 0);
			} else {
				const Vector3 la_f = yaw_q.inverse().xform(axis);
				const double level = std::sqrt(gd_maxf(0.0, 1.0 - ny * ny));
				const double lx = ad_clampf((double)la_f.x, -level, level);
				axis = yaw_q.xform(Vector3((real_t)lx, (real_t)ny, (real_t)std::sqrt(gd_maxf(0.0, level * level - lx * lx))));
			}
		}
	}
	// (He bends to a low blow by how low the mark is on the pane.)
	low = gd_maxf(0.0, -ad_clampf(hy / PANE_Y, -1.0, 1.0) * PI / 2.0 - 0.2) * (1.0 + 0.8 * ad_clampf((0.95 - reach) / 0.5, 0.0, 1.0));
	const double raise_k = ad_smoothstep(0.5, 1.2, elev);
	Vector3 ed = yaw_q.xform(Vector3((real_t)((left ? -1.0 : 1.0) * (1.0 - raise_k)), 0, (real_t)raise_k));
	ed -= axis * ed.dot(axis);
	Vector3 fz = yaw_q.xform(Vector3(0, 0, 1));
	fz -= axis * axis.dot(fz);
	const double keep = ad_smoothstep(0.05, 0.3, (double)ed.length());
	ed = eng_normalized(fz) * (real_t)(1.0 - keep) + ((double)ed.length_squared() > 1e-8 ? eng_normalized(ed) : eng_normalized(fz)) * (real_t)keep;
	if ((double)ed.length_squared() < 1e-6) {
		ed = fz;
	}
	ed = eng_normalized(ed);
	// The edge is where the wheel set it.
	const double tw = kk[51];
	ed = ed.rotated(axis, (real_t)tw);
	// A bot has no wheel: its blade turns to lead whichever way it sweeps (k 52), an axe's one sharp side always (k 53).
	bool led = false;
	if (kk[52] != 0.0) {
		const double e_side = kk[53];
		const Vector3 tv = target_vel - axis * target_vel.dot(axis);
		if ((double)tv.length() > 0.9) {
			const Vector3 nd = eng_normalized(tv);
			const Variant sd = d_stroke_dir[side_key];
			if (sd.get_type() == Variant::NIL || (double)((Vector3)sd).dot(nd) < -0.2) {
				d_stroke_dir[side_key] = nd;
			} else {
				d_stroke_dir[side_key] = eng_normalized(((Vector3)sd).slerp(nd, (real_t)gd_minf(1.0, dt * 10.0)));
			}
			d_stroke_idle[side_key] = 0.0;
		} else {
			const double idle = (double)d_stroke_idle[side_key] + dt;
			d_stroke_idle[side_key] = idle;
			if (idle > 0.6) {
				d_stroke_dir[side_key] = Variant();
			}
		}
		const Variant sd2 = d_stroke_dir[side_key];
		if (sd2.get_type() != Variant::NIL) {
			Vector3 lead = sd2;
			lead -= axis * lead.dot(axis);
			if ((double)lead.length_squared() > 1e-4) {
				const Vector3 lt = eng_normalized(lead);
				const Variant aq = d_aim_q[side_key];
				const Vector3 prev_ed = aq.get_type() != Variant::NIL ? ((Quaternion)aq).xform(Vector3(1, 0, 0)) : lt;
				ed = lt * (real_t)(e_side != 0.0 ? e_side : ((double)prev_ed.dot(lt) >= 0.0 ? 1.0 : -1.0));
				led = true;
			}
		}
	}
	const Variant prev_v = d_aim_q[side_key];
	const bool has_prev = prev_v.get_type() != Variant::NIL;
	const Quaternion prev = has_prev ? (Quaternion)prev_v : Quaternion();
	if (has_prev) {
		// Only the blade's line is held to the speed the weapon allows; turning the edge about the line is the wrist's.
		const double long_k = std::pow(gd_minf(1.0, 1.55 * S / gd_maxf(0.1, reach)), 1.5);
		const double wmax = 34.0 * (0.45 + 0.55 * hnd) * long_k * (kk[54] != 0.0 ? 1.2 : 1.0);
		const Vector3 pa = prev.xform(Vector3(0, 1, 0));
		const double ang = pa.angle_to(axis);
		if (ang > wmax * dt && ang > 1e-5) {
			const Vector3 rax = pa.cross(axis);
			if ((double)rax.length_squared() > 1e-10) {
				axis = eng_normalized(pa.rotated(eng_normalized(rax), (real_t)(wmax * dt)));
				ed -= axis * ed.dot(axis);
				if ((double)ed.length_squared() < 1e-6) {
					ed = prev.xform(Vector3(1, 0, 0));
					ed -= axis * ed.dot(axis);
				}
				ed = eng_normalized(ed);
			}
		}
	}
	if (has_prev && !led) {
		// The edge goes round with the blade, and settles back to the edge the body's frame gives it.
		const Vector3 pa2 = prev.xform(Vector3(0, 1, 0));
		Vector3 te = prev.xform(Vector3(1, 0, 0));
		if ((double)pa2.dot(axis) > -0.95) {
			te = ad_arc(pa2, axis).xform(te);
		}
		te -= axis * te.dot(axis);
		if ((double)te.length_squared() > 1e-6) {
			te = eng_normalized(te).rotated(axis, (real_t)(tw - (double)d_aim_tw[side_key]));
			const double off = std::atan2((double)te.cross(ed).dot(axis), (double)te.dot(ed));
			ed = te.rotated(axis, (real_t)(off * gd_minf(1.0, dt * 1.5)));
		}
	}
	d_aim_tw[side_key] = tw;
	const Vector3 z = eng_normalized(ed.cross(axis));
	const Vector3 e = axis.cross(z);
	const Quaternion desired = eng_rotation_quaternion(eng_orthonormalized(Basis(e, axis, z)));
	d_aim_q[side_key] = desired;
	return desired;
}

// Fighter._hold_elbow (ELBOW_BEND 2.6), for an arm whole and its elbow not locked: `j` its elbow's joint where that is a Generic6DOFJoint3D (else
// nothing is done, as there). The joint's own calls go by name (its class is not among the ones the core is built with): PARAM_ANGULAR_LOWER_LIMIT 10,
// PARAM_ANGULAR_UPPER_LIMIT 11 (tests/test_native.gd reads them back).
void ad_hold_elbow(RigidBody3D *upper, RigidBody3D *fore, Object *j, double want_bend, bool on, double dt, double rate) {
	static const StringName m_elbow_set("elbow_set"), m_set_x("set_param_x");
	if (j == nullptr) {
		return;
	}
	const bool has = fore->has_meta(m_elbow_set);
	if (!on) {
		if (has) {
			fore->remove_meta(m_elbow_set);
			j->call(m_set_x, 10, -0.05);
			j->call(m_set_x, 11, 2.6);
		}
		return;
	}
	double cur;
	if (!has) {
		cur = pd_quat_of(upper).xform(Vector3(0, -1, 0)).angle_to(pd_quat_of(fore).xform(Vector3(0, -1, 0)));
	} else {
		// Straightening into the blow is quick; giving way to more bend is slow.
		const double goal = ad_clampf(want_bend, 0.0, 2.6);
		const double held = fore->get_meta(m_elbow_set);
		cur = ad_move_toward(held, goal, (goal < held ? 6.0 : rate) * dt);
	}
	fore->set_meta(m_elbow_set, cur);
	j->call(m_set_x, 10, gd_maxf(-0.05, cur - 0.07));
	j->call(m_set_x, 11, gd_minf(2.6, cur + 0.07));
}

} // namespace

// A blade's arm in a plain step, whole (Fighter._drive_arm from `var w` to its weapon branch's end, but _free_wedged, the script's still): the hand's
// mark (arm_mark_core), the turn the weapon is asked (weapon_aim) and how fast that turns, the forearm's line, the elbow's way and the upper arm driven
// there (arm_elbow), the swing read and the elbow set for it (_hold_elbow), the hand's goal kept off the trunk as it is drawn (hand_off), and the drive
// from the forearm on (arm_blade), and the arm kept out of his body after it where the step asks that (arm_keep). Returns [the hand's goal, what
// low_hand is raised to], or nothing, having changed nothing, where the step is not a
// plain one. `elbow_joint`: the forearm's joint where it is a Generic6DOFJoint3D; `e_was`: the elbow's line of the step before (k 56: given).
// refs as arm_mark_core's, and: 24 aim_q, 25 aim_w, 26 aim_tw, 27 chop_mem, 28 stroke_dir, 29 stroke_idle, 30 spear_true, 31 elbow_prev, 32 pane_prev,
// 33 behind_t, 34 elbow_face.
// k as arm_mark_core's, and: 46 a spear (Fighter.is_spear; 1/0), 47 a look given (1/0), 48 its pitch, 49 its yaw, 50 ground_level, 51 the wheel's twist
// asked of this hand, 52 a bot's blade that leads its stroke (is_bot, no spear, Weapon.bites; 1/0), 53 its one sharp side (Weapon.edge_side), 54 the
// input's power (1/0), 55 elbow_low_on (1/0), 56 `e_was` given (1/0), 57 lf (FORE_LEN * S), 58 the weapon welded to the hand (1/0), 59 held by him (1/0).
Array VoxelCore::arm_armed(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, RigidBody3D *w, Object *elbow_joint, const Dictionary &hp_in, const Vector3 &e_was, const Quaternion &hold_q, const Quaternion &grip_q, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &shoulder_l, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &o_fo, const Array &refs, const String &side, const Vector3 &up_half, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca, const PackedFloat64Array &k) const {
	static const Variant k_y = String("y");
	Array r;
	if (upper == nullptr || fore == nullptr || torso == nullptr || head == nullptr || w == nullptr || k.size() < 67 || refs.size() < 35) {
		return r;
	}
	const double *kk = k.ptr();
	if (kk[15] == 0.0) {
		return r;
	}
	ArmMark m;
	if (!arm_mark_core(upper, fore, torso, head, true, hp_in, t_pos, t_rot, yaw_q, shoulder_l, hand_point, torso_half, head_half, sculpt, o_fo, refs, side, kk, m)) {
		return r;
	}
	const double S = kk[0], dt = kk[6], lu = kk[23], lf = kk[57];
	const bool power = kk[11] != 0.0, stand = kk[42] != 0.0, drawn = kk[25] != 0.0;
	const Variant side_key = side;
	Dictionary d_hand_input = refs[8], d_swing_hold = refs[23], d_aim_q = refs[24], d_aim_w = refs[25], d_elbow_prev = refs[31], d_pane_prev = refs[32], d_behind_t = refs[33];
	const Dictionary hp_now = d_hand_input[side_key];

	// The turn the weapon is asked, and how fast that turns (the arm is damped toward the turn the mouse asks for, not toward standing still).
	const Variant q_was = d_aim_q[side_key];
	double low = 0.0;
	const Quaternion w_aim = ad_weapon_aim(w, m.hand_w, m.target_w, m.target_vel, yaw_q, hp_now, refs, side_key, kk, m.hnd, low);
	const Vector3 w_ff = q_was.get_type() != Variant::NIL ? clamp_len(rot_error(w_aim, (Quaternion)q_was) / (real_t)dt, 30.0) : Vector3();
	const Vector3 aim_w = ((Vector3)d_aim_w[side_key]).lerp(w_ff, (real_t)0.5);
	d_aim_w[side_key] = aim_w;
	const Quaternion fore_q = w_aim * hold_q.inverse();
	const Vector3 fore_dir = fore_q.xform(Vector3(0, -1, 0));

	// The elbow's way, and the upper arm driven there.
	PackedFloat64Array k_el;
	k_el.resize(35);
	{
		double *q = k_el.ptrw();
		for (int i = 0; i < 35; i++) {
			q[i] = 0.0;
		}
		q[0] = S; q[1] = kk[1]; q[2] = kk[2]; q[6] = dt; q[10] = kk[10]; q[16] = kk[16]; q[18] = kk[18]; q[19] = kk[19]; q[20] = kk[20]; q[21] = kk[21];
		q[22] = kk[22]; q[23] = lu; q[24] = kk[24]; q[25] = kk[25]; q[26] = lf; q[33] = kk[55]; q[34] = kk[56];
	}
	const Vector3 elbow_dir = arm_elbow(upper, torso, m.target_w, m.shoulder_w, fore_dir, t_rot, e_was, sculpt, o_up, refs[34], torso_half, k_el);
	const Vector3 elbow = m.shoulder_w + elbow_dir * (real_t)lu;
	Vector3 hand_goal = elbow + fore_dir * (real_t)lf;
	d_elbow_prev[side_key] = elbow_dir;

	// A swing locks the elbow: the whole time the button is held, through any fast stroke of the hand and a moment after it. A high mark held still
	// with the button down is a high guard, and a high guard's elbows bend.
	d_pane_prev[side_key] = d_hand_input[side_key];
	const double tv_len = m.target_vel.length();
	double swing_hold = d_swing_hold[side_key];
	swing_hold = tv_len > 1.2 * S ? 0.35 : gd_maxf(0.0, swing_hold - dt);
	d_swing_hold[side_key] = swing_hold;
	const bool moving = tv_len > 0.3 * S;
	const bool high_guard = !moving && (double)hp_now.get(k_y, 0.0) > 0.6;
	const bool swinging = ((power && !high_guard) || swing_hold > 0.0) && stand && m.thrust < 0.05;
	const bool guard = !moving;
	const double bend_need = elbow_dir.angle_to(fore_dir);
	const double want_bend = gd_minf(bend_need, guard ? 3.14159265358979323846 : 0.35);
	ad_hold_elbow(upper, fore, elbow_joint, want_bend, swinging, dt, guard ? 1.5 : 0.2);

	// The hand's goal moved out until the arm, as thick as it is drawn, is out of the trunk as it is drawn.
	if (drawn) {
		const Vector3 g2 = hand_off(torso, sculpt, o_up, kk[22] != 0.0, o_fo, kk[26] != 0.0, m.shoulder_w, elbow, hand_goal, lu, lf, want_bend < 0.5, false, S, kk[19], kk[20], kk[21], kk[24]);
		if (!g2.is_equal_approx(hand_goal)) {
			hand_goal = g2;
		}
	}

	PackedFloat64Array k_bl;
	k_bl.resize(33);
	{
		double *q = k_bl.ptrw();
		for (int i = 0; i < 33; i++) {
			q[i] = 0.0;
		}
		q[0] = S; q[1] = kk[1]; q[2] = kk[2]; q[3] = m.strength; q[4] = m.hnd; q[5] = m.m_eff; q[6] = dt; q[7] = kk[7]; q[8] = kk[8]; q[9] = kk[9];
		q[11] = m.fist_home; q[12] = kk[11]; q[13] = kk[13]; q[17] = kk[17]; q[18] = kk[18]; q[26] = lf; q[27] = kk[45]; q[28] = kk[58]; q[29] = kk[59];
		q[30] = kk[40]; q[31] = kk[41]; q[32] = (double)d_behind_t[side_key];
	}
	arm_blade(upper, fore, torso, head, w, fore_q, fore_q, w_aim, w_aim, grip_q, aim_w, hand_goal, m.hand_w, m.hand_vel, m.target_vel, t_pos, t_rot, yaw_q, d_behind_t, refs[22], side, k_bl);
	arm_keep(upper, fore, torso, head, hand_point, torso_half, head_half, sculpt, o_up, o_fo, up_half, up_pa, up_ca, fo_pa, fo_ca, kk);
	r.resize(2);
	r[0] = hand_goal;
	r[1] = low;
	return r;
}

// The end of a leg's step in Fighter.control (from `var snap` to the loop's end): a planted foot held to its place on the sand, or a stepping foot
// kept no higher than its step; the thigh and the shin driven to where the step has them (motor_rel twice); the sole kept out of the sand. The
// script has worked out the leg's pose (`thigh_q`, `shin_q`) and which of these the step asks, as before. Returns true, having done nothing, where
// a planted foot stands higher than its plant: the script then asks the ground under it (a ray), moves the plant, and asks again (mode 3).
// k: 0 S, 1 MS, 2 f (the leg's strength this step), 3 dt, 4 mode (0: no hold; 1: a planted foot held to `goal`, its plant; 2: a stepping foot kept
// under k 5; 3: a planted foot held, the ground under it already asked), 5 the step's height (feet.target_y), 6 wn_k, 7 a kick (snap; 1/0), 8 the
// shin whole (not severed, not hanging; 1/0), 9 the sole kept out of the sand this step (1/0), 10 ground_y, 11 leg_func, 12 the shin's nominal
// mass, 13 the thigh's, 14 V, 15 FOOT_HOLD, 16 LEG_WN, 17 LEG_REACT, 18 GAIT.down.
bool VoxelCore::leg_tail(RigidBody3D *thigh, RigidBody3D *shin, RigidBody3D *torso, const Quaternion &thigh_q, const Quaternion &shin_q, const Vector3 &goal, const PackedFloat64Array &k) const {
	if (thigh == nullptr || shin == nullptr || torso == nullptr || k.size() < 19) {
		return false;
	}
	return leg_tail_k(thigh, shin, torso, thigh_q, shin_q, goal, k.ptr());
}

// (leg_tail's work on the scalars where they lie: leg_plant below has them in an array of its own.)
bool VoxelCore::leg_tail_k(RigidBody3D *thigh, RigidBody3D *shin, RigidBody3D *torso, const Quaternion &thigh_q, const Quaternion &shin_q, const Vector3 &goal, const double *kk) const {
	const double S = kk[0], MS = kk[1], f = kk[2], dt = kk[3];
	const int mode = (int)kk[4];
	const Vector3 sole_l(0, (real_t)(-4.0 * kk[14] * S), 0);
	if (mode == 1 || mode == 3) {
		// A foot down holds the sand: it stays where it was put while the body goes over it.
		const Vector3 sole = shin->get_global_transform().xform(sole_l);
		if (mode == 1 && (double)sole.y - (double)goal.y > kk[18] * S) {
			return true;
		}
		const Vector3 sv = ad_velocity_at(shin, sole);
		const Vector3 r_s = sole - shin->get_global_position();
		const double m_sole = 1.0 / (1.0 / gd_maxf(0.05, (double)shin->get_mass()) + (double)r_s.length_squared() / ad_inertia_of(shin));
		const double m_leg = kk[12] + kk[13] * 0.5;
		const double k_hold = gd_minf(kk[15] * m_leg, 0.25 * m_sole / (dt * dt));
		const double c_hold = gd_minf(60.0 * m_leg, 0.8 * m_sole / dt);
		Vector3 fh((real_t)(((double)goal.x - (double)sole.x) * k_hold - (double)sv.x * c_hold), 0, (real_t)(((double)goal.z - (double)sole.z) * k_hold - (double)sv.z * c_hold));
		fh = clamp_len(fh, 260.0 * f * MS * S);
		// Down onto the sand harder than along it.
		const double gap = (double)sole.y - (double)goal.y;
		fh.y = gap > 0.002 * S ? (real_t)ad_clampf(m_sole * (-gd_maxf(0.0, gap) / (3.0 * dt) - (double)sv.y) / dt, -600.0 * f * MS * S, 0.0) : (real_t)0.0;
		shin->apply_impulse(fh * (real_t)dt, sole - shin->get_global_position());
	} else if (mode == 2) {
		// A stepping foot no higher than its step.
		const Vector3 sole2 = shin->get_global_transform().xform(sole_l);
		const double over = (double)sole2.y - kk[5] - 0.02 * S;
		if (over > 0.0) {
			const Vector3 sv2 = ad_velocity_at(shin, sole2);
			const Vector3 r2 = sole2 - shin->get_global_position();
			const double m2 = 1.0 / (1.0 / gd_maxf(0.05, (double)shin->get_mass()) + (double)r2.length_squared() / ad_inertia_of(shin));
			const double fy = ad_clampf(-over * 0.25 * m2 / (dt * dt) - gd_maxf(0.0, (double)sv2.y) * 0.8 * m2 / dt, -400.0 * f * MS * S, 0.0);
			shin->apply_impulse(Vector3(0, (real_t)(fy * dt), 0), r2);
		}
	}
	const bool snap = kk[7] != 0.0;
	const double wn = kk[16] * kk[6] * std::sqrt(f);
	if (wn > 0.0) {
		motor_rel(thigh, torso, thigh_q, wn, (snap ? 1400.0 : 900.0) * f * MS * S, dt, kk[17]);
		if (kk[8] != 0.0) {
			motor_rel(shin, thigh, shin_q, wn, (snap ? 700.0 : 600.0) * f * MS * S, dt, 1.0);
		}
	}
	// The sand is under the sole, standing as lying: pushed up only, never along.
	if (kk[9] != 0.0) {
		const Vector3 sole_f = shin->get_global_transform().xform(sole_l);
		const double pen = kk[10] - (double)sole_f.y;
		if (pen > 0.005 * S) {
			const Vector3 r_f = sole_f - shin->get_global_position();
			const double m_f = 1.0 / (1.0 / gd_maxf(0.05, (double)shin->get_mass()) + (double)r_f.length_squared() / ad_inertia_of(shin));
			const double vy_f = ad_velocity_at(shin, sole_f).y;
			const double weak = ad_clampf((0.8 - kk[11]) / 0.5, 0.0, 1.0);
			const double jy = m_f * (gd_minf(pen, 0.2 * S) * (0.3 + 0.3 * weak) / dt - gd_minf(0.0, vy_f) * (0.8 + 0.2 * weak));
			shin->apply_impulse(Vector3(0, (real_t)gd_maxf(0.0, jy), 0), r_f);
		}
	}
	return false;
}

// A leg's step standing on the ground (Fighter._leg_plant, and Fighter._leg_end after it: control's loop over the legs for a leg that is not kicking, of a man
// who stands on the ground and is not getting up) in one call: where the foot stands or steps to (its record `ft`, the script's own dictionary, written as the
// script writes it), the thigh's turn and the knee's bend that put the sole there (Fighter._leg_aim), and leg_tail. The ground under a place is the script's
// own two rays (Fighter._ground_ray: `ray_all` and `ray_sand`, made by it); what a ray hits that is a body is asked of the script (_is_dead_ground: rare).
// k: 0 S, 1 MS, 2 the leg's strength f, 3 dt, 4 ground_y, 5 leg_f, 6 the shin's nominal mass, 7 the thigh's, 8 V, 9 FOOT_HOLD, 10 LEG_WN, 11 LEG_REACT,
// 12 GAIT.down, 13 GAIT.touch, 14 GAIT.behind, 15 GAIT.arc, 16 GAIT.arc_run, 17 gait_phase, 18 h_speed, 19 hop_phase, 20 hop_k, 21 step_len, 22 move_amt,
// 23 leg_avg, 24 land_sag, 25 the left leg (1/0), 26 sprint, 27 wants_move, 28 the other leg is one to stand on (1/0), 29 the shin severed, 30 the shin
// hanging, 31 jump_t. Returns land_sag as the step leaves it.
namespace {

struct LegKeys {
	Variant anchor, from, land, swing, s, half, slip, lift, gather, late, target_y, collider, position;
	StringName is_dead_ground;
	LegKeys() :
			anchor(String("anchor")), from(String("from")), land(String("land")), swing(String("swing")), s(String("s")), half(String("half")), slip(String("slip")),
			lift(String("lift")), gather(String("gather")), late(String("late")), target_y(String("target_y")), collider(String("collider")), position(String("position")),
			is_dead_ground("_is_dead_ground") {}
};

// (Made at the first call and never unmade: at the library's end the engine's strings are gone before a static's destructor would run.)
const LegKeys &leg_keys() {
	static const LegKeys *keys = new LegKeys();
	return *keys;
}

// Fighter._ground_ray from a place at the trunk's height: whether there is ground under it within reach, and how high.
bool lp_ground(Object *fighter, PhysicsDirectSpaceState3D *space, const Ref<PhysicsRayQueryParameters3D> &ray_all, const Ref<PhysicsRayQueryParameters3D> &ray_sand, const Vector3 &from, double S,
		const LegKeys &K, real_t &r_y) {
	const Vector3 to = from + Vector3(0, (real_t)(-2.2 * S), 0);
	ray_all->set_from(from);
	ray_all->set_to(to);
	Dictionary h = space->intersect_ray(ray_all);
	if (!h.is_empty()) {
		Object *c = h[K.collider];
		// (_is_dead_ground: what is no body at all, the sand and the props, is ground; a body is asked of the script.)
		const bool dead = Object::cast_to<RigidBody3D>(c) == nullptr ? true : (bool)fighter->call(K.is_dead_ground, c);
		if (!dead) {
			ray_sand->set_from(from);
			ray_sand->set_to(to);
			h = space->intersect_ray(ray_sand);
		}
	}
	if (h.is_empty()) {
		return false;
	}
	r_y = ((Vector3)h[K.position]).y;
	return true;
}

} // namespace

double VoxelCore::leg_plant(Object *fighter, RigidBody3D *thigh, RigidBody3D *shin, RigidBody3D *o_shin, RigidBody3D *torso, PhysicsDirectSpaceState3D *space,
		const Ref<PhysicsRayQueryParameters3D> &ray_all, const Ref<PhysicsRayQueryParameters3D> &ray_sand, Dictionary ft, const Variant &o_ft, const Vector3 &t_pos,
		const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &move_dir, const Vector3 &v_smooth, const Vector3 &pa, const Vector2 &stance, const PackedFloat64Array &k) const {
	if (k.size() < 32) {
		return 0.0;
	}
	const double *kk = k.ptr();
	double land_sag = kk[24];
	if (fighter == nullptr || thigh == nullptr || shin == nullptr || torso == nullptr || space == nullptr || ray_all.is_null() || ray_sand.is_null()) {
		return land_sag;
	}
	const LegKeys &K = leg_keys();
	const double S = kk[0], dt = kk[3], ground_y = kk[4], leg_f = kk[5], V = kk[8];
	const double h_speed = kk[18], hop_phase = kk[19], hop_k = kk[20], step_len = kk[21], move_amt = kk[22], leg_avg = kk[23];
	const bool side_l = kk[25] != 0.0, sprint = kk[26] != 0.0, wants_move = kk[27] != 0.0, shin_severed = kk[29] != 0.0, shin_hanging = kk[30] != 0.0;
	const double l1 = 8.0 * V * S;
	const double l2 = 8.0 * V * S;
	const Vector3 hip = t_pos + t_rot.xform(pa);
	const Quaternion t_inv = t_rot.inverse();
	const Vector3 sole_l(0, (real_t)(-4.0 * V * S), 0);
	const real_t trunk_y = torso->get_global_position().y;
	real_t gy = 0;

	// ----- Fighter._leg_plant -----
	const double pax = (double)pa.x;
	Vector3 neutral = t_pos + yaw_q.xform(Vector3((real_t)(pax * 1.15 + (pax > 0.0 ? 1.0 : (pax < 0.0 ? -1.0 : 0.0)) * (double)stance.y * S), 0, (real_t)((double)stance.x * S)));
	neutral.y = lp_ground(fighter, space, ray_all, ray_sand, Vector3(neutral.x, trunk_y, neutral.z), S, K, gy) ? gy : (real_t)ground_y;
	const int64_t half = (int64_t)std::floor(kk[17] / Math_PI);
	const bool my_swing = ((half % 2) == 0) == side_l;
	const bool moving = h_speed > 0.25;
	bool other_up = false;
	bool swing = (bool)ft[K.swing];
	if (o_ft.get_type() == Variant::DICTIONARY && kk[28] != 0.0 && o_shin != nullptr) {
		const Dictionary of = o_ft;
		const Vector3 o_sole = o_shin->get_global_transform().xform(sole_l);
		const Vector3 my_sole = shin->get_global_transform().xform(sole_l);
		const bool me_up = !swing && (double)my_sole.y - (double)((Vector3)ft[K.anchor]).y > kk[12] * S;
		other_up = (bool)of.get(K.swing, false) || ((double)o_sole.y - (double)((Vector3)of.get(K.anchor, Vector3())).y > kk[12] * S && !me_up);
	}
	if (hop_phase > 0.0) {
		// Hopping: the good foot stays under him.
		ft[K.swing] = false;
		Vector3 at = neutral + move_dir * (real_t)step_len * (real_t)0.25;
		ft[K.anchor] = at;
		if (leg_f < 0.1) {
			at = at + Vector3(0, (real_t)(0.25 * S), 0);
			ft[K.anchor] = at;
		}
		ft[K.from] = at;
		ft[K.land] = at;
	} else if (moving && !swing && !other_up && (double)(hip - (Vector3)ft[K.anchor]).length() > (l1 + l2) * kk[14]) {
		// Left behind farther than the leg reaches: it steps.
		const Variant at_now = ft[K.anchor];
		ft[K.half] = half;
		ft[K.swing] = true;
		ft[K.from] = at_now;
		ft[K.s] = 0.0;
	} else if (moving && my_swing && !swing && (int64_t)ft[K.half] != half && !other_up) {
		const Variant at_now = ft[K.anchor];
		ft[K.half] = half;
		ft[K.swing] = true;
		ft[K.from] = at_now;
		ft[K.s] = 0.0;
	}
	swing = (bool)ft[K.swing];
	if (swing) {
		Vector3 land = neutral + move_dir * (real_t)step_len * (real_t)0.5;
		ft[K.land] = land;
		// Set down on what is where it lands.
		land.y = lp_ground(fighter, space, ray_all, ray_sand, Vector3(land.x, trunk_y, land.z), S, K, gy) ? gy : neutral.y;
		ft[K.land] = land;
		// What is in the way between: the foot lifted over it.
		const Vector3 from = ft[K.from];
		const Vector3 mid_at = (from + land) * (real_t)0.5;
		const double over_h = (lp_ground(fighter, space, ray_all, ray_sand, Vector3(mid_at.x, trunk_y, mid_at.z), S, K, gy) ? (double)gy : (double)mid_at.y) - (double)mid_at.y;
		ft[K.lift] = over_h > 0.03 * S ? over_h + 0.06 * S : 0.0;
		double rate = moving ? h_speed / step_len : 4.0;
		const bool gather = (bool)ft.get(K.gather, false);
		if (gather) {
			rate = gd_maxf(rate, 2.5);
		}
		const double s = gd_minf(1.0, (double)ft[K.s] + dt * rate);
		ft[K.s] = s;
		const Vector3 sole_td = shin->get_global_transform().xform(sole_l);
		const bool touched = s > 0.55 && !shin_severed && (double)sole_td.y - (double)land.y < kk[13] * S;
		const double late = (double)ft.get(K.late, 0.0);
		const bool high = !touched && !shin_severed && (double)from.y - (double)land.y > 0.08 * S && (double)sole_td.y - (double)land.y > 0.03 * S && late < 0.25;
		const bool turn_over = moving && !my_swing && !gather;
		if ((s >= 1.0 || turn_over) && high) {
			ft[K.late] = late + dt;
		} else if (s >= 1.0 || turn_over || touched) {
			ft[K.swing] = false;
			ft[K.gather] = false;
			ft[K.late] = 0.0;
			land_sag = gd_maxf(land_sag, (0.06 + 0.03 * gd_minf(1.0, h_speed / 3.0)) * S * ad_clampf((leg_avg - 0.6) / 0.3, 0.0, 1.0));
			const Vector3 sole_at = shin->get_global_transform().xform(sole_l);
			const double floor_at = lp_ground(fighter, space, ray_all, ray_sand, Vector3(sole_at.x, trunk_y, sole_at.z), S, K, gy) ? (double)gy : (double)land.y;
			Vector3 anchor = (moving && wants_move && !shin_severed && (double)sole_at.distance_to(land) < 0.35 * S) ? Vector3(sole_at.x, (real_t)floor_at, sole_at.z) : land;
			ft[K.anchor] = anchor;
			if (!(moving && wants_move) && !shin_severed && (double)Vector2((real_t)((double)sole_at.x - (double)land.x), (real_t)((double)sole_at.z - (double)land.z)).length() > 0.12 * S) {
				anchor = Vector3(sole_at.x, (real_t)floor_at, sole_at.z);
				ft[K.anchor] = anchor;
			}
			ft[K.slip] = 0.0;
		}
	} else {
		const Vector3 anchor = ft[K.anchor];
		if ((double)ft[K.slip] > (moving ? (sprint ? 0.5 : 0.3) : 0.18) * S && !other_up) {
			ft[K.swing] = true;
			ft[K.from] = anchor;
			ft[K.s] = 0.0;
			ft[K.half] = half;
			ft[K.land] = neutral + eng_normalized(Vector3(v_smooth.x, 0, v_smooth.z)) * (real_t)0.25 * (real_t)S;
		} else if (!moving && (double)anchor.distance_to(neutral) > 0.3 * S && !other_up) {
			ft[K.swing] = true;
			ft[K.from] = anchor;
			ft[K.s] = 0.0;
			ft[K.land] = neutral;
		} else if (S >= 1.3 && !other_up && (double)Vector2((real_t)((double)anchor.x - (double)neutral.x), (real_t)((double)anchor.z - (double)neutral.z)).length() > 0.4 * S) {
			// A giant brings a foot left out wide back in under him.
			ft[K.swing] = true;
			ft[K.gather] = true;
			ft[K.from] = anchor;
			ft[K.s] = 0.0;
			ft[K.half] = half;
		}
	}
	swing = (bool)ft[K.swing];
	const double s_now = (double)ft[K.s];
	const double ease = s_now * s_now * (3.0 - 2.0 * s_now);
	Vector3 target;
	if (swing) {
		target = ((Vector3)ft[K.from]).lerp((Vector3)ft[K.land], (real_t)ease) + Vector3(0, (real_t)(std::sin(Math_PI * s_now) * ((kk[15] + kk[16] * move_amt) * S + (double)ft.get(K.lift, 0.0))), 0);
	} else {
		target = ft[K.anchor];
	}
	const double target_y = (double)target.y;
	ft[K.target_y] = target_y;
	if (hop_phase > 0.0 && hop_k > 0.6) {
		target.y = (real_t)((double)target.y + (hop_k - 0.6) * 0.2 * S);   // the foot tucks up at the top of the hop
	}
	// Fighter._leg_aim
	Vector3 hf = t_inv.xform(target - hip);
	double d = (double)hf.length();
	const double max_d = (l1 + l2) * 0.985;
	if (d > max_d) {
		hf *= (real_t)(max_d / d);
		d = max_d;
	}
	if (d < 0.05) {
		hf = Vector3(0, (real_t)-0.05, 0);
		d = 0.05;
	}
	const Vector3 dirv = hf / (real_t)d;
	const double a = std::acos(ad_clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0));
	const double bend = Math_PI - std::acos(ad_clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0));
	Vector3 axis = dirv.cross(Vector3(0, 0, 1));
	axis = (double)axis.length_squared() < 1e-6 ? Vector3(-1, 0, 0) : eng_normalized(axis);
	const Quaternion thigh_q = eng_quat_arc(Vector3(0, -1, 0), dirv.rotated(axis, (real_t)a));

	// ----- Fighter._leg_end (standing on the ground, not kicking, not getting up) -----
	const bool whole = !shin_severed && !shin_hanging;
	double lk[19];
	Vector3 goal_n;
	lk[4] = 0.0;
	lk[5] = 0.0;
	if (whole && !swing) {
		lk[4] = 1.0;
		goal_n = ft[K.anchor];
	} else if (whole && swing && kk[31] <= 0.0) {
		lk[4] = 2.0;
		lk[5] = target_y;
	}
	lk[0] = S;
	lk[1] = kk[1];
	lk[2] = kk[2];
	lk[3] = dt;
	lk[6] = 1.0;
	lk[7] = 0.0;
	lk[8] = whole ? 1.0 : 0.0;
	lk[9] = shin_severed ? 0.0 : 1.0;
	lk[10] = ground_y;
	lk[11] = leg_f;
	lk[12] = kk[6];
	lk[13] = kk[7];
	lk[14] = V;
	lk[15] = kk[9];
	lk[16] = kk[10];
	lk[17] = kk[11];
	lk[18] = kk[12];
	const Quaternion shin_q(Vector3(1, 0, 0), (real_t)bend);
	if (leg_tail_k(thigh, shin, torso, thigh_q, shin_q, goal_n, lk)) {
		// Planted on something higher than its plant (a body lying there, a dropped shield): it stands on that.
		const Vector3 sole_n = shin->get_global_transform().xform(sole_l);
		const double under_n = lp_ground(fighter, space, ray_all, ray_sand, Vector3(sole_n.x, trunk_y, sole_n.z), S, K, gy) ? (double)gy : (double)goal_n.y;
		if (under_n > (double)goal_n.y + 0.01 * S) {
			goal_n.y = (real_t)gd_minf(under_n, (double)sole_n.y);
			ft[K.anchor] = goal_n;
		}
		lk[4] = 3.0;
		leg_tail_k(thigh, shin, torso, thigh_q, shin_q, goal_n, lk);
	}
	return land_sag;
}

// Which arguments the arms' and the legs' calls take (the script asks before it uses them: a library left over from an older build would be called
// with the wrong ones).
int VoxelCore::drive_api() const {
	return 4;
}
