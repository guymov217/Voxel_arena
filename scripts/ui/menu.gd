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
var training := {"enemy": "gladiator", "count": 1, "difficulty": 0.5, "behaviour": "fights", "my_main": "built", "my_off": "roundShield", "immortal": true, "respawn": true}
var backdrop: Match = null      # bots fighting behind the menus, seen by an orbiting camera
var backdrop_off := false       # (screenshots of the menus' words on a slow renderer: no fight behind them)
var bg: ColorRect
var shade: TextureRect
var panel_style: StyleBoxFlat
const HERO_POS := Vector3(-1.45, 0, -9.7)
## Bread & Circuses is set aside for now (its screens and code stay, ready to come back).
const SHOW_CIRCUS := false

## The Ludus yard is the lobby of the campaign and of a party (between bouts, at a campaign's start,
## a room's host); the main menu has no door of its own to it (one let a new player through the
## gate into the first bout without choosing how the campaign deals with death: user). `-- --admin`
## on the command line (or "admin" in the save) shows one, for testing.
static func admin() -> bool:
	return OS.get_cmdline_user_args().has("--admin") or bool(Save.get_value("admin", false))
const CLOTH := [0x8a1c14, 0x1f4f8f, 0x2f6b2a, 0x6b2a7a, 0xc89a2a, 0x2a2a2a, 0xe8e0d0, 0xb4541e, 0x5a3a22, 0x1d6b6b, 0x8a8a80, 0xd06a8a]
## The look's slots as Your gladiator names them.
const SLOT_NAMES := {"hat": "Hat", "hair": "Hair", "hair_colour": "Hair colour", "beard": "Beard", "cape": "Cape", "eyes": "Eyes", "eye_colour": "Eye colour", "mouth": "Mouth", "face": "Face", "nose": "Nose", "scar": "Scar"}
const LOOK_SLOTS := {
	"hat": ["", "hat_laurel", "hat_crest", "hat_straw", "hat_horns", "hat_crown", "hat_feather", "hat_bandana", "hat_headband", "hat_phrygian", "hat_pileus", "hat_pelt", "hat_unbroken"],
	# (The man bald, "None"; the hairstyles of the arena's day: FineHead.STYLES, user.)
	"hair": ["", "hair_crop", "hair_curls_top", "hair_curly", "hair_long", "hair_braids", "hair_suebian", "hair_topknot", "hair_bun"],
	"beard": ["", "beard_braided", "beard_full", "beard_short", "beard_goatee", "beard_moustache", "beard_philosopher", "beard_stubble", "beard_mutton", "beard_chinstrap", "beard_forked"],
	"cape": ["", "cape", "cape_short"],
	"eyes": ["", "eyes_wide", "eyes_side", "eyes_cross", "eyes_angry", "eyes_sleepy", "eyes_blue", "eyes_green", "eyes_mad", "eyes_wink", "eyes_brown", "eyes_scar", "eyes_tired"],
	"mouth": ["", "mouth_gap", "mouth_grin", "mouth_snarl", "mouth_stern", "mouth_shout", "mouth_tongue", "mouth_toothless", "mouth_smirk", "mouth_buck", "mouth_frown", "mouth_gold", "mouth_grimace"],
	"hair_colour": ["", "hc_black", "hc_dark", "hc_brown", "hc_auburn", "hc_ginger", "hc_blond", "hc_platinum", "hc_grey", "hc_white", "hc_blue", "hc_green", "hc_pink", "hc_purple"],
	"eye_colour": ["", "iris_brown", "iris_hazel", "iris_green", "iris_blue", "iris_grey", "iris_amber", "iris_red", "iris_violet", "iris_gold", "iris_white"],
	"face": ["", "face_freckles", "face_stubble", "face_scar_cheek", "face_scar_lip", "face_scar_brow", "face_brows_thick", "face_unibrow", "face_woad", "face_warpaint", "face_ochre", "face_tattoo", "face_blush", "face_skull", "face_clown"],
	# (A nose and a scar of his own choosing, besides paint or stubble: the veteran's face is the
	# one every man has, his broken nose, scar and stubble each his own to pick: user.)
	"nose": ["", "nose_straight", "nose_roman", "nose_broken", "nose_small"],
	"scar": ["", "face_scar_brow", "face_scar_cheek", "face_scar_lip"],
}

func _ready() -> void:
	theme = UIStyle.theme()
	UIStyle.hook(get_tree())
	StationKit.pad_menu_keys()
	apply_display(Save.get_value("settings", {}), true)
	apply_picture(Save.get_value("settings", {}))
	apply_frame(Save.get_value("settings", {}))
	apply_ui_scale(Save.get_value("settings", {}))
	# A room between windows of this one computer (Net.local_room) draws a lower picture, and a room closed gives it back.
	Net.local_room_changed.connect(func():
		apply_render_scale(Save.get_value("settings", {}))
		apply_frame(Save.get_value("settings", {})))
	# Resized, moved to another screen, or full screen: the automatic resolution follows.
	get_tree().root.size_changed.connect(func(): apply_render_scale(Save.get_value("settings", {})))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.my_kit = kit()
	Net.my_body = body()
	Armory.register(Save.get_value("armor_designs", {}))   # the pieces designed at the bench
	_net_loadout()
	Achievements.sync.call_deferred()
	if Sfx.music:
		Sfx.music.volume = float(Save.get_value("settings", {}).get("music", 0.5))
	_cmdline_room.call_deferred()
	world_root = Node3D.new()
	get_parent().add_child.call_deferred(world_root)
	# F3: the frame rate in the corner, wherever he is (FpsMeter).
	get_tree().root.add_child.call_deferred(FpsMeter.new())
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
			if not Save.boxed:
				Net.send_to(int(id), "purse", coins())
			# The yard is the room: whoever joins walks in through the gate.
			if in_yard() and match_.role == "host":
				match_.add_peer(int(id), _peer_spec(int(id), true))
		if screen == "ff_setup":
			show_screen(screen))   # (the waiting room follows the room by itself)
	Net.peer_left.connect(func(id):
		if match_ and match_.role == "host":
			match_.drop_peer(int(id))
		if screen == "ff_setup":
			show_screen(screen))
	Net.connected.connect(func():
		in_room = true
		# A room opens on its waiting room (LobbyScreen): the host sees who comes in and opens the gates, the yard, when everyone is
		# here (a friend who comes later walks in by himself); a guest waits there until the host does.
		if Net.is_host():
			if Net.room_kind == Net.KIND_ARENA:
				_box_on()   # (the friends' room: the arena gladiator, not the campaign's)
			Net.set_lobby_info(Loc.t("In the lobby"))
		show_screen("room"))
	# A guest is told what the room is for as he comes in (before the yard): the friends' room has a sandbox of its own for him too.
	Net.room_kind_known.connect(func(kind):
		if kind == Net.KIND_ARENA:
			_box_on()
		else:
			_box_off()
		if screen == "room":
			show_screen("room"))
	Net.connection_failed.connect(func(r): show_screen("mp", r))
	Net.disconnected.connect(func():
		in_room = false
		_box_off()
		_end_match()
		var why := Net.leave_reason if Net.leave_reason != "" else "The host left"
		Net.leave_reason = ""
		show_screen("mp", why))
	Net.lobbies.connect(_on_lobbies)
	Net.my_name = Save.get_value("name", "Gladiator")
	show_screen("main")
	# A friend's invite taken while the game was closed: Steam started it for that room.
	var invited := Net.take_launch_lobby()
	if invited != 0:
		show_screen("mp", Loc.t("Joining your friend's room..."))
		Net.join_steam(invited)

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
	if Save.boxed:
		return Save.UNLIMITED   # (the friends' Arena: money is no object, and never the campaign's)
	if Net.active() and not Net.is_host():
		return shared_purse
	return int(Save.get_value("coins", START_COINS))

func add_coins(n: int) -> void:
	if Save.boxed:
		return
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
	# Bought in the yard: in his hands at once, there and then (with the chips the fight left in
	# what he kept: buying a shield did not mend the sword).
	if in_yard() and match_.me and is_instance_valid(match_.me.f) and match_.me.f.alive:
		var lo := Arms.loadout(Arms.sanitize(a))
		match_.me.f.rearm(lo.main, lo.off)
		for side in lo.worn:
			if match_.me.f.weapons.get(side) and not match_.me.f.fixed_hand[side]:
				match_.me.f.weapons[side].remove_voxels(lo.worn[side])
	_sync_my_spec()

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
	_armour_on_him()

## The yard's man as the save has him now (his arms bought, mended or reshaped, his armour bought,
## taken off or mended): what he is built again from (Match.rebuild: the physician, the smith; a
## fall in the yard).
func _sync_my_spec() -> void:
	if not in_yard() or match_.me == null or not (match_.me.get("spec") is Dictionary):
		return
	var sp: Dictionary = match_.me.spec
	var lo := Arms.loadout(arms())
	var lod: Dictionary = (sp.get("loadout", {}) as Dictionary).duplicate() if sp.get("loadout") is Dictionary else {}
	lod["main"] = lo.main if lo.main else ""
	lod["off"] = lo.off if lo.off else ""
	lod["armor"] = look_armor(look()) + worn_armor()
	lod["armor_defs"] = Armory.defs_of(worn_armor())
	lod["armor_wear"] = armor_wear()
	sp["loadout"] = lod
	sp["worn"] = lo.worn

## His armour bought, taken off or mended at the smith: on him in the yard at once as the save has
## it, built again with it (in a room on every screen: Match.rebuild, as the physician's work).
## (Mended, it stayed broken on him: the plates still off him were counted again as the yard's
## wear the next time a stall or the gate was opened, and the mending undone: user.)
func _armour_on_him() -> void:
	_sync_my_spec()
	if in_yard() and match_.me and is_instance_valid(match_.me.f) and match_.me.f.alive:
		match_.rebuild(match_.me, body())

## The player's own gladiator: skin, cloth colour and the cosmetic pieces (no armour: that is
## bought). Saved as indices, so an old or hand-edited save cannot name anything that is not there.
## (An older save's hairstyle is its index into the list as it was, HAIR_V1: the same style read
## from it, or the arena's nearest for one no longer offered, and saved so.)
const HAIR_V1 := ["", "hair_mohawk", "hair_long", "hair_curly", "hair_topknot", "hair_ponytail", "hair_crop", "hair_spikes", "hair_braids", "hair_bun", "hair_suebian", "hair_curls_top"]
const LOOK_V := 2
func look() -> Dictionary:
	var l: Dictionary = Save.get_value("look", {})
	var out := {"skin": clampi(int(l.get("skin", 0)), 0, Fighter.SKINS.size() - 1), "cloth": clampi(int(l.get("cloth", 0)), 0, CLOTH.size() - 1), "build": 0, "v": LOOK_V}   # (one build for every player, the hero: user, so that none looks the heavier man)
	var old := not l.is_empty() and int(l.get("v", 1)) < LOOK_V
	for k in LOOK_SLOTS:
		var i := int(l.get(k, 0))
		if k == "hair" and old:
			var was: String = HAIR_V1[clampi(i, 0, HAIR_V1.size() - 1)]
			i = maxi(0, LOOK_SLOTS.hair.find(String(FineHead.RETIRED.get(was, was))))
		out[k] = clampi(i, 0, LOOK_SLOTS[k].size() - 1)
		if look_locked(LOOK_SLOTS[k][out[k]]):
			out[k] = 0
	if old:
		Save.set_value("look", out)
	return out

## A look piece not yet earned: the Unbroken laurel is the Ironman's (CampaignRun), the freedman's
## cap his who took the rudis ("freed": _grant_rudis).
static func look_locked(id: String) -> bool:
	return (id == "hat_unbroken" and not CampaignRun.unbroken()) or (id == "hat_pileus" and not bool(Save.get_value("freed", false)))
## How a piece not yet earned is shown in the picker: its note and what earns it.
const LOOK_LOCKS := {"hat_unbroken": ["%s  (Ironman)", "Won by taking the rudis on Ironman, never once fallen"],
	"hat_pileus": ["%s  (the rudis)", "Won with the rudis: the whole campaign won"]}

## What the room is told about us: the arms, plus the look (other players see your hat).
func _net_loadout() -> void:
	var lo := Arms.loadout(arms())
	var lk := look()
	lo["look"] = look_armor(lk)
	lo["gear"] = worn_armor()
	lo["gear_defs"] = Armory.defs_of(lo.gear)   # what a designed piece is, for the others to see it
	lo["gear_wear"] = armor_wear()
	lo["stats"] = training_stats()
	lo["skin"] = Fighter.SKINS[lk.skin]
	lo["build"] = FineBody.BUILDS[lk.build]
	Net.my_loadout = lo
	Net.push_me()

## A guest's look, as the host accepts it: only the cosmetic pieces and the known skins.
## What the host spawns for a guest: his name, kit, body and the look and arms he sent.
func _peer_spec(id: int, geared: bool, with_body := true) -> Dictionary:
	var pl: Dictionary = Net.peers[id].get("loadout", {})
	var pk := peer_look(pl)
	return {"id": id, "name": Net.peers[id].name, "kit": Net.peers[id].get("kit", {}), "body": Net.peers[id].get("body", {}) if with_body else {}, "skin": pk.skin, "build": pk.build, "loadout": {"main": pl.get("main", "gladius"), "off": pl.get("off"), "armor": pk.armor + (pk.gear if geared else []), "armor_defs": Armory.defs_of(pk.gear) if geared else {}, "armor_wear": Armory.clean_wear(pl.get("gear_wear", {}), pk.gear) if geared else {}} if not pl.is_empty() else {"main": "gladius"}, "worn": pl.get("worn", {}) if pl.get("worn") is Dictionary else {}, "mods": Training.mods_of(Training.sanitize(pl.get("stats", {}))) if geared else {}}

func peer_look(pl: Dictionary) -> Dictionary:
	var ok := []
	for k in LOOK_SLOTS:
		ok += LOOK_SLOTS[k]
	var arm: Array = (pl.get("look", []) as Array).filter(func(id): return id is String and id != "" and ok.has(id)).slice(0, LOOK_SLOTS.size()) if pl.get("look") is Array else []
	var sk = pl.get("skin")
	Armory.register(pl.get("gear_defs", {}))   # his designed pieces, made safe, under their own ids
	# (His build is not his to choose: every player is drawn as the one man, Physique.build_of.)
	return {"armor": arm, "gear": Armory.sanitize(pl.get("gear", [])), "skin": int(sk) if (sk is int or sk is float) and Fighter.SKINS.has(int(sk)) else null, "build": ""}

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
	Net.push_me()
	# A limb or an eye given back in the yard (the Elixir, a prosthetic): he stands there with it
	# at once, his weapons in the hands it gave back (he walked about armless until the next bout).
	# A bone set by the physician the same: whole on him there and then (user: whatever he bought,
	# the broken arm stayed broken). An old wound closed the same (user: he bought the rare
	# medicine and nothing happened: the scar stayed on him until the next bout).
	if in_yard() and match_.me and is_instance_valid(match_.me.f) and (clean.missing != was.missing or clean.prosthetics != was.prosthetics or clean.eyes != was.eyes or clean.fractures != was.fractures or clean.pro_up != was.pro_up or Body.old_wound_closed(was, clean)):
		_sync_my_spec()
		match_.rebuild(match_.me, clean)
		return
	# Stitched in the yard: the wounds close on him there and then (each fresh wound that is closed
	# now: the rare medicine closes one part's and leaves the others open).
	if in_yard() and match_.me and is_instance_valid(match_.me.f):
		for n in was.fresh:
			var p = match_.me.f.by_name.get(n)
			var open: Array = clean.fresh.get(n, [])
			var closed: Array = (was.fresh[n] as Array).filter(func(i): return not open.has(i))
			if p and not closed.is_empty():
				p.restore_voxels(closed)
				# (Closed by the needle they heal into scars: a mark on the skin, a tiny dent where it was
				# hard; the rare medicine takes the scar away with the wound, and nothing is left.)
				var kept: Array = (clean.scars.get(n, []) as Array)
				p.heal_scar(closed.filter(func(i): return kept.has(i)))

func set_kit(k: Dictionary) -> void:
	var clean := Net.sanitize_kit(k)
	Save.set_value("kit", clean)
	Net.my_kit = clean
	Net.push_me()
	# Bought in the yard: the gladiator walking about in it has it in his bag at once (and the
	# yard ending does not write the old bag back over the purchase).
	if match_ and is_instance_valid(match_) and match_.me and match_.mode == "yard":
		match_.me.inventory = clean.duplicate()

## The stalls of the yard: with the keys in use they open on something to press.
const STALL_SCREENS := ["market", "yard", "physician", "trainer", "circus_market"]

func show_screen(s: String, msg := "") -> void:
	if Save.boxed and not Net.active():
		_box_off()   # (out of the friends' room by any way: the campaign's own gladiator again)
	var was := screen
	var focus_was := StationKit.focus_key(panel)
	if s == "main":
		# Back at the main menu he has left the yard: a fight picked from here ends here.
		if in_yard():
			_end_match()
		hub = false
	screen = s
	if s == "gladiator" and was != "gladiator":
		hero_turn = 0.0
	if backdrop and backdrop.hero and (was == "gladiator") != (s == "gladiator"):
		_dress_hero()
	visible = true
	_backdrop_on.call_deferred()
	if Sfx.music and match_ == null:
		Sfx.music.set_state("yard" if ["yard", "market", "circus_market"].has(s) else "menu")
	var v := _clear()
	if in_yard() or s == "yard":
		# The one way out of a stall; the smith seen from anywhere else leads into the yard.
		var way_out := StationKit.button(Loc.t({"market": "◀  Leave the market  (Esc)", "yard": "◀  Leave the smith  (Esc)", "physician": "◀  Leave the physician  (Esc)", "missions": "◀  Leave the board  (Esc)", "gate": "◀  Leave the gate  (Esc)", "fights": "◀  Back to the yard  (Esc)", "fight_setup": "◀  Back to the yard  (Esc)", "endless": "◀  Back to the yard  (Esc)", "room": "◀  Back to the yard  (Esc)"}.get(s, "◀  Leave the stall  (Esc)")), _close_overlay if in_yard() else func(): enter_yard(), true)
		way_out.set_meta("leave", true)
		v.add_child(way_out)
		if in_yard() and hud:
			hud.visible = false
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if s == "main" else (_lobby_style() if s == "room" else panel_style))
	if s != "main":
		UIStyle.frame_over(panel, Vector2(32, 26))
	panel.custom_minimum_size = Vector2(520 if s == "main" else (1180 if s == "training" or s == "fights" or s == "training_armour" or s == "endless" or s == "endless_armour" or s == "room" else 760), 0)
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
		"trainer": _trainer(v)
		"fights": _fights(v)
		"fight_setup": _fight_setup(v)
		"mp": _mp(v)
		"room": _room(v)
		"options": _options(v)
		"credits": _credits(v)
		"gladiator": _gladiator(v)
		"circus": _circus(v)
		"controls": _controls(v)
		"gate": _gate(v)
		"missions": _missions(v)
		"circus_market": _circus_market(v)
		"demo_end": _demo_end(v)
		"campaign_end": _campaign_end(v)
		"scroll": _scroll(v)
		"rudis": _rudis(v)
		"campaign_mode": _campaign_mode(v)
		"training_designs": _training_designs(v)
		"training_armour": _training_armour(v)
		"ff_setup": _ff_setup(v)
		"ff_contest": _ff_contest(v)
		"endless": _endless(v)
		"endless_armour": _endless_armour(v)
	StationKit.settle_focus(panel, "" if fresh else focus_was, STALL_SCREENS.has(s))
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

## The waiting room's plate: the menu's own, a little clearer, so that the arena behind it is seen.
func _lobby_style() -> StyleBoxFlat:
	var st: StyleBoxFlat = panel_style.duplicate()
	st.bg_color.a = 0.74
	return st

func _main(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 10)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	v.add_child(head)
	var laurel := Ornament.new("laurel", Vector2(150, 70))
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
	var tag := Label.new()
	tag.text = "FORGE  ·  FIGHT  ·  FALL"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", UIStyle.serif(6, 600))
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", Color(0.93, 0.84, 0.66, 0.85))
	tag.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.01))
	tag.add_theme_constant_override("outline_size", 4)
	head.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	v.add_child(gap)
	var st := int(Save.get_value("stage", 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(440, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(col)
	var rows := []
	# The campaign first and largest: where it stands (the bout, how death is dealt with) under it.
	var go := func():
		if st <= 1 and not CampaignRun.chosen():
			show_screen("campaign_mode")
		else:
			enter_yard()
	var fresh_run := st <= 1 and not CampaignRun.chosen()
	rows.append(UIStyle.hero_button("Continue the campaign" if not fresh_run else "Begin the campaign",
		(Loc.t("Bout %s of %d · %s") % [str(st), Data.campaign.get("stages", []).size(), Loc.t(String(CampaignRun.MODES[CampaignRun.mode()].name))]) if not fresh_run else "Sixty-four bouts to freedom", go))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 10)
	rows.append(gap2)
	var entries := []
	if SHOW_CIRCUS:
		entries.append(["Bread & Circuses", func(): show_screen("circus")])
	entries.append(["Your gladiator", func(): show_screen("gladiator")])
	if admin():
		entries.append(["The Ludus yard (admin)", enter_yard])
	entries.append_array([
		["Arena", func(): show_screen("fights")],
		["The endless arena", func():
			endless_back = "main"
			show_screen("endless")],
		["Training", func(): show_screen("training")],
		["The forge", _workshop_forge],
		["Multiplayer", func(): show_screen("mp")],
	])
	for en in entries:
		rows.append(UIStyle.menu_entry(String(en[0]), en[1]))
	var rule2 := Ornament.new("rule", Vector2(440, 18))
	rule2.color = Color(UIStyle.GOLD, 0.55)
	rows.append(rule2)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 0)
	foot.add_child(UIStyle.menu_entry("Settings", func(): show_screen("options"), 16))
	foot.add_child(UIStyle.menu_entry("Credits", func(): show_screen("credits"), 16))
	foot.add_child(UIStyle.menu_entry("Quit", func(): get_tree().quit(), 16))
	rows.append(foot)
	# Who he is and what he has, small, at the foot.
	var who := UIStyle.label(Loc.t("%s  ·  %d denarii%s") % [String(Save.get_value("name", "Gladiator")), coins(), (Loc.t("  ·  Unbroken") if CampaignRun.unbroken() else "")], 14, Color(UIStyle.MUTED, 0.85))
	who.autowrap_mode = TextServer.AUTOWRAP_OFF
	rows.append(who)
	for i in rows.size():
		var b: Control = rows[i]
		col.add_child(b)
		# The rows come in one after another, sliding a little from the left.
		b.modulate.a = 0.0
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.12 + i * 0.05)
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
	# here), for the physician to see to, and his weapons with the chips the fight took out of
	# them, for the smith to mend (user: the weapons' damage did not come back with him).
	start({"mode": "yard", "loadout_override": {"main": lo.main if lo.main else "", "off": lo.off if lo.off else ""}, "worn": lo.worn, "decrees": [], "hazards": [], "body": body()})   # (what he has: no shield he does not own)
	match_.station.connect(_open_station)
	if Sfx.music:
		Sfx.music.set_state("yard")
	if banner_text != "":
		match_._banner("Back in the yard", banner_text)

