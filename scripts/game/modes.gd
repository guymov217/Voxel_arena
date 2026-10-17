class_name Modes
extends RefCounted
## The fight modes outside the campaign (game.js, partyModes.js): a duel, best of three, free
## for all, chaos, players' brawl, co-op and gauntlet waves of bots, the monster hunt, Red vs
## Blue, King of the Arena, the Emperor (you judge from the box), King of the Hill, Last Limb
## Standing and head football. Host side; `m` is the Match.

const TEAM_COLORS := [0xa02020, 0x2050b0, 0x208040, 0xc0a020, 0x8030a0, 0x20a0a0, 0xd06020, 0x606060]
const ALL := ["duel", "bo3", "ffa", "chaos", "pvp", "coop", "gauntlet", "hunt", "teams", "king", "emperor", "hill", "lastLimb", "headball"]
const TITLES := {"duel": "Test fight!", "bo3": "Duel: best of three!", "ffa": "Free for all!", "chaos": "Chaos!", "pvp": "Players brawl!", "coop": "Co-op campaign!",
	"gauntlet": "Survive the waves!", "hunt": "Monster Hunt!", "teams": "Red vs Blue!", "king": "King of the Arena!", "emperor": "The Emperor watches!",
	"hill": "King of the Hill!", "lastLimb": "Last Limb Standing!", "headball": "Head Football!"}
const LABELS := {"teams": "Teams: players and bots split up", "hill": "Hold the circle alone for 20 s", "lastLimb": "The Emperor removes a limb from everyone every 15 s",
	"headball": "Kick the head into the other goal (first to 3)", "king": "The winner stays, the next challenger walks in", "emperor": "1 decree · 2 beast · 3 weapon · 4 tomato · 5 gift · 6/7 the verdict",
	"bo3": "Floored? Y yields, F fights on wounded for double the stake"}
const GOAL_X := 15.0 - 2.2

var m: Node
var mode := "duel"
var wave := 0
var wait_t := 0.0
var bo3 := {}
var king := {}
var emperor := {}
var hill := {}
var chop_t := 15.0
var chops := 0
var ball := {}
var ring: MeshInstance3D = null
var last_winner = null
var difficulty := 0.7

func _init(match_: Node, mode_: String) -> void:
	m = match_
	mode = mode_

static func handles(mode_: String) -> bool:
	return ALL.has(mode_)

## The team a player (the i-th) fights for.
static func player_team(mode_: String, i: int) -> int:
	match mode_:
		"teams", "headball": return i % 2
		"coop", "gauntlet", "hunt": return 0
	return i

static func coop_like(mode_: String) -> bool:
	return mode_ == "coop" or mode_ == "gauntlet" or mode_ == "hunt"

func bot_count(players: int) -> int:
	match mode:
		"emperor": return maxi(2, 4 - (players - 0))
		"duel", "bo3", "gauntlet": return 1 if not (mode == "bo3" and players >= 2) else 0
		"ffa", "chaos", "hill", "lastLimb", "king": return 3 if mode != "king" else 1
		"teams", "headball": return maxi(0, 4 - players)
		"coop": return maxi(2, players)
	return 0

static func spawn_pos(index: int, total: int) -> Vector3:
	var a := float(index) / maxf(2.0, float(total)) * TAU + 0.3
	var r := minf(15.0 - 2.0, 3.5 if total <= 2 else 5.0)   # a few strides apart: room to square up
	return Vector3(sin(a) * r, 0.02, cos(a) * r)

