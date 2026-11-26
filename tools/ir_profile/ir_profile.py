#!/usr/bin/env python3
"""What the scripts cost, counted in INSTRUCTIONS under valgrind's callgrind instead of timed: the same fight is the same instructions whatever else the machine does, so
a change of one per cent can be read (a clock on a shared machine cannot tell five). The fight is tests/irfight.gd: the diagnostic test's eight in the endless arena.

It REWRITES what it is given, so work on COPIES, never on a checkout (PROJ: a copy of the project with its .godot folder; EXT: a copy of extension/ with godot-cpp in it):

    python3 tools/ir_profile/ir_profile.py ext EXT              the counting calls added to the copy's VoxelCore; then build it WITH SYMBOLS and put it in PROJ:
        (cd EXT && scons platform=linux target=template_release debug_symbols=yes) ; cp EXT/../native/bin/*.so PROJ/native/bin/

    Whole functions (each call of one run inside a native function of its own name; up to 40 a run):
    python3 tools/ir_profile/ir_profile.py funcs PROJ SPEC.json      SPEC: {"scripts/fighter/fighter.gd": ["control", "_drive_arm"], ...} (methods, not static ones)
    python3 tools/ir_profile/ir_profile.py run-funcs PROJ OUT [AT] [SECS]     ->  <function> <calls a step> <million instructions a step> <instructions a call>
        (inclusive of what it calls; the native core's own functions are listed with them. A wrapped call costs about 800 instructions more inside, 2000 outside.)

    The statements of functions (a mark before each, down to DEPTH tabs in; a region runs from its mark to the next mark met, so a statement's count holds what it calls):
    python3 tools/ir_profile/ir_profile.py lines PROJ DEPTH REL:FUNC[:LASTLINE] ...     prints "K function:line statement" (keep it: NAMES)
    python3 tools/ir_profile/ir_profile.py run-lines PROJ NAMES OUTDIR K,K,... [B] [AT]  ->  <K> <times it ran> <instructions a time> <statement>
        (one region is counted at a time, B steps each (4), so a run is as long as its list: split a long list over several runs side by side. An empty statement reads
        about 3150: the mark's own cost, to be taken off each.)

With IR_DRAW=1 in the environment the men's per-frame drawing work is done too (as with a screen: Fighter.process_in_headless), a frame a step.
With IR_FX=1 the match is not a headless one: the effects of a fight are made as in play (blood, sparks, marks, sounds asked for), on a renderer that draws nothing.
AT is the second of the fight the counting starts at (1: eight men closing in, before the first blow; later seconds have the blows and the foes in them, and cost about
three minutes of valgrind each). The instructions of everything are counted, the engine's too; the main thread's only in the statements' way."""
import json, os, re, subprocess, sys

GODOT = os.environ.get("GODOT", "godot")
N_SEC = 40


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


def once(s, a, b, what):
    if s.count(a) != 1:
        sys.exit("cannot place the change (%s)" % what)
    return s.replace(a, b)


def cmd_ext(ext):
    here = os.path.dirname(os.path.abspath(__file__))
    open(os.path.join(ext, "src", "irprof.cpp"), "w").write(open(os.path.join(here, "irprof.cpp")).read())
    p = os.path.join(ext, "src", "voxel_core.h")
    s = open(p).read()
    decl = "".join("\tVariant sec%d(const Callable &c);\n" % i for i in range(N_SEC)) + "\tvoid ir_zero();\n\tvoid reg(int k);\n\tvoid ir_select(int k);\n"
    s = once(s, "\tint drive_api() const;\n", "\tint drive_api() const;\n" + decl, "voxel_core.h")
    s = once(s, "namespace godot {", "#define IR_SECTIONS(X) " + " ".join("X(%d)" % i for i in range(N_SEC)) + "\n\nnamespace godot {", "voxel_core.h, the namespace")
    open(p, "w").write(s)
    p = os.path.join(ext, "src", "voxel_core.cpp")
    s = open(p).read()
    a = '\tClassDB::bind_method(D_METHOD("drive_api"), &VoxelCore::drive_api);\n'
    bind = "".join('\tClassDB::bind_method(D_METHOD("sec%d", "c"), &VoxelCore::sec%d);\n' % (i, i) for i in range(N_SEC))
    bind += '\tClassDB::bind_method(D_METHOD("ir_zero"), &VoxelCore::ir_zero);\n\tClassDB::bind_method(D_METHOD("reg", "k"), &VoxelCore::reg);\n\tClassDB::bind_method(D_METHOD("ir_select", "k"), &VoxelCore::ir_select);\n'
    open(p, "w").write(once(s, a, a + bind, "voxel_core.cpp"))
    print("the counting calls are in %s: build it with debug_symbols=yes" % ext)


