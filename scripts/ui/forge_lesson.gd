class_name ForgeLesson
extends RefCounted
## The forge's own lesson, where the tutorial leaves the player: a card over the anvil with one
## thing to do at a time, done the moment it is done (a page to read turns with Next), from the
## quick start's cards through block by block, the view, the jobs and materials, the hand, undo,
## the bars and the gems, to swinging it and keeping it. It reads what the player did from the
## forge's own state; the forge draws the card (Forge._lesson_card).

## A step: its title, what to do (`keys`: the player's walking keys, which fly the view, put into
## the text in that order) and, for a page to read, `read`.
const STEPS := [
	{"id": "base", "title": "Quick start", "text": "The quickest way to a weapon: pick a base on the left."},
	{"id": "twist", "title": "Twists", "text": "Add a twist card (up to two). Its arrows tell what it does to speed, damage and reach: ▲ more, ▼ less."},
	{"id": "byhand", "title": "Shape by hand", "text": "Now open 2 · Shape by hand: there you make it block by block."},
	{"id": "turn", "title": "Turn it round", "text": "Hold the middle button (or Alt and the left button) and drag: the view turns round the weapon. With Shift held, it slides."},
	{"id": "zoom", "title": "Closer", "text": "Roll the wheel: the view draws in toward the mouse, or back out. F shows the whole weapon again."},
	{"id": "fly", "title": "Fly", "text": "%s %s %s %s fly the view, toward what the mouse points at; %s up, %s down, %s faster.", "keys": ["forward", "left", "back", "right", "jump", "crouch", "sprint"]},
	{"id": "build", "title": "Build", "text": "Click a face of the weapon: a block goes on it. Hold the button and drag to lay a row."},
	{"id": "erase", "title": "Take a block off", "text": "Right click a block to take it off (hold and drag for more). X is the eraser, B builds again."},
	{"id": "job", "title": "What a block does", "text": "Every block has a job: 1 Cut makes an edge, 2 Stab a point, 3 Crush a heavy head, 4 Hold the grip. Press 2 and build a point."},
	{"id": "mat", "title": "Material", "text": "Pick a material on the left: steel keeps an edge, iron is cheap and strong, wood light, lead heavy, gold makes the crowd roar. Build a block of another one."},
	{"id": "mirror", "title": "Mirror", "text": "M turns the mirror on and off (Shift+M the other one): while it is on, a block built on one side goes on the other side too."},
	{"id": "hand", "title": "Where it is held", "text": "H is the hand: click a block (or drag the gold ring) and the fighter holds the weapon there. A long grip takes two hands."},
	{"id": "undo", "title": "Undo", "text": "Ctrl+Z takes back the last change, Ctrl+Y puts it back. Take one back."},
	{"id": "bars", "title": "The bars", "read": true, "text": "Speed, Damage, Reach and Vs armour say what the weapon is; after a change, ▲ and ▼ show what it did. The white dot is where its weight sits: far up the blade, it hits hard but swings slow."},
	{"id": "gems", "title": "Gems", "read": true, "text": "Ruby, sapphire and emerald are costly sockets: a blow may set the part it strikes alight, freeze it stiff with frostbite that kills the flesh, or poison it. The more stones, the surer and the fiercer."},
	{"id": "swing", "title": "Swing it", "text": "Press Swing it: the weapon swings as fast as it would in the hand."},
	{"id": "save", "title": "Keep the design", "text": "Name it and press Save design: it waits in My designs, to load again; in the campaign the smith makes it for you."},
]

var f: Node             # the forge
var i := 0
var ok_t := 0.0
var finished := false
var skipped := false
var acc := 0.0          # what the step has seen done so far (radians turned, blocks laid...)
var start := {}         # the forge as it was when the step began
var last := {}          # ... and last frame

func _init(forge: Node) -> void:
	f = forge
	_begin()

func step() -> Dictionary:
	return STEPS[i] if i < STEPS.size() else {}

## A step's text in the player's language, his keys put in.
static func text_of(st: Dictionary) -> String:
	var args := []
	for k in st.get("keys", []):
		args.append(Tutorial.key_label(String(k)))
	var tx := Loc.t(String(st.text))
	return tx % args if not args.is_empty() else tx

## What the card shows now.
func view() -> Dictionary:
	if finished:
		return {"done": true, "title": "You know the forge", "text": Loc.t("Try it in the arena puts it in your hand in front of a dummy; Back leaves the forge."), "step": STEPS.size(), "total": STEPS.size(), "ok": true, "read": false}
	var st := step()
	return {"title": st.title, "text": text_of(st), "step": i, "total": STEPS.size(), "ok": ok_t > 0.0, "read": st.get("read", false)}

## Next, on a page to read.
func next() -> void:
	if not finished and step().get("read", false) and ok_t <= 0.0:
		ok_t = 0.01

func skip() -> void:
	skipped = true
	finished = true

func _count(job_is := "", mat_not := "") -> int:
	var n := 0
	for k in f.cells:
		var c: Array = f.cells[k]
		if (job_is == "" or c[1] == job_is) and (mat_not == "" or c[0] != mat_not):
			n += 1
	return n

## The forge as the step needs it measured.
func _measure(id: String) -> Dictionary:
	match id:
		"turn": return {"v": f.orbit}
		"zoom": return {"v": f.dist}
		"fly": return {"v": f.flown}
		"build", "erase": return {"v": f.cells.size()}
		"job": return {"v": _count("point")}
		"mat": return {"v": _count("", String(start.get("mat", "")))}
		"mirror": return {"v": [f.mirror, f.mirror_z]}
		"hand": return {"v": str(f.design.get("grips", {}))}
		"save": return {"v": f.saves}
	return {}

func _begin() -> void:
	acc = 0.0
	start = {"mat": f.mat}
	start.merge(_measure(String(step().get("id", ""))), true)
	last = start.duplicate()

func _done(id: String) -> bool:
	match id:
		"base": return f.base_key != ""
		"twist": return f.picks.size() >= 1
		"byhand": return f.mode == "voxels"
		"turn": return acc > 1.0
		"zoom": return acc > 0.4
		"fly": return acc > 0.3
		"build": return acc >= 3.0
		"erase": return acc >= 1.0
		"job", "mat": return acc >= 1.0
		"mirror": return str(last.v) != str(start.v)
		"hand": return str(last.v) != str(start.v)
		"undo": return f.redo_stack.size() > 0
		"swing": return f.swing_t >= 0.0
		"save": return int(last.v) > int(start.v)
	return false

func update(dt: float) -> void:
	if finished:
		return
	if ok_t > 0.0:
		ok_t -= dt
		if ok_t <= 0.0:
			i += 1
			if i >= STEPS.size():
				finished = true
				return
			_begin()
		return
	var id := String(step().id)
	if step().get("read", false):
		return   # (Next turns it)
	var now := _measure(id)
	if not now.is_empty():
		match id:
			"turn":
				if f.dragging:
					acc += absf((now.v as Vector2).x - (last.v as Vector2).x) + absf((now.v as Vector2).y - (last.v as Vector2).y)
			"zoom":
				acc += absf(log(maxf(1e-4, float(now.v)) / maxf(1e-4, float(last.v))))
			"fly":
				acc += maxf(0.0, float(now.v) - float(last.v))
			"build", "job", "mat":
				acc += maxf(0.0, float(now.v) - float(last.v))
			"erase":
				acc += maxf(0.0, float(last.v) - float(now.v))
		last = now
	if _done(id):
		ok_t = 0.9
		if Sfx:
			Sfx.ui("bell", 0.4)
