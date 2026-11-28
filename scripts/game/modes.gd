class_name Modes
extends RefCounted
## The fight modes outside the campaign (game.js, partyModes.js): a duel, best of three, free
## for all (with its bots and decrees as the host sets them), the players' brawl, co-op waves of
## bots, the monster hunt, Red vs Blue, King of the Arena, the tournament (Tourney), King of the
## Hill, Last Limb Standing, Forge and Fight and the endless arena (Endless). Host side; `m` is the Match.

const TEAM_COLORS := [0xa02020, 0x2050b0, 0x208040, 0xc0a020, 0x8030a0, 0x20a0a0, 0xd06020, 0x606060]
const ALL := ["duel", "bo3", "ffa", "pvp", "coop", "hunt", "teams", "king", "tourney", "hill", "lastLimb", "forgefight", "endless"]
const TITLES := {"duel": "Test fight!", "bo3": "Duel!", "ffa": "Free for all!", "pvp": "Players brawl!", "coop": "Co-op campaign!",
	"hunt": "Monster Hunt!", "teams": "Red vs Blue!", "king": "King of the Arena!", "tourney": "The Tournament!",
	"hill": "King of the Hill!", "lastLimb": "Last Limb Standing!", "forgefight": "Forge and Fight!", "endless": "The endless arena!"}
const LABELS := {"teams": "Red against Blue", "hill": "Hold the circle for 20 s", "lastLimb": "A limb lost every 15 s", "king": "The winner stays on",
	"bo3": "Floored? Y yields · F fights on", "forgefight": "To the death", "tourney": "Knockout"}

var m: Node
var mode := "duel"
var wave := 0
var wait_t := 0.0
var bo3 := {}
var king := {}
var hill := {}
var chop_t := 15.0
var chops := 0
var ring: MeshInstance3D = null
var last_winner = null
var difficulty := 0.7
var fight_s := 0.0   # Forge and Fight: the host's limit on the fight (0: to the death)
var fight_t := 0.0
const TOURNEY_CAP := 120.0   # a tournament's bout that goes on past this (two who will not close, or cannot) is the one with the most blood left's
## A fight where the fallen stand up again (user: Free For All on a clock, most kills wins, whoever dies stands up again and fights on; the hill too): how long they lie, the clock
## (`time_s`, seconds: 0 is no clock) and the tally ({t: seconds gone, kills, deaths: by entity id, fell: id -> seconds until he stands again}).
const RESPAWN_S := 3.0
const HILL_CAP := 300.0     # a hill held by nobody for twenty seconds is over after this: the most seconds on it
var time_s := 0.0
var dm := {}
var endless: Endless = null
var rounds := 0            # the host's rounds setting for this fight, in the sense of Series.kind (0: the fight's own)
var bots_opt := -1         # how many bots the host asked for (-1: the fight's usual; for Red vs Blue -1 is "fill the sides")
var pair_names: Array = [] # the tournament's bout: the names of the bots in it (the players are the room's, picked by `pair`)
var tourney_line := ""     # ... and what the HUD says of it ("The semi-final · Aulus against Crixus")
## The fights that are played in a room as bouts of a pair of it, the rest looking on (Menu picks the pair, `opts.pair`): the tournament, the duel and the king's court.
const PAIR_MODES := ["tourney", "bo3", "king"]
var paired := false        # this bout is such a pair's
var goal_waves := 0        # the hunt and the waves of gladiators: waves to clear to win (0: until the player falls)
var round_key := ""        # who the round just ended is for, as Series keys him (a player, a bot, a team)
var teams_chosen := false  # a team fight whose teams the players chose in the yard (TeamSetup): the sides are theirs, bots fill them
var bot_teams: Array = []  # ... and the side of each bot, one by one
var side_total := [0, 0]   # ... how many stand on each side at the start, and how many of them are placed already
var side_next := [0, 0]
var round_name := ""

func _init(match_: Node, mode_: String) -> void:
	m = match_
	mode = mode_

static func handles(mode_: String) -> bool:
	return ALL.has(mode_)

