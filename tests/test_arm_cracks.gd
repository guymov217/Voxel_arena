extends Node
## A player's arm (user: his hands broke far too easily, from one blow, and he was left with
## nothing to fight with): a sound arm bone only cracks from a single blow, however hard, and it
## breaks through only under a second, separate blow, not one in the same flurry; a hairline crack
## mends between bouts; the bots' arms, a player's legs and a player at Extreme as they were.

var t

const FAIR := 19.0   # a fair knock: it cracks a bone now and then and takes little of the arm away

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match(difficulty := 0.5) -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "difficulty": difficulty}, "decrees": [], "hazards": [], "headless": true, "seed": 5})
	return m

## One blunt blow of `J` on the front of `p`.
func _blow(v: Fighter, p: VoxelPart, J: float) -> void:
	p.hp = 1000.0
	var gt := p.global_transform
	var bz := gt.basis.orthonormalized() * Vector3(0, 0, 1)
	v.apply_hit(p, {"impulse": J, "type": "blunt", "hardness": 0.9, "heavy": 0.0, "point": gt * Vector3(0, 0, p.half_ext.z), "dir": -bz})
	await _steps(3)

## Fair blows on `p` until its bone cracks (at most `n`).
func _crack(v: Fighter, p: VoxelPart, n := 40) -> int:
	var k := 0
	while p.fracture == 0 and k < n:
		await _blow(v, p, FAIR)
		k += 1
	return k

## Fair blows on `p` until it is broken through (at most `n`).
func _snap(v: Fighter, p: VoxelPart, n := 40) -> int:
	var k := 0
	while not p.fractured and k < n:
		await _blow(v, p, FAIR)
		k += 1
	return k

func _grace_steps() -> int:
	return int(Fighter.ARM_CRACK_GRACE * Engine.physics_ticks_per_second) + 8

func test_a_players_sound_arm_only_cracks_from_one_blow() -> void:
	var m := _match()
	await _steps(30)
	var f: Fighter = m.me.f
	t.check(f.player and f.sturdy_arms, "a player's arms are the sturdy kind")
	var sword = f.weapons.R
	t.check(sword != null, "he has a sword in his right hand")
	await _blow(f, f.arm.R.fore, 200.0)
	t.check(f.arm.R.fore.fracture == 1 and not f.arm.R.fore.fractured, "a crushing blow on the forearm only cracks it (level %d)" % f.arm.R.fore.fracture)
	t.check(not f.arm_broken("R") and f.weapons.R == sword, "the arm is not broken and the sword is in his hand")
	t.check(f.arm_func("R") > 0.4, "the cracked arm still works (%.2f)" % f.arm_func("R"))
	await _blow(f, f.arm.R.upper, 120.0)
	t.check(f.arm.R.upper.fracture == 1 and not f.arm.R.upper.fractured, "so does the upper arm (level %d)" % f.arm.R.upper.fracture)
	m.queue_free()

func test_a_cracked_arm_is_not_broken_by_the_next_blow_of_the_flurry_but_by_one_after() -> void:
	seed(7)
	var m := _match()
	await _steps(30)
	var f: Fighter = m.me.f
	var fo: VoxelPart = f.arm.R.fore
	var sword = f.weapons.R
	# (Fair blows, none so hard it craters the arm away: this is about the bone.)
	await _crack(f, fo)
	t.check(fo.fracture == 1 and f.weapons.R == sword, "cracked by a fair blow, and the sword is still in his hand")
	# The flurry: blow after blow, every one of them able to break it.
	for i in 10:
		await _blow(f, fo, FAIR)
	t.check(fo.fracture == 1 and not fo.fractured and not f.arm_broken("R"), "the blows that follow in the same flurry do not break it (level %d)" % fo.fracture)
	await _steps(_grace_steps())
	await _snap(f, fo)
	t.check(fo.fracture >= 2 and f.arm_broken("R"), "a blow after the flurry breaks it through (level %d)" % fo.fracture)
	t.check(f.weapons.R == null, "and the sword is out of the hand")
	m.queue_free()

