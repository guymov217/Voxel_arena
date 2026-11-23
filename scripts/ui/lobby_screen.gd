class_name LobbyScreen
extends VBoxContainer
## The waiting room of a multiplayer room, for the host and for every guest. A card for each of the eight places (a medallion with
## the first letter of the name, a crown on the host's, the connection in bars, Mute and, for the host, Remove); the places still
## free are dashed rings, and to the host a ring is a button that gives a friend the way in (the address to copy, or Steam's
## invite); under them the few buttons there are: the host opens the yard (a campaign room's host begins the campaign there), everyone can leave.
## No instructions: a button does what it says. The screen follows the room by itself: a friend who comes or goes, a connection
## that changes.
##
## It is also what the pause menu opens over the yard ("The room"), so the host sees who is there, invites and removes from
## anywhere. `acts` are the menu's doings, so that this stays a picture of the room and nothing more:
##   enter (the host opens the yard: for a campaign room that is how the campaign begins), gate (the host to the gate, over the yard),
##   back (close this screen over the game), leave (out of the room), cap_text (why the campaign cannot begin), slot (the host opens
##   one of his campaigns kept for the groups of friends he plays with: its run), new_slot (a campaign for a new group), and two facts:
##   overlay (opened over a running game) and in_yard (that game is the yard).
## Buttons keep names the tests (and a tester's script) find them by: LobbyEnter, LobbyCampaign, LobbyYard, LobbyGate,
## LobbyBack, LobbyLeave, LobbyWait, LobbyInvite0 (the first free place), and for a guest in place n: Mute<n>, Remove<n>; a campaign
## room's host also has LobbySaves (the row of his campaigns), LobbySave<run> for each and LobbyNewSave.
## (LobbyCampaign is the campaign room's way into the yard; LobbyYard is gone.)

## (The places a room has: four in a campaign room, eight in an Arena room: Net.room_cap.)
## The medallions' colours, one for each place (cloth dyes: crimson, indigo, olive, purple, ochre, teal, rust, slate).
const TINTS := [Color(0.62, 0.17, 0.12), Color(0.17, 0.29, 0.58), Color(0.3, 0.44, 0.17), Color(0.45, 0.22, 0.52), Color(0.74, 0.54, 0.16), Color(0.12, 0.44, 0.44), Color(0.72, 0.34, 0.12), Color(0.36, 0.39, 0.44)]
const CARD := Vector2(268, 214)
const SAVE_COINS := 3           # (the friends of a saved campaign shown on its card: a campaign room has places for three besides the host)

var acts := {}
var _title: Label
var _grid: GridContainer
var _count: Label
var _cap: Label
var _saves: HBoxContainer        # (the host's campaigns, in a campaign room's lobby)
var _start: Button
var _t := 1.0
var _sig := ""
var _shown := {}                # id -> true: who was on the cards (a new one fades in)
var _live := {}                 # id -> {bars, ms}: what the next ping refresh moves

## How good a round trip is, in bars of four (0: not known yet).
static func bars_of(ping: float) -> int:
	if ping < 0.0:
		return 0
	if ping <= 60.0:
		return 4
	if ping <= 110.0:
		return 3
	if ping <= 180.0:
		return 2
	return 1

static func bars_colour(n: int) -> Color:
	if n >= 3:
		return Color(0.5, 0.8, 0.4)
	if n == 2:
		return Color(0.92, 0.72, 0.26)
	if n == 1:
		return Color(0.86, 0.3, 0.24)
	return Color(UIStyle.BRONZE_DARK, 0.6)

static func tint_of(slot: int) -> Color:
	return TINTS[posmod(slot, TINTS.size())]

static func initial_of(who: String) -> String:
	var t := who.strip_edges()
	return t.substr(0, 1).to_upper() if t != "" else "?"

static func ping_text(ping: float) -> String:
	return "—" if ping < 0.0 else "%d ms" % int(roundf(ping))