## How many of the Emperor's decrees a fight is under: the duel's one now and then, the free-for-all's as the host chose
## (none, one or three: what the Chaos fight was).
static func decree_count(mode_: String, opts: Dictionary) -> int:
	if mode_ == "ffa":
		return FightOpts.clean_value("ffa", "decrees", opts.get("decrees_n"))
	return 1 if mode_ == "duel" else 0

## A fight's name as the HUD gives it (a guest has no Modes of his own to ask).
static func title_of(mode_: String) -> String:
	return Loc.t(String(TITLES.get(mode_, mode_.capitalize()))).trim_suffix("!")

## The team a player (the i-th) fights for.
static func player_team(mode_: String, i: int) -> int:
	match mode_:
		"teams": return i % 2
		"coop", "hunt", "endless": return 0
	return i

static func coop_like(mode_: String) -> bool:
	return mode_ == "coop" or mode_ == "hunt"

func bot_count(players: int) -> int:
	if bots_opt >= 0 and FightOpts.BOT_MODES.has(mode):
		return FightOpts.bots_allowed(players, bots_opt)
	match mode:
		"duel", "bo3": return 1 if not (mode == "bo3" and players >= 2) else 0
		"ffa", "hill", "lastLimb", "king": return 3 if mode != "king" else 1
		"teams": return maxi(0, 4 - players)
		"coop": return maxi(2, players)
	return 0

static func spawn_pos(index: int, total: int) -> Vector3:
	var a := float(index) / maxf(2.0, float(total)) * TAU + 0.3
	var r := minf(15.0 - 2.0, 3.5 if total <= 2 else 5.0)   # a few strides apart: room to square up
	return Vector3(sin(a) * r, 0.02, cos(a) * r)

