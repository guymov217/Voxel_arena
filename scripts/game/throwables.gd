class_name Throwables
extends Node3D
## Pots, arrows, darts and the rest (throwables.js, weaponFx.js): what each one does where it
## breaks, the zones they leave on the sand (sand cloud, fire, acid, caltrops, oil, honey,
## smoke), the burning spray of Greek fire, the hotbar of a campaign kit, and the weapons that
## shoot (bows, crossbows, flame poles). Host side; `m` is the Match.

const POTS := {"thunderPot": "pot_thunder", "nailPot": "pot_nail", "sandPot": "pot_sand", "greekFire": "pot_fire", "vitriol": "pot_acid", "beehive": "pot_bees",
	"caltrops": "pot_caltrops", "goat": "pot_goat", "bola": "pot_bola", "oliveOil": "pot_oil", "garum": "pot_garum", "honey": "pot_honey", "smoke": "pot_smoke",
	"mystery": "pot_mystery", "chickens": "pot_chickens", "anvil": "pot_anvil", "harpoon": "pot_harpoon", "discus": "pot_discus", "bigNet": "pot_bignet"}
const THROW_SPEED := {"pot_anvil": 7.2, "pot_harpoon": 19.0, "pot_discus": 18.0, "pot_bola": 15.5}
const NAILS := 96
const CALTROPS := 14
const ZONE_COLORS := {"sand": Color(0.85, 0.75, 0.54, 0.45), "fire": Color(1.0, 0.48, 0.1, 0.55), "acid": Color(0.56, 0.83, 0.23, 0.7), "caltrops": Color(0.36, 0.37, 0.4, 1.0),
	"oil": Color(0.16, 0.23, 0.06, 0.7), "honey": Color(0.91, 0.63, 0.13, 0.75), "smoke": Color(0.6, 0.6, 0.6, 0.5)}

var m: Node
var zones: Array = []
var drops: Array = []
var next_zone := 1
var headless := false

func _init(match_: Node) -> void:
	m = match_
	headless = match_.headless

static func hotbar_of(inv: Dictionary) -> Array:
	var out := []
	for id in Data.shop.get("throwables", {}):
		if int(inv.get(id, 0)) > 0:
			out.append(id)
	return out

# ---------- Effects (cheap one-shot particle bursts) ----------

## A burst of particles in the colours of `color` (the effects module picks the kind).
func burst(p: Vector3, color: Color, n: int, speed := 2.0, _life := 0.7, _size := 0.05, _up := 1.0) -> void:
	var fx: Fx = m.fx
	if fx == null:
		return
	var kind := "debris"
	if color.r > 0.9 and color.g < 0.75 and color.b < 0.4:
		kind = "fire"
	elif color.g > color.r and color.g > color.b + 0.2:
		kind = "acid"
	elif color.r > 0.6 and color.g > 0.55 and color.b > 0.35 and color.b < color.g:
		kind = "dust"
	elif color.r > 0.7 and color.g < 0.3:
		kind = "blood"
	elif color.b > 0.8 and color.g > 0.8:
		kind = "sparks"
	fx.burst(kind, p, n, Vector3.UP, speed / 2.0)

func flash(p: Vector3, color: Color, energy := 8.0, r := 6.0) -> void:
	if m.fx:
		m.fx.flash(p, color, energy, r)

# ---------- Hits ----------

func _hit(c, part: VoxelPart, J: float, type: String, point: Vector3, dir: Vector3, owner_, extra := {}) -> Dictionary:
	var was_alive: bool = c.alive
	var h := {"impulse": J, "type": type, "hardness": extra.get("hardness", 0.9 if type == "point" else 0.6), "sharpness": extra.get("sharpness", 0.9 if type == "point" else 0.0), "point": point, "dir": dir, "axis": dir, "crush": extra.get("crush", 0.0), "heavy": extra.get("heavy", 0.0)}
	var res: Dictionary = c.apply_hit(part, h)
	if owner_ and owner_ != c:
		c.last_attacker = owner_
	m.report_hit({"kind": "hit", "p": point, "dir": dir, "J": J, "type": type, "char": c, "part": part, "attacker": owner_, "res": res, "killed": was_alive and not c.alive})
	return res

func _near(p: Vector3, r: float) -> Array:
	var out := []
	for e in m.entities:
		var c = e.f
		if not c.alive:
			continue
		var d: float = c.torso.global_position.distance_to(p)
		if d < r:
			out.append({"c": c, "d": d, "e": e})
	out.sort_custom(func(a, b): return a.d < b.d)
	return out

## A blast: every part of everyone in reach takes a blow on the side turned to it, harder the
## closer it is.
func blast(p: Vector3, radius := 3.5, power := 24.0, owner_ = null) -> void:
	for e in m.entities:
		var c = e.f
		if not c.alive:
			continue
		var hits := []
		for part in c.parts:
			if part.severed:
				continue
			var centre: Vector3 = part.global_position
			var to_p := p - centre
			var dc := to_p.length()
			var face := centre + to_p.normalized() * minf(dc, 0.1 * c.S)
			var d := face.distance_to(p)
			if d > radius:
				continue
			hits.append({"part": part, "face": face, "f": pow(1.0 - d / radius, 1.5)})
		hits.sort_custom(func(a, b): return a.f > b.f)
		for h in hits:
			if h.part.severed:
				continue
			var J: float = power * h.f
			if J < 3.0:
				continue
			_hit(c, h.part, J, "blunt", h.face, (h.face - p).normalized(), owner_, {"hardness": 0.6})

## Greek fire (or vitriol) breaks like a bottle: a spray of drops flying on their own momentum,
## and whatever a drop lands on catches where it landed (a body part, or the sand, where it pools).
func splash_burning(p: Vector3, dir, n: int, owner_, hit_part, hit_char, kind := "fire") -> void:
	var away := Vector3.UP
	if hit_part:
		away = p - hit_part.global_position
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 1e-4 else Vector3.UP
	var carry: Vector3 = (dir as Vector3) * 0.35 if dir != null else Vector3.ZERO
	for i in n:
		var a := randf() * TAU
		var up := randf()
		var v := (Vector3(cos(a), 0, sin(a)) * sqrt(1.0 - up * up) + Vector3(0, up, 0)).normalized()
		v = v.lerp(away, 0.45).normalized() * (1.2 + randf() * 2.6) + carry
		drops.append({"p": p + Vector3(randf_range(-0.04, 0.04), 0.04, randf_range(-0.04, 0.04)), "v": v, "fuel": 0.35 + randf() * 0.65, "life": 2.5, "owner": owner_, "acid": kind == "acid", "from": hit_char, "age": 0.0})
	if hit_part and hit_char and hit_char.alive:
		m.add_spot(hit_char, hit_part, kind, 6.0, owner_, p)
	burst(p, Color(1.0, 0.5, 0.1) if kind == "fire" else Color(0.56, 0.83, 0.23), 24, 2.5, 0.6, 0.04)