func _open_station(id: String) -> void:
	if id == "team_go":
		_team_go()
		return
	if visible:
		return
	# What the yard knocks out of his blade or his armour (a swing at the post, a friend's sword) is
	# never counted at the smith's: only what a bout in the arena did to them is (user: the lobby's
	# fights never count). Opening a stall saves nothing of it, and it is gone the next time he is
	# built, at the gate or at a purchase.
	# The gate: the gate's fights, a card each (GateScreen).
	# (A room's host at the gate when the demo is over: the gate's menu, with the modes for the room.)
	var arena_room: bool = Net.active() and Net.room_kind == Net.KIND_ARENA
	if id == "gate" and arena_room and not Net.is_host():
		# (The friends' room has no campaign to lead through the gate: the host picks the fight from the Arena's list.)
		match_._banner("The arena gate", "The host picks the fight for the room")
		return
	if id == "gate" and not arena_room and not (Net.active() and Net.is_host() and Edition.demo_over(int(Save.get_value("coop_stage", 1)))):
		_gate_open()
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
		"trainer": show_screen("trainer")
		"gate": show_screen("fights" if arena_room else "gate")

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

## The friends' room (Net.KIND_ARENA): the gladiator is the arena profile's, never the campaign's, and his purse has no limit (Save.box_begin).
func _box_on() -> void:
	if Save.boxed:
		return
	var fresh := {"coins": Save.UNLIMITED, "market_open": Market.AFTER_BOSS.size(), "coop_market_open": Market.AFTER_BOSS.size()}
	# The first time a man comes into a friends' room he is not left with the training stick: a gladius, a round shield and a
	# helmet (he buys what he likes in the yard, money no object; later times he has what he kept there).
	var start_arms := Arms.empty()
	for key in ["gladius", "roundShield"]:
		var r := Arms.buy(start_arms, key)
		if r.has("arms"):
			start_arms = r.arms
	fresh["arms"] = start_arms
	fresh["armor_worn"] = ["helmet"]
	Save.box_begin(fresh)
	Net.my_kit = kit()
	Net.my_body = body()
	_net_loadout()   # (the host sees the arena gladiator)

## Out of it: the campaign's own gladiator is read again.
func _box_off() -> void:
	if not Save.boxed:
		return
	Save.box_end()
	Net.my_kit = kit()
	Net.my_body = body()
	_net_loadout()

## Out of the room: the host closes it (his guests are told the host left), a guest goes.
func _leave_room() -> void:
	get_tree().paused = false
	_end_match()
	Net.leave()
	_box_off()
	in_room = false
	hub = false
	over_match = false
	show_screen("main")

## The fight the party is for (GateChoice): the one most of them are for (YardPlay.stands: the
## card each picked on his gate screen), the host for card `board` (-1: his own as it is).
func _party_pick(board: int) -> Dictionary:
	var offers := GateChoice.now(true)
	var stands: Array = match_.yard.stands() if match_ and is_instance_valid(match_) and match_.yard else []
	if not stands.is_empty() and board >= 0:
		stands[0] = board
	return offers[GateChoice.majority(stands, offers.size())]

# ---------- The gate's fights (GateScreen) ----------

var gate_screen: GateScreen = null

## The gate's cards over the yard, the first forward (the host's: his pick, if he has one).
## Alone: through the gate to the one he takes. In a room each one's pick is on the cards (a
## guest's pick is told to the host), and the host's own pick leads them through (or he takes them
## into another mode for the room). At the demo's end there is nothing to choose: straight to its end.
func _gate_open() -> void:
	if gate_screen and is_instance_valid(gate_screen):
		return
	var coop := Net.active()
	var guest := coop and not Net.is_host()
	var yard: YardPlay = match_.yard if match_ and is_instance_valid(match_) else null
	var st := int(Save.get_value("coop_stage" if coop else "stage", 1))
	var lap := int(Save.get_value("coop_lap" if coop else "lap", 1))
	var offers := GateChoice.now(coop)
	if guest:
		var gi: Dictionary = yard.gate_info if yard else {}
		if gi.is_empty():
			# (Nothing to choose, or a host of a game from before the gate's cards.)
			match_._banner("The arena gate", "The host leads the party through")
			return
		offers = gi.b
		st = int(gi.s)
		lap = int(gi.l)
	elif Edition.demo_over(st):
		_through_gate(0)
		return
	var mine := -1
	if coop and not guest and yard:
		mine = int(yard.picks.get(1, -1))
	var o := {"at": maxi(mine, 0), "mine": mine, "party": coop, "host": not guest, "lap": lap, "previews": DisplayServer.get_name() != "headless"}
	if coop and not guest:
		if Net.campaign_full():
			o.lead_block = campaign_full_text()
		o.extras = [[Loc.t("Close the room (main menu)"), func():
			_gate_shut()
			_leave_room()]]
	visible = true
	screen = "gate_cards"
	panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if match_.input:
		match_.input.enabled = false
	if hud:
		hud.visible = false
	gate_screen = GateScreen.open(self, offers, st, match_.humans().size() if coop else 1, o)
	gate_screen.chosen.connect(func(i: int):
		_gate_shut()
		_through_gate(i))
	gate_screen.closed.connect(func():
		_gate_shut()
		_close_overlay())
	if coop:
		gate_screen.voted.connect(func(i: int):
			if guest:
				Net.send_host("gate_pick", i)
			elif yard:
				yard.take_pick(1, i))
		if guest:
			match_.gate_picks.connect(_gate_seen)
			_gate_seen()
		elif yard:
			gate_screen.refresh = func(g: GateScreen):
				g.set_votes(yard.pick_names(), GateChoice.majority(yard.stands(), offers.size()))

## (A guest's) the party's picks on his cards, as the host told them.
func _gate_seen() -> void:
	var yard: YardPlay = match_.yard if match_ and is_instance_valid(match_) else null
	if gate_screen and is_instance_valid(gate_screen) and yard and not yard.picks_seen.is_empty():
		gate_screen.set_votes(yard.picks_seen.v, int(yard.picks_seen.l))

## The gate's cards gone (through the gate, back to the yard, the match over).
func _gate_shut() -> void:
	if gate_screen and is_instance_valid(gate_screen):
		gate_screen.queue_free()
	gate_screen = null
	if match_ and is_instance_valid(match_) and match_.gate_picks.is_connected(_gate_seen):
		match_.gate_picks.disconnect(_gate_seen)
	if panel:
		panel.visible = true

## Through the gate to a fight on offer by it: alone, board `board`'s (0: the gate's own); the
## host leads the party to the one most of them stand by (his own board counting, -1: none).
func _through_gate(board: int) -> void:
	var coop := Net.active()
	var st := int(Save.get_value("coop_stage" if coop else "stage", 1))
	if Edition.demo_over(st):
		if coop:
			Net.send_all("demo_end", {})
		_end_match()
		show_screen("demo_end")
		return
	if coop:
		var co := _party_pick(board)
		start({"mode": "coop", "role": "host", "bout": int(co.bout), "crowd": String(co.kind) == "crowd"})
		return
	var offers := GateChoice.now(false)
	var o: Dictionary = offers[clampi(board, 0, offers.size() - 1)]
	start({"mode": "campaign", "stage": st, "bout": int(o.bout), "crowd": String(o.kind) == "crowd"})

func _gate(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("The arena gate", 34))
	v.add_child(UIStyle.label("Pick the fight. You come back to the yard afterwards.", 15, UIStyle.MUTED))
	if Net.active() and Net.is_host():
		var cs := int(Save.get_value("coop_stage", 1))
		var co := _party_pick(-1)
		var cn := Data.stage(cs, mini(1 + Net.peers.size(), Net.CAMPAIGN_PLAYERS), int(co.bout), String(co.kind) == "crowd")
		if Edition.demo_over(cs):
			v.add_child(UIStyle.button("You have finished the demo", func():
				Net.send_all("demo_end", {})
				_end_match()
				show_screen("demo_end"), true))
		else:
			v.add_child(UIStyle.label(Loc.t("Next co-op bout: %s · %s") % [cn.get("title", Loc.t("Bout %d") % cs), cn.get("foe_name", "")], 15, UIStyle.GOLD))
			var go := UIStyle.button(Loc.t("The co-op campaign · bout %d (all of you)") % cs, func(): _through_gate(-1), true)
			v.add_child(go)
			_campaign_cap(go, v)
	elif Net.active() and not Net.is_host():
		v.add_child(UIStyle.label("The host leads the party through the gate.", 15, UIStyle.MUTED))
	else:
		var st := int(Save.get_value("stage", 1))
		var so: Dictionary = GateChoice.now(false)[0]
		var nxt := Data.stage(st, 1, int(so.bout), String(so.kind) == "crowd")
		if Edition.demo_over(st):
			v.add_child(UIStyle.button("You have finished the demo", func():
				_end_match()
				show_screen("demo_end"), true))
		else:
			v.add_child(UIStyle.label(Loc.t("Next bout: %s · %s") % [nxt.get("title", Loc.t("Bout %d") % st), nxt.get("foe_name", "")], 15, UIStyle.GOLD))
			v.add_child(UIStyle.button(Loc.t("The Campaign · bout %d") % st, func(): _through_gate(0), true))
	if SHOW_CIRCUS:
		v.add_child(UIStyle.button("Bread & Circuses", func():
			_end_match()
			show_screen("circus")))
	if not Net.active():
		v.add_child(UIStyle.button("Fights and party modes", func():
			_end_match()
			show_screen("fights")))
	if Net.active():
		if Net.transport == "steam" and Net.is_host():
			v.add_child(UIStyle.button("Invite friends (Steam)", func(): Net.invite_friends()))
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
	v.add_child(UIStyle.label(Loc.t("Rank: %s · reputation %d%s") % [Loc.t(rk.name), rep, (Loc.t(" · %s at %d") % [Loc.t(nxt.name), int(nxt.rep)]) if nxt else Loc.t(" · the highest rank")], 16, UIStyle.GOLD))
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
		v.add_child(UIStyle.label(Loc.t("%s  %s  (%d/%d) · %d denarii, %d reputation") % ["✔" if ms.get("done", false) else "·", Loc.t(String(d.text)), int(ms.n), int(d.count), int(round(int(d.coins) * Yard.mission_pay(rep))), int(d.rep)], 15, Color(0.6, 0.95, 0.5) if ms.get("done", false) else UIStyle.TEXT))

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
	var text := Loc.t("+%d reputation") % gain
	if not done.is_empty():
		text += Loc.t(" · missions done: %s (+%d denarii)") % [", ".join(done.map(func(id): return Loc.t(String(Yard.MISSIONS[id].text)))), int(pay.coins)]
	if after.index > before.index:
		text += Loc.t(" · NEW RANK: %s!") % Loc.t(String(after.name))
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
		var lbl := UIStyle.label(Loc.t(String(a.label)), 14)
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
	var what := id
	for a in Data.controls.get("actions", []):
		if a.id == id:
			what = Loc.t(String(a.label))
	show_screen("controls", "%s: %s" % [what, PlayerInput.label_of(code)])

func _tutorial() -> void:
	# (A kit of its own: the pot it hands over for the kit's step, and none of the campaign's.)
	start({"mode": "training", "tutorial": true, "training": {"enemy": "none", "respawn": false}, "inventory_override": {}})

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
			o.add_item(Loc.t(String(n)))
		# (The save gives numbers back as floats: 3.0 is not found among 1, 2, 3, and the list
		# showed "One" while three were sent in. What is shown is what is used.)
		var at := keys.find(training.get(key))
		if at < 0 and (training.get(key) is float):
			at = keys.find(int(training.get(key)))
		at = maxi(0, at)
		training[key] = keys[at]
		o.select(at)
		o.item_selected.connect(func(i): training[key] = keys[i])
		g.add_child(o)
	var ge: GridContainer = form.call("THE ENEMY")
	var foes: Array = Data.campaign.enemies.keys().map(func(k): return "foe:" + k)
	# The beasts by name, A to Z, without their "The" (the gorilla was "The Gorilla", last of
	# forty, and not to be found).
	var beast_name := func(k: String) -> String: return String(Data.beasts[k].name).trim_prefix("The ") if Loc.code() == "en" else Loc.t(String(Data.beasts[k].name))
	var beasts: Array = Data.beasts.keys()
	beasts.sort_custom(func(a, b): return beast_name.call(a) < beast_name.call(b))
	var who: Array = (["none", "gladiator"] + foes + beasts).filter(func(k): return Edition.foe_open(k))
	if not who.has(training.get("enemy")):
		training.enemy = "gladiator"
	pick.call(ge, "Who", who, who.map(func(k): return "Nobody" if k == "none" else ("Gladiator" if k == "gladiator" else (Data.campaign.enemies[k.trim_prefix("foe:")].get("label", k) if k.begins_with("foe:") else beast_name.call(k)))), "enemy")
	pick.call(ge, "How many", [1, 2, 3], ["One", "Two", "Three"], "count")
	pick.call(ge, "Behaviour", ["fights", "defends", "still", "moves"], ["Fights back", "Defends only", "Stands still (a dummy)", "Walks about, never attacks"], "behaviour")
	# How hard, by name, not a slider (user): the nearest of the four to what was set before.
	var levels := [0.25, 0.5, 0.75, 1.0]
	var was := float(training.get("difficulty", 0.5))
	var near_l: float = levels[0]
	for lv in levels:
		if absf(float(lv) - was) < absf(near_l - was):
			near_l = lv
	training.difficulty = near_l
	pick.call(ge, "Difficulty", levels, ["Easy", "Medium", "Hard", "Extreme"], "difficulty")
	var gy: GridContainer = form.call("YOU")
	var built: Dictionary = Save.get_value("training_weapon", {})
	var mains := ["built", "campaign", "fists", "gladius", "longsword", "zweihander", "falx", "axe", "executionerAxe", "mace", "warhammer", "hammer", "spear", "trident", "dagger", "plank", "chicken", "bow", "ram"]
	pick.call(gy, "Main hand", mains, mains.map(func(k): return (Loc.t("Forged: %s") % (String(built.name) if built.has("name") else Loc.t("none yet"))) if k == "built" else ("Your campaign arms" if k == "campaign" else ("Bare hands" if k == "fists" else Data.preset(k).get("name", k)))), "my_main")
	var built_off: Dictionary = Save.get_value("training_off_weapon", {})
	pick.call(gy, "Off hand", ["none", "roundShield", "scutum", "dagger", "gladius", "axe", "mace", "spear", "longsword", "campaign", "built"], ["Nothing", "Round shield", "Scutum", "Dagger", "Gladius", "Axe", "Mace", "Spear", "Longsword", "Your campaign arms", Loc.t("Design: %s") % (String(built_off.name) if built_off.has("name") else Loc.t("none yet"))], "my_off")
	# (A flow, not a row: three buttons in a row pushed the screen past the window's right edge.)
	var wb := HFlowContainer.new()
	wb.add_theme_constant_override("h_separation", 10)
	wb.add_theme_constant_override("v_separation", 8)
	wb.add_child(UIStyle.button("Weapons from My designs", func(): show_screen("training_designs")))
	var fm := UIStyle.button("Forge main hand", _training_forge)
	fm.tooltip_text = "Build a weapon for the main hand: free in training"
	wb.add_child(fm)
	var fo := UIStyle.button("Forge off hand", func(): _training_forge("L"))
	fo.tooltip_text = "Build a weapon for the off hand: free in training"
	wb.add_child(fo)
	left.add_child(wb)
	var t_arm := Armory.sanitize(training.get("armor", []))
	var t_kg := 0.0
	for id in t_arm:
		t_kg += Armory.kg(id)
	var al := UIStyle.label((Loc.t("Armour: %d pieces · %.1f kg") % [t_arm.size(), t_kg]) if not t_arm.is_empty() else "Armour: none", 15)
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
	var arm := Armory.sanitize(training.get("armor", []))
	return {"main": main if main != null else "", "off": off if off != null else "", "armor": arm, "armor_defs": Armory.defs_of(arm)}

func _start_training() -> void:
	# (No weapon is picked for the enemy: a sparring partner comes with one of his own, a foe or a
	# beast with its own; one picked in an older save is let go, user.)
	training.erase("weapon")
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
	v.add_child(UIStyle.label(Loc.t("YOUR BAG · free in training · keys 1 to 9 · %d of %d kinds") % [bag.size(), TRAINING_BAG_MAX], 13, UIStyle.BRONZE))
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
## With `lesson`, the forge's guided lesson (where the tutorial leads), on a plain gladius.
func _workshop_forge(lesson := false) -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.workshop = true
	var g: Array = f.gallery()
	f.open((g[0] as Dictionary).duplicate(true) if not g.is_empty() and not lesson else Data.preset("gladius").duplicate(true), 0, func(_d, _c):
		f.queue_free()
		show_screen("main"))
	panel.visible = false
	f.tree_exited.connect(func(): panel.visible = true)
	if lesson:
		f.start_lesson()

## The forge's "Try it in the arena": a training bout with the weapon on the anvil in hand and
## the dummy picked there in front of it; Esc (or Leave) goes straight back to the forge as it was
## (to the yard first, if the forge was the smith's), R starts it again with a fresh dummy. A line
## at the top keeps the weapon's score meanwhile, and the forge shows it when he is back.
var forge_trying = null
var forge_try_yard := false
var forge_try_spot = null   # where he stood in the yard (and which way he looked), to stand there again after
var forge_try_name := ""    # the weapon on trial and what it is tried on, for the line at the top
var forge_try_who := ""
var try_layer: CanvasLayer = null
var try_label: Label = null
var try_stats := {}
func try_from_forge(f: Node, d: Dictionary, who: String, fights: bool, who_name := "") -> void:
	forge_trying = f
	forge_try_yard = in_yard()
	forge_try_spot = null
	forge_try_name = String(d.get("name", ""))
	forge_try_who = who_name if who_name != "" else who
	if forge_try_yard and match_.me and is_instance_valid(match_.me.f):
		forge_try_spot = {"pos": match_.me.f.torso.global_position, "yaw": match_.me.f.yaw, "look": match_.input.look_yaw if match_.input else match_.me.f.yaw}
	f.visible = false
	f.process_mode = Node.PROCESS_MODE_DISABLED
	start({"mode": "training", "training": {"enemy": who, "count": 1, "weapon": "random", "behaviour": "fights" if fights else "still", "difficulty": 0.5, "immortal": true, "respawn": true},
		"loadout_override": {"main": d, "off": ""}, "decrees": [], "hazards": []})
	if match_:
		match_._banner("Trying it out", "Esc: back to the forge")

## The line at the top while a weapon is tried: what, on whom, the keys, and the weapon's score so
## far (its hits, the last blow and the best, the limbs it took off, the kills). Hung on every
## new bout of the trial (R makes one), and counted afresh there.
func _try_line() -> void:
	if try_layer:
		try_layer.queue_free()
	try_layer = CanvasLayer.new()
	try_layer.layer = 3
	add_child(try_layer)
	var top := CenterContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.theme = UIStyle.theme()
	try_layer.add_child(top)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.modulate.a = 0.92
	top.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var head := UIStyle.label(Loc.t("Trying %s against %s") % [forge_try_name if forge_try_name != "" else Loc.t("the weapon"), Loc.t(forge_try_who)], 15, UIStyle.GOLD)
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	try_label = UIStyle.label("", 14, UIStyle.TEXT)
	try_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	try_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(try_label)
	var keys := UIStyle.label("Esc: back to the forge · R: start again", 12, UIStyle.MUTED)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(keys)
	try_stats = {"hits": 0, "last": 0.0, "best": 0.0, "limbs": 0, "kills": 0}
	if match_ and match_.combat:
		match_.combat.hit.connect(_try_on_hit)
	_try_show()

## A blow of the weapon on trial (in his hand or thrown) on what it is tried on.
func _try_on_hit(h: Dictionary) -> void:
	if forge_trying == null or match_ == null or match_.me == null or h.get("attacker") != match_.me.f or h.get("weapon") == null or h.get("char") == match_.me.f:
		return
	var res = h.get("res")
	var dmg: float = float(res.get("dmg", 0.0)) if res is Dictionary else 0.0
	try_stats.hits += 1
	try_stats.last = dmg
	try_stats.best = maxf(float(try_stats.best), dmg)
	try_stats.limbs += (res.get("severed", []) as Array).size() if res is Dictionary else 0
	if h.get("killed", false):
		try_stats.kills += 1
	_try_show()

func _try_show() -> void:
	if try_label and is_instance_valid(try_label):
		try_label.text = Loc.t("%d hits · last blow %d · best %d · %d limbs off · %d kills") % [int(try_stats.hits), roundi(float(try_stats.last)), roundi(float(try_stats.best)), int(try_stats.limbs), int(try_stats.kills)]

func back_to_forge() -> void:
	var f = forge_trying
	forge_trying = null
	var tally := try_stats.duplicate()
	if try_layer:
		try_layer.queue_free()
		try_layer = null
		try_label = null
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
		if Sfx.music:
			Sfx.music.bench(true)
		if match_ and match_.input:
			match_.input.enabled = false
		if f.has_method("show_try_result") and not tally.is_empty():
			f.show_try_result(tally, forge_try_who)

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
	head.add_child(UIStyle.button("Forge one for the off hand", func(): _training_forge("L")))
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
		var info := UIStyle.label(Loc.t("%.1f kg · reach %.1f m%s") % [float(st.mass), float(st.reach), Loc.t(" · two hands") if dd.get("twoHanded", false) else ""], 13, UIStyle.MUTED)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(info)
		UIStyle.push_down(col)
		# (a line kept in every card, so the buttons of one in hand line up with the rest)
		var mark := UIStyle.label((Loc.t("In your %s") % Loc.t("main hand" if in_main else "off hand") if not (in_main and in_off) else "In both hands") if in_main or in_off else " ", 13, UIStyle.BRONZE)
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
		row.add_child(off)
		col.add_child(row)
		grid.add_child(card)
		Thumbs.weapon(tex, dd, "tdesign:%d" % dd.hash())