## Spawns the players and everything the mode starts with.
func setup(opts: Dictionary) -> void:
	difficulty = float(opts.get("difficulty", 0.7))
	rounds = Series.clean_rounds(mode, opts.get("rounds"))
	goal_waves = rounds if Series.kind(mode) == "waves" else 0
	bots_opt = FightOpts.clean_value(mode, "bots", opts.get("bots")) if opts.has("bots") and FightOpts.BOT_MODES.has(mode) else -1
	fight_s = maxf(0.0, float(opts.get("fight_s", 0.0)))
	time_s = float(FightOpts.clean_value(mode, "time", opts.get("time_n"))) * 60.0 if FightOpts.TIMED_MODES.has(mode) and opts.has("time_n") else 0.0
	var players := []
	players.append({"kind": "local", "name": opts.get("name", "Gladiator"), "loadout": opts.get("loadout", {"main": "gladius", "off": "roundShield"}), "skin": opts.get("skin"), "build": opts.get("build", "")})
	for p in opts.get("peers", []):
		players.append({"kind": "remote", "peer": p.id, "name": p.name, "loadout": p.get("loadout", {"main": "gladius"}), "kit": p.get("kit", {}), "skin": p.get("skin"), "build": p.get("build", "")})
	var bots := bot_count(players.size())
	# A bout of a pair (the tournament's, the duel's and the king's, in a room): only the two of the pair fight (the rest of the room watch, with no fighter of their own).
	var pair: Array = opts.get("pair") if opts.get("pair") is Array else []
	paired = PAIR_MODES.has(mode) and (not pair.is_empty() or mode == "tourney")
	if paired:
		var peers_in: Array = pair.filter(func(e): return e is Dictionary and not bool(e.get("bot", false))).map(func(e): return int(e.get("peer", -1)))
		players = players.filter(func(p): return peers_in.has(1 if p.kind == "local" else int(p.get("peer", -1))))
		pair_names = pair.filter(func(e): return e is Dictionary and bool(e.get("bot", false))).map(func(e): return String(e.get("name", "Crixus")))
		bots = pair_names.size()
		tourney_line = String(opts.get("bout_line", opts.get("tourney_line", "")))
	# The teams the players chose in the yard: each on his side, the bots filling the sides up (TeamSetup.fill_plan).
	var chosen: Dictionary = opts.get("teams") if opts.get("teams") is Dictionary and TeamSetup.is_team_mode(mode) else {}
	var side_of := []
	if not chosen.is_empty():
		var counts := [0, 0]
		for p in players:
			var tm := clampi(int(chosen.get(1 if p.kind == "local" else int(p.get("peer", -1)), -1)), -1, 1)
			side_of.append(tm)
		for i in side_of.size():
			if int(side_of[i]) < 0:
				side_of[i] = i % 2   # (one who came after: the side his turn falls on)
			counts[int(side_of[i])] += 1
		teams_chosen = true
		bot_teams = TeamSetup.fill_plan(counts) if bots_opt < 0 else TeamSetup.balance_plan(counts, bots)
		bots = bot_teams.size()
		side_total = [counts[0], counts[1]]
		for tm in bot_teams:
			side_total[int(tm)] += 1
	# (A fight with nobody to fight is no fight: one bot at least.)
	if not teams_chosen and players.size() + bots < 2:
		bots = 1
	var total := players.size() + bots
	# With a screen the friends' men are built over the frames that follow the start, the player's own at once (Match.bring_in, as in the yard): eight men built in the one frame were a stop of
	# 0.9 s (the user's record: "match setup: endless as host, 8 men in 918 ms"). Each is in the place he would have had and has his kit when he is in; none of the rules that end a round
	# is asked while any is on his way (Modes.check). Only where the player is one of them (a fight with nobody of the host's own in it is built as it was).
	var late_in: bool = m.stage_start() and players.any(func(q): return q.kind == "local")
	var staged := []
	var kits := {}
	for i in players.size():
		var p: Dictionary = players[i]
		var team := int(side_of[i]) if teams_chosen else player_team(mode, i)
		var pos := _side_pos(team) if teams_chosen else spawn_pos(i, total)
		var spec := {"kind": p.kind, "peer": p.get("peer", -1), "name": p.name, "loadout": p.loadout, "team": team, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "color": TEAM_COLORS[team % TEAM_COLORS.size()], "skin": p.get("skin"), "build": p.get("build", ""), "slot": i}
		if late_in and p.kind == "remote":
			staged.append(spec)
			kits[int(p.get("peer", -1))] = Net.sanitize_kit(p.get("kit", {}))
			continue
		var e = m.spawn_fighter(spec)
		e.inventory = opts.get("inventory", {}) if p.kind == "local" else Net.sanitize_kit(p.get("kit", {}))
		if p.kind == "local":
			m.me = e
	m.players_count = players.size()
	if not staged.is_empty():
		var mm: Match = m
		var on_in := func(e):
			var id := int(e.get("peer", -1))
			if Net.active() and not Net.peers.has(id):
				mm.drop_peer(id)   # (he left while his man was being built: Net.peer_left found no man of his to take away)
				return
			e.inventory = kits.get(id, {})
		mm.bring_in(staged, on_in, true)
	if opts.get("autopilot", false) and m.me:
		m.me.bot = Bot.new(m.me.f, float(opts.get("autopilot_diff", 0.9)), "standard", 99)
	wave = 1 if coop_like(mode) else 0
	match mode:
		"hunt":
			spawn_hunt_wave()
		"bo3":
			bo3 = {"round": 1, "max": rounds, "wins": {}, "stake": 30, "pause": 0.0, "loser": null, "choice": ""}
			spawn_bots(bots, players.size(), total)
		"king":
			king = {"streak": 0, "max": rounds}
			spawn_bots(bots, players.size(), total)
		"endless":
			endless = Endless.new(m, opts.get("endless", {}))
		_:
			spawn_bots(bots, players.size(), total)
	match mode:
		"hill":
			hill = {"p": Vector3.ZERO, "r": 2.4, "need": 20.0, "score": {}, "king": null}
			_ring(Vector3.ZERO, 2.4, Color(0.95, 0.8, 0.3, 0.5))
	if respawns():
		dm = {"t": 0.0, "kills": {}, "deaths": {}, "fell": {}}
	m._banner(TITLES.get(mode, "Fight!"), (Loc.t("Most kills in %d minutes") % int(time_s / 60.0) if time_s > 0.0 else LABELS.get(mode, "Wave 1" if coop_like(mode) else "")))
	if endless:
		endless.begin()

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