func _update_drops(dt: float) -> void:
	for d in drops.duplicate():
		d.life -= dt
		d.age += dt
		var from: Vector3 = d.p
		d.v.y -= 9.81 * dt
		d.v *= pow(0.7, dt)
		d.p += d.v * dt
		var done: bool = d.life <= 0.0
		if not done:
			# Did it land on someone between the last spot and this one?
			for e in m.entities:
				var c = e.f
				if not c.alive or (c == d.from and d.age < 0.3):
					continue
				for part in c.parts:
					if part.severed:
						continue
					if Social.box_distance(part, d.p) < 0.03:
						if d.acid:
							m.add_spot(c, part, "acid", 1.5 + 3.0 * d.fuel, d.owner, d.p)
						else:
							m.add_spot(c, part, "fire", 1.5 + 3.0 * d.fuel, d.owner, d.p)
						done = true
						break
				if done:
					break
		if not done and d.p.y <= 0.02:
			# On the sand it pools (a small fire or puddle, feeding one already there).
			var pool = null
			for z in zones:
				if z.type == ("acid" if d.acid else "fire") and Vector2(z.p.x - d.p.x, z.p.z - d.p.z).length() < z.r:
					pool = z
					break
			if pool:
				pool.t = maxf(pool.t, 3.0 + 4.0 * d.fuel)
			elif randf() < 0.35:
				add_zone("acid" if d.acid else "fire", Vector3(d.p.x, 0, d.p.z), 0.35 + 0.25 * d.fuel, 3.0 + 4.0 * d.fuel, d.owner)
			done = true
		if done:
			drops.erase(d)

# ---------- What breaks where ----------

## A pot (or an arrow, a dart, a stone) went off at `p`: on `hit_char`'s `hit_part` if it
## struck someone, else on the sand.
## Every pot breaks like a pot, whatever was in it: glazed shards flung off the way it was going
## and bouncing on the sand, a puff of clay dust, a splash of what it held, a crack of clay.
const CONTENTS := {"pot_fire": Color(1.0, 0.5, 0.12), "pot_acid": Color(0.56, 0.86, 0.22), "pot_oil": Color(0.25, 0.22, 0.08), "pot_honey": Color(0.95, 0.66, 0.12), "pot_garum": Color(0.55, 0.4, 0.18), "pot_sand": Color(0.86, 0.76, 0.52), "pot_smoke": Color(0.5, 0.5, 0.52), "pot_bees": Color(0.95, 0.75, 0.15), "pot_mystery": Color(0.85, 0.3, 0.7), "pot_nail": Color(0.55, 0.57, 0.6), "pot_caltrops": Color(0.3, 0.3, 0.3), "pot_chickens": Color(1.0, 0.95, 0.85), "pot_goat": Color(0.9, 0.88, 0.8), "pot_thunder": Color(0.4, 0.3, 0.5)}
func shatter(p: Vector3, type: String, dir = null) -> void:
	m.sfx("shatter", p, 1.0)
	var fx: Fx = m.fx
	if fx == null:
		return
	var glaze := Color.hex(int(Items.TYPES.get(type, {}).get("pot", 0x8a6a4a)) << 8 | 0xff)
	var d: Vector3 = (dir as Vector3) if dir is Vector3 and (dir as Vector3).length_squared() > 1e-4 else Vector3.UP
	var fling := (d.normalized() * Vector3(1, 0, 1) + Vector3(0, 1.2, 0)).normalized()
	fx.burst("debris", p, 28, fling, 1.2, glaze.darkened(0.15))
	fx.burst("debris", p, 14, Vector3.UP, 0.8, Color(0.7, 0.45, 0.3))   # the bare clay inside
	fx.burst("dust", p, 18, Vector3.UP, 0.8, Color(0.72, 0.55, 0.4, 0.5))
	fx.burst("bloodmist", p + Vector3(0, 0.1, 0), 16, fling, 1.0, Color(CONTENTS.get(type, glaze), 0.6))
	if p.y < 0.6:
		fx.mark("splat", Vector3(p.x, 0.01, p.z), 0.6)

