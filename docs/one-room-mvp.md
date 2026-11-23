# One Room — MVP plan

Status: proposed (2026-11-23)  
Narrows: [project plan](project-plan.md) §4–§7 (Phase 1 and the first half of Phase 2)

## 1. Why this plan exists

The engine is ahead of the game. Nested objects, instancing, forking with
**Make unique**, undo, save/load, a native mesher, distance LOD and an object
library all work. The recent work has been tech demos: WordNet, the hole, burst,
Black Rock City and Katamari. They proved the technology, but none of them gives
a player a reason to build.

This plan picks one loop and holds the next build to it.

## 2. The bet

Many Minecraft players start by building a house. The house does two jobs:

- **Safety.** It is a reason to build.
- **Identity.** It is *my* space, designed my way.

Creative mode keeps the second job and removes the first. A blank plot with
no reason to build tends to stall people. One Room replaces the safety reason
with **a space worth furnishing and someone to furnish it for.** It adds the one
thing other voxel builders cannot do: **rooms inside rooms**.

> Hypothesis: players given an interesting space, a small palette of
> furniture, and the ability to dive into any object will build past the brief,
> change scale without being told to, and want to show someone the result.

## 3. The loop

1. Pick a starting space, with an optional one-line brief.
2. Furnish it from the palette: place, move, rotate, recolour.
3. Dive into an object to change it at finer detail: open the dresser, edit
   the lamp, furnish the dollhouse.
4. Light it and inhabit it: time of day, lamps, the cube sits or stands in
   it.
5. Take a picture: a result card with the title, the space and a picture.
6. Save it as a plain project folder that someone else can open and fork.

There is no scoring, material budget or clearance simulation in this build.
Those come back in Small Works once the loop holds up (see §8).

## 4. Scope

### 4.1 Starting spaces (3)

Each one is a pre-built shell, so the first view is already worth a screenshot.
Each also has a built-in reason to change scale.

| Space | Base blocks | Why it is in |
| --- | --- | --- |
| Shipping-container cabin | 10 cm | Tight constraint, familiar shape, a strong first screenshot |
| Attic with a dollhouse | 10 cm room, 1 cm dollhouse | The room-inside-a-room moment is built into the space |
| Mouse's room inside a wall | 1 cm | Starts the player small; the human room is visible beyond the wall |

Each space has an optional brief of one sentence, for example *"A lighthouse
keeper's bunk: a bed, somewhere to cook, a view."* The brief is a prompt only.
Nothing checks whether the player followed it.

### 4.2 Plans (about 30, hand-made)

Every palette item is an Ourcraft object built **in Ourcraft, with the
in-game tools, saved in the normal format**. Nothing is generated or imported
for this build. Making them tests the editor and the format: each rough edge
hit while making a chair is a rough edge a player would hit too. Log them (§7).

Suggested split, about 6 per group:

- **Sit and sleep:** chair, stool, bed, bunk, sofa, beanbag.
- **Surfaces and storage:** table, desk, shelf, dresser *with drawers as child
  objects*, crate, wardrobe.
- **Light:** floor lamp, desk lamp, candle, string lights, window, skylight.
- **Life:** plant, rug, poster, mug, book stack, cat.
- **Structure:** door, stairs, ladder, partition wall, railing, dollhouse shell.

At least a third of them must have meaningful insides, such as drawers, a book
with pages, or a dollhouse with rooms. Without insides, diving has nothing to
find.

### 4.3 Verbs

Most of these already exist. This build polishes them and does not add new
verbs.

| Verb | Today | This build |
| --- | --- | --- |
| Place from library | Tab panel list | **Palette** (§5) |
| Move / rotate / delete | G, R, Del | Smooth snapping to floor and walls; rotation preview |
| Recolour | Pick and paint per block | Recolour a whole object or instance in one action |
| Dive in / out | Q, Enter, Backspace | A clear transition: the camera eases in and the player shrinks to fit |
| Fork | U (Make unique) | Prompt on the first edit of a shared instance: "Change all, or just this one?" |
| Undo / redo | Ctrl+Z | Covers every verb above, including recolour and dive |
| Save | Ctrl+S | Autosave plus named saves |

