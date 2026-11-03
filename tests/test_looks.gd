extends Node
## The arena's materials and life (drawing only): the time of day and its light, shafts of sun
## through the velarium, Rome beyond the walls, what the fights left on the sand; the props as big
## as they were; the beasts' coats and wet noses; bots' faces that have lived; sweat and sand on a
## body. None of it touches what the fight works out: the walls, the ground, every voxel, blood
## and breath stay as they were.

var t

const PROPS := {
	"brazier": [Vector3(-0.4, 0.0, -0.4), Vector3(0.4, 1.55, 0.4)],
	"gate_door": [Vector3(-0.25, 0.0, 0.0), Vector3(0.25, 2.4, 2.6)],
	"ludus_gate": [Vector3(-2.05, 0.0, -0.6), Vector3(2.05, 4.4, 0.75)],
	"crate": [Vector3(-0.32, 0.0, -0.32), Vector3(0.33, 0.6, 0.33)],
	"weapon_rack": [Vector3(-1.0, 0.0, -0.15), Vector3(1.0, 2.0, 0.2)],
	"sign_post": [Vector3(-0.5, 0.0, -0.1), Vector3(0.5, 2.2, 0.05)],
	"target": [Vector3(-0.5, -1.5, -0.07), Vector3(0.5, 0.5, 0.38)],
	"smithy": [Vector3(-1.45, 0.0, -0.65), Vector3(1.45, 3.0, 0.5)],
	"market_stall": [Vector3(-1.3, 0.0, -0.7), Vector3(1.3, 2.3, 0.95)],
	"notice_board": [Vector3(-0.95, 0.0, -0.1), Vector3(0.95, 2.1, 0.15)],
	"physician": [Vector3(-0.9, 0.0, -0.4), Vector3(0.9, 1.65, 0.35)],
}

func _arena(sky := "noon") -> Arena:
	var ar := Arena.new()
	add_child(ar)
	ar.build("colosseum", true, sky)
	ar.set_process(false)
	return ar

