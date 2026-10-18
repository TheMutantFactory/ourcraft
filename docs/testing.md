# Testing

| Tool | What it does |
|---|---|
| `tools/test.sh` | Unit and corner-case tests (`tests/run_tests.gd`). Fails on any script error. |
| `tools/fuzz.sh` | Random object-tree manipulation with invariant checks (`tests/tree_fuzz.gd`). |
| `tools/stress.sh` | Performance at increasing scale (see [perf/](perf/)). |
| `tools/wordnet-world.sh` | A real-vocabulary test world from WordNet's part-of relations. |
| `tools/synthetic-world.sh` | A synthetic deep-and-wide tree of random words, flat on the ground. |
| `tools/hole.sh` | The hole scenario: a watchable soak test of creating and deleting object trees. |
| `tools/burst.sh` | The burst scenario: gradient words on platforms burst into flying pieces. |
| `tools/black-rock-city.sh` | A roughly 1:1 Black Rock City: kilometres of roads, thousands of instanced camps. |

## Tree fuzzing

```bash
tools/fuzz.sh --seeds=40 --steps=400
tools/fuzz.sh --seed=17 --steps=400 --verbose
```

Each seed starts from a few objects and runs random operations: add,
remove, move, rotate, retarget (point an instance at another object),
re-parent, re-parent keeping the world position (as dragging in the
outline does), make unique, create, delete, rename, change block size, edit
voxels, undo and redo. Refusals are compared with an independent cycle
check. After every step it checks:

- every instance points at an existing object, and there are no cycles;
- instance ids are unique across the project;
- cached bounds and usage counts match a fresh recompute (checked before
  undo, which would clear a stale cache);
- chunk solid counts match their data;
- undo restores exactly the previous state and redo the next one, and an
  operation that changes nothing adds no history.

Every 25 steps it compares a live `WorldView` with the tree: placements,
each placement drawn exactly once (live or baked), a mesh entry for every
chunk of a placed object, and collision bodies pointing at real paths.
Every 50 steps it saves incrementally and reloads, checks that a fresh save
writes the same `objects.json`, and round-trips a random object through a
bundle.

A failure prints the seed, step and the operations before it, so it can be
replayed with `--seed`. To check that the fuzzer can see bugs, two were
planted on purpose (undo not recorded for removals, and a stale bounds
cache after moves); both were caught. Whether an operation recorded undo is
judged by the newest history entry, not its length, because a full history
(200 steps) drops its oldest entry as it records.

## Corner cases (tests/run_tests.gd)

- Re-parenting into your own descendant, or into yourself, is refused;
  moving within the same parent works; undo restores the old parent.
- **Depth limit:** paths deeper than `Project.MAX_DEPTH` (32) aren't drawn.
  A 40-deep chain renders 33 levels; the data keeps all 40. (Known limit.)
- 1,000 parts on one object render, each drawn once; empty objects have
  zero bounds and survive save/load.
- Four quarter turns are exactly the identity. Integer offsets stay exact
  up to 2^24 smallest blocks (~168 km at 1 cm); beyond that positions round.
  (Known limit.)
- Deleting an object used in many places removes every instance and clears
  undo history; the world can't be deleted.
- Blank names are ignored, names keep accents, duplicates are allowed, and
  undo history is capped at 200 steps.
- Importing a bundle whose object id already exists keeps the local version.

## Synthetic world

```bash
tools/synthetic-world.sh                      # ~5,300 objects, ~39,000 placed copies
tools/synthetic-world.sh --seed=2 --mutations=300 --out=user://projects/synthetic-scrambled.ourcraft
tools/run.sh --project=user://projects/synthetic.ourcraft
```

Random trees up to 14 levels deep, where some parts are shared between
wholes, plus three corner cases: a `deep` chain of 40 levels (only 33
render), a `wide` object with 300 parts (rows wrap at 30 m) and an `empty`
object. Words lie flat on the ground like an org chart. Press **L** in the
game to draw the relationship lines, which come from the live tree and stay
correct after edits. `--mutations` scrambles the world with the fuzzer's
operations (`--check` also runs its invariant checks, slowly).

## Hole scenario

```bash
tools/hole.sh                # watch it
tools/hole.sh --soak=120     # run 120 s, check, report, quit (non-zero exit on failure)
```

An 8 m square hole sits in the middle of the map and destroys anything
that touches it. Three clouds circle above it and each drops a new tree of
upright words every 1.5–3.5 s. The trees fall under gravity with some
sideways drift: most go into the hole, a few land beside it.

- **Destruction:** a destroyed tree is removed and every object only it
  used is deleted from the library (`Project.remove_and_prune`). Objects
  that end up over the hole (dragged there, or landed half over it) start
  falling. World blocks over the hole are erased, and a player who falls in
  is respawned at the edge.
