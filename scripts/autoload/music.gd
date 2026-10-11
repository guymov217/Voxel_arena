class_name Music
extends Node
## Procedural music (music.js): no files, a small band synthesised into a loop. The scale is the
## Phrygian dominant (the old Mediterranean "hijaz": D Eb F# G A Bb C), the band a frame drum, a
## riq's jingles, a low drone, a plucked lyre and a brass horn. Each state has its own tempo and
## layers: the menu is a lyre over a drone, a fight brings the drums in, a boss fight is faster
## with the horn on top, a win is a short fanfare. Loops are rendered on a worker thread the
## first time they are needed and cross-faded on the "Music" bus.

const RATE := 22050
const SCALE := [0, 1, 4, 5, 7, 8, 10]
const ROOT := 146.83
const STATES := {
	"menu": {"bpm": 76, "drum": 0.0, "riq": 0.0, "drone": 0.7, "lyre": 0.55, "horn": 0.0, "density": 0.35, "bars": 8},
	"yard": {"bpm": 92, "drum": 0.25, "riq": 0.35, "drone": 0.5, "lyre": 0.6, "horn": 0.0, "density": 0.45, "bars": 8},
	"fight": {"bpm": 112, "drum": 0.8, "riq": 0.5, "drone": 0.55, "lyre": 0.45, "horn": 0.15, "density": 0.4, "bars": 8},
	"boss": {"bpm": 128, "drum": 1.0, "riq": 0.7, "drone": 0.8, "lyre": 0.3, "horn": 0.6, "density": 0.55, "bars": 8},
	"victory": {"bpm": 104, "drum": 0.6, "riq": 0.6, "drone": 0.4, "lyre": 0.6, "horn": 0.8, "density": 0.7, "bars": 2, "once": true},
}
const DUM := [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0]
const TEK := [0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]

var state := "off"
var volume := 0.5
var cache := {}
var players: Array = []
var active := 0
var thread: Thread = null
var want := ""