func explode(type: String, p: Vector3, owner_ = null, dir = null, hit_char = null, hit_part = null, power := 1.0) -> void:
	var pot := type.begins_with("pot_") and not ["pot_bolt", "pot_dart", "pot_discus", "pot_harpoon", "pot_bola", "pot_bignet", "pot_anvil"].has(type) and not type.begins_with("pot_arrow")
	if pot:
		shatter(p, type, dir)
	match type:
		"pot_thunder":
			m.sfx("thud", p, 1.0)
			flash(p, Color(1.0, 0.8, 0.55), 14.0, 10.0)
			if m.fx:
				m.fx.burst("blastfire", p + Vector3(0, 0.25, 0), 70, Vector3.UP)
				m.fx.burst("dust", p, 140, Vector3.UP, 2.2)
				m.fx.burst("smoke", p + Vector3(0, 0.4, 0), 50, Vector3.UP, 1.5)
				m.fx.burst("sparks", p, 120, Vector3.UP, 2.0)
				m.fx.burst("debris", p, 50, Vector3.UP, 1.6)
				m.fx.mark("scorch", p, 2.6)
			blast(p, 3.8, 44.0, owner_)
			for x in _near(p, 3.5):
				var c = x.c
				var f: float = 1.0 - x.d / 3.5
				c.concussion = minf(1.0, c.concussion + 0.55 * f)
				var out: Vector3 = c.torso.global_position - p
				out.y = 0.5
				out = out.normalized()
				c.torso.apply_central_impulse(Vector3(out.x * 160.0 * f, 60.0 * f, out.z * 160.0 * f))
				if f > 0.35 and not c.mods.get("unstoppable", false):
					c.fall(1.6, true)
				if owner_:
					c.last_attacker = owner_
			m.feed.emit("BOOM!")
		"pot_nail":
			m.sfx("clang", p, 0.6)
			# The pot bursts into a hail of nails flying out every way, up, down and all round
			# (a few carried on with the pot). Each
			# is a real little dart: it goes in only where it meets a body and stays in it. The
			# man it broke on takes the nails that go his way.
			var fwd: Vector3 = (dir as Vector3).normalized() if dir is Vector3 and (dir as Vector3).length_squared() > 1e-4 else Vector3.ZERO
			for i in NAILS:
				var a := randf() * TAU
				var y := -0.55 + randf() * 1.45
				var d := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
				if fwd != Vector3.ZERO and randf() < 0.2:
					d = (d * 0.55 + fwd).normalized()   # carried on the way the pot was going
				var from := Vector3(p.x, maxf(0.15, p.y), p.z) - fwd * 0.06
				var it: Dictionary = m.items.spawn("nail", from, d * (22.0 + randf() * 14.0), owner_)
				it.from_char = hit_char
		"pot_sand":
			add_zone("sand", p, 3.2, 6.0, owner_)
			m.sfx("slap", p)
		"pot_fire":
			if p.y < 0.35 or hit_char == null:
				add_zone("fire", Vector3(p.x, 0, p.z), 0.9, 6.0, owner_)
			splash_burning(p, dir, 36, owner_, hit_part if hit_char and hit_char.alive else null, hit_char if hit_char and hit_char.alive else null)
			m.sfx("slash", p, 1.0)
		"pot_acid":
			if p.y < 0.35 or hit_char == null:
				add_zone("acid", Vector3(p.x, 0, p.z), 0.8, 10.0, owner_)
			splash_burning(p, dir, 36, owner_, hit_part if hit_char and hit_char.alive else null, hit_char if hit_char and hit_char.alive else null, "acid")
		"pot_caltrops":
			# The pot bursts and scatters real caltrops over the sand: each lands with a spike
			# up, and whoever walks over them (anyone) gets one in the foot.
			for i in CALTROPS:
				var a := randf() * TAU
				var out := 1.2 + randf() * 3.4
				m.items.spawn("caltrop", Vector3(p.x + cos(a) * 0.08, maxf(0.2, p.y), p.z + sin(a) * 0.08), Vector3(cos(a) * out, 1.0 + randf() * 2.5, sin(a) * out), owner_)
			m.feed.emit("Caltrops all over the sand. Watch your step.")
		"pot_bees":
			m.sfx("slap", p)
			for x in _near(p, 3.0):
				if x.c == owner_:
					continue
				x.c.bee_timer = 5.0
				if owner_:
					x.c.last_attacker = owner_
				m.feed.emit("%s is covered in bees!" % x.c.display_name)
		"pot_goat":
			m.spawn_beast({"beast": "goat", "team": 2, "pos": Vector3(p.x, 0.1, p.z), "yaw": 0.0, "harmless": true})
			m.feed.emit("The crowd laughs. Every beast wants the goat.")
		"pot_bola":
			for x in _near(p, 1.5):
				var c = x.c
				if c == owner_:
					continue
				c.set_net(true, 2.5)
				c.fall(4.0 if c.mods.get("cyclops", false) else 1.6, true)
				if owner_:
					c.last_attacker = owner_
				m.feed.emit("%s's legs are tied up" % c.display_name)
			m.sfx("slap", p)
		"pot_oil":
			add_zone("oil", Vector3(p.x, 0, p.z), 2.6, 14.0, owner_)
		"pot_garum":
			var dropped := 0
			for x in _near(p, 3.0):
				var c = x.c
				if c == owner_ or c.kind == "beast":
					continue
				c.stagger = minf(1.0, c.stagger + 0.5)
				c.concussion = minf(1.0, c.concussion + 0.2)
				for side in ["R", "L"]:
					var w = c.weapons.get(side)
					if w and not w.is_shield:
						c.release(side)
						dropped += 1
				if owner_:
					c.last_attacker = owner_
			m.feed.emit("Rotten fish sauce! %s" % ("%d weapon%s dropped in disgust." % [dropped, "s" if dropped > 1 else ""] if dropped else "The crowd holds its nose."))
			if owner_:
				m.crowd_add(owner_, 4, "disgusting")
		"pot_honey":
			add_zone("honey", Vector3(p.x, 0, p.z), 2.0, 12.0, owner_)
		"pot_smoke":
			add_zone("smoke", Vector3(p.x, 0, p.z), 3.0, 9.0, owner_)
			m.sfx("whoosh", p)
		"pot_mystery":
			var pick: String = ["pot_thunder", "pot_nail", "pot_goat", "pot_bees", "pot_chickens", "pot_confetti", "pot_grape", "pot_oil"][randi() % 8]
			m.feed.emit("The mystery amphora was... %s!" % ("a grape" if pick == "pot_grape" else ("confetti" if pick == "pot_confetti" else pick.trim_prefix("pot_"))))
			explode(pick, p, owner_)
		"pot_confetti":
			if m.fx:
				m.fx.burst("confetti", p + Vector3(0, 0.5, 0), 160, Vector3.UP, 1.3)
			m.sfx("cheer", p)
			if owner_:
				m.crowd_add(owner_, 15, "confetti!")
		"pot_grape":
			m.feed.emit("A single grape rolls out. The crowd is silent.")
			if owner_:
				m.crowd_add(owner_, -3, "a grape")
		"pot_chickens":
			var chicken := Data.preset("chicken")
			for i in 6:
				var w = m.spawn_loose_weapon(chicken, p + Vector3(randf_range(-0.2, 0.2), 0.4 + i * 0.1, randf_range(-0.2, 0.2)))
				if w:
					w.linear_velocity = Vector3(randf_range(-3.5, 3.5), 4.0 + randf() * 4.0, randf_range(-3.5, 3.5))
			m.feed.emit("CHICKENS EVERYWHERE!")
			if owner_:
				m.crowd_add(owner_, 10, "chickens")
		"pot_harpoon":
			var hv = hit_char if hit_char and hit_char != owner_ else null
			if hv == null:
				for x in _near(p, 1.2):
					if x.c != owner_:
						hv = x.c
						break
			if hv == null:
				return
			var hdir: Vector3 = (p - owner_.torso.global_position).normalized() if owner_ else Vector3(0, 0, 1)
			_hit(hv, hv.torso, 14.0, "point", hv.torso.global_position, hdir, owner_)
			hv.torso.bleed += 1.5
			if owner_:
				var pull: Vector3 = owner_.torso.global_position - hv.torso.global_position
				pull.y = 0.4
				hv.torso.apply_central_impulse(pull.normalized() * 260.0 * hv.S * hv.S)
				if hv.state == "stand":
					hv.fall(1.2)
				m.feed.emit("%s reeled in %s!" % [owner_.display_name, hv.display_name])
				m.crowd_add(owner_, 8, "catch of the day")
		"pot_bolt", "pot_arrow", "pot_arrow_fire", "pot_arrow_poison", "pot_arrow_ice", "pot_dart", "nail":
			_dart(type, p, owner_, dir, hit_char, hit_part, power)
		"pot_discus":
			m.sfx("clang", p, 0.5)
			var dv = _near(p, 1.1)
			if dv.is_empty():
				return
			var c = dv[0].c
			var part: VoxelPart = c.head if c.head.global_position.distance_to(p) < 0.35 else c.torso
			var ddir: Vector3 = p - owner_.torso.global_position if owner_ else Vector3(0, 0, 1)
			ddir.y = 0.0
			_hit(c, part, 16.0, "blunt", part.global_position, ddir.normalized(), owner_, {"hardness": 0.8})
			if c == owner_:
				m.feed.emit("%s got hit by their own discus" % c.display_name)
		"pot_bignet":
			var n := 0
			for x in _near(p, 1.8):
				if x.c == owner_:
					continue
				x.c.set_net(true, 4.0)
				n += 1
				if owner_:
					x.c.last_attacker = owner_
			m.feed.emit("%d caught in the big net" % n)
		"rock":
			if hit_char and hit_part:
				_hit(hit_char, hit_part, 9.0, "blunt", p, dir if dir != null else Vector3.DOWN, owner_, {"hardness": 0.7})
		"net":
			if hit_char:
				hit_char.set_net(true, 3.0)

