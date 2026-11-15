class_name GateScreen
extends Control
## The arena gate (user: the choice of the next fight attractive, interactive, dynamic and easy to
## use; a real background behind every foe): a card for each fight on offer by it (GateChoice).
## On a card: its kind on a ribbon; the foes themselves as the bout will bring them (Match.bout_foes:
## the same men, the same arms), standing in the arena they will be fought in (an arena of the
## cards' own, in a world of its own: its wall, its stands and their crowd, its gates, the
## Emperor's box, the evening sun), each kind of fight in its own place in it; their names, what
## they carry, what the fight pays. The card the pointer is on (or ← → pick) comes forward, lit:
## its foes stir (they stand as they stand in a fight; the others hold still), the view comes
## nearer, follows the pointer and turns with a drag. Its button, a double click, Enter or E goes
## through the gate; Esc, or the button in the corner, goes back to the yard. In a room each of the
## party picks a card (here, or by walking up to its board in the yard), the names of those for it
## are on each card, and the host leads them through to the one most of them picked
## (GateChoice.majority).

signal chosen(i: int)   # through the gate: alone to card i; the host leads the party (his own pick i, -1 none)
signal voted(i: int)    # in a room: card i is my pick
signal closed

const VIEW := Vector2i(376, 300)
const VIEW_ALONE := Vector2i(600, 330)   # a lone card's (a boss's day): the one fight, seen bigger
const MOST_SHOWN := 4    # foes stood in a card's view (all of them are named under it)
const SETTLE := 1.6      # seconds a foe has to take his stance before he is held still
const FOE_R := 9.0       # how far from the arena's middle a card's foes stand
const FOV := 40.0
## Where in the arena a fight of each kind is shown, in degrees round it (0: under the Emperor's
## box; 90 and 270: before the gates): the ladder's bout before a gate, the crowd's fight under
## the full stands, another bout under the stands to the side, a boss under the Emperor's eyes.
const SPOTS := {"ladder": 270.0, "crowd": 180.0, "other": 135.0, "boss": 0.0}
const SPARE_SPOTS := [225.0, 315.0, 90.0]
## How a man stands while his card is forward: his weapon up, his off hand across him.
const STANCE := {"main": {"x": 0.35, "y": -0.35}, "off": {"x": -0.5, "y": -0.3}}

var offers: Array = []
var stage := 1
var players := 1
var lap := 1
var at := 0                # the card come forward (pointed at, or picked with the keys)
var mine := -1             # in a room: my pick (-1: none yet)
var party := false         # in a room: a pick is a vote, the host leads them through
var host := true
var previews := true       # the arena and the foes in the cards' views (the tests leave them out)
var lead_block := ""       # the host: why the party cannot be led through now (too many in the room)
var extras: Array = []     # [[text, Callable]]: where else the gate leads (the host: a mode for the room)
var refresh: Callable      # called twice a second while open (the host: the party's picks)
var cards: Array = []      # a Dictionary a card (see _card)
var world: SubViewport     # the cards' arena and their foes: a world of its own
var arena: Arena
var fade: ColorRect
var lead: Button
var glows: Array = []      # the torchlight in the corners
var done := false
var lead_to := -1          # the card the party is led to (a room)
var _t := 0.0
var _refresh_t := 0.0
var _votes_shown := []
var _was_3d_off := false

## The gate's cards over `parent` (the menu): `offers` (GateChoice) at `stage` for `players`.
## `o`: at (the card come forward first), mine, party, host, lap, previews, lead_block, extras.
static func open(parent: Node, offers_: Array, stage_: int, players_: int, o := {}) -> GateScreen:
	var g := GateScreen.new()
	g.offers = offers_.slice(0, 3)
	g.stage = maxi(1, stage_)
	g.players = clampi(players_, 1, Net.CAMPAIGN_PLAYERS)
	g.party = bool(o.get("party", false))
	g.host = bool(o.get("host", true))
	g.lap = maxi(1, int(o.get("lap", 1)))
	g.previews = bool(o.get("previews", true))
	g.lead_block = String(o.get("lead_block", ""))
	g.extras = o.get("extras", []) if o.get("extras") is Array else []
	g.at = clampi(int(o.get("at", 0)), 0, maxi(0, g.offers.size() - 1))
	g.mine = clampi(int(o.get("mine", -1)), -1, g.offers.size() - 1)
	g.name = "gate_screen"
	parent.add_child(g)
	g._build()
	return g

