class_name Bot
extends RefCounted
## Bot brain: produces the same input the player produces (ai.js). Personalities change how a
## bot approaches, which attacks it likes and its tricks; difficulty makes it more patient,
## more accurate and better at reading the fight.

const ATTACKS := {
	"slashR": [[0.85, 0.8, 0.0, 0.45], [-0.85, -0.35, 0.2, 0.28]],
	"slashL": [[-0.85, 0.75, 0.0, 0.45], [0.85, -0.3, 0.2, 0.28]],
	"overhead": [[0.15, 1.0, 0.0, 0.5], [0.0, -0.55, 0.3, 0.3]],
	"thrust": [[0.05, 0.25, 0.0, 0.35], [0.0, 0.3, 1.0, 0.22]],
	"low": [[0.9, 0.1, 0.0, 0.4], [-0.8, -0.8, 0.2, 0.3]],
}
const ALL := ["slashR", "slashL", "overhead", "thrust", "low"]
const PERSONALITIES := {
	"standard": {"attacks": ALL},
	"turtle": {"attacks": ["thrust", "thrust", "low"], "think": 1.6, "approach": 0.5, "shield": true, "ideal": 0.75},
	"berserker": {"attacks": ["slashR", "slashL", "overhead"], "think": 0.15, "sprint": true, "power": true, "ideal": 0.6, "kick": 2.0},
	"coward": {"attacks": ALL, "keepAway": [3.5, 6.5], "ability": "rock", "cooldown": [1.8, 3.2]},
	"medic": {"attacks": ["thrust", "low"], "keepAway": [3.0, 5.0], "support": true, "ability": "heal", "cooldown": [5.0, 7.0]},
	"retiarius": {"attacks": ["thrust", "thrust", "low"], "ability": "net", "range": [2.2, 6.0], "cooldown": [7.0, 10.0]},
	"executioner": {"attacks": ["overhead"], "think": 1.3, "approach": 0.6, "power": true, "windup": 1.5},
	"praetorian": {"attacks": ["thrust", "slashR", "low"], "shield": true, "approach": 0.75, "think": 0.9, "ideal": 0.65},
	"hoplite": {"attacks": ["thrust", "thrust", "thrust", "low"], "shield": true, "approach": 0.7, "think": 0.9, "ideal": 1.05},
	"duelist": {"attacks": ["slashR", "slashL", "slashR", "slashL", "thrust"], "think": 0.5, "ideal": 0.75, "combo": 0.35, "dodge": 0.3},
	"bully": {"attacks": ["thrust", "thrust", "slashR"], "shield": true, "approach": 0.9, "think": 0.8, "ideal": 0.6, "kick": 2.0},
	"brute": {"attacks": ["overhead", "slashR", "slashL"], "power": true, "windup": 1.25, "think": 1.1, "kick": 3.0, "ideal": 0.85},
	"archer": {"attacks": ["thrust", "low"], "keepAway": [5.0, 9.0], "bow": true, "kick": 3.0},
	"skirmisher": {"attacks": ["thrust", "slashR", "slashL"], "ideal": 0.7, "think": 0.7},
	"pyro": {"attacks": ALL, "keepAway": [4.0, 7.5], "ability": "pot_fire", "range": [3.0, 9.0], "cooldown": [4.0, 6.0]},
	"whirler": {"attacks": ["slashR", "slashL", "overhead", "slashR"], "power": true, "ideal": 1.0, "think": 0.7},
}

var c: Fighter
var diff := 0.5
var p: Dictionary
var state := "approach"
var hand := {"x": 0.1, "y": 0.2}
var attack: Array = []
var key := 0
var key_t := 0.0
var aim_low := 0.0   # a big man's blow brought lower while its head is held above the small one
var feint_to: Array = []
var strafe := 1.0
var strafe_t := 0.0
var think := 0.0
var recover_t := 0.0
var dodge_t := 0.0
var dodge_cool := 0.0
var dodge := ""
var jab_cd := 0.0
var aim_pick = null
var rng := RandomNumberGenerator.new()
var grab_cool := 4.0            # the first grab waits: the weapon comes first
var hold_t := 0.0
var hold_move := ""
var follow_t := 0.0
var ability_t := 1.0
var draw_t := -0.8
var panic_t := 0.0             # enraged: when the blind lurch changes
var air_t := 0.0               # enraged: the next swing at the air, whatever is in reach
var rage_goal := Vector3.ZERO  # enraged: where he thinks the man is (heard or felt, with error)
var rage_known := false
var panic_off := Vector3.ZERO  # where, off the man, the half-blind giant is facing now
var panic_mx := 0.0
var weave := 0.0               # the guard's own motion: the blade is never held dead still
var lunge := false             # this blow began out of reach: he steps in with it

