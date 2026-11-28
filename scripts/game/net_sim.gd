class_name NetSim
extends RefCounted
## A net as it is in the world (the retiarius's, and the weighted net of the kit): a mesh of ropes with a lead weight at each knot of its rim. A rope has no stiffness, it only cannot
## be drawn past its length, so a net is a heap of slack that a throw flings open, that the air holds back at the middle while the weighted rim leads, that falls into a bowl over what
## it meets and hangs there on its own weight and on what it drapes over. Position based: the knots are drawn together by their ropes, and out of the bodies they are in (a man's parts,
## the sand, the arena wall), the rope's own slack taken up as it comes. (user: the net looked bad, a lattice of thin boxes thrown like a pot; it must work in physics as a net does, and be
## thrown as a net is thrown; and it must look caught on the man and never pass through him.) Pure logic: it is told where the fighters are, and says who it has caught; Items throws it,
## draws it and Throwables acts on the catch.
##
## No way through a body: a knot is followed along its way within a step (a swept test against each part's padded box, the part as it will be at the end of the step), so that however fast it
## goes it cannot be on the other side of him next; a rope that comes to a limb is stopped at the face it came to (its middle put out, its ends with it, never out by the far side); round a limb
## thinner than a rope is long the padding is made up to it, so that no rope lies across a limb with its ends on both sides; and where a net holds a man its knots that lie on him CATCH there
## (they ride on his parts as he moves, and let go only when their ropes are drawn tight), so it hangs on him, over his head, his shoulders and his limbs, and goes where he goes. What is drawn
## is drawn off the knots, about the bodies where they are when it is drawn, and put out of every box (shaders/net.gdshader, by the same boxes); the threads drawn between the ropes are not
## drawn where a body is, so a limb through a square of the net has the net about it and no thread through it.

const STEP := 1.0 / 60.0         # the net's own step (the world's is 120 a second: half the work, and the ropes do not need more)
const ITER := 4                  # passes over the ropes in a step
const GRAVITY := 9.81
const OPEN_T := 0.42             # s a thrown net takes to come open
const BUNDLE := 0.16             # how small it is in the hand, of its full size
const SPIN := 2.2                # rad/s it is thrown with (a throw's twist: it opens as it turns)
const DRAG_RIM := 0.55           # 1/s: a lead weight flies on...
const DRAG_ROPE := 2.1           # ...and the open rope between them is held back by the air: the middle lags, the net is a bowl
const RIM_INV_MASS := 0.35       # (the weights are heavy beside the rope: they pull it)
const THICK := 0.035             # m: how far from a body's box a knot is kept (the rope's own thickness, and what his skin stands out of the box)
const ARMOUR_PAD := 0.035        # m: more still round the trunk and the head, where the plates and the crest stand out
const ROPE_R := 0.012            # m: the drawn rope's own half thickness, kept out of the box too
const THIN_PAD := 0.06           # m: the most a thin part of a man (a limb, a hand) is padded more, so that a rope cannot lie across it with its ends on both sides
const FLOOR := 0.02              # a knot rests this high on the sand
const WALL := 14.7               # the arena's wall (Items.RADIUS less a little)
const MAX_SPEED := 14.0
const CLING_RANGE := 0.6         # m: how near a man's body a knot is for the net that holds him to draw it onto him
const MIN_TOUCH := 7             # knots against one man that make him caught...
const HOLD_T := 0.14             # ...for this long
const GRIP := 0.9                # how much of its slide a knot loses against a body it lies on (a rope on cloth and flesh)
const SAND_GRIP := 0.45
const CLING := 0.16              # how much of the way to the body it is drawn, a step, by a net that holds a man (its weights and the pull of its ropes close it round him)
const BUNCH := 0.5               # how close the knots may be drawn together, of a rope's length (a net does not crush to a point: its knots and weights have size)
const PIN_T := 0.1               # s a knot of a net that holds a man lies on him before it catches there
const PIN_SLIDE := 0.9           # m/s: the most it may slide on him and still catch
const PIN_STRAIN := 1.12         # a knot that has caught lets go when a rope of it is drawn this far past its length...
const PIN_STRAIN_T := 0.12       # ...for this long
const HOOD_R := 0.9              # m: a net whose middle is this near a man's head when it has caught him is drawn over his head
const HOOD_T := 0.5              # s it takes to draw it there
const OWNER_FREE := 0.3          # s a net that has just left a hand does not touch the man who threw it (it is at his hand)
const OWNER_CATCH := 1.2         # s before it can come down over him that threw it
const FAST := 0.05               # m a step: a knot that goes further than this is followed along its way
const SUB := 3                   # the drawn mesh: each square of the net as this many by this
const MAX_BOXES := 48            # the boxes the drawing is told of

