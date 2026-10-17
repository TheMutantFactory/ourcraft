# Testing

| Tool | What it does |
|---|---|
| `tools/test.sh` | Unit and corner-case tests (`tests/run_tests.gd`). Fails on any script error. |
| `tools/fuzz.sh` | Random object-tree manipulation with invariant checks (`tests/tree_fuzz.gd`). |
| `tools/stress.sh` | Performance at increasing scale (see [perf/](perf/)). |
| `tools/wordnet-world.sh` | A real-vocabulary test world from WordNet's part-of relations. |
| `tools/synthetic-world.sh` | A synthetic deep-and-wide tree of random words, flat on the ground. |
| `tools/hole.sh` | The hole scenario: a watchable soak test of creating and deleting object trees. |
| `tools/burst.sh` | The burst scenario: gradient words on platforms burst into flying cubes. |

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

A burst (`BurstEffect`) turns the object's blocks into coloured cubes that
fly out, spin, fall, bounce on the ground and shrink away, simulated on the
CPU into a single MultiMesh. Blocks are grouped into chunk³ cubes in their
most common colour:

- chunk grows (2, 4, 8…) until there are at most 1,500 cubes;
- chunk is at least big enough for 4 cm cubes, since 1 cm cubes are specks
  from a few metres away.

Slicing objects into irregular pieces is a later step. Cubes only bounce
off the ground, not off other objects.

**B** bursts the selected object (or the one under the crosshair) in normal
play too, where Ctrl+Z brings it back.

The soak also bursts several words at once every 7 s and checks every burst
made cubes and really removed its word. A 60 s soak (2026-10-17): 86 bursts,
10,210 cubes, all checks passed, about 119 fps.

Both scenarios share `game/scenario.gd` (soak timing, end-of-run checks,
report, HUD lines).

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
