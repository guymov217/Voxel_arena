extends CanvasLayer
## The game's opening: the picture the boot splash shows (art/splash.png: the emblem over the logo on
## the menus' dark brown) taken up as the first thing the game draws and brought to life for two
## seconds and a half. The swords strike (the emblem flares and swells, a warm light and a ring go
## out, sparks fly, a clang), a gleam runs across the logo, embers drift up, and the whole picture
## creeps in a little. Its first frame is the boot splash's own, so the two join without a seam.
##
## Then `covered` is emitted and the picture holds still: the one who waits for it builds the menu
## behind it (a heavy build that stalls the frames, which a still picture hides), and when that
## returns the picture fades off the menu and is gone. Any key, click or button brings the moment
## forward. main.gd plays it for a player's start only: not under the tests or probes, not headless,
## not with `-- --no-intro` or WRECKSMITH_NO_INTRO set.

signal covered

const SIZE := Vector2(1920.0, 1080.0)   # the pictures' size: the stage is this, fitted into the window
const EDGE := Color(0.0784314, 0.0509804, 0.0313725)   # boot_splash/bg_color: the bars round the picture
## Where the pieces are in the pictures (tools/make_app_icon.py prints them; tests/test_intro.gd holds them to the files).
const EMBLEM_CENTRE := Vector2(960.0, 291.0)
const LOGO_BOX := Rect2(482.0, 479.0, 955.0, 459.0)
const CLASH := 0.35        # the swords strike, seconds from the start
const GLEAM_FROM := 0.7    # the gleam starts across the logo ...
const GLEAM_TIME := 1.0    # ... and takes this long
const HOLD := 2.4          # the picture is whole and still: `covered`
const FADE := 0.55         # and then it fades off what was built behind it
const PUSH := 0.035        # the picture grows by this much ...
const PUSH_TIME := 3.2     # ... over this long
const MAX_STEP := 0.1      # a frame the loading made long counts for no more than this, so the beats are not skipped
const FADE_STEP := 0.034   # and the fade, which starts right after the menu's build has stalled the frames, for less

var _t := 0.0
var _clashed := false
var _covered := false
var _fade := -1.0
var _root: Control
var _stage: Control
var _flash: TextureRect
var _bloom: TextureRect
var _gleam: ShaderMaterial
var _ring: Ring
var _sparks: CPUParticles2D


## A ring of light going out from the swords.
class Ring extends Control:
	var at := Vector2.ZERO
	var progress := -1.0

	func _draw() -> void:
		if progress < 0.0 or progress >= 1.0:
			return
		var e := 1.0 - pow(1.0 - progress, 3.0)
		var fade := 1.0 - progress
		draw_arc(at, 46.0 + 300.0 * e, 0.0, TAU, 128, Color(1.0, 0.84, 0.52, 0.7 * fade), 2.0 + 6.0 * fade, true)


## A player's start gets it; the tests and probes (which main.gd sends elsewhere), a headless run and
## the switches below do not.
static func wanted(args: PackedStringArray, display := "") -> bool:
	if display == "":
		display = DisplayServer.get_name()
	return display != "headless" and not args.has("--no-intro") and OS.get_environment("WRECKSMITH_NO_INTRO") == ""


## How much the 1920 x 1080 pictures are scaled to fill a window of this size without cropping.
static func fit_scale(window: Vector2) -> float:
	return minf(window.x / SIZE.x, window.y / SIZE.y)


