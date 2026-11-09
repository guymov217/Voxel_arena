# CLAUDE.md

WRECKSMITH (formerly Voxel Arena): a physics gladiator brawler in Godot 4.7 (GDScript, Jolt at 120 Hz) with voxel damage,
a weapon forge, 24 beasts and host-authoritative multiplayer (GodotSteam or ENet). UI text is English.

## Layout

```
project.godot       the Godot project (this folder is res://)
scripts/            game code: fighter/, beast/, voxel/, game/ (match, modes, fx...), ui/, net/, autoload/
data/*.json         game tables (weapons, materials, body, beasts, campaign, shop, modes)
shaders/            crowd, flag, sky and voxel shaders (voxel.gdshader: the arena art; voxel_body: bodies, armour, weapons)
art/voxel/          the arena and its props as .glb, made by tools/gen_voxel_art.py (do not hand-edit; rebuild)
tools/              gen_voxel_art.py + voxlib.py (the voxel art), gen_textures.py
tests/              test_*.gd suites, plus probes (steamshots, beastshots, momentshots, net_host...)
native/             voxel_core.gdextension (+ .in, its template); the Linux and Windows libraries in native/bin/ (committed: rebuild both after changing extension/src)
extension/          C++ source of the voxel core (godot-cpp 4.4, scons); has a .gdignore
.github/workflows/  builds the extension and exports Windows, Linux and macOS
```

## Checks

```bash
sh check.sh                       # parse every script
sh run_tests.sh                   # parse check, all suites, two-process ENet test
godot --headless --path . -- --test test_fight
```

Run `run_tests.sh` before committing. Physics tests must stay deterministic (seed the RNG, set
velocities; compare numbers or names, never whole nodes). `run_tests.sh` runs the suites on one
worker thread (an `override.cfg` while they run): on the pool's threads the physics' jobs came
back in a different order run to run, and the same tests passed one run and failed the next. Run
a suite by hand with `[threading] worker_pool/max_threads=1` in `override.cfg` to get the same.
Each test runs in a physics world of its own (tests/runner.gd): in one shared world, a test's
fight came out one way after one set of tests and another way after a different set.

## Conventions

- GDScript: `:=` cannot infer from a Variant or an untyped call; give the type. Avoid names that
  shadow native properties (`scale`, `name`...).
- Full-screen Controls: use `set_anchors_and_offsets_preset`, not `set_anchors_preset`.
- Multiplayer is host-authoritative: anything the host changes mid-round goes to guests in a
  message (Match.guest_message) and is sanitized on arrival. A guest's own gladiator (arms,
  armour, look, teaching, bag, body) lives in his own save: he tells the host in his hello and
  again whenever it changes ("me", Net.push_me), and the host fights him as that (Net.peers).
- `scripts/voxel/greedy.gd` uses the C++ VoxelCore when it is loaded and falls back to GDScript;
  keep both in step (tests/test_native.gd).
- The arena's art is voxel models (art/voxel/*.glb) built by `python3 tools/gen_voxel_art.py`
  (numpy, numba, pillow). Each surface is named `<material>@<voxel cm>`; VoxelArt
  (scripts/game/voxel_art.gd) gives it the voxel shader. The layout numbers in the tool (tiers,
  gates, the box) must match arena.gd. Without the files the old box-built arena is drawn.
  `-- --probe artshots` renders the views.
