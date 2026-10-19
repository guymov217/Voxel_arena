extends Node
## The picture's settings: a voxel's corners are shaded where its neighbours shut it in (and
## follow the cuts), the options set the anti-aliasing and the shading, and a weapon's sharp
## voxels are drawn tapered (an edge a wedge, a point a tip).

var t

## A small part built by hand: a 3x3 floor of voxels and one more standing on its middle.
func _part() -> VoxelPart:
	var vox := []
	for x in 3:
		for z in 3:
			vox.append([x, 0, z, Color.WHITE, false, 0])
	vox.append([1, 1, 1, Color.WHITE, false, 0])
	var p := VoxelPart.new()
	add_child(p)
	p.setup(null, {"name": "block", "dims": [1, 1, 1], "grid": [3, 2, 3]}, vox, 1.0, 1.0)
	return p

func _index(p: VoxelPart, x: int, y: int, z: int) -> int:
	for i in p.fx.size():
		if p.fx[i] == x and p.fy[i] == y and p.fz[i] == z:
			return i
	return -1

func test_corners_are_shaded_where_neighbours_shut_them_in() -> void:
	var p := _part()
	# The +y face is face 2 (bits 8..11). A corner voxel of the floor, next to the one standing
	# in the middle: the top of it is shut in on the corner toward the middle.
	var corner := _index(p, 0, 0, 0)
	var top_bits := (p.ao[corner] >> 8) & 15
	t.check(top_bits != 0, "the floor's top darkens toward the block standing by it (%d)" % top_bits)
	# The standing voxel's own top is open sky: no corner of it is shut in.
	var tower := _index(p, 1, 1, 1)
	t.eq((p.ao[tower] >> 8) & 15, 0, "the top of the standing block is open")
	# Its side, against the floor below: the lower corners of that face are shut in.
	t.check((p.ao[tower] & 15) != 0, "the side of the standing block is shaded where it meets the floor")
	# Cut the standing voxel away: the floor's tops open up again.
	p.remove_voxels([tower], false, false)
	t.eq((p.ao[corner] >> 8) & 15, 0, "with it cut away the floor's corner is open again")
	p.restore_voxels([tower])
	t.check(((p.ao[corner] >> 8) & 15) != 0, "and shaded again when it is back")
	p.queue_free()

func test_the_options_set_the_anti_aliasing_and_the_shading() -> void:
	var menu = load("res://scripts/ui/menu.gd")
	var vp := get_tree().root
	menu.apply_picture({"aa": "msaa4", "voxelAO": true})
	t.eq(vp.msaa_3d, Viewport.MSAA_4X, "MSAA 4x by default")
	t.eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "and no blurring FXAA over it")
	t.check(VoxelPart.ao_strength > 0.0, "voxel shading on")
	t.check(float(VoxelPart.body_material().get_shader_parameter("ao_strength")) > 0.0, "and the voxel material shades")
	menu.apply_picture({"aa": "fxaa", "voxelAO": false})
	t.eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "FXAA chosen: no MSAA")
	t.eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "FXAA on")
	t.eq(float(VoxelPart.body_material().get_shader_parameter("ao_strength")), 0.0, "voxel shading off")
	menu.apply_picture({"aa": "smaa"})
	t.eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_SMAA, "SMAA on")
	menu.apply_picture({})
	t.eq(vp.msaa_3d, Viewport.MSAA_4X, "no setting saved: MSAA 4x")

## A blade three voxels wide and one thick, edges on both sides, a point at the top.
func _blade() -> Dictionary:
	var vox := []
	for y in range(0, 6):
		vox.append([-1, y, 0, "steel", "edge"])
		vox.append([0, y, 0, "steel", "blunt"])
		vox.append([1, y, 0, "steel", "edge"])
	vox.append([0, 6, 0, "steel", "point"])
	return {"name": "Test blade", "kind": "weapon", "voxels": vox}

