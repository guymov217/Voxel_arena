extends Node
## The elephant's stomp is seen coming: it rears up on its hind legs with both forefeet and the
## trunk in the air, then brings its weight down on them; a man close by is rocked by it.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_the_elephant_rears_then_stomps() -> void:
	for kind in ["elephant", "mammoth"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
		m.me.f.teleport(Vector3(0, 0, -14))
		var be = m.spawn_beast({"beast": kind, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "harmless": true})
		var b: Beast = be.f
		var stomps := [0]
		b.on_stomp = func(_b): stomps[0] += 1
		await _steps(120)
		var fl: VoxelPart = b.lower_of(b.by_name.legFL)
		var bl: VoxelPart = b.lower_of(b.by_name.legBL)
		var lift0: float = fl.global_position.y - bl.global_position.y
		b.ai.stomp = Beast.STOMP_T
		b.ai.stomped = false
		var lift := -INF
		var pitch_up := 0.0
		for i in int((Beast.STOMP_T - Beast.STOMP_DOWN) * 120.0):
			await get_tree().physics_frame
			lift = maxf(lift, fl.global_position.y - bl.global_position.y)
			var fwd: Vector3 = PD.quat_of(b.torso) * Vector3(0, 0, 1)
			pitch_up = maxf(pitch_up, fwd.y)
		t.check(lift - lift0 > 0.25 * b.S, "%s: the forefoot goes up (%.2f m above the hind foot, %.2f before)" % [kind, lift, lift0])
		t.check(pitch_up > 0.2, "%s: reared back on the hind legs (nose up %.2f)" % [kind, pitch_up])
		await _steps(int(Beast.STOMP_DOWN * 120.0) + 10)
		t.eq(stomps[0], 1, "%s: then the forefeet come down, once" % kind)
		m.queue_free()
		await get_tree().physics_frame

func test_the_ground_shakes_under_a_stomp() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -14))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 0, "pos": Vector3(1.6, 0, 4.0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	var be = m.spawn_beast({"beast": "elephant", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "harmless": true})
	await _steps(60)
	var v: Fighter = e.f
	v.stagger = 0.0
	m._stomp(be.f)
	t.check(v.stagger > 0.1, "a man near the stomp reels from it (stagger %.2f)" % v.stagger)
	m.queue_free()
