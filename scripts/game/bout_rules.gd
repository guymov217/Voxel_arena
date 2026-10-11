class_name BoutRules
extends RefCounted
## The special bouts of Bread & Circuses (boutRules.js). The host runs them: setup() once the
## fighters are in, update() every tick, check() says "win", "lose", or "" (the usual rule: the
## bout is won when every enemy is down), status() is the line under the HUD's title.
##   goldrush  the Emperor throws gold; grab it before time runs out
##   chariots  scythed chariots circle; survive the clock
##   whims     a new decree every 30 seconds
##   potato    a lit bomb passes to whoever its holder hits, and goes off
##   escort    walk a drunk senator across the arena while pots rain from the walls
##   hold      stand alone in the Emperor's circle until the crowd is satisfied
##   head      kill the insulter and carry his head to the Emperor's box

const WHIM_POOL := ["moon", "turbo", "drunk", "confetti", "bloodbath", "glass", "sparta", "giant"]

var m: Node
var type := ""
var bout: Dictionary = {}
var t := 0.0
var coins := 0                 # gold grabbed by the players (Gold Rush): 4 each
var whim_t := 4.0
var bomb := {"holder": null, "fuse": 0.0, "wait": 3.0}
var bomb_mesh: Node3D = null
var senator = null
var goal := Vector3.ZERO
var bomb_t := 6.0
var circle := {"p": Vector3.ZERO, "r": 2.2, "fill": 0.0, "need": 45.0}
var respawn_t := 6.0
var head_target = null
var trophy: Node3D = null
var carrier = null
var marker: MeshInstance3D = null

func _init(match_: Node, bout_: Dictionary) -> void:
	m = match_
	bout = bout_
	type = String(bout.get("type", ""))

## Hazards the bout needs, decided before anyone is spawned (they go to the guests with "start").
static func hazards_for(bout_: Dictionary) -> Array:
	if bout_.get("type", "") == "chariots":
		return [{"type": "chariot", "r": 7.5, "speed": 5.0, "phase": 0.0}, {"type": "chariot", "r": 4.5, "speed": -4.0, "phase": PI}]
	return []

func setup() -> void:
	match type:
		"goldrush":
			whim_t = 0.5
		"escort":
			var start := Vector3(-Arena.RADIUS + 2.0, 0.02, 0)
			goal = Vector3(Arena.RADIUS - 2.0, 0, 0)
			var e = m.spawn_fighter({"kind": "npc", "name": "Senator Pompous", "loadout": {"main": "", "off": ""}, "team": 0, "color": 0xf4f4f0,
				"pos": start, "yaw": PI / 2, "mods": {"drunk": 0.5, "toughness": 0.8}})
			e.drive = _senator_input
			e.senator = true
			senator = e.f
			_marker(goal, 1.5, Color(1.0, 0.85, 0.3, 0.8))
		"hold":
			_marker(circle.p, circle.r, Color(0.9, 0.75, 0.3, 0.85))
		"head":
			for e in m.enemies():
				if e.get("boss", false):
					head_target = e.f
					break
			if head_target == null and not m.enemies().is_empty():
				head_target = m.enemies()[0].f
			goal = Vector3(0, 0, Arena.RADIUS - 1.6)
			_marker(goal, 1.6, Color(0.7, 0.2, 0.9, 0.8))

func _marker(p: Vector3, r: float, color: Color) -> void:
	if m.headless:
		return
	marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.07
	tm.outer_radius = r
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = mat
	marker.mesh = tm
	m.add_child(marker)
	marker.global_position = p + Vector3(0, 0.03, 0)

func _players() -> Array:
	return m.humans()

func _alive_players() -> Array:
	return m.humans().filter(func(e): return is_instance_valid(e.f) and e.f.alive)

