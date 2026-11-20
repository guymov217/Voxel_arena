extends Node
## What a pot sounds like when it breaks (user: at the moment a thunder, a fire or a poison pot hit there was a very annoying,
## unnatural static): the break is the pot's knock, a crack, and single shards ringing down, not a rattle of noise.

var t

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

func test_a_pot_breaks_with_no_static() -> void:
	for take in 3:
		var w: AudioStreamWAV = Sfx._make("shatter", take)
		var f := _flatness(w.data)
		t.check(f < 0.1, "take %d of the shattering pot is rings, not a rattle of noise (flatness %.3f)" % [take, f])
		var peak := 0
		for i in w.data.size() / 2:
			peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
		t.check(peak > 12000 and peak < 26000, "and is heard, under the ceiling (%d)" % peak)
		t.check(w.data.size() / 2 <= int(Sfx.RATE * 0.5), "and is over in half a second")

## The thunder and the fire pot have a sound of their own at the impact (the boom, the flare): the pot's breaking is laid
## under it.
func test_a_pot_breaks_quieter_under_its_own_sound() -> void:
	var th := Throwables.shatter_gain("pot_thunder")
	var fi := Throwables.shatter_gain("pot_fire")
	var ac := Throwables.shatter_gain("pot_acid")
	t.check(th < fi and fi < ac and is_equal_approx(ac, 1.0), "under the boom the quietest, under the flare less than whole, a poison pot's alone is whole (%.1f, %.1f, %.1f)" % [th, fi, ac])
