extends Node
## The finer looks (drawing only): blood that stays on a blade and dries; a sweep behind a fast
## swing; a face that blinks, winces and breathes; prints in the sand that fade; the colour
## grade; the clouds' shadows drifting over; the cloth over the stands and the bowl in the metal.

var t

func _weapon(name_ := "gladius") -> Weapon:
	var w := Weapon.new()
	w.setup(Data.preset(name_).duplicate(true))
	add_child(w)
	return w

func _at(w: Weapon, i: int) -> Vector3:
	return Vector3(float(w.vox[i][0]), float(w.vox[i][1]), float(w.vox[i][2])) * w.vs

## Blood on a blade where it went in: the voxels round the blow red (in patches: each voxel
## covered or not, never a pink wash) and wet (a gloss in the shader), the grip clean; it dries to
## the brown of old blood and loses its gloss; another blow wets it again. (A voxel's colour and
## shader data as the weapon works them out: a headless game keeps no drawing to read back.)
func test_blood_stays_on_the_blade_and_dries() -> void:
	var w := _weapon()
	var tip := 0
	for i in w.vox.size():
		if _at(w, i).length() > _at(w, tip).length():
			tip = i
	var clean := w._vcolor(tip)
	w.bloody(w.to_global(_at(w, tip)), 0.8)
	t.check(w.bloodied.has(tip), "the voxels where it went in are bloodied")
	var red := w._vcolor(tip)
	t.check(red.r > red.g * 3.0 and red.r > red.b * 3.0 and red.r < 0.6, "dark red (%s, was %s)" % [red, clean])
	t.check(w._custom(tip).g < 0.0, "wet: the shader's gloss on")
	var grip := 0
	var pink := 0
	for i in w.bloodied:
		if w.vox[i][4] == "grip":
			grip += 1
		var c := w._vcolor(i)
		if c.r > 0.55 and c.g > 0.3 and c.g < c.r * 0.8:
			pink += 1
	t.eq(grip, 0, "the grip stays clean")
	t.eq(pink, 0, "no voxel washed pink")
	t.check(w.bloodied.size() * 2 < w.vox.size(), "only round the blow (%d of %d)" % [w.bloodied.size(), w.vox.size()])
	for k in 100:
		w._dry_blood(1.0)
	var dry := w._vcolor(tip)
	t.check(w._custom(tip).g >= 0.0, "dried: no gloss")
	t.check(dry.r < red.r and dry.g > red.g, "and the brown of old blood (%s)" % dry)
	w.bloody(w.to_global(_at(w, tip)), 0.5)
	t.check(w._custom(tip).g < 0.0, "another blow wets it again")
	w.queue_free()

## A fast swing leaves a sweep behind the blade, root to tip, that fades in a moment; a slow one
## leaves none, nor a weapon no one holds (thrown, lying on the sand).
func test_a_fast_swing_leaves_a_sweep_that_fades() -> void:
	var w := _weapon()
	w.holder = self
	var trail = load("res://scripts/fighter/swing_trail.gd").new(w)
	t.check(trail.tip_l.length() > trail.root_l.length() + 0.1, "from the root of the blade to its tip (%.2f, %.2f)" % [trail.root_l.length(), trail.tip_l.length()])
	var dt := 1.0 / 60.0
	var turn := func(a: float): w.vis.global_transform = Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, 1, 0))
	for i in 10:
		turn.call(i * 0.02)
		trail._process(dt)
	t.check(not trail.visible, "a slow swing leaves nothing")
	for i in 6:
		turn.call(0.2 + i * 0.26)
		trail._process(dt)
	t.check(trail.visible and trail.im.get_surface_count() == 1, "a fast one leaves its sweep")
	for i in 12:
		trail._process(dt)
	t.check(not trail.visible and trail.im.get_surface_count() == 0, "gone a moment after")
	w.holder = null
	for i in 6:
		turn.call(2.0 + i * 0.26)
		trail._process(dt)
	t.check(not trail.visible, "a weapon no one holds leaves none")
	trail.free()
	w.queue_free()