var cell := 0.25                 # the length of a rope between two knots
var n := 0                       # knots
var P := PackedVector3Array()    # where they are
var V := PackedVector3Array()    # how they move
var Q := PackedVector3Array()    # where the step is taking them
var W := PackedFloat32Array()    # 1 / mass (0 for a knot that has caught on a man)
var K := PackedFloat32Array()    # drag
var RIM := PackedByteArray()     # 1: a knot of the rim (weighted)
var EA := PackedInt32Array()     # the ropes: the knots at their two ends
var EB := PackedInt32Array()
var NB := PackedInt32Array()     # the knots a knot is roped to (four a knot, -1 for none)
var UV := PackedVector2Array()   # where each knot is on the net as it was knitted (in ropes: the drawn mesh follows it)
var radius := 1.0                # of the net open
var center := Vector3.ZERO       # where its middle is now
var velocity := Vector3.ZERO     # how the middle moves
var reach := 1.0                 # the farthest a knot is from the middle now
var low := 0.0                   # the lowest knot
var age := 0.0
var rest_t := 0.0                # s it has lain still on the sand
var caught: Array = []           # the men it holds
var pinned := 0                  # the knots that have caught on a man
var held_t := {}                 # fighter -> s in sustained contact
var held_for := {}               # fighter -> s he has been held in it (a guest lets him go when the time of a net is out: it is not told by the host when his is)
var touched := {}                # fighter -> knots against him in the last step
var ignore := {}                 # fighter -> s left that it will not take hold of him again (it has let him go)
var launch_at := Vector3.ZERO
var dirty := true                # it has moved since it was last drawn
var stones_dirty := true         # its knots have moved (a step) since the lead on its rim was last made
var box_count := 0               # the boxes of the bodies about it, for the drawing
var _acc := 0.0
var _near := PackedInt32Array()  # per knot: the part of a held man it is nearest (his index in the step's list * 64 + its place in his), -1 for none: a sixth of the knots look again each step
var _stepno := 0
var _w0 := PackedFloat32Array()  # 1 / mass of each knot as it was knitted
var _pin_part: Array = []        # the part of a man a knot has caught on, or null
var _pin_loc := PackedVector3Array()   # and where on it (in its own space)
var _touch := PackedFloat32Array()     # s each knot has lain against a held man
var _strain := PackedFloat32Array()    # s a knot that has caught has been drawn tight
var _cor := PackedByteArray()      # per knot: it has been moved by a body this step
var _kcl := PackedInt32Array()   # per knot: the block of the net it is in (3 by 3 knots), whose parts a step looks for once
var _cl_ids := PackedInt32Array()      # the blocks there are
var _cl_cand: Array = []         # per block: the parts of the men it may meet (their places in _allc), looked for again every step, or every third when the net lies calm
var _xf_of := {}                 # part -> where it will be at the end of this step (a part is met where it is going)
var _view_parts: Array = []      # the parts the drawing is told of, and the half extents of each (as it pads them)
var _view_he := PackedVector3Array()
var _allc: Array = []            # the parts of the men about the net this step, as _colliders made them
var _allc_n := -1                # (how many there were when the blocks looked)
var _cl_c := PackedVector3Array()
var _cl_n := PackedFloat32Array()
var _cl_r := PackedFloat32Array()
var _cling_every := 1            # (a net that lies calm looks at a knot every third step: it draws it on that much harder)
var _hood_head = null            # the head a net that has come down over a man is drawn on (its middle knots catch on it: a net over a man's head, hanging round him)
var _hood_knots := PackedInt32Array()
var _hood_loc := PackedVector3Array()
var _hood_t := 0.0
var _hooding := PackedByteArray() # per knot: it is being drawn onto the head (the bodies leave it be while it is)
var _calm := false               # a net that lies about a man or on the sand that moves little: the work against the bodies is shared out over three steps
var _calm_t := 0.0
var _fastest := 0.0              # the quickest part of a man about the net (m/s)
var _hit = null                  # (_against's: the part the knot was last put out of)
var _nc = null                   # (_cling's answer: the part nearest the knot, and how far off)
var _nd := 0.0
var _gi: Array = []              # the grid place of each knot
var _quads: Array = []           # the squares of the net that have all four knots: [grid x, grid y, its four knots]
var _side := 0                   # the grid of knots, as wide as this
var _gidx := PackedInt32Array()  # each knot's place in it
var _grid_f := PackedFloat32Array()    # the knots' places as the shader reads them (RGBA floats a place of the grid)
var _boxes := PackedFloat32Array()     # the boxes of the bodies, as the shader reads them (four texels a box)

## A net of `radius` metres knitted `cells` ropes to its radius.
static func make(radius_: float, cells: int) -> NetSim:
	var s := NetSim.new()
	s.radius = radius_
	s.cell = radius_ / float(cells)
	var side := cells * 2 + 1
	var at := PackedInt32Array()
	at.resize(side * side)
	at.fill(-1)
	var lim := float(cells * cells) + 1.5
	var gi := []
	for j in range(-cells, cells + 1):
		for i in range(-cells, cells + 1):
			if float(i * i + j * j) <= lim:
				at[(j + cells) * side + i + cells] = gi.size()
				gi.append(Vector2i(i, j))
	s.n = gi.size()
	s.P.resize(s.n)
	s.V.resize(s.n)
	s.Q.resize(s.n)
	s.W.resize(s.n)
	s.K.resize(s.n)
	s.RIM.resize(s.n)
	s.UV.resize(s.n)
	s._near.resize(s.n)
	s._near.fill(-1)
	s.NB.resize(s.n * 4)
	s.NB.fill(-1)
	s._pin_part.resize(s.n)
	s._pin_loc.resize(s.n)
	s._touch.resize(s.n)
	s._strain.resize(s.n)
	s._cor.resize(s.n)
	s._hooding.resize(s.n)
	s._gidx.resize(s.n)
	s._kcl.resize(s.n)
	var seen := {}
	for k in s.n:
		var gb: Vector2i = gi[k]
		var cid: int = ((gb.x + cells) / 2) * 8 + (gb.y + cells) / 2
		s._kcl[k] = cid
		if not seen.has(cid):
			seen[cid] = true
			s._cl_ids.append(cid)
	s._cl_cand.resize(64)
	s._cl_c.resize(64)
	s._cl_n.resize(64)
	s._cl_r.resize(64)
	for k in s.n:
		var g: Vector2i = gi[k]
		var edge := false
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for di in 4:
			var q: Vector2i = g + (dirs[di] as Vector2i)
			var inside := absi(q.x) <= cells and absi(q.y) <= cells and at[(q.y + cells) * side + q.x + cells] >= 0
			if inside:
				s.NB[k * 4 + di] = at[(q.y + cells) * side + q.x + cells]
			else:
				edge = true
		s.RIM[k] = 1 if edge else 0
		s.W[k] = RIM_INV_MASS if edge else 1.0
		s.K[k] = DRAG_RIM if edge else DRAG_ROPE
		s.UV[k] = Vector2(g.x + cells, g.y + cells)
		s._gidx[k] = (g.y + cells) * side + g.x + cells
	s._w0 = s.W.duplicate()
	for k in s.n:
		var g: Vector2i = gi[k]
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var q: Vector2i = g + d
			if absi(q.x) <= cells and absi(q.y) <= cells and at[(q.y + cells) * side + q.x + cells] >= 0:
				s.EA.append(k)
				s.EB.append(at[(q.y + cells) * side + q.x + cells])
		# (the drawn mesh: every square of the net that has all four knots)
		var r: Vector2i = g + Vector2i(1, 0)
		var dn: Vector2i = g + Vector2i(0, 1)
		var rd: Vector2i = g + Vector2i(1, 1)
		if absi(rd.x) <= cells and absi(rd.y) <= cells:
			var ir: int = at[(r.y + cells) * side + r.x + cells]
			var id: int = at[(dn.y + cells) * side + dn.x + cells]
			var ird: int = at[(rd.y + cells) * side + rd.x + cells]
			if ir >= 0 and id >= 0 and ird >= 0:
				s._quads.append([g.x + cells, g.y + cells, k, ir, id, ird])
	s._gi = gi
	s._side = side
	s._grid_f.resize(side * side * 4)
	s._boxes.resize(MAX_BOXES * 16)
	return s

