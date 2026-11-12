#pragma once
// The voxel hot paths in C++: greedy box merging for the colliders, flood fill for the
// lumps that come off a part and the searches over a part's voxels. Same results as scripts/voxel/greedy.gd and VoxelPart._flood.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

namespace godot {

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
	// A man's arms kept out of his trunk as it is drawn (Fighter._out_of_trunk with the limb's
	// thickness and the cuirass's on it, _elbow_off_trunk, _hand_off_trunk), as the script does
	// them. `o`: the trunk's outline (Fighter._outline); `bt`, `bi`: the trunk's transform and its
	// inverse; `band_*`: the cuirass (Fighter._plate_band); `marks`: [how far along, how thick] a mark.
	Vector3 sculpt_out(const Dictionary &o, const Vector3 &l, double limb_r, double band_lo, double band_hi, double band_pad) const;
	Vector3 sculpt_elbow(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &shoulder_w, const Vector3 &e_dir, double lu, double r_half, double r_three, double r_whole, double band_lo, double band_hi, double band_pad) const;
	Vector3 sculpt_hand(const Dictionary &o, const Transform3D &bt, const Transform3D &bi, const Vector3 &from, const Vector3 &goal, double size, const PackedFloat64Array &marks, double band_lo, double band_hi, double band_pad) const;
	PackedFloat64Array skin_nearest(const PackedInt32Array &fx, const PackedInt32Array &fy, const PackedInt32Array &fz, const PackedByteArray &alive, const Vector3i &grid, double vf, double scale, const Vector3 &half_ext, double max_depth, const Vector3 &want) const;
};

} // namespace godot
