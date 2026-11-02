#!/usr/bin/env python3
"""Collects the player-facing English strings of the game: string literals in the scripts that read
as words for a player (not paths, keys or identifiers), and the names, descriptions and texts in
data/*.json. Prints counts; writes the catalog (msgid -> [where...]) that the translations in
i18n/<code>.json are made from (Loc).

    python3 tools/i18n_extract.py . i18n/catalog.json"""
import json, os, re, sys
ROOT = sys.argv[1]
OUT = sys.argv[2]
lit = re.compile(r'"((?:[^"\\]|\\.)*)"')
cat = {}
def word_like(s):
    if len(s) < 2 or len(s) > 400: return False
    if s.startswith(("res://", "user://", "va_", "%", "#", "/")) and " " not in s: return False
    if re.fullmatch(r'[a-z0-9_]+', s): return False          # keys, ids
    if re.fullmatch(r'[A-Z]{3,}', s): return True             # a word in capitals (MAIN, BALANCE)
    if re.fullmatch(r'[A-Za-z]+[A-Z][A-Za-z0-9]*', s) and " " not in s: return False   # camelCase ids
    if re.fullmatch(r'[\W\d_]+', s): return False             # punctuation, numbers
    if not re.search(r'[A-Za-z]{2}', s): return False
    if s.endswith((".gd", ".png", ".ogg", ".wav", ".json", ".tscn", ".tres", ".gdshader", ".ttf")): return False
    return s[0].isupper() or " " in s or s[0] in "▲▼✋⟷⇅·•—"
skip_dirs = {"tests", ".godot", "addons"}
for dp, dn, fn in os.walk(os.path.join(ROOT, "scripts")):
    for f in fn:
        if not f.endswith(".gd") or f == "loc.gd": continue
        path = os.path.join(dp, f)
        rel = os.path.relpath(path, ROOT)
        for i, line in enumerate(open(path, encoding="utf-8")):
            code = line.split("##")[0]
            if code.strip().startswith("#"): continue
            if "font_names" in code or "SystemFont" in code: continue   # (font families, never shown)
            # drop trailing comments outside strings (rough)
            for m in lit.finditer(code):
                s = m.group(1)
                if "push_error" in code or "print(" in code or "printerr" in code or "get_node" in code or "has_meta" in code or "get_meta" in code or "set_meta" in code: continue
                if word_like(s):
                    cat.setdefault(s, []).append("%s:%d" % (rel, i + 1))
def walk_json(o, where):
    if isinstance(o, dict):
        for k, v in o.items():
            if isinstance(v, str) and k in ("name", "desc", "description", "text", "title", "sub", "label", "line", "lines", "says", "hint", "story", "intro", "outro", "tip", "flavor", "blurb", "short", "theme"):
                if word_like(v): cat.setdefault(v, []).append(where + "#" + k)
            else:
                walk_json(v, where)
    elif isinstance(o, list):
        for v in o:
            if isinstance(v, str) and word_like(v) and " " in v:
                cat.setdefault(v, []).append(where + "[]")
            else:
                walk_json(v, where)
for f in sorted(os.listdir(os.path.join(ROOT, "data"))):
    if f.endswith(".json"):
        walk_json(json.load(open(os.path.join(ROOT, "data", f), encoding="utf-8")), "data/" + f)
fmt = sum(1 for s in cat if "%" in s)
print("strings", len(cat), "with format", fmt, "words", sum(len(s.split()) for s in cat))
by = {}
for s, w in cat.items():
    top = w[0].split(":")[0].split("#")[0]
    by[top] = by.get(top, 0) + 1
for k, v in sorted(by.items(), key=lambda x: -x[1])[:25]:
    print("  %5d %s" % (v, k))
json.dump(cat, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