## What a card says of its fight: the kind's ribbon, its colour, its line, its word in Latin.
static func kind_of(o: Dictionary) -> Dictionary:
	match String(o.get("kind", "ladder")):
		"crowd":
			return {"title": "For the crowd", "latin": "PRO POPVLO", "line": "One more of them, and the crowd pays double for it.", "color": Color(0.6, 0.12, 0.08)}
		"boss":
			return {"title": "A boss's day", "latin": "", "line": "No choosing today: the boss waits for you.", "color": Color(0.4, 0.18, 0.47)}
		"other":
			if GateChoice.beasts(int(o.get("bout", 1))):
				return {"title": "A beast hunt", "latin": "VENATIO", "line": "Another bout of this stretch of the ladder, against beasts.", "color": Color(0.22, 0.37, 0.16)}
			return {"title": "Men with blades", "latin": "MVNVS", "line": "Another bout of this stretch of the ladder, against men.", "color": Color(0.29, 0.34, 0.42)}
	return {"title": "The ladder's bout", "latin": "", "line": "The fight the ladder has set you.", "color": Color(0.5, 0.36, 0.17)}

## A fight's foes as a board names them (YardPlay.fight_text's F lines).
static func foe_lines(text: String) -> Array:
	var out := []
	for l in text.split("\n"):
		if l.begins_with("F|"):
			out.append(l.substr(2))
	return out

## What the men of a fight carry, by name ("Gladius · Round Shield"); "" for beasts alone.
static func arms_line(specs: Array) -> String:
	var names := []
	for f in specs:
		var sp: Dictionary = f.spec
		if String(sp.get("kind", "")) == "beast" or not (sp.get("loadout") is Dictionary):
			continue
		for h in ["main", "off"]:
			var d = sp.loadout.get(h)
			var n := String(d.get("name", "")) if d is Dictionary else ""
			if n != "" and not names.has(Loc.t(n)):
				names.append(Loc.t(n))
	return " · ".join(names.slice(0, 4))

## What sets a fight apart, a word each (the chips over a card's view).
static func tags_of(o: Dictionary, specs: Array) -> Array:
	var out := []
	if String(o.get("kind", "")) == "crowd":
		out.append("One more foe")
		out.append("Double prize")
	if specs.any(func(f): return bool(f.get("late", false))):
		out.append("A second wave")
	if specs.any(func(f): return bool((f.spec as Dictionary).get("boss", false))):
		out.append("A boss")
	return out

# ---------- The screen ----------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIStyle.theme()
	# Behind it all: the dark under the stands, torchlight in its corners, embers on the draught.
	# (The yard is not drawn while the gate's cards are up: their views are drawn instead.)
	var bg := TextureRect.new()
	bg.texture = _backdrop()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for side: float in [0.0, 1.0]:
		var glow := TextureRect.new()
		glow.texture = _torch_glow()
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.anchor_left = side * 0.62
		glow.anchor_right = 0.38 + side * 0.62
		glow.anchor_top = 0.3
		glow.anchor_bottom = 1.3
		add_child(glow)
		glows.append(glow)
	if previews:
		var embers := CPUParticles2D.new()
		embers.amount = 46
		embers.lifetime = 7.0
		embers.preprocess = 7.0
		embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		embers.emission_rect_extents = Vector2(900, 12)
		embers.direction = Vector2(0.15, -1)
		embers.spread = 18.0
		embers.gravity = Vector2(0, -6)
		embers.initial_velocity_min = 40.0
		embers.initial_velocity_max = 120.0
		embers.scale_amount_min = 1.5
		embers.scale_amount_max = 3.5
		embers.color = Color(1.0, 0.56, 0.2, 0.75)
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 0.6, 0.4, 0.0)])
		embers.color_ramp = ramp
		embers.position = Vector2(800, 930)
		add_child(embers)
		_was_3d_off = get_viewport().disable_3d
		get_viewport().disable_3d = true
		_build_world()
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	center.add_child(col)
	var title := Label.new()
	title.text = Loc.t("The arena gate")
	title.add_theme_font_override("font", UIStyle.serif(4, 700))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", UIStyle.GOLD)
	title.add_theme_color_override("font_outline_color", UIStyle.INK)
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var rule := Ornament.new("rule", Vector2(380, 12))
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.color = Color(UIStyle.GOLD, 0.85)
	col.add_child(rule)
	var boss_day := offers.size() == 1 and String((offers[0] as Dictionary).get("kind", "")) == "boss"
	var sub_text := Loc.t("Bout %s of the ladder · choose your fight")
	if boss_day:
		sub_text = Loc.t("Bout %s of the ladder · a boss's day: no choosing")
	elif party:
		sub_text = Loc.t("Bout %s of the ladder · each of you picks a fight, and the host leads you to the one most of you picked")
	var sub := UIStyle.label(sub_text % YardPlay.roman(stage), 17, UIStyle.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_gap(10))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in offers.size():
		cards.append(_card(row, i, offers[i]))
	# Below the cards: the party led through (the host), where else the gate leads, what the keys do.
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 14)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if party and host:
		lead = UIStyle.button(Loc.t("Lead the party through"), func(): _go(mine), true)
		lead.focus_mode = Control.FOCUS_NONE
		lead.custom_minimum_size = Vector2(320, 46)
		if lead_block != "":
			lead.disabled = true
			lead.tooltip_text = lead_block
		foot.add_child(lead)
	for x in extras:
		if x is Array and (x as Array).size() == 2 and x[1] is Callable:
			var b := UIStyle.button(String(x[0]), x[1])
			b.focus_mode = Control.FOCUS_NONE
			foot.add_child(b)
	if foot.get_child_count() > 0:
		col.add_child(_gap(8))
		col.add_child(foot)
	if lead_block != "":
		var why := UIStyle.label(lead_block, 15, UIStyle.MUTED)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.custom_minimum_size = Vector2(760, 0)
		why.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(why)
	col.add_child(_gap(10))
	col.add_child(_keys())
	# The way back, where every stall has it: the corner.
	var back := UIStyle.button(Loc.t("◀  Back to the yard  (Esc)"), close)
	back.focus_mode = Control.FOCUS_NONE
	back.position = Vector2(28, 24)
	add_child(back)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	for j in cards.size():
		_style(j, false)
		var p: Control = cards[j].panel
		p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	# The cards come up one after another.
	for i in cards.size():
		var p: Control = cards[i].panel
		p.modulate.a = 0.0
		var tw := p.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.05 + 0.1 * i)
		tw.tween_property(p, "modulate:a", 1.0, 0.3)
	if previews:
		_fill.call_deferred()

