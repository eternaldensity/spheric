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
| Titanium Bearings | 0.027 | 1440 | 1.00 | **12** | **720W** | 300% |

The upgrade path requires BOTH better bearings AND more turbines. Upgrading bearings without adding turbines is catastrophic — bronze bearings on 3 turbines drops output from 240W to 155W (overspeed). Titanium on 3 turbines produces essentially nothing.

Steam turbines produce **water** as a byproduct, which can be recycled into the reactor's thermal regulator supply chain.

#### Steam Distribution: Pressure Model

Steam is not transported as discrete items on conveyors. Instead, the reactor and its turbines share a **steam pressure header** — an internal fluid value, not a countable resource.

**Fixed-demand model**: Each turbine has a fixed steam demand per tick (the rate that produces peak rotor speed). The header pressure determines whether that demand can be met:

- If header pressure ≥ total demand from all turbines → fully fed, each turbine gets exactly its demand
- If header pressure < total demand → rationed proportionally (starved), turbines slow down
- Power = `eff(speed) × max_eff × steam_actually_received` — steam is the energy source, efficiency is conversion rate
- Surplus steam during hot phases fills the header buffer; deficit during cold phases drains it

**Demand per turbine** (tuned so full feed → peak speed):
```
demand = peak_speed × friction / (accel × (1 - friction))
```

| Bearing Tier | Friction | Demand/tick |
|---|---|---|
| No bearings | 0.10 | 0.167 |
| Bronze | 0.07 | 0.113 |
| Steel | 0.05 | 0.079 |
| Titanium | 0.027 | 0.042 |

At base with 3 turbines: total demand = 0.5/tick = exactly the reactor's average steam output. During hot phases (steam > 0.5), surplus builds in the header. During cold phases (steam < 0.5), the header drains. Without buffering, turbines starve ~39% of the time.

**Why fixed demand (not proportional draw)**: If turbines drew proportional to pressure, the power formula self-balances (high steam × low efficiency ≈ low steam × high efficiency) and buffering doesn't help. Fixed demand creates meaningful starvation during cold phases that players can mitigate through engineering.

#### Player Optimization: Steam Smoothing

The temperature oscillation creates an inherent efficiency loss (~64% of theoretical maximum at base tier). Players have three tools to reduce this, forming a skill/investment ladder:

**1. Pressure Tanks** (buildable buffer):
- Each pressure tank adds header capacity
- Stores hot-phase surplus for cold-phase use
- Diminishing returns: the first tank helps most, extra tanks provide less marginal benefit

**2. Phase-Offset Dual Reactors**:
- Two reactors feeding a shared header, started at different times
- Offset by half a cycle (60 ticks): when reactor A heats (high steam), reactor B cools (low steam)
- Combined output is nearly constant → turbines rarely starve
- This is a player discovery: the game doesn't tell you to do this, but the physics reward it

**3. Bearing Upgrades** (reduce demand per turbine):
- Better bearings → lower friction → lower demand per turbine for same peak speed
- Lower demand means easier to keep turbines fed even during cold phases
- Also increases max_eff and widens sigma → higher power ceiling

**Efficiency by setup** (simulated, base bearings, 3 turbines):

| Setup | Power | % of Theoretical | Starvation |
|---|---|---|---|
| Basic (cap=2, no extras) | 154W | 64% | 39% of ticks |
| Pressure tanks (cap=15) | 223W | 93% | 11% of ticks |
| Dual reactor + offset (cap=15) | 234W | 98% | ~0% |
| Theoretical continuous | 240W | 100% | 0% |

**Full bearing progression** (pressure-optimal turbine counts):

| Tier | Opt Turbines | Basic | +Tanks | +Dual Offset | Continuous |
|---|---|---|---|---|---|
| No bearings | 3 | 154W (64%) | 223W (93%) | 234W (98%) | 240W |
| Bronze | 5 | 249W (73%) | 325W (95%) | 332W (97%) | 342W |
| Steel | 7 | 346W (73%) | 448W (95%) | 457W (97%) | 474W |
| Titanium | 13 | 529W (73%) | 678W (94%) | 689W (96%) | 720W |