## The next place on a side, in a line on his half of the sand.
func _side_pos(team: int) -> Vector3:
	var k: int = side_next[team]
	side_next[team] += 1
	return TeamSetup.spawn_pos(team, k, int(side_total[team]))

func spawn_bots(n: int, offset: int, total: int) -> void:
	var names: Array = pair_names if not pair_names.is_empty() else Data.modes.get("botNames", ["Crixus"])
	var los: Array = Data.modes.get("randomLoadouts", [{"main": "gladius", "off": "roundShield"}])
	var personalities := ["standard", "berserker", "duelist", "turtle", "brute", "skirmisher"]
	# (A wave that comes in while the fight goes on: over the frames that follow, Match.bring_in.)
	var staged: bool = m.staging()
	var specs := []
	for i in n:
		var idx := offset + i
		var team := 1 if coop_like(mode) else (idx % 2 if mode == "teams" else idx)
		var pos := spawn_pos(idx, total)
		if teams_chosen and i < bot_teams.size():
			team = int(bot_teams[i])
			pos = _side_pos(team)
		var lo: Dictionary = los[m.rng.randi_range(0, los.size() - 1)]
		var spec := {"kind": "bot", "name": names[i % names.size()] if not pair_names.is_empty() else names[(idx + wave * 3) % names.size()], "loadout": {"main": lo.main if lo.main else "", "off": lo.off if lo.off else ""},
			"team": team, "pos": pos, "yaw": atan2(-pos.x, -pos.z), "mods": _bot_mods(), "diff": difficulty, "personality": personalities[m.rng.randi_range(0, personalities.size() - 1)],
			"color": 0x303030 if coop_like(mode) else TEAM_COLORS[team % TEAM_COLORS.size()]}
		if staged:
			specs.append(spec)
		else:
			m.spawn_fighter(spec)
	if staged:
		m.bring_in(specs)

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
	var players := maxi(1, maxi(m.humans().size(), m.players_count))   # (the party's size: a friend's man may be on his way in)
	var total := 0
	for g in groups:
		total += 1 if g.get("boss", false) else int(g.n) + int((players - 1) / 2)
	var i := 0
	var names := []
	# (A wave that comes in while the hunt goes on: over the frames that follow, Match.bring_in.)
	var staged: bool = m.staging()
	var specs := []
	for g in groups:
		var n: int = 1 if g.get("boss", false) else int(g.n) + int((players - 1) / 2)
		var sp: Dictionary = Data.beasts.get(g.beast, {})
		for k in n:
			var a := float(i) / maxf(1.0, total) * TAU + PI
			i += 1
			var pos := Vector3(sin(a) * 7.5, 0.1, cos(a) * 7.5)
			var scale := float(sp.get("scale", 1.0)) * float(g.get("scaleMul", 1.0)) * (1.15 if g.get("boss", false) else 1.0)
			var spec := {"kind": "beast", "beast": g.beast, "scale": scale, "name": g.get("name", sp.get("name", g.beast)), "boss": g.get("boss", false), "team": 1, "pos": pos, "yaw": atan2(-pos.x, -pos.z)}
			if staged:
				specs.append(spec)
			else:
				m.spawn_beast(spec)
		names.append((Loc.t("%s (boss)") % g.get("name", sp.get("name", g.beast))) if g.get("boss", false) else ("%d × %s" % [n, sp.get("name", g.beast)]))
	if staged:
		m.bring_in(specs)
	m.feed.emit(Loc.t("Wave %d: %s") % [wave, ", ".join(names)])

## The fallen of a party stand up again as a wave of the hunt is beaten (those at death's door too), as in the endless arena: nobody lies through the rest of it (user: every mode of the Arena fits many players).
func _raise_fallen() -> void:
	for e in m.humans().duplicate():
		if is_instance_valid(e.f) and (not e.f.alive or e.f.dying > 0.0) and not e.get("swapping", false):
			if m.staging():
				m._respawn_apart(e)
			else:
				m.respawn_player(e)

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
		"endless": endless.update(dt)
	if mode == "bo3" and not paired:
		_bo3(dt, local_inp)
	if respawns():
		_stand_up(dt)