static func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

## What the keys do, each on its key.
func _keys() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 22)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var go_text := "through the gate"
	if party:
		go_text = "this fight is my pick"
	var keys := [[["Enter"], go_text], [["Esc"], "back to the yard"], [[], "drag a card to turn its foes"]]
	if offers.size() > 1:
		keys.push_front([["←", "→"], "choose a fight"])
	for kv in keys:
		var g := HBoxContainer.new()
		g.add_theme_constant_override("separation", 5)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for k in kv[0]:
			g.add_child(_keycap(String(k)))
		var l := UIStyle.label(Loc.t(String(kv[1])), 14, UIStyle.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		g.add_child(l)
		bar.add_child(g)
	return bar

static func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.16, 0.12, 0.085)
	s.border_color = Color(UIStyle.BRONZE, 0.75)
	s.set_border_width_all(1)
	s.border_width_bottom = 3
	s.set_corner_radius_all(5)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", s)
	var l := UIStyle.label(text, 13, UIStyle.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.add_child(l)
	return cap

# ---------- A card ----------

## A card: {panel, svc, vp, cam, fill, deg, dir, spot, centre, box, dist, near, look, look_to,
## turn, hover, chips, go, color, offer, specs, foes}.
func _card(row: HBoxContainer, i: int, o: Dictionary) -> Dictionary:
	var k := kind_of(o)
	var crowd := String(o.get("kind", "")) == "crowd"
	var bout := int(o.get("bout", stage))
	var foes := foe_lines(YardPlay.fight_text(stage, players, bout, crowd))
	var specs := Match.bout_foes(stage, players, bout, crowd, lap)
	var view := _view()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(view.x + 4, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_child(panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	# The ribbon: what kind of fight, and which bout of the ladder in numerals.
	var rib := PanelContainer.new()
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = k.color
	rs.border_color = (k.color as Color).lightened(0.3)
	rs.border_width_bottom = 2
	rs.corner_radius_top_left = 8
	rs.corner_radius_top_right = 8
	rs.content_margin_left = 16
	rs.content_margin_right = 14
	rs.content_margin_top = 8
	rs.content_margin_bottom = 7
	rib.add_theme_stylebox_override("panel", rs)
	col.add_child(rib)
	var rh := HBoxContainer.new()
	rh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rib.add_child(rh)
	var kt := Label.new()
	kt.text = Loc.t(String(k.title)).to_upper()
	kt.add_theme_font_override("font", UIStyle.serif(3, 700))
	kt.add_theme_font_size_override("font_size", 18)
	kt.add_theme_color_override("font_color", UIStyle.GOLD_LIGHT)
	kt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	kt.add_theme_constant_override("outline_size", 4)
	kt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kt.clip_text = true
	rh.add_child(kt)
	var num := Label.new()
	num.text = YardPlay.roman(bout)
	num.add_theme_font_override("font", UIStyle.serif(2, 700))
	num.add_theme_font_size_override("font_size", 18)
	num.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 0.6))
	rh.add_child(num)
	# The foes, in the arena.
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(view)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(svc)
	var vp := SubViewport.new()
	vp.size = view
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var c := {"panel": panel, "svc": svc, "vp": vp, "near": 0.0, "hover": false, "turn": 0.0, "look": Vector2.ZERO, "look_to": Vector2.ZERO,
		"color": k.color, "offer": o, "specs": specs, "foes": [], "dist": 4.4, "box": AABB(Vector3(-0.5, 0, -0.4), Vector3(1.0, 1.9, 0.8))}
	_spot(c, i)
	if world:
		vp.world_3d = world.find_world_3d()
		var cam := Camera3D.new()
		cam.fov = FOV
		cam.near = 0.1
		cam.far = 200.0
		vp.add_child(cam)
		cam.current = true
		c["cam"] = cam
		# A soft light on them from the view's side (their faces, under the stands' shade).
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.9, 0.76)
		# (Brighter on a beast's dark hide, and on a boss in the shade of the Emperor's box.)
		var beasts_only := specs.all(func(f): return String((f.spec as Dictionary).get("kind", "")) == "beast")
		fill.light_energy = 3.0 if String(o.get("kind", "")) == "boss" else (2.2 if beasts_only else 0.8)
		fill.shadow_enabled = false
		world.add_child(fill)
		c["fill"] = fill
		_place(c, 0.0)
		# A new view shows whatever was in the graphics memory until it has drawn once: kept clear till then.
		svc.modulate.a = 0.0
		_reveal(svc)
	# The view's edges darkened, its foot run into the card under it; over it, what sets the fight apart.
	var shade := TextureRect.new()
	shade.texture = _vignette()
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.add_child(shade)
	var foot_shade := TextureRect.new()
	foot_shade.texture = _foot_fade()
	foot_shade.stretch_mode = TextureRect.STRETCH_SCALE
	foot_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot_shade.anchor_top = 0.8
	foot_shade.anchor_right = 1.0
	foot_shade.anchor_bottom = 1.0
	svc.add_child(foot_shade)
	var tags := HFlowContainer.new()
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 4)
	tags.anchor_right = 1.0
	tags.offset_left = 10
	tags.offset_top = 10
	tags.offset_right = -10
	for tg in tags_of(o, specs):
		tags.add_child(_chip(Loc.t(String(tg)), UIStyle.GOLD_LIGHT, Color(0.1, 0.07, 0.05, 0.82)))
	svc.add_child(tags)
	# What it is: its foes, what they carry, its line, what it pays.
	var body := MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_left", 18)
	body.add_theme_constant_override("margin_right", 18)
	body.add_theme_constant_override("margin_top", 10)
	body.add_theme_constant_override("margin_bottom", 16)
	col.add_child(body)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 6)
	body.add_child(info)
	if String(k.latin) != "":
		var lat := Label.new()
		lat.text = String(k.latin)
		lat.add_theme_font_override("font", UIStyle.serif(5, 700))
		lat.add_theme_font_size_override("font_size", 12)
		lat.add_theme_color_override("font_color", (k.color as Color).lightened(0.55))
		info.add_child(lat)
	var fl := UIStyle.label(" · ".join(foes), 21, UIStyle.TEXT)
	fl.add_theme_font_override("font", UIStyle.serif(1, 700))
	info.add_child(fl)
	var arms := arms_line(specs)
	if arms != "":
		info.add_child(UIStyle.label(Loc.t("Armed with: %s") % arms, 14, UIStyle.BRONZE))
	info.add_child(UIStyle.label(Loc.t(String(k.line)), 14, UIStyle.MUTED))
	UIStyle.push_down(info)
	var pay_row := HBoxContainer.new()
	pay_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pay_row.add_theme_constant_override("separation", 9)
	info.add_child(pay_row)
	var pl := UIStyle.label(Loc.t("Prize"), 14, UIStyle.MUTED)
	pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pay_row.add_child(pl)
	var coin := Panel.new()
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.custom_minimum_size = Vector2(16, 16)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cs := StyleBoxFlat.new()
	cs.bg_color = UIStyle.GOLD
	cs.border_color = Color(0.5, 0.36, 0.12)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(8)
	coin.add_theme_stylebox_override("panel", cs)
	pay_row.add_child(coin)
	var pv := Label.new()
	pv.text = Loc.t("%d denarii") % Body.bout_pay(stage, crowd)
	pv.add_theme_font_override("font", UIStyle.serif(2, 700))
	pv.add_theme_font_size_override("font_size", 21)
	pv.add_theme_color_override("font_color", UIStyle.GOLD_LIGHT)
	pay_row.add_child(pv)
	if crowd:
		var dbl := _chip("×2", UIStyle.GOLD_LIGHT, Color(0.6, 0.12, 0.08))
		dbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pay_row.add_child(dbl)
	var chips := HFlowContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	info.add_child(chips)
	var go := UIStyle.button("", func(): _press(i), true)
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(0, 44)
	info.add_child(go)
	c["chips"] = chips
	c["go"] = go
	panel.mouse_entered.connect(func(): _hover(i, true))
	panel.mouse_exited.connect(func(): _hover(i, false))
	panel.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.double_click:
			_press(i)
		elif e is InputEventMouseMotion:
			if (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				# (Dragged across the card: its foes turned, to be seen from the side.)
				c.turn = clampf(float(c.turn) - e.relative.x * 0.012, -1.4, 1.4)
			elif panel.size.x > 1.0:
				# (The view follows the pointer a little.)
				c.look_to = Vector2(clampf(e.position.x / panel.size.x - 0.5, -0.5, 0.5), clampf(e.position.y / panel.size.y - 0.5, -0.5, 0.5)))
	return c

