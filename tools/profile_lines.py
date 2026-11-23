#!/usr/bin/env python3
"""Times the statements of one function, a call at a time, to see where inside it the time goes (#312): a checkpoint before each statement of the function's own
level (one tab in: every `if`, `for`, `var` and call of its body, a block as a whole, so the figure of an `if` is what its branch cost), the time since the last one
put to the last one's line. Costs about 0.5 us a checkpoint: read the figures as they stand against one another (tools/profile_funcs.py does the same for whole
functions). `--depth 2` also marks the statements one level in (the inside of the blocks), which costs more and shows more.

It REWRITES the script it is given, so run it on a COPY of the project, never on a checkout you work in:

    cp -r <project> /tmp/prof
    python3 tools/profile_lines.py /tmp/prof scripts/fighter/fighter.gd _drive_arm [--depth 2]
    cd /tmp/prof && N=8 BEHAVIOR=brawl SECS=6 NONPC=1 ARM_LOD=0 IDLE=0 godot --headless --fixed-fps 120 --path . -- --probe lobby298 | grep LNPROF

The function becomes a wrapper over `<name>__l` (its own body); the counters live in Fighter (Fighter.ln_clear(), Fighter.ln_text(steps, men, top)), and the markers of the
probes (`# profile_funcs.py: clear` and `# profile_funcs.py: print`, in tests/lobby298.gd, frame298.gd and mix298.gd) become the calls. Lines come out as
`LNPROF <line of the original> <calls a man and step> <us a man and step> <us a call> <the statement>`. The line is of the file before it was rewritten."""
import json, os, re, sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
depth = 2 if "--depth" in sys.argv and sys.argv[sys.argv.index("--depth") + 1] == "2" else 1
if "--depth" in sys.argv:
    args = [a for a in args if a != sys.argv[sys.argv.index("--depth") + 1]]
if len(args) != 3:
    print(__doc__)
    sys.exit(2)
root, rel, fname = args
path = os.path.join(root, rel)
src = open(path).read().split("\n")


def split_params(s):
    parts, d, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            d += 1
        if ch in ")]}":
            d -= 1
        if ch == "," and d == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


def bracket_delta(line):
    """The net depth of ([{ a line opens, outside its strings and its comment."""
    d, q, i = 0, None, 0
    while i < len(line):
        ch = line[i]
        if q:
            if ch == "\\":
                i += 1
            elif ch == q:
                q = None
        elif ch in "\"'":
            q = ch
        elif ch == "#":
            break
        elif ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
        i += 1
    return d


head_re = re.compile(r"^(static )?func %s\((.*)\)( -> ([A-Za-z0-9_\[\]\.]+))?:\s*$" % re.escape(fname))
start = next((i for i, l in enumerate(src) if head_re.match(l)), None)
if start is None:
    print("function not found: " + fname)
    sys.exit(1)
end = next((i for i in range(start + 1, len(src)) if re.match(r"^(static )?func |^var |^const |^signal |^class |^@", src[i])), len(src))
m = head_re.match(src[start])
static, params, ret = m.group(1) or "", m.group(2), m.group(4)
argn = [re.match(r"^([A-Za-z_0-9]+)", p).group(1) for p in split_params(params)]
retdecl = (" -> " + ret) if ret else ""

out = src[:start]
out.append("%sfunc %s(%s)%s:" % (static, fname, params, retdecl))
out.append("\tFighter._ln_begin()")
if ret == "void" or not ret:
    out.append("\t%s__l(%s)" % (fname, ", ".join(argn)))
    out.append("\tFighter._ln_end()")
else:
    out.append("\tvar _r = %s__l(%s)" % (fname, ", ".join(argn)))
    out.append("\tFighter._ln_end()")
    out.append("\treturn _r")
out.append("")
out.append("%sfunc %s__l(%s)%s:" % (static, fname, params, retdecl))

marks = []       # (line number of the original, statement text)
bdepth = 0
cont = False     # inside a statement carried over onto the next line by a backslash
prev_top_opens_block = False
for i in range(start + 1, end):
    line = src[i]
    stripped = line.lstrip("\t")
    ind = len(line) - len(stripped)
    if bdepth == 0 and not cont and stripped and not stripped.startswith("#") and 1 <= ind <= depth and not re.match(r"^(else|elif)\b", stripped) and not re.match(r"^(\"\"\"|'''|\))", stripped):
        # (a statement of its own: not the arm of an if-chain, not a pattern of a match)
        prev = None
        for j in range(i - 1, start, -1):
            pl = src[j].strip()
            if pl and not pl.startswith("#"):
                prev = src[j]
                break
        pind = len(prev) - len(prev.lstrip("\t")) if prev is not None else 0
        # a match's pattern lines sit one deeper than the `match`: skip any line whose block is a `match`
        in_match = False
        for j in range(i - 1, start, -1):
            pl = src[j]
            pi = len(pl) - len(pl.lstrip("\t"))
            if pl.strip() and not pl.strip().startswith("#") and pi < ind:
                in_match = pl.strip().startswith("match ")
                break
        ok_after_colon = True
        if prev is not None and pind == ind:
            # a statement that follows one of its own level: a checkpoint is allowed
            ok_after_colon = True
        if not in_match and ok_after_colon:
            marks.append((i + 1, stripped.strip()[:70]))
            out.append("\t" * ind + "Fighter._ln_cp(%d)" % (i + 1))
    out.append(line)
    bdepth += bracket_delta(line)
    if bdepth < 0:
        bdepth = 0
    cont = line.rstrip().endswith("\\")
