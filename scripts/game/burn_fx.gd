class_name BurnFx
extends RefCounted
## How fire and poison look on whatever they are on (only the look: Fire.tick and the zones do
## the harm). Each surface burns its own way:
##   flesh   flames and a little smoke (the voxels glow and char, see VoxelPart._write_glow)
##   wood    tall flames, embers flying off, dark smoke
##   cloth   quick flames (cloth, hide, fur, leather, hair) and flakes of ash rising
##   metal   a low blue-footed flame, the metal glowing hot, smoke (iron, bronze, gold)
##   stone   a low flame and smoke (bone, stone, gems)
## and takes poison its own way:
##   flesh   green bubbles rising
##   metal   green fumes hissing off it, a few bubbles   (stone the same)
##   wood    soaked in, dripping green                    (cloth the same)

## The surface a voxel kind (shaders/voxel_body.gdshader) burns as.
static func surface_of_kind(k: int) -> String:
	match k:
		0, 9, 10: return "flesh"
		1, 2, 8: return "cloth"
		5: return "wood"
		3, 4: return "metal"
	return "stone"

## The surface a weapon material (data/materials.json) burns as.
static func surface_of_material(mat: String) -> String:
	return surface_of_kind(VoxelPart.kind_of_material(mat))

## An emitter of fire (or poison, `fire` false) for `surface`, under `parent`; the others it
## needs (smoke, embers, ash, fumes, drips) ride on it as children. Null with no screen.
## `size` scales the spread (a part's or a weapon's size).
static func make(parent: Node3D, surface: String, fire: bool, size := 1.0) -> GPUParticles3D:
	var fx: Fx = Fx.current
	if fx == null or fx.headless:
		return null
	var main: GPUParticles3D
	if fire:
		match surface:
			"wood":
				main = fx.emitter("fire", parent, 90, 0.12 * size)
				_extra(fx, main, "embers", 24, 0.1 * size)
				_extra(fx, main, "smoke", 22, 0.09 * size, Color(0.1, 0.09, 0.08, 0.6))
			"cloth":
				main = fx.emitter("fire", parent, 70, 0.1 * size)
				_extra(fx, main, "ash", 22, 0.1 * size)
				_extra(fx, main, "smoke", 16, 0.08 * size, Color(0.16, 0.15, 0.14, 0.5))
			"metal", "stone":
				main = fx.emitter("lowfire", parent, 40, 0.1 * size)
				_extra(fx, main, "smoke", 12, 0.06 * size, Color(0.25, 0.24, 0.23, 0.45))
			_:
				main = fx.emitter("fire", parent, 70, 0.11 * size)
				_extra(fx, main, "smoke", 16, 0.06 * size, Color(0.18, 0.16, 0.15, 0.5))
	else:
		match surface:
			"metal", "stone":
				main = fx.emitter("fumes", parent, 16, 0.08 * size)
				_extra(fx, main, "poison", 12, 0.08 * size)
			"wood", "cloth":
				main = fx.emitter("poison", parent, 20, 0.08 * size)
				_extra(fx, main, "poisondrip", 18, 0.08 * size)
			_:
				main = fx.emitter("poison", parent, 40, 0.09 * size)
	if main:
		main.emitting = true
	return main

static func _extra(fx: Fx, main: GPUParticles3D, kind: String, n: int, r: float, tint := Color(0, 0, 0, 0)) -> void:
	if main == null:
		return
	var e := fx.emitter(kind, main, n, r)
	if e == null:
		return
	if kind == "smoke":
		e.set_meta("smoke", true)
	if tint.a > 0.0:
		var pm: ParticleProcessMaterial = e.process_material
		var g := Gradient.new()
		g.set_color(0, tint)
		g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
	e.emitting = true

## Turns an emitter made by make() (and what rides on it) on or off. When a fire goes out its
## smoke goes on rising a while from what smoulders.
static func set_on(main: GPUParticles3D, on: bool) -> void:
	if main == null or not is_instance_valid(main):
		return
	var was := main.emitting
	main.emitting = on
	for c in main.get_children():
		if c is GPUParticles3D:
			if not on and was and c.has_meta("smoke") and main.is_inside_tree():
				var ccr := weakref(c)       # (weak: see Weapon's stuck-load timer)
				var mr := weakref(main)
				main.get_tree().create_timer(4.0, false).timeout.connect(func():
					var cc = ccr.get_ref()
					var mn = mr.get_ref()
					if cc and mn and not mn.emitting:
						cc.emitting = false)
				continue
			c.emitting = on
