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

**Steam output rate** = `(temperature - operating_temp) / 100` steam per tick (while temp > operating_temp).

During normal operation the temperature oscillates between Operating and Danger, averaging ~150. This yields an average of **0.5 steam/tick**.

### Steam Turbine — Variable-Speed Model

Steam turbines are separate buildings that convert steam into power via a **variable-speed rotor** with bell curve efficiency.

#### Physics Model

Each turbine has a **speed** (RPM) that changes each tick:
- Steam **accelerates** the rotor: `speed += steam_per_tick * accel`
- Friction **decelerates** it: `speed *= (1 - friction)`
- **Terminal speed** (steady state): `steam_per_tick * accel * (1 - friction) / friction`

Power output depends on how close the rotor speed is to the **peak efficiency speed**:

```
efficiency(speed) = max_eff * exp(-(speed - peak)^2 / (2 * sigma^2))
power = efficiency(speed) * steam_per_tick
```

This is a Gaussian bell curve — the turbine has an optimal speed where it extracts maximum energy from steam. Too slow (underspeed) or too fast (overspeed) both reduce efficiency.

#### Base Parameters

| Parameter | Value |
|-----------|-------|
| Peak speed | 1.5 |
| Base max_eff | 480 W/steam |
| Base sigma | 0.4 |
| Accel | 1.0 |
| Base friction | 0.10 |

**3 turbines per reactor** at base:
- Steam per turbine: 0.5 / 3 = 0.167 steam/tick
- Terminal speed: 0.167 * 0.9 / 0.1 = 1.5 (= peak)
- Power per turbine: 480 * 0.167 = 80W
- **Total: 3 × 80W = 240W**

#### Why the Bell Curve Matters

Splitting steam across fewer or more turbines shifts each turbine's speed away from peak:
- **2 turbines**: each gets 0.25 steam → speed 2.25 (overspeed) → 17% eff → 41W total
- **3 turbines**: each gets 0.167 steam → speed 1.5 (peak) → 100% eff → **240W total**
- **4 turbines**: each gets 0.125 steam → speed 1.13 (underspeed) → 64% eff → 155W total

This makes the optimal turbine count a real design decision, not just "add more."

#### Bearing Upgrades

Bearings are per-turbine upgrades that affect **two parameters**:
1. **max_eff** increases — less friction means less energy wasted as heat
2. **sigma** widens — the turbine tolerates speed deviation better

Critically, bearings also reduce friction, which increases terminal speed for the same steam input. With better bearings, existing turbines **overspeed past peak** — the player must add more turbines to bring each one back to optimal speed.

| Bearing Tier | Friction | Max Eff | Sigma | Opt Turbines | Total W | vs Base |
|---|---|---|---|---|---|---|
| No bearings (base) | 0.10 | 480 | 0.40 | **3** | **240W** | 100% |
| Bronze Bearings | 0.07 | 720 | 0.55 | **4** | **345W** | 144% |
| Steel Bearings | 0.05 | 960 | 0.75 | **6** | **477W** | 199% |
| Titanium Bearings | 0.03 | 1440 | 1.00 | **11** | **720W** | 300% |

The upgrade path requires BOTH better bearings AND more turbines. Upgrading bearings without adding turbines is catastrophic — bronze bearings on 3 turbines drops output from 240W to 155W (overspeed). Titanium on 3 turbines produces essentially nothing.

Steam turbines produce **water** as a byproduct, which can be recycled into the reactor's thermal regulator supply chain.

### Thermal Cycling Mechanic

The reactor alternates between phases, each lasting **60 ticks** (4 phases per nuclear cell):

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

**Consumable rates per cell** (240 ticks = 4 phases):
- 1 nuclear cell per 240 ticks
- 1 thermal regulator per heating phase (typically 2 per cell)
- 1 coolant rod per cooling phase (typically 2 per cell)

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
| Cell duration | 240 ticks |
| Phase length | 60 ticks (4 per cell) |
| Recipe | 25 enriched_uranium + 6 advanced_composite |
| Produced in | Particle Collider (25-tick cycle, 60W) |

