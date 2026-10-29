class_name Fighter
extends Node3D
## A voxel gladiator: ten physical body parts on ball joints, held up and moved by forces the
## way character.js does it (a support spring on the torso, an upright balance torque, legs that
## plant their feet and step with a two-bone solver, hands that follow the mouse on a pane in
## front of the body with a weapon welded in line with the forearm), wounded voxel by voxel.

const V := 0.055
const LEG := 16 * V
const TORSO_H := 11 * V
const TORSO_Y := LEG + TORSO_H / 2.0
const HAND_POINT := Vector3(0, -3.3 * V, 0)
const UPPER_LEN := 7 * V
const FORE_LEN := 6.8 * V
const SHOULDER_R := Vector3(-5.5 * V, 0.2725, 0)
const SHOULDER_L := Vector3(5.5 * V, 0.2725, 0)
const ARM_REACH := 0.68
const HIT_SCALE := 0.8
const BLEED_RATE := 0.6
const JAB_TIME := 0.32
const LEG_MASS := 0.5
## How hard the body is pulled back over its planted feet (14 in the web game, whose legs are
## stiff joint motors; torque-driven legs lag their targets, so less here).
const ANCHOR_K := 4.0
const CENTER_K := 3.0
const STANCE_K := 2.5   # how hard the hips are drawn over the foot that bears the weight
const FOOT_HOLD := 900.0  # a planted foot's grip on the sand
const LEG_WN := 30.0
## How much of the leg drive pushes back on the torso (Rapier's joint motors are solved with the
## joints; a torque drive's full reaction fights the balance when the body lies on its side).
const LEG_REACT := 0.35
const GRAVITY := 9.81
const UP := Vector3.UP
const GRIP_Q := Quaternion(Vector3(1, 0, 0), PI)
## A bow is not a blade (character.js BOW_Q): its arrow direction (+x) runs along the forearm
## toward the target and the stave (+y) stands across it.
const BOW_Q := Quaternion(Vector3(1, 0, 0), PI) * Quaternion(Vector3(0, 0, 1), PI / 2.0)

static func grip_q(w) -> Quaternion:
	return BOW_Q if w and str(w.design.get("shoots", "")) == "arrow" else GRIP_Q

static func is_bow(w) -> bool:
	return w != null and str(w.design.get("shoots", "")) == "arrow"
var behind_t := {"R": 0.0, "L": 0.0}
var wedge_t := {"R": {}, "L": {}}   # a foe's part the blade has been pressed into, and for how long
var unwedge := []                   # [weapon, part, until, at most until]: let through a moment to come free
const SKINS := [0xe0b48c, 0xc68e5e, 0x9a6440, 0x6e4529, 0xf1c9a5, 0xb98a5e, 0x4f3220, 0xd9a07c]

signal died(fighter: Fighter, cause: String)
signal hit_taken(fighter: Fighter, info: Dictionary)
signal raged(fighter: Fighter)
signal note(fighter: Fighter, text: String)   # a word for the player about his own fighter
signal took_up(fighter: Fighter, w: Weapon)    # a hand closed on a weapon's grip (G) and has it
signal lodged(fighter: Fighter, w: Weapon, what: String, at: Vector3)   # "in" a blow left it in him, "free" wrenched out of him

var display_name := "Gladiator"
var slot := 0
var team := 0
var team_color := Color(0.627, 0.125, 0.125)
var skin := Color(0.878, 0.706, 0.549)
var is_bot := false
var face_ids: Array = []          # the eyes and the mouth he chose (Physique.FACES), drawing only
var kind := "fighter"
var mods := {"bodyScale": 1.0, "strength": 1.0, "speed": 1.0, "toughness": 1.0, "bleed": 1.0, "accel": 1.0, "unstoppable": false, "drunk": 0.0}
var S := 1.0
var MS := 1.0
var boss := false

var yaw := 0.0
var state := "stand"           # stand | down | rising | dead
var alive: bool:
	get:
		return state != "dead"
var down_timer := 0.0
var rise_t := 1.0
var rise_q0 = null
var tilt_t := 0.0
var stood_at := -99.0
var blood := 100.0
var stamina := 100.0
var stagger := 0.0
var concussion := 0.0
var pain := 0.0
var time := 0.0
var gait_phase := 0.0
var kick_timer := 0.0
var push_t := 0.0
var kills := 0
var last_attacker: Node = null
var injury := 0.0
var gravity := 9.81              # the Emperor may decree otherwise
# Wrestling and showing off (social.gd).
var holding = null              # {side, target (entity), part, joint, t, extra, limb}
var grabbed_by: Node = null
var pinned_arm := ""
var thrown_t := 0.0
var player := false              # a man's own fighter, his or a guest's (not a bot's)
var struck_frame := -10          # the physics frame a foe's weapon last pressed on him (VoxelPart)
var v_free := Vector3.ZERO       # his trunk's speed before it did
var thrown_by: Node = null
var shove_cool := 0.0
var shove_t := 0.0
var taunt_t := 0.0
var taunt_pose := 0.0
var limp := false
var played_dead := 0.0
var carrying := 0.0
var emote_t := 0.0
var emote_kind := -1
# What pots, nets and arrows do to a man (throwables.gd).
var slow_timer := 0.0
var slow_factor := 1.0
var net_timer := 0.0
var bee_timer := 0.0
var wine_timer := 0.0
var armor_kg := 0.0      # what the armour on him weighs now (plates knocked off lighten it)
var _armor_dirty := true
var sober_drunk := 0.0   # how drunk he was before the wine (mods.drunk goes back to it)
var help_t := 0.0        # a friend is helping him up: he rises twice as fast

## Wine: full breath at once, and a little drunk for ten seconds.
func drink_wine() -> void:
	stamina = breath_cap()
	if wine_timer <= 0.0:
		sober_drunk = float(mods.get("drunk", 0.0))
	wine_timer = 10.0
	mods.drunk = maxf(sober_drunk, 0.3)

## A friend's hand (and his bandage): down, he is up in half the time.
func help_up() -> void:
	help_t = 3.0
	if state == "down":
		down_timer = minf(down_timer, 0.5) if can_stand() else down_timer
var body := {}                    # Body: old wounds, lost limbs, prosthetics, eyes (the campaign)
var fixed_hand := {"R": false, "L": false}   # a blade arm: the weapon cannot leave that hand
var eye_floor := 0.0
var stuck_load := 0.0              # the weight of the blades stuck in him               # an eye lost: the aim never quite steadies
var crawling := false
var eye_hurt := 0.0
var enraged := false   # a giant with an eye put out fights on in a blind rage to the end of the bout
const RAGE_SIZE := 1.5   # from this size up an eye put out enrages instead of stunning
var eye_cells: Array = []   # the head's voxels around the eyes, on the face (big ones only)
var strip_clock := 0.0
var crawl_phase := 0.0
var stance_h := 0.0     # the hip height the planted leg gives (world y of the torso)
var hop_phase := 0.0   # on one leg he hops: 0..1 through each hop
var on_ground := true  # this step: the trunk held up by the legs over the sand (not in the air)
var cut_force := 99.0   # how hard the blow being dealt with cut (J x hardness x sharpness)
var throwing := {"R": false, "L": false}   # that arm winding up or letting go a throw
var thrust_amt := {"R": 0.0, "L": 0.0}   # how far that hand is driving a thrust (0 none)
var throw_pose := {"R": false, "L": false}   # a spear in the throwing hand, wound up or let go
var thrust_aim := {"R": null, "L": null}   # {dir, k}: the line a thrust holds the blade on
var thrust_line := {"R": null, "L": null}   # {o, dir, t}: a thrust's line in the body's frame
var thrust_ext := {"R": 0.0, "L": 0.0}   # how far along that line the hand is driven now
const THRUST_DRAW := 0.12   # s drawing the hand back along the line
const THRUST_DRIVE := 0.14   # s driving it out to the end of the arm
const THRUST_OVER := 0.15   # past the arm's reach, the body leaning in after it
var thrust_lean := 0.0
var chop_mem := {"R": 0.0, "L": 0.0}   # a downward chop, held a moment after the hand slows   # how far into the stab the body leans now (0..1)
var throw_anim = null            # {side, phase: "wind" | "follow", t}: the throwing arm's swing
var held_item = null             # {"type", "id", "node"}: a pot readied in the free hand
var net_mesh: MeshInstance3D = null

var parts: Array = []
var by_name := {}
var torso: VoxelPart
var head: VoxelPart
var arm := {}
var weapons := {"R": null, "L": null}
var weapon_joints := {"R": null, "L": null}
var two_handed := false
var feet := {"L": null, "R": null}
var v_smooth := Vector3.ZERO
var hand_lead := {"R": null, "L": null}
var lead_vel := {"R": Vector3.ZERO, "L": Vector3.ZERO}
var prev_target := {"R": Vector3.ZERO, "L": Vector3.ZERO}
var target_vel := {"R": Vector3.ZERO, "L": Vector3.ZERO}
var aim_q := {"R": null, "L": null}
var aim_tw := {"R": 0.0, "L": 0.0}
var stroke_dir := {"R": null, "L": null}   # a bot's stroke: which way it is going, across the blade
var stroke_idle := {"R": 0.0, "L": 0.0}
const TWO_HAND_TWIST := 0.22   # how far the shoulders turn with a two-handed stroke, per unit of the pane across
const TWO_HAND_TRUNK := 1.8   # how much harder the trunk holds upright with both hands on a haft
const HELD_STILL := 0.6   # the hand's mark moving slower than this (pane a second): held, not swung
const STROKE_REACH := 0.97   # of the arm's length the back hand may be asked to reach in a stroke
var twist_two := 0.0
var net_two_handed := false   # a guest's copy: the host has both his hands on one haft (status)
var two_front = null   # both hands on one haft: where the off hand should hold it this step
var two_main = null    # and the main hand (for the tests)
var two_gap = null     # the off hand's place from the main hand, along the blade's line
var grip_wait := 0.0   # H pressed with the haft's other end behind him: the off hand reaches for it in front, and takes it once it is there
var grip_gentle := false   # (that reach after a weapon taken up by hand: the off hand closes on the haft only once it is on it)
var forearms_pass := false   # the forearms let each other by: the off hand going to the haft beside the other fist, and holding it there
var haft_behind_t := 0.0    # how long the off hand on the haft has been dragged behind his back
var reach := {"R": null, "L": null}   # G: a hand on its way to a weapon's grip, or closed on it and turning it into the fist
var stoop := 0.0            # bent down to a grip low by his feet (0..1): the reach sets it every step
var arm_strain := {"R": 0.0, "L": 0.0}   # how far each hand is held off its mark (m): pulling on a weapon stuck fast
var wrench_t := {"R": 0.0, "L": 0.0}     # how long that hand has been pulling on a weapon stuck in a body
var body_mass := 70.0   # the fighter's own body (kg), from the support spring
var ground_level := 0.0   # the sand under the fighter, from the stance ray
var prev_vy := 0.0        # the torso's fall speed last step (a hard landing hurts)
var land_sag := 0.0       # how far the knees are giving under his weight just now (a landing, a footfall)
var air_time := 0.0       # how long his feet have been off the sand
var last_move := Vector3.ZERO   # where he is trying to go this step (world), for whatever holds him
var aim_w := {"R": Vector3.ZERO, "L": Vector3.ZERO}     # how fast the aim is turning (rad/s)
var elbow_prev := {"R": null, "L": null}
var hand_input := {"R": {"x": 0.1, "y": 0.1}, "L": {"x": -0.35, "y": 0.1}}
var hp_prev := {"R": Vector2(0.1, 0.1), "L": Vector2(-0.35, 0.1)}   # the hand's mark last step, for the breath a swing costs
var hp_vel := {"R": Vector2.ZERO, "L": Vector2.ZERO}
var handling := {"R": 1.0, "L": 1.0}
var jab_t := {"R": 0.0, "L": 0.0}
var swing_hold := {"R": 0.0, "L": 0.0}   # seconds the elbow stays set after a fast stroke
var pane_prev := {"R": null, "L": null}  # last step's hand on the pane (what the mouse asked)
var power_now := false                     # the swing button, this step (for the hand's target)
var low_hand := 0.0
var shoulder := {"R": SHOULDER_R, "L": SHOULDER_L}
var hand_point := HAND_POINT
var torso_y := TORSO_Y
var arm_reach := ARM_REACH
var gaze = null                 # a world point the head turns to (bots)
var off_goal = null             # a world point the free off hand reaches for: a bow's string, a crossbow's to cock
var space: PhysicsDirectSpaceState3D

# ---------- Building ----------

func build(spawn: Vector3, yaw_: float, loadout: Dictionary, opts := {}) -> void:
	display_name = opts.get("name", display_name)
	slot = int(opts.get("slot", 0))
	team = int(opts.get("team", slot))
	is_bot = bool(opts.get("bot", false))
	boss = bool(opts.get("boss", false))
	if opts.has("team_color"):
		team_color = opts.team_color
	skin = Color.hex(int(opts.get("skin", SKINS[slot % SKINS.size()])) << 8 | 0xff)
	for k in opts.get("mods", {}):
		mods[k] = opts.mods[k]
	S = float(mods.bodyScale)
	MS = pow(S, 2.5)
	hand_point = HAND_POINT * S
	shoulder = {"R": SHOULDER_R * S, "L": SHOULDER_L * S}
	arm_reach = ARM_REACH * S
	torso_y = TORSO_Y * S
	yaw = yaw_
	name = display_name.replace(" ", "_")
	var yaw_q := Quaternion(UP, yaw)
	var sk_lin := skin.srgb_to_linear()
	var plain_insides := Anatomy.gore() == "reduced"
	var tm_lin := team_color.srgb_to_linear()
	for d in Data.body_parts:
		var voxels := []
		for v in d.voxels:
			var c: Color
			var kind := 2
			match int(v[3]):
				1:
					c = (sk_lin * float(v[4])).linear_to_srgb()
					kind = 0
				2:
					c = (tm_lin * float(v[4])).linear_to_srgb()
					kind = 1
				_:
					c = Color.hex(int(v[4]) << 8 | 0xff)
					kind = VoxelPart.kind_of_body_color(c)
			# Only how he looks: muscles, a nose, folds in the cloth, whites to the eyes.
			if int(v[3]) == 1 or int(v[3]) == 2:
				var lin := c.srgb_to_linear()
				var k := style_shade(d.name, int(v[0]), int(v[1]), int(v[2]), d.grid, int(v[3]))
				c = Color(lin.r * k, lin.g * k, lin.b * k).linear_to_srgb()
				c = _grain(c, d.name, int(v[0]), int(v[1]), int(v[2]), int(v[3]))
				# Sandal straps laced up the lower shin, over the skin.
				if int(v[3]) == 1 and d.name.begins_with("shin") and _strap(int(v[0]), int(v[1]), int(v[2]), d.grid):
					c = _grain(Color.hex(0x5c3b22ff), d.name, int(v[0]), int(v[1]), int(v[2]), 0)
					kind = VoxelPart.kind_of_body_color(c)
			elif d.name == "head" and int(v[4]) == 0 and int(v[2]) == int(d.grid[2]) - 1 and (int(v[0]) == 2 or int(v[0]) == 7) and int(v[1]) >= 6 and int(v[1]) <= 7:
				c = Color(0.9, 0.88, 0.82)
			elif kind == 2 and organ_of(v) == Anatomy.NONE:
				c = _grain(c, d.name, int(v[0]), int(v[1]), int(v[2]), 0)   # worn leather
			c.a = 1.0
			var organ: int = int(v[6]) if v.size() > 6 else 0
			if organ != Anatomy.NONE and not Anatomy.is_bone(organ):
				kind = 9
				if plain_insides:
					c = Color.hex(0x9e1b1bff)
			voxels.append([v[0], v[1], v[2], c, v[5], kind, organ])
		var p := VoxelPart.new()
		var m: float = float(d.mass) * MS * (LEG_MASS if d.leg else 1.0)
		p.setup(self, d, voxels, S, m)
		p.linear_damp = 0.1
		p.angular_damp = 1.5 if d.name == "torso" else (3.0 if d.name == "head" else 0.6)
		p.collision_layer = VoxelPart.LAYER_BODY
		p.collision_mask = VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS | (0 if d.leg else VoxelPart.LAYER_WORLD)
		add_child(p)
		var pos := Vector3(float(d.pos[0]), float(d.pos[1]), float(d.pos[2])) * S
		p.global_transform = Transform3D(Basis(yaw_q), spawn + yaw_q * pos)
		parts.append(p)
		by_name[d.name] = p
		if d.parent != null:
			p.parent_part = by_name[d.parent]
			p.parent_part.child_parts.append(p)
	torso = by_name.torso
	head = by_name.head
	_count_organs()
	arm = {"R": {"upper": by_name.upperArmR, "fore": by_name.forearmR}, "L": {"upper": by_name.upperArmL, "fore": by_name.forearmL}}
	# A body does not pass through itself: only parts joined to each other (they overlap at the
	# joint) ignore one another, and the two legs while he is up (a stride brushes one past the
	# other). The joints have a body's limits, so a joined part cannot fold into its neighbour.
	for a in parts:
		for b in parts:
			if a != b and (a.parent_part == b or b.parent_part == a or (_is_leg(a) and _is_leg(b))):
				a.add_collision_exception_with(b)
	for p in parts:
		if p.parent_part:
			_make_pin(p)
	for p in parts:
		for id in loadout.get("armor", []):
			_add_armor(p, id)
	for id in loadout.get("armor", []):
		if String(id).begins_with("eyes_") or String(id).begins_with("mouth_"):
			face_ids.append(String(id))   # (a face is painted, not worn: Physique)
	if opts.get("body") is Dictionary:
		apply_body(opts.body)
	if String(mods.get("look", "")) != "":
		MonsterLook.paint_face(self, String(mods.look))
	# How he is drawn (Options: the gladiators' look). Drawing only.
	Physique.dress(self)
	var main = loadout.get("main")
	var off = loadout.get("off")
	# A blade arm carries its own blade; a hook carries nothing.
	for side in ["R", "L"]:
		var fore: VoxelPart = arm[side].fore
		if fore.prosthetic == "blade":
			equip(side, BLADE_ARM)
			fixed_hand[side] = true
		if fore.prosthetic != "":
			if side == "R":
				main = null
			else:
				off = null
	if main is String:
		main = Data.preset(main)
	if off is String:
		off = Data.preset(off)
	if main is Dictionary and not main.is_empty():
		equip("R", main)
		# A two-hander takes both hands only when nothing was given for the other one: a
		# longsword with a dagger is held in one hand, the dagger in the other (H joins them).
		if main.get("twoHanded", false) and not (off is Dictionary and not off.is_empty()) and off_hand_free() and weapons.R.two_hand_off() != null:
			two_handed = true
			_attach_off_hand(weapons.R)
	if off is Dictionary and not off.is_empty() and not two_handed and not weapons.L:
		equip("L", off)
	for w in weapons.values():
		if w and Combat.current:
			w.clear_spawn(Combat.current.fighters)

static func organ_of(v: Array) -> int:
	return int(v[6]) if v.size() > 6 else 0

## A voxel's own small difference from its neighbours, the same every time it is built (and on
## every machine): skin a touch lighter or darker here and there and now and then a little
## ruddier, cloth woven (alternate threads catch the light), leather worn unevenly.
static func _grain(c: Color, part: String, x: int, y: int, z: int, type: int) -> Color:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ part.hash()
	var r1 := float(h & 1023) / 1023.0 * 2.0 - 1.0
	var r2 := float((h >> 10) & 1023) / 1023.0
	var lin := c.srgb_to_linear()
	var k := 1.0
	match type:
		1:
			k = 1.0 + 0.07 * r1
			if r2 > 0.94:
				lin = Color(lin.r * 1.05, lin.g * 0.96, lin.b * 0.93)
		2:
			k = (1.045 if (x + y + z) % 2 == 0 else 0.955) * (1.0 + 0.03 * r1)
		_:
			k = 1.0 + 0.08 * r1
	return Color(lin.r * k, lin.g * k, lin.b * k).linear_to_srgb()

## Where a sandal's straps cross the shin: two bands round it above the sole and a lacing
## crossed up the front, as far as the bottom of the calf.
static func _strap(x: int, y: int, z: int, g: Array) -> bool:
	if y < 4 or y > 8:
		return false
	if y == 4 or y == 7:
		return true
	var front := z == int(g[2]) - 1
	return front and ((x + y) % 4 == 0 or (x - y + 16) % 4 == 0)

## The shading painted on a body voxel (skin type 1, cloth type 2), as a brightness factor on
## its colour: the brow, nose and chin of the face; pecs, breastbone, abs and navel on the chest,
## the spine and shoulder blades behind; limbs lighter toward the top, kneecaps; cloth in folds
## with a darker hem. Front is +z. Only the look: nothing reads it back.
static func style_shade(part: String, x: int, y: int, z: int, g: Array, type: int) -> float:
	var gx := int(g[0])
	var gy := int(g[1])
	var gz := int(g[2])
	var front := z == gz - 1
	var back := z == 0
	var side := x == 0 or x == gx - 1
	var k := 1.0
	if type == 2:
		if (front or back) and x % 4 == 0:
			k *= 0.92
		if side and y % 4 == 0:
			k *= 0.93
		if part.begins_with("thigh") and y == 10:
			k *= 0.72
		return k
	if side:
		k *= 0.93
	match part:
		"head":
			if front:
				if (x == 4 or x == 5) and y >= 4 and y <= 6:
					k *= 1.08
				elif (x == 3 or x == 6) and y == 4:
					k *= 0.86
				elif y == 8:
					k *= 0.9
				elif y <= 1:
					k *= 0.92
			elif back:
				k *= 0.92
		"torso":
			var mid := x == 7 or x == 8
			if front:
				if y == 15 and x >= 2 and x <= 13 and not mid:
					k *= 0.84
				elif (y == 17 or y == 18) and not mid and x >= 2 and x <= 13:
					k *= 1.04
				elif mid and y >= 10 and y <= 17:
					k *= 0.9
				elif (y == 10 or y == 12) and x >= 4 and x <= 11:
					k *= 0.9
				elif mid and y == 9:
					k *= 0.78
				if y == 20:
					k *= 1.05
			elif back:
				if mid and y >= 8 and y <= 20:
					k *= 0.9
				elif y >= 16 and y <= 18 and ((x >= 3 and x <= 5) or (x >= 10 and x <= 12)):
					k *= 1.05
				elif y == 15 and ((x >= 3 and x <= 5) or (x >= 10 and x <= 12)):
					k *= 0.9
		_:
			k *= 0.94 + 0.08 * float(y) / float(maxi(1, gy - 1))
			if part.begins_with("shin") and front and y >= 13 and (x == 3 or x == 4):
				k *= 1.07
	return k

## Takes up a new set of arms where he stands (bought at the smith in the yard): what is in his
## hands now is put away, the new ones are in them at once.
func rearm(main, off) -> void:
	for side in ["R", "L"]:
		var old: Weapon = weapons[side]
		if old and not fixed_hand[side]:
			release(side)
			if Combat.current:
				Combat.current.loose_weapons.erase(old)
			old.queue_free()
	if main is String:
		main = Data.preset(main)
	if off is String:
		off = Data.preset(off)
	if main is Dictionary and not main.is_empty() and not weapons.R:
		equip("R", main)
		# A two-hander takes both hands only when nothing was given for the other one: a
		# longsword with a dagger is held in one hand, the dagger in the other (H joins them).
		if main.get("twoHanded", false) and not (off is Dictionary and not off.is_empty()) and off_hand_free() and weapons.R.two_hand_off() != null:
			two_handed = true
			_attach_off_hand(weapons.R)
	if off is Dictionary and not off.is_empty() and not two_handed and not weapons.L:
		equip("L", off)

## The blade the physician rivets to a stump: a short, broad iron blade on a socket.
const BLADE_ARM := {"name": "Blade arm", "kind": "weapon", "sharpness": 0.85, "voxels": [
	[0, 0, 0, "iron", "grip"], [0, 1, 0, "iron", "grip"], [0, 2, 0, "iron", "grip"], [-1, 3, 0, "iron", "blunt"], [0, 3, 0, "iron", "blunt"], [1, 3, 0, "iron", "blunt"],
	[0, 4, 0, "steel", "edge"], [0, 5, 0, "steel", "edge"], [0, 6, 0, "steel", "edge"], [0, 7, 0, "steel", "edge"], [0, 8, 0, "steel", "edge"], [0, 9, 0, "steel", "edge"],
	[0, 10, 0, "steel", "edge"], [0, 11, 0, "steel", "edge"], [0, 12, 0, "steel", "edge"], [0, 13, 0, "steel", "edge"], [0, 14, 0, "steel", "edge"], [0, 15, 0, "steel", "edge"],
	[0, 16, 0, "steel", "edge"], [0, 17, 0, "steel", "edge"], [0, 18, 0, "steel", "point"]]}

## The body a campaign has left him (Body): old wounds as healed dents, lost limbs gone with
## their stumps closed, prosthetics where the physician fitted them, a lost or a glass eye.
func apply_body(b: Dictionary) -> void:
	body = Body.sanitize(b)
	for n in body.scars:
		var p: VoxelPart = by_name.get(n)
		if p:
			p.scar(body.scars[n])
	# The last fight's wounds are still open: blood round each, not yet the pink of a scar.
	for n in body.get("fresh", {}):
		var fp: VoxelPart = by_name.get(n)
		if fp and not (body.fresh[n] as Array).is_empty():
			var c := Vector3.ZERO
			for i in body.fresh[n]:
				c += fp.local_of(int(i))
			c /= float(body.fresh[n].size())
			fp.wound(c, fp.vf * fp.part_scale * (2.5 + sqrt(float(body.fresh[n].size())) * 0.6), "blood")
	for n in body.missing:
		var p: VoxelPart = by_name.get(n)
		if p and not p.missing:
			_make_missing(p)
	for n in body.prosthetics:
		var p: VoxelPart = by_name.get(n)
		if p:
			_fit_prosthetic(p, String(body.prosthetics[n]))
	for s in body.eyes:
		var ev := Body.eye_voxels(head, s)
		if body.eyes[s] == "glass":
			for i in ev:
				head.colors[i] = Color(0.86, 0.9, 0.95) if head.fy[i] % 2 == 1 else Color(0.25, 0.42, 0.6)
			head.refresh_colors(ev)
			eye_floor += 0.08
		else:
			head.scar(ev)
			eye_floor += 0.3
	for p in parts:
		if p.alive_count < p.fx.size() or p.prosthetic != "":
			p.resync_later()

## A limb lost in an earlier fight: not there at all, and the stump long since healed.
func _make_missing(part: VoxelPart) -> void:
	var stack := [part]
	while not stack.is_empty():
		var p: VoxelPart = stack.pop_back()
		p.missing = true
		p.severed = true
		p.hp = 0.0
		p.visible = false
		p.freeze = true
		p.collision_layer = 0
		p.collision_mask = 0
		if p.joint:
			p.joint.queue_free()
			p.joint = null
		stack.append_array(p.child_parts)
	var par: VoxelPart = part.parent_part
	if par and not par.missing:
		var pt := par.anchor_point(part)
		var r := par.vf * par.part_scale * 2.6
		var near := []
		for i in par.voxels_within(pt, r):
			par.colors[i] = par.colors[i].lerp(VoxelPart.SCAR, 0.6)
			near.append(i)
		par.refresh_colors(near)

## A prosthetic in the part's place: the part is reshaped (wood or iron, thinner) and works
## only so well (VoxelPart.function), and it does not bleed.
func _fit_prosthetic(p: VoxelPart, kind: String) -> void:
	p.prosthetic = kind
	p.missing = false
	var cx := (p.grid.x - 1) * 0.5
	var cz := (p.grid.z - 1) * 0.5
	var top := p.grid.y - 1
	var cuff_from := int(top * 0.72)
	var drop := []
	var paint := []
	for i in p.fx.size():
		var dx := absf(p.fx[i] - cx)
		var dz := absf(p.fz[i] - cz)
		var y: int = p.fy[i]
		if y >= cuff_from:
			# The leather cuff strapped over the stump, an iron band round it.
			p.colors[i] = Color(0.33, 0.21, 0.11) if y != cuff_from else Color(0.45, 0.47, 0.5)
			paint.append(i)
			continue
		var keep := false
		match kind:
			"peg":
				keep = dx < 1.3 and dz < 1.3 or (y > cuff_from - 3 and dx < 2.2 and dz < 2.2)
				if keep:
					p.colors[i] = Color(0.55, 0.38, 0.2) if (y / 2) % 2 == 0 else Color(0.48, 0.32, 0.17)
			"hook":
				var rod := dx < 0.8 and dz < 0.8 and y > 3
				var curve := y <= 3 and dx < 0.8 and p.fz[i] >= cz and p.fz[i] - cz < 3.0 - absf(y - 1.5)
				keep = rod or curve
				if keep:
					p.colors[i] = Color(0.5, 0.52, 0.56)
			"blade":
				keep = dx < 1.3 and dz < 1.3 and y > top * 0.35
				if keep:
					p.colors[i] = Color(0.42, 0.44, 0.48)
		if keep:
			paint.append(i)
		else:
			drop.append(i)
	p.refresh_colors(paint)
	p.remove_voxels(drop, false)
	p.bleed = 0.0
	p.artery = 0.0

static func _is_leg(p) -> bool:
	return String(p.part_name).begins_with("thigh") or String(p.part_name).begins_with("shin")

## Down or dead the legs are a ragdoll's: they knock against each other instead of passing.
func _legs_apart(on: bool) -> void:
	for a in parts:
		if not _is_leg(a) or a.severed:
			continue
		for b in parts:
			if b == a or not _is_leg(b) or b.severed or a.parent_part == b or b.parent_part == a:
				continue
			if String(a.part_name).right(1) == String(b.part_name).right(1):
				continue
			if on:
				a.remove_collision_exception_with(b)
			else:
				a.add_collision_exception_with(b)

## Joint limits, in the parent's frame at rest (everything hanging straight down), in the sense
## Godot's 6DOF joint measures them (the bend of an elbow is +x). [x, y, z] as [lo, hi].
const JOINT_LIMITS := {
	"head": [[-0.55, 0.65], [-1.25, 1.25], [-0.45, 0.45]],
	"thigh": [[-0.6, 2.2], [-0.7, 0.7], [-0.75, 0.75]],
	"shin": [[-2.5, 0.05], [-0.25, 0.25], [-0.06, 0.06]],
}

func _make_pin(p: VoxelPart) -> void:
	var n := String(p.part_name)
	if n.begins_with("forearm"):
		_make_elbow(p)
		return
	var key := "head" if n == "head" else ("thigh" if n.begins_with("thigh") else ("shin" if n.begins_with("shin") else ""))
	if key != "":
		_make_limited(p, JOINT_LIMITS[key])
		return
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = p.parent_part.global_transform * p.pa
	j.node_a = p.parent_part.get_path()
	j.node_b = p.get_path()
	p.joint = j

func _make_limited(p: VoxelPart, lim: Array) -> void:
	var j := Generic6DOFJoint3D.new()
	add_child(j)
	j.global_transform = Transform3D(p.parent_part.global_transform.basis.orthonormalized(), p.parent_part.global_transform * p.pa)
	j.node_a = p.parent_part.get_path()
	j.node_b = p.get_path()
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[0][0])
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[0][1])
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[1][0])
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[1][1])
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[2][0])
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[2][1])
	p.joint = j

func _lock_elbow_straight(side: String, on: bool) -> void:
	var fore: VoxelPart = arm[side].fore
	var upper: VoxelPart = arm[side].upper
	if not (fore.joint is Generic6DOFJoint3D) or fore.severed or upper.severed or fore.hanging or upper.hanging:
		return
	if bool(fore.get_meta("elbow_locked", false)) == on:
		return
	fore.set_meta("elbow_locked", on)
	var j: Generic6DOFJoint3D = fore.joint
	if on:
		# Snap it straight first, as the joint's frame is the straight arm.
		var uq := PD.quat_of(upper)
		var elbow: Vector3 = upper.global_transform * fore.pa
		fore.global_transform = Transform3D(Basis(uq), elbow - uq * fore.ca)
		fore.angular_velocity = upper.angular_velocity
		fore.linear_velocity = upper.velocity_at(elbow)
		for ax in ["x", "y", "z"]:
			j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.01)
			j.call("set_param_" + ax, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.01)
	else:
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.05)
		j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_BEND)
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -ELBOW_TURN)
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_TURN)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.06)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.06)

## A committed swing (the button held, the hand on its way) is made with a set elbow: its bend
## is held in a narrow window that follows the bend the aim wants only slowly, so a heavy head
## (a warhammer) swings on the whole arm from the shoulder instead of folding the elbow.
const ELBOW_SET_RATE := 0.2   # rad/s the set bend may follow the aim
func _hold_elbow(side: String, want_bend: float, on: bool, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var upper: VoxelPart = arm[side].upper
	if not (fore.joint is Generic6DOFJoint3D) or fore.severed or upper.severed or fore.hanging or upper.hanging or bool(fore.get_meta("elbow_locked", false)):
		return
	var j: Generic6DOFJoint3D = fore.joint
	var held = fore.get_meta("elbow_set") if fore.has_meta("elbow_set") else null
	if not on:
		if held != null:
			fore.remove_meta("elbow_set")
			j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.05)
			j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_BEND)
		return
	var cur: float
	if held == null:
		cur = (PD.quat_of(upper) * Vector3.DOWN).angle_to(PD.quat_of(fore) * Vector3.DOWN)
	else:
		# Straightening into the blow is quick (a heavy weapon is struck with the arms
		# extending); giving way to more bend is slow.
		var goal := clampf(want_bend, 0.0, ELBOW_BEND)
		cur = move_toward(float(held), goal, (6.0 if goal < float(held) else ELBOW_SET_RATE) * dt)
	fore.set_meta("elbow_set", cur)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, maxf(-0.05, cur - 0.07))
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, minf(ELBOW_BEND, cur + 0.07))

## The elbow is a hinge, not a ball: the forearm bends forward (up to ~150 degrees) and turns
## about its own length (the wrist, +-75), but it cannot swing sideways or spin round the upper
## arm. So a swung weapon is carried by the whole arm instead of flapping on a loose joint.
## The joint frame is the upper arm's at rest (arm straight down): x is the hinge.
const ELBOW_BEND := 2.6
const ELBOW_TURN := 1.3
func _make_elbow(p: VoxelPart) -> void:
	var j := Generic6DOFJoint3D.new()
	add_child(j)
	j.global_transform = Transform3D(p.parent_part.global_transform.basis.orthonormalized(), p.parent_part.global_transform * p.pa)
	j.node_a = p.parent_part.get_path()
	j.node_b = p.get_path()
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.05)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_BEND)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -ELBOW_TURN)
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, ELBOW_TURN)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -0.06)
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.06)
	p.joint = j

func _add_armor(p: VoxelPart, id: String) -> void:
	var a: Dictionary = Data.armor.get(id, {})
	var cells: Array = a.get("parts", {}).get(p.part_name, [])
	if cells.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * V * S * 0.98
	# Each cell its own colour and stuff (ArmorStyle): strands of hair, woven straw, plates
	# with a rim and rivets, a crown's stones, a cape's folds. Only the look.
	mesh.material = VoxelPart.body_material()
	var looks := ArmorStyle.cells(id, a, cells, ArmorStyle.base_color(id, a, skin))
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.use_colors = true
	mmesh.use_custom_data = true
	mmesh.mesh = mesh
	mmesh.instance_count = cells.size()
	for i in cells.size():
		var c: Array = cells[i]
		mmesh.set_instance_transform(i, Physique.plate_xf(p, c, Vector3(c[0] - (p.dims.x - 1) * 0.5, c[1] - (p.dims.y - 1) * 0.5, c[2] - (p.dims.z - 1) * 0.5) * V * S, id))
		mmesh.set_instance_color(i, looks[i][0])
		mmesh.set_instance_custom_data(i, VoxelPart.kind_data(int(looks[i][1])))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mmesh
	# A fixed box: plates knocked off one by one must not shrink it and cull the rest.
	var ext := (Vector3(p.dims.x, p.dims.y, p.dims.z) + Vector3.ONE * 2.0 * (Armory.DESIGN_OUT + 1)) * V * S * 0.5
	inst.custom_aabb = AABB(-ext, ext * 2.0)
	mmesh.custom_aabb = inst.custom_aabb
	inst.name = "Armor_" + id
	p.add_child(inst)
	var pts := []
	for c in cells:
		pts.append(Vector3(c[0] - (p.dims.x - 1) * 0.5, c[1] - (p.dims.y - 1) * 0.5, c[2] - (p.dims.z - 1) * 0.5) * V * S)
	var on := PackedByteArray()
	on.resize(cells.size())
	on.fill(1)
	var cols := []
	var ks := []
	for lk in looks:
		cols.append(lk[0])
		ks.append(int(lk[1]))
	p.set_meta("armor", p.get_meta("armor", []) + [{"id": id, "mat": a.get("mat", "iron"), "cells": cells, "pts": pts, "on": on, "alive": cells.size(), "node": inst, "cols": cols, "kinds": ks}])
	_armor_dirty = true

