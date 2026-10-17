# Ourcraft

A free, open-source Godot experiment in multiscale voxel construction—build,
simulate, fork, and share worlds down to 1/64-scale detail.

Ourcraft is at the planning and technical-prototype stage. The first goal is a
small, bounded building game that can prove whether moving between architectural,
object, and miniature scales is useful and fun.

See the [project plan](docs/project-plan.md) for scope, milestones, architecture,
validation criteria, and the first five days of work.

## Running the MVP

Requires Godot 4.7. The scripts in `tools/` find Godot on your `PATH`, in
`/Applications`, `~/Applications` or `~/Downloads`. Set `GODOT=/path/to/godot`
to use a different copy.

```bash
tools/run.sh          # play (tools/run.sh --demo starts a fresh demo street)
tools/test.sh         # headless core tests; non-zero exit on failure
tools/edit.sh         # open in the Godot editor
tools/build-native.sh # build the C++ extension (recommended, see below)
```

### Native extension

Filling and meshing voxels run in a small C++ GDExtension (`native/`), which
is about 50× faster than the GDScript versions. A 1 m cube at 1 cm resolution
takes a couple of milliseconds. Without the extension, the game falls back
to GDScript automatically.

```bash
git submodule update --init native/godot-cpp
python3 -m pip install --user scons
tools/build-native.sh
```

The first build compiles godot-cpp and takes about five minutes. Later builds
take seconds. The output goes to `bin/`, which isn't committed. The tests
compare the native and GDScript results. Set `OURCRAFT_NO_NATIVE=1` to force
the GDScript paths.

Known issue: Godot 4.7 can crash while exiting the first import of a fresh
checkout after the extension is built. The import still completes, the tools
scripts retry it automatically, and later runs are unaffected.

The first launch builds a demo street (World › Street › House › Kitchen ›
Table › Fork). Press **Ctrl+S** to save it to
`user://projects/default.ourcraft/`. Once saved, later launches load it. The
folder layout is described in [docs/file-format.md](docs/file-format.md).

### WordNet test world

`tools/wordnet-world.sh` builds a large test world from the part-of relations
in [Open English WordNet](https://en-word.net/) (CC-BY 4.0; downloaded on
first use into the git-ignored `data/`). Every object is its word written in
blocks, colored by WordNet category. Its parts are smaller words in a row in
front of it: wholes use 10 cm blocks, parts 5 cm, then 2 cm, then 1 cm. A
part shared by several wholes is one object instanced in each. The world has
about 7,000 objects and 8,700 placed copies, up to 15 levels deep.

```bash
tools/wordnet-world.sh
tools/run.sh --project=user://projects/wordnet.ourcraft
```

Sources are listed in [docs/bibliography.md](docs/bibliography.md).

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
- Where faces of nested objects line up in the same plane, the **deeper object
  wins**, so a child reads as a layer on top of its parent.
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
| T | Toggle placing flush on the aimed surface (default) or snapped to the brush grid |
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
| H | Show/hide the controls overlay |
| Ctrl+= / Ctrl+- / Ctrl+0 | Text size up / down / reset (default is 2× the screen's scale, so 4× on Retina) |

## Layout

- `core/`: sparse voxel grid, objects, instances, project, undo, file format
- `render/`: greedy chunk mesher, the world view with shared per-object meshes, overlays
- `game/`: player controller and input handling
- `ui/`: HUD and side panel
- `tests/`: headless core tests
- `tools/`: run, test, editor, native build, stress and WordNet world scripts
- `native/`: C++ GDExtension for voxel fill and meshing (godot-cpp is a submodule)