## The medallion of a place: a coin of cloth colour with the first letter of the name, a gold ring and a crown if he is the host;
## a free place is a dashed ring with a plus in it.
class Medallion extends Control:
	var tint := Color.WHITE
	var letter := ""
	var host := false
	var empty := false
	var _font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(90, 98)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = UIStyle.serif(0, 700)

	func _draw() -> void:
		var r := 37.0
		var c := Vector2(size.x * 0.5, size.y - r - 3.0)
		if empty:
			var n := 18
			for i in n:
				var a := TAU * float(i) / float(n)
				draw_arc(c, r - 1.0, a, a + TAU / float(n) * 0.55, 6, Color(UIStyle.BRONZE_DARK, 0.8), 2.0, true)
			var col := Color(UIStyle.BRONZE, 0.55)
			draw_line(c + Vector2(-12, 0), c + Vector2(12, 0), col, 3.0, true)
			draw_line(c + Vector2(0, -12), c + Vector2(0, 12), col, 3.0, true)
			return
		draw_circle(c, r, tint.darkened(0.4))
		draw_circle(c, r - 3.0, tint)
		draw_arc(c, r - 6.0, PI * 1.05, PI * 1.62, 14, Color(1, 1, 1, 0.24), 2.5, true)   # (the light on a struck coin)
		draw_arc(c, r - 0.5, 0.0, TAU, 48, UIStyle.GOLD if host else UIStyle.BRONZE_DARK.lightened(0.3), 3.5 if host else 2.5, true)
		var fs := 40
		var ts := _font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.34), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.82))
		if host:
			# A crown on the ring's top: a band and three points.
			var w := 38.0
			var by := c.y - r + 6.0
			var ty := by - 18.0
			var pts := PackedVector2Array([Vector2(c.x - w * 0.5, by), Vector2(c.x - w * 0.5, ty + 4.0), Vector2(c.x - w * 0.25, ty + 10.0), Vector2(c.x, ty), Vector2(c.x + w * 0.25, ty + 10.0), Vector2(c.x + w * 0.5, ty + 4.0), Vector2(c.x + w * 0.5, by)])
			draw_colored_polygon(pts, UIStyle.GOLD)
			draw_polyline(pts + PackedVector2Array([pts[0]]), UIStyle.INK, 1.5, true)
			for p in [pts[1], pts[3], pts[5]]:
				draw_circle(p, 2.6, UIStyle.GOLD_LIGHT)

## A connection's four bars.
class Bars extends Control:
	var level := 0

	func _init() -> void:
		custom_minimum_size = Vector2(24, 18)
		mouse_filter = Control.MOUSE_FILTER_PASS   # (so that its tooltip shows)

	func set_level(n: int) -> void:
		if n != level:
			level = n
			queue_redraw()

	func _draw() -> void:
		var col := LobbyScreen.bars_colour(level)
		for i in 4:
			var h := 6.0 + float(i) * 4.0
			draw_rect(Rect2(float(i) * 6.0, size.y - h, 4.0, h), col if i < level else Color(UIStyle.BRONZE_DARK, 0.5))