## A card's view: a lone card's bigger.
func _view() -> Vector2i:
	return VIEW if offers.size() > 1 else VIEW_ALONE

## Where in the arena card `i`'s foes stand: its kind's place (another, if that is taken).
func _spot(c: Dictionary, i: int) -> void:
	var deg: float = float(SPOTS.get(String((c.offer as Dictionary).get("kind", "ladder")), 270.0))
	if cards.any(func(x): return is_equal_approx(float(x.deg), deg)):
		deg = float(SPARE_SPOTS[i % SPARE_SPOTS.size()])
	var a := deg_to_rad(deg)
	c["deg"] = deg
	c["dir"] = Vector3(sin(a), 0, cos(a))
	c["spot"] = (c.dir as Vector3) * FOE_R
	c["centre"] = (c.spot as Vector3) + Vector3(0, 0.95, 0)

func _chip(text: String, fg: Color, bg: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(UIStyle.GOLD, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(9)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 1
	s.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", s)
	var l := UIStyle.label(text, 13, fg)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.add_child(l)
	return chip

static var _vig: GradientTexture2D
static func _vignette() -> GradientTexture2D:
	if _vig == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.04), Color(0.03, 0.015, 0.0, 0.5)])
		_vig = GradientTexture2D.new()
		_vig.gradient = g
		_vig.fill = GradientTexture2D.FILL_RADIAL
		_vig.fill_from = Vector2(0.5, 0.45)
		_vig.fill_to = Vector2(1.1, 1.0)
		_vig.width = 128
		_vig.height = 128
	return _vig