func update(dt: float) -> void:
	t += dt
	match type:
		"goldrush":
			whim_t -= dt
			if whim_t <= 0.0 and t < float(bout.get("duration", 45)):
				whim_t = 0.6
				var a := randf() * TAU
				var r := randf() * (Arena.RADIUS - 2.0)
				m.items.spawn("coin", Vector3(sin(a) * r, 2.5, cos(a) * r), Vector3(0, -1, 0))
		"whims":
			whim_t -= dt
			if whim_t <= 0.0:
				whim_t = 30.0
				m.apply_decree(Decrees.by_id(WHIM_POOL[randi() % WHIM_POOL.size()]))
		"potato":
			_potato(dt)
		"escort":
			bomb_t -= dt
			if bomb_t <= 0.0:
				bomb_t = 5.0
				var ps := _alive_players()
				if not ps.is_empty():
					var tf = ps[randi() % ps.size()].f
					var a := randf() * TAU
					var from := Vector3(sin(a) * (Arena.RADIUS + 1.0), 3.0, cos(a) * (Arena.RADIUS + 1.0))
					m.items.throw_at("pot_thunder" if randf() < 0.5 else "pot_nail", from, tf.torso.global_position * Vector3(1, 0, 1) + Vector3(0, 0.3, 0), null, 10.0, m.dec.gravity)
		"hold":
			var inside := func(e) -> bool:
				return is_instance_valid(e.f) and e.f.alive and (e.f.torso.global_position * Vector3(1, 0, 1)).distance_to(circle.p) < circle.r
			var mine: bool = _players().any(inside)
			var theirs: bool = m.enemies().any(inside)
			if mine and not theirs:
				circle.fill = float(circle.fill) + dt
			respawn_t -= dt
			if respawn_t <= 0.0 and m.enemies().filter(func(e): return e.f.alive).size() < 3 + _players().size():
				respawn_t = 8.0
				_reinforce(["recruit", "berserker", "coward"][randi() % 3])
		"head":
			_head()

func _senator_input(_e) -> Dictionary:
	var side := Vector3(0, 0, sin(m.time * 0.7) * 3.0)
	return {"mz": 0.45, "mx": 0.0, "main": {"x": sin(m.time * 2.0) * 0.5, "y": 0.6}, "off": {"x": -0.4, "y": 0.6}, "faceAt": goal + side}

func _reinforce(kind: String) -> void:
	var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
	var a := randf() * TAU
	var r := Arena.RADIUS - 1.5
	spec.pos = Vector3(sin(a) * r, 0.05, cos(a) * r)
	spec.yaw = atan2(-spec.pos.x, -spec.pos.z)
	m.spawn_fighter(spec)
	m.feed.emit("Reinforcements: %s jumps into the arena!" % spec.name)

func _potato(dt: float) -> void:
	var h = bomb.holder
	if h == null or not is_instance_valid(h):
		bomb.wait = float(bomb.wait) - dt
		if bomb.wait > 0.0:
			return
		var alive: Array = m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive and e.kind != "beast")
		if alive.is_empty():
			return
		bomb.holder = alive[randi() % alive.size()].f
		bomb.fuse = 12.0 + randf() * 6.0
		m.feed.emit("%s has the bomb! Hit someone to pass it!" % bomb.holder.display_name)
		m.sfx("horn", bomb.holder.torso.global_position, 1.0)
		return
	bomb.fuse = float(bomb.fuse) - dt
	if not h.alive:
		bomb.fuse = minf(bomb.fuse, 0.5)
	if not m.headless:
		if bomb_mesh == null:
			bomb_mesh = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.14
			sm.height = 0.28
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.08, 0.08, 0.09)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.3, 0.1)
			sm.material = mat
			bomb_mesh.mesh = sm
			m.add_child(bomb_mesh)
		bomb_mesh.global_position = h.head.global_position + Vector3(0, 0.38 * h.S, 0)
		var mat2: StandardMaterial3D = bomb_mesh.mesh.material
		mat2.emission_energy_multiplier = 0.5 + 2.5 * (0.5 + 0.5 * sin(m.time * (6.0 + 30.0 / maxf(0.5, bomb.fuse))))
	if bomb.fuse <= 0.0:
		var p: Vector3 = h.torso.global_position
		m.throwables.explode("pot_thunder", p, null)
		m.throwables.explode("pot_nail", p, null)
		bomb.holder = null
		bomb.wait = 3.0
		if bomb_mesh:
			bomb_mesh.queue_free()
			bomb_mesh = null

