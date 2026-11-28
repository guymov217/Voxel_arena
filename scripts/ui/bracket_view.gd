class_name BracketView
extends Control
## The tournament's tree (Tourney.tree), drawn by hand (user: a tree to be seen through the tournament, to understand who goes on to the next round and who does not): the
## rounds in columns, a box to a bout with its two names, the winner of a bout lit and the one put out dimmed, the bout being fought marked, the places not won yet empty,
## lines from a bout to the one its winner goes to, the viewer's own name marked. Small in the corner of a bout (`big` false), large between bouts. DOM-free but for the
## drawing: `layout` is plain data (what the test reads), `_draw` only paints it.

const GOLD := Color(0.82, 0.66, 0.32)
const GOLD_PALE := Color(0.95, 0.86, 0.6)
const TEXT := Color(0.93, 0.89, 0.8)
const MUTED := Color(0.6, 0.56, 0.5)
const DIM := Color(0.42, 0.39, 0.35)
const MINE := Color(0.62, 0.84, 1.0)
const BLOOD := Color(0.93, 0.28, 0.18)
const PLATE := Color(0.06, 0.055, 0.05, 0.74)
const PLATE_EDGE := Color(0.36, 0.32, 0.27, 0.9)
const BOX := Color(0.115, 0.105, 0.09, 0.92)

var tourney: Tourney = null
var mine := ""              # the viewer's own key as the bracket has it (a player "p<peer>"), "" for none
var big := false
var font: Font = null

## Sizes of a line of a name, of a box, of a column and the gaps (compact, large).
const LINE: Array[float] = [17.0, 27.0]
const FONT: Array[int] = [13, 19]
const COL_W: Array[float] = [124.0, 208.0]
const COL_GAP: Array[float] = [16.0, 40.0]
const ROW_GAP: Array[float] = [7.0, 14.0]
const HEAD: Array[float] = [17.0, 30.0]
const PAD: Array[float] = [6.0, 10.0]
const MARGIN: Array[float] = [7.0, 18.0]   # the plate round the tree

func set_state(tr: Tourney, mine_key: String, large: bool) -> void:
	tourney = tr
	mine = mine_key
	big = large
	custom_minimum_size = layout().size + Vector2(MARGIN[_i()], MARGIN[_i()]) * 2.0 if tr != null and not tr.entrants.is_empty() else Vector2.ZERO
	queue_redraw()

func _i() -> int:
	return 1 if big else 0

## The geometry and the words of the tree: {size, titles: [{p, text}], boxes: [{rect, open, done, names: [{text, state}], y}], lines: [[Vector2...]], champion}.
## A name's state: "mine", "won", "out", "alive", "empty" (a place not won yet) or "bye".
func layout() -> Dictionary:
	var out := {"size": Vector2(0, 0), "titles": [], "boxes": [], "lines": [], "champion": ""}
	if tourney == null or tourney.entrants.is_empty():
		return out
	var tree := tourney.tree()
	var i := _i()
	var line_h: float = LINE[i]
	var box_h := line_h * 2.0 + PAD[i] * 0.5
	var slot := box_h + ROW_GAP[i]
	var first_n: int = (tree[0].matches as Array).size()
	var top: float = HEAD[i]
	var centers := []   # [round][bout] -> y of its middle
	var xs := []
	for r in tree.size():
		xs.append(float(r) * (COL_W[i] + COL_GAP[i]))
	var gone := {}
	for k in tourney.out_keys():
		gone[k] = true
	for r in tree.size():
		var ms: Array = tree[r].matches
		var cs := []
		for j in ms.size():
			var y: float
			if r == 0:
				y = top + (float(j) + 0.5) * slot
			else:
				var pa: Array = centers[r - 1]
				var ya: float = pa[mini(2 * j, pa.size() - 1)]
				var yb: float = pa[mini(2 * j + 1, pa.size() - 1)]
				y = (ya + yb) * 0.5
			cs.append(y)
			var m: Dictionary = ms[j]
			var rect := Rect2(xs[r], y - box_h * 0.5, COL_W[i], box_h)
			var names := []
			for side in ["a", "b"]:
				var key := String(m[side])
				var st := "alive"
				var text := ""
				if key == "":
					st = "bye" if (side == "b" and bool(m.bye)) else "empty"
					text = Loc.t("(bye)") if st == "bye" else "…"
				else:
					text = tourney.name_of(key)
					var won := String(m.w) != "" and not bool(m.bye)
					if key == mine:
						st = "mine"
					if won and key == String(m.w):
						st = "won" if st != "mine" else "mine"
					elif won:
						st = "out"
					elif gone.has(key):
						st = "out"
				names.append({"text": text, "state": st, "key": key, "bot": tourney.is_bot(key) if key != "" else false, "won": String(m.w) != "" and key == String(m.w)})
			out.boxes.append({"rect": rect, "open": bool(m.open), "done": String(m.w) != "" and not bool(m.bye), "names": names, "round": r, "index": j, "y": y})
			# The line to the bout the winner goes to.
			if r < tree.size() - 1:
				var tj: int = j / 2
				out.lines.append({"round": r, "from": j, "to": tj, "won": String(m.w) != ""})
		centers.append(cs)
	# The lines' points, once the centres are all known.
	var segs := []
	for l in out.lines:
		var r: int = l.round
		var x0: float = xs[r] + COL_W[i]
		var x1: float = xs[r + 1]
		var y0: float = (centers[r] as Array)[l.from]
		var y1: float = (centers[r + 1] as Array)[l.to]
		var mid := (x0 + x1) * 0.5
		segs.append({"pts": [Vector2(x0, y0), Vector2(mid, y0), Vector2(mid, y1), Vector2(x1, y1)], "won": l.won})
	out.lines = segs
	for r in tree.size():
		out.titles.append({"p": Vector2(xs[r], HEAD[i] - 4.0), "text": String(tree[r].title).replace(Loc.t("The "), "") if not big else String(tree[r].title)})
	var w: float = xs[tree.size() - 1] + COL_W[i]
	var h: float = top + float(first_n) * slot - ROW_GAP[i] * 0.5 + (line_h + 4.0 if tourney.finished() else 0.0)
	out.size = Vector2(w, h)
	out.champion = tourney.name_of(tourney.champion()) if tourney.finished() else ""
	return out

