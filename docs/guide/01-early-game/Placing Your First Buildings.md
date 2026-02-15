# Placing Your First Buildings

This walkthrough takes you from an empty sphere to a working production line.

## Step 1: Find Iron

Rotate the sphere and look for tiles with a colored glow — these are resource deposits. Click a tile to inspect it. You're looking for tiles that say **Ferric Compound** (iron).

## Step 2: Place a Miner

1. Select the Miner from your [[The HUD#Hotbar|hotbar]] (press the appropriate number key)
2. Press **R** to rotate the building's orientation if needed — the orientation determines which direction items are pushed out
3. Click on an iron deposit tile to place the Miner

> [!important] Miners can only be placed on tiles with resource deposits.

## Step 3: Orientation Matters

Every building has a **facing direction** (W, S, E, N). This determines:
- Where a **Miner** pushes its output
- Where a **Conveyor** pushes items
- Which side a **Smelter** accepts input and pushes output

Press **R** before placing to cycle through orientations. Plan your layout so items flow naturally from one building to the next.

## Step 4: Connect with Conveyors

Place [[The Conveyor Network|Conveyors]] to create a path from your Miner to a Smelter. Each Conveyor pushes items in its facing direction. Chain them together so items flow downstream.

```
[Miner] → [Conveyor] → [Conveyor] → [Smelter] → [Conveyor] → [Terminal]
```

> [!tip] Line Mode
> Press **L** to enter Line Mode. Each click extends a straight line of conveyors — much faster than placing one at a time.

## Step 5: Place a Smelter

Place a [[Mining & Smelting|Smelter]] at the end of your conveyor chain. Make sure the Smelter's input side faces the incoming conveyor.

The Smelter converts:
- **Ferric Compound (Raw)** → **Ferric Standard** (iron ingot)
- **Paraelectric Ore (Raw)** → **Paraelectric Bar** (copper ingot)

## Step 6: Construction

When you place a building, it starts as a **construction site**. It needs materials delivered to it before it becomes operational.

> [!note] Auto-Delivery
> Ground items within **3 tiles** of a construction site are automatically consumed to build it. For your [[Your Starter Kit|Starter Kit]] buildings, the resources needed are minimal — just a few ingots.

Once built, the building activates and begins working on the next tick cycle.

## Your First Complete Chain

Set up two parallel lines:

```
Iron Deposit  → Miner → Conveyor → Smelter → Conveyor ─┐
                                                         ├→ Terminal
Copper Deposit → Miner → Conveyor → Smelter → Conveyor ─┘
```

This feeds both Ferric Standards and Paraelectric Bars into your Terminal, working toward your first [[Research Case Files|Case Files]].

---

**Previous:** [[Your Starter Kit]] | **Next:** [[The Conveyor Network]]