## `hand`: "L" builds the off hand's (kept as "your forged off-hand weapon", whatever it is).
func _training_forge(hand := "R") -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	var key := "training_off_weapon" if hand == "L" else "training_weapon"
	var base: Dictionary = Save.get_value(key, {})
	if base.is_empty():
		base = Data.preset("dagger" if hand == "L" else "gladius").duplicate(true)
	f.free_build = true
	f.open(base, 999999, func(design, _cost):
		if design != null:
			if hand == "L":
				Save.set_value("training_off_weapon", design)
				training.my_off = "built"
			else:
				Save.set_value("training_weapon", design)
				training.my_main = "built"
		f.queue_free()
		show_screen("training"))
	visible = true

# ---------- The endless arena ----------

var endless_back := "main"   # the screen its Back goes to (the main menu's own entry, or the Arena's card)

## What the endless arena is entered with (Save "endless_kit"): the arms (a weapon off the rack,
## or "built": forged here, Save "endless_weapon" / "endless_off_weapon"), ready-made armour,
## a few pots, and today's challenge or a free run.
var endless_kit := {}
const ENDLESS_MAINS := ["built", "gladius", "longsword", "zweihander", "falx", "axe", "executionerAxe", "mace", "warhammer", "hammer", "spear", "trident", "dagger"]
const ENDLESS_OFFS := ["none", "roundShield", "scutum", "dagger", "gladius", "axe", "mace", "built"]
const ENDLESS_POT_KINDS := 3   # kinds of pot in the bag
const ENDLESS_POT_EACH := 2    # and of each

func _endless_kit() -> Dictionary:
	if endless_kit.is_empty():
		endless_kit = {"main": "gladius", "off": "roundShield", "armor": ["helmet"], "pots": ["thunderPot"], "daily": false}
		var saved = Save.get_value("endless_kit", {})
		if saved is Dictionary:
			endless_kit.merge(saved, true)
	return endless_kit

func _endless_keep() -> void:
	Save.set_value("endless_kit", endless_kit)

## A hand's weapon as the kit has it: a preset's key, a forged design, or "" (none).
func _endless_arm(side: String):
	var k := _endless_kit()
	var pick := String(k.get("main" if side == "R" else "off", ""))
	if pick == "built":
		var d: Dictionary = Save.get_value("endless_weapon" if side == "R" else "endless_off_weapon", {})
		return d if not d.is_empty() else ("gladius" if side == "R" else "")
	if pick == "none" or not Data.presets.has(pick):
		return "" if side == "L" else "gladius"
	return pick

func _endless_bag() -> Dictionary:
	var bag := {}
	for id in _endless_kit().get("pots", []):
		if Endless.POTS.has(id) and bag.size() < ENDLESS_POT_KINDS:
			bag[String(id)] = ENDLESS_POT_EACH
	return Throwables.bag_clamp(bag)

func _endless(v: VBoxContainer) -> void:
	var k := _endless_kit()
	var rec: Dictionary = Save.get_value("endless", {})
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var tt := UIStyle.title("The endless arena", 34)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	v.add_child(head)
	v.add_child(UIStyle.label(Loc.t("Wave after wave of men and beasts, drawn at random, until you fall.") + " " + Loc.t("A great foe every fifth wave; between the waves a breath, and a reward to pick."), 15, UIStyle.MUTED))
	if Net.active():
		# (In a room the kit is the room's: everyone begins the waves with it, and the run is the party's.)
		var n := 1 + Net.peers.size()
		v.add_child(UIStyle.label(Loc.t("Your friends fight beside you with this same kit: the waves grow with the party, the fallen stand up again after each wave, and every one picks a reward of his own.") if n > 1 else Loc.t("Nobody else is in the room yet: friends who come in later join the next run."), 14, UIStyle.TEXT))
	var best := int(rec.get("best", 0))
	var today: Dictionary = rec.get("daily", {})
	var lines := []
	if best > 0:
		lines.append(Loc.t("Best: wave %d") % best)
	if String(today.get("day", "")) == Time.get_date_string_from_system(true) and int(today.get("best", 0)) > 0:
		lines.append(Loc.t("Today's challenge: wave %d") % int(today.best))
	if not lines.is_empty():
		v.add_child(UIStyle.label("  ·  ".join(lines), 16, UIStyle.GOLD))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(520, 0)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	left.add_child(UIStyle.label("YOUR ARMS", 13, UIStyle.BRONZE))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	left.add_child(g)
	var pick := func(label_: String, keys: Array, names: Array, key: String) -> void:
		var l := UIStyle.label(label_, 15)
		l.custom_minimum_size = Vector2(130, 0)
		g.add_child(l)
		var o := OptionButton.new()
		o.custom_minimum_size = Vector2(360, 0)
		o.fit_to_longest_item = false
		for n in names:
			o.add_item(Loc.t(String(n)))
		var at := maxi(0, keys.find(k.get(key)))
		k[key] = keys[at]
		o.select(at)
		o.item_selected.connect(func(i):
			k[key] = keys[i]
			_endless_keep())
		g.add_child(o)
	var forged := func(save_key: String) -> String:
		var d: Dictionary = Save.get_value(save_key, {})
		return Loc.t("Forged: %s") % (String(d.name) if d.has("name") else Loc.t("none yet"))
	pick.call("Main hand", ENDLESS_MAINS, ENDLESS_MAINS.map(func(x): return forged.call("endless_weapon") if x == "built" else Data.preset(x).get("name", x)), "main")
	pick.call("Off hand", ENDLESS_OFFS, ENDLESS_OFFS.map(func(x): return "Nothing" if x == "none" else (forged.call("endless_off_weapon") if x == "built" else Data.preset(x).get("name", x))), "off")
	var wb := HFlowContainer.new()
	wb.add_theme_constant_override("h_separation", 10)
	wb.add_theme_constant_override("v_separation", 8)
	wb.add_child(UIStyle.button("Forge main hand", func(): _endless_forge("R")))
	wb.add_child(UIStyle.button("Forge off hand", func(): _endless_forge("L")))
	left.add_child(wb)
	left.add_child(UIStyle.label(Loc.t("Armour").to_upper(), 13, UIStyle.BRONZE))
	var worn := Armory.sanitize(k.get("armor", []))
	var kg := 0.0
	for id in worn:
		kg += Armory.kg(id)
	var al := UIStyle.label((Loc.t("Armour: %d pieces · %.1f kg") % [worn.size(), kg]) if not worn.is_empty() else "Armour: none", 15)
	al.autowrap_mode = TextServer.AUTOWRAP_OFF
	_row(left, [al, UIStyle.button("Pick your armour", func(): show_screen("endless_armour"))])
	var daily := CheckBox.new()
	daily.text = "Today's challenge: the same waves for everyone"
	daily.button_pressed = bool(k.get("daily", false))
	daily.toggled.connect(func(x):
		k.daily = x
		_endless_keep())
	left.add_child(daily)
	# The pots: a few kinds, two of each, picked on and off.
	var pots: Array = (k.get("pots", []) as Array).filter(func(id): return Endless.POTS.has(id))
	k.pots = pots
	right.add_child(UIStyle.label(Loc.t("YOUR BAG · %d kinds at most, %d of each") % [ENDLESS_POT_KINDS, ENDLESS_POT_EACH], 13, UIStyle.BRONZE))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for id in Endless.POTS:
		var on: bool = pots.has(id)
		var item: Dictionary = Data.shop.get("throwables", {}).get(id, {})
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = on
		b.disabled = not on and pots.size() >= ENDLESS_POT_KINDS
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = Loc.t(String(item.get("desc", "")))
		var pot_id: String = id
		b.toggled.connect(func(x):
			var now: Array = k.get("pots", [])
			if x and not now.has(pot_id) and now.size() < ENDLESS_POT_KINDS:
				now.append(pot_id)
			elif not x:
				now.erase(pot_id)
			k.pots = now
			_endless_keep()
			show_screen("endless"))
		grid.add_child(b)
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 8
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(40, 40)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tex)
		var nm := UIStyle.label(Loc.t(String(item.get("name", id))), 15, UIStyle.TEXT if on else UIStyle.MUTED)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.size_flags_vertical = Control.SIZE_FILL
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(nm)
		Thumbs.item(tex, id)
	var go := _row(v, [UIStyle.button("Into the arena", _start_endless, true), UIStyle.button("Back", func(): show_screen(endless_back))])
	go.alignment = BoxContainer.ALIGNMENT_END

## The armour for the endless arena: the armourer's ready pieces, worn or taken off at a click
## (a piece over the same place takes the other off), nothing paid.
func _endless_armour(v: VBoxContainer) -> void:
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(1180.0, maxf(760.0, vp.x - 144.0)), maxf(480.0, vp.y - 80.0))
	var k := _endless_kit()
	var worn := Armory.sanitize(k.get("armor", []))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var tt := UIStyle.title("Armour", 34)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	head.add_child(UIStyle.button("Back", func(): show_screen("endless")))
	v.add_child(head)
	v.add_child(UIStyle.label("Nothing is paid for here. Click Wear on a piece; a piece that covers the same place takes the other off.", 13, UIStyle.MUTED))
	var set_worn := func(now: Array) -> void:
		k.armor = now
		_endless_keep()
		show_screen("endless_armour")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := _armour_worn_column(worn, func(id: String): set_worn.call(Armory.sanitize(k.get("armor", [])).filter(func(o): return o != id)), "No armour: put on what you like from the right.")
	if not worn.is_empty():
		left.add_child(UIStyle.button("Take it all off", func(): set_worn.call([])))
	cols.add_child(left)
	var scroll := _smith_scroll(cols)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	scroll.add_child(right)
	_armour_sections(right, Armory.SHOP.map(func(r): return r[0]), worn, func(col: VBoxContainer, id: String, on: bool):
		col.add_child(UIStyle.button("Take off" if on else "Wear", func():
			var now := Armory.sanitize(k.get("armor", []))
			set_worn.call(now.filter(func(o): return o != id) if on else Armory.buy(now, id).worn), not on)))

## The forge, free, for a hand of the endless arena's kit; back to its screen with the design
## kept for that hand.
func _endless_forge(hand: String) -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	var key := "endless_off_weapon" if hand == "L" else "endless_weapon"
	var base: Dictionary = Save.get_value(key, {})
	if base.is_empty():
		base = Data.preset("dagger" if hand == "L" else "gladius").duplicate(true)
	f.free_build = true
	f.open(base, 999999, func(design, _cost):
		if design != null:
			Save.set_value(key, design)
			_endless_kit()["off" if hand == "L" else "main"] = "built"
			_endless_keep()
		f.queue_free()
		show_screen("endless"))
	visible = true

func _start_endless() -> void:
	var k := _endless_kit()
	_endless_keep()
	var arm := Armory.sanitize(k.get("armor", []))
	var lo := {"main": _endless_arm("R"), "off": _endless_arm("L"), "armor": arm, "armor_defs": Armory.defs_of(arm)}
	start({"mode": "endless", "loadout_override": lo, "inventory_override": _endless_bag(), "decrees": [], "hazards": [], "endless": {"daily": bool(k.get("daily", false))}})

## Between the waves: the three rewards on cards, the arena held still while one is picked
## (a click, or 1, 2 or 3).
var endless_layer: CanvasLayer = null
var endless_deadline := 0   # (ms) when a party's time to pick runs out
## `wave` and `pick_time` only for a guest's (the host's word, `remote`): his pick goes to the host.
func _endless_offer(rewards: Array, wave := -1, pick_time := -1.0, remote := false) -> void:
	_endless_close()
	if match_ == null:
		return
	var en: Endless = match_.modes.endless if match_.modes and match_.modes.endless else null
	if en == null and not remote:
		return
	if not remote and en.party():
		pick_time = en.rest_t
	if wave < 0:
		wave = en.wave
	endless_layer = CanvasLayer.new()
	endless_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(endless_layer)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.theme = UIStyle.theme()
	endless_layer.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	UIStyle.frame_over(p)
	v.add_child(UIStyle.title(Loc.t("Wave %d beaten!") % wave, 32))
	v.add_child(UIStyle.label("Pick a reward: 1, 2 or 3", 15, UIStyle.MUTED))
	if pick_time > 0.0:
		# A party does not wait for the slowest: past this the first reward is taken for him.
		endless_deadline = Time.get_ticks_msec() + int(pick_time * 1000.0)
		var clock := UIStyle.label("", 15, UIStyle.GOLD)
		v.add_child(clock)
		var tick_clock := func():
			clock.text = Loc.t("%d s to pick, else the first is taken") % ceili(maxf(0.0, float(endless_deadline - Time.get_ticks_msec()) / 1000.0))
		tick_clock.call()
		var tm := Timer.new()
		tm.wait_time = 0.25
		tm.autostart = true
		tm.process_mode = Node.PROCESS_MODE_ALWAYS
		tm.timeout.connect(tick_clock)
		endless_layer.add_child(tm)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for i in rewards.size():
		var rw: Dictionary = rewards[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 132)
		var sc := Shortcut.new()
		var key := InputEventKey.new()
		key.physical_keycode = [KEY_1, KEY_2, KEY_3][mini(i, 2)]
		sc.events = [key]
		b.shortcut = sc
		b.shortcut_in_tooltip = false
		var at := i
		b.pressed.connect(func(): _endless_take(at, remote))
		var m := MarginContainer.new()
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 12)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(col)
		var nm := UIStyle.label("%d  ·  %s" % [i + 1, Loc.t(String(rw.title)).to_upper()], 16, UIStyle.GOLD_LIGHT)
		nm.add_theme_font_override("font", UIStyle.serif(1, 700))
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
		var tx := UIStyle.label(Loc.t(String(rw.text)), 15, UIStyle.TEXT)
		tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(tx)
		row.add_child(b)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.active():
		get_tree().paused = true

func _endless_take(i: int, remote := false) -> void:
	var en = match_.modes.endless if match_ and match_.modes else null
	_endless_close()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if remote:
		Net.send_host("endless_pick", i)   # (the host gives it, and tells me when every one has picked)
	elif en:
		en.take(i)

## Every reward of the rest is taken (or the time ran out): the screen of the rewards goes, if it is still up.
func _endless_done() -> void:
	if endless_layer == null:
		return
	_endless_close()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _endless_close() -> void:
	if endless_layer and is_instance_valid(endless_layer):
		endless_layer.queue_free()
	endless_layer = null

# ---------- The yard: the smith ----------

func _yard(v: VBoxContainer) -> void:
	SmithScreen.build(self, v)

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
	var q := UIStyle.label(Loc.t("Both your hands are full. Which one does Vulcanus take for the %s?") % Loc.t(nm), 16, UIStyle.TEXT)
	q.custom_minimum_size = Vector2(420, 0)
	v.add_child(q)
	for sd in sides:
		var side: String = sd
		var d = arms().main if side == "R" else arms().off
		var r: Dictionary = buy.call(side)
		var b := UIStyle.button(Loc.t("Sell the %s (main hand) · pay %d" if side == "R" else "Sell the %s (off hand) · pay %d") % [Loc.t(str(d.get("name", "?"))) if d else "?", int(r.get("cost", 0))], func():
			dim.queue_free()
			var got: Dictionary = buy.call(side)
			if bought.is_valid() and not got.has("error") and int(got.get("cost", 0)) <= coins():
				bought.call()
			_pay(got))
		b.disabled = int(r.get("cost", 0)) > coins()
		v.add_child(b)
	v.add_child(UIStyle.button("Keep both", func(): dim.queue_free()))

## Selling a weapon in a hand to the smith, asked once more first: it cannot be had back.
func _sell_confirm(side: String) -> void:
	var d = arms().main if side == "R" else arms().off
	if not (d is Dictionary) or Arms.is_stick(d):
		return
	var got := Arms.sale_price(d)
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
	var q := UIStyle.label(Loc.t("Sell the %s to Vulcanus? It is gone for good.") % Loc.t(str(d.get("name", "it"))), 16, UIStyle.TEXT)
	q.custom_minimum_size = Vector2(420, 0)
	v.add_child(q)
	v.add_child(UIStyle.label(Loc.t("You get %d denarii · you will have %d") % [got, coins() + got], 15, UIStyle.GOLD))
	v.add_child(UIStyle.button("Sell it", func():
		dim.queue_free()
		_pay(Arms.sell(arms(), side)), true))
	v.add_child(UIStyle.button("Keep it", func(): dim.queue_free()))

## This campaign run's seed for the smith's oddities (drawn once, kept with the save).
func run_seed() -> int:
	if Save.get_value("run_seed") == null:
		Save.set_value("run_seed", randi())
	return int(Save.get_value("run_seed", 0))

## Every worn piece mended at once at the smith, and whole on him in the yard there and then.
func _mend_all_armour() -> void:
	var m := Armory.mend_all(armor_wear(), worn_armor())
	if int(m.cost) > coins():
		show_screen("yard", "Not enough denarii")
		return
	add_coins(-int(m.cost))
	set_armor_wear(m.wear)
	_armour_on_him()
	show_screen("yard")

## A list on the smith's screen that takes what height is left and scrolls within it.
func _smith_scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll

var smith_tab := "weapons"
var smith_group := "arms"      # the list on the smith's right: arms, sale, works, designs
var smith_sel := {}            # what lies on his anvil
var armour_sel := ""           # the piece of armour he is looking at
var armour_region := "all"     # and the part of the body the rack is shown for
var trainer_prev := {}         # what the trainer had taught him before the session just bought (the radar moves from it)
var station_note := {}         # what a deed leaves to show when its stall is drawn again: the price that rises from the purse, why it could not be done (warn), the ability to light on the radar (axis)

const ARMOUR_PARTS := {"head": "head", "torso": "body", "upperArmR": "arms", "upperArmL": "arms", "forearmR": "forearms", "forearmL": "forearms", "thighR": "thighs", "thighL": "thighs", "shinR": "shins", "shinL": "shins"}

static func _dots(x: float) -> String:
	var n := clampi(int(round(x * 5.0)), 0, 5)
	return "●".repeat(n) + "○".repeat(5 - n)

# ---------- Armour at the forge and in training ----------

## Which part of the body a piece is for, for the sections of an armour screen.
const ARMOUR_REGIONS := [["Head", ["head"]], ["Body", ["torso"]], ["Arms", ["upperArmR", "upperArmL", "forearmR", "forearmL"]], ["Legs", ["thighR", "thighL", "shinR", "shinL"]]]

static func _armour_region(id: String) -> String:
	var parts: Array = Armory.parts_of(id)
	for r in ARMOUR_REGIONS:
		for k in r[1]:
			if parts.has(k):
				return r[0]
	return "Body"

## A little man with the parts a set of pieces covers filled in their metal's colour (the HUD's
## figure); `covered` is {part: Color}. `px` is the figure's width.
func _armour_figure(covered: Dictionary, px := 58.0) -> Control:
	var fig := Control.new()
	var k_ := px / Hud.FIG_W
	fig.custom_minimum_size = Vector2(Hud.FIG_W, Hud.FIG_H) * k_
	fig.draw.connect(func():
		fig.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k_, k_))
		for k in Hud.LAYOUT:
			var rr: Rect2 = Hud.LAYOUT[k]
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(4 if k != "head" else 10)
			var on: bool = covered.has(k)
			sb.bg_color = covered[k] if on else Color(1, 1, 1, 0.08)
			sb.border_color = Color(1, 1, 1, 0.3) if on else Color(1, 1, 1, 0.07)
			sb.set_border_width_all(1)
			fig.draw_style_box(sb, rr.grow(-1.0)))
	return fig

static func _armour_colour(id: String) -> Color:
	return Weapon.voxel_color(Data.armor.get(id, {}).get("mat", "iron"), "blunt")

## {part: Color} for everything in `worn`.
static func _armour_cover(worn: Array) -> Dictionary:
	var out := {}
	for id in worn:
		for k in Armory.parts_of(id):
			out[k] = _armour_colour(id)
	return out