func test_a_blade_that_only_nicks_a_cracked_bone_does_not_break_it() -> void:
	var m := _match()
	await _steps(30)
	var f: Fighter = m.me.f
	var fo: VoxelPart = f.arm.R.fore
	seed(11)
	await _crack(f, fo)
	t.check(fo.fracture == 1, "cracked")
	await _steps(_grace_steps())
	# (A cut that takes a notch of the bone: a share of it below ARM_CRACK_CUT.)
	var res := {}
	var bones := []
	for i in fo.bone.size():
		if fo.alive[i] == 1 and fo.bone[i]:
			bones.append(i)
	t.check(bones.size() > 6, "the forearm has a bone to cut (%d voxels)" % bones.size())
	var notch := bones.slice(0, maxi(1, int(bones.size() * 0.15)))
	f._edge_on_bone(fo, notch, Vector3.ZERO, Vector3(0, 0, -1), 30.0, res)
	t.check(not f.arm_broken("R") and fo.fracture == 1, "a nick of 15%% of the cracked bone leaves it cracked (level %d)" % fo.fracture)
	var deep := bones.slice(0, maxi(2, int(bones.size() * 0.4)))
	f._edge_on_bone(fo, deep, Vector3.ZERO, Vector3(0, 0, -1), 30.0, res)
	t.check(f.arm_broken("R"), "a cut through 40%% of it breaks it through (level %d)" % fo.fracture)
	m.queue_free()

func test_a_bot_arm_a_players_leg_and_extreme_are_as_they_were() -> void:
	var m := _match()
	await _steps(30)
	var f: Fighter = m.me.f
	# A bot's arm: one crushing blow breaks it through.
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0.1, 4), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	var v: Fighter = e.f
	t.check(not v.sturdy_arms, "a bot's arms are not the sturdy kind")
	await _steps(30)
	await _blow(v, v.arm.R.fore, 200.0)
	t.check(v.arm_broken("R"), "a crushing blow breaks a bot's forearm through at once")
	# A player's leg: as before.
	await _blow(f, f.by_name.shinL, 60.0)
	t.check(f.by_name.shinL.fractured, "a player's leg breaks as it did")
	m.queue_free()
	# Extreme: the old rules.
	var mx := _match(1.0)
	await _steps(30)
	var fx: Fighter = mx.me.f
	t.check(fx.player and not fx.sturdy_arms, "at Extreme a player's arms are not the sturdy kind")
	await _blow(fx, fx.arm.R.fore, 200.0)
	t.check(fx.arm_broken("R"), "and one crushing blow breaks his forearm through")
	mx.queue_free()

func test_a_hairline_crack_mends_between_bouts_but_a_break_stays() -> void:
	var m := _match()
	await _steps(30)
	var f: Fighter = m.me.f
	seed(13)
	await _crack(f, f.arm.R.fore)
	await _blow(f, f.by_name.shinL, 60.0)
	t.check(f.arm.R.fore.fracture == 1 and f.by_name.shinL.fractured, "a crack in the arm and a broken shin")
	var snap := Body.snapshot(f)
	t.check(not snap.fractures.has("forearmR"), "the crack in the arm is not carried on to the next bout")
	t.check(snap.fractures.has("shinL"), "the broken shin is")
	await _steps(_grace_steps())
	await _snap(f, f.arm.R.fore)
	t.check(f.arm_broken("R"), "the arm broken through")
	t.check(Body.snapshot(f).fractures.has("forearmR"), "a broken arm is carried on until the physician sets it")
	m.queue_free()

## His weapon arm out and his good hand on a shield (user: he lived on and could do nothing but run):
## G lets the shield go and takes the sword lying by him.
func test_with_the_sword_arm_out_g_swaps_the_shield_for_the_sword() -> void:
	var m := _match(1.0)   # (at Extreme the old rules break the arm in one blow: here to put it out)
	await _steps(30)
	var f: Fighter = m.me.f
	var sword = f.weapons.R
	var shield = f.weapons.L
	t.check(sword != null and shield != null and shield.is_shield, "a sword in the right hand and a shield in the left")
	t.check(f.swap_target(m.combat.loose_weapons).is_empty(), "with a sword arm that works there is nothing to swap")
	await _blow(f, f.arm.R.fore, 40.0)
	t.check(f.arm_broken("R") and f.weapons.R == null, "the sword arm broken, the sword let fall")
	t.check(f.state == "stand", "and he is on his feet (%s)" % f.state)
	await _steps(20)
	var sw := f.swap_target(m.combat.loose_weapons)
	t.check(not sw.is_empty() and sw.side == "L" and sw.w == sword, "the sword lying by him is what the left hand would go for")
	f.sturdy_arms = false
	var took = f.grab_nearest(m.combat.loose_weapons)
	t.check(took == sword and f.weapons.L == null, "G lets the shield go and reaches for the sword")
	await _steps(240)
	t.check(f.weapons.L == sword, "and the sword is in his left hand")
	# A man who could still strike with an arm does not drop his shield for it.
	var m2 := _match()
	await _steps(30)
	var g: Fighter = m2.me.f
	var s2 = g.weapons.R
	g.release("R")
	await _steps(20)
	t.check(g.swap_target(m2.combat.loose_weapons).is_empty(), "with the right arm sound he picks it up with that one: no swap")
	m2.queue_free()
	m.queue_free()
