# Design Notes: Vertical Building (Scaffolds & Elevation)

## Core Concept

Buildings can be raised to higher levels by placing **scaffolds** beneath them. The world has a ground level (level 0) and up to **4 elevated levels** (levels 1-4). Elevation provides production speed bonuses at the cost of increased power draw, with asymmetric vertical logistics creating a new dimension of factory design.

## Scaffold Mechanics

### Raising Buildings

To elevate a building, the player places a scaffold structure at the same tile location. The scaffold pushes the existing building up one level, occupying the ground-level slot itself. Stacking scaffolds raises the building further:

```
Level 4:  [Machine]           ← 4 scaffolds deep, fastest but most expensive
Level 3:  [Scaffold]
Level 2:  [Scaffold]
Level 1:  [Scaffold]
Level 0:  [Scaffold]          ← ground level occupied by scaffold base
```

Each scaffold level requires its own scaffold building below. A level-3 machine needs 3 scaffolds stacked beneath it.

### Scaffold Tiers

**Base Scaffold**: No overhang — can only be placed directly above a ground-level tile that has a scaffold or building below it. The elevated footprint mirrors the ground footprint exactly.

**Advanced Scaffold**: Allows slight overhang (1 tile). Can extend a platform one tile past the edge of the support structure below. This enables compact elevated clusters over areas without ground-level buildings (e.g., above conveyor highways or empty tiles).

```
Ground:     [S] [S] [S]
Level 1:   [A] [S] [S] [S] [A]    ← advanced scaffolds overhang by 1 tile each side
```

