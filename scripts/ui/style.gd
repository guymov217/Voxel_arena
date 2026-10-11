class_name UIStyle
## The look of the menus (the web game's dark leather and bronze).

const BG := Color(0.08, 0.06, 0.045, 0.94)
const PANEL := Color(0.13, 0.1, 0.075, 0.97)
const BRONZE := Color(0.79, 0.64, 0.35)
const BRONZE_DARK := Color(0.45, 0.32, 0.16)
const TEXT := Color(0.95, 0.9, 0.82)
const MUTED := Color(0.7, 0.64, 0.55)
const RED := Color(0.66, 0.25, 0.16)

static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.17, 0.13, 0.095)
	btn.border_color = BRONZE_DARK
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(8)
	btn.content_margin_left = 16; btn.content_margin_right = 16; btn.content_margin_top = 10; btn.content_margin_bottom = 10
	var hov := btn.duplicate()
	hov.bg_color = Color(0.24, 0.18, 0.12)
	hov.border_color = BRONZE
	var prs := btn.duplicate()
	prs.bg_color = Color(0.34, 0.24, 0.13)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("focus", "Button", hov)
	var dis := btn.duplicate()
	dis.bg_color = Color(0.12, 0.1, 0.08)
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.85))
	t.set_color("font_disabled_color", "Button", MUTED * Color(1, 1, 1, 0.6))
	t.set_color("font_color", "Label", TEXT)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = BRONZE_DARK
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(14)
	panel.content_margin_left = 28; panel.content_margin_right = 28; panel.content_margin_top = 22; panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0.1, 0.08, 0.06)
	edit.border_color = BRONZE_DARK
	edit.set_border_width_all(1)
	edit.set_corner_radius_all(6)
	edit.content_margin_left = 10; edit.content_margin_right = 10; edit.content_margin_top = 6; edit.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("normal", "OptionButton", btn)
	t.set_stylebox("hover", "OptionButton", hov)
	t.set_stylebox("pressed", "OptionButton", prs)
	t.set_color("font_color", "OptionButton", TEXT)
	_theme = t
	return t

static func title(text: String, size := 44) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", BRONZE)
	return l

static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	if primary:
		var s := StyleBoxFlat.new()
		s.bg_color = RED
		s.border_color = Color(0.85, 0.45, 0.3)
		s.set_border_width_all(1)
		s.set_corner_radius_all(8)
		s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 12; s.content_margin_bottom = 12
		b.add_theme_stylebox_override("normal", s)
		var h := s.duplicate()
		h.bg_color = RED.lightened(0.15)
		b.add_theme_stylebox_override("hover", h)
	return b

const GOLD := Color(0.88, 0.71, 0.38)
static var _serif: FontVariation

## A Roman capital face (whatever serif the system has), spaced out like an inscription.
static func serif(spacing := 2) -> Font:
	if _serif == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Times New Roman", "Liberation Serif", "DejaVu Serif", "Serif"])
		sf.font_weight = 700
		_serif = FontVariation.new()
		_serif.base_font = sf
	var v := FontVariation.new()
	v.base_font = _serif.base_font
	v.spacing_glyph = spacing
	return v

static func _plate(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 22; s.content_margin_right = 22; s.content_margin_top = 12; s.content_margin_bottom = 12
	return s

## The title screen's buttons: dark stone plates framed in gold; the first one is gilded and
## marked with a diamond, the others get the diamond while the mouse is on them.
static func menu_button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	var cap := text.to_upper()
	b.text = ("◆   " + cap) if primary else cap
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(420, 56)
	b.add_theme_font_override("font", serif(3))
	b.add_theme_font_size_override("font_size", 22)
	var normal := _plate(Color(0.42, 0.29, 0.11, 0.95) if primary else Color(0.075, 0.062, 0.05, 0.9), GOLD if primary else Color(0.55, 0.42, 0.22), 2)
	var hover := _plate(Color(0.52, 0.37, 0.14, 0.97) if primary else Color(0.16, 0.12, 0.08, 0.94), Color(1.0, 0.84, 0.5), 2)
	var press := _plate(Color(0.3, 0.2, 0.08, 0.97), GOLD, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", press)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78) if primary else Color(0.93, 0.86, 0.72))
	b.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.85))
	b.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02))
	b.add_theme_constant_override("outline_size", 3)
	if not primary:
		b.mouse_entered.connect(func(): b.text = "◆   " + cap)
		b.mouse_exited.connect(func(): b.text = cap)
	return b