## Spawns the players (no fighter for the Emperor himself) and everything the mode starts with.
func setup(opts: Dictionary) -> void:
	difficulty = float(opts.get("difficulty", 0.7))
	var players := []
	if mode != "emperor":
		players.append({"kind": "local", "name": opts.get("name", "Gladiator"), "loadout": opts.get("loadout", {"main": "gladius", "off": "roundShield"}), "skin": opts.get("skin")})
	for p in opts.get("peers", []):
		players.append({"kind": "remote", "peer": p.id, "name": p.name, "loadout": p.get("loadout", {"main": "gladius"}), "kit": p.get("kit", {}), "skin": p.get("skin")})
	var bots := bot_count(players.size())
	var total := players.size() + bots
	for i in players.size():
		var p: Dictionary = players[i]
		var team := player_team(mode, i)
		var pos := spawn_pos(i, total)
		var e = m.spawn_fighter({"kind": p.kind, "peer": p.get("peer", -1), "name": p.name, "loadout": p.loadout, "team": team, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "color": TEAM_COLORS[team % TEAM_COLORS.size()], "skin": p.get("skin")})
		e.inventory = opts.get("inventory", {}) if p.kind == "local" else Net.sanitize_kit(p.get("kit", {}))
		if p.kind == "local":
			m.me = e
	m.players_count = players.size()
	if opts.get("autopilot", false) and m.me:
		m.me.bot = Bot.new(m.me.f, float(opts.get("autopilot_diff", 0.9)), "standard", 99)
	wave = 1 if coop_like(mode) else 0
	match mode:
		"hunt":
			spawn_hunt_wave()
		"bo3":
			bo3 = {"round": 1, "wins": {}, "stake": 30, "pause": 0.0, "loser": null, "choice": ""}
			spawn_bots(bots, players.size(), total)
		"king":
			king = {"streak": 0, "max": 7}
			spawn_bots(bots, players.size(), total)
		"emperor":
			emperor = {"cool": {}, "verdict": ""}
			spawn_bots(bots, players.size(), total)
		_:
			spawn_bots(bots, players.size(), total)
	match mode:
		"hill":
			hill = {"p": Vector3.ZERO, "r": 2.4, "need": 20.0, "score": {}, "king": null}
			_ring(Vector3.ZERO, 2.4, Color(0.95, 0.8, 0.3, 0.5))
		"headball":
			ball = {"score": [0, 0], "reset_t": 0.0}
			for e in m.entities:
				e.f.mods.downable = false
			_spawn_ball()
			for x in [-GOAL_X, GOAL_X]:
				_ring(Vector3(x, 0, 0), 2.2, Color(1, 1, 1, 0.4))
	m._banner(TITLES.get(mode, "Fight!"), LABELS.get(mode, "Wave 1" if coop_like(mode) else ""))

func _ring(p: Vector3, r: float, color: Color) -> void:
	if m.headless:
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.06
	tm.outer_radius = r
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = mat
	mi.mesh = tm
	m.add_child(mi)
	mi.global_position = p + Vector3(0, 0.02, 0)
	ring = mi

func _bot_mods() -> Dictionary:
	var d := difficulty
	return {"strength": 1.0 + (d - 0.7) * 0.8, "speed": 1.0 + (d - 0.7) * 0.5, "toughness": 1.0 + (d - 0.7) * 0.6} if d >= 0.7 else {}

func spawn_bots(n: int, offset: int, total: int) -> void:
	var names: Array = Data.modes.get("botNames", ["Crixus"])
	var los: Array = Data.modes.get("randomLoadouts", [{"main": "gladius", "off": "roundShield"}])
	var personalities := ["standard", "berserker", "duelist", "turtle", "brute", "skirmisher"]
	for i in n:
		var idx := offset + i
		var team := 1 if coop_like(mode) else (idx % 2 if mode == "teams" or mode == "headball" else idx)
		var pos := spawn_pos(idx, total)
		var lo: Dictionary = los[m.rng.randi_range(0, los.size() - 1)]
		m.spawn_fighter({"kind": "bot", "name": names[(idx + wave * 3) % names.size()], "loadout": {"main": lo.main if lo.main else "", "off": lo.off if lo.off else ""},
			"team": team, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "mods": _bot_mods(), "diff": difficulty, "personality": personalities[m.rng.randi_range(0, personalities.size() - 1)],
			"color": 0x303030 if coop_like(mode) else TEAM_COLORS[team % TEAM_COLORS.size()]})

func hunt_wave(n: int) -> Array:
	var table: Array = Data.modes.get("huntWaves", [])
	if n <= table.size():
		return (table[n - 1] as Array).duplicate(true)
	var bosses := ["cerberus", "griffin", "hydra", "manticore", "chimera", "basilisk", "dragon", "mammoth", "rhino"]
	var escorts := ["rat", "hyena", "wolf", "spider", "crocodile", "tiger"]
	var grow := 1.0 + 0.08 * (n - table.size())
	return [{"beast": bosses[m.rng.randi_range(0, bosses.size() - 1)], "n": 1, "boss": true, "scaleMul": grow}, {"beast": escorts[m.rng.randi_range(0, escorts.size() - 1)], "n": 2 + int((n - table.size()) / 3)}]

