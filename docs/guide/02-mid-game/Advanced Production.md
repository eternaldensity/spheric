# Advanced Production

At Clearance 4–5, you unlock higher-tier production buildings that process more complex materials.

## Compound Mixer (Mixer)

*Unlocked at Clearance 5*

- **Dual-input** building that combines two different materials
- Processing time: **15 ticks**
- Produces fuel blends for [[Power & Energy|Bio Generators]] and the drone

| Input A | Input B | Output |
|---|---|---|
| Black Rock Ichor (Crude) | Astral Ingot | Catalysed Ichor Fuel |
| Catalysed Ichor Fuel ×8 | Refined Entity Fuel ×8 | Unstable Mixed Fuel ×16 |
| Unstable Mixed Fuel ×5 | Threshold Compound | Stable Mixed Fuel ×2 |

> [!note] Fuel Blending Chain
> The Mixer enables a multi-step fuel chain: crude oil + titanium → catalysed fuel → unstable fuel → stable fuel. **Stable Mixed Fuel** burns for **325 ticks** in a Bio Generator, over 6× longer than biofuel. However, the chain requires Distiller output (Refined Entity Fuel, Threshold Compound) alongside Mixer processing.

**Cost:** 15 Heavy Astral Frame, 8 Shielded Conductor, 2 Advanced Resonance Circuit

---

## Cryogenic Processor (Freezer)

*Unlocked at Clearance 5*

- **Dual-input, dual-output** building — the first machine that produces two different items per cycle
- Processing time: **20 ticks**
- Produces coolant cubes for future nuclear reactor recipes

| Input A | Input B | Output A | Output B |
|---|---|---|---|
| Crystalized Water ×5 | Liquefacted Stars ×3 | The Moyst ×5 | Shivering Ingot ×1 |
| The Moyst ×20 | Shivering Ingot ×2 | Crystalized Water ×20 | Shivering Ingot ×2 |

> [!note] Dual Output
> The Cryogenic Processor is unique — it outputs **two different item types** per cycle. The primary output drains first, then the secondary output. Both outputs use the same conduit exit point, so downstream routing may need a [[Advanced Logistics#Selective Distributor (Filtered Splitter)|Selective Distributor]] to separate them. The **Refreeze** recipe reverses the process, converting water back into ice while recycling coolant cubes.

**Cost:** 12 Heavy Astral Frame, 10 Thermal Regulator, 2 Advanced Resonance Circuit

---

## Matter Recycler (Recycler)

*Unlocked at Clearance 4*

- Accepts **any 10 items** (mixed types allowed) as input
- Processing time: **30 ticks** (slow, heavy machine)
- Outputs **1 random raw resource** weighted by the biome the recycler sits on

| Input | Output |
|---|---|
| Any Item ×10 | 1 random raw resource (biome-weighted) |

> [!tip] Biome Placement Matters
> The recycler's output is weighted by the biome it's built on. A recycler on a **Volcanic** biome favors Ferric Compound and Astral Ore, while one in a **Forest** biome favors Paraelectric Ore and Resonance Crystal. Place recyclers strategically to target the resources you need most. See [[Biomes & Resources]] for full biome distributions.

> [!note] Universal Input
> Unlike other production buildings, the Matter Recycler has no recipe constraints — it accepts *any* item from a conduit. This makes it ideal for consuming excess or unwanted items. Feed it junk and get raw resources back.

**Cost:** 8 Heavy Astral Frame, 4 Resonance Circuit, 3 Kinetic Driver

---

## Advanced Processor (Advanced Smelter)

*Unlocked at Clearance 4*

- **Faster** processing: 8 ticks vs [[Extraction & Processing|standard Processor's]] 10
- Handles all standard Processor recipes **plus** advanced materials:

| Input | Output |
|---|---|
| Threshold Radiant (Raw) | Enriched Radiant |
| 5 Whispering Powder | 2 Whispering Ingot |

Processes **Threshold Radiant** (uranium), a critical resource for [[High-Tech Manufacturing|late-game]] production, and refines **Whispering Powder** into ingots used for building upgrades.

**Cost:** 12 Heavy Astral Frame, 8 Thermal Regulator, 5 Resonance Circuit

---

## Advanced Fabricator (Advanced Assembler)

*Unlocked at Clearance 5*

- **Dual-input** assembler for advanced recipes
- Processing time: **12 ticks**
- Produces the heavy components needed for [[High-Tech Manufacturing|high-tech]] and [[Paranatural Synthesis|paranatural]] buildings

| Input A | Input B | Output |
|---|---|---|
| Astral Frame | Reinforced Plate | Heavy Astral Frame |
| Resonance Circuit | Shielded Conductor | Advanced Resonance Circuit |
| Stabilized Polymer | Threshold Compound | Polymer Membrane |
| 10 Ferric Standard | 10 Hiss Residue | 10 Whispering Powder |

**Cost:** 20 Heavy Astral Frame, 4 Kinetic Driver, 3 Advanced Resonance Circuit

---

## Fabrication Plant

*Unlocked at Clearance 5*

- **Triple-input** assembler — the most complex production building
- Processing time: **20 ticks**
- Produces mid-to-late-game components

| Input A | Input B | Input C | Output |
|---|---|---|---|
| Advanced Resonance Circuit | Advanced Resonance Circuit | Polymer Membrane | Computation Matrix |
| Heavy Astral Frame | Kinetic Driver | Thermal Regulator | Armored Drive Assembly |
| Reinforced Plate | Polymer Membrane | Astral Ingot | Structural Composite |

> [!note] Layout Planning
> The Fabrication Plant needs **three separate conduit lines**. Plan your routing carefully — consider using [[Advanced Logistics#Transit Interchange (Crossover)|Transit Interchanges]] or [[Advanced Logistics#Subsurface Link (Underground Conduit)|Subsurface Links]] to avoid crossing paths.

**Cost:** 30 Heavy Astral Frame, 15 Shielded Conductor, 9 Kinetic Driver, 5 Advanced Resonance Circuit

---

## Essence Extractor

*Unlocked at Clearance 5*

- Produces **Entity Essence** from an assigned captured creature
- The creature is **not consumed** — it stays assigned indefinitely
- Processing time: **30 ticks** (boosted by output-type creatures)
- Requires a creature captured with a [[The Hiss & Corruption#Defense Buildings|Containment Trap]]

Entity Essence is needed for several [[Paranatural Synthesis|paranatural]] recipes and late-game research.

**Cost:** 30 Astral Frame, 10 Refined Resonance Crystal, 5 Resonance Circuit

---

**Previous:** [[The Distiller]] | **Next:** [[High-Tech Manufacturing]]
