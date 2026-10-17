# Ourcraft project plan

Status: planning and technical prototype  
License: MIT  
Engine: Godot 4  

## 1. Product thesis

Ourcraft is a free and open-source multiscale voxel construction game and
creative medium. It lets people build, simulate, fork, and share places and
working objects at scales ranging from landscapes and buildings to components
and miniatures.

Minecraft makes a single block the unit of terrain, inventory, and labor.
Ourcraft treats a plan as the important unit. A wall may contain framing,
insulation, pipes, fasteners, furniture, and a model village. Players should be
able to enter a structure, inspect how it is assembled, adapt it to new
constraints, and publish a derived version without losing its history.

The core loop is:

> Find a plan -> fork it -> adapt it -> fabricate it -> simulate or inhabit it
> -> publish what happened.

Mining and crafting may eventually exist, but they are not the product's
foundation. Construction, composition, simulation, reuse, and stewardship are.

## 2. Primary audience and initial promise

The initial audience is creative builders who enjoy voxel games, model making,
systems games, level editors, dollhouses, model railroads, CAD, and sharing
their work with other builders.

Initial promise:

> Build a small world at several scales, discover whether it works, and let
> someone else fork it.

The project must earn broader claims through a working build. It should not yet
describe itself as an infinite world, a Minecraft replacement, a collaboration
platform, or a general-purpose CAD system.

## 3. Experience principles

1. **Plans, not piles.** Reusable constructions are first-class objects with
   names, versions, dependencies, and authorship.
2. **Detail is local.** Players subdivide only the regions that need detail;
   the entire world is never represented at maximum resolution.
3. **Changing scale is playful.** Moving from a room to a hinge to a miniature
   should feel legible and surprising rather than like operating a CAD camera.
4. **Simulation explains consequences.** Cost, mass, clearance, access, energy,
   and other constraints turn construction into play.
5. **Forking is normal.** Reuse and adaptation retain visible lineage and
   attribution.
6. **Local ownership comes first.** Projects are ordinary inspectable files.
   Online services are optional conveniences, not custodians of the work.
7. **Servers are portable.** A host should be able to run an experience from a
   versioned manifest and move it elsewhere.
8. **The engine and default game are separable.** Other people should be able
   to create different games with the multiscale construction core.

## 4. First product: Ourcraft — Small Works

The first release is a bounded daily design-and-simulation game for desktop and
the web. It is deliberately not an infinite survival world.

Each challenge provides:

- a small build volume;
- a short client or story brief;
- a limited material palette;
- a budget or resource constraint;
- one functional requirement;
- a starting plan that can be forked when appropriate; and
- a result card that can be saved and shared.

Example challenges include fitting a fishing cabin inside a shipping
container, repairing a dollhouse staircase, making a mouse-sized bakery inside
a wall, or adapting someone else's enclosure after a component changes size.

### Minimum playable loop

1. Choose a challenge or fork a previous solution.
2. Place, remove, paint, select, copy, and transform voxel material.
3. Focus a selected region and subdivide it for finer work.
4. Assemble at least one reusable plan into the build.
5. Run a small deterministic simulation.
6. Receive an understandable result: fit, cost, mass, clearance, or failure.
7. Save the build locally and export a compact shareable artifact.

### Initial scale model

The experiment should support four addressable detail levels:

- 1: world or architectural unit;
- 1/4: structural detail;
- 1/16: object detail; and
- 1/64: component and miniature detail.

These are coordinate resolutions, not a requirement to allocate every possible
cell. If the base unit is subdivided by 64 on all three axes, it contains
262,144 possible microcells. Only edited regions may allocate fine data.

### Initial simulation

Start with two cheap, legible systems:

- **material accounting:** quantity, mass, and cost by material; and
- **clearance:** whether a character or designated moving part can traverse its
  required swept volume.

Structural strength, fluids, electricity, heat, manufacturing tolerances,
ecology, and economies remain later experiments.

## 5. Vertical-slice acceptance criteria

The first public build is complete when a new player can:

- open it on desktop or in a supported web browser;
- understand the camera and basic editing tools without a tutorial video;
- complete one challenge in under ten minutes;
- subdivide one region to 1/64 resolution without a visible frame-rate
  collapse;