The design intent: a basic reactor "just works" at ~64-73% efficiency. Players who invest in pressure tanks reach ~93-95%. Those who figure out phase-offset dual reactors approach the theoretical maximum. None of these require the game to explain the optimization — the pressure gauge and starvation indicators naturally guide discovery.

#### Header Capacity

The header has a base capacity (built into the reactor, e.g. 2.0) plus any connected pressure tanks. Key capacity thresholds (base, 3 turbines):

| Capacity | Power | Starvation | Notes |
|---|---|---|---|
| 2 | 154W | 39% | Reactor only — minimal buffer |
| 5 | 170W | 31% | Small tank |
| 10 | 194W | 22% | Medium tank |
| 15 | 223W | 11% | Large tank — sweet spot |
| 20+ | 225W | 6% | Diminishing returns |

The player's interaction with steam is indirect — they see the reactor's temperature gauge, the header's pressure gauge, the turbines' speed indicators, and the power output. The "plumbing" is implicit in how buildings are connected (adjacency or pipe connections).

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

Power is capacity-based. The reactor's output depends on how well the player manages steam pressure:

- **Base (3 turbines, 154-234W)**: At minimum setup (154W), slightly below 12 bio generators. With pressure tanks and optimization, approaches 234W — comparable to bio gens in less space. The investment is in density and engineering skill.
- **Bronze-Steel (5-7 turbines, 249-457W)**: Reactor surpasses bio generators even at basic setup. Pressure optimization pushes output significantly higher.
- **Titanium (13 turbines, 529-689W)**: Endgame powerhouse. Even at basic efficiency, far exceeds bio generators. Fully optimized approaches 3x bio gen output.

**Comparison to bio generators:**
- 12 bio generators × 20W = 240W
- Base reactor (basic): 154W from 4 buildings — worse output but room to improve
- Base reactor (optimized): 234W from 4 buildings + tanks — comparable in less space
- Bio generators: far better ROI but no skill ceiling; reactor rewards engineering
- Reactor is higher risk (meltdown) but higher reward with investment in smoothing

### Thermal Management Items

Already implemented in fabrication plant recipes:

- **Coolant rod** (ice + plastic_sheet + coolant_cube) — consumed during cooling phase
- **Thermal regulator** (water + plastic_sheet + heat_sink) — consumed during heating phase

### Energy Budget (from `mix fuel_efficiency` analysis)

Run `mix fuel_efficiency` for full numbers. Key reactor metrics at base (3 turbines, no bearings):

| Metric | Basic (cap=2) | +Tanks (cap=15) | 12 Bio Gens |
|--------|---------------|-----------------|-------------|
| Cell duration | 240 ticks | 240 ticks | — |
| Avg power | 154W | 223W | 240W |
| Gross output/cell | 36,960 Wt | 53,520 Wt | 57,600 Wt |
| Nuclear cell cost | 43,271 Wt | 43,271 Wt | — |
| Thermal cost | 5,017 Wt | 5,017 Wt | — |
| Total cost | 48,288 Wt | 48,288 Wt | 3,256 Wt |
| ROI | **0.77x** | **1.11x** | 17.69x |

The basic reactor setup actually loses energy (0.77x ROI) — the temperature oscillation starves turbines too often. Adding pressure tanks pushes it above break-even (1.11x). This creates a clear upgrade path: the reactor isn't "free power" out of the box; it requires engineering investment to become profitable.

**The value proposition**: Bio generators have far better ROI but require 12 buildings for 240W. The reactor with tanks produces comparable power from fewer buildings. At higher bearing tiers, the reactor far exceeds what bio generators can deliver.

#### Bearing Upgrade Progression

With bearing upgrades and additional turbines, the reactor scales dramatically. Numbers shown for three player skill levels:

| Setup | Buildings | Basic W | +Tanks W | +Dual Offset W |
|-------|-----------|---------|----------|----------------|
| Base (3 turbines) | 4 (+tanks) | 154W | 223W | 234W |
| Bronze (5 turbines) | 6 (+tanks) | 249W | 325W | 332W |
| Steel (7 turbines) | 8 (+tanks) | 346W | 448W | 457W |
| Titanium (13 turbines) | 14 (+tanks) | 529W | 678W | 689W |