## One piece as a card: the little man with the piece on him, its name, metal, protection and
## weight, what it replaces, and the button to wear it or take it off (`act` fills the button
## and any lines of its own below the facts: act(col, id, on)).
func _armour_card(id: String, worn: Array, act: Callable) -> PanelContainer:
	var a: Dictionary = Data.armor.get(id, {})
	var on := worn.has(id)
	var card := PanelContainer.new()
	var sb := UIStyle._plate(Color(0.1, 0.075, 0.055, 0.95), UIStyle.GOLD if on else UIStyle.BRONZE_DARK, 2 if on else 1)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var cov := {}
	for k in Armory.parts_of(id):
		cov[k] = _armour_colour(id)
	row.add_child(_armour_figure(cov, 50.0))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var name_row := HBoxContainer.new()
	var nm := UIStyle.label(String(a.get("name", id)), 16, UIStyle.GOLD if on else UIStyle.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	if on:
		var tag := UIStyle.label("WORN", 11, UIStyle.GOLD)
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF   # (squeezed to a letter a line beside the name)
		name_row.add_child(tag)
	col.add_child(name_row)
	var where := []
	for k in Armory.parts_of(id):
		if not where.has(ARMOUR_PARTS.get(k, k)):
			where.append(ARMOUR_PARTS.get(k, k))
	col.add_child(UIStyle.label("%s · %s" % [String(a.get("mat", "iron")).capitalize(), ", ".join(where)], 12, UIStyle.BRONZE))
	col.add_child(UIStyle.label(Loc.t("Protection %s · %.1f kg") % [_dots(Armory.protection(id)), Armory.kg(id)], 12, UIStyle.TEXT))
	if not on:
		var swaps := worn.filter(func(o): return Armory.clashes(o, id))
		if not swaps.is_empty():
			col.add_child(UIStyle.label(Loc.t("Replaces your %s") % Loc.t(String(Data.armor[swaps[0]].name)), 12, UIStyle.MUTED))
	act.call(col, id, on)
	return card

## The pieces in sections by the part of the body they are for, My designs first, two cards a
## row; `act` as in _armour_card.
func _armour_sections(parent: Control, ids: Array, worn: Array, act: Callable, columns := 2) -> void:
	var designs: Dictionary = Save.get_value("armor_designs", {})
	var groups := {"My designs": []}
	for r in ARMOUR_REGIONS:
		groups[r[0]] = []
	for idv in ids:
		var id: String = idv
		if Data.armor.get(id, {}).is_empty():
			continue
		groups["My designs" if designs.has(id) else _armour_region(id)].append(id)
	for g in groups:
		var list: Array = groups[g]
		if list.is_empty():
			continue
		# (A label in a row with nothing to fill it was squeezed to a letter a line: _row sets
		# its wrapping off.)
		var worn_here: int = list.filter(func(i): return worn.has(i)).size()
		_row(parent, [UIStyle.label(Loc.t(String(g)).to_upper(), 13, UIStyle.BRONZE)] + ([UIStyle.label(Loc.t("· %d worn") % worn_here, 12, UIStyle.GOLD)] if worn_here > 0 else []))
		var grid := GridContainer.new()
		grid.columns = columns
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		parent.add_child(grid)
		for id in list:
			grid.add_child(_armour_card(id, worn, act))

## What is worn, as a column: the figure with it all on, the pieces one a line with a button to
## take each off, and what it all weighs and costs in breath and pace.
func _armour_worn_column(worn: Array, take_off: Callable, empty_text: String) -> VBoxContainer:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 8)
	left.add_child(UIStyle.label("YOU WEAR", 13, UIStyle.BRONZE))
	var figrow := HBoxContainer.new()
	figrow.alignment = BoxContainer.ALIGNMENT_CENTER
	figrow.add_child(_armour_figure(_armour_cover(worn), 120.0))
	left.add_child(figrow)
	if worn.is_empty():
		var e := UIStyle.label(empty_text, 13, UIStyle.MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(e)
		return left
	var kg := 0.0
	for id in worn:
		kg += Armory.kg(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := UIStyle.label(Loc.t("%s · %.1f kg") % [Loc.t(String(Data.armor[id].name)), Armory.kg(id)], 13, UIStyle.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := UIStyle.button("Take off", take_off.bind(id))
		b.tooltip_text = Loc.t("Take off the %s") % Loc.t(String(Data.armor[id].name))
		row.add_child(b)
		left.add_child(row)
	var with := Armory.burden(kg)
	left.add_child(UIStyle.label(Loc.t("%d piece · %.1f kg" if worn.size() == 1 else "%d pieces · %.1f kg") % [worn.size(), kg], 14, UIStyle.TEXT))
	left.add_child(UIStyle.label(Loc.t("Breath ×%.2f · pace %d%%") % [float(with.breath), int(round(float(with.pace) * 100.0))], 13, UIStyle.MUTED))
	return left

## Armour for training, free: every piece the smith sells and every one of My designs, in
## sections by the part of the body, worn or taken off with a click (a piece replaces what it
## clashes with); what is worn stands on the left; or a new one made at the bench.
func _training_armour(v: VBoxContainer) -> void:
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(1180.0, maxf(760.0, vp.x - 144.0)), maxf(480.0, vp.y - 80.0))
	var worn := Armory.sanitize(training.get("armor", []))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var tt := UIStyle.title("Armour for training", 34)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	if Armory.plate_bench_open:
		head.add_child(UIStyle.button("Make a piece at the bench (free)", func():
			bench_mode = "training"
			_plate_bench(Armory.design_piece(bench.region, bench.mat, bench.y0, bench.y1, bench.front, bench.cap, ""), _bench_worn_kg())))
	head.add_child(UIStyle.button("Back", func(): show_screen("training")))
	v.add_child(head)
	v.add_child(UIStyle.label("Nothing is paid for here. Click Wear on a piece; a piece that covers the same place takes the other off.", 13, UIStyle.MUTED))
	var set_worn := func(now: Array) -> void:
		training.armor = now
		Save.set_value("training", training)
		show_screen("training_armour")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := _armour_worn_column(worn, func(id: String): set_worn.call(Armory.sanitize(training.get("armor", [])).filter(func(o): return o != id)), "You wear no armour in training. Put on what you like from the right.")
	if not worn.is_empty():
		left.add_child(UIStyle.button("Take it all off", func(): set_worn.call([])))
	cols.add_child(left)
	var scroll := _smith_scroll(cols)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	scroll.add_child(right)
	var designs: Dictionary = Save.get_value("armor_designs", {})
	var ids: Array = designs.keys().filter(func(i): return Armory.custom(String(i))) + Armory.SHOP.map(func(r): return r[0])
	_armour_sections(right, ids, worn, func(col: VBoxContainer, id: String, on: bool):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UIStyle.button("Take off" if on else "Wear", func():
			var now := Armory.sanitize(training.get("armor", []))
			set_worn.call(now.filter(func(o): return o != id) if on else Armory.buy(now, id).worn), not on))
		if designs.has(id):
			var bin := UIStyle.button("Delete the design", func():
				var ds: Dictionary = Save.get_value("armor_designs", {})
				ds.erase(id)
				Save.set_value("armor_designs", ds)
				set_worn.call(Armory.sanitize(training.get("armor", [])).filter(func(o): return o != id)))
			row.add_child(bin)
		col.add_child(row))

# ---------- The armourer's bench ----------

var bench := {"region": "torso", "mat": "iron", "y0": 0.3, "y1": 1.0, "front": false, "cap": true, "name": ""}
## Whose bench it is: "smith" (the campaign's, paid for and worn), "workshop" (the main menu's
## armourer: designed and kept in My designs, free) or "training" (made free and worn there).
var bench_mode := "smith"

func _bench_back() -> String:
	return {"smith": "yard", "workshop": "main", "training": "training_armour", "contest": "ff_contest"}.get(bench_mode, "yard")

## Back from the armour bench to where it was opened (the main menu's forge opens again).
func _bench_return(msg := "") -> void:
	if bench_mode == "contest":
		ff_open = null   # (the bench closed: the contest screen is drawn afresh as things change)
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
		"contest": return Armory.sanitize(ff.get("kit", {}).get("armor", []))
	return []

## A piece made at a free bench (the workshop's or training's): kept in My designs, and in
## training put on as well.
func _bench_keep(final: Dictionary) -> void:
	var ids := Armory.register([final])
	if bench_mode == "contest":
		# Forge and Fight: made and worn for the fight (it replaces what covers the same place).
		ff_open = null
		if not ids.is_empty() and not ff.is_empty():
			var r := Armory.buy(ff.kit.armor, String(ids[0]))
			if r.has("worn"):
				ff.kit.armor = r.worn
			_ff_changed()
		show_screen("ff_contest")
		return
	if ids.is_empty():
		show_screen(_bench_back())
		return
	var designs: Dictionary = Save.get_value("armor_designs", {})
	designs[ids[0]] = final
	Achievements.unlock("armourer")
	Save.set_value("armor_designs", designs)
	if bench_mode == "training":
		training.armor = Armory.buy(Armory.sanitize(training.get("armor", [])), ids[0]).worn
		Save.set_value("training", training)
	_bench_return(Loc.t("%s kept in My designs and worn" if bench_mode == "training" else "%s kept in My designs") % String(final.get("name", Loc.t("The piece"))))

## The armourer's bench voxel by voxel (ArmourForge) over the smith's screen.
func _plate_bench(def: Dictionary, worn_kg: float) -> void:
	var f := ArmourForge.new()
	add_child(f)
	if bench_mode == "contest":
		ff_open = f   # (closed by the clock if it is still open when the time is up)
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
	Achievements.unlock("armourer")
	show_screen("yard")

## Every other way to fight (game.js modes, partyModes.js).
## The fights, as cards in four groups: each says in a line what the bout is.
const FIGHT_GROUPS := [
	["Single combat", ["bo3", "king", "tourney"]],
	["The melee", ["ffa", "teams", "forgefight"]],
	["Beasts and waves", ["endless", "hunt"]],
	["Games for the Emperor", ["emperor", "hill", "lastLimb"]],
]
const FIGHT_BLURBS := {
	"endless": "Wave after wave of men and beasts, drawn at random, until you fall.",
	"bo3": "One against one. Floored: yield, or fight on wounded for double the stake.",
	"king": "The winner stays and the next challenger walks in. Reign for seven.",
	"tourney": "One on one, the winner goes on to the next round, until one is crowned.",
	"ffa": "Everyone on one sand, the last one standing wins. Bots and decrees as you choose.",
	"teams": "Red against Blue: friends walk into a circle to pick a side, bots fill the rest.",
	"hunt": "Beasts pour through the gates in waves. Each wave beaten heals you.",
	"emperor": "You are the Emperor: send decrees, beasts, weapons and tomatoes, then judge.",
	"hill": "Hold the circle alone for 20 seconds.",
	"lastLimb": "Every 15 seconds the Emperor takes a limb from everyone.",
	"forgefight": "Everyone forges weapons and armour against the clock, then all fight to the death with what they made.",
}

func _fights(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("The Arena", 34))
	var in_room := Net.active()
	if not (in_room and Net.room_kind == Net.KIND_ARENA):
		v.add_child(UIStyle.label("Your arms from the yard stay home: these fights hand out their own weapons.", 15, UIStyle.MUTED))
	for g in FIGHT_GROUPS:
		# (The friends' fights only in a room; the endless arena only alone.)
		var keys: Array = (g[1] as Array).filter(func(k): return (k != "forgefight" or in_room) and Edition.mode_open(k, in_room))
		if keys.is_empty():
			continue
		v.add_child(UIStyle.label(Loc.t(String(g[0])).to_upper(), 13, UIStyle.BRONZE))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		v.add_child(grid)
		for k in keys:
			grid.add_child(_fight_card(k))
	if in_yard():
		pass   # (the way out is the button at the top: the yard went on behind this screen)
	elif Net.active() and Net.is_host():
		v.add_child(UIStyle.button("Back to the yard, all of you", func(): enter_yard()))
	else:
		v.add_child(UIStyle.button("Back", func(): show_screen("main")))

## What a fight is started with, as the host last set it (per fight, in the settings: "fight_opts"): each setting one of the
## numbers the fight offers (FightOpts).
func _fight_opts_of(k: String) -> Dictionary:
	var all = Save.get_value("settings", {}).get("fight_opts")
	return FightOpts.clean(k, (all as Dictionary).get(k) if all is Dictionary else {})

func _set_fight_opt(k: String, key: String, v: int) -> void:
	var st: Dictionary = Save.get_value("settings", {})
	var all: Dictionary = st.get("fight_opts") if st.get("fight_opts") is Dictionary else {}
	var mine: Dictionary = all.get(k) if all.get(k) is Dictionary else {}
	mine[key] = v
	all[k] = mine
	st["fight_opts"] = all
	Save.set_value("settings", st)

## The settings as a start takes them: the rounds, the bots, the decrees (named as Match and Modes read them).
func _fight_start_opts(k: String) -> Dictionary:
	var o := _fight_opts_of(k)
	var out := {"mode": k}
	for key in o:
		out[{"rounds": "rounds", "bots": "bots", "decrees": "decrees_n"}[key]] = o[key]
	return out

var fight_pick := ""   # the fight whose settings are on the screen (fight_setup)

## A fight's card: the fights with settings open them first (fight_setup), the others begin.
func _fight_press(k: String) -> void:
	if k == "endless":
		endless_back = "fights"
		show_screen("endless")
	elif FightOpts.offers(k).is_empty():
		start({"mode": k})
	else:
		fight_pick = k
		show_screen("fight_setup")

## The settings of a fight (rounds, bots, decrees, as the fight offers them), what that makes of the sand, and the start.
func _fight_setup(v: VBoxContainer) -> void:
	var k := fight_pick
	v.add_child(UIStyle.title(Loc.t(String(Modes.TITLES.get(k, k))).trim_suffix("!"), 32))
	v.add_child(UIStyle.label(FIGHT_BLURBS.get(k, Modes.LABELS.get(k, "")), 15, UIStyle.MUTED))
	var mine := _fight_opts_of(k)
	for key in FightOpts.offers(k):
		var on := FightOpts.choices(k, key)
		var lab := UIStyle.label(FightOpts.label(k, key, int(mine[key])), 17, UIStyle.GOLD_LIGHT)
		lab.custom_minimum_size = Vector2(230, 0)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var step := func(d: int):
			var i := on.find(int(_fight_opts_of(k)[key]))
			_set_fight_opt(k, key, int(on[posmod(i + d, on.size())]))
			show_screen("fight_setup")
		var less := UIStyle.button("◀", func(): step.call(-1))
		var more := UIStyle.button("▶", func(): step.call(1))
		less.tooltip_text = "Fewer"
		more.tooltip_text = "More"
		var name_l := UIStyle.label(FightOpts.title(key), 16, UIStyle.MUTED)
		name_l.custom_minimum_size = Vector2(90, 0)   # (the arrows of every row stand in one line)
		_row(v, [name_l, less, lab, more])
	var humans := 1 + (Net.peers.size() if Net.active() else 0)
	var bots := _bots_of(k, humans)
	v.add_child(UIStyle.label(FightOpts.fighters_text(humans, bots), 15, UIStyle.TEXT))
	var lonely := mine.has("bots") and humans + bots < 2
	if lonely:
		v.add_child(UIStyle.label("A fight needs at least two: add a bot.", 14, Color(0.95, 0.4, 0.3)))
	var go := UIStyle.button("Begin", func(): _fight_go(k), true)
	go.disabled = lonely
	_row(v, [go, UIStyle.button("Back", func(): show_screen("fights"))])

## How many bots the settings put on the sand beside `humans` (a fight's usual when none was set).
func _bots_of(k: String, humans: int) -> int:
	var m := Modes.new(null, k)
	var mine := _fight_opts_of(k)
	if k == "tourney":
		return maxi(0, Tourney.entrant_count(humans, int(mine.get("bots", FightOpts.FILL))) - humans)
	if mine.has("bots") and int(mine.bots) >= 0:
		return FightOpts.bots_allowed(humans, int(mine.bots))
	return m.bot_count(humans if k != "emperor" else humans - 1) if k != "teams" else maxi(0, 4 - humans)

## A team fight in a room: the friends pick their sides first, each walking into the circle on the sand (in the yard) of the
## team he plays for; the host begins (E) when all stand in one (_team_go).
func _team_setup(k: String, opts: Dictionary) -> void:
	enter_yard()
	if match_ and is_instance_valid(match_) and match_.yard:
		match_.yard.begin_teams(k, opts)
		match_._banner(Modes.title_of(k), Loc.t("Choose your team"))

## All stand in a circle and the host begins: the fight, each on the side of his circle.
func _team_go() -> void:
	if not (match_ and is_instance_valid(match_) and match_.yard and match_.yard.team_setup != null and Net.is_host()):
		return
	var ts: TeamSetup = match_.yard.team_setup
	if not ts.ready():
		return
	var opts: Dictionary = ts.opts.duplicate()
	opts.mode = ts.mode
	opts.teams = ts.assignment()
	match_.yard.end_teams()
	start(opts)

## The settings are in: the fight begins (the team fights first have the friends pick their sides in the yard).
func _fight_go(k: String) -> void:
	var opts := _fight_start_opts(k)
	if k == "tourney":
		_tourney_begin(opts)
	elif k == "forgefight":
		ff_setup()
	elif TeamSetup.is_team_mode(k) and Net.active() and Net.is_host():
		_team_setup(k, opts)
	else:
		start(opts)

## One fight's card: its name in capitals, under it what it is, the whole card a button.
func _fight_card(k: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(262, 104)
	b.pressed.connect(func():
		if k == "forgefight":
			ff_setup()
		else:
			_fight_press(k))
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
	var blurb := UIStyle.label(_forge_fight_line() if k == "forgefight" else FIGHT_BLURBS.get(k, Modes.LABELS.get(k, "")), 15, UIStyle.MUTED)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(blurb)
	return b

## The co-op campaign's button (the gate's, the room's, its card among the fights), held back
## while more are in the room than the campaign takes, with the reason under it (user: four at
## most in the campaign, eight in every other fight).
func _campaign_cap(b: Button, v: Control) -> void:
	if not Net.campaign_full():
		return
	b.disabled = true
	b.tooltip_text = campaign_full_text()
	v.add_child(UIStyle.label(campaign_full_text(), 15, UIStyle.MUTED))

func campaign_full_text() -> String:
	return Loc.t("The co-op campaign takes %d players at most, and %d of you are in the room. The arena modes take up to %d.") % [Net.CAMPAIGN_PLAYERS, Net.peers.size() + 1, Net.MAX_PLAYERS]

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
		v.add_child(UIStyle.label(Loc.t("Day %s is over. Pick one blessing for the rest of the run.") % ROMAN[clampi(int(run.day) - 1, 0, 6)], 15, UIStyle.MUTED))
		for id in run.pending_blessing:
			var b: Dictionary = Circus.blessings().get(id, {})
			var btn := UIStyle.button("%s: %s" % [Loc.t(String(b.get("name", id))), Loc.t(String(b.get("desc", "")))], func():
				var r2 = circus_run()
				Circus.grant(r2, id)
				Save.set_value("circus_run", r2)
				show_screen("circus", Loc.t("%s blesses you") % Loc.t(String(b.get("name", id)))), true)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(btn)
		return
	var day: Dictionary = Circus.days()[int(run.day)]
	v.add_child(UIStyle.title(Loc.t("Day %s · %s") % [ROMAN[int(run.day)], Loc.t(String(day.get("theme", "")))], 26))
	for i in day.bouts.size():
		var b: Dictionary = day.bouts[i]
		var mark := "✔" if i < int(run.bout) else ("▶" if i == int(run.bout) else "·")
		var col := UIStyle.MUTED if i < int(run.bout) else (UIStyle.GOLD if i == int(run.bout) else UIStyle.TEXT)
		v.add_child(UIStyle.label("%s  %s%s" % [mark, Loc.t(String(b.name)), Loc.t("  · boss") if b.get("boss", false) else ""], 16, col))
	var bout := Circus.current(run)
	v.add_child(UIStyle.label(String(bout.get("intro", "")), 15, UIStyle.TEXT))
	var bl: Array = run.blessings.map(func(id): return Loc.t(String(Circus.blessings().get(id, {}).get("name", id))))
	var inv: Array = []
	for id in run.inventory:
		if int(run.inventory[id]) > 0:
			inv.append("%s ×%d" % [Loc.t(String(Data.shop.get("throwables", {}).get(id, {}).get("name", id))), int(run.inventory[id])])
	v.add_child(UIStyle.label(Loc.t("Gold: %d · blessings: %s · kit: %s%s") % [int(run.gold), ", ".join(bl) if not bl.is_empty() else Loc.t("none yet"),
		", ".join(inv) if not inv.is_empty() else Loc.t("nothing yet"), Loc.t(" · DAILY GAMES") if run.get("daily", false) else ""], 14, UIStyle.BRONZE))
	_row(v, [UIStyle.button(Loc.t("Fight: %s") % Loc.t(String(bout.get("name", ""))), _circus_fight, true), UIStyle.button("The market", func(): show_screen("circus_market")),
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
		UIStyle.button(Loc.t("The Daily Games · %s") % Circus.daily_label(), func():
			Save.set_value("circus_run", Circus.new_run(ludus(), true))
			show_screen("circus", "Today's games: the same bouts, decrees and blessings for everyone"))])
	v.add_child(UIStyle.title(Loc.t("The ludus · %d denarii") % int(lu.denarii), 24))
	for id in Circus.ludus_upgrades():
		var u: Dictionary = Circus.ludus_upgrades()[id]
		var lvl := int(lu.levels.get(id, 0))
		var maxed := lvl >= int(u.get("max", 1))
		var b := UIStyle.button((Loc.t("%s (%d/%d) · maxed") % [Loc.t(String(u.name)), lvl, int(u.max)]) if maxed else ("%s (%d/%d) · %d" % [Loc.t(String(u.name)), lvl, int(u.max), Circus.ludus_price(id, lvl)]), func():
			var l2 := ludus()
			var why = Circus.buy_upgrade(l2, id)
			Save.set_value("ludus", l2)
			show_screen("circus", why if why != null else Loc.t("%s bought") % Loc.t(String(u.name))))
		b.tooltip_text = u.get("desc", "")
		b.disabled = maxed
		_row(v, [b, UIStyle.label(String(u.get("desc", "")), 13, UIStyle.MUTED)])
	var hall: Array = Save.get_value("hall", [])
	if not hall.is_empty():
		v.add_child(UIStyle.title("Hall of Fame", 24))
		for i in mini(5, hall.size()):
			var h: Dictionary = hall[i]
			v.add_child(UIStyle.label(Loc.t("%d. %s · %s · %d bouts, %d kills%s") % [i + 1, h.name, Loc.t("won the rudis" if h.get("campaign", false) else "crowned by the Emperor") if h.won else Loc.t("fell on day %s to %s") % [ROMAN[clampi(int(h.day) - 1, 0, 6)], Loc.t(String(h.get("fate", "the arena")))], int(h.bouts), int(h.kills), Loc.t(" · daily") if h.get("daily", false) else (Loc.t(" · the campaign") if h.get("campaign", false) else "")], 14, UIStyle.GOLD if h.won else UIStyle.TEXT))
	_row(v, [UIStyle.button("Main menu", func(): show_screen("main"))])

func _circus_market(v: VBoxContainer) -> void:
	var run = circus_run()
	if run == null:
		show_screen("circus")
		return
	v.add_child(UIStyle.title("The market", 32))
	v.add_child(UIStyle.label(Loc.t("Gold: %d · what you buy is used in the next bouts (keys 1 to 8)") % int(run.gold), 15, UIStyle.BRONZE))
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
		# (What he carries of it, of the most he can hold; and when none fit, the reason in the button.)
		var carry := StationKit.carry_of(run.inventory, id)
		var none := String(carry.why) != ""
		var lbl := UIStyle.label("%s  %d/%d" % [Loc.t(String(it.name)), have, int(carry.max)], 15, StationKit.BAD if none else UIStyle.TEXT)
		lbl.custom_minimum_size = Vector2(190, 0)
		lbl.tooltip_text = it.get("desc", "")
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		var b := UIStyle.button(StationKit.carry_short(carry) if none else Loc.t("Buy · %d gold") % price, func():
			var r2 = circus_run()
			if int(r2.gold) < price:
				show_screen("circus_market", "Not enough gold")
				return
			if not Throwables.bag_has_room(r2.inventory, id):
				show_screen("circus_market", StationKit.carry_short(StationKit.carry_of(r2.inventory, id)))
				return
			r2.gold = int(r2.gold) - price
			r2.inventory[id] = int(r2.inventory.get(id, 0)) + 1
			Save.set_value("circus_run", r2)
			show_screen("circus_market"))
		b.disabled = none
		b.tooltip_text = StationKit.carry_line(carry)
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
	last_result = {"text": Loc.t("The ludus earns %d denarii from this run.") % pay}

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
			show_screen("circus", Loc.t("Victory! +%d gold") % pay)
		"dayEnd":
			show_screen("circus", Loc.t("Victory! +%d gold. The day is done.") % pay)
		"spared":
			show_screen("circus", "PLUTO SAYS NO: you are sent back from the underworld. Fight the bout again.")
		"victory":
			_circus_close(run, "")
			show_screen("circus", Loc.t("THE EMPEROR CROWNS YOU! Seven days, and you still stand. %s") % last_result.text)
		"wipe":
			_circus_close(run, String(r.get("killer", "the arena")))
			show_screen("circus", Loc.t("You fell on day %s. %s") % [ROMAN[clampi(int(run.day), 0, 6)], last_result.text])

## The market (yardUI.js): every product on a card with its own model, what it does, how it is
## used and what it costs; tabs by what a ware does (Market). A ware the trader has not brought
## yet lies on his table all the same, with the bout whose boss brings it.
const MARKET_USE := {"self": "Press its number: used on you at once", "place": "Press its number: laid or bowled in front of you", "throw": "Its number takes it in hand; hold F to aim, let go to throw",
	"arrow": "Its number picks it for your bow: every arrow you loose is this one till they run out; its number again puts it back"}
const FRIENDLY_FIRE := ["thunderPot", "nailPot", "caltrops", "oliveOil", "honey", "anvil", "greekFire", "vitriol", "mystery", "torch", "fireArrow", "blastArrow"]
var market_tab := "fire"
var market_sel := ""        # the ware on the trader's stand

static func kit_use(id: String) -> String:
	return "self" if ["bandage", "bread", "wine", "waterSkin"].has(id) else ("place" if ["bananas", "cheese"].has(id) else ("arrow" if Throwables.ARROWS.has(id) else "throw"))

func _market(v: VBoxContainer) -> void:
	MarketScreen.build(self, v)

## The bout the campaign is on and its time round, for the trader's table: alone his own; in a
## party the party's (a guest is told the host's with the gate's fights: YardPlay.gate_info).
func _market_at() -> Vector2i:
	var coop := Net.active()
	if coop and not Net.is_host():
		var yard: YardPlay = match_.yard if match_ and is_instance_valid(match_) else null
		var gi: Dictionary = yard.gate_info if yard else {}
		if not gi.is_empty():
			return Vector2i(int(gi.s), int(gi.l))
	return Vector2i(int(Save.get_value("coop_stage" if coop else "stage", 1)), int(Save.get_value("coop_lap" if coop else "lap", 1)))

## The physician's stall in the yard: the same treatments as between rounds, and his supplies for
## the fight (PhysicianScreen).
func _physician(v: VBoxContainer) -> void:
	var yard := in_yard()
	PhysicianScreen.build(self, v, panel, {
		"body": body(), "stage": int(Save.get_value("stage", 1)), "supplies": true,
		"done_text": "" if yard else "Back",
		"done": func(nb):
			set_body(nb)
			if yard:
				_close_overlay()
			else:
				show_screen("yard"),
		"changed": func(nb):
			set_body(nb)
			show_screen("physician")})

## What the trainer has taught this gladiator (Training), kept with the campaign under "trainer"
## (it was kept under "training", with the training ground's own choices, and each wrote over the
## other: a session bought threw away the training ground's bag, and the training ground put back
## what a death had taken).
func training_stats() -> Dictionary:
	var raw = Save.get_value("trainer")
	if not (raw is Dictionary):
		raw = Training.from_old(Save.get_value("training", {}))
	var st := Training.sanitize(raw)
	var vt := int(Save.get_value("virtus", 0))
	if vt > 0:
		st = Training.sanitize(st.merged({"virtus": vt}, true))
	return st

## (Virtus is kept apart: a death and a new campaign clear the rest, never it.)
func set_training_stats(st: Dictionary) -> void:
	var clean := Training.sanitize(st)
	if clean.has("virtus"):
		Save.set_value("virtus", int(clean.virtus))
	clean.erase("virtus")
	Save.set_value("trainer", clean)
	_net_loadout()

## The trainer's yard: six abilities, a session of each for denarii, no further than the bout
## allows. Alone and in a party alike (each man trains his own body from the party's purse).
func _trainer(v: VBoxContainer) -> void:
	TrainerScreen.build(self, v)

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
		p.add_theme_stylebox_override("panel", panel_style)
		cc.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		p.add_child(v)
		UIStyle.frame_over(p, Vector2(32, 26))
		PhysicianScreen.build(self, v, p, {
			"body": cur[0], "news": news, "stage": stage_, "done_text": "Back to the arena",
			"done": func(nb):
				layer.queue_free()
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				done.call(nb),
			"changed": func(nb):
				cur[0] = nb
				rebuild.call(rebuild)})
	build.call(build)

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

## The smith's work on his body, paid for (a prosthetic refitted): on him at once.
func _pay_body(r: Dictionary) -> void:
	if r.has("error"):
		show_screen("yard", r.error)
		return
	if int(r.cost) > coins():
		show_screen("yard", "Not enough denarii")
		return
	add_coins(-int(r.cost))
	set_body(r.body)
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
## `hand`: "L" makes it for the off hand (a dagger, a hatchet, a second sword).
func _scratch_forge(hand := "") -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.scratch = true
	var blank := {"name": "New weapon" if hand != "L" else "Off-hand weapon", "kind": "weapon", "sharpness": 0.8, "voxels": [[0, 0, 0, "wood", "grip"]]}
	f.open(blank, coins(), func(design, _cost):
		f.queue_free()
		show_screen("yard")
		if design == null:
			return
		var r := Arms.buy_design(arms(), design, "", -1, hand)
		if r.has("choose"):
			_sell_choice(str(design.get("name", "it")), func(sd): return Arms.buy_design(arms(), design, sd, -1, hand), r.choose)
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

# ---------- Forge and Fight ----------

## The game under way: its phase ("weapons", "armour", "fight"), when the phase ends, the kit
## made so far (what the fight is fought with), and on the host the kits and the "ready" of all.
var ff := {}
var ff_times := ForgeFight.DEFAULT.duplicate()
var ff_open: Node = null         # the forge or the bench open now (closed by the clock)
var ff_open_side := "main"
var ff_timer: Timer = null
var ff_clock_layer: CanvasLayer = null
var ff_clock: Label = null

## The host picks the times first; only the host starts it, and not alone.
func ff_setup() -> void:
	if not Net.active() or not Net.is_host():
		show_screen("fights", "Only the host of a room starts Forge and Fight")
		return
	show_screen("ff_setup")

func _ff_setup(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("Forge and Fight", 34))
	v.add_child(UIStyle.label(_forge_fight_line(), 15, UIStyle.MUTED))
	# (With the armour bench down there is no time to set for the armour: none is made.)
	if not Armory.plate_bench_open:
		ff_times["armour"] = 0
	for row in [["weapons", "Time to forge the weapons", ForgeFight.WEAPON_MIN], ["armour", "Time to make the armour", ForgeFight.ARMOUR_MIN], ["fight", "Time limit on the fight", ForgeFight.FIGHT_MIN]]:
		if row[0] == "armour" and not Armory.plate_bench_open:
			continue
		v.add_child(UIStyle.label(Loc.t(String(row[1])).to_upper(), 13, UIStyle.BRONZE))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		for mins in row[2]:
			var txt: String = (Loc.t("%d min") % mins) if int(mins) > 0 else Loc.t("No armour" if row[0] == "armour" else "To the death")
			h.add_child(UIStyle.button(txt, func():
				ff_times[row[0]] = int(mins)
				show_screen("ff_setup"), int(ff_times[row[0]]) == int(mins)))
		v.add_child(h)
	if row_note_needed():
		v.add_child(UIStyle.label("Wait for at least one friend in the room: it is a fight between players.", 14, Color(1, 0.6, 0.5)))
	var go := UIStyle.button("To the forges!", func(): _ff_begin(ff_times.duplicate(), true), true)
	go.disabled = row_note_needed()
	_row(v, [go, UIStyle.button("Back", func(): show_screen("fights"))])

## What Forge and Fight is, in a line: with the armour bench down, only weapons are forged.
func _forge_fight_line() -> String:
	if Armory.plate_bench_open:
		return FIGHT_BLURBS["forgefight"]
	return "Everyone forges weapons against the clock, then all fight to the death with what they made."

func row_note_needed() -> bool:
	return Net.peers.is_empty()

## The forges are lit: everyone (the host sends it to the room) starts on his weapons.
func _ff_begin(times, as_host: bool) -> void:
	var t := ForgeFight.clean_times(times)
	ff = {"times": t, "phase": "", "end": 0.0, "kit": {"main": "", "off": "", "armor": []}, "ready": false, "kits": {}, "readies": {}}
	# Out of the yard (or whatever ran) to the forges, the pointer free.
	_end_match()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if as_host:
		Net.send_all("ff_begin", t)
		Net.set_lobby_info(Loc.t("Forge and Fight"))
	_ff_timer_on(true)
	_ff_phase("weapons")

func _ff_now() -> float:
	return Time.get_ticks_msec() / 1000.0

## A phase begins (on a guest, when the host says so): what is open closes and is kept as it
## stands, the clock starts again, the ready marks are cleared.
func _ff_phase(p: String) -> void:
	if ff.is_empty():
		return
	_ff_close_open()
	ff.phase = p
	ff.end = _ff_now() + ForgeFight.phase_seconds(p, ff.times)
	ff.ready = false
	ff.readies = {}
	if p == "fight":
		_ff_send_kit()
		if Net.is_host():
			# The last kits a moment to come in, then the sand.
			ff.phase = "closing"
			get_tree().create_timer(ForgeFight.GRACE).timeout.connect(_ff_fight)
	show_screen("ff_contest")

## The host moves the room on: when the clock runs out, or everyone says he is ready.
func _ff_tick() -> void:
	if ff.is_empty():
		_ff_timer_on(false)
		return
	if not Net.active():
		_ff_quit()
		return
	var left: float = maxf(0.0, float(ff.end) - _ff_now())
	if ff_clock:
		ff_clock.visible = ff.phase == "weapons" or ff.phase == "armour"
		ff_clock.text = (Loc.t("Weapons") if ff.phase == "weapons" else Loc.t("Armour")) + "  " + ForgeFight.clock(left)
		ff_clock.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if left <= 10.0 else UIStyle.GOLD_LIGHT)
	if not Net.is_host() or not (ff.phase == "weapons" or ff.phase == "armour"):
		return
	var all_ready: bool = bool(ff.ready) and Net.peers.keys().all(func(id): return bool(ff.readies.get(id, false)))
	if left <= 0.0 or all_ready:
		var nxt := ForgeFight.next_phase(String(ff.phase), ff.times)
		Net.send_all("ff_phase", nxt)
		_ff_phase(nxt)

func _ff_timer_on(on: bool) -> void:
	if on and ff_timer == null:
		ff_timer = Timer.new()
		ff_timer.wait_time = 0.25
		ff_timer.autostart = true
		ff_timer.timeout.connect(_ff_tick)
		add_child(ff_timer)
		# The clock over everything, the forge included.
		ff_clock_layer = CanvasLayer.new()
		ff_clock_layer.layer = 90
		add_child(ff_clock_layer)
		ff_clock = UIStyle.label("", 30, UIStyle.GOLD_LIGHT)
		ff_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		ff_clock.position.y = 8
		ff_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ff_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ff_clock_layer.add_child(ff_clock)
	elif not on and ff_timer != null:
		ff_timer.queue_free()
		ff_timer = null
		ff_clock_layer.queue_free()
		ff_clock_layer = null
		ff_clock = null

## Out of the contest (the room is gone): what is open shuts, nothing kept, the clock off.
func _ff_quit() -> void:
	if ff_open != null and is_instance_valid(ff_open):
		for c in ff_open.tree_exited.get_connections():
			ff_open.tree_exited.disconnect(c.callable)
		ff_open.queue_free()
		panel.visible = true
	ff_open = null
	ff = {}
	_ff_timer_on(false)

## The time is up with the forge open: what is on the anvil is taken as it stands, if it can be
## held; else the hand keeps what it had. A piece half made at the bench is lost.
func _ff_close_open() -> void:
	if ff_open == null or not is_instance_valid(ff_open):
		ff_open = null
		return
	var f := ff_open
	ff_open = null
	if f.has_method("_design_now"):
		var d: Dictionary = f._design_now()
		var st := ForgeLib.compute_stats(d)
		if st.get("hasGrip", false):
			d.stats = st
			ff.kit[ff_open_side] = d
			_ff_changed(false)
	for c in f.tree_exited.get_connections():
		f.tree_exited.disconnect(c.callable)
	f.queue_free()
	panel.visible = true

## The kit changed: the host is told (a guest's), and the screen shows it.
func _ff_changed(redraw := true) -> void:
	_ff_send_kit()
	if redraw and screen == "ff_contest" and ff_open == null:
		show_screen("ff_contest")

func _ff_send_kit() -> void:
	if ff.is_empty() or Net.is_host():
		return
	var k: Dictionary = ff.kit.duplicate(true)
	k.armor_defs = Armory.defs_of(k.armor)
	Net.send_host("ff_kit", k)

## The forge for one hand, free (the clock is the price): what it had, or a bare grip to start.
func _ff_forge(side: String) -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	var cur = ff.kit[side]
	var d: Dictionary = cur if cur is Dictionary else {"name": "My weapon" if side == "main" else "Off-hand weapon", "kind": "weapon", "sharpness": 0.8, "voxels": [[0, 0, 0, "wood", "grip"]]}
	ff_open = f
	ff_open_side = side
	f.open(d, 0, func(design, _cost):
		ff_open = null
		f.queue_free()
		if ff.is_empty():
			return
		if design != null:
			ff.kit[side] = design
			_ff_send_kit()
		show_screen("ff_contest"))
	f._show_mode("voxels")
	panel.visible = false
	f.tree_exited.connect(func(): panel.visible = true)

func _ff_name(w) -> String:
	if w is Dictionary:
		var st: Dictionary = w.get("stats", ForgeLib.compute_stats(w))
		return Loc.t("%s · %.1f kg · reach %.2f m") % [Loc.t(String(w.get("name", "Weapon"))), float(st.get("mass", 0.0)), float(st.get("reach", 0.0))]
	if w == "roundShield":
		return Loc.t("A round shield")
	return Loc.t("Nothing yet: bare fists")

func _ff_ready(on: bool) -> void:
	ff.ready = on
	if not Net.is_host():
		Net.send_host("ff_ready", on)
	show_screen("ff_contest")

## The contest's own screen: the clock, what is made so far, the way to the forge or the bench.
func _ff_contest(v: VBoxContainer) -> void:
	if ff.is_empty():
		v.add_child(UIStyle.label("Forge and Fight is over.", 16))
		v.add_child(UIStyle.button("Back", func(): show_screen("main")))
		return
	v.add_child(UIStyle.title("Forge and Fight", 34))
	match String(ff.phase):
		"weapons":
			v.add_child(UIStyle.label(Loc.t("Forge your weapons: %d min. When the time is up, everyone fights with what is on his anvil.") % int(ff.times.weapons), 15, UIStyle.MUTED))
			for side in ["main", "off"]:
				v.add_child(UIStyle.label(Loc.t("MAIN HAND") if side == "main" else Loc.t("OFF HAND"), 13, UIStyle.BRONZE))
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 10)
				var nm := UIStyle.label(_ff_name(ff.kit[side]), 16)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(nm)
				row.add_child(UIStyle.button("Keep forging" if ff.kit[side] is Dictionary else "Forge it", func(): _ff_forge(side), true))
				if side == "off":
					row.add_child(UIStyle.button("Round shield", func():
						ff.kit.off = "roundShield"
						_ff_changed()))
					row.add_child(UIStyle.button("Empty hand", func():
						ff.kit.off = ""
						_ff_changed()))
				v.add_child(row)
		"armour":
			v.add_child(UIStyle.label(Loc.t("Make your armour at the bench: %d min. A piece counts once it is made.") % int(ff.times.armour), 15, UIStyle.MUTED))
			var worn: Array = Armory.sanitize(ff.kit.armor)
			if worn.is_empty():
				v.add_child(UIStyle.label("No armour made yet.", 15))
			for id in worn:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 10)
				var nm := UIStyle.label(Loc.t("%s · %.1f kg") % [Loc.t(String(Data.armor[id].get("name", id))), Armory.kg(id)], 16)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(nm)
				row.add_child(UIStyle.button("Take off", func():
					ff.kit.armor = (ff.kit.armor as Array).filter(func(o): return o != id)
					_ff_changed()))
				v.add_child(row)
			if Armory.plate_bench_open:
				v.add_child(UIStyle.button("Make a piece at the bench", func():
					bench_mode = "contest"
					_plate_bench(Armory.design_piece(bench.region, bench.mat, bench.y0, bench.y1, bench.front, bench.cap, ""), _bench_worn_kg()), true))
		_:
			v.add_child(UIStyle.label("The forges go cold. To the sand!", 20, UIStyle.GOLD))
			return
	var waiting := 0
	if Net.is_host():
		waiting = Net.peers.keys().filter(func(id): return not bool(ff.readies.get(id, false))).size()
	_row(v, [UIStyle.button("Not ready yet" if ff.ready else "I'm ready", func(): _ff_ready(not ff.ready), not ff.ready)]
		+ ([UIStyle.label(Loc.t("%d still forging") % waiting, 14, UIStyle.MUTED)] if Net.is_host() and waiting > 0 else []))

