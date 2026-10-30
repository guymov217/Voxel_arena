extends Node
## Sounds made on the fly (audio.js does the same with WebAudio): a clang is a few inharmonic
## partials, a cut a burst of filtered noise, a thud a low knock. No sound files to ship.
## Each kind comes in a few takes, played at a varied pitch and level through the "SFX" bus (the
## arena's stone reverb); the crowd murmurs on its own "Crowd" bus, which ducks under the blows
## (a sidechained compressor) and for the big moments (duck()).

const RATE := 22050
var volume := 0.8
var backdrop_mul := 1.0   # 0 while the menu shows the attract fight: the fight behind the menus is silent
var _cache := {}
var _players: Array = []
const TAKES := 3
const MAX_TAKES := 8        # rendered voices: as many takes as there are files (men have six)
var _last_take := {}        # voice key -> the take heard last, never played twice running
var _ambience: AudioStreamPlayer = null
var _crowd_want := 0.3
var _duck := 0.0
var music: Music = null
var _ui_player: AudioStreamPlayer = null
const LENGTH := {"grunt": 0.3, "pain": 0.45, "scream": 0.9, "growl": 0.7, "hiss": 0.6, "trumpet": 1.0, "screech": 0.6, "roar": 1.1, "clang": 0.5, "whoosh": 0.35, "cheer": 1.4, "boo": 1.2, "honk": 0.45, "slap": 0.12, "pickup": 0.12, "bell": 1.2, "horn": 1.0, "draw": 0.5, "twang": 0.4, "shatter": 0.45, "thump": 0.28, "boing": 0.5, "squeak": 0.18, "freeze": 0.4, "giggle": 0.6, "tick": 0.07, "scrape": 0.32, "chop": 0.22, "crunch": 0.28, "flat": 0.14, "slash": 0.2, "stab": 0.22}

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_buses()
	music = Music.new()
	add_child(music)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "SFX"
	add_child(_ui_player)
	for i in 16:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 40.0
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