## A saved campaign's face: the friends who play it as small coins of their cloth colours (overlapped; one dashed coin while none has
## played it yet), and the bout it has reached in digits. The card for a new campaign is a dashed ring with a plus.
class SaveMark extends Control:
	var names: Array = []
	var stage := 1
	var plus := false
	var _font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(150, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = UIStyle.serif(0, 700)

	func _draw() -> void:
		var r := 19.0
		var cy := size.y * 0.5
		if plus:
			var c0 := Vector2(size.x * 0.5, cy)
			var n := 14
			for i in n:
				var a := TAU * float(i) / float(n)
				draw_arc(c0, r - 1.0, a, a + TAU / float(n) * 0.55, 5, Color(UIStyle.BRONZE_DARK, 0.8), 2.0, true)
			var col := Color(UIStyle.BRONZE, 0.7)
			draw_line(c0 + Vector2(-9, 0), c0 + Vector2(9, 0), col, 3.0, true)
			draw_line(c0 + Vector2(0, -9), c0 + Vector2(0, 9), col, 3.0, true)
			return
		var shown := names.slice(maxi(0, names.size() - LobbyScreen.SAVE_COINS))
		if shown.is_empty():
			var c1 := Vector2(r + 3.0, cy)
			for i in 14:
				var a := TAU * float(i) / 14.0
				draw_arc(c1, r - 1.0, a, a + TAU / 14.0 * 0.55, 5, Color(UIStyle.BRONZE_DARK, 0.8), 2.0, true)
		for i in shown.size():
			var who := String(shown[i])
			var c := Vector2(r + 3.0 + float(i) * r * 1.6, cy)   # (overlapped, a letter of each still whole)
			var tint := LobbyScreen.tint_of(absi(hash(who)))
			draw_circle(c, r, tint.darkened(0.4))
			draw_circle(c, r - 2.0, tint)
			draw_arc(c, r - 0.5, 0.0, TAU, 32, UIStyle.BRONZE_DARK.lightened(0.3), 2.0, true)
			var fs := 22
			var letter := LobbyScreen.initial_of(who)
			var ts := _font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(_font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.34), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.82))
		var fs2 := 28
		var digits := str(stage)
		var ds := _font.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
		draw_string(_font, Vector2(size.x - ds.x - 4.0, cy + fs2 * 0.34), digits, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UIStyle.GOLD_LIGHT)

func _init(acts_ := {}) -> void:
	acts = acts_
	add_theme_constant_override("separation", 18)
	name = "Lobby"

func _ready() -> void:
	var arena := Net.room_kind == Net.KIND_ARENA
	var host := Net.is_host()
	var list := Net.room_list()
	var host_name := ""
	for r in list:
		if r.host:
			host_name = String(r.name)
	# The head: whose room it is, what it is for, how many are in it.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	add_child(head)
	_title = UIStyle.title(_title_of(arena, host_name), 34)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_title)
	head.add_child(_kind_chip(arena))
	_count = Label.new()
	_count.add_theme_font_override("font", UIStyle.serif(2, 700))
	_count.add_theme_font_size_override("font_size", 22)
	_count.add_theme_color_override("font_color", UIStyle.GOLD)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	# The eight places.
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	add_child(_grid)
	# The host's campaigns, one for each group of friends he plays with (the lobby before the campaign, not the pause menu's room).
	if host and not arena and not bool(acts.get("overlay", false)):
		add_child(_saves_row())
	# The buttons.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)
	var first := _build_bar(bar, arena, host)
	_sig = _signature(list)
	_rebuild(list)
	if first != null:
		first.grab_focus.call_deferred()   # (Enter, Space or the pad's A does the one thing to do)

## Whose room it is, by what it is for.
static func _title_of(arena: bool, host_name: String) -> String:
	return (Loc.t("%s's arena") if arena else Loc.t("%s's party")) % host_name

## What the room is for, as a badge at the head of the screen.
func _kind_chip(arena: bool) -> Control:
	var chip := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.2, 0.14, 0.05, 0.9) if arena else Color(0.3, 0.08, 0.06, 0.9)
	s.border_color = UIStyle.GOLD
	s.set_border_width_all(1)
	s.border_width_left = 4
	s.set_corner_radius_all(3)
	s.content_margin_left = 16; s.content_margin_right = 16; s.content_margin_top = 8; s.content_margin_bottom = 8
	chip.add_theme_stylebox_override("panel", s)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.name = "KindChip"
	var k := Label.new()
	k.text = Loc.t("ARENA WITH FRIENDS") if arena else Loc.t("CAMPAIGN TOGETHER")
	k.add_theme_font_override("font", UIStyle.serif(2, 700))
	k.add_theme_font_size_override("font_size", 17)
	k.add_theme_color_override("font_color", UIStyle.GOLD_LIGHT)
	chip.add_child(k)
	return chip