def cmd_funcs(root, specfile):
    spec = json.load(open(specfile))
    names = []
    for rel, funcs in spec.items():
        path = os.path.join(root, rel)
        stem = os.path.splitext(os.path.basename(rel))[0]
        out, found = [], set()
        for line in open(path, encoding="utf-8").read().split("\n"):
            m = re.match(r"^func ([A-Za-z_0-9]+)\((.*)\)( -> ([A-Za-z0-9_\[\]\.]+))?:\s*$", line)
            if not (m and m.group(1) in funcs):
                out.append(line)
                continue
            if len(names) >= N_SEC:
                sys.exit("more than %d functions: split them over runs" % N_SEC)
            name, params, ret = m.group(1), m.group(2), m.group(4)
            argn = [re.match(r"^([A-Za-z_0-9]+)", p).group(1) for p in split_params(params)]
            call = "Greedy.core().sec%d(%s__s%s)" % (len(names), name, (".bind(%s)" % ", ".join(argn)) if argn else "")
            names.append("%s.%s" % (stem, name))
            found.add(name)
            retdecl = (" -> " + ret) if ret else ""
            out += ["func %s(%s)%s:" % (name, params, retdecl), "\t" + (call if ret == "void" else "return " + call), "", "func %s__s(%s)%s:" % (name, params, retdecl)]
        for f in funcs:
            if f not in found:
                print("not found in %s: %s" % (rel, f))
        open(path, "w", encoding="utf-8").write("\n".join(out))
    json.dump(names, open(os.path.join(root, "ir_funcs.json"), "w"))
    print("%d functions wrapped (their names: %s/ir_funcs.json)" % (len(names), root))


def cmd_lines(root, depth, jobs):
    k = 0
    for job in jobs:
        rel, fname, maxline = (job.split(":") + ["999999"])[:3]
        path = os.path.join(root, rel)
        src = open(path, encoding="utf-8").read().split("\n")
        head_re = re.compile(r"^func %s\((.*)\)( -> ([A-Za-z0-9_\[\]\.]+))?:\s*$" % re.escape(fname))
        start = next((i for i, l in enumerate(src) if head_re.match(l)), None)
        if start is None:
            sys.exit("function not found: " + fname)
        end = next((i for i in range(start + 1, len(src)) if re.match(r"^(static )?func |^var |^const |^signal |^class |^@|^## ", src[i])), len(src))
        m = head_re.match(src[start])
        params, ret = m.group(1), m.group(3)
        argn = [re.match(r"^([A-Za-z_0-9]+)", p).group(1) for p in split_params(params)]
        retdecl = (" -> " + ret) if ret else ""
        out = src[:start] + ["func %s(%s)%s:" % (fname, params, retdecl)]
        if ret == "void" or not ret:
            out += ["\t%s__l(%s)" % (fname, ", ".join(argn)), "\tGreedy.core().reg(-1)"]
        else:
            out += ["\tvar _r = %s__l(%s)" % (fname, ", ".join(argn)), "\tGreedy.core().reg(-1)", "\treturn _r"]
        out += ["", "func %s__l(%s)%s:" % (fname, params, retdecl)]
        bdepth, cont = 0, False
        for i in range(start + 1, end):
            line = src[i]
            stripped = line.lstrip("\t")
            ind = len(line) - len(stripped)
            if i + 1 <= int(maxline) and bdepth == 0 and not cont and stripped and not stripped.startswith("#") and 1 <= ind <= depth \
                    and not re.match(r"^(else|elif)\b", stripped) and not re.match(r"^(\"\"\"|'''|\))", stripped):
                # (not a pattern of a match: those sit one deeper than the `match`)
                in_match = False
                for j in range(i - 1, start, -1):
                    pl = src[j]
                    if pl.strip() and not pl.strip().startswith("#") and len(pl) - len(pl.lstrip("\t")) < ind:
                        in_match = pl.strip().startswith("match ")
                        break
                if not in_match:
                    print("%d %s:%d %s" % (k, fname, i + 1, stripped.strip()[:90]))
                    out.append("\t" * ind + "Greedy.core().reg(%d)" % k)
                    k += 1
            out.append(line)
            bdepth = max(0, bdepth + bracket_delta(line))
            cont = line.rstrip().endswith("\\")
        open(path, "w", encoding="utf-8").write("\n".join(out + src[end:]))