## How much wear (summed blow force) knocks a plate off at last, by its stuff: leather 14,
## bronze 29, iron 31, steel 35 (in blow force, J: a gladius cut is about 24, a hammer blow
## 32, a heavy hammer blow 95: a cut goes through leather at once and dents nothing off steel
## or iron until it adds up; a hammer takes an iron plate at a blow and two or three off steel
## when swung with weight behind it).
const PLATE_WEAR := 23.0
static func plate_wear(mat: String) -> float:
	return PLATE_WEAR * (0.5 + float(Data.material(mat).get("hardness", 0.6)))

## A plate knocked off: gone from him, it flies off the way the blow drove it, a piece of its
## own (what is left of him is uncovered there).
func _knock_plate(part: VoxelPart, ad: Dictionary, ci: int, dir: Vector3, force: float) -> void:
	ad.on[ci] = 0
	ad.alive -= 1
	_armor_dirty = true
	var at: Vector3 = (ad.pts[ci] as Vector3) + Physique.inset(part, ad.cells[ci])
	if ad.node and is_instance_valid(ad.node):
		ad.node.multimesh.set_instance_transform(ci, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	if part == head and not _cosmetic(String(ad.id)):
		place_armor()   # (the hair the plate covered bursts out of the hole)
		_hair_pop = 1.0
		_hair_lagv += dir.normalized() * 0.6 if dir.length_squared() > 1e-6 else Vector3.ZERO
	if part.freeze or not part.is_inside_tree():
		return
	# The plate as voxels of the body's own size, two to a side, in its colour and stuff.
	var c: Color = ad.cols[ci] if ad.has("cols") else Color(0.5, 0.5, 0.5)
	var kind: int = ad.kinds[ci] if ad.has("kinds") else 3
	var q := V * S * 0.25
	var voxels := []
	for dx in [-q, q]:
		for dy in [-q, q]:
			for dz in [-q, q]:
				voxels.append({"p": part.global_transform * (at + Vector3(dx, dy, dz)), "color": c, "kind": kind})
	var out := (part.global_transform.basis * at).normalized()
	var d: Vector3 = dir.normalized() if dir.length_squared() > 1e-6 else out
	Chunk.spawn(part, voxels, (d * 0.6 + out * 0.4 + Vector3.UP * 0.25).normalized() * clampf(force / 40.0, 0.6, 2.0))

## The plates a piece came in without (Armory wear: {id: {part: [cell index]}}): off him from
## the start, quietly (nothing flies).
func apply_armor_wear(wear: Dictionary) -> void:
	for p in parts:
		for ad in p.get_meta("armor", []):
			var idx = wear.get(ad.id, {}).get(p.part_name) if wear.get(ad.id) is Dictionary else null
			if not (idx is Array):
				continue
			for c in idx:
				var ci := int(c)
				if ci >= 0 and ci < ad.on.size() and ad.on[ci] == 1:
					ad.on[ci] = 0
					ad.alive -= 1
					if ad.node and is_instance_valid(ad.node):
						ad.node.multimesh.set_instance_transform(ci, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_armor_dirty = true

## The plates off him now, piece by piece, for the save (the same shape apply_armor_wear takes).
func armor_wear() -> Dictionary:
	var out := {}
	for p in parts:
		for ad in p.get_meta("armor", []):
			if not (Armory.sold(ad.id) or Armory.custom(ad.id)):
				continue
			var idx := []
			for ci in ad.on.size():
				if ad.on[ci] == 0:
					idx.append(ci)
			if not idx.is_empty():
				var piece: Dictionary = out.get(ad.id, {})
				piece[p.part_name] = idx
				out[ad.id] = piece
	return out

## His armour drawn again on the outline of his look (Physique): each plate still on him pulled
## in onto the voxels drawn under it. Where it stops blows ("pts") stays as it was.
func place_armor() -> void:
	for p in parts:
		for ad in p.get_meta("armor", []):
			if ad.node == null or not is_instance_valid(ad.node):
				continue
			var m: MultiMesh = ad.node.multimesh
			for ci in ad.cells.size():
				if ad.on[ci] == 1:
					m.set_instance_transform(ci, Physique.plate_xf(p, ad.cells[ci], ad.pts[ci] as Vector3, String(ad.id)))
		_tuck_hair(p)

## Hair and a beard under a helmet are drawn tucked inside it: a lock with a plate of the helmet
## on it or next to it is not drawn (what hangs out below, a ponytail, braids, stays). Drawing
## only; and as the helmet's plates are knocked off, what they covered shows again.
static func _cosmetic(id: String) -> bool:
	return id.begins_with("hair_") or id.begins_with("beard_") or id.begins_with("hat_") or id.begins_with("mon_") or id == "cape"

func _tuck_hair(p: VoxelPart) -> void:
	var covered := {}
	var holes := {}    # where a plate of the helmet was knocked off: the hair bursts out there
	var capped := {}   # under a cap or a hat: only the locks in its cells and just below them
	for ad in p.get_meta("armor", []):
		var hid := String(ad.id)
		if _cosmetic(hid):
			continue
		for ci in ad.cells.size():
			var c := Vector3i(int(ad.cells[ci][0]), int(ad.cells[ci][1]), int(ad.cells[ci][2]))
			if ad.on[ci] == 1:
				covered[c] = true
			else:
				holes[c] = true
	for ad in p.get_meta("armor", []):
		var hid := String(ad.id)
		if not hid.begins_with("hat_") or ad.node == null or not is_instance_valid(ad.node):
			continue
		if not covered.is_empty():
			# A hat is not worn under a helmet: while the helmet is on him the hat is not drawn
			# (when the last of its plates is knocked off, the hat shows again).
			for ci in ad.cells.size():
				ad.node.multimesh.set_instance_transform(ci, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		for ci in ad.cells.size():
			if ad.on[ci] == 1:
				var c := Vector3i(int(ad.cells[ci][0]), int(ad.cells[ci][1]), int(ad.cells[ci][2]))
				capped[c] = true
				capped[c + Vector3i.DOWN] = true
	if p == head:
		_hair = []
	for ad in p.get_meta("armor", []):
		var id := String(ad.id)
		if not (id.begins_with("hair_") or id.begins_with("beard_")) or ad.node == null or not is_instance_valid(ad.node):
			continue
		# Each lock's place at rest ("base") and how freely it swings ("sway", Fighter._sway_hair).
		var top := -INF
		for c in ad.cells:
			top = maxf(top, float(c[1]))
		var base := []
		var sway := PackedFloat32Array()
		var out := PackedByteArray()
		for ci in ad.cells.size():
			var c := Vector3i(int(ad.cells[ci][0]), int(ad.cells[ci][1]), int(ad.cells[ci][2]))
			var xf := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
			var w := 0.0
			var burst := false
			if ad.on[ci] == 1:
				xf = Physique.plate_xf(p, ad.cells[ci], ad.pts[ci] as Vector3, id)
				w = clampf(0.35 + (top - float(c.y)) / 6.0, 0.35, 1.2)
				var under := capped.has(c)
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						for dz in [-1, 0, 1]:
							if covered.has(c + Vector3i(dx, dy, dz)):
								under = true
				for d in [Vector3i.ZERO, Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
					if holes.has(c + d):
						burst = true
				if burst and not covered.has(c):
					xf = Physique.fluff_xf(p, xf)
					w += 0.6
				elif under:
					xf = Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
					w = 0.0
					burst = false
			base.append(xf)
			sway.append(w)
			out.append(1 if burst and w > 0.0 else 0)
			ad.node.multimesh.set_instance_transform(ci, xf)
		ad["base"] = base
		ad["sway"] = sway
		ad["out"] = out
		if p == head:
			_hair.append(ad)

## The hair is alive (drawing only): each lock lags the head on a spring as he moves, swings
## and takes blows, the long locks hanging lowest the most; a tuft burst out of a broken helmet
## pops out big and settles.
var _hair: Array = []
var _hair_lag := Vector3.ZERO
var _hair_lagv := Vector3.ZERO
var _hair_prev := Vector3.ZERO
var _hair_vel := Vector3.ZERO
var _hair_pop := 0.0
var _hair_moved := false
const HAIR_K := 90.0
const HAIR_D := 9.0
const HAIR_MAX := 0.035

func _sway_hair(dt: float) -> void:
	if _hair.is_empty() or dt <= 0.0 or head == null or head.missing:
		return
	var x := head.get_global_transform_interpolated().origin
	var v := (x - _hair_prev) / dt
	_hair_prev = x
	if v.length() > 30.0:   # (a teleport, a respawn)
		v = Vector3.ZERO
		_hair_vel = Vector3.ZERO
	var acc := (v - _hair_vel) / dt
	_hair_vel = v
	_hair_lagv += (-HAIR_K * _hair_lag - HAIR_D * _hair_lagv - acc * 0.15) * dt
	_hair_lag += _hair_lagv * dt
	if _hair_lag.length() > HAIR_MAX:
		_hair_lag = _hair_lag.normalized() * HAIR_MAX
		_hair_lagv *= 0.5
	_hair_pop = maxf(0.0, _hair_pop - dt * 2.5)
	var local := head.global_transform.basis.inverse() * _hair_lag
	if local.length() < 0.0005 and _hair_pop <= 0.0:
		if not _hair_moved:
			return
		local = Vector3.ZERO
	_hair_moved = local != Vector3.ZERO or _hair_pop > 0.0
	var pop := 1.0 + 0.45 * _hair_pop * _hair_pop
	for ad in _hair:
		if not ad.has("base") or ad.node == null or not is_instance_valid(ad.node):
			continue
		var m: MultiMesh = ad.node.multimesh
		for ci in ad.base.size():
			var w: float = ad.sway[ci]
			if w <= 0.0:
				continue
			var xf: Transform3D = ad.base[ci]
			if ad.out[ci] == 1 and pop > 1.0:
				xf.basis = xf.basis.scaled(Vector3.ONE * pop)
			xf.origin += local * w
			m.set_instance_transform(ci, xf)

## All he carries, kg: his armour and the weapons in his hands (a warhammer and a tower of a
## shield tire a man as plate does).
func carried_kg() -> float:
	var kg := armor_weight()
	for w in weapons.values():
		if w and is_instance_valid(w):
			kg += w.mass
	return kg

## The armour's weight on him, kg (Armory.kg for each piece, the plates still on it).
func armor_weight() -> float:
	if _armor_dirty:
		_armor_dirty = false
		var kg := 0.0
		for p in parts:
			if p.severed:
				continue
			for ad in p.get_meta("armor", []):
				if Armory.sold(String(ad.id)) or Armory.custom(String(ad.id)):
					kg += int(ad.alive) * float(Data.material(String(ad.mat)).get("mass", 0.03)) * Armory.KG_PER_CELL
		armor_kg = kg
	return armor_kg

## The armourer's pieces worn now: those not in `ids` come off, the missing ones go on (in the
## yard, bought or taken off at the smith). Cosmetic pieces are left alone.
func set_armor_pieces(ids: Array) -> void:
	for p in parts:
		var keep := []
		for ad in p.get_meta("armor", []):
			if (Armory.sold(ad.id) or Armory.custom(ad.id)) and not ids.has(ad.id):
				if ad.node and is_instance_valid(ad.node):
					ad.node.queue_free()
			else:
				keep.append(ad)
		p.set_meta("armor", keep)
	_armor_dirty = true
	for id in ids:
		var on := false
		for p in parts:
			if (p.get_meta("armor", []) as Array).any(func(ad): return ad.id == id):
				on = true
		if not on:
			for p in parts:
				if not p.severed:
					_add_armor(p, id)

func hand_world(side: String) -> Vector3:
	return arm[side].fore.global_transform * hand_point

func equip(side: String, design: Dictionary) -> void:
	var fore: VoxelPart = arm[side].fore
	if fore.missing:
		return
	var w := Weapon.new()
	w.setup(design, S * float(mods.get("weaponScale", 1.0)))
	get_parent().add_child(w)
	var rot: Quaternion
	if w.is_shield:
		rot = Quaternion(UP, yaw)
	else:
		rot = PD.quat_of(fore) * grip_q(w)
	var hand := hand_world(side)
	w.global_transform = Transform3D(Basis(rot), hand - rot * w.grip_main)
	w.build_chain()
	_exempt(w)
	w.set_held_by(self)
	weapons[side] = w
	weapon_joints[side] = _grip_joint(fore, w, hand)
	w.welded = not w.is_shield

## A weapon in your hands does not collide with your own body or your other weapon.
func _exempt(w: Weapon) -> void:
	for b in w.bodies():
		for p in parts:
			b.add_collision_exception_with(p)
		for o in weapons.values():
			if o and o != w:
				for ob in o.bodies():
					b.add_collision_exception_with(ob)

## The hand on a weapon: a shield hangs on a pin; a blade is held fast but for the wrist, which
## turns it about its own length (the wheel sets the edge, _drive_wrist turns it there). A
## bow, a crossbow or a chain weapon is simply held fast.
func _grip_joint(fore: VoxelPart, w: Weapon, hand: Vector3) -> Joint3D:
	if w.is_shield:
		return _joint_at(fore, w, hand, false)
	var j := Generic6DOFJoint3D.new()
	add_child(j)
	if has_wrist(w):
		var ax := PD.quat_of(w) * Vector3.UP
		var o := ax.cross(Vector3.FORWARD if absf(ax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		j.global_transform = Transform3D(Basis(ax, o, ax.cross(o)), hand)
		j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
	else:
		j.global_position = hand
	j.node_a = fore.get_path()
	j.node_b = w.get_path()
	return j

## A long pointed shaft (spear, javelin, trident): held and thrust point first.
static func is_spear(w) -> bool:
	if w == null:
		return false
	if not w.has_meta("spear"):
		w.set_meta("spear", w.point_first() and w.design.get("chain") == null)
	return bool(w.get_meta("spear"))

static func has_wrist(w) -> bool:
	return w != null and not w.is_shield and not w.design.has("shoots") and w.design.get("chain") == null

func _joint_at(a: RigidBody3D, b: RigidBody3D, at: Vector3, fixed: bool) -> Joint3D:
	var j: Joint3D
	if fixed:
		j = Generic6DOFJoint3D.new()
	else:
		j = PinJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = a.get_path()
	j.node_b = b.get_path()
	return j

func _attach_off_hand(w: Weapon, move_arm := true) -> void:
	if not w or is_bow(w):
		return   # the off hand of an archer draws the string; it does not hold the stave
	var fore: VoxelPart = arm.L.fore
	var at := w.global_transform * w.grip_off
	if not move_arm:
		# (The hand got there itself: it closes on the haft where it is.)
		weapon_joints.L = _joint_at(fore, w, hand_world("L"), false)
		return
	fore.global_position += at - hand_world("L")
	weapon_joints.L = _joint_at(fore, w, at, false)

func release(side: String) -> Weapon:
	var w: Weapon = weapons[side]
	if not w:
		return null
	if fixed_hand[side] and not arm[side].fore.severed:
		return null
	if weapon_joints[side]:
		weapon_joints[side].queue_free()
		weapon_joints[side] = null
	if side == "R" and two_handed and weapon_joints.L:
		weapon_joints.L.queue_free()
		weapon_joints.L = null
	two_handed = false if side == "R" else two_handed
	weapons[side] = null
	w.holder = null
	w.welded = false
	# Loose: for a moment more it ignores the body that let it go, then it hits anyone.
	w.last_side = side
	w.own_by = self
	w.own_t = 0.35
	if Combat.current and not Combat.current.loose_weapons.has(w):
		Combat.current.loose_weapons.append(w)
	return w

## H: the off hand takes hold of the main weapon's haft too, or lets go of it (character.js
## toggleGrip). Two hands: more power and better control of a heavy weapon; one: the off hand
## is free. Returns "one", "two" or null.
func toggle_grip() -> Variant:
	# A weapon in the left hand alone crosses to the right first, then both take it.
	if not weapons.R and weapons.L and not weapons.L.is_shield and alive:
		swap_hands()
	var w: Weapon = weapons.R
	if not w or w.is_shield or not alive or w.design.get("chain") != null:
		return null
	if two_handed or grip_wait > 0.0:
		grip_wait = 0.0
		if weapon_joints.L:
			weapon_joints.L.queue_free()
			weapon_joints.L = null
		two_handed = false
		two_front = null
		two_gap = null
		return "one"
	if not off_hand_free() or fixed_hand.R or fixed_hand.L:
		return null
	# Room on the grip for the other fist, at its far end; on a short grip the hands crushed
	# together and the arms locked against each other in a swing.
	var off_at = w.two_hand_off()
	if off_at == null:
		return "short"
	w.grip_off = off_at
	# Whatever the off hand held (the shield it came in with, a dagger) is let fall to the sand:
	# the hand is wanted on the haft.
	if weapons.L and not release("L"):
		return null
	# Never onto the haft behind his back (user): where that end of it is behind him, the hand
	# reaches for it in front and closes on it when the haft comes round (_grip_reach).
	if _out_front(w.global_transform * w.grip_off) != Vector3.ZERO and not is_bow(w):
		grip_wait = 1.5
		return "wait"
	two_handed = true
	_attach_off_hand(w)
	return "two"

## H was pressed with the other end of the haft behind him: the off hand takes it once it is out
## in front and in reach. And with both on it, an off hand dragged round behind his back (a low
## stroke across to the far hip) lets go rather than stay there; it takes hold again in front.
func _grip_reach(dt: float) -> void:
	if forearms_pass and not grip_gentle and not two_handed:
		_forearms_pass(false)
	var w: Weapon = weapons.R
	if two_handed:
		grip_wait = 0.0
		if state == "stand" and w and weapon_joints.L and _out_front(hand_world("L")).length() > 0.04 * S:
			haft_behind_t += dt
			if haft_behind_t > 0.12:
				haft_behind_t = 0.0
				_off_hand_off_haft()
				grip_wait = 1.5
		else:
			haft_behind_t = 0.0
		return
	haft_behind_t = 0.0
	if grip_wait <= 0.0:
		grip_gentle = false
		return
	grip_wait -= dt
	if w == null or w.is_shield or weapons.L or held_item != null or not off_hand_free() or state != "stand":
		grip_wait = 0.0
		return
	var at: Vector3 = w.global_transform * w.grip_off
	if _out_front(at) == Vector3.ZERO and hand_world("L").distance_to(at) < (0.07 if grip_gentle else 0.35) * S:
		grip_wait = 0.0
		two_handed = true
		_attach_off_hand(w, not grip_gentle)
		grip_gentle = false

## J: what is in each hand changes hands (a sword to the left, a shield to the right, or the
## one weapon across to the empty hand). Not with both hands on one haft, an arm gone or a
## weapon fixed to a stump. Returns true if anything moved.
func swap_hands() -> bool:
	if not alive or two_handed or held_item != null or (not weapons.R and not weapons.L):
		return false
	for side in ["R", "L"]:
		var fore: VoxelPart = arm[side].fore
		if fixed_hand[side] or fore.severed or fore.hanging or fore.missing or fore.prosthetic != "" or arm[side].upper.severed or arm[side].upper.hanging:
			return false
	var r := release("R")
	var l := release("L")
	for pair in [[r, "L"], [l, "R"]]:
		var w = pair[0]
		if w:
			w.own_t = 0.0
			if Combat.current:
				Combat.current.loose_weapons.erase(w)
			pick_up(pair[1], w)
	# A two-hander that crossed to the right takes the off hand back onto its haft.
	return true

## Slowed for `seconds` to `factor` of the pace (ice, honey, poison); a weaker slow does not
## replace a stronger one.
func slow(seconds: float, factor: float) -> void:
	if slow_timer > 0.0 and slow_factor < factor:
		slow_timer = maxf(slow_timer, seconds * 0.5)
		return
	slow_timer = seconds
	slow_factor = factor

## Caught in a net (bola, weighted net): a quarter of the pace until it is off.
func set_net(on: bool, seconds := 4.0) -> void:
	net_timer = seconds if on else 0.0
	if on and net_mesh == null and DisplayServer.get_name() != "headless":
		net_mesh = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(12, 14, 8) * V * S
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.54, 0.42, 0.23, 0.6)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.material = m
		net_mesh.mesh = bm
		torso.add_child(net_mesh)
	if net_mesh:
		net_mesh.visible = on

## G next to a weapon lying loose (or stuck in someone): the nearest free hand reaches for its
## grip and takes it when it gets there (_reach_tick), never before; a hand already reaching
## goes on reaching.
func grab_nearest(list: Array, only_side := "") -> Weapon:
	if not alive:
		return null
	for side in ["R", "L"]:
		if (only_side == "" or side == only_side) and reach[side] != null:
			return reach[side].w
	for side in ["R", "L"]:
		if only_side != "" and side != only_side:
			continue
		if weapons[side] or arm[side].fore.severed or arm[side].fore.hanging or (side == "L" and two_handed) or (holding != null and holding.side == side):
			continue
		var hand := hand_world(side)
		var best: Weapon = null
		var bd := 0.75
		for w in list:
			if not is_instance_valid(w) or w.holder != null or w.alive_count() == 0:
				continue
			var g: Vector3 = w.grip_world()
			# Reaching down counts for little: a weapon on the sand by your feet is in reach.
			var dx := Vector2(g.x - hand.x, g.z - hand.z).length()
			var dy := hand.y - g.y
			if dy < -0.5 or dy > 1.7 * S:
				continue
			var d := dx + maxf(0.0, dy - 0.4) * 0.15
			if d < bd:
				bd = d
				best = w
		if best and reach_for(side, best):
			return best
	return null

## Taking a weapon up is the hand's own doing (user: no weapon ever jumps into a hand): the hand
## goes to the grip where it lies (he stoops to one on the sand), the fingers close on it and
## draw it into the palm, and the wrist turns it into line with the forearm; only then is it
## held. One stuck in a body stays stuck in it, the hand on its grip, until it is wrenched out.
const REACH_T := 2.2      # how long a hand goes on reaching for a grip before it gives up (s)
const CLOSE_R := 0.12     # the palm this near the grip (x S): the fingers take it
const TURN_T := 1.2       # how long the fist may take drawing it in and turning it into line (s)

func reach_for(side: String, w: Weapon) -> bool:
	if w == null or not is_instance_valid(w) or w.holder != null or not _hand_can_take(side) or reach[side] != null:
		return false
	for o in ["R", "L"]:
		if reach[o] != null and reach[o].w == w:
			return false
	reach[side] = {"w": w, "t": REACH_T, "phase": "reach", "pin": null}
	# The reaching hand goes round the weapon to its grip, not into it (pushed by the knuckles it
	# slid off across the sand, and one stuck in a man shoved him away).
	_arm_exempt(side, w, true)
	return true

func _arm_exempt(side: String, w: Weapon, on: bool) -> void:
	for b in w.bodies():
		if b is PhysicsBody3D:
			for p in [arm[side].fore, arm[side].upper]:
				if on:
					b.add_collision_exception_with(p)
				else:
					b.remove_collision_exception_with(p)

func _hand_can_take(side: String) -> bool:
	var fore: VoxelPart = arm[side].fore
	return alive and not weapons[side] and not fore.severed and not fore.hanging and not fore.missing and fore.prosthetic == "" and not arm[side].upper.severed and not arm[side].upper.hanging and not arm_broken(side) and not (side == "L" and two_handed) and not (holding != null and holding.side == side)

func cancel_reach(side: String) -> void:
	var r = reach[side]
	reach[side] = null
	if r == null:
		return
	if r.pin and is_instance_valid(r.pin):
		r.pin.queue_free()
	if is_instance_valid(r.w) and r.w.holder == null:
		if r.phase == "reach":
			_arm_exempt(side, r.w, false)
		else:
			r.w.own_by = self
			r.w.own_t = 0.3   # (let go of: for a moment more it passes through the hand that had it)

## The weapon a hand is reaching for or turning into the fist, if any.
func reaching(side: String) -> Weapon:
	return reach[side].w if reach[side] != null else null

## A weapon in his hand that is stuck in a body (a blow left it there, or he took hold of one
## stuck in someone): which hand, or "".
func lodged_side() -> String:
	for side in ["R", "L"]:
		var w: Weapon = weapons[side]
		if w and w.stuck != null:
			return side
		var r = reach[side]
		if r != null and r.phase == "fist" and is_instance_valid(r.w) and r.w.stuck != null:
			return side
	return ""

## G with a weapon stuck fast in a body: he lets go of it (it stays where it is).
func let_go_lodged() -> bool:
	var side := lodged_side()
	if side == "":
		return false
	if weapons[side]:
		return release(side) != null
	cancel_reach(side)
	return true

## A weapon in his hand stuck in a body comes out of it when the hand pulls on it long and hard
## enough: the arm held off its mark by it (pulling back, stepping away, or the man it is in
## pulling the other way), both hands on the haft pulling harder, a strong man harder, a winded
## one weaker. Pulling on it drags the man it is in (the joint holds until then).
func _wrench(dt: float) -> void:
	for side in ["R", "L"]:
		var w: Weapon = weapons[side]
		if not (w and w.stuck != null):
			var r = reach[side]
			w = r.w if r != null and r.phase == "fist" and is_instance_valid(r.w) and r.w.stuck != null else null
		if w == null or (side == "L" and two_handed and weapons.R == w):
			wrench_t[side] = 0.0
			continue
		if not is_instance_valid(w.stuck.get("joint")) or not is_instance_valid(w.stuck.get("part")):
			w.unstick()   # (what it was in is gone: nothing holds it any more)
			continue
		var pull := clampf((float(arm_strain[side]) - 0.05 * S) / (0.22 * S), 0.0, 1.5)
		if side == "R" and two_handed:
			pull = maxf(pull, clampf((float(arm_strain.L) - 0.05 * S) / (0.22 * S), 0.0, 1.5)) * 1.5
		pull *= float(mods.strength) * (0.45 + 0.55 * minf(1.0, stamina / 60.0)) * (1.0 if state == "stand" else 0.4)
		wrench_t[side] += pull * dt
		stamina = maxf(0.0, stamina - pull * dt * 5.0)
		if wrench_t[side] >= float(w.stuck.get("need", 0.5)):
			wrench_t[side] = 0.0
			var at := w.stuck_point()
			var part = w.stuck.part
			w.unstick()
			if is_instance_valid(part) and not part.severed:
				part.bleed += 0.8
			lodged.emit(self, w, "free", at)

func _reach_tick(dt: float) -> void:
	stoop = maxf(0.0, stoop - dt * 2.5)
	for side in ["R", "L"]:
		var r = reach[side]
		if r == null:
			continue
		var w: Weapon = r.w
		r.t -= dt
		if not is_instance_valid(w) or w.holder != null or w.alive_count() == 0 or not _hand_can_take(side) or state == "dead" or (state != "stand" and r.phase != "fist") or (r.t <= 0.0 and r.phase == "reach"):
			cancel_reach(side)
			continue
		var fore: VoxelPart = arm[side].fore
		var palm := hand_world(side)
		var g: Vector3 = w.grip_world()
		var d := palm.distance_to(g)
		if r.phase == "reach" and Vector2(g.x - torso.global_position.x, g.z - torso.global_position.z).length() > 1.0 * S:
			cancel_reach(side)   # (gone out of reach: kicked away, taken, rolled off)
			continue
		if r.phase != "fist":
			# Down to it: he bends lower and lower while the hand is still above the grip, and no
			# lower than gets it there.
			r.bend = clampf(float(r.get("bend", 0.0)) + dt * (2.2 if palm.y > g.y + 0.03 * S else -0.8), 0.0, 1.0)
			stoop = maxf(stoop, r.bend)
			if r.phase == "reach" and d < CLOSE_R * S:
				r.phase = "draw"
				r.draw_t = 0.5
				r.hold = Quaternion(UP, yaw).inverse() * (palm - torso.global_position)
				for bd in w.bodies():
					if bd is RigidBody3D:
						bd.freeze = false
						bd.sleeping = false
				_exempt(w)
				if w.own_by and is_instance_valid(w.own_by) and w.own_by != self:
					w.forget_owner()
				w.own_by = self
				w.own_t = 1e9   # (his while it is in his hand: it hurts nobody until it is held)
			if r.phase == "draw":
				# The fingers close round it and draw the grip into the palm (one stuck fast does
				# not come: the hand is drawn to it instead), the arm taking the pull.
				r.draw_t -= dt
				_draw_in(w, fore, palm, g, dt)
				if d < 0.015 * S or (w.stuck != null and d < 0.08 * S):
					# In the palm: the fist closes on it there (one stuck fast in a body, as near
					# as the hand gets to it: it is drawn in properly once it is out). It hangs in it for now; the wrist
					# turns it into line next, and he straightens up with it.
					var j := PinJoint3D.new()
					add_child(j)
					j.global_position = palm
					j.node_a = fore.get_path()
					j.node_b = w.get_path()
					r.pin = j
					r.phase = "fist"
					r.t = TURN_T
					r.from = Quaternion(UP, yaw).inverse() * (palm - torso.global_position)
				elif r.draw_t <= 0.0:
					r.phase = "reach"   # it would not come: the hand goes on reaching for it
			continue
		# In the fist: he straightens up with it, the hand coming up to his guard (_drive_arm),
		# and the wrist turns it into line with the forearm against its weight and its swing.
		r.lift = minf(1.0, float(r.get("lift", 0.0)) + dt / 0.55)
		stoop = maxf(stoop, float(r.get("bend", 0.0)) * (1.0 - r.lift))
		var want: Quaternion = (Quaternion(UP, yaw) if w.is_shield else PD.quat_of(fore) * grip_q(w))
		var err := PD.rot_error(want, PD.quat_of(w))
		if w.stuck != null:
			r.t = TURN_T   # (stuck fast in a body: held on to until it comes out or he lets go)
			continue
		if d > 0.02 * S:
			# Out of the body now, and not yet in the palm: the fingers draw it in.
			if r.pin and is_instance_valid(r.pin):
				r.pin.queue_free()
			r.pin = null
			r.phase = "draw"
			r.draw_t = 0.5
			r.hold = Quaternion(UP, yaw).inverse() * (palm - torso.global_position)
			continue
		var wr := 24.0
		var rel := w.angular_velocity - fore.angular_velocity
		# (Turned about the fist, not its own middle: the weight out along the haft is turned too,
		# and held up against its sagging.)
		var lever := (w.global_transform * w.center_of_mass) - palm
		var about := minf(4.0, 1.0 + w.mass * lever.length_squared() / PD.inertia_of(w))
		var tq := PD.torque_for(w, err * wr * wr - rel * 2.0 * wr) * about - lever.cross(Vector3(0, -w.mass * gravity, 0))
		tq = PD.clamp_len(tq, 90.0 * MS * S * float(mods.strength))
		w.apply_torque_impulse(tq * dt)
		fore.apply_torque_impulse(-tq * dt * 0.5)
		if err.length() < deg_to_rad(6.0) or r.t <= 0.0:
			var pin = r.pin
			reach[side] = null
			if pin and is_instance_valid(pin):
				pin.queue_free()
			w.own_t = 0.0
			if err.length() > deg_to_rad(40.0):
				# It never came into line (jammed against something): it falls from his hand.
				w.own_t = 0.3
				continue
			if pick_up(side, w, true):
				took_up.emit(self, w)

## The fingers drawing a grip into the palm: the two points are brought together the way a
## joint would bring them (an impulse at each, as the bodies' masses and inertia answer it at
## that point), gently and no harder than a hand pulls, the arm taking it back.
func _draw_in(w: Weapon, fore: VoxelPart, palm: Vector3, g: Vector3, dt: float) -> void:
	var rel_v: Vector3 = w.velocity_at(g) - fore.velocity_at(palm)
	var v_des := ((palm - g) / 0.07).limit_length(1.6 * S)
	var k := PD.k_add(PD.point_k(w, g), PD.point_k(fore, palm))
	if absf(k.determinant()) < 1e-9:
		return
	var J := (k.inverse() * (v_des - rel_v)).limit_length(500.0 * MS * S * float(mods.strength) * dt)
	w.apply_impulse(J, g - w.global_position)
	fore.apply_impulse(-J, palm - fore.global_position)

## Takes `w` into the hand on `side`: the grip moved into the palm and welded there (`by_hand`:
## the hand has already brought it there itself, _reach_tick).
func pick_up(side: String, w: Weapon, by_hand := false) -> bool:
	var fore: VoxelPart = arm[side].fore
	if weapons[side] or fore.severed or fore.hanging or fore.missing or fore.prosthetic != "" or arm[side].upper.severed or arm[side].upper.hanging or arm_broken(side):
		return false
	if w.own_by and is_instance_valid(w.own_by) and w.own_by != self:
		w.forget_owner()
	if w.stuck != null:
		w.unstick()
	# Whatever state it lay there in is shed: a frozen one (a guest's, or one held still by the
	# host for them) moves again, a thrown one gets its damping back, and it is awake. Welded
	# to a body that could not move, the hand was pinned where it closed and nothing it did,
	# the throw included, came to anything.
	for b in w.bodies():
		if b is RigidBody3D:
			b.freeze = false
			b.sleeping = false
	w.linear_damp = 0.0   # (the world's own damping again; -1 is not a value Godot 4.7 takes)
	w.angular_damp = 0.0
	var rot: Quaternion = Quaternion(UP, yaw) if w.is_shield else PD.quat_of(fore) * grip_q(w)
	var hand := hand_world(side)
	w.global_transform = Transform3D(Basis(rot), hand - rot * w.grip_main)
	w.linear_velocity = fore.linear_velocity
	w.angular_velocity = Vector3.ZERO
	_exempt(w)
	# The arm starts fresh with it: no stroke, throw or set elbow carried over from before.
	swing_hold[side] = 0.0
	throw_pose[side] = false
	throwing[side] = false
	behind_t[side] = 0.0
	if fore.has_meta("elbow_set"):
		_hold_elbow(side, 0.0, false, 0.0)
	w.set_held_by(self)
	w.thrown_t = 0.0
	w.thrower = null
	w.own_t = 0.0
	weapons[side] = w
	weapon_joints[side] = _grip_joint(fore, w, hand)
	w.welded = not w.is_shield
	aim_q[side] = null
	if Combat.current:
		Combat.current.loose_weapons.erase(w)
	if side == "R" and w.design.get("twoHanded", false) and not weapons.L and off_hand_free() and w.two_hand_off() != null:
		if by_hand:
			# Taken up by hand: the other hand goes to the haft too and takes it when it is there.
			w.grip_off = w.two_hand_off()
			grip_wait = 1.5
			grip_gentle = true
			_forearms_pass(true)
		else:
			two_handed = true
			_attach_off_hand(w)
	return true

## The arm model of any throw (launchVelocity): how fast the hand can send `mass` off, and the
## elevation that lands it on `aim_at` (the lower of the two arcs), with a little scatter.
func launch_velocity(from: Vector3, aim_at: Vector3, mass_: float, power := 0.8, javelin := false, scatter := 0.0, arm_f := 1.0, speed_k := 1.0) -> Vector3:
	var m_arm := 2.5 * pow(S, 2.5)
	var tired := 0.65 + 0.35 * minf(1.0, stamina / 100.0)
	var v_hand := (31.0 if javelin else 24.0) * sqrt(S) * float(mods.strength) * (0.5 + 0.5 * arm_f) * (1.0 - 0.5 * injury) * (0.3 + 0.7 * power) * tired
	var v := minf(38.0, v_hand * speed_k * sqrt(m_arm / (m_arm + maxf(0.05, mass_))))
	var d := aim_at - from
	var dx := maxf(0.01, Vector2(d.x, d.z).length())
	var dy := d.y
	var g := gravity
	# The angle it leaves at is the one a full throw would take to the mark, however hard this
	# one is: the wind-up says how far, not which way (worked out at each throw's own speed, a
	# short flick and a long wind-up at the same crosshair left the hand at angles a world
	# apart, and no two throws looked alike: user).
	var v_aim := v / (0.3 + 0.7 * clampf(power, 0.0, 1.0))
	var disc := pow(v_aim, 4) - g * (g * dx * dx + 2.0 * dy * v_aim * v_aim)
	# Out of reach (a mark on the far wall, the sky): it goes along the line it was aimed, a
	# little above it, never off on a 45-degree lob somewhere else.
	var theta := atan2(v_aim * v_aim - sqrt(disc), g * dx) if disc >= 0.0 else atan2(dy, dx) + 0.05
	var yaw_ := atan2(d.x, d.z)
	var pitch := theta
	if scatter > 0.0:
		var a := randf() * TAU
		var r := sqrt(randf()) * scatter
		yaw_ += cos(a) * r
		pitch += sin(a) * r
	return Vector3(sin(yaw_) * cos(pitch) * v, sin(pitch) * v, cos(yaw_) * cos(pitch) * v)

## F: the weapon in `side`'s hand flies at `target` (or along `dir`): point first if it is a
## javelin, end over end if it is a throwing axe, tumbling otherwise.
const THROW_MADE_SPEED := 1.2     # a throwing weapon leaves the hand this much faster
const THROW_MADE_SCATTER := 0.4   # and strays this much less off its line
func throw_weapon(side: String, target = null, power := 0.8, dir = null) -> Weapon:
	# A hurt arm still throws (a fractured one at a tenth of its strength), only weakly: once
	# a single cracked bone was enough to make F do nothing at all.
	if not alive or arm_func(side) < 0.05:
		return null
	var w: Weapon = weapons[side]
	if not w or (side == "L" and two_handed) or fixed_hand[side]:
		return null
	var from := w.global_transform * w.center_of_mass
	var arm_f := arm_func(side)
	release(side)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var aim_at: Vector3 = target if target != null else from + (dir if dir != null else fwd) * 20.0
	# Made to be thrown (the forge's Throwable): balanced to fly, it leaves the hand faster and
	# goes truer than the same weapon not made for it.
	var made := bool(w.design.get("throwable", false))
	# (A little stray, less than it was: every throw went off a different way.)
	var scatter := (0.003 + 0.01 * (1.0 - power) + 0.002 * minf(6.0, w.mass) + 0.02 * (1.0 - arm_f)) * (THROW_MADE_SCATTER if made else 1.0)
	var point_first := w.point_first() and not w.is_shield
	var vel := launch_velocity(from, aim_at, w.mass, power, point_first, scatter, arm_f, THROW_MADE_SPEED if made else 1.0)
	w.linear_velocity = vel
	if w.is_shield:
		# A shield goes like a discus: flat, face up, spinning, rim first into the man.
		var sd0 := vel.cross(UP)
		sd0 = Vector3(1, 0, 0) if sd0.length_squared() < 1e-6 else sd0.normalized()
		var fw0 := Vector3(vel.x, 0, vel.z).normalized() if Vector2(vel.x, vel.z).length() > 0.01 else Vector3(0, 0, 1)
		var qs := PD.quat_from_axes(sd0, fw0, sd0.cross(fw0).normalized())
		w.global_transform = Transform3D(Basis(qs), from - qs * w.center_of_mass)
		w.angular_damp = 0.05
		w.angular_velocity = (qs * Vector3(0, 0, 1)) * 16.0
	elif point_first:
		var q := Quaternion(UP, vel.normalized())
		w.global_transform = Transform3D(Basis(q), from - q * w.center_of_mass)
		w.angular_velocity = Vector3.ZERO
	else:
		# A spear flies straight; anything else (an axe, a sword, a chair) turns end over end in
		# the plane it flies in: blade up, spinning about the side axis, a heavy one slower.
		var sd := vel.cross(UP)
		sd = Vector3(1, 0, 0) if sd.length_squared() < 1e-6 else sd.normalized()
		var fw := Vector3(vel.x, 0, vel.z).normalized()
		var q := PD.quat_from_axes(UP.cross(sd).normalized(), UP, sd)
		if (q * Vector3(1, 0, 0)).dot(fw) < 0.0:
			q = q * Quaternion(UP, PI)
		w.global_transform = Transform3D(Basis(q), from - q * w.center_of_mass)
		w.angular_damp = 0.03
		var spin := 15.5 if Weapon.spins_in_flight(w.design) else clampf(5.0 + 9.0 / sqrt(maxf(0.3, w.mass)), 6.0, 15.5)
		# A thrower times the turns to the distance (axe throwing): whole turns over the flight,
		# so the blade comes round edge first at the mark. A hurried, weak throw misjudges it.
		var hs := Vector2(vel.x, vel.z).length()
		if hs > 0.5:
			# It lands when its head reaches the front of the man, not when it gets to his middle.
			var span: float = w.mm.get_aabb().size.y * 0.5 if w.mm else 0.3
			var tof := maxf(0.02, Vector2(aim_at.x - from.x, aim_at.z - from.z).length() - span - 0.12) / hs
			var turns := roundf(spin * tof / TAU)
			if turns >= 1.0:
				spin = clampf(TAU * turns / tof, 4.0, 20.0)
			elif tof > 0.05:
				spin = clampf(TAU * 0.04 / tof, 0.0, 4.0)   # too close for a turn: thrown flat, edge on
			spin *= 1.0 + randf_range(-1.0, 1.0) * (0.03 + 0.12 * (1.0 - power) + 0.1 * (1.0 - arm_f))
		w.angular_velocity = sd * -spin
	w.thrower = self
	w.thrown_t = 3.0
	stamina = maxf(0.0, stamina - (6.0 + 8.0 * power) * (0.6 + 0.15 * minf(6.0, w.mass)))
	return w

# ---------- Function of limbs ----------

func leg_func(side: String) -> float:
	var t: VoxelPart = by_name["thigh" + side]
	var s: VoxelPart = by_name["shin" + side]
	if t.severed or s.severed:
		return 0.0
	return minf(t.function(), s.function()) * cord_legs * pelvis_f

## Whether that hand can do anything at all: there, not hanging, not broken, not a hook.
func hand_works(side: String) -> bool:
	var fore: VoxelPart = arm[side].fore
	var upper: VoxelPart = arm[side].upper
	return not (fore.severed or fore.hanging or fore.missing or fore.prosthetic != "" or upper.severed or upper.hanging or arm_broken(side))

## The hand a pot is held in and thrown from: the one it was readied in while that hand still
## works, else the free one (the left first), else whichever works. "" with no hand left. (The
## throw came from the left hand whatever happened to it: cut off by a crocodile, it left from
## the forearm lying on the sand, user.)
func item_hand() -> String:
	if held_item != null and held_item.get("side", "") != "" and hand_works(held_item.side):
		return held_item.side
	# The free hand first: not the one on the haft beside the weapon hand (a pot readied there was
	# thrown from the weapon's grip, as if from the hand holding the sword: user), and with both
	# hands full the off hand rather than the weapon's; the pot is never put in a fist round a hilt
	# while another hand could take it.
	for sd in ["L", "R"]:
		if not weapons[sd] and hand_works(sd) and not (sd == "L" and two_handed):
			return sd
	for sd in ["L", "R"]:
		if hand_works(sd):
			return sd
	return ""

## Whether the left hand can take hold of a haft beside the right: not cut off, hanging, broken,
## lost or a prosthetic (a hand cut off by the crocodile took up a hammer with the good one).
func off_hand_free() -> bool:
	var fore: VoxelPart = arm.L.fore
	var upper: VoxelPart = arm.L.upper
	return not (fore.severed or fore.hanging or fore.missing or fore.prosthetic != "" or upper.severed or upper.hanging or arm_broken("L"))

## A bone of that arm broken: it hangs, and its hand holds nothing (user).
func arm_broken(side: String) -> bool:
	return arm[side].upper.fractured or arm[side].fore.fractured

func arm_func(side: String) -> float:
	var a: Dictionary = arm[side]
	if a.upper.severed or a.fore.severed:
		return 0.0
	return minf(a.upper.function(), a.fore.function()) * cord_arms

## Whether the legs can hold him up: one good leg will do (he hops), two battered ones will
## not; neither will bleeding out or a head too rung to balance. Down, he crawls.
func can_stand() -> bool:
	var l := leg_func("L")
	var r := leg_func("R")
	if bool(mods.get("cyclops", false)) and (l <= 0.0 or r <= 0.0):
		return false
	return state != "dead" and (l > 0.15 or r > 0.15) and (l + r) * 0.5 > 0.3 and blood > 14.0 and (concussion < 0.85 or enraged)

func is_active() -> bool:
	return state != "dead"

## Fall damage: the blow of the sand coming up at `speed` m/s. Standing, the shins take it (and
## he may crumple); down, the part lowest takes it. A giant falls as hard as a man per metre.
func _land_hard(speed: float) -> void:
	var J := (speed - 4.5) * 3.2 * sqrt(S)
	if J < 3.0:
		return
	var targets := []
	if state == "stand" or state == "rising":
		for n in ["shinL", "shinR"]:
			var sh: VoxelPart = by_name[n]
			if not sh.severed:
				targets.append(sh)
	if targets.is_empty():
		var low = null
		for q in parts:
			if not q.severed and (low == null or q.global_position.y < low.global_position.y):
				low = q
		if low:
			targets.append(low)
	for q in targets:
		var at: Vector3 = q.global_position - Vector3(0, q.half_ext.y * 0.9, 0)
		# (The blow is driven down into the sand, which holds him: the hurt without a bounce.)
		var res: Dictionary = apply_hit(q, {"impulse": J / targets.size(), "type": "blunt", "hardness": 0.8, "sharpness": 0.0, "point": at, "dir": Vector3.DOWN, "heavy": 0.2, "crush": minf(0.08, 0.002 * J)})
		if Combat.current:
			Combat.current.hit.emit({"kind": "hit", "p": at, "dir": Vector3.DOWN, "J": J / targets.size(), "type": "blunt", "char": self, "part": q, "attacker": null, "res": res, "killed": not alive, "fall": true})
	if J > 14.0 and state == "stand":
		fall(1.2, true)

## Out cold: on the sand with the head too far gone (bled white or rung senseless) to ever get
## up again. Alive, but beaten: the bout is over for him.
func is_out() -> bool:
	if not _out_cold_now():
		_out_since = -1
		return false
	var now := Engine.get_physics_frames()
	if _out_since < 0:
		_out_since = now
	return float(now - _out_since) / float(Engine.physics_ticks_per_second) >= OUT_HOLD

## Out cold only once it lasts: down, unable to stand, the head too far gone or ringing for
## OUT_HOLD seconds on end. A single hard knock that sends him down (and clears in a moment, as a
## ringing head does on the sand) no longer ends his bout on the spot; a crushing blow, a cracked
## skull or a ruined head still does.
const OUT_HOLD := 0.6
const CONC_PER_BLOW := 0.7   # the most one blow to a sound skull adds to the concussion
var _out_since := -1   # the physics frame he was first seen out cold (-1: he is not)
func _out_cold_now() -> bool:
	if state != "down" or not alive or can_stand():
		return false
	return head.hp < 30.0 or (concussion >= 0.85 and not enraged)

## A giant (or anything his size) with an eye put out, an arrow in it or a blade through it, is
## not put down by it: he goes berserk in a blind panic and fights on the harder to the end of
## the bout, his head ringing no more than enough to spoil his aim (bot.gd: lashing out every
## way, kicking, grabbing, punching).
func enrage() -> void:
	if enraged or not alive or S < RAGE_SIZE:
		return
	enraged = true
	raged.emit(self)

## The voxels of the eyes: on the front of the head, the band across it where the eyes are (a
## man's two, the Cyclops' one great eye in the middle; monster_look paints them there).
func _eye_cells() -> Array:
	if eye_cells.is_empty():
		var front := head.dims.z * int(Data.body_res) - 1
		for i in head.fx.size():
			if head.fz[i] == front and head.fx[i] >= 2 and head.fx[i] <= 7 and head.fy[i] >= 5 and head.fy[i] <= 8:
				eye_cells.append(i)
	return eye_cells

## An eye put out (some of its voxels knocked away) enrages a big one.
func _check_eye() -> void:
	if enraged or S < RAGE_SIZE or head.severed:
		return
	var gone := 0
	for i in _eye_cells():
		if head.alive[i] == 0:
			gone += 1
	if gone >= 2:
		enrage()

## Beaten, one way or the other.
func is_beaten() -> bool:
	return not alive or is_out()

# ---------- PD drives ----------

func pd_axis(part: VoxelPart, local_axis: Vector3, des: Vector3, wn: float, zeta: float, max_t: float, dt: float, scale := 1.0, w_des := Vector3.ZERO) -> void:
	if part.severed or wn <= 0.0 or max_t <= 0.0:
		return
	var nc := Greedy.core()
	if nc:
		nc.pd_axis(part, local_axis, des, wn, zeta, max_t, dt, scale, w_des)
		return
	var kp := wn * wn
	var kd := 2.0 * zeta * wn
	var cur := PD.quat_of(part) * local_axis
	var err := PD.dir_error(cur, des.normalized())
	var alpha := err * kp - (part.angular_velocity - w_des) * kd
	var tq: Vector3
	if scale != 1.0:
		var tw := cur * alpha.dot(cur)
		tq = PD.torque_for(part, alpha - tw, scale) + PD.torque_for(part, tw, 1.0)
	else:
		tq = PD.torque_for(part, alpha, 1.0)
	part.apply_torque_impulse(PD.clamp_len(tq, max_t) * dt)

func pd_relative(part: VoxelPart, parent: VoxelPart, rel_q: Quaternion, wn: float, zeta: float, max_t: float, dt: float, boost := 1.0, react := 1.0) -> void:
	if part.severed or wn <= 0.0:
		return
	var nc := Greedy.core()
	if nc:
		nc.pd_relative(part, parent, rel_q, wn, zeta, max_t, dt, boost, react)
		return
	var ic := PD.inertia_of(part)
	var ip := PD.inertia_of(parent)
	var desired := PD.quat_of(parent) * rel_q
	var err := PD.rot_error(desired, PD.quat_of(part))
	var rel := part.angular_velocity - parent.angular_velocity
	var tq := PD.torque_for(part, err * (wn * wn) - rel * (2.0 * zeta * wn), boost * ip / (ic + ip))
	tq = PD.clamp_len(tq, max_t)
	part.apply_torque_impulse(tq * dt)
	parent.apply_torque_impulse(-tq * dt * react)

## The legs' joint drive (character.js motorRel, which used Rapier's implicit motors). A torque
## PD stepped at 120 Hz with the leg's gains chattered every frame (the knee's acceleration
## flipped sign at the step rate, so the legs shook and the feet skated). This one steers the
## joint's relative angular velocity toward a target set by the angle error and closes only part
## of the gap each step, so it can never overshoot and never chatters, however stiff.
func motor_rel(part: VoxelPart, parent: VoxelPart, rel_q: Quaternion, wn: float, max_t: float, dt: float, react := 1.0) -> void:
	if part.severed or wn <= 0.0:
		return
	var nc := Greedy.core()
	if nc:
		nc.motor_rel(part, parent, rel_q, wn, max_t, dt, react)
		return
	var desired := PD.quat_of(parent) * rel_q
	var err := PD.rot_error(desired, PD.quat_of(part))
	var rel := part.angular_velocity - parent.angular_velocity
	var v_des := PD.clamp_len(err * wn, 16.0)
	var tq := PD.torque_for(part, (v_des - rel) / dt, 1.0) * 0.6
	tq = PD.clamp_len(tq, max_t)
	part.apply_torque_impulse(tq * dt)
	parent.apply_torque_impulse(-tq * dt * react)

func pd_twist(part: VoxelPart, ref: RigidBody3D, kp: float, kd: float, max_t: float, dt: float) -> void:
	if part.severed:
		return
	var nc := Greedy.core()
	if nc:
		nc.pd_twist(part, ref, kp, kd, max_t, dt)
		return
	var q := PD.quat_of(part)
	var axis := q * Vector3(0, -1, 0)
	var rq := PD.quat_of(ref)
	var f := q * Vector3(0, 0, 1)
	f -= axis * axis.dot(f)
	var rf := rq * Vector3(0, 0, 1)
	rf -= axis * axis.dot(rf)
	if f.length_squared() < 1e-6 or rf.length_squared() < 1e-6:
		return
	f = f.normalized(); rf = rf.normalized()
	var ang := atan2(f.cross(rf).dot(axis), f.dot(rf))
	var spin := (part.angular_velocity - ref.angular_velocity).dot(axis)
	var t := clampf(kp * ang - kd * spin, -max_t, max_t)
	part.apply_torque_impulse(axis * t * dt)

## The part rolled about its own length (its -y) until its front (+z) lies along `want`
## (projected across the axis): a hinge's bend plane set to where the next bone must go.
func _twist_to(part: VoxelPart, want: Vector3, kp: float, kd: float, max_t: float, dt: float) -> void:
	if part.severed:
		return
	var q := PD.quat_of(part)
	var axis := q * Vector3(0, -1, 0)
	var f := q * Vector3(0, 0, 1)
	f -= axis * axis.dot(f)
	var rf := want - axis * axis.dot(want)
	if f.length_squared() < 1e-6 or rf.length_squared() < 1e-6:
		return
	f = f.normalized()
	rf = rf.normalized()
	var ang := atan2(f.cross(rf).dot(axis), f.dot(rf))
	var spin := part.angular_velocity.dot(axis)
	part.apply_torque_impulse(axis * clampf(kp * ang - kd * spin, -max_t, max_t) * dt)

# ---------- Control ----------

## One physics step of a fighter driven by `inp` (the same input dictionary as the web game:
## mx, mz, main{x,y}, off{x,y}, thrust, power, sprint, jump, crouch, kick, look{yaw,pitch}...).
## A blow moves a man, it does not fling him: while a foe's weapon presses on him, and for a
## moment after (a part pressed into a big weapon is pushed back out of it hard), it can add no
## more than this to his speed (a battering ram threw men five metres up, a warhammer half a
## metre; user). Thrown by a giant or blown up by a pot, he flies as before.
const STRUCK_V := 3.5        # m/s along the ground
const STRUCK_VY := 1.0       # m/s upward
const STRUCK_FRAMES := 30    # physics frames after the weapon last touched him (a quarter second)
func _no_fling() -> void:
	var tv: Vector3 = torso.linear_velocity
	# (A beast's own lunges and rolls are its own, and a man in a hold goes where he is dragged.)
	if Engine.get_physics_frames() - struck_frame <= STRUCK_FRAMES and thrown_t <= 0.0 and not (self is Beast) and not is_instance_valid(grabbed_by):
		var h := Vector2(tv.x, tv.z)
		var h_max := maxf(STRUCK_V * sqrt(S), Vector2(v_free.x, v_free.z).length())
		var want := Vector3(tv.x, minf(tv.y, maxf(STRUCK_VY, v_free.y)), tv.z)
		if h.length() > h_max:
			h = h.limit_length(h_max)
			want = Vector3(h.x, want.y, h.y)
		var fix := want - tv
		if fix.length_squared() > 1e-4:
			for p in parts:
				if not p.severed:
					p.linear_velocity += fix
		return
	v_free = tv

func control(dt: float, inp_in: Dictionary) -> void:
	time += dt
	space = get_world_3d().direct_space_state
	_no_fling()
	for p in parts:
		if p.flinch_t > 0.0:
			p.flinch_t -= dt
	if push_t > 0.0:
		push_t -= dt
	var live := state != "dead"
	shove_t = maxf(0.0, shove_t - dt)
	slow_timer = maxf(0.0, slow_timer - dt)
	if throw_anim != null:
		throw_anim.t -= dt
		if throw_anim.t <= 0.0:
			throw_anim = null
	if net_timer > 0.0:
		net_timer -= dt
		if net_timer <= 0.0:
			set_net(false)
	if wine_timer > 0.0:
		wine_timer -= dt
		if wine_timer <= 0.0:
			mods.drunk = sober_drunk   # back to what he was (an Emperor's drunk decree stays)
	if help_t > 0.0:
		help_t -= dt
	# Playing dead: a standing fighter goes fully limp until the key is let go.
	if limp and live:
		if state == "stand":
			set_standing(false)
			state = "down"
			down_timer = 0.4
		elif state == "down":
			down_timer = maxf(down_timer, 0.4)
	var inp: Dictionary = inp_in if live and not limp else {}
	if inp.get("grip", false) and state == "stand":
		if toggle_grip() == "short":
			note.emit(self, "The grip is too short for two hands")
	if inp.get("swap", false) and state == "stand":
		swap_hands()
	_grip_reach(dt)
	_reach_tick(dt)
	_wrench(dt)
	var t_pos: Vector3 = torso.global_position
	var t_rot: Quaternion = PD.quat_of(torso)
	var yaw_q := Quaternion(UP, yaw)
	var leg_l := leg_func("L")
	var leg_r := leg_func("R")
	var leg_avg := (leg_l + leg_r) * 0.5
	var blood_f: float = minf(1.0, 0.35 + blood / 100.0)
	pain = maxf(0.0, pain - dt * 0.2)
	var heavy := 1.0 - 0.5 * injury
	var stam_f := (0.3 + 0.7 * stamina / 100.0) * (0.6 + 0.4 * heavy)
	var conc_f := 1.0 - concussion * 0.6

	# Bleeding, recovery.
	var bleed := 0.0
	# The heart pushes the blood out in beats while it still beats (a cut artery spurts with it).
	var beat := 0.5 + 0.5 * sin(time * TAU * (1.2 + 0.6 * pain)) if state != "dead" and blood > 5.0 and heart_t < 0.0 else 0.0
	# A wound clots at the rate the man bleeds: a player's (PLAYER_BLEED) and a hide trained
	# to bleed slow close sooner, a berserker's slower.
	var clot := dt * 0.08 / maxf(0.3, float(mods.bleed))
	for p in parts:
		bleed += p.bleed + p.artery
		p.bleed = maxf(0.0, p.bleed - clot)
		p.update_drips()
		p.update_blood(dt, beat)
		if p.stump:
			p.stump_t += dt
			bleed += 2.5 * maxf(0.0, 1.0 - p.stump_t / 12.0)
	blood = maxf(0.0, blood - bleed * BLEED_RATE * float(mods.bleed) / (S * S) * dt)
	if dying > 0.0:
		# At death's door: no blood comes back, and the door shuts when the time is up.
		blood = minf(blood, 12.0)
		dying -= dt
		if dying <= 0.0:
			dying = 0.0
			die("bleed")
			inp = {}
	# Out cold on the sand with his wounds staunched, he comes round: the blood comes back up
	# to where his legs will hold him and his head clears, faster lying still than on his
	# feet. (Felled with too little blood or too rung a head to stand, and no longer bleeding,
	# a man once lay there alive for the rest of the bout.)
	if state == "down" and bleed < 0.15 and blood > 0.0 and blood < 22.0:
		blood = minf(22.0, blood + 1.2 * dt)
	_organs_tick(dt)
	_check_joints(dt)
	stagger = maxf(0.0, stagger - dt * 1.6)
	eye_hurt = maxf(eye_floor, eye_hurt - dt * 0.01)
	_tear_strips(dt)
	concussion = maxf(float(mods.drunk), concussion - dt * (0.05 if state == "stand" else 0.16))
	if enraged:
		concussion = minf(concussion, 0.45)
	if live and (blood <= 0.0 or head.hp <= 0.0 or head.severed or torso.hp <= 0.0 or _head_ruined()):
		die("decap" if head.severed else ("bleed" if blood <= 0.0 else "wounds"))
		live = false
		inp = {}

	var stamina_use := 0.0
	# ----- Stance -----
	var up_w := t_rot * UP
	var tilt := acos(clampf(up_w.y, -1.0, 1.0))
	tilt_t = tilt_t + dt if tilt > 1.15 else 0.0
	var fresh := time - stood_at < 5.0
	if state == "stand" and (tilt_t > (0.45 if fresh else 0.2) or (tilt > 1.5 and (not fresh or tilt_t > 0.25)) or not can_stand()):
		fall(1.8 if can_stand() else 99.0, true)
	if state == "down":
		down_timer -= dt
		# Felled for a cause (too rung, too drained, the legs gone) he lies "until further
		# notice"; the moment the cause has passed, the notice is a couple of seconds.
		if can_stand() and down_timer > 2.0 and not limp:
			down_timer = 2.0
		if down_timer <= 0.0 and can_stand():
			state = "rising"
			rise_t = 0.0
			rise_q0 = null
			_legs_touch_ground(false)
	if state == "rising":
		rise_t = minf(1.0, rise_t + dt / (1.5 * (1.0 + injury)) * (2.0 if help_t > 0.0 else 1.0))
		if rise_q0 == null:
			rise_q0 = t_rot
		if rise_t >= 1.0 and tilt < 0.5:
			set_standing(true)
		if not can_stand():
			fall(99.0)
	var rising := state == "rising"
	var e1 := PD.smooth(0.0, 0.45, rise_t) if rising else 1.0
	var e2 := PD.smooth(0.35, 1.0, rise_t) if rising else 1.0
	var standing := state == "stand" or rising
	var stand_f := 0.6 + 0.4 * e1 if rising else 1.0

	# ----- Support spring -----
	var total_mass := 0.0
	for p in parts:
		if not p.severed:
			total_mass += p.nominal_mass / (LEG_MASS if p.def.get("leg", false) else 1.0)
	body_mass = total_mass
	for w in weapons.values():
		if w:
			total_mass += w.mass
	# The sand, or whatever lies on it under him: a man or a beast down there holds him up too
	# (read off the sand alone, standing on a body he was "in the air", no foot planted, and
	# the legs hung).
	var hit := _ground_ray(space, t_pos)
	var crouch := 1.0 - e2 if rising else (1.0 if inp.get("crouch", false) else minf(1.0, maxf(low_hand * 0.9, stoop)))
	var one_leg: bool = minf(leg_l, leg_r) < 0.1
	var leg_flinch := 1.0
	for n in ["thighL", "thighR", "shinL", "shinR"]:
		if by_name[n].flinch_t > 0.0:
			leg_flinch = 0.6
	var support: float = minf(1.0, leg_avg * 1.6) * (0.75 if one_leg else 1.0) * stand_f * leg_flinch if standing else 0.0
	var lv0 := torso.linear_velocity
	# A hard landing (thrown by a giant, tossed by a bull, off a crate) breaks on the legs if
	# he comes down on them, on whatever hits first if he does not: the faster, the worse.
	# (The fastest he fell since he left the ground, cashed in when the fall is over.)
	if lv0.y < -3.0:
		prev_vy = minf(prev_vy, lv0.y)
	elif prev_vy < -5.5 and lv0.y > -1.0:
		if live:
			_land_hard(-prev_vy)
		prev_vy = 0.0
	elif lv0.y > -1.0:
		prev_vy = 0.0
	var walk_amt: float = minf(1.0, Vector2(lv0.x, lv0.z).length() / 2.5)
	var bob := 0.035 * S * walk_amt * (0.5 - 0.5 * cos(2.0 * gait_phase)) if standing else 0.0
	# On one leg he cannot walk: he hops, a push off the good leg and a short flight, and only
	# the push moves him on. Standing on it he sways, catching his balance.
	var hop_k := 0.0
	var wants_move := Vector2(float(inp.get("mx", 0.0)), float(inp.get("mz", 0.0))).length_squared() > 0.05
	if one_leg and standing and not rising and wants_move:
		hop_phase = fmod(hop_phase + dt * 2.3 * (0.6 + 0.4 * stamina / 100.0), 1.0)
		hop_k = maxf(0.0, sin(hop_phase * TAU))
		bob = 0.22 * S * hop_k
		stamina_use += 4.0 * dt
	else:
		hop_phase = 0.0
	var grounded := false
	var ground_y := 0.0
	if hit:
		var dist = t_pos.y - hit.position.y
		ground_y = hit.position.y
		ground_level = ground_y
		var run_low := 0.06 * minf(1.0, walk_amt * 2.5 / 3.5)
		# His weight is on his legs: the knees give a little under what he carries (armour, a
		# heavy weapon), and for a moment under every footfall and landing (land_sag), more the
		# harder he came down (user: he floated, the legs carried nothing).
		var burden_k := clampf(carried_kg() / 25.0, 0.0, 1.0)
		var desired := torso_y * (0.95 - run_low - 0.035 * burden_k) * (1.0 - crouch * 0.22 - stoop * 0.24 - (0.12 if one_leg else 0.0)) * (0.7 + 0.3 * support) * (0.55 + 0.45 * e2 if rising else 1.0) + bob
		# The weight is on the leg that is down: the hips ride as high as that leg, a little bent,
		# reaches from the foot planted on the sand to the hip (an inverted pendulum: up as the body
		# passes over the foot, down as the stride opens). Never higher than the legs reach, so
		# a planted foot always stands on the sand.
		if state == "stand" and not one_leg and hop_phase <= 0.0:
			var pend := INF
			var reach_l := 16.0 * V * S * (0.965 - crouch * 0.12 - stoop * 0.14 - run_low * 0.5)
			for sd in ["L", "R"]:
				var ftp = feet[sd]
				if ftp == null or ftp.swing or by_name["shin" + sd].severed:
					continue
				var hip_w: Vector3 = t_pos + t_rot * by_name["thigh" + sd].pa
				var dxz := Vector2(hip_w.x - ftp.anchor.x, hip_w.z - ftp.anchor.z).length()
				var hh := sqrt(maxf(0.0, reach_l * reach_l - dxz * dxz))
				pend = minf(pend, float((ftp.anchor as Vector3).y) + hh + (t_pos.y - hip_w.y))
			if pend < INF:
				stance_h = maxf(pend, ground_y + torso_y * (0.82 - crouch * 0.2 - stoop * 0.24))
			if stance_h > 0.0:
				desired = minf(desired, stance_h - ground_y) if pend < INF else desired
		desired -= land_sag   # (after the planted leg's height: walking, that is what holds him up)
		# The feet stand on the sand, never in it and never above it: standing, the legs do not
		# meet the ground (the spring holds him), so the hips are set by where the soles are. A
		# sole sunk in lifts him by as much (a cyclops with his shins hacked away stood knee-deep
		# in the arena, user); both soles up off it let him down by as much, until one touches
		# (a man hit hard hovered with his feet clear of the sand, user). In a hop or getting up,
		# no.
		if state == "stand" and hop_phase <= 0.0 and not rising and dist < desired + 0.25:
			var sole_lo := INF
			var sole_planted := INF
			for sd in ["L", "R"]:
				var sh: VoxelPart = by_name["shin" + sd]
				if sh.severed or by_name["thigh" + sd].severed:
					continue
				var sy: float = (sh.global_transform * Vector3(0, -4 * V * S, 0)).y - ground_y
				sole_lo = minf(sole_lo, sy)
				var ftp = feet[sd]
				if ftp != null and not ftp.swing:
					sole_planted = minf(sole_planted, sy)
			if sole_planted < -0.03 * S:
				desired = maxf(desired, dist - sole_planted - 0.01 * S)
			elif sole_lo < INF and sole_lo > 0.05 * S:
				desired = minf(desired, dist - (sole_lo - 0.02 * S))
		grounded = dist < desired + 0.25
		# Touching down after a jump or a flight, the knees take the fall.
		if grounded and air_time > 0.12 and standing and not rising:
			land_sag = maxf(land_sag, clampf((0.015 + 0.012 * maxf(0.0, -lv0.y)) * S, 0.025 * S, 0.07 * S))
		if grounded and support > 0.0:
			var vy := torso.linear_velocity.y
			var f = total_mass * (gravity * minf(1.0, support * 1.1) + 140.0 * (desired - dist) * support - 22.0 * vy * support)
			f = clampf(f, 0.0, total_mass * 30.0)
			torso.apply_central_impulse(Vector3(0, f * dt, 0))

	air_time = 0.0 if grounded else air_time + dt
	land_sag *= exp(-dt * 10.0)
	# Off the sand he comes down like the weight he is: a jump or a stumble off a ledge falls
	# faster than a feather (gravity alone, with the legs held up by nothing, let him hang in
	# the air and drift down: user). Only on his own feet: a man thrown, held or lying falls as
	# he falls.
	if standing and not rising and not grounded and live and not is_instance_valid(grabbed_by) and not (has_meta("beast_hold") and is_instance_valid(get_meta("beast_hold"))):
		var g_more := 0.9 if torso.linear_velocity.y < 0.0 else 0.45
		torso.apply_central_impulse(Vector3(0, -total_mass * gravity * g_more * dt, 0))

	# ----- Locomotion -----
	var lv := torso.linear_velocity
	var move_local := Vector3.ZERO if rising else Vector3(inp.get("mx", 0.0), 0, inp.get("mz", 0.0))
	# A thrust is a lunge: the feet carry him a step in after the point while the button is down
	# (held out at arm's length and no more, the point only pricked).
	var lunge := maxf(float(inp.get("thrust", 0.0)), float(inp.get("offThrust", 0.0)))
	if lunge > 0.3 and standing and not rising and shove_t <= 0.0 and (weapons.R or weapons.L) and holding == null:
		# The step goes the way the point goes: along the thrust's line as it lies on the ground
		# (a stab across the body steps across, one straight up or down hardly steps at all).
		var tl_m = thrust_line.R if thrust_line.R != null else thrust_line.L
		var step := Vector3(0, 0, 1)
		if tl_m != null:
			var d: Vector3 = tl_m.dir
			step = Vector3(d.x, 0.0, d.z) * clampf(1.0 - 1.3 * absf(d.y), 0.0, 1.0)
		step *= 0.75 * clampf(lunge, 0.0, 1.0)
		move_local.z = maxf(move_local.z, step.z)
		if absf(step.x) > absf(move_local.x):
			move_local.x = step.x
	# Reaching for a weapon a step off: he steps to it (nothing else moving him).
	var rs = reach.R if reach.R != null and reach.R.phase == "reach" else (reach.L if reach.L != null and reach.L.phase == "reach" else null)
	if rs != null and is_instance_valid(rs.w) and standing and move_local.length_squared() < 0.05:
		var to_g: Vector3 = (rs.w as Weapon).grip_world() - t_pos
		to_g.y = 0.0
		var far := to_g.length() - 0.36 * S
		if far > 0.0:
			move_local += yaw_q.inverse() * to_g.normalized() * clampf(far / (0.3 * S), 0.3, 0.6)
	if move_local.length_squared() > 1.0:
		move_local = move_local.normalized()
	var sprint: bool = inp.get("sprint", false) and stamina > 5.0 and move_local.z > 0.3
	var load_ := Armory.burden(carried_kg())
	var speed := (3.8 if sprint else 2.1) * sqrt(S) * float(mods.speed) * float(load_.pace) * (0.3 if one_leg else 0.4 + 0.6 * leg_avg) * blood_f * heavy * (1.0 - crouch * 0.45) / (1.0 + carrying * 0.9 + 0.05 * stuck_load) * (slow_factor if slow_timer > 0.0 else 1.0) * (0.25 if net_timer > 0.0 else 1.0)
	var dir_f = (1.0 + 0.35 * move_local.z if move_local.z < 0.0 else 1.0) * (1.0 - 0.15 * abs(move_local.x))
	var move_world = yaw_q * move_local * speed * dir_f
	last_move = yaw_q * move_local if live else Vector3.ZERO
	var planted := 0
	var anchor_v := Vector3.ZERO
	if standing and grounded:
		for side in ["L", "R"]:
			var ft = feet[side]
			var shin: VoxelPart = by_name["shin" + side]
			if ft == null or ft.swing or shin.severed:
				continue
			var foot := shin.global_transform * Vector3(0, -4 * V * S, 0)
			ft.slip = Vector2(ft.anchor.x - foot.x, ft.anchor.z - foot.z).length()
			anchor_v.x += (ft.anchor.x - foot.x) * ANCHOR_K
			anchor_v.z += (ft.anchor.z - foot.z) * ANCHOR_K
			planted += 1
		if planted > 0:
			move_world += PD.clamp_len(anchor_v / planted, 1.5)
		# The weight sits over the feet: with both planted, the hips are drawn over the point
		# between them (standing still, every way; walking, only sideways, which also keeps the
		# walk straight). Godot's joint torques, unlike Rapier's motors, let the body creep off
		# its feet and glide as if it hovered.
		# On one foot the weight goes over it: the hips swing across to stand above it.
		if planted == 1 and move_local.length_squared() > 0.01:
			for sd in ["L", "R"]:
				var fs = feet[sd]
				if fs and not fs.swing and not by_name["shin" + sd].severed:
					var side_w2 := yaw_q * Vector3(1, 0, 0)
					var off1 := Vector3(fs.anchor.x - t_pos.x, 0, fs.anchor.z - t_pos.z)
					move_world += PD.clamp_len(side_w2 * off1.dot(side_w2) * 0.6 * STANCE_K, 0.25)
		if planted == 2 and feet.L and feet.R:
			var mid: Vector3 = ((feet.L.anchor as Vector3) + (feet.R.anchor as Vector3)) * 0.5
			var off := Vector3(mid.x - t_pos.x, 0, mid.z - t_pos.z)
			if move_local.length_squared() > 0.01:
				var side_w := yaw_q * Vector3(1, 0, 0)
				off = side_w * off.dot(side_w)
			move_world += PD.clamp_len(off * CENTER_K, 1.0)
	on_ground = grounded
	if grounded and standing:
		# He moves himself by pushing off the sand: with no foot down there is next to nothing to push on.
		var accel := (2.5 + 18.5 * minf(1, planted)) * stand_f * float(mods.accel) * (0.55 + 0.45 * heavy)
		if one_leg:
			accel *= (0.2 + 2.2 * hop_k) if hop_phase > 0.0 else 1.0
		var ix := Vector2(move_world.x - lv.x, move_world.z - lv.z).limit_length(6.0) * accel * total_mass * dt
		torso.apply_central_impulse(Vector3(ix.x, 0, ix.y))
		if sprint:
			stamina_use += 10.0 * dt
		if inp.get("jump", false) and stamina > 15.0:
			torso.apply_central_impulse(Vector3(0, total_mass * 3.8 * maxf(0.3, leg_avg), 0))   # (a man's jump: it went up a metre and more and hung there)
			stamina -= 15.0
	# Down but alive: drag yourself along on your arms, slowly, slower still the worse you are.
	crawling = false
	if live and state == "down" and grounded and move_local.length_squared() > 0.05 and net_timer <= 0.0:
		var crawl_speed := 0.75 * sqrt(S) * (0.35 + 0.65 * heavy) * (0.5 + 0.5 * (arm_func("L") + arm_func("R")) * 0.5)
		var cw: Vector3 = yaw_q * move_local * crawl_speed
		var ixc := Vector2(cw.x - lv.x, cw.z - lv.z).limit_length(3.0) * 26.0 * total_mass * dt
		torso.apply_central_impulse(Vector3(ixc.x, 0, ixc.y))
		crawl_phase += dt * 4.5
		crawling = true
		stamina_use += 3.0 * dt
	v_smooth = v_smooth.lerp(Vector3(lv.x, 0, lv.z), minf(1.0, dt * 10.0))
	var h_speed := Vector2(v_smooth.x, v_smooth.z).length()
	var step_len: float = (minf(1.0, 0.3 + 0.17 * h_speed) if sprint else minf(0.66, 0.28 + 0.12 * h_speed)) * S
	if h_speed > 0.25:
		gait_phase += dt * h_speed * PI / step_len

	# ----- Upright balance -----
	if standing:
		var balance: float = minf(1.0, (0.25 + 0.75 * minf(1.0, leg_avg * 1.3)) * (1.0 - stagger * 0.6) * sqrt(conc_f)) * stand_f
		var low_lean := low_hand * 0.42 / sqrt(maxf(1.0, S)) + thrust_lean * 0.35
		low_hand = 0.0
		thrust_lean = 0.0
		var kneel_lean := 0.75 * (1.0 - e2) if rising else 0.0
		var lean := Quaternion(Vector3(1, 0, 0), (0.2 if sprint else 0.1) * move_local.z + crouch * 0.25 / sqrt(maxf(1.0, S)) + (0.12 if one_leg else 0.0) + low_lean + kneel_lean + stoop * 0.6 / sqrt(maxf(1.0, S)))
		if h_speed < 0.4 and live:
			var sway := 7.0 if one_leg else 1.0
			lean = Quaternion(Vector3(0, 0, 1), 0.01 * sway * sin(time * 0.6 * sqrt(sway) + slot * 2)) * Quaternion(Vector3(1, 0, 0), 0.012 * sway * sin(time * 0.9 * sqrt(sway) + slot)) * lean
		var twist := 0.0
		for s in ["R", "L"]:
			var t: float = jab_t[s]
			if t > 0.0:
				var k := 1.0 - t / JAB_TIME
				twist += (1.0 if s == "R" else -1.0) * 0.5 * (k / 0.15 if k < 0.15 else (1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4))
		# Both hands on a haft, the shoulders turn with the stroke: out to the side the arm across
		# the chest was at the end of its reach and the blade stopped short of the mouse.
		if two_handed and live:
			var hx := clampf(float(hand_input.R.get("x", 0.0)), -2.0, 2.0)
			var low_t := clampf(-float(hand_input.R.get("y", 0.0)) - 0.4, 0.0, 1.0)   # (bent over a low guard, less)
			twist_two = lerpf(twist_two, -hx * TWO_HAND_TWIST * (1.0 - 0.6 * low_t), minf(1.0, dt * 6.0))
			twist += twist_two
		else:
			twist_two = 0.0
		var desired_q := yaw_q * Quaternion(UP, twist) * lean
		if rising and rise_q0 != null:
			desired_q = (rise_q0 as Quaternion).normalized().slerp(desired_q.normalized(), e1)
		var err := PD.rot_error(desired_q, t_rot)
		var I := 4.0 * MS * S * S
		# Both hands on a heavy haft, the trunk holds itself up against it harder: swung with the
		# arms alone it bent him over sideways and back like a bow.
		var hold := TWO_HAND_TRUNK if two_handed and not rising else 1.0
		var wn := (8.0 if rising else 12.0) * sqrt(balance) * sqrt(hold)
		var tq := (err * (wn * wn) - torso.angular_velocity * (2.0 * wn)) * I
		torso.apply_torque_impulse(PD.clamp_len(tq, 1400.0 * balance * MS * S * hold) * dt)

	# ----- Head -----
	if not head.severed:
		var neck := (0.45 + 0.55 * conc_f if live else 0.18) * (0.22 if head.hanging else 1.0)
		var ly := 0.0
		var lp := 0.0
		if live and inp.has("look"):
			ly = float(inp.look.yaw) - yaw
			lp = float(inp.look.pitch) * 0.7
		elif live and gaze != null:
			var d: Vector3 = gaze - t_pos - Vector3(0, 0.6 * S, 0)
			ly = atan2(d.x, d.z) - yaw
			lp = atan2(d.y, Vector2(d.x, d.z).length())
		elif live:
			ly = 0.3 * sin(time * 0.37 + slot)
		ly = atan2(sin(ly), cos(ly))
		ly = clampf(ly, -1.1, 1.1)
		lp = clampf(lp, -0.4, 0.45)
		var look_q := Quaternion(UP, ly) * Quaternion(Vector3(1, 0, 0), -lp)
		pd_relative(head, torso, look_q, 20.0 * neck, 0.95, 90.0 * neck * MS * S, dt)

	# ----- Legs -----
	kick_timer = maxf(0.0, kick_timer - dt)
	if inp.get("kick", false) and kick_timer <= 0.0 and stamina > 12.0 and standing:
		kick_timer = 0.42
		stamina -= 12.0
	var move_amt: float = minf(1.0, h_speed / 2.5)
	var t_inv := t_rot.inverse()
	var move_dir := v_smooth.normalized() if v_smooth.length_squared() >= 0.04 else Vector3.ZERO
	for side in ["L", "R"]:
		var thigh: VoxelPart = by_name["thigh" + side]
		var shin: VoxelPart = by_name["shin" + side]
		if thigh.severed:
			continue
		var f := maxf(0.15, leg_func(side)) * (0.12 + 0.88 * e1 if rising else 1.0) if standing else 0.03
		var kicking = side == "R" and kick_timer > 0.0
		var l1 := 8 * V * S
		var l2 := 8 * V * S
		var hip := t_pos + t_rot * (thigh.pa)
		var thigh_q := Quaternion.IDENTITY
		var bend := 0.2
		if kicking:
			var chamber := kick_timer > 0.3
			thigh_q = Quaternion(Vector3(-1, 0, 0), 1.1 if chamber else 1.45)
			bend = 1.7 if chamber else 0.05
			if feet[side]:
				feet[side].swing = true
		elif standing and grounded:
			var neutral := t_pos + yaw_q * Vector3(thigh.pa.x * 1.15, 0, 0)
			neutral.y = _ground_under(neutral, ground_y)
			var ft = feet[side]
			if ft == null:
				ft = {"anchor": neutral, "from": neutral, "swing": false, "s": 0.0, "land": neutral, "half": -1, "slip": 0.0}
				feet[side] = ft
			var half := int(floor(gait_phase / PI))
			var my_swing = (half % 2 == 0) == (side == "L")
			var moving := h_speed > 0.25
			if hop_phase > 0.0:
				# Hopping: the good foot stays under him, leaves the sand at the top of each hop
				# and lands a little ahead; the stump does not step.
				ft.swing = false
				ft.anchor = neutral + move_dir * step_len * 0.25
				if leg_func(side) < 0.1:
					ft.anchor = (ft.anchor as Vector3) + Vector3(0, 0.25 * S, 0)
				ft.from = ft.anchor
				ft.land = ft.anchor
			elif moving and my_swing and not ft.swing and ft.half != half:
				ft.half = half
				ft.swing = true
				ft.from = ft.anchor
				ft.s = 0.0
			if ft.swing:
				ft.land = neutral + move_dir * step_len * 0.5
				var rate: float = h_speed / step_len if moving else 4.0
				ft.s = minf(1.0, ft.s + dt * rate)
				if ft.s >= 1.0 or (moving and not my_swing):
					ft.swing = false
					land_sag = maxf(land_sag, (0.06 + 0.03 * minf(1.0, h_speed / 3.0)) * S * clampf((leg_avg - 0.6) / 0.3, 0.0, 1.0))   # the weight comes onto the foot (hacked legs, already low on them, not at all: it sank a giant's feet in the sand)
					# Walking, it stays where it actually came down (short of the mark, it used to be
					# drawn on along the sand to it, and the planted foot skated). A step taken to
					# catch his balance still goes to its mark.
					var sole_at := shin.global_transform * Vector3(0, -4 * V * S, 0)
					ft.anchor = Vector3(sole_at.x, (ft.land as Vector3).y, sole_at.z) if moving and wants_move and not shin.severed and sole_at.distance_to(ft.land) < 0.35 * S else ft.land
					# Kept off its mark (a heap under him it came down on, a body in the way), it
					# stands where it came down: held to a mark it could not reach, it read as
					# slipping at once and stepped again and again, never down.
					if not (moving and wants_move) and not shin.severed and Vector2(sole_at.x - ft.land.x, sole_at.z - ft.land.z).length() > 0.12 * S:
						ft.anchor = Vector3(sole_at.x, clampf(sole_at.y, (ft.land as Vector3).y, (ft.land as Vector3).y + 0.6 * S), sole_at.z)   # (on the sand, never under it)
					ft.slip = 0.0
			elif ft.slip > ((0.5 if sprint else 0.3) if moving else 0.18) * S:
				ft.swing = true
				ft.from = ft.anchor
				ft.s = 0.0
				ft.half = half
				ft.land = neutral + Vector3(v_smooth.x, 0, v_smooth.z).normalized() * 0.25 * S
			elif not moving and (ft.anchor as Vector3).distance_to(neutral) > 0.3 * S:
				ft.swing = true
				ft.from = ft.anchor
				ft.s = 0.0
				ft.land = neutral
			var ease: float = ft.s * ft.s * (3.0 - 2.0 * ft.s)
			var target: Vector3 = (ft.from as Vector3).lerp(ft.land, ease) + Vector3(0, sin(PI * ft.s) * (0.08 + 0.06 * move_amt) * S, 0) if ft.swing else ft.anchor
			if hop_phase > 0.0 and hop_k > 0.6:
				target.y += (hop_k - 0.6) * 0.2 * S   # the foot tucks up at the top of the hop
			var hf := t_inv * (target - hip)
			var d := hf.length()
			var max_d := (l1 + l2) * 0.985
			if d > max_d:
				hf *= max_d / d
				d = max_d
			if d < 0.05:
				hf = Vector3(0, -0.05, 0)
				d = 0.05
			var dirv := hf / d
			var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
			bend = PI - acos(clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0))
			var axis := dirv.cross(Vector3(0, 0, 1))
			axis = Vector3(-1, 0, 0) if axis.length_squared() < 1e-6 else axis.normalized()
			thigh_q = Quaternion(Vector3(0, -1, 0), dirv.rotated(axis, a))
		else:
			bend = 0.9 if state == "down" and live else 0.2
			if feet[side]:
				feet[side].swing = true
		if rising:
			var k := PD.smooth(0.3, 0.9, rise_t)
			thigh_q = Quaternion(Vector3(1, 0, 0), -0.75).slerp(thigh_q, k)
			bend = 1.6 * (1.0 - k) + bend * k
		var snap: bool = kicking
		# A foot down holds the sand (friction): it stays where it was put while the body goes
		# over it, instead of skating along under it.
		if standing and grounded and not kicking and feet[side] and not feet[side].swing and not shin.severed and not shin.hanging and not rising:
			var sole := shin.global_transform * Vector3(0, -4 * V * S, 0)
			var goal: Vector3 = feet[side].anchor
			var sv := shin.velocity_at(sole)
			# Held and braked no harder than the sole itself answers to: pushed at the sole the
			# shin turns about it, much lighter than the leg it stands for, and braked as the
			# whole leg it overshot every step and the legs buzzed while he stood still.
			var r_s: Vector3 = sole - shin.global_position
			var m_sole := 1.0 / (1.0 / maxf(0.05, shin.mass) + r_s.length_squared() / PD.inertia_of(shin))
			var m_leg := shin.nominal_mass + thigh.nominal_mass * 0.5
			var k_hold := minf(FOOT_HOLD * m_leg, 0.25 * m_sole / (dt * dt))
			var c_hold := minf(60.0 * m_leg, 0.8 * m_sole / dt)
			var fh := Vector3((goal.x - sole.x) * k_hold - sv.x * c_hold, minf(0.0, (goal.y - sole.y) * k_hold - sv.y * c_hold), (goal.z - sole.z) * k_hold - sv.z * c_hold)
			fh = PD.clamp_len(fh, 260.0 * f * MS * S)
			shin.apply_impulse(fh * dt, sole - shin.global_position)
		motor_rel(thigh, torso, thigh_q, LEG_WN * sqrt(f), (1400.0 if snap else 900.0) * f * MS * S, dt, LEG_REACT)
		if not shin.severed and not shin.hanging:
			motor_rel(shin, thigh, Quaternion(Vector3(1, 0, 0), bend), LEG_WN * sqrt(f), (700.0 if snap else 600.0) * f * MS * S, dt)
		# The sand is under the sole, standing as lying: the legs pass through the ground while
		# he stands (the spring holds him), and a weak leg's step dragged its foot along under
		# the sand (a cyclops with hacked shins stood knee-deep, user). Pushed up only, never
		# along, so it does not catch.
		if standing and (grounded or (rising and hit)) and not shin.severed:
			var sole_f := shin.global_transform * Vector3(0, -4 * V * S, 0)
			var pen := ground_y - sole_f.y
			if pen > 0.005 * S:
				var r_f: Vector3 = sole_f - shin.global_position
				var m_f := 1.0 / (1.0 / maxf(0.05, shin.mass) + r_f.length_squared() / PD.inertia_of(shin))
				var vy_f := shin.velocity_at(sole_f).y
				var jy := m_f * (minf(pen, 0.2 * S) * 0.3 / dt - minf(0.0, vy_f) * 0.8)
				shin.apply_impulse(Vector3(0, maxf(0.0, jy), 0), r_f)

	# ----- Arms and weapons -----
	var power: bool = inp.get("power", false) and stamina > 3.0
	if power:
		stamina_use += 3.0 * dt
	two_front = null
	two_gap = null
	for side in ["R", "L"]:
		_drive_arm(side, inp, live and not limp, power, stam_f, blood_f, t_pos, t_rot, yaw_q, dt)
		# The breath goes with the work of the swing while the button is down: how far the hand
		# is sent across the pane and how sharply it is turned, more with a heavy weapon in it.
		# Held still it costs little; whirled hard it winds him fast.
		if power and live and not limp:
			var hp_now: Dictionary = hand_input[side]
			var hpv := Vector2(float(hp_now.get("x", 0.0)) - float(hp_prev[side].x), float(hp_now.get("y", 0.0)) - float(hp_prev[side].y)) / dt
			var hpa: Vector2 = (hpv - hp_vel[side]) / dt
			hp_vel[side] = hpv
			hp_prev[side] = Vector2(float(hp_now.get("x", 0.0)), float(hp_now.get("y", 0.0)))
			var wm: float = weapons[side].mass if weapons[side] else 0.5
			stamina_use += (0.9 * minf(12.0, hpv.length()) + 0.03 * minf(120.0, hpa.length())) * (0.7 + 0.12 * minf(8.0, wm)) * dt
		else:
			hp_vel[side] = Vector2.ZERO
			var hp_now2: Dictionary = hand_input[side]
			hp_prev[side] = Vector2(float(hp_now2.get("x", 0.0)), float(hp_now2.get("y", 0.0)))
		# Whatever the arm is doing (swinging, limp, hanging by a strip, on a corpse), it never
		# passes into its own chest or head.
		if not arm[side].upper.severed:
			_keep_arm_out(side, dt)

	# A blade whirled hard winds him: the swing's own speed, the weapon turning against his
	# body while he swings (the button down). Not the turn of the whole man (walking about and
	# looking round with the mouse carried the sword round with him and cost breath as if every
	# turn of the head were a cut), and not a weapon bouncing in a hand at rest.
	var sw: Weapon = weapons.R
	if sw and not sw.is_shield and power:
		# Only the turn that carries the tip through the air: the blade turned about its own
		# length (the wheel setting the edge) moves the tip a finger's breadth, not its reach.
		var rel_w: Vector3 = sw.angular_velocity - torso.angular_velocity
		var haft: Vector3 = PD.quat_of(sw) * Vector3.UP
		var tip := (rel_w - haft * rel_w.dot(haft)).length() * sw.reach
		stamina_use += 0.6 * maxf(0.0, tip - 3.0) * (0.6 + 0.25 * minf(6.0, sw.mass)) * dt
	# Armour is carried: every exertion (sprinting, swinging, the struggle) costs more breath
	# the more he has on.
	stamina_use *= float(Armory.burden(carried_kg()).breath)
	# A giant's lungs and muscle go with his size: the same swing of a weapon scaled to him
	# costs him no more breath than a man's costs the man.
	if S > 1.2:
		stamina_use /= maxf(1.0, pow(S, 1.5) * float(mods.get("strength", 1.0)))
	var still := Vector2(v_smooth.x, v_smooth.z).length() < 0.4
	var regen := 3.0 if stamina_use > 0.02 * dt * 60.0 else (18.0 if still else 9.0)
	# A chest cut open or stove in: he gets his breath back slowly.
	regen *= (0.35 + 0.65 * torso.function()) * float(mods.get("wind", 1.0))   # (wind: the trainer's)
	# Torn lungs draw breath slower and fill no further than they still can.
	stamina = clampf(stamina - stamina_use + regen * heavy * (0.35 + 0.65 * lungs()) * dt, 0.0, maxf(stamina - stamina_use, breath_cap()))

## Every joint drawn whole (drawing only): a block of the limb's own thickness and colour sits
## on the joint's pivot, hidden inside the two parts while the limb is straight, and filling
## the wedge their blocks open between them when it bends, so no arm, leg or head is seen to
## float off the body. At the shoulder it is the deltoid: turned with the arm and run on from
## the arm's top into the chest as far as the arm's line meets it (the socket sits an arm's
## width out from the chest, and a raised arm pivots there, its top a hand off the chest); the
## others turn with the part the limb hangs from.
var joint_caps := {}
func _process(_dt: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_seat_drawing()
	_draw_joint_caps()
	_sway_hair(_dt)

## Drawn where the bodies are now, with the game paused (the kill cam): the joints closed and
## capped off the bodies' own transforms, not the interpolation's.
func draw_now() -> void:
	_seat_drawing(false)
	_draw_joint_caps(false)

## What the physics leaves open of a joint (a few millimetres under load, a couple of
## centimetres in a hard blow) is closed on screen: each joined part is drawn moved so that
## its anchor meets its parent's where the parent is drawn, parents before children, and the
## weapon in a hand is drawn moved with the forearm. The bodies are not touched (setting them
## back on their joints before each step, or more solver iterations, cost the arms their
## precision with a heavy head); a part cut off, hanging or gone is drawn where it is.
func _seat_drawing(interp := true) -> void:
	for p: VoxelPart in parts:
		var par: VoxelPart = p.parent_part
		p.draw_shift = Vector3.ZERO
		if par == null or p.severed or p.hanging or p.missing or par.severed or p.joint == null:
			continue
		var tp := par.get_global_transform_interpolated() if interp else par.global_transform
		var tc := p.get_global_transform_interpolated() if interp else p.global_transform
		p.draw_shift = tp * p.pa + par.draw_shift - tc * p.ca
	for side in ["R", "L"]:
		var w: Weapon = weapons[side]
		if w == null:
			continue
		var fore: VoxelPart = arm[side].fore
		var shift: Vector3 = fore.draw_shift if not two_handed or side == "R" else arm.R.fore.draw_shift
		for b in w.bodies():
			if b is Weapon:
				b.draw_shift = shift

func _draw_joint_caps(interp := true) -> void:
	for p: VoxelPart in parts:
		var par: VoxelPart = p.parent_part
		var cap: MeshInstance3D = joint_caps.get(p)
		var show := par != null and p.joint != null and not p.severed and not p.hanging and not p.missing and not par.severed and not par.missing and p.prosthetic == "" and p.alive_count > 0
		if not show:
			if cap:
				cap.visible = false
			continue
		if cap == null:
			cap = MeshInstance3D.new()
			cap.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			cap.mesh = BoxMesh.new()
			var mat := StandardMaterial3D.new()
			mat.albedo_color = _body_color(p).srgb_to_linear()   # (the voxels' colours are sRGB)
			mat.roughness = 0.9
			cap.material_override = mat
			add_child(cap)
			joint_caps[p] = cap
		cap.visible = true
		var tc := p.get_global_transform_interpolated() if interp else p.global_transform
		var tp := par.get_global_transform_interpolated() if interp else par.global_transform
		var pivot: Vector3 = tc * p.ca + p.draw_shift
		# Turned halfway between the two parts, a shade smaller than the limb: it fills the inner
		# part of the wedge and shows little past either block (turned with one of them, a
		# block the limb's full size stood out of the other: user screenshot).
		var hx := p.half_ext.x * 0.88
		var hz := p.half_ext.z * 0.88
		var b := Basis(tp.basis.get_rotation_quaternion().slerp(tc.basis.get_rotation_quaternion(), 0.5))
		var mid := pivot
		var hy := minf(hx, hz)
		if p == arm.R.upper or p == arm.L.upper:
			b = tc.basis.orthonormalized()
			# The deltoid: from a little inside the arm's top, on along the arm's line to just
			# inside the chest, where that line enters it. Where the line misses the chest (the
			# arm hanging, or raised up or back past the shoulder) the cap stays inside the arm.
			var tb := tp.basis.orthonormalized()
			var along: Vector3 = tb.inverse() * b.y
			var inward := -signf(p.pa.x)
			var run := 0.0
			if along.x * inward > 0.05:
				var t := (-inward * (par.half_ext.x - 0.03 * S) - p.pa.x) / along.x
				var at: Vector3 = p.pa + along * t
				if t > 0.0 and t < 0.2 * S and absf(at.y) < par.half_ext.y - 0.01 and absf(at.z) < par.half_ext.z - 0.01:
					run = t
			hx = p.half_ext.x * 0.96
			hz = p.half_ext.z * 0.96
			hy = (run + hx * 0.6) * 0.5
			mid = pivot + b.y * (run - hx * 0.6) * 0.5
		cap.global_transform = Transform3D(b.scaled_local(Vector3(hx, hy, hz)), mid)

## The colour most of a part is (its skin, or the cloth or leather over it), for its joint cap.
static func _body_color(p: VoxelPart) -> Color:
	var count := {}
	var best = null
	for i in p.colors.size():
		if i < p.alive.size() and p.alive[i] == 0:
			continue
		var k := p.colors[i].to_rgba32() & 0xF0F0F0F0
		count[k] = int(count.get(k, 0)) + 1
		if best == null or count[k] > count[best]:
			best = k
	return Color.hex(best) if best != null else Color(0.8, 0.6, 0.45)

func _drive_arm(side: String, inp: Dictionary, live: bool, power: bool, stam_f: float, blood_f: float, t_pos: Vector3, t_rot: Quaternion, yaw_q: Quaternion, dt: float) -> void:
	var a: Dictionary = arm[side]
	var upper: VoxelPart = a.upper
	var fore: VoxelPart = a.fore
	var e_was = elbow_prev[side]   # last step's elbow line, only while a weapon arm drives on
	elbow_prev[side] = null
	if upper.severed or fore.severed or upper.hanging or fore.hanging or not live:
		if not live and fore.has_meta("elbow_set"):
			_hold_elbow(side, 0.0, false, dt)
		# A stump is held in to the side, weakly: left to itself it flapped about with every
		# turn of the body.
		if live and fore.severed and not upper.severed and not upper.hanging:
			motor_rel(upper, torso, Quaternion.IDENTITY, 5.0, 25.0 * MS * S, dt, 0.5)
		return
	var af := arm_func(side)
	# The arm's function, again below, is the same this step (unless a frost on it is thawing:
	# that is read off the clock).
	var af_now := af if upper.frozen_until <= 0.0 and fore.frozen_until <= 0.0 else -1.0
	if fore.flinch_t > 0.0 or upper.flinch_t > 0.0:
		af *= 0.6
	# Caught by that arm: it cannot swing until it is wrenched free.
	if pinned_arm == side and is_instance_valid(grabbed_by):
		af *= 0.12
	if side == "L" and two_handed and not (off_goal != null and is_bow(weapons.R)):
		var hand_l := hand_world("L")
		var sh_l = t_pos + t_rot * shoulder.L
		# The off arm bends at an elbow as the main one does, the elbow out to its own side, down
		# and a little back of the line from shoulder to hand (never up over it nor in across the
		# chest), and the upper arm is rolled so the hinge bends toward the hand: pointed straight
		# at its hand with the roll left to drift, the elbow turned up over the shoulder and
		# jammed in a slow circle with a heavy haft, a chicken wing (user; a probe of circles,
		# eights and side-to-side with the zweihander and the warhammer).
		var to_h: Vector3 = hand_l - sh_l
		var dist_h := maxf(0.05, to_h.length())
		var line: Vector3 = to_h / dist_h
		if S >= 1.6:
			# A giant's off arm keeps the old drive, pointed at its hand with the upper arm pushed
			# down. Its bot sends both hands to a mark out of reach (a blow held over a small
			# man) and the arm goes straight; the drive below, and every variant of it measured
			# (its push down faded in as the arm straightens, the bot bringing the blow lower,
			# the roll weak, strong, kneed, reacted or gated), left it locked straight on 1-3
			# seeds of 8 with the hammer's head at the man's height half a metre short, and the
			# cyclops of the giants test never landed; pointed and pushed down it lands 8 of 8.
			pd_axis(upper, Vector3(0, -1, 0), (line + Vector3(0, -0.3, 0)).normalized(), 10.0, 0.8, 50.0 * af * MS * S, dt)
			pd_axis(fore, Vector3(0, -1, 0), line, 8.0, 0.8, 30.0 * af * MS * S, dt)
		else:
			var lu_l := UPPER_LEN * S
			var lf_l := FORE_LEN * S
			var cos_a := clampf((lu_l * lu_l + dist_h * dist_h - lf_l * lf_l) / (2.0 * lu_l * dist_h), -1.0, 1.0)
			var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
			var elbow_dir_l := Vector3.ZERO
			var elbow_l := Vector3.ZERO
			# Out, down and a little back; where that elbow would sit in the chest (the hand
			# across the body, the haft held in front), down and forward instead: an elbow aimed
			# into the chest was shoved up over the shoulder by it.
			for pref_l in [Vector3(0.5, -0.7, -0.4), Vector3(0.25, -0.65, 0.75)]:
				var pref: Vector3 = t_rot * (pref_l as Vector3).normalized()
				var perp: Vector3 = pref - line * pref.dot(line)
				if perp.length_squared() < 1e-4:
					perp = t_rot * Vector3(1, 0, 0)
				perp = perp.normalized()
				elbow_dir_l = _elbow_dir("L", t_rot.inverse() * (line * cos_a + perp * sin_a), lu_l, t_rot)
				elbow_l = sh_l + elbow_dir_l * lu_l
				var in_chest: Vector3 = t_rot.inverse() * (elbow_l - t_pos)
				var th_l: Vector3 = torso.half_ext
				if not (absf(in_chest.x) < th_l.x + 0.06 * S and absf(in_chest.y) < th_l.y + 0.02 * S and in_chest.z < th_l.z + 0.06 * S):
					break
			# Driven as hard as the main arm's (at a fifth of it the pull on the haft folded the
			# elbow up over the shoulder), firm while the hands move slowly or hold (a guard, a
			# slow circle: where the elbow stood up), giving way in a fast stroke, where the off
			# arm has to follow the haft and a firm one pulled the blade off the mouse.
			# Driven as hard as the main arm's (at a fifth of it the pull on the haft folded the elbow
			# up over the shoulder), firm while the hands move slowly or hold (a guard, a slow circle:
			# where the elbow stood up), giving way in a fast stroke, where the off arm has to follow
			# the haft and a firm one pulled the blade off the mouse. A giant's bot, whose hands go
			# to a mark out of reach in a blow held over a small man, brings the blow lower itself
			# while the hammer's head is above him (bot.gd): with this drive alone it held the arm
			# straight and the head at the man's height half a metre short, and never landed.
			var spd_l: float = (fore.velocity_at(hand_l) - torso.linear_velocity).length() / S
			var calm := clampf(1.3 - spd_l / 3.0, 0.3, 1.0)
			# As the arm straightens the routed elbow comes onto the line to the hand and the drive
			# has nothing left to bend the arm with; the old push down on the upper arm comes in
			# then (none at a bend of 24 degrees or more, all at straight). A giant's off arm
			# stretched to a mark out of reach (a blow held over a small man) stayed locked straight
			# without it, the hammer's head at the man's height half a metre short, and the cyclops
			# of the giants test never landed; pushed down, the arm bends, the haft tilts and the
			# head comes down on him, as it did before the routing.
			var straight := clampf(1.0 - sin_a / 0.4, 0.0, 1.0)
			pd_axis(upper, Vector3(0, -1, 0), (elbow_dir_l + Vector3(0, -0.3, 0) * straight).normalized(), 12.0, 0.9, 120.0 * calm * af * MS * S, dt)
			var fore_dir_l: Vector3 = (hand_l - elbow_l).normalized()
			pd_axis(fore, Vector3(0, -1, 0), fore_dir_l, 10.0, 0.8, 50.0 * calm * af * MS * S, dt)
			# The elbow is a hinge that bends the forearm toward the upper arm's front: the upper
			# arm is rolled so that its front is the way the forearm has to bend to reach the
			# hand, else the hinge's plane is wherever the roll drifted and the elbow ends up over
			# the shoulder or in the chest however the two bones are pointed.
			_twist_to(upper, fore_dir_l, 14.0 * MS, 1.4 * MS, 90.0 * calm * MS, dt)
		# It bears its own weight and its half of the weapon's (the other arm held it all up, and a
		# raised blade sank and crept while the mouse stood still).
		var m_arm := (fore.nominal_mass + upper.nominal_mass * 0.5)
		var m_bear: float = m_arm + (weapons.R.mass * 0.5 if weapons.R and two_front != null else 0.0)
		fore.apply_impulse(Vector3(0, m_bear * gravity * minf(1.0, af * 1.2) * dt, 0), hand_l - fore.global_position)
		if not on_ground:
			torso.apply_central_impulse(Vector3(0, -m_bear * gravity * minf(1.0, af * 1.2) * dt, 0))
		# The off hand works too: it carries its end of the haft to where the swing wants it (the
		# front hand's place), as hard as an arm can, instead of hanging on as dead weight for the
		# other arm to haul round (the blade lagged a stroke behind the mouse and drifted).
		if two_front != null and weapons.R:
			var vel_l := fore.velocity_at(hand_l) - torso.linear_velocity
			var m_l: float = m_arm + weapons.R.mass * 0.5
			var wn_l := 22.0
			var J_l := PD.clamp_len((((two_front as Vector3) - hand_l) * wn_l * wn_l - vel_l * 2.0 * 0.9 * wn_l) * m_l * dt, 700.0 * af * stam_f * blood_f * MS * dt)
			fore.apply_impulse(J_l, hand_l - fore.global_position)
			torso.apply_central_impulse(-J_l * (0.5 if on_ground else 1.0))
		return
	var w: Weapon = weapons[side]
	power_now = power
	var strength := af * stam_f * blood_f * (1.45 if power else 1.0) * (1.6 if two_handed else 1.0) * (1.0 if state == "stand" else 0.3) * (1.35 if enraged else 1.0)
	# A thrust is made with the whole body: the arm drives harder along the line and the body
	# lunges after the point (held out at arm's length and no more, the point only pricked).
	var th_in: float = float(inp.get("thrust", 0.0) if side == "R" else inp.get("offThrust", 0.0))
	if th_in > 0.3 and state == "stand" and w and not w.is_shield and not w.design.has("shoots") and shove_t <= 0.0:
		strength *= 1.0 + 0.6 * clampf(th_in, 0.0, 1.0)
	var hp: Dictionary = inp.get("main" if side == "R" else "off", {"x": 0.1 if side == "R" else -0.35, "y": 0.1})
	if not w and inp.get("jabR" if side == "R" else "jabL", false) and jab_t[side] <= 0.0 and state == "stand" and stamina > 4.0:
		jab_t[side] = JAB_TIME
		stamina -= 5.0
	jab_t[side] = maxf(0.0, jab_t[side] - dt)
	var jk: float = 1.0 - jab_t[side] / JAB_TIME if jab_t[side] > 0.0 else -1.0
	var jab = null
	if jk >= 0.0:
		jab = -0.9 * jk / 0.12 if jk < 0.12 else (1.8 if jk < 0.6 else 1.8 * (1.0 - (jk - 0.6) / 0.4))
	var thrust: float = 1.0 if shove_t > 0.0 else (jab if jab != null else float(inp.get("thrust", 0.0) if side == "R" else inp.get("offThrust", 0.0)))
	# A fist is thrown with a straight arm (character.js lockElbowOf): an empty hand with its
	# button held, or a jab, locks the elbow rigid, so the forearm goes where the upper arm
	# drives it and the punch lands with the whole arm behind it.
	_lock_elbow_straight(side, not w and state == "stand" and (power or jab_t[side] > 0.0) and af > 0.25 and held_item == null and not crawling)
	if not (w and not w.is_shield and weapon_joints[side]):
		_hold_elbow(side, 0.0, false, dt)
	var down_hp = {"x": 0.4 if side == "R" else -0.4, "y": -0.5} if state != "stand" else ({"x": 0.25 if side == "R" else -0.25, "y": 0.35} if shove_t > 0.0 else null)
	if crawling:
		# The arms reach ahead and haul, one after the other.
		down_hp = {"x": 0.35 if side == "R" else -0.35, "y": 0.55 + 0.45 * sin(crawl_phase + (0.0 if side == "R" else PI))}
		thrust = 0.5
	# Throwing: drawn back high behind the shoulder while F is held (further the longer it is
	# held) or a bot winds up, then whipped forward and across in the follow-through.
	var t_side := item_hand() if held_item != null else ("R" if weapons.R and not weapons.R.is_shield else "L")
	if held_item == null and inp.get("throwOther", false) and weapons["L" if t_side == "R" else "R"]:
		t_side = "L" if t_side == "R" else "R"
	var ta = throw_anim
	var charging := float(inp.get("charging", 0.0))
	var winding: bool = (ta != null and ta.side == side and ta.phase == "wind") or (ta == null and side == t_side and charging > 0.0 and (state == "stand" or state == "down"))
	var following: bool = ta != null and ta.side == side and ta.phase == "follow"
	throwing[side] = winding or following
	# Down but awake, a man still throws and shoots from where he lies: the arm comes up off the
	# sand for it (it stayed on the sand, and the pot or the arrow left from there into the
	# ground), with less behind it than on his feet.
	if state == "down" and down_hp != null and (winding or following or (side == "R" and w and w.design.has("shoots"))):
		down_hp = null
		thrust = 0.0
		strength *= 2.0
	# A throw is made with one hand: the off hand lets go of the haft as the arm draws back.
	if (winding or following) and side == "R" and two_handed and held_item == null:
		if weapon_joints.L:
			weapon_joints.L.queue_free()
			weapon_joints.L = null
		two_handed = false
	# Winding up a throw and letting it go, the hand closes hard on the weapon: it is held
	# firm and drawn back with the arm instead of wobbling in the fist.
	if winding or following:
		strength *= 1.8
	thrust_amt[side] = clampf(thrust, 0.0, 1.5) if down_hp == null else 0.0
	var spear: bool = w != null and w.point_first() and held_item == null
	throw_pose[side] = spear and down_hp == null and (winding or following)
	if down_hp == null and (winding or following):
		if spear:
			# A spear: drawn back level above the shoulder, point at the mark, then driven
			# straight forward and a little down along the line it will fly.
			down_hp = {"x": (0.45 if side == "R" else -0.45), "y": 1.05} if winding else {"x": (-0.15 if side == "R" else 0.15), "y": 0.55}
			thrust = -1.3 * maxf(0.5, charging if ta == null else 1.0 - ta.t / 0.45) if winding else 1.4
		else:
			down_hp = {"x": (0.55 if side == "R" else -0.55), "y": 1.5} if winding else {"x": (-0.7 if side == "R" else 0.7), "y": -0.25}
			thrust = -1.5 * maxf(0.5, charging if ta == null else 1.0 - ta.t / 0.45) if winding else 1.3
	# The other arm keeps clear of a throw: out to the side and down as a counterweight, not
	# reaching along the haft (it looked as if both hands threw it).
	var other := "L" if side == "R" else "R"
	if down_hp == null and not weapons[side] and held_item == null and (throwing[other] or (ta != null and ta.side == other)):
		down_hp = {"x": (0.9 if side == "R" else -0.9), "y": -0.35}
		thrust = 0.0
	var hp_used: Dictionary = down_hp if down_hp != null else hp
	# A bow is held out at the shoulder, stave upright, whatever the mouse does.
	if down_hp == null and side == "R" and w and w.design.has("shoots"):
		var ap := _shoot_pitch(inp)
		hp_used = {"x": 0.3 if is_bow(w) else 0.15, "y": clampf((0.45 if is_bow(w) else 0.38) + ap * 0.9, -0.4, 1.4)}
		thrust = 0.6 if is_bow(w) else 0.3
	hand_input[side] = hp_used
	# A thrust with a blade (the button, not the little reach a stroke is given) is driven along
	# the blade's own line (see below): the hand's mark is where it was, not pushed out ahead.
	var line_on: bool = th_in > 0.5 and w != null and not w.is_shield and not w.design.has("shoots") and down_hp == null and held_item == null and shove_t <= 0.0
	var target := hand_target_local(side, hp_used, 0.0 if line_on else thrust)
	# Reaching for the haft (H pressed with its end behind him): to the grip, or to the nearest
	# place in front of the body while the grip is behind it.
	if side == "L" and grip_wait > 0.0 and weapons.R and not two_handed:
		var at_g: Vector3 = weapons.R.global_transform * weapons.R.grip_off
		target = yaw_q.inverse() * (at_g + _out_front(at_g) - t_pos)
	# Reaching for a weapon (G): to its grip, wherever it lies; with it in the fist, back up from
	# there to the guard, not in one leap.
	var rch = reach[side]
	if rch != null and is_instance_valid(rch.w):
		if rch.phase == "reach":
			target = yaw_q.inverse() * ((rch.w as Weapon).grip_world() - t_pos)
		elif rch.phase == "draw":
			# Held still while the fingers draw it in; to it, if it is stuck fast and will not come.
			target = yaw_q.inverse() * ((rch.w as Weapon).grip_world() - t_pos) if rch.w.stuck != null else rch.hold
		elif rch.get("from") is Vector3:
			var k := float(rch.get("lift", 1.0))
			target = (rch.from as Vector3).lerp(target, k * k * (3.0 - 2.0 * k))
	# A hurt arm sags, more the worse it is; it does not wander. A player's blade stays where he
	# last aimed it: a hurt arm, a ringing head or wine had the hand going round in circles on
	# its own, the weapon with it, with nothing touched (user: the most important of all). Their
	# harm is in the arm's strength and speed, the stagger and the blurred eyes. A bot's ringing
	# head still has its blows go wide (the giants' were brought down onto a man by it).
	var arm_hurt := 1.0 - minf(1.0, (af_now if af_now >= 0.0 else arm_func(side)) / 0.85)
	target.y -= maxf(0.0, arm_hurt - 0.1) * 0.08 * S
	if concussion > 0.1 and not player:
		target.x += sin(time * 3.1 + slot) * concussion * 0.25
		target.y += cos(time * 2.3) * concussion * 0.2
	# A free hand caught behind the back (let go of the haft at the far hip, knocked round) lay
	# wedged between the back, the buttock and the thigh, which it knocks against, and stayed
	# there whatever pushed it (user: never behind the back): after a moment it passes through
	# them, straight to its mark in front, and is solid again once out in front.
	_unwedge(side, dt, yaw_q, t_pos)
	target = _clear_body(target, yaw_q, t_pos)
	var target_w := t_pos + yaw_q * target
	# A thrust is a straight stab along the blade, wherever it points: the line the blade is on
	# when the button goes down (in the body's frame, so it turns with him) is kept, the hand is
	# drawn back along it a little and then driven out along it, hard and fast, to the end of
	# the arm. The blade stays on that line the whole way: the point goes where it points.
	thrust_aim[side] = null
	thrust_ext[side] = 0.0
	if not line_on:
		thrust_line[side] = null
	else:
		var tl = thrust_line[side]
		if tl == null:
			# The line the blade really lies on, and the hand where it really is.
			var d0: Vector3 = yaw_q.inverse() * (PD.quat_of(w) * Vector3.UP)
			d0.z = maxf(d0.z, 0.2)
			tl = {"o": yaw_q.inverse() * (hand_world(side) - t_pos), "dir": d0.normalized(), "t": 0.0}
			thrust_line[side] = tl
		tl.t += dt
		var ext := _thrust_ext(tl, tl.o, shoulder[side])
		thrust_ext[side] = ext
		# The body leans into a level stab; a stab up or down is the arm's (leaning, the shoulder
		# would carry the point off its line).
		thrust_lean = maxf(thrust_lean, clampf((float(tl.t) - THRUST_DRAW) / THRUST_DRIVE, 0.0, 1.0) * clampf(1.0 - 1.5 * absf((tl.dir as Vector3).y), 0.0, 1.0))
		target_w = t_pos + yaw_q * ((tl.o as Vector3) + (tl.dir as Vector3) * ext)
		# Held on the line against the sag of its own weight: asked as far past it as it hangs off.
		var dw: Vector3 = yaw_q * (tl.dir as Vector3)
		var now := PD.quat_of(w) * Vector3.UP
		thrust_aim[side] = {"dir": (dw + (dw - now).limit_length(0.4)).normalized(), "k": 1.0}
	# The off hand at work on a bow or a crossbow: on the string, wherever that is.
	if side == "L" and off_goal != null and not w and down_hp == null:
		target_w = off_goal
	# The hand moves like an arm: limited speed and acceleration toward the mouse's mark.
	var lead = hand_lead[side]
	if lead != null and (lead as Vector3).distance_to(target_w) < 2.5 * S:
		var h: float = handling[side]
		# Winded, the arm is slow as well as weak: the hand gets to its mark at half the pace.
		var wind := 0.35 + 0.65 * minf(1.0, stamina / 60.0)
		var vmax := 15.0 * S * (long_k(w) if not line_on and thrust <= 0.3 else 1.0) * (2.0 if jab_t[side] > 0.0 else (3.0 if line_on else (2.2 if thrust > 0.3 else 1.0))) * (0.55 + 0.45 * h) * (0.5 + 0.5 * minf(1.0, (af_now if af_now >= 0.0 else arm_func(side)) / 0.85)) * wind
		var amax := 140.0 * S * (0.4 + 0.6 * h) * (1.3 if power else 1.0) * (4.0 if jab_t[side] > 0.0 else (6.0 if line_on else (3.0 if thrust > 0.3 else 1.0))) * (0.5 + 0.5 * wind)
		var to_t: Vector3 = target_w - lead
		var dist := to_t.length()
		var v_des := to_t * (minf(minf(vmax, sqrt(2.0 * amax * dist)), dist / dt) / dist) if dist > 1e-5 else Vector3.ZERO
		var acc := PD.clamp_len((v_des - lead_vel[side]) / dt, amax)
		lead_vel[side] += acc * dt
		lead = lead + lead_vel[side] * dt
		hand_lead[side] = lead
		target_w = lead
	else:
		hand_lead[side] = target_w
		lead_vel[side] = Vector3.ZERO
	target_vel[side] = (target_w - prev_target[side]) / dt
	if target_vel[side].length_squared() > 2500.0:
		target_vel[side] = Vector3.ZERO
	prev_target[side] = target_w

	var hand_w := hand_world(side)
	var hand_vel := fore.velocity_at(hand_w)
	var in_fist: Weapon = reach[side].w if reach[side] != null and reach[side].phase == "fist" and is_instance_valid(reach[side].w) else null
	var m_eff := (fore.nominal_mass + upper.nominal_mass * 0.5) + (w.mass if w else (in_fist.mass if in_fist else 0.0))
	var load := (w.mass * 0.22 + float(w.stats.get("inertia", 0.0)) * 0.9) / (float(mods.strength) * sqrt(S) * (1.7 if two_handed else 1.0)) if w else 0.0
	var hnd := 1.0 / (1.0 + load)
	if fixed_hand[side]:
		hnd *= 0.6   # no wrist, no fingers: the blade goes where the stump drags it
	handling[side] = hnd
	var hand_goal := target_w
	var shoulder_w = t_pos + t_rot * shoulder[side]
	var dir = (target_w - shoulder_w).normalized()
	if w and not w.is_shield and weapon_joints[side]:
		var q_was = aim_q[side]
		var w_aim := weapon_aim(side, w, target_w, t_pos, yaw_q, inp, dt)
		# The arm is damped toward the turn the mouse asks for, not toward standing still: damped
		# to rest it trailed a fast stroke by a tenth of a second and ran out of drive near the end.
		var w_ff: Vector3 = PD.clamp_len(PD.rot_error(w_aim, q_was) / dt, 30.0) if q_was != null else Vector3.ZERO
		aim_w[side] = (aim_w[side] as Vector3).lerp(w_ff, 0.5)
		if side == "R" and two_handed and weapon_joints.L and not throw_pose[side]:
			# Both hands on one haft: the front hand is the pivot. It sits ahead of its own
			# shoulder (lower for a low guard or a blow at a man on the sand, aside with the
			# sweep), the back hand behind it down the shaft, and a thrust drives both along it.
			# So the off hand is never stretched across the body, and the head goes wherever the
			# mouse sends it, up, down or round.
			# Both hands go where the mouse sends them, as one hand does: the main hand to the
			# mark one hand is given (hand_target_local: the same reach every way), the front
			# hand ahead of it down the haft. Where an arm cannot reach its grip (the front hand
			# high across the face or far out past the other shoulder) the pair is moved in
			# toward the shoulders, the blade's line kept. (Held at a guard in front of the face
			# with only the blade turning, the hands never left the brow, the blade stood up over
			# the head and the arms looked tangled, while one hand swung wide: user video.)
			var gap: Vector3 = w_aim * (w.grip_off - w.grip_main)
			var front: Vector3 = target_w + gap
			# Where the back hand's end of the haft would be behind his back, the haft is turned
			# about the front hand to bring it round in front (and what that leaves, below, moves
			# the pair forward): the hand follows the haft, so the haft is what has to stay out.
			var turn_fix := _out_front(front)
			if turn_fix != Vector3.ZERO and gap.length() > 1e-4:
				var g2: Vector3 = (gap + turn_fix).normalized()
				if g2.dot(gap.normalized()) > -0.99:
					w_aim = (Quaternion(gap.normalized(), g2) * w_aim).normalized()
					gap = w_aim * (w.grip_off - w.grip_main)
					front = target_w + gap
			var tl2 = thrust_line[side]
			if tl2 != null:
				# A thrust drives the front hand along the blade's line, as far as that arm reaches.
				# From where the front hand really is (the guard's mark was off it, and the stab
				# began with a jump off its own line).
				if not tl2.has("f"):
					tl2.f = yaw_q.inverse() * (hand_world("L") - t_pos)
				front = t_pos + yaw_q * ((tl2.f as Vector3) + (tl2.dir as Vector3) * _thrust_ext(tl2, tl2.o, shoulder[side], (tl2.f as Vector3).z))
				target_w = front - gap
			var sh_r: Vector3 = t_pos + t_rot * shoulder.R
			var sh_l: Vector3 = t_pos + t_rot * shoulder.L
			# (Not in a thrust: that goes out to the full reach of the arm along its line.)
			if tl2 == null:
				for _pass in 2:
					var far_l := front.distance_to(sh_l) - arm_reach * 0.9
					if far_l > 0.0:
						var pull_l: Vector3 = (sh_l - front).normalized() * far_l
						front += pull_l
						target_w += pull_l
					var far_r := target_w.distance_to(sh_r) - arm_reach * 0.9
					if far_r > 0.0:
						var pull_r: Vector3 = (sh_r - target_w).normalized() * far_r
						front += pull_r
						target_w += pull_r
			# The off hand never takes the haft behind his back (user: pressing H with the spear
			# up across to the left, the butt was behind him and the hand went round to it): the
			# pair is carried forward, the blade's line kept, until the back hand's end is out in
			# front of the chest (or, beside the body, no further back than its middle).
			var fwd_fix := _out_front(front)
			front += fwd_fix
			target_w += fwd_fix
			two_front = front
			two_main = target_w
			two_gap = front - target_w if tl2 == null else null   # (a thrust drives the front hand along its line)
		var fore_q := w_aim * grip_q(w).inverse()
		var fore_dir := fore_q * Vector3(0, -1, 0)
		var lu := UPPER_LEN * S
		var lf := FORE_LEN * S
		var side_sign := -1.0 if side == "R" else 1.0
		var e_local = t_rot.inverse() * (target_w - fore_dir * lf - shoulder_w)
		if e_local.length_squared() < 1e-6:
			e_local = Vector3(side_sign * 0.3, -1, -0.3)
		e_local = e_local.normalized().lerp(Vector3(side_sign * 0.5, -0.7, -0.5).normalized(), 0.06 if two_handed else 0.18).normalized()
		# The elbow never folds in through the chest: in the body's frame it stays on its own
		# side of the shoulder (at most 0.22 S across the shoulder line) and at most 0.28 S above it.
		var elbow_dir = _route_front(PD.quat_of(upper) * Vector3(0, -1, 0), _elbow_dir(side, e_local, lu, t_rot), t_rot)
		var elbow = shoulder_w + elbow_dir * lu
		hand_goal = elbow + fore_dir * lf
		if side == "R" and two_gap != null:
			# The off hand's place is taken off where the main arm is really driven (its elbow and
			# forearm as the blade's line has them), not off the mouse's mark: the arm cannot always
			# put its hand on the mark, and the off hand sent to the mark's end of the haft pulled
			# it the other way. The two hands fought over the haft: a longsword in both stopped at
			# 30 degrees of the 86 asked out to the side, its side stroke little more than half as
			# long as in one hand.
			two_front = hand_goal + (two_gap as Vector3)
			two_front += _out_front(two_front)
		var m_load := (fore.nominal_mass + w.mass) * lu * lu
		var k_up := 1.0 + m_load / PD.inertia_of(upper)
		var up_ff: Vector3 = PD.clamp_len((e_was as Vector3).cross(elbow_dir) / dt, 25.0) if e_was != null else Vector3.ZERO
		elbow_prev[side] = elbow_dir
		pd_axis(upper, Vector3(0, -1, 0), elbow_dir, 16.0, 1.0, 260.0 * af * MS * S, dt, minf(5.0 if two_handed else 12.0, k_up), up_ff)
		# The upper arm does not roll on its own length under a swing: the elbow keeps pointing
		# down and out, the hinge where it belongs.
		pd_twist(upper, torso, 4.0 * MS, 0.6 * MS, 25.0 * MS, dt)
		# A swing locks the elbow: the whole time the swing button is held, and through any fast
		# stroke of the hand (button or not) and a moment after it, so the weight of the head
		# (a warhammer most) is carried round on the straight arm from the shoulder instead of
		# folding the elbow and stopping dead in mid-flight. Not in a thrust: the arm has to
		# straighten along the line.
		# A fast stroke with both hands on the haft is the mouse's, read off the pane: read off the
		# hand's mark, a still mouse set it going again and again and the arm pumped in and out.
		var hp_now: Dictionary = hand_input[side]
		var hp_was = pane_prev[side]
		pane_prev[side] = hp_now
		var in_spd := Vector2(float(hp_now.get("x", 0.0)) - float(hp_was.get("x", 0.0)), float(hp_now.get("y", 0.0)) - float(hp_was.get("y", 0.0))).length() / dt if hp_was is Dictionary else 0.0
		# (Two hands only: there the hand's mark goes round with the body and the other hand, and
		# the arm's own set pumping it kept the set on; one hand reads its mark as before.)
		if (in_spd > 2.4) if two_handed else (target_vel[side].length() > 1.2 * S):
			swing_hold[side] = 0.35
		else:
			swing_hold[side] = maxf(0.0, swing_hold[side] - dt)
		# A high mark held still with the button down is a high guard, and a high guard's elbows
		# bend: kept near straight, the blade could not be stood up and hung 40 degrees off the
		# mouse. (Out to the side and below the arms are near straight anyway, and the set elbow
		# is what holds a long blade out there.)
		var moving: bool = in_spd > HELD_STILL if two_handed else target_vel[side].length() > 0.3 * S
		var high_guard: bool = not moving and float(hp_now.get("y", 0.0)) > 0.6
		var swinging: bool = ((power and not high_guard) or swing_hold[side] > 0.0) and state == "stand" and thrust < 0.05 and w.design.get("chain") == null and not w.design.has("shoots")
		# A swing is made with the arm near straight, light weapon or heavy.
		var want_bend := minf(elbow_dir.angle_to(fore_dir), 0.35)
		_hold_elbow(side, want_bend, swinging, dt)
		_drive_forearm(side, w, fore_q, strength, dt)
		_lock_elbow(side, w, fore_q, strength, dt)
		if has_wrist(w):
			_drive_wrist(side, w, w_aim, strength, dt)
		if side == "R" and two_handed and weapon_joints.L and thrust_line[side] == null:
			_drive_haft(w, w_aim, strength, dt)
		elif side == "R":
			haft_i = Vector3.ZERO
		_unjam_blade(side, w, fore_q, t_pos, t_rot, dt)
		_free_wedged(side, w, dt)
		if not throwing[side]:
			_keep_blade_front(side, w, yaw_q, dt)
		if thrust_line[side] != null:
			_hold_thrust_line(side, w, t_pos, yaw_q, strength, dt)
		var wmax := swing_cap(side, w) if thrust_line[side] == null else 45.0
		if w.angular_velocity.length() > wmax:
			var k := wmax / w.angular_velocity.length()
			w.angular_velocity *= k
			fore.angular_velocity *= k
	elif not w and (jab_t[side] > 0.0):
		var jk2 = 1.0 - jab_t[side] / JAB_TIME
		var out = jk2 > 0.1 and jk2 < 0.6
		pd_axis(upper, Vector3(0, -1, 0), dir if out else (dir + Vector3(0, -0.35, 0)).normalized(), 30.0 if out else 14.0, 0.8, (320.0 if out else 90.0) * af * MS * S, dt)
		pd_axis(fore, Vector3(0, -1, 0), dir, 26.0 if out else 10.0, 0.8, (220.0 if out else 60.0) * af * MS * S, dt)
		pd_twist(upper, torso, 4.0 * MS, 0.6 * MS, 30.0 * MS, dt)
	else:
		# A shield or an empty hand: the same elbow as a weapon arm, mirrored for the left, so
		# the arm never folds in through the chest whichever hand it is.
		var lu := UPPER_LEN * S
		var e_dir := _elbow_dir(side, t_rot.inverse() * (dir + Vector3(0, -0.35, 0)).normalized(), lu, t_rot)
		var elbow = shoulder_w + e_dir * lu
		var f_dir = (target_w - elbow).normalized() if (target_w - elbow).length_squared() > 1e-6 else dir
		pd_axis(upper, Vector3(0, -1, 0), e_dir, 14.0, 0.8, 90.0 * af * MS * S, dt)
		pd_axis(fore, Vector3(0, -1, 0), f_dir, 10.0, 0.8, 60.0 * af * MS * S, dt)
		pd_twist(upper, torso, 1.5 * MS, 0.25 * MS, 12.0 * MS, dt)
		pd_twist(fore, upper, 1.0 * MS, 0.2 * MS, 8.0 * MS, dt)
		if w and w.is_shield:
			_orient_shield(w, target_w, t_pos, yaw_q, strength, dt)
	# Damped to the critical whatever the weapon weighs (a heavy head once got less damping and
	# the arm bounced it about like a whip): the hand settles on its mark instead of overshooting.
	# A thrust is driven hard: the hand is held tight to its line and its mark along it.
	var kp := 300.0 * (0.5 + 0.5 * hnd) * (2.5 if thrust_line[side] != null else 1.0)
	var kd := 2.1 * sqrt(kp) * (1.1 if power else 1.0)
	# The braking is no harder than stops the hand in one step: pushed at the hand, the forearm
	# answers as a much lighter mass than the arm and blade it stands for (it swings on the
	# elbow), and braked as the whole of them its hand overshot every step and the arm trembled.
	var r_h: Vector3 = hand_w - fore.global_position
	var m_pt := 1.0 / (1.0 / maxf(0.05, fore.mass) + r_h.length_squared() / PD.inertia_of(fore))
	var damp := minf(kd * m_eff, 1.6 * m_pt / dt)
	arm_strain[side] = (hand_goal - hand_w).length()
	var F = (hand_goal - hand_w) * kp * m_eff + (target_vel[side] - hand_vel) * damp
	F.y += m_eff * gravity * minf(1.0, af * 1.2)
	F = PD.clamp_len(F, 1150.0 * (1.5 if thrust_line[side] != null else 1.0) * strength * MS * float(mods.strength) * (0.55 + 0.45 * hnd) * (1.0 + 0.35 * (1.0 - hnd)) * (2.2 if not w and jab_t[side] > 0.0 else 1.0) * (1.0 + (0.08 * minf(8.0, w.mass) if w else 0.0)))
	# The hands never press down harder than a share of the body's own weight: bearing down on
	# a man on the sand (or the sand itself) with an arm's whole drive lifted the striker off
	# his feet and flung him up.
	F.y = maxf(F.y, -0.35 * body_mass * gravity)
	# Nor pull up harder than a man can lift: a giant's weapon resting on the sand is dragged,
	# not hauled up, and the arm straining at it no longer hoists its wielder off his feet.
	F.y = minf(F.y, (fore.nominal_mass + upper.nominal_mass * 0.5) * gravity + 0.45 * body_mass * gravity * float(mods.strength))
	fore.apply_impulse(F * dt, hand_w - fore.global_position)
	if on_ground:
		torso.apply_central_impulse(Vector3(-F.x * dt * 0.35, 0, -F.z * dt * 0.35))
	else:
		# In the air nothing under him takes the arm's push: it is his own, all of it back on the
		# trunk (a two-handed weapon held out in a jump flew him metres up and aside).
		torso.apply_central_impulse(-F * dt)
	if w and w.holder == self and not w.is_shield:
		_keep_weapon_out(w, dt)

## An arm never passes through its own chest or head (the body's parts do not collide with each
## other): the elbow, the forearm and the hand are pushed back out of the torso and the head,
## out the front, or out to the arm's own side if they are behind the middle.
const ARM_OUT_K := 900.0
func _keep_arm_out(side: String, dt: float) -> void:
	var up: VoxelPart = arm[side].upper
	var fo: VoxelPart = arm[side].fore
	var out_x := -1.0 if side == "R" else 1.0
	var pts := [[up, up.global_transform * Vector3(0, -up.half_ext.y, 0)]]
	# The middle of the upper arm too, but not with both hands on a haft: reaching across the
	# chest for the other end of it, the off arm's lies along the front of the chest, at the
	# box's corner by the shoulder, and pushed out from there all the time it twisted the haft
	# off the mouse (a longsword aimed out to the right stood 69 degrees short of it).
	if not two_handed:
		pts.append([up, up.global_position])
	if not fo.severed:
		pts.append_array([[fo, fo.global_position], [fo, hand_world(side)]])
	for body in [torso, head]:
		if body.severed:
			continue
		var bt: Transform3D = body.global_transform
		var bq := PD.quat_of(body)
		var e: Vector3 = body.half_ext + Vector3(0.02, 0.0, 0.02) * S
		for pp in pts:
			var l: Vector3 = bt.affine_inverse() * (pp[1] as Vector3)
			if absf(l.x) >= e.x or absf(l.y) >= e.y or absf(l.z) >= e.z:
				continue
			var front := e.z - l.z
			var aside := e.x - l.x * out_x
			var push := Vector3(0, 0, front) if front < aside or l.z > 0.0 else Vector3(out_x * aside, 0, 0)
			var part: VoxelPart = pp[0]
			var v_out := (bq * push.normalized()).dot(part.velocity_at(pp[1]) - body.velocity_at(pp[1]))
			var m_eff: float = (0.0 if fo.severed else fo.nominal_mass) + up.nominal_mass * 0.5 + (weapons[side].mass if weapons[side] else 0.0)
			# A soft, critically damped push (a stiff one fought a two-handed grip and set the
			# hands buzzing at the hilt).
			var acc: float = push.length() * ARM_OUT_K - minf(0.0, v_out) * 2.0 * sqrt(ARM_OUT_K)
			var jo: Vector3 = bq * push.normalized() * acc * m_eff * dt
			part.apply_impulse(jo, (pp[1] as Vector3) - part.global_position)
			body.apply_central_impulse(-jo)   # (the arm pushes off his own body, not off the air)
	_keep_hand_front(side, dt)

var wedged := {"R": 0.0, "L": 0.0}   # how long a free hand has been caught behind the back (s); < 0: passing through
func _unwedge(side: String, dt: float, yaw_q: Quaternion, t_pos: Vector3) -> void:
	var fo: VoxelPart = arm[side].fore
	if fo.severed:
		return
	var hl: Vector3 = yaw_q.inverse() * (hand_world(side) - t_pos)
	var te: Vector3 = torso.half_ext
	var behind: bool = hl.z < -0.7 * te.z and absf(hl.x) < te.x + 0.15 * S and hl.y > -te.y - 0.12 * S and hl.y < te.y + 0.2 * S   # (from the hips up: a hand down at the thigh is no matter)
	var free_hand: bool = state == "stand" and not weapons[side] and not (side == "L" and two_handed) and not throwing[side] and held_item == null
	var mates := [torso, by_name["thigh" + side], by_name["thigh" + ("L" if side == "R" else "R")]]
	if wedged[side] < 0.0:
		wedged[side] = minf(0.0, wedged[side] + dt)
		if hl.z > te.z or wedged[side] >= 0.0 or not free_hand:
			wedged[side] = 0.0
			for p in mates:
				if not p.severed:
					fo.remove_collision_exception_with(p)
		return
	if not (behind and free_hand):
		wedged[side] = 0.0
		return
	wedged[side] += dt
	if wedged[side] > 0.05:
		wedged[side] = -0.6
		for p in mates:
			if not p.severed:
				fo.add_collision_exception_with(p)

## How far (world) `p` has to go forward to be out in front of the body: in front of the chest
## across its width, and beside it no further back than its middle. Zero when it is already.
func _out_front(p: Vector3) -> Vector3:
	var bt: Transform3D = torso.global_transform
	var l: Vector3 = bt.affine_inverse() * p
	var e: Vector3 = torso.half_ext
	if l.y < -e.y - 0.25 * S or l.y > e.y + 0.35 * S:
		return Vector3.ZERO
	var ax := absf(l.x)
	var zmin := -0.2 * e.z if ax > e.x + 0.06 * S else e.z + 0.06 * S
	if ax > e.x + 0.22 * S or l.z >= zmin:
		return Vector3.ZERO
	return bt.basis.orthonormalized() * Vector3(0, 0, zmin - l.z)

## Nor does a hand ever go round behind his back: an empty hand knocked or dragged there stayed
## at the small of the back as if tied (user, more than once), a hand from the hips to the
## shoulders behind the back's plane is pushed out to its own side and on round to the front.
## (Not a throw drawing back over the shoulder, which is above it, nor while something holds him.)
func _keep_hand_front(side: String, dt: float) -> void:
	var up: VoxelPart = arm[side].upper
	var fo: VoxelPart = arm[side].fore
	# Only while he has his body to himself, on his feet or getting up: lying, flung or torn, a
	# hand pushed round against what pins it put the energy into his flight (a man an ape tore
	# and threw went up at 21 m/s).
	# (Staggering on his feet, a hand pushed round fought the ape or giant that had him: only
	# getting up is always put right.)
	if torso.severed or not (state == "stand" or state == "rising") or (state == "stand" and stagger > 0.35) or torso.linear_velocity.length() > 3.0 or (throwing[side] and fo.global_position.y > torso.global_position.y) or (pinned_arm == side and is_instance_valid(grabbed_by)) or (has_meta("beast_hold") and is_instance_valid(get_meta("beast_hold"))):
		return
	# Not with a beast on him (an ape's grip, a croc's jaws, a python's coils: they have their
	# own say over where his arms go, and the push fought them).
	if Combat.current != null and kind != "beast":
		for o in Combat.current.fighters:
			if o != self and is_instance_valid(o) and o.get("kind") == "beast" and o.alive and o.torso.global_position.distance_to(torso.global_position) < 4.0 * maxf(1.0, o.S):
				return
	var out_x := -1.0 if side == "R" else 1.0
	var bt: Transform3D = torso.global_transform
	var inv := bt.affine_inverse()
	var bq := PD.quat_of(torso)
	var e: Vector3 = torso.half_ext
	var pts := [[up, up.global_transform * Vector3(0, -up.half_ext.y, 0)]]
	if not fo.severed:
		pts.append([fo, hand_world(side)])
	# The hand on the haft beside the weapon hand (two hands, across to the other side) is brought
	# round the front, not out to its own side: that way lay across the small of the back (user:
	# H with a mace held low to the right, the off hand on the haft behind the right hip).
	var on_haft: bool = side == "L" and two_handed and weapon_joints.L != null
	for pp in pts:
		var l: Vector3 = inv * (pp[1] as Vector3)
		if l.z > -e.z or absf(l.x) > e.x + 0.12 * S or l.y < -e.y - 0.1 * S or l.y > e.y + 0.25 * S:
			continue
		# Out past the hip or the flank on the side it is on, and on forward: a hand gone round
		# behind the other hip is not dragged back across the small of the back (nor pushed
		# straight on into the buttock and thigh, which it knocks against), it comes out round
		# that side.
		var sx: float = signf(l.x) if absf(l.x) > 0.3 * e.x else out_x
		var push := Vector3(sx * maxf(0.0, e.x + 0.16 * S - l.x * sx), 0.0, maxf(0.0, -0.3 * e.z - l.z))
		if push.length_squared() < 1e-8:
			continue
		var part: VoxelPart = pp[0]
		var dir: Vector3 = bq * push.normalized()
		var v_out := dir.dot(part.velocity_at(pp[1]) - torso.velocity_at(pp[1]))
		var m_eff: float = (0.0 if fo.severed else fo.nominal_mass) + up.nominal_mass * 0.5 + (weapons[side].mass if weapons[side] else 0.0) + (weapons.R.mass * 0.5 if on_haft and weapons.R else 0.0)
		var acc: float = minf(push.length(), 0.3 * S) * ARM_OUT_K - minf(0.0, v_out) * 2.0 * sqrt(ARM_OUT_K)
		var jo: Vector3 = dir * acc * m_eff * dt
		part.apply_impulse(jo, (pp[1] as Vector3) - part.global_position)
		torso.apply_central_impulse(-jo)

## Where a bow or a crossbow points: at the player's crosshair (aimAt), a bot's target (gaze),
## or straight ahead. A bow lies with the arrow (+x) on that line and the stave upright; a
## crossbow's stock (+y) is on it. Slewed at the weapon's rate, like any held weapon.
func _shoot_point(inp: Dictionary) -> Vector3:
	if inp.get("aimAt") is Vector3:
		return inp.aimAt
	if gaze != null:
		return gaze
	return torso.global_position + Vector3(sin(yaw), 0.3, cos(yaw)) * 10.0

func _shoot_pitch(inp: Dictionary) -> float:
	var d := _shoot_point(inp) - (torso.global_position + Vector3(0, 0.3 * S, 0))
	return atan2(d.y, Vector2(d.x, d.z).length())

func _shooter_aim(side: String, w: Weapon, inp: Dictionary, yaw_q: Quaternion, dt: float) -> Quaternion:
	var from := hand_world(side)
	var dir := _shoot_point(inp) - from
	if dir.length_squared() < 1e-4:
		dir = yaw_q * Vector3(0, 0, 1)
	dir = dir.normalized()
	var side_v := dir.cross(UP)
	if side_v.length_squared() < 1e-4:
		side_v = yaw_q * Vector3(1, 0, 0)
	side_v = side_v.normalized()
	var up_v := side_v.cross(dir).normalized()
	var desired: Quaternion
	if is_bow(w):
		# x along the shot, y the stave (tipped a little, as archers cant it), z across.
		var stave := up_v.rotated(dir, -0.18)
		desired = PD.quat_from_axes(dir, stave, dir.cross(stave).normalized())
	else:
		desired = PD.quat_from_axes(side_v, dir, side_v.cross(dir).normalized())
	var prev = aim_q[side]
	if prev != null:
		var step := PD.rot_error(desired, prev)
		var wmax := 14.0 * (0.45 + 0.55 * float(handling[side]))
		var rate := step.length() / dt
		if rate > wmax:
			step *= wmax / rate
			var ang := step.length()
			desired = Quaternion(step / ang, ang) * (prev as Quaternion)
	aim_q[side] = desired
	return desired

## The elbow's direction from the shoulder (a direction in the body's frame): kept on its own
## side of the body (at most 0.22 S across the shoulder line) and at most 0.28 S above the
## shoulder (high enough for an overhead blow), the same for both arms, mirrored.
func _elbow_dir(side: String, e_local: Vector3, lu: float, t_rot: Quaternion) -> Vector3:
	var flip := side == "L"
	if flip:
		e_local.x = -e_local.x
	e_local = _limit_dir(e_local.normalized(), 0, 0.22 * S / lu)
	if flip:
		e_local.x = -e_local.x
	e_local = _limit_dir(e_local, 1, 0.28 * S / lu)
	return (t_rot * e_local).normalized()

## A hand's mark (in the yaw frame, from the torso) moved out of the torso and the head to the
## front of them: neither hand is ever pulled in through its own body.
func _clear_body(target: Vector3, yaw_q: Quaternion, t_pos: Vector3) -> Vector3:
	var th: Vector3 = torso.half_ext
	var tz := th.z + 0.09 * S
	if target.y < th.y and target.y > -th.y * 1.1 and absf(target.x) < th.x + 0.05 * S and target.z < tz:
		target.z = tz
	if not head.severed:
		var hh: Vector3 = head.half_ext
		var hl := yaw_q.inverse() * (head.global_position - t_pos)
		var hz := hl.z + hh.z + 0.09 * S
		if absf(target.x - hl.x) < hh.x + 0.05 * S and absf(target.y - hl.y) < hh.y + 0.05 * S and target.z < hz:
			target.z = hz
	return target

func arm_of(w: Weapon) -> Dictionary:
	return arm.R if weapons.R == w else arm.L

## Caps one component (0 = x, 1 = y) of a unit direction, keeping it a unit direction: the
## other components take up the rest in their own proportion.
static func _limit_dir(e: Vector3, axis: int, mx: float) -> Vector3:
	if e[axis] <= mx:
		return e
	e[axis] = mx
	var rest := sqrt(maxf(0.0, 1.0 - mx * mx))
	var o: Array = [1, 2] if axis == 0 else [0, 2]
	var l := Vector2(e[o[0]], e[o[1]]).length()
	if l < 1e-4:
		e[o[0]] = -rest * 0.8 if axis == 0 else 0.0
		e[o[1]] = -rest * (0.6 if axis == 0 else 1.0)
	else:
		e[o[0]] *= rest / l
		e[o[1]] *= rest / l
	return e

## A held blade never passes through its owner: own parts do not collide with own weapons, so
## when the hand-to-tip line comes inside the torso or head it is pushed back out.
func _keep_weapon_out(w: Weapon, dt: float) -> void:
	var q := PD.quat_of(w)
	var from := w.global_position
	var tip := from + q * Vector3(0, w.reach, 0)
	var base := from + q * Vector3(0, -0.15, 0)
	var ab := tip - base
	for part in [torso, head]:
		if part.severed:
			continue
		var c: Vector3 = part.global_position
		var k := clampf((c - base).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
		var p := base + ab * k
		var d := p - c
		d.y *= 0.7
		var r := (0.2 if part == head else 0.22) * S
		var dist := d.length()
		if dist >= r or dist < 1e-4:
			continue
		# Welded in the hand, the blade only moves if the forearm goes with it.
		var push: Vector3 = d / dist * ((r - dist) / r * 900.0 * (w.mass + 0.8)) * dt
		w.apply_impulse(push, p - w.global_position)
		if w.welded:
			arm_of(w).fore.apply_impulse(push * 0.6, hand_world("R" if weapons.R == w else "L") - arm_of(w).fore.global_position)
		# And as much back on the body it is pushed off: his own haft over his head could
		# otherwise push him up and up off his feet (a push with nothing pushing back).
		part.apply_central_impulse(-push * (1.6 if w.welded else 1.0))

## A big blade left behind its wielder's back, with the arm too weak to haul it round, is swung
## back over the shoulder after a moment (sooner the heavier it is).
func _unjam_blade(side: String, w: Weapon, fore_q: Quaternion, t_pos: Vector3, t_rot: Quaternion, dt: float) -> void:
	if not w.welded:
		behind_t[side] = 0.0
		return
	var inv := t_rot.inverse()
	var wrot := PD.quat_of(w)
	var tip := inv * (w.global_position + wrot * Vector3(0, w.reach * 0.85, 0) - t_pos)
	var want := (fore_q * grip_q(w)) * Vector3(0, 1, 0)
	var want_l := inv * want
	var heavy := clampf((w.mass - 2.0) / 5.0, 0.0, 1.0)
	var behind := tip.z < -(0.12 - 0.08 * heavy) * S
	behind_t[side] = behind_t[side] + dt if behind else 0.0
	var pulling := want_l.z > -0.2
	if behind_t[side] < ((0.6 - 0.35 * heavy) if pulling else (1.2 - 0.5 * heavy)):
		return
	if not pulling:
		want = t_rot * Vector3(0.15, 0.55, 1).normalized()
	var cur := wrot * Vector3(0, 1, 0)
	var axis := cur.cross(want)
	if axis.length_squared() < 1e-6:
		axis = t_rot * Vector3(0, 1, 0)
	var ang := acos(clampf(cur.dot(want), -1.0, 1.0))
	var av := axis.normalized() * minf(9.0, 5.0 * ang + 2.0) + torso.angular_velocity
	w.angular_velocity = av
	arm[side].fore.angular_velocity = av

## A blade driven into a man (a head, more often than not) could wedge there: pressed into the
## part, or the part's shape made again round it when a cut took voxels out, and the arm
## pulling at it for nothing while it stayed in (user: the sword goes into a head and sticks).
## Pressed into one part of a foe for half a second while the hand is pulling away from it, the
## blade is let through that part for a moment and slides out.
const WEDGE_T := 0.5
func _free_wedged(side: String, w: Weapon, dt: float) -> void:
	var now := time
	for k in range(unwedge.size() - 1, -1, -1):
		var u: Array = unwedge[k]
		if now >= float(u[2]):
			if is_instance_valid(u[0]) and is_instance_valid(u[1]):
				# Wrenched free, it slides on out: the part lets it through until the blade is
				# clear of it (given it back while still half in, it caught there again), for a
				# second and a half at most.
				if now < float(u[3]) and _blade_in((u[0] as Weapon), (u[1] as VoxelPart)):
					u[2] = now + 0.1
					continue
				(u[0] as Weapon).remove_collision_exception_with(u[1])
			unwedge.remove_at(k)
	var held: Dictionary = wedge_t[side]
	var touching := {}
	for b in w.get_colliding_bodies():
		if b is VoxelPart and b.fighter != null and b.fighter != self:
			touching[b] = true
	for b in held.keys():
		if not touching.has(b):
			held.erase(b)
	if touching.is_empty():
		return
	# Pulling away: the hand's mark is off where the hand is, and away from the part.
	var hw := hand_world(side)
	var goal = hand_lead[side]
	if goal == null:
		return
	var pull: Vector3 = (goal as Vector3) - hw
	if pull.length() < 0.12 * S:
		for b in touching:
			held.erase(b)
		return
	for b in touching:
		if pull.dot((b as VoxelPart).global_position - hw) > 0.0:
			held.erase(b)
			continue
		held[b] = float(held.get(b, 0.0)) + dt
		if float(held[b]) >= WEDGE_T:
			held.erase(b)
			w.add_collision_exception_with(b)
			unwedge.append([w, b, now + 0.35, now + 1.5])

## Whether the blade still runs into the part: the part's box, grown a little, crosses the line
## from the grip to the tip.
static func _blade_in(w: Weapon, b: VoxelPart) -> bool:
	var a := w.grip_world()
	var tip := w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)
	var inv := b.global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * tip
	var e: Vector3 = b.half_ext + Vector3.ONE * 0.04
	for i in 9:
		var q := la.lerp(lb, i / 8.0)
		if absf(q.x) < e.x and absf(q.y) < e.y and absf(q.z) < e.z:
			return true
	return false

## The hand moves on a flat pane in front of the body, Half Sword style.
## This fighter's own bodies, kept out of the rays he casts down for the ground.
var _rids: Array[RID] = []
func _own_rids() -> Array[RID]:
	if _rids.is_empty():
		for p: VoxelPart in parts:
			_rids.append(p.get_rid())
	return _rids

## The ground under a foot's spot: the sand, or a body lying on it there; `fallback` with
## nothing under it within reach.
func _ground_under(at: Vector3, fallback: float) -> float:
	var h := _ground_ray(torso.get_world_3d().direct_space_state, Vector3(at.x, torso.global_position.y, at.z))
	return float(h.position.y) if h else fallback

## The ground under `from`, 2.2 S down: the sand, or a dead man or beast lying still on it.
## A live one is not ground (a beast charging under him, or biting at his legs, read as ground
## threw him into the air or sat him on its head), nor a body still on the move.
func _ground_ray(space: PhysicsDirectSpaceState3D, from: Vector3) -> Dictionary:
	var to := from + Vector3(0, -2.2 * S, 0)
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, VoxelPart.LAYER_WORLD | VoxelPart.LAYER_BODY, _own_rids()))
	if h and not _is_dead_ground(h.collider):
		h = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, VoxelPart.LAYER_WORLD))
	return h

static func _is_dead_ground(c: Object) -> bool:
	if not (c is VoxelPart):
		return not (c is RigidBody3D)   # the sand and the props
	var p := c as VoxelPart
	if p.linear_velocity.length() > 0.5:
		return false
	var o: Node = p.fighter
	if o == null:
		return p.severed   # a piece cut off, lying there
	return o is Fighter and not (o as Fighter).alive   # (a Beast is a Fighter too)

func hand_target_local(side: String, hp: Dictionary, thrust: float) -> Vector3:
	var sh: Vector3 = shoulder[side]
	var x := -clampf(float(hp.get("x", 0.0)), -2.0, 2.0) * 0.5 * S
	# Both hands on the haft: out to the main hand's own side the other hand has to cross the
	# whole chest to keep its grip, so that way the mark goes only part as far.
	if two_handed and side == "R" and x * sh.x > 0.0:
		x *= 0.5
	var fist := 0.12 if not weapons[side] else 0.0
	var hy := clampf(float(hp.get("y", 0.0)), -1.6, 1.6)
	var y := (-0.08 + (hy * 0.42 if hy >= 0.0 else -0.3 * minf(0.4, -hy) - (0.6 if fist > 0.0 else 0.4) * maxf(0.0, -hy - 0.4))) * S
	var cross: float = maxf(0.0, -float(hp.get("x", 0.0))) if side == "R" else maxf(0.0, float(hp.get("x", 0.0)))
	# A low guard or a blow at a man on the sand: the body leans in and the hands go out ahead
	# of the bent chest (held in under it, they folded the elbow to keep out of it), so the arm
	# stays straight and the point goes down to the sand.
	var low := clampf((-hy - 0.5) / 0.9, 0.0, 1.0) if fist == 0.0 else 0.0
	# A short weapon (a dagger, a stick) has to be taken all the way down to a man on the sand:
	# the shorter it is, the lower the hand goes, the body stooping and the knees bending with it.
	var short := clampf((0.95 - float(weapons[side].reach)) / 0.5, 0.0, 1.0) if weapons[side] and not weapons[side].is_shield else 0.0
	y -= 0.3 * low * short * S
	# Both hands go no lower than the hips: a long blade pointed down from lower than that
	# went into the sand and could not follow the mouse.
	if two_handed and side == "R":
		y = minf(maxf(y, -0.55 * S), 0.55 * S)
	# "tuck": a hand held in to the body (a bot clutching a wound), not out in front of it.
	var z := (0.40 + fist + thrust * 0.4 + 0.1 * minf(1.0, cross / 1.5) + 0.3 * low + 0.08 * low * short - 0.32 * clampf(float(hp.get("tuck", 0.0)), 0.0, 1.0)) * S
	var d := Vector3(x + (0.1 if side == "R" else -0.1) * S, y, z)
	# Never round behind the back (only a throw is drawn back there on purpose).
	if thrust > -0.5:
		d.z = maxf(d.z, 0.12 * S)
	# A weapon swung (the button held, or a fast stroke) goes out at the end of a straight arm:
	# held in close the elbow had to bend to reach it, and a heavy head folded it further.
	var w_side = weapons[side]
	if w_side and not w_side.is_shield and absf(thrust) < 0.05 and (power_now or swing_hold[side] > 0.0) and d.length() > 1e-4:
		d = d.normalized() * maxf(d.length(), arm_reach * 0.92)
	d = PD.clamp_len(d, (UPPER_LEN + FORE_LEN) * 0.97 * S if fist > 0.0 and jab_t[side] > 0.0 else arm_reach)
	return d + sh

## Where the blade should point: elevation from the hand's height, yaw from a pivot behind the
## hand, the edge leading the stroke; slewed at the rate the weapon allows.
## How far along a thrust's line (from `o`, in the body's frame) the hand is now: drawn back
## along it (half an arm, to no nearer than just in front of the chest), then driven out fast
## past the end of the arm (reached from the shoulder `sh`), held there while the button is down.
## Two hands on the haft: `chest_z` is the nearer hand's, which the drawing back is kept off.
func _thrust_ext(tl: Dictionary, o_l: Vector3, sh: Vector3, chest_z := INF) -> float:
	var d: Vector3 = tl.dir
	var o := o_l - sh
	var reach := arm_reach * 0.98
	var bq := o.dot(d)
	var disc := bq * bq - (o.length_squared() - reach * reach)
	var e_hi := 0.45 * S
	var e_lo := -0.2 * S
	if disc > 0.0:
		var rt := sqrt(disc)
		e_hi = clampf(-bq + rt, 0.0, 0.6 * S)
		e_lo = maxf(-bq - rt, e_hi - 0.5 * S)
	e_lo = minf(0.0, maxf(e_lo, (0.15 * S - minf(o_l.z, chest_z)) / d.z))
	# Driven a hand past the arm's reach: the straight arm hauls the shoulder after it, the body
	# leaning into the stab as the feet lunge.
	e_hi += THRUST_OVER * S
	var t: float = tl.t
	if t < THRUST_DRAW:
		return e_lo * smoothstep(0.0, 1.0, t / THRUST_DRAW)
	var k := minf(1.0, (t - THRUST_DRAW) / THRUST_DRIVE)
	return lerpf(e_lo, e_hi, 1.0 - (1.0 - k) * (1.0 - k))

## A limb or a blade asked to turn far at once (an arm hanging at the side, wanted high across
## the body) took the short way, across its own hips and chest, was pushed back out of them
## and stuck there. So such a turn goes round by the front of the body, and the direction
## asked is never more than AIM_AHEAD ahead of where the thing really points: the next step
## from `cur` toward `want` (unit directions, `frame` the body's facing).
const AIM_AHEAD := 1.6
static func _route_front(cur: Vector3, want: Vector3, frame: Quaternion) -> Vector3:
	var ahead := cur.angle_to(want)
	var go := want
	if ahead > 0.9:
		var mid := frame.inverse() * (cur + want)
		if mid.length_squared() < 0.0025:
			mid = Vector3(0, 0, 1)
		if mid.normalized().z < 0.45:
			mid.z = maxf(mid.z, 1.2)
			go = frame * mid.normalized()
	if ahead <= AIM_AHEAD and go == want:
		return want
	var ax := cur.cross(go)
	if ax.length_squared() < 1e-8:
		return want
	return cur.rotated(ax.normalized(), minf(AIM_AHEAD, cur.angle_to(go))).normalized()

func weapon_aim(side: String, w: Weapon, target_w: Vector3, t_pos: Vector3, yaw_q: Quaternion, inp: Dictionary, dt: float) -> Quaternion:
	if w.design.has("shoots") and not w.design.get("chain"):
		return _shooter_aim(side, w, inp, yaw_q, dt)
	var local := (yaw_q.inverse() * (target_w - t_pos)) / S
	var hy := float(hand_input[side].get("y", 0.15))
	# Right up and right down at the ends of the pane (the sand stops a long blade short below).
	var elev := clampf(hy * PI / 2.0 / 1.6, -PI / 2.0, PI / 2.0)
	# Both hands on the haft swing it about the middle of the chest, one about its own shoulder.
	var shx: float = 0.0 if two_handed else shoulder[side].x / S
	var pivot := Vector3(shx + (local.x - shx) * 0.2, local.y, local.z - 0.28)
	var flat := Vector3(local.x - pivot.x, 0, local.z - pivot.z)
	if flat.length_squared() < 1e-4:
		flat = Vector3(0, 0, 1)
	flat = flat.normalized()
	if not is_spear(w):
		# The sweep comes from the mouse itself, the wrists and forearms carrying the blade round
		# (90 degrees either way at the ends of the pane), not from how far the hands can get: in
		# one hand or two, light or heavy, every blade sweeps as wide.
		# (Narrower the lower the blade: low across the body it would end up behind the back.)
		var sweep := -clampf(float(hand_input[side].get("x", 0.0)), -2.0, 2.0) * PI / 4.0 * (1.0 - 0.45 * clampf(-elev / 1.2, 0.0, 1.0))
		flat = Vector3(sin(sweep), 0, cos(sweep))
	var axis := yaw_q * Vector3(flat.x * cos(elev), sin(elev), flat.z * cos(elev))
	if is_spear(w) and not throw_pose[side]:
		# A spear is held couched, its point on the line the fighter looks along; the mouse
		# moves the point about that line (up for an overhand grip, aside to cover), it does
		# not tilt the shaft up like a sword blade.
		var lk = inp.get("look")
		var base: Vector3 = yaw_q * Vector3(0, 0, 1)
		if lk is Dictionary:
			var pt := clampf(float(lk.get("pitch", 0.0)), -0.9, 0.9) * 0.8
			base = Vector3(sin(float(lk.yaw)) * cos(pt), sin(pt), cos(float(lk.yaw)) * cos(pt))
		var hx := clampf(float(hand_input[side].get("x", 0.0)), -2.0, 2.0)
		axis = base.rotated(Vector3.UP, -hx * 0.6)
		var side_ax := axis.cross(Vector3.UP).normalized()
		if side_ax.length_squared() > 1e-4:
			axis = axis.rotated(side_ax, clampf(hy, -1.6, 1.6) * 0.55).normalized()
	var ta = thrust_aim[side]
	if ta != null:
		axis = axis.slerp(ta.dir, ta.k).normalized()
	if not throwing[side]:
		# Nor the blade: it never points back past the shoulders.
		var la_ := yaw_q.inverse() * axis
		if la_.z < -0.15:
			var flat2 := Vector2(la_.x, la_.y)
			var keep := sqrt(maxf(0.0, 1.0 - 0.15 * 0.15))
			flat2 = flat2.normalized() * keep if flat2.length() > 1e-4 else Vector2(0, keep)
			axis = yaw_q * Vector3(flat2.x, flat2.y, -0.15)
	# The line asked for is never far ahead of where the blade really is, nor on a way through
	# the body (see _route_front); kept off the sand below like any other.
	if not throwing[side] and not throw_pose[side]:
		axis = _route_front(PD.quat_of(w) * Vector3.UP, axis, yaw_q)
	if not throwing[side]:
		# A low blow comes down to the sand and skims it instead of ploughing in (a sweep with the
		# tip dug in stuck fast there): the point is let down to just above the ground (a heavy
		# head sags a little below its aim). Measured from where the hand is going, the lowest it
		# gets in the stroke, not where it is on the way: from there the limit climbed as the hand
		# came down and pulled the falling blade back up, braking every chop halfway.
		# Close over the sand only in a chop, the hand coming down fast; a sideways sweep keeps
		# the point higher, as dragged along the sand a long blade stalled in it.
		var hand_low := minf(hand_world(side).y, target_w.y)
		# A chop stays a chop to its end: the hand slows as it comes down onto the man, and taken
		# for a sweep there the point was hauled back up just before it landed.
		chop_mem[side] = maxf(clampf(-target_vel[side].y / (1.5 * S), 0.0, 1.0), float(chop_mem[side]) - dt / 0.6)
		var chop: float = chop_mem[side]
		var margin := lerpf(0.13 + 0.035 * minf(4.0, w.mass), 0.025 + 0.008 * minf(4.0, w.mass), chop)
		if is_spear(w):
			# A spear's point lowered (couched low, or at a man on the sand) stops just over the
			# sand: driven into it, the long haft caught there and would not come back up.
			margin = 0.05 + 0.008 * minf(4.0, w.mass)
		var floor_gap := hand_low - (ground_level + margin * S)
		var reach_w := maxf(0.2, w.reach + 0.04 * S)
		if axis.y < 0.0 and axis.y * reach_w < -floor_gap:
			var ny := clampf(-floor_gap / reach_w, -1.0, 0.0)
			var hz := Vector3(axis.x, 0, axis.z)
			hz = hz.normalized() if hz.length_squared() > 1e-6 else yaw_q * Vector3(0, 0, 1)
			axis = hz * sqrt(1.0 - ny * ny) + Vector3(0, ny, 0)
	if throw_pose[side]:
		# A spear being thrown points where it will go, at the mark (or ahead and a touch up).
		var at = inp.get("aimAt")
		var fly: Vector3 = ((at as Vector3) - target_w).normalized() if at is Vector3 and (at as Vector3).distance_to(target_w) > 0.5 else yaw_q * Vector3(0, 0.17, 1).normalized()
		axis = (fly + Vector3(0, 0.08, 0)).normalized()
	low_hand = maxf(low_hand, maxf(0.0, -elev - 0.2) * (1.0 + 0.8 * clampf((0.95 - w.reach) / 0.5, 0.0, 1.0)))
	var raise_k := smoothstep(0.5, 1.2, elev)
	var ed := yaw_q * Vector3((1.0 if side == "R" else -1.0) * (1.0 - raise_k), 0, raise_k)
	ed -= axis * ed.dot(axis)
	# Where the blade lies along that edge line (swept full out to the side) the edge is taken
	# from straight ahead instead, eased over so it never jumps from one to the other.
	var fz := yaw_q * Vector3(0, 0, 1)
	fz -= axis * axis.dot(fz)
	var keep := smoothstep(0.05, 0.3, ed.length())
	ed = (fz.normalized() * (1.0 - keep) + (ed.normalized() if ed.length_squared() > 1e-8 else fz.normalized()) * keep)
	if ed.length_squared() < 1e-6:
		ed = fz
	ed = ed.normalized()
	# The edge is where the wheel set it, and stays there through every stroke: it is not rolled
	# over to lead the swing (that turned a pick's head over at each change of way, on its own).
	var tw := float(inp.get("twist" if side == "R" else "offTwist", 0.0))
	ed = ed.rotated(axis, tw)
	# A bot has no wheel: its blade (sharp on both sides) turns to lead whichever way it sweeps,
	# the nearer side forward (without it a giant's blows came down on the flat and seldom
	# reached a man on the sand).
	var led := false
	if is_bot and not is_spear(w) and w.bites() and w.edge_side() == 0.0:
		var tv: Vector3 = target_vel[side] - axis * target_vel[side].dot(axis)
		if tv.length() > 0.9:
			var nd := tv.normalized()
			var sd = stroke_dir[side]
			stroke_dir[side] = nd if sd == null or (sd as Vector3).dot(nd) < -0.2 else (sd as Vector3).slerp(nd, minf(1.0, dt * 10.0)).normalized()
			stroke_idle[side] = 0.0
		else:
			stroke_idle[side] = float(stroke_idle[side]) + dt
			if float(stroke_idle[side]) > 0.6:
				stroke_dir[side] = null
		if stroke_dir[side] != null:
			var lead: Vector3 = stroke_dir[side]
			lead -= axis * lead.dot(axis)
			if lead.length_squared() > 1e-4:
				var lt := lead.normalized()
				var prev_ed: Vector3 = (aim_q[side] as Quaternion) * Vector3.RIGHT if aim_q[side] != null else lt
				ed = lt * (1.0 if prev_ed.dot(lt) >= 0.0 else -1.0)
				led = true
	var prev = aim_q[side]
	if prev != null:
		# Only the blade's line is held to the speed the weapon allows; turning the edge about
		# the line is the wrist's, and does not eat into the sweep (when the stroke turned back
		# and the edge rolled over to lead it, the sweep stalled while it did).
		var h: float = handling[side]
		var wmax := 34.0 * (0.45 + 0.55 * h) * long_k(w) * (1.2 if inp.get("power", false) else 1.0)
		var pa: Vector3 = (prev as Quaternion) * Vector3.UP
		var ang := pa.angle_to(axis)
		if ang > wmax * dt and ang > 1e-5:
			var rax := pa.cross(axis)
			if rax.length_squared() > 1e-10:
				axis = (pa.rotated(rax.normalized(), wmax * dt)).normalized()
				ed -= axis * ed.dot(axis)
				if ed.length_squared() < 1e-6:
					ed = ((prev as Quaternion) * Vector3.RIGHT)
					ed -= axis * ed.dot(axis)
				ed = ed.normalized()
	if prev != null and not led:
		# The edge goes round with the blade: the last aim's edge carried along the turn the blade
		# makes, so swinging never rolls it about the haft; the wheel turns it by what the wheel
		# turned, and over a second or so it settles back to the edge the body's frame gives it.
		var pa2: Vector3 = (prev as Quaternion) * Vector3.UP
		var te: Vector3 = (prev as Quaternion) * Vector3.RIGHT
		if pa2.dot(axis) > -0.95:
			te = Quaternion(pa2, axis) * te
		te -= axis * te.dot(axis)
		if te.length_squared() > 1e-6:
			te = te.normalized().rotated(axis, tw - float(aim_tw[side]))
			var off := atan2(te.cross(ed).dot(axis), te.dot(ed))
			# Not with both hands on the haft: there the edge stays where the turns and the
			# wheel left it. Settling it to the frame's asked the two arms to roll the haft up
			# to a quarter turn while holding still (a high guard: edge forward, up from edge
			# right), which two arms on one grip cannot do, so the blade tilted instead, 30
			# degrees off the mouse in two seconds at a high guard and 41 out to the side,
			# and a low guard stuck 34 off (user: holding a long weapon in two hands).
			ed = te.rotated(axis, off * minf(1.0, dt * (0.0 if two_handed else 1.5)))
	aim_tw[side] = tw
	var z := ed.cross(axis).normalized()
	var e := axis.cross(z)
	var desired := PD.quat_from_axes(e, axis, z)
	aim_q[side] = desired
	return desired

## How fast a weapon can be swung round (rad/s): a light blade whips round, a weight far out on
## a haft (a hammer's head, a lead-weighted club) turns slower, by its moment about the hand,
## though it lands with more behind it. A strong man swings a heavy one a little faster.
const SWING_I_REF := 0.25   # kg·m², a sword's
## A long weapon is not whipped round as fast as a short one, however light: the hands carry it
## and turn it slower the longer it is past a zweihander's length, so its end goes no faster than
## a sword's point (a two-metre pole with a little head on it went round at 26 m/s at the end,
## the gladius 16: user).
const LONG_REACH := 1.55   # m: a zweihander's length; longer than that, slower
func long_k(w) -> float:
	if w == null or w.is_shield:
		return 1.0
	return pow(minf(1.0, LONG_REACH * S / maxf(0.1, float(w.reach))), 1.5)

func swing_cap(side: String, w: Weapon) -> float:
	var lever := w.global_transform * w.center_of_mass - hand_world(side)
	var i_wpn := PD.inertia_of(w) + w.mass * lever.length_squared()
	var k := pow(SWING_I_REF * S * S * float(mods.get("strength", 1.0)) / maxf(1e-4, i_wpn), 0.25)
	# A touch slower than it was (user: the swings feel very, very fast).
	var cap := clampf(38.0 * k, 16.0, 38.0)
	if float(w.reach) > LONG_REACH * S:
		cap = minf(cap, 12.0 * S * sqrt(float(mods.get("strength", 1.0))) / float(w.reach))
	return cap

func _drive_forearm(side: String, w: Weapon, fore_q: Quaternion, strength: float, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var rot := PD.quat_of(fore)
	var err := PD.rot_error(fore_q, rot)
	# In a thrust the wrist and forearm lock the blade on its line: it is driven along it, not
	# turned off it by the push of the arm.
	var hold := 1.8 if thrust_line[side] != null else 1.0
	var wn := 16.0 * hold
	var alpha := PD.clamp_len(err * (wn * wn) - (fore.angular_velocity - (aim_w[side] as Vector3)) * (2.0 * 0.8 * wn), 920.0 * hold * hold * (0.6 + 0.4 * strength) * float(mods.strength))
	var hand_w := hand_world(side)
	var com_w := w.global_transform * w.center_of_mass
	var lever := com_w - hand_w
	var i_fore := PD.inertia_of(fore) + fore.nominal_mass * pow(FORE_LEN * S * 0.5, 2)
	var i_wpn := PD.inertia_of(w) + w.mass * lever.length_squared()
	var i_asm := i_fore + i_wpn
	var along := rot * Vector3(0, -1, 0)
	var twist_a := along * alpha.dot(along)
	var tq := PD.torque_for(fore, alpha - twist_a, i_asm / PD.inertia_of(fore)) + PD.torque_for(fore, twist_a, 1.5)
	# A fighter puts his body into a heavy weapon: the torque he can turn it with grows with how
	# hard it is to turn (a hammer head far out on its haft), so it moves with his hands under
	# control instead of trailing behind them.
	var heft := clampf(i_wpn / (MS * S * S * 0.6), 0.0, 6.0)
	tq = PD.clamp_len(tq, 90.0 * hold * strength * MS * S * float(mods.strength) * (1.0 + 0.45 * heft))
	var mg := w.mass * gravity * minf(1.0, strength * 2.0)
	tq += Vector3(-lever.z * mg, 0, lever.x * mg)
	var f := i_fore / i_asm
	var tw := tq * (1.0 - f)
	if has_wrist(w):
		# The wrist turns freely about the blade's length (_drive_wrist sets the edge): none of
		# the arm's torque goes into that light roll, or it spins the blade in the hand.
		var bax := PD.quat_of(w) * Vector3.UP
		tw -= bax * tw.dot(bax)
	fore.apply_torque_impulse((tq - tw) * dt)
	w.apply_torque_impulse(tw * dt)

## A fighter's elbow is held, not left to flap: the forearm (and the weapon welded to it) is
## steered relative to the upper arm, its bend changing no faster than a trained arm would
## change it, the reaction going into the upper arm. So the arm swings as one lever from the
## shoulder, like real technique, and a heavy head cannot whip it about.
const ELBOW_DAMP := 45.0
const ELBOW_PULL := 40.0
func _lock_elbow(side: String, w: Weapon, fore_q: Quaternion, strength: float, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var upper: VoxelPart = arm[side].upper
	var ax := PD.quat_of(fore) * Vector3(0, -1, 0)
	# Only the bend: the twist about the forearm is the wrist's business (handled above).
	var err := PD.rot_error(fore_q, PD.quat_of(fore))
	err -= ax * err.dot(ax)
	var rel := fore.angular_velocity - upper.angular_velocity
	rel -= ax * rel.dot(ax)
	var hand_w := hand_world(side)
	var lever := (w.global_transform * w.center_of_mass) - hand_w
	var i_fore := PD.inertia_of(fore) + fore.nominal_mass * pow(FORE_LEN * S * 0.5, 2)
	var i_asm := i_fore + PD.inertia_of(w) + w.mass * lever.length_squared()
	# The bend is between two bodies: sized on their combined (reduced) inertia, the upper arm's
	# about its own middle (a torque turns it there; sized about the shoulder, the damper
	# overdrove it and the arm buzzed at full reach).
	var i_up := PD.inertia_of(upper)
	var i_red := i_asm * i_up / (i_asm + i_up)
	# A damper on the bend, with a gentle pull toward the bend the aim wants: the elbow does
	# not flex fast unless the fighter means it, so a swing is one lever from the shoulder.
	var tq := (err * ELBOW_PULL - rel * ELBOW_DAMP) * i_red
	# About the hinge only: not about the upper arm's own length either, round which it is far
	# lighter than i_red allows for (pushed there, it buzzed every step under a two-handed grip).
	var au := PD.quat_of(upper) * Vector3(0, -1, 0)
	tq -= au * tq.dot(au)
	tq = PD.clamp_len(tq, 260.0 * maxf(0.3, strength) * MS * S * float(mods.strength))
	fore.apply_torque_impulse(tq * dt)
	upper.apply_torque_impulse(-tq * dt)

## Both hands on a haft turn it as a lever, one hand pushing as the other pulls: the blade's line
## is steered onto the aim's from the pair of them, the reaction going into the body. (Each arm alone, driven to its own place on the haft, could not hold that line: the
## off arm reaching across the chest pulled it its own way and the blade stood off the mouse.)
## Not its roll, which is the wrists' (_drive_wrist).
const HAFT_WN := 12.0
const HAFT_KI := 6.0   # how hard a held error is worked off, per second of it
var haft_i := Vector3.ZERO   # the haft drive's held correction (_drive_haft)
const HAFT_MAX := 70.0
func _drive_haft(w: Weapon, w_aim: Quaternion, strength: float, dt: float) -> void:
	var ax := PD.quat_of(w) * Vector3.UP
	var want := w_aim * Vector3.UP
	var c := ax.cross(want)
	var err := c.normalized() * ax.angle_to(want) if c.length_squared() > 1e-10 else Vector3.ZERO
	var rel := w.angular_velocity - (aim_w.R as Vector3)
	rel -= ax * rel.dot(ax)
	# A steady pull off the line (the arms' own pose, a heavy head's weight) is worked off as he
	# holds it: the correction grows while the blade stays off the mouse, and lets go as it comes
	# on or as the stroke moves fast.
	var moving := (aim_w.R as Vector3).length() > 3.0
	haft_i = (haft_i + err * dt) * (0.9 if moving else 1.0)
	haft_i -= ax * haft_i.dot(ax)   # (about the haft's line only, never its roll)
	haft_i = PD.clamp_len(haft_i, 0.35)
	var alpha := err * HAFT_WN * HAFT_WN + haft_i * HAFT_WN * HAFT_WN * HAFT_KI - rel * (2.0 * 0.9 * HAFT_WN)
	var mid := (hand_world("R") + hand_world("L")) * 0.5
	var lever := (w.global_transform * w.center_of_mass) - mid
	var i_wpn := PD.inertia_of(w) + w.mass * lever.length_squared()
	var heft := clampf(i_wpn / (MS * S * S * 0.6), 0.0, 6.0)
	var tq := PD.clamp_len(alpha * i_wpn, HAFT_MAX * strength * MS * S * float(mods.strength) * (1.0 + 0.45 * heft))
	w.apply_torque_impulse(tq * dt)
	# The shoulders and the trunk turn it: half the reaction is the trunk's, a quarter each upper
	# arm's (all on the trunk, a war hammer swung about leaned the whole man over with it; all on
	# the arms, the sword arm was pushed in across the chest).
	torso.apply_torque_impulse(-tq * 0.5 * dt)
	arm.R.upper.apply_torque_impulse(-tq * 0.25 * dt)
	arm.L.upper.apply_torque_impulse(-tq * 0.25 * dt)

## The wrist turns the blade about its own length to the edge the aim wants (the wheel's
## twist, the lean into the stroke), the reaction going into the forearm.
func _drive_wrist(side: String, w: Weapon, w_aim: Quaternion, strength: float, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var q := PD.quat_of(w)
	var ax := q * Vector3.UP
	var want := w_aim * Vector3.RIGHT
	want -= ax * want.dot(ax)
	if want.length_squared() < 1e-6:
		return
	var cur := q * Vector3.RIGHT
	var ang := atan2(cur.cross(want).dot(ax), cur.dot(want.normalized()))
	var spin := (w.angular_velocity - fore.angular_velocity).dot(ax) - ((aim_w[side] as Vector3) - fore.angular_velocity).dot(ax)
	var b := w.global_transform.basis.orthonormalized()
	var la := b.inverse() * ax
	var i_ax := maxf(1e-4, la.x * la.x * w.inertia.x + la.y * la.y * w.inertia.y + la.z * la.z * w.inertia.z)
	# Held firm at the angle the wheel set, through the swing and the knocks of a blow: a stiff
	# grip, and as strong as the head is hard to turn (an axe head off its haft's line). Every
	# fighter's, the host's guests' as well (they are all run by this code on the host).
	var wn := 52.0
	var t := (ang * wn * wn - spin * 2.0 * wn) * i_ax
	var grip_k := 3.0 if throw_pose[side] or (throw_anim != null and throw_anim.side == side) else 1.0
	# A head off the haft's line (an axe) is turned by its own weight: the grip holds against it.
	var lever := (w.global_transform * w.center_of_mass) - w.global_position
	t -= lever.cross(Vector3(0, -w.mass * gravity, 0)).dot(ax)
	var t_max := maxf(70.0 * MS * S, i_ax * wn * wn * 2.5) * grip_k * maxf(0.4, strength)
	t = clampf(t, -t_max, t_max)
	w.apply_torque_impulse(ax * t * dt)
	fore.apply_torque_impulse(-ax * t * dt)

## A thrust keeps to its line: the hand's drift off the line and the blade's turn off it are
## damped out (the push going back into the body), so the stab goes straight, point first,
## parallel to the blade, wherever along it the hand is being driven.
func _hold_thrust_line(side: String, w: Weapon, t_pos: Vector3, yaw_q: Quaternion, strength: float, dt: float) -> void:
	var tl = thrust_line[side]
	if not w.welded:
		return
	var fore: VoxelPart = arm[side].fore
	var d: Vector3 = yaw_q * (tl.dir as Vector3)
	var wn := 40.0
	var hand := hand_world(side)
	var off: Vector3 = t_pos + yaw_q * (tl.o as Vector3) - hand
	off -= d * off.dot(d)
	var v := fore.velocity_at(hand) - torso.linear_velocity
	v -= d * v.dot(d)
	var m := fore.nominal_mass + w.mass
	var J := PD.clamp_len((off * wn * wn - v * 2.0 * wn) * m * dt, 1200.0 * maxf(0.3, strength) * MS * dt)
	fore.apply_impulse(J, hand - fore.global_position)
	torso.apply_central_impulse(-J * 0.5)
	var ax := PD.quat_of(w) * Vector3.UP
	var wv := w.angular_velocity - torso.angular_velocity
	wv -= ax * wv.dot(ax)
	var lever := (w.global_transform * w.center_of_mass) - hand
	var i_asm := PD.inertia_of(fore) + PD.inertia_of(w) + w.mass * lever.length_squared()
	var tq := PD.clamp_len((ax.cross(d) * wn * wn - wv * 2.0 * wn) * i_asm, 260.0 * maxf(0.3, strength) * MS * S)
	w.apply_torque_impulse(tq * dt)
	torso.apply_torque_impulse(-tq * dt * 0.5)

## A held blade is never swung round behind its own back: past the line of the shoulders the
## arm turns it back to the front, firmly (only a throw is drawn back there on purpose).
func _keep_blade_front(side: String, w: Weapon, yaw_q: Quaternion, dt: float) -> void:
	var fore: VoxelPart = arm[side].fore
	var ax := PD.quat_of(w) * Vector3.UP
	var la := yaw_q.inverse() * ax
	if la.z > -0.05:
		return
	var tgt := Vector3(la.x, la.y, 0.05)
	tgt = yaw_q * tgt.normalized()
	var turn := ax.cross(tgt)
	if turn.length_squared() < 1e-8:
		return
	var ang := ax.angle_to(tgt)
	var lever := (w.global_transform * w.center_of_mass) - hand_world(side)
	var i_asm := PD.inertia_of(fore) + PD.inertia_of(w) + w.mass * lever.length_squared()
	var wn := 18.0
	var spin := (w.angular_velocity).dot(turn.normalized())
	var alpha := turn.normalized() * (ang * wn * wn - minf(0.0, spin) * 2.0 * wn)
	var tq := PD.clamp_len(alpha * i_asm, 400.0 * MS * S * (1.0 + 0.6 * minf(6.0, w.mass)))
	var f := PD.inertia_of(fore) / i_asm
	fore.apply_torque_impulse(tq * dt * f)
	w.apply_torque_impulse(tq * dt * (1.0 - f))

func _orient_shield(w: Weapon, target_w: Vector3, t_pos: Vector3, yaw_q: Quaternion, strength: float, dt: float) -> void:
	var fwd := yaw_q * Vector3(0, 0, 1)
	var out := target_w - t_pos
	out.y = 0
	fwd = fwd.lerp(out.normalized(), 0.4).normalized()
	var desired := PD.quat_from_axes(UP.cross(fwd).normalized(), UP, fwd)
	var err := PD.rot_error(desired, PD.quat_of(w))
	var wn := 18.0
	var tq := PD.torque_for(w, err * (wn * wn) - w.angular_velocity * (2.0 * 0.9 * wn), 1.5)
	w.apply_torque_impulse(PD.clamp_len(tq, 70.0 * strength * MS * S * float(mods.strength)) * dt)

# ---------- Falling, standing, dying ----------

func set_standing(on: bool) -> void:
	if on:
		state = "stand"
		stood_at = time
	_legs_touch_ground(not on)
	_legs_apart(not on)

## Standing (and getting up) the legs are held by the support spring, not the sand; lying, they
## rest on it.
func _legs_touch_ground(on: bool) -> void:
	for side in ["L", "R"]:
		for n in ["thigh" + side, "shin" + side]:
			var p: VoxelPart = by_name[n]
			if not p.severed:
				p.collision_mask = VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS | (VoxelPart.LAYER_WORLD if on else 0)

func fall(duration: float, force := false) -> void:
	if state == "dead":
		return
	if bool(mods.get("unstoppable", false)) and not force and blood > 40.0:
		return
	state = "down"
	down_timer = duration
	set_standing(false)

## Moves the whole body (every part, its weapons) so the torso stands over `p`, at rest.
## Moves him (and what he holds) to `p` on the sand, at the height he is; with `feet_at_y`, up or
## down as well, so that his lowest sole stands at p.y (set down on a heap, a crate, a body: moved
## across at his own height he was pushed through whatever stood there, and stuck in it).
func teleport(p: Vector3, feet_at_y := false) -> void:
	var off := Vector3(p.x, 0.0, p.z) - Vector3(torso.global_position.x, 0.0, torso.global_position.z)
	if feet_at_y:
		var lo := INF
		for n in ["shinL", "shinR"]:
			var sh: VoxelPart = by_name[n]
			if not sh.severed:
				lo = minf(lo, (sh.global_transform * Vector3(0, -4 * V * S, 0)).y)
		if lo == INF:
			lo = torso.global_position.y - torso.half_ext.y
		off.y = p.y - lo
	var bodies: Array = parts.duplicate()
	for side in weapons:
		if weapons[side]:
			bodies.append(weapons[side])
	for b in bodies:
		if is_instance_valid(b):
			b.global_position += off
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
			b.snap_drawing()   # drawn there at once, not swept across

## At death's door (a party, co-op): a man whose wounds would kill him falls instead, his
## bleeding stopped, DYING_T seconds for a friend to lift him before they do. Only when the
## match says so (a friend still stands), never a beheading, and once per fall.
const LIMB_BLOW := 55.0  # the most one blow takes off a limb (a limb has 100)
const BITE_LIMB := 30.0  # and the most a bite or a claw does (two bites took both arms)
const BITE_BLEED := 0.4  # a bite's wound bleeds this much of a blade's
const BLEED_BLOW := 4.0  # the most bleeding one blow's wound starts
const GIANT_BLOW := 0.5  # a giant's blows, pulled (Combat): still the heaviest, not death in one or two
const LAYER_ABSORB := 0.06  # what each layer of armour under the struck one adds
const GLANCE_INTO := 0.35   # a weapon coming in at less than this (cosine to the plate's normal) starts to skid off
const DYING_T := 20.0
const LIFT_T := 2.5
var dying := 0.0         # seconds left at death's door (0: not there)
var spared := false      # this fall was spared: the next death is for good
var lifts := 0           # how often friends lifted him this bout (less time each time)
var spare: Callable      # the match's say: may this man be spared now?

func die(cause := "") -> void:
	if state == "dead":
		return
	if cause != "decap" and not head.severed and not spared and spare.is_valid() and spare.call(self, cause):
		_fall_dying()
		return
	state = "dead"
	set_standing(false)
	for side in ["R", "L"]:
		release(side)
	died.emit(self, cause)

func _fall_dying() -> void:
	spared = true
	dying = maxf(8.0, DYING_T - 5.0 * lifts)
	set_standing(false)
	for side in ["R", "L"]:
		release(side)
	for p in parts:
		p.bleed = 0.0
		p.artery = 0.0
		p.stump_t = 99.0
	blood = maxf(blood, 8.0)
	torso.hp = maxf(torso.hp, 6.0)
	head.hp = maxf(head.hp, 6.0)
	concussion = minf(concussion, 0.5)
	note.emit(self, "%s is at death's door" % display_name)

## A friend's hands: up from death's door with a little blood, able to fight on.
func lift() -> void:
	if dying <= 0.0:
		return
	dying = 0.0
	spared = false
	lifts += 1
	blood = maxf(blood, 35.0)
	torso.hp = maxf(torso.hp, 25.0)
	head.hp = maxf(head.hp, 25.0)
	for p in parts:
		p.bleed = 0.0
		p.artery = 0.0
	help_up()
	note.emit(self, "%s is lifted" % display_name)
	Achievements.unlock("lifted")

# ---------- Wounds ----------

## A blow lands on `part` (the same hit as the web game's applyHit: impulse, type, hardness,
## sharpness, point, dir, axis, edge, heavy...). Returns what it did.
func apply_hit(part: VoxelPart, hit: Dictionary) -> Dictionary:
	var res := {"removed": [], "severed": [], "dmg": 0.0}
	if _shield_takes(hit):
		res.blocked = true
		return res
	organs_hit = []
	var detached := part.severed
	var keep_stagger := stagger
	var keep_conc := concussion
	var cracked_before := skull_cracked
	var type: String = hit.get("type", "blunt")
	var hardness: float = hit.get("hardness", 0.3)
	var sharpness: float = hit.get("sharpness", 0.0)
	var heavy: float = clampf(hit.get("heavy", 0.0), 0.0, 1.0)
	var J: float = float(hit.get("impulse", 0.0)) * HIT_SCALE
	var inv := part.global_transform.affine_inverse()
	var lp: Vector3 = inv * (hit.point as Vector3)
	var basis_inv := part.global_transform.basis.orthonormalized().inverse()
	var ld: Vector3 = (basis_inv * (hit.dir as Vector3)).normalized()
	var la: Vector3 = (basis_inv * (hit.get("axis", hit.dir) as Vector3)).normalized()
	# Armour takes it first, where there is armour (character.js armorNear): the blow knocks
	# off the plates nearest it, the harder the more, and a bare spot is not covered any more.
	var near := [] if detached else _armor_near(part, lp, V * S * 1.7)
	var armor_f := 1.0   # what the armour left of the blow (the cap on a blow shrinks with it)
	if not near.is_empty():
		var a0: Dictionary = near[0][0]
		var h: float = Data.material(a0.mat).get("hardness", 0.6)
		# A weapon that meets the plate at a slant, or a blade that comes in flat, skids off it
		# (a spark, a scrape) and does little to the plate or the man under it; one that meets it
		# square bites.
		var on_plate: Vector3 = a0.pts[near[0][1]]
		var glance := _glance(part, on_plate, ld, type, basis_inv, hit) if hit.get("weapon", false) else 0.0
		if glance > 0.0:
			J *= 1.0 - 0.6 * glance
			if glance > 0.35:
				res.glance = glance
				res.glance_n = (part.global_transform.basis * _surface_normal(part, on_plate)).normalized()
		var force := J * (1.0 + 0.6 * heavy)   # a dent knocks a plate as a cut does; the blow's bite is another matter (armor_f)
		var gone := 0
		var reach := V * S * 1.7
		for k in near.size():
			var ad: Dictionary = near[k][0]
			var ci: int = near[k][1]
			# Every plate guards the spot it sits on until it is worn through: each blow near
			# it, from whatever side and at whatever angle, wears it (the nearest most), and
			# at plate_wear it gives and flies off. A blow carrying several plates' worth of
			# wear takes that many of the nearest at once (a hammer through a leather cap).
			var thr := plate_wear(ad.mat)
			if not ad.has("wear"):
				ad.wear = PackedFloat32Array()
				ad.wear.resize(ad.cells.size())
			ad.wear[ci] += force * (1.0 - float(near[k][2]) / reach)
			if k < int(force / thr) or ad.wear[ci] >= thr:
				_knock_plate(part, ad, ci, hit.dir, force)
				gone += 1
		if gone > 0:
			res.armor_hit = gone
		# Plate on plate: armour built thicker (the bench's second and third layers under the
		# blow) takes more of it, a step for each layer beneath the one it struck.
		# (The plates stand off the body, the outer layers furthest: how far out along the
		# blow's path the armour over the spot reaches is how many layers it went through.)
		var in_most := INF
		var out_most := -INF
		for n2 in _armor_near(part, lp, V * S * 3.4):
			var off: Vector3 = (n2[0].pts[n2[1]] as Vector3) - lp
			var along := off.dot(ld)
			if (off - ld * along).length() < V * S * 1.2:   # under the blow's line
				in_most = minf(in_most, along)
				out_most = maxf(out_most, along)
		var layers := 1 + (int(round((out_most - in_most) / (V * S))) if out_most > in_most else 0)
		var absorb := minf(0.92, 0.3 + 0.55 * h + LAYER_ABSORB * (layers - 1))
		armor_f = 1.0 - (absorb * 0.55 if type == "blunt" else absorb)
		J *= armor_f
		res.armor = true
	var bleed_before := part.bleed
	var dmg := 0.0
	var remove := []
	var vfs := part.vf * part.part_scale
	# A wound is the size of what made it: a gladius opens the same cut in a giant as in a man
	# (sized to the man it was in, every blow took a slab out of a giant).
	var wsz := clampf(float(hit.get("wsz", S)), 0.5, 4.0)
	var hollow := 0.0 if detached else _hollow(part, lp, ld, V * S * 1.6)
	if type == "edge":
		var edge_v: Vector3 = hit.get("edge", Vector3.ZERO)
		var align := abs(ld.dot((basis_inv * edge_v).normalized())) if edge_v != Vector3.ZERO else 0.5
		var eff := hardness * sharpness * (0.12 + 0.88 * pow(align, 1.5))
		dmg = J * 2.4 * eff + (J * 0.6 if align < 0.35 else 0.0)
		if align < 0.35:
			stagger = minf(1.0, stagger + J / float(mods.get("footing", 1.0)) * 0.006)
			res.slid = true
		part.bleed += dmg * 0.05 * (2.0 if hit.get("serrated", false) else 1.0)
		var big: float = maxf(1.0, S)
		# A light cut only opens the skin; the depth climbs faster than the blow (a full swing
		# of a keen blade still goes through a limb in one).
		var bite := J * eff * (1.0 + 0.8 * heavy)
		var depth: float = minf(0.3 + 0.2 * heavy, 0.011 * bite * clampf(bite / 30.0, 0.3, 1.0)) * S / pow(big, 1.5) * float(hit.get("chunk", 1.0))
		# No one blow goes through: at most a share of how thick the part is there (a light cut
		# a sixth, the hardest a little over half). Through comes from blows into the same wound,
		# each one carrying on from where the last one stopped (_wound below).
		var thick := 2.0 * (absf(ld.x) * part.half_ext.x + absf(ld.y) * part.half_ext.y + absf(ld.z) * part.half_ext.z)
		# The trunk is the hardest to cut through: ribs, spine and a body's depth of flesh (a man,
		# a beast or a monster); it takes many hard blows in one wound to halve one. The share is
		# of a body the blade's own size: a man's sword goes no deeper into a giant than into a man.
		var trunk := 0.55 if part == torso or part == head else 1.0
		depth = minf(depth, thick * minf(1.0, wsz / S) * (0.1 + 0.35 * clampf(bite / 60.0, 0.0, 1.0)) * trunk)
		var width := V * wsz * (0.75 + 0.5 * heavy)
		# A blow that cuts at all goes at least one layer of voxels deeper into the wound: shorter
		# than a voxel, the same light blows only ever scraped the same mouth of it.
		depth = maxf(depth, vfs * 1.1)
		if J * eff > 3.0 * big:
			var n := la.cross(ld)
			if n.length_squared() < 1e-4:
				n = Vector3(1, 0, 0)
			n = n.normalized()
			var span := (0.24 + 0.08 * heavy) * wsz
			# A blade landing beside an open slot slides into it (a giant's voxels are wider than
			# a man's cut: blows a hand's breadth apart on him opened a new slot each, and none
			# of them ever got through).
			if not detached:
				lp += n * _slot_beside(part, lp, ld, n, width, la, span, vfs)
			# A blade follows the wound: a second blow into an open cut starts where the first
			# one stopped, so a thick limb is chopped through blow by blow instead of each one
			# only scraping the same mouth of the wound.
			var open := 0.0 if detached else _wound(part, lp, ld, n, width, la, span, depth)
			# A slot already out of the far side of a limb too broad for the blade (a giant's
			# thigh under a man's sword: the cut was through, and the leg hung on by its sides
			# for good) widens instead of deepening: the blade in the slot takes the flesh
			# beside it, a layer a blow, until the limb is off.
			if not detached and part != torso:
				var slot := _slot(part, lp, ld, n, width, la, vfs)
				if slot.y <= 0.0:
					span = maxf(span, slot.x + depth)
			for i in part.fx.size():
				if part.alive[i] == 0:
					continue
				var d := part.local_of(i) - lp
				if abs(d.dot(n)) < width and d.dot(ld) > -V * S and d.dot(ld) < depth + open and abs(d.dot(la)) < span:
					remove.append(i)
			remove = _stop_at_bone(part, remove, lp, ld, bite, res)
	elif type == "point":
		var eff := hardness * sharpness * maxf(0.15, la.dot(ld))
		# Driven home in a thrust the point goes in deep, the body's weight behind it: a
		# longer, wider channel and the harm that goes with it (a prick of the tip did little).
		var th := clampf(float(hit.get("thrust", 0.0)), 0.0, 1.0)
		dmg = J * 2.8 * eff * (1.0 + 0.7 * th)
		part.bleed += dmg * 0.07
		var depth: float = minf(0.3 + 0.2 * heavy + 0.25 * th, 0.02 * J * eff * (1.0 + 0.8 * heavy) * (1.0 + 0.6 * th)) * S * float(hit.get("chunk", 1.0))
		# A stab or a thrown point goes in, it rarely comes out the far side: at most a share of
		# the thickness along its line (a thrown one less, the shaft takes the blow's way off;
		# a thrust more, the whole man leaning on it).
		var stab := J * eff * (1.0 + 0.8 * heavy) * (1.0 + 0.5 * th)
		var thick_p := 2.0 * (absf(la.x) * part.half_ext.x + absf(la.y) * part.half_ext.y + absf(la.z) * part.half_ext.z) * minf(1.0, wsz / S)
		depth = minf(depth, thick_p * (0.2 + 0.4 * clampf(stab / 70.0, 0.0, 1.0) + 0.25 * th) * (0.75 if hit.get("thrown", false) else 1.0) * ((0.6 + 0.25 * th) if part == torso or part == head else 1.0))
		if J * eff > 2.5:
			var r := V * wsz * (1.2 + 0.5 * heavy + 0.25 * th)
			var open := 0.0 if detached else _wound(part, lp, la, Vector3.ZERO, r, Vector3.ZERO, 0.0, depth)
			for i in part.fx.size():
				if part.alive[i] == 0:
					continue
				var d := part.local_of(i) - lp
				var along := d.dot(la)
				if along > -V * S and along < depth + open and (d - la * along).length() < r:
					remove.append(i)
			# A point goes between the ribs more often than not (a chop meets them flat): the bones
			# turn it only when it comes in weakly, a thrust hardly at all.
			remove = _stop_at_bone(part, remove, lp, la, stab * (2.2 + 2.5 * th), res)
	else:
		# A blunt blow does its harm inside: bruising, crushed flesh and broken bone. A club or a
		# hammer in earnest is as dangerous as a blade, only in a different way.
		# Hard and heavy hurts more than soft and light: a steel mace far more than a wooden stick.
		dmg = J * 1.9 * (0.55 + 0.6 * clampf(hardness, 0.0, 1.0))
		var shielded := part == head and not skull_cracked   # (as it was before this blow)
		stagger = minf(1.0, stagger + J / float(mods.get("footing", 1.0)) * 0.011)
		if part == head:
			concussion = minf(1.0, concussion + J * 0.009 * (1.6 if skull_cracked else 1.0) / sqrt(maxf(1.0, S)))
		if (part == torso or part == head) and not detached:
			_bruise_organs(part, lp, ld, J)
			_break_trunk_bones(part, lp, J, heavy, res)
		if part == torso and lp.y < 0.0 and J > 8.0 and not detached:
			stamina = maxf(0.0, stamina - J * 1.3)
			res.winded = true
		# A giant's bones are as much thicker as he is bigger: what breaks a man's thigh only
		# bruises his.
		var big := maxf(1.0, S)
		if not detached and J > 16.0 * big and not part.fractured and part != torso and part != head and randf() < (J - 14.0 * big) * 0.06 * (1.0 + heavy) / (float(mods.toughness) * big):
			_fracture(part, lp, J, res)
		# A burst (a thunder pot, powder going off) blows a crater out of the side of the part
		# turned to it, at its nearest point to where it went off (not the part's middle): as
		# wide as the blast was strong (blast_r) right against it, nothing a little way off.
		if hit.has("blast"):
			var at_b: Vector3 = inv * (hit.blast as Vector3)
			var bp: Vector3 = at_b.clamp(-part.half_ext, part.half_ext)
			var rb: float = (float(hit.blast_r) - 0.6 * at_b.distance_to(bp)) * armor_f * float(hit.get("chunk", 1.0))
			for i in (part.voxels_within(bp, rb) if rb > 0.0 else PackedInt32Array()):
				if not (shielded and part.organ[i] == Anatomy.BRAIN):
					remove.append(i)
			if not remove.is_empty():
				part.bleed += J * 0.02
				if not detached and not part.fractured and part != torso and part != head and remove.any(func(i): return part.bone[i]):
					_fracture(part, lp, J, res)
		# The crater a blow leaves: from a fair knock up, as wide as it was hard.
		elif J > 9.0 or (hollow > 0.0 and J > 6.0):
			# (Armour over the spot keeps the crater small too, else a giant's hammer took a
			# helmeted head clean off in one while the number on it said a bruise.)
			var r: float = (minf(0.09 + 0.04 * heavy, 0.03 + maxf(0.0, J - 9.0) * 0.0028 * (1.0 + heavy)) + minf(0.03, hollow * 0.3)) * wsz * armor_f * float(hit.get("pull", 1.0))
			var at := lp + ld * hollow
			# The skull spreads a blow to the head: the brain under it is shaken (bruised, the
			# concussion above), not crushed away, until the skull has cracked.
			for i in part.voxels_within(at, r):
				if not (shielded and part.organ[i] == Anatomy.BRAIN):
					remove.append(i)
			part.bleed += J * 0.02
			# A crater down into the bone of a limb has broken it.
			if not detached and not part.fractured and part != torso and part != head and remove.any(func(i): return part.bone[i]):
				_fracture(part, lp, J, res)
	# A crushing bite (or weight) smashes a crater whatever kind of blow it is; what it breaks
	# loose falls away as pieces.
	var crush: float = float(hit.get("crush", 0.0))
	if crush > 0.0:
		# From the nearest point of the part (a heavy thing's middle may be outside it).
		var cp := lp.clamp(-part.half_ext, part.half_ext)
		for i in part.voxels_within(cp, crush):
			remove.append(i)
		part.bleed += J * 0.03
	# Every cut or stab that lands takes something with it: under the threshold for a real wound
	# it still nicks a few voxels out at the point it struck, more the harder it came in.
	if remove.is_empty() and not detached and type != "blunt" and J * hardness * sharpness > 1.0:
		var rn := vfs * (0.75 + minf(1.6, J * hardness * sharpness * 0.08)) * float(hit.get("chunk", 1.0))
		for i in part.voxels_within(lp, rn):
			if not part.bone[i]:
				remove.append(i)
	if hollow > 0.0 and not detached:
		dmg *= 1.0 + minf(0.4 if type == "blunt" else 1.0, hollow / 0.1)
	if part == torso or part == head:
		stagger = minf(1.0, stagger + J / float(mods.get("footing", 1.0)) * 0.004)
	# A blow across the face near the eyes: the view closes in from the edges (players), the
	# aim wanders (everyone). It heals a little over the fight.
	if part == head and not detached and lp.z > V * S * 0.5 and absf(lp.y - V * S * 0.6) < V * S * 1.6 and J > 5.0:
		eye_hurt = minf(1.0, eye_hurt + J * (0.012 if type == "blunt" else 0.025))
	if not detached and part.parent_part and part.parent_part != torso:
		part.parent_part.flinch_t = maxf(part.parent_part.flinch_t, 0.1 + J * 0.005)
	if not detached:
		# A wrecked trunk holds him up worse: every blow rocks him more.
		stagger = minf(1.0, stagger + J / float(mods.get("footing", 1.0)) * 0.0035 * (1.0 + injury) * (1.0 + 0.8 * (1.0 - minf(1.0, stamina / 40.0))) * (1.0 + 0.8 * (1.0 - torso.function())))
		part.flinch_t = maxf(part.flinch_t, minf(0.3, 0.08 + J * 0.006))
		if push_t <= 0.0 and J > 4.0:
			push_t = 0.3
			# A fighter takes a blow and fights on: it rocks him, it does not bowl him over.
			var push: float = minf(60.0 if hit.get("thrown", false) else 32.0, J * (1.6 if hit.get("thrown", false) else 0.8)) * MS * S
			var dv: Vector3 = hit.dir
			torso.apply_central_impulse(Vector3(dv.x * push, 0, dv.z * push))
	if part.prosthetic != "":
		part.bleed = bleed_before
		dmg *= 0.5
	# A point (an arrow, a bolt, a thrust) goes into a giant as it goes into a man: flesh is
	# flesh, and its size soaks it only a little (thirty arrows left the titan at 88%: user).
	var soak := pow(S, 0.5 if type == "point" else 1.5) * float(mods.toughness)
	dmg *= part.mult / soak * (0.75 if part == torso or part == head else 1.0)
	if boss:
		dmg *= 0.6
	if part == torso or part == head:
		# (A thrust driven home goes past the cap a blow keeps to: it is the deep wound that kills.)
		# (Armour counts against a heavy blow too: a blow past the cap is capped lower for it,
		# else a club through a steel cuirass hurt as much as through a tunic.)
		dmg = minf(dmg, (16.0 if part == head else 28.0) * (1.0 + 0.7 * clampf(float(hit.get("thrust", 0.0)), 0.0, 1.0)) * part.mult / float(mods.toughness) * (0.7 if boss else 1.0) * armor_f * float(hit.get("pull", 1.0)))
	elif not detached:
		# A limb too: one blow (a dragon's bite, a rhino's horn) cannot take a whole limb's
		# worth of hurt; cutting it clean off is the blade's work (the wound above), not the
		# number's.
		dmg = minf(dmg, (BITE_LIMB if hit.get("bite", false) else LIMB_BLOW) * part.mult / float(mods.toughness) * (0.7 if boss else 1.0) * armor_f * float(hit.get("pull", 1.0)))
	# One blow opens one wound: however hard it came, the bleeding it starts is bounded (a
	# dragon's bite once bled a man white in a minute from a single wound); a cut artery is
	# its own matter (part.artery), and wound on wound still adds up.
	if not detached:
		part.bleed = minf(part.bleed, bleed_before + BLEED_BLOW * (BITE_BLEED if hit.get("bite", false) else 1.0))
	if dying > 0.0 and not detached:
		dying = maxf(0.0, dying - 2.5)   # every blow on a man at death's door hurries it
	if detached:
		stagger = keep_stagger
		concussion = keep_conc
		dmg = 0.0
	part.hp = maxf(0.0, part.hp - dmg)
	res.dmg = dmg
	# Blood runs from every cut and stab that opened the skin (a bruise does not bleed).
	if not detached and type != "blunt" and part.bleed > 0.05:
		part.add_drip(lp.clamp(-part.half_ext, part.half_ext))
	pain = minf(1.0, pain + dmg / 70.0)
	var steady: bool = bool(mods.get("unstoppable", false)) and blood > 40.0
	if concussion > 0.85 and state == "stand" and not steady:
		fall(3.0)
	if stagger > 0.95 and J >= 16.0 * maxf(1.0, S * 0.8) * float(mods.get("footing", 1.0)) and state == "stand" and not steady:
		fall(1.5 / float(mods.get("footing", 1.0)))
	if remove.is_empty() and not detached and J > 3.0:
		var bruise := type == "blunt"
		part.wound(lp, (minf(0.13, 0.05 + J * 0.003) if bruise else V * 1.6) * S, "bruise" if bruise else "blood")
	if not remove.is_empty():
		cut_force = J * hardness * sharpness * (1.0 + heavy)
		if remove.size() > 80 * 8:
			remove.sort_custom(func(a, b): return part.local_of(a).distance_squared_to(lp) < part.local_of(b).distance_squared_to(lp))
			remove = remove.slice(0, 80 * 8)
		# The skull and the depth of it: no one blow takes more than a quarter of the brain, so a
		# head is split blow after blow, not ended by one.
		if part == head and not detached:
			var cap := ceili(0.25 * float(organ_total.get(Anatomy.BRAIN, 0)))
			var brain := remove.filter(func(i): return part.organ[i] == Anatomy.BRAIN)
			if brain.size() > cap:
				brain.sort_custom(func(a, b): return part.local_of(a).distance_squared_to(lp) < part.local_of(b).distance_squared_to(lp))
				var spare := {}
				for i in brain.slice(cap):
					spare[i] = true
				remove = remove.filter(func(i): return not spare.has(i))
		# Where the blade went in, the wound bleeds from then on: a cut artery (the throat, the
		# groin, the armpit) or a torn heart pours, spurting with every beat.
		if type != "blunt" and not detached:
			# (Teeth tear, they do not open an artery: a bite's bleeding is its own, BITE_BLEED;
			# a bite in the thigh once bled a man white in seconds.)
			var cut_artery := false
			for i in (remove if not hit.get("bite", false) else []):
				if Anatomy.artery_at(part.part_name, part.fx[i], part.fy[i], part.fz[i]) and not part.bone[i]:
					cut_artery = true
					break
			if part == torso and remove.any(func(i): return part.organ[i] == Anatomy.HEART):
				cut_artery = true
			if cut_artery:
				res.artery = true
			part.open_wound(lp.clamp(-part.half_ext, part.half_ext), -ld, cut_artery, 6.0 / maxf(1.0, S))
		var voxels := part.remove_voxels(remove)
		# Nothing cut away just vanishes: the slice a blade takes, the plug a point punches
		# out, the flesh a blow crushes, all fall to the sand as pieces.
		var piece = Chunk.spawn(part, voxels, hit.dir) if not part.freeze and voxels.size() >= 1 else null
		res.removed.append({"part": part, "indices": remove, "voxels": voxels, "chunk": piece != null})
		# What is gone from the head takes sight with it, and stays gone: the view closes in
		# (players) and the aim wanders (everyone), more the more of the head is lost.
		if part == head and not detached:
			var lost := 1.0 - part.integrity
			eye_floor = maxf(eye_floor, minf(0.85, lost * 1.6))
			eye_hurt = maxf(eye_hurt, eye_floor)
			concussion = minf(1.0, concussion + float(remove.size()) / maxf(1.0, float(part.fx.size())) * 1.5)
			_check_eye()
		break_loose(part, res, hit.dir, detached)
		_check_flaps(res)
		if part == torso and not detached and type != "blunt":
			_check_belly(res)
		if not part.severed and part.integrity < (HEAD_DEATH if part == head else 0.4):
			part.hp = 0.0
	# One knock rings the head and may floor him, all it does at once (the blow, the crater, the
	# brain shaken) together; it takes another before the first has cleared, or a skull already
	# cracked, to leave him senseless (CONC_PER_BLOW).
	if not detached and not cracked_before:
		concussion = minf(concussion, maxf(keep_conc, keep_conc + CONC_PER_BLOW))
	if part == head and part.hp <= 0.0:
		die("ko")
	if part == torso and part.hp <= 0.0:
		die("wounds")
	if not organs_hit.is_empty():
		res.organs = organs_hit.map(func(o): return Anatomy.organ_name(o))
		if res.get("spilled", false) and not res.organs.has("guts"):
			res.organs.append("guts")
	res.part_name = part.part_name
	hit_taken.emit(self, res)
	return res

## The armour plates within `r` of a part-local point, nearest first: [[piece, cell index]].
## Outward from a part's surface at `lp` (its local frame): the body is rounded, so the normal
## of the ellipsoid that fills the part's box, not of the box's flat faces.
static func _surface_normal(part: VoxelPart, lp: Vector3) -> Vector3:
	var he := part.half_ext.max(Vector3.ONE * 0.005)
	var n := lp / (he * he)
	return n.normalized() if n.length_squared() > 1e-8 else Vector3.UP

## How much of a weapon's blow at the plate point `lp` skids off (0 square, 1 all of it): it
## comes in along the surface rather than into it, or (an edge) with the flat of the blade.
func _glance(part: VoxelPart, lp: Vector3, ld: Vector3, type: String, basis_inv: Basis, hit: Dictionary) -> float:
	var into := absf(ld.dot(_surface_normal(part, lp)))
	var g := clampf((GLANCE_INTO - into) / 0.25, 0.0, 1.0)
	if type == "edge":
		var ev: Vector3 = hit.get("edge", Vector3.ZERO)
		if ev != Vector3.ZERO and absf(ld.dot((basis_inv * ev).normalized())) < 0.35:
			g = maxf(g, 0.6)
	elif type == "point":
		# A point turns off a plate unless it comes in nearly square (a thrust at a breastplate
		# from the side slides round it).
		g = clampf((GLANCE_INTO + 0.15 - into) / 0.25, 0.0, 1.0)
	return g

func _armor_near(part: VoxelPart, lp: Vector3, r: float) -> Array:
	var out := []
	for ad in part.get_meta("armor", []):
		for i in ad.pts.size():
			if ad.on[i]:
				var d: float = (ad.pts[i] as Vector3).distance_to(lp)
				if d < r:
					out.append([ad, i, d])
	out.sort_custom(func(x, y): return x[2] < y[2])
	return out

## A shield in the way takes the blow: a bite, a claw, a ram, a stamp or a blade that comes at
## him through the shield he holds (on its way in, the last stretch before the spot it struck)
## lands on the shield, not on the arm behind it or the body: a knock on the shield, a jolt to
## the man, no wound.
func _shield_takes(hit: Dictionary) -> bool:
	var d: Vector3 = hit.get("dir", Vector3.ZERO)
	if d.length_squared() < 1e-6 or not (hit.get("point") is Vector3) or not alive:
		return false
	d = d.normalized()
	var p: Vector3 = hit.point
	for side in ["L", "R"]:
		var sh = weapons[side]
		if sh == null or not is_instance_valid(sh) or not sh.is_shield or sh.holder != self:
			continue
		var box: AABB = sh.local_box()
		if box.size == Vector3.ZERO:
			continue
		var inv: Transform3D = sh.global_transform.affine_inverse()
		var at = box.grow(sh.vs).intersects_segment(inv * (p - d * 0.7 * S), inv * p)
		if at == null:
			continue
		var J := float(hit.get("impulse", 0.0))
		sh.apply_impulse(d * J * 0.4, p - sh.global_position)
		# The shield pays for it as any weapon does: chipped where it was struck, split and
		# broken in the end by blows enough (Weapon.knock).
		var best := -1
		var bd := INF
		for i in sh.vox.size():
			if sh.alive[i]:
				var dd: float = (Vector3(sh.vox[i][0], sh.vox[i][1], sh.vox[i][2]) * sh.vs).distance_squared_to(at)
				if dd < bd:
					bd = dd
					best = i
		if best >= 0:
			var own_h: float = Data.material(sh.vox[best][3]).get("hardness", 0.5)
			var mult: float = Combat.current.chip_mult if Combat.current else 1.0
			var k: Dictionary = sh.knock(best, Weapon.chip_score(J * mult, own_h, float(hit.get("hardness", 0.5))))
			if not k.is_empty() and Combat.current:
				Combat.current.chip.emit({"kind": "chip", "weapon": sh, "indices": k.indices, "voxels": k.voxels, "p": p, "broke": k.broke})
		stagger = minf(1.0, stagger + J / float(mods.get("footing", 1.0)) * 0.004)
		if Combat.current:
			Combat.current.clang.emit({"p": p, "J": J, "metal": 1.0})
		return true
	return false

## How deep a wound already goes in from `lp` along `ld` (character.js wound): the farthest dead
## voxel inside the blade's slab (or the point's bore, when `n` is zero), counted only while the
## hole is open all the way from the surface (a cavity deeper in, from another cut, is not reached).
func _wound(part: VoxelPart, lp: Vector3, ld: Vector3, n: Vector3, width: float, la: Vector3, span: float, step: float) -> float:
	var seen := []
	var slab := n != Vector3.ZERO
	for i in part.fx.size():
		if part.alive[i]:
			continue
		var d := part.local_of(i) - lp
		var along := d.dot(ld)
		if along <= 0.0:
			continue
		if slab:
			if absf(d.dot(n)) >= width or absf(d.dot(la)) >= span:
				continue
		elif (d - ld * along).length() >= width:
			continue
		seen.append(along)
	seen.sort()
	var deepest := 0.0
	var gap := maxf(step, part.vf * part.part_scale * 2.0)
	for a in seen:
		if a > deepest + gap:
			break
		deepest = a
	return deepest

## How far along `n` (across the blade) a blow at `lp` has to shift to land in an open slot
## beside it: the nearest dead voxel's row within a voxel of the blow's own band, when the
## band itself has no slot (0 otherwise).
func _slot_beside(part: VoxelPart, lp: Vector3, ld: Vector3, n: Vector3, width: float, la: Vector3, span: float, vfs: float) -> float:
	var best := 0.0
	var best_d := INF
	for i in part.fx.size():
		if part.alive[i]:
			continue
		var d := part.local_of(i) - lp
		var along := d.dot(ld)
		if along <= 0.0 or along > vfs * 2.5 or absf(d.dot(la)) >= span:
			continue
		var side := d.dot(n)
		var off := absf(side)
		if off < width:
			return 0.0   # in a slot already
		if off < width + vfs * 1.1 and off < best_d:
			best_d = off
			best = side
	return best

## The slot a blow at `lp` heading `ld` lands in: x, how far along the blade (`la`) its dead
## voxels already reach, so a blow into it can widen it from there; y, how much flesh is left
## alive on the blow's own line (0: the slot is through, whatever shape the part is there).
func _slot(part: VoxelPart, lp: Vector3, ld: Vector3, n: Vector3, width: float, la: Vector3, vfs: float) -> Vector2:
	var far := 0.0
	var left := 0.0
	for i in part.fx.size():
		var d := part.local_of(i) - lp
		if d.dot(ld) <= 0.0 or absf(d.dot(n)) >= width:
			continue
		var side := absf(d.dot(la))
		if part.alive[i]:
			if side < vfs * 1.1:
				left += 1.0
		else:
			far = maxf(far, side)
	return Vector2(far, left)

## How deep an open hole goes under a blow at `lp` heading `ld` (0 on whole skin).
func _hollow(part: VoxelPart, lp: Vector3, ld: Vector3, width: float) -> float:
	var seen := []
	for i in part.fx.size():
		if part.alive[i]:
			continue
		var d := part.local_of(i) - lp
		var along := d.dot(ld)
		if along <= 0.0 or (d - ld * along).length() >= width:
			continue
		seen.append(along)
	seen.sort()
	var deepest := 0.0
	var step: float = maxf(V * S * 2.0, part.vf * part.part_scale * 2.0)
	for a in seen:
		if a > deepest + step:
			break
		deepest = a
	return deepest

## Flaps: a lump of a part cut almost free (a piece of the scalp, a slice of a thigh, a beast's
## jowl) hangs on by the few voxels left at the cut, its own little body on a loose joint,
## swinging and flapping with every move, until a blow cuts the strip it hangs by.
var flaps: Array = []
const MAX_FLAPS := 8
const FLAP_MIN := 8

func _make_flaps(part: VoxelPart, res: Dictionary) -> bool:
	var cut := []
	for r in res.removed:
		if r.part == part:
			cut.append_array(r.indices)
	var made := false
	if part.freeze or part.severed or part.hanging or cut.is_empty() or flaps.size() >= MAX_FLAPS or not part.is_inside_tree():
		return false
	var wf: int = part.grid.x
	var hf: int = part.grid.y
	var df: int = part.grid.z
	var cellmap := PackedInt32Array()
	cellmap.resize(wf * hf * df)
	for i in part.fx.size():
		if part.alive[i]:
			cellmap[(part.fx[i] * hf + part.fy[i]) * df + part.fz[i]] = i + 1
	# The lips of the cut: the flesh left within two voxels of what was just taken.
	var lips := {}
	for i in cut:
		var x: int = part.fx[i]
		var y: int = part.fy[i]
		var z: int = part.fz[i]
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					if absi(dx) + absi(dy) + absi(dz) > 2:
						continue
					var xx := x + dx
					var yy := y + dy
					var zz := z + dz
					if xx < 0 or yy < 0 or zz < 0 or xx >= wf or yy >= hf or zz >= df:
						continue
					var k := cellmap[(xx * hf + yy) * df + zz]
					if k > 0:
						lips[k - 1] = true
	if lips.is_empty():
		return false
	var lip_list := PackedInt32Array(lips.keys())
	# What would come away if the lips were gone hangs by them alone.
	for lump in part.loose_lumps(lip_list):
		# (Not the end of a limb: a lump that big is an amputation once the blade is through
		# (break_loose), not a flap; as a flap, a giant's half forearm fell off a stump that
		# never counted as cut.)
		if lump.size() < FLAP_MIN or lump.size() >= (0.6 if part == torso or part == head else 0.4) * part.alive_count or part.near_child_anchor(lump):
			continue
		var inside := {}
		for i in lump:
			inside[i] = true
		var link := PackedInt32Array()
		for i in lip_list:
			var x: int = part.fx[i]
			var y: int = part.fy[i]
			var z: int = part.fz[i]
			for nb in [[x - 1, y, z], [x + 1, y, z], [x, y - 1, z], [x, y + 1, z], [x, y, z - 1], [x, y, z + 1]]:
				if nb[0] < 0 or nb[1] < 0 or nb[2] < 0 or nb[0] >= wf or nb[1] >= hf or nb[2] >= df:
					continue
				var k := cellmap[(nb[0] * hf + nb[1]) * df + nb[2]]
				if k > 0 and inside.has(k - 1):
					link.append(i)
					break
		# Only a real strip: a few voxels, not a broad bridge of flesh.
		if link.is_empty() or link.size() > maxi(6, int(lump.size() * 0.2)):
			continue
		var idx := Array(lump)
		# Not told to the guests yet: for them it stays on the part until it drops.
		var vox := part.remove_voxels(idx, false, false)
		var ch := Chunk.spawn(part, vox, Vector3.ZERO)
		if ch == null:
			on_part_voxels_lost(part, idx, vox)
			continue
		ch.linear_velocity = part.velocity_at(ch.global_position)
		ch.angular_velocity = part.angular_velocity
		var at := Vector3.ZERO
		for i in link:
			at += part.world_of(i)
		at /= float(link.size())
		var out := ch.global_position - at
		var xa := out.normalized() if out.length() > 1e-4 else Vector3.DOWN
		var ya := xa.cross(Vector3.FORWARD if absf(xa.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var j := ConeTwistJoint3D.new()
		ch.get_parent().add_child(j)
		j.global_transform = Transform3D(Basis(xa, ya, xa.cross(ya)), at)
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(75.0))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(35.0))
		j.node_a = part.get_path()
		j.node_b = ch.get_path()
		ch.flap_of = part
		ch.flap_joint = j
		# It swings against the flesh it hangs from rather than through it.
		ch.remove_collision_exception_with(part)
		ch.collision_mask |= VoxelPart.LAYER_BODY
		flaps.append({"chunk": ch, "part": part, "link": link, "idx": idx})
		res.flapped = true
		made = true
		if flaps.size() >= MAX_FLAPS:
			break
	return made

## A flap whose strip has been cut through (most of the voxels it hung by gone) drops off.
func _check_flaps(res: Dictionary) -> void:
	for fl in flaps.duplicate():
		var ch = fl.chunk
		if not is_instance_valid(ch) or ch.flap_of == null:
			flaps.erase(fl)
			continue
		var p: VoxelPart = fl.part
		var left := 0
		for i in fl.link:
			if p.alive[i]:
				left += 1
		if left * 3 < (fl.link as PackedInt32Array).size():
			ch.let_go()
			ch.linear_velocity += Vector3(0, -0.5, 0)
			flaps.erase(fl)
			# The guests drop it now (it stayed on the part for them while it hung).
			on_part_voxels_lost(p, fl.idx, [])
			res.flap_off = true

## After voxels are gone: a lump cut off falls away; a limb cut clean through comes off; a limb
## left on a thin strip hangs.
func break_loose(part: VoxelPart, res: Dictionary, dir: Vector3, detached := false) -> void:
	var before := part.alive_count
	var cut_off = null
	for lump in part.loose_lumps():
		# The torso: a lump with limbs rooted in it (the pelvis with the legs, a shoulder with
		# its arm) comes away as a half, limbs and all; so does any big piece.
		# Only a real chop halves a man: a big lump, or one carrying a limb's root that a strong
		# blow cut free (a light nick by the shoulder once took the arm and half the chest).
		var big_lump: bool = lump.size() > 0.25 * before
		var root_cut: bool = part.near_child_anchor(lump) and lump.size() > 0.08 * before and cut_force > 14.0
		if part == torso and not detached and (big_lump or root_cut):
			_drop_half(part, lump, res, dir)
			continue
		var amputation: bool = not detached and part != torso and (part.near_child_anchor(lump) or lump.size() >= 0.4 * before or lump.size() == before)
		if amputation and (cut_off == null or lump.size() > cut_off.size()):
			cut_off = lump
		elif not amputation:
			# A lump cut loose falls as a real piece (a guest's puppet only loses the voxels).
			var idx := Array(lump)
			var vox := part.remove_voxels(idx, false)
			var piece = Chunk.spawn(part, vox, dir) if not part.freeze and idx.size() > 2 else null
			res.removed.append({"part": part, "indices": idx, "voxels": vox, "chunk": piece != null})
	if cut_off == null and not detached and part != torso and part.alive_count == 0:
		cut_off = PackedInt32Array()
	_drop_unheld(part, res)
	if cut_off != null:
		sever(part, res, cut_off)
	elif not detached and _make_flaps(part, res):
		pass   # what was nearly off hangs on as a flap; the rest of the part is whole enough
	elif not detached and part != torso and not part.hanging and part.thin_ratio() < float(mods.get("sever", 0.3)) and may_hang(part):
		hang(part, res)

## Whether a part cut thin hangs by what is left of it (a beast's one head does not: see Beast).
func may_hang(_part: VoxelPart) -> bool:
	return true

## Every part jointed onto `part` where `part` has no flesh left falls off, with all below it:
## a forearm whose elbow end of the upper arm is gone, a head on a neck cut away, a leg whose
## hip is gone. Nothing stays on a body it is not joined to by its voxels.
func _drop_unheld(part: VoxelPart, res: Dictionary) -> void:
	if part.severed:
		return
	for ch in part.child_parts.duplicate():
		if is_instance_valid(ch) and not ch.severed and not ch.missing and not part.holds_child(ch):
			var all := PackedInt32Array()
			for i in ch.fx.size():
				if ch.alive[i]:
					all.append(i)
			sever(ch, res, all)

## The same, now and then, for whatever ate away at the voxels without a blow (fire, frostbite,
## acid): the hit path checks it at once.
var _joints_t := 0.0
var _joints_seen := -1
func _check_joints(dt: float) -> void:
	_joints_t -= dt
	if _joints_t > 0.0:
		return
	_joints_t = 0.4
	if torso.freeze:
		return   # (a guest's puppet: the host says what has come off)
	# Nothing has come off any part since the last look: nothing can have come loose.
	var seen := 0
	for p in parts:
		seen += p.alive_count * 3 + (1 if p.severed else 0)
	if seen == _joints_seen:
		return
	_joints_seen = seen
	var res := {"removed": [], "severed": []}
	for p in parts:
		if is_instance_valid(p) and not p.severed and not p.missing:
			_drop_unheld(p, res)

## A half: a lump of the torso cut clean away with the limbs rooted in it. The lump becomes a
## body of its own and the limbs are jointed onto it, so a man cut through at the waist leaves
## his legs standing (for a moment) on a pelvis and goes down on his hands; cut down the middle,
## a side with its arm and leg goes one way and he the other. It is the end of him, soon.
func _drop_half(part: VoxelPart, lump: PackedInt32Array, res: Dictionary, dir: Vector3) -> void:
	var carried := []
	for ch in part.child_parts:
		if ch != head and not ch.severed and not ch.missing and part.lump_holds(lump, ch):
			carried.append(ch)
	var fraction := float(lump.size()) / maxf(1.0, part.fx.size())
	var idx := Array(lump)
	var at := {}
	for ch in carried:
		at[ch] = part.global_transform * ch.pa
	var vox := part.remove_voxels(idx, false)
	res.removed.append({"part": part, "indices": idx, "voxels": vox, "chunk": true})
	var piece = Chunk.spawn(part, vox, dir) if not part.freeze else null
	if piece:
		piece.angular_velocity = Vector3.ZERO
		piece.mass = maxf(piece.mass, part.nominal_mass * fraction)
		piece.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_BODY | VoxelPart.LAYER_DEBRIS
		piece.angular_damp = 0.3
	var names := []
	for ch in carried:
		names.append(ch.part_name)
		detach_limb(ch, res)
		if piece:
			var pieces := [ch]
			var stack := [ch]
			while not stack.is_empty():
				var c: VoxelPart = stack.pop_back()
				for cc in c.child_parts:
					pieces.append(cc)
					stack.append(cc)
			for pc in pieces:
				piece.add_collision_exception_with(pc)
			var j := PinJoint3D.new()
			add_child(j)
			j.global_position = at[ch]
			j.node_a = piece.get_path()
			j.node_b = ch.get_path()
			ch.joint = j
	# Nothing holds a half up: the whole piece, limbs and all, topples with the blow as one,
	# turning about the ground under it, and the limbs on it go slack and slide.
	if piece:
		var d := Vector3(dir.x, 0, dir.z)
		d = Vector3(1, 0, 0) if d.length_squared() < 1e-4 else d.normalized()
		var wv := UP.cross(d) * 3.5
		var bodies: Array = [piece]
		for ch in carried:
			var stack2 := [ch]
			while not stack2.is_empty():
				var c: VoxelPart = stack2.pop_back()
				bodies.append(c)
				var pm := PhysicsMaterial.new()
				pm.friction = 0.3
				c.physics_material_override = pm
				stack2.append_array(c.child_parts)
		var pivot: Vector3 = piece.global_position
		for b in bodies:
			pivot.y = minf(pivot.y, b.global_position.y - 0.2 * S)
		pivot.y = maxf(0.0, pivot.y)
		for b in bodies:
			var r: Vector3 = b.global_position - pivot
			b.linear_velocity = wv.cross(r) + d * 0.6
			b.angular_velocity = Vector3(wv.x, 0, wv.z)
	res.halved = res.get("halved", []) + names
	blood = minf(blood, 40.0)
	part.bleed += 6.0
	pain = 1.0
	stagger = 1.0
	if state == "stand":
		fall(99.0, true)

## A limb left on a strip of a few voxels does not hold for long: the thinner the strip, the
## gentler the swing that tears it off (character.js tearStrips).
static var tear_strips := false
func _tear_strips(dt: float) -> void:
	strip_clock += dt
	if strip_clock < 0.15:
		return
	strip_clock = 0.0
	for p in parts:
		if not p.hanging or p.severed or p.parent_part == null or p.freeze:
			continue
		var thin: float = p.thin_ratio()
		var w: float = (p.angular_velocity - p.parent_part.angular_velocity).length()
		var lv: float = (p.linear_velocity - p.parent_part.linear_velocity).length() / sqrt(S)
		p.hang_t += 0.15
		if p.hang_t < 0.6:
			continue
		# Nothing comes off unless the blows cut it free: a limb on a strip hangs, useless, until
		# a blade takes the last of it (it used to tear the strip off itself with a swing).
		if tear_strips and ((thin < 0.06 and (w > 5.0 or lv > 2.8)) or (thin < 0.15 and (w > 9.0 or lv > 4.5)) or (thin < 0.3 and (w > 16.0 or lv > 8.0))):
			_tear_off(p)

func _tear_off(part: VoxelPart) -> void:
	var tl = part.thin_layer
	if tl == null:
		return
	var strip := []
	for i in part.fx.size():
		if not part.alive[i]:
			continue
		var k: int = part.fx[i] if tl[0] == 0 else (part.fy[i] if tl[0] == 1 else part.fz[i])
		if k == tl[1]:
			strip.append(i)
	if strip.is_empty():
		return
	var res := {"removed": [], "severed": [], "dmg": 0.0}
	res.removed.append({"part": part, "indices": strip, "voxels": part.remove_voxels(strip)})
	var dir := part.linear_velocity.normalized() if part.linear_velocity.length_squared() > 1e-4 else Vector3.DOWN
	cut_force = 99.0
	break_loose(part, res, dir, false)
	hit_taken.emit(self, res)

func hang(part: VoxelPart, res: Dictionary) -> void:
	if part.hanging or part.severed:
		return
	part.hanging = true
	part.bleed += 3.0
	res.hanging = part
	for side in arm:
		if (part == arm[side].fore or part == arm[side].upper) and weapons[side]:
			release(side)
	if arm.has("L") and two_handed and (part == arm.L.fore or part == arm.L.upper):
		_off_hand_off_haft()
	if part == head:
		concussion = minf(1.0, concussion + 0.5)
	part.angular_damp = 2.0

## The off hand lets go of the two-handed haft: its arm is cut, hanging or broken. Still joined
## to the hammer by the hand that was gone, the stump spun round and round after it (user video,
## the forearm taken by the crocodile) and the main arm was dragged into a knot.
## The forearms pass each other (on) or knock against each other again (off): the off hand
## comes in beside the main fist on the haft, where the two would otherwise jam.
func _forearms_pass(on: bool) -> void:
	forearms_pass = on
	for a in [arm.L.fore, arm.L.upper]:
		for b in [arm.R.fore, arm.R.upper]:
			if a == arm.L.upper and b == arm.R.upper:
				continue
			if on:
				a.add_collision_exception_with(b)
			else:
				a.remove_collision_exception_with(b)

func _off_hand_off_haft() -> void:
	if weapon_joints.L:
		weapon_joints.L.queue_free()
		weapon_joints.L = null
	two_handed = false
	two_front = null
	two_gap = null

## Cut through: the stump side stays on (removed from the falling piece), the piece with
## whatever hangs from it is no longer his.
func sever(part: VoxelPart, res: Dictionary, keep: PackedInt32Array) -> void:
	if part.severed:
		return
	var kept := {}
	for i in keep:
		kept[i] = true
	var stump_side := []
	for i in part.fx.size():
		if part.alive[i] and not kept.has(i):
			stump_side.append(i)
	if not stump_side.is_empty() and stump_side.size() < part.alive_count:
		res.removed.append({"part": part, "indices": stump_side, "voxels": part.remove_voxels(stump_side)})
	detach_limb(part, res)

func detach_limb(part: VoxelPart, res: Dictionary) -> void:
	var pieces := []
	var walk := func(p: VoxelPart, f: Callable) -> void:
		pieces.append(p)
		for c in p.child_parts:
			f.call(c, f)
	walk.call(part, walk)
	for p in pieces:
		p.severed = true
		p.hp = 0.0
		p.collision_layer = VoxelPart.LAYER_DEBRIS
		p.collision_mask = VoxelPart.LAYER_WORLD | VoxelPart.LAYER_BODY | VoxelPart.LAYER_WEAPON | VoxelPart.LAYER_DEBRIS
	# The piece still overlaps the stump it came off: meeting its owner's body at once, the
	# solver flung it across the arena. It falls clear first, then it is a thing in the world.
	if is_inside_tree():
		var me := weakref(self)   # (weak: he may be gone, a round over, before it runs)
		get_tree().create_timer(0.7, false, true).timeout.connect(func():
			var f = me.get_ref()
			if f == null:
				return
			for p in pieces:
				if not is_instance_valid(p):
					continue
				for o in f.parts:
					if is_instance_valid(o) and not pieces.has(o):
						p.remove_collision_exception_with(o))
	if part.joint:
		part.joint.queue_free()
		part.joint = null
	if part.parent_part:
		part.parent_part.stump = true
		part.parent_part.add_drip(part.parent_part.anchor_point(part))
		part.parent_part.stump_t = 0.0
	for side in arm:
		if pieces.has(arm[side].fore) and weapons[side]:
			release(side)
	if arm.has("L") and two_handed and pieces.has(arm.L.fore):
		_off_hand_off_haft()
	res.severed.append(part)
	Physique.reshape(self, part)
	on_severed(part)

## What losing a part means (a man dies without his head; a hydra has others).
func on_severed(part: VoxelPart) -> void:
	if part == head:
		die("decap")

signal voxels_lost(fighter: Fighter, part_index: int, indices: Array, voxels: Array)

func on_part_voxels_lost(part: VoxelPart, indices: Array, out: Array) -> void:
	if part == torso or part == head:
		_organ_lost(part, indices)
	voxels_lost.emit(self, parts.find(part), indices, out)

# ---------- Organs ----------
# What is inside (Anatomy): each organ as voxels of the torso or the head. What is lost of each
# decides what it does to him: a torn heart kills in seconds, the lungs take his breath, the
# liver bleeds hard, a cut spinal cord takes the legs (or the arms too, high up), the brain
# fells him. A hard blunt blow bruises what lies under it without breaking the skin.

var organ_total := {}     # organ id -> voxels it has
var organ_lost := {}      # organ id -> voxels lost
var organ_bruise := {}    # organ id -> 0..1 of harm done inside by blunt blows
var organs_hit: Array = []  # the organs the blow being dealt with reached (apply_hit's res)
var heart_t := -1.0       # seconds left to live once the heart is torn (-1: whole)
var cord_legs := 1.0      # how much the spinal cord still carries to the legs, 0..1
var cord_arms := 1.0      # and to the arms (cut above the shoulder blades)

func _count_organs() -> void:
	organ_total = {}
	for p in [torso, head]:
		for i in p.organ.size():
			var o: int = p.organ[i]
			if o != Anatomy.NONE:
				organ_total[o] = int(organ_total.get(o, 0)) + 1

## 0..1: how much of an organ is left whole (voxels and bruising both).
## Most of his head gone, or most of his brain: no man lives through that (he lay on the sand
## "alive" and the bout never ended). Short of it a split head rings him, blinds him, fells
## him; it does not end him: that takes blow after blow.
func _head_ruined() -> bool:
	if head.severed or get("kind") == "beast":   # a beast's heads are its own (beast.gd)
		return false
	return brain_lost() >= BRAIN_DEATH or head.integrity < HEAD_DEATH

const BRAIN_DEATH := 0.7   # the share of the brain torn away that kills
const HEAD_DEATH := 0.35   # the share of the head left that still lives

## 0..1: how much of the brain is torn away (bruising rings him, it does not kill).
func brain_lost() -> float:
	var nb: int = organ_total.get(Anatomy.BRAIN, 0)
	return float(organ_lost.get(Anatomy.BRAIN, 0)) / float(nb) if nb > 0 else 0.0

func organ_health(id: int) -> float:
	var n: int = organ_total.get(id, 0)
	if n == 0:
		return 1.0
	return clampf(1.0 - float(organ_lost.get(id, 0)) / float(n) - float(organ_bruise.get(id, 0.0)), 0.0, 1.0)

## Both lungs together: how much breath he can still draw.
func lungs() -> float:
	return (organ_health(Anatomy.LUNG_R) + organ_health(Anatomy.LUNG_L)) * 0.5

func _organ_lost(part: VoxelPart, indices: Array) -> void:
	var lost := {}
	for i in indices:
		var o: int = part.organ[i]
		if o != Anatomy.NONE:
			lost[o] = int(lost.get(o, 0)) + 1
	if lost.is_empty():
		return
	for o in lost:
		organ_lost[o] = int(organ_lost.get(o, 0)) + lost[o]
		if not organs_hit.has(o):
			organs_hit.append(o)
	# What runs out of each (into the torso's bleeding), as much as was torn.
	var n_heart: int = lost.get(Anatomy.HEART, 0)
	var n_lung: int = lost.get(Anatomy.LUNG_R, 0) + lost.get(Anatomy.LUNG_L, 0)
	torso.bleed += n_heart * 2.5 + lost.get(Anatomy.LIVER, 0) * 0.7 + n_lung * 0.2 + lost.get(Anatomy.STOMACH, 0) * 0.3 + lost.get(Anatomy.GUTS, 0) * 0.15
	if n_heart > 0 and heart_t < 0.0 and organ_health(Anatomy.HEART) < 0.75:
		# A big beast's heart takes longer to stop than a man's.
		heart_t = (3.0 if organ_health(Anatomy.HEART) > 0.4 else 1.2) * clampf(torso.nominal_mass / 32.0, 1.0, 6.0)
	if n_lung > 0:
		stamina = minf(stamina, breath_cap())
	if lost.has(Anatomy.BRAIN):
		# As much as the share of it torn (by the voxel, a nick of the brain rang him senseless).
		concussion = minf(1.0, concussion + 2.0 * float(lost[Anatomy.BRAIN]) / maxf(1.0, float(organ_total.get(Anatomy.BRAIN, 1))))
	if lost.has(Anatomy.SPINE):
		_read_cord()

## Where the spinal cord is cut through: a level of the spine (its 2 x 2 voxels) with 3 of 4
## gone severs it there. Below the shoulder blades it takes the legs; above them the arms
## weaken as well. Nicked, it only weakens what is below.
func _read_cord() -> void:
	var levels := {}
	for i in torso.organ.size():
		if torso.organ[i] == Anatomy.SPINE and not torso.alive[i]:
			levels[torso.fy[i]] = int(levels.get(torso.fy[i], 0)) + 1
	var legs := 1.0
	var arms := 1.0
	for y in levels:
		var gone: int = levels[y]
		if gone >= 3:
			legs = 0.0
			if y >= 16:
				arms = minf(arms, 0.35)
		else:
			legs = minf(legs, 1.0 - 0.2 * gone)
	cord_legs = minf(cord_legs, legs)
	cord_arms = minf(cord_arms, arms)

## The top of his breath: torn lungs fill no further.
func breath_cap() -> float:
	return 100.0 * (0.3 + 0.7 * lungs()) * (1.0 - 0.06 * mini(5, ribs_broken)) * float(mods.get("wind", 1.0))

## A blast's shock through the trunk or the skull (Throwables.blast): every organ in it is
## bruised a little, the lungs worst (they burst), the brain rung like a bell.
func blast_shock(part: VoxelPart, J: float) -> void:
	if J < 6.0 or part.severed:
		return
	var k := minf(0.4, (J - 6.0) * 0.014) / sqrt(maxf(1.0, float(mods.toughness)))
	var seen := {}
	for i in part.organ.size():
		var o: int = part.organ[i]
		if o == Anatomy.NONE or Anatomy.is_bone(o) or seen.has(o) or not part.alive[i]:
			continue
		seen[o] = true
		var kk := k * (1.5 if o == Anatomy.LUNG_R or o == Anatomy.LUNG_L else 1.0)
		organ_bruise[o] = minf(0.9, float(organ_bruise.get(o, 0.0)) + kk)
		match o:
			Anatomy.LIVER, Anatomy.STOMACH, Anatomy.GUTS:
				torso.bleed += kk * 2.0
				pain = minf(1.0, pain + kk * 0.5)
			Anatomy.HEART:
				torso.bleed += kk * 2.0
			Anatomy.BRAIN:
				concussion = minf(1.0, concussion + kk)
	if seen.has(Anatomy.LUNG_R) or seen.has(Anatomy.LUNG_L):
		stamina = minf(stamina, breath_cap())

## A hard blunt blow to the trunk or the head bruises the organ under it (no skin broken): a
## kicked liver bleeds inside, crushed ribs take the breath, a skull blow shakes the brain.
func _bruise_organs(part: VoxelPart, lp: Vector3, ld: Vector3, J: float) -> void:
	if J < 12.0:
		return
	var best: int = Anatomy.NONE
	var bd := INF
	var deep := lp + ld * part.half_ext.length() * 0.45
	for i in part.organ.size():
		var o: int = part.organ[i]
		if o == Anatomy.NONE or Anatomy.is_bone(o) or not part.alive[i]:
			continue
		var d := part.local_of(i).distance_squared_to(deep)
		if d < bd:
			bd = d
			best = o
	if best == Anatomy.NONE or bd > pow(part.half_ext.length() * 0.6, 2.0):
		return
	var k := minf(0.3, (J - 12.0) * 0.008) / float(mods.toughness)
	organ_bruise[best] = minf(0.9, float(organ_bruise.get(best, 0.0)) + k)
	if not organs_hit.has(best):
		organs_hit.append(best)
	match best:
		Anatomy.LIVER, Anatomy.STOMACH, Anatomy.GUTS:
			torso.bleed += k * 6.0
			pain = minf(1.0, pain + k)
		Anatomy.LUNG_R, Anatomy.LUNG_L:
			stamina = minf(stamina, breath_cap())
		Anatomy.HEART:
			torso.bleed += k * 3.0
		Anatomy.BRAIN:
			concussion = minf(1.0, concussion + k * 0.5)

## The belly opened wide enough to let the guts out: they come out through the wound as a chain
## of their own voxels, hanging and swinging (GutRope; with gore reduced they are only lost). It
## bleeds hard, it hurts, it takes the breath. Once per body. A beast's belly the same.
signal guts_spilled(fighter: Fighter, groups: Array, at: Vector3, out: Vector3)
signal guts_pulled(fighter: Fighter, group: Array)
var guts_queue: Array = []        # the lengths still in the belly, nearest the wound first
var gut_rope: GutRope = null
const SPILL_EXPOSED := 24
var guts_out := false

func _cells(p: VoxelPart) -> Dictionary:
	if not p.has_meta("cells"):
		var m := {}
		for i in p.fx.size():
			m[Vector3i(p.fx[i], p.fy[i], p.fz[i])] = i
		p.set_meta("cells", m)
	return p.get_meta("cells")

const _NB := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

func _check_belly(res: Dictionary) -> void:
	if guts_out or torso.severed or not organ_total.has(Anatomy.GUTS):
		return
	var cells := _cells(torso)
	var exposed := []
	var out := Vector3.ZERO
	for i in torso.organ.size():
		if torso.organ[i] != Anatomy.GUTS or not torso.alive[i]:
			continue
		var c := Vector3i(torso.fx[i], torso.fy[i], torso.fz[i])
		var open := false
		for d in _NB:
			var j = cells.get(c + d)
			if j != null and not torso.alive[j]:
				open = true
				out += Vector3(d)
		if open:
			exposed.append(i)
	# Bared over enough of them, and wide open (a long slash, not a deep stab's narrow hole).
	if exposed.size() < maxi(SPILL_EXPOSED, int(organ_total.get(Anatomy.GUTS, 0) * 0.07)):
		return
	var lo_c := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi_c := -lo_c
	for i in exposed:
		var c := Vector3i(torso.fx[i], torso.fy[i], torso.fz[i])
		lo_c = Vector3i(mini(lo_c.x, c.x), mini(lo_c.y, c.y), mini(lo_c.z, c.z))
		hi_c = Vector3i(maxi(hi_c.x, c.x), maxi(hi_c.y, c.y), maxi(hi_c.z, c.z))
	var span := hi_c - lo_c
	var ax := out.abs()
	var wide := maxi(span.y, span.z) if ax.x >= ax.y and ax.x >= ax.z else (maxi(span.x, span.z) if ax.y >= ax.z else maxi(span.x, span.y))
	if wide < 6:
		return
	guts_out = true
	var centre := Vector3.ZERO
	for i in exposed:
		centre += torso.local_of(i)
	centre /= float(exposed.size())
	var lout := out.normalized() if out.length_squared() > 1e-6 else Vector3(0, 0, 1)
	# The coils nearest the wound first, in links of a few voxels each.
	var guts := []
	for i in torso.organ.size():
		if torso.organ[i] == Anatomy.GUTS and torso.alive[i]:
			guts.append(i)
	guts.sort_custom(func(a, b): return torso.local_of(a).distance_squared_to(centre) < torso.local_of(b).distance_squared_to(centre))
	guts = guts.slice(0, GutRope.MAX_LINKS * GutRope.LINK_VOX)
	var groups := []
	for k in range(0, guts.size(), GutRope.LINK_VOX):
		groups.append(guts.slice(k, k + GutRope.LINK_VOX))
	# A first length comes out at once; the rest stays in until it is pulled out (pull_guts).
	guts_queue = groups.slice(GutRope.FIRST_LINKS)
	groups = groups.slice(0, GutRope.FIRST_LINKS)
	var flat := []
	for g in groups:
		flat += g
	_organ_lost(torso, flat)
	torso.bleed += 3.0
	pain = 1.0
	stamina = maxf(0.0, stamina - 30.0)
	stagger = minf(1.0, stagger + 0.5)
	res.spilled = true
	var at := torso.global_transform * (centre + lout * torso.vf * torso.part_scale * 2.0)
	var wout := (torso.global_transform.basis.orthonormalized() * lout).normalized()
	spill_guts(groups, at, wout)
	guts_spilled.emit(self, groups, at, wout)

## Takes the links out of the torso: a hanging chain with gore on, plainly gone without.
func spill_guts(groups: Array, at: Vector3, out: Vector3) -> void:
	guts_out = true
	if Anatomy.gore() == "full":
		gut_rope = GutRope.spill(self, groups, at, out)
		if gut_rope:
			return
	var flat := []
	for g in groups:
		flat += g
	torso.remove_voxels(flat, true, false)

## The chain hanging out of him pulled taut (GutRope): another length slides out of the wound.
func pull_guts() -> void:
	if guts_queue.is_empty():
		return
	var g: Array = guts_queue.pop_front()
	_organ_lost(torso, g)
	torso.bleed += 0.4
	pain = minf(1.0, pain + 0.15)
	if gut_rope and is_instance_valid(gut_rope):
		gut_rope.pull(g)
	else:
		torso.remove_voxels(g, true, false)
	guts_pulled.emit(self, g)

## Every tick (the host): the heart's last seconds, a brain too broken to go on.
func _organs_tick(dt: float) -> void:
	if state == "dead":
		return
	if heart_t >= 0.0:
		heart_t -= dt
		if heart_t <= 0.0:
			die("heart")
			return
	# (A many-headed monster lives on without one of its heads' brains.)
	var many: bool = get("sp") is Dictionary and get("sp").get("multiHead", false)
	if brain_lost() >= BRAIN_DEATH and not many:
		die("brain")

# ---------- Bones ----------
# The skeleton (the limbs' bones from body.json, the trunk's and the skull from Anatomy): a blade
# too weak to chop bone stops at it, and hard blunt blows break bones: a limb hangs loose at its
# joint (an open break shows the bone), cracked ribs take the breath, a cracked skull makes every
# blow to the head ring worse, a broken pelvis half takes the legs.

const BONE_BITE := 16.0   # a blow's bite (impulse x keenness) that chops clean through bone
var ribs_broken := 0
var skull_cracked := false
var pelvis_f := 1.0

## Of the voxels a cut or a stab would take, bone gives way only as far as the blow is strong:
## a blow at BONE_BITE chops all the bone in its way; a weaker one a share of it (the nearest
## first, a light one barely notches it), and nothing beyond the last bone it got through.
func _stop_at_bone(part: VoxelPart, remove: Array, lp: Vector3, ld: Vector3, bite: float, res: Dictionary) -> Array:
	var bones := []
	for i in remove:
		if part.bone[i]:
			bones.append([(part.local_of(i) - lp).dot(ld), i])
	if bones.is_empty():
		return remove
	res.bone = true
	var f := clampf((bite / (BONE_BITE * S) - 0.2) / 0.8, 0.0, 1.0)
	if f >= 1.0:
		return remove
	bones.sort_custom(func(x, y): return x[0] < y[0])
	var n := maxi(1 if bite >= BONE_BITE * S * 0.12 else 0, ceili(bones.size() * f))
	# How deep the blow gets: through the bones it chops, up to the first one it does not.
	var stop: float = bones[n][0] if n < bones.size() else INF
	var out := []
	for i in remove:
		var a := (part.local_of(i) - lp).dot(ld)
		if part.bone[i]:
			if a < stop or (n > 0 and a <= bones[n - 1][0]):
				out.append(i)
		elif a < stop:
			out.append(i)
	return out

## A limb's bone breaks: it works at a tenth (VoxelPart.function), the joint gives sideways as the
## broken bone lets it, and a hard enough blow opens the skin over the break to the bone.
func _fracture(part: VoxelPart, lp: Vector3, J: float, res: Dictionary) -> void:
	part.fractured = true
	part.bleed += 0.5
	part.wound(lp, minf(0.16, 0.08 + J * 0.002) * S, "bruise")
	res.fractured = part
	var j = part.joint
	if j is Generic6DOFJoint3D:
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, j.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT) - 0.5)
		j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, j.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) + 0.5)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, j.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT) - 0.7)
		j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, j.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) + 0.7)
	if J >= 28.0:
		_open_break(part, lp)
	# A broken arm cannot hold on: what was in its hand falls, and an off hand on a two-handed
	# haft lets go of it.
	for side in ["L", "R"]:
		if not arm.has(side):
			continue   # (a beast's legs are not arms)
		if part == arm[side].upper or part == arm[side].fore:
			if side == "L" and two_handed:
				_off_hand_off_haft()
			elif weapons[side]:
				release(side)