# ---------- Where the fallen stand up again ----------

## Whether the fallen stand up again in this fight: a melee or a team fight on a clock, and the hill.
func respawns() -> bool:
	return time_s > 0.0 or mode == "hill"

## Each step: the clock runs, the fallen are counted, and each stands up again after RESPAWN_S, in the place farthest from the men still on their feet (Match.respawn_player, or built
## apart over the frames with a screen). One who can do no more (Match._unfit) is fallen too.
func _stand_up(dt: float) -> void:
	if m.over or wait_t > 0.0 or m.coming > 0 or dm.is_empty():
		return
	dm.t += dt
	for e in m.entities.duplicate():
		if e.kind == "beast" or e.get("harmless", false) or not is_instance_valid(e.f):
			continue
		if e.f.alive:
			if float(e.get("unfit_t", 0.0)) >= Match.UNFIT_OUT:
				e.f.die("wounds")
			continue
		if e.get("swapping", false):
			continue
		if not dm.fell.has(e.id):
			dm.fell[e.id] = RESPAWN_S
			dm.deaths[e.id] = int(dm.deaths.get(e.id, 0)) + 1
			if e.kind == "local":
				m._banner(Loc.t("You fell"), Loc.t("Back on your feet in %d seconds") % int(RESPAWN_S))
			elif e.kind == "remote" and Net.active():
				Net.send_to(int(e.get("peer", -1)), "banner", {"text": Loc.t("You fell"), "sub": Loc.t("Back on your feet in %d seconds") % int(RESPAWN_S)})
		else:
			dm.fell[e.id] -= dt
			if float(dm.fell[e.id]) <= 0.0:
				dm.fell.erase(e.id)
				_stand_again(e)

func _stand_again(e: Dictionary) -> void:
	var p := _spawn_point(int(e.team))
	e.spec["pos"] = p
	e.spec["yaw"] = atan2(-p.x, -p.z)
	if m.staging():
		await m._respawn_apart(e)
	else:
		m.respawn_player(e)

## Where a man stands up: of a ring of places (a team's, on its own side), the one farthest from every man on his feet.
func _spawn_point(team: int) -> Vector3:
	var best := Vector3(0, 0.02, 8.0)
	var best_d := -1.0
	var on_feet := _alive_fighters()
	for k in 12:
		var p: Vector3
		if mode == "teams":
			p = Vector3((-1.0 if team % 2 == 0 else 1.0) * m.rng.randf_range(4.0, 7.0), 0.02, m.rng.randf_range(-6.0, 6.0))
		else:
			var a: float = TAU * (float(k) + float(m.rng.randf())) / 12.0
			p = Vector3(sin(a) * 8.0, 0.02, cos(a) * 8.0)
		var dmin := 99.0
		for o in on_feet:
			dmin = minf(dmin, Vector2(o.f.torso.global_position.x - p.x, o.f.torso.global_position.z - p.z).length())
		if dmin > best_d:
			best_d = dmin
			best = p
	return best

## One kill is set down for the man who dealt it (Match._credit_kill): a man's own, not a team-mate's.
func on_kill(victim, attacker) -> void:
	if time_s <= 0.0 or dm.is_empty() or m.over:
		return
	var ve = m.entity_of(victim)
	var ae = m.entity_of(attacker)
	if ve == null or ae == null or ve == ae or int(ve.team) == int(ae.team):
		return
	dm.kills[ae.id] = int(dm.kills.get(ae.id, 0)) + 1

## The tally as rows [name, kills, deaths, team, id], the most kills first, then the fewest deaths: the scoreboard (and the friends are sent it).
func board() -> Array:
	var rows := []
	if dm.is_empty():
		return rows
	for e in m.entities:
		if e.kind == "beast" or e.get("harmless", false) or not is_instance_valid(e.f):
			continue
		rows.append([String(e.f.display_name), int(dm.kills.get(e.id, 0)), int(dm.deaths.get(e.id, 0)), int(e.team), int(e.id)])
	rows.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and (a[2] < b[2] or (a[2] == b[2] and a[4] < b[4]))))
	return rows.slice(0, 8)

