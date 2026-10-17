# Ourcraft

A free, open-source Godot experiment in multiscale voxel construction—build,
simulate, fork, and share worlds down to 1/64-scale detail.

Ourcraft is at the planning and technical-prototype stage. The first goal is a
small, bounded building game that can prove whether moving between architectural,
object, and miniature scales is useful and fun.

See the [project plan](docs/project-plan.md) for scope, milestones, architecture,
validation criteria, and the first five days of work.

## Running the MVP

Requires Godot 4.7. Open `project.godot` in the Godot editor and press Play, or:

```bash
godot --path .
```

Run the core tests headlessly:

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

The first launch builds a demo street (World › Street › House › Kitchen ›
Table › Fork). Press **Ctrl+S** to save it to
`user://projects/default.ourcraft/`. Once saved, later launches load it.

## Concepts

- **Smallest block size** is a project setting (default 1 cm; Tab → Settings).
  All coordinates are integers in this unit.
- An **object** has its own voxels plus nested instances of other objects.
  Each object has a block size that is a multiple of the smallest block. The
  demo house uses 10 cm blocks and the fork uses 1 cm, so fine detail stays
  local and cheap.
- An **instance** places an object inside another one. Copies share the
  same object, so editing one updates them all. **Make unique** (U) forks the
  copy into its own object.
- You always **edit** one object at a time. Blocks you place and break go
  into it. Enter an object to edit it in context; press I to isolate it.

## Controls

| Input | Action |
| --- | --- |
| WASD, Space, Shift | Move, jump, sprint |
| F | Toggle flying (Space/Shift go up/down) |
| `,` `.` | Shrink/grow yourself (0.05×–2×) for fine work |
| Left / right / middle click | Break / place / pick colour |
| 1–0, mouse wheel | Colour, brush size (1–100 cm) |
| Q | Select the object under the crosshair; press again to walk up the tree |
| Shift+Q | Walk back down toward the object under the crosshair |
| Enter / Backspace | Edit the selected object / leave the current object |
| I | Isolate the object being edited |
| N | New object at the crosshair (block size = current brush) |
| G, R, Del | Move, rotate 90°, delete the selected instance |
| Ctrl+C / Ctrl+V / Ctrl+D | Copy, paste an instance, duplicate |
| U | Make the selected instance unique (fork) |
| Ctrl+Z / Ctrl+Shift+Z | Undo / redo |
| Ctrl+S / Ctrl+O | Save / reload |
| Tab | Panel: outline tree, object library (rename, place, export, import, delete), settings |

## Layout

- `core/`: sparse voxel grid, objects, instances, project, undo, file format
- `render/`: greedy chunk mesher, the world view with shared per-object meshes, overlays
- `game/`: player controller and input handling
- `ui/`: HUD and side panel
- `tests/`: headless core tests