- **Undo:** off while the scenario runs (`Project.set_recording(false)`),
  so the simulation doesn't flood the history.
- **Live drawing:** falling trees and clouds are drawn live
  (`WorldView.set_dynamic`), not baked, since they move every frame.
- **HUD:** shows spawned, destroyed, landed and falling counts and the
  library size.
- **Isolation:** it runs on `user://projects/hole-scratch.ourcraft`, which
  is only saved if you press Ctrl+S.

`--soak` also pokes the hole every 5 s: it drags a landed tree over it,
places a world block over it and drops the player in, and fails if any of
these isn't dealt with within 4 s. At the end it runs the fuzzer's
invariant and view checks on the live project and fails if any object is
left that nothing uses (a leak).

A 120 s soak (2026-10-17): 142 trees spawned, 94 destroyed, 577 objects
deleted, 23 player drops, all checks passed, about 110 fps, RAM +28 MB
(mostly trees that landed and stayed).

## Burst scenario

```bash
tools/burst.sh               # watch it; B bursts the selected or aimed object
tools/burst.sh --soak=60
```

Fourteen stone platforms of different heights stand in a ring. Each has a
couple of words on top, facing the middle, with each letter a step along a
colour gradient (`PaletteRamps`: 8 ramps × 8 steps appended to the palette;
the hotbar still shows the first ten colours). Every 0.6–1.6 s a random word
bursts and new words keep appearing. Platforms never burst. The words are
instances inside their platform objects, so bursting removes nested objects
from baked regions.

A burst (`BurstEffect`) breaks the object (and everything in it) into
irregular pieces of its real voxels that fly out, spin, fall, bounce and
fade away:

- **Slicing.** Each object's voxels are copied into a dense box and split
  by random flood fill: about 0.8·√voxels seed voxels (5–60 per burst,
  shared between nested objects by size) grow into their neighbours, the
  next voxel to grow from picked at random, so borders are ragged. Pieces
  are always connected; bits no seed reaches (a separate letter, a stray
  block) become pieces of their own. At most 1,500 pieces per burst.
- **Big objects** are grouped into chunk³ blocks (most common colour) until
  there are at most 40,000 voxels to slice.
- **Meshing.** Each piece is greedy-meshed by `Mesher` on its own, in its
  own colours, and drawn as a RenderingServer instance (no nodes).
- **Flight.** Pieces are rigid: they spin about their centre of mass, fall,
  and bounce off the ground and off the voxels of objects within 8 m (looked
  up directly in their grids, so it works where no physics bodies exist).
  A piece is treated as a ball of half its smallest extent.
- **Cost.** The gather into the box and the slicing are native kernels
  (`VoxelKernels.gather_box`, `slice_pieces`; GDScript fallbacks in
  `BurstEffect`). Collecting a word takes about 1 ms, a 64³ cube about
  35 ms; a frame of 60 flying pieces about 0.2 ms.

Tests check that every solid voxel ends up in exactly one piece with its
colour (for a word, a grouped 64³ cube and nested objects), that pieces are
connected and repeatable for a seed, that both slicers and both gathers
agree on the rules, that the piece budget holds, and that pieces dropped
onto another object land on it.

**B** bursts the selected object (or the one under the crosshair) in normal
play too, where Ctrl+Z brings it back.

The soak also bursts several words at once every 7 s and checks every burst
made pieces and really removed its word. A 60 s soak (2026-10-17, uniform
cubes): 86 bursts, 10,210 cubes, about 119 fps. With sliced pieces
(2026-10-17): 86 bursts, 1,357 pieces, all checks passed, about 120 fps.

Both scenarios share `game/scenario.gd` (soak timing, end-of-run checks,
report, HUD lines).

## Black Rock City

```bash
tools/black-rock-city.sh                 # ~5,900 objects, ~23,000 placed copies, ~3.5 s
tools/black-rock-city.sh --seed=2 --density=0.1 --out=user://projects/brc-sparse.ourcraft
tools/run.sh --project=user://projects/black-rock-city.ourcraft
```

A test level for chunks, distance and scale, laid out roughly 1:1 after
the Burning Man city plan (sources in [bibliography.md](bibliography.md)).
The clock is the city's: 12:00 is -Z, 3:00 is +X, 6:00 is +Z. You start at
Center Camp facing the Man. Fly with F; flight speeds up with height
(twice as fast at 6 m, 150× at 900 m), so the whole playa can be crossed.