func _ready() -> void:
	if not AudioServer.get_bus_index("Music") >= 0:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, "Music")
		AudioServer.set_bus_send(b, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.6
		rv.wet = 0.18
		AudioServer.add_bus_effect(b, rv)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		players.append(p)

static func hz(deg: int, octave := 0) -> float:
	var d := posmod(deg, 7)
	var o := octave + floori(deg / 7.0)
	return ROOT * pow(2.0, (SCALE[d] + 12 * o) / 12.0)

## A bar's melody: a walk on the scale with the odd leap, landing on the root or the fifth.
static func phrase(seed_: int, density: float) -> Array:
	var s := (seed_ * 9301 + 49297) % 233280
	var notes := []
	var deg := 4
	for i in 16:
		s = (s * 9301 + 49297) % 233280
		var r := s / 233280.0
		if i == 14:
			notes.append({"step": i, "deg": 0 if r < 0.5 else 4, "len": 2})
			break
		if r < (density + 0.3 if i % 4 == 0 else density * 0.7):
			s = (s * 9301 + 49297) % 233280
			var r2 := s / 233280.0
			deg += (-3 if r2 < 0.07 else 3) if r2 < 0.15 else (-1 if r2 < 0.57 else 1)
			deg = clampi(deg, -2, 9)
			notes.append({"step": i, "deg": deg, "len": 2 if r2 > 0.7 else 1})
	return notes

## Renders a state's loop into 16-bit PCM.
static func render(name_: String) -> AudioStreamWAV:
	var st: Dictionary = STATES[name_]
	var step_s := 60.0 / float(st.bpm) / 4.0
	var bars := int(st.bars)
	var n := int(bars * 16 * step_s * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name_)
	# The drone: root and fifth, a slow swell, the whole way.
	if float(st.drone) > 0.0:
		var f0 := hz(0, -1)
		var f1 := hz(4, -1)
		for i in n:
			var t := float(i) / RATE
			var sw := 0.75 + 0.25 * sin(TAU * t / (bars * 16 * step_s) * 2.0)
			var v := sin(TAU * f0 * t) + 0.5 * sin(TAU * f0 * 2.0 * t) + 0.3 * sin(TAU * f0 * 3.0 * t) + 0.6 * sin(TAU * f1 * t)
			buf[i] += v * 0.05 * float(st.drone) * sw
	for bar in bars:
		var mel := phrase(bar * 7 + hash(name_) % 97, float(st.density))
		for stp in 16:
			var t0 := (bar * 16 + stp) * step_s
			# Frame drum: the low "dum" and the high "tek".
			if float(st.drum) > 0.0:
				if DUM[stp]:
					_hit(buf, t0, 0.32, func(t): return (sin(TAU * (62.0 + 50.0 * exp(-t * 30.0)) * t) * 0.9 + rng.randf_range(-0.2, 0.2) * exp(-t * 40.0)) * exp(-t * 9.0) * 0.5 * float(st.drum))
				if TEK[stp]:
					_hit(buf, t0, 0.08, func(t): return rng.randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.22 * float(st.drum))
			# Riq: jingles on the offbeats.
			if float(st.riq) > 0.0 and stp % 2 == 1:
				_hit(buf, t0, 0.06, func(t): return (rng.randf_range(-1.0, 1.0) * sin(TAU * 5200.0 * t)) * exp(-t * 70.0) * 0.08 * float(st.riq))
		# Lyre: plucked, a few partials ringing down.
		if float(st.lyre) > 0.0:
			for note in mel:
				var f := hz(int(note.deg), 1)
				var dur := 1.1 + 0.4 * int(note.len)
				_hit(buf, (bar * 16 + int(note.step)) * step_s, dur, func(t): return (sin(TAU * f * t) + 0.45 * sin(TAU * f * 2.0 * t) * exp(-t * 3.0) + 0.2 * sin(TAU * f * 3.0 * t) * exp(-t * 6.0)) * exp(-t * 2.6) * minf(1.0, t * 400.0) * 0.12 * float(st.lyre))
		# Horn: a long call on the strong beats of every other bar.
		if float(st.horn) > 0.0 and (bar % 2 == 1 or st.get("once", false)):
			for k in [0, 8]:
				var deg2: int = [4, 2, 0, 4][(bar + k / 8) % 4]
				var fh := hz(deg2, 0)
				var len_s := step_s * 6.0
				_hit(buf, (bar * 16 + k) * step_s, len_s, func(t):
					var vib := 1.0 + 0.006 * sin(TAU * 5.5 * t)
					var saw := 0.0
					for hk in range(1, 7):
						saw += sin(TAU * fh * vib * hk * t) / hk
					return saw * minf(1.0, t * 14.0) * minf(1.0, (len_s - t) * 8.0) * 0.07 * float(st.horn))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(tanh(buf[i] * 1.2), -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if not st.get("once", false):
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w

static func _hit(buf: PackedFloat32Array, t0: float, dur: float, f: Callable) -> void:
	var i0 := int(t0 * RATE)
	var cnt := int(dur * RATE)
	for j in cnt:
		var i := i0 + j
		if i >= buf.size():
			break
		buf[i] += f.call(float(j) / RATE)

## Switches the music to a state ("off" for silence), cross-fading.
func set_state(s: String) -> void:
	if s == state or DisplayServer.get_name() == "headless":
		return
	state = s
	if s == "off" or not STATES.has(s):
		_fade_to(null)
		return
	if cache.has(s):
		_fade_to(cache[s])
		return
	want = s
	if thread == null or not thread.is_alive():
		if thread:
			thread.wait_to_finish()
		thread = Thread.new()
		thread.start(_render_job.bind(s))

func _render_job(s: String) -> void:
	var w := render(s)
	call_deferred("_rendered", s, w)

func _rendered(s: String, w: AudioStreamWAV) -> void:
	cache[s] = w
	if thread:
		thread.wait_to_finish()
		thread = null
	if state == s:
		_fade_to(w)
	elif STATES.has(state) and not cache.has(state):
		var next := state
		state = ""
		set_state(next)

func _fade_to(stream) -> void:
	var old: AudioStreamPlayer = players[active]
	active = 1 - active
	var nu: AudioStreamPlayer = players[active]
	var tw := create_tween().set_parallel()
	tw.tween_property(old, "volume_db", -60.0, 1.2)
	if stream:
		nu.stream = stream
		nu.volume_db = -60.0
		nu.play()
		tw.tween_property(nu, "volume_db", linear_to_db(maxf(0.001, volume * 0.8)), 1.5)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	var p: AudioStreamPlayer = players[active]
	if p.playing:
		p.volume_db = linear_to_db(maxf(0.001, volume * 0.8))

func _exit_tree() -> void:
	if thread:
		thread.wait_to_finish()
