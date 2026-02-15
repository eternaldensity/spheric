# Mining & Smelting

The extraction-and-processing loop is the foundation of everything you build.

## The Miner (Extractor)

- Can **only** be placed on tiles with resource deposits
- Extracts 1 raw ore per cycle (every **10 ticks**)
- Pushes ore in its facing direction
- Stops producing when the deposit is depleted (100–500 units per tile)

> [!tip] Deposit Scouting
> Click tiles to check for resources before committing to a layout. Look for clusters of the same resource type to minimize [[The Conveyor Network|conveyor]] length.

## The Smelter (Processor)

- Accepts raw ore from an adjacent [[The Conveyor Network|conveyor]]
- Processes one ore every **10 ticks**
- Outputs the corresponding ingot in its facing direction

### Smelter Recipes (Clearance 0)

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
[Iron Deposit] → [Miner →] → [Conveyor →] → [Smelter →] → [Conveyor →] → [Terminal]
```

The arrows show the facing direction of each building. Every building must face toward the next one in the chain.

> [!important] Orientation
> Press **R** to rotate before placing. A misaligned building won't connect to the chain and wastes resources.

## What Happens to Output

Ingots produced by the Smelter are pushed downstream. They can go to:
- A **[[Submitting Research|Submission Terminal]]** — to count toward research
- Another production building (like an [[The Assembler|Assembler]], unlocked later)
- A **[[Building Reference#Storage & Trade|Storage Container]]** — to buffer surplus

---

**Previous:** [[The Conveyor Network]] | **Next:** [[Submitting Research]]
