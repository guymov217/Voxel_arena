extends Node
## What a thrust does follows the man who drives it and the weapon he drives (user: at the campaign's
## start a knife to the belly killed any man at once, and a thrust went in at the front and out at the
## back): his strength and the weight of what he holds are what he puts behind the point, and one
## lunge is one blow.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## A full thrust of `wk`, held by a man whose strength (the training's Vis) is `str_k`, into a man who
## stands and takes it: `aim` "down" at his belly, "level" at his chest. {hits: [{part, J, dmg}], dmg:
## what the trunk lost, hole: the share of the trunk's thickness (along the stab) that is gone,
## alive: whether he lives `after` seconds on}.
func _stab(wk: String, str_k: float, aim: String, after := 0) -> Dictionary:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(-12, 0, 8))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": wk}, "team": 1, "pos": Vector3.ZERO, "yaw": 0.0, "mods": {"strength": str_k}})
	e.erase("bot")
	var f: Fighter = e.f
	var st := {"thrust": 0.0}
	var at: Dictionary = {"level": {"x": 0.0, "y": 0.15}, "down": {"x": 0.0, "y": -0.2}}[aim]
	e.drive = func(_e): return {"main": at, "off": {"x": -0.35, "y": 0.1}, "power": true, "thrust": st.thrust, "look": {"yaw": 0.0, "pitch": 0.0}}
	await _steps(200)
	var w: Weapon = f.weapons.R
	var ax: Vector3 = PD.quat_of(w) * Vector3.UP
	var spot := w.global_position + ax * (w.reach + 0.35)
	var d = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {}, "team": 2, "pos": Vector3(spot.x, 0, spot.z) + Vector3(ax.x, 0, ax.z).normalized() * 0.15, "yaw": PI})
	d.erase("bot")
	d.drive = func(_e): return {}
	var foe: Fighter = d.f
	var hits := []
	m.combat.hit.connect(func(h): if h.get("char") == foe and h.get("weapon") == f.weapons.R: hits.append({"part": h.part, "J": float(h.J), "dmg": float(h.res.get("dmg", 0.0))}))
	await _steps(30)
	var hp0 := foe.torso.hp
	st.thrust = 1.0
	await _steps(72)
	st.thrust = 0.0
	# All the trunk voxels gone, along the stab, over the whole thickness.
	var tor: VoxelPart = foe.torso
	var lax := (tor.global_transform.basis.orthonormalized().inverse() * ax).normalized()
	var lo := INF
	var hi := -INF
	for i in tor.fx.size():
		if tor.alive[i] == 0:
			var a := tor.local_of(i).dot(lax)
			lo = minf(lo, a)
			hi = maxf(hi, a)
	var thick := 2.0 * (absf(lax.x) * tor.half_ext.x + absf(lax.y) * tor.half_ext.y + absf(lax.z) * tor.half_ext.z)
	var out := {"hits": hits, "dmg": hp0 - foe.torso.hp, "hole": (hi - lo) / thick if hi > lo else 0.0, "alive": true}
	await _steps(120 * after)
	out.alive = foe.alive
	m.queue_free()
	await get_tree().process_frame
	return out

## The power behind a point: more with a heavier weapon, in proportion to the man's strength, and
## not without limit.
func test_a_thrusts_power_follows_the_weapon_and_the_man() -> void:
	var dagger := Combat.thrust_power(0.42, 1.0)
	var spear := Combat.thrust_power(0.87, 1.0)
	var gladius := Combat.thrust_power(1.7, 1.0)
	var great := Combat.thrust_power(3.5, 1.0)
	t.check(dagger < spear and spear < gladius, "a heavier weapon drives harder (dagger %.2f, spear %.2f, gladius %.2f)" % [dagger, spear, gladius])
	t.check(dagger > 0.4 * gladius, "a dagger still has something behind it (%.2f of a gladius's)" % (dagger / gladius))
	t.check(great <= gladius * 1.15, "a great weapon does not drive far past a gladius (%.2f of it)" % (great / gladius))
	t.check(absf(Combat.thrust_power(1.7, 1.3) - 1.3 * gladius) < 0.001, "in proportion to the man's strength")
	t.check(Combat.thrust_power(1.7, 0.8) < gladius, "a weaker man drives it less")
	t.check(gladius < 1.0, "a man untaught does not drive the whole lunge (%.2f)" % gladius)

## A knife to the belly at the campaign's start (strength 1) hurts him and bleeds him; it does not
## kill him at once, nor go through him; a gladius does more, not more than half a man.
func test_a_knife_to_the_belly_does_not_kill_at_once_nor_go_through() -> void:
	var k := await _stab("dagger", 1.0, "down", 8)
	t.check(k.hits.size() >= 1, "the knife landed (%d hits)" % k.hits.size())
	t.check(k.dmg > 8.0 and k.dmg < 30.0, "it hurts him, not past a third of him (%.0f of 100)" % k.dmg)
	t.check(k.hole < 0.6, "it does not go through him (%.0f%% of his thickness)" % (k.hole * 100.0))
	t.check(k.alive, "he is alive eight seconds on")
	var g := await _stab("gladius", 1.0, "down", 8)
	t.check(g.dmg > k.dmg and g.dmg < 45.0, "a gladius does more than a knife and not past half of him (%.0f against %.0f)" % [g.dmg, k.dmg])
	t.check(g.hole < 0.6, "nor does it go through him (%.0f%%)" % (g.hole * 100.0))
	t.check(g.alive, "and he lives eight seconds on")

## A man trained in strength drives the same point harder.
func test_a_stronger_man_stabs_harder() -> void:
	var weak := await _stab("gladius", 1.0, "down")
	var strong := await _stab("gladius", 1.3, "down")
	t.check(strong.dmg > weak.dmg * 1.1, "strength 1.3 does more than strength 1 (%.0f against %.0f)" % [strong.dmg, weak.dmg])
	var jw := 0.0
	var js := 0.0
	for h in weak.hits:
		jw = maxf(jw, h.J)
	for h in strong.hits:
		js = maxf(js, h.J)
	t.check(js > jw * 1.25, "and the blow is heavier by the strength put in it (%.0f against %.0f)" % [js, jw])

## One lunge is one blow: a point that touches and then drives on in the same thrust lands with what
## the first contact left of it, not whole on top of it (a spear's thrust was two or three blows).
func test_one_lunge_is_one_blow() -> void:
	var r := _victim()
	var m: Match = r[0]
	var v: Fighter = r[1]
	await _steps(30)
	var tor := v.torso
	tor.hp = 1000.0
	var gt := tor.global_transform
	var fwd := gt.basis.orthonormalized() * Vector3(0, 0, 1)
	var hit := {"impulse": 60.0, "type": "point", "hardness": 0.9, "sharpness": 0.9, "point": gt * Vector3(0.0, 0.0, tor.half_ext.z), "dir": -fwd, "axis": -fwd, "thrust": 1.0, "tpower": 1.0}
	var first: Dictionary = v.apply_hit(tor, hit.duplicate())
	var again := hit.duplicate()
	again.prior = float(first.dmg)
	var second: Dictionary = v.apply_hit(tor, again)
	t.check(float(first.dmg) > 10.0, "the first contact hurts (%.1f)" % float(first.dmg))
	t.check(float(second.dmg) < 1.0, "the same lunge's second contact adds nothing of the same weight (%.1f)" % float(second.dmg))
	m.queue_free()

func _victim() -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -8))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	return [m, e.f]
