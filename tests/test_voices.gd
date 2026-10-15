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
	t.eq(Voices.file_key(e.f, "hurt"), "elephant_hurt", "the elephant's own rendered cry")
	t.eq(Voices.file_key(e.f, "grave"), "elephant_call", "a beast's grave cry is its call")
	t.eq(Voices.file_key(man, "grave"), "man_scream", "a man's grave cry is a scream")
	t.eq(Voices.file_key(man, "effort"), "man_effort", "and his swing an effort")
	man.mods["voice"] = "minotaur"
	t.eq(Voices.file_key(man, "effort"), "minotaur_call", "a minotaur bellows with his own voice")
	t.eq(Voices.file_key(man, "grunt"), "minotaur_hurt", "and is hurt in it")
	t.eq(Voices.file_key(man, "death"), "minotaur_death", "and dies in it")
	t.check(is_equal_approx(Voices.pitch_of_species(man), Voices.pitch_of(man)), "a giant's rendered voice is not shifted again")
	man.mods.erase("voice")
	m.queue_free()

func test_every_voice_is_rendered() -> void:
	var keys := []
	for sp in Data.beasts.keys():
		for ev in ["call", "hurt", "death"]:
			keys.append("%s_%s" % [sp, ev])
	for g in Voices.GIANTS:
		for ev in ["call", "hurt", "death"]:
			keys.append("%s_%s" % [g, ev])
	for ev in ["effort", "grunt", "pain", "scream", "death"]:
		keys.append("man_" + ev)
	var missing := []
	for k in keys:
		for i in range(1, Sfx.TAKES + 1):
			var path := Sfx.VOICE_DIR + "%s_%d.ogg" % [k, i]
			if not (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
				missing.append(path)
	t.check(missing.is_empty(), "every voice has its three takes (%d keys); missing: %s" % [keys.size(), str(missing.slice(0, 6))])
	var st := Sfx._voice_stream("lion_call")
	t.check(st != null, "a rendered voice loads as a stream")

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
