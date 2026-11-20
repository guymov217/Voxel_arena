extends Node
## The game's opening (scripts/ui/intro.gd): when it plays, that its first picture is the boot splash's
## own, the order of its beats, that it hands over once and fades away, and that a key brings the
## hand-over forward. (What it looks like is seen with `--write-movie`; these hold what it does.)

var t
const Intro := preload("res://scripts/ui/intro.gd")

## Frames at sixty a second, the way a window gives them.
func _drive(intro, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		intro._process(1.0 / 60.0)
		left -= 1.0 / 60.0

func _opening():
	var intro = Intro.new()
	add_child(intro)
	intro.set_process(false)     # the test turns the frames by hand
	return intro

func test_a_player_gets_it_and_the_tests_and_headless_runs_do_not() -> void:
	t.check(Intro.wanted(PackedStringArray([]), "windows"), "a player's start plays it")
	t.check(not Intro.wanted(PackedStringArray([]), "headless"), "not headless")
	t.check(not Intro.wanted(PackedStringArray(["--no-intro"]), "windows"), "-- --no-intro turns it off")
	OS.set_environment("WRECKSMITH_NO_INTRO", "1")
	t.check(not Intro.wanted(PackedStringArray([]), "windows"), "so does WRECKSMITH_NO_INTRO")
	OS.unset_environment("WRECKSMITH_NO_INTRO")
	t.check(not Intro.wanted(OS.get_cmdline_user_args()), "and this run, headless, does not get it")

func test_its_first_picture_is_the_boot_splashs_own() -> void:
	var splash: String = ProjectSettings.get_setting("application/boot_splash/image")
	var intro = _opening()
	var base: TextureRect = intro._stage.get_child(0)
	t.eq(base.texture.resource_path, splash, "the picture it starts from is the boot splash's file")
	t.eq(base.size, Intro.SIZE, "at the file's size")
	t.eq(intro._root.get_child(0).color, Color(ProjectSettings.get_setting("application/boot_splash/bg_color")), "and the bars round it are the boot splash's colour")
	t.eq(intro._flash.modulate.a, 0.0, "nothing is lit yet: the emblem is not flaring")
	t.check(float(intro._gleam.get_shader_parameter("sweep")) < 0.0, "the gleam is off the logo")
	t.check(intro._ring.progress < 0.0, "there is no ring")
	var window: Vector2 = intro.get_viewport().get_visible_rect().size
	t.check(is_equal_approx(intro._stage.scale.x, Intro.fit_scale(window)), "it fills the window as the boot splash does, no more")

func test_the_picture_is_fitted_into_any_window_without_cropping() -> void:
	t.check(is_equal_approx(Intro.fit_scale(Vector2(1920, 1080)), 1.0), "a 1920 x 1080 window shows it as it is")
	t.check(is_equal_approx(Intro.fit_scale(Vector2(1600, 900)), 1600.0 / 1920.0), "a smaller one scales it down")
	t.check(is_equal_approx(Intro.fit_scale(Vector2(2560, 1080)), 1.0), "a wide window fits its height, with bars at the sides")
	t.check(is_equal_approx(Intro.fit_scale(Vector2(1920, 1440)), 1.0), "a tall one fits its width")

func test_the_beats_come_in_order_and_it_hands_over_once_and_goes() -> void:
	var intro = _opening()
	var fired := [0]
	intro.covered.connect(func(): fired[0] += 1)
	_drive(intro, Intro.CLASH - 0.05)
	t.check(not intro._clashed and intro._flash.modulate.a == 0.0, "before the swords strike nothing flares")
	_drive(intro, 0.1)
	t.check(intro._clashed and intro._flash.modulate.a > 0.5, "the swords strike and the emblem flares")
	t.check(intro._bloom.modulate.a > 0.3 and intro._sparks.emitting, "a warm light and a shower of sparks go out")
	t.check(intro._ring.progress >= 0.0 and intro._ring.progress < 1.0, "a ring goes out")
	_drive(intro, 0.7)
	t.check(intro._flash.modulate.a < 0.1 and intro._bloom.modulate.a < 0.1, "the flare and the light die away")
	var mid := float(intro._gleam.get_shader_parameter("sweep"))
	t.check(mid > 0.0 and mid < 1.0, "the gleam is on its way across the logo (%.2f)" % mid)
	_drive(intro, Intro.GLEAM_FROM + Intro.GLEAM_TIME - intro._t + 0.05)
	t.check(float(intro._gleam.get_shader_parameter("sweep")) > 1.2, "and has run off its far end")
	t.eq(fired[0], 0, "it has not handed over before its time")
	_drive(intro, Intro.HOLD - intro._t + 0.05)
	t.eq(fired[0], 1, "it hands over when the picture is whole")
	var held: float = intro._root.modulate.a
	_drive(intro, Intro.FADE / 2.0)
	t.check(intro._root.modulate.a < held and not intro.is_queued_for_deletion(), "then it fades")
	_drive(intro, Intro.FADE)
	t.eq(fired[0], 1, "and hands over no second time")
	t.check(intro.is_queued_for_deletion(), "and is gone")

func test_a_long_frame_while_loading_does_not_swallow_the_beats() -> void:
	var intro = _opening()
	intro._process(1.5)        # the first frame after the game loaded
	t.check(intro._t <= Intro.MAX_STEP + 0.0001 and not intro._clashed, "it counts for no more than a short frame")

func test_a_key_a_click_or_a_button_brings_the_hand_over_forward() -> void:
	var intro = _opening()
	var fired := [0]
	intro.covered.connect(func(): fired[0] += 1)
	_drive(intro, 0.2)
	var held := InputEventKey.new()
	held.keycode = KEY_SPACE
	held.pressed = true
	held.echo = true
	intro._input(held)
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	up.pressed = false
	intro._input(up)
	t.eq(fired[0], 0, "a key held down or let go does not skip it")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	intro._input(key)
	t.eq(fired[0], 1, "a key pressed hands over at once")
	intro._input(key)
	t.eq(fired[0], 1, "and a second does nothing")
	for ev in [InputEventMouseButton.new(), InputEventJoypadButton.new()]:
		var other = _opening()
		var n := [0]
		other.covered.connect(func(): n[0] += 1)
		ev.pressed = true
		other._input(ev)
		t.eq(n[0], 1, "%s skips it too" % ev.get_class())

func test_the_pictures_are_there_and_the_pieces_are_where_the_code_says() -> void:
	# (The picture files themselves, not the imported copies: the pieces' places are read off their pixels.)
	for f in ["splash", "intro/emblem", "intro/logo"]:
		var im := Image.load_from_file(ProjectSettings.globalize_path("res://art/%s.png" % f))
		t.check(im != null and Vector2(im.get_size()) == Intro.SIZE, "art/%s.png is 1920 x 1080" % f)
	var em := Image.load_from_file(ProjectSettings.globalize_path("res://art/intro/emblem.png")).get_used_rect()
	t.check(Vector2(em.get_center()).distance_to(Intro.EMBLEM_CENTRE) <= 1.5, "the emblem's centre is where EMBLEM_CENTRE says (%s)" % str(em.get_center()))
	var lg := Image.load_from_file(ProjectSettings.globalize_path("res://art/intro/logo.png")).get_used_rect()
	t.check(absf(lg.position.x - Intro.LOGO_BOX.position.x) <= 1.0 and absf(lg.position.y - Intro.LOGO_BOX.position.y) <= 1.0 \
			and absf(lg.size.x - Intro.LOGO_BOX.size.x) <= 1.0 and absf(lg.size.y - Intro.LOGO_BOX.size.y) <= 1.0, "the logo's box is where LOGO_BOX says (%s)" % str(lg))
	t.check(em.end.y < lg.position.y, "the emblem is over the logo")

func test_a_player_start_goes_through_main_gd() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	t.check(src.contains("intro_script.wanted(args)") and src.contains("await intro.covered"), "main.gd plays it and waits for its hand-over")
	t.check(src.find("args.has(\"--probe\")") < src.find("intro_script"), "after the test and probe branches, which return first")