out.extend(src[end:])

helper = '''
static var _ln_t := PackedInt64Array()
static var _ln_c := PackedInt64Array()
static var _ln_m := PackedInt64Array()   # the longest single stretch of each (a stall, not a sum)
static var _ln_last := 0
static var _ln_t0 := 0
const _LN_LINES := %s
const _LN_TEXT := %s
static func _ln_slot(id: int) -> int:
	return _LN_LINES.find(id) + 1
static func _ln_begin() -> void:
	if _ln_t.is_empty():
		_ln_t.resize(%d)
		_ln_c.resize(%d)
		_ln_m.resize(%d)
	_ln_last = 0
	_ln_t0 = Time.get_ticks_usec()
static func _ln_cp(id: int) -> void:
	var now := Time.get_ticks_usec()
	var d := now - _ln_t0
	_ln_t[_ln_last] += d
	_ln_c[_ln_last] += 1
	if d > _ln_m[_ln_last]:
		_ln_m[_ln_last] = d
	_ln_last = _LN_LINES.find(id) + 1
	_ln_t0 = Time.get_ticks_usec()
static func _ln_end() -> void:
	var now := Time.get_ticks_usec()
	var d := now - _ln_t0
	_ln_t[_ln_last] += d
	_ln_c[_ln_last] += 1
	if d > _ln_m[_ln_last]:
		_ln_m[_ln_last] = d
static func ln_clear() -> void:
	if _ln_t.is_empty():
		_ln_t.resize(%d)
		_ln_c.resize(%d)
		_ln_m.resize(%d)
	_ln_t.fill(0)
	_ln_c.fill(0)
	_ln_m.fill(0)
## The statements with the longest single stretch (`LNMAX <line> <longest ms> <calls> <statement>`), those over `min_us`.
static func ln_max_text(top: int, min_us := 1500) -> String:
	var ids := []
	for k in _ln_m.size():
		if _ln_m[k] >= min_us:
			ids.append(k)
	ids.sort_custom(func(a, b): return _ln_m[a] > _ln_m[b])
	var lines := []
	for k in ids.slice(0, top):
		var ln: int = _LN_LINES[k - 1] if k > 0 else 0
		var tx: String = _LN_TEXT[k - 1] if k > 0 else "(entry)"
		lines.append("   LNMAX %%d %%.2f %%d %%s" %% [ln, float(_ln_m[k]) / 1000.0, _ln_c[k], tx])
	return "\n".join(lines)
static func ln_text(steps: int, men: int, top: int) -> String:
	var ids := []
	for k in _ln_t.size():
		if _ln_c[k] > 0:
			ids.append(k)
	ids.sort_custom(func(a, b): return _ln_t[a] > _ln_t[b])
	var ms := maxf(1.0, float(steps * men))
	var total := 0
	for k in ids:
		total += _ln_t[k]
	var lines := ["   LNPROF total %%.1f us a man and step" %% (float(total) / ms)]
	var shown := 0
	for k in ids:
		if shown >= top:
			break
		shown += 1
		var ln: int = _LN_LINES[k - 1] if k > 0 else 0
		var tx: String = _LN_TEXT[k - 1] if k > 0 else "(entry)"
		lines.append("   LNPROF %%d %%.2f %%.2f %%.2f %%s" %% [ln, float(_ln_c[k]) / ms, float(_ln_t[k]) / ms, float(_ln_t[k]) / maxf(1.0, float(_ln_c[k])), tx])
	return "\\n".join(lines)
''' % ("[" + ", ".join(str(a) for a, _ in marks) + "]", "[" + ", ".join(json.dumps(t, ensure_ascii=True) for _, t in marks) + "]", len(marks) + 1, len(marks) + 1, len(marks) + 1, len(marks) + 1, len(marks) + 1, len(marks) + 1)
open(path, "w").write("\n".join(out) + helper)

# the probes: the markers become the calls
tdir = os.path.join(root, "tests")
for fn in sorted(os.listdir(tdir)):
    if not fn.endswith(".gd"):
        continue
    p = os.path.join(tdir, fn)
    s = open(p).read()
    if "# profile_funcs.py:" not in s:
        continue
    lines = s.split("\n")
    for i, l in enumerate(lines):
        ind = l[:len(l) - len(l.lstrip("\t"))]
        if l.strip() == "# profile_funcs.py: clear":
            lines[i] = ind + "Fighter.ln_clear()"
        elif l.strip() == "# profile_funcs.py: print":
            if fn.startswith("mix298"):
                lines[i] = ind + 'print(Fighter.ln_text(steps, m.entities.size(), int(_env("TOPN", "80"))))'
                lines[i] += "\n" + ind + 'print(Fighter.ln_max_text(30))'
            elif fn.startswith("frame298"):
                lines[i] = ind + 'print(Fighter.ln_text(frames, n_men, int(_env("TOPN", "80"))))'
                lines[i] += "\n" + ind + 'print(Fighter.ln_max_text(30))'
            else:
                lines[i] = ind + 'print(Fighter.ln_text(steps, n_men, int(_env("TOPN", "80"))))'
                lines[i] += "\n" + ind + 'print(Fighter.ln_max_text(30))'
    open(p, "w").write("\n".join(lines))
print("marked %d statements of %s (depth %d)" % (len(marks), fname, depth))
