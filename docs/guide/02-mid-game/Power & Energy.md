# Power & Energy

At **Clearance 4**, you unlock the power infrastructure buildings. But power matters from the very start — even basic Extractors and Processors draw power, and without a network they run at a heavily penalized speed.

## How Power Works

Power is **capacity-based**. Each generator produces a certain number of **watts** (W), and each building draws a certain number of watts. A power network's total generation must meet or exceed its total load — otherwise every building in the network slows down.

> [!important] Brownout
> When a network is **overloaded** (total draw exceeds total generation), all buildings in that network experience proportional slowdown. A network at 150% load makes everything roughly twice as slow. Build more generators to fix it.

> [!note] Disconnected buildings
> Buildings not connected to any power network at all suffer an even worse penalty — they slow down based on their clearance tier. Higher-tier buildings are penalised more heavily. Connect them to a substation network to avoid this.

### Zero-draw buildings

Not every building draws power. **Logistics buildings** (all conduits, splitters, mergers, balancers, crossovers, subsurface links), **storage** (vaults, submission terminals, trade terminals, gathering posts, drone bays), and **power infrastructure** (generators, substations, transfer stations) draw **0W** and are never affected by power shortages.

> [!note] Power switch vs. power network
> Every machine also has a manual **ON/OFF power switch** you can toggle from the tile info panel. This is separate from the power network — even a fully powered machine can be switched off by its operator. Switched-off buildings do not count toward network load.

---

## Power Draw by Building

| Draw | Buildings |
|------|-----------|
| 0W | All conduits, Submission Terminal, Gathering Post, all splitters/mergers/balancers, Crossover, Subsurface Link, Shadow Panel, Bio Generator, Substation, Transfer Station, Claim Beacon, Vault, Drone Bay, Trade Terminal |
| 1W | Lamp |
| 2W | Extractor, Processor, Assembler |
| 4W | Distiller |
| 6W | Containment Trap, Purification Beacon, Defense Turret |
| 8W | Advanced Processor, Insertion Arm, Extraction Arm |
| 12W | Recycler, Compound Mixer, Cryogenic Freezer, Advanced Assembler, Fabrication Plant, Essence Extractor |
| 20W | Particle Collider, Nuclear Refinery |
| 30W | Dimensional Stabilizer, Paranatural Synthesizer, Astral Projection Chamber |
| 50W | Board Interface |

---

## Bio Generator

The primary power source. Consumes fuel to generate power.

- **Output:** 20W
- Powers nearby buildings via [[#Substation|Substations]]
- Accepts five fuel types with different burn durations:

| Fuel | Duration (ticks) | Duration (seconds) | Source |
|---|---|---|---|
| Entity Biofuel | 50 | 10s | [[Creatures & Containment\|Gathering Post]] |
| Catalysed Ichor Fuel | 75 | 15s | [[Advanced Production#Compound Mixer\|Compound Mixer]] |
| Refined Entity Fuel | 100 | 20s | [[The Distiller]] |
| Unstable Mixed Fuel | 20 | 4s | [[Advanced Production#Compound Mixer\|Compound Mixer]] |
| Stable Mixed Fuel | 325 | 65s | [[Advanced Production#Compound Mixer\|Compound Mixer]] |

> [!tip] Fuel Efficiency
> **Stable Mixed Fuel** is the most efficient fuel by far (325 ticks / 65 seconds), but requires the Compound Mixer and a multi-step blending chain. Early on, stick with Entity Biofuel or Refined Entity Fuel from the Distiller.

**Cost:** 3 Astral Frame, 3 Shielded Conductor, 2 Kinetic Driver

---

## Substation

Distributes power from generators to machines within its radius.

- **Radius:** 4 tiles (Chebyshev distance)
- Passive — no fuel or input needed
- Chain substations together to extend power coverage
- Generators must be within **3 tiles** of a substation to feed into the network

> [!important] Power does not cross face boundaries.
> Substations and transfer stations only connect to buildings on the same face. Each face needs its own power infrastructure.

**Cost:** 10 Paraelectric Bar, 6 Structural Plate, 5 Shielded Conductor

---

## Transfer Station

Bridges long distances between substations without directly powering buildings.

- **Radius:** 8 tiles (connects to substations and other transfer stations)
- Does **not** power buildings directly — only extends the network to reach more substations
- Useful for connecting distant substation clusters without filling the gap with substations

**Cost:** 10 Shielded Conductor, 6 Resonance Circuit, 2 Astral Frame

---

## Shadow Panel

An alternative power source that generates power from darkness. Output scales with how dark the cell is.

- **Output:** 0–10W (scales with darkness)
- Full 10W in deep shadow (illumination below 15%)
- Ramps linearly from 10W down to 0W between 15% and 50% illumination
- 0W above 50% illumination
- Uses per-cell illumination for precise shadow boundaries
- **Disabled** if a powered Lamp is within radius 3
- No fuel required — completely passive

Shadow Panels are most effective on the dark side of the sphere where illumination is near zero. During twilight transitions they produce partial power, making the transition from day to night gradual rather than abrupt. They complement Bio Generators for round-the-clock power, but their variable output means you'll want extras to maintain reliable capacity through the dimmer periods.

**Cost:** 3 Refined Resonance Crystal, 2 Astral Frame, 2 Conductive Filament

---

## Planning Your Power Grid

### Early Game (Clearance 0-1)

Even before you unlock generators, your Extractors and Processors draw 2W each. Without power they run with a tier-based penalty. At Clearance 0 the penalty is mild, so you can get started without power, but efficiency drops quickly as you scale up.

### Mid Game (Clearance 2-4)

Once you unlock the Bio Generator and Substation at Clearance 4, build your first power network immediately. A single Bio Generator (20W) can power:

- 4 Extractors + 4 Processors + 2 Assemblers = 20W (exactly one generator)
- Add a Distiller (4W) and you'll need a second generator

### Late Game (Clearance 5+)

High-tier buildings draw significantly more power. A single Fabrication Plant draws 12W — over half a generator's output. A Particle Collider draws 20W — an entire generator by itself. Plan your power infrastructure to scale with your production.

> [!tip] Checking Power Status
> Click any building to see its power draw and network status in the tile info panel. You'll see the building's draw, total network load, and total network capacity. A **BROWNOUT** warning means you need more generators. A **DISCONNECTED** warning means the building isn't connected to any substation network.

---

**Previous:** [[Advanced Logistics]] | **Next:** [[The Hiss & Corruption]]
