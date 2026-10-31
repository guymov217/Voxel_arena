class_name Body
extends RefCounted
## The gladiator's body between fights in the campaign (physician.js, extended): the limbs he
## has lost, what replaced them, every hole the fights left in him (healed over into a dent the
## shape of the blow), and his eyes. It is read off his fighter after every round, the physician
## sees to it for a price, and a new campaign (or a fall back to the checkpoint) starts him whole.
## Plain data, so it is saved as it is and sent over the network to the host in co-op.

## What each prosthetic replaces, and what it costs.
const PROSTHETICS := {
	"peg": {"name": "Peg leg", "parts": ["shinL", "shinR"], "price": 40,
		"desc": "A wooden shin, strapped on below the knee. Does not bleed. You walk again, slower, and a peg is never a foot."},
	"hook": {"name": "Hook hand", "parts": ["forearmL", "forearmR"], "price": 40,
		"desc": "An iron hook in place of the hand. It cannot hold a weapon, but it rips."},
	"blade": {"name": "Blade arm", "parts": ["forearmL", "forearmR"], "price": 75,
		"desc": "A blade riveted to the stump. It can never be dropped or knocked away, and it is clumsy: the arm swings it slower and less surely than a hand would."},
	"glassEye": {"name": "Glass eye", "parts": ["eyeL", "eyeR"], "price": 50,
		"desc": "A fine Egyptian glass eye. Nobody can say how, but the world on that side comes back, most of it."},
}
## How well a replaced part works (1 for a whole one): walking on a peg, swinging a fixed blade.
const PROSTHETIC_FN := {"peg": 0.6, "hook": 0.75, "blade": 0.7}
## The rare medicine (one old wound closed): half the elixir's price, so both follow the pay.
const MEDICINE_BOUTS := 1.5
const MEDICINE_MIN := 30
## The physician's dearest bottle: it gives back all a campaign took (limbs, eyes, old wounds).
## It costs what a few bouts at this point of the campaign pay (ELIXIR_BOUTS of them): dear, but
## within reach of a man who saves for it, early on as late.
const ELIXIR_BOUTS := 3.0
const ELIXIR_MIN := 60

## What winning the bout at `stage` pays one man (its stage pay and its round, as Match pays them).
static func bout_pay(stage: int) -> int:
	var st := Data.stage(maxi(1, stage), 1)
	return int(round(float(st.get("stagePay", 30)) * Match.PAY_SCALE)) + int(round(float(st.get("roundPay", 10)) * Match.PAY_SCALE))

static func elixir_price(stage: int) -> int:
	return maxi(ELIXIR_MIN, roundi(ELIXIR_BOUTS * bout_pay(stage)))

static func medicine_price(stage: int) -> int:
	return maxi(MEDICINE_MIN, roundi(MEDICINE_BOUTS * bout_pay(stage)))
## Broken bones carried out of a fight (`fractures`): a limb's by its part name, 1 cracked, 2
## broken through under the skin, 3 broken out through it; "skull" the same; "ribs" how many;
## "pelvis" 1. They stay as they are, a broken limb no use, until the physician sets them (no
## elixir needed: a bone knits, a hand does not grow back). What setting costs, in bouts' pay.
const SET_BOUTS := {1: 0.25, 2: 0.5, 3: 0.8}
const SET_MIN := {1: 8, 2: 15, 3: 25}
const RIB_BOUTS := 0.12
const BONES := {"skull": "skull", "ribs": "ribs", "pelvis": "pelvis"}

static func set_price(key: String, lv: int, stage: int) -> int:
	if key == "ribs":
		return maxi(6 * lv, roundi(RIB_BOUTS * lv * bout_pay(stage)))
	if key == "pelvis":
		lv = 2
	lv = clampi(lv, 1, 3)
	var k := 1.5 if key == "skull" else 1.0
	return maxi(roundi(SET_MIN[lv] * k), roundi(SET_BOUTS[lv] * k * bout_pay(stage)))

static func bone_label(key: String) -> String:
	return BONES.get(key, label(key))

