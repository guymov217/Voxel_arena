extends Node
## Voices: who calls how, and that each call is a real sound (shaped, loud enough, not clipping).

var t

func test_who_cries_what() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var man: Fighter = m.me.f
	t.eq(Voices.hurt_call(man, 8.0, false), "grunt", "a light blow gets a grunt")
	t.eq(Voices.hurt_call(man, 20.0, false), "pain", "a hard one a cry")
	t.eq(Voices.hurt_call(man, 20.0, true), "scream", "a limb off, a scream")
	var e = m.spawn_beast({"beast": "elephant", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 6), "yaw": PI})
	t.eq(Voices.beast_call("elephant"), "trumpet", "an elephant trumpets")
	t.eq(Voices.hurt_call(e.f, 30.0, false), "trumpet", "and trumpets when hurt")
	t.eq(Voices.beast_call("python"), "hiss", "a python hisses")
	t.check(Voices.pitch_of(e.f) < Voices.pitch_of(man) * 0.8, "the elephant's throat is deeper (%.2f vs %.2f)" % [Voices.pitch_of(e.f), Voices.pitch_of(man)])
	m.queue_free()

func test_every_call_is_a_shaped_sound() -> void:
	for kind in Voices.KINDS:
		var w: AudioStreamWAV = Sfx._make(kind, 0)
		var n := w.data.size() / 2
		var peak := 0
		var clipped := 0
		var sum := 0.0
		var tail := 0.0
		var tail_n := 0
		for i in n:
			var v := absi(w.data.decode_s16(i * 2))
			peak = maxi(peak, v)
			sum += v
			if v >= 31900:
				clipped += 1
			if i > n * 0.95:
				tail += v
				tail_n += 1
		t.check(peak > 6000, "%s is loud enough (peak %d)" % [kind, peak])
		t.check(clipped < n / 50, "%s does not clip (%d samples)" % [kind, clipped])
		t.check(tail / maxi(1, tail_n) < 0.3 * sum / n, "%s dies away at the end" % kind)
		t.check(sum / n < peak * 0.6, "%s is shaped, not a flat buzz" % kind)
