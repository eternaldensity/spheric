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

**Cost:** 3 Astral Frame, 2 Kinetic Driver, 3 Shielded Conduit

## Substation

Distributes power from a Generator to surrounding buildings.

- Power radius: **10 tiles**
- All buildings within range operate normally
- Buildings outside all Substation radii are **unpowered**

**Cost:** 5 Shielded Conduit, 10 Paraelectric Bar, 3 Structural Plate

## Shadow Panel

Alternative power generation unlocked at Clearance 3.

**Cost:** 2 Astral Frame, 3 Refined Resonance Crystal, 2 Conductive Filament

## Power Network Layout

```
[Bio Generator] → power → [Substation] → radius 10 → [all buildings in range]
```

For larger factories, chain multiple Substations:

```
[Generator] → [Substation A] ← [Transfer Station] → [Substation B] → [distant buildings]
```

The **Transfer Station** (Clearance 4) bridges distant Substations to extend your power network. See [[Advanced Logistics#Transfer Station]].

## Getting Biofuel

Biofuel comes from [[Creatures & Containment|creatures]]:

1. Capture creatures with a Gathering Post + Containment Trap
2. Use an **Essence Extractor** (Clearance 5) to extract essence from assigned creatures
3. Route **Entity Biofuel** or **Anomalous Essence** into your Refinery to produce **Refined Entity Fuel**

> [!tip] Fuel Planning
> A single Bio Generator consumes fuel continuously. Plan your creature capture pipeline early — you'll need a steady supply of biofuel for any serious mid-to-late-game production.

## Planning Your Grid

- Place Substations **centrally** within factory clusters
- One Substation per production area (radius 10 covers a lot)
- Ensure all production buildings, especially [[Advanced Production|advanced]] ones, are in range
- Generators need a fuel supply line — don't forget to route biofuel to them

---

**Previous:** [[Creatures & Containment]] | **Next:** [[Advanced Production]]
