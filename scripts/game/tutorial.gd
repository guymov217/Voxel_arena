class_name Tutorial
extends RefCounted
## The tutorial: every key of the fight in a short step of its own, each done the moment the
## player has done it once (no walls of text; the few pages to read turn by themselves), a dummy
## to practise on, then a real recruit to beat. After him the menu takes the player on to the
## forge's own lesson (ForgeLesson). The keys in the texts are the player's own bindings. It
## measures what the player did from his fighter and his input; Match plays it in training mode
## and the HUD shows the step.

## A step: its title, what to do in it with the player's keys (`keys`, bindings) and mouse buttons
## (`mouse`: "main" swings the sword, "off" the shield; left-handed, the other way round) put into
## its text in that order, and for a page to read, how long it stays up (s).
const STEPS := [
	{"id": "move", "title": "Walk", "text": "%s %s %s %s to walk, hold %s to run. Take a few steps.", "keys": ["forward", "left", "back", "right", "sprint"]},
	{"id": "look", "title": "Look", "text": "Move the mouse with no button held to look around. Look all the way round."},
	{"id": "jump", "title": "Jump and crouch", "text": "%s jumps (and struggles free when someone holds you); hold %s to crouch. Do both.", "keys": ["jump", "crouch"]},
	{"id": "freelook", "title": "Look round you", "text": "Hold the middle button and move the mouse: the view goes round you while you stand still. Let go and it swings back."},
	{"id": "swing", "title": "Swing", "text": "Hold the %s button and sweep the mouse: the sword follows your hand. Hit the dummy twice. Fast sweeps cut deep.", "mouse": ["main"]},
	{"id": "twist", "title": "Turn the blade", "text": "Roll the wheel: the sword turns in your hand, so the edge leads the cut and not the flat. Roll it a few notches."},
	{"id": "thrust", "title": "Thrust", "text": "Hold %s and push the mouse forward: the blade drives straight out; pull back and it comes in. Drive it all the way out.", "keys": ["thrust"]},
	{"id": "guard", "title": "Guard", "text": "Hold the %s button: now the mouse moves the shield. Raise it up for a moment.", "mouse": ["off"]},
	{"id": "kick", "title": "Kick and shove", "text": "%s kicks (and stamps on a man who is down), %s shoves. Kick or shove the dummy.", "keys": ["kick", "shove"]},
	{"id": "swap", "title": "Swap hands", "text": "%s swaps what your hands hold: the sword to the left, the shield to the right. Swap, then swap back.", "keys": ["swap"]},
	{"id": "throw", "title": "Throw", "text": "Hold %s to aim, let go to throw: the right hand first, then the left. Throw the sword, then the shield, at the dummy.", "keys": ["throw"]},
	{"id": "fists", "title": "Fists", "text": "With empty hands you box: the fists come up in a guard. Hold a button and sweep, as with the sword: punch the dummy twice."},
	{"id": "grab", "title": "Grab", "text": "By the dummy, hold a mouse button and press %s: that hand takes hold of him (both buttons, both hands). %s throws him, %s again lets go. Take hold of him.", "keys": ["grab", "throw", "grab"]},
	{"id": "pickup", "title": "Pick up", "text": "A longsword lies by you: walk over and press %s to pick it up.", "keys": ["grab"], "setup": "longsword"},
	{"id": "both", "title": "Both hands", "text": "%s puts both hands on the hilt: slower to start, much more behind each blow; again, and one hand lets go. Take it in both hands.", "keys": ["grip"]},
	{"id": "items", "title": "Your kit", "text": "The number keys take up what is in your kit, the slots at the bottom: press 1 for the sand pot, then %s throws it at the dummy. The market sells pots for the campaign.", "keys": ["throw"], "setup": "pot"},
	{"id": "crowd", "title": "The crowd", "text": "%s taunts the crowd, %s strikes a pose: the crowd loves a show. Do one.", "keys": ["taunt", "emote"]},
	{"id": "keys", "title": "More keys", "read": 12.0, "text": "Hold %s to play dead. Hold %s by a fallen friend to lift him. With friends in a room, hold %s to talk. %s starts the round again. Esc pauses; the options change any key.", "keys": ["limp", "revive", "talk", "restart"]},
	{"id": "body", "title": "Blood and breath", "read": 10.0, "text": "Two bars: your blood (wounds bleed until they close; a cut artery spurts) and your breath (every hard stroke costs some; out of breath you are slower and weaker). The figure shows every wound and every piece you have lost."},
	{"id": "yard", "title": "The yard", "read": 10.0, "text": "Between bouts the yard has the smith (weapons and armour, both mended there as they wear), the market (pots, the Hand of Jupiter: twice a bout, it holds a man where you look, the wheel draws him in, F hurls him), the physician for your wounds, and the trainer: strength, blow, wind, hide, blood and footing, a session at a time, no further than the bouts you have won."},
	{"id": "fight", "title": "A real fight", "text": "A recruit steps in, and he fights back. Beat him. (You cannot die in here.)", "setup": "fight"},
]
const POT := "sandPot"   # the kit's step: a pot that blinds, and hurts nobody

