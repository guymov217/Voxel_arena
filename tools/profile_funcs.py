#!/usr/bin/env python3
"""Times whole functions of the game's scripts, a call at a time, to see where a step or a frame goes (#298k): one `Time.get_ticks_usec()` pair round each function
named, inclusive of what it calls, with the calls counted. Costs about 0.3 us a call: read the figures as they stand against one another.

It REWRITES the scripts it is given, so run it on a COPY of the project, never on a checkout you work in:

    cp -r <project> /tmp/prof                                   (the .godot folder may come along)
    cat > /tmp/spec.json <<'JSON'
    {"scripts/fighter/fighter.gd": ["control", "_drive_arm", "_clear_body"],
     "scripts/fighter/combat.gd": ["_physics_process", "report"],
     "scripts/voxel/voxel_part.gd": ["_integrate_forces"]}
    JSON
    python3 tools/profile_funcs.py /tmp/prof scripts/fighter/fighter.gd /tmp/spec.json
    cd /tmp/prof && N=8 BEHAVIOR=walk SECS=6 NONPC=1 ARM_LOD=0 IDLE=0 godot --headless --fixed-fps 120 --path . -- --probe lobby298 | grep BLKF

Each function becomes a wrapper `f` over `f__f` (its own body); the counters live in the class of the first script (the "collector": Fighter), which also gets
Fighter.blk_clear() and Fighter.blk_text(steps, men, top). The probes tests/lobby298.gd, tests/frame298.gd and tests/mix298.gd carry the marker comments
`# profile_funcs.py: clear` and `# profile_funcs.py: print` where the counters are zeroed after the warm-up and printed at the end; this script turns the markers of
the probes found under <project>/tests into those calls. Lines come out as `BLKF <file>.<function> <calls a man and step> <us a man and step> <us a call>`.
Not for what the engine does between the scripts (the physics engine itself, the drawing): there the engine's own F3 meter and the probes' step times are the measure."""
import json, os, re, sys

if len(sys.argv) != 4:
    print(__doc__)
    sys.exit(2)
root, collector, specfile = sys.argv[1], sys.argv[2], sys.argv[3]
spec = json.load(open(specfile))
cls = "Fighter"


def split_params(s):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1
        if ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


names = []
for rel, funcs in spec.items():
    path = os.path.join(root, rel)
    stem = os.path.splitext(os.path.basename(rel))[0]
    src = open(path).read().split("\n")
    out = []
    found = set()
    for line in src:
        m = re.match(r"^(static )?func ([A-Za-z_0-9]+)\((.*)\)( -> ([A-Za-z0-9_\[\]\.]+))?:\s*$", line)
        if not (m and m.group(2) in funcs):
            out.append(line)
            continue
        static, name, params, _, ret = m.group(1) or "", m.group(2), m.group(3), m.group(4), m.group(5)
        slot = len(names)
        names.append("%s.%s" % (stem, name))
        found.add(name)
        argn = [re.match(r"^([A-Za-z_0-9]+)", p).group(1) for p in split_params(params)]
        retdecl = (" -> " + ret) if ret else ""
        out.append("%sfunc %s(%s)%s:" % (static, name, params, retdecl))
        out.append("\tvar _t0 := Time.get_ticks_usec()")
        if ret == "void":
            out.append("\t%s__f(%s)" % (name, ", ".join(argn)))
            out.append("\t%s._fadd(%d, Time.get_ticks_usec() - _t0)" % (cls, slot))
        else:
            out.append("\tvar _r = %s__f(%s)" % (name, ", ".join(argn)))
            out.append("\t%s._fadd(%d, Time.get_ticks_usec() - _t0)" % (cls, slot))
            out.append("\treturn _r")
        out.append("")
        out.append("%sfunc %s__f(%s)%s:" % (static, name, params, retdecl))
    for f in funcs:
        if f not in found:
            print("not found in %s: %s" % (rel, f))
    open(path, "w").write("\n".join(out))

n = len(names) + 2
helper = '''
static var _ft := PackedInt64Array()
static var _fc := PackedInt64Array()
static var _fm := PackedInt64Array()   # the longest single call of each, in us (the stalls)
const _FNAMES := %s
static func _fadd(slot: int, us: int) -> void:
	if _ft.is_empty():
		_ft.resize(%d)
		_fc.resize(%d)
		_fm.resize(%d)
	_ft[slot] += us
	_fc[slot] += 1
	if us > _fm[slot]:
		_fm[slot] = us
static func blk_clear() -> void:
	if _ft.is_empty():
		_ft.resize(%d)
		_fc.resize(%d)
		_fm.resize(%d)
	_ft.fill(0)
	_fc.fill(0)
	_fm.fill(0)
## The calls that took longest (one call, not a sum): `BLKMAX <function> <longest call ms> <calls> <total ms>`, those over `min_us`.
static func blk_max_text(top: int, min_us := 5000) -> String:
	var ids := []
	for k in _fm.size():
		if _fm[k] >= min_us:
			ids.append(k)
	ids.sort_custom(func(a, b): return _fm[a] > _fm[b])
	var lines := []
	for k in ids.slice(0, top):
		lines.append("   BLKMAX %%s %%.1f %%d %%.1f" %% [_FNAMES[k], float(_fm[k]) / 1000.0, _fc[k], float(_ft[k]) / 1000.0])
	return "\n".join(lines)
static func blk_text(steps: int, men: int, top: int) -> String:
	var ids := []
	for k in _ft.size():
		if _fc[k] > 0:
			ids.append(k)
	ids.sort_custom(func(a, b): return _ft[a] > _ft[b])
	var ms := maxf(1.0, float(steps * men))
	var lines := []
	var shown := 0
	for k in ids:
		if shown >= top:
			break
		shown += 1
		lines.append("   BLKF %%s %%.2f %%.2f %%.2f" %% [_FNAMES[k], float(_fc[k]) / ms, float(_ft[k]) / ms, float(_ft[k]) / maxf(1.0, float(_fc[k]))])
	return "\\n".join(lines)
''' % (json.dumps(names), n, n, n, n, n, n)
open(os.path.join(root, collector), "a").write(helper)

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
            lines[i] = ind + "%s.blk_clear()" % cls
        elif l.strip() == "# profile_funcs.py: print":
            # the probes' own count of steps and men (lobby298: steps, n_men; frame298: frames, n_men; mix298: steps, m.entities.size())
            if fn.startswith("mix298"):
                lines[i] = ind + 'print(%s.blk_text(steps, m.entities.size(), 60))' % cls
            elif fn.startswith("frame298"):
                lines[i] = ind + 'print(%s.blk_text(frames, n_men, 40))' % cls
            else:
                lines[i] = ind + 'print(%s.blk_text(steps, n_men, int(_env("TOPN", "60"))))' % cls
    open(p, "w").write("\n".join(lines))
print("wrapped %d functions; the collector is %s in %s" % (len(names), cls, collector))
