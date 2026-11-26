class_name Greedy
## Greedy box merging over a voxel grid: runs along x, then whole rows up y, then slabs along
## z. `solid(x, y, z)` says which cells are filled; returns [[x0, y0, z0, x1, y1, z1], ...].
## When the C++ extension (native/, class VoxelCore) is loaded it does the work; this script is
## the fallback and the reference the tests hold it to.

static var native: Object = null
static var _checked := false
static var use_native := true
static var arm_ok := false   # the loaded core has the arms' natives (an older build does not: the script keeps the arms out)
static var arm_drive_ok := false   # and the arm's drive itself, as far as it has been moved there (VoxelCore.arm_plain; docs/PERF_RESEARCH.md, section 20)
static var leg_ok := false   # and the end of a leg's step (VoxelCore.leg_tail)
static var bulk_ok := false   # and what is asked of every body in one go (VoxelCore.pack_parts, record_vel)
const DRIVE_API := 4   # the arguments the arms' and the legs' calls take, as this script hands them over (VoxelCore.drive_api: a library of another build is not asked)

static func core() -> Object:
	if not _checked:
		_checked = true
		if ClassDB.class_exists("VoxelCore"):
			native = ClassDB.instantiate("VoxelCore")
			arm_ok = native.has_method("keep_arm_out") and native.has_method("keep_hand_front") and native.has_method("keep_elbow_low") and native.has_method("clear_body") and native.has_method("elbow_off") and native.has_method("hand_off")
			var api_ok: bool = native.has_method("drive_api") and int(native.drive_api()) == DRIVE_API
			arm_drive_ok = arm_ok and api_ok and native.has_method("arm_plain") and native.has_method("arm_blade") and native.has_method("arm_elbow") and native.has_method("arm_free") and native.has_method("arm_armed")
			leg_ok = arm_ok and api_ok and native.has_method("leg_tail")
			bulk_ok = native.has_method("pack_parts") and native.has_method("record_vel")
	return native if use_native else null

static func boxes(w: int, h: int, d: int, solid: PackedByteArray) -> Array:
	var nc := core()
	if nc:
		return nc.greedy_boxes(w, h, d, solid)
	return boxes_gd(w, h, d, solid)

static func boxes_gd(w: int, h: int, d: int, solid: PackedByteArray) -> Array:
	var used := PackedByteArray()
	used.resize(w * h * d)
	var out: Array = []
	for z in d:
		for y in h:
			for x in w:
				var c := x + w * (y + h * z)
				if solid[c] == 0 or used[c] != 0:
					continue
				var x1 := x
				while x1 + 1 < w and _free(solid, used, w, h, x1 + 1, y, z):
					x1 += 1
				var y1 := y
				while y1 + 1 < h and _row(solid, used, w, h, x, x1, y1 + 1, z):
					y1 += 1
				var z1 := z
				while z1 + 1 < d and _slab(solid, used, w, h, x, x1, y, y1, z1 + 1):
					z1 += 1
				for cz in range(z, z1 + 1):
					for cy in range(y, y1 + 1):
						for cx in range(x, x1 + 1):
							used[cx + w * (cy + h * cz)] = 1
				out.append([x, y, z, x1, y1, z1])
	return out

static func _free(solid: PackedByteArray, used: PackedByteArray, w: int, h: int, x: int, y: int, z: int) -> bool:
	var c := x + w * (y + h * z)
	return solid[c] != 0 and used[c] == 0

static func _row(solid: PackedByteArray, used: PackedByteArray, w: int, h: int, x0: int, x1: int, y: int, z: int) -> bool:
	for x in range(x0, x1 + 1):
		if not _free(solid, used, w, h, x, y, z):
			return false
	return true

static func _slab(solid: PackedByteArray, used: PackedByteArray, w: int, h: int, x0: int, x1: int, y0: int, y1: int, z: int) -> bool:
	for y in range(y0, y1 + 1):
		if not _row(solid, used, w, h, x0, x1, y, z):
			return false
	return true