var m: Node
var i := 0
var s := {"moved": 0.0, "turned": 0.0, "jumps": 0, "crouch_t": 0.0, "free_t": 0.0, "twisted": 0.0, "depth": 0.0, "pad_thrust": 0.0,
	"hits": 0, "guard_t": 0.0, "kicks": 0, "swaps": 0, "throws": 0, "punches": 0, "shows": 0, "armed": true, "won": false, "read_t": 0.0}
var ok_t := 0.0
var finished := false
var setup_done := {}
var last_pos = null
var last_yaw = null
var last_twist = null
var had_weapon := true
var sword = null        # what the right hand held when the swap step began (it must end there again)
var dummy = null
var recruit = null

func _init(match_: Node) -> void:
	m = match_

func step() -> Dictionary:
	return STEPS[i] if i < STEPS.size() else {}

## How one of the player's keys reads ("W", "Space"): his own binding, else the default.
static func key_label(id: String) -> String:
	var b = Save.get_value("settings", {}).get("bindings", {})
	var code := str(b.get(id, "")) if b is Dictionary else ""
	if code == "":
		code = str(Data.controls.get("defaults", {}).get(id, ""))
	return PlayerInput.label_of(code)

## A step's text in the player's language, his keys and buttons put in.
func text_of(st: Dictionary) -> String:
	var args := []
	for k in st.get("keys", []):
		args.append(key_label(String(k)))
	var lefty: bool = m.input != null and m.input.left_handed
	for b in st.get("mouse", []):
		args.append(Loc.t("LEFT" if (b == "main") != lefty else "RIGHT"))
	var tx := Loc.t(String(st.text))
	return tx % args if not args.is_empty() else tx

## What the HUD shows now.
func view() -> Dictionary:
	if finished or i >= STEPS.size():
		return {"done": true, "title": "You are ready", "text": Loc.t("Next, the forge: how to make a weapon of your own."), "step": STEPS.size(), "total": STEPS.size(), "ok": true}
	var st := step()
	return {"title": st.title, "text": text_of(st), "step": i, "total": STEPS.size(), "ok": ok_t > 0.0}

func setup() -> void:
	var e = m.spawn_fighter({"kind": "npc", "name": Loc.t("Training dummy"), "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM,
		"pos": Vector3(0, 0.02, -3.6), "yaw": 0.0, "mods": {"toughness": 3.0}, "color": 0xb08a5a})
	e.drive = func(_e): return {}
	e.harmless = true
	dummy = e.f

func _done(id: String, f: Fighter) -> bool:
	if step().has("read"):
		return float(s.read_t) >= float(step().read)   # a page to read: it turns by itself
	match id:
		"move": return s.moved > 2.5
		"look": return s.turned > 2.2
		"jump": return int(s.jumps) >= 1 and float(s.crouch_t) > 0.3
		"freelook": return float(s.free_t) > 0.5
		"swing": return s.hits >= 2
		"twist": return float(s.twisted) > 0.7
		"thrust": return float(s.depth) > 0.6 or float(s.pad_thrust) > 0.6
		"guard": return s.guard_t > 0.8
		"kick": return s.kicks >= 1
		"swap": return int(s.swaps) >= 2 and sword != null and f.weapons.get("R") == sword
		"throw": return f.weapons.get("R") == null and f.weapons.get("L") == null
		"fists": return int(s.punches) >= 2
		"grab": return f.holding != null and f.holding.get("target") is Dictionary and f.holding.target.get("f") == dummy
		"pickup": return f.weapons.get("R") != null or f.weapons.get("L") != null
		"both": return f.two_handed
		"items": return setup_done.has("items") and int(m.me.get("inventory", {}).get(POT, 0)) <= 0
		"crowd": return int(s.shows) >= 1
		"fight": return s.won
	return false