## A face alive: a blink shuts the eyes with his eyelids, a blow that hurts screws it up (brows
## down, eyes squeezed, teeth bared), and each comes off again leaving his own face; talking takes
## the grimace's teeth off first; he blinks on his own, winces when the pain leaps, breathes
## (deeper out of breath); a dead man does none of it.
func test_a_face_blinks_winces_and_breathes() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var f: Fighter = m.me.f
	var head: VoxelPart = f.head
	var at := {}
	for i in head.fx.size():
		if head.fz[i] == head.grid.z - 1:
			at[Vector2i(head.fx[i], head.fy[i])] = i
	var before := {}
	for k in at:
		before[k] = head.colors[at[k]]
	var own := func() -> bool:
		for k in at:
			if head.colors[at[k]] != before[k]:
				return false
		return true
	Physique.express(f, true, false)
	var lid: Color = head.get_meta("lid_c", Color(0.5, 0.33, 0.25))
	t.eq(head.colors[at[Vector2i(2, 6)]], lid, "a blink: the eye shut by its lid")
	t.eq(head.colors[at[Vector2i(7, 6)]], lid, "both eyes")
	Physique.express(f, false, false)
	t.check(own.call(), "open again: his own face")
	Physique.express(f, false, true)
	t.eq(head.colors[at[Vector2i(2, 8)]], Physique.DARK, "hurt: the brows down")
	t.eq(head.colors[at[Vector2i(6, 6)]], Physique.DARK, "the eyes squeezed")
	var teeth := 0
	for k in at:
		if head.colors[at[k]] == Physique.WHITE and before[k] != Physique.WHITE:
			teeth += 1
	t.check(teeth > 0, "the teeth bared (%d)" % teeth)
	Physique.talk(f, 2)
	t.eq(head.colors[at[Vector2i(4, 2)]], Physique.MOUTH, "he talks: his mouth open over the grimace")
	Physique.talk(f, 0)
	Physique.express(f, false, true)
	Physique.express(f, false, false)
	t.check(own.call(), "and it all comes off again: his own face")
	# Of itself, every frame.
	var shut := false
	var reopened := false
	for i in 420:
		Physique.live(f, 1.0 / 60.0)
		if int(head.get_meta("expr_state", 0)) & 1:
			shut = true
		elif shut:
			reopened = true
	t.check(shut and reopened, "he blinks on his own and opens his eyes again")
	f.pain = float(f.pain) + 0.3
	Physique.live(f, 1.0 / 60.0)
	t.check(int(head.get_meta("expr_state", 0)) & 2, "pain leaping up screws his face up")
	for i in 60:
		Physique.live(f, 1.0 / 60.0)
	t.eq(int(head.get_meta("expr_state", 0)) & 2, 0, "for a moment")
	var breath := func() -> float:
		var lo := 9.0
		var hi := 0.0
		for i in 300:
			Physique.live(f, 1.0 / 60.0)
			lo = minf(lo, f.torso.draw_scale.z)
			hi = maxf(hi, f.torso.draw_scale.z)
		return hi - lo
	var fresh: float = breath.call()
	t.check(fresh > 0.005, "his chest rises and falls (%.3f)" % fresh)
	f.stamina = 5.0
	var winded: float = breath.call()
	t.check(winded > fresh * 1.5, "deeper out of breath (%.3f)" % winded)
	f.die("wounds")
	Physique.live(f, 1.0 / 60.0)
	t.eq(f.torso.draw_scale, Vector3.ONE, "a dead man does not breathe")
	t.eq(int(head.get_meta("expr_state", 0)), 0, "nor blink nor wince")
	m.queue_free()

## Prints in the sand: a left foot the mirror of the right, the toes at the end he walks toward, a
## heel at the other; each sunk (its normal map leans off the walls of the hollow); a pool of
## their own that keeps the newest, fading as the sand settles until they are gone.
func test_prints_in_the_sand_mirror_sink_and_fade() -> void:
	var r: Image = Fx.print_texture("footR").get_image()
	var l: Image = Fx.print_texture("footL").get_image()
	var w := r.get_width()
	var h := r.get_height()
	var mirrored := true
	for y in h:
		for x in w:
			if absf(r.get_pixel(x, y).a - l.get_pixel(w - 1 - x, y).a) > 0.02:
				mirrored = false
	t.check(mirrored, "the left foot the right one's mirror")
	var runs := 0
	var inside := false
	for x in w:
		var on := false
		for y in range(int(h * 0.8), int(h * 0.94)):
			on = on or r.get_pixel(x, y).a > 0.3
		if on and not inside:
			runs += 1
		inside = on
	t.eq(runs, 5, "five toes at the front")
	t.check(r.get_pixel(w / 2, int(h * 0.19)).a > 0.6, "a heel at the back")
	var n: Image = Fx.print_texture("footR_n").get_image()
	var lean := 0.0
	for y in h:
		for x in w:
			var c := n.get_pixel(x, y)
			lean = maxf(lean, Vector2(c.r - 0.5, c.g - 0.5).length())
	t.check(lean > 0.2, "sunk: its walls lean (%.2f)" % lean)
	var fx := Fx.new(false)
	fx.quality = "high"
	add_child(fx)
	for i in Fx.MAX_PRINTS + 12:
		fx.footprint("footR" if i % 2 else "footL", Vector3(i * 0.01, 0, 0), 0.0, 1.0)
	fx.footprint("peg", Vector3(0, 0, 1), 0.0, 1.0)
	fx.footprint("drag", Vector3(0, 0, 2), 0.4, 1.0, 0.6)
	t.eq(fx.prints.size(), Fx.MAX_PRINTS, "a pool of their own, the oldest going first")
	var last: Decal = fx.prints[-1].d
	t.check(is_instance_valid(last) and last.size.z >= 0.6, "the newest kept (the furrow, as long as it was dragged)")
	var a0 := last.modulate.a
	fx._process(Fx.PRINT_LIFE * 0.8)
	var a1 := last.modulate.a
	t.check(a1 < a0 * 0.7 and a1 > 0.0, "fading as the sand settles (%.2f -> %.2f)" % [a0, a1])
	fx._process(Fx.PRINT_LIFE * 0.3)
	t.eq(fx.prints.size(), 0, "and gone")
	fx.footprint("footR", Vector3.ZERO, 0.0, 1.0)
	fx.clear()
	t.eq(fx.prints.size(), 0, "cleared with the rest")
	fx.quality = "low"
	fx.footprint("footR", Vector3.ZERO, 0.0, 1.0)
	t.eq(fx.prints.size(), 0, "none at the lowest setting")
	fx.free()

