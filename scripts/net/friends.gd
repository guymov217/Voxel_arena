class_name Friends
extends Node
## Friends who are not there: for one person to try multiplayer by hand, a room with the others played by the game itself. The
## host's game opens other games of this project (no window, nothing on the screen), each of which joins the room by address as a
## friend would and plays one (FriendPilot: it walks the yard, goes into the stalls, fights as a bot does, picks its reward,
## votes), and the host adds a friend, sends one away or has one's connection lost, whenever he likes (FriendsStrip: three
## buttons and F6, F7, F8). The room is an ordinary ENet room; what the friends say and do is what a friend's game says and does.

const PERSONAS := [
	{"name": "Brutus", "main": "gladius", "off": "scutum", "temper": 0.5, "shops": 0.4},
	{"name": "Cassia", "main": "spear", "off": "", "temper": 0.2, "shops": 0.8},
	{"name": "Decimus", "main": "axe", "off": "", "temper": 0.8, "shops": 0.2},
	{"name": "Felix", "main": "mace", "off": "scutum", "temper": 0.6, "shops": 0.5},
	{"name": "Gaia", "main": "gladius", "off": "", "temper": 0.3, "shops": 0.6},
	{"name": "Hector", "main": "axe", "off": "scutum", "temper": 0.7, "shops": 0.3},
	{"name": "Livia", "main": "spear", "off": "scutum", "temper": 0.4, "shops": 0.7},
]
const POOR_LAG := 120        # a poor line (ms each way, percent of the unreliable packets lost): what Net.set_lag takes
const POOR_LOSS := 3
const MAX_FRIENDS := 7       # (the room has eight places and the host has one)

signal changed

var port := 0                # the room's port (0: Net.PORT)
var poor := false            # friends who come now come over a poor line
var friends: Array = []      # [{"pid", "persona", "name", "at"}]: the games started and still running

func _ready() -> void:
	set_process(true)

func _exit_tree() -> void:
	kill_all()

func _process(_dt: float) -> void:
	var gone := false
	for i in range(friends.size() - 1, -1, -1):
		if not OS.is_process_running(int(friends[i].pid)):
			friends.remove_at(i)
			gone = true
	if gone:
		changed.emit()

## How many are in, or on their way (a game started and not yet over).
func count() -> int:
	return friends.size()

func names() -> Array:
	return friends.map(func(f): return String(f.name))

## The persona the next friend has: the first of the table not in the room now.
func next_persona() -> int:
	var taken := names()
	for i in PERSONAS.size():
		if not taken.has(String(PERSONAS[i].name)):
			return i
	return friends.size() % PERSONAS.size()

## What a persona carries, bought at the smith as a player buys: his main weapon, and a shield in the off hand if he has one.
static func arms_of(persona: int) -> Dictionary:
	var p: Dictionary = PERSONAS[clampi(persona, 0, PERSONAS.size() - 1)]
	var a := Arms.empty()
	for key in [String(p.main), String(p.off)]:
		if key != "":
			var r := Arms.buy(a, key, "R", "")
			if r.has("arms"):
				a = r.arms
	return a

## The arguments of a friend's game (a static function, for the test).
static func args_for(persona: int, room_port: int, project: String, headless := true, lag := 0, loss := 0, log_file := "") -> PackedStringArray:
	var a := PackedStringArray()
	if project != "":
		a.append_array(["--path", project])
	if headless:
		a.append("--headless")
	if log_file != "":
		a.append_array(["--log-file", log_file])
	a.append_array(["--", "--friend", "--join", "127.0.0.1", "--port", str(room_port), "--persona", str(persona)])
	if lag > 0:
		a.append_array(["--lag", str(lag), "--loss", str(loss)])
	return a

## Opens a friend's game. False when the room is full or the game could not be started.
func add() -> bool:
	# (The places of the room: the host's, those of the players in it, those of friends on their way in.)
	var on_their_way := friends.filter(func(f): return peer_of(String(f.name)) < 0).size()
	if friends.size() >= MAX_FRIENDS or 1 + Net.peers.size() + on_their_way >= Net.MAX_PLAYERS:
		return false
	var persona := next_persona()
	var proj := "" if OS.has_feature("template") else ProjectSettings.globalize_path("res://").trim_suffix("/")
	var logf := ProjectSettings.globalize_path("user://friend_%s.log" % String(PERSONAS[persona].name).to_lower())
	var pid := OS.create_process(OS.get_executable_path(), args_for(persona, port if port > 0 else Net.PORT, proj, true, POOR_LAG if poor else 0, POOR_LOSS if poor else 0, logf))
	if pid <= 0:
		return false
	friends.append({"pid": pid, "persona": persona, "name": String(PERSONAS[persona].name), "at": Time.get_ticks_msec()})
	changed.emit()
	return true

## The newest friend's peer id in the room, or -1 (the room knows him by his name once he has said hello).
func peer_of(name: String) -> int:
	for id in Net.peers:
		if String(Net.peers[id].get("name", "")) == name:
			return int(id)
	return -1

## The newest friend goes: he is asked to leave and does, as one who says goodbye (he leaves the room and closes). One whose
## game has not got as far as the room is simply closed.
func leave_one() -> bool:
	if friends.is_empty():
		return false
	var f: Dictionary = friends[friends.size() - 1]
	var id := peer_of(String(f.name))
	if id >= 0:
		Net.send_to(id, "friend_cmd", "leave")
	else:
		OS.kill(int(f.pid))
	return true

## The newest friend's connection is lost: his game is stopped at once, without a word, as a game that crashes or a line that
## goes. The room finds him gone after the connection's timeout.
func drop_one() -> bool:
	if friends.is_empty():
		return false
	var f: Dictionary = friends[friends.size() - 1]
	OS.kill(int(f.pid))
	return true

func kill_all() -> void:
	for f in friends:
		OS.kill(int(f.pid))
	friends.clear()