## The fight (on the host): everyone with what he made, to the death, or to the time limit.
func _ff_fight() -> void:
	if ff.is_empty() or not Net.is_host():
		return
	var kits: Dictionary = ff.kits.duplicate(true)
	var mine: Dictionary = ff.kit.duplicate(true)
	var limit := float(ff.times.fight) * 60.0
	ff = {}
	_ff_timer_on(false)
	start({"mode": "forgefight", "role": "host", "rounds": int(_fight_opts_of("forgefight").get("rounds", 1)), "kits": kits, "fight_s": limit, "loadout_override": {"main": mine.main, "off": mine.off, "armor": mine.armor, "armor_defs": Armory.defs_of(mine.armor)}, "decrees": [], "hazards": []})

# ---------- Multiplayer ----------

## What the room about to be opened is for (kept in the settings): the friends' Arena (the first time) or the co-op campaign.
var mp_kind := ""

func _mp_kind() -> String:
	if mp_kind == "":
		var saved = Save.get_value("settings", {}).get("room_kind")
		mp_kind = Net.clean_kind(saved) if saved is String else Net.KIND_ARENA
	return mp_kind

func _set_mp_kind(k: String) -> void:
	mp_kind = Net.clean_kind(k)
	var st: Dictionary = Save.get_value("settings", {})
	st["room_kind"] = mp_kind
	Save.set_value("settings", st)

## A room is opened of the kind chosen on the screen (the guests are told it as they come in).
func _host_room(open: Callable) -> void:
	Net.room_kind = _mp_kind()
	open.call()

## One of the two kinds of room, as a card to pick.
func _kind_card(k: String) -> Button:
	var on := _mp_kind() == k
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size = Vector2(330, 86)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		_set_mp_kind(k)
		show_screen("mp"))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var head := UIStyle.label(("● " if on else "○ ") + Loc.t("ARENA WITH FRIENDS" if k == Net.KIND_ARENA else "CAMPAIGN TOGETHER"), 16, UIStyle.GOLD_LIGHT if on else UIStyle.TEXT)
	head.add_theme_font_override("font", UIStyle.serif(1, 700))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	b.tooltip_text = Loc.t("Fights, tournaments, teams and the endless arena. Everyone has a gladiator of his own here and money is no object; your campaign is never touched.") if k == Net.KIND_ARENA else Loc.t("The co-op campaign, bout after bout. The party's purse is the host's, so money is limited as in the campaign.")
	var blurb := UIStyle.label(Loc.t("Fights · teams · endless · money is no object") if k == Net.KIND_ARENA else Loc.t("Co-op · bout after bout"), 14, UIStyle.TEXT if on else UIStyle.MUTED)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(blurb)
	return b

func _mp(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("Multiplayer", 34))
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 12)
	kinds.add_child(_kind_card(Net.KIND_ARENA))
	kinds.add_child(_kind_card(Net.KIND_CAMPAIGN))
	v.add_child(kinds)
	v.add_child(UIStyle.label("OPEN A ROOM", 13, UIStyle.BRONZE))
	if Net.steam_available():
		_row(v, [UIStyle.button("Host a Steam lobby", func(): _host_room(func(): Net.host_steam(true)), true), UIStyle.button("Friends only", func(): _host_room(func(): Net.host_steam(false)))])
	else:
		var line := Loc.t("Steam is not running")
		if Net.steam_problem.begins_with("Steam is running"):
			line = Loc.t("Steam multiplayer is not in this build")
		v.add_child(UIStyle.label(line, 14, UIStyle.MUTED))
	v.add_child(UIStyle.button("Host by address", func():
		_host_room(func():
			var err := Net.host_enet()
			if err != OK:
				show_screen("mp", Loc.t("Could not open port %d") % Net.PORT))))
	v.add_child(UIStyle.label("JOIN A ROOM", 13, UIStyle.BRONZE))
	if Net.steam_available():
		v.add_child(UIStyle.button("Refresh rooms", func(): Net.list_steam_lobbies()))
		room_list = VBoxContainer.new()
		v.add_child(room_list)
		Net.list_steam_lobbies()
	var addr := LineEdit.new()
	addr.placeholder_text = "Host address, e.g. 192.168.1.20"
	addr.custom_minimum_size = Vector2(300, 0)
	addr.text_submitted.connect(func(_t): _join_address(addr.text))
	_row(v, [addr, UIStyle.button("Join", func(): _join_address(addr.text))])
	v.add_child(UIStyle.button("Back", func(): show_screen("main")))

func _join_address(text: String) -> void:
	var err := Net.join_enet(text.strip_edges() if text.strip_edges() != "" else "127.0.0.1")
	if err != OK:
		show_screen("mp", "Could not connect")

## Straight into a room from the command line, for testing with two windows on one machine:
## `--host` opens a room by address (`--arena` for the friends' Arena, else the co-op campaign's; `--yard` goes into the yard
## at once instead of waiting in the lobby), `--join 127.0.0.1` joins one, `--name Guest` names you,
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
		Net.room_kind = Net.KIND_ARENA if args.has("--arena") else Net.KIND_CAMPAIGN
		if Net.host_enet() != OK:   # `connected` takes the host to the lobby
			show_screen("mp", Loc.t("Could not open port %d") % Net.PORT)
		elif args.has("--yard"):
			enter_yard()
		return
	i = args.find("--join")
	if i >= 0:
		var addr := args[i + 1] if args.size() > i + 1 and not args[i + 1].begins_with("--") else "127.0.0.1"
		if Net.join_enet(addr) != OK:
			show_screen("mp", Loc.t("Could not connect to %s") % addr)

func _on_lobbies(list: Array) -> void:
	if room_list == null or not is_instance_valid(room_list):
		return
	for c in room_list.get_children():
		c.queue_free()
	if list.is_empty():
		room_list.add_child(UIStyle.label("No open rooms. Host one and invite your friends.", 14, UIStyle.MUTED))
	for l in list:
		var tag := Loc.t("Arena") if String(l.get("kind", "")) == Net.KIND_ARENA else Loc.t("Campaign")
		_row(room_list, [UIStyle.label("[%s]  %s · %d/8 · %s" % [tag, l.name, l.players, l.mode], 15), UIStyle.button("Join", func(): Net.join_steam(l.id))])