| Part | Built as | Block |
|---|---|---|
| Man (centre), Temple (12:00, 762 m out) | one object each, stepped base | 25 cm |
| Esplanade (762 m) and A–K (to 1,780 m), 12 m wide, 2:00–10:00 | one object per street, sunk flush with the playa | 1 m |
| 17 radials, every half hour from 2:00 to 10:00 | one object each | 1 m |
| 9 plazas on B and G (61 m across) | one ring object, instanced | 1 m |
| Center Camp at 6:00 & A: Rod's Road, about an acre of canopy, sign | object with three parts | 1 m, 50 cm, 10 cm |
| 204 street signs, one per intersection ("4:30 & G") | unique text objects, one instanced post | 5 cm |
| ~4,200 camps in 18 m lots: sector › block › camp | 2–6 instanced tents, shade, RVs and domes each; one in five named | 10 cm, 5 cm |
| 60 word trees on the open playa, OURCRAFT by the Man | WordTrees | 5–1 cm, 25 cm |
| Trash fence, a pentagon about 14.5 km around (circumradius ~2.46 km) | one object | 25 cm |

The ground is 6 km across and lowered 2 cm so road tops don't z-fight it.
Ground, fog, far plane and spawn come from the project's `environment`
(manifest.json), which any world can set.

Estimates, not from the published plans: the Temple's distance (same as
the Esplanade), Rod's Road's radius (91 m), the canopy size and the fence
(it's described as about nine miles around). The 2022 street names and
block depths are used.

**Measured (2026-10-18, M1 Pro, 2720×1710).** Generating takes 3.4 s and
peaks at 0.8 GB. In game: 5,203 baked regions, 22,931 placements, 17,069
of them live (the camp items each have hundreds of copies, so they're
MultiMeshes).

| View (`--fly --pose=…`) | Before distance LOD | With distance LOD |
|---|---|---|
| Spawn at Center Camp (`-2,0.2,3,0,0`) | 8 fps, 215 M triangles | **116 fps**, 3.2 M |
| Over the 3:00 camps (`880,25,40,-90,-25`) | 8 fps, 215 M | **71 fps**, 8.6 M |
| Whole city from 900 m (`0,900,2400,0,-40`) | 18 fps, 44 M | **71 fps**, 2.0 M |

The same city with no camps (`--density=0`) ran at 67 fps before LOD.

**Distance LOD** (`InstanceRenderer`). Before, every copy of a camp item
was drawn at full detail from anywhere in the city: one city-wide
MultiMesh per object, which can't be culled. Now groups of 16 or more
copies are split into 256 m cells. Each cell draws its copies with one
MultiMesh per detail level, switched by Godot visibility ranges:

- **Full detail:** the object's chunk meshes merged into one.
- **Coarse levels:** its voxels grouped 4³ and then 16³ into one, in the
  most common colour (`BurstEffect.voxel_box`, native).
- **Nothing**, once the whole object would be about 2 px tall.

A level is used until its voxels would be 1.5 px tall, plus ¾ of a cell
of margin because ranges are measured to the cell. Edits rebuild the
merged and coarse meshes once an object has been left alone for 0.5 s.

**Found along the way:**

- With one MultiMesh per chunk per cell (14,332 nodes), Metal silently
  rendered whole frames black, HUD included, with no error. Merging each
  object's chunks brought it down to 2,238 nodes, which is fine.
- `--shot` captures are black, and the game is throttled to a few fps,
  while its window is behind other windows: macOS stops presenting
  occluded Metal windows. Keep the window in front when measuring.

`--shot` runs now also print draw calls, objects and triangles per frame.

## What these found (2026-10-17)

- **Fixed: objects created by "make unique" or by importing a bundle were
  never meshed.** Their voxels arrived without a change signal, so baked
  copies were invisible until reload. Forking now announces its chunks, and
  the view queues any chunk of a placed object that has no mesh entry.
- **Fixed: the outline panel froze for 39 s** on the WordNet world.
- **Fixed: instancing threshold.** Drawing any object with 4+ copies via
  MultiMesh made thousands of small instanced groups in the synthetic world
  (19 fps). Objects now need 64+ copies to be instanced; the rest are baked
  (39–47 fps). Baked regions are now a single surface each, with the tree
  depth in UV.x.
- **Added: re-parenting** (`Project.reparent_instance`, and
  `Project.reparent_path`, which keeps the object where it is in the world),
  undoable. In the game, drag a row onto another row in the outline. The
  fuzzer's `keep` operation checks that such moves never change the world
  position.
- **Open: intermittent renderer crash.** Three times today, Godot 4.7 crashed
  in a memory copy inside its renderer while loading scenes with thousands
  of mesh nodes. It wasn't reproducible on demand (0 of 16 retries, plus
  2,400 edits of instanced objects). Next step: a Godot build with debug
  symbols, or comparing with the Vulkan driver.
