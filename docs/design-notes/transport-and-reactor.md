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

The reactor is a high-tier power source that consumes nuclear cells as fuel and requires active thermal management through alternating hot/cold phases. It does not produce electricity directly — it produces **steam**, which is fed into **steam turbines** that generate power.

### Steam Generation Model

The reactor has an internal temperature that determines steam output:

- **Operating Temperature** (e.g. 100): Steam production begins. Rate is proportional to temperature above this threshold.
- **Danger Temperature** (e.g. 200): Phase switches from heating to cooling (or vice versa).
- **Critical Temperature** (e.g. 300): Reactor enters shutdown mode.

**Steam output rate** = `(temperature - operating_temp) / 200` steam per tick (while temp > operating_temp).

During normal operation the temperature oscillates between Operating and Danger, averaging ~150. This yields an average of **0.25 steam/tick**.

### Steam Turbine

Steam turbines are separate buildings that consume steam and produce power:

| Parameter | Value |
|-----------|-------|
| Cycle time | 240 ticks |
| Steam per cycle | 20 |
| Power output | 80W (while processing) |
| Demand rate | 0.083 steam/tick |

**3 turbines per reactor** for nominal 240W total output:
- 3 × 0.083 = 0.25 steam/tick demand (matches reactor average supply)
- 3 × 80W = 240W

Steam turbines produce **water** as a byproduct, which can be recycled into the reactor's thermal regulator supply chain.

### Thermal Cycling Mechanic

The reactor alternates between two phases, each lasting **60 ticks** (2 phases per nuclear cell):

**Phase determination** (checked at phase boundary):
- If temperature < Danger Temperature → **Heating phase**
  - Consumes 1 thermal regulator. If available: temperature rises throughout phase.
  - If missing: temperature falls (reactor cools without regulation).
- If temperature ≥ Danger Temperature → **Cooling phase**
  - Consumes 1 coolant rod. If available: temperature drops throughout phase.
  - If missing: temperature rises (reactor overheats without cooling).

This creates sustained demand for both water and ice:
- The Freezer becomes critical permanent infrastructure (not one-time bootstrap)
- Tundra ice remains relevant as ongoing supply
- Players must solve a three-input logistics puzzle: nuclear cells + thermal regulators + coolant rods

**Consumable rates per cell** (120 ticks = 2 phases):
- 1 nuclear cell per 120 ticks
- 1 thermal regulator per heating phase (typically 1 per cell)
- 1 coolant rod per cooling phase (typically 1 per cell)

### Failure Cascade

Temperature thresholds create a graduated failure sequence:

1. **Miss a thermal item** → temperature drifts wrong direction, steam output becomes suboptimal
2. **Temperature reaches Critical** → **Shutdown mode**:
   - Reactor stops consuming nuclear cells
   - Continues cooling phase behavior (needs coolant rods to cool down)
   - If current cell exhausts during shutdown, no further heating occurs
   - Still needs coolant rods to bring temperature back down
3. **Temperature stays above Critical for 5 phase changes** → **Meltdown**:
   - Reactor is destroyed
   - Adjacent structures are destroyed
4. **Temperature reaches zero** → Normal operation may resume

This gives players a window to react: shutdown is recoverable if you feed coolant rods, but neglect leads to catastrophic loss.

### Nuclear Cell Parameters

| Parameter | Value |
|-----------|-------|
| Cell duration | 120 ticks |
| Phase length | 60 ticks (2 per cell) |
| Recipe | 25 enriched_uranium + 6 advanced_composite |
| Produced in | Particle Collider (25-tick cycle, 60W) |

### Why Nuclear Cells (Not Raw Uranium)

The reactor takes **nuclear cells** as fuel (already an expensive crafted item: 25 enriched_uranium + 6 advanced_composite per cell). This means:

- The full uranium processing chain must be operational before the reactor works
- The reactor is a true endgame building, not accessible early
- Nuclear cells burn for a long duration, making the thermal management the real ongoing challenge

### Power System Context

Power is capacity-based. This makes the reactor's enormous production chain worthwhile — it powers an entire high-tier factory cluster that would otherwise need 12 bio generators on stable fuel.

**Comparison to bio generators:**
- 12 bio generators × 20W = 240W (equivalent to 1 reactor + 3 turbines)
- Bio generators need continuous fuel supply (stable fuel = complex chain)
- Reactor needs nuclear cells + thermal items but at much lower item throughput
- Reactor is higher risk (meltdown) but lower logistics overhead once running

### Thermal Management Items

Already implemented in fabrication plant recipes:

- **Coolant rod** (ice + plastic_sheet + coolant_cube) — consumed during cooling phase
- **Thermal regulator** (water + plastic_sheet + heat_sink) — consumed during heating phase

### Energy Budget (from `mix fuel_efficiency` analysis)

Run `mix fuel_efficiency` for full numbers. Key reactor metrics:

| Metric | Reactor + 3 Turbines | 12 Bio Gens (Stable Fuel) |
|--------|---------------------|--------------------------|
| Gross output | 28,800 Wt per cell | 28,800 Wt per 120 ticks |
| Production cost | 45,779.5 Wt | 3,256.1 Wt |
| Net energy | **-16,979.5 Wt** | +25,543.9 Wt |
| ROI | **0.63x** | 8.85x |

**The reactor currently loses energy.** The nuclear cell alone costs 43,271 Wt to produce (25 enriched_uranium through the nuclear refinery + 6 advanced_composite through the particle collider), far exceeding the 28,800 Wt it generates. Bio generators on stable fuel are overwhelmingly more efficient.

**Possible rebalancing levers:**
- Increase nuclear cell burn duration (e.g. 120 → 600+ ticks) to amortize the massive production cost
- Reduce nuclear cell recipe inputs (fewer enriched_uranium or advanced_composite per cell)
- Increase turbine output (80W → higher) or add more turbines per reactor
- Reduce enriched_uranium cost (lower raw_uranium input or faster nuclear refinery rate)
- Accept the energy deficit and position the reactor as a **compact power source** whose value is density/logistics simplicity rather than raw efficiency

### Remaining Open Questions

- Construction cost and tier placement (likely Tier 6-7)
- 3D model design
- Multi-tile structure?
- Exact temperature values (Operating/Danger/Critical) and rate of change per tick
- Steam turbine construction cost and tier
- Whether water byproduct from turbines is 1:1 with steam input
