# AGENTS.md

## Mission & Steam Provenance Guarantee
- This is a **Godot 4.7.2** project using **GdUnit4** (`addons/gdUnit4/`) for automated testing.
- AI agents are used strictly for **GDScript game logic, architecture, automated tests, and editor/build tooling**.
- **Zero AI Art/Audio Policy:** To ensure clean Steam disclosure compliance, all shipping visual and audio assets must be 100% human-authored or properly licensed with human provenance. Never generate, synthesize, or modify art, textures, custom 3D meshes, animations, fonts, sound effects, or music.

## Directory Boundaries
- **AI Read/Write Allowed:**
  - `src/core/` — Autoloads, state machines, event bus, save/load logic.
  - `src/entities/` — Player, enemies, interactive props (logic & scene wiring).
  - `src/systems/` — Game rules, combat, inventory, UI controllers.
  - `src/tools/` — Editor scripts, validation tools, build helpers.
  - `tests/` — GdUnit4 test suites (`*_test.gd`).
- **Read-Only / Human-Owned (DO NOT MODIFY):**
  - `assets_quarantine/` — All human-authored art, audio, fonts, and approved shaders.
  - `addons/gdUnit4/` — Installed test framework (do not edit).
- **Banned File Types for AI Creation/Modification:**
  - Never create, edit, or delete `.png`, `.jpg`, `.jpeg`, `.webp`, `.svg`, `.ase`, `.aseprite`, `.wav`, `.ogg`, `.mp3`, `.flac`, `.ttf`, `.otf`, `.glb`, `.gltf`, `.fbx`, `.obj`, `.blend`, or `.gdshader` files.

## Placeholder Visuals Policy (2D & 3D)
When prototyping scenes or entities before human assets exist in `assets_quarantine/`:
- **Allowed 2D Placeholders:** Standard UI/2D nodes (`ColorRect`, `Polygon2D`, `Line2D`, `Label`) and `CollisionShape2D` with built-in `Shape2D` resources.
- **Allowed 3D Placeholders:**
  - `MeshInstance3D` using **only** built-in `PrimitiveMesh` subclasses (`BoxMesh`, `SphereMesh`, `CapsuleMesh`, `CylinderMesh`, `PlaneMesh`, `PrismMesh`, `TorusMesh`, `QuadMesh`) or `CSGShape3D` primitives (`CSGBox3D`, `CSGSphere3D`, `CSGCylinder3D`, `CSGTorus3D`).
  - Flat-color `StandardMaterial3D` (`albedo_color` only; no textures).
- **Strict Prohibitions:**
  - Never generate custom geometry (`ArrayMesh`, `SurfaceTool`, `MeshDataTool`, `ImmediateMesh`) or save `.tres`/`.mesh` files for visual geometry/materials.
  - Never use procedural texture generators (`NoiseTexture2D`, `GradientTexture2D`) to simulate artwork.
- **Mandatory Placeholder Tracking:**
  - Prefix every placeholder node name with `Placeholder_` (e.g., `Placeholder_BodyMesh`) and add it to the scene group `ai_placeholder` so all placeholders can be audited and replaced before Steam builds.

## Godot 4.7.2 & GdUnit4 Workflow
- Write typed GDScript (`class_name`, static types on variables/parameters/return values) compatible with Godot 4.7.2.
- Keep core game rules decoupled from scene tree dependencies where practical so logic can be unit-tested cleanly.
- Write or update GdUnit4 tests in `tests/` for all new gameplay logic and bug fixes.
- Run headless verification before finishing a task:
  ```bash
  godot --headless --path . --import
  godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ --ignoreHeadlessMode
  ```

## Git & Branching Rules (Strict)
- Never commit to, merge into, or rebase main.
- Pre-Task Branch Check:
  1. Run `git status` and check the active branch before making any edits.
  2. If currently on `main` and the working tree is completely clean (`git status --porcelain` is empty), automatically create and check out a new semantic feature branch before editing files:
     - `feat/short-kebab-name` for new features/systems
     - `fix/short-kebab-name` for bug fixes
     - `chore/short-kebab-name` or `test/short-kebab-name` for tooling/tests
  3. If you are on `main` and the working tree has any uncommitted changes, untracked files, staged files, or merge conflicts, or if you are already on a dirty branch with unrelated work, stop immediately and ask the user before touching Git or writing code.
- Semantic Commits (on feature branches only):
  - Commit logical units of work on the active feature branch using Conventional Commits:
    - feat: short description
    - fix: short description
    - test: short description
    - refactor: short description
    - chore: short description
- Never run destructive Git commands (`git reset --hard`, `git clean -fd`, `git push --force`) without explicit user permission.