At titanium bearings with full optimization, a single reactor with 13 turbines produces **689W** — nearly triple the output of 12 bio generators. Even at basic setup (529W), it far exceeds bio generator capacity. The reactor transitions from a compact power source that rewards engineering skill to the dominant endgame power plant.

#### Reinforced Casing: Asymmetric Heating Upgrade

A **Reinforced Casing** upgrade raises the reactor's Critical Temperature from 300 to ~350, unlocking a higher-output operating mode.

**The 2H-2C cycle**: Instead of alternating heat-cool-heat-cool, the player schedules two consecutive heating phases followed by two cooling phases:

```
Standard:  H-C-H-C  → 100 → 200 → 100 → 200 → 100   (peaks at 200)
2H-2C:    H-H-C-C  → 100 → 200 → 300 → 200 → 100   (peaks at 300)
```

This doubles the average steam output (1.0/tick vs 0.5/tick) at the **same consumable cost** — still 2 regulators + 2 coolant per 240-tick nuclear cell. The player gets twice the steam for free by simply reordering their thermal management schedule.

The catch: the reactor peaks at exactly 300 (Critical). Without Reinforced Casing, this triggers shutdown. With it, the player has a safe margin but is operating much closer to the edge — a missed coolant rod is catastrophic instead of merely suboptimal.

**Turbine scaling for 2H-2C** (base bearings, cap=15):

| Turbines | Power | Starved | Notes |
|---|---|---|---|
| 3 | 228W | 0% | Same as standard — steam surplus vented |
| 5 | 335W | 8% | Good intermediate |
| 6 | 357W | 15% | Diminishing returns begin |
| 8 | 370W | 28% | Optimal — 62% more than standard |
| 10 | 350W | 38% | Overshoot — too many turbines |

**Cost/benefit comparison** (cap=15, optimal turbine counts):

| Setup | Turbines | Power | Consumables/cell | ROI |
|---|---|---|---|---|
| Standard + tanks | 3 | 223W | 2 reg + 2 cool | 1.11x |
| 2H-2C + tanks | 8 | 370W | 2 reg + 2 cool | 1.84x |

The upgrade path:
1. Build Reinforced Casing (raises Critical to ~350)
2. Add 5 more turbines (total 8)
3. Switch reactor scheduling to 2H-2C
4. Result: 62% more power, same fuel cost, higher meltdown risk

This creates an interesting player decision: the Reinforced Casing is a significant investment, and the player must also build 5 additional turbines and manage the tighter safety margin. But the payoff — nearly doubling power from the same fuel — is substantial.

**Combining with other optimizations**: 2H-2C stacks with bearing upgrades and dual-reactor offset. The full progression at base bearings:

| Stage | Buildings | Power | Per-Reactor | ROI |
|---|---|---|---|---|
| Bare minimum (1R 3T cap=2) | 5 | 154W | 154W | 0.77x |
| + Pressure tank (1R 3T cap=15) | 5 | 230W | 230W | 1.15x |
| + Dual offset (2R 6T cap=15) | 9 | 455W | 227W | 1.13x |
| + Reinforced Casing (1R 8T cap=15) | 10 | 370W | 370W | 1.84x |
| + Dual 2H-2C offset (2R 12T cap=15) | 15 | 866W | 433W | 2.15x |

**Dual 2H-2C with offset 120**: The 2H-2C cycle is 240 ticks (H-H-C-C at 60 ticks each). Two 2H-2C reactors offset by 120 ticks (half-cycle) complement each other perfectly — when reactor A is in its heating phases, B is cooling, and vice versa. This produces **866W from 12 turbines** at base bearings with only 12% starvation and 0% vented steam. Remarkably, this configuration **doesn't need pressure tanks** — the offset itself provides all the smoothing (cap=2 through cap=50 give identical results).

**Bearing tier scaling with 2H-2C**: The hotter cycle multiplies bearing gains:

| Tier | Standard Optimal | 2H-2C Optimal | Gain |
|---|---|---|---|
| No bearings | 3T → 230W | 8T → 370W | +60% |
| Bronze | 5T → 329W | 13T → 584W | +77% |
| Steel | 7T → 457W | 19T → 823W | +80% |
| Titanium | 13T → 696W | 30T → 1210W | +74% |

At titanium + 2H-2C, a single reactor with 30 turbines produces **1210W** — a genuine endgame powerhouse.

**Patterns that don't work well**:
- **Triple reactor (1/3-cycle offset)**: 224W/reactor — worse per-reactor than dual offset (227W). The 1/3 offset doesn't smooth well.
- **Short-phase cycling (30t, 15t)**: Less steam (narrower temp range) AND more consumables (more phases per cell). A trap.
- **Mixed-mode (1 standard + 1 2H-2C)**: Awkward — different steam rates make turbine tuning difficult, and the offset timing is suboptimal for both cycles.

### Resolved Design Decisions

- **Steam transfer model**: Fixed-demand pressure header (not discrete items). See simulation: `scripts/steam_pressure.exs`
- **Temperature values**: Operating=100, Danger=200, temp_rate=1.667/tick (100→200 in 60 ticks)
- **Steam header capacity**: Base reactor has 2.0 capacity; Pressure Tank building adds capacity
- **Turbine demand**: Fixed per-tick demand tuned to peak speed. `demand = peak × friction / (accel × (1-friction))`
- **Power formula**: `power = eff(speed) × max_eff × steam_actually_received_this_tick`
- **Optimal turbine counts**: Base=3, Bronze=5, Steel=7, Titanium=13 (under pressure model)
- **Bearings are per-turbine upgrades** (each turbine has its own friction, max_eff, sigma)
- **Asymmetric heating (2H-2C)**: Viable upgrade path via Reinforced Casing. Doubles steam at same fuel cost, peaks at 300. See simulation: `scripts/steam_asymmetric.exs`
- **Dual 2H-2C offset**: 120-tick offset (half of 240-tick 2H-2C cycle) is optimal. Produces 866W from 12T base bearings, no tanks needed. See: `scripts/steam_patterns.exs`
- **Bearing + 2H-2C scaling**: Confirmed — 2H-2C multiplies bearing gains by ~60-80%. Titanium 2H-2C = 1210W from 30T.
- **Triple reactor**: Not worth it — worse per-reactor efficiency than dual offset. Two reactors is the sweet spot.
- **Short phases / temperature setpoints**: Not viable as player optimizations under current consumable-per-phase design.

### Resolved Design Decisions (Continued)

- **Tier placement**: Reactor is **Tier 6**. A 2nd-stage reactor (breeder? fusion?) at Tier 7.
- **Not a multi-tile structure**: The nuclear cell processing chain (enrichment → collider → cell) plus multiple turbines already creates enough spatial complexity. Multi-tile would add friction without adding interesting decisions.
- **Water byproduct is negligible**: Each coolant rod / thermal regulator consumes 1 water/ice per cycle. With 2 of each per 240-tick cell, that's 4 water consumed total. Split across turbines, the per-turbine water output per cycle is a tiny fraction — not worth building a recycling loop around.
- **Water-steam recycling requires separate water input**: For a meaningful water→steam→water loop, the reactor would need a dedicated water input beyond what thermal items consume. This is a future design question — the current model doesn't produce enough water byproduct to sustain recycling.
- **Dual reactor offset is player-controlled**: Players must start the second reactor at the right time to achieve the offset. The game doesn't auto-synchronize reactors. This is part of the engineering skill ceiling.
- **2H-2C scheduling mechanism**: The player controls phase scheduling by **restricting the inflow of heating/cooling consumables**. To achieve 2H-2C, the player withholds coolant rods during heating phases and withholds thermal regulators during cooling phases — the reactor's phase logic naturally extends the current phase when the next consumable is missing. This could be done via filtered input (only allow the correct item during the correct phase) or a simple toggle/mode switch on the reactor.
- **Pressure tanks are a mid-game optimization**: At endgame with dual 2H-2C offset, pressure tanks become obsolete — the offset provides all necessary smoothing. This is acceptable. Tanks serve as the "first optimization" players discover, then get replaced by more sophisticated engineering (more turbines + offset timing). The progression is: basic → +tanks → +more turbines → +offset → tanks no longer needed.