## What is wrong with a bone, in a few words.
static func break_words(key: String, lv: int) -> String:
	if key == "ribs":
		return "%d broken rib%s" % [lv, "s" if lv > 1 else ""]
	if key == "pelvis":
		return "a cracked pelvis"
	return ["", "a cracked %s", "a broken %s", "an open break of the %s"][clampi(lv, 1, 3)] % bone_label(key)

## The most of a part's voxels an old wound may leave missing for good.
const SCAR_CAP := {"head": 0.18, "torso": 0.25}
const SCAR_CAP_LIMB := 0.3

static func empty() -> Dictionary:
	return {"missing": [], "prosthetics": {}, "scars": {}, "eyes": {}, "fights": 0, "fresh": {}, "fractures": {}}

static func part_names() -> Array:
	return Data.body_parts.map(func(d): return String(d.name))

static func voxel_count(name: String) -> int:
	for d in Data.body_parts:
		if d.name == name:
			return d.voxels.size()
	return 0

## A body from a save or from the wire: only real parts, sane indices, nothing contradictory.
static func sanitize(raw) -> Dictionary:
	var b := empty()
	if not (raw is Dictionary):
		return b
	var names := part_names()
	for n in raw.get("missing", []) if raw.get("missing") is Array else []:
		if names.has(str(n)) and str(n) != "torso" and str(n) != "head" and not b.missing.has(str(n)):
			b.missing.append(str(n))
	var pro = raw.get("prosthetics", {})
	if pro is Dictionary:
		for k in pro:
			var kind := str(pro[k])
			if PROSTHETICS.has(kind) and PROSTHETICS[kind].parts.has(str(k)):
				b.prosthetics[str(k)] = kind
	var sc = raw.get("scars", {})
	if sc is Dictionary:
		for k in sc:
			var n := str(k)
			if not names.has(n) or not (sc[k] is Array):
				continue
			var total := voxel_count(n)
			var cap := int(total * float(SCAR_CAP.get(n, SCAR_CAP_LIMB)))
			var seen := {}
			var list := []
			for i in sc[k]:
				var ii := int(i)
				if ii >= 0 and ii < total and not seen.has(ii) and list.size() < cap:
					seen[ii] = true
					list.append(ii)
			if not list.is_empty():
				b.scars[n] = list
	var ey = raw.get("eyes", {})
	if ey is Dictionary:
		for s in ["L", "R"]:
			var v := str(ey.get(s, ""))
			if v == "lost" or v == "glass":
				b.eyes[s] = v
	b.fights = maxi(0, int(raw.get("fights", 0)))
	var fx = raw.get("fractures", {})
	if fx is Dictionary:
		for k in fx:
			var key := str(k)
			var lv := int(fx[k]) if (fx[k] is int or fx[k] is float) else 0
			if key == "ribs":
				lv = clampi(lv, 0, 12)
			elif key == "pelvis":
				lv = clampi(lv, 0, 1)
			elif key == "skull" or (names.has(key) and key != "torso" and key != "head"):
				lv = clampi(lv, 0, 3)
			else:
				lv = 0
			if lv > 0:
				b.fractures[key] = lv
	# A part replaced is not missing; a part missing has no scar, and nor does what hangs off it.
	for k in b.prosthetics.keys():
		if k.begins_with("eye"):
			continue
		b.missing.erase(k)
	for n in b.missing:
		b.scars.erase(n)
		for c in children_of(n):
			b.scars.erase(c)
	for k in b.prosthetics:
		b.scars.erase(k)
		b.fractures.erase(k)
	for n in b.missing:
		b.fractures.erase(n)
		for c in children_of(n):
			b.fractures.erase(c)
	# The wounds of the last fight, still open: a part of its scars the physician can still close.
	var fr = raw.get("fresh", {})
	if fr is Dictionary:
		for k in fr:
			var n := str(k)
			if b.scars.has(n) and fr[k] is Array:
				var have := {}
				for i in b.scars[n]:
					have[int(i)] = true
				var keep := []
				for i in fr[k]:
					if have.has(int(i)) and not keep.has(int(i)):
						keep.append(int(i))
				if not keep.is_empty():
					b.fresh[n] = keep
	return b

