extends Node
## The procedural music (music.js): every state renders a loop of the right length that is not
## silence, and the tunes keep to the scale.

var t

func test_every_state_renders_a_loop() -> void:
	for s in Music.STATES:
		var t0 := Time.get_ticks_msec()
		var w := Music.render(s)
		var st: Dictionary = Music.STATES[s]
		var want := int(int(st.bars) * 16 * (60.0 / float(st.bpm) / 4.0) * Music.RATE)
		t.eq(w.data.size(), want * 2, "%s: the length of its bars" % s)
		var peak := 0
		for i in range(0, w.data.size(), 200):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		t.check(peak > 2000 and peak < 32000, "%s: music, not silence and not clipping (peak %d, %d ms)" % [s, peak, Time.get_ticks_msec() - t0])
		t.eq(w.loop_mode == AudioStreamWAV.LOOP_FORWARD, not st.get("once", false), "%s: loops unless it is a fanfare" % s)

func test_the_melody_keeps_to_the_scale() -> void:
	var notes := Music.phrase(3, 0.5)
	t.check(notes.size() >= 3, "a phrase has notes")
	t.check(notes[notes.size() - 1].deg == 0 or notes[notes.size() - 1].deg == 4, "it lands on the root or the fifth")
	t.check(absf(Music.hz(0) - Music.ROOT) < 0.01 and absf(Music.hz(7) - Music.ROOT * 2.0) < 0.01, "the octave doubles")

## The loop comes round with no jump (what rings past its end goes on at its start), and two
## quick changes of state never leave two loops playing over each other.
func test_one_seamless_loop_at_a_time() -> void:
	var w := Music.render("fight")
	var n := w.data.size() / 2
	var seam := absi(w.data.decode_s16((n - 1) * 2) - w.data.decode_s16(0))
	t.check(seam < 6000, "no jump where the loop comes round (%d)" % seam)
	var mu := Music.new()
	add_child(mu)
	var other := Music.render("menu")
	mu._fade_to(w)
	await get_tree().create_timer(0.3).timeout
	mu._fade_to(other)
	await get_tree().create_timer(0.2).timeout
	mu._fade_to(w)
	await get_tree().create_timer(2.0).timeout
	var on := mu.players.filter(func(p): return p.playing)
	t.eq(on.size(), 1, "one loop playing after quick changes")
	mu.queue_free()