## The room's waiting room (LobbyScreen): who is in it, how friends come in, and what is done next. The host sees it first
## after opening a room and opens the gates (the yard) when everyone is here; a guest waits in it until he does. Over a running game
## (the pause menu's "The room") it is the room's list, with the host's Remove and everyone's Mute.
func _room(v: VBoxContainer) -> void:
	v.add_child(LobbyScreen.new({
		"overlay": over_match,
		"in_yard": in_yard(),
		"enter": func(): enter_yard(),
		"campaign": func(): start({"mode": "coop", "role": "host"}),
		"gate": func():
			_close_overlay()
			_open_station("gate"),
		"back": _close_overlay,
		"leave": _lobby_leave,
		"cap_text": campaign_full_text,
	}))

## Out of the room from its screen: over a running game that is the way out of the room, else back to the Multiplayer screen.
func _lobby_leave() -> void:
	if match_ != null and is_instance_valid(match_):
		_leave_room()
		return
	Net.leave()
	_box_off()
	in_room = false
	show_screen("mp")

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

## The credits and the licences of what the game is made with (scripts/game/credits.gd): a tab for each part, the text of the open one
## in a read-only box that scrolls (Godot's own components are a hundred kilobytes) and can be selected and copied.
var credits_section := "game"
func _credits(v: VBoxContainer) -> void:
	v.add_child(UIStyle.title("Credits & licences", 34))
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for sd in Credits.SECTIONS:
		var key: String = sd[0]
		var tb := UIStyle.button(sd[1], func():
			credits_section = key
			show_screen("credits"))
		tb.toggle_mode = true
		tb.button_pressed = credits_section == key
		tabs.add_child(tb)
	v.add_child(tabs)
	var box := TextEdit.new()
	box.text = Credits.text_of(credits_section)
	box.editable = false
	box.context_menu_enabled = false
	box.virtual_keyboard_enabled = false
	box.caret_blink = false
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.custom_minimum_size = Vector2(0, 380)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # (licence texts are read as they are written)
	box.add_theme_font_override("font", UIStyle.body())
	box.add_theme_font_size_override("font_size", 15)
	for c in ["font_color", "font_readonly_color"]:
		box.add_theme_color_override(c, UIStyle.TEXT)
	box.add_theme_color_override("background_color", Color(0, 0, 0, 0.28))
	v.add_child(box)
	v.add_child(UIStyle.button("Back", func(): show_screen("main")))

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
	# The language: the system's, or one picked (each named in its own tongue, never translated).
	var lsel := OptionButton.new()
	lsel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lsel.add_item(tr("Automatic") + " (%s)" % Loc.name_of(Loc.resolve("auto")))
	for l in Loc.LANGS:
		lsel.add_item(String(l[1]))
	var cur := str(st.get("language", "auto"))
	var at := 0
	for i in Loc.LANGS.size():
		if Loc.LANGS[i][0] == cur:
			at = i + 1
	lsel.select(at)
	lsel.item_selected.connect(func(i):
		var c: String = "auto" if i == 0 else String(Loc.LANGS[i - 1][0])
		_set_opt("language", c)
		Loc.apply(c)
		show_screen("options"))
	_opt_row(v, "Language", lsel)
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

var _chars_opt: OptionButton = null   # the Characters choice (the look Low graphics fall back to shows in it)
func _options_graphics(v: VBoxContainer, st: Dictionary) -> void:
	var q := OptionButton.new()
	var levels := ["low", "medium", "high", "ultra"]
	for l in levels:
		q.add_item(l.capitalize())
	q.select(maxi(0, levels.find(str(st.get("quality", "high")))))
	q.item_selected.connect(func(i):
		_set_opt("quality", levels[i])
		# (Low draws the characters in the classic blocks unless a look was picked below.)
		Physique.restyle_all(get_tree().root)
		if _chars_opt != null and is_instance_valid(_chars_opt):
			_chars_opt.select(1 if Physique.current() == "strong" else 0))
	_opt_row(v, "Graphics", q, "Low: no shadows or effects lighting. Ultra: global illumination and fog.")
	var aa := OptionButton.new()
	for a in AA_MODES:
		aa.add_item(a[1])
	aa.select(maxi(0, AA_MODES.map(func(a): return a[0]).find(str(st.get("aa", "msaa4")))))
	aa.item_selected.connect(func(i):
		_set_opt("aa", AA_MODES[i][0])
		apply_picture(Save.get_value("settings", {})))
	_opt_row(v, "Anti-aliasing", aa, "MSAA smooths the edges of the blocks and keeps everything else sharp (4x is the best balance; 8x for strong cards). FXAA is the lightest but blurs the picture.")
	var gl := OptionButton.new()
	gl.add_item("Detailed (new)")
	gl.add_item("Classic")
	gl.select(1 if Physique.current() == "strong" else 0)
	_chars_opt = gl
	gl.item_selected.connect(func(i):
		_set_opt("physique", "strong" if i == 1 else "human")
		Physique.restyle_all(get_tree().root))
	_opt_row(v, "Characters", gl, "Detailed: gladiators, giants and beasts in voxels half the size, with muscles, hands and feet; wounds open on skin, fat, flesh and bone. Classic: the blocks as they were. Only the look: every blow lands the same.")
	var vao := _check("Voxel shading: corners and creases between blocks in soft shadow", bool(st.get("voxelAO", true)), func(on):
		_set_opt("voxelAO", on)
		apply_picture(Save.get_value("settings", {})))
	v.add_child(vao)
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
	_opt_row(v, "Display", dm, "F11 toggles full screen. F3 shows the frame rate.")
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

## What a room between windows of this one computer draws (Net.local_room): they share one graphics card.
const LOCAL_ROOM_SCALE := 0.7
const LOCAL_ROOM_FPS := 60

static func room_scale(k: float, local: bool) -> float:
	return minf(k, LOCAL_ROOM_SCALE) if local else k

static func room_fps(cap: int, local: bool) -> int:
	return LOCAL_ROOM_FPS if local and (cap == 0 or cap > LOCAL_ROOM_FPS) else cap

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
	k = room_scale(k, Net.local_room)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if k >= 0.999 else Viewport.SCALING_3D_MODE_FSR
	root.scaling_3d_scale = k

## The display mode in the settings (older saves had a fullscreen flag; a new one starts full screen).
static func display_mode(st: Dictionary) -> String:
	if st.has("display"):
		return str(st.display)
	if st.has("fullscreen"):
		return "fullscreen" if st.fullscreen else "windowed"
	return "fullscreen"

## `-- --keep-window`: the window stays as the engine's own flags made it (`--position 40,60 --resolution 1100x650`; the
## engine takes those for itself and does not show them to scripts) instead of the saved display mode, which is full
## screen unless the player chose otherwise. The multiplayer test's windows carry it: without it both opened full screen
## at 1440p on one graphics card, and the one behind drew 17 frames a second (9 ms of graphics card to a frame each), so
## the host's window, and with it the guest's whole game, answered late.
const KEEP_WINDOW := "--keep-window"

static func window_asked(user_args: Array) -> bool:
	return user_args.has(KEEP_WINDOW)

