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