## A step begins: what it is measured from.
func _begin(id: String, f: Fighter) -> void:
	match id:
		"swap":
			s.swaps = 0
			sword = f.weapons.get("R")
		"fists":
			s.punches = 0

func update(dt: float, inp: Dictionary) -> void:
	if finished or m.me == null:
		return
	var f: Fighter = m.me.f
	# Nobody dies in the training ring: the player and the dummy are patched up as they go.
	f.blood = maxf(f.blood, 60.0)
	if dummy and is_instance_valid(dummy):
		dummy.blood = 100.0
	var p := f.torso.global_position
	if last_pos != null:
		s.moved = float(s.moved) + Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
	last_pos = p
	if inp.get("look") is Dictionary:
		var yaw := float(inp.look.yaw)
		if last_yaw != null:
			s.turned = float(s.turned) + absf(wrapf(yaw - float(last_yaw), -PI, PI))
		last_yaw = yaw
	if inp.get("jump", false):
		s.jumps = int(s.jumps) + 1
	if inp.get("crouch", false):
		s.crouch_t = float(s.crouch_t) + dt
	if m.input != null and (m.input.free_look as Vector2).length() > 0.35:
		s.free_t = float(s.free_t) + dt
	if inp.has("twist"):
		var tw := float(inp.twist)
		if last_twist != null:
			s.twisted = float(s.twisted) + absf(wrapf(tw - float(last_twist), -PI, PI))
		last_twist = tw
	if inp.get("depthOn", false):
		s.depth = maxf(float(s.depth), float(inp.get("depth", 0.0)))
	elif float(inp.get("thrust", 0.0)) > 0.5:
		s.pad_thrust = float(s.pad_thrust) + dt   # (a pad's thrust drives itself out)
	var off: Dictionary = inp.get("off", {}) if inp.get("off") is Dictionary else {}
	if inp.get("power", false) and inp.get("grabHands", null) == "L" and float(off.get("y", 0.0)) > 0.35:
		s.guard_t = float(s.guard_t) + dt
	if (inp.get("kick", false) or inp.get("shove", false)) and dummy and is_instance_valid(dummy) and p.distance_to(dummy.torso.global_position) < 2.2:
		s.kicks = int(s.kicks) + 1
	if inp.get("swap", false):
		s.swaps = int(s.swaps) + 1
	if inp.get("taunt", false) or inp.get("emote", false):
		s.shows = int(s.shows) + 1
	var armed: bool = f.weapons.get("R") != null
	if had_weapon and not armed:
		s.throws = int(s.throws) + 1
	had_weapon = armed
	s.armed = armed
	if recruit and is_instance_valid(recruit) and not recruit.alive:
		s.won = true
	if ok_t > 0.0:
		ok_t -= dt
		if ok_t <= 0.0:
			i += 1
			s.read_t = 0.0
			if i >= STEPS.size():
				finished = true
			else:
				_begin(String(step().id), f)
		return
	var st := step()
	s.read_t = float(s.read_t) + dt
	if st.has("setup") and not setup_done.has(st.id):
		setup_done[st.id] = true
		_setup(String(st.setup))
	if _done(String(st.id), f):
		ok_t = 0.9
		m.sfx("bell", p, 0.5)

func _setup(what: String) -> void:
	var f: Fighter = m.me.f
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	match what:
		"longsword":
			m.spawn_loose_weapon(Data.preset("longsword"), f.torso.global_position + fwd.rotated(Vector3.UP, 0.8) * 1.3 + Vector3(0, 0.3, 0))
		"pot":
			var kit: Dictionary = m.me.get("inventory", {})
			kit[POT] = 1
			m.me.inventory = kit
		"fight":
			var spec: Dictionary = m.enemy_spec({"e": "recruit"}, 0, 1)
			spec.pos = Vector3(0, 0.05, 5.0)
			spec.diff = 0.45
			recruit = m.spawn_fighter(spec).f
			if dummy and is_instance_valid(dummy):
				dummy.die("retired")

func on_hit(h: Dictionary) -> void:
	if m.me and h.get("attacker") == m.me.f and h.get("char") == dummy and float(h.get("J", 0.0)) > 2.0:
		s.hits = int(s.hits) + 1
		var f: Fighter = m.me.f
		if String(step().get("id", "")) == "fists" and f.weapons.get("R") == null and f.weapons.get("L") == null:
			s.punches = int(s.punches) + 1