func _init(fighter: Fighter, difficulty := 0.5, personality := "standard", seed_ := 0) -> void:
	c = fighter
	diff = difficulty
	p = PERSONALITIES.get(personality, PERSONALITIES.standard)
	rng.seed = seed_ if seed_ else randi()
	strafe = -1.0 if rng.randf() < 0.5 else 1.0
	ability_t = 0.4 if p.has("range") else 1.0 + rng.randf() * 2.0

func _lerp_hand(x: float, y: float, k: float) -> void:
	k = minf(1.0, k)
	hand.x += (x - hand.x) * k
	hand.y += (y - hand.y) * k

func _pick(list: Array) -> Array:
	return ATTACKS[list[rng.randi_range(0, list.size() - 1)]]

## The input for this step against `target` (a Fighter or a Beast).
## `world`: {"loose": weapons lying about}.
func update(dt0: float, target: Node3D, world := {}) -> Dictionary:
	var dt := dt0 / (1.0 + 0.9 * c.injury)
	# Enraged (a giant hurt in the head): no pause between blows, short wind-ups, wild wide
	# strokes one after another, the button always down, kicks and grabs far more often.
	var rage: bool = bool(c.get("enraged"))
	var inp := {"mx": 0.0, "mz": 0.0, "main": hand.duplicate(), "off": {"x": -0.35, "y": 0.15}, "thrust": 0.0, "power": false, "twist": 0.0}
	if not c.alive:
		return inp
	ability_t -= dt
	# Medicus: walk to the most hurt ally and patch him up.
	if p.get("support", false):
		var hurt = null
		for a in world.get("allies", []):
			if a != c and a.alive and a.blood < 80.0 and (hurt == null or a.blood < hurt.blood):
				hurt = a
		if hurt:
			var hd := Vector2(hurt.torso.global_position.x - c.torso.global_position.x, hurt.torso.global_position.z - c.torso.global_position.z).length()
			inp.faceAt = hurt.torso.global_position
			inp.mz = 1.0 if hd > 1.1 else 0.0
			inp.sprint = hd > 4.0
			if hd < 1.4 and ability_t <= 0.0:
				inp.ability = {"type": "heal", "target": hurt}
				ability_t = rng.randf_range(p.cooldown[0], p.cooldown[1])
			return inp
	if target == null:
		return inp
	var special = _wrestle(dt, target, world, inp)
	if special != null:
		return special
	strafe_t -= dt
	if strafe_t <= 0.0:
		strafe = -strafe
		strafe_t = 1.5 + rng.randf() * 2.5
	var me := c.torso.global_position
	var tp: Vector3 = target.torso.global_position
	var dist := Vector2(tp.x - me.x, tp.z - me.z).length()
	var S := c.S
	var w: Weapon = c.weapons.R
	var reach := 0.55 * S + (w.reach if w else 0.25) * 0.85
	var ideal := reach * float(p.get("ideal", 0.9))
	# A giant over a man a third his size: he steps in so the blade's length is over the man,
	# and every blow is brought down to where the man actually is (standing, or on the sand),
	# not swung at a giant's own height over his head.
	var tS: float = float(target.get("S")) if target.get("S") != null else 1.0
	var big: bool = S > tS * 1.5 and w != null
	var aim_small = null
	var swing_reach := reach
	if big:
		# Where the blade must end: on the man, a little below his chest. From the shoulder's
		# height that fixes the blade's pitch, and the pitch fixes how far off he must stand for
		# the blade's length to come down through him.
		# (Measured: at the end of a chop the hand is 0.27 S below the chest and 0.59 S ahead of
		# it; from there the blade's length must span to the man.)
		var low_y: float = tp.y - 0.2 * tS
		var hand_y: float = me.y - 0.27 * S
		var hand_fwd: float = 0.59 * S
		var dy := low_y - hand_y
		var horiz := sqrt(maxf(0.0, w.reach * w.reach - dy * dy))
		ideal = hand_fwd + horiz * 0.65
		swing_reach = hand_fwd + horiz * 1.0
		aim_small = clampf(atan2(dy, maxf(0.3, dist - hand_fwd)) / 0.92, -1.5, 0.6)
	var keep_away = p.get("keepAway")
	var cornered: bool = keep_away != null and dist < 1.6
	if keep_away != null and not cornered:
		if dist < keep_away[0]:
			inp.mz = -1.0
		elif dist > keep_away[1]:
			inp.mz = 0.8
		inp.mx = strafe * 0.8
	else:
		var closing := state == "attack" or think <= 0.15
		if dist > ideal + (0.15 if closing else 0.6):
			inp.mz = minf(1.0, float(p.get("approach", 0.8)) * (1.0 if closing else 0.6))
		elif dist < ideal - 0.3:
			inp.mz = -0.7
		inp.mx = strafe * (0.6 if dist < reach * 1.8 else 0.2) * (0.5 if p.get("shield", false) else 1.0)
		inp.sprint = dist > 2.5 if p.get("sprint", false) else dist > 6.0
		if recover_t > 0.0:
			recover_t -= dt
			inp.mz = -0.6
			inp.mx = strafe * 0.8
	# Ranged trick almost ready but too close: back off to throwing range.
	if p.has("range") and ability_t < 0.8 and dist < p.range[0] + 0.6:
		inp.mz = -1.0
		inp.sprint = true
	if c.state != "stand":
		# Down and alive he does not lie there: he crawls at the man and fights on from the
		# sand (a giant with a leg blown off by a thunder pot lay still and the bout ran out
		# on him: user). Up to the man's reach, then he stays and swings.
		inp.mx = 0.0
		inp.mz = 1.0 if dist > reach * 0.6 + 0.3 * S else 0.0
		inp.faceAt = tp
	# Ranged tricks: a rock, a net, a pot of Greek fire.
	if p.has("ability") and p.ability != "heal" and ability_t <= 0.0 and c.state == "stand":
		var rg: Array = p.get("range", [2.5, 9.0])
		if dist > rg[0] and dist < rg[1]:
			inp.ability = {"type": p.ability, "target": target}
			ability_t = rng.randf_range(p.cooldown[0], p.cooldown[1])
	var gy := clampf((tp.y + 0.3 - me.y) / S * 0.9, -0.2, 0.8)
	if p.get("shield", false):
		inp.off = {"x": -0.28, "y": gy}
	# A weapon flying at us: good bots dodge or parry.
	var tw = target.weapons.get("R") if target.get("weapons") != null else null
	var incoming := 0.0
	if tw:
		var v: Vector3 = tw.linear_velocity
		var d: Vector3 = me - tw.global_position
		var sp := v.length()
		if sp > 4.5 - diff * 1.2 and d.length() < reach * (1.1 + 0.4 * diff) and v.x * d.x + v.z * d.z > 0.0:
			incoming = sp
	dodge_t = maxf(0.0, dodge_t - dt)
	dodge_cool = maxf(0.0, dodge_cool - dt)
	if incoming > 0.0 and not rage and dodge_t <= 0.0 and dodge_cool <= 0.0 and state != "attack" and c.state == "stand" and rng.randf() < ((diff - 0.4) * 1.2 + float(p.get("dodge", 0.0))) * (1.0 - 0.6 * c.injury):
		dodge_t = 0.35
		dodge_cool = 1.6
		dodge = "side" if rng.randf() < 0.5 else "parry"
		if dodge == "side":
			strafe = -strafe
	if dodge_t > 0.0:
		if dodge == "side":
			inp.mx = strafe
			inp.mz = -0.6
			inp.sprint = true
		elif tw:
			var d2: Vector3 = tw.global_position - me
			var right := Vector3(cos(c.yaw), 0, -sin(c.yaw))
			_lerp_hand(clampf(-d2.dot(right) * 1.5, -1.0, 1.0), clampf((tw.global_position.y - me.y) * 0.9, -0.2, 1.0), dt * 14.0)
			inp.main = hand.duplicate()
			inp.thrust = 0.6
			inp.power = true
			think = 0.0
			return inp
	if keep_away != null and not cornered:
		# An archer draws while he circles and looses once the bow is full.
		if p.get("bow", false) and w and str(w.design.get("shoots", "")) == "arrow" and c.state == "stand" and dist < 12.0:
			draw_t += dt
			if draw_t > 0.0:
				inp.power = true
				inp.faceAt = tp
				_lerp_hand(0.05, 0.55, dt * 8.0)
			if draw_t > 1.1 + (1.0 - diff) * 0.7:
				inp.power = false
				draw_t = -rng.randf_range(0.9, 2.2) * (1.3 - diff * 0.5)
		inp.main = hand.duplicate()
		return inp
	# (Enraged he also swings at the air, at nothing in particular, every couple of seconds:
	# a timer, not a chance a step, which left him standing nine seconds between swings.)
	if rage:
		air_t -= dt
	# A man does not walk up to the reach of his blade and then begin: from a step outside it
	# he starts the blow and steps in with it (they walked at the man like the dead, the blade
	# held still, and swung only once there: user).
	var step_in: bool = w != null and not big and keep_away == null and c.state == "stand" and dist < reach * 1.7 and dist > reach * 0.9
	var ready: bool = (dist < (reach * 1.15 if not big else swing_reach) or step_in or (rage and (dist < reach * 1.8 or air_t <= 0.0))) and c.stamina > (8.0 if rage else 20.0)
	if state == "approach" or state == "guard":
		# On guard the blade moves: it weaves on its line, and near the man it is drawn back to
		# the shoulder, cocked for the blow, with a half-feint now and then.
		weave += dt * (2.2 + 1.2 * diff)
		var near: float = clampf((reach * 2.2 - dist) / maxf(0.3, reach * 1.2), 0.0, 1.0) if w != null else 0.0
		var gx: float = 0.15 + 0.12 * sin(weave) + 0.3 * near * (0.6 + 0.4 * sin(weave * 0.37))
		var gyy: float = gy + 0.1 * sin(weave * 1.31 + 1.0) + 0.25 * near
		_lerp_hand(gx, gyy, dt * (2.0 + diff * 4.0))
		think -= dt * (5.0 if rage else 1.0)
		if think > 0.0 and diff > 0.45 and ready:
			var open: bool = float(target.get("stagger")) > 0.25 or target.state != "stand"
			if open and rng.randf() < dt * (diff - 0.3) * 12.0:
				think = 0.0
		if ready and think <= 0.0:
			air_t = rng.randf_range(1.5, 3.0)
			attack = ATTACKS.thrust if dist > reach and rng.randf() < 0.5 else _pick(p.attacks)
			feint_to = _pick(p.attacks) if diff > 0.6 and rng.randf() < (diff - 0.6) * 0.4 else []
			key = 0
			key_t = 0.0
			state = "attack"
			lunge = dist > reach * 1.05
			aim_pick = null
			if diff > 0.7 and rng.randf() < (diff - 0.6) * 1.6:
				var head_y: float = minf(1.0, (target.head.global_position.y - me.y) / S * 0.9)
				aim_pick = head_y if rng.randf() < 0.6 else -0.6
		if dist < (1.3 if rage else 1.0) * S and rng.randf() < dt * 0.15 * diff * float(p.get("kick", 1.0)) * (8.0 if rage else 1.0):
			inp.kick = true
		if S > 1.2 and dist < ideal * (0.5 if big else 0.7) and target.state == "stand":
			inp.mz = -1.0
			if rng.randf() < dt * 2.5:
				inp.kick = true
	if state == "attack" and not attack.is_empty():
		if key == 0:
			aim_low = 0.0
		var k_: Array = attack[key]
		var x: float = k_[0]
		var y: float = k_[1]
		var th: float = k_[2]
		var dur: float = k_[3]
		if key == attack.size() - 1 and aim_pick != null:
			y = y * 0.4 + float(aim_pick) * 0.6
		if key == attack.size() - 1 and aim_small != null:
			# Held at the end of the blow with the head still above the man, the blow is brought
			# lower, a little a frame, until the head is down on him: the pitch the mark asked
			# for is not always the pitch the haft takes (the hands pulled in to their reach, the
			# off arm stretched straight), and the cyclops held its hammer at the man's head
			# height half a metre short of him and never landed.
			if key_t >= 0.85 and w != null:
				var hd: Vector3 = w.global_position + PD.quat_of(w) * Vector3(0, w.reach * 0.85, 0)
				if hd.y > tp.y - 0.2 * tS:
					aim_low = maxf(-1.0, aim_low - 2.0 * dt)
			y = clampf(float(aim_small) + aim_low, -1.5, 0.6)   # the blow ends on the small man, wherever he is
			x = 0.0                # and comes down through the middle of him, not past his shoulder
		var windup: float = (float(p.get("windup", 1.0)) if key == 0 else 1.0) * (0.6 if rage else 1.0)
		if rage:
			x = clampf(x * 1.35, -2.0, 2.0)
		if big:
			# A giant's weapon is long and heavy: the stroke takes longer to come round, and the
			# blow is held at its end until the blade has finished its arc onto the man.
			windup *= 1.0 + (0.25 if key == 0 else 0.55) * (S - 1.0)
		key_t += dt / (dur * windup * 1.15)
		var kk := minf(1.0, key_t)
		_lerp_hand(x, y, kk * kk)
		inp.thrust = th * kk
		inp.power = p.get("power", false) or key == attack.size() - 1 or rage
		if lunge and c.state == "stand" and dist > reach * 0.7:
			inp.mz = 1.0
			inp.mx = 0.0
		if not feint_to.is_empty() and key == 0 and key_t > 0.5:
			attack = feint_to
			feint_to = []
			key_t = 0.2
		var settle: float = 1.0 + (0.2 * S if big and key == attack.size() - 1 else 0.0) / maxf(0.05, dur * windup * 1.15)
		if key_t >= settle:
			key += 1
			key_t = 0.0
			if key >= attack.size():
				if (rage and c.stamina > 15.0 and rng.randf() < 0.85) or (diff > 0.5 and rng.randf() < (diff - 0.4) * 0.7 + float(p.get("combo", 0.0)) and c.stamina > 50.0):
					attack = _pick(p.attacks)
					key = 0
					feint_to = []
				else:
					state = "guard"
					lunge = false
					# (Armed, the next blow comes sooner; a giant's bare hands keep their pace.)
					recover_t = (0.25 + rng.randf() * 0.3) if w else (0.35 + rng.randf() * 0.4)
					think = (1.5 - diff * 0.4) * ((0.35 + 0.7 * rng.randf()) if w else (0.5 + rng.randf())) * float(p.get("think", 1.0))
	# Bare-handed: jab when in reach.
	# Close in: a shove now and then, more when the other man is off balance or tired.
	if dist < 0.9 * S + 0.4 and c.state == "stand" and state != "attack" and rng.randf() < dt * diff * float(p.get("shove", 1.0)) * (3.0 if rage else 1.0) * (0.25 + (0.9 if float(target.get("stagger")) > 0.4 or float(target.get("stamina")) < 35.0 else 0.0)):
		inp.shove = true
	# A throwing weapon in hand and the man in range: let it fly.
	if w and w.design.get("throwable", false) and dist > 2.8 and dist < 8.0 and c.state == "stand" and rng.randf() < dt * 0.5:
		inp.throw = true
		inp.throwPower = 0.85
	if dist < (1.25 if rage else 0.95) * S and c.state == "stand" and c.stamina > 15.0:
		jab_cd -= dt
		if jab_cd <= 0.0:
			var side := ""
			if not c.weapons.R:
				side = "R"
			elif not c.weapons.L and not c.two_handed:
				side = "L"
			if side != "":
				inp["jab" + side] = true
				jab_cd = (0.9 - 0.4 * diff) * (0.6 + rng.randf() * 0.8) * (0.4 if rage else 1.0)
	if rage:
		# Blind and mad with it: he does not see the man, only hears and feels him. Where he
		# thinks the man is gets set when the man is close enough to hear (within two of his
		# own heights) or hits him, with a wide error, and goes stale otherwise; most of the
		# time he lurches some other way altogether, turning as he goes and lashing out at the
		# air, and bears down on his idea of the man only now and then. (He went straight for
		# the man as if he saw him: user.)
		panic_t -= dt
		if dist < 2.0 * S or float(c.get("stagger")) > 0.15:
			rage_goal = tp + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 0.6 * S
			rage_known = true
		if panic_t <= 0.0:
			panic_t = rng.randf_range(0.5, 1.4)
			var at_goal: bool = rage_known and rng.randf() < 0.45
			var dir_: Vector3 = (rage_goal - me) if at_goal else Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
			dir_.y = 0.0
			panic_off = dir_.normalized() * 3.0 * S if dir_.length() > 0.05 else Vector3(0, 0, 3.0 * S)
			panic_mx = rng.randf_range(-1.0, 1.0)
		inp.faceAt = me + panic_off
		inp.mx = panic_mx * 0.6
		inp.mz = 1.0 if (me + panic_off).distance_to(me) > 0.5 else 0.0
		if dist < reach * 0.7:
			inp.mz = rng.randf_range(-0.4, 0.8)
		# Kicking out and punching with the free fist in the middle of the strokes.
		if dist < 1.6 * S and c.state == "stand" and rng.randf() < dt * 1.2:
			inp.kick = true
		if dist < 1.4 * S and not c.weapons.L and not c.two_handed and rng.randf() < dt * 2.0:
			inp.jabL = true
	inp.main = hand.duplicate()
	return inp

