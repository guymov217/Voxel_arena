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
const LENGTH := {"grunt": 0.3, "pain": 0.45, "scream": 0.9, "growl": 0.7, "hiss": 0.6, "trumpet": 1.0, "screech": 0.6, "roar": 1.1, "clang": 0.5, "whoosh": 0.35, "cheer": 1.4, "boo": 1.2, "honk": 0.45, "slap": 0.12, "pickup": 0.12, "bell": 1.2, "horn": 1.0, "draw": 0.5, "twang": 0.4, "shatter": 0.45, "thump": 0.28}

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_buses()
	music = Music.new()
	add_child(music)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + take * 7919
	# Takes differ a little in body as well as in the noise.
	var tone := 1.0 + (take - 1) * 0.06
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		match kind:
			"clang":
				s = (sin(TAU * 1250.0 * tone * t) + 0.6 * sin(TAU * 2830.0 * tone * t) + 0.35 * sin(TAU * 4410.0 / tone * t)) * exp(-t * 9.0 * tone) * 0.4
			"slash":
				lp += (rng.randf_range(-1, 1) - lp) * 0.35
				s = lp * exp(-t * 18.0) * 0.9
			"stab":
				lp += (rng.randf_range(-1, 1) - lp) * 0.2
				s = (lp + 0.4 * sin(TAU * 180.0 * t)) * exp(-t * 22.0) * 0.8
			"slap":
				var hp := rng.randf_range(-1, 1) - lp
				lp += hp * 0.5
				s = hp * exp(-t * 45.0) * 0.9
			"whoosh":
				lp += (rng.randf_range(-1, 1) - lp) * (0.05 + 0.25 * sin(PI * t / 0.35))
				s = lp * sin(PI * t / 0.35) * 1.4
			"cheer", "boo":
				var L: float = LENGTH[kind]
				lp += (rng.randf_range(-1, 1) - lp) * (0.25 if kind == "cheer" else 0.08)
				var env := sin(PI * t / L) * (0.75 + 0.25 * sin(TAU * (7.0 if kind == "cheer" else 3.0) * t))
				s = (lp + (0.0 if kind == "cheer" else 0.25 * sin(TAU * 120.0 * t * (1.0 - 0.3 * t / L)))) * env * 0.9
			"honk":
				s = (1.0 if fmod(t * 233.0, 1.0) < 0.5 else -1.0) * 0.35 * minf(1.0, t * 40.0) * minf(1.0, (0.45 - t) * 20.0)
			"draw":
				# A bow string creaking back.
				lp += (rng.randf_range(-1, 1) - lp) * 0.08
				s = (lp * 0.6 + 0.25 * sin(TAU * (140.0 + 90.0 * t) * t)) * sin(PI * t / 0.5) * 0.7
			"twang":
				s = (sin(TAU * 196.0 * tone * t) + 0.5 * sin(TAU * 392.0 * tone * t) * exp(-t * 18.0)) * exp(-t * 11.0) * 0.55
			"shatter":
				# Clay giving way: a dull knock, then a rattle of bright little cracks.
				var hp2 := rng.randf_range(-1, 1) - lp
				lp += hp2 * 0.6
				var crackle := hp2 * (0.6 if rng.randf() < 0.18 * exp(-t * 6.0) + 0.02 else 0.12) * exp(-t * 7.0)
				s = (sin(TAU * 130.0 * tone * t) * exp(-t * 30.0) * 0.7 + crackle * 1.4)
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
			"bell":
				s = (sin(TAU * 660.0 * t) + 0.5 * sin(TAU * 1584.0 * t) + 0.25 * sin(TAU * 2310.0 * t)) * exp(-t * 3.0) * 0.35
			"horn":
				var v := sin(TAU * 196.0 * t) + 0.5 * sin(TAU * 392.0 * t) + 0.3 * sin(TAU * 588.0 * t)
				s = v * 0.25 * minf(1.0, t * 8.0) * minf(1.0, (1.0 - t) * 6.0)
			_:
				s = (sin(TAU * 90.0 * tone * t * (1.0 - t)) + rng.randf_range(-0.3, 0.3)) * exp(-t * 20.0) * 0.9
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	_cache[key] = w
	return w

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
		var ph := fmod(f0 * t + 0.2 * rasp * sin(TAU * 33.0 * t), 1.0)
		for h in range(1, 14):
			var fh := f0 * h
			var a := 1.0 / h
			var r1 := fh / f1
			var r2 := fh / f2
			a *= 1.0 / (1.0 + 4.0 * (r1 - 1.0) * (r1 - 1.0)) + 0.6 / (1.0 + 4.0 * (r2 - 1.0) * (r2 - 1.0)) + 0.05
			s += a * sin(TAU * h * ph)
		s *= 0.35
		if rasp > 0.0:
			s *= 1.0 - rasp * 0.4 * maxf(0.0, sin(TAU * f0 * 0.5 * t))   # the fold catching every other beat
	# Breath through the vowel: noise around the first formant.
	_vlp += (rng.randf_range(-1.0, 1.0) - _vlp) * clampf(f1 / 3000.0, 0.08, 0.9)
	s += _vlp * noise * 0.8
	return clampf(s * env * 0.9, -1.0, 1.0)

var _vlp := 0.0

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

func play(kind: String, at: Vector3, gain := 1.0) -> void:
	if _players.is_empty() or gain < 0.05 or backdrop_mul <= 0.0:
		return
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
