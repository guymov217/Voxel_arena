class_name VoiceChat
extends Node
## Proximity voice chat: hold the talk key and the microphone goes to everyone in the room, each
## hearing you from where your gladiator stands (an AudioStreamPlayer3D at his head: near, loud;
## across the arena, faint; behind the wall of the yard, gone). The sound is plain 16-bit PCM at
## VOICE_RATE, in short packets over the unreliable channel; the host relays a guest's packets to
## the other guests. No codec to ship: ~22 KB/s a talker.

const VOICE_RATE := 11025
const MAX_DIST := 22.0
const PACKET_FRAMES := 441   # 40 ms

var menu = null               # the Menu, for the match of the moment
var talking := false
var capture: AudioEffectCapture = null
var mic: AudioStreamPlayer = null
var players := {}             # peer id -> AudioStreamPlayer3D
var factor := 4
var _acc := PackedVector2Array()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	Net.message.connect(_on_net)
	Net.peer_left.connect(func(id): _drop(int(id)))
	factor = maxi(1, roundi(AudioServer.get_mix_rate() / float(VOICE_RATE)))

## The microphone is opened only when first spoken into (it needs audio input on in the project;
## opening it costs a little and asks the OS).
func _open_mic() -> bool:
	if capture != null:
		return true
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		return false
	if AudioServer.get_bus_index("Mic") < 0:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, "Mic")
		AudioServer.set_bus_mute(b, true)   # heard by the others, never by yourself
		capture = AudioEffectCapture.new()
		capture.buffer_length = 0.5
		AudioServer.add_bus_effect(b, capture)
	else:
		capture = AudioServer.get_bus_effect(AudioServer.get_bus_index("Mic"), 0) as AudioEffectCapture
	mic = AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = "Mic"
	add_child(mic)
	mic.play()
	return capture != null

func _process(_dt: float) -> void:
	var want: bool = Net.active() and InputMap.has_action("va_talk") and Input.is_action_pressed("va_talk") and menu != null and menu.match_ != null
	if want and not talking:
		talking = _open_mic()
		if capture:
			capture.clear_buffer()
	elif not want and talking:
		talking = false
	if talking and capture:
		var n := capture.get_frames_available()
		if n > 0:
			_acc.append_array(capture.get_buffer(n))
		var need := PACKET_FRAMES * factor
		while _acc.size() >= need:
			var chunk := _acc.slice(0, need)
			_acc = _acc.slice(need)
			Net.send_all("vc", encode(chunk, factor), false)
	_place()

## Mixes the stereo capture to mono, takes every `factor`th sample (averaged), and packs 16-bit.
static func encode(frames: PackedVector2Array, factor_: int) -> PackedByteArray:
	var n := frames.size() / factor_
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		var v := 0.0
		for k in factor_:
			var f := frames[i * factor_ + k]
			v += (f.x + f.y) * 0.5
		v /= factor_
		out.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	return out

static func decode(bytes: PackedByteArray) -> PackedVector2Array:
	var n := bytes.size() / 2
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var v := bytes.decode_s16(i * 2) / 32000.0
		out[i] = Vector2(v, v)
	return out

func _on_net(type: String, data, from: int) -> void:
	if type != "vc":
		return
	var who := from
	var bytes = data
	if data is Dictionary:
		who = int(data.get("f", from))
		bytes = data.get("d")
	if not (bytes is PackedByteArray) or bytes.size() > PACKET_FRAMES * 4 or who == Net.my_id():
		return
	var p := _player_for(who)
	if p == null:
		return
	var gen := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if gen == null:
		return
	var frames := decode(bytes)
	if gen.get_frames_available() >= frames.size():
		gen.push_buffer(frames)

## The speaker's player, made when first heard, under the match so it sits in the world.
func _player_for(id: int) -> AudioStreamPlayer3D:
	var p = players.get(id)
	if p != null and is_instance_valid(p):
		return p
	if menu == null or menu.match_ == null or not is_instance_valid(menu.match_):
		return null
	p = AudioStreamPlayer3D.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = VOICE_RATE
	g.buffer_length = 0.3
	p.stream = g
	p.max_distance = MAX_DIST
	p.unit_size = 3.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.bus = "SFX"
	menu.match_.add_child(p)
	p.play()
	players[id] = p
	return p

func _drop(id: int) -> void:
	var p = players.get(id)
	if p != null and is_instance_valid(p):
		p.queue_free()
	players.erase(id)

## Every voice from its gladiator's head (a player without one yet speaks from the gate).
func _place() -> void:
	if menu == null or menu.match_ == null or not is_instance_valid(menu.match_):
		for id in players.keys():
			_drop(id)
		return
	var m = menu.match_
	for id in players:
		var p: AudioStreamPlayer3D = players[id]
		if not is_instance_valid(p):
			continue
		var at := Vector3(0, 1.6, Arena.RADIUS - 2.0)
		for e in m.entities:
			if int(e.get("peer", -1)) == id and is_instance_valid(e.f):
				at = e.f.head.global_position if not e.f.head.severed else e.f.torso.global_position
				break
		p.global_position = at