func _buses() -> void:
	if AudioServer.get_bus_index("SFX") >= 0:
		return
	AudioServer.add_bus()
	var sfx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(sfx, "SFX")
	AudioServer.set_bus_send(sfx, "Master")
	var rv := AudioEffectReverb.new()       # an open stone bowl: a big room, not much of it
	rv.room_size = 0.7
	rv.damping = 0.55
	rv.spread = 0.8
	rv.wet = 0.16
	rv.dry = 1.0
	rv.predelay_msec = 40.0
	AudioServer.add_bus_effect(sfx, rv)
	AudioServer.add_bus()
	var crowd := AudioServer.bus_count - 1
	AudioServer.set_bus_name(crowd, "Crowd")
	AudioServer.set_bus_send(crowd, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 2600.0
	AudioServer.add_bus_effect(crowd, lp)
	var cmp := AudioEffectCompressor.new()  # the crowd steps back when steel rings
	cmp.sidechain = "SFX"
	cmp.threshold = -22.0
	cmp.ratio = 5.0
	cmp.attack_us = 2000.0
	cmp.release_ms = 450.0
	AudioServer.add_bus_effect(crowd, cmp)
	var rv2 := AudioEffectReverb.new()
	rv2.room_size = 0.8
	rv2.wet = 0.3
	AudioServer.add_bus_effect(crowd, rv2)
	var lim := AudioEffectHardLimiter.new()
	AudioServer.add_bus_effect(0, lim)

func _process(dt: float) -> void:
	if _ambience == null:
		return
	_duck = maxf(0.0, _duck - dt)
	var want := linear_to_db(clampf((0.08 + 0.55 * _crowd_want) * volume * backdrop_mul * (0.35 if _duck > 0.0 else 1.0), 0.001, 1.0))
	_ambience.volume_db = lerpf(_ambience.volume_db, want, minf(1.0, dt * (6.0 if _duck > 0.0 else 1.5)))
	_ambience.pitch_scale = lerpf(_ambience.pitch_scale, 0.94 + 0.12 * _crowd_want, dt)

## The crowd's murmur while an arena stands; level 0..1 follows its excitement.
func ambience(on: bool) -> void:
	if _players.is_empty():
		return
	if on and _ambience == null:
		_ambience = AudioStreamPlayer.new()
		_ambience.bus = "Crowd"
		_ambience.stream = _murmur()
		_ambience.volume_db = -40.0
		add_child(_ambience)
		_ambience.play()
	elif not on and _ambience:
		_ambience.queue_free()
		_ambience = null

func crowd(level: float) -> void:
	_crowd_want = clampf(level, 0.0, 1.0)

## Hush the crowd for a moment (a death, a horn) so the big sound stands alone.
func duck(seconds := 1.2) -> void:
	_duck = maxf(_duck, seconds)

func _murmur() -> AudioStreamWAV:
	# Many voices: band-limited noise with slow swells, a few hundred "talkers" summed as noise
	# through two filters; loops seamlessly (the swells are whole periods of the loop).
	var L := 6.0
	var n := int(RATE * L)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var a := 0.0
	var b := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1, 1)
		a += (w - a) * 0.12
		b += (a - b) * 0.3
		var sw := 0.7 + 0.18 * sin(TAU * t / L * 2.0) + 0.12 * sin(TAU * t / L * 5.0 + 1.3)
		var s := (a - b * 0.6) * sw * 1.6
		# Fade the seam so the loop never clicks.
		var edge := minf(1.0, minf(t, L - t) * 20.0)
		data.encode_s16(i * 2, int(clampf(s * edge, -1.0, 1.0) * 30000))
	var wv := AudioStreamWAV.new()
	wv.format = AudioStreamWAV.FORMAT_16_BITS
	wv.mix_rate = RATE
	wv.data = data
	wv.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wv.loop_end = n
	return wv

