class_name Voices
## Who sounds how: the call each beast makes, what a man cries when struck, and how deep a
## throat is (by the size of the body). DOM-free; the sounds themselves are Sfx's.

const KINDS := ["grunt", "pain", "scream", "growl", "hiss", "trumpet", "screech", "roar"]

const CALLS := {
	"lion": "roar", "tiger": "roar", "bear": "roar", "wolf": "growl", "hyena": "growl", "rat": "screech",
	"boar": "growl", "bull": "growl", "rhino": "growl", "goat": "screech",
	"crocodile": "hiss", "python": "hiss", "basilisk": "hiss", "scorpion": "hiss", "spider": "hiss",
	"elephant": "trumpet", "mammoth": "trumpet",
	"ostrich": "screech", "griffin": "screech",
	"cerberus": "roar", "hydra": "roar", "chimera": "roar", "manticore": "roar", "dragon": "roar",
}

static func beast_call(species: String) -> String:
	return CALLS.get(species, "growl")

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

## What one cries when struck: a man a grunt or a cry, a scream for a lost limb or a death blow;
## a beast its own call (a sting of pain for the small ones).
static func hurt_call(f, J: float, grave: bool) -> String:
	if f.get("kind") == "beast":
		var c := beast_call(String(f.species))
		return c if (grave or J > 14.0) else ("screech" if c == "screech" else ("hiss" if c == "hiss" else "growl"))
	if grave:
		return "scream"
	return "pain" if J > 11.0 else "grunt"

static func death_call(f) -> String:
	if f.get("kind") == "beast":
		return beast_call(String(f.species))
	return "scream"