static var _foot: GradientTexture2D
static func _foot_fade() -> GradientTexture2D:
	if _foot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(0.07, 0.052, 0.038, 0.0), Color(0.07, 0.052, 0.038, 0.9)])
		_foot = GradientTexture2D.new()
		_foot.gradient = g
		_foot.fill_from = Vector2(0, 0)
		_foot.fill_to = Vector2(0, 1)
		_foot.width = 8
		_foot.height = 64
	return _foot

static var _bg: GradientTexture2D
static func _backdrop() -> GradientTexture2D:
	if _bg == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0.135, 0.092, 0.06), Color(0.062, 0.043, 0.03), Color(0.02, 0.014, 0.01)])
		_bg = GradientTexture2D.new()
		_bg.gradient = g
		_bg.fill = GradientTexture2D.FILL_RADIAL
		_bg.fill_from = Vector2(0.5, 0.42)
		_bg.fill_to = Vector2(1.05, 1.1)
		_bg.width = 256
		_bg.height = 256
	return _bg

static var _glow: GradientTexture2D
static func _torch_glow() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(1.0, 0.5, 0.16, 0.2), Color(1.0, 0.4, 0.1, 0.0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow

func _reveal(svc: Control) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	if is_instance_valid(svc):
		var tw := svc.create_tween()
		tw.tween_property(svc, "modulate:a", 1.0, 0.3)

# ---------- The cards' arena, and the foes in it ----------

## The arena the cards' foes stand in: the one they will be fought in, late in the day, in a world
## of its own (nothing of the yard's in it, nothing of it in the yard). Built in a few tens of
## milliseconds: the yard's own arena has made everything it is made of.
func _build_world() -> void:
	world = SubViewport.new()
	world.name = "gate_world"
	world.own_world_3d = true
	world.size = Vector2i(2, 2)
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(world)
	arena = Arena.new()
	world.add_child(arena)
	arena.build("colosseum", true, "golden")
	arena.set_physics_process(false)   # (the crowd's noise is the yard's arena's to make)
	if arena.crowd_mat:
		arena.crowd_mat.set_shader_parameter("excitement", 0.55)
	if arena.crowd_far_mat:
		arena.crowd_far_mat.set_shader_parameter("excitement", 0.55)

## The foes, built a card after another (the one come forward first), a part a frame (staged:
## opening the gate is no stop of the game), each set down in his card's place in the arena.
func _fill() -> void:
	var order := range(cards.size())
	order.erase(at)
	order.push_front(at)
	for i in order:
		if done or not is_inside_tree() or i >= cards.size():
			return
		await _foes(cards[i])
		if i < cards.size():
			cards[i].built = true

func _foes(c: Dictionary) -> void:
	var list: Array = (c.specs as Array).slice(0, MOST_SHOWN)
	var dir: Vector3 = c.dir
	var side := Vector3(dir.z, 0, -dir.x)   # along the wall
	var face := atan2(-dir.x, -dir.z)        # toward the middle of the arena: the view
	var built := []
	for k in list.size():
		var spec: Dictionary = list[k].spec
		if done or not is_instance_valid(world):
			break
		var at_first: Vector3 = (c.spot as Vector3) + Vector3(0, 0.1, 0)
		var w: Fighter
		if String(spec.get("kind", "")) == "beast":
			var b := Beast.new()
			b.visible = false
			b.process_mode = Node.PROCESS_MODE_DISABLED
			world.add_child(b)
			var sc: float = float(spec.scale) if spec.get("scale") != null else float(Data.beasts.get(spec.beast, {}).get("scale", 1.0))
			# (Half turned: a beast seen along its flank, its head toward the view.)
			await b.build_beast(String(spec.beast), at_first, face + 0.75, {"name": spec.get("name", ""), "scale": sc, "boss": spec.get("boss", false), "team": 1, "seed": 1, "staged": true})
			w = b
		else:
			var f := Fighter.new()
			f.visible = false
			f.process_mode = Node.PROCESS_MODE_DISABLED
			world.add_child(f)
			# (As Match._new_fighter builds him: his face is drawn from his name and his place.)
			var fo := {"name": spec.get("name", ""), "slot": int(list[k].slot), "team": 1, "mods": spec.get("mods", {}), "boss": spec.get("boss", false), "bot": true, "staged": true,
				"team_color": Color.hex(int(spec.color) << 8 | 0xff) if spec.get("color") != null else Color(0.19, 0.19, 0.19)}
			if spec.get("skin") != null:
				fo["skin"] = int(spec.skin)
			if spec.get("build") is String:
				fo["build"] = spec.build
			await f.build(at_first, face + (0.22 if k % 2 == 0 else -0.22), Match._resolve_loadout(spec.loadout), fo)
			w = f
		if not is_instance_valid(w):
			break
		if done or not is_inside_tree() or w.torso == null:
			w.queue_free()
			break
		# Whole: into the arena beside those before him, standing.
		w.process_mode = Node.PROCESS_MODE_INHERIT
		w.visible = true
		if not built.is_empty():
			var prev := _row_box(built, side)
			var mine_ := _box_of(w, side)
			_shift(w, side * (prev.end.x + 0.35 - mine_.position.x))
		w.set_meta("anchor", w.torso.global_position)
		w.set_meta("settle", 0.0)
		built.append(w)
		c.foes = built.duplicate()
		_fit(c, side)
	if built.size() > 1 and not done:
		# All of them in: the row's middle on the card's place.
		var all := _row_box(built, side)
		var mid := all.position.x + all.size.x * 0.5
		for w in built:
			if is_instance_valid(w):
				_shift(w, -side * mid)
				w.set_meta("anchor", (w.get_meta("anchor") as Vector3) - side * mid)
		_fit(c, side)

## A foe moved where he stands by `by` (all of him: his parts, what he holds).
func _shift(w: Fighter, by: Vector3) -> void:
	for p in _bodies(w):
		(p as Node3D).global_position += by
		if p is RigidBody3D:
			(p as RigidBody3D).linear_velocity = Vector3.ZERO
			(p as RigidBody3D).angular_velocity = Vector3.ZERO
		(p as Node3D).reset_physics_interpolation()
		if p is VoxelPart:
			(p as VoxelPart).snap_drawing()

func _bodies(w: Fighter) -> Array:
	var out: Array = (w.parts as Array).filter(func(p): return is_instance_valid(p))
	for s in ["R", "L"]:
		var wp = w.weapons.get(s)
		if wp != null and is_instance_valid(wp) and not out.has(wp):
			out.append(wp)
	return out

## The box a foe fills, measured from his card's place (`side`: along the wall, x; up, y; toward
## the middle of the arena, z).
func _box_of(w: Fighter, side: Vector3) -> AABB:
	var fwd := Vector3(-side.z, 0, side.x)
	var lo := Vector3.ONE * INF
	var hi := -Vector3.ONE * INF
	var spot := Vector3.ZERO
	for p in _bodies(w):
		var he := Vector3.ONE * 0.1
		if p is VoxelPart:
			he = (p as VoxelPart).half_ext
		var xf: Transform3D = (p as Node3D).global_transform
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var q: Vector3 = xf * Vector3(he.x * sx, he.y * sy, he.z * sz) - spot
					var v := Vector3(q.dot(side), q.y, q.dot(fwd))
					lo = lo.min(v)
					hi = hi.max(v)
	lo.y = 0.0
	return AABB(lo, hi - lo)

## The box a card's foes fill together (as _box_of).
func _row_box(list: Array, side: Vector3) -> AABB:
	var all := AABB()
	var first := true
	for w in list:
		if not is_instance_valid(w):
			continue
		var bx := _box_of(w, side)
		all = bx if first else all.merge(bx)
		first = false
	return all

## The view fitted to a card's foes: far enough to hold them all, their middle its aim.
func _fit(c: Dictionary, side: Vector3) -> void:
	var list: Array = (c.foes as Array).filter(func(w): return is_instance_valid(w))
	if list.is_empty():
		return
	var fwd := Vector3(-side.z, 0, side.x)
	var all := _row_box(list, side)
	var mid := all.position + all.size * 0.5
	c.centre = side * mid.x + fwd * mid.z + Vector3(0, mid.y, 0)
	c.box = all
	var half_v := deg_to_rad(FOV * 0.5)
	var aspect := float(_view().x) / float(_view().y)
	var need_h := all.size.y * 0.5 / (0.66 * tan(half_v))
	var need_w := all.size.x * 0.5 / (0.8 * tan(half_v) * aspect)
	c.dist = clampf(maxf(need_h, need_w) + all.size.z * 0.5, 2.4, FOE_R + 4.0)

## The view of a card: from the arena's middle toward its foes, low (they stand over it, the
## stands and the sky behind them), swinging slowly round them; nearer while the card is forward;
## turned by a drag and a little by the pointer.
func _place(c: Dictionary, t: float) -> void:
	if not c.has("cam") or not is_instance_valid(c.cam):
		return
	var cam: Camera3D = c.cam
	var dir: Vector3 = c.dir
	var j := cards.find(c)
	var look: Vector2 = c.look
	var yaw := atan2(dir.x, dir.z) + PI + sin(t * 0.3 + float(j) * 1.7) * 0.16 + float(c.turn) + look.x * 0.3
	var d: float = float(c.dist) * (1.0 - 0.14 * float(c.near))
	var ctr: Vector3 = c.centre
	var bx: AABB = c.box
	var h := maxf(0.35, ctr.y * 0.62 - look.y * 0.5)
	cam.position = Vector3(ctr.x, 0, ctr.z) + Vector3(sin(yaw), 0, cos(yaw)) * d + Vector3(0, h, 0)
	cam.look_at(ctr + Vector3(0, bx.size.y * 0.1, 0))
	if c.has("fill") and is_instance_valid(c.fill):
		var fill: OmniLight3D = c.fill
		fill.position = Vector3(ctr.x, 0, ctr.z) + Vector3(sin(yaw + 0.5), 0, cos(yaw + 0.5)) * (d * 0.45) + Vector3(0, ctr.y + bx.size.y * 0.4 + 0.6, 0)
		fill.omni_range = d * 1.6 + 2.0

## The foes of the card come forward stand as they stand in a fight (their own balance, their
## breath, a beast's restlessness); the others, once they have taken their stance, hold still.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	for j in cards.size():
		var c: Dictionary = cards[j]
		for w in c.foes:
			if not is_instance_valid(w) or w.torso == null:
				continue
			var t: float = float(w.get_meta("settle", 0.0))
			var held: bool = bool(w.get_meta("held", false))
			if t < SETTLE or (j == at and not done):
				if held:
					_hold(w, false)
				w.set_meta("settle", t + dt)
				w.control(dt, STANCE)
				# He holds his mark: a soft spring on the torso (Match's champion's).
				var d: Vector3 = (w.get_meta("anchor") as Vector3) - w.torso.global_position
				var v: Vector3 = w.torso.linear_velocity
				w.torso.apply_central_force(Vector3(d.x * 600.0 - v.x * 60.0, 0, d.z * 600.0 - v.z * 60.0) * w.torso.mass)
			elif not held:
				_hold(w, true)

## A card's foes still coming in, or taking their stance.
func _settling(c: Dictionary) -> bool:
	if world == null:
		return false
	return not bool(c.get("built", false)) or (c.foes as Array).any(func(w): return is_instance_valid(w) and not bool(w.get_meta("held", false)))

## A foe held as he stands (every part of him kept where it is), or let go again.
func _hold(w: Fighter, on: bool) -> void:
	for b in _bodies(w):
		if b is RigidBody3D:
			(b as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			(b as RigidBody3D).freeze = on
			(b as RigidBody3D).linear_velocity = Vector3.ZERO
			(b as RigidBody3D).angular_velocity = Vector3.ZERO
	w.set_meta("held", on)

func _process(dt: float) -> void:
	_t += dt
	for j in cards.size():
		var c: Dictionary = cards[j]
		c.near = move_toward(float(c.near), 1.0 if j == at else 0.0, dt * 2.2)
		c.look = (c.look as Vector2).lerp(c.look_to if c.hover else Vector2.ZERO, minf(1.0, dt * 5.0))
		# Only a card that is forward (or coming forward, or going back), pointed at, or whose foes
		# are still coming in or taking their stance is drawn every frame; the others keep their
		# last picture, their view still: one arena drawn a frame, not three.
		var live: bool = j == at or float(c.near) > 0.0 or bool(c.hover) or _settling(c)
		var vp: SubViewport = c.vp
		if live:
			c.t = float(c.get("t", 0.0)) + dt
			_place(c, float(c.t))
			if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
				vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		elif vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for k in glows.size():
		(glows[k] as Control).modulate.a = 0.75 + 0.25 * sin(_t * 9.0 + k * 2.3) * sin(_t * 5.3 + k)
	if refresh.is_valid():
		_refresh_t -= dt
		if _refresh_t <= 0.0:
			_refresh_t = 0.5
			refresh.call(self)

# ---------- Picking ----------

func _hover(i: int, on: bool) -> void:
	if i >= cards.size():
		return
	cards[i].hover = on
	if on and not done:
		_focus(i)

## Card `i` comes forward (pointed at, or picked with the keys): bigger, lit in gold, its foes
## stirring; the others a little back and darker.
func _focus(i: int, sound := true) -> void:
	if cards.is_empty() or done:
		return
	var was := at
	at = clampi(i, 0, cards.size() - 1)
	for j in cards.size():
		_style(j)
	if sound and was != at:
		Sfx.ui("tick")

func _style(j: int, tween := true) -> void:
	var c: Dictionary = cards[j]
	var lit: bool = j == at
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.088, 0.065, 0.047, 0.98) if lit else Color(0.07, 0.052, 0.038, 0.97)
	b.border_color = UIStyle.GOLD_LIGHT if lit else (c.color as Color)
	b.set_border_width_all(3 if lit else 2)
	b.set_corner_radius_all(10)
	b.shadow_color = Color(1.0, 0.76, 0.36, 0.32) if lit else Color(0, 0, 0, 0.55)
	b.shadow_size = 24 if lit else 10
	var p: PanelContainer = c.panel
	p.add_theme_stylebox_override("panel", b)
	p.z_index = 1 if lit else 0
	if c.has("go"):
		var go: Button = c.go
		if party:
			go.text = Loc.t("Your pick") if j == mine else Loc.t("Pick this fight")
		else:
			go.text = Loc.t("Fight")
		go.modulate.a = 1.0 if lit or (party and j == mine) else 0.6
	var s := 1.03 if lit else 0.975
	var v := 1.0 if lit else 0.78
	p.pivot_offset = p.size * 0.5
	if not tween or not is_inside_tree():
		p.scale = Vector2.ONE * s
		p.modulate = Color(v, v, v, p.modulate.a)
		return
	var tw := p.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "scale", Vector2.ONE * s, 0.16)
	for ch in ["r", "g", "b"]:
		tw.tween_property(p, "modulate:" + ch, v, 0.16)