func _make(kind: String, take := 0) -> AudioStreamWAV:
	var key := "%s#%d" % [kind, take]
	if _cache.has(key):
		return _cache[key]
	var n := int(RATE * float(LENGTH.get(kind, 0.25)))
	var data := PackedByteArray()
	data.resize(n * 2)
	if BLOWS.has(kind):
		var buf := _blow_sound(kind, take, n)
		for i in n:
			data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000))
		var bw := AudioStreamWAV.new()
		bw.format = AudioStreamWAV.FORMAT_16_BITS
		bw.mix_rate = RATE
		bw.data = data
		_cache[key] = bw
		return bw
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + take * 7919
	# Takes differ a little in body as well as in the noise.
	var tone := 1.0 + (take - 1) * 0.06
	var lp := 0.0
	var lp2 := 0.0   # a second pole over lp: noise rounded off twice (one pole left a hiss on top)
	var ph := 0.0    # a phase run up sample by sample (a pitch that moves without a jump)
	_vph = 0.0
	_vph2 = 0.0
	_crk_n = 0
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		match kind:
			"clang":
				s = (sin(TAU * 1250.0 * tone * t) + 0.6 * sin(TAU * 2830.0 * tone * t) + 0.35 * sin(TAU * 4410.0 / tone * t)) * exp(-t * 9.0 * tone) * 0.4
			"slap":
				# A palm or a flat on skin: a short dull smack, rounded off (high-passed noise was a
				# crackle of static).
				var k := _lp_k(1800.0)
				lp += (rng.randf_range(-1, 1) - lp) * k
				lp2 += (lp - lp2) * k
				ph += TAU * 220.0 * tone / RATE
				s = (lp2 * 2.6 + sin(ph) * 0.35) * exp(-t * 45.0)
			"whoosh":
				# Air parted by a swing: a band of noise that rises and falls, rounded on top.
				var L: float = LENGTH[kind]
				var e := sin(PI * minf(1.0, t / L))
				var k := _lp_k(500.0 + 1300.0 * e)
				lp += (rng.randf_range(-1, 1) - lp) * k
				lp2 += (lp - lp2) * k
				s = lp2 * e * 2.2
			"cheer", "boo":
				var L: float = LENGTH[kind]
				var k := _lp_k(1400.0 if kind == "cheer" else 600.0)
				lp += (rng.randf_range(-1, 1) - lp) * k
				lp2 += (lp - lp2) * k
				var env := sin(PI * t / L) * (0.75 + 0.25 * sin(TAU * (7.0 if kind == "cheer" else 3.0) * t))
				ph += TAU * 120.0 * (1.0 - 0.3 * t / L) / RATE
				s = (lp2 * 2.2 + (0.0 if kind == "cheer" else 0.25 * sin(ph))) * env * 0.9
			"honk":
				# A clown's horn: a square tone, its harmonics stopped below the hiss (a raw square
				# clicked at every edge).
				var sq := 0.0
				for hh in [1, 3, 5, 7, 9]:
					sq += sin(TAU * 233.0 * hh * t) / hh
				s = sq * 0.4 * minf(1.0, t * 40.0) * minf(1.0, (0.45 - t) * 20.0)
			"draw":
				# A bow string creaking back.
				lp += (rng.randf_range(-1, 1) - lp) * 0.08
				s = (lp * 0.6 + 0.25 * sin(TAU * (140.0 + 90.0 * t) * t)) * sin(PI * t / 0.5) * 0.7
			"twang":
				s = (sin(TAU * 196.0 * tone * t) + 0.5 * sin(TAU * 392.0 * tone * t) * exp(-t * 18.0)) * exp(-t * 11.0) * 0.55
			"shatter":
				# Clay giving way: a dull knock, then a rattle of little cracks, each a short burst
				# rounded off (bursts switched on and off sample by sample were static).
				if _crk_n <= 0 and rng.randf() < 0.012 * exp(-t * 6.0):
					_crk_n = rng.randi_range(60, 140)
					_crk_len = _crk_n
					_crk_a = rng.randf_range(0.4, 1.0)
				var cr := 0.0
				if _crk_n > 0:
					_crk_n -= 1
					cr = rng.randf_range(-1, 1) * _crk_a * sin(PI * float(_crk_n) / _crk_len)
				var k := _lp_k(2600.0)
				lp += (cr - lp) * k
				lp2 += (lp - lp2) * k
				s = sin(TAU * 130.0 * tone * t) * exp(-t * 30.0) * 0.7 + lp2 * 2.4 * exp(-t * 5.0)
			"grunt", "pain", "scream", "growl", "hiss", "trumpet", "screech", "roar":
				s = _voice_sample(kind, t, rng, take)
			"thump":
				# A cupped palm on a barrel chest: a deep hollow boom that drops in pitch, the
				# chest ringing a moment, and the smack of the hand on top.
				var f := 82.0 * tone * (1.0 + 0.7 * exp(-t * 35.0))
				var body := sin(TAU * f * t) * exp(-t * 14.0) + 0.35 * sin(TAU * f * 2.1 * t) * exp(-t * 26.0)
				var hp3 := rng.randf_range(-1, 1) - lp
				lp += hp3 * 0.3
				s = body * 0.6 * minf(1.0, t * 600.0) + hp3 * exp(-t * 90.0) * 0.22
			"pickup":
				s = sin(TAU * (600.0 + 2500.0 * t) * t) * exp(-t * 25.0) * 0.6
			"tick":
				# A menu press: a small dry knock of wood on stone.
				var k := _lp_k(2400.0)
				lp += (rng.randf_range(-1, 1) - lp) * k
				lp2 += (lp - lp2) * k
				s = (sin(TAU * 820.0 * t) * 0.6 + lp2 * 1.5) * exp(-t * 70.0) * 0.5
			"boing":
				# A spring let go: a low tone that wobbles up and down as it dies away.
				s = sin(TAU * 150.0 * tone * t * (1.0 + 0.35 * sin(TAU * 9.0 * t) * exp(-t * 3.0))) * exp(-t * 5.0) * 0.6
			"squeak":
				s = sin(TAU * (900.0 + 1400.0 * sin(PI * t / 0.18)) * tone * t) * sin(PI * t / 0.18) * 0.4
			"freeze":
				# Ice: a bright crack, then a tinkle of little shards (the tinkle swells and fades
				# smoothly: switched on and off it clicked).
				var k := _lp_k(3500.0)
				lp += (rng.randf_range(-1, 1) - lp) * k
				lp2 += (lp - lp2) * k
				s = lp2 * 2.0 * exp(-t * 40.0) + sin(TAU * 3100.0 * tone * t) * exp(-t * 9.0) * (0.15 + 0.1 * sin(TAU * 23.0 * t))
			"giggle":
				# A run of "hee"s, each a little higher.
				var k := int(t / 0.12)
				var u := fmod(t, 0.12) / 0.12
				s = sin(TAU * (520.0 + 40.0 * k) * tone * t) * sin(PI * u) * (0.5 + 0.3 * sin(TAU * 1040.0 * t)) * exp(-t * 2.0) * 0.4
			"bell":
				s = (sin(TAU * 660.0 * t) + 0.5 * sin(TAU * 1584.0 * t) + 0.25 * sin(TAU * 2310.0 * t)) * exp(-t * 3.0) * 0.35
			"horn":
				var v := sin(TAU * 196.0 * t) + 0.5 * sin(TAU * 392.0 * t) + 0.3 * sin(TAU * 588.0 * t)
				s = v * 0.25 * minf(1.0, t * 8.0) * minf(1.0, (1.0 - t) * 6.0)
			_:
				var k := _lp_k(600.0)
				lp += (rng.randf_range(-1, 1) - lp) * k
				lp2 += (lp - lp2) * k
				ph += TAU * 90.0 * tone * (1.0 - 2.0 * t) / RATE
				s = (sin(ph) + lp2 * 1.5) * exp(-t * 20.0) * 0.9
		buf[i] = s
	_finish(buf)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	_cache[key] = w
	return w