### 4.4 Light and inhabitant

- A time-of-day slider and a few lamp plans that cast light. Lighting does
  more for screenshots than any amount of detail.
- The existing cube player can stand in the room in third person and sit on
  anything tagged as a seat. That shows scale without a measuring tool.

### 4.5 Result card

One key captures a framed image: the space, title, author and the date. It is
written as a PNG next to the project folder. Sharing is done by the player
outside the game.

## 5. Decision: palette now, database browser later

**Now:** a palette is a grid of thumbnails in five tabs (§4.2). Click a
thumbnail to hold the plan, then click to place it. It reads from the
existing object library. Thumbnails are rendered once when a plan is saved.

**Not now:** search, tags, filters, metadata editing, a WordNet-backed
taxonomy, remote catalogs.

**Build a real browser when any of these happens:**

- the palette passes about 40 plans;
- a playtester asks "where's the …?" and the answer exists;
- players start trading plan files.

Until then, put the effort into camera, selection, snapping and undo. Those
make builders quit; a missing item rarely does.

## 6. Out of scope for this build

Mining, crafting, survival, scoring, budgets, the clearance simulation, a
browser (web) build, accounts, catalogs, multiplayer, procedural terrain and
new tech demos. Parked feature branches stay parked.

## 7. Schedule

These dates are targets. They assume the Raves of Mud and FFFF releases ship in
December.

| Week | Dates | Done when |
| --- | --- | --- |
| 1 | Jan 5–9 | Palette reads the library with thumbnails; snapping to floor and walls; the container space exists |
| 2 | Jan 12–16 | 15 plans made in-game; dive transition; recolour-object; rough-edge log started |
| 3 | Jan 19–23 | 30 plans; attic and mouse-room spaces; time of day and lamps; sit |
| 4 | Jan 26–30 | Result card; fork prompt; autosave; desktop build a stranger can run cold |
| 5–6 | Feb 2–13 | Five observed playtests (§8) |
| — | Feb 16 | Decision (§8) |

The rough-edge log (`docs/one-room-rough-edges.md`) records every friction hit
while making plans: what you were doing, what went wrong, and whether it was
fixed. It is the backlog for weeks 2–4, and it is how the claim that we
"improve the UX as we hit the rough edges" gets measured.

## 8. Playtests and the decision

**Who:** five people who have not seen Ourcraft. At least one should be about
10–14 years old, and at least one should be a model-maker or
dollhouse/diorama person. Friends who already know about the project don't
count.

**How:** give them the build and a single sentence, "build a room you'd want to
show someone," then watch without helping for 20 minutes. Record the screen if
they agree.

**Measure:**

| Measure | How |
| --- | --- |
| Time to first "look at this" | Minutes until they point something out unprompted |
| Unprompted scale change | Did they dive or shrink without being told? Yes/no, and when |
| Session length | Did they keep building past 15 minutes? |
| Beyond the brief | Did they build something no palette item or brief suggested? |
| Share intent | Did they take a result card or ask how to send it? |
| Stuck points | Every time they asked for help or gave up on a verb |

**Gate:** if at least 3 of 5 reach the "look at this" moment, and at least 2 of 5
change scale unprompted, One Room is the MVP. The next step is Small Works
briefs with cost and clearance (project plan Phase 2) and a browser build.

If not, change the starting spaces and the palette before adding any system,
then run three more playtests. Do not move on to catalogs, sharing
infrastructure or multiplayer on technical progress alone.

## 9. Open questions

- Should the brief be shown, offered, or hidden behind a button?
- Is diving into an object (an entering transition) or shrinking the player
  (`,` `.`) the better way to change scale? This build should keep both and
  watch which one testers use.
- Should a starting space be locked (walls not editable) to keep the focus on
  furnishing, or fully editable?
- Can one object hold an instance of an ancestor (the attic contains a
  dollhouse of the attic)? If not, the dollhouse is a separate shell, and that
  is fine for this build.