### Remaining Open Questions

- Construction costs: reactor, turbines, pressure tanks, reinforced casing, bearings per tier
- 3D model designs for reactor, turbines, pressure tanks
- How turbines connect to the reactor (adjacency? pipe building? implicit within radius?)
- UI: how to display header pressure, turbine speed, starvation indicators
- Reinforced Casing: exact Critical Temperature value (350? 400?)
- 2H-2C scheduling UI: does the player use item filters on input slots, or a dedicated reactor mode toggle?
- 2H-2C at titanium bearings needs 30 turbines — space/layout constraints on a single face?
- Tier 7 reactor design — see below

---

## Tier 7: Dark Reactor (Concept)

### Core Concept

The Dark Reactor is a Tier 7 endgame power source that consumes **spent nuclear cells** (reprocessed waste from Tier 6 reactors) and emits **beams of intense darkness** that supercharge shadow panels in their path.

Unlike the Tier 6 reactor's steam-and-turbines model, the Dark Reactor doesn't generate power directly. It amplifies existing shadow panel infrastructure — turning the day-night lighting system into a power generation mechanic.

### Fuel: Spent Nuclear Cells

Tier 6 reactors produce **spent nuclear cells** as waste. A reprocessing chain (new Tier 7 recipes) converts these into **dark fuel cells** — the Dark Reactor's consumable. This creates a direct dependency chain:

```
Tier 6 Reactor → spent nuclear cells → reprocessing → dark fuel cells → Tier 7 Dark Reactor
```

The Tier 7 reactor doesn't replace Tier 6 — it builds on top of it. Players need running Tier 6 reactors to fuel the Tier 7.

### Darkness Beams

The reactor emits **4 beams** of concentrated darkness (one per cardinal direction on the tile grid). Each beam travels in a straight line, hitting every shadow panel in its path.

#### Beam Attenuation

Beams have an **intensity** that starts at 1.0 at the reactor and decays as the beam travels. Intensity determines how much bonus a shadow panel receives — panels closer to the reactor get more power than distant ones.

Three interaction types with different attenuation effects:
- **Empty tile**: small decay (e.g. ×0.95 per tile — loses 5%)
- **Utilisation** (shadow panel or crystalliser tapped): larger decay (e.g. ×0.80 per interaction — loses 20%)
- **Shadow Mirror**: slight *amplification* (e.g. ×1.05 — gains 5%). Mirrors focus the beam, boosting intensity on the redirected path

The beam terminates when intensity drops below a threshold (e.g. 0.05). This creates a natural range limit that depends on what the beam passes through — a beam through empty space reaches much further than one passing through a dense array of panels.

**Range examples** (at 0.95 empty / 0.80 utilised / 1.05 mirror / 0.05 cutoff):

| Path | Approximate Range |
|------|-------------------|
| Empty space only | ~58 tiles |
| Shadow panel every tile | ~12 tiles |
| Panel every 3rd tile | ~25 tiles |
| Mirror every 3rd tile (empty between) | ~87 tiles |
| Mirror every tile | infinite (0.95 × 1.05 ≈ 1.0) |

Mirrors counteract empty-tile decay, extending effective beam range. Dense mirror chains approach lossless transmission — but mirrors degrade and need null crystal maintenance, so extending beams this way has an ongoing resource cost.

Sparse panel placement extends beam range at the cost of fewer total panels hit. Dense placement maximises panels hit but the beam dies quickly and far panels get very little bonus.

#### Per-Panel Bonus (Scaled by Intensity)

Each beam hitting a shadow panel applies a bonus **scaled by beam intensity at that point**:
- **Flat bonus**: `+10W × intensity`
- **Multiplier**: `1.0 + 0.5 × intensity` (i.e. up to ×1.5 at full intensity, ×1.0 at zero)