def valgrind(root, env, args):
    e = dict(os.environ)
    e.update(env)
    return subprocess.run(["valgrind", "--tool=callgrind"] + args + [GODOT, "--headless", "--fixed-fps", "120", "--path", root, "--", "--probe", "irfight"],
                          env=e, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cmd_run_funcs(root, out, at="1", secs="1"):
    names = json.load(open(os.path.join(root, "ir_funcs.json")))
    valgrind(root, {"IR_AT": at, "IR_SECS": secs}, ["--instr-atstart=no", "--callgrind-out-file=" + out])
    ids, calls, incl = {}, {}, {}
    lines = open(out, errors="replace").read().split("\n")
    for i, l in enumerate(lines):
        m = re.match(r"c?fn=\((\d+)\)(?: (.*))?", l)
        if not m:
            continue
        if m.group(2):
            ids[m.group(1)] = m.group(2)
        if not l.startswith("cfn="):
            continue
        nm = ids.get(m.group(1), "")
        m2 = re.search(r"VoxelCore::(sec(\d+)|[a-z_0-9]+)\(", nm)
        if not m2 or "::_gde" in nm or "builtin_vararg" in nm:
            continue
        j = i + 1
        while not lines[j].startswith("calls="):
            j += 1
        key = names[int(m2.group(2))] if m2.group(2) else "native " + m2.group(1)
        calls[key] = calls.get(key, 0) + int(lines[j].split("=")[1].split()[0])
        incl[key] = incl.get(key, 0) + int(lines[j + 1].split()[1])
    steps = int(secs) * 120.0
    for key in sorted(incl, key=lambda x: -incl[x]):
        if calls[key] > 0:
            print("%-34s %8.1f calls a step %9.3f M a step %9.0f a call" % (key, calls[key] / steps, incl[key] / steps / 1e6, incl[key] / calls[key]))


def cmd_run_lines(root, namesfile, outdir, klist, b="4", at="1"):
    names = {}
    for l in open(namesfile):
        p = l.rstrip("\n").split(" ", 1)
        if len(p) == 2 and p[0].isdigit():
            names[int(p[0])] = p[1]
    os.makedirs(outdir, exist_ok=True)
    valgrind(root, {"IR_LIST": klist, "IR_B": b, "IR_AT": at}, ["--instr-atstart=no", "--collect-atstart=no", "--callgrind-out-file=" + os.path.join(outdir, "cg")])
    rows = []
    for fn in os.listdir(outdir):
        if not fn.startswith("cg."):
            continue
        desc = tot = None
        for l in open(os.path.join(outdir, fn), errors="replace"):
            if l.startswith("desc: Trigger:") and "Request: r" in l:
                desc = l.split("Request: r")[1].split()
            elif l.startswith(("totals:", "summary:")) and tot is None:
                tot = int(l.split(":")[1].split()[0])
        if desc and tot is not None:
            rows.append((int(desc[0]), int(desc[1][1:]), tot))
    for k, n, ir in sorted(rows):
        print("%4d %6d %9.0f  %s" % (k, n, ir / max(1, n), names.get(k, "")))


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == "ext":
        cmd_ext(a[1])
    elif len(a) == 3 and a[0] == "funcs":
        cmd_funcs(a[1], a[2])
    elif len(a) >= 4 and a[0] == "lines":
        cmd_lines(a[1], int(a[2]), a[3:])
    elif len(a) >= 3 and a[0] == "run-funcs":
        cmd_run_funcs(*a[1:5])
    elif len(a) >= 5 and a[0] == "run-lines":
        cmd_run_lines(*a[1:7])
    else:
        print(__doc__)
        sys.exit(2)