func _dart(type: String, p: Vector3, owner_, dir, hit_char, hit_part, power := 1.0) -> void:
	# A nail only wounds what it actually met: one that reaches the sand lies there.
	if type == "nail" and (hit_char == null or hit_part == null):
		return
	if type == "pot_arrow_fire":
		add_zone("fire", Vector3(p.x, 0.0, p.z), 0.8, 3.0, owner_)
	var c = hit_char if hit_char and hit_char.alive and hit_char != owner_ else null
	if c == null:
		for x in _near(p, 0.9 if type == "pot_dart" else 1.0):
			if x.c != owner_:
				c = x.c
				break
	if c == null:
		return
	var part: VoxelPart = hit_part if hit_part and c.parts.has(hit_part) and not hit_part.severed else null
	if part == null:
		var bd := INF
		for q in c.parts:
			if q.severed:
				continue
			var d: float = q.global_position.distance_to(p)
			if d < bd:
				bd = d
				part = q
	if part == null:
		return
	var hdir: Vector3 = dir if dir != null else ((p - owner_.torso.global_position).normalized() if owner_ else Vector3(0, 0, 1))
	var was_alive: bool = c.alive
	var arrow := type.begins_with("pot_arrow")
	var headshot: bool = part == c.head and (arrow or type == "pot_bolt")
	# An arrow strikes as hard as the bow was drawn (a half draw stings, a full one goes deep);
	# a crossbow's bolt always has the whole of the prod behind it.
	if type == "nail":
		# A nail is a sting, not a stab: it goes in and stays, it bleeds a little. Out of one
		# burst only the first dozen in a body count; the rest just stick (a dragon catches half
		# the hail, and every nail at full weight bled it dry in seconds and stalled the game).
		var now := Time.get_ticks_msec()
		var nh: Array = c.get_meta("nail_hits", [0, 0])
		if now - int(nh[0]) > 1500:
			nh = [now, 0]
		nh[1] = int(nh[1]) + 1
		c.set_meta("nail_hits", nh)
		if int(nh[1]) <= 12:
			_hit(c, part, 1.2, "point", p, hdir, owner_)
			part.bleed += 0.06 / maxf(1.0, c.S)
		part.stick("nail", p, hdir)
		return
	var J := (17.0 if type == "pot_bolt" else ((3.0 + 13.0 * clampf(power, 0.0, 1.0)) if arrow else 10.0)) * ((1.2 if c.S >= 1.5 else 1.8) if headshot else 1.0)
	_hit(c, part, J, "point", p, hdir, owner_)
	if headshot:
		c.concussion = minf(1.0, c.concussion + 0.5)
		m.feed.emit("HEADSHOT! %s%s's head%s" % [(owner_.display_name + " puts one in ") if owner_ else "", c.display_name, ". Down and out." if was_alive and not c.alive else ""])
	if type == "pot_bolt":
		part.bleed += 1.0
		part.stick("pot_bolt", p, hdir)
	if arrow:
		part.bleed += (0.5 + 1.0 * clampf(power, 0.0, 1.0)) / maxf(1.0, c.S * 0.6)
		part.stick(type, p, hdir)
	if type == "pot_arrow_fire":
		m.add_spot(c, part, "fire", 4.0, owner_, p)
	if type == "pot_arrow_poison":
		part.bleed += 2.0
		c.slow(3.0, 0.7)
		m.add_spot(c, part, "acid", 5.0, owner_, p)
	if type == "pot_arrow_ice":
		c.slow(4.0, 0.45)
		burst(p, Color(0.66, 0.91, 1.0), 12, 1.5, 0.6, 0.03)