## The moves that are not swings: going for a weapon lying about when empty-handed, and the
## big men's grab, hoist and hurl (or slam). Returns the whole input when it takes over.
func _wrestle(dt: float, target: Node3D, world: Dictionary, inp: Dictionary):
	var S := c.S
	var me := c.torso.global_position
	var tp: Vector3 = target.torso.global_position
	var dist := Vector2(tp.x - me.x, tp.z - me.z).length()
	# Empty-handed with a weapon lying nearer than the enemy: go and pick it up.
	if not c.weapons.R and c.holding == null and c.state == "stand" and c.kind != "beast" and not c.arm.R.fore.severed:
		var hand_p := c.hand_world("R")
		var best = null
		var bd := minf(8.0, dist + 1.0)
		for w in world.get("loose", []):
			if not is_instance_valid(w) or w.holder != null or w.is_shield or w.alive_count() < 3:
				continue
			var d := Vector2(w.global_position.x - hand_p.x, w.global_position.z - hand_p.z).length()
			if d < bd:
				bd = d
				best = w
		if best:
			inp.faceAt = best.global_position
			inp.mz = 1.0 if bd > 0.6 else 0.0
			inp.crouch = bd < 1.5
			inp.main = {"x": 0.0, "y": -1.0}
			inp.thrust = 0.8
			inp.grab = bd < 1.0
			return inp
	grab_cool = maxf(0.0, grab_cool - dt)
	if c.holding == null:
		hold_move = ""
	if c.holding == null and follow_t > 0.0:
		follow_t -= dt
		var k := 1.0 - follow_t / 0.45
		inp.off = {"x": 0.6 - 0.2 * k, "y": 0.3 - 1.0 * k}
		inp.offThrust = 1.4 - 0.8 * k
		inp.main = {"x": 0.7, "y": 0.4}
		inp.mz = 0.2
		return inp
	# Giants and trolls now and then grab the nearest fighter and hurl him across the arena;
	# the weapon is the main threat, the grab the surprise (never before the first blows).
	var rage: bool = bool(c.get("enraged"))
	if S >= 1.8 and c.holding == null and dist < 0.8 * S + 0.7 and grab_cool <= 0.0 and (state != "attack" or rage) and c.state == "stand" and rng.randf() < dt * (1.4 if rage else 0.4):
		inp.grab = true
		grab_cool = 1.5
		hold_t = 0.0
	if c.holding != null and c.holding.limb == null:
		grab_cool = (8.0 + rng.randf() * 4.0) * (0.35 if rage else 1.0)
		hold_t += dt
		inp.mz = 0.0
		inp.mx = 0.0
		if hold_move == "":
			hold_move = "slam" if rng.randf() < 0.5 else "throw"
		var T := hold_t
		var lift := minf(1.0, T / 0.9)
		inp.off = {"x": -0.2 + 0.3 * lift, "y": -1.6 + 3.1 * lift}
		inp.offThrust = 0.3 * lift
		if hold_move == "throw":
			if T > 1.2 and T <= 1.75:
				var k := minf(1.0, (T - 1.2) / 0.45)
				inp.off = {"x": -0.1 - 1.3 * k, "y": 1.5 - 0.3 * k}
				inp.offThrust = 0.3 - 1.4 * k
				inp.main = {"x": 0.9, "y": 0.2}
			elif T > 1.75:
				var k := minf(1.0, (T - 1.75) / 0.22)
				inp.off = {"x": -1.4 + 2.0 * k, "y": 1.2 - 0.9 * k}
				inp.offThrust = -1.1 + 2.6 * k
				inp.power = true
				if k >= 1.0:
					inp.throw = true
					inp.throwPower = 1.0
					follow_t = 0.45
		elif T > 1.1:
			var down := minf(1.0, (T - 1.1) / 0.25)
			inp.off = {"x": 0.1, "y": 1.5 - 3.1 * down}
			inp.offThrust = 0.3 + 0.5 * down
			inp.power = true
			var caught: float = c.holding.target.f.torso.global_position.y
			if (down >= 1.0 and caught < 1.1 * c.holding.target.f.S) or T > 1.9:
				inp.slam = true
		return inp
	return null