## `startup`: the game is opening (a window the command line asked to keep is left as it is).
static func apply_display(st: Dictionary, startup := false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Smaller than this nothing on the screen can be read.
	DisplayServer.window_set_min_size(Vector2i(960, 540))
	apply_render_scale.call_deferred(st)
	if startup and window_asked(OS.get_cmdline_user_args()):
		return
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
	Engine.max_fps = room_fps(clampi(int(st.get("fpsCap", 0)), 0, 500), Net.local_room)

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
	StationKit.note_input(e)
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		var on := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		set_fullscreen(on)
		get_viewport().set_input_as_handled()
		return
	# The dressing screen: Esc leaves it; a drag begun anywhere off its panel turns the champion
	# round, to be seen from every side (user).
	if screen == "gladiator" and visible and match_ == null:
		if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			show_screen("main")
			get_viewport().set_input_as_handled()
			return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drag_turn = e.pressed and not panel.get_global_rect().has_point(e.position)
		elif e is InputEventMouseMotion and _drag_turn and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_turn_hero(e.relative.x * 0.012)
	_input_more(e)

func _set_opt(k: String, val) -> void:
	var st: Dictionary = Save.get_value("settings", {})
	st[k] = val
	Save.set_value("settings", st)

# ---------- Matches ----------

var last_start := {}   # what the match running now was started with (R plays it again)
var series_note := {}  # (a guest's) what the host said of the round that just ended in a match of several rounds: {next}
var series_look_ms := 3200    # how long the end of a round is looked at in a match of several rounds, then the score is shown this long
var series_score_ms := 3600

func start(opts: Dictionary) -> void:
	# The friends' room has no campaign: whatever asks for one (a stale button, a message) is refused, never run on the
	# campaign's own save.
	if Save.boxed and (opts.get("mode") == "coop" or opts.get("mode") == "campaign"):
		return
	# Co-op is the campaign for a party: the same ladder of bouts, foes for every friend, its
	# own progress (it does not move your solo campaign on).
	if opts.get("mode") == "coop":
		opts.mode = "campaign"
		opts.coop = true
		opts.stage = int(Save.get_value("coop_stage", 1))
	# A bout of the campaign is the fight chosen at the gate (GateChoice), else the gate's own (on a
	# boss's day the boss the run drew).
	if opts.get("mode") == "campaign" and not opts.has("bout"):
		opts.bout = int(GateChoice.at(int(opts.get("stage", 1)), bool(opts.get("coop", false)))[0].bout)
	# Four at most in the co-op campaign: with more in the room it does not begin (its buttons are
	# held back; this is for a friend who came in after the screen was drawn), and the screen is
	# drawn again with the reason.
	if opts.get("coop", false) and Net.campaign_full():
		if screen == "gate_cards" and in_yard():
			_gate_open()   # (the gate's cards again, the reason under them)
		else:
			show_screen(screen if ["gate", "room", "fights"].has(screen) else "room")
		return
	# Hosting a room, every fight (and the yard) takes the whole room along, not only the
	# campaign: the guests are sent the start and join as themselves.
	if not opts.has("role") and Net.active() and Net.is_host() and not ["training", "circus"].has(String(opts.get("mode", ""))) and not opts.get("tutorial", false):
		opts.role = "host"   # (alone in the room too: whoever joins is brought into what runs)
	# The time of day it is fought under (only the look; the guests are told it).
	if not opts.has("sky"):
		opts.sky = Arena.pick_sky(String(opts.get("mode", "")))
	# The rounds of the fight (its own count, or the host's), and a match of several rounds begun: each round after the
	# first comes through here again with the match's score carried in `series` (_series_after).
	if String(opts.get("mode", "")) != "tourney":
		tourney = null   # (any other fight ends the tournament)
	if opts.has("bots") or opts.has("decrees_n"):
		var cleaned := FightOpts.clean(String(opts.get("mode", "")), {"bots": opts.get("bots"), "decrees": opts.get("decrees_n")})
		opts.erase("bots")
		opts.erase("decrees_n")
		if cleaned.has("bots"):
			opts.bots = cleaned.bots
		if cleaned.has("decrees"):
			opts.decrees_n = cleaned.decrees
	var round_kind := Series.kind(String(opts.get("mode", "")))
	if round_kind != "":
		opts.rounds = Series.clean_rounds(String(opts.mode), opts.get("rounds"))
		if round_kind == "series" and int(opts.rounds) > 1:
			if not (opts.get("series") is Dictionary):
				opts.series = Series.new(int(opts.rounds)).to_dict()
		else:
			opts.erase("series")
	last_start = opts.duplicate(true)
	_end_match()
	# In a friends' room the fights are fought with the arms and armour of its yard (not the endless arena's kit for all, the forges'
	# own making, nor the campaign, the yard, the training ground).
	var arena_gear: bool = Save.boxed and not ["campaign", "yard", "endless", "forgefight", "training", "circus"].has(String(opts.get("mode", ""))) and not opts.get("tutorial", false)
	var a := arms()
	var lo := Arms.loadout(a)
	var checkpoint_bout := false
	opts.name = Save.get_value("name", "Gladiator")
	if opts.mode == "campaign":
		opts.loadout = {"main": lo.main, "off": lo.off}
		opts.worn = lo.worn
		if int(opts.get("stage", 1)) <= 1:
			set_body(Body.empty())
		opts.body = body()
		# Through the gate into a checkpoint's bout: a death brings him back as he went in (and his
		# guests are told to keep themselves as they go in).
		checkpoint_bout = CampaignRun.walks_in(int(opts.get("stage", 1)), bool(opts.get("coop", false)))
		CampaignRun.walk_in(int(opts.get("stage", 1)), bool(opts.get("coop", false)))
	else:
		opts.loadout = opts.get("loadout_override", {"main": "gladius", "off": "roundShield"})
		if arena_gear:
			# The friends' room: each fights with the arms and armour he took in its yard (money was no object there).
			var alo := Arms.loadout(arms())
			opts.loadout = {"main": alo.main if alo.main else "", "off": alo.off if alo.off else ""}
	if opts.get("autopilot", false) or cmd_bot:
		opts.autopilot = true
	var lk := look()
	opts.loadout = opts.loadout.duplicate()
	opts.loadout.armor = opts.loadout.get("armor", []) + look_armor(lk)
	var geared: bool = opts.mode == "campaign" or opts.mode == "yard" or arena_gear
	if geared:
		opts.loadout.armor += worn_armor()
		opts.loadout["armor_defs"] = Armory.defs_of(worn_armor())
		opts.loadout["armor_wear"] = armor_wear()
		# What the trainer taught him, on top of what the mode gives.
		var tm := Training.mods_of(training_stats())
		var om: Dictionary = opts.get("mods", {}).duplicate()
		for k in tm:
			om[k] = float(om.get(k, 1.0)) * float(tm[k])
		opts.mods = om
	opts.skin = Fighter.SKINS[lk.skin]
	opts.build = FineBody.BUILDS[lk.build]
	opts.color = CLOTH[lk.cloth]
	opts.inventory = opts.get("inventory_override", kit())
	# The decrees are drawn here, so the guests can be told them before anyone is spawned.
	var decree_n := Modes.decree_count(String(opts.mode), opts)
	if decree_n > 0 and not opts.has("decrees"):
		var setting: String = Save.get_value("settings", {}).get("decrees", "sometimes")
		var rng2 := RandomNumberGenerator.new()
		rng2.randomize()
		var picked: Array = [] if (setting == "off" and opts.mode != "ffa") else Decrees.roll(1.0 if opts.mode == "ffa" or setting == "always" else 0.6, decree_n, rng2)
		opts.decrees = picked.map(func(d): return d.id)
		opts.hazards = Hazards.random_specs(Decrees.combine(picked).hazards, rng2)
	if opts.get("role", "local") == "host":
		var peers := []
		for id in Net.peers:
			var spec := _peer_spec(int(id), geared, int(opts.get("stage", 1)) > 1)
			if opts.mode == "forgefight":
				# What he forged and made (sent as he made it, made safe on arrival), and his look.
				var kit: Dictionary = (opts.get("kits", {}) as Dictionary).get(int(id), {"main": ""})
				var made: Dictionary = kit.duplicate(true)
				made.armor = (spec.loadout.get("armor", []) as Array) + (kit.get("armor", []) as Array)
				spec.loadout = made
			elif opts.mode == "endless":
				# The waves are met with the host's kit, the same for everyone (his choice for the room), each in his own look.
				var made2: Dictionary = (opts.get("loadout_override", {}) as Dictionary).duplicate(true)
				made2.armor = (made2.get("armor", []) as Array) + (spec.loadout.get("armor", []) as Array)
				spec.loadout = made2
				spec.kit = (opts.get("inventory_override", {}) as Dictionary).duplicate()
			peers.append(spec)
		opts.peers = peers
		Net.send_all("start", {"mode": opts.mode, "stage": opts.get("stage", 1), "coop": opts.get("coop", false), "rounds": int(opts.get("rounds", 0)), "series": opts.get("series", {}), "decrees": opts.get("decrees", []), "hazards": opts.get("hazards", []), "circus": {"day": opts.get("circus", {}).get("day", 0), "bout_index": opts.get("circus", {}).get("bout_index", 0)}, "fight_s": float(opts.get("fight_s", 0.0)), "sky": String(opts.get("sky", "noon")), "keep": checkpoint_bout, "run": int(Save.get_value("run_seed", 0))})
		if Net.room_kind == Net.KIND_ARENA:
			Net.set_lobby_info(Loc.t("Arena") + (" · " + Modes.title_of(String(opts.mode)) if opts.mode != "yard" else ""))
		else:
			Net.set_lobby_info(Loc.t("Campaign · stage %d") % opts.get("stage", 1))
	# The crowd's favourite of the party's last bout wears the laurel, in the yard and through the
	# next bout (PartyGlory; the host's save).
	if opts.get("role", "local") == "host" and (opts.mode == "yard" or bool(opts.get("coop", false))):
		opts.crowned = String(Save.get_value("coop_favourite", ""))
	match_ = Match.new()
	world_root.add_child(match_)
	match_.setup(opts)
	_apply_input_settings()
	match_.finished.connect(_on_finished)
	match_.lost.connect(_campaign_lost)
	if match_.modes and match_.modes.endless:
		match_.modes.endless.offered.connect(_endless_offer)
		match_.modes.endless.picked_all.connect(_endless_done)
	match_.doctor.connect(func(e, b, news): _doctor_visit(b, news, match_.stage, func(nb): match_.doctor_done(e.id, nb)))
	hud = Hud.new(match_)
	world_root.add_child(hud)
	if forge_trying != null:
		_try_line()
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Sfx.music:
		var mood := fight_mood(match_)
		Sfx.music.set_state(mood)
		# The guests hear the bout the host hears (they learn of its foes only as they come).
		if Net.active() and Net.is_host():
			Net.send_all("music", mood)

## The music a bout calls for: a boss's, a beast hunt's, or a fight's.
static func fight_mood(m: Match) -> String:
	var foes := m.enemies()
	if foes.any(func(e): return e.get("boss", false)):
		return "boss"
	if not foes.is_empty() and foes.all(func(e): return e.kind == "beast"):
		return "beast"
	return "fight"

func _backdrop_on() -> void:
	if backdrop or backdrop_off or match_ or not visible or DisplayServer.get_name() == "headless" or not world_root.is_inside_tree():
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
	var yaw := atan2(cam_at.x - HERO_POS.x, cam_at.z - HERO_POS.z) - 0.2 + (hero_turn if screen == "gladiator" else 0.0)
	backdrop.add_hero(HERO_POS, yaw, {"main": "gladius", "off": "scutum", "armor": armor}, Color.hex(CLOTH[lk.cloth] << 8 | 0xff), Fighter.SKINS[lk.skin], screen == "gladiator", FineBody.BUILDS[lk.build])

## The title shot, or a close look at the champion while he is being dressed.
func _frame_hero() -> void:
	backdrop.hero_cam = _hero_cam()

func _hero_cam() -> Dictionary:
	if screen == "gladiator":
		return {"pos": HERO_POS + Vector3(1.9, 1.35, -2.6), "look": HERO_POS + Vector3(0.55, 1.05, 0)}
	return {"pos": Vector3(0.0, 1.05, -13.3), "look": Vector3(-0.35, 1.5, -3.0)}

func _gladiator(v: VBoxContainer) -> void:
	panel.custom_minimum_size.x = 640
	v.add_child(UIStyle.title("Your gladiator", 34))
	v.add_child(UIStyle.label("How the crowd will know you. The champion on the right wears it as you choose.", 14, UIStyle.MUTED))
	# Everything to choose in a scroll as tall as the window leaves room for, the buttons under it
	# always in sight (taller than the window, the last choices and the way out were off the
	# bottom of the screen, and the screen could not be left: user).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	var name_edit := LineEdit.new()
	name_edit.text = Save.get_value("name", "Gladiator")
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(300, 0)
	name_edit.text_changed.connect(func(tx):
		Save.set_value("name", tx)
		Net.my_name = tx)
	_row(body, [UIStyle.label("Name", 15, UIStyle.MUTED), name_edit])
	var lk := look()
	body.add_child(UIStyle.label("Skin", 15, UIStyle.MUTED))
	_swatches(body, Fighter.SKINS, lk.skin, func(i): _set_look("skin", i), 38)
	body.add_child(UIStyle.label("Loincloth and cape", 15, UIStyle.MUTED))
	_swatches(body, CLOTH, lk.cloth, func(i): _set_look("cloth", i), 38)
	# The rest two to a row (one under another they made the screen taller than the window).
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for k in ["hair", "hair_colour", "beard", "hat", "eyes", "eye_colour", "mouth", "nose", "face", "scar", "cape"]:
		var ob := OptionButton.new()
		for id in LOOK_SLOTS[k]:
			var first := "Plain" if k == "eyes" or k == "mouth" or k == "face" else ("Natural" if k.ends_with("_colour") else ("Broad nose" if k == "nose" else "None"))
			var item_nm := Loc.t(first) if id == "" else Loc.t(String(Physique.FACES.get(id, Data.armor.get(id, {}).get("name", id))))
			var lock_note: Array = LOOK_LOCKS.get(id, LOOK_LOCKS.hat_unbroken)
			ob.add_item(Loc.t(String(lock_note[0])) % item_nm if look_locked(id) else item_nm)
			if look_locked(id):
				ob.set_item_disabled(ob.item_count - 1, true)
				ob.set_item_tooltip(ob.item_count - 1, String(lock_note[1]))
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ob.select(lk[k])
		ob.custom_minimum_size = Vector2(176, 0)
		ob.item_selected.connect(func(i): _set_look(k, i))
		var kl := UIStyle.label(Loc.t(String(SLOT_NAMES.get(k, k.capitalize()))), 15, UIStyle.MUTED)
		kl.custom_minimum_size = Vector2(84, 0)
		grid.add_child(kl)
		grid.add_child(ob)
	# Turned round to be seen from every side: the buttons, or a drag anywhere off this panel.
	_row(v, [UIStyle.button("◀  Turn", func(): _turn_hero(-PI / 4.0)), UIStyle.button("Turn  ▶", func(): _turn_hero(PI / 4.0)), UIStyle.label("or drag him round", 13, UIStyle.MUTED)])
	_row(v, [UIStyle.button("Random", func():
		var r := {"v": LOOK_V}
		r.skin = randi() % Fighter.SKINS.size()
		r.cloth = randi() % CLOTH.size()
		r.build = 0
		for k in LOOK_SLOTS:
			r[k] = randi() % LOOK_SLOTS[k].size()
			if look_locked(LOOK_SLOTS[k][r[k]]):
				r[k] = 0
		Save.set_value("look", r)
		_net_loadout()
		show_screen("gladiator")), UIStyle.button("Done  (Esc)", func(): show_screen("main"), true)])
	# (As tall as all of it, no taller than the window leaves: the column's margins, the panel's,
	# the title and its line, the two rows of buttons and the gaps between them.)
	var room := get_viewport_rect().size.y - 80.0 - 52.0 - 64.0 - 2.0 * 46.0 - 5.0 * 12.0
	scroll.custom_minimum_size.y = clampf(body.get_combined_minimum_size().y + 4.0, 120.0, maxf(120.0, room))
	_fit_scroll.call_deferred(scroll, body, room)
	_dress_hero.call_deferred()

## A scroll made as tall as what is in it once that is laid out (its rows' heights are known then:
## the swatches wrap only once they have a width), no taller than `room`.
func _fit_scroll(scroll: ScrollContainer, body: Control, room: float) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(body):
		scroll.custom_minimum_size.y = clampf(body.size.y + 4.0, 120.0, maxf(120.0, room))

## The champion on the dressing screen turned round where he stands, by `a` (radians).
var hero_turn := 0.0
var _drag_turn := false
func _turn_hero(a: float) -> void:
	hero_turn = wrapf(hero_turn + a, -PI, PI)
	if backdrop and backdrop.hero and is_instance_valid(backdrop.hero):
		backdrop.turn_hero(a)

func _swatches(v: VBoxContainer, colors: Array, sel: int, cb: Callable, size := 44) -> void:
	var h := HFlowContainer.new()   # (wraps when there are more than fit the panel)
	h.add_theme_constant_override("h_separation", 8)
	h.add_theme_constant_override("v_separation", 8)
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(size, size)
		var st := StyleBoxFlat.new()
		st.bg_color = Color.hex(int(colors[i]) << 8 | 0xff)
		st.set_corner_radius_all(size / 2)
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
	_gate_shut()
	_backdrop_off()
	if endless_layer:
		_endless_close()
	# No fight, nothing held still: a fight left in the middle of its replay (which pauses the
	# game until its end) left the next screen and the next fight frozen.
	get_tree().paused = false
	if match_:
		match_.queue_free()
		match_ = null
	if hud:
		hud.queue_free()
		hud = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## A death ends the campaign: the next one begins at the first bout, with a beginner's purse,
## stick and body (online and alone alike; the host's word is the party's). Done the moment
## the bout is lost (Match.lost), so a player who leaves the fight, or the game, during the kill
## cam cannot come back to the bout he fell in; and again, harmlessly, when the result is read.
var fell_back := 0   # the bout a Legionary went back to on his last death (0: the run ended)

## What a player dead on the sand in a bout his party won is told in the yard (Match._note_fall).
const CARRIED_OFF := "You were carried off the sand: the physician will see to your wounds."

## A guest of the co-op campaign, the party fallen after the checkpoint (the host's word: bout `at`
## of his run `run`): his own put back as he walked into the checkpoint's bout
## (CampaignRun.keep_own), the bout he lost and all it did to him gone, and the host told
## (Net.push_me). Nothing kept there (he came after it): he stays as he is.
func _guest_fell_back(at: int, run: int) -> void:
	if not CampaignRun.fall_back_own(at, run):
		return
	fell_back = clampi(at, 1, 999)
	Net.my_body = body()
	Net.my_kit = kit()
	_net_loadout()

func _campaign_lost(r: Dictionary) -> void:
	# Legionary: back to the last checkpoint as he left it; Ironman (or none yet): it is over.
	var back := CampaignRun.fall_back(bool(r.get("coop", false)))
	fell_back = back
	if back > 0:
		Net.my_body = body()   # (the checkpoint's, put back in the save: what a room is told)
		_net_loadout()
		if Net.active():
			Net.send_all("purse", coins())
			if Net.is_host() and not r.get("told", false):
				# The party goes back with me: each guest puts himself back as he walked into the
				# checkpoint's bout (called again as the result is read: told once).
				r["told"] = true
				Net.send_all("fell_back", {"stage": back, "run": int(Save.get_value("run_seed", 0))})
		return
	var sk := "coop_stage" if r.get("coop", false) else "stage"
	var ck := "coop_checkpoint" if r.get("coop", false) else "checkpoint"
	Save.set_value(sk, 1)
	Save.set_value("coop_lap" if r.get("coop", false) else "lap", 1)
	Save.set_value("run_seed", randi())   # a new run: other oddities at the smith
	GateChoice.clear(bool(r.get("coop", false)))
	Save.set_value("oddities_sold", {})
	Save.set_value(ck, 1)
	Save.set_value("coins", START_COINS)
	set_body(Body.empty())
	set_arms(Arms.empty())
	set_kit({})   # the pots in his bag went with him (user)
	set_worn_armor([])
	set_armor_wear({})
	set_training_stats({})
	if Net.active():
		Net.send_all("purse", coins())

## A round of a match of several rounds is over. The host (or the one playing alone) counts it, tells the guests, shows how
## the match stands and brings the next round, or declares the match's end; a guest waits for the host's word and for the
## round he is sent. True when the match goes on or the screen has changed (the caller is to stop), false when the match is
## over and the flow after any bout takes him on.
func _series_after(r: Dictionary, was: Match) -> bool:
	if was.role == "guest":
		var t0 := Time.get_ticks_msec()
		while series_note.is_empty() and match_ == was and Time.get_ticks_msec() - t0 < 6000:
			await get_tree().process_frame
		if match_ != was:
			return true
		if series_note.is_empty():
			return false   # (the host said nothing: out of the match as after any bout)
		var next: bool = bool(series_note.get("next", false))
		series_note = {}
		var t1 := Time.get_ticks_msec()
		while match_ == was and Time.get_ticks_msec() - t1 < (20000 if next else series_score_ms):
			await get_tree().process_frame
		return match_ != was
	var winner := String(r.get("round_key", ""))
	if not was.series.is_empty():
		var s := Series.from_dict(last_start.get("series"))
		s.record(String(r.get("round_key", "")), String(r.get("round_name", "")))
		last_start.series = s.to_dict()
		was.set_series(last_start.series)
		var done := s.decided()
		var text := s.final_text() if done else s.score_line()
		var sub := s.score_line() if done else (Loc.t("Round %d of %d next") % [s.round_now(), s.rounds] if s.played < s.rounds else Loc.t("A deciding round next"))
		was._banner(text, sub)
		if Net.active() and Net.is_host():
			Net.send_all("series", {"s": s.to_dict(), "next": not done or tourney != null, "t": text, "sub": sub})
		var t2 := Time.get_ticks_msec()
		while match_ == was and Time.get_ticks_msec() - t2 < series_score_ms:
			await get_tree().process_frame
		if match_ != was:
			return true   # (restarted, or left, in the meantime)
		if not done:
			var again: Dictionary = last_start.duplicate(true)
			again.erase("sky")   # (another hour of the day for the next round)
			start(again)
			return true
		winner = s.winner()
		if tourney == null:
			return false
	if was.mode == "tourney" and tourney != null:
		return await _tourney_after(winner, was)
	return false

# ---------- The tournament ----------
# One on one, single elimination (Tourney): the room's players, and the bots that fill the bracket, drawn into pairs; each pair
# fights a bout in the arena, the rest of the room look on; the winner goes on, until one is crowned. Bouts of two bots are
# settled unseen. The host (or the one alone) plays it out, bout by bout, and tells the guests how it stands.

var tourney: Tourney = null
var tourney_opts := {}

func _tourney_begin(opts: Dictionary) -> void:
	var list := [{"key": Series.human_key(1), "name": String(Save.get_value("name", "Gladiator")), "peer": 1, "bot": false}]
	if Net.active():
		for id in Net.peers:
			list.append({"key": Series.human_key(int(id)), "name": String(Net.peers[id].name), "peer": int(id), "bot": false})
	var total := Tourney.entrant_count(list.size(), int(opts.get("bots", FightOpts.FILL)))
	var names: Array = Data.modes.get("botNames", ["Crixus"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var used := {}
	for e in list:
		used[String(e.name)] = true
	var at := rng.randi() % maxi(1, names.size())
	while list.size() < total:
		var nm := String(names[at % names.size()])
		at += 1
		if used.has(nm):
			nm = "%s %d" % [nm, list.size()]
		used[nm] = true
		list.append({"key": Series.bot_key(nm), "name": nm, "peer": -1, "bot": true})
	tourney = Tourney.make(list, rng.randi(), int(opts.get("rounds", 1)))
	tourney_opts = opts.duplicate()
	if not _tourney_go():
		_tourney_over()

## The next bout that is to be seen is begun. False when the tournament is over (decided, or no player left in it).
func _tourney_go() -> bool:
	var mt := _tourney_plan()
	if mt.is_empty():
		return false
	start(_tourney_bout(mt))
	return true

## Forfeits and the bouts of bots settled, the rounds carried on: the next bout to be seen ({} when there is none).
func _tourney_plan() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for guard in 16:
		for e in tourney.entrants:
			if not bool(e.bot) and int(e.peer) != 1 and not Net.peers.has(int(e.peer)) and not bool(e.get("gone", false)):
				tourney.forfeit(String(e.key))   # (a player who left: the other goes on)
		tourney.settle_bots(rng)
		if tourney.finished() or tourney.humans_left() == 0:
			return {}
		var mt := tourney.open_match()
		if not mt.is_empty():
			return mt
		if not tourney.advance():
			return {}
	return {}

func _tourney_bout(mt: Dictionary) -> Dictionary:
	return {"mode": "tourney", "rounds": int(tourney_opts.get("rounds", 1)), "pair": [tourney.entrant(String(mt.a)), tourney.entrant(String(mt.b))],
		"tourney_line": "%s · %s" % [tourney.round_name(), tourney.match_text(mt)]}

## The bout is over (host, or alone): the winner goes on; how it stands is shown (and told); the next bout, or the end.
func _tourney_after(winner: String, was: Match) -> bool:
	var mt := tourney.open_match()
	if mt.is_empty():
		return false
	if winner != String(mt.a) and winner != String(mt.b):
		winner = String(mt.a) if randf() < 0.5 else String(mt.b)   # (a drawn bout: the coin decides)
	var out_of := tourney.name_of(String(mt.b) if winner == String(mt.a) else String(mt.a))
	tourney.report(mt, winner)
	var next := _tourney_plan()
	var text := Loc.t("%s goes on") % tourney.name_of(winner)
	var sub := Loc.t("%s is out") % out_of
	if tourney.finished():
		text = Loc.t("%s is the champion!") % tourney.name_of(tourney.champion())
		sub = Loc.t("The tournament is won")
	elif next.is_empty():
		text = Loc.t("The tournament is over")
		sub = Loc.t("No player is left in it")
	else:
		sub = "%s · %s · %s" % [sub, tourney.round_name(), tourney.match_text(next)]
	was._banner(text, sub)
	if Net.active() and Net.is_host():
		Net.send_all("series", {"s": {}, "next": not next.is_empty(), "t": text, "sub": sub})
	var t0 := Time.get_ticks_msec()
	while match_ == was and Time.get_ticks_msec() - t0 < series_score_ms + 800:
		await get_tree().process_frame
	if match_ != was:
		return true
	if next.is_empty():
		tourney = null
		return false
	start(_tourney_bout(next))
	return true

## No player is left in it (or it never began): back to where a fight ends.
func _tourney_over() -> void:
	tourney = null
	if Net.active() and Net.is_host():
		enter_yard()
	else:
		show_screen("fights")

func _on_finished(r: Dictionary) -> void:
	var was := match_
	# Five seconds on the banner over the arena, to take in how the bout ended (Space or Enter
	# goes on sooner, but not in the first moment, nor a mouse button still held from the fight).
	# A round of a match of several rounds: a shorter look, then the match's score (_series_after).
	var in_series: bool = was != null and (not was.series.is_empty() or was.mode == "tourney")
	var began := Time.get_ticks_msec()
	var wait_until := began + (series_look_ms if in_series else 5000)
	while Time.get_ticks_msec() < wait_until and match_ == was:
		await get_tree().process_frame
		if Time.get_ticks_msec() > began + 1500 and (Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)):
			break
	if match_ != was:
		return   # restarted (R) in the meantime
	if in_series and await _series_after(r, was):
		return
	if match_ != was:
		return
	var mode := match_.mode if match_ else "campaign"
	var to_lesson: bool = match_ != null and match_.tut != null and match_.tut.finished
	if to_lesson:
		Save.set_value("tutorial_done", true)
	var mission_text := _settle_missions(r, match_.mode if match_ else "")
	if mode == "circus" and match_ and match_.role != "guest":
		var inv: Dictionary = match_.me.get("inventory", {}) if match_.me else {}
		_end_match()
		_circus_finished(r, inv)
		return
	# (A kit lent for the bout, training's bag or the tutorial's pot, is not the one kept.)
	if match_ and match_.me and match_.role != "guest" and mode != "circus" and not last_start.has("inventory_override"):
		set_kit(match_.me.get("inventory", kit()))
	if mode == "campaign" and match_ and match_.role == "guest":
		if not r.get("won", false) and fell_back > 0:
			# Back at the checkpoint with the party, as I walked into its bout: the lost bout's
			# chips are not in my blade.
			last_result = {"text": Loc.t("You fell. Back to the last checkpoint: bout %d, as you left it.") % fell_back}
		else:
			# A guest's own sword takes its knocks too: the host does not keep it, he does.
			set_arms(Arms.add_wear(arms(), match_.my_wear()))
			if r.get("won", false) and r.get("fell", false):
				last_result = {"text": Loc.t(CARRIED_OFF)}
	if mode == "campaign" and match_ and match_.role != "guest":
		var sk := "coop_stage" if r.get("coop", false) else "stage"
		var ck := "coop_checkpoint" if r.get("coop", false) else "checkpoint"
		if r.get("body") is Dictionary:
			set_body(r.body)
		set_arms(Arms.add_wear(arms(), r.get("wear", {})))
		# A hand lost in the bout: the weapon into the hand he has left, or up on the smith's rack
		# (user). Told with the bout's result.
		var fitted := Arms.fit_hands(arms(), body())
		if not (fitted.moved as Array).is_empty():
			set_arms(fitted.arms)
		set_armor_wear(Armory.add_wear(armor_wear(), r.get("wear", {}).get("armor", {}), worn_armor()))
		# The party's run set down on its scroll, and the crowd's favourite of the bout (PartyGlory).
		if r.get("coop", false) and r.get("party") is Dictionary:
			Save.set_value("coop_scroll", PartyGlory.add_bout(_party_scroll(), r.party, String(r.get("favourite", ""))))
			Save.set_value("coop_favourite", String(r.get("favourite", "")))
		elif not r.get("coop", false):
			# Alone: the bout on his run's scroll (RunScroll), won or a fall.
			var mine := {}
			if r.get("party") is Dictionary:
				for row in (r.party as Dictionary).values():
					mine = row
			Save.set_value("run_scroll", RunScroll.add_bout(_run_scroll(), mine, bool(r.won)))
		if r.won:
			add_coins(int(r.pay))
			GateChoice.mark_won(int(r.get("bout", r.stage)), bool(r.get("coop", false)))
			if r.get("checkpoint") != null:
				Save.set_value(ck, int(r.checkpoint))
			Save.set_value(sk, int(r.stage) + 1)
			if r.get("checkpoint") != null:
				CampaignRun.keep(bool(r.get("coop", false)))
			if r.get("boss", false):
				Achievements.unlock("boss")
			if int(r.stage) >= 8:
				Achievements.unlock("eight_bouts")
			if int(r.stage) >= 32:
				Achievements.unlock("halfway")
			last_result = {"text": Loc.t("Stage %d cleared: %d denarii.") % [r.stage, r.pay]}
			if r.get("fell", false):
				last_result.text += " " + Loc.t(CARRIED_OFF)
			# A boss beaten: the trader brings one more ware (Market).
			var mk_coop := bool(r.get("coop", false))
			var mk_had := Market.saved(mk_coop)
			var mk_has := Market.opened(mk_coop, int(r.stage) + 1, int(Save.get_value("coop_lap" if mk_coop else "lap", 1)))
			if mk_has > mk_had:
				last_result.text += " " + Loc.t("The trader brings a new ware: %s.") % Loc.t(String(Data.shop.get("throwables", {}).get(Market.AFTER_BOSS[mk_has - 1], {}).get("name", "")))
			if int(r.stage) >= Data.campaign.get("stages", []).size():
				# The last bout won: the rudis. The campaign begins again, the same man and his
				# gear, the foes a third tougher each time round (lap).
				var lk := "coop_lap" if r.get("coop", false) else "lap"
				var kills := int(r.get("kills", {}).size()) if r.get("kills") is Dictionary else 0
				var party: bool = bool(r.get("coop", false)) and Net.active()
				if not party:
					Save.set_value("hall", Circus.hall_add(Save.get_value("hall", []), Save.get_value("name", "Gladiator"),
						{"day": 7, "won": true, "kills": kills, "bouts_won": int(r.stage), "campaign": true}, ""))
				Achievements.unlock("rudis")
				if CampaignRun.won(bool(r.get("coop", false))):
					Save.set_value("unbroken_news", true)
				if int(Save.get_value(lk, 1)) >= 2:
					Achievements.unlock("rudis_again")
				Save.set_value(lk, int(Save.get_value(lk, 1)) + 1)
				Save.set_value(sk, 1)
				Save.set_value(ck, 1)
				GateChoice.clear(bool(r.get("coop", false)))   # (every bout to win again)
				CampaignRun.keep(bool(r.get("coop", false)))   # (the next time round starts as he is now)
				if party:
					# A party: the Emperor has one rudis for it (PartyGlory), the scroll unrolled.
					_end_match()
					_rudis_open(kills, int(r.stage))
					return
				if Net.active():
					Net.send_all("campaign_end", {})
				rudis_end = {}
				if not bool(r.get("coop", false)):
					run_shown = _run_scroll()   # (his run's scroll, read out under the rudis)
					Save.set_value("run_scroll", {})
					# The scene in the arena first (EndingScene: the Emperor rises, the rudis in his
					# hand), then the rudis screen.
					if match_ and is_instance_valid(match_) and not match_.headless and not Net.active():
						var scene := EndingScene.play(match_, hud)
						await scene.done
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
			_campaign_lost(r)
			last_result = {"text": (Loc.t("You fell. Back to the last checkpoint: bout %d, as you left it.") % fell_back) if fell_back > 0 else "You fell. The campaign is over; a new one begins at bout 1."}
			if r.get("coop", false) and fell_back <= 0 and Net.active():
				_scroll_open("lost")   # (the run is over: its scroll unrolled for the party)
			elif not r.get("coop", false) and fell_back <= 0:
				# Alone, the run is over: his scroll unrolled, a new one begun.
				run_shown = _run_scroll()
				Save.set_value("run_scroll", {})
				scroll_shown = {}
				scroll_due = true
		if r.won and not (fitted.moved as Array).is_empty():
			last_result = {"text": (String(last_result.get("text", "")) + " " + ". ".join(fitted.moved) + ".").strip_edges()}
	_end_match()
	if to_lesson:
		# The tutorial is done: on to the forge, to learn it there (its own lesson).
		visible = true
		_workshop_forge(true)
		return
	if scroll_due:
		scroll_due = false
		show_screen("scroll")
		return
	if mode == "pvp" and bool(last_start.get("rudis", false)) and Net.active() and Net.is_host():
		_rudis_won(String(r.get("winner", "")))
		return
	if Net.active() and not Net.is_host():
		show_screen("room")
	else:
		# Between bouts of the campaign the gladiator goes back to the yard, the lobby: the
		# smith, the market, the physician, friends, and the gate to the next bout.
		if hub or mode == "campaign" or (Net.active() and Net.is_host()):
			enter_yard(((last_result.get("text", "") + " · ") if mode == "campaign" and last_result.get("text", "") != "" else "") + mission_text)
		else:
			show_screen("yard" if mode == "campaign" else ("endless" if mode == "endless" else "main"), mission_text)

## The fight's time limit from the host (s): a number within the longest on the list, else none.
static func _clean_fight_s(v) -> float:
	if (v is float or v is int) and is_finite(float(v)):
		return clampf(float(v), 0.0, float(ForgeFight.FIGHT_MIN.max()) * 60.0)
	return 0.0

func _on_net(type: String, data, _from: int) -> void:
	match type:
		"start":
			if not Net.is_host():
				if not ff.is_empty():
					ff = {}   # (the forges are cold: the fight is on)
					_ff_timer_on(false)
				_end_match()
				match_ = Match.new()
				world_root.add_child(match_)
				var ids: Array = (data.get("decrees", []) as Array).filter(func(i): return not Decrees.by_id(str(i)).is_empty()) if data.get("decrees") is Array else []
				var hz: Array = (data.get("hazards", []) as Array).filter(func(h): return h is Dictionary and ["spikes", "blade", "chariot"].has(h.get("type"))).slice(0, 8) if data.get("hazards") is Array else []
				if data.mode == "campaign" and int(data.stage) <= 1:
					set_body(Body.empty())
				fell_back = 0
				if data.mode == "campaign" and data.get("keep") == true:
					# Into the checkpoint's bout (the host's word): what a fall brings me back to.
					CampaignRun.keep_own(int(Net.num(data.get("stage"))), int(Net.num(data.get("run"))))
				series_note = {}
				match_.setup({"mode": data.mode, "stage": data.stage, "coop": bool(data.get("coop", false)), "role": "guest", "autopilot": cmd_bot, "rounds": Series.clean_rounds(String(data.mode), data.get("rounds")), "series": Series.clean(data.get("series")), "decrees": ids, "hazards": hz, "circus": data.get("circus", {}) if data.get("circus") is Dictionary else {}, "fight_s": _clean_fight_s(data.get("fight_s")), "sky": Arena.clean_sky(data.get("sky"))})
				_apply_input_settings()
				match_.finished.connect(_on_finished)
				match_.lost.connect(_campaign_lost)
				if data.mode == "yard":
					# A guest has the yard as the host has it: the stalls open for him too.
					hub = true
					match_.station.connect(_open_station)
					if Sfx.music:
						Sfx.music.set_state("yard")
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
			# The host's word on what the stage left on me (dead in a bout the party won: as I died).
			if data is Dictionary and not Net.is_host():
				set_body(data)
		"armor_wear":
			# The plates the bout knocked off my armour (the host saw them go).
			if data is Dictionary and not Net.is_host():
				set_armor_wear(Armory.add_wear(armor_wear(), data, worn_armor()))
		"endless_offer":
			# The rewards the host holds out to me after a wave (made safe: Endless.clean_offer); my pick goes back to him.
			if not Net.is_host() and match_ and match_.mode == "endless" and data is Dictionary:
				var rs := Endless.clean_offer(data.get("r"))
				if not rs.is_empty():
					_endless_offer(rs, clampi(int(Net.num(data.get("w"))), 0, 9999), clampf(Net.num(data.get("t"), Endless.PICK_TIME), 1.0, 60.0), true)
		"endless_done":
			if not Net.is_host():
				_endless_done()
		"endless_pick":
			# A guest's pick of his rewards (0, 1 or 2).
			if Net.is_host() and match_ and match_.modes and match_.modes.endless and (data is int or data is float) and is_finite(float(data)):
				match_.modes.endless.take_for(_from, int(data))
		"fell_back":
			# The party fell after the checkpoint and the host goes back to it: so do I.
			if not Net.is_host() and data is Dictionary:
				_guest_fell_back(int(Net.num(data.get("stage"))), int(Net.num(data.get("run"))))
		"ff_begin":
			if not Net.is_host() and data is Dictionary:
				_ff_begin(data, false)
		"ff_phase":
			if not Net.is_host() and not ff.is_empty() and (data == "armour" or data == "fight"):
				_ff_phase(String(data))
		"ff_kit":
			if Net.is_host() and not ff.is_empty() and ff.phase != "fight" and Net.peers.has(_from):
				ff.kits[_from] = ForgeFight.clean_kit(data)
		"ff_ready":
			if Net.is_host() and not ff.is_empty() and Net.peers.has(_from):
				ff.readies[_from] = data == true
		"doctor":
			if data is Dictionary and not Net.is_host():
				_doctor_visit(Body.sanitize(data.get("body", {})), (data.get("news", []) as Array).map(func(x): return str(x).left(80)) if data.get("news") is Array else [], int(data.get("stage", 1)), func(nb): Net.send_host("doctor_done", nb))
		"me":
			# A guest the physician or the smith saw to in the yard: the host's copy of him, the one
			# that moves, is built again with the body and the armour he has now (his arm was set on
			# his own screen and hung broken on everyone's until the next bout).
			if Net.is_host() and in_yard() and Net.peers.has(_from):
				match_.peer_body(_from, Net.peers[_from].get("body", {}), _peer_spec(_from, true).get("loadout", {}))
		"gate_pick":
			# A guest's pick of the gate's fights (a card's number, anything else none).
			if match_ and Net.is_host() and match_.yard:
				match_.yard.take_pick(_from, data)
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
		"series":
			# How a round of a match of several rounds went and where the match stands (the host's word, made safe): shown, and
			# the guest stays in his arena until the host brings the next round (or the match's end).
			if not Net.is_host() and match_ and data is Dictionary:
				var sd := Series.clean(data.get("s"))
				if not sd.is_empty():
					match_.set_series(sd)
				series_note = {"next": data.get("next") == true}
				match_.banner.emit(str(data.get("t", "")).left(60), str(data.get("sub", "")).left(140))
		"isnap", "zone", "spot", "feed", "wloose", "wspawn", "wpick", "lsnap", "fx", "guts", "gutp", "kc", "kcr", "yard_next", "gate_picks", "teams", "bone", "held", "fstat":
			if match_:
				match_.guest_message(type, data)
		"music":
			if not Net.is_host() and data is String and Music.MOODS.has(data) and Sfx.music:
				Sfx.music.set_state(data)
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
				# How the party's one rudis went (PartyGlory), as the host says: names as names.
				rudis_end = {}
				if data is Dictionary and (data.get("winner") is String):
					rudis_end = {"winner": Net.clean_name(data.winner)}
				elif data is Dictionary and (data.get("shared") is Array):
					rudis_end = {"shared": (data.shared as Array).slice(0, PartyGlory.MOST).map(func(x): return Net.clean_name(x))}
				_end_match()
				show_screen("campaign_end")
		"scroll":
			# The run is over: its scroll, as the host keeps it (made safe: PartyGlory.clean).
			if not Net.is_host() and data is Dictionary:
				scroll_shown = PartyGlory.clean(data.get("s"))
				scroll_why = "lost"
				_end_match()
				show_screen("scroll")
		"rudis_ask":
			if not Net.is_host() and data is Dictionary:
				scroll_shown = PartyGlory.clean(data.get("s"))
				scroll_why = "won"
				rudis_mine = ""
				rudis_end = {}
				rudis_count = [0, 1 + Net.peers.size()]
				_end_match()
				show_screen("rudis")
		"rudis_count":
			if not Net.is_host() and data is Dictionary:
				rudis_count = [clampi(int(Net.num(data.get("n"))), 0, 8), clampi(int(Net.num(data.get("of"))), 0, 8)]
				if screen == "rudis":
					show_screen("rudis")
		"rudis_vote":
			if Net.is_host() and data is String:
				rudis_take(_from, String(data))
		"purse_add":
			# What a guest spent comes off the purse; what he puts in, only as much as he may
			# (Net.purse_take: no more than he took out, and what his fights paid).
			if Net.is_host() and (data is int or data is float) and is_finite(float(data)):
				var n := clampi(int(data), -5000, 5000)
				if n < 0:
					var before := coins()
					add_coins(n)
					Net.purse_spent(_from, before - coins())
				else:
					add_coins(Net.purse_take(_from, n))
		"end":
			if match_:
				# (The pay went into the party's purse on the host's side.)
				match_.guest_end(data)

func _unhandled_input(e: InputEvent) -> void:
	# F12: a screenshot (with Steam running, Steam takes its own on the same key).
	if e is InputEventKey and e.pressed and not e.is_echo() and e.keycode == KEY_F12 and not Net.steam_ready:
		_screenshot()
		return
	# The kill cam keeps its own keys (E or Esc skip it): Esc here opened the pause menu over it,
	# and closing that unpaused the arena in the middle of the replay; R started the bout again
	# under it.
	if match_ and is_instance_valid(match_) and match_.killcam and match_.killcam.playing:
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
	# (The pad's B leaves a stall as Esc does.)
	if e is InputEventJoypadButton and e.pressed and e.is_action_pressed("ui_cancel") and (in_yard() or over_match) and visible and match_:
		_close_overlay()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and match_ and not visible:
		# Trying a weapon from the forge: Esc goes straight back to it, as the line at the top
		# says (it opened the pause menu, and the way back was a click more in there).
		if forge_trying != null and pause_layer == null:
			back_to_forge()
			return
		_toggle_pause()

# ---------- The party's glory: the run's scroll and one rudis (PartyGlory) ----------

const HONOUR_TEXT := {"kills": "Most kills: %s (%d)", "lifts": "Lifted the most friends: %s (%d)",
	"limbs": "Left the most limbs on the sand: %s (%d)", "fav": "The crowd's favourite most often: %s (%d bouts)"}
var scroll_shown := {}     # the scroll on the screen: the host's save's, or what the host sent
var scroll_why := ""       # "lost": the run is over; "won": the ladder is won (the rudis follows)
var scroll_due := false    # (the host's: the scroll, not the yard, once the bout is put away)
var rudis_votes := {}      # (the host's) who would do what: 1 for the host, a guest by his id
var rudis_count := [0, 0]  # how many have spoken, of how many (a guest's: as the host tells it)
var rudis_mine := ""       # what I would do
var rudis_kills := 0       # (the host's: the Hall of Fame's entry)
var rudis_stage := 0
var rudis_end := {}        # how the one rudis went: {"winner": name} or {"shared": [names]}

## A lone man's run's scroll as the save keeps it (RunScroll), and the one read out at its end.
static func _run_scroll() -> Dictionary:
	var v = Save.get_value("run_scroll", {})
	return v if v is Dictionary else {}
var run_shown := {}

## His run's scroll read out: what he did, and the weapon that killed the most.
func _run_scroll_rows(v: VBoxContainer, scroll: Dictionary) -> void:
	var g := GridContainer.new()
	g.columns = RunScroll.ROWS.size()
	g.add_theme_constant_override("h_separation", 26)
	for kt in RunScroll.ROWS:
		var l := UIStyle.label(String(kt[1]), 13, UIStyle.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		g.add_child(l)
	for kt in RunScroll.ROWS:
		g.add_child(UIStyle.label(str(int(scroll.get(kt[0], 0))), 22, UIStyle.TEXT))
	v.add_child(g)
	var bw := RunScroll.best_weapon(scroll)
	if not bw.is_empty():
		v.add_child(UIStyle.label(Loc.t("The weapon that killed the most: %s (%d)") % [Loc.t(String(bw[0])), int(bw[1])], 17, UIStyle.GOLD))

## The run's scroll as the host's save keeps it.
static func _party_scroll() -> Dictionary:
	var v = Save.get_value("coop_scroll", {})
	return v if v is Dictionary else {}

## The run is over: its scroll unrolled for the party (the host's, told to the guests), and a new
## one begun.
func _scroll_open(why: String) -> void:
	scroll_shown = _party_scroll()
	scroll_why = why
	Save.set_value("coop_scroll", {})
	Save.set_value("coop_favourite", "")
	if Net.active() and Net.is_host():
		Net.send_all("scroll", {"s": scroll_shown, "why": why})
	scroll_due = true

func _scroll(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 10)
	v.add_child(UIStyle.title("THE SCROLL OF THE GAMES", 36))
	if not Net.active() and scroll_shown.is_empty():
		v.add_child(UIStyle.label("The run is over. The scribe reads out what you did in it.", 15, UIStyle.MUTED))
		_run_scroll_rows(v, run_shown)
		v.add_child(UIStyle.button("Back to the yard", func(): enter_yard(""), true))
		return
	v.add_child(UIStyle.label("The run is over. The scribe reads out what each of you did in it.", 15, UIStyle.MUTED))
	_scroll_rows(v)
	if Net.active() and not Net.is_host():
		v.add_child(UIStyle.button("Back to the room", func(): show_screen("room"), true))
	else:
		v.add_child(UIStyle.button("Back to the yard", func(): enter_yard(""), true))

## The scroll's honours, then each of the party's tallies.
func _scroll_rows(v: VBoxContainer) -> void:
	for h in PartyGlory.honours(scroll_shown):
		v.add_child(UIStyle.label(Loc.t(HONOUR_TEXT[h[0]]) % [h[1], h[2]], 17, UIStyle.GOLD))
	if scroll_shown.is_empty():
		return
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 22)
	var cells := []
	for t in ["", "Bouts", "Kills", "Friends lifted", "Limbs lost", "Crowned"]:
		cells.append(UIStyle.label(t, 13, UIStyle.MUTED))
	for n in scroll_shown:
		var row: Dictionary = scroll_shown[n] if scroll_shown[n] is Dictionary else {}
		cells.append(UIStyle.label(String(n), 15, UIStyle.TEXT))
		for k in ["bouts", "kills", "lifts", "limbs", "fav"]:
			cells.append(UIStyle.label(str(int(row.get(k, 0))), 15, UIStyle.TEXT))
	for c in cells:
		(c as Label).autowrap_mode = TextServer.AUTOWRAP_OFF   # (a column as wide as what is in it)
		g.add_child(c)
	v.add_child(g)

## The ladder won by a party: the Emperor has one rudis for it. The scroll unrolled; each says
## whether he would share the glory or fight the others for it, and the host counts (PartyGlory.
## verdict). Alone in the room: it is his.
func _rudis_open(kills: int, stage: int) -> void:
	scroll_shown = _party_scroll()
	scroll_why = "won"
	rudis_votes = {}
	rudis_mine = ""
	rudis_kills = kills
	rudis_stage = stage
	rudis_end = {}
	if Net.peers.is_empty():
		_rudis_settle("share")
		return
	rudis_count = [0, 1 + Net.peers.size()]
	Net.send_all("rudis_ask", {"s": scroll_shown})
	show_screen("rudis")

func _rudis(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 10)
	v.add_child(UIStyle.title("ONE RUDIS", 40))
	var t := UIStyle.label("The Emperor rises. The crowd is on its feet. He holds out one wooden sword, not one for each of you: one of you goes free. Share the glory, all of you named on the scroll, or fight one another for it on the sand?", 16, UIStyle.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	_scroll_rows(v)
	if rudis_mine == "":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(UIStyle.button("Share the glory", func(): _rudis_vote("share"), true))
		row.add_child(UIStyle.button("Fight for it", func(): _rudis_vote("fight")))
		v.add_child(row)
	else:
		v.add_child(UIStyle.label(Loc.t("You would share the glory. %d of %d have spoken." if rudis_mine == "share" else "You would fight for it. %d of %d have spoken.") % [rudis_count[0], rudis_count[1]], 15, UIStyle.GOLD))
	# (A friend gone quiet, or gone: the host settles it with the word of those who spoke.)
	if Net.is_host() and not rudis_votes.is_empty() and rudis_votes.size() < 1 + Net.peers.size():
		v.add_child(UIStyle.button("Settle it with those who have spoken", func(): _rudis_settle(PartyGlory.verdict(rudis_votes.values()))))

func _rudis_vote(choice: String) -> void:
	rudis_mine = choice
	if Net.active() and not Net.is_host():
		Net.send_host("rudis_vote", choice)
		show_screen("rudis")
		return
	rudis_take(1, choice)

## (The host's) a word on the one rudis: when the whole room has spoken, the party's word.
func rudis_take(id: int, choice: String) -> void:
	if scroll_why != "won" or not rudis_end.is_empty() or not ["share", "fight"].has(choice):
		return
	rudis_votes[id] = choice
	rudis_count = [rudis_votes.size(), 1 + Net.peers.size()]
	Net.send_all("rudis_count", {"n": rudis_count[0], "of": rudis_count[1]})
	if rudis_votes.size() >= 1 + Net.peers.size():
		_rudis_settle(PartyGlory.verdict(rudis_votes.values()))
	elif screen == "rudis":
		show_screen("rudis")

## (The host's) the party's word. Shared: the rudis is all of theirs, their names together in the
## Hall of Fame. Fought for: the players' brawl, and the last of them on his feet takes it
## (_rudis_won).
func _rudis_settle(verdict: String) -> void:
	if verdict == "fight" and not Net.peers.is_empty():
		rudis_end = {"fight": true}
		start({"mode": "pvp", "rudis": true})
		return
	_rudis_shared()

## (The host's) the glory shared: the rudis is all of theirs, all named on the scroll.
func _rudis_shared() -> void:
	var names: Array = scroll_shown.keys().map(func(n): return String(n))
	if names.is_empty():
		names = [String(Save.get_value("name", "Gladiator"))]
	rudis_end = {"shared": names}
	_rudis_hall(" & ".join(names))
	if Net.active():
		Net.send_all("campaign_end", rudis_end)
	show_screen("campaign_end")

## (The host's) the brawl for the one rudis is over: the last of them on his feet takes it (none
## left standing: it is shared after all).
func _rudis_won(winner: String) -> void:
	if winner == "":
		_rudis_shared()
		return
	rudis_end = {"winner": winner}
	_rudis_hall(winner)
	Net.send_all("campaign_end", rudis_end)
	show_screen("campaign_end")

func _rudis_hall(name_: String) -> void:
	Save.set_value("hall", Circus.hall_add(Save.get_value("hall", []), name_, {"day": 7, "won": true, "kills": rudis_kills, "bouts_won": rudis_stage, "campaign": true}, ""))
	Save.set_value("coop_scroll", {})
	Save.set_value("coop_favourite", "")

## The end of the demo: the second boss is down. The campaign stops here; the demo again from
## bout 1, or back to the menu.
## The campaign won: the rudis, the wooden sword of a gladiator set free. The next campaign
## waits in the yard, the same man and his gear, the foes tougher (Match.lap).
func _campaign_end(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 12)
	var lap := int(Save.get_value("coop_lap" if Net.active() else "lap", 2))
	v.add_child(UIStyle.title("THE RUDIS", 40))
	if rudis_end.has("winner"):
		v.add_child(UIStyle.label(Loc.t("%s took the one rudis, won on the sand from the friends who walked the ladder with him.") % String(rudis_end.winner), 18, UIStyle.GOLD))
	elif rudis_end.has("shared") and (rudis_end.shared as Array).size() > 1:
		v.add_child(UIStyle.label(Loc.t("The glory shared: %s, named together in the Hall of Fame.") % ", ".join(rudis_end.shared), 18, UIStyle.GOLD))
	v.add_child(UIStyle.label(Loc.t("The Emperor rises. The crowd is on its feet. The wooden sword is put in your hand: %d bouts, every beast and monster of the ladder, and you are free.") % Data.campaign.get("stages", []).size(), 17, UIStyle.TEXT))
	if not rudis_end.has("winner") or String(rudis_end.winner) == String(Save.get_value("name", "")):
		v.add_child(UIStyle.label("Your name is in the Hall of Fame.", 15, UIStyle.GOLD))
		_grant_rudis()
		var gift := UIStyle.label("The Emperor's gilded rudis hangs on the smith's rack, yours to fight with, and the freedman's cap is yours to wear (Your gladiator: Hat).", 15, UIStyle.GOLD)
		gift.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(gift)
	if not Net.active() and not run_shown.is_empty():
		v.add_child(UIStyle.label("THE SCROLL OF THE GAMES", 20, UIStyle.BRONZE))
		_run_scroll_rows(v, run_shown)
	if bool(Save.get_value("unbroken_news", false)):
		Save.set_value("unbroken_news", false)
		var un := UIStyle.label("UNBROKEN. One life, and you never fell. The Emperor sets a laurel of gold on your head (Your gladiator: Hat), and Doctore will teach you Virtus, which no death can take.", 16, UIStyle.GOLD)
		un.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(un)
	v.add_child(UIStyle.label(Loc.t("But the arena calls. Campaign %s waits in the yard: your gladiator, his arms and his purse as they are; the foes a third tougher, the beasts bigger.") % str(lap), 15, UIStyle.MUTED))
	v.add_child(UIStyle.button("Back to the ludus", func(): show_screen("main" if not Net.active() else "room"), true))

## The rudis won (alone, the brawl for it won, or the glory shared): the Emperor's gilded wooden
## sword hung on the smith's rack for him, once, and the freedman's cap his to wear (user: a real
## reward at the campaign's end).
func _grant_rudis() -> void:
	Save.set_value("freed", true)
	var a := arms()
	var held := [a.get("main"), a.get("off")] + (a.get("rack", []) as Array)
	if held.any(func(d): return d is Dictionary and String(d.get("name", "")) == "Rudis"):
		return
	var rack: Array = a.get("rack", [])
	rack.append(Data.preset("rudis").duplicate(true))
	while rack.size() > Arms.RACK_MAX:
		rack.pop_front()
	a["rack"] = rack
	set_arms(a)

func _demo_end(v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", 12)
	v.add_child(UIStyle.title("The end of the demo", 40))
	v.add_child(UIStyle.label(Loc.t("You have fought through all %d bouts of the demo.") % Edition.DEMO_STAGES, 17, UIStyle.TEXT))
	if not Net.active() or Net.is_host():
		v.add_child(UIStyle.button("Play the demo again from bout 1", func():
			Save.set_value("coop_stage", 1)
			Save.set_value("coop_checkpoint", 1)
			GateChoice.clear(true)
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
		match_.feed.emit(Loc.t("Screenshot saved: %s") % path.get_file())
	return path

## A new campaign: back to bout 1, the body whole, the arms and the bag as for a beginner.
func restart_campaign() -> void:
	if Save.boxed:
		return   # (the friends' room has no campaign to begin again)
	Save.set_value("run_seed", randi())   # a new run: other oddities at the smith
	Save.set_value("run_scroll", {})
	GateChoice.clear(false)
	Save.set_value("oddities_sold", {})
	Save.set_value("coins", START_COINS)
	Save.set_value("stage", 1)
	Save.set_value("checkpoint", 1)
	Save.set_value("lap", 1)
	Save.set_value("coop_lap", 1)
	set_body(Body.empty())
	set_arms(Arms.empty())
	set_kit({})
	set_worn_armor([])
	set_armor_wear({})
	set_training_stats({})
	# How death is dealt with this time, then the yard, not straight into bout 1: the smith, the
	# market and the gate first (online the host brings the whole party back with him).
	if match_:
		_end_match()
	show_screen("campaign_mode")

## A new campaign: Legionary (back to the last checkpoint on a death) or Ironman (one life).
func _campaign_mode(v: VBoxContainer) -> void:
	var coop := Net.active()
	v.add_theme_constant_override("separation", 14)
	v.add_child(UIStyle.label("A NEW CAMPAIGN" + (" · CO-OP" if coop else ""), 13, UIStyle.BRONZE))
	v.add_child(UIStyle.title("How will you die?", 36))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	for m in ["legionary", "ironman"]:
		var md: Dictionary = CampaignRun.MODES[m]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(300, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.1, 0.075, 0.055, 0.95)
		cs.border_color = UIStyle.GOLD if m == "ironman" else UIStyle.BRONZE
		cs.set_border_width_all(2 if m == "ironman" else 1)
		cs.set_corner_radius_all(8)
		cs.content_margin_left = 16; cs.content_margin_right = 16; cs.content_margin_top = 12; cs.content_margin_bottom = 14
		card.add_theme_stylebox_override("panel", cs)
		row.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		card.add_child(col)
		col.add_child(UIStyle.title(Loc.t(String(md.name)), 26))
		var d := UIStyle.label(Loc.t(String(md.desc)), 14, UIStyle.TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(0, 72)
		col.add_child(d)
		if m == "ironman":
			var rw := UIStyle.label("Earned: the Unbroken laurel, and Virtus from the trainer." if CampaignRun.unbroken() else "The reward: the Unbroken laurel, and Virtus from the trainer.", 13, UIStyle.GOLD)
			rw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(rw)
		col.add_child(UIStyle.button("Begin as a legionary" if m == "legionary" else "Begin as an ironman", func():
			CampaignRun.begin(m, coop)
			enter_yard(Loc.t("A new campaign begins · %s") % Loc.t(String(md.name))), m == "legionary"))

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
	UIStyle.frame_over(p)
	v.add_child(UIStyle.title("Paused", 30))
	v.add_child(UIStyle.button("Back to the yard" if in_yard() else "Back to the fight", _toggle_pause, true))
	if Net.active() and Net.is_host() and Net.room_kind == Net.KIND_ARENA and in_yard():
		v.add_child(UIStyle.button("The Arena: pick a fight for the room", func():
			_toggle_pause()
			_open_station("gate")))
	if forge_trying != null:
		v.add_child(UIStyle.button("Back to the forge", func():
			_toggle_pause()
			back_to_forge(), true))
	if match_ and (match_.mode == "campaign" or match_.mode == "yard") and (not Net.active() or Net.is_host()) and not Save.boxed:
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
		# Who is in the room, the invite, Mute and (for the host) Remove: the room's own screen, over the game.
		v.add_child(UIStyle.button(Loc.t("The room · %d of %d") % [Net.room_list().size(), Net.MAX_PLAYERS], func():
			_toggle_pause()
			_open_over_match("room")))
		if Net.transport == "steam" and Net.is_host():
			v.add_child(UIStyle.button("Invite friends (Steam)", func(): Net.invite_friends()))
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
			var to_endless: bool = match_ != null and match_.mode == "endless"
			_end_match()
			show_screen("training" if to_training else ("endless" if to_endless else "main"))))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.active():
		get_tree().paused = true
