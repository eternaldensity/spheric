# Design Notes: Tier 7 Dark Reactor

## Core Concept

The Dark Reactor is a Tier 7 endgame power source that consumes **spent nuclear cells** (reprocessed waste from Tier 6 reactors) and emits **beams of intense darkness** that supercharge shadow panels in their path.

Unlike the Tier 6 reactor's steam-and-turbines model, the Dark Reactor doesn't generate power directly. It amplifies existing shadow panel infrastructure — turning the day-night lighting system into a power generation mechanic.

## Fuel: Spent Nuclear Cells

Tier 6 reactors produce **spent nuclear cells** as waste. A reprocessing chain (new Tier 7 recipes) converts these into **dark fuel cells** — the Dark Reactor's consumable. This creates a direct dependency chain:

```
Tier 6 Reactor → spent nuclear cells → reprocessing → dark fuel cells → Tier 7 Dark Reactor
```

The Tier 7 reactor doesn't replace Tier 6 — it builds on top of it. Players need running Tier 6 reactors to fuel the Tier 7.

## Darkness Beams

The reactor emits **4 beams** of concentrated darkness (one per cardinal direction on the tile grid). Each beam travels in a straight line, hitting every shadow panel in its path.

### Beam Attenuation

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

### Per-Panel Bonus (Scaled by Intensity)

Each beam hitting a shadow panel applies a bonus **scaled by beam intensity at that point**:
- **Flat bonus**: `+10W × intensity`
- **Multiplier**: `1.0 + 0.5 × intensity` (i.e. up to ×1.5 at full intensity, ×1.0 at zero)

For multiple beams hitting the same panel, additions are summed first, then multipliers stack multiplicatively:

```
power = (base_power + sum(10 * intensity_i)) * product(1 + 0.5 * intensity_i)
```

Where `base_power` depends on ambient light (0W full light, 10W full dark).

### Beam Stacking Tables (at full intensity, i.e. close to reactor)

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

### Design Implications of Attenuation

The attenuation model creates several interesting optimisations:

1. **Panel density vs range trade-off**: Packing panels densely near the reactor maximises per-panel bonus but the beam dies fast. Spacing panels out extends range but wastes intensity on empty tiles.

2. **Mirror placement matters**: Mirrors should redirect beams early (near the reactor, while intensity is high) to send high-intensity beams toward convergence points. A mirror at the end of a long beam redirects a weak beam — less useful.

3. **Convergence near the reactor**: The best place to stack multiple beams is close to the reactor where all beams are near full intensity. But this competes for space with other reactor infrastructure.

4. **Crystalliser positioning**: Placing a crystalliser in the beam costs significant intensity (utilisation decay). Players must balance null crystal production against downstream power output. Crystallisers should go at the tail end of beams where intensity is already low.

A single beam per panel is modest — the real power comes from routing multiple high-intensity beams through the same panels. Getting 3-4 beams to converge on a panel requires **Shadow Mirrors** to redirect beams.

### Power Scaling Examples

A single Dark Reactor, 4 beams, panels every other tile (intensity ~0.90 per panel on avg), 8 panels per beam (32 total, no overlaps):
- Full light: ~32 × 13.5W avg = **~430W**
- Full dark: ~32 × 27W avg = **~864W**

With Shadow Mirrors routing 3 beams to converge on 6 panels near the reactor (avg intensity ~0.9), plus remaining single-hit panels further out (avg intensity ~0.6):
- 6 panels × 3 beams at 0.9: 6 × ~82W = 492W
- Plus ~12 single-hit panels at 0.6: 12 × ~9W = 108W
- **Total: ~600W in full light**

The optimisation puzzle is now multi-dimensional: panel placement, panel density, mirror positioning, crystalliser placement at beam tails, and convergence point selection. Panels are cheap but Shadow Mirrors are expensive — and both mirrors and panels consume beam intensity.

## Shadow Mirrors & Darkness Crystalliser

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

## What Differentiates It from Tier 6

| Aspect | Tier 6 (Nuclear) | Tier 7 (Dark Reactor) |
|--------|-------------------|----------------------|
| Fuel source | Nuclear cells (crafted) | Spent cells (Tier 6 waste) |
| Power mechanism | Steam → turbines (new buildings) | Darkness beams → shadow panels (existing buildings) |
| Scaling | Add turbines + bearings | Add/arrange shadow panels + mirrors in beam paths |
| Spatial challenge | Turbine count & layout | Beam routing & panel convergence |
| Day-night interaction | None | Works 24/7; stronger at night |
| Skill expression | Thermal timing, offset sync | Beam network topology |
| Risk | Meltdown (thermal) | TBD — beam containment? corruption? |

## Resolved Design Decisions

- **Beam attenuation**: Scaled model — intensity starts at 1.0, decays per tile. Bonus scales with intensity (not binary). Panel ordering and density are meaningful optimisations.
- **Three attenuation types**: empty tile (small decay), utilisation/panel/crystalliser (larger decay), mirror (slight amplification). Beam terminates at a minimum intensity threshold.
- **Crystalliser passes beam through**: doesn't block, but costs utilisation attenuation. Best placed at beam tails.
- **Mirrors amplify**: slight intensity boost (×1.05) on redirect, counteracting empty-tile decay. Prevents mirrors from being a net loss.
- **Mirrors degrade**: ongoing null crystal maintenance cost. Network size limited by null crystal production rate, creating a natural equilibrium between crystalliser investment and mirror network extent.
- **Beam stacking formula**: `power = (base + sum(10 * I_i)) * product(1 + 0.5 * I_i)` — multiplicative multiplier stacking, additive flat bonus, both scaled by intensity.

## Open Questions

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
- Interaction with vertical building: do beams travel on a specific level? Can they cross levels? See [vertical-building.md](vertical-building.md)