## Every part hanging off `name` (a lost thigh takes the shin with it).
static func children_of(name: String) -> Array:
	var out := []
	var stack := [name]
	while not stack.is_empty():
		var n: String = stack.pop_back()
		for d in Data.body_parts:
			if d.parent == n:
				out.append(String(d.name))
				stack.append(String(d.name))
	return out

## The eye cells on the face of a human head (character.js: coarse cells (1,3) and (3,3) on the
## front): the fine voxels of each. R is the low-x one, the right side of the body.
static func eye_voxels(head: VoxelPart, side: String) -> Array:
	var res := int(Data.body_res)
	var ix := 1 if side == "R" else 3
	var out := []
	for i in head.fx.size():
		if int(head.fx[i] / res) == ix and int(head.fy[i] / res) == 3 and int(head.fz[i] / res) == head.dims.z - 1:
			out.append(i)
	return out

## What a fight left on him, read off his fighter.
static func snapshot(f) -> Dictionary:
	var snap := {"lost": [], "holes": {}, "eyes_lost": []}
	for p in f.parts:
		var n := String(p.part_name)
		if n == "torso" or n == "head":
			continue
		if p.severed and not p.missing:
			snap.lost.append(n)
	for p in f.parts:
		if p.severed or p.missing or p.prosthetic != "":
			continue
		var dead := []
		for i in p.fx.size():
			if p.alive[i] == 0:
				dead.append(i)
		if not dead.is_empty():
			snap.holes[String(p.part_name)] = dead
	var fr := {}
	for p in f.parts:
		var n := String(p.part_name)
		if n != "torso" and n != "head" and not p.severed and not p.missing and p.prosthetic == "" and p.fracture > 0:
			fr[n] = int(p.fracture)
	if int(f.get("skull_fracture")) > 0 and not f.head.severed:
		fr["skull"] = int(f.skull_fracture)
	if int(f.ribs_broken) > 0:
		fr["ribs"] = int(f.ribs_broken)
	if float(f.pelvis_f) < 1.0:
		fr["pelvis"] = 1
	snap["fractures"] = fr
	if not f.head.severed:
		for s in ["L", "R"]:
			var ev := eye_voxels(f.head, s)
			var gone := ev.filter(func(i): return f.head.alive[i] == 0).size()
			if not ev.is_empty() and gone * 2 > ev.size():
				snap.eyes_lost.append(s)
	return snap

## Fold a snapshot into the body. Returns {body, news: [...], doctor: bool}: `doctor` when he
## lost a hand, a foot, a whole limb or an eye this time, and should be taken to the physician.
static func merge(body: Dictionary, snap: Dictionary) -> Dictionary:
	var b := sanitize(body)
	var news := []
	var doctor := false
	for n in snap.get("lost", []):
		if b.missing.has(n):
			continue
		var had: String = b.prosthetics.get(n, "")
		b.prosthetics.erase(n)
		# Only the top of what came off counts: the shin went with the thigh.
		var parent := ""
		for d in Data.body_parts:
			if d.name == n:
				parent = str(d.parent) if d.parent != null else ""
		if not snap.lost.has(parent):
			news.append(("lost the %s" % label(n)) if had == "" else ("the %s was knocked off" % PROSTHETICS[had].name.to_lower()))
			doctor = doctor or n.begins_with("forearm") or n.begins_with("upperArm") or n.begins_with("shin") or n.begins_with("thigh")
		b.missing.append(n)
	# Last fight's wounds left unstitched have healed over into scars for good; this fight's
	# are fresh, for the physician to close.
	b.fresh = {}
	for n in snap.get("holes", {}):
		if b.missing.has(n):
			continue
		var old: Array = b.scars.get(n, [])
		var had := old.size()
		var seen := {}
		for i in old:
			seen[i] = true
		var new_ones := []
		for i in snap.holes[n]:
			if not seen.has(i):
				old.append(i)
				new_ones.append(i)
				seen[i] = true
		b.scars[n] = old
		if not new_ones.is_empty():
			b.fresh[n] = new_ones
		if old.size() > had:
			news.append("a new scar on the %s" % label(n))
	for s in snap.get("eyes_lost", []):
		if not b.eyes.has(s):
			b.eyes[s] = "lost"
			news.append("lost the %s eye" % ("right" if s == "R" else "left"))
			doctor = true
	var fr: Dictionary = snap.get("fractures", {})
	for k in fr:
		var lv := int(fr[k])
		var had := int(b.fractures.get(k, 0))
		if lv > had and not b.missing.has(k):
			b.fractures[k] = lv
			news.append(break_words(k, lv))
			# Broken through (a limb, the skull driven in, ribs in the lung's way): to the physician.
			doctor = doctor or (k != "ribs" and lv >= 2) or (k == "ribs" and lv >= 3)
	b.fights = int(b.fights) + 1
	return {"body": sanitize(b), "news": news, "doctor": doctor}

