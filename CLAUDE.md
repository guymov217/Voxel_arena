# CLAUDE.md

Voxel Arena: a physics gladiator brawler in Godot 4.4 (GDScript, Jolt at 120 Hz) with voxel damage,
a weapon forge, 24 beasts and host-authoritative multiplayer (GodotSteam or ENet). UI text is English.

## Layout

```
project.godot       the Godot project (this folder is res://)
scripts/            game code: fighter/, beast/, voxel/, game/ (match, modes, fx...), ui/, net/, autoload/
data/*.json         game tables (weapons, materials, body, beasts, campaign, shop, modes)
shaders/            crowd and flag shaders
tests/              test_*.gd suites, plus probes (steamshots, beastshots, momentshots, net_host...)
native/             voxel_core.gdextension.in (copied to .gdextension where the library is built); the built library goes in native/bin/ (not committed)
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
velocities; compare numbers or names, never whole nodes).

## Conventions

- GDScript: `:=` cannot infer from a Variant or an untyped call; give the type. Avoid names that
  shadow native properties (`scale`, `name`...).
- Full-screen Controls: use `set_anchors_and_offsets_preset`, not `set_anchors_preset`.
- Multiplayer is host-authoritative: anything the host changes mid-round goes to guests in a
  message (Match.guest_message) and is sanitized on arrival.
- `scripts/voxel/greedy.gd` uses the C++ VoxelCore when it is loaded and falls back to GDScript;
  keep both in step (tests/test_native.gd).
