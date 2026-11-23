# pandei

**pandei** is a **top-down action RPG rendered in 3D with low-poly assets**, built with Godot 4.7.2 and GDScript.

## Controls

| Keys | Action |
| --- | --- |
| `W` `A` `S` `D` (or arrow keys) | Move |

## Project layout

- `src/core/` — autoloads, state machines, event bus, save/load logic, main scene
- `src/entities/` — player, enemies, interactive props (logic & scene wiring)
- `src/systems/` — game rules, combat, inventory, UI controllers
- `src/tools/` — editor scripts, validation tools, build helpers
- `tests/` — GdUnit4 test suites (`*_test.gd`)

## Running

Open the project in Godot 4.7.2 and press Play. The starting scene
(`src/core/main.tscn`) places a placeholder 3D character on a flat ground
plane, controllable with WASD.

## Testing

```bash
godot --headless --path . --import
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ --ignoreHeadlessMode
```

## Asset policy

All shipping visual/audio assets are 100% human-authored or properly licensed
(see `assets_quarantine/`). Until human assets land, 3D placeholders use only
built-in primitive meshes with flat-color materials, are prefixed with
`Placeholder_`, and are tracked in the `ai_placeholder` scene group so they
can be audited and replaced before release builds.