## What an item event means: a splat (it broke, or struck someone), food eaten, a banana
## slipped on, a cheese wheel bowling a man over, a boomerang caught.
func on_item(ev: Dictionary) -> void:
	var c = ev.get("char")
	var it: Dictionary = ev.item
	var owner_ = it.get("owner")
	match ev.kind:
		"strike":
			# A heavy thing's blow is its momentum: 30 kg of iron at a walking throw's speed
			# crushes what it lands on and puts a man down.
			var part: VoxelPart = ev.part
			var spd: float = ev.speed
			var J := minf(95.0, float(ev.mass) * spd * 0.42)
			m.sfx("thud", ev.p, 1.0)
			burst(ev.p, Color(0.6, 0.5, 0.4), 14, 2.0)
			if part and c and c.alive:
				# It crushes what it lands on: a dent the size of the blow, flesh and bone.
				var crush := minf(0.12, 0.03 + J * 0.0009) * sqrt(float(c.S))
				_hit(c, part, J, "blunt", ev.p, ev.dir, owner_, {"hardness": 1.0, "crush": crush, "heavy": clampf(J / 60.0, 0.0, 1.0)})
				var push: Vector3 = (ev.dir as Vector3) * float(ev.mass) * spd * 0.35
				c.torso.apply_central_impulse(Vector3(push.x, maxf(0.0, push.y), push.z))
				if c.state == "stand" and J > 25.0 and not c.mods.get("unstoppable", false):
					c.fall(2.0)
				m.feed.emit("An anvil hits %s. Classic." % c.display_name)
				if owner_ and owner_ != c:
					m.crowd_add(owner_, 10, "anvil")
		"land":
			m.sfx("thud", ev.p, minf(1.0, float(ev.speed) / 8.0))
			if m.fx:
				m.fx.burst("dust", ev.p, 16, Vector3.UP, 0.8)
				m.fx.mark("crater", ev.p, 0.5)
		"splat":
			if ev.type == "tomato":
				if c:
					m.feed.emit("SPLAT! A tomato hits %s" % c.display_name)
					m.crowd_add(c, -2, "tomato")
				burst(ev.p, Color(0.82, 0.16, 0.11), 10, 1.5, 0.5, 0.03)
			else:
				explode(ev.type, ev.p, owner_, ev.get("dir"), c, ev.get("part"), float(it.get("power", 1.0)))
		"eat":
			match ev.type:
				"bread":
					c.blood = minf(100.0, c.blood + 30.0)
					m.feed.emit("%s eats the bread" % c.display_name)
				"wine":
					c.stamina = 100.0
					c.wine_timer = 10.0
					c.mods.drunk = maxf(float(c.mods.drunk), 0.3)
					m.feed.emit("%s downs the wine" % c.display_name)
				"coin":
					m.feed.emit("%s pockets a gold coin" % c.display_name)
					m.on_coin(c)
		"caltrop":
			var part: VoxelPart = ev.part
			var foot: bool = part.def.get("leg", false) and c.state == "stand"
			var Jc := 7.0 * sqrt(float(c.S)) if foot else 4.0
			var was: bool = c.alive
			var res: Dictionary = c.apply_hit(part, {"impulse": Jc, "type": "point", "hardness": 0.95, "sharpness": 1.0, "point": ev.p, "dir": Vector3.UP, "axis": Vector3.UP})
			part.bleed += 0.8
			if not headless:
				part.stick("caltrop", ev.p, Vector3.UP)
			if foot:
				# He snatches the foot up and hops: slower for a while, the leg buckling under him.
				c.slow(2.5, 0.5)
				part.flinch_t = maxf(part.flinch_t, 0.8)
				c.stagger = minf(1.0, c.stagger + 0.35 / float(c.S))
				m.feed.emit("%s steps on a caltrop!" % c.display_name)
				m.crowd_add(c, -2, "caltrop")
			if owner_ and owner_ != c:
				c.last_attacker = owner_
			m.report_hit({"kind": "hit", "p": ev.p, "dir": Vector3.UP, "J": Jc, "type": "point", "char": c, "part": part, "attacker": owner_, "res": res, "killed": was and not c.alive})
		"slip":
			c.fall(1.6, true)
			c.torso.apply_central_impulse(Vector3(0, 30.0, 0))
			m.feed.emit("%s slipped on a banana peel!" % c.display_name)
			m.crowd_add(c, -3, "banana")
			m.sfx("whoosh", ev.p)
		"ram":
			c.fall(1.4, true)
			m.feed.emit("%s is bowled over by a cheese wheel" % c.display_name)
			if owner_:
				m.crowd_add(owner_, 6, "cheese")
		"return":
			m.feed.emit("%s caught the boomerang" % c.display_name)
		"kick":
			if m.modes:
				m.modes.kick_ball(ev)

# ---------- Zones ----------

func add_zone(type: String, p: Vector3, r: float, t: float, owner_ = null) -> Dictionary:
	var z := {"id": next_zone, "type": type, "p": p, "r": r, "t": t, "owner": owner_, "tick": 0.0, "node": null}
	next_zone += 1
	if not headless:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 1.6 if type == "sand" or type == "smoke" else 0.02
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ZONE_COLORS.get(type, Color.WHITE)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if type == "fire" else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if type == "sand" or type == "smoke":
			mat.albedo_color.a = 0.3
		cm.material = mat
		mi.mesh = cm
		add_child(mi)
		mi.global_position = Vector3(p.x, 0.8 if type == "sand" or type == "smoke" else 0.02, p.z)
		z.node = mi
	zones.append(z)
	if m.fx and (type == "fire" or type == "acid"):
		m.fx.mark("scorch" if type == "fire" else "acid", p, r * 2.2)
	if m.fx and type == "fire" and r >= 0.5 and t > 2.0 and z.node:
		var fl: GPUParticles3D = m.fx.emitter("fire", z.node, int(clampf(r * 40.0, 12.0, 80.0)), r * 0.8)
		if fl:
			fl.emitting = true
	if m.role == "host":
		Net.send_all("zone", {"type": type, "p": [p.x, p.y, p.z], "r": r, "t": t})
	return z

func inside(type: String, pos: Vector3) -> bool:
	for z in zones:
		if z.type == type and Vector2(pos.x - z.p.x, pos.z - z.p.z).length() < z.r:
			return true
	return false

## Bots in sand or smoke, or covered in bees, cannot fight properly.
func impaired(c) -> bool:
	return c.bee_timer > 0.0 or inside("sand", c.torso.global_position) or inside("smoke", c.torso.global_position)

func update(dt: float) -> void:
	_update_drops(dt)
	for z in zones.duplicate():
		z.t -= dt
		z.tick -= dt
		if z.node and z.type == "fire":
			z.node.mesh.material.albedo_color.a = 0.4 + sin(m.time * 20.0) * 0.1
		if m.role != "guest" and z.tick <= 0.0:
			z.tick = 0.6 if z.type == "caltrops" else 0.5
			for e in m.entities:
				var c = e.f
				if not c.alive or Vector2(c.torso.global_position.x - z.p.x, c.torso.global_position.z - z.p.z).length() > z.r:
					continue
				var v: Vector3 = c.torso.linear_velocity
				match z.type:
					"oil":
						if c.state != "stand" or Vector2(v.x, v.z).length() < 1.1:
							continue
						c.fall(1.4)
						c.torso.apply_central_impulse(Vector3(v.x * 8.0, 40.0, v.z * 8.0))
						m.crowd_add(c, -3, "slip")
						m.feed.emit("%s slipped in the olive oil" % c.display_name)
					"honey":
						c.slow(0.7, 0.3)
						if c.bee_timer > 0.0:
							c.bee_timer += 0.3
					"fire":
						var low: float = c.S * 0.65
						for part in c.parts:
							if not part.severed and (c.state != "stand" or part.global_position.y < low) and randf() < 0.6:
								m.add_spot(c, part, "fire", 2.5, z.owner, Vector3(part.global_position.x, 0, part.global_position.z))
						c.blood = maxf(0.0, c.blood - 0.5)
					"acid":
						var low2: float = c.S * 0.45
						for part in c.parts:
							if not part.severed and (c.state != "stand" or part.global_position.y < low2) and randf() < 0.5:
								m.add_spot(c, part, "acid", 2.0, z.owner, Vector3(part.global_position.x, 0, part.global_position.z))
					"caltrops":
						if Vector2(v.x, v.z).length() < 0.5:
							continue
						var shin = null
						for n in ["shinL", "shinR"]:
							var sp = c.by_name.get(n)
							if sp and not sp.severed:
								shin = sp
								break
						if shin:
							var sp2: Vector3 = shin.global_position
							_hit(c, shin, 5.0, "point", Vector3(sp2.x, 0.05, sp2.z), Vector3.UP, z.owner)
		if z.t <= 0.0:
			if z.node:
				z.node.queue_free()
			zones.erase(z)
	# Bees sting the man they cover now and then.
	if m.role != "guest":
		for e in m.entities:
			var c = e.f
			if c.bee_timer > 0.0:
				c.bee_timer -= dt
				if c.alive and randf() < dt * 2.0:
					var part: VoxelPart = c.parts[randi() % c.parts.size()]
					if not part.severed:
						_hit(c, part, 3.0, "point", part.global_position, Vector3.DOWN, null, {"hardness": 0.5, "sharpness": 0.5})
						c.stagger = minf(1.0, c.stagger + 0.15)