func on_hit(h: Dictionary) -> void:
	if type != "potato" or bomb.holder == null:
		return
	var c = h.get("char")
	if h.get("attacker") == bomb.holder and c != bomb.holder and c is Fighter and c.alive:
		bomb.holder = c
		bomb.fuse = maxf(float(bomb.fuse), 3.0)
		m.feed.emit("The bomb passes to %s!" % c.display_name)

func on_coin(c) -> void:
	if type == "goldrush" and m.humans().any(func(e): return e.f == c):
		coins += 1

func _head() -> void:
	var tf = head_target
	if tf and is_instance_valid(tf) and not tf.alive and trophy == null:
		trophy = Node3D.new()
		m.add_child(trophy)
		trophy.global_position = tf.head.global_position * Vector3(1, 0, 1) + Vector3(0, 0.15, 0)
		if not m.headless:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.26 * tf.S
			var mat := StandardMaterial3D.new()
			mat.albedo_color = tf.skin
			bm.material = mat
			mi.mesh = bm
			trophy.add_child(mi)
		m.feed.emit("Grab his head and bring it to the Emperor's box!")
	if trophy == null:
		return
	if carrier and (not is_instance_valid(carrier) or not carrier.alive or carrier.state != "stand"):
		trophy.global_position = (carrier.torso.global_position if is_instance_valid(carrier) else trophy.global_position) * Vector3(1, 0, 1) + Vector3(0, 0.15, 0)
		carrier = null
	if carrier == null:
		for e in _alive_players():
			if (e.f.torso.global_position * Vector3(1, 0, 1)).distance_to(trophy.global_position * Vector3(1, 0, 1)) < 0.9:
				carrier = e.f
				m.feed.emit("%s grabbed the head!" % e.f.display_name)
				m.sfx("cheer", e.f.torso.global_position, 0.6)
				break
	else:
		trophy.global_position = carrier.head.global_position + Vector3(0, 0.4 * carrier.S, 0)

func check() -> String:
	var dur := float(bout.get("duration", 60 if type == "chariots" else 45))
	match type:
		"goldrush", "chariots":
			return "win" if t >= dur else ""
		"escort":
			if senator == null or not is_instance_valid(senator) or not senator.alive:
				return "lose"
			return "win" if (senator.torso.global_position * Vector3(1, 0, 1)).distance_to(goal) < 1.5 else ""
		"hold":
			return "win" if circle.fill >= circle.need else ""
		"head":
			if head_target == null:
				return ""
			return "win" if carrier and (carrier.torso.global_position * Vector3(1, 0, 1)).distance_to(goal) < 1.6 else "none"
	return ""

## Whether the usual "every enemy down" rule decides this bout.
func default_rule() -> bool:
	return not ["goldrush", "chariots", "escort", "hold", "head"].has(type)

func status() -> String:
	var dur := float(bout.get("duration", 60 if type == "chariots" else 45))
	var left := "%ds" % maxi(0, ceili(dur - t))
	match type:
		"goldrush": return "Grab the gold! %d coins · %s" % [coins, left]
		"chariots": return "Survive %s" % left
		"whims": return "Next decree in %ds" % maxi(0, ceili(whim_t))
		"potato":
			return ("%s has the bomb · %ds" % [bomb.holder.display_name, maxi(0, ceili(bomb.fuse))]) if bomb.holder and is_instance_valid(bomb.holder) else "A new bomb is coming"
		"escort":
			if senator == null or not is_instance_valid(senator):
				return ""
			var total := 2.0 * (Arena.RADIUS - 2.0)
			var done := clampf(1.0 - (senator.torso.global_position * Vector3(1, 0, 1)).distance_to(goal) / total, 0.0, 1.0)
			return "Senator %d%% across · blood %d" % [int(done * 100.0), int(senator.blood)]
		"hold": return "The circle: %d%%" % int(circle.fill / circle.need * 100.0)
		"head":
			if trophy:
				return ("%s carries the head" % carrier.display_name) if carrier else "The head is on the sand!"
			return "Kill %s" % (head_target.display_name if head_target and is_instance_valid(head_target) else "the target")
	return ""