func spawn_hunt_wave() -> void:
	var groups := hunt_wave(wave)
	var players := maxi(1, m.humans().size())
	var total := 0
	for g in groups:
		total += 1 if g.get("boss", false) else int(g.n) + int((players - 1) / 2)
	var i := 0
	var names := []
	for g in groups:
		var n: int = 1 if g.get("boss", false) else int(g.n) + int((players - 1) / 2)
		var sp: Dictionary = Data.beasts.get(g.beast, {})
		for k in n:
			var a := float(i) / maxf(1.0, total) * TAU + PI
			i += 1
			var pos := Vector3(sin(a) * 7.5, 0.1, cos(a) * 7.5)
			var scale := float(sp.get("scale", 1.0)) * float(g.get("scaleMul", 1.0)) * (1.15 if g.get("boss", false) else 1.0)
			m.spawn_beast({"beast": g.beast, "scale": scale, "name": g.get("name", sp.get("name", g.beast)), "boss": g.get("boss", false), "team": 1, "pos": pos, "yaw": atan2(-pos.x, -pos.z)})
		names.append(("%s (boss)" % g.get("name", sp.get("name", g.beast))) if g.get("boss", false) else ("%d × %s" % [n, sp.get("name", g.beast)]))
	m.feed.emit("Wave %d: %s" % [wave, ", ".join(names)])

func _heal(list: Array, blood: float) -> void:
	for h in list:
		var c = h.f
		c.blood = minf(100.0, c.blood + blood)
		c.stamina = 100.0
		for p in c.parts:
			if not p.severed:
				p.bleed = 0.0
				p.artery = 0.0

func _next_wave(text: String, sub: String) -> void:
	wave += 1
	m._banner(text % wave, sub)
	wait_t = 2.5
	m.sfx("horn", Vector3.ZERO)

# ---------- Each step ----------

## Holds everyone still while a countdown or a best-of-three pause runs.
func frozen() -> bool:
	return wait_t > 0.0 or (not bo3.is_empty() and float(bo3.pause) > 0.0)

func update(dt: float, local_inp: Dictionary) -> void:
	if wait_t > 0.0:
		wait_t -= dt
	match mode:
		"hill": _hill(dt)
		"lastLimb": _last_limb(dt)
		"headball": _headball(dt)
		"emperor": _emperor(dt, local_inp)
	if mode == "bo3":
		_bo3(dt, local_inp)

func _alive_fighters() -> Array:
	return m.entities.filter(func(e): return e.f.alive and e.kind != "beast")

func _hill(dt: float) -> void:
	var inside: Array = _alive_fighters().filter(func(e): return Vector2(e.f.torso.global_position.x - hill.p.x, e.f.torso.global_position.z - hill.p.z).length() < hill.r)
	if inside.size() == 1:
		var e: Dictionary = inside[0]
		hill.score[e.id] = float(hill.score.get(e.id, 0.0)) + dt
		if hill.king != e.id:
			hill.king = e.id
			m.feed.emit("%s holds the hill" % e.f.display_name)
	var k = m.entity_by_id(int(hill.king)) if hill.king != null else null
	for e in m.entities:
		if e.kind == "bot" and k and k.f.alive and e != k:
			e.manual_target = k

func _last_limb(dt: float) -> void:
	chop_t -= dt
	if chop_t > 0.0:
		return
	chop_t = 15.0
	chops += 1
	var order := ["forearmL", "forearmR", "shinL", "shinR", "upperArmL", "upperArmR", "thighL", "thighR"]
	for e in _alive_fighters():
		var c = e.f
		var options: Array = c.parts.filter(func(p): return not p.severed and order.has(p.part_name))
		if options.is_empty():
			continue
		var part: VoxelPart = options[m.rng.randi_range(0, options.size() - 1)]
		c.detach_limb(part, {"removed": [], "severed": []})
	m._banner("THUMBS DOWN", "The Emperor takes a limb from everyone (%d)" % chops)
	m.sfx("boo", Vector3.ZERO)

func _spawn_ball() -> void:
	m.items.spawn("ball", Vector3(0, 1.5, 0))

func ball_item():
	for it in m.items.list:
		if it.type == "ball":
			return it
	return null