func _ready() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # a click is the player's skip, not a press on what is behind
	add_child(_root)
	var bars := ColorRect.new()
	bars.color = EDGE
	bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bars)
	_stage = Control.new()
	_stage.size = SIZE
	_stage.pivot_offset = SIZE / 2.0
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stage)
	_stage.add_child(_picture("res://art/splash.png"))
	# The embers go under the light, the flash and the gleam, the ring and the sparks over them.
	_stage.add_child(_embers())
	_bloom = _glow()
	_stage.add_child(_bloom)
	_flash = _picture("res://art/intro/emblem.png")
	_flash.material = _additive()
	_flash.pivot_offset = EMBLEM_CENTRE
	_flash.modulate = Color(1.0, 0.86, 0.6, 0.0)
	_stage.add_child(_flash)
	var logo := _picture("res://art/intro/logo.png")
	_gleam = ShaderMaterial.new()
	_gleam.shader = load("res://shaders/intro_gleam.gdshader")
	_gleam.set_shader_parameter("box", Vector4(LOGO_BOX.position.x / SIZE.x, LOGO_BOX.position.y / SIZE.y, LOGO_BOX.end.x / SIZE.x, LOGO_BOX.end.y / SIZE.y))
	_gleam.set_shader_parameter("sweep", -0.3)
	logo.material = _gleam
	_stage.add_child(logo)
	_ring = Ring.new()
	_ring.size = SIZE
	_ring.at = EMBLEM_CENTRE
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.material = _additive()
	_stage.add_child(_ring)
	_sparks = _burst()
	_stage.add_child(_sparks)
	_fit()


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_STEP)
	_t += dt
	_fit()
	if not _clashed and _t >= CLASH:
		_clashed = true
		_sparks.emitting = true
		Sfx.ui("clang", 0.45)
	if _clashed:
		var since := _t - CLASH
		_flash.modulate.a = 0.9 * exp(-since * 5.0)
		_flash.scale = Vector2.ONE * (1.0 + 0.09 * (1.0 - exp(-since * 12.0)))   # the flare swells as it dies
		_bloom.modulate.a = 0.6 * exp(-since * 3.6)
		_bloom.scale = Vector2.ONE * (0.55 + 0.7 * (1.0 - exp(-since * 4.0)))
		_ring.progress = since / 0.8
		_ring.queue_redraw()
	var g := clampf((_t - GLEAM_FROM) / GLEAM_TIME, 0.0, 1.0)
	_gleam.set_shader_parameter("sweep", lerpf(-0.3, 1.3, g * g * (3.0 - 2.0 * g)))
	if _fade >= 0.0:
		_fade += minf(delta, FADE_STEP)
		var a := 1.0 - clampf(_fade / FADE, 0.0, 1.0)
		_root.modulate.a = a * a * (3.0 - 2.0 * a)
		if _fade >= FADE:
			queue_free()
	elif _t >= HOLD:
		_cover()


func _input(event: InputEvent) -> void:
	if _covered:
		return
	var press := false
	if event is InputEventKey:
		press = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventJoypadButton:
		press = event.pressed
	if press:
		get_viewport().set_input_as_handled()
		_cover()


## The picture is whole: whoever waits builds what follows (the menu) behind it, and it fades off that.
func _cover() -> void:
	if _covered:
		return
	_covered = true
	covered.emit()
	_fade = 0.0


## The pictures fitted into the window, and creeping in a little over their time.
func _fit() -> void:
	var window := get_viewport().get_visible_rect().size
	var grow := 1.0 + PUSH * (1.0 - pow(1.0 - clampf(_t / PUSH_TIME, 0.0, 1.0), 3.0))
	_stage.scale = Vector2.ONE * fit_scale(window) * grow
	_stage.position = window / 2.0 - SIZE / 2.0


func _picture(path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.size = SIZE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## A soft warm light round the swords, dark until they strike.
func _glow() -> TextureRect:
	var tex := GradientTexture2D.new()
	tex.gradient = _ramp([[0.0, Color(1.0, 0.82, 0.5, 0.95)], [0.3, Color(1.0, 0.58, 0.22, 0.4)], [1.0, Color(1.0, 0.4, 0.1, 0.0)]])
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 512
	tex.height = 512
	var tr := TextureRect.new()
	tr.texture = tex
	tr.size = Vector2(1300.0, 1300.0)
	tr.position = EMBLEM_CENTRE - tr.size / 2.0
	tr.pivot_offset = tr.size / 2.0
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.material = _additive()
	tr.modulate.a = 0.0
	return tr


func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colours := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colours.append(s[1])
	g.offsets = offsets
	g.colors = colours
	return g


## The shower of sparks where the swords strike (let go at CLASH).
func _burst() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = EMBLEM_CENTRE
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 90
	p.lifetime = 1.15
	p.local_coords = true
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.initial_velocity_min = 320.0
	p.initial_velocity_max = 980.0
	p.gravity = Vector2(0.0, 1300.0)
	p.damping_min = 30.0
	p.damping_max = 100.0
	p.scale_amount_min = 5.0       # voxel-sized: the game is made of squares
	p.scale_amount_max = 12.0
	p.color_ramp = _ramp([[0.0, Color(1.0, 0.96, 0.8, 1.0)], [0.3, Color(1.0, 0.7, 0.25, 1.0)], [1.0, Color(0.9, 0.25, 0.05, 0.0)]])
	p.material = _additive()
	return p


## Embers drifting up over the whole picture, from nothing at the start.
func _embers() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(960.0, 790.0)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(920.0, 300.0)
	p.amount = 110
	p.lifetime = 3.2
	p.local_coords = true
	p.direction = Vector2(0.0, -1.0)
	p.spread = 24.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 170.0
	p.gravity = Vector2(8.0, -20.0)
	p.scale_amount_min = 3.5
	p.scale_amount_max = 8.0
	p.color_ramp = _ramp([[0.0, Color(1.0, 0.62, 0.2, 0.0)], [0.12, Color(1.0, 0.76, 0.34, 0.95)], [0.7, Color(1.0, 0.52, 0.16, 0.6)], [1.0, Color(0.8, 0.2, 0.05, 0.0)]])
	p.material = _additive()
	return p