## One of the screen's big buttons: the title screen's plates (the one to press gilded).
func _action(text: String, cb: Callable, button_name: String, primary: bool) -> Button:
	var b := UIStyle.menu_button(text, cb, primary)
	b.name = button_name
	b.custom_minimum_size = Vector2(400 if primary else 250, 62)
	return b

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

## The row of buttons under the cards, by who he is and where: the host opens the yard (or starts the campaign), a guest waits,
## and over a game it is the way back or on to the gate. The one to press is returned (it has the focus).
func _build_bar(bar: HBoxContainer, arena: bool, host: bool) -> Button:
	var first: Button = null
	var over := bool(acts.get("overlay", false))
	var in_yard := bool(acts.get("in_yard", false))
	if over:
		# Over the game (the pause menu's "The room"): the yard has its own way back at the top of the screen.
		if host and in_yard and acts.has("gate"):
			first = _action("Go to the gate", acts.gate, "LobbyGate", true)
		elif not in_yard:
			first = _action("Back to the fight", acts.get("back", func(): pass), "LobbyBack", true)
		if first != null:
			bar.add_child(first)
	elif host:
		if arena:
			first = _action("Enter the yard", acts.enter, "LobbyEnter", true)
			bar.add_child(first)
		else:
			first = _campaign_bar(bar)
	else:
		var wait := Label.new()
		wait.text = Loc.t("Waiting for the host...")
		wait.name = "LobbyWait"
		wait.add_theme_font_override("font", UIStyle.serif(2, 700))
		wait.add_theme_font_size_override("font_size", 20)
		wait.add_theme_color_override("font_color", UIStyle.GOLD)
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(wait)
		var tw := wait.create_tween().set_loops()
		tw.tween_property(wait, "modulate:a", 0.4, 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(wait, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	bar.add_child(_spacer())
	bar.add_child(_action("Close the room" if host else "Leave the room", acts.get("leave", func(): pass), "LobbyLeave", false))
	return first

## The host of a campaign room: how death is dealt with before the first bout, then the campaign, which begins as it does alone,
## in the yard (the lobby: the smith, the market, the physician, and the gate to the bout).
func _campaign_bar(bar: HBoxContainer) -> Button:
	var cs := int(Save.get_value("coop_stage", 1))
	if cs <= 1:
		var mo := OptionButton.new()
		for m in ["legionary", "ironman"]:
			mo.add_item(Loc.t(String(CampaignRun.MODES[m].name)))
		mo.select(1 if CampaignRun.mode(true) == "ironman" else 0)
		mo.tooltip_text = "%s\n%s" % [Loc.t(String(CampaignRun.MODES.legionary.desc)), Loc.t(String(CampaignRun.MODES.ironman.desc))]
		mo.item_selected.connect(func(i): CampaignRun.begin(["legionary", "ironman"][i], true))
		mo.custom_minimum_size = Vector2(150, 62)
		mo.name = "LobbyDeath"
		bar.add_child(mo)
	_start = _action("Begin the campaign" if cs <= 1 else "Continue the campaign", acts.enter, "LobbyCampaign", true)
	_start.custom_minimum_size.x = 340
	bar.add_child(_start)
	_cap = Label.new()
	_cap.text = Loc.t("%d at most") % Net.CAMPAIGN_PLAYERS
	_cap.add_theme_font_size_override("font_size", 16)
	_cap.add_theme_color_override("font_color", Color(1, 0.62, 0.5))
	_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cap.visible = false
	bar.add_child(_cap)
	return _start

## The row of the host's campaigns: a scrolling strip, one card for each (filled by _fill_saves).
func _saves_row() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "LobbySaves"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 92)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saves = HBoxContainer.new()
	_saves.add_theme_constant_override("separation", 12)
	sc.add_child(_saves)
	return sc

## One card for each campaign kept (the open one ringed in gold: its friends are those in the room now, and those who have played it
## before) and a plus for a campaign of a new group. A card opens its campaign for the room.
func _fill_saves(list: Array) -> void:
	if _saves == null:
		return
	for c in _saves.get_children():
		c.queue_free()
		_saves.remove_child(c)
	var here := []
	for r in list:
		if not r.host:
			here.append(String(r.name))
	var open_card: Control = null
	for sv in Save.coop_slots():
		var names: Array = (sv.members as Array).duplicate()
		if bool(sv.active):
			for n in here:
				if not names.has(n):
					names.append(n)
		var card := _save_card(int(sv.run), names, int(sv.stage), bool(sv.active))
		_saves.add_child(card)
		if bool(sv.active):
			open_card = card
	var nb := _save_button("LobbyNewSave", _card_style("guest"), func(): _act("new_slot"))
	var pm := SaveMark.new()
	pm.plus = true
	_in_button(nb, pm)
	_saves.add_child(nb)
	if open_card != null:
		_show_card.call_deferred(open_card)

## The strip scrolled to the card of the campaign that is open (the strip is laid out a frame after it is filled).
func _show_card(card: Control) -> void:
	if is_instance_valid(card) and card.get_parent() != null and card.get_parent().get_parent() is ScrollContainer:
		(card.get_parent().get_parent() as ScrollContainer).ensure_control_visible(card)

func _save_card(run: int, names: Array, stage: int, active: bool) -> Button:
	var b := _save_button("LobbySave%d" % run, _card_style("host" if active else "guest"), func(): _act("slot", run))
	var mk := SaveMark.new()
	mk.names = names
	mk.stage = stage
	_in_button(b, mk)
	b.tooltip_text = ", ".join(PackedStringArray(names))
	return b

func _save_button(button_name: String, base: StyleBoxFlat, cb: Callable) -> Button:
	var b := Button.new()
	b.name = button_name
	b.custom_minimum_size = Vector2(176, 80)
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, base)
	for st in ["hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, _card_style("free_hover"))
	b.pressed.connect(cb)
	return b

func _in_button(b: Button, mk: Control) -> void:
	mk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mk.offset_left = 12
	mk.offset_right = -12
	b.add_child(mk)

## The menu's doing named `what`, with its arguments (nothing happens if the menu has none).
func _act(what: String, arg = null) -> void:
	var cb = acts.get(what)
	if cb is Callable and (cb as Callable).is_valid():
		if arg == null:
			(cb as Callable).call()
		else:
			(cb as Callable).call(arg)

func _small_button(text: String, cb: Callable) -> Button:
	var b := UIStyle.button(text, cb)
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var base: StyleBox = UIStyle.theme().get_stylebox(st, "Button")
		var sm := base.duplicate()
		if sm is StyleBoxFlat:
			sm.content_margin_left = 12
			sm.content_margin_right = 12
			sm.content_margin_top = 4
			sm.content_margin_bottom = 4
		b.add_theme_stylebox_override(st, sm)
	return b

## What the cards show, in a line: who is there, in what order, and what room it is (so that a change is noticed).
func _signature(list: Array) -> String:
	return "%s|%s|%s" % [Net.room_kind, Net.campaign_full(), str(list.map(func(r): return [r.id, r.name]))]

func _process(dt: float) -> void:
	_t += dt
	if _t < 0.25:
		return
	_t = 0.0
	var list := Net.room_list()
	var sig := _signature(list)
	if sig != _sig:
		_sig = sig
		_rebuild(list)
	else:
		_update_pings(list)

## The eight places, again: those who are in the room, then the places kept for friends to come.
func _rebuild(list: Array) -> void:
	for c in _grid.get_children():
		c.queue_free()
		_grid.remove_child(c)
	_live.clear()
	var now := {}
	var free := 0
	var slots := Net.room_cap()
	for i in slots:
		var card: Control
		if i < list.size():
			var r: Dictionary = list[i]
			card = _card(i, r)
			now[int(r.id)] = true
			if not _shown.is_empty() and not _shown.has(int(r.id)):
				# A friend who has just come in: his card comes up, and a tick tells the host who is not looking.
				card.modulate.a = 0.0
				card.create_tween().tween_property(card, "modulate:a", 1.0, 0.35)
				if not r.you:
					Sfx.ui("tick", 0.6)
		else:
			card = _free_card(free)
			free += 1
		_grid.add_child(card)
	_shown = now
	_fill_saves(list)
	_count.text = "%d / %d" % [list.size(), slots]
	for r in list:
		if r.host:
			_title.text = _title_of(Net.room_kind == Net.KIND_ARENA, String(r.name))   # (a guest learns the host's name from the first roster)
	if _cap != null:
		var full := Net.campaign_full()
		_cap.visible = full
		if _start != null:
			_start.disabled = full
			_start.tooltip_text = String(acts.get("cap_text", Callable()).call()) if full and acts.get("cap_text") is Callable else ""

func _card_style(kind: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(4)
	s.set_border_width_all(1)
	match kind:
		"host":
			s.bg_color = Color(0.18, 0.125, 0.06, 0.93)
			s.border_color = UIStyle.GOLD
			s.set_border_width_all(2)
		"you":
			s.bg_color = Color(0.145, 0.108, 0.07, 0.93)
			s.border_color = UIStyle.BRONZE
		"free":
			s.bg_color = Color(0.05, 0.04, 0.03, 0.4)
			s.border_color = Color(UIStyle.BRONZE_DARK, 0.45)
		"free_hover":
			s.bg_color = Color(0.1, 0.075, 0.045, 0.6)
			s.border_color = UIStyle.GOLD
		_:
			s.bg_color = Color(0.11, 0.085, 0.06, 0.93)
			s.border_color = UIStyle.BRONZE_DARK
	s.content_margin_left = 12; s.content_margin_right = 12; s.content_margin_top = 8; s.content_margin_bottom = 8
	return s

## A place not taken: a dashed ring. To the host it is a button that gives a friend the way in: the address on this network,
## copied (the first free place shows it), or Steam's invite window.
func _free_card(n: int) -> Control:
	var steam := Net.transport == "steam"
	var addrs := [] if steam else Net.lan_addresses()
	var can := Net.is_host() and (steam or not addrs.is_empty())
	var caption := ""
	if can and n == 0:
		caption = Loc.t("Invite") if steam else String(addrs[0])
	var holder: Control
	if can:
		var b := Button.new()
		b.name = "LobbyInvite%d" % n
		b.custom_minimum_size = CARD
		for st in ["normal", "disabled"]:
			b.add_theme_stylebox_override(st, _card_style("free"))
		for st in ["hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(st, _card_style("free_hover"))
		holder = b
	else:
		var p := PanelContainer.new()
		p.custom_minimum_size = CARD
		p.add_theme_stylebox_override("panel", _card_style("free"))
		holder = p
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if can:
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_top = 8
	holder.add_child(col)
	var med := Medallion.new()
	med.empty = true
	med.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(med)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_override("font", UIStyle.serif(2, 700))
	cap.add_theme_font_size_override("font_size", 17)
	cap.add_theme_color_override("font_color", UIStyle.GOLD)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.custom_minimum_size = Vector2(0, 24)
	col.add_child(cap)
	if can:
		(holder as Button).pressed.connect(func():
			if steam:
				Net.invite_friends()
				return
			DisplayServer.clipboard_set(String(addrs[0]))
			cap.text = Loc.t("Copied")
			get_tree().create_timer(1.6).timeout.connect(func():
				if is_instance_valid(cap):
					cap.text = caption))
	return holder

func _card(i: int, r: Dictionary) -> Control:
	var who := String(r.name)
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD
	card.name = "Slot%d" % i
	card.add_theme_stylebox_override("panel", _card_style("host" if r.host else ("you" if r.you else "guest")))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(col)
	var med := Medallion.new()
	med.tint = tint_of(i)
	med.letter = initial_of(who)
	med.host = bool(r.host)
	med.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(med)
	var nl := Label.new()
	nl.text = who
	nl.add_theme_font_override("font", UIStyle.serif(1, 700))
	nl.add_theme_font_size_override("font_size", 21)
	nl.add_theme_color_override("font_color", UIStyle.GOLD_LIGHT if r.host else UIStyle.TEXT)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.custom_minimum_size = Vector2(120, 0)
	nl.tooltip_text = who
	col.add_child(nl)
	var role := PackedStringArray()
	if r.host:
		role.append(Loc.t("HOST"))
	if r.you:
		role.append(Loc.t("YOU"))
	var rl := UIStyle.label(" · ".join(role), 12, Color(UIStyle.BRONZE, 0.9))
	rl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.custom_minimum_size = Vector2(0, 16)
	col.add_child(rl)
	if not r.host:
		var sig := HBoxContainer.new()
		sig.alignment = BoxContainer.ALIGNMENT_CENTER
		sig.add_theme_constant_override("separation", 8)
		col.add_child(sig)
		var bars := Bars.new()
		bars.tooltip_text = Loc.t("The round trip to the host: under 60 ms is smooth, over 180 ms will feel late.")
		sig.add_child(bars)
		var ms := UIStyle.label("", 13, UIStyle.MUTED)
		ms.autowrap_mode = TextServer.AUTOWRAP_OFF
		sig.add_child(ms)
		_live[int(r.id)] = {"bars": bars, "ms": ms}
		_set_ping(int(r.id), float(r.ping))
	if not r.you:
		# Mute (his voice not played here) for everyone, and Remove for the host.
		var btns := HBoxContainer.new()
		btns.alignment = BoxContainer.ALIGNMENT_CENTER
		btns.add_theme_constant_override("separation", 8)
		col.add_child(btns)
		var pid := int(r.id)
		var mb := _small_button(Loc.t("Unmute") if VoiceChat.muted.has(pid) else Loc.t("Mute"), func(): pass)
		mb.name = "Mute%d" % i
		mb.tooltip_text = Loc.t("Stop hearing this player's voice (only for you)")
		mb.pressed.connect(func():
			if VoiceChat.muted.has(pid):
				VoiceChat.muted.erase(pid)
			else:
				VoiceChat.muted[pid] = true
			mb.text = Loc.t("Unmute") if VoiceChat.muted.has(pid) else Loc.t("Mute"))
		btns.add_child(mb)
		if Net.is_host():
			var kb := _small_button(Loc.t("Remove"), func(): pass)
			kb.name = "Remove%d" % i
			kb.tooltip_text = Loc.t("Send this player out of the room: they cannot come back until you open a new one")
			kb.pressed.connect(func():
				if not kb.has_meta("armed"):
					kb.set_meta("armed", true)
					kb.text = Loc.t("Sure?")
					return
				Net.kick(pid))
			btns.add_child(kb)
	return card

func _set_ping(id: int, ping: float) -> void:
	var w: Dictionary = _live.get(id, {})
	if w.is_empty():
		return
	var n := bars_of(ping)
	(w.bars as Bars).set_level(n)
	(w.ms as Label).text = ping_text(ping)
	(w.ms as Label).add_theme_color_override("font_color", bars_colour(n) if n > 0 else UIStyle.MUTED)

func _update_pings(list: Array) -> void:
	for r in list:
		_set_ping(int(r.id), float(r.ping))