## The kills of each team (Red, Blue), and the deaths.
func _team_tally() -> Array:
	var out := [[0, 0], [0, 0]]
	for e in m.entities:
		if e.kind == "beast" or e.get("harmless", false):
			continue
		var tm := int(e.team) % 2
		out[tm][0] += int(dm.kills.get(e.id, 0))
		out[tm][1] += int(dm.deaths.get(e.id, 0))
	return out

## The clock is out: the one with the most kills wins (the fewer deaths if level; level still, nobody: a draw). In the team fight, the team.
func _clock_end() -> void:
	if dm.is_empty() or float(dm.t) < time_s:
		return
	var winner = null
	if mode == "teams":
		var tl := _team_tally()
		var win_team := -1
		if int(tl[0][0]) != int(tl[1][0]):
			win_team = 0 if int(tl[0][0]) > int(tl[1][0]) else 1
		elif int(tl[0][1]) != int(tl[1][1]):
			win_team = 0 if int(tl[0][1]) < int(tl[1][1]) else 1
		if win_team >= 0:
			var side: Array = m.entities.filter(func(e): return e.kind != "beast" and int(e.team) % 2 == win_team and is_instance_valid(e.f))
			var up: Array = side.filter(func(e): return e.f.alive)
			winner = (up[0] if not up.is_empty() else (side[0] if not side.is_empty() else null))
	else:
		var rows := board()
		if rows.size() == 1 or (rows.size() > 1 and (int(rows[0][1]) != int(rows[1][1]) or int(rows[0][2]) != int(rows[1][2]))):
			winner = m.entity_by_id(int(rows[0][4]))
	_win(winner)

func _alive_fighters() -> Array:
	return m.entities.filter(func(e): return e.f.alive and e.kind != "beast")

func _hill(dt: float) -> void:
	var inside: Array = _alive_fighters().filter(func(e): return Vector2(e.f.torso.global_position.x - hill.p.x, e.f.torso.global_position.z - hill.p.z).length() < hill.r)
	if inside.size() == 1:
		var e: Dictionary = inside[0]
		hill.score[e.id] = float(hill.score.get(e.id, 0.0)) + dt
		if hill.king != e.id:
			hill.king = e.id
			m.feed.emit(Loc.t("%s holds the hill") % e.f.display_name)
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
	m._banner("THUMBS DOWN", Loc.t("The Emperor takes a limb from everyone (%d)") % chops)
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
		if choice == "yield" or not l.alive or int(bo3.round) >= int(bo3.max):
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
		m._banner(Loc.t("Round %d") % bo3.round, Loc.t("%s fights on, wounded. The stake is %d denarii") % [l.display_name, bo3.stake])
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
		if not c.alive or int(bo3.wins[winner.id]) >= int(bo3.max) / 2 + 1 or int(bo3.round) >= int(bo3.max):
			_bo3_end()
			return
		bo3.pause = 8.0
		if c.alive:
			m._tape_kill(c, "out")
		m._round_replay()
		m._banner(Loc.t("Round %d to %s") % [bo3.round, winner.f.display_name], "You are down. Y: yield · F: fight on, wounded, for double the stake" if e.kind == "local" else Loc.t("%s is down and must choose: yield, or fight on for double the stake") % c.display_name)
		return