## A card's button (or a double click on it): alone, through the gate to it; in a room, it is my pick.
func _press(i: int) -> void:
	if done:
		return
	_focus(i, false)
	if party:
		_vote(i)
		return
	_go(i)

## In a room: card `i` is my pick.
func _vote(i: int) -> void:
	if done or not party:
		return
	mine = clampi(i, 0, cards.size() - 1)
	for j in cards.size():
		_style(j)
	Sfx.ui("tick")
	voted.emit(mine)

## Through the gate (alone to card `i`; the host leads the party through, his own pick `i`): the
## horn, the other cards gone, the screen dark, then the fight.
func _go(i: int) -> void:
	if done or (party and not host):
		return
	if party and lead != null and lead.disabled:
		return
	if not party:
		_focus(i, false)
	done = true
	Sfx.ui("horn", 0.35)
	var to := lead_to if party and lead_to >= 0 else at
	for j in cards.size():
		var p: Control = cards[j].panel
		var tw := p.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if j == to:
			tw.tween_property(p, "scale", Vector2.ONE * 1.08, 0.4)
		else:
			tw.tween_property(p, "modulate:a", 0.0, 0.25)
	var ft := create_tween()
	ft.tween_interval(0.15)
	ft.tween_property(fade, "color:a", 1.0, 0.35)
	ft.tween_callback(func(): chosen.emit(i))

