extends Control
## Menus and the flow between them (main.js): the main screen, training, the yard with the
## smith after each campaign stage, multiplayer rooms (Steam lobbies or a direct address),
## options, and the pause screen. Starts and ends matches, and routes network messages to them.

var match_: Match = null
var hud: Hud = null
var screen := "main"
var panel: PanelContainer
var world_root: Node3D
var pause_layer: CanvasLayer
var last_result := {}
var in_room := false
var over_match := false   # a menu screen opened over a running match (Settings from the pause menu)
var cmd_bot := false
var room_list: VBoxContainer
var _training_loaded := false
var training := {"enemy": "gladiator", "weapon": "gladius", "count": 1, "difficulty": 0.5, "behaviour": "fights", "my_main": "built", "my_off": "roundShield", "immortal": true, "respawn": true}
var backdrop: Match = null      # bots fighting behind the menus, seen by an orbiting camera
var bg: ColorRect
var shade: TextureRect
var panel_style: StyleBoxFlat
const HERO_POS := Vector3(-1.45, 0, -9.7)
## Bread & Circuses is set aside for now (its screens and code stay, ready to come back).
const SHOW_CIRCUS := false

## The walkable Ludus yard is for testing only: `-- --admin` on the command line (or "admin"
## in the save) shows it; players go from fight to the smith.
static func admin() -> bool:
	return OS.get_cmdline_user_args().has("--admin") or bool(Save.get_value("admin", false))
const CLOTH := [0x8a1c14, 0x1f4f8f, 0x2f6b2a, 0x6b2a7a, 0xc89a2a, 0x2a2a2a, 0xe8e0d0, 0xb4541e]
const LOOK_SLOTS := {
	"hat": ["", "hat_laurel", "hat_crest", "hat_straw", "hat_horns", "hat_crown", "hat_feather", "hat_bandana"],
	"hair": ["", "hair_mohawk", "hair_long", "hair_curly", "hair_topknot", "hair_ponytail"],
	"beard": ["", "beard_braided"],
	"cape": ["", "cape"],
}

func _ready() -> void:
	theme = UIStyle.theme()
	UIStyle.hook(get_tree())
	apply_display(Save.get_value("settings", {}))
	apply_picture(Save.get_value("settings", {}))
	apply_frame(Save.get_value("settings", {}))
	apply_ui_scale(Save.get_value("settings", {}))
	# Resized, moved to another screen, or full screen: the automatic resolution follows.
	get_tree().root.size_changed.connect(func(): apply_render_scale(Save.get_value("settings", {})))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.my_kit = kit()
	Net.my_body = body()
	Armory.register(Save.get_value("armor_designs", {}))   # the pieces designed at the bench
	_net_loadout()
	if Sfx.music:
		Sfx.music.volume = float(Save.get_value("settings", {}).get("music", 0.5))
	_cmdline_room.call_deferred()
	world_root = Node3D.new()
	get_parent().add_child.call_deferred(world_root)
	bg = ColorRect.new()
	bg.color = Color(0.06, 0.045, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.name = "Backdrop"
	add_child(bg)
	# Over the live arena: dark on the left behind the panel, clear on the right, dimmed edges.
	shade = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.03, 0.02, 0.9))
	g.add_point(0.42, Color(0.04, 0.03, 0.02, 0.62))
	g.set_color(g.get_point_count() - 1, Color(0.04, 0.03, 0.02, 0.05))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var vig := TextureRect.new()
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0))
	vg.add_point(0.6, Color(0, 0, 0, 0.0))
	vg.set_color(vg.get_point_count() - 1, Color(0, 0, 0, 0.55))
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 1.0)
	vig.texture = vt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	var side := MarginContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	side.add_theme_constant_override("margin_left", 72)
	side.add_theme_constant_override("margin_top", 40)
	side.add_theme_constant_override("margin_bottom", 40)
	add_child(side)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	side.add_child(col)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.075, 0.056, 0.04, 0.86)
	ps.border_color = UIStyle.BRONZE_DARK
	ps.border_width_left = 1; ps.border_width_right = 1; ps.border_width_bottom = 1
	ps.border_width_top = 3
	ps.set_corner_radius_all(4)
	ps.shadow_color = Color(0, 0, 0, 0.45)
	ps.shadow_size = 18
	ps.content_margin_left = 32; ps.content_margin_right = 32; ps.content_margin_top = 26; ps.content_margin_bottom = 26
	panel_style = ps
	col.add_child(panel)
	var ver := UIStyle.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.1"), 12, Color(1, 1, 1, 0.45))
	ver.anchor_left = 1.0; ver.anchor_right = 1.0
	ver.offset_left = -420; ver.offset_right = -20; ver.offset_top = 12; ver.offset_bottom = 34
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	Net.message.connect(_on_net)
	var vc := VoiceChat.new()
	vc.menu = self
	add_child(vc)
	Net.peer_joined.connect(func(id, _info):
		if Net.is_host():
			Net.send_to(int(id), "purse", coins())
			# The yard is the room: whoever joins walks in through the gate.
			if in_yard() and match_.role == "host":
				match_.add_peer(int(id), _peer_spec(int(id), true))
		if screen == "room":
			show_screen("room"))
	Net.peer_left.connect(func(id):
		if match_ and match_.role == "host":
			match_.drop_peer(int(id))
		if screen == "room":
			show_screen("room"))
	Net.connected.connect(func():
		in_room = true
		# Online the lobby is the yard: the host walks in at once and the others join him
		# there; the gate is where he picks the campaign or an arena mode for everyone.
		if Net.is_host():
			enter_yard()
		else:
			show_screen("room"))
	Net.connection_failed.connect(func(r): show_screen("mp", r))
	Net.disconnected.connect(func():
		in_room = false
		_end_match()
		show_screen("mp", "The host left"))
	Net.lobbies.connect(_on_lobbies)
	Net.my_name = Save.get_value("name", "Gladiator")
	show_screen("main")

func _clear() -> VBoxContainer:
	for c in panel.get_children():
		c.queue_free()
		panel.remove_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	return v

func _row(parent: Control, items: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for i in items:
		if i is Label:
			i.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(i)
	parent.add_child(h)
	return h

## The purse. In a room it is one purse for the party, the host's: what any of them earns goes
## into it and what any of them buys comes out of it; the host keeps the count and tells the
## rest (a guest's own purse waits for him at home).
var shared_purse := 0

## A beginner's purse: a dagger (35) or a leather cap and a few blocks on the stick at the forge,
## not a proper weapon from the rack.
const START_COINS := 60

func coins() -> int:
	if Net.active() and not Net.is_host():
		return shared_purse
	return int(Save.get_value("coins", START_COINS))

func add_coins(n: int) -> void:
	if Net.active() and not Net.is_host():
		shared_purse = maxi(0, shared_purse + n)
		Net.send_host("purse_add", n)
		return
	Save.set_value("coins", maxi(0, coins() + n))
	if Net.active():
		Net.send_all("purse", coins())

func arms() -> Dictionary:
	return Arms.sanitize(Save.get_value("arms", {}))

func set_arms(a: Dictionary) -> void:
	Save.set_value("arms", a)
	_net_loadout()
	# Bought in the yard: in his hands at once, there and then.
	if in_yard() and match_.me and is_instance_valid(match_.me.f) and match_.me.f.alive:
		var lo := Arms.loadout(Arms.sanitize(a))
		match_.me.f.rearm(lo.main, lo.off)

func kit() -> Dictionary:
	return Net.sanitize_kit(Save.get_value("kit", {}))

## The armour bought at the smith and worn into every bout of the campaign (and about the yard).
func worn_armor() -> Array:
	return Armory.sanitize(Save.get_value("armor_worn", []))

## The plates off the worn pieces (Armory wear), until the smith mends them.
func armor_wear() -> Dictionary:
	return Armory.clean_wear(Save.get_value("armor_wear", {}), worn_armor())

func set_armor_wear(w: Dictionary) -> void:
	Save.set_value("armor_wear", Armory.clean_wear(w, worn_armor()))
	_net_loadout()

func set_worn_armor(a: Array) -> void:
	Save.set_value("armor_worn", Armory.sanitize(a))
	Save.set_value("armor_wear", Armory.clean_wear(Save.get_value("armor_wear", {}), Armory.sanitize(a)))   # a piece taken off takes its wear with it
	_net_loadout()
	if in_yard() and match_.me and is_instance_valid(match_.me.f) and match_.me.f.alive:
		match_.me.f.set_armor_pieces(worn_armor())

## The player's own gladiator: skin, cloth colour and the cosmetic pieces (no armour: that is
## bought). Saved as indices, so an old or hand-edited save cannot name anything that is not there.
func look() -> Dictionary:
	var l: Dictionary = Save.get_value("look", {})
	var out := {"skin": clampi(int(l.get("skin", 0)), 0, Fighter.SKINS.size() - 1), "cloth": clampi(int(l.get("cloth", 0)), 0, CLOTH.size() - 1)}
	for k in LOOK_SLOTS:
		out[k] = clampi(int(l.get(k, 0)), 0, LOOK_SLOTS[k].size() - 1)
	return out

## What the room is told about us: the arms, plus the look (other players see your hat).
func _net_loadout() -> void:
	var lo := Arms.loadout(arms())
	var lk := look()
	lo["look"] = look_armor(lk)
	lo["gear"] = worn_armor()
	lo["gear_defs"] = Armory.defs_of(lo.gear)   # what a designed piece is, for the others to see it
	lo["gear_wear"] = armor_wear()
	lo["skin"] = Fighter.SKINS[lk.skin]
	Net.my_loadout = lo

## A guest's look, as the host accepts it: only the cosmetic pieces and the known skins.
## What the host spawns for a guest: his name, kit, body and the look and arms he sent.
func _peer_spec(id: int, geared: bool, with_body := true) -> Dictionary:
	var pl: Dictionary = Net.peers[id].get("loadout", {})
	var pk := peer_look(pl)
	return {"id": id, "name": Net.peers[id].name, "kit": Net.peers[id].get("kit", {}), "body": Net.peers[id].get("body", {}) if with_body else {}, "skin": pk.skin, "loadout": {"main": pl.get("main", "gladius"), "off": pl.get("off"), "armor": pk.armor + (pk.gear if geared else []), "armor_defs": Armory.defs_of(pk.gear) if geared else {}, "armor_wear": Armory.clean_wear(pl.get("gear_wear", {}), pk.gear) if geared else {}} if not pl.is_empty() else {"main": "gladius"}, "worn": pl.get("worn", {}) if pl.get("worn") is Dictionary else {}}

func peer_look(pl: Dictionary) -> Dictionary:
	var ok := []
	for k in LOOK_SLOTS:
		ok += LOOK_SLOTS[k]
	var arm: Array = (pl.get("look", []) as Array).filter(func(id): return id is String and id != "" and ok.has(id)).slice(0, 4) if pl.get("look") is Array else []
	var sk = pl.get("skin")
	Armory.register(pl.get("gear_defs", {}))   # his designed pieces, made safe, under their own ids
	return {"armor": arm, "gear": Armory.sanitize(pl.get("gear", [])), "skin": int(sk) if (sk is int or sk is float) and Fighter.SKINS.has(int(sk)) else null}

func look_armor(l: Dictionary) -> Array:
	var a := []
	for k in LOOK_SLOTS:
		var id: String = LOOK_SLOTS[k][l[k]]
		if id != "":
			a.append(id)
	return a

## The gladiator's body in the campaign (Body): old wounds, lost limbs, prosthetics, eyes.
func body() -> Dictionary:
	return Body.sanitize(Save.get_value("body", {}))

func set_body(b: Dictionary) -> void:
	var clean := Body.sanitize(b)
	var was := Body.sanitize(Save.get_value("body", {}))
	Save.set_value("body", clean)
	Net.my_body = clean
	# Stitched in the yard: the wounds close on him there and then.
	if in_yard() and match_.me and is_instance_valid(match_.me.f) and clean.fresh.is_empty():
		for n in was.fresh:
			var p = match_.me.f.by_name.get(n)
			if p:
				p.restore_voxels(was.fresh[n])

func set_kit(k: Dictionary) -> void:
	var clean := Net.sanitize_kit(k)
	Save.set_value("kit", clean)
	Net.my_kit = clean
	# Bought in the yard: the gladiator walking about in it has it in his bag at once (and the
	# yard ending does not write the old bag back over the purchase).
	if match_ and is_instance_valid(match_) and match_.me and match_.mode == "yard":
		match_.me.inventory = clean.duplicate()

func show_screen(s: String, msg := "") -> void:
	var was := screen
	if s == "main":
		# Back at the main menu he has left the yard: a fight picked from here ends here.
		if in_yard():
			_end_match()
		hub = false
	screen = s
	if backdrop and backdrop.hero and (was == "gladiator") != (s == "gladiator"):
		_dress_hero()
	visible = true
	_backdrop_on.call_deferred()
	if Sfx.music and match_ == null:
		Sfx.music.set_state("yard" if ["yard", "market", "circus_market"].has(s) else "menu")
	var v := _clear()
	if in_yard() or s == "yard":
		# The one way out of a stall; the smith seen from anywhere else leads into the yard.
		v.add_child(UIStyle.button("◀  Leave the %s  (Esc)" % {"market": "market", "yard": "smith", "physician": "physician", "missions": "board", "gate": "gate"}.get(s, "stall"), _close_overlay if in_yard() else func(): enter_yard(), true))
		if in_yard() and hud:
			hud.visible = false
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if s == "main" else panel_style)
	panel.custom_minimum_size = Vector2(520 if s == "main" else (1180 if s == "training" or s == "fights" or s == "training_armour" else 760), 0)
	# A new screen slides in and its rows come up one after another (a screen redrawn in place,
	# a count changed in the bag, stays put).
	var fresh := s != was or not panel.has_meta("shown")
	panel.set_meta("shown", true)
	if fresh:
		panel.modulate.a = 0.0
		panel.position.x = -24.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.28)
		tw.tween_property(panel, "position:x", 0.0, 0.32)
	if msg != "":
		v.add_child(UIStyle.label(msg, 16, Color(1, 0.6, 0.5)))
	match s:
		"main": _main(v)
		"training": _training(v)
		"yard": _yard(v)
		"market": _market(v)
		"physician": _physician(v)
		"fights": _fights(v)
		"mp": _mp(v)
		"room": _room(v)
		"options": _options(v)
		"gladiator": _gladiator(v)
		"circus": _circus(v)
		"controls": _controls(v)
		"gate": _gate(v)
		"missions": _missions(v)
		"circus_market": _circus_market(v)
		"demo_end": _demo_end(v)
		"campaign_end": _campaign_end(v)
		"training_designs": _training_designs(v)
		"training_armour": _training_armour(v)
	if fresh and s != "main":
		var rows := v.get_children()
		for i in rows.size():
			var r: Control = rows[i]
			r.modulate.a = 0.0
			var rt := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			rt.tween_interval(0.05 + minf(i, 10) * 0.035)
			rt.tween_property(r, "modulate:a", 1.0, 0.22)
	if backdrop and backdrop.hero:
		_frame_hero()