## Gathered in the hand at `at`, and flung open: it goes with `v`, its disc across `normal` (the way it will face as it opens), turning `spin_dir` (+1 or -1) as it opens. Every knot
## is at the place of a smaller net and moving to the place of the full one in OPEN_T seconds: a throw's fling, which the ropes stop where they come taut.
func launch(at: Vector3, v: Vector3, normal: Vector3, spin_dir: float) -> void:
	launch_at = at
	var nz := normal.normalized()
	var ax := nz.cross(Vector3.UP if absf(nz.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var az := nz.cross(ax).normalized()
	var om := nz * (SPIN * spin_dir)
	for k in n:
		var g: Vector2i = _gi[k]
		var full := (ax * float(g.x) + az * float(g.y)) * cell
		P[k] = at + full * BUNDLE
		V[k] = v + full * ((1.0 - BUNDLE) / OPEN_T) + om.cross(full)
		Q[k] = P[k]
	center = at
	velocity = v
	_measure()

## What the net does in `dt` seconds with `chars` (the fighters and beasts about it) in the world; returns the men it has just caught. `owner_`, who threw it, is left alone for the first
## moments of its flight, while it is at his hand.
func advance(dt: float, chars: Array, owner_ = null) -> Array:
	var got := []
	_acc += dt
	var steps := 0
	while _acc >= STEP - 1e-6 and steps < 3:
		_acc -= STEP
		steps += 1
		_step(STEP, chars, owner_, got)
		dirty = true
		stones_dirty = true
	if not _view_parts.is_empty() or pinned > 0:
		dirty = true   # (the bodies about it move between its steps: it is drawn about them where they are)
	if _acc >= STEP:
		_acc = 0.0
	return got

func _step(dt: float, chars: Array, owner_, got: Array) -> void:
	age += dt
	# The bodies it is near, set up once: each man's reach, and each part's box in the world.
	var men := _colliders(chars, owner_)
	var held_any := false
	for man in men:
		held_any = held_any or man.held
	_stepno += 1
	_cor.fill(0)
	_candidates(men)
	# Where each knot is taking itself: one that has caught rides on the part it caught on, the rest fly on.
	var g := Vector3(0, -GRAVITY * dt, 0)
	for k in n:
		var pp = _pin_part[k]
		if pp != null:
			if is_instance_valid(pp) and not (pp as VoxelPart).severed:
				var pxf = _xf_of.get(pp)
				Q[k] = (pxf if pxf != null else (pp as Node3D).global_transform) * _pin_loc[k]
				W[k] = 0.0
				continue
			_unpin(k)
		W[k] = _w0[k]
		var v: Vector3 = (V[k] + g) / (1.0 + K[k] * dt)
		var sp := v.length()
		if sp > MAX_SPEED:
			v *= MAX_SPEED / sp
		Q[k] = P[k] + v * dt
	_solve()
	if _hood_t > 0.0:
		_draw_hood(dt)
	# The knots against the bodies, the sand and the wall.
	var every_k := 3 if _calm else 1
	_cling_every = every_k
	for k in n:
		if _pin_part[k] != null:
			continue
		if every_k > 1 and _hooding[k] == 0 and (k + _stepno) % every_k != 0:
			# (not its turn to look at the bodies: but the sand and the wall are never passed)
			var qs: Vector3 = Q[k]
			if qs.y < FLOOR:
				qs.y = FLOOR
				var sl := Vector3(qs.x - P[k].x, 0, qs.z - P[k].z)
				qs.x -= sl.x * SAND_GRIP
				qs.z -= sl.z * SAND_GRIP
			var rs := Vector2(qs.x, qs.z).length()
			if rs > WALL:
				qs.x *= WALL / rs
				qs.z *= WALL / rs
			Q[k] = qs
			continue
		var q: Vector3 = Q[k]
		_nc = null
		_nd = 1e9
		if held_any:
			q = _cling(q, men, k)
		_hit = null
		q = _against(k, q, dt, true)
		var hitc = _hit
		if q.y < FLOOR:
			q.y = FLOOR
			var s := Vector3(q.x - P[k].x, 0, q.z - P[k].z)
			q.x -= s.x * SAND_GRIP
			q.z -= s.z * SAND_GRIP
		var rr := Vector2(q.x, q.z).length()
		if rr > WALL:
			q.x *= WALL / rr
			q.z *= WALL / rr
		Q[k] = q
		# On a man it holds, a knot that has lain still on him a moment catches there.
		var pc = hitc
		if pc == null and _nc != null and (_nd - float(_nc.pad)) * (1.0 - CLING) < 0.03:
			pc = _nc
		if pc != null and pc.held:
			_touch[k] += dt * float(every_k)
			if _touch[k] >= PIN_T:
				var pv: Vector3 = (pc.part as RigidBody3D).linear_velocity
				if ((q - P[k]) / dt - pv).length() < PIN_SLIDE and not _lies_across(k, q, pc):
					_pin(k, pc.part, (pc.inv as Transform3D) * q)
		else:
			_touch[k] = 0.0
	# A knot that hangs on a man's part and has a limb of his come over it lets go (it is put out of the limb the next step).
	if pinned > 0 and _stepno % (6 if _calm else 2) == 0:
		for k in n:
			var pp = _pin_part[k]
			if pp == null:
				continue
			var q: Vector3 = Q[k]
			for ci in _cl_cand[_kcl[k]]:
				var c: Dictionary = _allc[ci]
				if c.part == pp or (q - c.at).length_squared() > c.r2:
					continue
				var l: Vector3 = (c.inv as Transform3D) * q
				var he: Vector3 = c.he
				if absf(l.x) < he.x and absf(l.y) < he.y and absf(l.z) < he.z:
					_unpin(k)
					break
	# The middle of each rope is kept out of the men too (a rope between two knots, neither in a body, may still cross a limb or a corner), and the knots it has moved are put out of the bodies
	# again: the bodies have the last word, and the ropes are drawn in the next step.
	if not men.is_empty():
		_ropes_out()
		for k in n:
			if _cor[k] != 0 and _pin_part[k] == null:
				_hit = null
				var q2: Vector3 = _against(k, Q[k], dt, false)
				if q2.y < FLOOR:
					q2.y = FLOOR
				Q[k] = q2
	for k in n:
		var nv: Vector3 = (Q[k] - P[k]) / dt
		if _cor[k] != 0:
			nv *= 0.6   # (a knot a body has held a rope off keeps little of the push)
		var sp2 := nv.length()
		V[k] = nv if sp2 <= MAX_SPEED else nv * (MAX_SPEED / sp2)
		P[k] = Q[k]
	# A knot that has caught lets go when its ropes are drawn tight (he has moved a limb away, or a heavy edge drags at it).
	if pinned > 0:
		var tight := cell * cell * PIN_STRAIN * PIN_STRAIN
		for k in n:
			if _pin_part[k] == null:
				continue
			var worst := 0.0
			for j in 4:
				var o := NB[k * 4 + j]
				if o >= 0:
					worst = maxf(worst, (P[o] - P[k]).length_squared())
			if worst > tight:
				_strain[k] += dt
				if _strain[k] > PIN_STRAIN_T:
					_unpin(k)
			else:
				_strain[k] = maxf(0.0, _strain[k] - dt)
	_measure()
	_pack_boxes(men)
	# Who it holds: knots in sustained contact with the man's trunk or head.
	touched.clear()
	for man in men:
		var f = man.f
		var cnt := 0
		var on_body := false
		for c in man.cols:
			cnt += int(c.cnt)
			if c.cnt > 0 and (c.part == f.torso or c.part == f.head):
				on_body = true
		touched[f] = cnt
		if on_body and cnt >= MIN_TOUCH and f.alive and not caught.has(f) and not ignore.has(f) and not (f == owner_ and age < OWNER_CATCH):
			held_t[f] = float(held_t.get(f, 0.0)) + dt
			if float(held_t[f]) >= HOLD_T:
				caught.append(f)
				got.append(f)
				_hood_start(f)
		elif not caught.has(f):
			held_t[f] = maxf(0.0, float(held_t.get(f, 0.0)) - dt)
	for f in caught:
		held_for[f] = float(held_for.get(f, 0.0)) + dt
	for f in ignore.keys():
		ignore[f] = float(ignore[f]) - dt
		if float(ignore[f]) <= 0.0:
			ignore.erase(f)
	var spread := _spread_speed()
	rest_t = rest_t + dt if (caught.is_empty() and low < 0.25 and velocity.length() < 0.35 and spread < 0.5) else 0.0
	var settled := not caught.is_empty() or low < 0.25
	if _calm:
		if spread > 0.6 or _fastest > 1.0 or not settled:
			_calm = false
			_calm_t = 0.0
	else:
		_calm_t = _calm_t + dt if (age > 1.2 and spread < 0.3 and _fastest < 0.7 and settled) else 0.0
		_calm = _calm_t > 0.3

## The ropes drawn in to their length: a rope that is not stretched does nothing, and two knots are not drawn together past BUNCH of it.
func _solve(passes := ITER) -> void:
	var m := EA.size()
	var c2 := cell * cell
	var lo := cell * BUNCH
	var lo2 := lo * lo
	for _p in passes:
		for s in m:
			var a: int = EA[s]
			var b: int = EB[s]
			var d: Vector3 = Q[b] - Q[a]
			var l2 := d.length_squared()
			if l2 > c2:
				var l := sqrt(l2)
				var wa: float = W[a]
				var wb: float = W[b]
				var w := wa + wb
				if w > 0.0:
					var k := (l - cell) / (l * w)
					Q[a] += d * (k * wa)
					Q[b] -= d * (k * wb)
			elif l2 < lo2 and l2 > 1e-10:
				var l := sqrt(l2)
				var wa: float = W[a]
				var wb: float = W[b]
				var w := wa + wb
				if w > 0.0:
					var k := (l - lo) / (l * w)
					Q[a] += d * (k * wa)
					Q[b] -= d * (k * wb)

## How far from a part's box a knot is kept: the rope's own thickness and what his skin stands out of the box, and round a trunk and a head the plates and the crest of his armour besides.
func _pad_of(part) -> float:
	return THICK + (ARMOUR_PAD if part.part_name == "torso" or part.part_name == "head" else 0.0)

## Where a part will be `lead` seconds on (it goes on as it goes: a net is put out of a body where the body is going, not where it was, and drawn where it is).
func _ahead(part, lead: float) -> Transform3D:
	var rb := part as RigidBody3D
	var xf: Transform3D = rb.global_transform
	xf.origin += rb.linear_velocity * lead
	var w: Vector3 = rb.angular_velocity
	var wl := w.length()
	if wl > 1e-3:
		xf.basis = Basis(w / wl, wl * lead) * xf.basis
	return xf

## The men near the net, each with his reach and the boxes of his parts, what the step needs of them.
func _colliders(chars: Array, owner_) -> Array:
	var men := []
	_fastest = 0.0
	_allc = []
	_xf_of.clear()
	for f in chars:
		if not is_instance_valid(f):
			continue
		# (A net that has just left a hand is at the hand of the man who threw it, and at whoever stands by him: its guests cannot say who threw it.)
		if age < OWNER_FREE and (f == owner_ or (owner_ == null and (f.torso.global_position - launch_at).length() < 0.9)):
			continue
		var tp: Vector3 = f.torso.global_position
		var s: float = f.S
		if (tp - center).length() > reach + 1.5 * s + 0.6:
			continue
		var held := caught.has(f)
		var cols := []
		for part in f.parts:
			if part == null or part.severed:
				continue
			_fastest = maxf(_fastest, (part as RigidBody3D).linear_velocity.length())
			var he: Vector3 = part.half_ext
			var pad := _pad_of(part)
			var xf: Transform3D = _ahead(part, STEP)
			_xf_of[part] = xf
			# (A rope is `cell` long: round a part thinner than that, its padding is made up to it, so that no rope lies across it with its ends on both sides of it.)
			var hp := Vector3(pad, pad, pad)
			for i in 3:
				hp[i] = clampf(0.5 * cell - he[i], pad, THIN_PAD)
			var rr := he.length() + THIN_PAD + 0.05
			_allc.append(null)
			var cd := {"i": _allc.size() - 1, "part": part, "inv": xf.affine_inverse(), "xf": xf, "he0": he, "he": he + hp, "her": he + Vector3(ROPE_R, ROPE_R, ROPE_R), "rr2": pow(he.length() + ROPE_R + 0.002, 2.0), "pad": pad, "held": held, "at": xf.origin, "r": rr, "r2": rr * rr, "r2c": pow(he.length() + CLING_RANGE + 0.05, 2.0), "cnt": 0}
			_allc[_allc.size() - 1] = cd
			cols.append(cd)
		var mr := 1.25 * s + (0.7 if held else 0.15)
		men.append({"f": f, "cols": cols, "held": held, "at": tp + Vector3(0, 0.25 * s, 0), "r": mr, "r2": mr * mr})
	return men

## A net that holds a man closes round him: a knot within CLING_RANGE of his body is drawn toward the nearest place on it (a hanging weight and the rope's pull do that, and a rope on cloth and flesh
## stays where it lies). Which part is nearest a knot is looked for a sixth of the steps and kept between (it changes slowly). Sets _nc, the part nearest it, and _nd, how far it was.
func _cling(q: Vector3, men: Array, k: int) -> Vector3:
	var best := CLING_RANGE
	var goal := q
	var cl = null
	if (k + _stepno) % 6 == 0:
		_near[k] = -1
		for mi in men.size():
			var man: Dictionary = men[mi]
			if not man.held or (q - man.at).length_squared() > man.r2:
				continue
			var cols: Array = man.cols
			for ci in cols.size():
				var c: Dictionary = cols[ci]
				if (q - c.at).length_squared() > c.r2c:
					continue
				var gt := _toward(q, c)
				if gt.w < best:
					best = gt.w
					goal = Vector3(gt.x, gt.y, gt.z)
					cl = c
					_near[k] = mi * 64 + ci
	else:
		var at := _near[k]
		if at < 0 or at / 64 >= men.size():
			return q
		var cs: Array = (men[at / 64] as Dictionary).cols
		if at % 64 >= cs.size():
			return q
		var g2 := _toward(q, cs[at % 64])
		if g2.w >= CLING_RANGE:
			_near[k] = -1
			return q
		goal = Vector3(g2.x, g2.y, g2.z)
		best = g2.w
		cl = cs[at % 64]
	if best >= CLING_RANGE:
		return q
	_nc = cl
	_nd = best
	return q + (goal - q) * minf(CLING * float(_cling_every), 0.6)

## Whether a rope from the place `q` (of knot `k`) to any knot it is roped to goes through a part's box (a knot is not to catch where its ropes would lie across the very part it hangs on).
func _lies_across(k: int, q: Vector3, c: Dictionary) -> bool:
	var inv: Transform3D = c.inv
	var he: Vector3 = c.her
	var la: Vector3 = inv * q
	for j in 4:
		var o := NB[k * 4 + j]
		if o < 0:
			continue
		var d: Vector3 = (inv * Q[o]) - la
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for i in 3:
			var da: float = d[i]
			var oa: float = la[i]
			var h: float = he[i]
			if absf(da) < 1e-9:
				if absf(oa) >= h:
					hit = false
					break
			else:
				var ta := (-h - oa) / da
				var tb := (h - oa) / da
				if ta > tb:
					var tmp := ta
					ta = tb
					tb = tmp
				t0 = maxf(t0, ta)
				t1 = minf(t1, tb)
				if t0 >= t1:
					hit = false
					break
		if hit:
			return true
	return false

## The nearest place on a part's box to `q` (xyz, its padding out from it) and how far it is (w).
func _toward(q: Vector3, c: Dictionary) -> Vector4:
	var l: Vector3 = (c.inv as Transform3D) * q
	var he0: Vector3 = c.he0
	var cl := l.clamp(-he0, he0)
	var d := l - cl
	var dist := d.length()
	if dist < 1e-5:
		return Vector4(q.x, q.y, q.z, 0.0)
	var p: Vector3 = (c.xf as Transform3D) * cl + ((c.xf as Transform3D).basis * d / dist) * float(c.pad)
	return Vector4(p.x, p.y, p.z, dist)

## A knot going from `p0` to `q` through a body's padded box, or in it, is put out of it: where it went in (it is followed along its way when it goes fast, so that it cannot be through
## him between two steps), or by the way of least depth. It clings (the rope on cloth and flesh): where it would slide along him it slides less. Null if it is clear.
func _push(p0: Vector3, q: Vector3, c: Dictionary, dt: float, k: int, swept: bool):
	var inv: Transform3D = c.inv
	var he: Vector3 = c.he
	var l1: Vector3 = inv * q
	var nl := Vector3.ZERO
	var lo := l1
	if absf(l1.x) < he.x and absf(l1.y) < he.y and absf(l1.z) < he.z:
		var dx := he.x - absf(l1.x)
		var dy := he.y - absf(l1.y)
		var dz := he.z - absf(l1.z)
		if dx <= dy and dx <= dz:
			nl.x = signf(l1.x) if l1.x != 0.0 else 1.0
			lo.x = nl.x * he.x
		elif dy <= dz:
			nl.y = signf(l1.y) if l1.y != 0.0 else 1.0
			lo.y = nl.y * he.y
		else:
			nl.z = signf(l1.z) if l1.z != 0.0 else 1.0
			lo.z = nl.z * he.z
	elif swept:
		# Through it between the two steps: the knot stops where it went in.
		var l0: Vector3 = inv * p0
		var d := l1 - l0
		var t0 := 0.0
		var t1 := 1.0
		var axis := -1
		var sgn := 0.0
		for a in 3:
			var da: float = d[a]
			var oa: float = l0[a]
			var h: float = he[a]
			if absf(da) < 1e-9:
				if absf(oa) >= h:
					return null
			else:
				var ta := (-h - oa) / da
				var tb := (h - oa) / da
				var tn := minf(ta, tb)
				var tf := maxf(ta, tb)
				if tn > t0:
					t0 = tn
					axis = a
					sgn = -signf(da)
				t1 = minf(t1, tf)
				if t0 > t1:
					return null
		if axis < 0 or t0 >= 1.0:
			return null
		lo = l0 + d * t0
		lo[axis] = sgn * (he[axis] + 0.001)
		nl[axis] = sgn
	else:
		return null
	var out: Vector3 = (c.xf as Transform3D) * lo
	var nw: Vector3 = ((c.xf as Transform3D).basis * nl).normalized()
	# What the part is doing: the knot goes with it a part of the way.
	var pv: Vector3 = (c.part as RigidBody3D).linear_velocity
	var slide: Vector3 = (out - P[k]) - pv * dt
	slide -= nw * slide.dot(nw)
	return out - slide * (GRIP if _hooding[k] == 0 else 0.0)   # (a knot being drawn over a head slides over it)

## One knot against the bodies: out of every padded box it is in (a few passes: out of one it may be in the next, as the shoulder's is in the arm's), where it went in when it goes fast.
## Sets _hit to the last part it was put out of.
func _against(k: int, q: Vector3, dt: float, first: bool) -> Vector3:
	var cand: PackedInt32Array = _cl_cand[_kcl[k]]
	if cand.is_empty():
		return q
	var stepd := (q - P[k]).length()
	var swept := first and stepd > FAST
	for pass_i in 3:
		var moved := false
		for ci in cand:
			var c: Dictionary = _allc[ci]
			if (q - c.at).length() > c.r + stepd:
				continue
			var sw := swept and pass_i == 0
			if not sw:
				# (in no box, and no sweep: nothing to do)
				var l1: Vector3 = (c.inv as Transform3D) * q
				var he: Vector3 = c.he
				if absf(l1.x) >= he.x or absf(l1.y) >= he.y or absf(l1.z) >= he.z:
					continue
			var hit = _push(P[k], q, c, dt, k, sw)
			if hit != null:
				q = hit
				if pass_i == 0 and first:
					c.cnt += 1
				_hit = c
				moved = true
		if not moved:
			break
	return q

## What each block of knots may meet: the parts whose reach comes within the block's own (its knots' spread about their middle, and as far as a step or a rope carries them). Looked for
## again every step, and every third when the net lies calm (the same parts are about it, and they are indices into this step's list of them).
func _candidates(men: Array) -> void:
	if _calm and _stepno % 3 != 0 and _allc.size() == _allc_n:
		return
	_allc_n = _allc.size()
	for ci in _cl_ids:
		_cl_cand[ci] = PackedInt32Array()
		_cl_c[ci] = Vector3.ZERO
		_cl_n[ci] = 0.0
		_cl_r[ci] = 0.0
	if men.is_empty():
		return
	for k in n:
		var ci: int = _kcl[k]
		_cl_c[ci] += P[k]
		_cl_n[ci] += 1.0
	for ci in _cl_ids:
		_cl_c[ci] = _cl_c[ci] / _cl_n[ci]
	for k in n:
		var ci: int = _kcl[k]
		var d2 := (P[k] - _cl_c[ci]).length_squared()
		if d2 > _cl_r[ci]:
			_cl_r[ci] = d2
	for ci in _cl_ids:
		var ctr: Vector3 = _cl_c[ci]
		var rad := sqrt(_cl_r[ci]) + 0.45 + cell
		var list := PackedInt32Array()
		for man in men:
			if (ctr - man.at).length() > man.r + rad:
				continue
			for c in man.cols:
				if (ctr - c.at).length() <= c.r + rad:
					list.append(c.i)
		_cl_cand[ci] = list

## Where a point in a part's padded box is put out of it (by the way of least depth), or null if it is clear.
func _out_of(p: Vector3, c: Dictionary):
	var l: Vector3 = (c.inv as Transform3D) * p
	var he: Vector3 = c.he
	var dx := he.x - absf(l.x)
	var dy := he.y - absf(l.y)
	var dz := he.z - absf(l.z)
	if dx <= 0.0 or dy <= 0.0 or dz <= 0.0:
		return null
	if dx <= dy and dx <= dz:
		l.x = (signf(l.x) if l.x != 0.0 else 1.0) * he.x
	elif dy <= dz:
		l.y = (signf(l.y) if l.y != 0.0 else 1.0) * he.y
	else:
		l.z = (signf(l.z) if l.z != 0.0 else 1.0) * he.z
	return (c.xf as Transform3D) * l

## The middle of each rope kept out of the men. A rope that has come into a part's box has come to it by one face (the one its middle was beyond before, the box as it is now): its middle is
## put out through that face, both its ends going with it as much, as a rope laid against a limb is held off it by the limb at its middle. (Not by the way of least depth: that would send the
## middle of a rope that flew into an arm out through the arm's end or the far side of it, with its ends on both sides of the arm: the net would go through him.) A knot that has caught on
## a man is not moved (the rope's other end is, twice as far); a rope with both ends caught on different parts lets them go.
func _ropes_out() -> void:
	var every := 3 if _calm else 1
	var e := _stepno % every
	var m := EA.size()
	while e < m:
		var a: int = EA[e]
		var b: int = EB[e]
		e += every
		var cand: PackedInt32Array = _cl_cand[_kcl[a]]
		if cand.is_empty():
			continue
		var pp = _pin_part[a]
		if pp != null and pp == _pin_part[b]:
			continue   # (both caught on one part: the rope is as rigid as it)
		var mid: Vector3 = (Q[a] + Q[b]) * 0.5
		for ci in cand:
			var c: Dictionary = _allc[ci]
			if (mid - c.at).length_squared() > c.rr2:
				continue
			var inv: Transform3D = c.inv
			var he: Vector3 = c.her
			var lm: Vector3 = inv * mid
			var dx := he.x - absf(lm.x)
			var dy := he.y - absf(lm.y)
			var dz := he.z - absf(lm.z)
			if dx <= 0.0 or dy <= 0.0 or dz <= 0.0:
				continue
			var l0: Vector3 = inv * ((P[a] + P[b]) * 0.5)
			var ax := -1
			var best := 1.0
			for i in 3:
				var r := absf(l0[i]) / he[i]
				if r > best:
					best = r
					ax = i
			var sg := 1.0
			if ax >= 0:
				sg = signf(l0[ax])
			else:
				if dx <= dy and dx <= dz:
					ax = 0
				elif dy <= dz:
					ax = 1
				else:
					ax = 2
				sg = signf(lm[ax]) if lm[ax] != 0.0 else 1.0
			var out := Vector3.ZERO
			out[ax] = sg * (he[ax] + 0.002) - lm[ax]
			var dl: Vector3 = (c.xf as Transform3D).basis * out
			var pa := _pin_part[a] != null
			var pb := _pin_part[b] != null
			if pa and pb:
				_unpin(a)
				_unpin(b)
				pa = false
				pb = false
			if pa:
				_shove(b, dl * 2.0)
			elif pb:
				_shove(a, dl * 2.0)
			else:
				_shove(a, dl)
				_shove(b, dl)
			mid = (Q[a] + Q[b]) * 0.5

## A knot moved by `d` by the body that holds a rope off it (never one that has caught, nor one that is being drawn onto a head): one that has been moved loses part of its speed.
func _shove(k: int, d: Vector3) -> void:
	if _hooding[k] != 0:
		return
	Q[k] += d
	_cor[k] = 1

## A net that has come down over a man whose head is under its middle: its middle five knots are to hang on his head (the crown, and the four edges of it), as a net thrown over a man comes to
## lie on his head and hang from it round his shoulders and his back; the rest of it falls from them and drapes as it will.
func _hood_start(f) -> void:
	var head = f.head
	if head == null or (head as VoxelPart).severed or not is_instance_valid(head):
		return
	var k0 := -1
	for k in n:
		var g: Vector2i = _gi[k]
		if g.x == 0 and g.y == 0:
			k0 = k
	if k0 < 0 or (P[k0] - (head as Node3D).global_position).length() > HOOD_R:
		return
	var he: Vector3 = (head as VoxelPart).half_ext
	var pad := _pad_of(head)
	# (All five on the plane of the crown, the four at the edges of it: a rope between two of them lies along the crown, never through the head's corner.)
	var top := he.y + pad
	var ring := {}
	ring[Vector2i(0, 0)] = Vector3(0.0, top, 0.0)
	ring[Vector2i(1, 0)] = Vector3(he.x + pad, top, 0.0)
	ring[Vector2i(-1, 0)] = Vector3(-(he.x + pad), top, 0.0)
	ring[Vector2i(0, 1)] = Vector3(0.0, top, he.z + pad)
	ring[Vector2i(0, -1)] = Vector3(0.0, top, -(he.z + pad))
	_hood_knots = PackedInt32Array()
	_hood_loc = PackedVector3Array()
	for k in n:
		var g: Vector2i = _gi[k]
		if ring.has(g):
			_hood_knots.append(k)
			_hood_loc.append(ring[g])
	_hood_head = head
	_hood_t = HOOD_T

## The middle of the net drawn onto the head it is over, and caught there.
func _draw_hood(dt: float) -> void:
	_hood_t -= dt
	var head = _hood_head
	if head == null or not is_instance_valid(head) or (head as VoxelPart).severed:
		_hood_t = 0.0
		_hooding.fill(0)
		return
	var hxf = _xf_of.get(head)
	if hxf == null:
		return
	for i in _hood_knots.size():
		var k := _hood_knots[i]
		if _pin_part[k] != null:
			continue
		var goal: Vector3 = (hxf as Transform3D) * _hood_loc[i]
		var d: Vector3 = goal - Q[k]
		if d.length() < 0.03:
			Q[k] = goal
			_hooding[k] = 0
			_pin(k, head, _hood_loc[i])
		else:
			Q[k] += d * 0.3
			_hooding[k] = 1
	if _hood_t <= 0.0:
		_hooding.fill(0)

func _pin(k: int, part, loc: Vector3) -> void:
	if _pin_part[k] == null:
		pinned += 1
	_pin_part[k] = part
	_pin_loc[k] = loc
	_strain[k] = 0.0
	W[k] = 0.0

func _unpin(k: int) -> void:
	if _pin_part[k] != null:
		pinned -= 1
	_pin_part[k] = null
	_touch[k] = 0.0
	_strain[k] = 0.0
	W[k] = _w0[k]

func _measure() -> void:
	var s := Vector3.ZERO
	var v := Vector3.ZERO
	var lo := 1e9
	for k in n:
		s += P[k]
		v += V[k]
		lo = minf(lo, P[k].y)
	center = s / float(n)
	velocity = v / float(n)
	low = lo
	var r := 0.0
	for k in n:
		r = maxf(r, (P[k] - center).length())
	reach = r

## How much the knots move among themselves (a net lying still has none; one that swings or is dragged has).
func _spread_speed() -> float:
	var s := 0.0
	for k in n:
		s += (V[k] - velocity).length_squared()
	return sqrt(s / float(n))

## It has let go of `f` (he has shaken it off): it falls from him (off his body, never through it), and does not take hold of him again.
func release(f) -> void:
	if _hood_head != null and f.parts.has(_hood_head):
		_hood_head = null
		_hood_t = 0.0
		_hooding.fill(0)
	caught.erase(f)
	held_t.erase(f)
	held_for.erase(f)
	ignore[f] = 30.0
	if is_instance_valid(f):
		for k in n:
			var pp = _pin_part[k]
			if pp != null and (not is_instance_valid(pp) or f.parts.has(pp)):
				_unpin(k)
		var tp: Vector3 = f.torso.global_position
		for k in n:
			var away: Vector3 = P[k] - tp
			away.y = 0.0
			if away.length_squared() > 1e-4:
				V[k] += away.normalized() * 1.6 + Vector3(0, 0.6, 0)

## The whole net taken by `d` (a guest's net follows the host's word of where it is).
func shift(d: Vector3) -> void:
	for k in n:
		P[k] += d
		Q[k] += d
	center += d

# ---------- Drawing ----------
## The net is drawn by one mesh made once, a fine one (each square of the net as SUB by SUB), whose every vertex is put in its place by the shader, off the knots' places (a texture, one texel
## a knot, in the net's grid) and out of the boxes of the bodies about it (a texture too): the net is a surface, drawn smooth over a man, and nowhere in him.

## The fine mesh: its vertices are the net's grid coordinates and where in a square they are (the shader works out the rest), its colour the stoutness of the rope there (the rim).
func build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for q in _quads:
		var base := verts.size()
		for b in SUB + 1:
			for a in SUB + 1:
				var fa := float(a) / float(SUB)
				var fb := float(b) / float(SUB)
				verts.append(Vector3.ZERO)
				uv.append(Vector2(float(q[0]) + fa, float(q[1]) + fb))
				uv2.append(Vector2(float(q[0]), float(q[1])))
				var r := lerpf(lerpf(float(RIM[q[2]]), float(RIM[q[3]]), fa), lerpf(float(RIM[q[4]]), float(RIM[q[5]]), fa), fb)
				col.append(Color(r, 0.0, 0.0, 1.0))
		for b in SUB:
			for a in SUB:
				var v00 := base + b * (SUB + 1) + a
				var v10 := v00 + 1
				var v01 := v00 + SUB + 1
				var v11 := v01 + 1
				idx.append_array([v00, v10, v01, v10, v11, v01])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## How wide the grid of knots is (the knot texture is this by this).
func grid_side() -> int:
	return _side

## The knots' places for the shader: this by this texels of four floats, a knot's place at its place of the grid (the rest nothing).
func grid_bytes() -> PackedByteArray:
	var lead := 1.0 / float(Engine.physics_ticks_per_second)
	for k in n:
		var i := _gidx[k] * 4
		var p: Vector3 = P[k]
		var pp = _pin_part[k]
		if pp != null and is_instance_valid(pp):
			# (a knot that has caught is drawn where its part is when the frame is: it is not a step behind it)
			p = _ahead(pp, lead) * _pin_loc[k]
		_grid_f[i] = p.x
		_grid_f[i + 1] = p.y
		_grid_f[i + 2] = p.z
	return _grid_f.to_byte_array()

## The boxes of the bodies about it for the shader: MAX_BOXES of four texels of four floats (a box's world-to-its-own columns with its origin in w, then its half extents, the rope's own half
## thickness out).
func box_bytes() -> PackedByteArray:
	var lead := 1.0 / float(Engine.physics_ticks_per_second)
	var cnt := 0
	for ci in _view_parts.size():
		if cnt >= MAX_BOXES:
			break
		var part = _view_parts[ci]
		if not is_instance_valid(part):
			continue
		var inv: Transform3D = _ahead(part, lead).affine_inverse()
		var b := inv.basis
		var o := inv.origin
		var he: Vector3 = _view_he[ci] + Vector3(ROPE_R, ROPE_R, ROPE_R)
		var i := cnt * 16
		_boxes[i] = b.x.x
		_boxes[i + 1] = b.x.y
		_boxes[i + 2] = b.x.z
		_boxes[i + 3] = o.x
		_boxes[i + 4] = b.y.x
		_boxes[i + 5] = b.y.y
		_boxes[i + 6] = b.y.z
		_boxes[i + 7] = o.y
		_boxes[i + 8] = b.z.x
		_boxes[i + 9] = b.z.y
		_boxes[i + 10] = b.z.z
		_boxes[i + 11] = o.z
		_boxes[i + 12] = he.x
		_boxes[i + 13] = he.y
		_boxes[i + 14] = he.z
		cnt += 1
	box_count = cnt
	return _boxes.to_byte_array()

## The parts the drawing is told of (the boxes themselves are made where the parts are when it is drawn: box_bytes).
func _pack_boxes(men: Array) -> void:
	_view_parts.clear()
	_view_he.clear()
	for man in men:
		for c in man.cols:
			_view_parts.append(c.part)
			_view_he.append(c.he)

## Where it is, for the drawing's bounds.
func bounds() -> AABB:
	return AABB(center - Vector3.ONE * (reach + 0.4), Vector3.ONE * (reach * 2.0 + 0.8))

## The lead of the rim as small stones at its knots, made anew each time (a few hundred vertices).
func fill_stones(stones: ArrayMesh) -> void:
	stones.clear_surfaces()
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var ix := PackedInt32Array()
	var h := 0.03
	for k in n:
		if RIM[k] == 0:
			continue
		var b := vs.size()
		var p: Vector3 = P[k]
		vs.append_array([p + Vector3(h, 0, 0), p - Vector3(h, 0, 0), p + Vector3(0, h, 0), p - Vector3(0, h, 0), p + Vector3(0, 0, h), p - Vector3(0, 0, h)])
		ns.append_array([Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD])
		ix.append_array([b, b + 2, b + 4, b + 4, b + 2, b + 1, b + 1, b + 2, b + 5, b + 5, b + 2, b, b, b + 4, b + 3, b + 4, b + 1, b + 3, b + 1, b + 5, b + 3, b + 5, b, b + 3])
	var sa := []
	sa.resize(Mesh.ARRAY_MAX)
	sa[Mesh.ARRAY_VERTEX] = vs
	sa[Mesh.ARRAY_NORMAL] = ns
	sa[Mesh.ARRAY_INDEX] = ix
	stones.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sa)
	stones.custom_aabb = bounds()
