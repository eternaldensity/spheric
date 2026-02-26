# Design Notes: Rail Transport & Nuclear Reactor

## Rail Transport Analysis

### Current Logistics Hierarchy

| Scale | Solution | Throughput | Range |
|-------|----------|-----------|-------|
| Local (tile-to-tile) | Conveyors Mk1-3 | 1.67 - 5 items/sec | Adjacent tile |
| Short (2 tiles) | Loader/Unloader arms | 5-50 items/sec | Manhattan dist ≤2 |
| Mid-range | Underground conduits | Limited by feeder belt | Adjacent faces only |
| Construction supply | Delivery drones | 2 items/trip | ~1 cell (~16 tiles) |
| Long-range bulk | ??? | — | — |

### Do We Need Mass Transit (Trains/Rails)?

**Conclusion: No — the economy doesn't generate enough long-distance bulk demand.**

The resource distribution is designed so that:

- **Tier 0-5**: Any face is self-sufficient. All 6 common resources (iron, copper, quartz, titanium, oil, sulfur) spawn in every biome.
- **Ice** (tundra-only): One-time bootstrap need of ~50-100 units. Once a Freezer has 1 coolant_cube, the recipe `20 water + 2 coolant_cube → 20 ice + 2 coolant_cube` is self-sustaining.
- **Uranium** (volcanic-only): The only true ongoing cross-face dependency, but throughput needs are modest — a nuclear production chain consumes items slowly (particle collider: 25 enriched per cell, 25-tick cycle). A single conduit pair handles this.

The scarcity is in **production rate**, not **distribution capacity**. A handful of underground conduit pairs chained across adjacent faces handles all cross-face needs. The real logistics challenge is local — getting ore from mines through smelters and assemblers across a single face.

### Where Trains Could Add Value (If Revisited)

Not as a logistics necessity, but as:

- **Multiplayer trade automation** — replacing manual trade terminal exchanges with automated routes between player bases
- **Spectacle and world-feel** — trains moving across the sphere surface make the world feel alive
- **Endgame infrastructure hobby** — a macro-scale project for players with running factories

### Unique Sphere Geometry Opportunities

If trains are ever added, the rhombic triacontahedron creates interesting design space:

- **Great circle routes**: Rails following geodesic paths across curved face surfaces
- **Face-edge junctions**: The 60 edges become natural interchange points
- **Vertex hubs**: 32 vertices (where 3 or 5 faces meet) are natural "Grand Central" locations
- **Orbital loops**: Equatorial/latitudinal trade rings connecting biome types

### FBC Lore Fit

Rail cars could be Altered Items — impossible vehicles traversing "thresholds" (face boundaries). The rail network as the "Astral Rail" or "Transit Conduit".

---

## Nuclear Reactor Design

### Core Concept

The reactor is a high-tier power source that consumes nuclear cells as fuel and requires active thermal management through alternating hot/cold phases.

### Thermal Cycling Mechanic

The reactor alternates between two phases:

- **Heating phase**: Reactor temperature rises. Needs items that require **water** (cooling) to prevent overheating.
- **Cooling phase**: Reactor temperature drops. Needs items that require **ice** to prevent overcooling.

This creates sustained demand for both water and ice, which means:

- The Freezer becomes critical permanent infrastructure (not one-time bootstrap)
- Tundra ice remains relevant as ongoing supply
- Players must solve a three-input logistics puzzle: nuclear cells + water-based items + ice-based items

### Why Nuclear Cells (Not Raw Uranium)

The reactor takes **nuclear cells** as fuel (already an expensive crafted item: 25 enriched_uranium + 6 advanced_composite per cell). This means:

- The full uranium processing chain must be operational before the reactor works
- The reactor is a true endgame building, not accessible early
- Nuclear cells burn for a long duration, making the thermal management the real ongoing challenge

### Power System Prerequisite

**The reactor only makes sense if power becomes quantitative (capacity-based).**

Currently power is binary — 1 generator powers unlimited buildings through chained substations. A reactor producing "more power" has no meaning in this system.

The plan: rework power so generators produce wattage, buildings draw wattage, and networks can be overloaded. Then:

- Bio generator: low wattage (e.g., 10W)
- Shadow panel: low wattage (e.g., 5W)
- Nuclear reactor: massive wattage (e.g., 100-200W)
- Buildings draw wattage scaled by tier

This makes the reactor's enormous production chain worthwhile — it powers an entire high-tier factory cluster that would otherwise need 10-20 bio generators.

### Intermediate Items (To Be Designed)

The water/ice thermal management items are TBD. Possibilities:

- **Coolant rods** (ice + copper_ingot?) — consumed during cooling phase
- **Thermal regulators** (water + heat_sink?) — consumed during heating phase
- Or: reactor directly accepts water and ice, alternating which slot it pulls from

### Open Questions

- Exact wattage output
- Thermal cycle duration (ticks per phase)
- What happens on overheat/overcool — reduced output? Shutdown? Meltdown (area damage)?
- Construction cost and tier placement (likely Tier 6-7)
- 3D model design