- create and place a reusable plan;
- see cost and clearance react to the construction;
- undo and redo destructive edits;
- save, close, reload, and obtain the same result;
- fork an included solution with retained attribution; and
- export a result image plus a portable project bundle.

The slice does not require accounts, cloud storage, procedural terrain,
real-time multiplayer, combat, mobs, mining, crafting, or a public marketplace.

## 6. Technical strategy

### 6.1 Prototype stack

- Godot 4 with the Compatibility renderer for the first web-capable build.
- GDScript for the game shell and initial algorithms.
- Integer coordinates and deterministic operations in the persistent model.
- ArrayMesh or another chunk-mesh implementation for rendered voxel surfaces;
  no scene node per voxel.
- A native GDExtension only after profiling identifies a proven bottleneck.
- Automated headless tests for serialization, coordinate transforms, plan
  instancing, and simulation rules.

Existing Godot voxel projects may be used for research and short-lived spikes,
but the saved-artifact model must remain owned by Ourcraft. Terrain technology
must not dictate the plan format.

### 6.2 Spatial representation

Treat macro terrain and detailed constructions as related but distinct needs.
The first prototype should compare two representations:

1. a sparse tree of subdivided cells; and
2. fixed-size sparse bricks referenced from a hierarchy.

Choose using measured editing latency, memory use, mesh rebuild time,
serialization complexity, and ease of plan instancing. Do not commit to an
octree merely because the product is hierarchical.

Required properties:

- allocate fine cells only in edited regions;
- rebuild only affected mesh chunks;
- instance repeated plans instead of expanding them eagerly;
- express transforms exactly at every supported scale;
- distinguish an instance from a locally modified fork; and
- preserve stable identifiers across save/load cycles.

### 6.3 Artifact model

An Ourcraft project is a directory that can be versioned with Git and inspected
without an Ourcraft account. The first format should contain:

```text
project.ourcraft/
├── manifest.json
├── world/
│   ├── index.json
│   └── chunks/
├── plans/
├── materials/
├── simulations/
├── previews/
└── provenance/
```

The manifest records:

- format and engine compatibility versions;
- title, description, authors, and license;
- root scene and coordinate conventions;
- plan and material dependencies;
- content hashes;
- fork ancestry; and
- optional challenge and simulation configuration.

Binary chunk data is acceptable for performance, but it must be documented,
versioned, independently testable, and accompanied by human-readable metadata.
Canonical ordering and deterministic serialization should make diffs and
content hashes stable.

### 6.4 Plans and instances

A plan is a versioned, reusable construction. It may contain voxel data,
nested plan instances, attachment points, parameter defaults, simulation
metadata, and a preview. Plans should support:

- placement, rotation, mirroring, and scale-compatible attachment;
- nested instances;
- material substitution;
- local overrides;
- conversion of an override into a fork;
- dependency enumeration; and
- attribution and license display.

Arbitrary scripting inside downloaded plans is excluded from early releases.
Declarative behaviors should precede executable extensions so that browsing and
simulation remain safe and deterministic.

### 6.5 System boundaries

Keep these packages conceptually separate even if they begin in one Godot
project:

- **ourcraft-core:** coordinates, sparse storage, operations, plans, formats;
- **ourcraft-renderer:** meshing, picking, highlighting, level of detail;
- **small-works:** challenges, scoring, interface, and default materials;
- **ourcraft-sim:** deterministic simulation modules;
- **ourcraft-cli:** validate, inspect, pack, unpack, and migrate artifacts;
- **ourcraft-catalog:** later web browsing, search, previews, and federation;
- **ourcraft-server:** later authoritative multiplayer and automation.

The core should not depend on the catalog or an Internet connection.

## 7. Delivery phases

Dates begin when active development starts. Each phase ends with a demonstrable
artifact and a decision, not merely more infrastructure.

### Phase 0 — Questions and spikes (weeks 1–2)

Deliver:

- a one-page interaction specification;
- camera and selection prototype;
- coarse-to-fine coordinate and editing spike;
- sparse-tree versus sparse-brick benchmark;
- chunk meshing and picking benchmark;
- draft artifact manifest; and
- desktop and single-threaded web performance notes.

Decision: can local subdivision feel immediate on representative hardware?

### Phase 1 — Construction toy (weeks 3–5)