## What a man can touch in the arena: every collision shape, where it is and how big.
func _solids(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		var size := ""
		if cs.shape is BoxShape3D:
			size = str((cs.shape as BoxShape3D).size.snapped(Vector3.ONE * 0.001))
		out.append("%s %s %s" % [str(cs.global_transform.origin.snapped(Vector3.ONE * 0.001)), str(cs.global_transform.basis.get_euler().snapped(Vector3.ONE * 0.001)), size])
	out.sort()
	return out

func _shafts(ar: Arena) -> int:
	var n := 0
	var sh: Shader = load("res://shaders/light_shaft.gdshader")
	for c in ar.get_children():
		if c is MeshInstance3D and c.material_override is ShaderMaterial and (c.material_override as ShaderMaterial).shader == sh:
			t.eq((c as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "a shaft of sun casts no shadow")
			n += 1
	return n

## The time of day a bout is fought under: the guests are told it and it is made safe on arrival;
## the yard and the training ground always at noon; picking one leaves the game's own dice alone.
func test_the_time_of_day_is_picked_and_made_safe() -> void:
	t.eq(Arena.clean_sky("evening"), "evening", "a time of day as sent")
	t.eq(Arena.clean_sky("midnight"), "noon", "one it does not know is noon")
	t.eq(Arena.clean_sky(5), "noon", "not a word: noon")
	t.eq(Arena.clean_sky(null), "noon", "nothing: noon")
	t.eq(Arena.pick_sky("yard"), "noon", "the yard at noon")
	t.eq(Arena.pick_sky("training"), "noon", "the training ground at noon")
	seed(77)
	var a := randi()
	seed(77)
	var seen := {}
	for i in 400:
		seen[Arena.pick_sky("campaign")] = true
	t.eq(randi(), a, "picking leaves the game's own dice where they were")
	t.eq(seen.size(), Arena.SKIES.size(), "every time of day comes up (%s)" % [seen.keys()])

## Each time of day lights the arena its own way: late in the day the sun low and gold; overcast
## the sun dim behind the cloud, its disc hidden; at dusk the sun down behind the stands and the
## torches brighter; by day (not overcast, not dusk) shafts of sun through the velarium. The walls,
## the ground and everything a man can touch the same under every sky.
func test_each_time_of_day_has_its_own_light_and_the_same_walls() -> void:
	var q := str(Save.get_value("settings", {}).get("quality", "high")) if Save else "high"
	var noon := _arena("noon")
	var solid := _solids(noon)
	t.check(solid.size() > 30, "the walls and the ground are there (%d)" % solid.size())
	var shafts := _shafts(noon)
	if q != "low":
		t.check(shafts >= 3, "at noon shafts of sun through the velarium (%d)" % shafts)
	for sky in ["golden", "overcast", "evening"]:
		var ar := _arena(sky)
		t.eq(_solids(ar), solid, "%s: the same walls and ground" % sky)
		var skym := (ar.env.sky.sky_material as ShaderMaterial)
		match sky:
			"golden":
				t.check(ar.sun.rotation.x > noon.sun.rotation.x + 0.1, "late in the day the sun lower")
				t.check(ar.sun.light_color.b < noon.sun.light_color.b - 0.1, "and more gold")
				if q != "low":
					t.check(_shafts(ar) >= 3, "its shafts too")
			"overcast":
				t.check(ar.sun.light_energy < noon.sun.light_energy * 0.6, "the sun dim behind the cloud")
				t.check(float(skym.get_shader_parameter("sun_disc")) < 0.5, "its disc hidden")
				t.check(float(skym.get_shader_parameter("cover")) > 0.7, "the sky covered")
				t.eq(_shafts(ar), 0, "no shafts of sun")
			"evening":
				t.check(ar.sun.rotation.x > -0.2, "the sun down at the stands' rim")
				t.check(ar.torch_base > 2.0, "the torches lit up (%.1f)" % ar.torch_base)
				t.eq(_shafts(ar), 0, "no shafts of sun")
		ar.free()
	noon.free()

## Whatever the sky, the fight's own dice come out the same once the arena is built: nothing the
## looks draw (embers, the dust in the sun's shafts: specks of a shader, no particle system, which
## Godot seeds from those dice) takes a number from them.
func test_the_sky_leaves_the_fights_dice_alone() -> void:
	var after := []
	for sky in Arena.SKIES:
		seed(3)
		var ar := _arena(sky)
		after.append(randi())
		ar.free()
	t.check(after.min() == after.max(), "the same dice after every sky (%s)" % [after])

## Rome beyond the arena and what the fights left on the sand are drawing only: nothing in either
## to stand on or trip over, no shadow from the city.
func test_rome_and_the_litter_are_only_drawn() -> void:
	var ar := _arena()
	var city := ar.get_node_or_null("Skyline") as GeometryInstance3D
	t.check(city != null, "Rome round the arena")
	if city:
		t.eq(city.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "casting no shadow")
		t.eq(city.find_children("*", "CollisionObject3D", true, false).size(), 0, "nothing in it to touch")
	var lit := ar.get_node_or_null("Litter") as GeometryInstance3D
	t.check(lit != null, "arrows, splinters, bones and straw by the wall")
	if lit:
		t.eq(lit.find_children("*", "CollisionObject3D", true, false).size(), 0, "nothing in it to trip on")
	ar.free()

## The props as big as they were: only their colours changed (the grain in the wood, the rust, the
## green on bronze), so the box that stops a man is the size it was.
func test_the_props_keep_their_size() -> void:
	for nm in PROPS:
		var n := VoxelArt.make(nm)
		t.check(n != null, nm + " is there")
		if n == null:
			continue
		var box := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var ab: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()
			box = ab if first else box.merge(ab)
			first = false
		var lo: Vector3 = PROPS[nm][0]
		var hi: Vector3 = PROPS[nm][1]
		t.check(box.position.distance_to(lo) < 0.005 and box.end.distance_to(hi) < 0.005, "%s as big as it was (%s..%s)" % [nm, box.position, box.end])
		n.free()

## A beast's look: every voxel where it was, flesh and bone as they were; its coat and mane in
## colour only; the dark at the very front of a lion's head (nose and lips) wet.
func test_beasts_coats_and_wet_noses() -> void:
	for sp in ["lion", "wolf", "boar", "goat", "bear", "crocodile"]:
		for d in Data.beasts[sp].parts:
			var vox := []
			for v in d.voxels:
				vox.append([v[0], v[1], v[2], Color.hex(int(v[3]) << 8 | 0xff), v[4]])
			var out := BeastStyle.style_part(sp, str(d.name), d.get("grid", [1, 1, 1]), vox)
			var same := out.size() == vox.size()
			for i in mini(out.size(), vox.size()):
				if out[i][0] != vox[i][0] or out[i][1] != vox[i][1] or out[i][2] != vox[i][2] or out[i][4] != vox[i][4]:
					same = false
			t.check(same, "%s %s: every voxel where it was" % [sp, d.name])
	var wet := 0
	for d in Data.beasts.lion.parts:
		if str(d.name) != "beastHead":
			continue
		var vox := []
		for v in d.voxels:
			vox.append([v[0], v[1], v[2], Color.hex(int(v[3]) << 8 | 0xff), v[4]])
		for v in BeastStyle.style_part("lion", "beastHead", d.grid, vox):
			if int(v[5]) == 7 and int(v[2]) >= int(d.grid[2]) - 2:
				wet += 1
	t.check(wet >= 4, "the lion's nose and lips wet (%d voxels)" % wet)

## A bot's face that has lived: stubble, a scar, heavy brows, each on his face's grid; not on the
## editor's list (a player's face is his own choosing).
func test_bots_faces_have_lived() -> void:
	for id in ["bot_stubble", "bot_scar_cheek", "bot_scar_lip", "bot_brows_thick", "bot_unibrow"]:
		var marks := Physique.face_marks(id)
		t.check(not marks.is_empty(), id + " paints something")
		var inside := true
		for mk in marks:
			if int(mk[0]) < 0 or int(mk[0]) > 9 or int(mk[1]) < 0 or int(mk[1]) > 9:
				inside = false
		t.check(inside, id + " on the face")
		t.check(not Physique.FACES.has(id), id + " not on the editor's list")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "Scarred", "loadout": {"main": "", "off": ""}, "team": 1, "pos": Vector3(2, 0, 2), "yaw": PI})
	var f: Fighter = e.f
	f.face_ids = ["bot_scar_cheek"]
	Physique._faces(f)
	var head: VoxelPart = f.head
	var at := -1
	for i in head.fx.size():
		if head.fz[i] == head.grid.z - 1 and head.fx[i] == 8 and head.fy[i] == 4:
			at = i
	t.check(at >= 0 and head.colors[at] == VoxelPart.SCAR, "the scar across his cheek")
	m.queue_free()

