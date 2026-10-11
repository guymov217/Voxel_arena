#pragma once
// The voxel hot paths in C++: greedy box merging for the colliders and flood fill for the
// lumps that come off a part. Same results as scripts/voxel/greedy.gd and VoxelPart._flood.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

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
};

} // namespace godot