## The blows' own sounds (a cut biting in, the flat of a blade, bone giving, steel skidding off
## a plate, a club's knock): noise filtered down to the body of the sound over tones, never raw
## noise (that was a hiss of static over every blow), and levelled to a peak well under full
## scale (they come two and three to a blow, and clipped, they crackled).
const BLOWS := {"chop": 0.55, "flat": 0.45, "crunch": 0.5, "scrape": 0.4, "thud": 0.7, "slash": 0.45, "stab": 0.5}   # each one's peak
const PEAK := 0.7   # no other sound made here goes higher (a few at once must not clip)

## Every made sound: a 2 ms onset and a 6 ms close (no click at either end: a sound that starts
## or stops on a full sample clicks), and no peak over PEAK.
var _crk_n := 0
var _crk_len := 1
var _crk_a := 0.0
static func _finish(buf: PackedFloat32Array) -> void:
	var n := buf.size()
	var a := maxi(1, int(0.002 * RATE))
	var r := maxi(1, int(0.006 * RATE))
	var peak := 0.0
	for i in n:
		var g := 1.0
		if i < a:
			g = float(i) / a
		if i >= n - r:
			g = minf(g, float(n - 1 - i) / r)
		buf[i] *= g
		peak = maxf(peak, absf(buf[i]))
	if peak > PEAK:
		var k := PEAK / peak
		for i in n:
			buf[i] *= k

static func _lp_k(hz: float) -> float:
	return 1.0 - exp(-TAU * hz / RATE)