static func label(n: String) -> String:
	for d in Data.body_parts:
		if d.name == n:
			return String(d.label).to_lower()
	return n

## One line about the state of him.
static func summary(body: Dictionary) -> String:
	var b := sanitize(body)
	var bits := []
	for n in b.missing:
		var parent := ""
		for d in Data.body_parts:
			if d.name == n:
				parent = str(d.parent) if d.parent != null else ""
		if not b.missing.has(parent):
			bits.append("no " + label(n))
	for k in b.prosthetics:
		bits.append(PROSTHETICS[b.prosthetics[k]].name.to_lower())
	for s in b.eyes:
		bits.append(("glass %s eye" if b.eyes[s] == "glass" else "blind in the %s eye") % ("right" if s == "R" else "left"))
	for k in b.fractures:
		bits.append(break_words(k, int(b.fractures[k])))
	if not b.scars.is_empty():
		bits.append("%d scarred part%s" % [b.scars.size(), "s" if b.scars.size() > 1 else ""])
	return " · ".join(bits) if not bits.is_empty() else "whole"

## The rare medicine is in stock on some stages only (the same for everyone on that stage).
static func medicine_in_stock(stage: int) -> bool:
	return (stage * 7 + 3) % 4 == 0

## What the physician can do for this body: [{id, name, desc, price, part}].
static func offers(body: Dictionary, stage: int) -> Array:
	var b := sanitize(body)
	var out := []
	for kind in ["peg", "hook", "blade"]:
		for n in PROSTHETICS[kind].parts:
			var parent := ""
			for d in Data.body_parts:
				if d.name == n:
					parent = str(d.parent)
			if b.missing.has(n) and not b.missing.has(parent):
				out.append({"id": "%s:%s" % [kind, n], "name": "%s (%s)" % [PROSTHETICS[kind].name, label(n)], "desc": PROSTHETICS[kind].desc, "price": PROSTHETICS[kind].price})
	for s in ["R", "L"]:
		if b.eyes.get(s, "") == "lost":
			out.append({"id": "glassEye:%s" % s, "name": "Glass eye (%s)" % ("right" if s == "R" else "left"), "desc": PROSTHETICS.glassEye.desc, "price": PROSTHETICS.glassEye.price})
	# Broken bones set and splinted (an open break cleaned and sewn over it too): they knit by the
	# next bout. No elixir needed.
	for k in b.fractures:
		var lv := int(b.fractures[k])
		var what := "Set the %s" % bone_label(k)
		var desc := "The bone pulled straight, set and splinted: it knits by the next bout. Left alone it stays broken, and the limb no use."
		if k == "ribs":
			what = "Bind the ribs"
			desc = "The broken ribs bound tight: you breathe freely again by the next bout. Left alone, every breath is short."
		elif k == "skull":
			what = "Mend the skull"
			desc = "The cracked bone lifted and bound, the head kept still: the ringing and the blurring stop. Left alone, every knock to the head goes straight to the brain."
		elif k == "pelvis":
			what = "Bind the pelvis"
			desc = "The hips bound tight in linen: the legs bear you again. Left alone, they buckle."
		elif lv == 1:
			what = "Splint the cracked %s" % bone_label(k)
			desc = "The crack splinted until it holds: whole again by the next bout. Left alone it stays weak, and a lesser blow breaks it through."
		elif lv == 3:
			desc = "The bone that came out through the skin cleaned, pushed back, set and the wound sewn over it: it knits by the next bout. Left alone it stays broken, and the limb no use."
		out.append({"id": "set:%s" % k, "name": what, "desc": desc, "price": set_price(k, lv, stage)})
	var fresh_n := 0
	for n in b.fresh:
		fresh_n += b.fresh[n].size()
	if fresh_n > 0:
		out.append({"id": "stitch:all", "name": "Stitch and dress your wounds", "desc": "The cuts and the crushed flesh of your last fight, cleaned, stitched and bound: they heal without a mark. Left alone, they scar over for good.", "price": stitch_price(b)})
	if not b.scars.is_empty() and medicine_in_stock(stage):
		var worst := ""
		for n in b.scars:
			if worst == "" or b.scars[n].size() > b.scars[worst].size():
				worst = n
		out.append({"id": "medicine:%s" % worst, "name": "Rare medicine", "desc": "A jar of something black from the East. The physician has one today. It closes the worst of your old wounds (the %s) as if it had never been." % label(worst), "price": medicine_price(stage)})
	# The magic one: everything the campaign took, given back at once.
	if not b.missing.is_empty() or not b.prosthetics.is_empty() or not b.eyes.is_empty() or not b.scars.is_empty():
		out.append({"id": "elixir:all", "name": "Elixir of Asclepius", "desc": "A small blue bottle, sealed with the god's serpent. One swallow and the body grows back as it was before the arena: lost hands and legs, a blind eye, every old wound. It costs a fortune, and it is worth it.", "price": elixir_price(stage)})
	return out

