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
	t.check(Voices.file_key(man, "grave").ends_with("_scream") and Voices.file_key(man, "grave").begins_with("man_"), "a man's grave cry is a scream")
	t.check(Voices.file_key(man, "effort").ends_with("_effort"), "and his swing an effort")
	t.check(["man_light", "man_mid", "man_heavy"].has(Voices.throat_of(man)), "a man has one of the three throats")
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
	for th in ["man_light", "man_mid", "man_heavy"]:
		for ev in ["effort", "grunt", "pain", "scream", "death"]:
			keys.append(th + "_" + ev)
	var missing := []
	for k in keys:
		for i in range(1, Sfx.TAKES + 1):
			var path := Sfx.VOICE_DIR + "%s_%d.ogg" % [k, i]
			if not (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
				missing.append(path)
	t.check(missing.is_empty(), "every voice has its three takes (%d keys); missing: %s" % [keys.size(), str(missing.slice(0, 6))])
	for ev in ["grunt", "pain", "scream"]:
		t.check(FileAccess.file_exists(Sfx.VOICE_DIR + "man_mid_%s_6.ogg" % ev), "a man has six takes of his %s" % ev)
	var seen := {}
	for i in 12:
		seen[Sfx._voice_stream("man_mid_pain")] = true
	t.check(seen.size() >= 3, "the takes vary (%d of 6 heard in 12 cries)" % seen.size())
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

## The Cyclops, and only he, screams when his one eye is put out and roars on as he rages blind:
## his own takes, rendered and loadable; the other giants keep their own voices.
func test_the_cyclops_screams_when_blinded() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var man: Fighter = m.me.f
	man.mods["voice"] = "cyclops"
	t.eq(Voices.file_key(man, "rage"), "cyclops_rage", "his eye out: his own scream")
	t.eq(Voices.file_key(man, "rampage"), "cyclops_rampage", "then his raging")
	t.eq(Voices.file_key(man, "death"), "cyclops_death", "and still dies in his own voice")
	for g in ["minotaur", "titan", "troll", "giant"]:
		man.mods["voice"] = g
		t.check(not Voices.file_key(man, "rage").begins_with("cyclops_"), "%s does not take the Cyclops' scream" % g)
	man.mods.erase("voice")
	for k in [["cyclops_rage", 3], ["cyclops_rampage", 5]]:
		for i in range(1, int(k[1]) + 1):
			var path := Sfx.VOICE_DIR + "%s_%d.ogg" % [k[0], i]
			t.check(ResourceLoader.exists(path) or FileAccess.file_exists(path), "%s is there" % path.get_file())
	t.check(Sfx._voice_stream("cyclops_rage") != null, "the scream loads as a stream")
	t.check(Sfx._voice_stream("cyclops_rampage") != null, "and the raging")
	m.queue_free()

## Blinded, the Cyclops' rampage goes on: the raging cry comes again and again while he rages.
func test_the_blind_cyclops_roars_on() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	var spec: Dictionary = m.enemy_spec({"e": "cyclops"}, 0, 1)
	spec.pos = Vector3(0, 0.1, 9)
	var e = m.spawn_fighter(spec)
	var f: Fighter = e.f
	t.eq(Voices.giant_voice(f), "cyclops", "the campaign's Cyclops has the Cyclops' voice")
	f.raged.emit(f)
	t.check(f.has_meta("rage_t"), "his scream marks when he began to rage")
	var first := float(f.get_meta("rage_t"))
	f.enraged = true
	for i in 120 * 8:
		await get_tree().physics_frame
	t.check(float(f.get_meta("rage_t")) > first, "and he roared again as he raged (%.1f s -> %.1f s)" % [first, float(f.get_meta("rage_t"))])
	m.queue_free()

## Every sound is made before it is first heard (user: the frame rate drops in a fight: made at
## its first blow, a blow's sound stalled the frame it landed in): the bank lists every kind the
## game plays, a sound made once is the same sound after, and one asked for while another thread
## makes the bank is made whole, once.
func test_sounds_are_made_before_they_are_heard() -> void:
	for kind in Sfx.LENGTH:
		t.check(Sfx.BANK.has(kind), "%s is made beforehand" % kind)
	for kind in Sfx.BLOWS:
		t.check(Sfx.BANK.has(kind), "a blow's %s is made beforehand" % kind)
	t.check(Sfx.BANK.find("thud") < Sfx.BANK.find("boom") and Sfx.BANK.find("chop") < Sfx.BANK.find("cheer"), "the blows first")
	var a := Sfx._make("chop", 1)
	t.check(a != null and a.data.size() == int(Sfx.RATE * float(Sfx.LENGTH["chop"])) * 2, "a sound is made whole")
	t.check(is_same(a, Sfx._make("chop", 1)), "and is the one sound from then on")
	# Asked for here while a thread makes them: each made once, the two given the one sound.
	var th := Thread.new()
	var theirs := []
	th.start(func():
		for k in ["flat", "stab", "slap", "twang"]:
			for take in Sfx.TAKES:
				theirs.append(Sfx._make(k, take)))
	var mine := []
	for k in ["twang", "slap", "stab", "flat"]:
		for take in Sfx.TAKES:
			mine.append([k, take, Sfx._make(k, take)])
	th.wait_to_finish()
	t.eq(theirs.size(), 12, "the thread made its sounds")
	var same := 0
	var whole := 0
	for row in mine:
		var w: AudioStreamWAV = row[2]
		if is_same(w, Sfx._make(row[0], row[1])) and theirs.has(w):
			same += 1
		if w.data.size() == int(Sfx.RATE * float(Sfx.LENGTH.get(row[0], 0.25))) * 2:
			whole += 1
	t.eq(same, 12, "asked for from two threads, each sound is made once")
	t.eq(whole, 12, "and whole")
	var mur := Sfx._make("murmur")
	t.check(mur != null and mur.loop_mode == AudioStreamWAV.LOOP_FORWARD and is_same(mur, Sfx._make("murmur")), "the crowd's murmur with them, made once")
