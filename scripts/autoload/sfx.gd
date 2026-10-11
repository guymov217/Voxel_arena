extends Node
## Sounds made on the fly (audio.js does the same with WebAudio): a clang is a few inharmonic
## partials, a cut a burst of filtered noise, a thud a low knock. No sound files to ship.
## Each kind comes in a few takes, played at a varied pitch and level through the "SFX" bus (the
## arena's stone reverb); the crowd murmurs on its own "Crowd" bus, which ducks under the blows
## (a sidechained compressor) and for the big moments (duck()).

const RATE := 22050
var volume := 0.8
var backdrop_mul := 1.0   # quieter while the menu shows the attract fight
var _cache := {}
var _players: Array = []
const TAKES := 3
var _ambience: AudioStreamPlayer = null
var _crowd_want := 0.3
var _duck := 0.0
var music: Music = null
const LENGTH := {"clang": 0.5, "whoosh": 0.35, "cheer": 1.4, "boo": 1.2, "honk": 0.45, "slap": 0.12, "pickup": 0.12, "bell": 1.2, "horn": 1.0}

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

func play(kind: String, at: Vector3, gain := 1.0) -> void:
	if _players.is_empty() or gain < 0.05:
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
