# Placing Your First Buildings

This walkthrough takes you from an empty sphere to a working production line.

## Step 1: Find Ferric Compound

Rotate the sphere and look for tiles with a colored glow — these are resource deposits. Click a tile to inspect it. You're looking for tiles that say **Ferric Compound**.

## Step 2: Place an Extractor

1. Select the Extractor from your [[The HUD#Hotbar|hotbar]] (press the appropriate number key)
2. Press **R** to rotate the building's orientation if needed — the orientation determines which direction items are pushed out
3. Click on a Ferric Compound deposit tile to place the Extractor

> [!important] Extractors can only be placed on tiles with resource deposits.

## Step 3: Orientation Matters

Every building has a **facing direction** (W, S, E, N). This determines:
- Where an **Extractor** pushes its output
- Where a **Conduit** pushes items
- Which side a **Processor** accepts input and pushes output

Press **R** before placing to cycle through orientations. Plan your layout so items flow naturally from one building to the next.

## Step 4: Connect with Conduits

Place [[The Conduit Network|Conduits]] to create a path from your Extractor to a Processor. Each Conduit pushes items in its facing direction. Chain them together so items flow downstream.

```
[Extractor] → [Conduit] → [Conduit] → [Processor] → [Conduit] → [Terminal]
```

> [!tip] Line Mode
> Press **L** to enter Line Mode. Each click extends a straight line of Conduits — much faster than placing one at a time.

## Step 5: Place a Processor

Place a [[Extraction & Processing|Processor]] at the end of your Conduit chain. Make sure the Processor's input side faces the incoming Conduit.

The Processor converts:
- **Ferric Compound (Raw)** → **Ferric Standard**
- **Paraelectric Ore (Raw)** → **Paraelectric Bar**

## Step 6: Construction

Your [[Your Starter Kit|Starter Kit]] buildings are placed **instantly** — no construction needed. Once your free buildings are used up, every new building starts as a **construction site** that needs materials delivered before it becomes operational.

### How to recognise a construction site

Construction sites appear as **translucent wireframes** — a ghostly outline of the finished building. Click one to see its progress in the tile info panel:

```
CLASSIFIED  Extractor
Under construction (0/3) — needs 2 Ferric Standard, 1 Paraelectric Bar
```

### Delivering materials

> [!note] Auto-Delivery
> Ground items within **3 tiles** of a construction site are automatically consumed each tick. Drop the required resources on the ground nearby and they will be pulled in.

Once all materials are delivered, the wireframe solidifies into the finished building and it begins working on the next tick.

### Power switch

Every machine (Extractors, Processors, Fabricators, Distillers, and all advanced production buildings) has a **power switch**. Click the building to open the tile info panel — you'll see an **ON / OFF** toggle button.

When you switch a machine **OFF**:
- Production **stops** — no progress is made
- The machine **refuses incoming items** — Conduits will back up
- Items already inside the machine's buffers are **preserved** and will resume processing when you switch it back on
- The tile info panel shows **OFFLINE** as the building status

> [!tip] When to use the power switch
> - **Debugging flow**: turn off a machine to see where items are backing up
> - **Saving resources**: pause an Extractor to preserve a deposit until you need it
> - **Reconfiguring**: stop production while you rearrange Conduits downstream

### Ejecting items

If a building's output is stuck — for example, a Processor with no downstream Conduit — you can manually retrieve the item. Click the building to open the tile info panel, then press the **Eject** button. The item drops onto the ground on the building's output side (its facing direction).

> [!tip] Bootstrapping
> Early on you may have a Processor producing Ferric Standards but no Conduits to move them. Eject an ingot from the Processor, and the nearby construction site will automatically pick it up.

### Construction limits

You can have at most **5 construction sites** pending at once. Finish existing sites before placing more buildings. This keeps your resource flow focused and prevents over-expanding before your factory can supply the materials.

### Decommissioning

Click a building and press **Decommission** to remove it. What you get back depends on the building's tier:

- **Tier 0** (Conduits, Extractors, Processors, Terminals): the building is returned to your [[Your Starter Kit|Starter Kit]] as a free placement. No resources are dropped — you simply get the free build credit back.
- **Tier 1+**: **half** the construction cost is dropped as ground items. If a [[Building Reference#Storage & Trade|Containment Vault]] with space is within **3 tiles**, the **full** amount of that resource is deposited into the container instead.
- **Incomplete construction sites**: whatever materials were delivered so far are refunded using the same rules above.

Any items held by the building (Conduit cargo, Processor buffers, etc.) are always dropped as ground items.

> [!tip] Reconfiguring
> Since tier 0 buildings refund as free placements, you can freely rearrange your early factory without wasting resources.

## Your First Complete Chain

Set up two parallel lines:

```
Ferric Compound Deposit  → Extractor → Conduit → Processor → Conduit ─┐
                                                                        ├→ Terminal
Paraelectric Ore Deposit → Extractor → Conduit → Processor → Conduit ─┘
```

This feeds both Ferric Standards and Paraelectric Bars into your Terminal, working toward your first [[Research Case Files|Case Files]].

---

**Previous:** [[Your Starter Kit]] | **Next:** [[The Conduit Network]]
