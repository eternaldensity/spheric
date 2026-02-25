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

> [!tip] Pair arms with Containment Vaults
> The typical pattern is: **Extraction Arm → Vault → Insertion Arm**. The unloader grabs output from a machine, the vault buffers it, and the loader feeds it into the next machine. This decouples production stages and smooths throughput.
