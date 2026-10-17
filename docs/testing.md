# Testing

| Tool | What it does |
|---|---|
| `tools/test.sh` | Unit and corner-case tests (`tests/run_tests.gd`). Fails on any script error. |
| `tools/fuzz.sh` | Random object-tree manipulation with invariant checks (`tests/tree_fuzz.gd`). |
| `tools/stress.sh` | Performance at increasing scale (see [perf/](perf/)). |
| `tools/wordnet-world.sh` | A real-vocabulary test world from WordNet's part-of relations. |
| `tools/synthetic-world.sh` | A synthetic deep-and-wide tree of random words, flat on the ground. |

## Tree fuzzing

```bash
tools/fuzz.sh --seeds=40 --steps=400
tools/fuzz.sh --seed=17 --steps=400 --verbose
```

Each seed starts from a few objects and runs random operations: add,
remove, move, rotate, retarget (point an instance at another object),
re-parent, make unique, create, delete, rename, change block size, edit
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
cache after moves); both were caught.

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
- **Added: re-parenting** (`Project.reparent_instance`), undoable. There's
  no UI for it yet.
- **Open: intermittent renderer crash.** Three times today, Godot 4.7 crashed
  in a memory copy inside its renderer while loading scenes with thousands
  of mesh nodes. It wasn't reproducible on demand (0 of 16 retries, plus
  2,400 edits of instanced objects). Next step: a Godot build with debug
  symbols, or comparing with the Vulkan driver.