Deliver:

- bounded editable volume;
- four scale levels;
- place, remove, paint, select, copy, transform, undo, and redo;
- materials with quantity, mass, and cost;
- save/load with round-trip tests;
- one reusable nested plan; and
- desktop builds for development testers.

Decision: do five testers voluntarily make something not requested by the
brief?

### Phase 2 — Small Works vertical slice (weeks 6–9)

Deliver:

- three challenges;
- clearance simulation;
- legible results and failure explanations;
- supplied starting plans and example solutions;
- local fork lineage;
- screenshot/result-card export;
- first browser build; and
- concise onboarding embedded in the game.

Decision: do players complete, replay, or fork rather than merely admire the
technology?

### Phase 3 — Shareable alpha (weeks 10–12)

Deliver:

- documented alpha artifact format;
- pack, unpack, validate, and inspect commands;
- downloadable project bundles;
- static catalog pages for submitted builds;
- license and attribution display;
- telemetry that is optional, minimal, and documented; and
- public source repository, issue templates, contributor guide, and tagged
  alpha release.

Decision: can another person publish a plan and can a stranger successfully
fork it without direct assistance?

### Phase 4 — Library and federation research

Begin only after the shareable alpha demonstrates repeat creation and reuse.

Explore:

- catalog indexing without taking custody of canonical repositories;
- signed manifests and content-addressed assets;
- dependency resolution and lockfiles;
- remote Git and static HTTP catalogs;
- following and curating independent catalogs;
- moderation boundaries;
- cross-catalog search; and
- browser previews that do not execute untrusted code.

### Phase 5 — Portable servers and multiplayer research

Begin only after the single-player artifact and simulation model is stable.

Explore:

- headless Godot server builds;
- authoritative edit operations rather than raw voxel replication;
- permissions by region, plan, and operation;
- conflict handling and edit history;
- versioned experience manifests;
- OCI images and container-compose examples; and
- export, backup, migration, and federation between hosts.

Multiplayer must not make local projects second-class or turn the public service
into mandatory managed hosting.

## 8. Twelve-week evidence goals

Recruit testers from voxel-building, model-making, Godot, and systems-game
communities rather than relying only on friends already invested in the idea.

Measure:

- percentage who complete their first challenge;
- median time until the first successful edit at a finer scale;
- percentage who begin a second challenge;
- percentage who fork an existing plan;
- creations made without an explicit assignment;
- exported or shared result cards;
- successful artifact round trips;
- peak memory and worst-frame mesh rebuild time; and
- requests to create, host, or commission something specific.

Promising alpha evidence would be:

- 8 of 10 observed testers complete one challenge without developer help;
- at least half begin another build or fork;
- at least three people create something unprompted;
- at least two people publish a reusable plan; and
- one community, artist, educator, or server operator asks to use the system for
  a concrete experience.

These are learning thresholds, not market-size claims.

## 9. Performance and quality budgets

Initial targets, to be revised from measurements:

- 60 frames per second during ordinary editing on a mid-range desktop;
- no interaction stall longer than 100 ms for a typical single edit;
- fine-detail mesh rebuilds limited to affected chunks;
- first web interaction within 10 seconds on a normal broadband connection;
- a representative Small Works project under 10 MB compressed;
- deterministic save/load and simulation results on supported platforms; and
- recovery from interrupted writes without corrupting the last valid save.

Accessibility requirements include remappable controls, keyboard-operable UI,
scalable text, high-contrast selection states, reduced-motion options, and no
meaning conveyed only by color.

## 10. Explicit non-goals for the alpha

- Infinite procedural terrain.
- Minecraft file or protocol compatibility.
- Survival progression, combat, mobs, or a crafting tree.
- Real-time multiplayer.
- An in-game economy or cryptocurrency.
- A general CAD replacement.
- Photorealism or physically complete simulation.
- Mobile editing.
- A universal mod API.
- Executing arbitrary downloaded scripts.
- Mandatory accounts, cloud saves, or managed hosting.
- A commercial asset marketplace.

Importers, exporters, and compatibility adapters should be evaluated after the
native plan model works; they must not define it prematurely.

## 11. Community and governance

The repository and artifact specifications remain public under clear licenses.
Project governance should grow with actual contributors rather than being
simulated in advance.