## The colour grade: black stays black, white near enough white; the shade a touch cooler, the
## sunlit a touch warmer, the middle tones a little firmer, and never more than a touch; the table
## made once for day and once for night.
func test_the_grade_cools_the_shade_and_warms_the_light() -> void:
	for day in [true, false]:
		var k: Color = Arena.grade(Color.BLACK, day)
		t.check(k.r + k.g + k.b < 0.001, "black stays black (%s)" % k)
		var wh: Color = Arena.grade(Color.WHITE, day)
		t.check(wh.r > 0.99 and wh.g > 0.99 and wh.b > 0.94, "white near enough white (%s)" % wh)
		var d: Color = Arena.grade(Color(0.2, 0.2, 0.2), day)
		t.check(d.b > d.r + 0.005, "the shade a touch cooler (%s)" % d)
		var li: Color = Arena.grade(Color(0.8, 0.8, 0.8), day)
		t.check(li.r > li.b + 0.01, "the light a touch warmer (%s)" % li)
		t.check(d.get_luminance() < 0.2 and li.get_luminance() > 0.8, "the middle tones firmer")
		var most := 0.0
		for c in [Color(0.3, 0.5, 0.2), Color(0.9, 0.4, 0.1), Color(0.1, 0.2, 0.6), Color(0.5, 0.5, 0.5), Color(0.7, 0.62, 0.45)]:
			var g: Color = Arena.grade(c, day)
			most = maxf(most, maxf(absf(g.r - c.r), maxf(absf(g.g - c.g), absf(g.b - c.b))))
		t.check(most < 0.07, "a touch, not a filter (%.3f at most)" % most)
	var lut: ImageTexture3D = Arena.grade_lut(true)
	t.eq(lut.get_width(), 17, "a table 17 a side")
	t.eq(lut.get_depth(), 17, "17 deep")
	t.check(Arena.grade_lut(true) == lut, "made once")

## The clouds' shadows: patches of shade with open sun between, carried by the wind; gone far
## enough, they fade out, come back in from the other side and fade in again.
func test_cloud_shadows_drift_and_come_round_again() -> void:
	var img := Arena.cloud_texture().get_image()
	var shade := 0
	var open := 0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var a := img.get_pixel(x, y).a
			n += 1
			if a > 0.5:
				shade += 1
			elif a < 0.05:
				open += 1
	t.check(shade > n * 0.15 and open > n * 0.25, "patches of shade with open sun between (%d shaded, %d open of %d)" % [shade, open, n])
	var ar := Arena.new()
	ar.set_process(false)
	add_child(ar)
	ar._build_cloud_shadows()
	var p0: Vector3 = ar.cloud_shade.position
	var cover := Arena.shade_over_sand(img, p0)
	t.check(cover > 0.2 and cover < 0.7, "it starts with a cloud's edge across the sand (%.2f in shade)" % cover)
	for i in 60:
		ar._move_clouds(0.1)
	var moved: Vector3 = ar.cloud_shade.position - p0
	t.check(moved.dot(Arena.CLOUD_WIND) > 0.0 and absf(moved.length() - Arena.CLOUD_WIND.length() * 6.0) < 0.01, "carried by the wind (%s)" % moved)
	t.check(absf(ar.cloud_shade.modulate.a - Arena.CLOUD_DARK) < 1e-4, "as dark as a cloud's shade")
	ar.cloud_shade.position = Vector3(Arena.CLOUD_TRAVEL + 1.0, 15.0, 0.0)
	var faded := false
	var back := false
	for i in 200:
		ar._move_clouds(0.1)
		if ar.cloud_shade.modulate.a < 0.01:
			faded = true
		if faded and ar.cloud_shade.position.x < 0.0:
			back = true
	t.check(faded and back, "gone far enough: out, and back in from the other side")
	t.check(absf(ar.cloud_shade.modulate.a - Arena.CLOUD_DARK) < 1e-4, "and dark again")
	ar.free()