func clear() -> void:
	for z in zones:
		if z.node:
			z.node.queue_free()
	zones.clear()
	drops.clear()

# ---------- The hotbar ----------

## Uses the kit item in hotbar `slot`: food and bandages at once; anything thrown goes into the
## free hand for a player (aimed and thrown with F), straight at the target for a bot.
func use_item(e: Dictionary, slot: int) -> bool:
	var inv: Dictionary = e.get("inventory", {})
	var bar := hotbar_of(inv)
	if slot < 0 or slot >= bar.size():
		return false
	var id: String = bar[slot]
	var c = e.f
	if not c.alive:
		return false
	inv[id] = int(inv[id]) - 1
	var fwd := Vector3(sin(c.yaw), 0, cos(c.yaw))
	var player: bool = e.kind == "local" or e.kind == "remote"
	var hand_type = POTS.get(id, {"darts": "pot_dart", "boomerang": "boomerang"}.get(id))
	if hand_type != null and player:
		hold_item(e, hand_type, id)
		return true
	match id:
		"bandage":
			for p in c.parts:
				p.bleed = 0.0
				p.stump = false
			c.torso.hp = minf(100.0, c.torso.hp + 15.0)
			m.feed.emit("%s bandaged up" % c.display_name)
		"bread":
			c.blood = minf(100.0, c.blood + 40.0)
		"wine":
			c.stamina = 100.0
			c.wine_timer = 10.0
			c.mods.drunk = maxf(float(c.mods.drunk), 0.3)
		"cheese":
			var cp: Vector3 = c.torso.global_position + fwd * 0.8
			var it: Dictionary = m.items.spawn("cheese", Vector3(cp.x, 0.12, cp.z), fwd * 7.0, c)
			it.grounded = true
			m.feed.emit("%s bowled a cheese wheel" % c.display_name)
		"bananas":
			for i in [-1, 0, 1]:
				var bp: Vector3 = c.torso.global_position + fwd * 1.2 + Vector3(fwd.z * i * 0.6, 0, -fwd.x * i * 0.6)
				var it2: Dictionary = m.items.spawn("banana", Vector3(bp.x, 0.06, bp.z), Vector3.ZERO, c)
				it2.grounded = true
			m.feed.emit("%s laid a banana trap" % c.display_name)
		_:
			var tgt = m.nearest_enemy(e)
			var aim: Vector3 = tgt.f.torso.global_position if tgt else c.torso.global_position + fwd * 6.0
			var ia = e.get("last_aim")
			if player and ia is Vector3:
				aim = ia   # a player's pot goes to the crosshair
			throw_type(c, hand_type, aim, null, player)
	return true

## A pot readied in the free hand (the left, or the right if the left is busy): held where it
## can be seen until F throws it.
func hold_item(e: Dictionary, type: String, id: String) -> void:
	var c = e.f
	drop_held(c)
	var node = null
	if not headless:
		node = Items.visual(type)
		var side := "L" if not c.weapons.L else "R"
		c.arm[side].fore.add_child(node)
		node.position = c.hand_point
	c.held_item = {"type": type, "id": id, "node": node}
	if e.kind == "local":
		m.feed.emit("%s ready: hold F to aim, let go to throw" % Data.shop.throwables.get(id, {}).get("name", id))

func drop_held(c) -> void:
	if c.held_item == null:
		return
	if c.held_item.node and is_instance_valid(c.held_item.node):
		c.held_item.node.queue_free()
	c.held_item = null

## Throws the readied pot where the player looks (power from the wind-up).
func throw_held(e: Dictionary, inp: Dictionary) -> void:
	var c = e.f
	var h = c.held_item
	if h == null:
		return
	drop_held(c)
	var look = inp.get("look", {"yaw": c.yaw, "pitch": 0.0})
	var power := clampf(float(inp.get("throwPower", 0.8)), 0.3, 1.0)
	var dir := Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch), cos(look.yaw) * cos(look.pitch))
	var reach := 4.0 + 10.0 * power
	var aim: Vector3 = c.head.global_position + dir * reach
	if inp.get("aimAt") is Vector3:
		aim = Social.aim_ahead(c, inp.aimAt, look)
	aim.y = maxf(0.1, aim.y)
	throw_type(c, h.type, aim, null, true, power)

## `straight`: a player's throw flies along the line to the crosshair (the flat one of the two
## arcs that reach it, or along the line itself when it is out of reach), never a lob.
func throw_type(c, type: String, aim: Vector3, _dir, straight := false, power := 0.8) -> void:
	var from: Vector3 = c.hand_world("L" if not c.weapons.L else "R") + Vector3(0, 0.3, 0)
	if type == "pot_dart":
		var fwd: Vector3 = (aim - from)
		fwd.y = 0.0
		fwd = fwd.normalized()
		for i in [-1, 0, 1]:
			var da := aim + Vector3(fwd.z * i * 0.5, i * 0.15, -fwd.x * i * 0.5)
			if straight:
				m.items.throw_flat("pot_dart", from, da, c, 19.0)
			else:
				m.items.throw_at("pot_dart", from, da, c, 15.0)
	elif type == "boomerang":
		m.items.throw_at("boomerang", from, aim, c, 12.0, 0.0)
	elif straight:
		m.items.throw_flat(type, from, aim, c, float(THROW_SPEED.get(type, 14.5)) * (0.8 + 0.35 * power))
	else:
		m.items.throw_at(type, from, aim, c, THROW_SPEED.get(type, 14.5))
	m.sfx("whoosh", from)

# ---------- Weapons that shoot ----------