Before accepting outside plan submissions, publish:

- a contributor covenant and moderation policy;
- accepted content and code licenses;
- attribution behavior for forks and nested plans;
- a security-reporting process;
- rules for trademarks and third-party assets; and
- a documented path for exporting or mirroring catalog data.

The default catalog should favor remixable work and make license compatibility
visible before a user forks or bundles a plan.

## 12. Sustainable work and revenue

The open engine, formats, local tools, and federation protocol should remain
usable without payment. Potential paid work sits around the commons:

- commissioned worlds, installations, and promotional experiences;
- private catalogs and deployment support;
- training and workshops;
- migration, validation, and long-term maintenance;
- curated experience packs;
- art, museum, education, and community projects; and
- support contracts for organizations running their own servers.

Do not build billing, subscriptions, or managed hosting before users repeatedly
create and exchange plans. Early commercial validation is a paid request for a
specific experience, not a pricing page.

## 13. Principal risks and responses

### Scope collapse

Risk: attempting an infinite sandbox, CAD tool, simulation engine, catalog, and
multiplayer platform at once.

Response: ship the bounded Small Works loop and require evidence before opening
each later phase.

### Voxel explosion

Risk: treating 1/64 scale as a uniform grid creates impossible memory, meshing,
physics, and networking costs.

Response: allocate detail locally, instance plans, mesh surfaces, and benchmark
representations before selecting one.

### Editor without a game

Risk: technically capable tools produce no reason to return.

Response: every public milestone includes briefs, constraints, consequences,
and results that can be discussed or shared.

### Format churn

Risk: public creations become unreadable as the prototype changes.

Response: version every artifact, provide validators and migrations, and delay
a stability promise until the alpha model survives real forks.

### Unsafe community content

Risk: executable extensions, hostile files, license conflicts, and moderation
costs arrive with sharing.

Response: begin with declarative artifacts, strict parsers, explicit limits,
visible licenses, static previews, and no automatic script execution.

### Founder distraction

Risk: the long-term vision consumes time required for income and shorter
creative releases.

Response: use time-boxed phases, keep the prototype small enough to demonstrate
on a weekly stream, and pause after any decision gate that does not produce the
required evidence.

## 14. Open decisions

Resolve through prototypes rather than prolonged abstraction:

- What physical length, if any, does one base unit represent?
- Is scale entered through semantic objects, spatial focus, or both?
- Which sparse representation produces the best editing and persistence model?
- Are all scale transitions powers of four, or should plans declare their own
  rational resolution?
- What is the smallest useful plan parameter system?
- How are nested licenses summarized and conflicts explained?
- Should a fork retain a live dependency or snapshot its parent by default?
- Which simulation consequence is most fun after cost and clearance?
- Can the browser build share the native file format without compromising it?
- What name should be used before investing in identity and trademark work?

## 15. First five days

### Day 1 — Interaction and coordinate contract

- Write the coordinate, scale, selection, and focus rules.
- Sketch the build interface and one complete challenge.
- Create the Godot project with a headless test target.
- Implement exact conversion between the four initial scale levels.

### Day 2 — Editing spike

- Render one bounded chunk.
- Implement ray picking, place, remove, and paint.
- Rebuild only affected geometry.
- Record edit latency and memory use.

### Day 3 — Subdivision spike

- Allow a selected cell or region to acquire finer detail.
- Make focus transitions understandable through camera movement and overlays.
- Demonstrate coarse and fine geometry touching without gaps.
- Save and reload the edited result.

### Day 4 — Plans and undo

- Define a minimal plan manifest.
- Capture a selection as a plan and place two instances.
- Add operation-based undo and redo.
- Modify one instance and convert it into a local fork.

### Day 5 — First consequence

- Add material quantity, mass, and cost.
- Build the smallest playable challenge around a budget.
- Export a desktop build and attempt a single-threaded web build.
- Record failures, performance, and the next decision in the repository.

## 16. References for initial technical investigation

- [Godot procedural geometry documentation](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/index.html)
- [Godot web export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Voxel Tools for Godot](https://github.com/Zylann/godot_voxel)
- [Luanti, an established FOSS voxel game platform](https://www.luanti.org/)

These references are research inputs, not architectural commitments.