## The skin and flesh between the broken bone and where the blow landed burst open: the bone shows.
func _open_break(part: VoxelPart, lp: Vector3) -> void:
	var b := -1
	var bd := INF
	for i in part.fx.size():
		if part.alive[i] and part.bone[i]:
			var d := part.local_of(i).distance_squared_to(lp)
			if d < bd:
				bd = d
				b = i
	if b < 0:
		return
	var from := part.local_of(b)
	var surf := lp.clamp(-part.half_ext, part.half_ext)
	var r := part.vf * part.part_scale * 1.3
	var gone := []
	for i in part.fx.size():
		if not part.alive[i] or part.bone[i]:
			continue
		var q := part.local_of(i)
		var seg := surf - from
		var t := clampf((q - from).dot(seg) / maxf(1e-6, seg.length_squared()), 0.0, 1.0)
		if q.distance_to(from + seg * t) < r:
			gone.append(i)
	if not gone.is_empty():
		part.remove_voxels(gone)
		part.bleed += 1.5
		part.set_meta("open_break", true)

## Hard blunt blows to the trunk crack ribs (high) or the pelvis (low); to the head, the skull.
func _break_trunk_bones(part: VoxelPart, lp: Vector3, J: float, heavy: float, res: Dictionary) -> void:
	var tough := float(mods.toughness)
	if part == head:
		if not skull_cracked and J > 20.0 and randf() < (J - 18.0) * 0.05 * (1.0 + heavy) / tough:
			skull_cracked = true
			res.broke = "skull"
			concussion = minf(1.0, concussion + 0.2)
		return
	var hy := part.half_ext.y
	if lp.y > -hy * 0.05 and J > 18.0 and randf() < (J - 16.0) * 0.05 * (1.0 + heavy) / tough:
		ribs_broken += 2 if J > 32.0 else 1
		res.broke = "ribs"
		pain = minf(1.0, pain + 0.25)
		stamina = minf(stamina, breath_cap())
	elif lp.y < -hy * 0.6 and pelvis_f > 0.5 and J > 24.0 and randf() < (J - 22.0) * 0.04 * (1.0 + heavy) / tough:
		pelvis_f = 0.5
		res.broke = "pelvis"
		pain = minf(1.0, pain + 0.4)