func _blow_sound(kind: String, take: int, n: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + take * 7919
	var tone := 1.0 + (take - 1) * 0.06
	var out := PackedFloat32Array()
	out.resize(n)
	var L := float(n) / RATE
	# Two-pole low-passes over the one noise: a (and its second pole a2), b, c.
	var a1 := 0.0; var a2 := 0.0; var b1 := 0.0; var b2 := 0.0; var c1 := 0.0; var c2 := 0.0
	var ph := 0.0; var ph2 := 0.0
	var crack := 0.0; var crack_n := 0; var crack_a := 0.0; var crack_len := 1
	for i in n:
		var t := float(i) / RATE
		var nz := rng.randf_range(-1.0, 1.0)
		var att := minf(1.0, t * 450.0)   # (a 2 ms onset: no click at the start)
		var s := 0.0
		match kind:
			"chop":
				# A blade biting into meat: the knock of the body taking it (a low tone falling),
				# the soft tear of the flesh, and a wet thud under it.
				var ka := _lp_k(1500.0)
				a1 += (nz - a1) * ka; a2 += (a1 - a2) * ka
				var kb := _lp_k(700.0)
				var kc := _lp_k(220.0)
				b1 += (nz - b1) * kb; b2 += (b1 - b2) * kb
				c1 += (nz - c1) * kc; c2 += (c1 - c2) * kc
				ph += TAU * (150.0 - 75.0 * minf(1.0, t / 0.12)) * tone / RATE
				s = sin(ph) * exp(-t * 26.0) * 0.55 + a2 * 3.2 * exp(-t * 40.0) + (b2 - c2) * 5.0 * exp(-t * 18.0)
			"flat":
				# The flat of a blade on flesh: a dull smack, no edge in it.
				var ka := _lp_k(1100.0)
				a1 += (nz - a1) * ka; a2 += (a1 - a2) * ka
				ph += TAU * 190.0 * tone / RATE
				s = a2 * 3.5 * exp(-t * 55.0) + sin(ph) * exp(-t * 38.0) * 0.4
			"crunch":
				# Bone giving way: a low knock, and a run of short dry cracks thinning out, each
				# a little burst of noise rounded off (no fizz over the top).
				if crack_n <= 0 and rng.randf() < 0.010 * exp(-t * 9.0):
					crack_n = rng.randi_range(40, 90)
					crack_len = crack_n
					crack_a = rng.randf_range(0.4, 1.0)
				var cr := 0.0
				if crack_n > 0:
					crack_n -= 1
					cr = nz * crack_a * sin(PI * float(crack_n) / crack_len)   # (each crack swells and dies: no edge)
				var ka := _lp_k(2600.0)
				a1 += (cr - a1) * ka; a2 += (a1 - a2) * ka
				var kc := _lp_k(350.0)
				c1 += (nz - c1) * kc; c2 += (c1 - c2) * kc
				ph += TAU * 105.0 * tone / RATE
				s = sin(ph) * exp(-t * 24.0) * 0.5 + a2 * 2.2 * exp(-t * 6.0) + c2 * 2.5 * exp(-t * 30.0)
			"scrape":
				# Steel skidding off a plate: a metal ring sliding down as the edge runs off, and
				# the grind of it in a narrow band, rough with the plate's grain.
				var slide := 1.0 - 0.15 * t / L
				ph += TAU * 1650.0 * tone * slide / RATE
				ph2 += TAU * 2480.0 * tone * slide / RATE
				var ring := (sin(ph) * 0.6 + sin(ph2) * 0.35) * exp(-t * 7.5)
				var ka := _lp_k(2400.0)
				var kc := _lp_k(1000.0)
				a1 += (nz - a1) * ka; a2 += (a1 - a2) * ka
				c1 += (nz - c1) * kc; c2 += (c1 - c2) * kc
				var grind := (a2 - c2) * (0.65 + 0.35 * sin(TAU * 28.0 * t)) * sin(PI * minf(1.0, t / (0.9 * L)))
				s = ring * 0.5 + grind * 1.6
			"slash":
				# A cut that only opens the skin: a short swish of the edge across it, in a band
				# (the old one, near raw noise, was a hiss of static on every light cut).
				var ka := _lp_k(2300.0)
				var kc := _lp_k(700.0)
				a1 += (nz - a1) * ka; a2 += (a1 - a2) * ka
				c1 += (nz - c1) * kc; c2 += (c1 - c2) * kc
				ph += TAU * 160.0 * tone / RATE
				s = (a2 - c2) * 3.0 * exp(-t * 28.0) + sin(ph) * exp(-t * 45.0) * 0.3
			"stab":
				# A point driven in: a short knock falling in pitch, and a wet rounded thud.
				var kc := _lp_k(900.0)
				c1 += (nz - c1) * kc; c2 += (c1 - c2) * kc
				ph += TAU * (190.0 - 70.0 * minf(1.0, t / 0.1)) * tone / RATE
				s = sin(ph) * exp(-t * 24.0) * 0.6 + c2 * 3.0 * exp(-t * 26.0)
			"thud":
				# A knock: a low tone falling away, with a dull rumble of the blow in it.
				var kc := _lp_k(500.0)
				c1 += (nz - c1) * kc; c2 += (c1 - c2) * kc
				ph += TAU * 90.0 * tone * (1.0 - 2.0 * t) / RATE
				s = (sin(ph) + c2 * 2.6) * exp(-t * 20.0)
		s *= att * minf(1.0, (L - t) * 200.0)   # (and a 5 ms close: no click at the end)
		out[i] = s
	# Levelled: every take to the same peak, well under full scale.
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 1e-6:
		var k: float = float(BLOWS[kind]) / peak
		for i in n:
			out[i] *= k
	return out

## A voice: a throat (a pulse train at the pitch, with its vibrato and its break) through two
## formants (a vowel), with breath noise. Men grunt with the effort, cry out when struck and
## scream when a limb comes off; beasts growl, hiss, trumpet, screech or roar. Only the shape
## of each call lives here; who makes it, and how deep, is the caller's (voice()).
func _voice_sample(kind: String, t: float, rng: RandomNumberGenerator, take: int) -> float:
	var L: float = LENGTH[kind]
	var u := t / L
	var f0 := 120.0
	var env := 1.0
	var noise := 0.1
	var f1 := 600.0
	var f2 := 1200.0
	var rasp := 0.0
	match kind:
		"grunt":
			# "Hngh": a short push from the belly, pitch falling.
			f0 = 130.0 * (1.0 - 0.3 * u) * (1.0 + 0.08 * take)
			env = minf(1.0, t * 60.0) * exp(-t * 7.0)
			f1 = 450.0; f2 = 1100.0; noise = 0.25
		"pain":
			# "Agh!": a jump up, a wobble, and a fall away.
			f0 = (170.0 + 60.0 * sin(PI * u) - 40.0 * u) * (1.0 + 0.06 * take) * (1.0 + 0.03 * sin(TAU * 7.0 * t))
			env = minf(1.0, t * 40.0) * (1.0 - u) * (1.0 - u)
			f1 = 750.0; f2 = 1300.0; noise = 0.18
		"scream":
			# A long high cry that breaks on the way down.
			f0 = (260.0 + 120.0 * sin(PI * minf(1.0, u * 1.6)) - 60.0 * u) * (1.0 + 0.05 * take) * (1.0 + 0.05 * sin(TAU * 6.0 * t + take))
			env = minf(1.0, t * 30.0) * (1.0 if u < 0.6 else (1.0 - u) / 0.4)
			f1 = 900.0; f2 = 1700.0; noise = 0.22; rasp = 0.35
		"growl":
			# Low, rough, the throat rattling.
			f0 = 55.0 * (1.0 + 0.1 * take) * (1.0 + 0.1 * sin(TAU * 25.0 * t))
			env = minf(1.0, t * 20.0) * (1.0 - u) * (0.7 + 0.3 * sin(TAU * 14.0 * t))
			f1 = 350.0; f2 = 900.0; noise = 0.3; rasp = 0.8
		"hiss":
			# Breath forced through the fangs: all noise, a narrow bright band.
			f0 = 0.0
			env = sin(PI * u) * (0.85 + 0.15 * sin(TAU * 30.0 * t))
			f1 = 2600.0; f2 = 4200.0; noise = 1.0
		"trumpet":
			# A brass blast that climbs and cracks at the top.
			f0 = (240.0 + 160.0 * minf(1.0, u * 2.5)) * (1.0 + 0.04 * take) * (1.0 + 0.02 * sin(TAU * 9.0 * t))
			env = minf(1.0, t * 12.0) * minf(1.0, (1.0 - u) * 5.0)
			f1 = 700.0; f2 = 1900.0; noise = 0.08; rasp = 0.5
		"screech":
			# High and thin, sliding down.
			f0 = (900.0 - 350.0 * u) * (1.0 + 0.06 * take) * (1.0 + 0.04 * sin(TAU * 18.0 * t))
			env = minf(1.0, t * 50.0) * (1.0 - u)
			f1 = 1800.0; f2 = 3200.0; noise = 0.15; rasp = 0.3
		"roar":
			# Opens with a bark, then a chest-deep bellow that sags away.
			f0 = (90.0 + 50.0 * exp(-t * 6.0) - 20.0 * u) * (1.0 + 0.07 * take) * (1.0 + 0.06 * sin(TAU * 11.0 * t))
			env = minf(1.0, t * 30.0) * (1.0 if u < 0.5 else (1.0 - u) * 2.0) * (0.8 + 0.2 * sin(TAU * 17.0 * t))
			f1 = 500.0; f2 = 1100.0; noise = 0.25; rasp = 0.6
	env *= minf(1.0, (1.0 - u) * 10.0)   # every call closes, none is cut off
	# The throat: a pulse train, its harmonics shaped by the two formants (a resonance each).
	var s := 0.0
	if f0 > 0.0:
		# (The phase run up from the pitch sample by sample: f0 * t jumped as the pitch moved, a
		# click a cycle, a crackle through every growl and roar.)
		_vph = fmod(_vph + f0 / RATE, 1.0)
		var ph := fmod(_vph + 0.2 * rasp * sin(TAU * 33.0 * t) + 1.0, 1.0)
		for h in range(1, 14):
			var fh := f0 * h
			var a := 1.0 / h
			var r1 := fh / f1
			var r2 := fh / f2
			a *= 1.0 / (1.0 + 4.0 * (r1 - 1.0) * (r1 - 1.0)) + 0.6 / (1.0 + 4.0 * (r2 - 1.0) * (r2 - 1.0)) + 0.05
			s += a * sin(TAU * h * ph)
		s *= 0.35
		if rasp > 0.0:
			_vph2 = fmod(_vph2 + 0.5 * f0 / RATE, 1.0)
			s *= 1.0 - rasp * 0.4 * maxf(0.0, sin(TAU * _vph2))   # the fold catching every other beat
	# Breath through the vowel: noise around the first formant.
	# (Rounded off twice: one pole left near white noise on top, a fizz over every call.)
	var kb := clampf(f1 / 3000.0, 0.08, 0.6)
	_vlp += (rng.randf_range(-1.0, 1.0) - _vlp) * kb
	_vlp2 += (_vlp - _vlp2) * kb
	s += _vlp2 * noise * 1.1
	return clampf(s * env * 0.9, -1.0, 1.0)

var _vlp := 0.0
var _vlp2 := 0.0
var _vph := 0.0
var _vph2 := 0.0

## The rendered voices (art/audio/voices, built by tools/build_voices.py from CC0 recordings, see
## art/CREDITS.md): "<species>_<call>", "man_<throat>_<call>" (light, mid, heavy; six takes) or "<giant>_<call>", three takes each. Loaded once; a missing one plays the on-the-fly voice instead.
const VOICE_DIR := "res://art/audio/voices/"
var _voices := {}

## A take of a rendered voice, never the one heard last (a man struck twice cried the one cry).
func _pick_take(key: String) -> AudioStream:
	var takes: Array = _voices[key]
	if takes.is_empty():
		return null
	var i := randi() % takes.size()
	if takes.size() > 1 and i == int(_last_take.get(key, -1)):
		i = (i + 1 + randi() % (takes.size() - 1)) % takes.size()
	_last_take[key] = i
	return takes[i]

func _voice_stream(key: String) -> AudioStream:
	if _voices.has(key):
		return _pick_take(key)
	var takes := []
	for i in range(1, MAX_TAKES + 1):
		var path := VOICE_DIR + "%s_%d.ogg" % [key, i]
		var st: AudioStream = null
		if ResourceLoader.exists(path):
			st = load(path)
		elif FileAccess.file_exists(path):
			st = AudioStreamOggVorbis.load_from_file(path)
		if st:
			takes.append(st)
	_voices[key] = takes
	return _pick_take(key)

## A character's voice: `pitch` 1.0 for a man, lower for the big (a giant at 0.6, an elephant at
## 0.5), higher for the small. `file` names a rendered voice ("lion_call"); without one, or
## without the file, the voice is made on the fly from `kind`.
func voice(kind: String, at: Vector3, gain := 1.0, pitch := 1.0, file := "") -> void:
	if _players.is_empty() or gain < 0.05 or backdrop_mul <= 0.0:
		return
	for p in _players:
		if not p.playing:
			var st: AudioStream = _voice_stream(file) if file != "" else null
			p.stream = st if st else _make(kind, randi() % TAKES)
			p.global_position = at
			p.volume_db = linear_to_db(clampf(gain * volume * backdrop_mul, 0.01, 1.0)) + randf_range(-1.5, 1.5)
			p.pitch_scale = clampf(pitch * randf_range(0.92, 1.08), 0.3, 3.0)
			p.play()
			return

## A sound of the menus, heard the same everywhere (not placed in the arena).
func ui(kind: String, gain := 0.5) -> void:
	if _ui_player == null:
		return
	_ui_player.stream = _make(kind)
	_ui_player.volume_db = linear_to_db(clampf(gain * volume, 0.01, 1.0))
	_ui_player.pitch_scale = randf_range(0.94, 1.06)
	_ui_player.play()

## The one sound in the one place again within REPEAT_S is the same sound: one blow came as a run
## of contacts a few milliseconds apart, each starting the blow's sound over the last, a crackle
## like static on every hit (user: a sword on a gladiator).
const REPEAT_S := 0.08
var _last_play := {}   # kind -> [msec, position]
func play(kind: String, at: Vector3, gain := 1.0) -> void:
	if _players.is_empty() or gain < 0.05 or backdrop_mul <= 0.0:
		return
	var now := Time.get_ticks_msec()
	var lp = _last_play.get(kind)
	if lp != null and now - int(lp[0]) < int(REPEAT_S * 1000.0) and (lp[1] as Vector3).distance_to(at) < 1.5:
		return
	_last_play[kind] = [now, at]
	for p in _players:
		if not p.playing:
			p.stream = _make(kind, randi() % TAKES)
			p.global_position = at
			p.volume_db = linear_to_db(clampf(gain * volume * backdrop_mul, 0.01, 1.0)) + randf_range(-1.5, 1.5)
			p.pitch_scale = randf_range(0.88, 1.12)
			if kind == "horn" or kind == "bell":
				duck(1.4)
			p.play()
			return
