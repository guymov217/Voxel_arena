extends Node
## Data, voxel parts and weapons.

var t

func test_data_is_the_web_games() -> void:
	t.check(Data.presets.has("gladius") and Data.presets.size() >= 35, "weapon presets")
	t.eq(Data.body_parts.size(), 10, "ten body parts")
	t.check(Data.beasts.has("dragon") and Data.beasts.size() >= 24, "beasts")
	var st := Data.stage(4, 1)
	t.check(st.boss, "stage 4 is a boss")
	t.eq(Data.campaign.stages[3].byPlayers["1"].rounds.size(), 3, "three rounds a stage in the web game's tables")
	t.eq(st.rounds.size(), 1, "the campaign plays each stage as one bout")
	t.check(Data.campaign.enemies.has("hoplite"), "enemy types")

func test_greedy_merges_a_full_block_into_one_box() -> void:
	var solid := PackedByteArray()
	solid.resize(4 * 3 * 2)
	solid.fill(1)
	t.eq(Greedy.boxes(4, 3, 2, solid).size(), 1, "one box")
	solid[5] = 0
	t.check(Greedy.boxes(4, 3, 2, solid).size() > 1, "a hole splits it")

func test_weapon_from_design() -> void:
	var w := Weapon.new()
	w.setup(Data.preset("gladius"))
	add_child(w)
	t.check(w.mass > 1.0 and w.mass < 2.5, "gladius weighs about 1.7 kg (%s)" % w.mass)
	var shapes := 0
	for c in w.get_children():
		if c is CollisionShape3D:
			shapes += 1
	t.check(shapes > 2 and shapes < 30, "a handful of merged boxes (%d)" % shapes)
	var n := w.alive_count()
	var idx := w.chip_indices(30, 45.0)
	t.check(idx.size() >= 1, "a hard knock chips")
	w.remove_voxels(idx)
	t.eq(w.alive_count(), n - idx.size(), "voxels gone")
	w.queue_free()
