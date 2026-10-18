class_name Tutorial
extends RefCounted
## The tutorial (tutorial.js): eight short steps in the training ring with a dummy, each done as
## soon as the player has done it once (no walls of text, no timers), then a real recruit to beat.
## It measures what the player did from his fighter and his input; Match plays it in training
## mode and the HUD shows the step.

const STEPS := [
	{"id": "move", "title": "Walk", "text": "W A S D to walk, hold Shift to run. Take a few steps."},
	{"id": "look", "title": "Look", "text": "Move the mouse with no button held to look around. Look all the way round."},
	{"id": "swing", "title": "Swing", "text": "Hold the LEFT button and sweep the mouse: the sword follows your hand. Hit the dummy twice. Fast sweeps cut deep."},
	{"id": "guard", "title": "Guard", "text": "Hold the RIGHT button: now the mouse moves the shield. Raise it up for a moment."},
	{"id": "kick", "title": "Kick and shove", "text": "E kicks, Q shoves. Kick or shove the dummy."},
	{"id": "throw", "title": "Throw", "text": "Hold F to aim, let go to throw. Throw your sword at the dummy."},
	{"id": "pickup", "title": "Pick up", "text": "Your hand is empty now. A javelin lies by you: walk over and press G to pick it up.", "setup": "javelin"},
	{"id": "forge", "title": "The forge", "read": 9.0, "text": "At the smith, Reshape in the forge changes your weapon. Quick start: a base and up to two twists (▲ more, ▼ less speed, damage, reach). Shape by hand: left click builds, right click takes a block off, middle drag turns it, Shift and middle drag slides it, the wheel zooms to the mouse, F shows it all again, Ctrl+Z undoes."},
	{"id": "blocks", "title": "Blocks", "read": 9.0, "text": "Each block has a material (its hardness and weight) and a job: Edge cuts, Point stabs, Blunt crushes and holds it together, Grip is where you hold it. Save design keeps a weapon in My designs to load again."},
	{"id": "gems", "title": "Gems", "read": 8.0, "text": "Ruby, sapphire and emerald are costly sockets: a blow may set the part it strikes alight, freeze it stiff with frostbite that kills the flesh, or poison it. The more stones, the surer and the fiercer."},
	{"id": "fight", "title": "A real fight", "text": "A recruit steps in, and he fights back. Beat him. (You cannot die in here.)", "setup": "fight"},
]

var m: Node
var i := 0
var s := {"moved": 0.0, "turned": 0.0, "hits": 0, "guard_t": 0.0, "kicks": 0, "throws": 0, "armed": true, "won": false, "read_t": 0.0}
var ok_t := 0.0
var finished := false
var setup_done := {}
var last_pos = null
var last_yaw = null
var had_weapon := true
var dummy = null
var recruit = null

func _init(match_: Node) -> void:
	m = match_

func step() -> Dictionary:
	return STEPS[i] if i < STEPS.size() else {}

## What the HUD shows now.
func view() -> Dictionary:
	if finished or i >= STEPS.size():
		return {"done": true, "title": "You are ready", "text": "That is all there is to it. The campaign waits at the gate.", "step": STEPS.size(), "total": STEPS.size(), "ok": true}
	var st := step()
	return {"title": st.title, "text": st.text, "step": i, "total": STEPS.size(), "ok": ok_t > 0.0}

func setup() -> void:
	var e = m.spawn_fighter({"kind": "npc", "name": "Training dummy", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM,
		"pos": Vector3(0, 0.02, -3.6), "yaw": 0.0, "mods": {"toughness": 3.0}, "color": 0xb08a5a})
	e.drive = func(_e): return {}
	e.harmless = true
	dummy = e.f

func _done(id: String) -> bool:
	if step().has("read"):
		return float(s.read_t) >= float(step().read)   # a page to read: it turns by itself
	match id:
		"move": return s.moved > 2.5
		"look": return s.turned > 2.2
		"swing": return s.hits >= 2
		"guard": return s.guard_t > 0.8
		"kick": return s.kicks >= 1
		"throw": return s.throws >= 1
		"pickup": return s.armed
		"fight": return s.won
	return false

func update(dt: float, inp: Dictionary) -> void:
	if finished or m.me == null:
		return
	var f: Fighter = m.me.f
	# Nobody dies in the training ring: the player and the dummy are patched up as they go.
	f.blood = maxf(f.blood, 60.0)
	if dummy and is_instance_valid(dummy):
		dummy.blood = 100.0
	var p := f.torso.global_position
	if last_pos != null:
		s.moved = float(s.moved) + Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
	last_pos = p
	if inp.get("look") is Dictionary:
		var yaw := float(inp.look.yaw)
		if last_yaw != null:
			s.turned = float(s.turned) + absf(wrapf(yaw - float(last_yaw), -PI, PI))
		last_yaw = yaw
	var off: Dictionary = inp.get("off", {}) if inp.get("off") is Dictionary else {}
	if inp.get("power", false) and inp.get("grabHands", null) == "L" and float(off.get("y", 0.0)) > 0.35:
		s.guard_t = float(s.guard_t) + dt
	if (inp.get("kick", false) or inp.get("shove", false)) and dummy and is_instance_valid(dummy) and p.distance_to(dummy.torso.global_position) < 2.2:
		s.kicks = int(s.kicks) + 1
	var armed: bool = f.weapons.get("R") != null
	if had_weapon and not armed:
		s.throws = int(s.throws) + 1
	had_weapon = armed
	s.armed = armed
	if recruit and is_instance_valid(recruit) and not recruit.alive:
		s.won = true
	if ok_t > 0.0:
		ok_t -= dt
		if ok_t <= 0.0:
			i += 1
			s.read_t = 0.0
			if i >= STEPS.size():
				finished = true
		return
	var st := step()
	s.read_t = float(s.read_t) + dt
	if st.has("setup") and not setup_done.has(st.id):
		setup_done[st.id] = true
		_setup(String(st.setup))
	if _done(String(st.id)):
		ok_t = 0.9
		m.sfx("bell", p, 0.5)

func _setup(what: String) -> void:
	var f: Fighter = m.me.f
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	match what:
		"javelin":
			m.spawn_loose_weapon(Data.preset("javelin"), f.torso.global_position + fwd.rotated(Vector3.UP, 0.8) * 1.3 + Vector3(0, 0.3, 0))
		"fight":
			var spec: Dictionary = m.enemy_spec({"e": "recruit"}, 0, 1)
			spec.pos = Vector3(0, 0.05, 5.0)
			spec.diff = 0.45
			recruit = m.spawn_fighter(spec).f
			if dummy and is_instance_valid(dummy):
				dummy.die("retired")

func on_hit(h: Dictionary) -> void:
	if m.me and h.get("attacker") == m.me.f and h.get("char") == dummy and float(h.get("J", 0.0)) > 2.0:
		s.hits = int(s.hits) + 1
