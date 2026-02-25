# Advanced Logistics

Clearance 1 and 2 unlock several logistics buildings that let you build complex routing networks beyond simple [[The Conduit Network|Conduit]] chains.

---

## Conduit Tiers

Higher-tier conduits move items faster but cost more to build. Speed is measured in ticks per tile (1 tick = 200ms).

| Tier | Bureau Name | Clearance | Speed | Throughput | Cost |
|---|---|---|---|---|---|
| Mk-I | Conduit | 0 | 3 ticks/tile | 1.67/sec | 1 Ferric Standard |
| Mk-II | Conduit Mk-II | 1 | 2 ticks/tile | 2.5/sec | 2 Ferric Standard, 1 Conductive Filament |
| Mk-III | Conduit Mk-III | 2 | 1 tick/tile | 5.0/sec | 3 Structural Plate, 2 Conductive Filament |

See [[The Conduit Network]] for full details on conduit mechanics and Line Mode.

---

## Distributor (Splitter)

*Unlocked at [[Reaching Clearance 1|Clearance 1]]*

- **1 input → 3 outputs**
- Items are distributed round-robin to all connected output directions
- Use to fan out a production line to multiple consumers

**Cost:** 3 Ferric Standard, 2 Paraelectric Bar

---

## Converger (Merger)

*Unlocked at [[Reaching Clearance 1|Clearance 1]]*

- **2 inputs → 1 output**
- Accepts items from the left and right sides, pushes forward
- Use to combine two material streams into one conduit line

**Cost:** 3 Ferric Standard, 2 Paraelectric Bar

---

## Containment Vault (Storage Container)

*Unlocked at [[Reaching Clearance 1|Clearance 1]]*

- Buffers up to **100 items** of a single type
- Accepts items from the rear, outputs from the front
- Once an item type is set, only accepts that type until emptied
- Useful as a buffer between production stages or for stockpiling

**Cost:** 5 Ferric Standard, 2 Structural Plate

---

## Load Equalizer (Balancer)

*Unlocked at Clearance 2*

- **1 input → 2 outputs** (left and right)
- Routes items to the less-full downstream building
- Falls back to alternating if both sides are equally available
- Use to evenly split production across parallel lines

**Cost:** 5 Structural Plate, 1 Resonance Circuit

---

## Selective Distributor (Filtered Splitter)

*Unlocked at Clearance 3*

- **1 input → 2 outputs** (left and right)
- Routes items by type: items matching the **filter** go left, everything else goes right
- When no filter is set, alternates left/right like a regular Distributor
- Select the building in the tile info panel to choose a filter item or clear it

**Cost:** 3 Structural Plate, 2 Resonance Circuit, 1 Astral Frame

> [!tip] Sort mixed production lines
> Place a Selective Distributor after a machine that produces mixed outputs. Set the filter to the item you want separated — matching items route left to one line, everything else continues right to another.

---

## Surplus Router (Overflow Gate)

*Unlocked at Clearance 3*

- **1 input → 2 outputs** (forward primary, left overflow)
- Items enter from the rear and pass **straight through** to the forward output
- When the forward destination is full or blocked, items overflow to the **left** side instead
- If both outputs are full, the item is held

**Cost:** 4 Structural Plate, 1 Resonance Circuit, 1 Astral Frame

> [!tip] Handle excess production
> Place a Surplus Router inline on a conduit feeding a machine. When the machine backs up, excess items automatically route to the side — into a Containment Vault, a secondary production line, or an Exchange Terminal.

---

## Priority Converger (Priority Merger)

*Unlocked at Clearance 3*

- **2 inputs → 1 output** (forward)
- The **left** input has priority — items from the left side are always accepted first
- The right input only feeds when no item is pending from the left
- Use to create a "main line with supplement" pattern

**Cost:** 4 Paraelectric Bar, 1 Resonance Circuit, 1 Astral Frame

> [!tip] Supplement a primary supply
> Feed your main production output into the priority (left) side and a backup source into the right. The right side only activates when the main line can't keep up, ensuring smooth throughput without waste.

---

## Subsurface Link (Underground Conduit)

*Unlocked at Clearance 2*

- Tunnels items under one tile to a paired exit
- Place two Subsurface Links and use the **Link** button in the tile info panel to pair them
- Items enter at one end and emerge at the other, bypassing surface buildings
- Use to route around obstacles or cross paths without a Transit Interchange

**Cost:** 8 Structural Plate, 5 Conductive Filament

---

## Transit Interchange (Crossover)

*Unlocked at Clearance 2*

- Two perpendicular conduit streams pass through without merging
- Horizontal items (W/E) use one slot, vertical items (N/S) use the other
- Each item passes straight through to the opposite side
- Use where two conduit lines need to cross paths

**Cost:** 4 Structural Plate, 1 Conductive Filament

---

## Transfer Station

*Unlocked at Clearance 4*

- Bridges items between [[Power & Energy#Substation|Substations]]
- Use to move items across longer distances without conduit chains

**Cost:** 10 Shielded Conductor, 6 Resonance Circuit, 2 Astral Frame

---

## Insertion Arm (Loader)

*Unlocked at Clearance 4*

- Transfers items **from a Containment Vault** to a target tile (machine input, conduit, or ground)
- Range 2 tiles (Manhattan distance, same face)
- Transfers bypass the normal conduit push system — items move directly in a dedicated phase each tick
- Can be upgraded to **Bulk Transfer** mode (moves up to 10 stacked items per tick)
- Requires [[Power & Energy|power]] to operate

**Configuration:** Select the arm in the tile info panel, then use the **Set** buttons to link a source (must be a Containment Vault) and destination (any tile in range). Click a tile on the map to confirm each link.

**Cost:** 3 Shielded Conductor, 2 Astral Frame, 1 Kinetic Driver

**Bulk Transfer Upgrade:** 2 Shielded Conductor, 1 Resonance Circuit, 1 Whispering Ingot, 1 Kinetic Driver — drop materials on the arm's tile, then click **Enable** in the tile info panel.

> [!tip] Use arms to solve throughput bottlenecks
> Some recipes consume inputs faster than a single conduit can deliver. Even a Mk-III conduit maxes out at 1 item/tick (5/sec). An Insertion Arm pulling from a Containment Vault provides a parallel feed channel, keeping machines running at full speed.

---

## Extraction Arm (Unloader)

*Unlocked at Clearance 4*

- Transfers items **from a source tile** (machine output, conduit, or ground) **into a Containment Vault**
- Range 2 tiles (Manhattan distance, same face)
- Grabs items before the conduit push phase — prevents output buffer congestion
- Can be upgraded to **Bulk Transfer** mode (moves up to 10 stacked items per tick)
- Requires [[Power & Energy|power]] to operate

**Configuration:** Same as the Insertion Arm — use the tile info panel to set source (any tile) and destination (must be a Containment Vault).

**Cost:** 3 Shielded Conductor, 2 Astral Frame, 1 Kinetic Driver

**Bulk Transfer Upgrade:** 2 Shielded Conductor, 1 Resonance Circuit, 1 Whispering Ingot, 1 Kinetic Driver — drop materials on the arm's tile, then click **Enable** in the tile info panel.

> [!tip] Pair arms with Containment Vaults
> The typical pattern is: **Extraction Arm → Vault → Insertion Arm**. The unloader grabs output from a machine, the vault buffers it, and the loader feeds it into the next machine. This decouples production stages and smooths throughput.