## The head is kicked: it flies the way the leg was going.
func kick_ball(ev: Dictionary) -> void:
	var it: Dictionary = ev.item
	it.kicker = ev.char
	it.p.y = maxf(it.p.y, 0.25)
	it.grounded = false
	it.vel = ev.dir * ev.speed * 1.6 + Vector3(0, 2.5 + ev.speed * 0.3, 0)
	m.sfx("thud", it.p, 0.6)

func _headball(dt: float) -> void:
	if float(ball.reset_t) > 0.0:
		ball.reset_t -= dt
		if ball.reset_t <= 0.0:
			_spawn_ball()
		return
	var it = ball_item()
	if it == null:
		_spawn_ball()
		return
	if absf(it.p.x) > GOAL_X and absf(it.p.z) < 2.2:
		# The left goal is Red's (team 0): a ball in it scores for Blue.
		var scorer := 1 if it.p.x < 0.0 else 0
		ball.score[scorer] += 1
		var kicker = it.get("kicker")
		m._banner("GOAL! %s" % ["Red", "Blue"][scorer], "%d : %d%s" % [ball.score[0], ball.score[1], (" · %s scores!" % kicker.display_name) if kicker and is_instance_valid(kicker) else ""])
		if kicker:
			m.crowd_add(kicker, 20, "GOAL!")
		m.items.remove(it)
		ball.reset_t = 2.0
		return
	for e in m.entities:
		if e.kind == "bot":
			e.ball_target = it.p

func _emperor(_dt: float, inp: Dictionary) -> void:
	var cool: Dictionary = emperor.cool
	for k in cool:
		cool[k] = maxf(0.0, cool[k] - _dt)
	var slot := int(inp.get("useItem", -1)) + 1
	var fighters: Array = _alive_fighters()
	var pick = fighters[m.rng.randi_range(0, fighters.size() - 1)].f if not fighters.is_empty() else null
	var use := func(n: int, cd: float) -> bool:
		if slot != n or float(cool.get(n, 0.0)) > 0.0:
			return false
		cool[n] = cd
		return true
	if not m.over:
		if use.call(1, 12.0):
			var d := Decrees.roll(1.0, 1, m.rng)
			if not d.is_empty():
				m.add_runtime_decree(d[0])
		if use.call(2, 20.0):
			var sp := ["lion", "wolf", "bear", "boar", "tiger", "hyena"]
			var k: String = sp[m.rng.randi_range(0, sp.size() - 1)]
			m.spawn_beast({"beast": k, "team": 9, "pos": Vector3(0, 0.1, 12), "yaw": PI})
			m.feed.emit("The Emperor releases a %s!" % Data.beasts.get(k, {}).get("name", k).to_lower())
		if use.call(3, 6.0) and pick:
			var keys := ["gladius", "axe", "mace", "spear", "warhammer", "longsword", "chicken", "fish", "plank", "dagger"]
			m.spawn_loose_weapon(Data.preset(keys[m.rng.randi_range(0, keys.size() - 1)]), pick.torso.global_position + Vector3(randf_range(-0.8, 0.8), 5.0, randf_range(-0.8, 0.8)))
			m.feed.emit("The Emperor throws a weapon down to %s" % pick.display_name)
		if use.call(4, 1.2) and pick:
			m.items.throw_from_stands("tomato", pick.head.global_position, 0.9)
		if use.call(5, 4.0) and pick:
			m.items.throw_from_stands("bread" if randf() < 0.5 else "wine", pick.torso.global_position + Vector3(0.5, -pick.torso.global_position.y + 0.1, 0.5))
			m.crowd_add(pick, 5, "imperial favour")
			m.feed.emit("A gift from the Emperor for %s" % pick.display_name)
	elif emperor.verdict == "" and last_winner and is_instance_valid(last_winner):
		if use.call(6, 1.0):
			emperor.verdict = "up"
			m._banner("The Emperor: thumbs up!", "%s lives, and is paid double" % last_winner.display_name)
			m.sfx("cheer", Vector3.ZERO)
		elif use.call(7, 1.0):
			emperor.verdict = "down"
			m._banner("The Emperor: thumbs down!", "%s wins nothing today" % last_winner.display_name)
			last_winner.die("wounds")
			m.sfx("boo", Vector3.ZERO)

