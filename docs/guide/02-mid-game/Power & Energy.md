# Power & Energy

At **Clearance 4**, you unlock the power system. Many advanced buildings require power to operate.

## Why Power Matters

> [!important] Unpowered buildings stall.
> Buildings without power stop producing entirely. Once you start building Clearance 4+ structures, power infrastructure is mandatory.

> [!note] Power switch vs. power network
> Every machine also has a manual **ON/OFF power switch** you can toggle from the tile info panel. This is separate from the power network — even a fully powered machine can be switched off by its operator. See [[Placing Your First Buildings#Power switch]].

## Bio Generator

The primary power source. Consumes fuel to generate power.

- Burns **Entity Biofuel** or **Refined Entity Fuel**
- Fuel is consumed every **5 ticks**
- Powers nearby buildings via [[#Substation|Substations]]

**Cost:** 3 Astral Frame, 3 Shielded Conductor, 2 Kinetic Driver

---

## Substation

Distributes power from generators to machines within its radius.

- **Radius:** 4 tiles
- Passive — no fuel or input needed
- Chain substations together to extend power coverage
- Generators must be within a substation's radius to contribute power

> [!tip] Power Grid Layout
> Place substations in a grid pattern with overlapping coverage. A single Bio Generator powers all machines within its connected substation network.

**Cost:** 10 Paraelectric Bar, 6 Structural Plate, 5 Shielded Conductor

---

## Shadow Panel

An alternative power source that generates power from darkness.

- Produces power when its cell is in **shadow** (sun on the far side of the sphere)
- Uses per-cell illumination for precise shadow boundaries
- **Disabled** if a powered Lamp is within radius 3
- No fuel required — completely passive

Shadow Panels are useful on the dark side of the sphere where solar cycles provide long shadow periods. They complement Bio Generators for round-the-clock power.

**Cost:** 3 Refined Resonance Crystal, 2 Astral Frame, 2 Conductive Filament

---

**Previous:** [[Advanced Logistics]] | **Next:** [[The Hiss & Corruption]]
