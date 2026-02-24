# The Conduit Network

Conduits (commonly: Conveyors) are the arteries of your factory. Understanding them is essential.

## How Conduits Work

- Each Conduit holds **1 item** at a time in its buffer
- Every tick, the Conduit attempts to push its item to the next building in its facing direction
- If the next building's input is full, the item **waits**
- If there's nowhere to go, the item **drops to the ground** on that tile

## Conduit Tiers

| Bureau Name | Common Name | Unlocked At | Speed |
|---|---|---|---|
| Conduit | Conveyor | Start | Standard |
| Conduit Mk-II | Conveyor Mk2 | [[Reaching Clearance 1|Clearance 1]] | Faster |
| Conduit Mk-III | Conveyor Mk3 | Clearance 2 | Fastest |

See [[Building Reference]] for construction costs.

## Planning a Line

Think of your factory as a flow:

```
Resource Tile → Extractor → Conduits → Processor → Conduits → Destination
```

Keep lines straight when possible.

## Line Mode

Press **L** to toggle Line Mode. In this mode, each click extends a straight line of Conduits automatically — much faster than placing one at a time for long runs.

## Dealing with Overflow

If a Conduit can't push its item forward (the next building is full or missing), the item drops to the ground on that tile as a **ground item**. Ground items within **3 tiles** of a construction site are automatically consumed for building. Otherwise, they sit until picked up by a neighboring Conduit.

## Advanced Routing

Once you unlock [[Advanced Logistics|advanced logistics]] buildings at Clearance 1–2, you can build complex networks:

- **[[Advanced Logistics#Distributor (Splitter)|Distributor]]** — 1 input → 3 outputs
- **[[Advanced Logistics#Converger (Merger)|Converger]]** — multiple inputs → 1 output
- **[[Advanced Logistics#Load Equalizer (Balancer)|Load Equalizer]]** — 1 input → 4 even outputs
- **[[Advanced Logistics#Subsurface Link (Underground Conduit)|Subsurface Link]]** — tunnel under 1 tile
- **[[Advanced Logistics#Transit Interchange (Crossover)|Transit Interchange]]** — cross paths without merging

---

**Previous:** [[Placing Your First Buildings]] | **Next:** [[Extraction & Processing]]
