class_name FriendPilot
extends Node
## A friend who is not there: this game (opened by the host's Friends, `-- --friend --join 127.0.0.1 --port N --persona I`) joins the
## room by address as any friend's game does, through the game's own screens and messages, and plays a friend: in the yard he
## wanders, goes up to the stalls and into them, now and then picks a quarrel with whoever is near; in a fight a bot plays his
## fighter; the rewards, the rudis and the forge's ready he answers as a person does, after a moment's thought. Told to leave
## he says goodbye (leaves the room, closes); his room gone, he closes by himself. What he does is only what a player's hands
## and the game's own calls do, so that what the host sees is what a friend's game would show him.

const STALLS := ["smith", "market", "trainer", "physician"]
const HANDS := {"main": {"x": 0.1, "y": 0.15}, "off": {"x": -0.35, "y": 0.1}}
const ROOM_GONE_S := 6.0      # his room closed: he closes after this long
const NEVER_JOINED_S := 90.0  # no room to be found: he closes after this long
const MENU_STUCK_S := 25.0    # a screen of the game open this long over the yard that he did not open: he closes it

var menu: Node
var persona: Dictionary = {}
var persona_index := 0
var address := "127.0.0.1"
var room_port := 0

var state := "idle"           # idle | walk | stall | brawl
var target := Vector3.ZERO
var stall := ""
var victim = null
var _act_t := 2.0
var _stall_t := 0.0
var _think_t := 0.0
var _join_t := 0.0
var _offline_t := 0.0
var _joined := false
var _stuck := 0
var _last_pos := Vector3.ZERO
var _wait := {}               # a prompt -> how long before he answers it
var _menu_t := 0.0
var _leaving := false
var _quarrel_now := false

func setup(menu_: Node, persona_index_: int, addr: String, port: int) -> void:
	menu = menu_
	persona_index = clampi(persona_index_, 0, Friends.PERSONAS.size() - 1)
	persona = Friends.PERSONAS[persona_index]
	address = addr
	room_port = port

func _ready() -> void:
	Engine.max_fps = 60   # (a game without a window runs as fast as it can else, and a game of it a core)
	Net.message.connect(_on_message)
	# The room says what it is for (an Arena room gives him a sandbox gladiator of its own, Menu): he puts on what is his again.
	Net.room_kind_known.connect(func(_kind): menu.set_arms(Friends.arms_of(persona_index)))
	_act_t = randf_range(1.5, 4.0)

## What the host's Friends tells him: "leave", or (the test's) "stall[:smith]" to go into a stall now, "brawl" to pick a quarrel now.
func _on_message(type: String, data, _from: int) -> void:
	if type != "friend_cmd":
		return
	var cmd := String(data)
	if cmd == "leave":
		_leave()
	elif cmd.begins_with("stall"):
		var s := cmd.get_slice(":", 1) if cmd.contains(":") else String(STALLS[randi() % STALLS.size()])
		if Yard.STATIONS.has(s):
			stall = s
			var p: Vector3 = Yard.STATIONS[s].p
			target = p - p.normalized() * 1.6
			state = "walk"
			_act_t = 40.0
	elif cmd == "brawl":
		_act_t = 0.0
		_quarrel_now = true

## Says goodbye: out of the room (the host sees him go), then closes.
func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if menu.get("match_") != null and is_instance_valid(menu.match_):
		menu.match_.probe_input = {}
	Net.leave()
	get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit())

func _process(dt: float) -> void:
	if _leaving:
		return
	if not Net.active():
		_offline(dt)
		return
	_joined = true
	_offline_t = 0.0
	_prompts(dt)
	var m = menu.match_ if menu.get("match_") != null and is_instance_valid(menu.match_) else null
	if m == null or m.me == null or not is_instance_valid(m.me.f):
		return
	if menu.in_yard():
		_yard(dt, m)
	else:
		# A fight: a bot plays his fighter.
		m.guest_bot_on = true
		m.guest_bot_target = null
		m.probe_input = {}
		state = "idle"
		_act_t = randf_range(2.0, 5.0)
		_menu_t = 0.0

# ---------- Getting into the room, and out of it ----------

func _offline(dt: float) -> void:
	_offline_t += dt
	_join_t -= dt
	if not _joined:
		if _join_t <= 0.0:
			_join_t = 4.0
			Net.leave()
			Net.join_enet(address, room_port if room_port > 0 else Net.PORT)
		if _offline_t > NEVER_JOINED_S:
			get_tree().quit(1)
	elif _offline_t > ROOM_GONE_S:
		get_tree().quit()

# ---------- What he answers ----------

## True once he has waited out a moment of thought (random between `lo` and `hi` s) over `key`.
func _later(key: String, dt: float, lo: float, hi: float) -> bool:
	if not _wait.has(key):
		_wait[key] = randf_range(lo, hi)
	_wait[key] = float(_wait[key]) - dt
	if float(_wait[key]) <= 0.0:
		_wait.erase(key)
		return true
	return false