## A bow: hold the button to draw, let go to loose an arrow where the archer looks (bots at their
## target). Power comes from the draw time and the length of the limbs. A crossbow shoots a bolt
## on a thrust; a flame pole sets alight what its jet plays over.
func update_shooters(dt: float) -> void:
	for e in m.entities:
		var c = e.f
		if c.kind == "beast" or not c.alive:
			continue
		c.off_goal = null
		for side in ["R", "L"]:
			var w = c.weapons.get(side)
			if w == null or not w.design.has("shoots"):
				continue
			var inp: Dictionary = e.get("input", {})
			match String(w.design.shoots):
				"arrow":
					_draw_bow(e, w, inp, dt)
				"bolt":
					# A thrust, or (a player) a click of that hand's button.
					var click := false
					if e.kind == "local" or e.kind == "remote":
						var pw: bool = inp.get("power", false)
						click = pw and not w.get_meta("pw", false)
						w.set_meta("pw", pw)
					_crossbow(e, w, 1.0 if click else float(inp.get("thrust" if side == "R" else "offThrust", 0.0)), dt, inp)
				"flame":
					_flame(e, w, float(inp.get("thrust" if side == "R" else "offThrust", 0.0)), dt)

func _draw_bow(e: Dictionary, w: Weapon, inp: Dictionary, dt: float) -> void:
	var c = e.f
	var held: bool = inp.get("power", false)
	var ys := []
	for v in w.design.voxels:
		ys.append(v[1])
	# A war bow is hard work: a long pull (longer the longer the limbs, slower tired), a pause to
	# nock the next arrow after each shot, and a full draw held costs breath fast.
	var draw_time := (0.9 + (int(ys.max()) - int(ys.min())) * 0.035) * (1.0 + 0.6 * (1.0 - minf(1.0, c.stamina / 100.0)))
	var nock: float = maxf(0.0, float(w.get_meta("nock", 0.0)) - dt)
	w.set_meta("nock", nock)
	var draw: float = w.get_meta("draw", 0.0)
	var hold_t: float = w.get_meta("hold_t", 0.0)
	if held and nock > 0.0 and draw <= 0.0:
		return
	if held:
		if draw <= 0.0:
			m.sfx("draw", w.global_position, 0.6)
		draw = minf(1.0, draw + dt / draw_time)
		hold_t += dt
		if draw >= 1.0:
			c.stamina = maxf(0.0, c.stamina - 12.0 * dt)
		w.set_meta("draw", draw)
		w.set_meta("hold_t", hold_t)
		_show_draw(w, c, draw)
		return
	_show_draw(w, c, 0.0)
	w.set_meta("draw", 0.0)
	w.set_meta("hold_t", 0.0)
	if draw <= 0.2:
		return
	w.set_meta("nock", 0.8)
	var from: Vector3 = w.global_transform * w.center_of_mass + Vector3(0, 0.15, 0)
	var vel: Vector3
	var look = inp.get("look")
	var player: bool = e.kind == "local" or e.kind == "remote"
	if player and inp.get("aimAt") is Vector3:
		# Where the crosshair sits, allowing for the drop over the distance (weaponFx.js): a
		# short draw, a long hold or a tired arm scatters it a little.
		var speed := ARROW_SPEED.x + ARROW_SPEED.y * draw
		var dd: Vector3 = (inp.aimAt as Vector3) - from
		var dist := dd.length()
		var wobble := _bow_wobble(c, draw, hold_t)
		var a1 := randf() * TAU
		var r1 := sqrt(randf()) * wobble
		var sd := Vector3(dd.z, 0, -dd.x).normalized()
		var upv := sd.cross(dd).normalized()
		dd += sd * cos(a1) * r1 * dist + upv * sin(a1) * r1 * dist
		var t := maxf(0.1, dist / speed)
		vel = Vector3(dd.x / t, (dd.y + 0.5 * 9.81 * t * t) / t, dd.z / t)
		from += dd.normalized() * 0.5
	elif player and look != null:
		var speed := ARROW_SPEED.x + ARROW_SPEED.y * draw
		var wobble := _bow_wobble(c, draw, hold_t)
		var dir := Vector3(sin(look.yaw) * cos(look.pitch), sin(look.pitch) + 0.06, cos(look.yaw) * cos(look.pitch)).normalized()
		dir = dir.rotated(Vector3.UP, randf_range(-wobble, wobble)).normalized()
		dir.y += randf_range(-wobble, wobble)
		vel = dir.normalized() * speed
		from += dir * 0.5
	else:
		var tgt = m.nearest_enemy(e)
		var aim: Vector3 = tgt.f.torso.global_position + Vector3(0, 0.2, 0) if tgt else from + Vector3(sin(c.yaw) * 8.0, 0.5, cos(c.yaw) * 8.0)
		var dd := aim - from
		var t := maxf(0.15, dd.length() / (ARROW_SPEED.x + ARROW_SPEED.y * draw))
		vel = Vector3(dd.x / t, (dd.y + 0.5 * 9.81 * t * t) / t, dd.z / t)
		from += dd.normalized() * 0.5
	var gem = w.design.get("gem")
	var type: String = ("pot_arrow_" + str(gem)) if gem != null and Items.TYPES.has("pot_arrow_" + str(gem)) else "pot_arrow"
	var it: Dictionary = m.items.spawn(type, from, vel, c)
	it.power = draw
	m.sfx("twang", from)
	m.sfx("whoosh", from, 0.6)
	c.stamina = maxf(0.0, c.stamina - 9.0)

## Arrows fly fast and near straight (a dropping lob was the old slow arrow): speed at no draw
## plus what a full draw adds, m/s.
const ARROW_SPEED := Vector2(20.0, 38.0)
const BOLT_SPEED := 58.0

## How far off the mark the arrow may go: a short draw, a full draw held too long (the arm
## shakes from about a second), a tired archer, one on the move or on the ground.
func _bow_wobble(c, draw: float, hold_t: float) -> float:
	var tired: float = 1.0 - minf(1.0, c.stamina / 100.0)
	var lv: Vector3 = c.torso.linear_velocity
	var moving := minf(1.0, Vector2(lv.x, lv.z).length() / 3.0)
	return (0.008 + 0.045 * (1.0 - draw) + 0.03 * minf(1.0, maxf(0.0, hold_t - 1.0) / 2.0) + 0.03 * tired + 0.03 * moving) * (1.0 if c.state == "stand" else 2.0)