func test_sharp_voxels_are_drawn_tapered() -> void:
	var cells := {}
	for v in _blade().voxels:
		cells[Vector3i(v[0], v[1], v[2])] = v[4]
	# The left edge: narrows toward -x (bit 1), pinched across the blade's thickness (z, bit 8).
	var left := VoxelPart.taper_code(cells, Vector3i(-1, 3, 0))
	t.eq(left & 63, 2, "an edge narrows toward its open side")
	t.eq((left >> 6) & 7, 4, "and is thin across the blade")
	t.eq(left >> 9, 0, "as a wedge, not a tip")
	# The top corner of the edge narrows toward the side and the top.
	t.eq(VoxelPart.taper_code(cells, Vector3i(1, 5, 0)) & 63, 1 | 4, "the corner of the edge toward both its open sides")
	# The point narrows up, pinched both ways: a tip.
	var tip := VoxelPart.taper_code(cells, Vector3i(0, 6, 0))
	t.eq(tip & 63, 4, "the point narrows toward its end")
	t.eq((tip >> 6) & 7, 1 | 4, "pinched across both ways")
	t.eq(tip >> 9, 1, "a tip")
	t.eq(VoxelPart.taper_code(cells, Vector3i(0, 3, 0)), 0, "a blunt voxel is a plain block")
	# A blade two voxels thick: each half narrows toward the face the two share.
	var thick := cells.duplicate()
	for k in cells:
		thick[k + Vector3i(0, 0, 1)] = cells[k]
	var front := VoxelPart.taper_code(thick, Vector3i(-1, 3, 0))
	t.eq(front & 63, 2, "half of a thick edge still faces out")
	t.eq((front >> 6) & 7, 4, "and narrows across the blade")
	t.eq((front >> 10) & 63, 1 << 4, "toward the face it shares with its other half (+z)")
	t.eq((VoxelPart.taper_code(thick, Vector3i(-1, 3, 1)) >> 10) & 63, 1 << 5, "the other half toward -z")
	# Three thick: a block.
	var block := thick.duplicate()
	for k in cells:
		block[k + Vector3i(0, 0, 2)] = cells[k]
	t.eq(VoxelPart.taper_code(block, Vector3i(-1, 3, 1)), 0, "a thick edge stays a block")
	# An edge one voxel wide and thick (a spike on a blade lying flat in x and z): thin the way
	# the weapon is thinnest round it, here y, not the forge's depth.
	var flat := {}
	for x in range(-3, 4):
		for z in range(-3, 1):
			flat[Vector3i(x, 0, z)] = "blunt"
	flat[Vector3i(0, 0, 1)] = "edge"
	t.eq((VoxelPart.taper_code(flat, Vector3i(0, 0, 1)) >> 6) & 7, 2, "thin across the blade's own thickness (y)")
	# The kind still reads back under the taper.
	var c := VoxelPart.kind_data(3, 0, tip)
	var kc := int(floor(c.r * 16.0 + 0.5))
	t.eq(kc % 16, 3, "the kind reads back")
	t.eq(kc / 16, tip, "and the taper with it")

func test_when_the_edge_chips_the_row_behind_is_the_edge() -> void:
	var d := _blade()
	# A second row of edge voxels behind the left edge.
	for v in d.voxels:
		if v[0] == 0 and v[4] == "blunt":
			v[4] = "edge"
	var w := Weapon.new()
	w.setup(d, 1.0)
	w.freeze = true
	add_child(w)
	var mid := -1
	var outer := -1
	for i in w.vox.size():
		if w.vox[i][1] == 3 and w.vox[i][0] == 0:
			mid = i
		if w.vox[i][1] == 3 and w.vox[i][0] == -1:
			outer = i
	t.check(w.taper[outer] != 0, "the outer edge is tapered")
	t.eq(w.taper[mid], 0, "the edge behind it is a block while covered")
	w.remove_voxels([outer])
	t.check(w.taper[mid] != 0, "chipped away, the edge behind it is the edge now")
	# (What it hands the shader: headless, the MultiMesh keeps no data to read back.)
	t.eq(int(floor(w._custom(mid).r * 16.0 + 0.5)) / 16, w.taper[mid], "and is drawn so")
	w.queue_free()
