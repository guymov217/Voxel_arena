class_name StartVeil
extends CanvasLayer
## The screen a game's start waits behind (`Match.hold`): the men of a room's fight or yard are built, the host's and every guest's, before the map is shown, and the game begins for all
## of them at once (user: "why can't they all be there before the map is shown? that they come in one by one makes the start unequal"). It stays up while the match holds, says how many of the
## men are in (the host's count; a guest says how many he has still to build), takes in every key and click meanwhile (nothing can be done to a world that is asleep, and the pause menu's
## closing would wake it), and fades away when the game begins.

const FADE_S := 0.35        # (the first drawing of the map, whose materials have never been drawn, happens behind the fading veil)

var match_: Match
var _shade: ColorRect
var _centre: CenterContainer
var _count: Label
var _track: ColorRect
var _fill: ColorRect
var _t := 0.0
var _gone := -1.0           # (the time the game began, in this veil's own: -1 while it holds)

func _init(m: Match) -> void:
	match_ = m
	name = "StartVeil"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade = ColorRect.new()
	_shade.color = Color(0.06, 0.045, 0.034)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_centre = CenterContainer.new()
	_centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_centre.add_child(box)
	var title := Label.new()
	title.text = Loc.t("The gladiators gather")
	title.add_theme_font_override("font", UIStyle.serif(3, 700))
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UIStyle.GOLD_LIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_count = Label.new()
	_count.add_theme_font_override("font", UIStyle.body("medium"))
	_count.add_theme_font_size_override("font_size", 22)
	_count.add_theme_color_override("font_color", UIStyle.MUTED)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_count)
	_track = ColorRect.new()
	_track.color = Color(1, 1, 1, 0.09)
	_track.custom_minimum_size = Vector2(360, 4)
	box.add_child(_track)
	_fill = ColorRect.new()
	_fill.color = UIStyle.GOLD
	_track.add_child(_fill)

## What the veil says: how many of the men are in.
static func line_for(p: Vector2i, guest: bool) -> String:
	var total := maxi(p.x, p.y)
	if guest:
		return Loc.t("%d to build") % (p.y - p.x) if p.y > p.x else Loc.t("Waiting for the others")
	return Loc.t("%d of %d in") % [p.x, total]

func _input(_ev: InputEvent) -> void:
	if _gone < 0.0:
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	_t += dt
	if match_ == null or not is_instance_valid(match_) or match_.over:
		queue_free()
		return
	if _gone < 0.0 and not match_.hold:
		_gone = _t
		_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _gone >= 0.0:
		var k := clampf((_t - _gone) / FADE_S, 0.0, 1.0)
		_shade.color.a = 1.0 - k
		_centre.modulate.a = 1.0 - k
		if k >= 1.0:
			queue_free()
		return
	var p := match_.hold_progress()
	_count.text = line_for(p, match_.role == "guest") + ".".repeat(int(_t * 2.0) % 4)
	var total := maxi(p.x, p.y)
	var frac := (float(p.x) / float(total)) if total > 0 and match_.role != "guest" else clampf(_t / 8.0, 0.0, 0.9)
	_fill.size = Vector2(_track.size.x * frac, _track.size.y)
