extends Node
## What a pot sounds like when it bursts. Each kind has a sound of its own (art/audio/pots: the clay, then what was in it; the
## thunder pot's is the blast too: user, of three, the soft boom with the pot loud over it), heard here and by the guests. Where
## a build lacks the files, the shatter made on the fly stays (its break is the pot's knock, a crack, and single shards ringing
## down, not the rattle of noise that was a static at every pot: user).

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	return m

## How much of a sound is noise and how much is rings: its spectral flatness, the geometric mean of the power spectrum over
## its arithmetic mean (0 for a pure tone, 1 for white noise), between 200 Hz and 8 kHz in frames of 256 samples, each frame
## counted by its energy.
func _flatness(d: PackedByteArray) -> float:
	var n := d.size() / 2
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		x[i] = float(d.decode_s16(i * 2)) / 32768.0
	const N := 256
	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	var win := PackedFloat32Array()
	for i in N:
		cs.append(cos(TAU * i / N))
		sn.append(sin(TAU * i / N))
		win.append(0.5 - 0.5 * cos(TAU * i / (N - 1)))
	var num := 0.0
	var den := 0.0
	var at := 0
	while at + N <= n:
		var e := 0.0
		for i in N:
			e += x[at + i] * x[at + i]
		var sum_log := 0.0
		var sum := 0.0
		var bins := 0
		for k in range(int(200.0 / Sfx.RATE * N) + 1, int(8000.0 / Sfx.RATE * N) + 1):
			var re := 0.0
			var im := 0.0
			for i in N:
				var v: float = x[at + i] * win[i]
				var q := (k * i) % N
				re += v * cs[q]
				im -= v * sn[q]
			var pw := re * re + im * im + 1e-12
			sum_log += log(pw)
			sum += pw
			bins += 1
		num += e * (exp(sum_log / bins) / (sum / bins))
		den += e
		at += N
	return num / maxf(den, 1e-12)

func test_the_meter_tells_noise_from_rings() -> void:
	var noise := PackedByteArray()
	noise.resize(Sfx.RATE * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in Sfx.RATE:
		noise.encode_s16(i * 2, int(rng.randf_range(-1.0, 1.0) * 12000.0))
	var tone := PackedByteArray()
	tone.resize(Sfx.RATE * 2)
	for i in Sfx.RATE:
		tone.encode_s16(i * 2, int(sin(TAU * 1500.0 * i / Sfx.RATE) * 12000.0))
	var fn := _flatness(noise)
	var ft := _flatness(tone)
	t.check(fn > 0.35, "white noise reads as noise (%.2f)" % fn)
	t.check(ft < 0.05, "a ring reads as a ring (%.3f)" % ft)

func test_the_shatter_made_on_the_fly_has_no_static() -> void:
	for take in 3:
		var w: AudioStreamWAV = Sfx._make("shatter", take)
		var f := _flatness(w.data)
		t.check(f < 0.1, "take %d of the shattering pot is rings, not a rattle of noise (flatness %.3f)" % [take, f])
		var peak := 0
		for i in w.data.size() / 2:
			peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
		t.check(peak > 12000 and peak < 26000, "and is heard, under the ceiling (%d)" % peak)
		t.check(w.data.size() / 2 <= int(Sfx.RATE * 0.5), "and is over in half a second")

func test_every_kind_of_pot_has_a_sound_of_its_own() -> void:
	var kinds := {}
	for type in Items.TYPES:
		kinds[type] = true
	for type in Throwables.POTS.values():
		kinds[type] = true
	for type in ["pot_confetti", "pot_grape"]:      # (only a mystery pot brings these out)
		kinds[type] = true
	var pots := 0
	for type in kinds:
		if Throwables.is_pot(type):
			pots += 1
			t.check(Sfx.POT_SOUNDS.has(type), "%s has its own sound" % type)
			t.eq(Sfx.pot_key(type), type, "and is heard as it")
	t.eq(pots, Sfx.POT_SOUNDS.size() - 1, "every kind of pot there is has one (and the clay's alone is the extra)")
	t.eq(Sfx.pot_key("pot_never_made"), "pot_clay", "a pot with none breaks as clay")
	t.check(not Throwables.is_pot("pot_arrow") and not Throwables.is_pot("pot_bolt") and not Throwables.is_pot("pot_anvil") and not Throwables.is_pot("tomato"), "an arrow, a bolt, an anvil, a tomato are no pots")

func test_each_sound_is_a_file_of_about_two_seconds() -> void:
	for key in Sfx.POT_SOUNDS:
		var st = Sfx._pot_stream(key)
		t.check(st is AudioStreamWAV, "%s is a sound in this build" % key)
		if st is AudioStreamWAV:
			var w: AudioStreamWAV = st
			t.check(w.get_length() > 1.5 and w.get_length() < 2.2, "%s lasts %.2f s" % [key, w.get_length()])
			t.check(w.format == AudioStreamWAV.FORMAT_16_BITS and not w.stereo, "%s is 16-bit mono" % key)
			var peak := 0
			for i in w.data.size() / 2:
				peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
			t.check(peak > 12000 and peak < 28000, "%s is heard, and under the ceiling (%d)" % [key, peak])

## The thunder pot's was picked from three (user: the soft boom and the pot loud over it): 1.84 s where the others were 1.90 s.
func test_the_thunder_pot_is_the_soft_boom_with_the_pot_loud_over_it() -> void:
	var w: AudioStreamWAV = Sfx._pot_stream("pot_thunder")
	t.check(w != null and absf(w.get_length() - 1.84) < 0.03, "the thunder pot's sound is the one picked (%.2f s)" % (w.get_length() if w else -1.0))

func test_a_burst_asks_for_the_sound_of_its_kind() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -10))
	for type in ["pot_thunder", "pot_fire", "pot_acid", "pot_goat", "pot_nail", "pot_smoke"]:
		m.last_pot_sound = ""
		m.throwables.explode(type, Vector3(3, 0.2, 3), m.me.f)
		t.eq(m.last_pot_sound, type, "%s bursts as itself" % type)
	m.last_pot_sound = ""
	m.throwables.explode("pot_arrow", Vector3(3, 0.2, 3), m.me.f)
	t.eq(m.last_pot_sound, "", "an arrow is no pot: no pot's sound")
	m.last_pot_sound = ""
	m.throwables.explode("pot_mystery", Vector3(3, 0.2, 3), m.me.f)
	t.check(m.last_pot_sound != "" and m.last_pot_sound != "pot_mystery", "a mystery pot bursts, and the pot it turns out to be bursts after it (%s)" % m.last_pot_sound)
	m.queue_free()

## A guest is sent the pot's sound with where it burst; what is not a sound there is a file of is not played, and nothing in it makes the game fail.
func test_a_guest_takes_only_a_sound_there_is_a_file_of() -> void:
	var m := _match()
	for data in [{"k": "pot", "t": "pot_fire", "p": [1.0, 0.2, 2.0], "g": 1.0}, {"k": "pot", "t": "../../evil", "p": [0, 0, 0]}, {"k": "pot", "t": 5, "p": [0, 0, 0], "g": "loud"}, {"k": "pot", "p": [0, 0]}, {"k": "pot", "t": "pot_fire"}]:
		m.guest_message("fx", data)
	t.check(true, "no message made the guest fail")
	m.queue_free()