func _name_color(n: Dictionary) -> Color:
	match String(n.state):
		"mine": return MINE
		"won": return GOLD_PALE
		"out": return DIM
		"empty", "bye": return MUTED
	return TEXT if not bool(n.bot) else Color(TEXT, 0.82)

func _fit(f: Font, text: String, fs: int, max_w: float) -> String:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var s := text
	while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		s = s.left(s.length() - 1)
	return s + "…"

func _draw() -> void:
	if tourney == null:
		return
	var d := layout()
	if (d.boxes as Array).is_empty():
		return
	var f: Font = font if font != null else ThemeDB.fallback_font
	var i := _i()
	var fs: int = FONT[i]
	var size_: Vector2 = d.size
	var mg: float = MARGIN[i]
	draw_rect(Rect2(Vector2.ZERO, size_ + Vector2(mg, mg) * 2.0), PLATE)
	draw_rect(Rect2(Vector2.ZERO, size_ + Vector2(mg, mg) * 2.0), PLATE_EDGE, false, 1.0)
	draw_set_transform(Vector2(mg, mg))
	for l in d.lines:
		draw_polyline(PackedVector2Array(l.pts), Color(GOLD, 0.8) if l.won else Color(MUTED, 0.5), 1.5 if big else 1.0, true)
	for tl in d.titles:
		draw_string(f, tl.p, _fit(f, String(tl.text).to_upper(), fs - 1, COL_W[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, Color(GOLD, 0.9))
	for b in d.boxes:
		var rect: Rect2 = b.rect
		draw_rect(rect, BOX)
		var edge := GOLD if b.open else (Color(PLATE_EDGE, 0.7) if b.done else PLATE_EDGE)
		draw_rect(rect, edge, false, 2.0 if b.open else 1.0)
		var pad: float = PAD[i]
		for k in 2:
			var n: Dictionary = b.names[k]
			var base := rect.position.y + PAD[i] * 0.25 + (float(k) + 0.8) * LINE[i]
			var text := String(n.text)
			var prefix := "▶ " if n.state == "mine" else ("✓ " if n.state == "won" else "")
			var col := _name_color(n)
			draw_string(f, Vector2(rect.position.x + pad, base), _fit(f, prefix + text, fs, rect.size.x - pad * 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			if n.state == "out":
				var w := minf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, rect.size.x - pad * 2.0)
				draw_line(Vector2(rect.position.x + pad, base - fs * 0.32), Vector2(rect.position.x + pad + w, base - fs * 0.32), Color(DIM, 0.9), 1.0)
	if String(d.champion) != "":
		draw_string(f, Vector2(0, size_.y - 4.0), "♛ " + String(d.champion), HORIZONTAL_ALIGNMENT_LEFT, size_.x, fs + 1, GOLD_PALE)