## The arena dressed: the velarium's sails over the stands on their masts and the banners hung
## from the arcade, none of it shading the sand; the bowl taken once into a reflection that holds
## the arena and no one in it; and by day the clouds' shadows (above the lowest setting).
func test_the_arena_wears_its_cloth_and_shows_in_metal() -> void:
	var ar := Arena.new()
	add_child(ar)
	ar.build("colosseum", true)
	ar.set_process(false)
	var vel: MeshInstance3D = ar.get_node_or_null("Velarium")
	t.check(vel != null, "the velarium over the stands")
	var banners := 0
	var shading := 0
	for c in ar.get_children():
		if c is GeometryInstance3D and c.material_override is ShaderMaterial and (c.material_override as ShaderMaterial).shader == load("res://shaders/cloth.gdshader"):
			if (c.material_override as ShaderMaterial).get_shader_parameter("hanging"):
				banners += 1
			if (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shading += 1
	t.eq(banners, 8, "eight banners from the arcade")
	t.eq(shading, 0, "and none of the cloth shades the sand")
	var q := str(Save.get_value("settings", {}).get("quality", "high")) if Save else "high"
	var rp: ReflectionProbe = ar.get_node_or_null("Reflections")
	if q == "low":
		t.check(rp == null, "no reflection at the lowest setting")
	else:
		t.check(rp != null and rp.update_mode == ReflectionProbe.UPDATE_ONCE, "the bowl taken once into a reflection")
		t.eq(rp.cull_mask, Arena.STATIC_LAYER, "of the arena alone")
		var sand: VisualInstance3D = ar.get_node("Sand")
		t.check(sand.layers & Arena.STATIC_LAYER, "the sand in it")
		t.check(ar.get_node_or_null("CloudShadows") != null, "by day the clouds' shadows")
	ar.free()

## What a fight's effects are made of is made before the fight (user: the frame rate drops in a
## fight: the first burst of blood, the first wound that dripped, made its material as the blow
## landed and the engine compiled its shader then). Every kind's material, its emitter's (out of
## a sphere, kept: its shader lives as long as one made so does) and its mesh; a blow that throws
## its blood past a part draws nothing of the part anew.
func test_effects_are_made_before_the_fight() -> void:
	Fx._warm = false
	Fx.warm()
	var n := 0
	for kind in Fx.KINDS:
		n += 1
		if not t.check(Fx._process_mats.has(kind) and Fx._sphere_mats.has(kind) and Fx._draw_meshes.has(kind), "%s: its materials and its mesh are made" % kind):
			continue
		var base: ParticleProcessMaterial = Fx._process_mats[kind]
		var sph: ParticleProcessMaterial = Fx._sphere_mats[kind]
		t.check(sph.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_SPHERE and base.emission_shape != ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "%s: an emitter's out of a sphere, a burst's from a point" % kind)
		t.check(is_equal_approx(sph.spread, base.spread) and sph.gravity == base.gravity and is_same(sph.color_ramp, base.color_ramp), "%s: the emitter's is the kind's own otherwise" % kind)
	t.check(n > 20, "every kind (%d)" % n)
	for tx in ["soft", "splat", "ring", "spark", "flame", "print_body", "print_drag", "print_body_n", "print_drag_n"]:
		t.check(Fx._textures.has(tx), "the texture %s is made" % tx)
	# Blood thrown past a part touches none of its voxels: nothing of it is coloured anew.
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var f := w.fighter(Vector3(0, 1.2, 0), 0.0, {}, {})
	var p: VoxelPart = f.torso
	var was := p.colors.duplicate()
	t.eq(p.wound(Vector3(9.0, 9.0, 9.0), 0.05, "blood"), 0, "a spot of blood that lands past the part touches no voxel of it")
	t.check(p.colors == was, "and colours none")
	t.check(p.wound(Vector3(0.0, 0.0, p.half_ext.z), p.vf * p.part_scale * 3.0, "blood") > 0 and p.colors != was, "one that lands on it soaks in")
	w.queue_free()
