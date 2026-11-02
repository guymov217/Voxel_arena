class_name Music
extends Node
## Procedural music (music.js): no files, a small band synthesised into loops and cross-faded on
## the "Music" bus. The band: frame drums and war toms, a riq's jingles, hand claps, a smith's
## anvil, a low drone, a plucked lyre, a reed pipe (the aulos), bowed strings, a choir, a brass
## horn and a bell. Each piece has its own mode, key, tempo and band (STATES). A mood has a few
## pieces and plays them in turn (MOODS): each fight its own tune, the yard a new one after every
## fight. The menu is slow and quiet, the yard lively, a fight driving, a boss heavier and faster,
## a win a fanfare and a defeat a lament.
## Every piece is also recorded, played by real instruments (tools/make_music.py: frame drum,
## darbuka, harp, psaltery, oboe, horns, strings...) into art/audio/music/<piece>.ogg: that is what
## the game plays; the band synthesised here is the fallback when a file is missing.
## Loops are loaded (or rendered) on a worker thread the first time they are needed; in a quiet
## moment (the menu, the yard, the forge) the pieces likely next are made ready ahead.

const RATE := 22050
## The old Mediterranean "hijaz" (Phrygian dominant: D Eb F# G A Bb C): the first pieces' scale.
const SCALE := [0, 1, 4, 5, 7, 8, 10]
const ROOT := 146.83
const DORIAN := [0, 2, 3, 5, 7, 9, 10]
const MIXOLYDIAN := [0, 2, 4, 5, 7, 9, 10]
const AEOLIAN := [0, 2, 3, 5, 7, 8, 10]
const PHRYGIAN := [0, 1, 3, 5, 7, 8, 10]
const HARMONIC_MINOR := [0, 2, 3, 5, 7, 8, 11]
## Each piece. `chords` are the bars' harmony (scale degrees: the strings, pad, choir, bass, harp
## and horn follow it, the melody lands on it); a piece without them stays on its root.
const STATES := {
	"menu": {"bpm": 76, "drum": 0.0, "riq": 0.0, "drone": 0.7, "lyre": 0.55, "horn": 0.0, "density": 0.35, "bars": 8},
	# Dawn over the ludus: a reed pipe over a slow harp and a soft pad, in Dorian.
	"menu2": {"bpm": 66, "scale": DORIAN, "root": 164.81, "drone": 0.4, "pipe": 0.55, "arp": 0.3, "pad": 0.5, "density": 0.3, "chords": [0, 0, 3, 3, 6, 6, 0, 0], "bars": 8},
	"yard": {"bpm": 92, "drum": 0.25, "riq": 0.35, "drone": 0.5, "lyre": 0.6, "horn": 0.0, "density": 0.45, "bars": 8},
	# Market day: claps, jingles, a lilting pipe tune over a harp, in Mixolydian.
	"yard2": {"bpm": 104, "scale": MIXOLYDIAN, "root": 196.0, "drum": 0.3, "riq": 0.45, "clap": 0.45, "drone": 0.25, "pipe": 0.45, "arp": 0.28, "bass": 0.35, "density": 0.5, "swing": 0.16, "chords": [0, 6, 3, 0, 0, 6, 3, 4], "bars": 8},
	# The smithy: hammer on anvil in the beat, a low drone and the lyre, in Aeolian.
	"yard3": {"bpm": 86, "scale": AEOLIAN, "root": 130.81, "drum": 0.2, "anvil": 0.5, "anvil_pat": [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0], "drone": 0.55, "lyre": 0.55, "bass": 0.3, "density": 0.4, "chords": [0, 5, 6, 0, 0, 5, 3, 4], "bars": 8},
	# The forge: a slow working beat on the anvil under a harp, quiet enough to think by.
	"forge": {"bpm": 90, "scale": DORIAN, "root": 146.83, "anvil": 0.35, "anvil_pat": [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0], "drone": 0.4, "lyre": 0.35, "arp": 0.25, "pad": 0.3, "bass": 0.25, "density": 0.3, "chords": [0, 3, 0, 3, 6, 3, 0, 0], "bars": 8},
	"fight": {"bpm": 118, "drum": 0.85, "riq": 0.5, "drone": 0.4, "lyre": 0.4, "horn": 0.2, "bass": 0.7, "strings": 0.4, "stab": 0.3, "fills": 1.0, "density": 0.45, "bars": 16},
	# Blood on the sand: war toms in 3+3+2, Phrygian strings, a pipe and brass.
	"fight2": {"bpm": 126, "scale": PHRYGIAN, "root": 164.81, "drum": 0.55, "toms": 0.7, "toms_pat": [2, 0, 0, 1, 0, 0, 2, 0, 2, 0, 0, 1, 0, 0, 1, 1], "riq": 0.35, "drone": 0.35, "pipe": 0.3, "horn": 0.4, "bass": 0.75, "strings": 0.5, "stab": 0.35, "fills": 1.0, "density": 0.4, "chords": [0, 0, 1, 1, 0, 0, 6, 6], "bars": 16},
	# The gallop: a cavalry rhythm on the toms, harmonic minor, the horn carrying the tune.
	"fight3": {"bpm": 120, "scale": HARMONIC_MINOR, "root": 146.83, "drum": 0.45, "toms": 0.7, "toms_pat": [1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 0, 1, 1, 2, 2], "riq": 0.4, "drone": 0.3, "lyre": 0.25, "horn": 0.5, "horn_lead": true, "bass": 0.7, "strings": 0.45, "fills": 1.0, "density": 0.45, "chords": [0, 0, 5, 5, 3, 3, 4, 4], "bars": 16},
	# The hunt (a beast in the arena): tribal toms, a growling drone, the pipe's shrill calls.
	"beast": {"bpm": 132, "scale": PHRYGIAN, "root": 174.61, "drum": 0.55, "toms": 0.75, "toms_pat": [2, 0, 1, 0, 0, 1, 2, 0, 2, 0, 1, 1, 0, 1, 2, 1], "riq": 0.45, "drone": 0.45, "pipe": 0.35, "bass": 0.55, "strings": 0.35, "fills": 0.8, "density": 0.35, "chords": [0, 0, 0, 1], "bars": 16},
	"boss": {"bpm": 136, "drum": 1.0, "riq": 0.7, "drone": 0.5, "lyre": 0.25, "horn": 0.65, "bass": 0.9, "strings": 0.6, "stab": 0.7, "fills": 1.0, "density": 0.55, "bars": 16},
	# The colossus: a choir over war drums, the hijaz a semitone down.
	"boss2": {"bpm": 140, "scale": SCALE, "root": 138.59, "drum": 0.85, "toms": 0.65, "toms_pat": [2, 0, 0, 0, 2, 0, 1, 0, 2, 0, 0, 0, 2, 0, 1, 1], "riq": 0.55, "drone": 0.4, "choir": 0.5, "horn": 0.55, "bass": 0.75, "strings": 0.5, "stab": 0.55, "fills": 0.9, "density": 0.5, "chords": [0, 0, 1, 1, 0, 0, 3, 1], "bars": 16},
	"victory": {"bpm": 104, "drum": 0.6, "riq": 0.6, "drone": 0.4, "lyre": 0.6, "horn": 0.8, "density": 0.7, "bars": 2, "once": true},
	# Defeat: a short lament, a bell's toll and the horn falling to the root.
	"defeat": {"bpm": 58, "scale": AEOLIAN, "root": 146.83, "toll": 0.7, "drone": 0.4, "strings": 0.5, "horn": 0.6, "line": [[0, 4, 5], [6, 3, 4], [10, 2, 6], [16, 1, 5], [22, 0, 10]], "density": 0.0, "chords": [3, 0], "bars": 2, "once": true},
}
## The moods the game asks for, and the pieces each plays in turn.
const MOODS := {
	"menu": ["menu", "menu2"],
	"yard": ["yard", "yard2", "yard3"],
	"forge": ["forge"],
	"fight": ["fight", "fight2", "fight3"],
	"beast": ["beast"],
	"boss": ["boss", "boss2"],
	"victory": ["victory"],
	"defeat": ["defeat"],
}
const DUM := [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0]
const TEK := [0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
## The war drum's second pattern for the fight: a driving dum on every beat with a pickup.
const DUM2 := [1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 1, 0]
## The bass: an ostinato under the fight, root and fifth with a slide to the flat second (the
## hijaz's bite), in eighths.
const BASS := [0, 0, 4, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 7, 1, 0]
const BASS_ON := [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0]
## The harp's broken chord, an eighth each (degrees over the bar's chord).
const ARP := [0, 2, 4, 7, 4, 2, 4, 2]
## One period of each sustained voice, read back at any pitch (a table read instead of a sum of
## a dozen sines a sample: the long pieces render in a fraction of the time).
const TB := 512
const MUSIC_DIR := "res://art/audio/music/"
const PAD_W := [1.0, 0.35, 0.15, 0.08, 0.04]

var state := "off"      # the mood
var piece := ""         # the piece of it playing (or coming)
var turn := {}          # mood -> which of its pieces came last
var volume := 0.5
var cache := {}
var players: Array = []
var active := 0
var thread: Thread = null
var fade: Tween = null
var _before_bench := ""

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
	# Each game starts its moods at a piece of their own: not the same first fight every time.
	for m in MOODS:
		turn[m] = randi() % (MOODS[m] as Array).size() - 1

static func hz(deg: int, octave := 0) -> float:
	return hz_in(SCALE, ROOT, deg, octave)

## A degree of a piece's scale (`sc`, on `root`) as a pitch.
static func hz_in(sc: Array, root: float, deg: int, octave := 0) -> float:
	var m := sc.size()
	var d := posmod(deg, m)
	var o := octave + floori(deg / float(m))
	return root * pow(2.0, (float(sc[d]) + 12.0 * o) / 12.0)

## A bar's melody: a walk on the scale with the odd leap, landing on the bar's chord (`land`:
## its root or its fifth).
static func phrase(seed_: int, density: float, land := 0) -> Array:
	var s := (seed_ * 9301 + 49297) % 233280
	var notes := []
	var deg := 4
	for i in 16:
		s = (s * 9301 + 49297) % 233280
		var r := s / 233280.0
		if i == 14:
			notes.append({"step": i, "deg": land if r < 0.5 else (land + 4 if land + 4 <= 9 else land - 3), "len": 2})
			break
		if r < (density + 0.3 if i % 4 == 0 else density * 0.7):
			s = (s * 9301 + 49297) % 233280
			var r2 := s / 233280.0
			deg += (-3 if r2 < 0.07 else 3) if r2 < 0.15 else (-1 if r2 < 0.57 else 1)
			deg = clampi(deg, -2, 9)
			notes.append({"step": i, "deg": deg, "len": 2 if r2 > 0.7 else 1})
	return notes

## One period of a voice made of harmonics `w` (the first the fundamental).
static func _cycle(w: Array) -> PackedFloat32Array:
	var tb := PackedFloat32Array()
	tb.resize(TB + 1)
	for i in TB:
		var x := TAU * i / TB
		var v := 0.0
		for k in w.size():
			v += float(w[k]) * sin((k + 1) * x)
		tb[i] = v
	tb[TB] = tb[0]
	return tb

## A voice's period read at `cycles` periods in.
static func _at(tb: PackedFloat32Array, cycles: float) -> float:
	var p := (cycles - floorf(cycles)) * TB
	var i := int(p)
	return tb[i] + (tb[i + 1] - tb[i]) * (p - i)

## A choir's "ah" at `f`: the harmonics near the vowel's formants ring out.
static func _ah(f: float) -> Array:
	var w := []
	for k in range(1, 15):
		var fk := f * k
		w.append(0.2 / k + exp(-pow((fk - 730.0) / 170.0, 2.0)) + 0.7 * exp(-pow((fk - 1090.0) / 190.0, 2.0)) + 0.2 * exp(-pow((fk - 2440.0) / 320.0, 2.0)))
	return w

## Renders a piece's loop into 16-bit PCM.
static func render(name_: String) -> AudioStreamWAV:
	var st: Dictionary = STATES[name_]
	var sc: Array = st.get("scale", SCALE)
	var rt := float(st.get("root", ROOT))
	var step_s := 60.0 / float(st.bpm) / 4.0
	var bar_s := step_s * 16.0
	var bars := int(st.bars)
	var n := int(bars * 16 * step_s * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name_)
	_wrap = not st.get("once", false)
	var chords: Array = st.get("chords", [0])
	var swing := float(st.get("swing", 0.0))
	var drum := float(st.get("drum", 0.0))
	var riq := float(st.get("riq", 0.0))
	var lyre := float(st.get("lyre", 0.0))
	var horn := float(st.get("horn", 0.0))
	var dum: Array = st.get("dum", DUM)
	var dum2: Array = st.get("dum2", DUM2)
	var tek: Array = st.get("tek", TEK)
	var bass_pat: Array = st.get("bass_pat", BASS)
	var bass_on: Array = st.get("bass_on", BASS_ON)
	var saw6 := _cycle([1.0, 1.0 / 2, 1.0 / 3, 1.0 / 4, 1.0 / 5, 1.0 / 6])
	var saw7 := _cycle([1.0, 1.0 / 2, 1.0 / 3, 1.0 / 4, 1.0 / 5, 1.0 / 6, 1.0 / 7])
	var bowed := _cycle([1.0, 1.0 / 4, 1.0 / 9, 1.0 / 16, 1.0 / 25])
	var soft := _cycle(PAD_W)
	var ahs := {}
	# The drone: root and fifth, a slow swell, the whole way.
	if float(st.get("drone", 0.0)) > 0.0:
		var f0 := hz_in(sc, rt, 0, -1)
		var f1 := hz_in(sc, rt, 4, -1)
		for i in n:
			var t := float(i) / RATE
			var sw := 0.75 + 0.25 * sin(TAU * t / (bars * 16 * step_s) * 2.0)
			var v := sin(TAU * f0 * t) + 0.5 * sin(TAU * f0 * 2.0 * t) + 0.3 * sin(TAU * f0 * 3.0 * t) + 0.6 * sin(TAU * f1 * t)
			buf[i] += v * 0.05 * float(st.drone) * sw
	for bar in bars:
		var c := int(chords[bar % chords.size()])
		var mel := phrase(bar * 7 + hash(name_) % 97, float(st.density), c)
		for stp in 16:
			# (A lilt: the off sixteenths a little late.)
			var t0 := (bar * 16 + stp) * step_s + (swing * step_s if stp % 2 == 1 else 0.0)
			# Frame drum: the low "dum" and the high "tek" (the war drum's own pattern every other
			# four bars of a fight).
			if drum > 0.0:
				var driving: bool = float(st.get("bass", 0.0)) > 0.0 and (bar / 4) % 2 == 1
				if (dum2 if driving else dum)[stp]:
					_hit(buf, t0, 0.32, func(t): return (sin(TAU * (62.0 + 50.0 * exp(-t * 30.0)) * t) * 0.9 + rng.randf_range(-0.2, 0.2) * exp(-t * 40.0)) * exp(-t * 9.0) * 0.5 * drum)
				if tek[stp]:
					_hit(buf, t0, 0.08, func(t): return rng.randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.22 * drum)
			# Riq: jingles on the offbeats.
			if riq > 0.0 and stp % 2 == 1:
				_hit(buf, t0, 0.06, func(t): return (rng.randf_range(-1.0, 1.0) * sin(TAU * 5200.0 * t)) * exp(-t * 70.0) * 0.08 * riq)
			# The bass, on the bar's chord.
			if float(st.get("bass", 0.0)) > 0.0 and bass_on[stp]:
				# (An octave under the root, round tones: two octaves down with a square edge on it
				# was a sub-bass rumble most speakers could only buzz and crackle at.)
				var fb := hz_in(sc, rt, int(bass_pat[stp]) + c, -1)
				_hit(buf, t0, step_s * 1.9, func(t): return (sin(TAU * fb * t) + 0.35 * sin(TAU * fb * 2.0 * t) + 0.12 * sin(TAU * fb * 3.0 * t)) * minf(1.0, t * 90.0) * exp(-t * 4.0) * 0.16 * float(st.bass))
			# Fills: a roll of the drum into every fourth bar, and a crash of jingles on the one.
			if float(st.get("fills", 0.0)) > 0.0 and bar % 4 == 3 and stp >= 12:
				for sub in 2:
					_hit(buf, t0 + sub * step_s * 0.5, 0.12, func(t): return (sin(TAU * (90.0 + 60.0 * exp(-t * 30.0)) * t) * 0.8 + rng.randf_range(-0.3, 0.3) * exp(-t * 40.0)) * exp(-t * 14.0) * 0.4 * float(st.fills))
			if float(st.get("fills", 0.0)) > 0.0 and bar % 4 == 0 and stp == 0:
				_hit(buf, t0, 0.5, func(t): return rng.randf_range(-1.0, 1.0) * (0.6 + 0.4 * sin(TAU * 4100.0 * t)) * exp(-t * 7.0) * 0.14 * float(st.fills))
			# Brass stabs: short horn chords on the pickup to the one and on the three.
			if float(st.get("stab", 0.0)) > 0.0 and (stp == 8 or stp == 15) and bar % 2 == 1:
				var fs := hz_in(sc, rt, (0 if stp == 8 else 1) + c, 0)
				_hit(buf, t0, step_s * 1.5, func(t): return (_at(saw7, fs * t) + 0.8 * _at(saw7, fs * 1.5 * 1.002 * t)) * minf(1.0, t * 40.0) * exp(-t * 5.0) * 0.07 * float(st.stab))
			# War toms: the low one heavy, the high one a crack (each strike falls in pitch).
			if float(st.get("toms", 0.0)) > 0.0:
				var tp: Array = st.get("toms_pat", [])
				var kind := int(tp[stp]) if stp < tp.size() else 0
				if kind > 0:
					var ftop := 150.0 if kind == 1 else 92.0
					var fbot := 108.0 if kind == 1 else 60.0
					var amp := (0.3 if kind == 1 else 0.48) * float(st.toms) * (1.0 if stp % 4 == 0 else 0.8)
					var zt := [0.0]
					_hit(buf, t0, 0.42 if kind == 2 else 0.28, func(t):
						var ph: float = TAU * (fbot * t + (ftop - fbot) * (1.0 - exp(-t * 22.0)) / 22.0)
						zt[0] += (rng.randf_range(-1.0, 1.0) - zt[0]) * 0.3
						return (sin(ph) * exp(-t * (7.0 if kind == 2 else 10.0)) + zt[0] * 0.6 * exp(-t * 45.0)) * amp)
			# The anvil: a hammer's ring (a few inharmonic partials) and its thunk.
			if float(st.get("anvil", 0.0)) > 0.0:
				var ap: Array = st.get("anvil_pat", [])
				if stp < ap.size() and int(ap[stp]) > 0:
					var fa := 1180.0 * rng.randf_range(0.99, 1.01)
					var aa := 0.055 * float(st.anvil) * (1.0 if stp % 8 == 0 else 0.6)
					_hit(buf, t0, 0.7, func(t):
						var ring := sin(TAU * fa * t) * exp(-t * 5.0) + 0.45 * sin(TAU * fa * 2.756 * t) * exp(-t * 9.0) + 0.2 * sin(TAU * fa * 5.404 * t) * exp(-t * 16.0)
						return (ring + sin(TAU * 210.0 * t) * exp(-t * 30.0) * 0.6 + rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.5) * aa)
			# Hand claps on two and four: three quick slaps and a tail, the noise in a clap's band.
			if float(st.get("clap", 0.0)) > 0.0 and (stp == 4 or stp == 12):
				var zc := [0.0, 0.0]
				var ca := 0.4 * float(st.clap)
				_hit(buf, t0, 0.2, func(t):
					var e := exp(-t * 28.0) * 0.5
					for k in 3:
						if t >= k * 0.011:
							e += exp(-(t - k * 0.011) * 350.0)
					zc[0] += (rng.randf_range(-1.0, 1.0) - zc[0]) * 0.57
					zc[1] += (zc[0] - zc[1]) * 0.2
					return (zc[0] - zc[1]) * e * ca)
			# The harp: the bar's chord broken in eighths.
			if float(st.get("arp", 0.0)) > 0.0 and stp % 2 == 0:
				var fh2 := hz_in(sc, rt, c + int(ARP[stp / 2]), 0)
				var arpa := 0.08 * float(st.arp)
				_hit(buf, t0, 0.9, func(t): return (sin(TAU * fh2 * t) + 0.4 * sin(TAU * fh2 * 2.0 * t) * exp(-t * 4.0)) * exp(-t * 4.0) * minf(1.0, t * 400.0) * arpa)
		# Lyre: plucked, a few partials ringing down.
		if lyre > 0.0:
			for note in mel:
				var f := hz_in(sc, rt, int(note.deg), 1)
				var dur := 1.1 + 0.4 * int(note.len)
				_hit(buf, (bar * 16 + int(note.step)) * step_s + (swing * step_s if int(note.step) % 2 == 1 else 0.0), dur, func(t): return (sin(TAU * f * t) + 0.45 * sin(TAU * f * 2.0 * t) * exp(-t * 3.0) + 0.2 * sin(TAU * f * 3.0 * t) * exp(-t * 6.0)) * exp(-t * 2.6) * minf(1.0, t * 400.0) * 0.12 * lyre)
		# The pipe (the aulos): the tune held note to note, with breath and a vibrato that grows.
		if float(st.get("pipe", 0.0)) > 0.0:
			for k in mel.size():
				var note: Dictionary = mel[k]
				var nxt := int(mel[k + 1].step) if k + 1 < mel.size() else 18
				var dur := maxf(step_s, (nxt - int(note.step)) * step_s * 0.92)
				var fp := hz_in(sc, rt, int(note.deg), 1)
				var pa := 0.1 * float(st.pipe)
				var zp := [0.0]
				_hit(buf, (bar * 16 + int(note.step)) * step_s + (swing * step_s if int(note.step) % 2 == 1 else 0.0), dur, func(t):
					var ph: float = TAU * fp * t - (fp * 0.007 * minf(1.0, t * 2.5) / 5.2) * cos(TAU * 5.2 * t)
					zp[0] += (rng.randf_range(-1.0, 1.0) - zp[0]) * 0.25
					var breath: float = zp[0] * (0.08 + 0.5 * exp(-t * 25.0))
					return (sin(ph) + 0.22 * sin(2.0 * ph) + 0.07 * sin(3.0 * ph) + breath) * minf(1.0, t * 18.0) * minf(1.0, (dur - t) * 12.0) * pa)
		# The horn as the lead: the tune itself, held note to note.
		if horn > 0.0 and st.get("horn_lead", false):
			for k in mel.size():
				var note: Dictionary = mel[k]
				var nxt := int(mel[k + 1].step) if k + 1 < mel.size() else 18
				var dur := maxf(step_s, (nxt - int(note.step)) * step_s * 0.95)
				var fl := hz_in(sc, rt, int(note.deg), 0)
				_hit(buf, (bar * 16 + int(note.step)) * step_s, dur, func(t): return _at(saw6, fl * (1.0 + 0.006 * sin(TAU * 5.5 * t)) * t) * minf(1.0, t * 14.0) * minf(1.0, (dur - t) * 8.0) * 0.07 * horn)
		# Strings: a tremolo pad of detuned bowed voices on the chord's root and fifth, swelling
		# into the second half of each four bars (the tension under a fight).
		if float(st.get("strings", 0.0)) > 0.0:
			var fr := hz_in(sc, rt, c, 0)
			var ff := hz_in(sc, rt, c + 4, 0)
			var swell := 0.4 + 0.6 * float(bar % 4) / 3.0
			_hit(buf, bar * bar_s, bar_s, func(t):
				var trem := 0.75 + 0.25 * sin(TAU * 9.0 * t)
				var v := 0.0
				for det in [0.996, 1.0, 1.004]:
					v += _at(bowed, fr * det * t) + 0.6 * _at(bowed, ff * det * t)
				return v * trem * swell * minf(1.0, t * 6.0) * minf(1.0, (bar_s - t) * 6.0) * 0.045 * float(st.strings))
		# A soft pad, or a choir singing "ah", on the bar's chord (each bar's chord breathes into
		# the next).
		var pad := float(st.get("pad", 0.0))
		var choir := float(st.get("choir", 0.0))
		if pad > 0.0 or choir > 0.0:
			for d in [c, c + 2, c + 4]:
				var fpd := hz_in(sc, rt, d, 0)
				if choir > 0.0 and not ahs.has(d):
					ahs[d] = _cycle(_ah(fpd))
				var tb: PackedFloat32Array = ahs[d] if choir > 0.0 else soft
				var g := 0.016 * choir * (0.5 + 0.5 * float(bar % 4) / 3.0) if choir > 0.0 else 0.03 * pad
				var hold := bar_s + 0.6
				_hit(buf, bar * bar_s, hold, func(t):
					var vib := 1.0 + 0.004 * sin(TAU * 4.8 * t)
					return (_at(tb, fpd * 0.997 * t) + _at(tb, fpd * 1.003 * vib * t)) * minf(1.0, t * 1.6) * minf(1.0, (hold - t) / 0.6) * g)
		# Horn: a long call on the strong beats of every other bar.
		if horn > 0.0 and not st.get("horn_lead", false) and not st.has("line") and (bar % 2 == 1 or st.get("once", false)):
			for k in [0, 8]:
				var deg2: int = [4, 2, 0, 4][(bar + k / 8) % 4] + c
				var fh := hz_in(sc, rt, deg2, 0)
				var len_s := step_s * 6.0
				_hit(buf, (bar * 16 + k) * step_s, len_s, func(t): return _at(saw6, fh * (1.0 + 0.006 * sin(TAU * 5.5 * t)) * t) * minf(1.0, t * 14.0) * minf(1.0, (len_s - t) * 8.0) * 0.07 * horn)
		# A bell's toll on the one, low, ringing long.
		if float(st.get("toll", 0.0)) > 0.0:
			var ft := hz_in(sc, rt, c, -1)
			var ta := 0.2 * float(st.toll)
			_hit(buf, bar * bar_s, minf(4.0, bar_s), func(t): return (sin(TAU * ft * t) * exp(-t * 0.9) + 0.5 * sin(TAU * ft * 2.0 * t) * exp(-t * 1.4) + 0.35 * sin(TAU * ft * 2.4 * t) * exp(-t * 2.0) + 0.2 * sin(TAU * ft * 3.0 * t) * exp(-t * 2.6) + 0.12 * sin(TAU * ft * 4.2 * t) * exp(-t * 3.5)) * minf(1.0, t * 200.0) * ta)
	# A set line for the horn (the lament): [step, degree, steps held].
	for nt in st.get("line", []):
		var fl2 := hz_in(sc, rt, int(nt[1]), 0)
		var dl := float(nt[2]) * step_s
		_hit(buf, float(nt[0]) * step_s, dl, func(t): return _at(saw6, fl2 * (1.0 + 0.007 * sin(TAU * 5.0 * t) * minf(1.0, t * 2.0)) * t) * minf(1.0, t * 10.0) * minf(1.0, (dl - t) * 3.0) * 0.08 * horn)
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

## A note into the loop. What still rings past the loop's end goes round onto its start (the
## loop is seamless: no tail cut off, no stumble in the beat where it comes round).
static var _wrap := true

static func _hit(buf: PackedFloat32Array, t0: float, dur: float, f: Callable) -> void:
	var n := buf.size()
	var i0 := int(t0 * RATE)
	var cnt := mini(int(dur * RATE), n)
	# Every note let go over its last few milliseconds: cut off where it still sounded, each one
	# ended in a click, and the clicks of a fight's notes were a crackle under the whole bout.
	var rel := maxi(1, mini(int(0.008 * RATE), cnt / 4))
	for j in cnt:
		var i := i0 + j
		if i >= n:
			if not _wrap:
				break
			i -= n
		var v: float = f.call(float(j) / RATE)
		if j >= cnt - rel:
			v *= float(cnt - j) / rel
		buf[i] += v

## The piece a mood plays now: the next of its pieces in turn, or (`again`) the one it played
## last (back from the forge to the same yard tune).
func pick(mood: String, again := false) -> String:
	var list: Array = MOODS.get(mood, [mood])
	var i := int(turn.get(mood, -1))
	if not again or i < 0:
		i = (i + 1) % list.size()
		turn[mood] = i
	return list[i]

## The piece a mood would play next, without moving on.
func peek(mood: String) -> String:
	var list: Array = MOODS.get(mood, [mood])
	return list[(int(turn.get(mood, -1)) + 1) % list.size()]

## Switches the music to a mood ("off" for silence), cross-fading; `again` plays the mood's last
## piece once more instead of its next.
func set_state(s: String, again := false) -> void:
	if s == state or DisplayServer.get_name() == "headless":
		return
	state = s
	if not MOODS.has(s) and not STATES.has(s):
		piece = ""
		_fade_to(null)
		return
	piece = pick(s, again) if MOODS.has(s) else s
	if cache.has(piece):
		_fade_to(cache[piece])
		_prerender()
	elif thread == null:
		_start(piece)
	# (else: the piece being made now finishes first, then this one)

## A forge (for weapons or armour) opened: its own music; closed: back to the tune before it.
func bench(on: bool) -> void:
	if on:
		# (Back from trying a weapon in the arena the forge opens again over the fight's tune:
		# what it goes back to is still the menu's or the yard's.)
		if state == "menu" or state == "yard":
			_before_bench = state
		set_state("forge")
	elif state == "forge":
		set_state(_before_bench if _before_bench != "" else "menu", true)

func _start(p: String) -> void:
	thread = Thread.new()
	thread.start(_render_job.bind(p))

## A piece as played by real instruments, when its file is there (null when not).
static func recorded(name_: String) -> AudioStream:
	var path := MUSIC_DIR + name_ + ".ogg"
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
	elif FileAccess.file_exists(path):
		st = AudioStreamOggVorbis.load_from_file(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = not STATES[name_].get("once", false)
	return st

func _render_job(p: String) -> void:
	var w: AudioStream = recorded(p)
	if w == null:
		w = render(p)
	call_deferred("_rendered", p, w)

func _rendered(p: String, w: AudioStream) -> void:
	cache[p] = w
	if thread:
		thread.wait_to_finish()
		thread = null
	if piece == p:
		_fade_to(w)
	if piece != "" and not cache.has(piece):
		_start(piece)
	else:
		_prerender()

## In a quiet moment (the menu, the yard, the forge) the pieces likely next are made ready ahead,
## one at a time: a fight's tune comes in with the fight, not seconds into it.
func _prerender() -> void:
	if thread != null or not ["menu", "yard", "forge"].has(state):
		return
	for m in ["fight", "beast", "boss", "victory", "defeat", "yard", "menu", "forge"]:
		var p := peek(m)
		if not cache.has(p):
			_start(p)
			return

## One loop at a time: the one playing fades out and stops while the next fades in. A fade
## still going is cut short first, so two quick changes never leave two loops playing over
## each other (the music doubled, out of step with itself).
func _fade_to(stream) -> void:
	if fade and fade.is_valid():
		fade.kill()
	var old: AudioStreamPlayer = players[active]
	active = 1 - active
	var nu: AudioStreamPlayer = players[active]
	nu.stop()
	fade = create_tween().set_parallel()
	fade.tween_property(old, "volume_db", -60.0, 1.2)
	if stream:
		nu.stream = stream
		nu.volume_db = -60.0
		nu.play()
		fade.tween_property(nu, "volume_db", linear_to_db(maxf(0.001, volume * 0.8)), 1.5)
	fade.chain().tween_callback(old.stop)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	var p: AudioStreamPlayer = players[active]
	if p.playing:
		p.volume_db = linear_to_db(maxf(0.001, volume * 0.8))

func _exit_tree() -> void:
	if thread:
		thread.wait_to_finish()