## Freezes every body: a guest only draws what the host simulates.
func make_puppet() -> void:
	for p in parts:
		p.freeze = true
		p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	for w in weapons.values():
		if w:
			w.freeze = true
			w.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

# ---------- Network ----------

## Positions and rotations of every part, for guests to draw.
## Every part's place, seven floats each (position, rotation): a third of the bytes the nested
## arrays took, so the host can send it more often.
func snapshot() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(parts.size() * 7)
	var i := 0
	for p in parts:
		var t: Transform3D = p.global_transform
		var q := t.basis.get_rotation_quaternion()
		out[i] = t.origin.x
		out[i + 1] = t.origin.y
		out[i + 2] = t.origin.z
		out[i + 3] = q.x
		out[i + 4] = q.y
		out[i + 5] = q.z
		out[i + 6] = q.w
		i += 7
	return out

func apply_snapshot(s) -> void:
	if s is PackedFloat32Array:
		for i in mini(s.size() / 7, parts.size()):
			var o := i * 7
			parts[i].global_transform = Transform3D(Basis(Quaternion(s[o + 3], s[o + 4], s[o + 5], s[o + 6]).normalized()), Vector3(s[o], s[o + 1], s[o + 2]))
		return
	for i in mini(s.size(), parts.size()):
		var a: Array = s[i]
		parts[i].global_transform = Transform3D(Basis(Quaternion(a[3], a[4], a[5], a[6])), Vector3(a[0], a[1], a[2]))

