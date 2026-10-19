extends Node
## The picture's settings: a voxel's corners are shaded where its neighbours shut it in (and
## follow the cuts), and the options set the anti-aliasing and the shading.

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