## The party's picks on their cards (`by`: names a card), and the card the host leads them to.
func set_votes(by: Array, lead_to_ := -1) -> void:
	if _votes_shown == [by, lead_to_]:
		return
	_votes_shown = [by.duplicate(true), lead_to_]
	lead_to = lead_to_
	for j in cards.size():
		var box: HFlowContainer = cards[j].chips
		for ch in box.get_children():
			ch.queue_free()
		var names: Array = by[j] if j < by.size() and by[j] is Array else []
		if j == lead_to and party:
			box.add_child(_chip(Loc.t("The party's pick"), UIStyle.GOLD_LIGHT, Color(0.42, 0.3, 0.1)))
		for n in names.slice(0, Net.CAMPAIGN_PLAYERS):
			box.add_child(_chip(String(n), UIStyle.TEXT, Color(0.18, 0.13, 0.09)))

## Back to the yard.
func close() -> void:
	if done:
		return
	done = true
	closed.emit()

func _exit_tree() -> void:
	if previews and is_instance_valid(get_viewport()):
		get_viewport().disable_3d = _was_3d_off
	if arena and is_instance_valid(arena):
		arena.crowd_mat = null   # (its going does not hush the yard's arena: Arena._exit_tree)

func _unhandled_input(e: InputEvent) -> void:
	if done:
		return
	if e.is_action_pressed("ui_left") or e.is_action_pressed("va_left"):
		_focus(at - 1)
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("va_right"):
		_focus(at + 1)
	elif (e.is_action_pressed("ui_accept") or e.is_action_pressed("va_kick")) and not e.is_echo():
		_press(at)
	elif e.is_action_pressed("ui_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()
