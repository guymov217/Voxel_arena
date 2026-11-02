extends Node
## The procedural music (music.js): every piece renders a loop of the right length that is not
## silence, the tunes keep to their scales, and each moment of the game has pieces of its own that
## take turns.

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

## Every mood the game asks for has its pieces, and enough of them where the player spends his
## time (a fight, the yard, the menu); the fanfare and the lament play once, the rest loop.
func test_every_mood_has_its_pieces() -> void:
	for mood in Music.MOODS:
		for p in Music.MOODS[mood]:
			t.check(Music.STATES.has(p), "%s: its piece %s exists" % [mood, p])
	t.check(Music.MOODS.fight.size() >= 3, "three fight tunes")
	t.check(Music.MOODS.yard.size() >= 3, "three for the yard (the lobby)")
	t.check(Music.MOODS.menu.size() >= 2 and Music.MOODS.boss.size() >= 2, "two for the menu, two for the bosses")
	for mood in ["forge", "beast", "victory", "defeat"]:
		t.check(Music.MOODS.has(mood), "a %s mood" % mood)
	t.eq(bool(Music.STATES.defeat.get("once", false)) and bool(Music.STATES.victory.get("once", false)), true, "the end of a bout plays once")

## Each fight its own tune: a mood plays its pieces in turn, and coming back from the forge the
## yard plays the tune it was playing.
func test_moods_take_turns() -> void:
	var mu := Music.new()
	var seen := []
	for i in Music.MOODS.fight.size():
		seen.append(mu.pick("fight"))
	t.eq(seen.size(), Music.MOODS.fight.size(), "a pick a fight")
	var distinct := {}
	for p in seen:
		distinct[p] = true
	t.eq(distinct.size(), seen.size(), "each fight a different tune (%s)" % str(seen))
	t.eq(mu.pick("fight"), seen[0], "and round again")
	var y := mu.pick("yard")
	t.eq(mu.pick("yard", true), y, "back from the forge: the same yard tune")
	t.check(mu.pick("yard") != y, "after the next fight: another")
	t.eq(mu.peek("menu"), mu.pick("menu"), "peek tells what comes next")
	mu.free()

## Each moment its pace: every fight piece faster than every yard piece, every yard piece faster
## than the menu's; the menu has no drums, every fight has them.
func test_each_moment_has_its_pace() -> void:
	var slowest_fight := 999
	for mood in ["fight", "beast", "boss"]:
		for p in Music.MOODS[mood]:
			var st: Dictionary = Music.STATES[p]
			slowest_fight = mini(slowest_fight, int(st.bpm))
			t.check(float(st.get("drum", 0.0)) + float(st.get("toms", 0.0)) > 0.4, "%s: drums" % p)
	var fastest_yard := 0
	var slowest_yard := 999
	for p in Music.MOODS.yard + Music.MOODS.forge:
		fastest_yard = maxi(fastest_yard, int(Music.STATES[p].bpm))
		slowest_yard = mini(slowest_yard, int(Music.STATES[p].bpm))
	var fastest_menu := 0
	for p in Music.MOODS.menu:
		fastest_menu = maxi(fastest_menu, int(Music.STATES[p].bpm))
		t.eq(float(Music.STATES[p].get("drum", 0.0)), 0.0, "%s: no drums" % p)
	t.check(slowest_fight > fastest_yard, "fights (%d+) faster than the yard (to %d)" % [slowest_fight, fastest_yard])
	t.check(slowest_yard > fastest_menu, "the yard (%d+) livelier than the menu (to %d)" % [slowest_yard, fastest_menu])

## A tune that moves through chords comes home to the bar's chord.
func test_the_melody_lands_on_its_chord() -> void:
	for land in [0, 3, 5, 6]:
		var notes := Music.phrase(11, 0.5, land)
		var last: int = notes[notes.size() - 1].deg
		t.check(last == land or last == land + 4 or last == land - 3, "on chord %d it lands on its root or fifth (%d)" % [land, last])
	t.check(absf(Music.hz_in(Music.DORIAN, 220.0, 7) - 440.0) < 0.01, "an octave in any mode doubles")