func _prompts(dt: float) -> void:
	# The endless arena's rewards: cards, one of which he picks.
	var el = menu.get("endless_layer")
	if el != null and is_instance_valid(el):
		if _later("endless", dt, 1.0, 3.5):
			var cards: Array = (el as Node).find_children("*", "Button", true, false)
			if not cards.is_empty():
				(cards[randi() % cards.size()] as Button).pressed.emit()
	else:
		_wait.erase("endless")
	# The one rudis: share the glory or fight for it.
	if String(menu.get("screen")) == "rudis" and String(menu.get("rudis_mine")) == "":
		if _later("rudis", dt, 1.5, 5.0):
			menu._rudis_vote("share" if randf() < 0.7 else "fight")
	else:
		_wait.erase("rudis")
	# Forge and Fight: ready, with what he has.
	var ff = menu.get("ff")
	if ff is Dictionary and not (ff as Dictionary).is_empty() and String(menu.get("screen")) == "ff_contest" and not bool((ff as Dictionary).get("ready", false)):
		if _later("ff", dt, 3.0, 8.0):
			menu._ff_ready(true)
	else:
		_wait.erase("ff")
	# The gate's cards (a campaign room): a card is his pick.
	var gs = menu.get("gate_screen")
	if gs != null and is_instance_valid(gs):
		if _later("gate", dt, 1.5, 4.0) and not (gs.cards as Array).is_empty():
			gs._vote(randi() % (gs.cards as Array).size())
	else:
		_wait.erase("gate")

# ---------- The yard ----------

func _hands(mx: float, mz: float, yaw: float, run := false) -> Dictionary:
	return {"mx": mx, "mz": mz, "look": {"yaw": yaw, "pitch": 0.0}, "sprint": run, "main": HANDS.main, "off": HANDS.off}

func _yard(dt: float, m) -> void:
	var f: Fighter = m.me.f
	m.guest_bot_on = state == "brawl"
	m.guest_bot_target = victim if state == "brawl" else null
	if not f.alive:
		m.probe_input = {}
		return
	var here := f.torso.global_position
	# A screen of the game over the yard: a stall he went into, or one he did not open and leaves after a while.
	if menu.visible:
		m.probe_input = _hands(0.0, 0.0, f.yaw)
		_menu_t += dt
		if state == "stall":
			_stall_t -= dt
			if _stall_t <= 0.0:
				_leave_stall()
		elif _menu_t > MENU_STUCK_S:
			menu._close_overlay()
			_menu_t = 0.0
		return
	_menu_t = 0.0
	if state == "stall":
		state = "idle"   # (its screen closed by itself)
		_act_t = randf_range(1.0, 3.0)
	_act_t -= dt
	_think_t += dt
	match state:
		"idle":
			m.probe_input = _hands(0.0, 0.0, f.yaw)
			if _act_t <= 0.0:
				_choose(m)
		"walk":
			var d := Vector2(target.x - here.x, target.z - here.z)
			var near := 2.0 if stall != "" else 1.0
			if d.length() < near:
				if stall != "":
					_enter_stall()
				else:
					state = "idle"
					_act_t = randf_range(1.5, 6.0)
				return
			m.probe_input = _hands(0.0, 1.0, atan2(d.x, d.y), d.length() > 9.0)
			if _act_t <= 0.0:
				state = "idle"
				_act_t = 0.5
			# (Stuck on something in the way: another way.)
			if _think_t >= 1.0:
				_think_t = 0.0
				if (here - _last_pos).length() < 0.25:
					_stuck += 1
					if _stuck >= 2:
						_stuck = 0
						state = "idle"
						stall = ""
						_act_t = 0.1
				else:
					_stuck = 0
				_last_pos = here
		"brawl":
			m.probe_input = {}
			if _act_t <= 0.0 or victim == null or not is_instance_valid(victim.f) or not victim.f.alive:
				victim = null
				state = "idle"
				_act_t = randf_range(3.0, 8.0)

## What he does next: a quarrel with one of the others, a stall, the gate (a campaign room), or a stroll.
func _choose(m) -> void:
	var others: Array = m.humans().filter(func(e): return not is_same(e, m.me) and is_instance_valid(e.f) and e.f.alive)
	var r := 0.0 if _quarrel_now else randf()
	_quarrel_now = false
	var temper := float(persona.get("temper", 0.5))
	var shops := float(persona.get("shops", 0.5))
	if (r < temper * 0.2 or r == 0.0) and not others.is_empty():
		var here: Vector3 = m.me.f.torso.global_position
		others.sort_custom(func(a, b): return a.f.torso.global_position.distance_to(here) < b.f.torso.global_position.distance_to(here))
		victim = others[0]
		state = "brawl"
		_act_t = randf_range(5.0, 10.0)
		return
	if r < temper * 0.2 + shops * 0.35:
		var options := STALLS.duplicate()
		if Net.room_kind == Net.KIND_CAMPAIGN:
			options.append("gate")
		stall = String(options[randi() % options.size()])
		var p: Vector3 = Yard.STATIONS[stall].p
		target = p - p.normalized() * 1.6
		state = "walk"
		_act_t = 30.0
		return
	stall = ""
	for i in 12:
		target = Vector3(randf_range(-11.0, 11.0), 0.0, randf_range(-8.0, 9.0))
		var clear := true
		for dm in Yard.DUMMIES:
			if Vector2(target.x - dm.x, target.z - dm.z).length() < 2.5:
				clear = false
		if clear:
			break
	state = "walk"
	_act_t = 25.0

func _enter_stall() -> void:
	_stall_t = randf_range(4.0, 9.0)
	menu._open_station(stall)
	if not menu.visible:
		state = "idle"
		stall = ""
		_act_t = randf_range(2.0, 5.0)
		return
	state = "stall"
	# At the smith of an Arena room (money is no object there) he sometimes swaps what he carries for another weapon.
	if stall == "smith" and Net.room_kind == Net.KIND_ARENA and randf() < 0.5:
		var bases := Arms.bases().filter(func(b): return String(b.slot) == "main")
		if not bases.is_empty():
			var r := Arms.buy(menu.arms(), String(bases[randi() % bases.size()].key), "R", "")
			if r.has("arms"):
				menu.set_arms(r.arms)

func _leave_stall() -> void:
	menu._close_overlay()
	state = "idle"
	stall = ""
	_act_t = randf_range(2.0, 5.0)
