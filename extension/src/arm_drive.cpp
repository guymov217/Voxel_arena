// The arm's drive in C++ (docs/PERF_RESEARCH.md, section 20), a piece at a time, each the same as the script's to the bit.
// Here: the bones of a shield's or an empty hand's arm and the pull of the hand to its mark (Fighter._drive_arm's last
// branch and its tail, with _elbow_dir, _limit_dir, _twist_to and _orient_shield) in one call. As in drive.cpp and arm.cpp
// each line does what the script's line does, in the same types and order: scalars in double, vectors in float, a vector
// times a scalar taking the scalar as a float. The bodies are the script's own; what the script has worked out before
// (the mark, the hand's place and speed, the arm's strength) comes in as arguments.

#include "voxel_core.h"
#include "engine_math.h"

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
// plain case: one hand on the weapon, no throw, the trunk's sculpt given. Returns the elbow's direction; the script sets elbow_prev by it and goes on.
// `k` as arm_plain's, and: 16 the weapon's mass, 33 elbow_low_on (1/0), 34 an elbow's line from the step before is given (`e_was`; 1/0).
Vector3 VoxelCore::arm_elbow(RigidBody3D *upper, RigidBody3D *torso, const Vector3 &target_w, const Vector3 &shoulder_w, const Vector3 &fore_dir, const Quaternion &t_rot, const Vector3 &e_was, const Dictionary &sculpt, const Dictionary &o_up, const PackedFloat64Array &k) const {
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
	elbow_dir = elbow_off(torso, sculpt, o_up, kk[22] != 0.0, shoulder_w, elbow_dir, lu, kk[19], kk[20], kk[21], kk[24]);
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
