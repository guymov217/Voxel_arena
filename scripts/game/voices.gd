class_name Voices
## Who sounds how: the call each beast makes, what a man cries when struck, and how deep a
## throat is (by the size of the body). DOM-free; the sounds themselves are Sfx's.

const KINDS := ["grunt", "pain", "scream", "growl", "hiss", "trumpet", "screech", "roar"]

const CALLS := {
	"lion": "roar", "tiger": "roar", "bear": "roar", "gorilla": "roar", "wolf": "growl", "hyena": "growl", "rat": "screech",
	"boar": "growl", "bull": "growl", "rhino": "growl", "goat": "screech",
	"crocodile": "hiss", "python": "hiss", "basilisk": "hiss", "scorpion": "hiss", "spider": "hiss",
	"elephant": "trumpet", "mammoth": "trumpet",
	"ostrich": "screech", "griffin": "screech",
	"cerberus": "roar", "hydra": "roar", "chimera": "roar", "manticore": "roar", "dragon": "roar",
}

## The giants of myth with a rendered voice of their own (mods.voice, set for a boss).
const GIANTS := ["cyclops", "giant", "minotaur", "troll", "titan"]

static func giant_voice(f) -> String:
	var mods = f.get("mods")
	if mods is Dictionary and GIANTS.has(String(mods.get("voice", ""))):
		return String(mods.voice)
	return ""

static func beast_call(species: String) -> String:
	return CALLS.get(species, "growl")

## How loud a species calls, against the rest (the hydra's roar was a din).
const CALL_GAIN := {"hydra": 0.45, "cerberus": 0.8, "python": 0.4, "basilisk": 0.7}
static func call_gain(species: String) -> float:
	return float(CALL_GAIN.get(species, 1.0))

## How deep the voice: a man at 1.0, the big lower (a giant three times a man's size at 0.55),
## the small higher.
static func pitch_of(f) -> float:
	var s: float = float(f.get("S")) if f.get("S") != null else 1.0
	var p := 1.0 / sqrt(maxf(0.4, s))
	if f.get("kind") == "beast":
		p *= 1.1
	elif f.get("skin") is Color:
		# Each man his own throat, a little above or below, by his look.
		p *= 0.92 + 0.16 * fmod(float(f.skin.r) * 7.0 + float(f.skin.g) * 13.0, 1.0)
	return clampf(p, 0.4, 2.2)

## The depth a species' rendered voice was made at: its usual size (the files are only shifted
## for a beast scaled away from it, or a giant of a man).
static func pitch_of_species(f) -> float:
	if f.get("kind") == "beast":
		var base: float = float(Data.beasts.get(String(f.species), {}).get("scale", f.get("S")))
		return clampf(1.1 / sqrt(maxf(0.4, base)), 0.4, 2.2)
	if giant_voice(f) != "":
		return pitch_of(f)  # rendered at his own depth already
	return 1.0

## What one cries when struck: a man a grunt or a cry, a scream for a lost limb or a death blow;
## a beast its own call (a sting of pain for the small ones).
static func hurt_call(f, J: float, grave: bool) -> String:
	if f.get("kind") == "beast":
		var c := beast_call(String(f.species))
		return c if (grave or J > 14.0) else ("screech" if c == "screech" else ("hiss" if c == "hiss" else "growl"))
	if grave:
		return "scream"
	return "pain" if J > 11.0 else "grunt"

## Which of the three men's throats a fighter has: by his size first (a big man speaks from
## the heavy one, a small one from the light), and among men of a size by chance, fixed for
## each man (his name and his colours), so he sounds the same every time he is met.
static func throat_of(f) -> String:
	var s: float = float(f.get("S")) if f.get("S") != null else 1.0
	if s >= 1.15:
		return "man_heavy"
	if s <= 0.9:
		return "man_light"
	var h := hash(String(f.get("display_name")))
	if f.get("skin") is Color:
		h = hash([h, f.skin.to_html()])
	match absi(h) % 3:
		0: return "man_light"
		1: return "man_heavy"
	return "man_mid"

## The rendered voice for an event: "lion_call", "elephant_hurt", "man_mid_scream"...
static func file_key(f, event: String) -> String:
	if f.get("kind") == "beast":
		return "%s_%s" % [String(f.species), event if ["call", "hurt", "death"].has(event) else "call"]
	var g := giant_voice(f)
	if g != "":
		return "%s_%s" % [g, "death" if event == "death" else ("call" if ["call", "effort"].has(event) else "hurt")]
	var t := throat_of(f)
	match event:
		"call", "effort": return t + "_effort"
		"grunt": return t + "_grunt"
		"hurt": return t + "_pain"
		"grave": return t + "_scream"
		"death": return t + "_death"
	return t + "_grunt"

static func death_call(f) -> String:
	if f.get("kind") == "beast":
		return beast_call(String(f.species))
	return "scream"