func status() -> Dictionary:
	return {"blood": snappedf(blood, 0.1), "stamina": snappedf(stamina, 0.1), "state": state, "hp": parts.map(func(p): return snappedf(p.hp, 0.1))}

## The same on the wire: [blood, stamina, state, hp of each part], a fraction of the bytes.
func status_packed() -> Array:
	var hp := PackedFloat32Array()
	hp.resize(parts.size())
	for i in parts.size():
		hp[i] = parts[i].hp
	return [snappedf(blood, 0.1), snappedf(stamina, 0.1), state, hp, snappedf(dying, 0.1), 1 if two_handed else 0]

func apply_status(s) -> void:
	if s is Array:
		if s.size() < 4:
			return
		blood = maxf(0.0, float(s[0]))
		stamina = maxf(0.0, float(s[1]))
		if ["stand", "down", "dead", "rising"].has(String(s[2])):
			state = String(s[2])
		var ph = s[3]
		if ph is PackedFloat32Array:
			for i in mini(ph.size(), parts.size()):
				parts[i].hp = ph[i]
		if s.size() > 4:
			dying = maxf(0.0, float(s[4]))
		if s.size() > 5:
			net_two_handed = int(s[5]) == 1
		return
	blood = s.get("blood", blood)
	stamina = s.get("stamina", stamina)
	state = s.get("state", state)
	var hps: Array = s.get("hp", [])
	for i in mini(hps.size(), parts.size()):
		parts[i].hp = hps[i]

## How far from death he is, 0..1 (the enemy's health plate): whatever ends him soonest, of the
## head, the torso, the blood running out, the brain (BRAIN_DEATH of it torn is death) and a torn
## heart's last seconds; and nothing once he is beaten (out cold, the bout is over). The plate
## read the head, the torso and the blood only, and a man went down for good with a third of it
## left on it (user: the bar is not accurate).
func vitality() -> float:
	if not alive or is_beaten():
		return 0.0
	return clampf(minf(minf(minf(head.hp, torso.hp), blood) / 100.0, organ_vitality()), 0.0, 1.0)

## The organs' share of it: the brain torn toward BRAIN_DEATH, a torn heart's seconds running out.
func organ_vitality(brain := true) -> float:
	var v := 1.0 - brain_lost() / BRAIN_DEATH if brain else 1.0
	if heart_t >= 0.0:
		v = minf(v, 0.2 * minf(1.0, heart_t / 3.0))
	return v

func total_hp() -> float:
	var t := 0.0
	for p in parts:
		t += p.hp
	return t