## Sweat as he tires (and it stays a while after), sand on him where he went down: his look only;
## his breath, his blood and every voxel as they were.
func test_sweat_and_sand_are_only_on_his_look() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var f: Fighter = m.me.f
	Physique.live(f, 1.0 / 60.0)
	var life: Dictionary = f.head.get_meta("life")
	t.check(float(life.get("sweat", 0.0)) < 0.05, "fresh, dry")
	f.stamina = 0.0
	for i in 900:
		Physique.live(f, 1.0 / 60.0)
	t.eq(f.stamina, 0.0, "living his look leaves his breath alone")
	var wet := float(life.get("sweat", 0.0))
	t.check(wet > 0.5, "out of breath, he sweats (%.2f)" % wet)
	f.stamina = 100.0
	for i in 120:
		Physique.live(f, 1.0 / 60.0)
	t.check(float(life.get("sweat", 0.0)) > wet - 0.1 and float(life.get("sweat", 0.0)) < wet, "rested, it dries slowly")
	var p: VoxelPart = f.torso
	var alive := p.alive_count
	var hp := p.hp
	var bleed: float = float(f.get("blood")) if f.get("blood") != null else 0.0
	var front := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var n := p.wound(p.to_local(p.global_position + front * 0.12 * f.S), 0.2 * f.S, "dust")
	t.check(n > 0, "sand on him where he went down (%d voxels)" % n)
	var sandy := 0
	for i in p.colors.size():
		var c: Color = p.colors[i]
		if absf(c.r - VoxelPart.DUST.r) < 0.12 and absf(c.g - VoxelPart.DUST.g) < 0.12 and absf(c.b - VoxelPart.DUST.b) < 0.14:
			sandy += 1
	t.check(sandy > 0, "the colour of the sand (%d)" % sandy)
	t.eq(p.alive_count, alive, "not a voxel lost")
	t.eq(p.hp, hp, "not a scratch")
	t.eq(float(f.get("blood")) if f.get("blood") != null else 0.0, bleed, "not a drop of blood")
	m.queue_free()