func _bo3(dt: float, inp: Dictionary) -> void:
	var f: Array = m.entities.filter(func(e): return e.kind != "beast")
	if f.size() < 2 or m.over:
		return
	if float(bo3.pause) > 0.0:
		bo3.pause -= dt
		var loser: Dictionary = bo3.loser
		var l = loser.f
		var choice := ""
		if loser.kind == "local":
			if Input.is_physical_key_pressed(KEY_Y):
				choice = "yield"
			if inp.get("throw", false) or inp.get("charging", 0.0) > 0.0:
				choice = "fight"
		elif loser.kind == "bot" and bo3.pause < 4.0:
			choice = "fight" if l.alive and l.blood > 35.0 and m.rng.randf() < 0.7 else "yield"
		elif loser.kind == "remote" and bo3.pause < 4.0:
			choice = "fight" if l.alive else "yield"
		if bo3.pause <= 0.0 and choice == "":
			choice = "yield"
		if choice == "":
			return
		if choice == "yield" or not l.alive or int(bo3.round) >= 3:
			_bo3_end()
			return
		bo3.round += 1
		bo3.stake *= 2
		bo3.pause = 0.0
		for e in f:
			var c = e.f
			if c.alive:
				c.blood = maxf(c.blood, 55.0)
				c.stamina = 100.0
				c.stagger = 0.0
				for p in c.parts:
					if not p.severed:
						p.bleed = 0.0
						p.artery = 0.0
				if c.state == "down":
					c.down_timer = 0.1
		m._banner("Round %d" % bo3.round, "%s fights on, wounded. The stake is %d denarii" % [l.display_name, bo3.stake])
		wait_t = 2.0
		return
	if wait_t > 0.0:
		return
	for e in f:
		var c = e.f
		if c.state == "stand":
			e.down_for = 0.0
		else:
			e.down_for = float(e.get("down_for", 0.0)) + dt
		var floored: bool = not c.alive or c.blood < 20.0 or (c.state != "stand" and not c.can_stand()) or float(e.down_for) > 2.5
		if not floored:
			continue
		var winner: Dictionary = f[0] if f[1] == e else f[1]
		bo3.wins[winner.id] = int(bo3.wins.get(winner.id, 0)) + 1
		bo3.loser = e
		if not c.alive or int(bo3.wins[winner.id]) >= 2 or int(bo3.round) >= 3:
			_bo3_end()
			return
		bo3.pause = 8.0
		if c.alive:
			m._tape_kill(c, "out")
		m._round_replay()
		m._banner("Round %d to %s" % [bo3.round, winner.f.display_name], "You are down. Y: yield · F: fight on, wounded, for double the stake" if e.kind == "local" else "%s is down and must choose: yield, or fight on for double the stake" % c.display_name)
		return

func _bo3_end() -> void:
	var f: Array = m.entities.filter(func(e): return e.kind != "beast")
	f.sort_custom(func(x, y): return int(bo3.wins.get(x.id, 0)) > int(bo3.wins.get(y.id, 0)))
	var w: Dictionary = f[0]
	var score := "%d-%d" % [int(bo3.wins.get(f[0].id, 0)), int(bo3.wins.get(f[1].id, 0))]
	m._end(w == m.me, "%s wins the duel %s" % [w.f.display_name, score], "For %d denarii" % bo3.stake, int(bo3.stake) if w == m.me else 0)

