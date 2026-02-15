# The Conveyor Network

Conveyors (Conduits) are the arteries of your factory. Understanding them is essential.

## How Conveyors Work

- Each conveyor holds **1 item** at a time in its buffer
- Every tick, the conveyor attempts to push its item to the next building in its facing direction
- If the next building's input is full, the item **waits**
- If there's nowhere to go, the item **drops to the ground** on that tile

## Conveyor Tiers

| Conveyor | Bureau Name | Unlocked At | Speed |
|---|---|---|---|
| Conveyor | Conduit | Start | Standard |
| Conveyor Mk2 | Conduit Mk-II | [[Reaching Clearance 1|Clearance 1]] | Faster |
| Conveyor Mk3 | Conduit Mk-III | Clearance 2 | Fastest |

See [[Building Reference]] for construction costs.

## Planning a Line

Think of your factory as a flow:

```
Resource Tile → Miner → Conveyors → Smelter → Conveyors → Destination
```

Keep lines straight when possible.

## Line Mode

Press **L** to toggle Line Mode. In this mode, each click extends a straight line of conveyors automatically — much faster than placing one at a time for long runs.

## Dealing with Overflow

If a conveyor can't push its item forward (the next building is full or missing), the item drops to the ground on that tile as a **ground item**. Ground items within **3 tiles** of a construction site are automatically consumed for building. Otherwise, they sit until picked up by a neighboring conveyor.

## Advanced Routing

Once you unlock [[Advanced Logistics|advanced logistics]] buildings at Clearance 1–2, you can build complex networks:

- **[[Advanced Logistics#Splitter (Distributor)|Splitter]]** — 1 input → 3 outputs
- **[[Advanced Logistics#Merger (Converger)|Merger]]** — multiple inputs → 1 output
- **[[Advanced Logistics#Balancer (Load Equalizer)|Balancer]]** — 1 input → 4 even outputs
- **[[Advanced Logistics#Underground Conduit (Subsurface Link)|Underground Conduit]]** — tunnel under 1 tile
- **[[Advanced Logistics#Crossover (Transit Interchange)|Crossover]]** — cross paths without merging

---

**Previous:** [[Placing Your First Buildings]] | **Next:** [[Mining & Smelting]]