## Apply a treatment by its offer id. Returns the new body (unchanged if it does not apply).
static func apply(body: Dictionary, id: String) -> Dictionary:
	var b := sanitize(body)
	var bits := id.split(":")
	if bits.size() != 2:
		return b
	var kind := bits[0]
	var n := bits[1]
	match kind:
		"peg", "hook", "blade":
			if PROSTHETICS[kind].parts.has(n) and b.missing.has(n):
				b.missing.erase(n)
				b.prosthetics[n] = kind
		"glassEye":
			if b.eyes.get(n, "") == "lost":
				b.eyes[n] = "glass"
		"medicine":
			b.scars.erase(n)
		"set":
			b.fractures.erase(n)
		"elixir":
			var fights: int = int(b.get("fights", 0))
			b = empty()
			b.fights = fights
		"stitch":
			for p in b.fresh:
				var gone := {}
				for i in b.fresh[p]:
					gone[int(i)] = true
				b.scars[p] = (b.scars.get(p, []) as Array).filter(func(i): return not gone.has(int(i)))
				if (b.scars[p] as Array).is_empty():
					b.scars.erase(p)
			b.fresh = {}
	return sanitize(b)

## What stitching the fresh wounds costs: a little for a scratch, more for a man cut to ribbons.
static func stitch_price(b: Dictionary) -> int:
	var n := 0
	for p in b.get("fresh", {}):
		n += (b.fresh[p] as Array).size()
	return clampi(15 + n / 6, 15, 160)

static func price_of(id: String, body := {}, stage := 1) -> int:
	var kind := id.split(":")[0]
	if kind == "stitch":
		return stitch_price(sanitize(body))
	if kind == "medicine":
		return medicine_price(stage)
	if kind == "elixir":
		return elixir_price(stage)
	if kind == "set":
		var key := id.split(":")[1] if id.split(":").size() > 1 else ""
		return set_price(key, int(sanitize(body).fractures.get(key, 1)), stage)
	return int(PROSTHETICS.get(kind, {}).get("price", 0))