## The end of a round, by the mode's own rules.
func check(dt: float) -> void:
	if m.over:
		return
	# One who has lain unable to stand for a while is out (Match._unfit), as in any bout.
	var alive: Array = m.entities.filter(func(e): return e.f.alive and not m._unfit(e, dt) and not e.get("harmless", false))
	var humans_alive: Array = m.humans().filter(func(e): return e.f.alive and float(e.get("unfit_t", 0.0)) < Match.UNFIT_OUT)
	match mode:
		"hill":
			for id in hill.score:
				var e = m.entity_by_id(int(id))
				if e and float(hill.score[id]) >= float(hill.need) and e.f.alive:
					_win(e)
					return
			var fa: Array = _alive_fighters()
			if fa.size() <= 1:
				_win(fa[0] if fa.size() else null)
			return
		"lastLimb":
			var fa2: Array = _alive_fighters()
			if fa2.size() <= 1:
				_win(fa2[0] if fa2.size() else null)
			return
		"headball":
			if ball.score[0] >= 3 or ball.score[1] >= 3:
				var team := 0 if ball.score[0] >= 3 else 1
				var mine: bool = m.me != null and m.me.team == team
				m._end(mine, "%s team wins!" % ["Red", "Blue"][team], "%d : %d" % [ball.score[0], ball.score[1]], 30 if mine else 0)
			return
		"bo3":
			return
		"hunt":
			if humans_alive.is_empty():
				m._end(false, "The monsters won in wave %d" % wave, "")
				return
			if not alive.any(func(e): return e.kind == "beast" and e.team == 1):
				_heal(humans_alive, 22.0)
				m._round_replay()
				_next_wave("Wave %d!", "The gates open again")
				spawn_hunt_wave()
			return
		"coop", "gauntlet":
			if humans_alive.is_empty():
				m._end(false, "You fell in wave %d" % wave, "")
				return
			if not alive.any(func(e): return e.kind == "bot"):
				_heal(humans_alive, 35.0)
				m._round_replay()
				_next_wave("Wave %d!", "The crowd wants more blood")
				var n := mini(5, ceili(wave * 0.7) + m.players_count - 1)
				spawn_bots(n, m.entities.size(), m.entities.size() + n)
				if wave % 3 == 0:
					m.spawn_beast({"beast": "lion", "team": 1, "pos": Vector3(0, 0.1, 12), "yaw": PI})
					m.feed.emit("Wave %d: the lions join in!" % wave)
			return
	if m.entities.size() < 2:
		return
	var teams := {}
	for e in alive:
		if e.kind != "beast":
			teams[e.team] = true
	if teams.size() > 1:
		return
	var winner = null
	for e in alive:
		if e.kind != "beast":
			winner = e
			break
	if mode == "king" and winner:
		if winner.kind == "bot" or int(king.streak) + 1 >= int(king.max):
			m._end(winner == m.me, ("%s reigns: the players are all down after %d bouts" % [winner.f.display_name, king.streak]) if winner.kind == "bot" else ("%s is King of the Arena: %d bouts unbeaten!" % [winner.f.display_name, king.max]), "", 60 if winner == m.me else 0)
			return
		king.streak += 1
		m._round_replay()
		var c = winner.f
		c.blood = minf(100.0, c.blood + 15.0)
		c.stamina = 100.0
		for p in c.parts:
			if not p.severed:
				p.bleed = 0.0
				p.artery = 0.0
		if winner == m.me:
			m.round_pay += 10 + 8 * int(king.streak)
		m._banner("%s holds the arena (%d)" % [c.display_name, king.streak], "The next challenger walks in")
		spawn_bots(1, m.entities.size(), m.entities.size() + 1)
		wait_t = 2.0
		return
	_win(winner)

func _win(winner) -> void:
	last_winner = winner.f if winner else null
	var mine: bool = winner != null and m.me != null and (winner == m.me or (mode == "teams" and winner.team == m.me.team))
	var text := ("%s team wins!" % ["Red", "Blue"][winner.team % 2]) if mode == "teams" and winner else (("%s wins!" % winner.f.display_name) if winner else "Draw!")
	var sub := "The Emperor decides: 6 thumbs up · 7 thumbs down" if mode == "emperor" else ""
	var verdict: Dictionary = m.spectacle.verdict(winner.f if winner else null)
	if mine:
		sub = verdict.text
	m._end(mine, text, sub, (m.round_pay + 20 + int(verdict.bonus / 4)) if mine else 0, mode == "emperor")

func status() -> String:
	match mode:
		"hill":
			var best = null
			var bs := 0.0
			for id in hill.score:
				if float(hill.score[id]) > bs:
					bs = hill.score[id]
					best = m.entity_by_id(int(id))
			return ("%s %ds to go" % [best.f.display_name, ceili(hill.need - bs)]) if best else "nobody on the hill"
		"lastLimb": return "next chop in %ds" % ceili(chop_t)
		"headball": return "Red %d : %d Blue · kick the head!" % [ball.score[0], ball.score[1]]
		"hunt", "coop", "gauntlet": return "Wave %d" % wave
		"king": return "Reign: %d of %d" % [king.streak, king.max]
		"bo3": return "Round %d · stake %d" % [bo3.round, bo3.stake]
		"emperor": return LABELS.emperor
	return TITLES.get(mode, "")