func _main(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 10)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	v.add_child(head)
	var laurel := Ornament.new("laurel", Vector2(170, 86))
	laurel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(laurel)
	var t := Label.new()
	t.text = "WRECKSMITH"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", UIStyle.serif(4))
	t.add_theme_font_size_override("font_size", 84)
	t.add_theme_color_override("font_color", UIStyle.GOLD)
	t.add_theme_color_override("font_outline_color", Color(0.2, 0.11, 0.03))
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("shadow_offset_y", 5)
	t.add_theme_constant_override("shadow_outline_size", 12)
	head.add_child(t)
	t.modulate.a = 0.0
	create_tween().tween_property(t, "modulate:a", 1.0, 0.7)
	if Edition.demo():
		var badge := UIStyle.label("DEMO", 16, UIStyle.BRONZE)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(badge)
	# The gold glints now and then.
	var glint := create_tween().set_loops()
	glint.bind_node(t)
	glint.tween_interval(3.5)
	glint.tween_property(t, "self_modulate", Color(1.3, 1.22, 1.05), 0.25)
	glint.tween_property(t, "self_modulate", Color.WHITE, 0.7)
	var rule := Ornament.new("rule", Vector2(380, 22))
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	v.add_child(gap)
	var st := int(Save.get_value("stage", 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(col)
	var buttons := [
		# A campaign under way goes on from the yard, the lobby between bouts.
		UIStyle.menu_button(("Continue · bout %d" % st) if st > 1 else "Begin the campaign", func(): enter_yard(), true),
	]
	if SHOW_CIRCUS:
		buttons.append(UIStyle.menu_button("Bread & Circuses", func(): show_screen("circus")))
	buttons.append(UIStyle.menu_button("Your gladiator", func(): show_screen("gladiator")))
	if admin():
		buttons.append(UIStyle.menu_button("The Ludus yard (admin)", enter_yard))
	buttons.append_array([
		UIStyle.menu_button("Arena", func(): show_screen("fights")),
		UIStyle.menu_button("Training", func(): show_screen("training")),
		UIStyle.menu_button("The forge", _workshop_forge),
		UIStyle.menu_button("Multiplayer", func(): show_screen("mp")),
		UIStyle.menu_button("Settings", func(): show_screen("options")),
		UIStyle.menu_button("Quit", func(): get_tree().quit()),
	])
	for i in buttons.size():
		var b: Button = buttons[i]
		col.add_child(b)
		# The plates slide in one after another.
		b.modulate.a = 0.0
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.12 + i * 0.06)
		tw.tween_property(b, "modulate:a", 1.0, 0.3)

var rebinding := ""
var hub := false                 # in the walkable yard, or coming back to it after a fight

func in_yard() -> bool:
	return match_ != null and is_instance_valid(match_) and match_.mode == "yard"

## The Ludus yard: walk between the stations; G at one opens it over the yard.
func enter_yard(banner_text := "") -> void:
	hub = true
	var lo := Arms.loadout(arms())
	# He walks about the yard as the last fight left him: his wounds on him (nobody bleeds out
	# here), for the physician to see to.
	start({"mode": "yard", "loadout_override": {"main": lo.main if lo.main else "", "off": lo.off if lo.off else ""}, "decrees": [], "hazards": [], "body": body()})   # (what he has: no shield he does not own)
	match_.station.connect(_open_station)
	if Sfx.music:
		Sfx.music.set_state("yard")
	if banner_text != "":
		match_._banner("Back in the yard", banner_text)

func _open_station(id: String) -> void:
	if visible:
		return
	# Alone, the gate is the way to the next bout: through it and into the arena, no menu.
	# A room's host gets the gate's menu (the co-op campaign or another mode for everyone).
	if id == "gate" and not Net.active():
		var st := int(Save.get_value("stage", 1))
		if Edition.demo_over(st):
			_end_match()
			show_screen("demo_end")
			return
		start({"mode": "campaign", "stage": st})
		return
	if id == "gate" and Net.active() and not Net.is_host():
		match_._banner("The arena gate", "The host leads the party through")
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if match_.input:
		match_.input.enabled = false
	# The fight's HUD (blood, breath, the crowd, the item bar) goes while a stall is open.
	if hud:
		hud.visible = false
	match id:
		"smith": show_screen("yard")
		"market": show_screen("market")
		"board": show_screen("missions")
		"physician": show_screen("physician")
		"gate": show_screen("gate")

func _close_overlay() -> void:
	visible = false
	over_match = false
	if match_:
		match_.process_mode = Node.PROCESS_MODE_INHERIT
	if hud:
		hud.visible = true
	_apply_input_settings()   # (a key rebound or the sensitivity changed meanwhile takes at once)
	if match_ and match_.input:
		match_.input.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## A menu screen over a running match (Settings from the pause menu): the fight goes on
## underneath online, the hands are off it until the screen is closed.
func _open_over_match(s: String) -> void:
	over_match = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if match_ and match_.input:
		match_.input.enabled = false
	if match_ and not Net.active():
		match_.process_mode = Node.PROCESS_MODE_DISABLED   # alone, the fight waits for him
	if hud:
		hud.visible = false
	show_screen(s)

## Out of the room: the host closes it (his guests are told the host left), a guest goes.
func _leave_room() -> void:
	get_tree().paused = false
	_end_match()
	Net.leave()
	in_room = false
	hub = false
	over_match = false
	show_screen("main")

func _gate(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("The arena gate", 34))
	v.add_child(UIStyle.label("Pick the fight. You come back to the yard afterwards.", 15, UIStyle.MUTED))
	if Net.active() and Net.is_host():
		var cs := int(Save.get_value("coop_stage", 1))
		var cn := Data.stage(cs, 1 + Net.peers.size())
		if Edition.demo_over(cs):
			v.add_child(UIStyle.button("You have finished the demo", func():
				Net.send_all("demo_end", {})
				_end_match()
				show_screen("demo_end"), true))
		else:
			v.add_child(UIStyle.label("Next co-op bout: %s · %s" % [cn.get("title", "Bout %d" % cs), cn.get("foe_name", "")], 15, UIStyle.GOLD))
			v.add_child(UIStyle.button("The co-op campaign · bout %d (all of you)" % cs, func(): start({"mode": "coop", "role": "host"}), true))
	elif Net.active() and not Net.is_host():
		v.add_child(UIStyle.label("The host leads the party through the gate.", 15, UIStyle.MUTED))
	else:
		var st := int(Save.get_value("stage", 1))
		var nxt := Data.stage(st)
		if Edition.demo_over(st):
			v.add_child(UIStyle.button("You have finished the demo", func():
				_end_match()
				show_screen("demo_end"), true))
		else:
			v.add_child(UIStyle.label("Next bout: %s · %s" % [nxt.get("title", "Bout %d" % st), nxt.get("foe_name", "")], 15, UIStyle.GOLD))
			v.add_child(UIStyle.button("The Campaign · bout %d" % st, func(): start({"mode": "campaign", "stage": st}), true))
	if SHOW_CIRCUS:
		v.add_child(UIStyle.button("Bread & Circuses", func():
			_end_match()
			show_screen("circus")))
	v.add_child(UIStyle.button("An arena mode for the room" if Net.active() else "Fights and party modes", func():
		_end_match()
		show_screen("fights")))
	if Net.active():
		v.add_child(UIStyle.button("Close the room (main menu)" if Net.is_host() else "Leave the room (main menu)", func(): _leave_room()))
	else:
		v.add_child(UIStyle.button("Leave the yard (main menu)", func(): show_screen("main")))

func missions() -> Array:
	var ms = Save.get_value("missions", [])
	if not (ms is Array) or ms.is_empty():
		ms = Yard.roll_missions(randi())
		Save.set_value("missions", ms)
	return ms

func _missions(v: VBoxContainer) -> void:
	var rep := int(Save.get_value("rep", 0))
	var rk := Yard.rank_of(rep)
	v.add_child(UIStyle.title("The mission board", 34))
	var nxt = rk.next
	v.add_child(UIStyle.label("Rank: %s · reputation %d%s" % [rk.name, rep, (" · %s at %d" % [nxt.name, int(nxt.rep)]) if nxt else " · the highest rank"], 16, UIStyle.GOLD))
	v.add_child(UIStyle.label(String(rk.perk), 14, UIStyle.MUTED))
	if nxt:
		var bar := ProgressBar.new()
		bar.min_value = float(rk.rep)
		bar.max_value = float(nxt.rep)
		bar.value = float(rep)
		bar.custom_minimum_size = Vector2(500, 14)
		bar.show_percentage = false
		v.add_child(bar)
	v.add_child(UIStyle.label("For the next fight:", 15, UIStyle.TEXT))
	for ms in missions():
		var d: Dictionary = Yard.MISSIONS.get(ms.id, {})
		if d.is_empty():
			continue
		v.add_child(UIStyle.label("%s  %s  (%d/%d) · %d denarii, %d reputation" % ["✔" if ms.get("done", false) else "·", d.text, int(ms.n), int(d.count), int(round(int(d.coins) * Yard.mission_pay(rep))), int(d.rep)], 15, Color(0.6, 0.95, 0.5) if ms.get("done", false) else UIStyle.TEXT))

## A fight is over: count what it did toward the missions, pay them, and the reputation.
func _settle_missions(r: Dictionary, mode: String) -> String:
	if mode == "yard" or mode == "training":
		return ""
	var ms := missions()
	var done := Yard.apply_counts(ms, r.get("missions", {}))
	var rep := int(Save.get_value("rep", 0))
	var kills_me := int(r.get("kills", {}).get(Save.get_value("name", "Gladiator"), 0))
	var gain := Yard.fight_rep(r.get("won", false), kills_me, r.get("boss", false))
	var pay := Yard.payout(done, rep)
	gain += int(pay.rep)
	add_coins(int(pay.coins))
	var before := Yard.rank_of(rep)
	Save.set_value("rep", rep + gain)
	var after := Yard.rank_of(rep + gain)
	# Finished missions make room for new ones.
	var keep: Array = ms.filter(func(x): return not x.get("done", false))
	var fresh := Yard.roll_missions(randi(), 6).filter(func(x): return not keep.any(func(k): return k.id == x.id))
	while keep.size() < 3 and not fresh.is_empty():
		keep.append(fresh.pop_front())
	Save.set_value("missions", keep)
	var text := "+%d reputation" % gain
	if not done.is_empty():
		text += " · missions done: %s (+%d denarii)" % [", ".join(done.map(func(id): return Yard.MISSIONS[id].text)), int(pay.coins)]
	if after.index > before.index:
		text += " · NEW RANK: %s!" % after.name
	return text

func bindings() -> Dictionary:
	var b = Save.get_value("settings", {}).get("bindings", {})
	return b if b is Dictionary else {}

func _controls(v: VBoxContainer) -> void:
	panel.custom_minimum_size.x = 900
	v.add_child(UIStyle.title("Controls", 34))
	v.add_child(UIStyle.label("Click a key, then press the new one (Esc cancels). Gamepad: left stick walks, right stick looks; hold the right trigger and the right stick moves the sword hand, the left trigger the shield hand. A jump, B kick, X grab, Y throw, LB shove, RB thrust, D-pad uses the kit.", 14, UIStyle.MUTED))
	var cur: Dictionary = Data.controls.get("defaults", {}).duplicate()
	var mine := bindings()
	for k in mine:
		cur[k] = mine[k]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for a in Data.controls.get("actions", []):
		var id: String = a.id
		if not cur.has(id):
			continue
		var lbl := UIStyle.label(String(a.label), 14)
		lbl.custom_minimum_size = Vector2(250, 0)
		grid.add_child(lbl)
		var b := UIStyle.button("Press a key…" if rebinding == id else PlayerInput.label_of(String(cur[id])), func():
			rebinding = id
			show_screen("controls"))
		b.custom_minimum_size = Vector2(150, 0)
		grid.add_child(b)
	_row(v, [UIStyle.button("Reset to defaults", func():
		_set_opt("bindings", {})
		show_screen("controls", "Back to the defaults")), UIStyle.button("Done", func(): show_screen("options"), true)])

func _input_more(e: InputEvent) -> void:
	if rebinding == "" or not (e is InputEventKey) or not e.pressed:
		return
	get_viewport().set_input_as_handled()
	var id := rebinding
	rebinding = ""
	if e.keycode == KEY_ESCAPE:
		show_screen("controls")
		return
	var code := PlayerInput.code_of(e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode)
	if code == "":
		show_screen("controls", "That key cannot be bound")
		return
	var b := bindings().duplicate()
	var cur: Dictionary = Data.controls.get("defaults", {}).duplicate()
	for k in b:
		cur[k] = b[k]
	# A key does one thing: whatever had it swaps to this action's old key.
	for other in cur:
		if other != id and cur[other] == code:
			b[other] = cur[id]
	b[id] = code
	_set_opt("bindings", b)
	show_screen("controls", "%s: %s" % [id, PlayerInput.label_of(code)])

func _tutorial() -> void:
	start({"mode": "training", "tutorial": true, "training": {"enemy": "none", "respawn": false}})

## Foes kept out of the training for now (the flail fighter: the flail is not right yet).
const TRAINING_OUT := ["flailman"]

func _training(v: VBoxContainer) -> void:
	# The saved choices once; after that the screen is redrawn from what is being picked (each
	# redraw read the save back over it, and a + or − in the bag came to nothing).
	if not _training_loaded:
		training.merge(Save.get_value("training", {}), true)
		_training_loaded = true
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var tt := UIStyle.title("Training", 34)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	head.add_child(UIStyle.button("Tutorial", _tutorial))
	v.add_child(head)
	# Two columns: who you face and what you carry on the left, the bag on the right.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(520, 0)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var form := func(title: String) -> GridContainer:
		left.add_child(UIStyle.label(title, 13, UIStyle.BRONZE))
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 8)
		left.add_child(g)
		return g
	var pick := func(g: GridContainer, label_: String, keys: Array, names: Array, key: String) -> void:
		var l := UIStyle.label(label_, 15)
		l.custom_minimum_size = Vector2(130, 0)
		g.add_child(l)
		var o := OptionButton.new()
		o.custom_minimum_size = Vector2(360, 0)
		o.fit_to_longest_item = false
		for n in names:
			o.add_item(n)
		o.select(maxi(0, keys.find(training.get(key))))
		o.item_selected.connect(func(i): training[key] = keys[i])
		g.add_child(o)
	var ge: GridContainer = form.call("THE ENEMY")
	var foes: Array = Data.campaign.enemies.keys().filter(func(k): return not TRAINING_OUT.has(k)).map(func(k): return "foe:" + k)
	var who: Array = (["none", "gladiator"] + foes + Data.beasts.keys()).filter(func(k): return Edition.foe_open(k))
	if not who.has(training.get("enemy")):
		training.enemy = "gladiator"
	pick.call(ge, "Who", who, who.map(func(k): return "Nobody" if k == "none" else ("Gladiator" if k == "gladiator" else (Data.campaign.enemies[k.trim_prefix("foe:")].get("label", k) if k.begins_with("foe:") else Data.beasts[k].name))), "enemy")
	pick.call(ge, "How many", [1, 2, 3], ["One", "Two", "Three"], "count")
	var weapons := ["random", "fists", "gladius", "longsword", "zweihander", "axe", "executionerAxe", "mace", "warhammer", "hammer", "spear", "trident", "dagger", "bow"]
	pick.call(ge, "Their weapon", weapons, weapons.map(func(k): return "Random" if k == "random" else ("Bare hands" if k == "fists" else Data.preset(k).get("name", k))), "weapon")
	pick.call(ge, "Behaviour", ["fights", "defends", "still", "moves"], ["Fights back", "Defends only", "Stands still (a dummy)", "Walks about, never attacks"], "behaviour")
	var dl := UIStyle.label("Difficulty", 15)
	ge.add_child(dl)
	var diff := HSlider.new()
	diff.min_value = 0.1
	diff.max_value = 1.0
	diff.step = 0.05
	diff.value = training.difficulty
	diff.custom_minimum_size = Vector2(360, 24)
	diff.value_changed.connect(func(x): training.difficulty = x)
	ge.add_child(diff)
	var gy: GridContainer = form.call("YOU")
	var built: Dictionary = Save.get_value("training_weapon", {})
	var mains := ["built", "campaign", "fists", "gladius", "longsword", "zweihander", "axe", "executionerAxe", "mace", "warhammer", "hammer", "spear", "trident", "dagger", "plank", "chicken", "bow", "ram"]
	pick.call(gy, "Main hand", mains, mains.map(func(k): return ("Forged: " + String(built.get("name", "none yet"))) if k == "built" else ("Your campaign arms" if k == "campaign" else ("Bare hands" if k == "fists" else Data.preset(k).get("name", k)))), "my_main")
	var built_off: Dictionary = Save.get_value("training_off_weapon", {})
	pick.call(gy, "Off hand", ["none", "roundShield", "scutum", "dagger", "campaign", "built"], ["Nothing", "Round shield", "Scutum", "Dagger", "Your campaign arms", "Design: " + String(built_off.get("name", "none yet"))], "my_off")
	_row(left, [UIStyle.button("Weapons from My designs", func(): show_screen("training_designs")), UIStyle.button("Forge a weapon (free in training)", _training_forge)])
	var t_arm := Armory.sanitize(training.get("armor", []))
	var t_kg := 0.0
	for id in t_arm:
		t_kg += Armory.kg(id)
	var al := UIStyle.label(("Armour: %d pieces · %.1f kg" % [t_arm.size(), t_kg]) if not t_arm.is_empty() else "Armour: none", 15)
	al.autowrap_mode = TextServer.AUTOWRAP_OFF
	_row(left, [al, UIStyle.button("Armour (free in training)", func(): show_screen("training_armour"))])
	var imm := CheckBox.new()
	imm.text = "I cannot die"
	imm.button_pressed = training.immortal
	imm.toggled.connect(func(x): training.immortal = x)
	var res := CheckBox.new()
	res.text = "The enemy comes back"
	res.button_pressed = training.respawn
	res.toggled.connect(func(x): training.respawn = x)
	_row(left, [imm, res])
	_training_bag(right)
	var go := _row(v, [UIStyle.button("Start training", _start_training, true), UIStyle.button("Back", func(): show_screen("main"))])
	go.alignment = BoxContainer.ALIGNMENT_END

func _training_loadout() -> Dictionary:
	var lo := Arms.loadout(arms())
	var built: Dictionary = Save.get_value("training_weapon", {})
	var m = training.my_main
	var main = (built if not built.is_empty() else "gladius") if m == "built" else (lo.main if m == "campaign" else ("" if m == "fists" else m))
	var o = training.my_off
	var built_off: Dictionary = Save.get_value("training_off_weapon", {})
	var off = lo.off if o == "campaign" else ("" if o == "none" else ((built_off if not built_off.is_empty() else "") if o == "built" else o))
	if main is Dictionary and main.get("twoHanded", false):
		off = ""
	var arm := Armory.sanitize(training.get("armor", []))
	return {"main": main if main != null else "", "off": off if off != null else "", "armor": arm, "armor_defs": Armory.defs_of(arm)}

func _start_training() -> void:
	Save.set_value("training", training)
	var opts := {"mode": "training", "training": training.duplicate(), "loadout_override": _training_loadout()}
	var bag := _bag_clean(training.get("bag", {}))
	if not bag.is_empty():
		opts.inventory_override = bag
	start(opts)

