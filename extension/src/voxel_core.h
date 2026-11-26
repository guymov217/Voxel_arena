#pragma once
// The voxel hot paths in C++: greedy box merging for the colliders, flood fill for the
// lumps that come off a part and the searches over a part's voxels. Same results as scripts/voxel/greedy.gd and VoxelPart._flood.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

namespace godot {

struct ArmMark;

class VoxelCore : public RefCounted {
	GDCLASS(VoxelCore, RefCounted)

protected:
	static void _bind_methods();

public:
	// [[x0, y0, z0, x1, y1, z1], ...] covering the solid cells (index x + w * (y + h * z)).
	Array greedy_boxes(int w, int h, int d, const PackedByteArray &solid) const;
	// VoxelPart.loose_lumps: `cell` holds voxel index + 1 (0 empty) at z + d * (y + h * x). With
	// axis >= 0 the part is held on at the face `edge` of that axis; otherwise the biggest lump
	// stays. Returns the other lumps, each a PackedInt32Array of voxel indices.
	Array loose_lumps(const PackedInt32Array &cell, int w, int h, int d, int axis, int edge) const;
	// The living voxels (fx, fy, fz, alive of a VoxelPart) whose VoxelPart.local_of lies nearer
	// than `r` to `p`, in index order; at most `limit` of them (0: all).
	PackedInt32Array within(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive, const Vector3i &grid, double vf, double scale, const Vector3 &p, double r, int limit) const;
	// VoxelPart.update_blood's search: of the living voxels at most `max_depth` under a face of
	// the box `half_ext`, the one nearest `want`. Returns [index or -1, squared distance].
	// The PD drives of the limbs (Fighter.motor_rel, pd_relative, pd_axis, pd_twist, with the
	// helpers of PD), step for step as GDScript does them: scalars in double, vectors in float.
	// The callers check `severed` first; each applies its torque impulses as the script does.
	void motor_rel(RigidBody3D *part, RigidBody3D *parent, const Quaternion &rel_q, double wn, double max_t, double dt, double react) const;
	void pd_relative(RigidBody3D *part, RigidBody3D *parent, const Quaternion &rel_q, double wn, double zeta, double max_t, double dt, double boost, double react) const;
	void pd_axis(RigidBody3D *part, const Vector3 &local_axis, const Vector3 &des, double wn, double zeta, double max_t, double dt, double scale, const Vector3 &w_des) const;
	void pd_twist(RigidBody3D *part, RigidBody3D *ref, double kp, double kd, double max_t, double dt) const;
	// PD's helpers on their own (for the tests that hold the C++ to the GDScript).
	Quaternion quat_of(Node3D *body) const;
	Vector3 rot_error(const Quaternion &to, const Quaternion &from) const;
	Vector3 dir_error(const Vector3 &cur, const Vector3 &des) const;
	Vector3 clamp_len(const Vector3 &v, double mx) const;
	Vector3 torque_for(RigidBody3D *body, const Vector3 &alpha, double scale) const;
	// VoxelPart._lay_bend: the voxels over a break laid round the bend, each set on `multimesh`
	// (set_instance_transform). `rows`: 19 floats a voxel (its unbent place, the basis by rows each
	// with its origin after it, how far past the break, its offset across the bone and that offset
	// x the bone's line); `ix`: [slot, voxel] a row. Dead and veiled voxels are passed over, and
	// those past the bend unless the last layout (`b_was` long) had them in it.
	void lay_band(Object *multimesh, const PackedFloat32Array &rows, const PackedInt32Array &ix, const PackedByteArray &alive, const PackedByteArray &veil, const Quaternion &q, const Vector3 &n, double theta, double b, double b_was, double k, int axis, const Vector3 &pv, const Vector3 &tip, const Transform3D &inv) const;
	// A man's drawing work a frame (draw.cpp): the fine voxels of a shoulder guard that lie under
	// his arm's armour or are cut off by those (Fighter._clip_shoulder_guards), and what is drawn
	// on the voxels of a limb bent at a break, set where the bend has each (FineBody.lay).
	PackedByteArray guard_reach(const PackedVector3Array &pts, const Transform3D &to_arm, const PackedFloat32Array &reach, int rows, int na, double y0, double dy, double pad) const;
	PackedByteArray guard_cut(const PackedByteArray &hide_in, const PackedInt32Array &adj, const PackedInt32Array &adj_at, const PackedByteArray &anc) const;
	PackedByteArray guard_cut_near(const PackedByteArray &under, const PackedInt32Array &adj, const PackedInt32Array &adj_at, const PackedByteArray &anc, const PackedByteArray &base) const;
	PackedInt32Array bytes_changed(const PackedByteArray &was, const PackedByteArray &now) const;
	PackedInt32Array clip_plates(const Transform3D &to_t, const PackedVector3Array &origins, const PackedByteArray &on, const PackedByteArray &clip, const AABB &box) const;
	void lay_plates(Object *plates, Object *shell, const PackedFloat32Array &base, const PackedByteArray &on, const PackedByteArray &clip, const PackedInt32Array &of_at, const PackedInt32Array &of, const PackedFloat32Array &rel, const PackedByteArray &vclip, Dictionary now, const Quaternion &q, const Vector3 &n, double theta, double b, double k, int axis, const Vector3 &pv, const Vector3 &tip, const Transform3D &far_x) const;
	void lay_cells(Object *multimesh, const PackedFloat32Array &rows, const PackedInt32Array &slots, const Quaternion &q, const Vector3 &n, double theta, double b, double k, int axis, const Vector3 &pv, const Vector3 &tip, const Transform3D &far_x) const;
	// What a blow changes of a man's fine look (fine.cpp; `part` a VoxelPart with FineBody's look on
	// it, `res` and `margin` the look's template's): the fine voxels over its voxels coloured as they
	// are now (FineBody.colored), a wound's cells written (_write_wound, _write_wound_glow), the
	// fine voxels over voxels knocked out put away and the voxels a wound is looked at for (shown),
	// and what is drawn of a piece cut off (taken). As the script does them.
	bool fine_ready(Object *part) const;
	PackedFloat32Array fine_colored(Object *part, const PackedInt32Array &indices, bool apply, int res, int margin, bool colors) const;
	PackedFloat32Array fine_wound(Object *part, const PackedInt32Array &voxels, int mode, bool apply, bool apply_xf, int res, int margin) const;
	PackedInt32Array fine_show(Object *part, const PackedInt32Array &indices, bool on, bool apply) const;
	PackedFloat32Array fine_taken(Object *part, const PackedInt32Array &idx, int res, int margin) const;
	void fine_swell(Object *part, const PackedInt32Array &voxels, const Vector3 &lp, double r, double k, const Vector3 &n, double vox, double swell_max) const;
	Array shade_all(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedInt32Array &cellmap, const PackedByteArray &alive, const PackedByteArray &veil, const Vector3i &grid, bool bevel) const;
	PackedVector3Array local_all(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const Vector3i &grid, double vf, double scale) const;
	Array index_cells(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive, const Vector3i &grid, const Vector3i &dims, int res) const;
	PackedFloat32Array part_rows(const PackedVector3Array &lpos, const PackedColorArray &colors, const PackedByteArray &kinds, const PackedInt32Array &ao, const PackedInt32Array &bev) const;
	void shape_all(Object *multimesh, const Array &shape, const PackedVector3Array &lpos, const PackedByteArray &alive, const PackedByteArray &veil, const PackedInt32Array &skip) const;
	Array fine_own(const PackedColorArray &colors, const PackedByteArray &kinds, const PackedByteArray &alive, const PackedInt32Array &par, const PackedFloat32Array &shade, const PackedInt32Array &cells, const Array &palette, const Array &cloth, const Color &sk_lin, bool beast, const PackedFloat32Array &buf, const PackedFloat32Array &na) const;
	// VoxelPart._reshade's search with shade_bits of each voxel found; a weapon's voxels round a
	// point and the one nearest it (Weapon.bloody, Match._spray_on).
	PackedInt32Array reshade(const PackedInt32Array &changed, const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedInt32Array &cellmap, const PackedByteArray &alive, const PackedByteArray &veil, const Vector3i &grid, bool bevel) const;
	PackedInt32Array points_near(const PackedVector3Array &pts, const PackedByteArray &alive, const PackedByteArray &skip, const Vector3 &q, double r) const;
	int point_nearest(const PackedVector3Array &pts, const PackedByteArray &alive, const Vector3 &q) const;
	// A man's arms kept out of his trunk as it is drawn (Fighter._out_of_trunk with the limb's
	// thickness and the cuirass's on it, _elbow_off_trunk, _hand_off_trunk), as the script does
	// them. `o`: the trunk's outline (Fighter._outline); `bt`, `bi`: the trunk's transform and its
	// inverse; `band_*`: the cuirass (Fighter._plate_band); `marks`: [how far along, how thick] a mark.
	Vector3 sculpt_out(const Dictionary &o, const Vector3 &l, double limb_r, double band_lo, double band_hi, double band_pad) const;
	Vector3 sculpt_elbow(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &shoulder_w, const Vector3 &e_dir, double lu, double r_half, double r_three, double r_whole, double band_lo, double band_hi, double band_pad) const;
	Vector3 sculpt_hand(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &from, const Vector3 &goal, double size, const PackedFloat64Array &marks, double band_lo, double band_hi, double band_pad) const;
	// A man's arms kept out of his own body (arm.cpp: Fighter._keep_arm_out, _keep_hand_front, _keep_elbow_low), step for step as
	// GDScript does them: the bodies are the script's VoxelParts, what the script knows of them (their half extents, masses, whether
	// they are severed, the thickness each limb is drawn with, Fighter._limb_r) comes as arguments, and each push is applied
	// to the part and to the body it pushes off, in the order the script has them. `sculpt`: the drawn trunk (Fighter._outline),
	// used when `drawn_on`; the script's checks of when an arm is let alone (his state, a beast's hold) are made by the caller.
	void keep_arm_out(RigidBody3D *up, RigidBody3D *fo, RigidBody3D *torso, RigidBody3D *head, const Vector3 &up_half, const Vector3 &torso_half, const Vector3 &head_half, const Vector3 &hand_point, double out_x, double S, double dt, bool two_handed, bool fo_severed, bool torso_severed, bool head_severed, double up_mass, double fo_mass, double weapon_mass, double out_k, double upper_out, bool drawn_on, const Dictionary &sculpt, double band_lo, double band_hi, double band_pad, const Dictionary &o_up, bool armored_up, const Dictionary &o_fo, bool armored_fo, double limb_plate, bool up_joint, bool fo_joint, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca) const;
	void keep_hand_front(RigidBody3D *up, RigidBody3D *fo, RigidBody3D *torso, const Vector3 &up_half, const Vector3 &torso_half, const Vector3 &hand_point, double out_x, double S, double dt, bool fo_severed, double up_mass, double fo_mass, double side_weapon_mass, double haft_half_mass, double out_k) const;
	// Fighter._clear_body (a hand's mark moved out of the trunk and the head), _elbow_off_trunk (the elbow's direction) and _hand_off_trunk (the
	// hand's goal), with the limb thickness (Fighter._limb_r) worked out from the limbs' outlines (Fighter._outline) here.
	Vector3 clear_body(const Vector3 &target, const Quaternion &yaw_q, const Vector3 &t_pos, RigidBody3D *torso, RigidBody3D *head, const Vector3 &torso_half, const Vector3 &head_half, double S, bool torso_severed, bool head_severed, bool fo_severed, bool drawn_on, const Dictionary &sculpt, double band_lo, double band_hi, double band_pad, const Dictionary &o_fo, bool armored_fo, double limb_plate, double hand_y) const;
	Vector3 elbow_off(RigidBody3D *torso, const Dictionary &sculpt, const Dictionary &o_up, bool armored_up, const Vector3 &shoulder_w, const Vector3 &e_dir, double lu, double band_lo, double band_hi, double band_pad, double limb_plate) const;
	Vector3 hand_off(RigidBody3D *torso, const Dictionary &sculpt, const Dictionary &o_up, bool armored_up, const Dictionary &o_fo, bool armored_fo, const Vector3 &shoulder_w, const Vector3 &elbow_w, const Vector3 &goal, double lu, double lf, bool straight, bool fo_severed, double S, double band_lo, double band_hi, double band_pad, double limb_plate) const;
	void keep_elbow_low(RigidBody3D *up, RigidBody3D *fo, RigidBody3D *torso, const Vector3 &up_pa, const Vector3 &fo_pa, const Vector3 &hand_point, bool right, double S, double dt, double up_mass, double fo_mass, double elbow_over, double elbow_over_hand, double elbow_soft, double low_k) const;
	// The arm's drive itself, a piece at a time (arm_drive.cpp; docs/PERF_RESEARCH.md, section 20). arm_plain: the bones of a shield's or an
	// empty hand's arm and the hand's pull to its mark (Fighter._drive_arm's last branch and its tail); `k` as arm_drive.cpp lists it.
	double arm_plain(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *shield, const Vector3 &target_w, const Vector3 &shoulder_w, const Vector3 &dir, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &hand_w, const Vector3 &hand_vel, const Vector3 &target_vel, const Dictionary &sculpt, const Dictionary &o_up, const PackedFloat64Array &k) const;
	// arm_blade: a blade's arm from its forearm on (the forearm's and the elbow's drives, the blade unjammed and kept in front, the swing's cap,
	// the wrist, the hand's pull, the weapon kept out of his own body), in the plain case the script asks it for.
	void arm_blade(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, RigidBody3D *w, const Quaternion &fore_q, const Quaternion &aim_fore_q, const Quaternion &w_aim, const Quaternion &aim_q, const Quaternion &grip_q, const Vector3 &aim_w, const Vector3 &hand_goal, const Vector3 &hand_w, const Vector3 &hand_vel, const Vector3 &target_vel, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, Dictionary behind_t, Dictionary arm_strain, const String &side, const PackedFloat64Array &k) const;
	// arm_elbow: the way a blade arm's elbow goes (routed in front, off the drawn trunk) and its upper arm driven there; returns the elbow's direction.
	Vector3 arm_elbow(RigidBody3D *upper, RigidBody3D *torso, const Vector3 &target_w, const Vector3 &shoulder_w, const Vector3 &fore_dir, const Quaternion &t_rot, const Vector3 &e_was, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &elbow_face, const Vector3 &torso_half, const PackedFloat64Array &k) const;
	// arm_free: the whole drive of a shield's or an empty hand's arm in the plain case (the mark worked out, then arm_plain); false, nothing changed, where it is not.
	Array arm_armed(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, RigidBody3D *w, Object *elbow_joint, const Dictionary &hp_in, const Vector3 &e_was, const Quaternion &hold_q, const Quaternion &grip_q, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &shoulder_l, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &o_fo, const Array &refs, const String &side, const Vector3 &up_half, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca, const PackedFloat64Array &k) const;
	bool leg_tail(RigidBody3D *thigh, RigidBody3D *shin, RigidBody3D *torso, const Quaternion &thigh_q, const Quaternion &shin_q, const Vector3 &goal, const PackedFloat64Array &k) const;
	int drive_api() const;
	PackedByteArray pack_parts(const Array &parts) const;
	void record_vel(const Array &bodies, Dictionary vel) const;
	bool arm_mark_core(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, bool blade, const Dictionary &hp_in, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &shoulder_l, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_fo, const Array &refs, const String &side, const double *kk, ArmMark &out) const;
	void arm_keep(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &o_fo, const Vector3 &up_half, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca, const double *kk) const;
	bool arm_free(RigidBody3D *upper, RigidBody3D *fore, RigidBody3D *torso, RigidBody3D *head, RigidBody3D *shield, const Dictionary &hp_in, const Vector3 &t_pos, const Quaternion &t_rot, const Quaternion &yaw_q, const Vector3 &shoulder_l, const Vector3 &hand_point, const Vector3 &torso_half, const Vector3 &head_half, const Dictionary &sculpt, const Dictionary &o_up, const Dictionary &o_fo, const Array &refs, const String &side, const Vector3 &up_half, const Vector3 &up_pa, const Vector3 &up_ca, const Vector3 &fo_pa, const Vector3 &fo_ca, const PackedFloat64Array &k) const;
	// The fine look's smooth skin (FineSmooth: solid, joined, blurred's passes, ways, corners), as
	// the script does them. `at`, `inner`: fine voxels, x y z by turns. A field is the script's
	// {f, sx, sy, sz, lo, pad}; an empty one where the script is given none.
	Dictionary smooth_solid(const PackedInt32Array &at, const PackedInt32Array &inner, int res, bool seal_lo, bool seal_hi, int pad) const;
	Dictionary smooth_joined(const Dictionary &sol, const Array &beside) const;
	PackedFloat32Array smooth_blur(const PackedFloat32Array &f, int sx, int sy, int sz, int r) const;
	PackedFloat32Array smooth_ways(const PackedInt32Array &at, const Dictionary &fld, const Dictionary &sol, const Dictionary &own_fld) const;
	PackedFloat32Array smooth_corners(const PackedInt32Array &at, const Dictionary &sol, const Dictionary &shape, const Dictionary &light, const Dictionary &own, const Dictionary &own_shape, const Dictionary &own_light, double held_in, double held_out, int even_r) const;
	PackedFloat64Array skin_nearest(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive, const Vector3i &grid, double vf, double scale, const Vector3 &half_ext, double max_depth, const Vector3 &want) const;
};

} // namespace godot