## The crossbow's string and bolt: `k` 0 just shot (the string slack at the prod, no bolt) to
## 1 cocked and loaded. In between the free off hand works the string back to the latch.
func _show_cock(w: Weapon, c, k: float) -> void:
	var vs: float = w.vs
	var latch_y := 15.0 * vs
	var prod_y := 18.0 * vs
	# Hand to the string at the prod (first fifth), haul it to the latch, lay the bolt (last fifth).
	var pull := clampf((k - 0.2) / 0.6, 0.0, 1.0)
	var sy := lerpf(prod_y, latch_y, pull * pull * (3.0 - 2.0 * pull))
	if k < 1.0 and c.weapons.L == null and c.arm.L.fore.function() > 0.2:
		c.off_goal = w.global_transform * Vector3(0, sy if k > 0.2 else prod_y, 0.0)
	if Fx.current == null or Fx.current.headless:
		return
	var vis: Node3D = w.get_node_or_null("CockVis")
	if vis == null:
		var bolt := Items.visual("pot_bolt")
		vis = _cords_node(w, bolt)
		vis.name = "CockVis"
		bolt.basis = Basis(Vector3(1, 0, 0), -PI / 2.0)   # its nose (+z) up the stock (+y)
	# The voxel string is the cocked one; while cocking it is drawn by the cords instead.
	_set_cords(vis, Vector3(-7.0 * vs, latch_y, 0), Vector3(7.0 * vs, latch_y, 0), Vector3(0, sy, 0))
	(vis.get_child(0) as Node3D).visible = k < 1.0
	(vis.get_child(1) as Node3D).visible = k < 1.0
	var bolt_n: Node3D = vis.get_child(2)
	bolt_n.visible = k >= 0.85
	bolt_n.position = Vector3(0, latch_y + 0.17, 0.04)
	w.set_string_hidden(k < 1.0)

func _tip(w: Weapon) -> Array:
	var top := -999
	for v in w.design.voxels:
		top = maxi(top, int(v[1]))
	var q := w.global_transform.basis.get_rotation_quaternion()
	return [w.global_transform * Vector3(0, (top + 1) * w.vs, 0), q * Vector3.UP]

## The drawn bow (weaponFx.js showDraw): the string pulled back to the nock with an arrow laid
## on it, and the off hand there pulling. The stave runs up the bow's y, the string on its -x
## side, the arrow flies out along +x.
func _show_draw(w: Weapon, c, d: float) -> void:
	var vs: float = w.vs
	var ys := []
	var sx := 0.0
	for v in w.design.voxels:
		if v[3] == "leather" and v[0] < 0:
			ys.append(v[1])
			sx = minf(sx, v[0])
	var y0: float = (ys.min() if not ys.is_empty() else 2) * vs
	var y1: float = (ys.max() if not ys.is_empty() else 18) * vs
	sx *= vs
	var pull := sx - d * 7.0 * vs
	var ym := (y0 + y1) * 0.5
	var nock := Vector3(pull, ym, 0)
	c.off_goal = w.global_transform * nock
	if Fx.current == null or Fx.current.headless:
		return
	var vis: Node3D = w.get_node_or_null("DrawVis")
	if vis == null:
		vis = _cords_node(w, Items.visual(("pot_arrow_" + str(w.design.gem)) if w.design.get("gem") != null else "pot_arrow"))
		vis.name = "DrawVis"
		var ar: Node3D = vis.get_child(2)
		ar.basis = Basis(Vector3.UP, PI / 2.0)   # its nose (+z) along the shot (+x)
	vis.visible = d > 0.0
	if d <= 0.0:
		return
	_set_cords(vis, Vector3(sx, y0, 0), Vector3(sx, y1, 0), nock)
	(vis.get_child(2) as Node3D).position = Vector3(pull + 0.3, ym, 0)

## Two cords from the string's ends to the nock, and (third child) what lies on the string.
func _cords_node(w: Weapon, load_vis: Node3D) -> Node3D:
	var vis := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.94, 0.91, 0.82)
	mat.roughness = 0.9
	for i in 2:
		var cm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.014, 0.014, 1.0)
		bm.material = mat
		cm.mesh = bm
		cm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		vis.add_child(cm)
	load_vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vis.add_child(load_vis)
	vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	w.add_child(vis)
	return vis

func _set_cords(vis: Node3D, a: Vector3, b: Vector3, nock: Vector3) -> void:
	for i in 2:
		var end: Vector3 = a if i == 0 else b
		var seg := nock - end
		var cord: MeshInstance3D = vis.get_child(i)
		var l := maxf(0.01, seg.length())
		var z := seg / l
		var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
		cord.transform = Transform3D(Basis(x, z.cross(x), z * l), end + seg * 0.5)

## A crossbow (weaponFx.js shoot, extended): after each bolt the string is cocked again, the
## off hand hauling it back from the prod to the latch while the bolt is laid in, and only then
## can it shoot. A player shoots where the crosshair is, allowing for the drop; a bot at its man.
const CROSSBOW_RELOAD := 2.2
func _crossbow(e: Dictionary, w: Weapon, thrust: float, dt: float, inp := {}) -> void:
	var c = e.f
	var reload: float = maxf(0.0, w.get_meta("reload", 0.0) - dt)
	w.set_meta("reload", reload)
	_show_cock(w, c, 1.0 - reload / CROSSBOW_RELOAD if reload > 0.0 else 1.0)
	if thrust < 0.6 or reload > 0.0:
		return
	var td := _tip(w)
	w.set_meta("reload", CROSSBOW_RELOAD)
	var tgt = m.nearest_enemy(e)
	var aim: Vector3 = tgt.f.torso.global_position if tgt else td[0] + td[1] * 8.0
	if (e.kind == "local" or e.kind == "remote") and inp.get("aimAt") is Vector3:
		aim = inp.aimAt
	var bolt: Dictionary = m.items.throw_flat("pot_bolt", td[0], aim, c, BOLT_SPEED)
	bolt.power = 1.0
	m.sfx("clang", td[0], 0.4)
	c.stamina = maxf(0.0, c.stamina - 8.0)

func _flame(e: Dictionary, w: Weapon, thrust: float, dt: float) -> void:
	var c = e.f
	var reload: float = maxf(0.0, w.get_meta("reload", 0.0) - dt)
	w.set_meta("reload", reload)
	if thrust < 0.6 or reload > 0.0:
		return
	w.set_meta("reload", 0.35)
	var fuel: int = int(w.get_meta("fuel", 12)) - 1
	w.set_meta("fuel", fuel)
	if fuel < 0:
		w.set_meta("reload", 2.0)
		return
	var td := _tip(w)
	var tip: Vector3 = td[0]
	var dir: Vector3 = td[1]
	var zp := tip + dir * 0.9
	add_zone("fire", Vector3(zp.x, 0.05, zp.z), 0.9, 1.6, c)
	for o in m.entities:
		var oc = o.f
		if oc == c or not oc.alive:
			continue
		for part in oc.parts:
			if part.severed:
				continue
			var along := clampf((part.global_position - tip).dot(dir), 0.0, 1.8)
			var at := tip + dir * along
			if at.distance_to(part.global_position) < 0.22 * oc.S:
				m.add_spot(oc, part, "fire", 3.0, c, at)
	burst(tip + dir * 0.4, Color(1.0, 0.6, 0.15), 10, 2.0, 0.4, 0.04, -0.2)
