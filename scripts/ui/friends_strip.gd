class_name FriendsStrip
extends CanvasLayer
## The host's way to have friends who are not there (Friends, FriendPilot), over every screen of the game while he tries a room
## by himself: three buttons and as many keys. F6 a friend comes in, F7 the newest says goodbye and goes, F8 the newest one's line
## goes at once (a game that crashes, a cable pulled), F9 the friends who come now come over a poor line (120 ms, 3% lost). The
## names of the friends in the room are shown, and nothing else is written: no help, no list of what to try.

const KEYS := {KEY_F6: "add", KEY_F7: "leave", KEY_F8: "drop", KEY_F9: "poor"}

var friends: Friends
var panel: PanelContainer
var row: HBoxContainer
var names_label: Label
var poor_button: Button

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	friends = Friends.new()
	add_child(friends)
	friends.changed.connect(_refresh)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.03, 0.82)
	sb.set_corner_radius_all(6)
	sb.border_color = UIStyle.BRONZE_DARK
	sb.set_border_width_all(1)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var title := UIStyle.label("FRIENDS", 13, UIStyle.GOLD)
	row.add_child(title)
	names_label = UIStyle.label("", 13, UIStyle.TEXT)
	row.add_child(names_label)
	row.add_child(_button("+", "add", "F6"))
	row.add_child(_button("−", "leave", "F7"))
	row.add_child(_button("×", "drop", "F8"))
	poor_button = _button("~", "poor", "F9")
	poor_button.toggle_mode = true
	row.add_child(poor_button)
	_refresh()
	# (Placed once its buttons are in it, for its size to be the one the corner is worked out for.)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

func _button(text: String, what: String, key: String) -> Button:
	var b := UIStyle.button(text, func(): act(what))
	b.name = "Friend_" + what
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 28)
	b.tooltip_text = key
	return b

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.is_echo() and KEYS.has(e.keycode):
		act(String(KEYS[e.keycode]))
		get_viewport().set_input_as_handled()

## What a button or a key does.
func act(what: String) -> void:
	match what:
		"add": friends.add()
		"leave": friends.leave_one()
		"drop": friends.drop_one()
		"poor":
			friends.poor = not friends.poor
	_refresh()

func _refresh() -> void:
	if names_label == null:
		return
	names_label.text = ", ".join(friends.names())
	names_label.visible = friends.count() > 0
	if poor_button:
		poor_button.set_pressed_no_signal(friends.poor)
