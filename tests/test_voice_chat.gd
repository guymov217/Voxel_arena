extends Node
## Proximity voice chat: the packet codec round-trips, and the talk key is bound.

var t

func test_voice_packets_round_trip() -> void:
	var frames := PackedVector2Array()
	for i in VoiceChat.PACKET_FRAMES * 4:
		var v := 0.5 * sin(TAU * 440.0 * i / 44100.0)
		frames.append(Vector2(v, v))
	var bytes := VoiceChat.encode(frames, 4)
	t.eq(bytes.size(), VoiceChat.PACKET_FRAMES * 2, "a 40 ms packet is %d bytes" % (VoiceChat.PACKET_FRAMES * 2))
	var back := VoiceChat.decode(bytes)
	t.eq(back.size(), VoiceChat.PACKET_FRAMES, "and decodes to its frames")
	var err := 0.0
	var peak := 0.0
	for i in back.size():
		err = maxf(err, absf(back[i].x - frames[i * 4].x))
		peak = maxf(peak, absf(back[i].x))
	t.check(peak > 0.4, "the voice comes through (peak %.2f)" % peak)
	t.check(err < 0.12, "close to what went in (worst %.3f)" % err)

func test_the_talk_key_is_bound() -> void:
	var pi := PlayerInput.new()
	add_child(pi)
	t.check(InputMap.has_action("va_talk"), "va_talk is an action")
	t.eq(String(Data.controls.defaults.get("talk", "")), "KeyN", "N talks")
	pi.queue_free()

## A man talking opens his mouth as loud as he talks, and shuts it on his own face again (what
## blood put on it meanwhile stays).
func test_the_mouth_opens_with_the_voice() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var f: Fighter = m.me.f
	var head: VoxelPart = f.head
	var at := {}
	for i in head.fx.size():
		if head.fz[i] == head.grid.z - 1:
			at[Vector2i(head.fx[i], head.fy[i])] = i
	var before := {}
	for k in at:
		before[k] = head.colors[at[k]]
	Physique.talk(f, 3)
	t.eq(head.colors[at[Vector2i(4, 2)]], Physique.MOUTH, "wide open: the mouth dark")
	t.eq(head.colors[at[Vector2i(4, 1)]], Physique.TONGUE, "the tongue in it")
	t.eq(head.colors[at[Vector2i(4, 3)]], Physique.WHITE, "the teeth over it")
	Physique.talk(f, 1)
	t.eq(head.colors[at[Vector2i(4, 2)]], Physique.MOUTH, "a crack: still dark in the middle")
	t.eq(head.colors[at[Vector2i(4, 3)]], before[Vector2i(4, 3)], "the teeth gone again")
	Physique.talk(f, 0)
	var same := true
	for k in at:
		same = same and head.colors[at[k]] == before[k]
	t.check(same, "shut: his own face again, voxel for voxel")
	Physique.talk(f, 2)
	var blood := Color(0.5, 0.02, 0.02)
	head.colors[at[Vector2i(3, 2)]] = blood
	Physique.talk(f, 0)
	t.eq(head.colors[at[Vector2i(3, 2)]], blood, "blood that came while he talked stays")
	t.eq(head.colors[at[Vector2i(4, 2)]], before[Vector2i(4, 2)], "the rest of the mouth shut")
	f.die("wounds")
	Physique.talk(f, 3)
	t.eq(int(head.get_meta("talk_state", 0)), 0, "a dead man's mouth stays shut")
	m.queue_free()

## The mouth follows the voice: shut in a whisper, wider the louder (against the talker's own
## loud, each microphone is its own), and shuts again when he stops.
func test_the_mouth_follows_the_voice() -> void:
	t.eq(VoiceChat.mouth_state(0.0, 0.3), 0, "silence: shut")
	t.eq(VoiceChat.mouth_state(0.06, 0.3), 1, "softly: a crack")
	t.eq(VoiceChat.mouth_state(0.15, 0.3), 2, "talking: open")
	t.eq(VoiceChat.mouth_state(0.28, 0.3), 3, "loud: wide")
	t.eq(VoiceChat.mouth_state(0.05, 0.05), 3, "a quiet microphone still opens it wide at its loudest")
	var frames := PackedVector2Array()
	for i in 441:
		var v := 0.5 * sin(TAU * 300.0 * i / 11025.0)
		frames.append(Vector2(v, v))
	t.check(absf(VoiceChat.rms(frames) - 0.354) < 0.02, "a half-scale tone measures as one (%.3f)" % VoiceChat.rms(frames))
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var vc := VoiceChat.new()
	add_child(vc)
	vc.menu = {"match_": m}
	var head: VoxelPart = m.me.f.head
	vc.heard(Net.my_id(), 0.3, Time.get_ticks_msec())
	vc.animate(1.0 / 60.0)
	t.eq(int(head.get_meta("talk_state", 0)), 3, "his voice: his mouth wide")
	vc.heard(Net.my_id(), 0.3, Time.get_ticks_msec() + 100000)
	vc.animate(1.0 / 60.0)
	t.check(int(head.get_meta("talk_state", 0)) >= 2, "what has not reached the ears yet does not move it (still open from before)")
	for i in 60:
		vc.animate(1.0 / 60.0)
	t.eq(int(head.get_meta("talk_state", 0)), 0, "a second of silence after: shut")
	vc.queue_free()
	m.queue_free()