## The market's wares to try out in training, free: what is taken, how many of each (up to 9
## kinds, one for each number key).
const TRAINING_BAG_MAX := Throwables.BAG_KINDS
func _bag_clean(raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for id in raw:
			out[str(id)] = int(raw[id])
	return Throwables.bag_clamp(out)

func _training_bag(v: VBoxContainer) -> void:
	var bag := _bag_clean(training.get("bag", {}))
	training.bag = bag
	v.add_child(UIStyle.label("YOUR BAG · free in training · keys 1 to 9 · %d of %d kinds" % [bag.size(), TRAINING_BAG_MAX], 13, UIStyle.BRONZE))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var table: Dictionary = Data.shop.get("throwables", {})
	for id in table:
		var have := int(bag.get(id, 0))
		var item_id: String = id
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.1, 0.075, 0.055, 0.95)
		st.border_color = UIStyle.GOLD if have > 0 else UIStyle.BRONZE_DARK
		st.set_border_width_all(1)
		st.set_corner_radius_all(6)
		st.content_margin_left = 8; st.content_margin_right = 8; st.content_margin_top = 4; st.content_margin_bottom = 4
		tile.add_theme_stylebox_override("panel", st)
		tile.tooltip_text = str(table[id].get("desc", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		tile.add_child(row)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(40, 40)
		row.add_child(tex)
		var nm := UIStyle.label(str(table[id].get("name", id)), 15, UIStyle.TEXT if have > 0 else UIStyle.MUTED)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.custom_minimum_size = Vector2(150, 0)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nm)
		var minus := UIStyle.button("−", func():
			var b: Dictionary = training.bag
			b[item_id] = maxi(0, int(b.get(item_id, 0)) - 1)
			if int(b[item_id]) == 0:
				b.erase(item_id)
			Save.set_value("training", training)
			show_screen("training"))
		minus.custom_minimum_size = Vector2(36, 34)
		minus.disabled = have == 0
		row.add_child(minus)
		var cnt := UIStyle.label(str(have), 17, UIStyle.GOLD if have > 0 else UIStyle.MUTED)
		cnt.custom_minimum_size = Vector2(26, 0)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(cnt)
		var plus := UIStyle.button("+", func():
			var b: Dictionary = training.bag
			if Throwables.bag_has_room(b, item_id):
				b[item_id] = int(b.get(item_id, 0)) + 1
			Save.set_value("training", training)
			show_screen("training"))
		plus.custom_minimum_size = Vector2(36, 34)
		plus.disabled = not Throwables.bag_has_room(bag, item_id)
		row.add_child(plus)
		grid.add_child(tile)
		Thumbs.item(tex, id)   # once it is in the tree, so the picture can be made for it

## The forge from the main menu: the smith's forge as it is, to design weapons and keep them in
## My designs; nothing is taken from here or paid for (the smith makes a design in the campaign).
func _workshop_forge() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.workshop = true
	var g: Array = f.gallery()
	f.open((g[0] as Dictionary).duplicate(true) if not g.is_empty() else Data.preset("gladius").duplicate(true), 0, func(_d, _c):
		f.queue_free()
		show_screen("main"))
	panel.visible = false
	f.tree_exited.connect(func(): panel.visible = true)

## The forge's "Try it in the arena": a training bout with the weapon on the anvil in hand and
## the dummy picked there in front of it; Esc (or Leave) goes back to the forge as it was (to
## the yard first, if the forge was the smith's).
var forge_trying = null
var forge_try_yard := false
var forge_try_spot = null   # where he stood in the yard (and which way he looked), to stand there again after
func try_from_forge(f: Node, d: Dictionary, who: String, fights: bool) -> void:
	forge_trying = f
	forge_try_yard = in_yard()
	forge_try_spot = null
	if forge_try_yard and match_.me and is_instance_valid(match_.me.f):
		forge_try_spot = {"pos": match_.me.f.torso.global_position, "yaw": match_.me.f.yaw, "look": match_.input.look_yaw if match_.input else match_.me.f.yaw}
	f.visible = false
	f.process_mode = Node.PROCESS_MODE_DISABLED
	start({"mode": "training", "training": {"enemy": who, "count": 1, "weapon": "random", "behaviour": "fights" if fights else "still", "difficulty": 0.5, "immortal": true, "respawn": true},
		"loadout_override": {"main": d, "off": ""}, "decrees": [], "hazards": []})
	if match_:
		match_._banner("Trying it out", "Esc: back to the forge")

func back_to_forge() -> void:
	var f = forge_trying
	forge_trying = null
	get_tree().paused = false
	_end_match()
	if forge_try_yard:
		enter_yard()
		# Back where he was at the smith's, not at the gate of the yard.
		if forge_try_spot != null and match_ and match_.me and is_instance_valid(match_.me.f):
			match_.me.f.teleport(forge_try_spot.pos)
			match_.me.f.yaw = forge_try_spot.yaw
			if match_.input:
				match_.input.look_yaw = forge_try_spot.look
	forge_try_spot = null
	visible = true
	panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if f != null and is_instance_valid(f):
		f.visible = true
		f.process_mode = Node.PROCESS_MODE_INHERIT
		if match_ and match_.input:
			match_.input.enabled = false

## Training: My designs as the forge shows them, a card for each saved weapon (its picture, its
## weight and reach) to take into the main or the off hand; the ones in hand are marked.
func _training_designs(v: VBoxContainer) -> void:
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(1100.0, maxf(640.0, vp.x - 144.0)), maxf(420.0, vp.y - 80.0))
	var head := HBoxContainer.new()
	head.add_child(UIStyle.title("My designs", 34))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UIStyle.button("Forge a new one", _training_forge))
	head.add_child(UIStyle.button("Back", func(): show_screen("training")))
	v.add_child(head)
	v.add_child(UIStyle.label("Pick a weapon you saved in the forge for either hand", 15, UIStyle.MUTED))
	var g: Array = load("res://scripts/ui/forge.gd").gallery()
	if g.is_empty():
		v.add_child(UIStyle.label("Nothing saved yet: save a design in the forge first", 15, UIStyle.MUTED))
		return
	var main_d: Dictionary = Save.get_value("training_weapon", {}) if training.my_main == "built" else {}
	var off_d: Dictionary = Save.get_value("training_off_weapon", {}) if training.my_off == "built" else {}
	var scroll := _smith_scroll(v)
	var grid := GridContainer.new()
	grid.columns = maxi(2, int((panel.custom_minimum_size.x - 60.0) / 250.0))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for d in g:
		var dd: Dictionary = d
		var in_main := not main_d.is_empty() and main_d.hash() == dd.hash()
		var in_off := not off_d.is_empty() and off_d.hash() == dd.hash()
		var card := PanelContainer.new()
		var sb := UIStyle._plate(UIStyle.PANEL, UIStyle.BRONZE if in_main or in_off else UIStyle.BRONZE_DARK, 2 if in_main or in_off else 1)
		sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 8; sb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", sb)
		card.custom_minimum_size = Vector2(230, 0)
		var col := VBoxContainer.new()
		card.add_child(col)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(0, 120)
		col.add_child(tex)
		var nm := UIStyle.label(str(dd.get("name", "?")), 16, UIStyle.TEXT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size = Vector2(200, 0)
		col.add_child(nm)
		var st := ForgeLib.compute_stats(dd)
		var info := UIStyle.label("%.1f kg · reach %.1f m%s" % [float(st.mass), float(st.reach), " · two hands" if dd.get("twoHanded", false) else ""], 13, UIStyle.MUTED)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(info)
		UIStyle.push_down(col)
		# (a line kept in every card, so the buttons of one in hand line up with the rest)
		var mark := UIStyle.label(("In your %s" % ("main hand" if in_main else "off hand") if not (in_main and in_off) else "In both hands") if in_main or in_off else " ", 13, UIStyle.BRONZE)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(mark)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UIStyle.button("Main hand", func():
			Save.set_value("training_weapon", dd)
			training.my_main = "built"
			show_screen("training")))
		var off := UIStyle.button("Off hand", func():
			Save.set_value("training_off_weapon", dd)
			training.my_off = "built"
			show_screen("training"))
		off.disabled = bool(dd.get("twoHanded", false))
		off.tooltip_text = "Two-handed: it takes both hands" if off.disabled else ""
		row.add_child(off)
		col.add_child(row)
		grid.add_child(card)
		Thumbs.weapon(tex, dd, "tdesign:%d" % dd.hash())

## The forge, free: build any weapon to try out; it is kept as "your forged weapon".
func _training_forge() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	var base: Dictionary = Save.get_value("training_weapon", {})
	if base.is_empty():
		base = Data.preset("gladius").duplicate(true)
	f.free_build = true
	f.open(base, 999999, func(design, _cost):
		if design != null:
			Save.set_value("training_weapon", design)
			training.my_main = "built"
		f.queue_free()
		show_screen("training"))
	visible = true

# ---------- The yard: the smith ----------

func _yard(v: VBoxContainer) -> void:
	# The smith takes the whole window: a header, then your arms on the left and the rack on
	# the right, each scrolling on its own so nothing is ever cut off.
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(maxf(640.0, vp.x - 144.0), maxf(420.0, vp.y - 80.0))
	if v.get_child_count() > 0 and v.get_child(0) is Button:
		v.get_child(0).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(UIStyle.label("THE LUDUS YARD", 13, UIStyle.BRONZE))
	names.add_child(UIStyle.title("The smith", 36))
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 6)
	head.add_child(right)
	var purse := UIStyle.label("Purse: %d denarii" % coins(), 18, UIStyle.GOLD)
	purse.autowrap_mode = TextServer.AUTOWRAP_OFF
	purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(purse)
	var tabs: Array = []
	for t in [["weapons", "Weapons"], ["armour", "Armour"], ["bench", "Design armour"]]:
		var tab_id: String = t[0]
		tabs.append(UIStyle.button(t[1], func():
			smith_tab = tab_id
			show_screen("yard"), tab_id == smith_tab))
	_row(right, tabs).alignment = BoxContainer.ALIGNMENT_END
	if not last_result.is_empty():
		v.add_child(UIStyle.label(last_result.get("text", ""), 16))
	v.add_child(HSeparator.new())
	var inner_w := panel.custom_minimum_size.x - 64.0
	if smith_tab == "armour":
		_smith_armour(v, inner_w)
		return
	if smith_tab == "bench":
		bench_mode = "smith"
		_armour_bench(v, inner_w)
		return
	var a := arms()
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# Your arms, as they are: a picture of each with what the smith can do to it.
	var left_w := clampf(inner_w * 0.36, 330.0, 500.0)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = left_w
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(UIStyle.label("YOUR ARMS", 13, UIStyle.BRONZE))
	var lscroll := _smith_scroll(left)
	var mine := VBoxContainer.new()
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine.add_theme_constant_override("separation", 10)
	lscroll.add_child(mine)
	for side in ["R", "L"]:
		var d = a.main if side == "R" else a.off
		var card := _smith_card(d, ("Main hand" if side == "R" else "Off hand"), "arm:%s:%s" % [side, str(d.hash()) if d != null else "none"], 104)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mine.add_child(card)
		var col: VBoxContainer = card.get_meta("col")
		if d == null:
			col.add_child(UIStyle.label("Empty: buy a shield or a dagger from the rack", 14, UIStyle.MUTED))
			continue
		var cond := int(Arms.condition(a, side) * 100.0)
		var coat: String = Arms.COATING_NAMES.get(d.get("imbue", ""), "")
		col.add_child(UIStyle.label(str(d.get("name", "?")), 17, UIStyle.TEXT))
		col.add_child(UIStyle.label("%s%d voxels · condition %d%%" % [(coat + " · ") if coat != "" else "", d.voxels.size(), cond], 13, UIStyle.GOLD if cond >= 80 else (UIStyle.MUTED if cond >= 40 else Color(1, 0.55, 0.45))))
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 6)
		acts.add_theme_constant_override("v_separation", 6)
		col.add_child(acts)
		var rc := Arms.repair_cost(a, side)
		var mend := UIStyle.button("Mend · %d denarii" % rc if rc > 0 else "Sound", func(): _pay(Arms.repair(arms(), side)))
		mend.disabled = rc == 0 or rc > coins()
		mend.tooltip_text = "The smith puts back every voxel it has lost." + (" Purse after: %d" % (coins() - rc) if rc <= coins() else " %d more needed" % (rc - coins()))
		acts.add_child(mend)
		for id in Arms.UPGRADES:
			if Arms.can_upgrade(id, d):
				var price := Arms.upgrade_price(id, d)
				var b := UIStyle.button("%s · %d denarii" % [Arms.UPGRADES[id].label, price], func(): _pay(Arms.upgrade(arms(), side, id)))
				b.disabled = price > coins()
				b.tooltip_text = String(Arms.UPGRADES[id].desc) + (" Purse after: %d" % (coins() - price) if price <= coins() else " %d more needed" % (price - coins()))
				acts.add_child(b)
		acts.add_child(UIStyle.button("Reshape in the forge", func(): open_forge(side)))
	body.add_child(VSeparator.new())
	var rack := VBoxContainer.new()
	rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.add_theme_constant_override("separation", 8)
	body.add_child(rack)
	var rh := HBoxContainer.new()
	var rl := UIStyle.label("WEAPONS FOR SALE", 13, UIStyle.BRONZE)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(rl)
	rh.add_child(UIStyle.button("Forge a new weapon from nothing", _scratch_forge, true))
	rack.add_child(rh)
	rack.add_child(UIStyle.label("It goes in a free hand. With both hands full you pick which one he takes, for half its worth.", 13, UIStyle.MUTED))
	var scroll := _smith_scroll(rack)
	var rack_w := inner_w - left_w - 60.0
	var grid := GridContainer.new()
	grid.columns = clampi(int(rack_w / 166.0), 2, 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var rack_box := VBoxContainer.new()
	rack_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack_box.add_theme_constant_override("separation", 10)
	scroll.add_child(rack_box)
	rack_box.add_child(grid)
	var tile_st := StyleBoxFlat.new()
	tile_st.bg_color = Color(0.1, 0.075, 0.055, 0.95)
	tile_st.border_color = UIStyle.BRONZE_DARK
	tile_st.set_border_width_all(1)
	tile_st.set_corner_radius_all(8)
	tile_st.content_margin_left = 8; tile_st.content_margin_right = 8; tile_st.content_margin_top = 8; tile_st.content_margin_bottom = 8
	for b in Arms.bases():
		var key: String = b.key
		var pre := Arms.buy(arms(), key)
		var choose: bool = pre.has("choose")
		var trade := 0
		if choose:
			for sd in pre.choose:
				trade = maxi(trade, Arms.value(arms().main if sd == "R" else arms().off) / 2)
		else:
			trade = int(pre.get("trade_in", 0))
		var afford: bool = Arms.base_price(b) <= coins() + trade
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", tile_st)
		tile.custom_minimum_size = Vector2(146, 0)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tooltip_text = "%s · %s hand" % [b.name, "main" if b.slot == "main" else "off"]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		tile.add_child(box)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(0, 96)
		tex.modulate = Color.WHITE if afford else Color(1, 1, 1, 0.45)
		box.add_child(tex)
		var nm := UIStyle.label(str(b.name), 14, UIStyle.TEXT if afford else UIStyle.MUTED)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nm)
		var goes := "both hands full: you pick which one he takes" if choose else ("into both hands" if pre.get("sold", []).size() > 1 else ("into the main hand" if pre.get("side", "R") == "R" else "into the off hand"))
		var pr := UIStyle.label(goes, 12, UIStyle.MUTED)
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(pr)
		_price_lines(box, Arms.base_price(b), trade, "your old one" if choose else "what you hand in")
		var buy := UIStyle.button("Buy", func():
			var r := Arms.buy(arms(), key)
			if r.has("choose"):
				_sell_choice(str(b.name), func(sd): return Arms.buy(arms(), key, sd), r.choose)
			else:
				_pay(r), afford)
		buy.disabled = not afford
		buy.tooltip_text = "" if afford else "Not enough in your purse"
		UIStyle.push_down(box)
		box.add_child(buy)
		grid.add_child(tile)
		Thumbs.weapon(tex, Data.preset(key), "base:" + key)
		_viewable(tex, Data.preset(key), "%d denarii at the smith" % Arms.base_price(b))
	# The bout's oddities, his own designs (made to order), then the smith's rack.
	var odd := _smith_oddities(rack_box, grid.columns, tile_st)
	if _smith_designs(rack_box, grid.columns, tile_st) or odd:
		rack_box.add_child(UIStyle.label("THE SMITH'S RACK", 13, UIStyle.BRONZE))
		rack_box.move_child(grid, rack_box.get_child_count() - 1)

## What a thing costs, spelled out under it: the price, what is taken off for the old one handed
## in, what is paid, and the purse after (or how much is missing).
func _price_lines(box: Container, price: int, trade := 0, trade_what := "") -> void:
	var pay := maxi(0, price - trade)
	var left := coins() - pay
	if trade > 0:
		var l1 := UIStyle.label("%d denarii, less %d for %s" % [price, trade, trade_what], 12, UIStyle.MUTED)
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l1)
	var l2 := UIStyle.label(("You pay %d · purse after %d" % [pay, left]) if left >= 0 else ("You pay %d · %d more needed" % [pay, -left]), 13, UIStyle.GOLD if left >= 0 else Color(1, 0.55, 0.45))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l2)

## Both hands full: which one the smith takes in part exchange for what is bought.
func _sell_choice(nm: String, buy: Callable, sides: Array, bought := Callable()) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", panel_style)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	var q := UIStyle.label("Both your hands are full. Which one does Vulcanus take for the %s?" % nm, 16, UIStyle.TEXT)
	q.custom_minimum_size = Vector2(420, 0)
	v.add_child(q)
	for sd in sides:
		var side: String = sd
		var d = arms().main if side == "R" else arms().off
		var r: Dictionary = buy.call(side)
		var b := UIStyle.button("Sell the %s (%s hand) · pay %d" % [str(d.get("name", "?")) if d else "?", "main" if side == "R" else "off", int(r.get("cost", 0))], func():
			dim.queue_free()
			var got: Dictionary = buy.call(side)
			if bought.is_valid() and not got.has("error") and int(got.get("cost", 0)) <= coins():
				bought.call()
			_pay(got))
		b.disabled = int(r.get("cost", 0)) > coins()
		v.add_child(b)
	v.add_child(UIStyle.button("Keep both", func(): dim.queue_free()))

## This campaign run's seed for the smith's oddities (drawn once, kept with the save).
func run_seed() -> int:
	if Save.get_value("run_seed") == null:
		Save.set_value("run_seed", randi())
	return int(Save.get_value("run_seed", 0))

## The oddities on the stall this bout: one-off weapons of the smith's own, other ones each bout
## and each run; one bought is gone.
func _smith_oddities(box: VBoxContainer, columns: int, tile_st: StyleBoxFlat) -> bool:
	var stage := int(Save.get_value("stage", 1))
	var key := "%d:%d" % [run_seed(), stage]
	var sold: Array = (Save.get_value("oddities_sold", {}) as Dictionary).get(key, [])
	var list := Arms.oddities(run_seed(), stage)
	box.add_child(UIStyle.label("VULCANUS'S ODDITIES · this bout only, one of each", 13, UIStyle.GOLD))
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(g)
	for dv in list:
		var d: Dictionary = dv
		var idx := int(d.oddity.i)
		var price := Arms.oddity_price(d)
		var tile := PanelContainer.new()
		var st := tile_st.duplicate()
		if d.oddity.rare:
			st.border_color = UIStyle.GOLD
			st.set_border_width_all(2)
		tile.add_theme_stylebox_override("panel", st)
		tile.custom_minimum_size = Vector2(146, 0)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		tile.add_child(col)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(0, 96)
		col.add_child(tex)
		var nm := UIStyle.label(str(d.get("name", "?")), 14, UIStyle.GOLD if d.oddity.rare else UIStyle.TEXT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nm)
		var gems := []
		for v in d.voxels:
			if Weapon.GEMS.has(v[3]) and not gems.has(v[3]):
				gems.append(v[3])
		if not gems.is_empty():
			var info := UIStyle.label("Set with " + ", ".join(gems), 12, UIStyle.MUTED)
			info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(info)
		if not sold.has(idx):
			_price_lines(col, price)
		UIStyle.push_down(col)
		if sold.has(idx):
			col.add_child(UIStyle.label("Sold", 13, UIStyle.MUTED))
			tex.modulate = Color(1, 1, 1, 0.35)
		else:
			var mark_sold := func():
				var all: Dictionary = Save.get_value("oddities_sold", {})
				var got: Array = all.get(key, [])
				if not got.has(idx):
					got.append(idx)
				all[key] = got
				Save.set_value("oddities_sold", all)
			var pay := func(r: Dictionary):
				if r.has("error") or int(r.get("cost", 0)) > coins():
					_pay(r)
					return
				mark_sold.call()
				_pay(r)
			var buy := UIStyle.button("Buy", func():
				var r := Arms.buy_design(arms(), d, "", price)
				if r.has("choose"):
					_sell_choice(str(d.get("name", "it")), func(sd): return Arms.buy_design(arms(), d, sd, price), r.choose, mark_sold)
				else:
					pay.call(r), true)
			buy.disabled = price > coins() + (Arms.value(arms().main) + Arms.value(arms().off)) / 2
			col.add_child(buy)
		g.add_child(tile)
		Thumbs.weapon(tex, d, "odd:%d:%d:%d" % [run_seed(), stage, idx])
		_viewable(tex, d, "%d denarii%s" % [price, (" · " + ", ".join(gems)) if not gems.is_empty() else ""])
		var keep := d.duplicate(true)
		keep.erase("oddity")
		var saved: bool = load("res://scripts/ui/forge.gd").gallery().any(func(o): return o.get("voxels") == keep.voxels)
		var sv := UIStyle.button("In My designs" if saved else "Save to My designs", func():
			var mine: Array = load("res://scripts/ui/forge.gd").gallery()
			if not mine.any(func(o): return o.get("voxels") == keep.voxels):
				mine.push_front(keep)
				Save.set_value("forge_gallery", mine.slice(0, 24))
			show_screen("yard"))
		sv.disabled = saved
		col.add_child(sv)
	return true