func _bo3_end() -> void:
	var f: Array = m.entities.filter(func(e): return e.kind != "beast")
	# Level on rounds (one each, and the man down yields): the duel is his who did not yield.
	# Sorted by the rounds alone, a level score went to whoever was first on the list, as often
	# as not the man who had just yielded.
	var lost_id = bo3.loser.id if bo3.get("loser") is Dictionary else null
	f.sort_custom(func(x, y):
		var wx := int(bo3.wins.get(x.id, 0))
		var wy := int(bo3.wins.get(y.id, 0))
		return wx > wy or (wx == wy and y.id == lost_id and x.id != lost_id))
	var w: Dictionary = f[0]
	var score := "%d-%d" % [int(bo3.wins.get(f[0].id, 0)), int(bo3.wins.get(f[1].id, 0))]
	m._end(w == m.me, Loc.t("%s wins the duel %s") % [w.f.display_name, score], Loc.t("For %d denarii") % bo3.stake, int(bo3.stake) if w == m.me else 0)

## The end of a round, by the mode's own rules.
func check(dt: float) -> void:
	if m.over:
		return
	# (Not while a wave is still on its way in, built over these frames: Match.bring_in.)
	if m.coming > 0:
		return
	# One who has lain unable to stand for a while is out (Match._unfit), as in any bout.
	var alive: Array = m.entities.filter(func(e): return e.f.alive and not m._unfit(e, dt) and not e.get("harmless", false))
	var humans_alive: Array = m.humans().filter(func(e): return e.f.alive and float(e.get("unfit_t", 0.0)) < Match.UNFIT_OUT)
	# A fight on a clock ends on the clock, whoever is standing.
	if time_s > 0.0:
		_clock_end()
		return
	match mode:
		"hill":
			for id in hill.score:
				var e = m.entity_by_id(int(id))
				if e and float(hill.score[id]) >= float(hill.need) and e.f.alive:
					_win(e)
					return
			# (The fallen stand up again, so the last one standing is no end of it: a hill nobody holds for the twenty seconds is the most seconds on it's, after HILL_CAP.)
			if not dm.is_empty() and float(dm.t) >= HILL_CAP:
				var top = null
				var ts := 0.0
				for id in hill.score:
					if float(hill.score[id]) > ts:
						ts = float(hill.score[id])
						top = m.entity_by_id(int(id))
				_win(top)
			return
		"lastLimb":
			var fa2: Array = _alive_fighters()
			if fa2.size() <= 1:
				_win(fa2[0] if fa2.size() else null)
			return
		"bo3":
			if not paired:
				return   # (the duel of one man against a bot ends by its own rules: _bo3; a pair of friends' is a bout like any other, and its rounds the match's: Series)
		"endless":
			endless.check(dt, alive, humans_alive)
			return
		"forgefight":
			# Out of time: the one standing with the most blood left takes it.
			fight_t += dt
			if fight_s > 0.0 and fight_t >= fight_s:
				_win(ForgeFight.leader(_alive_fighters()))
				return
		"tourney":
			# Every bout of a tournament is watched through to its end (the bouts of bots too): one that will not end is ended by the clock, as above (a level one is the menu's coin).
			fight_t += dt
			if fight_t >= TOURNEY_CAP:
				_win(ForgeFight.leader(_alive_fighters()))
				return
		"hunt":
			if humans_alive.is_empty():
				m._end(false, Loc.t("The monsters won in wave %d") % wave, "")
				return
			if not alive.any(func(e): return e.kind == "beast" and e.team == 1):
				if goal_waves > 0 and wave >= goal_waves:
					m._end(true, Loc.t("You cleared %d waves!") % wave, "", 10 * wave)
					return
				_raise_fallen()
				_heal(humans_alive, 22.0)
				m._round_replay()
				_next_wave("Wave %d!", "The gates open again")
				spawn_hunt_wave()
			return
		"coop":
			if humans_alive.is_empty():
				m._end(false, Loc.t("You fell in wave %d") % wave, "")
				return
			if not alive.any(func(e): return e.kind == "bot"):
				if goal_waves > 0 and wave >= goal_waves:
					m._end(true, Loc.t("You cleared %d waves!") % wave, "", 10 * wave)
					return
				_heal(humans_alive, 35.0)
				m._round_replay()
				_next_wave("Wave %d!", "The crowd wants more blood")
				var n := mini(5, ceili(wave * 0.7) + m.players_count - 1)
				spawn_bots(n, m.entities.size(), m.entities.size() + n)
				if wave % 3 == 0:
					m.bring_in([{"kind": "beast", "beast": "lion", "team": 1, "pos": Vector3(0, 0.1, 12), "yaw": PI}])
					m.feed.emit(Loc.t("Wave %d: the lions join in!") % wave)
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
	if mode == "king" and winner and not paired:
		if winner.kind == "bot" or int(king.streak) + 1 >= int(king.max):
			m._end(winner == m.me, (Loc.t("%s reigns: the players are all down after %d bouts") % [winner.f.display_name, king.streak]) if winner.kind == "bot" else (Loc.t("%s is King of the Arena: %d bouts unbeaten!") % [winner.f.display_name, king.max]), "", 60 if winner == m.me else 0)
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
		m._banner(Loc.t("%s holds the arena (%d)") % [c.display_name, king.streak], "The next challenger walks in")
		spawn_bots(1, m.entities.size(), m.entities.size() + 1)
		wait_t = 2.0
		return
	_win(winner)