### Why Nuclear Cells (Not Raw Uranium)

The reactor takes **nuclear cells** as fuel (already an expensive crafted item: 25 enriched_uranium + 6 advanced_composite per cell). This means:

- The full uranium processing chain must be operational before the reactor works
- The reactor is a true endgame building, not accessible early
- Nuclear cells burn for a long duration, making the thermal management the real ongoing challenge

### Power System Context

Power is capacity-based. The reactor's progression tells a clear story:

- **Base (3 turbines, 240W)**: Matches 12 bio generators in half the footprint. Barely positive ROI — the investment is in density, not efficiency.
- **Bronze-Steel (4-6 turbines, 345-477W)**: Reactor surpasses what bio generators can deliver. Worth the production chain investment.
- **Titanium (11 turbines, 720W)**: Endgame powerhouse. 3x the output of a full bio generator array. Powers an entire high-tier factory cluster from a single fuel source.

**Comparison to bio generators:**
- 12 bio generators × 20W = 240W (equivalent to 1 base reactor + 3 turbines)
- Bio generators: far better ROI (17.69x vs 1.19x) but cap out at 240W without building more
- Reactor: lower ROI but scales to 720W with bearing upgrades — 3x more power from the same building count
- Reactor is higher risk (meltdown) but lower logistics overhead once running

### Thermal Management Items

Already implemented in fabrication plant recipes:

- **Coolant rod** (ice + plastic_sheet + coolant_cube) — consumed during cooling phase
- **Thermal regulator** (water + plastic_sheet + heat_sink) — consumed during heating phase

### Energy Budget (from `mix fuel_efficiency` analysis)

Run `mix fuel_efficiency` for full numbers. Key reactor metrics at base (3 turbines, no bearings):

| Metric | Reactor + 3 Turbines | 12 Bio Gens (Stable Fuel) |
|--------|---------------------|--------------------------|
| Cell duration | 240 ticks | — |
| Gross output | 57,600 Wt per cell | 57,600 Wt per 240 ticks |
| Nuclear cell cost | 43,271 Wt | — |
| Thermal cost | 5,017 Wt (4 phases) | — |
| Total cost | 48,288 Wt | 3,256 Wt (per 120t, prorated) |
| ROI | **1.19x** | 17.69x |

The base reactor just barely breaks even at 1.19x ROI. Bio generators have far better energy ROI, but the reactor's value is **power density** — 240W from 4 buildings (1 reactor + 3 turbines) vs 240W from 12 bio generators.

#### Bearing Upgrade Progression

With bearing upgrades and additional turbines, the reactor scales dramatically:

| Setup | Buildings | Total W | ROI | vs 12 Bio Gens |
|-------|-----------|---------|-----|----------------|
| Base (3 turbines) | 4 | 240W | 1.19x | 1x (equal power) |
| Bronze (4 turbines) | 5 | 345W | 1.71x | 1.4x more power |
| Steel (6 turbines) | 7 | 477W | 2.37x | 2x more power |
| Titanium (11 turbines) | 12 | 720W | 3.58x | 3x more power |

At titanium bearings, a single reactor with 11 turbines produces **720W** — triple the output of 12 bio generators, from the same building count. The reactor transitions from a compact break-even power source to the dominant endgame power plant.

### Remaining Open Questions

- Construction cost and tier placement (likely Tier 6-7)
- 3D model design
- Multi-tile structure?
- Exact temperature values (Operating/Danger/Critical) and rate of change per tick
- Steam turbine construction cost and tier
- Whether water byproduct from turbines is 1:1 with steam input
- Bearing construction costs per tier (must justify the power gain)
- Whether bearings are per-turbine upgrades or a shared reactor upgrade
- Steam distribution mechanic: does the reactor split steam evenly, or do turbines pull individually?