## The player's own designs (My designs, from the forge), made by the smith at what they are
## worth: their stuff block by block and his labour. Bought, one goes in a free hand like any.
func _smith_designs(box: VBoxContainer, columns: int, tile_st: StyleBoxFlat) -> bool:
	var designs: Array = load("res://scripts/ui/forge.gd").gallery()
	if designs.is_empty():
		return false
	box.add_child(UIStyle.label("YOUR DESIGNS · made to order", 13, UIStyle.BRONZE))
	var g2 := GridContainer.new()
	g2.columns = columns
	g2.add_theme_constant_override("h_separation", 10)
	g2.add_theme_constant_override("v_separation", 10)
	g2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(g2)
	for dv in designs:
		var d: Dictionary = dv
		var pre := Arms.buy_design(arms(), d)
		if pre.has("error"):
			continue
		var price := Arms.design_price(d)
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", tile_st)
		tile.custom_minimum_size = Vector2(146, 0)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		tile.add_child(col)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(0, 96)
		col.add_child(tex)
		var nm := UIStyle.label(str(d.get("name", "?")), 14, UIStyle.TEXT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nm)
		var pr := UIStyle.label("%d blocks · made to order" % d.voxels.size(), 12, UIStyle.MUTED)
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(pr)
		_price_lines(col, price)
		var buy := UIStyle.button("Have it made", func():
			var r := Arms.buy_design(arms(), d)
			if r.has("choose"):
				_sell_choice(str(d.get("name", "it")), func(sd): return Arms.buy_design(arms(), d, sd), r.choose)
			else:
				_pay(r), true)
		buy.disabled = price > coins() + (Arms.value(arms().main) + Arms.value(arms().off)) / 2   # (with what he could trade in)
		UIStyle.push_down(col)
		col.add_child(buy)
		g2.add_child(tile)
		Thumbs.weapon(tex, d, "gallery:%d" % d.hash())
		_viewable(tex, d, "Your design · %d denarii to have it made" % price)
	return true

## A list on the smith's screen that takes what height is left and scrolls within it.
func _smith_scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll

var smith_tab := "weapons"

const ARMOUR_PARTS := {"head": "head", "torso": "body", "upperArmR": "arms", "upperArmL": "arms", "forearmR": "forearms", "forearmL": "forearms", "thighR": "thighs", "thighL": "thighs", "shinR": "shins", "shinL": "shins"}