## Who a round is for, as the match's score keeps him: a team in a team fight, else the one man (a player by his peer, a bot by name).
func _claim(winner) -> void:
	round_key = ""
	round_name = ""
	if winner == null:
		return
	if mode == "teams":
		round_key = Series.team_key(int(winner.team))
		round_name = Series.team_name(int(winner.team))
	elif winner.kind == "bot":
		round_key = Series.bot_key(String(winner.f.display_name))
		round_name = String(winner.f.display_name)
	else:
		round_key = Series.human_key(1 if winner.kind == "local" else int(winner.get("peer", -1)))
		round_name = String(winner.f.display_name)

func _win(winner) -> void:
	last_winner = winner.f if winner else null
	_claim(winner)
	var mine: bool = winner != null and m.me != null and (winner == m.me or (mode == "teams" and winner.team == m.me.team))
	var text := (Loc.t("%s team wins!") % Loc.t(["Red", "Blue"][winner.team % 2])) if mode == "teams" and winner else ((Loc.t("%s wins!") % winner.f.display_name) if winner else "Draw!")
	var sub := ""
	var verdict: Dictionary = m.spectacle.verdict(winner.f if winner else null)
	if mine:
		sub = verdict.text
	m._end(mine, text, sub, (m.round_pay + 20 + int(verdict.bonus / 4)) if mine else 0)

func status() -> String:
	if paired and tourney_line != "":
		return tourney_line
	if time_s > 0.0 and not dm.is_empty():
		var clock := ForgeFight.clock(maxf(0.0, time_s - float(dm.t)))
		if mode == "teams":
			var tl := _team_tally()
			return "%s · %s %d – %d %s" % [Loc.t("%s left") % clock, Loc.t("Red"), int(tl[0][0]), int(tl[1][0]), Loc.t("Blue")]
		var rows := board()
		return "%s%s" % [Loc.t("%s left") % clock, (" · %s %d" % [rows[0][0], int(rows[0][1])]) if not rows.is_empty() and int(rows[0][1]) > 0 else ""]
	match mode:
		"hill":
			var best = null
			var bs := 0.0
			for id in hill.score:
				if float(hill.score[id]) > bs:
					bs = hill.score[id]
					best = m.entity_by_id(int(id))
			return (Loc.t("%s %ds to go") % [best.f.display_name, ceili(hill.need - bs)]) if best else "nobody on the hill"
		"lastLimb": return Loc.t("next chop in %ds") % ceili(chop_t)
		"forgefight": return (Loc.t("%s left") % ForgeFight.clock(fight_s - fight_t)) if fight_s > 0.0 else Loc.t("to the death")
		"hunt", "coop": return (Loc.t("Wave %d of %d") % [wave, goal_waves]) if goal_waves > 0 else (Loc.t("Wave %d") % wave)
		"king": return Loc.t("Reign: %d of %d") % [king.streak, king.max]
		"bo3": return Loc.t("Round %d · stake %d") % [bo3.round, bo3.stake]
		"tourney": return tourney_line if tourney_line != "" else TITLES.tourney.trim_suffix("!")
		"endless": return endless.status()
	return TITLES.get(mode, "")
