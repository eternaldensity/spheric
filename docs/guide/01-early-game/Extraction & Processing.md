# Extraction & Processing

The extraction-and-processing loop is the foundation of everything you build.

## The Extractor (Miner)

- Can **only** be placed on tiles with resource deposits
- Extracts 1 raw ore per cycle (every **10 ticks**)
- Pushes ore in its facing direction
- Stops producing when the deposit is depleted (100–500 units per tile)

> [!tip] Deposit Scouting
> Resources appear in **ore veins** — clusters of the same type radiating from a central point. When you find a resource tile, explore the surrounding area to find the full vein. Place Extractors on the densest part of the cluster to minimize [[The Conduit Network|Conduit]] length.

## The Processor (Smelter)

- Accepts raw ore from an adjacent [[The Conduit Network|Conduit]]
- Processes one ore every **10 ticks**
- Outputs the corresponding ingot in its facing direction

### Processor Recipes (Clearance 0)

| Input | Output |
|---|---|
| Ferric Compound (Raw) | Ferric Standard |
| Paraelectric Ore (Raw) | Paraelectric Bar |

Additional recipes unlock as you progress:

| Input | Output | Available At |
|---|---|---|
| Astral Ore (Raw) | Astral Ingot | Clearance 2 |
| Resonance Crystal (Raw) | Refined Resonance Crystal | Clearance 2 |

For the complete recipe list, see [[Recipe Reference]].

## Building Your First Chain

```
[Ferric Compound Deposit] → [Extractor →] → [Conduit →] → [Processor →] → [Conduit →] → [Terminal]
```

The arrows show the facing direction of each building. Every building must face toward the next one in the chain.

> [!important] Orientation
> Press **R** to rotate before placing. A misaligned building won't connect to the chain and wastes resources.

## What Happens to Output

Ingots produced by the Processor are pushed downstream. They can go to:
- A **[[Submitting Research|Terminal]]** — to count toward research
- Another production building (like a [[The Fabricator|Fabricator]], unlocked later)
- A **[[Building Reference#Storage & Trade|Containment Vault]]** — to buffer surplus

---

**Previous:** [[The Conduit Network]] | **Next:** [[Submitting Research]]