For multiple beams hitting the same panel, additions are summed first, then multipliers stack multiplicatively:

```
power = (base_power + sum(10 * intensity_i)) * product(1 + 0.5 * intensity_i)
```

Where `base_power` depends on ambient light (0W full light, 10W full dark).

#### Beam Stacking Tables (at full intensity, i.e. close to reactor)

**Full light** (base = 0W):

| Beams | Additive | Multiplier | Total |
|-------|----------|------------|-------|
| 1 | 10W | 1.5x | **15W** |
| 2 | 20W | 2.25x | **45W** |
| 3 | 30W | 3.375x | **101W** |
| 4 | 40W | 5.063x | **203W** |

**Full dark** (base = 10W):

| Beams | Additive | Multiplier | Total |
|-------|----------|------------|-------|
| 0 | 10W | 1.0x | **10W** |
| 1 | 20W | 1.5x | **30W** |
| 2 | 30W | 2.25x | **68W** |
| 3 | 40W | 3.375x | **135W** |
| 4 | 50W | 5.063x | **253W** |

At half intensity (distant panel or after passing through several panels), a single beam gives +5W and ×1.25 instead of +10W and ×1.5. The stacking tables above represent the best case — panels near the reactor or at the start of a mirror-redirected beam.

#### Design Implications of Attenuation

The attenuation model creates several interesting optimisations:

1. **Panel density vs range trade-off**: Packing panels densely near the reactor maximises per-panel bonus but the beam dies fast. Spacing panels out extends range but wastes intensity on empty tiles.

2. **Mirror placement matters**: Mirrors should redirect beams early (near the reactor, while intensity is high) to send high-intensity beams toward convergence points. A mirror at the end of a long beam redirects a weak beam — less useful.

3. **Convergence near the reactor**: The best place to stack multiple beams is close to the reactor where all beams are near full intensity. But this competes for space with other reactor infrastructure.

4. **Crystalliser positioning**: Placing a crystalliser in the beam costs significant intensity (utilisation decay). Players must balance null crystal production against downstream power output. Crystallisers should go at the tail end of beams where intensity is already low.

A single beam per panel is modest — the real power comes from routing multiple high-intensity beams through the same panels. Getting 3-4 beams to converge on a panel requires **Shadow Mirrors** to redirect beams.

#### Power Scaling Examples

A single Dark Reactor, 4 beams, panels every other tile (intensity ~0.90 per panel on avg), 8 panels per beam (32 total, no overlaps):
- Full light: ~32 × 13.5W avg = **~430W**
- Full dark: ~32 × 27W avg = **~864W**

With Shadow Mirrors routing 3 beams to converge on 6 panels near the reactor (avg intensity ~0.9), plus remaining single-hit panels further out (avg intensity ~0.6):
- 6 panels × 3 beams at 0.9: 6 × ~82W = 492W
- Plus ~12 single-hit panels at 0.6: 12 × ~9W = 108W
- **Total: ~600W in full light**

The optimisation puzzle is now multi-dimensional: panel placement, panel density, mirror positioning, crystalliser placement at beam tails, and convergence point selection. Panels are cheap but Shadow Mirrors are expensive — and both mirrors and panels consume beam intensity.

### Shadow Mirrors & Darkness Crystalliser

**Darkness Crystalliser**: A machine that sits in a darkness beam's path. While being hit by a beam, it converts **resonance crystals** into **null crystals**. The beam passes through the crystalliser and continues — it doesn't block the beam.

**Null Crystals** are crafted into **Shadow Mirrors** — buildings that redirect a darkness beam 90°. A mirror takes an incoming beam from one direction and outputs it in a perpendicular direction, allowing the player to:
- Route beams around obstacles
- Converge multiple beams onto the same row of shadow panels
- Create beam networks that maximize multi-hit coverage

Mirrors slightly **amplify** beam intensity (×1.05) when redirecting — they focus the darkness rather than dispersing it. This means a well-placed mirror network can extend beams far beyond their natural straight-line range.