Overhang rules:
- An advanced scaffold must be adjacent (cardinal) to a supported scaffold on the same level
- Maximum 1 tile of overhang from the nearest supported column
- Diagonal overhang is not allowed
- An overhanging scaffold can support further levels above it (it's structurally valid once placed)

### Escalating Scaffold Costs

Scaffold construction cost increases with height, making tall structures progressively more expensive:

| Level | Scaffold Cost | Cumulative (to reach this level) | Character |
|---|---|---|---|
| 1 | 1× base cost | 1× | Accessible mid-game |
| 2 | 2× base cost | 3× | Meaningful investment |
| 3 | 4× base cost | 7× | Expensive — selective use |
| 4 | 8× base cost | 15× | Prohibitive — only for key machines |

The exponential scaling means level 1 is broadly useful, level 2 is for important production lines, level 3 is for critical bottleneck machines, and level 4 is reserved for the single most important building in your factory. Players naturally create a production hierarchy where height reflects priority.

**Scaffold base recipe** (TBD — should require mid-tier materials):
- Candidate: steel_frame + concrete + advanced_composite
- Advanced scaffold adds: titanium_frame + reinforced_composite

## Production Speed Bonus

Elevated machines have their **ticks per cycle reduced** — they produce faster. The bonus applies per level:

| Level | Ticks Multiplier | Effect on 25-tick recipe | Power Multiplier |
|---|---|---|---|
| 0 (ground) | 1.0× | 25 ticks | 1.0× |
| 1 | 0.85× | ~21 ticks | 1.5× |
| 2 | 0.70× | ~18 ticks | 2.25× |
| 3 | 0.55× | ~14 ticks | 3.375× |
| 4 | 0.40× | 10 ticks | 5.0× |

The power multiplier scales faster than the speed bonus — each additional level is less efficient per watt than the last. Level 1 is a good deal (15% faster for 50% more power). Level 4 is dramatic (2.5× faster for 5× power) and only makes sense for bottleneck machines where throughput matters more than efficiency.

**What this means for specific buildings**:
- **Particle Collider** (25-tick, 60W): At level 4 → 10-tick cycle, 300W draw. 2.5× throughput for the most expensive recipe in the game — worth it if you have the power.
- **Assembler** (10-tick, 15W): At level 4 → 4-tick cycle, 75W. Diminishing returns — assemblers are rarely the bottleneck.
- **Gathering Post** (passive): No meaningful benefit from elevation — the speed bonus applies to active production cycles, not passive resource generation.

### Reactor Interaction

An elevated reactor has **shorter phase durations** (the phase timer ticks faster), not more steam per tick. This means:
- The temperature oscillation is faster — phases complete in fewer game ticks
- Total steam produced per nuclear cell is unchanged (same temperature range, same steam-per-degree)
- But the cell is consumed faster — more cells per unit time
- Net effect: higher instantaneous steam rate, higher fuel consumption, same steam-per-cell

At level 1 (0.85× ticks): phases complete in ~51 ticks instead of 60. The reactor burns through cells ~18% faster but produces steam at a ~18% higher instantaneous rate. Turbines need to be re-tuned (more turbines or different bearing tier) to handle the shifted steam profile.

This makes reactor elevation a trade-off: peak power increases, but fuel costs scale proportionally. It's useful for burst demand or when nuclear cells are abundant, not as a free efficiency gain.

## Vertical Logistics

### Items Going Down: Gravity Drop

Items can be **dropped** from any level to the level directly below, or all the way to ground. This is the simple, cheap direction:

- A **drop chute** building takes items from a conveyor on its level and drops them to the level below (or ground)
- Items arrive on the lower level at a designated pickup point adjacent to the chute's ground position
- Drop chutes are fast — no processing delay, just a transfer
- Multiple chutes can stack: level 3 → level 2 → level 1 → ground (or direct drop to ground)

This means raw materials processed at elevation can easily return to ground level for further logistics.

### Items Going Up: Rail Elevator

The **only** way to send items upward is via the rail network. This gives rail a mandatory logistics role:

- A **rail elevator** building connects a ground-level rail station to an elevated platform
- Items are loaded into rail cars at ground level, lifted to the target level, and unloaded
- Each elevator serves one pair of levels (ground ↔ level 1, ground ↔ level 2, etc.)
- Elevator throughput is limited — not all items should go up, only the ones that need elevated processing

This asymmetry is the core of vertical logistics design:
- **Raw materials** are gathered at ground level (gathering posts, mines)
- **Critical intermediates** are railed up to elevated machines for fast processing
- **Finished products** drop back down for distribution

Players must decide which production steps are worth elevating. Elevating the wrong thing wastes power and rail capacity on a non-bottleneck.

### Why This Asymmetry Matters

Without the asymmetry (if items could go up freely), elevation is just "pay more power for faster machines" — a simple scaling knob. The rail-up/drop-down constraint creates genuine logistics puzzles:

- Where do you place the elevator? It needs rail access and ground-level input.
- How do you batch items efficiently for the elevator trip?
- Which machines justify the rail capacity investment?
- Can you chain elevated production to avoid round-trips (up → process → process → drop)?

## Power Per Level

Each level has its **own independent power network**. Power does not flow between levels by default.

### Power Poles (Cross-Level Power Transfer)

A **power pole** is a tall structure that occupies a tile on two adjacent levels and transfers excess power from one level to the other. It works as a paired consumer/generator:

- On the **source level**: the power pole acts as a power consumer, drawing available excess power
- On the **destination level**: the power pole acts as a power generator, providing that power

Key properties:
- **Transfer direction is configurable** — the player sets which level is source and which is destination (or it auto-detects based on surplus/deficit)
- **Transfer has efficiency loss** (e.g. 90%) — some power is lost in transmission, discouraging long vertical chains
- **Each pole has a transfer capacity cap** (e.g. 100W per pole) — scaling requires multiple poles
- **Poles don't merge grids** — each level remains a separate power network. A pole is just a building that consumes on one level and generates on the other

This is simpler than grid-linking because:
- No complex multi-level network resolution
- Power flow is explicit and visible (you can see how much each pole transfers)
- Transfer losses create real cost for vertical power distribution
- Players can build dedicated "power floors" — a level with just generators and power poles exporting to production floors above/below

**Typical setups**:
- Reactors on ground level, power poles sending power up to elevated production
- Solar/shadow panels on the highest level (unobstructed), power poles sending power down
- Each production level has its own power budget determined by available poles

### Why Not Grid Linking?

Merging power networks across levels would mean:
- A single reactor could power everything on all levels — no spatial power planning
- No incentive to place generators strategically per level
- The power pole building becomes trivial (just a wire, not a meaningful structure)
- Debugging power issues becomes harder (where is the drain coming from?)

Separate networks with explicit transfer buildings make power distribution a visible, plannable system.

## Level Restrictions

### No Creatures on Upper Levels

Creatures (both hostile Hiss entities and beneficial Altered Entities) only exist at ground level:

- **Hiss corruption** cannot spread to elevated buildings — elevation is inherently safe from corruption
- **Creature boosts** (Altered Entity production bonuses) only apply to ground-level machines
- **Defense perimeters** only need to protect ground level

This creates a pull/push dynamic:
- **Push to elevate**: safety from Hiss, faster production
- **Pull to stay grounded**: creature boosts, cheaper infrastructure (no scaffolds), simpler logistics

A player might keep their most valuable machines elevated (safe from corruption) while keeping boosted machines at ground level (benefiting from Altered Entity bonuses). The optimal layout mixes levels.

### No Underground Conduits on Upper Levels

Underground conduits (cross-face item transport) can only be placed at ground level:

- Inter-face logistics must go through ground level
- Items produced at elevation must drop down before crossing to another face
- This prevents players from replicating the entire logistics network at every level

Upper levels are **production-focused**, not logistics-focused. The ground level remains the logistics backbone of the factory.

### No Scaffolds on Face Edges/Vertices

Scaffolds cannot be placed on tiles at face edges or vertices (where faces meet on the rhombic triacontahedron). This keeps the sphere geometry clean and avoids collision issues between elevated structures on adjacent faces meeting at angles.

## Visual & Rendering Considerations

### Level of Detail

Elevated buildings add significant visual complexity:
- Each scaffold level is a visible structure (metallic framework, supports, walkways)
- Elevated machines sit on platforms above the scaffolding
- Drop chutes and rail elevators have visible vertical shafts

**LOD implications**:
- Distant faces: collapse all levels into ground-level rendering (just show the highest building's icon)
- Medium distance: show scaffold columns as simple pillars, machines as simplified meshes
- Close up: full scaffold detail, platform surfaces, visible conveyor routing on each level

### Height from Surface

Buildings at each level need to render at increasing distances from the face surface:

| Level | Height Above Surface |
|---|---|
| 0 | Standard (current) |
| 1 | +1 building height |
| 2 | +2 building heights |
| 3 | +3 building heights |
| 4 | +4 building heights |

On the curved sphere surface, very tall structures at level 4 may become visible from adjacent faces, creating an interesting skyline effect.

### Camera Implications

The drone camera (current camera system) naturally handles vertical building — the player can fly up to inspect elevated platforms. Waypoints could store a target level in addition to position.

## Interaction with Other Systems

### Dark Reactor Beams (Tier 7)

Open question: do darkness beams travel on a specific level, or do they penetrate all levels? Options:
- **Level-specific beams**: each beam operates on one level. Dark reactors on different levels create separate beam networks. Simple but limits cross-level interaction.
- **Vertical beams**: beams could be directed upward/downward (in addition to cardinal directions) using special mirrors. Shadow panels on elevated platforms could be hit from below. Complex but interesting.

### Construction Sites

Elevated construction sites need scaffolding material delivered via rail elevator before the actual building materials. This adds a bootstrapping step to building at height.

### Deconstruction

Deconstructing a scaffold that has levels above it should cascade — either preventing deconstruction (error: "support structure in use") or triggering a controlled collapse that deconstructs everything above and drops items to ground level.

## Design Summary

| Aspect | Rule |
|---|---|
| Max levels | 4 (above ground) |
| Building elevation | Place scaffolds to push buildings up |
| Base scaffold | No overhang, mirrors ground footprint |
| Advanced scaffold | 1-tile overhang from nearest support |
| Scaffold cost | Exponential with height (1×, 2×, 4×, 8×) |
| Speed bonus | -15% ticks per level (0.85× at L1, 0.40× at L4) |
| Power penalty | 1.5× per level (1.5× at L1, 5× at L4) |
| Items down | Gravity drop (free, fast) |
| Items up | Rail elevator only (capacity-limited) |
| Power per level | Independent networks, power poles transfer between adjacent levels |
| Power pole | Consumer on source level, generator on destination level, ~90% efficiency, capacity-capped |
| Creatures | Ground level only |
| Underground conduits | Ground level only |
| Face edges/vertices | No scaffolds allowed |
| Reactor elevation | Faster phases, same steam/cell, more fuel consumed |

## Resolved Design Decisions

- **4 max levels**: enough for meaningful vertical hierarchy without excessive complexity
- **Exponential scaffold costs**: naturally limits height usage to high-priority buildings
- **Power poles as consumer/generator pairs**: simpler than grid linking, explicit transfer with visible throughput and efficiency loss
- **Rail-only upward transport**: gives rail a mandatory role, creates asymmetric logistics
- **No creatures at height**: safety incentive to elevate, boost incentive to stay grounded
- **No conduits at height**: ground level remains the logistics backbone
- **Reactor elevation = faster burn, not more output**: prevents free power scaling

## Open Questions

- Exact scaffold construction costs and recipes
- Advanced scaffold unlock tier
- Power pole transfer efficiency (90%? 85%?) and capacity cap (100W? 200W?)
- Rail elevator throughput limits
- Drop chute: instant transfer or small delay?
- Can the player build directly at a target level, or must they always scaffold up from ground?
- Scaffold 3D model design (industrial framework? FBC-themed supports?)
- How does the tile info panel display multi-level information?
- Does elevation affect building placement preview (showing scaffold requirements)?
- Can scaffolds be shared? (two adjacent elevated buildings sharing a scaffold column)
- Interaction with line-drawing tool: can you draw conveyors on elevated levels?
- Maximum buildings per level per tile: still 1, or can scaffolds enable denser packing?