## The armourer's rack: every piece with a figure showing what it covers, what it is made of, and
## Buy (it replaces what it clashes with, sold back for half) or Take off.
func _smith_armour(v: VBoxContainer, inner_w: float) -> void:
	var worn := worn_armor()
	v.add_child(UIStyle.label(("Worn: " + ", ".join(worn.map(func(i): return String(Data.armor[i].name)))) if not worn.is_empty() else "You wear no armour. What you buy here goes with you into every bout of the campaign; the plates a fight knocks off are back on for the next.", 14, UIStyle.MUTED))
	var scroll := _smith_scroll(v)
	var grid := GridContainer.new()
	grid.columns = clampi(int((inner_w - 16.0) / 340.0), 1, 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var ids: Array = Armory.SHOP.map(func(r): return r[0])
	ids = (Save.get_value("armor_designs", {}) as Dictionary).keys().filter(func(i): return Armory.custom(String(i))) + ids
	for idv in ids:
		var id: String = idv
		var a: Dictionary = Data.armor.get(id, {})
		if a.is_empty():
			continue
		var on := worn.has(id)
		var card := _smith_card(null, "", "", 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row: HBoxContainer = card.get_child(0)
		var fig := Control.new()
		fig.custom_minimum_size = Vector2(58, 106)
		var covered: Array = Armory.parts_of(id)
		var mc := Weapon.voxel_color(a.get("mat", "iron"), "blunt")
		fig.draw.connect(func():
			fig.draw_set_transform(Vector2(1, 1), 0.0, Vector2(0.78, 0.78))
			for k in Hud.LAYOUT:
				var rr: Rect2 = Hud.LAYOUT[k]
				var sb := StyleBoxFlat.new()
				sb.set_corner_radius_all(4 if k != "head" else 10)
				sb.bg_color = mc if covered.has(k) else Color(1, 1, 1, 0.08)
				sb.border_color = Color(1, 1, 1, 0.25) if covered.has(k) else Color(1, 1, 1, 0.06)
				sb.set_border_width_all(1)
				fig.draw_style_box(sb, rr.grow(-1.0)))
		row.add_child(fig)
		row.move_child(fig, 0)
		var col: VBoxContainer = card.get_meta("col")
		col.add_child(UIStyle.label(String(a.name), 16, UIStyle.GOLD if on else UIStyle.TEXT))
		var where := []
		for k in covered:
			if not where.has(ARMOUR_PARTS.get(k, k)):
				where.append(ARMOUR_PARTS.get(k, k))
		col.add_child(UIStyle.label("%s · %s" % [String(a.get("mat", "iron")).capitalize(), ", ".join(where)], 12, UIStyle.BRONZE))
		col.add_child(UIStyle.label("Protection %s · %.1f kg" % [_dots(Armory.protection(id)), Armory.kg(id)], 12, UIStyle.TEXT))
		col.add_child(UIStyle.label(String(Armory.BLURB.get(id, "Your own design, from the bench.")), 12, UIStyle.MUTED))
		var price := Armory.price(id)
		if on:
			var aw := armor_wear()
			var lost: Array = Armory.plates_lost(id, aw)
			if int(lost[0]) > 0:
				var mc_ := Armory.mend_cost(id, aw)
				col.add_child(UIStyle.label("%d of %d plates knocked off · condition %d%%" % [lost[0], lost[1], int(Armory.condition(id, aw) * 100.0)], 12, Color(1, 0.55, 0.45)))
				var mend := UIStyle.button("Mend · %d denarii" % mc_, func():
					var m := Armory.mend(armor_wear(), id)
					if int(m.cost) > coins():
						show_screen("yard", "Not enough denarii")
						return
					add_coins(-int(m.cost))
					set_armor_wear(m.wear)
					show_screen("yard"))
				mend.disabled = mc_ > coins()
				mend.tooltip_text = "The armourer puts back every plate it has lost." + (" Purse after: %d" % (coins() - mc_) if mc_ <= coins() else " %d more needed" % (mc_ - coins()))
				col.add_child(mend)
			col.add_child(UIStyle.button("Worn · take off (+%d)" % (price / 2), func():
				var t := Armory.take_off(worn_armor(), id)
				if not t.has("error"):
					add_coins(-int(t.cost))
					set_worn_armor(t.worn)
				show_screen("yard")))
		else:
			var b := Armory.buy(worn, id)
			var cost: int = int(b.get("cost", price))
			var swaps := worn.filter(func(o): return Armory.clashes(o, id))
			if not swaps.is_empty():
				col.add_child(UIStyle.label("Replaces your %s (taken in part exchange)" % String(Data.armor[swaps[0]].name).to_lower(), 12, UIStyle.MUTED))
			var btn := UIStyle.button(("Buy · %d denarii" % cost) if cost > 0 else ("Swap · %d denarii back" % -cost), func():
				var t := Armory.buy(worn_armor(), id)
				if t.has("error"):
					show_screen("yard", t.error)
				elif int(t.cost) > coins():
					show_screen("yard", "Not enough denarii")
				else:
					add_coins(-int(t.cost))
					set_worn_armor(t.worn)
					show_screen("yard"), true)
			btn.disabled = cost > coins()
			col.add_child(btn)
		grid.add_child(card)

static func _dots(x: float) -> String:
	var n := clampi(int(round(x * 5.0)), 0, 5)
	return "●".repeat(n) + "○".repeat(5 - n)

# ---------- Armour at the forge and in training ----------

## The pieces kept in My designs, one line, each with a bin.
func _armour_designs_row(v: VBoxContainer) -> void:
	var designs: Dictionary = Save.get_value("armor_designs", {})
	if designs.is_empty():
		return
	v.add_child(UIStyle.label("MY DESIGNS", 13, UIStyle.BRONZE))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for idv in designs:
		var id: String = idv
		var d: Dictionary = designs[id]
		row.add_child(UIStyle.label("%s · %s · %.1f kg" % [String(d.get("name", id)), String(d.get("mat", "iron")).capitalize(), Armory.design_kg(d)], 13, UIStyle.TEXT))
		row.add_child(UIStyle.button("✕", func():
			var ds: Dictionary = Save.get_value("armor_designs", {})
			ds.erase(id)
			Save.set_value("armor_designs", ds)
			training.armor = Armory.sanitize(training.get("armor", [])).filter(func(o): return o != id)
			Save.set_value("training", training)
			show_screen(screen)))
	v.add_child(row)

## Armour for training, free: every piece the smith sells and every one of My designs, worn or
## taken off with a click (a piece replaces what it clashes with); or a new one made at the bench.
func _training_armour(v: VBoxContainer) -> void:
	var worn := Armory.sanitize(training.get("armor", []))
	var head := HBoxContainer.new()
	var tt := UIStyle.title("Armour for training", 34)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	head.add_child(UIStyle.button("Make your own at the forge (free)", func():
		bench_mode = "training"
		_plate_bench(Armory.design_piece(bench.region, bench.mat, bench.y0, bench.y1, bench.front, bench.cap, ""), _bench_worn_kg())))
	v.add_child(head)
	var kg := 0.0
	for id in worn:
		kg += Armory.kg(id)
	var with := Armory.burden(kg)
	v.add_child(UIStyle.label(("Worn: %s · %.1f kg · breath ×%.2f · pace %d%%" % [", ".join(worn.map(func(i): return String(Data.armor[i].name))), kg, float(with.breath), int(round(float(with.pace) * 100.0))]) if not worn.is_empty() else "You wear no armour in training. Put on what you like: nothing is paid for here.", 14, UIStyle.MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var ids: Array = (Save.get_value("armor_designs", {}) as Dictionary).keys().filter(func(i): return Armory.custom(String(i))) + Armory.SHOP.map(func(r): return r[0])
	for idv in ids:
		var id: String = idv
		var a: Dictionary = Data.armor.get(id, {})
		if a.is_empty():
			continue
		var on := worn.has(id)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIStyle.label(String(a.name), 15, UIStyle.GOLD if on else UIStyle.TEXT))
		var where := []
		for k in Armory.parts_of(id):
			if not where.has(ARMOUR_PARTS.get(k, k)):
				where.append(ARMOUR_PARTS.get(k, k))
		col.add_child(UIStyle.label("%s · %s · Protection %s · %.1f kg" % [String(a.get("mat", "iron")).capitalize(), ", ".join(where), _dots(Armory.protection(id)), Armory.kg(id)], 12, UIStyle.BRONZE))
		col.add_child(UIStyle.button("Worn · take off" if on else "Wear", func():
			var now := Armory.sanitize(training.get("armor", []))
			training.armor = now.filter(func(o): return o != id) if on else Armory.buy(now, id).worn
			Save.set_value("training", training)
			show_screen("training_armour")))
		grid.add_child(col)
	_armour_designs_row(v)
	_row(v, [UIStyle.button("Take it all off", func():
		training.armor = []
		Save.set_value("training", training)
		show_screen("training_armour")), UIStyle.button("Back", func(): show_screen("training"))]).alignment = BoxContainer.ALIGNMENT_END

# ---------- The armourer's bench ----------

var bench := {"region": "torso", "mat": "iron", "y0": 0.3, "y1": 1.0, "front": false, "cap": true, "name": ""}
## Whose bench it is: "smith" (the campaign's, paid for and worn), "workshop" (the main menu's
## armourer: designed and kept in My designs, free) or "training" (made free and worn there).
var bench_mode := "smith"

func _bench_back() -> String:
	return {"smith": "yard", "workshop": "main", "training": "training_armour"}.get(bench_mode, "yard")

## Back from the armour bench to where it was opened (the main menu's forge opens again).
func _bench_return(msg := "") -> void:
	show_screen(_bench_back(), msg)
	if bench_mode == "workshop":
		_workshop_forge()

func _bench_worn_kg() -> float:
	var kg := 0.0
	for id in _bench_worn():
		kg += Armory.kg(id)
	return kg

## The forge's Armour tab: the forge gives way to the armour bench, free or paid as the forge was
## (the main menu's: kept in My designs; training's: kept and worn; the smith's: made and worn).
func armour_from_forge(f: Node) -> void:
	bench_mode = "workshop" if f.workshop else ("training" if f.free_build else "smith")
	for c in f.tree_exited.get_connections():
		f.tree_exited.disconnect(c.callable)
	f.queue_free()
	_plate_bench(Armory.design_piece(bench.region, bench.mat, bench.y0, bench.y1, bench.front, bench.cap, ""), _bench_worn_kg())

## What the bench is wearing it against: the campaign's armour, the training kit, or nothing.
func _bench_worn() -> Array:
	match bench_mode:
		"smith": return worn_armor()
		"training": return Armory.sanitize(training.get("armor", []))
	return []

## A piece made at a free bench (the workshop's or training's): kept in My designs, and in
## training put on as well.
func _bench_keep(final: Dictionary) -> void:
	var ids := Armory.register([final])
	if ids.is_empty():
		show_screen(_bench_back())
		return
	var designs: Dictionary = Save.get_value("armor_designs", {})
	designs[ids[0]] = final
	Save.set_value("armor_designs", designs)
	if bench_mode == "training":
		training.armor = Armory.buy(Armory.sanitize(training.get("armor", [])), ids[0]).worn
		Save.set_value("training", training)
	_bench_return("%s kept in My designs" % String(final.get("name", "The piece")) + (" and worn" if bench_mode == "training" else ""))

## The armourer's bench: a piece of your own, where it goes, what it is made of and how much
## of the part it covers; what it keeps out, what it weighs and what the weight costs in breath
## and pace, all as you choose; then made, paid for and worn.
func _armour_bench(v: VBoxContainer, _inner_w: float) -> void:
	var def := Armory.design_piece(bench.region, bench.mat, bench.y0, bench.y1, bench.front, bench.cap, bench.name)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	v.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(520, 0)
	body.add_child(left)
	var pick := func(label: String, keys: Array, names: Callable, cur: String, set: Callable) -> void:
		left.add_child(UIStyle.label(label, 13, UIStyle.BRONZE))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		for k in keys:
			var key: String = k
			var b := UIStyle.button(names.call(key), func():
				set.call(key)
				show_screen(_bench_back()))
			b.toggle_mode = true
			b.button_pressed = key == cur
			row.add_child(b)
		left.add_child(row)
	pick.call("WHERE", Armory.REGIONS.keys(), func(k): return Armory.REGIONS[k].label, bench.region, func(k): bench.region = k)
	pick.call("MATERIAL", Armory.BENCH_MATS, func(k): return String(k).capitalize(), bench.mat, func(k): bench.mat = k)
	left.add_child(UIStyle.label("%s   Protection %s   Weight %s" % [String(bench.mat).capitalize(), _dots(float(Data.material(bench.mat).get("hardness", 0.5))), _dots(clampf(float(Data.material(bench.mat).get("mass", 0.03)) / 0.1, 0.0, 1.0))], 13, UIStyle.MUTED))
	left.add_child(UIStyle.label("COVERS", 13, UIStyle.BRONZE))
	for sl_def in [["From", "y0"], ["To", "y1"]]:
		var key: String = sl_def[1]
		var row := HBoxContainer.new()
		var l := UIStyle.label(sl_def[0], 14, UIStyle.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size = Vector2(60, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(bench[key])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.drag_ended.connect(func(_c):
			bench[key] = sl.value
			show_screen(_bench_back()))
		row.add_child(sl)
		left.add_child(row)
	var opt := HBoxContainer.new()
	var fr := CheckBox.new()
	fr.text = "Front and sides only"
	fr.button_pressed = bench.front
	fr.toggled.connect(func(x):
		bench.front = x
		show_screen(_bench_back()))
	opt.add_child(fr)
	var cp := CheckBox.new()
	cp.text = "Cap the top"
	cp.button_pressed = bench.cap
	cp.toggled.connect(func(x):
		bench.cap = x
		show_screen(_bench_back()))
	opt.add_child(cp)
	left.add_child(opt)
	var nm := LineEdit.new()
	nm.placeholder_text = String(def.name)
	nm.text = String(bench.name)
	nm.max_length = 24
	nm.text_changed.connect(func(x): bench.name = x)
	left.add_child(nm)
	# What it comes to: the figure with what it covers, and the numbers.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	var fig := Control.new()
	fig.custom_minimum_size = Vector2(120, 220)
	var covered: Array = (def.parts as Dictionary).keys()
	var mc := Weapon.voxel_color(String(def.mat), "blunt")
	fig.draw.connect(func():
		fig.draw_set_transform(Vector2(4, 4), 0.0, Vector2(1.6, 1.6))
		for k in Hud.LAYOUT:
			var rr: Rect2 = Hud.LAYOUT[k]
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(4 if k != "head" else 10)
			sb.bg_color = mc if covered.has(k) else Color(1, 1, 1, 0.08)
			sb.border_color = Color(1, 1, 1, 0.3) if covered.has(k) else Color(1, 1, 1, 0.06)
			sb.set_border_width_all(1)
			fig.draw_style_box(sb, rr.grow(-1.0)))
	right.add_child(fig)
	var kg := Armory.design_kg(def)
	var worn_kg := 0.0
	for id in _bench_worn():
		worn_kg += Armory.kg(id)
	var with := Armory.burden(worn_kg + kg)
	var price := Armory.design_price(def)
	right.add_child(UIStyle.label(String(def.name), 18, UIStyle.GOLD))
	right.add_child(UIStyle.label("Protection %s" % _dots(float(Data.material(String(def.mat)).get("hardness", 0.5))), 15, UIStyle.TEXT))
	right.add_child(UIStyle.label("Weight %.1f kg  (all you wear: %.1f kg)" % [kg, worn_kg + kg], 15, UIStyle.TEXT))
	right.add_child(UIStyle.label("Breath when running and swinging: ×%.2f" % float(with.breath), 14, UIStyle.MUTED))
	right.add_child(UIStyle.label("Pace: %d%%" % int(round(float(with.pace) * 100.0)), 14, UIStyle.MUTED))
	var free := bench_mode != "smith"
	var make := UIStyle.button(("Make and wear · free in training" if bench_mode == "training" else "Keep in My designs") if free else ("Forge and wear · %d denarii" % price), func():
		var piece := Armory.design_piece(bench.region, bench.mat, bench.y0, bench.y1, bench.front, bench.cap, bench.name)
		if free:
			_bench_keep(piece)
		else:
			_forge_armour(piece), true)
	make.disabled = not free and price > coins()
	right.add_child(make)
	# Or plate by plate, as a weapon is built at the forge (from the shape above).
	right.add_child(UIStyle.button("Shape it plate by plate", func(): _plate_bench(def, worn_kg)))

## The armourer's bench voxel by voxel (ArmourForge) over the smith's screen.
func _plate_bench(def: Dictionary, worn_kg: float) -> void:
	var f := ArmourForge.new()
	add_child(f)
	panel.visible = false
	f.tree_exited.connect(func(): panel.visible = true)
	f.open(def, String(bench.region), func(final):
		# (Its going would show the panel over a forge opened again after it.)
		for c in f.tree_exited.get_connections():
			f.tree_exited.disconnect(c.callable)
		panel.visible = true
		f.queue_free()
		smith_tab = "armour"
		if final == null:
			_bench_return()
		elif bench_mode != "smith":
			_bench_keep(final)
		else:
			_forge_armour(final), worn_kg, coins() if bench_mode == "smith" else -1)

## A designed piece made at the smith and put on, paid for less what it replaces fetches.
func _forge_armour(final: Dictionary) -> void:
	smith_tab = "armour"
	if Armory.design_price(final) > coins():
		show_screen("yard", "Not enough denarii")
		return
	var ids := Armory.register([final])
	if ids.is_empty():
		show_screen("yard")
		return
	var designs: Dictionary = Save.get_value("armor_designs", {})
	designs[ids[0]] = final
	Save.set_value("armor_designs", designs)
	var t := Armory.buy(worn_armor(), ids[0])
	if t.has("error"):
		show_screen("yard", t.error)
		return
	add_coins(-int(t.cost))   # what it costs, less what any piece it replaces fetches
	set_worn_armor(t.worn)
	show_screen("yard")

## A weapon's picture that opens it in the round (WeaponView) when clicked.
func _viewable(tex: TextureRect, d, line := "") -> void:
	if not (d is Dictionary) or not (d.get("voxels") is Array):
		return
	tex.mouse_filter = Control.MOUSE_FILTER_STOP
	tex.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tex.tooltip_text = "Click to see it all round"
	tex.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			WeaponView.show_for(self, d, line))

## A card on the smith's counter: a picture of the weapon and a column for what goes with it.
func _smith_card(d, title: String, key: String, pic := 128) -> PanelContainer:
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.075, 0.055, 0.95)
	st.border_color = UIStyle.BRONZE_DARK
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.content_margin_left = 10; st.content_margin_right = 10; st.content_margin_top = 8; st.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(pic, pic)
	row.add_child(tex)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	if title != "":
		col.add_child(UIStyle.label(title.to_upper(), 12, UIStyle.BRONZE))
	card.set_meta("col", col)
	if d is Dictionary:
		row.ready.connect(func(): Thumbs.weapon(tex, d, key), CONNECT_ONE_SHOT)
		_viewable(tex, d, "%d voxels" % d.voxels.size())
	return card

## Every other way to fight (game.js modes, partyModes.js).
## The fights, as cards in four groups: each says in a line what the bout is.
const FIGHT_GROUPS := [
	["Single combat", ["duel", "bo3", "king", "gauntlet"]],
	["The melee", ["ffa", "chaos", "teams", "pvp"]],
	["Beasts and waves", ["hunt", "coop"]],
	["Games for the Emperor", ["emperor", "hill", "lastLimb", "headball"]],
]
const FIGHT_BLURBS := {
	"duel": "One against one, a quick bout. The Emperor may throw in a decree.",
	"bo3": "Three bouts with one rival. Floored: yield, or fight on wounded for double the stake.",
	"king": "The winner stays and the next challenger walks in. Reign for seven.",
	"gauntlet": "One foe after another, wave after wave. How long do you last?",
	"ffa": "Four gladiators on one sand. The last one standing wins.",
	"chaos": "Everyone against everyone, under three of the Emperor's decrees at once.",
	"teams": "Red against Blue: players and bots split into two sides.",
	"pvp": "Players only, no bots: settle it among yourselves.",
	"hunt": "Beasts pour through the gates in waves. Each wave beaten heals you.",
	"coop": "Waves of gladiators against you and your friends, side by side.",
	"emperor": "You are the Emperor: send decrees, beasts, weapons and tomatoes, then judge.",
	"hill": "Hold the circle alone for 20 seconds.",
	"lastLimb": "Every 15 seconds the Emperor takes a limb from everyone.",
	"headball": "Kick a severed head into the other goal. First to three.",
}

func _fights(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("The Arena", 34))
	v.add_child(UIStyle.label("Your arms from the yard stay home: these fights hand out their own weapons.", 15, UIStyle.MUTED))
	var in_room := Net.active()
	for g in FIGHT_GROUPS:
		var keys: Array = (g[1] as Array).filter(func(k): return (not ["pvp", "coop"].has(k) or in_room) and Edition.mode_open(k, in_room))   # (the friends' fights only in a room)
		if keys.is_empty():
			continue
		v.add_child(UIStyle.label(String(g[0]).to_upper(), 13, UIStyle.BRONZE))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		v.add_child(grid)
		for k in keys:
			grid.add_child(_fight_card(k))
	if Net.active() and Net.is_host() and not Net.peers.is_empty():
		v.add_child(UIStyle.button("Back to the yard, all of you", func(): enter_yard()))
	else:
		v.add_child(UIStyle.button("Back", func(): show_screen("main")))

## One fight's card: its name in capitals, under it what it is, the whole card a button.
func _fight_card(k: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(262, 104)
	b.pressed.connect(func(): start({"mode": k}))
	b.tooltip_text = Modes.LABELS.get(k, "")
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var nm := Label.new()
	nm.text = "◆  " + Modes.TITLES[k].trim_suffix("!")
	nm.add_theme_font_override("font", UIStyle.serif(1, 700))
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", UIStyle.GOLD_LIGHT)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var blurb := UIStyle.label(FIGHT_BLURBS.get(k, Modes.LABELS.get(k, "")), 15, UIStyle.MUTED)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(blurb)
	return b

## The market (market.js): pots, food and tricks for the kit, used in a fight with 1 to 8.
# ---------- Bread & Circuses ----------

func circus_run():
	var r = Save.get_value("circus_run", null)
	return r if r is Dictionary and not r.is_empty() and not r.get("over", false) else null

func ludus() -> Dictionary:
	var l = Save.get_value("ludus", {})
	var out := Circus.empty_ludus()
	if l is Dictionary:
		out.denarii = int(l.get("denarii", 0))
		out.runs = int(l.get("runs", 0))
		out.levels = l.get("levels", {}) if l.get("levels") is Dictionary else {}
	return out

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII"]

func _circus(v: VBoxContainer) -> void:
	panel.custom_minimum_size.x = 820
	v.add_child(UIStyle.label("SEVEN DAYS · THE EMPEROR'S GAMES", 13, UIStyle.BRONZE))
	var t := UIStyle.title("BREAD & CIRCUSES", 40)
	t.add_theme_font_override("font", UIStyle.serif(3))
	t.add_theme_color_override("font_color", UIStyle.GOLD)
	v.add_child(t)
	var run = circus_run()
	if run == null:
		_circus_lobby(v)
		return
	if not run.get("pending_blessing", []).is_empty():
		v.add_child(UIStyle.title("The gods are watching", 26))
		v.add_child(UIStyle.label("Day %s is over. Pick one blessing for the rest of the run." % ROMAN[clampi(int(run.day) - 1, 0, 6)], 15, UIStyle.MUTED))
		for id in run.pending_blessing:
			var b: Dictionary = Circus.blessings().get(id, {})
			var btn := UIStyle.button("%s: %s" % [b.get("name", id), b.get("desc", "")], func():
				var r2 = circus_run()
				Circus.grant(r2, id)
				Save.set_value("circus_run", r2)
				show_screen("circus", "%s blesses you" % b.get("name", id)), true)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(btn)
		return
	var day: Dictionary = Circus.days()[int(run.day)]
	v.add_child(UIStyle.title("Day %s · %s" % [ROMAN[int(run.day)], day.get("theme", "")], 26))
	for i in day.bouts.size():
		var b: Dictionary = day.bouts[i]
		var mark := "✔" if i < int(run.bout) else ("▶" if i == int(run.bout) else "·")
		var col := UIStyle.MUTED if i < int(run.bout) else (UIStyle.GOLD if i == int(run.bout) else UIStyle.TEXT)
		v.add_child(UIStyle.label("%s  %s%s" % [mark, b.name, "  · boss" if b.get("boss", false) else ""], 16, col))
	var bout := Circus.current(run)
	v.add_child(UIStyle.label(String(bout.get("intro", "")), 15, UIStyle.TEXT))
	var bl: Array = run.blessings.map(func(id): return Circus.blessings().get(id, {}).get("name", id))
	var inv: Array = []
	for id in run.inventory:
		if int(run.inventory[id]) > 0:
			inv.append("%s ×%d" % [Data.shop.get("throwables", {}).get(id, {}).get("name", id), int(run.inventory[id])])
	v.add_child(UIStyle.label("Gold: %d · blessings: %s · kit: %s%s" % [int(run.gold), ", ".join(bl) if not bl.is_empty() else "none yet",
		", ".join(inv) if not inv.is_empty() else "empty", " · DAILY GAMES" if run.get("daily", false) else ""], 14, UIStyle.BRONZE))
	_row(v, [UIStyle.button("Fight: %s" % bout.get("name", ""), _circus_fight, true), UIStyle.button("The market", func(): show_screen("circus_market")),
		UIStyle.button("Give up the run", func():
			var r2 = circus_run()
			r2.over = true
			_circus_close(r2, "gave up")
			show_screen("circus", "You walk out of the arena. The ludus keeps what you earned.")),
		UIStyle.button("Main menu", func(): show_screen("main"))])

func _circus_lobby(v: VBoxContainer) -> void:
	var lu := ludus()
	v.add_child(UIStyle.label("Seven days of bouts, beasts and bosses for the Emperor. Gold buys pots between bouts; after each day a god offers a blessing. Fall once and the run is over.", 15, UIStyle.TEXT))
	_row(v, [UIStyle.button("Begin a new run", func():
		Save.set_value("circus_run", Circus.new_run(ludus()))
		show_screen("circus", "Day I begins"), true),
		UIStyle.button("The Daily Games · %s" % Circus.daily_label(), func():
			Save.set_value("circus_run", Circus.new_run(ludus(), true))
			show_screen("circus", "Today's games: the same bouts, decrees and blessings for everyone"))])
	v.add_child(UIStyle.title("The ludus · %d denarii" % int(lu.denarii), 24))
	for id in Circus.ludus_upgrades():
		var u: Dictionary = Circus.ludus_upgrades()[id]
		var lvl := int(lu.levels.get(id, 0))
		var maxed := lvl >= int(u.get("max", 1))
		var b := UIStyle.button(("%s (%d/%d) · maxed" % [u.name, lvl, int(u.max)]) if maxed else ("%s (%d/%d) · %d" % [u.name, lvl, int(u.max), Circus.ludus_price(id, lvl)]), func():
			var l2 := ludus()
			var why = Circus.buy_upgrade(l2, id)
			Save.set_value("ludus", l2)
			show_screen("circus", why if why != null else "%s bought" % u.name))
		b.tooltip_text = u.get("desc", "")
		b.disabled = maxed
		_row(v, [b, UIStyle.label(String(u.get("desc", "")), 13, UIStyle.MUTED)])
	var hall: Array = Save.get_value("hall", [])
	if not hall.is_empty():
		v.add_child(UIStyle.title("Hall of Fame", 24))
		for i in mini(5, hall.size()):
			var h: Dictionary = hall[i]
			v.add_child(UIStyle.label("%d. %s · %s · %d bouts, %d kills%s" % [i + 1, h.name, ("won the rudis" if h.get("campaign", false) else "crowned by the Emperor") if h.won else "fell on day %s to %s" % [ROMAN[clampi(int(h.day) - 1, 0, 6)], h.get("fate", "the arena")], int(h.bouts), int(h.kills), " · daily" if h.get("daily", false) else (" · the campaign" if h.get("campaign", false) else "")], 14, UIStyle.GOLD if h.won else UIStyle.TEXT))
	_row(v, [UIStyle.button("Main menu", func(): show_screen("main"))])

func _circus_market(v: VBoxContainer) -> void:
	var run = circus_run()
	if run == null:
		show_screen("circus")
		return
	v.add_child(UIStyle.title("The market", 32))
	v.add_child(UIStyle.label("Gold: %d · what you buy is used in the next bouts (keys 1 to 8)" % int(run.gold), 15, UIStyle.BRONZE))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 400)
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	scroll.add_child(grid)
	var table: Dictionary = Data.shop.get("throwables", {})
	for id in table:
		var it: Dictionary = table[id]
		var price := int(round(int(it.price) * 0.6))
		var have := int(run.inventory.get(id, 0))
		var lbl := UIStyle.label("%s%s" % [it.name, (" ×%d" % have) if have else ""], 15)
		lbl.custom_minimum_size = Vector2(190, 0)
		lbl.tooltip_text = it.get("desc", "")
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		var b := UIStyle.button("Buy · %d gold" % price, func():
			var r2 = circus_run()
			if int(r2.gold) < price:
				show_screen("circus_market", "Not enough gold")
				return
			if not Throwables.bag_has_room(r2.inventory, id):
				show_screen("circus_market", "Your bag is full: %d of those at most, %d kinds in all" % [Throwables.stack_max(id), Throwables.BAG_KINDS])
				return
			r2.gold = int(r2.gold) - price
			r2.inventory[id] = int(r2.inventory.get(id, 0)) + 1
			Save.set_value("circus_run", r2)
			show_screen("circus_market"))
		var row := HBoxContainer.new()
		row.add_child(lbl)
		row.add_child(b)
		grid.add_child(row)
	_row(v, [UIStyle.button("Back to the games", func(): show_screen("circus"), true)])

func _circus_fight() -> void:
	var run = circus_run()
	if run == null:
		return
	var bout := Circus.current(run)
	var bm := Circus.blessing_mods(run, Circus.rng_for(run, "fortune"))
	var ids: Array = (bout.get("decrees", []) as Array).duplicate()
	if run.get("daily", false):
		for d in Decrees.roll(0.7, 1, Circus.rng_for(run, "decree")):
			if not ids.has(d.id):
				ids.append(d.id)
	var lo := {"main": "chicken" if bm.fortune and bm.fortune.get("chicken", false) else "gladius", "off": "roundShield"}
	start({"mode": "circus", "loadout_override": lo, "mods": bm.mods, "inventory_override": run.inventory.duplicate(), "decrees": ids, "hazards": BoutRules.hazards_for(bout),
		"circus": {"bout": bout, "day": int(run.day), "bout_index": int(run.bout), "fortune": bm.fortune}})

## A run is over: the ludus keeps its share, the Hall of Fame remembers it.
func _circus_close(run: Dictionary, fate: String) -> void:
	var lu := ludus()
	var pay := Circus.payout(run)
	lu.denarii = int(lu.denarii) + pay
	lu.runs = int(lu.runs) + 1
	Save.set_value("ludus", lu)
	Save.set_value("hall", Circus.hall_add(Save.get_value("hall", []), Save.get_value("name", "Gladiator"), run, fate))
	Save.set_value("circus_run", null)
	last_result = {"text": "The ludus earns %d denarii from this run." % pay}

func _circus_finished(r: Dictionary, inv: Dictionary) -> void:
	var run = circus_run()
	if run == null:
		show_screen("circus")
		return
	run.inventory = Net.sanitize_kit(inv)
	var kills_me := int(r.get("kills", {}).get(Save.get_value("name", "Gladiator"), 0))
	var pay := Circus.reward(run, kills_me, float(r.get("favor", 0.0)), float(r.get("time", 999.0)) < 60.0) + 4 * int(r.get("coins", 0)) if r.won else 0
	var state := Circus.finish(run, r.won, kills_me, pay)
	Save.set_value("circus_run", run)
	match state:
		"next":
			show_screen("circus", "Victory! +%d gold" % pay)
		"dayEnd":
			show_screen("circus", "Victory! +%d gold. The day is done." % pay)
		"spared":
			show_screen("circus", "PLUTO SAYS NO: you are sent back from the underworld. Fight the bout again.")
		"victory":
			_circus_close(run, "")
			show_screen("circus", "THE EMPEROR CROWNS YOU! Seven days, and you still stand. " + last_result.text)
		"wipe":
			_circus_close(run, String(r.get("killer", "the arena")))
			show_screen("circus", "You fell on day %s. %s" % [ROMAN[clampi(int(run.day), 0, 6)], last_result.text])

## The market (yardUI.js): every product on a card with its own model, what it does, how it is
## used and what it costs; tabs for the things thrown, the things laid down and the supplies.
const MARKET_TABS := [["throw", "Throwables"], ["place", "Traps & bowls"]]   # the supplies are the physician's
const MARKET_USE := {"self": "Press its number: used on you at once", "place": "Press its number: laid or bowled in front of you", "throw": "Press its number to take it in hand, hold F to aim, let go to throw; its number again puts it away"}
const FRIENDLY_FIRE := ["thunderPot", "nailPot", "caltrops", "oliveOil", "honey", "anvil", "greekFire", "vitriol", "mystery"]
var market_tab := "throw"

static func kit_use(id: String) -> String:
	return "self" if ["bandage", "bread", "wine"].has(id) else ("place" if ["bananas", "cheese"].has(id) else "throw")

func _market(v: VBoxContainer) -> void:
	v.add_child(UIStyle.label("THE LUDUS YARD", 13, UIStyle.BRONZE))
	v.add_child(UIStyle.title("The market", 36))
	var k := kit()
	var bag := []
	for id in k:
		if int(k[id]) > 0:
			bag.append("%s ×%d" % [Data.shop.throwables.get(id, {}).get("name", id), int(k[id])])
	v.add_child(UIStyle.label("Purse: %d denarii · %s" % [coins(), ("In your bag: " + ", ".join(bag)) if not bag.is_empty() else "Your bag is empty"], 15, UIStyle.BRONZE))
	v.add_child(UIStyle.label("Everything here comes with you into every fight: keys 1 to 9 use it.", 13, UIStyle.MUTED))
	var tabs: Array = []
	for t in MARKET_TABS:
		var tab_id: String = t[0]
		var tb := UIStyle.button(t[1], func():
			market_tab = tab_id
			show_screen("market"), tab_id == market_tab)
		tabs.append(tb)
	_row(v, tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var table: Dictionary = Data.shop.get("throwables", {})
	for id in table:
		if kit_use(id) != market_tab:
			continue
		grid.add_child(_market_card(id, table[id], int(k.get(id, 0))))
	if not in_yard():
		_row(v, [UIStyle.button("Back to the smith", func(): show_screen("yard")), UIStyle.button("Main menu", func(): show_screen("main"))])

func _market_card(id: String, it: Dictionary, have: int, back := "market") -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(286, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.075, 0.055, 0.95)
	st.border_color = UIStyle.BRONZE if have > 0 else UIStyle.BRONZE_DARK
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.content_margin_left = 10; st.content_margin_right = 10; st.content_margin_top = 8; st.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	# The model, on a dark medallion, with how many are in the bag.
	var pic := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.04, 0.03, 0.9)
	ps.set_corner_radius_all(40)
	pic.add_theme_stylebox_override("panel", ps)
	pic.custom_minimum_size = Vector2(84, 84)
	pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(84, 84)
	pic.add_child(tex)
	if have > 0:
		var own := UIStyle.label("×%d" % have, 13, UIStyle.GOLD)
		own.size_flags_vertical = Control.SIZE_SHRINK_END
		own.size_flags_horizontal = Control.SIZE_SHRINK_END
		pic.add_child(own)
	row.add_child(pic)
	tex.tree_entered.connect(func(): Thumbs.item(tex, id), CONNECT_ONE_SHOT)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	col.add_child(UIStyle.label(String(it.name), 16, UIStyle.TEXT))
	var d := UIStyle.label(String(it.get("desc", "")), 12, UIStyle.MUTED)
	d.custom_minimum_size = Vector2(170, 0)
	col.add_child(d)
	col.add_child(UIStyle.label(MARKET_USE[kit_use(id)], 11, UIStyle.BRONZE))
	if FRIENDLY_FIRE.has(id):
		col.add_child(UIStyle.label("Hurts friends too", 11, Color(0.95, 0.55, 0.4)))
	var price := int(it.price)
	var room := Throwables.bag_has_room(kit(), id)
	var b := UIStyle.button("Buy · %d denarii" % price if room else ("Bag full (%d)" % Throwables.stack_max(id) if have > 0 else "Bag full (%d kinds)" % Throwables.BAG_KINDS), func():
		var k2 := kit()
		if price > coins():
			show_screen(back, "Not enough denarii")
			return
		if not Throwables.bag_has_room(k2, id):
			show_screen(back, "Your bag is full: %d of those at most, %d kinds in all" % [Throwables.stack_max(id), Throwables.BAG_KINDS])
			return
		add_coins(-price)
		k2[id] = int(k2.get(id, 0)) + 1
		set_kit(k2)
		if Sfx:
			Sfx.play("pickup", Vector3.ZERO, 0.6)
		show_screen(back), price <= coins() and room)
	b.disabled = price > coins() or not room
	col.add_child(b)
	return card

## The physician's stall in the yard: the same treatments as between rounds.
func _physician(v: VBoxContainer) -> void:
	var yard := in_yard()
	_doctor_panel(v, body(), [], int(Save.get_value("stage", 1)), func(nb):
		set_body(nb)
		if yard:
			_close_overlay()
		else:
			show_screen("yard"), "" if yard else "Back", func(nb):
		set_body(nb)
		show_screen("physician"))
	# His supplies under his name, above the treatments.
	var n0 := v.get_child_count()
	_medicine(v)
	for k in v.get_child_count() - n0:
		v.move_child(v.get_child(n0 + k), 1 + k)

## The physician's supplies for the fight (bandages, bread, wine), into the bag like the market's.
func _medicine(v: VBoxContainer) -> void:
	v.add_child(UIStyle.label("SUPPLIES FOR THE FIGHT", 13, UIStyle.BRONZE))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var k := kit()
	var table: Dictionary = Data.shop.get("throwables", {})
	for id in table:
		if kit_use(id) == "self":
			grid.add_child(_market_card(id, table[id], int(k.get(id, 0)), "physician"))
	v.add_child(HSeparator.new())

## Between rounds: a player who lost a limb or an eye is taken to the physician (an overlay on
## the paused arena). `done` gets the body he leaves with.
func _doctor_visit(b: Dictionary, news: Array, stage_: int, done: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var cur := [b]
	var build := func(rebuild: Callable) -> void:
		for c in layer.get_children():
			c.queue_free()
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc.theme = UIStyle.theme()
		layer.add_child(cc)
		var p := PanelContainer.new()
		cc.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		p.add_child(v)
		_doctor_panel(v, cur[0], news, stage_, func(nb):
			layer.queue_free()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			done.call(nb), "Back to the arena", func(nb):
			cur[0] = nb
			rebuild.call(rebuild))
	build.call(build)

func _doctor_panel(v: VBoxContainer, b: Dictionary, news: Array, stage_: int, done: Callable, done_text: String, changed: Callable) -> void:
	v.custom_minimum_size = Vector2(420, 0)
	v.add_child(UIStyle.title("The physician", 30))
	var state := Body.summary(b)
	if not news.is_empty():
		state = ", ".join(news.map(func(n): return str(n)))
		state = state.left(1).to_upper() + state.substr(1)
	v.add_child(UIStyle.label(state, 15, Color(1, 0.62, 0.5) if not news.is_empty() else UIStyle.MUTED))
	for o in Body.offers(b, stage_):
		var price := int(o.price)
		var id := String(o.id)
		var row := HBoxContainer.new()
		row.tooltip_text = String(o.desc)
		var name_l := UIStyle.label(String(o.name), 16)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_l.tooltip_text = String(o.desc)
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_l)
		var btn := UIStyle.button("%d" % price, func():
			if price > coins():
				return
			add_coins(-price)
			if Sfx:
				Sfx.play("pickup", Vector3.ZERO, 0.6)
			changed.call(Body.apply(b, id)))
		btn.disabled = price > coins()
		btn.custom_minimum_size = Vector2(80, 0)
		btn.tooltip_text = String(o.desc)
		row.add_child(btn)
		v.add_child(row)
	var foot := HBoxContainer.new()
	var purse := UIStyle.label("%d denarii" % coins(), 14, UIStyle.BRONZE)
	purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(purse)
	if done_text != "":
		foot.add_child(UIStyle.button(done_text, func(): done.call(b), true))
	v.add_child(foot)

func _pay(r: Dictionary) -> void:
	if r.has("error"):
		show_screen("yard", r.error)
		return
	if int(r.cost) > coins():
		show_screen("yard", "Not enough denarii")
		return
	add_coins(-int(r.cost))
	set_arms(r.arms)
	show_screen("yard")

## Reshaping a weapon, the smith is asked for a new one from nothing instead: the reshape is
## left as it was and a blank anvil comes up.
func scratch_from_forge(f: Node) -> void:
	# (Its going would show the smith's panel again over the new anvil.)
	for c in f.tree_exited.get_connections():
		f.tree_exited.disconnect(c.callable)
	f.done.call(null, 0)
	_scratch_forge()

## At the smith, a weapon of any kind from a blank anvil: built block by block and, taken,
## made and paid for at what it is worth; it goes in a free hand like one bought.
func _scratch_forge() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.scratch = true
	var blank := {"name": "New weapon", "kind": "weapon", "sharpness": 0.8, "voxels": [[0, 0, 0, "wood", "grip"]]}
	f.open(blank, coins(), func(design, _cost):
		f.queue_free()
		show_screen("yard")
		if design == null:
			return
		var r := Arms.buy_design(arms(), design)
		if r.has("choose"):
			_sell_choice(str(design.get("name", "it")), func(sd): return Arms.buy_design(arms(), design, sd), r.choose)
		else:
			_pay(r))
	f._show_mode("voxels")
	visible = true
	panel.visible = false
	f.tree_exited.connect(func(): panel.visible = true)

func open_forge(side: String) -> void:
	var a := arms()
	if not a.wear[side].is_empty():
		show_screen("yard", "Mend it first: the smith reshapes only a sound weapon")
		return
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(a.main if side == "R" else a.off, coins(), func(design, cost):
		if design != null:
			var arms2 := arms()
			arms2["main" if side == "R" else "off"] = design
			add_coins(-cost)
			set_arms(arms2)
		f.queue_free()
		show_screen("yard"))
	visible = true
	panel.visible = false
	f.tree_exited.connect(func(): panel.visible = true)

# ---------- Multiplayer ----------

func _mp(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("Multiplayer", 34))
	v.add_child(UIStyle.label("Fight the campaign together. The host's game runs the fight; friends join the room.", 14, UIStyle.MUTED))
	if Net.steam_available():
		_row(v, [UIStyle.button("Host a Steam lobby", func(): Net.host_steam(true), true), UIStyle.button("Friends only", func(): Net.host_steam(false)), UIStyle.button("Refresh rooms", func(): Net.list_steam_lobbies())])
		room_list = VBoxContainer.new()
		v.add_child(room_list)
		Net.list_steam_lobbies()
	else:
		v.add_child(UIStyle.label("Steam is not running: host or join by address (LAN, or a forwarded port %d)." % Net.PORT, 14, UIStyle.MUTED))
	var addr := LineEdit.new()
	addr.placeholder_text = "Host address, e.g. 192.168.1.20"
	addr.custom_minimum_size = Vector2(300, 0)
	_row(v, [UIStyle.button("Host by address", func():
		var err := Net.host_enet()
		if err != OK:
			show_screen("mp", "Could not open port %d" % Net.PORT)), addr, UIStyle.button("Join", func():
		var err := Net.join_enet(addr.text.strip_edges() if addr.text.strip_edges() != "" else "127.0.0.1")
		if err != OK:
			show_screen("mp", "Could not connect"))])
	v.add_child(UIStyle.button("Back", func(): show_screen("main")))

## Straight into a room from the command line, for testing with two windows on one machine:
## `--host` opens a room by address, `--join 127.0.0.1` joins one, `--name Guest` names you,
## `--bot` lets a bot play this window's fighter, `--lag 120 --loss 3` fakes a poor connection
## (multiplayer_test.bat).
func _cmdline_room() -> void:
	await get_tree().process_frame   # (the world root is added deferred too: a yard needs it in the tree)
	var args := OS.get_cmdline_user_args()
	cmd_bot = args.has("--bot")
	var lag := args.find("--lag")
	if lag >= 0 and args.size() > lag + 1:
		var ls := args.find("--loss")
		Net.set_lag(int(args[lag + 1]), float(args[ls + 1]) if ls >= 0 and args.size() > ls + 1 else 0.0)
	var i := args.find("--name")
	if i >= 0 and args.size() > i + 1:
		Net.my_name = args[i + 1]
	if args.has("--host"):
		if Net.host_enet() != OK:   # `connected` takes the host into the yard
			show_screen("mp", "Could not open port %d" % Net.PORT)
		return
	i = args.find("--join")
	if i >= 0:
		var addr := args[i + 1] if args.size() > i + 1 and not args[i + 1].begins_with("--") else "127.0.0.1"
		if Net.join_enet(addr) != OK:
			show_screen("mp", "Could not connect to %s" % addr)

func _on_lobbies(list: Array) -> void:
	if room_list == null or not is_instance_valid(room_list):
		return
	for c in room_list.get_children():
		c.queue_free()
	if list.is_empty():
		room_list.add_child(UIStyle.label("No open rooms. Host one and invite your friends.", 14, UIStyle.MUTED))
	for l in list:
		_row(room_list, [UIStyle.label("%s · %d/8 · %s" % [l.name, l.players, l.mode], 15), UIStyle.button("Join", func(): Net.join_steam(l.id))])

func _room(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("The room", 34))
	v.add_child(UIStyle.label("You are the host." if Net.is_host() else "Joining the host's yard...", 15, UIStyle.MUTED))
	v.add_child(UIStyle.label("· %s (you)" % Net.my_name, 16))
	for id in Net.peers:
		v.add_child(UIStyle.label("· %s" % Net.peers[id].name, 16))
	if Net.is_host():
		var cs := int(Save.get_value("coop_stage", 1))
		var nb := Data.stage(cs, 1 + Net.peers.size())
		v.add_child(UIStyle.label("Co-op campaign: bout %d · %s" % [cs, nb.get("foe_name", "")], 15, UIStyle.GOLD))
		v.add_child(UIStyle.button("Start the co-op campaign · bout %d" % cs, func(): start({"mode": "coop", "role": "host"}), true))
		v.add_child(UIStyle.button("Into the yard together (shop, heal, play)", func(): enter_yard()))
	v.add_child(UIStyle.button("Leave", func():
		Net.leave()
		in_room = false
		show_screen("mp")))

var options_tab := "game"
const OPTION_TABS := [["game", "Game"], ["controls", "Controls"], ["graphics", "Graphics"], ["sound", "Sound"]]

## Options in four tabs: the game, the controls, the picture and the sound.
func _options(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("Options", 34))
	var st: Dictionary = Save.get_value("settings", {})
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for td in OPTION_TABS:
		var key: String = td[0]
		var tb := UIStyle.button(td[1], func():
			options_tab = key
			show_screen("options"))
		tb.toggle_mode = true
		tb.button_pressed = options_tab == key
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tb)
	v.add_child(tabs)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.custom_minimum_size = Vector2(0, 330)
	v.add_child(page)
	match options_tab:
		"game": _options_game(page, st)
		"controls": _options_controls(page, st)
		"graphics": _options_graphics(page, st)
		"sound": _options_sound(page, st)
	v.add_child(UIStyle.button("Back to the game" if over_match and match_ else "Back", func():
		if over_match and match_:
			_close_overlay()
		else:
			show_screen("main")))

func _slider(lo: float, hi: float, step: float, val: float, cb: Callable) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.custom_minimum_size = Vector2(320, 24)
	sl.value_changed.connect(cb)
	return sl

## A setting's row: its name in a column of its own, the control, a word on what it does.
func _opt_row(v: Control, name_: String, ctl: Control, note := "") -> void:
	var l := UIStyle.label(name_, 16)
	l.custom_minimum_size = Vector2(190, 0)
	var items: Array = [l, ctl]
	if note != "":
		var n := UIStyle.label(note, 14, UIStyle.MUTED)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		items.append(n)
	_row(v, items)
	# (_row keeps labels on one line; the note may wrap.)
	if note != "":
		(items[2] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _check(text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(cb)
	return c

func _options_game(v: VBoxContainer, st: Dictionary) -> void:
	var gore := OptionButton.new()
	gore.add_item("Full")
	gore.add_item("Reduced")
	gore.select(1 if str(st.get("gore", "full")) == "reduced" else 0)
	gore.item_selected.connect(func(k): _set_opt("gore", "reduced" if k == 1 else "full"))
	_opt_row(v, "Gore", gore, "Reduced: the insides drawn as plain flesh, no guts spill. The wounds hurt the same. From the next fight.")
	var dsel := OptionButton.new()
	var dopts := ["off", "sometimes", "always"]
	for o in ["No decrees", "Decrees sometimes", "Decrees always"]:
		dsel.add_item(o)
	dsel.select(dopts.find(str(st.get("decrees", "sometimes"))))
	dsel.item_selected.connect(func(i): _set_opt("decrees", dopts[i]))
	_opt_row(v, "The Emperor's decrees", dsel, "Odd rules the Emperor lays on an arena duel.")
	v.add_child(_check("Kill cam: the best kill replayed at the end of a fight (alone and online)", bool(st.get("killcam", true)), func(on): _set_opt("killcam", on)))

func _options_controls(v: VBoxContainer, st: Dictionary) -> void:
	_opt_row(v, "Mouse sensitivity", _slider(0.3, 2.5, 0.05, float(st.get("sensitivity", 1.0)), func(x): _set_opt("sensitivity", x)))
	v.add_child(_check("Left-handed (the right button swings the main weapon)", bool(st.get("leftHanded", false)), func(on): _set_opt("leftHanded", on)))
	v.add_child(_check("Invert vertical look", bool(st.get("invertY", false)), func(on): _set_opt("invertY", on)))
	v.add_child(UIStyle.button("Rebind keys · gamepad", func(): show_screen("controls")))
	v.add_child(UIStyle.label("Mouse looks; hold the left button and move the mouse to swing the main hand, the right button for the shield. WASD move, Shift run, Space jump, Ctrl crouch, E kick, C thrust, the wheel turns the blade, H takes it in both hands, J swaps hands, Esc frees the mouse.", 15, UIStyle.MUTED))

func _options_graphics(v: VBoxContainer, st: Dictionary) -> void:
	var q := OptionButton.new()
	var levels := ["low", "medium", "high", "ultra"]
	for l in levels:
		q.add_item(l.capitalize())
	q.select(maxi(0, levels.find(str(st.get("quality", "high")))))
	q.item_selected.connect(func(i): _set_opt("quality", levels[i]))
	_opt_row(v, "Graphics", q, "Low: no shadows or effects lighting. Ultra: global illumination and fog.")
	var aa := OptionButton.new()
	for a in AA_MODES:
		aa.add_item(a[1])
	aa.select(maxi(0, AA_MODES.map(func(a): return a[0]).find(str(st.get("aa", "msaa4")))))
	aa.item_selected.connect(func(i):
		_set_opt("aa", AA_MODES[i][0])
		apply_picture(Save.get_value("settings", {})))
	_opt_row(v, "Anti-aliasing", aa, "MSAA smooths the edges of the blocks and keeps everything else sharp (4x is the best balance; 8x for strong cards). FXAA is the lightest but blurs the picture.")
	var vao := _check("Voxel shading: corners and creases between blocks in soft shadow", bool(st.get("voxelAO", true)), func(on):
		_set_opt("voxelAO", on)
		apply_picture(Save.get_value("settings", {})))
	v.add_child(vao)
	var look := OptionButton.new()
	for k in Physique.STYLES:
		look.add_item(Physique.NAMES[k])
	look.select(maxi(0, Physique.STYLES.find(Physique.current())))
	look.item_selected.connect(func(i):
		_set_opt("physique", Physique.STYLES[i])
		look.tooltip_text = Physique.BLURB[Physique.STYLES[i]]
		Physique.restyle_all(get_tree().root))
	look.tooltip_text = Physique.BLURB[Physique.current()]
	_opt_row(v, "Gladiators' look", look, "How the gladiators are drawn: " + " ".join(Physique.STYLES.map(func(k): return Physique.NAMES[k] + ": " + Physique.BLURB[k]))
		+ " Only the drawing: every cut, organ and limb works the same. Changes at once.")
	if Match.SMOOTH_BODIES_OFFERED:
		var bo := OptionButton.new()
		bo.add_item("Smooth")
		bo.add_item("Blocky voxels")
		bo.select(1 if str(st.get("bodies", "smooth")) == "blocky" else 0)
		bo.item_selected.connect(func(i): _set_opt("bodies", "blocky" if i == 1 else "smooth"))
		_opt_row(v, "Bodies", bo, "Smooth: a skin drawn over the voxels (they still take every cut). Applies from the next fight.")
	var dm := OptionButton.new()
	for d in DISPLAY_MODES:
		dm.add_item(d[1])
	dm.select(maxi(0, DISPLAY_MODES.map(func(d): return d[0]).find(display_mode(st))))
	dm.item_selected.connect(func(i):
		_set_opt("display", DISPLAY_MODES[i][0])
		apply_display(Save.get_value("settings", {})))
	_opt_row(v, "Display", dm, "F11 toggles full screen.")
	var ws := OptionButton.new()
	var sizes := window_sizes()
	var scr := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	for w in sizes:
		ws.add_item(("%d × %d (this screen)" if w == scr else "%d × %d") % [w.x, w.y])
	ws.select(maxi(0, sizes.find(Vector2i(st.get("windowW", 1600), st.get("windowH", 900)))))
	ws.item_selected.connect(func(i):
		_set_opt("windowW", sizes[i].x)
		_set_opt("windowH", sizes[i].y)
		apply_display(Save.get_value("settings", {})))
	_opt_row(v, "Window", ws)
	var rs := OptionButton.new()
	for r in RENDER_SCALES:
		rs.add_item(r[1])
	rs.select(maxi(0, RENDER_SCALES.map(func(r): return r[0]).find(str(st.get("renderScale", "auto")))))
	rs.item_selected.connect(func(i):
		_set_opt("renderScale", RENDER_SCALES[i][0])
		apply_render_scale(Save.get_value("settings", {})))
	_opt_row(v, "3D resolution", rs, "Auto: full up to 1440p, sharpened down on 4K and wider screens. Menus are always sharp.")
	var vs := CheckBox.new()
	vs.text = "VSync"
	vs.button_pressed = bool(st.get("vsync", true))
	vs.toggled.connect(func(on):
		_set_opt("vsync", on)
		apply_frame(Save.get_value("settings", {})))
	_opt_row(v, "VSync", vs, "Draws in step with the screen: no tearing, no wasted frames.")
	var fc := OptionButton.new()
	for f in FPS_CAPS:
		fc.add_item(f[1])
	fc.select(maxi(0, FPS_CAPS.map(func(f): return f[0]).find(int(st.get("fpsCap", 0)))))
	fc.item_selected.connect(func(i):
		_set_opt("fpsCap", FPS_CAPS[i][0])
		apply_frame(Save.get_value("settings", {})))
	_opt_row(v, "Frame rate cap", fc, "A ceiling on the frames drawn a second: cooler and quieter on a strong PC, steadier on a laptop.")
	var us := OptionButton.new()
	for u in UI_SCALES:
		us.add_item(u[1])
	us.select(maxi(0, UI_SCALES.map(func(u): return u[0]).find(snappedf(float(st.get("uiScale", 1.0)), 0.01))))
	us.item_selected.connect(func(i):
		_set_opt("uiScale", UI_SCALES[i][0])
		apply_ui_scale(Save.get_value("settings", {})))
	_opt_row(v, "Text and menus", us, "The size of the menus and the HUD: larger for a TV, a 4K screen or the Deck. Changes at once.")

func _options_sound(v: VBoxContainer, st: Dictionary) -> void:
	_opt_row(v, "Sound", _slider(0.0, 1.0, 0.05, float(st.get("volume", 0.8)), func(x):
		_set_opt("volume", x)
		Sfx.volume = x))
	_opt_row(v, "Music", _slider(0.0, 1.0, 0.05, float(st.get("music", 0.5)), func(x):
		_set_opt("music", x)
		if Sfx.music:
			Sfx.music.set_volume(x)))

const DISPLAY_MODES := [["fullscreen", "Full screen"], ["exclusive", "Full screen (exclusive)"], ["maximized", "Window, maximized"], ["windowed", "Window"]]
const AA_MODES := [["off", "Off"], ["fxaa", "FXAA (soft)"], ["smaa", "SMAA"], ["msaa2", "MSAA 2x"], ["msaa4", "MSAA 4x"], ["msaa8", "MSAA 8x"]]

## The picture's finish from the settings: the anti-aliasing of the window (MSAA keeps the
## voxels' edges smooth and the rest sharp; FXAA blurs the whole frame a little) and the voxels'
## corner shading.
static func apply_picture(st: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var vp: Viewport = tree.root
		var mode := str(st.get("aa", "msaa4"))
		vp.msaa_3d = {"msaa2": Viewport.MSAA_2X, "msaa4": Viewport.MSAA_4X, "msaa8": Viewport.MSAA_8X}.get(mode, Viewport.MSAA_DISABLED)
		vp.screen_space_aa = {"fxaa": Viewport.SCREEN_SPACE_AA_FXAA, "smaa": Viewport.SCREEN_SPACE_AA_SMAA}.get(mode, Viewport.SCREEN_SPACE_AA_DISABLED)
	VoxelPart.set_ao(bool(st.get("voxelAO", true)))
# The common screens of today: 16:9, 16:10, 21:9 and 32:9, laptop to 4K. The menu offers the
# ones that fit this screen, and the screen's own size.
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1536, 864), Vector2i(1600, 900),
	Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(2560, 1600),
	Vector2i(3440, 1440), Vector2i(3840, 1600), Vector2i(3840, 2160), Vector2i(5120, 1440), Vector2i(5120, 2160)]
const RENDER_SCALES := [["auto", "Auto"], ["1.0", "100%"], ["0.85", "85%"], ["0.75", "75%"], ["0.6", "60%"], ["0.5", "50%"]]

## The window sizes to choose from on this screen: those that fit, and the screen itself.
static func window_sizes() -> Array:
	var out := []
	var scr := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1920, 1080)
	for w in WINDOW_SIZES:
		if w.x <= scr.x and w.y <= scr.y:
			out.append(w)
	if not out.has(scr):
		out.append(scr)
	return out

## The 3D picture's resolution: the whole of it up to about 1440p, then drawn smaller and
## sharpened up (FSR) so a 4K or a 5K screen keeps its frame rate; the menus stay sharp.
static func apply_render_scale(st: Dictionary) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root if Engine.get_main_loop() is SceneTree else null
	if root == null:
		return
	var pick := str(st.get("renderScale", "auto"))
	var k := 1.0
	if pick == "auto":
		var px := float(root.size.x) * float(root.size.y)
		k = clampf(sqrt(2560.0 * 1440.0 / maxf(1.0, px)), 0.6, 1.0)
	else:
		k = clampf(float(pick), 0.5, 1.0)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if k >= 0.999 else Viewport.SCALING_3D_MODE_FSR
	root.scaling_3d_scale = k

## The display mode in the settings (older saves had a fullscreen flag; a new one starts full screen).
static func display_mode(st: Dictionary) -> String:
	if st.has("display"):
		return str(st.display)
	if st.has("fullscreen"):
		return "fullscreen" if st.fullscreen else "windowed"
	return "fullscreen"

static func apply_display(st: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Smaller than this nothing on the screen can be read.
	DisplayServer.window_set_min_size(Vector2i(960, 540))
	apply_render_scale.call_deferred(st)
	match display_mode(st):
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"exclusive":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"maximized":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var sz := Vector2i(int(st.get("windowW", 1600)), int(st.get("windowH", 900)))
			var screen := DisplayServer.screen_get_usable_rect().size
			sz = Vector2i(mini(sz.x, screen.x), mini(sz.y, screen.y))
			DisplayServer.window_set_size(sz)
			DisplayServer.window_set_position(DisplayServer.screen_get_usable_rect().position + (screen - sz) / 2)

const FPS_CAPS := [[0, "Off"], [30, "30"], [60, "60"], [72, "72"], [90, "90"], [120, "120"], [144, "144"], [165, "165"], [240, "240"]]
const UI_SCALES := [[0.8, "Smaller"], [0.9, "Small"], [1.0, "Normal"], [1.15, "Large"], [1.3, "Larger"], [1.5, "Largest"]]

## VSync and the frame-rate cap from the settings.
static func apply_frame(st: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(st.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = clampi(int(st.get("fpsCap", 0)), 0, 500)

## The size of everything drawn flat (menus, HUD) from the settings: the window's content scale.
static func apply_ui_scale(st: Dictionary) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root if Engine.get_main_loop() is SceneTree else null
	if root == null:
		return
	root.content_scale_factor = clampf(float(st.get("uiScale", 1.0)), 0.7, 1.6)

static func set_fullscreen(on: bool) -> void:
	var st: Dictionary = Save.get_value("settings", {})
	st.display = "fullscreen" if on else "windowed"
	Save.set_value("settings", st)
	apply_display(st)

## F11 anywhere (in a fight too): full screen or back to the window.
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		var on := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		set_fullscreen(on)
		get_viewport().set_input_as_handled()
		return
	_input_more(e)

func _set_opt(k: String, val) -> void:
	var st: Dictionary = Save.get_value("settings", {})
	st[k] = val
	Save.set_value("settings", st)

# ---------- Matches ----------

var last_start := {}   # what the match running now was started with (R plays it again)

func start(opts: Dictionary) -> void:
	# Co-op is the campaign for a party: the same ladder of bouts, foes for every friend, its
	# own progress (it does not move your solo campaign on).
	if opts.get("mode") == "coop":
		opts.mode = "campaign"
		opts.coop = true
		opts.stage = int(Save.get_value("coop_stage", 1))
	# Hosting a room, every fight (and the yard) takes the whole room along, not only the
	# campaign: the guests are sent the start and join as themselves.
	if not opts.has("role") and Net.active() and Net.is_host() and not ["training", "circus"].has(String(opts.get("mode", ""))) and not opts.get("tutorial", false):
		opts.role = "host"   # (alone in the room too: whoever joins is brought into what runs)
	last_start = opts.duplicate(true)
	_end_match()
	var a := arms()
	var lo := Arms.loadout(a)
	opts.name = Save.get_value("name", "Gladiator")
	if opts.mode == "campaign":
		opts.loadout = {"main": lo.main, "off": lo.off}
		opts.worn = lo.worn
		if int(opts.get("stage", 1)) <= 1:
			set_body(Body.empty())
		opts.body = body()
	else:
		opts.loadout = opts.get("loadout_override", {"main": "gladius", "off": "roundShield"})
	if opts.get("autopilot", false) or cmd_bot:
		opts.autopilot = true
	var lk := look()
	opts.loadout = opts.loadout.duplicate()
	opts.loadout.armor = opts.loadout.get("armor", []) + look_armor(lk)
	var geared: bool = opts.mode == "campaign" or opts.mode == "yard"
	if geared:
		opts.loadout.armor += worn_armor()
		opts.loadout["armor_defs"] = Armory.defs_of(worn_armor())
		opts.loadout["armor_wear"] = armor_wear()
	opts.skin = Fighter.SKINS[lk.skin]
	opts.color = CLOTH[lk.cloth]
	opts.inventory = opts.get("inventory_override", kit())
	# The decrees are drawn here, so the guests can be told them before anyone is spawned.
	if (opts.mode == "duel" or opts.mode == "chaos") and not opts.has("decrees"):
		var setting: String = Save.get_value("settings", {}).get("decrees", "sometimes")
		var rng2 := RandomNumberGenerator.new()
		rng2.randomize()
		var picked: Array = [] if setting == "off" else Decrees.roll(1.0 if opts.mode == "chaos" or setting == "always" else 0.6, 3 if opts.mode == "chaos" else 1, rng2)
		opts.decrees = picked.map(func(d): return d.id)
		opts.hazards = Hazards.random_specs(Decrees.combine(picked).hazards, rng2)
	if opts.get("role", "local") == "host":
		var peers := []
		for id in Net.peers:
			peers.append(_peer_spec(int(id), geared, int(opts.get("stage", 1)) > 1))
		opts.peers = peers
		Net.send_all("start", {"mode": opts.mode, "stage": opts.get("stage", 1), "coop": opts.get("coop", false), "decrees": opts.get("decrees", []), "hazards": opts.get("hazards", []), "circus": {"day": opts.get("circus", {}).get("day", 0), "bout_index": opts.get("circus", {}).get("bout_index", 0)}})
		Net.set_lobby_info("Campaign · stage %d" % opts.get("stage", 1))
	match_ = Match.new()
	world_root.add_child(match_)
	match_.setup(opts)
	_apply_input_settings()
	match_.finished.connect(_on_finished)
	match_.doctor.connect(func(e, b, news): _doctor_visit(b, news, match_.stage, func(nb): match_.doctor_done(e.id, nb)))
	hud = Hud.new(match_)
	world_root.add_child(hud)
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Sfx.music:
		Sfx.music.set_state("boss" if match_.enemies().any(func(e): return e.get("boss", false)) else "fight")

func _backdrop_on() -> void:
	if backdrop or match_ or not visible or DisplayServer.get_name() == "headless" or not world_root.is_inside_tree():
		return
	backdrop = Match.new()
	world_root.add_child(backdrop)
	backdrop.attract = true
	backdrop.setup({"mode": "ffa", "autopilot": true, "decrees": [], "hazards": [], "seed": randi()})
	if backdrop.input:
		backdrop.input.set_process_unhandled_input(false)
		backdrop.input.set_process(false)
	backdrop.finished.connect(func(_r): _backdrop_restart.call_deferred())
	_stage_hero()
	Sfx.backdrop_mul = 0.0   # the fight behind the menus is seen, not heard
	bg.visible = false
	shade.visible = true

## The title shot: a champion in bronze stands close to the camera on the right, the fight goes
## on behind him, embers and petals drift past, and a column with an SPQR banner frames the left.
func _stage_hero() -> void:
	var b := backdrop
	var cam_pos := Vector3(0.0, 1.05, -13.3)
	b.hero_cam = {"pos": cam_pos, "look": Vector3(-0.35, 1.5, -3.0)}
	b.cam.global_position = cam_pos
	b.cam.fov = 55.0
	_dress_hero()
	b.hero_inp = {"main": {"x": 0.45, "y": -0.4}, "off": {"x": -0.6, "y": -0.3}}
	_frame_hero()
	var drift := Node3D.new()
	b.add_child(drift)
	drift.global_position = cam_pos + Vector3(0, 0.2, 3.2)
	b.fx.emitter("embers", drift, 60, 2.6)
	b.fx.emitter("petals", drift, 14, 2.8)
	# The column and its banner, just off the left of the shot.
	if VoxelArt.place(b, "column", Vector3(3.4, 0.0, -8.4), 0.4) != null and VoxelArt.place(b, "banner", Vector3(2.75, 1.1, -8.75), PI) != null:
		return
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.45, 0.4)
	stone.roughness = 0.9
	var colm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.36
	cm.height = 6.0
	cm.radial_segments = 16
	cm.material = stone
	colm.mesh = cm
	b.add_child(colm)
	colm.global_position = Vector3(3.4, 3.0, -8.4)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.45, 0.06, 0.05)
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ban := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(1.1, 2.4)
	bq.material = cloth
	ban.mesh = bq
	b.add_child(ban)
	ban.global_position = Vector3(2.75, 2.3, -8.75)
	ban.rotation.y = PI
	var spqr := Label3D.new()
	spqr.text = "S·P·Q·R"
	spqr.font = UIStyle.serif(2)
	spqr.font_size = 64
	spqr.pixel_size = 0.004
	spqr.modulate = UIStyle.GOLD
	spqr.outline_size = 0
	ban.add_child(spqr)
	spqr.position = Vector3(0, -0.55, 0.01)

## The champion wears the player's look (and, on the title screen, gilded armour).
func _dress_hero() -> void:
	if backdrop == null:
		return
	var lk := look()
	var armor := look_armor(lk)
	if screen != "gladiator":
		armor = ["goldHelmet", "goldLorica", "manica", "greaves"] + armor
	# He stands facing the camera of the screen he is on (a touch turned, his sword side forward),
	# not side-on to it.
	var cam_at: Vector3 = _hero_cam().pos
	var yaw := atan2(cam_at.x - HERO_POS.x, cam_at.z - HERO_POS.z) - 0.2
	backdrop.add_hero(HERO_POS, yaw, {"main": "gladius", "off": "scutum", "armor": armor}, Color.hex(CLOTH[lk.cloth] << 8 | 0xff), Fighter.SKINS[lk.skin], screen == "gladiator")

## The title shot, or a close look at the champion while he is being dressed.
func _frame_hero() -> void:
	backdrop.hero_cam = _hero_cam()

func _hero_cam() -> Dictionary:
	if screen == "gladiator":
		return {"pos": HERO_POS + Vector3(1.9, 1.35, -2.6), "look": HERO_POS + Vector3(0.55, 1.05, 0)}
	return {"pos": Vector3(0.0, 1.05, -13.3), "look": Vector3(-0.35, 1.5, -3.0)}

func _gladiator(v: VBoxContainer) -> void:
	panel.custom_minimum_size.x = 620
	v.add_child(UIStyle.title("Your gladiator", 34))
	v.add_child(UIStyle.label("How the crowd will know you. The champion on the right wears it as you choose.", 14, UIStyle.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = Save.get_value("name", "Gladiator")
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(300, 0)
	name_edit.text_changed.connect(func(tx):
		Save.set_value("name", tx)
		Net.my_name = tx)
	_row(v, [UIStyle.label("Name", 15, UIStyle.MUTED), name_edit])
	var lk := look()
	v.add_child(UIStyle.label("Skin", 15, UIStyle.MUTED))
	_swatches(v, Fighter.SKINS, lk.skin, func(i): _set_look("skin", i))
	v.add_child(UIStyle.label("Loincloth and cape", 15, UIStyle.MUTED))
	_swatches(v, CLOTH, lk.cloth, func(i): _set_look("cloth", i))
	for k in ["hat", "hair", "beard", "cape"]:
		var ob := OptionButton.new()
		for id in LOOK_SLOTS[k]:
			ob.add_item("None" if id == "" else String(Data.armor.get(id, {}).get("name", id)))
		ob.select(lk[k])
		ob.custom_minimum_size = Vector2(260, 0)
		ob.item_selected.connect(func(i): _set_look(k, i))
		var kl := UIStyle.label(k.capitalize(), 15, UIStyle.MUTED)
		kl.custom_minimum_size = Vector2(64, 0)   # the four drop-downs in one column
		ob.custom_minimum_size = Vector2(220, 0)
		_row(v, [kl, ob])
	_row(v, [UIStyle.button("Random", func():
		var r := {}
		r.skin = randi() % Fighter.SKINS.size()
		r.cloth = randi() % CLOTH.size()
		for k in LOOK_SLOTS:
			r[k] = randi() % LOOK_SLOTS[k].size()
		Save.set_value("look", r)
		_net_loadout()
		show_screen("gladiator")), UIStyle.button("Done", func(): show_screen("main"), true)])
	_dress_hero.call_deferred()

func _swatches(v: VBoxContainer, colors: Array, sel: int, cb: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		var st := StyleBoxFlat.new()
		st.bg_color = Color.hex(int(colors[i]) << 8 | 0xff)
		st.set_corner_radius_all(22)
		st.set_border_width_all(3 if i == sel else 1)
		st.border_color = UIStyle.GOLD if i == sel else Color(0, 0, 0, 0.6)
		b.add_theme_stylebox_override("normal", st)
		var hv := st.duplicate()
		hv.border_color = Color(1, 0.9, 0.6)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.pressed.connect(func(): cb.call(i))
		h.add_child(b)
	v.add_child(h)

func _set_look(k: String, i: int) -> void:
	var l := look()
	l[k] = i
	Save.set_value("look", l)
	_net_loadout()
	if k == "skin" or k == "cloth":
		show_screen("gladiator")
	else:
		_dress_hero()

## The fight behind the menus is over: after a moment fresh men come in where it was fought.
## Only the fighters are replaced (built anew, the whole scene came back with its camera from
## the start and the champion in front settled again: the screen visibly reset).
func _backdrop_restart() -> void:
	await get_tree().create_timer(2.5).timeout
	if backdrop:
		backdrop.restart_attract({"mode": "ffa", "autopilot": true, "decrees": [], "hazards": [], "seed": randi()})
		if backdrop.input:
			backdrop.input.set_process_unhandled_input(false)
			backdrop.input.set_process(false)

func _backdrop_off() -> void:
	if backdrop:
		backdrop.queue_free()
		world_root.remove_child(backdrop)
		backdrop = null
	Sfx.backdrop_mul = 1.0
	bg.visible = true

## The player's own keys, sensitivity and hand go to every match he plays in, a guest's too.
func _apply_input_settings() -> void:
	var st: Dictionary = Save.get_value("settings", {})
	if match_ and match_.input:
		match_.input.setup_actions(bindings())
		match_.input.sensitivity = float(st.get("sensitivity", 1.0))
		match_.input.left_handed = bool(st.get("leftHanded", false))
		match_.input.invert_y = bool(st.get("invertY", false))

func _end_match() -> void:
	_backdrop_off()
	if match_:
		match_.queue_free()
		match_ = null
	if hud:
		hud.queue_free()
		hud = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_finished(r: Dictionary) -> void:
	var was := match_
	# Five seconds on the banner over the arena, to take in how the bout ended (Space or Enter
	# goes on sooner, but not in the first moment, nor a mouse button still held from the fight).
	var wait_until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < wait_until and match_ == was:
		await get_tree().process_frame
		if Time.get_ticks_msec() > wait_until - 3500 and (Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)):
			break
	if match_ != was:
		return   # restarted (R) in the meantime
	var mode := match_.mode if match_ else "campaign"
	if match_ and match_.tut and match_.tut.finished:
		Save.set_value("tutorial_done", true)
	var mission_text := _settle_missions(r, match_.mode if match_ else "")
	if mode == "circus" and match_ and match_.role != "guest":
		var inv: Dictionary = match_.me.get("inventory", {}) if match_.me else {}
		_end_match()
		_circus_finished(r, inv)
		return
	if match_ and match_.me and match_.role != "guest" and mode != "circus":
		set_kit(match_.me.get("inventory", kit()))
	if mode == "campaign" and match_ and match_.role == "guest":
		# A guest's own sword takes its knocks too: the host does not keep it, he does.
		set_arms(Arms.add_wear(arms(), match_.my_wear()))
	if mode == "campaign" and match_ and match_.role != "guest":
		var sk := "coop_stage" if r.get("coop", false) else "stage"
		var ck := "coop_checkpoint" if r.get("coop", false) else "checkpoint"
		if r.get("body") is Dictionary:
			set_body(r.body)
		set_arms(Arms.add_wear(arms(), r.get("wear", {})))
		set_armor_wear(Armory.add_wear(armor_wear(), r.get("wear", {}).get("armor", {}), worn_armor()))
		if r.won:
			add_coins(int(r.pay))
			if r.get("checkpoint") != null:
				Save.set_value(ck, int(r.checkpoint))
			Save.set_value(sk, int(r.stage) + 1)
			last_result = {"text": "Stage %d cleared: %d denarii." % [r.stage, r.pay]}
			if int(r.stage) >= Data.campaign.get("stages", []).size():
				# The last bout won: the rudis. The campaign begins again, the same man and his
				# gear, the foes a third tougher each time round (lap).
				var lk := "coop_lap" if r.get("coop", false) else "lap"
				var kills := int(r.get("kills", {}).size()) if r.get("kills") is Dictionary else 0
				Save.set_value("hall", Circus.hall_add(Save.get_value("hall", []), Save.get_value("name", "Gladiator"),
					{"day": 7, "won": true, "kills": kills, "bouts_won": int(r.stage), "campaign": true}, ""))
				Save.set_value(lk, int(Save.get_value(lk, 1)) + 1)
				Save.set_value(sk, 1)
				Save.set_value(ck, 1)
				if Net.active():
					Net.send_all("campaign_end", {})
				_end_match()
				show_screen("campaign_end")
				return
			if Edition.demo_over(int(r.stage) + 1):
				# The demo's last boss down: what the full game holds, for the whole party.
				if Net.active():
					Net.send_all("demo_end", {})
				_end_match()
				show_screen("demo_end")
				return
		else:
			# A death ends the campaign: the next one begins at the first bout, with a beginner's
			# purse, stick and body (online and alone alike; the host's word is the party's).
			Save.set_value(sk, 1)
			Save.set_value("coop_lap" if r.get("coop", false) else "lap", 1)
			Save.set_value("run_seed", randi())   # a new run: other oddities at the smith
			Save.set_value("oddities_sold", {})
			Save.set_value(ck, 1)
			Save.set_value("coins", START_COINS)
			set_body(Body.empty())
			set_arms(Arms.empty())
			set_worn_armor([])
			set_armor_wear({})
			if Net.active():
				Net.send_all("purse", coins())
			last_result = {"text": "You fell. The campaign is over; a new one begins at bout 1."}
	_end_match()
	if Net.active() and not Net.is_host():
		show_screen("room")
	else:
		# Between bouts of the campaign the gladiator goes back to the yard, the lobby: the
		# smith, the market, the physician, friends, and the gate to the next bout.
		if hub or mode == "campaign" or (Net.active() and Net.is_host()):
			enter_yard(((last_result.get("text", "") + " · ") if mode == "campaign" and last_result.get("text", "") != "" else "") + mission_text)
		else:
			show_screen("yard" if mode == "campaign" else "main", mission_text)

func _on_net(type: String, data, _from: int) -> void:
	match type:
		"start":
			if not Net.is_host():
				_end_match()
				match_ = Match.new()
				world_root.add_child(match_)
				var ids: Array = (data.get("decrees", []) as Array).filter(func(i): return not Decrees.by_id(str(i)).is_empty()) if data.get("decrees") is Array else []
				var hz: Array = (data.get("hazards", []) as Array).filter(func(h): return h is Dictionary and ["spikes", "blade", "chariot"].has(h.get("type"))).slice(0, 8) if data.get("hazards") is Array else []
				if data.mode == "campaign" and int(data.stage) <= 1:
					set_body(Body.empty())
				match_.setup({"mode": data.mode, "stage": data.stage, "coop": bool(data.get("coop", false)), "role": "guest", "autopilot": cmd_bot, "decrees": ids, "hazards": hz, "circus": data.get("circus", {}) if data.get("circus") is Dictionary else {}})
				_apply_input_settings()
				match_.finished.connect(_on_finished)
				if data.mode == "yard":
					# A guest has the yard as the host has it: the stalls open for him too.
					hub = true
					match_.station.connect(_open_station)
				hud = Hud.new(match_)
				world_root.add_child(hud)
				visible = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		"spawn":
			if match_:
				match_.guest_spawn(data)
		"despawn":
			if match_ and data is Dictionary:
				match_.guest_despawn(int(data.get("id", -1)))
		"body":
			# The host's word on what the stage left on me (a fall: whole again).
			if data is Dictionary and not Net.is_host():
				set_body(data)
		"armor_wear":
			# The plates the bout knocked off my armour (the host saw them go).
			if data is Dictionary and not Net.is_host():
				set_armor_wear(Armory.add_wear(armor_wear(), data, worn_armor()))
		"doctor":
			if data is Dictionary and not Net.is_host():
				_doctor_visit(Body.sanitize(data.get("body", {})), (data.get("news", []) as Array).map(func(x): return str(x).left(80)) if data.get("news") is Array else [], int(data.get("stage", 1)), func(nb): Net.send_host("doctor_done", nb))
		"doctor_done":
			if match_ and Net.is_host() and data is Dictionary:
				for e in match_.humans():
					if e.kind == "remote" and int(e.peer) == _from:
						match_.doctor_done(e.id, Body.sanitize(data))
		"snap":
			if match_:
				match_.apply_snapshot(data)
		"vox":
			if match_:
				match_.guest_vox(data)
		"wvox":
			if match_:
				match_.guest_wvox(data)
		"banner":
			if match_:
				match_.banner.emit(data.text, data.sub)
		"isnap", "zone", "spot", "feed", "wloose", "wspawn", "wpick", "lsnap", "fx", "guts", "gutp", "kc", "kcr", "yard_next":
			if match_:
				match_.guest_message(type, data)
		"purse":
			# The party's purse, as the host counts it.
			if not Net.is_host() and (data is int or data is float):
				shared_purse = maxi(0, int(data))
				if screen != "" and visible:
					show_screen(screen)
		"demo_end":
			if not Net.is_host():
				_end_match()
				show_screen("demo_end")
		"campaign_end":
			if not Net.is_host():
				_end_match()
				show_screen("campaign_end")
		"purse_add":
			if Net.is_host() and (data is int or data is float):
				add_coins(clampi(int(data), -5000, 5000))
		"end":
			if match_:
				# (The pay went into the party's purse on the host's side.)
				match_.guest_end(data)

func _unhandled_input(e: InputEvent) -> void:
	# F12: a screenshot (with Steam running, Steam takes its own on the same key).
	if e is InputEventKey and e.pressed and not e.is_echo() and e.keycode == KEY_F12 and not Net.steam_ready:
		_screenshot()
		return
	# R: the stage (the bout, the training) again from the start. Alone only: in a room the
	# host's match is everyone's.
	# (Not in the campaign: a bout there is not taken back; Esc offers a fresh campaign instead.)
	if e.is_action_pressed("va_restart") and not e.is_echo() and match_ and not visible and pause_layer == null and not Net.active() and not last_start.is_empty() and not in_yard() and String(last_start.get("mode", "")) != "campaign":
		start(last_start.duplicate(true))
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and (in_yard() or over_match) and visible and match_:
		_close_overlay()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and match_ and not visible:
		_toggle_pause()

## The end of the demo: the second boss is down. The campaign stops here; the demo again from
## bout 1, or back to the menu.
## The campaign won: the rudis, the wooden sword of a gladiator set free. The next campaign
## waits in the yard, the same man and his gear, the foes tougher (Match.lap).
func _campaign_end(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 12)
	var lap := int(Save.get_value("coop_lap" if Net.active() else "lap", 2))
	v.add_child(UIStyle.title("THE RUDIS", 40))
	v.add_child(UIStyle.label("The Emperor rises. The crowd is on its feet. The wooden sword is put in your hand: %d bouts, every beast and monster of the ladder, and you are free." % Data.campaign.get("stages", []).size(), 17, UIStyle.TEXT))
	v.add_child(UIStyle.label("Your name is in the Hall of Fame.", 15, UIStyle.GOLD))
	v.add_child(UIStyle.label("But the arena calls. Campaign %s waits in the yard: your gladiator, his arms and his purse as they are; the foes a third tougher, the beasts bigger." % ROMAN[clampi(lap - 1, 0, 6)], 15, UIStyle.MUTED))
	v.add_child(UIStyle.button("Back to the ludus", func(): show_screen("main" if not Net.active() else "room"), true))

func _demo_end(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 12)
	v.add_child(UIStyle.title("The end of the demo", 40))
	v.add_child(UIStyle.label("You have fought through all %d bouts of the demo." % Edition.DEMO_STAGES, 17, UIStyle.TEXT))
	if not Net.active() or Net.is_host():
		v.add_child(UIStyle.button("Play the demo again from bout 1", func():
			Save.set_value("coop_stage", 1)
			Save.set_value("coop_checkpoint", 1)
			restart_campaign(), true))
	v.add_child(UIStyle.button("Main menu" if not Net.active() else "Back to the room", func(): show_screen("main" if not Net.active() else "room")))

## A screenshot of the game as it is on screen, into the screenshots folder (Pictures/WRECKSMITH
## where there is one, else the game's own data folder).
func _screenshot() -> String:
	var img := get_viewport().get_texture().get_image()
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	var dir := pics.path_join("WRECKSMITH") if pics != "" else ProjectSettings.globalize_path("user://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("wrecksmith_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	if img.save_png(path) != OK:
		return ""
	if match_ and is_instance_valid(match_):
		match_.feed.emit("Screenshot saved: " + path.get_file())
	return path

## A new campaign: back to bout 1, the body whole, the arms and the bag as for a beginner.
func restart_campaign() -> void:
	Save.set_value("run_seed", randi())   # a new run: other oddities at the smith
	Save.set_value("oddities_sold", {})
	Save.set_value("coins", START_COINS)
	Save.set_value("stage", 1)
	Save.set_value("checkpoint", 1)
	Save.set_value("lap", 1)
	Save.set_value("coop_lap", 1)
	set_body(Body.empty())
	set_arms(Arms.empty())
	set_worn_armor([])
	set_armor_wear({})
	# Back to the yard, not straight into bout 1: the smith, the market and the gate first
	# (online the host brings the whole party back with him).
	enter_yard("A new campaign begins")

func _toggle_pause() -> void:
	if pause_layer:
		pause_layer.queue_free()
		pause_layer = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not Net.active():
			get_tree().paused = false
		return
	pause_layer = CanvasLayer.new()
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.theme = UIStyle.theme()
	pause_layer.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UIStyle.title("Paused", 30))
	v.add_child(UIStyle.button("Back to the fight", _toggle_pause, true))
	if forge_trying != null:
		v.add_child(UIStyle.button("Back to the forge", func():
			_toggle_pause()
			back_to_forge(), true))
	if match_ and (match_.mode == "campaign" or match_.mode == "yard") and (not Net.active() or Net.is_host()):
		# Twice, to be sure: the whole campaign over from bout 1, whole of body, bare of arms.
		var rb := UIStyle.button("Restart the campaign", func(): pass)
		rb.pressed.connect(func():
			if not rb.has_meta("armed"):
				rb.set_meta("armed", true)
				rb.text = "Click again: start over from bout 1 (all progress lost)"
				return
			_toggle_pause()
			get_tree().paused = false
			restart_campaign())
		v.add_child(rb)
	# Settings for every player, the host and his guests alike (the game runs on meanwhile online).
	v.add_child(UIStyle.button("Settings", func():
		_toggle_pause()
		_open_over_match("options")))
	if Net.active() and Net.is_host() and match_ and not in_yard():
		v.add_child(UIStyle.button("Back to the yard (everyone)", func():
			_toggle_pause()
			enter_yard("The host called the party back")))
	if Net.active():
		v.add_child(UIStyle.button("Close the room (main menu)" if Net.is_host() else "Leave the room (main menu)", func():
			_toggle_pause()
			_leave_room()))
	else:
		v.add_child(UIStyle.button("Leave the fight", func():
			_toggle_pause()
			get_tree().paused = false
			if forge_trying != null:
				back_to_forge()
				return
			# Out of training, back to its own screen (to change the foe or the kit and go again).
			var to_training: bool = match_ != null and match_.mode == "training" and match_.tut == null
			_end_match()
			show_screen("training" if to_training else "main")))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.active():
		get_tree().paused = true