**Mirror degradation**: Mirrors degrade over time while a beam passes through them, eventually breaking and needing replacement. This creates an ongoing **null crystal maintenance cost** proportional to the size of the beam network. The better the network, the more crystallisers needed to sustain it.

```
resonance_crystal → [Darkness Crystalliser, in beam] → null_crystal
null_crystal + ??? → [crafting] → shadow_mirror (new)
null_crystal → shadow_mirror repair (maintenance)
```

**The endgame resource loop**:
1. Crystallisers consume beam intensity to produce null crystals
2. Null crystals build and repair mirrors
3. Mirrors amplify beams but degrade, needing more null crystals
4. More mirrors = more maintenance = more crystallisers = more intensity sacrificed

The network's maximum size is naturally limited by null crystal throughput. Players must balance how much beam intensity they divert to crystallisers (reducing power output) versus how many mirrors they can sustain (increasing power output through better routing). There's an optimal equilibrium that depends on the specific layout.

The Darkness Crystalliser creates an interesting bootstrapping challenge: you need beams to make mirrors, but mirrors make beams more useful. The first reactor's raw straight-line beams are your starting point; as you accumulate null crystals, you progressively build a more sophisticated beam network.

### What Differentiates It from Tier 6

| Aspect | Tier 6 (Nuclear) | Tier 7 (Dark Reactor) |
|--------|-------------------|----------------------|
| Fuel source | Nuclear cells (crafted) | Spent cells (Tier 6 waste) |
| Power mechanism | Steam → turbines (new buildings) | Darkness beams → shadow panels (existing buildings) |
| Scaling | Add turbines + bearings | Add/arrange shadow panels + mirrors in beam paths |
| Spatial challenge | Turbine count & layout | Beam routing & panel convergence |
| Day-night interaction | None | Works 24/7; stronger at night |
| Skill expression | Thermal timing, offset sync | Beam network topology |
| Risk | Meltdown (thermal) | TBD — beam containment? corruption? |

### Resolved Design Decisions (Tier 7)

- **Beam attenuation**: Scaled model — intensity starts at 1.0, decays per tile. Bonus scales with intensity (not binary). Panel ordering and density are meaningful optimisations.
- **Three attenuation types**: empty tile (small decay), utilisation/panel/crystalliser (larger decay), mirror (slight amplification). Beam terminates at a minimum intensity threshold.
- **Crystalliser passes beam through**: doesn't block, but costs utilisation attenuation. Best placed at beam tails.
- **Mirrors amplify**: slight intensity boost (×1.05) on redirect, counteracting empty-tile decay. Prevents mirrors from being a net loss.
- **Mirrors degrade**: ongoing null crystal maintenance cost. Network size limited by null crystal production rate, creating a natural equilibrium between crystalliser investment and mirror network extent.
- **Beam stacking formula**: `power = (base + sum(10 * I_i)) * product(1 + 0.5 * I_i)` — multiplicative multiplier stacking, additive flat bonus, both scaled by intensity.

### Open Questions (Tier 7)

- Spent nuclear cell output: 1 per Tier 6 cell consumed? Separate waste output slot?
- Reprocessing recipe chain: what buildings/resources convert spent cells → dark fuel cells?
- Dark fuel cell burn duration (how many ticks per cell?)
- Attenuation tuning: exact values for empty-tile decay, utilisation decay, and cutoff threshold
- Does the beam create a visible darkness overlay on tiles it passes through?
- Does the beam affect other things in its path? (creature effects, hiss interaction, crop growth?)
- Shadow Mirror crafting recipe (null_crystal + what?)
- Mirror degradation rate: how many ticks before a mirror breaks? How many null crystals to repair?
- Can mirrors split beams, or only redirect? (splitting would multiply beam count but weaken each)
- Darkness Crystalliser: conversion rate (how many resonance → null per tick while in beam?)
- Construction cost for Dark Reactor, Crystalliser, Shadow Mirror
- Risk/failure mode: what happens if the dark reactor malfunctions? Permanent darkness zone? Hiss attraction?
- FBC lore tie-in: the "darkness" could be Astral Plane energy, making this an Altered Item-class building
