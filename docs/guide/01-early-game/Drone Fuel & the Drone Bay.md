# Drone Fuel & the Drone Bay

Your camera drone runs on fuel. Managing your fuel supply is an early-game concern that gives **Entity Biofuel** an immediate purpose — long before you unlock Bio Generators at Clearance 4.

## How Drone Fuel Works

The drone carries a **5-slot fuel tank**. Each slot holds one unit of fuel.

| Fuel Type | Duration | Available At |
|---|---|---|
| Entity Biofuel | 60 seconds | Clearance 0 (Gathering Post output) |
| Refined Entity Fuel | 150 seconds | Clearance 2 (Distiller output) |

Fuel is consumed in real time while you play. The active fuel unit drains first; when it empties, the next unit in the tank is loaded automatically.

> [!info] Starting Fuel
> New Operators begin with a full tank of 5 Entity Biofuel — that's **5 minutes** of flight time before you need to refuel.

## Low Power Mode

When the tank runs dry, the drone enters **low power mode**:

- Movement speed drops to **25%** of normal
- A red vignette overlay appears on screen
- The fuel gauge flickers

You can still fly and build in low power mode — it's just much slower. Pick up fuel to restore full speed immediately.

## The Fuel Gauge

The fuel gauge appears at the **bottom center** of the screen, just above the toolbar. It shows one pip per tank slot:

- **Green pip**: Entity Biofuel
- **Cyan pip**: Refined Entity Fuel
- **Dark pip**: Empty slot
- **Flashing red**: Warning — fuel is critically low

The leftmost pip is the active (draining) fuel unit.

## Picking Up Fuel

To refuel, **zoom close to the surface** (scroll down) near a tile that has Entity Biofuel or Refined Entity Fuel on the ground. When your drone is low enough (altitude below ~0.3), it automatically collects fuel items and adds them to the tank.

Common fuel sources:
- **[[Your Starter Kit#Gathering Post|Gathering Posts]]** produce Entity Biofuel as a byproduct and output it onto [[The Conduit Network|Conduits]]
- Eject biofuel from a building's output buffer onto the ground, then fly low to pick it up
- Route biofuel off your production line to a convenient pickup spot

> [!tip] Fuel Depot
> Early on, build a short Conduit spur off your Gathering Post that dumps biofuel onto an open tile. Fly there when you need to refuel.

## The Drone Bay (Clearance 1)

At **Clearance 1**, you unlock the **Drone Bay** — a personal upgrade station for your camera drone.

**Construction Cost:** 15 Ferric Standard, 10 Paraelectric Bar

Click a Drone Bay to open its upgrade panel. The bay offers six permanent upgrades — some require higher Clearance levels:

### Upgrades

| Upgrade | Clearance | Resource Cost | Effect |
|---|---|---|---|
| **Auto-Refuel** | 1 | 5 Ferric Standard, 3 Paraelectric Bar, 2 Conductive Filament | Bay accepts biofuel into a buffer and auto-refuels your drone when you fly nearby |
| **Expanded Tank** | 1 | 4 Conductive Filament, 3 Structural Plate, 2 Resonance Circuit | Increases tank capacity from 5 to **10 slots** |
| **Drone Spotlight** | 1 | 4 Ferric Standard, 3 Conductive Filament, 2 Paraelectric Bar | Toggleable light (press **L**); burns fuel at **2x speed** while on |
| **Expanded Cargo** | 1 | 5 Structural Plate, 3 Resonance Circuit, 6 Conductive Filament | Increases drone cargo capacity from 1 to **4 items** |
| **Delivery Drone** | 3 | 3 Astral Frame, 3 Resonance Circuit, 2 Kinetic Driver, 5 Entity Biofuel | Adds an automated delivery drone to this bay (see below) |
| **Delivery Cargo** | 4 | 2 Heavy Astral Frame, 1 Advanced Resonance Circuit, 2 Kinetic Driver | Increases delivery drone cargo capacity from 2 to **4 items** |

### Installing an Upgrade

1. Click the Drone Bay to open the tile info panel
2. Select an upgrade and click **Install**
3. The bay enters **accepting mode** — it now accepts only the required items via Conduit input (from the rear)
4. Feed the required resources. Progress is shown in the panel.
5. Once all items are delivered, the upgrade is permanently applied

> [!note] Upgrades Are Permanent
> Drone upgrades are tied to your Operator account, not the building. You keep them even if the Drone Bay is decommissioned. You can also build multiple Drone Bays.

### Auto-Refuel

Once installed, the Drone Bay accepts Entity Biofuel and Refined Entity Fuel into an internal buffer (up to 5 units). When your drone is zoomed close to any part of the sphere, it automatically draws fuel from any of your bays that have buffered fuel. Route a Conduit line of biofuel into the bay to keep it topped up.

### Drone Spotlight

Press **L** (when no building is selected for placement) to toggle the spotlight. The spotlight illuminates the area around your drone but doubles fuel consumption while active.

## Delivery Drone (Clearance 3)

At **Clearance 3**, you can install the **Delivery Drone** upgrade on a Drone Bay. This adds an automated logistics drone that flies between [[Placing Your First Buildings#Containment Vaults|Containment Vaults]] (storage containers) and construction sites, delivering the materials they need.

### How It Works

Each Drone Bay with the upgrade gets its own delivery drone. The drone operates in a cycle:

1. **Idle at bay** — the drone waits docked at the bay, scanning for work
2. **Fly to storage** — when a nearby construction site needs materials and a nearby Containment Vault has them, the drone flies to the vault
3. **Pick up items** — the drone loads up to **2 items** (4 with [[#Upgrades|Delivery Cargo]] upgrade) from the vault
4. **Fly to construction site** — the drone carries the materials to the site
5. **Deliver** — the items are deposited into the construction site
6. **Return to bay** — the drone flies back and the cycle repeats

The drone moves at **1 tile per tick** (200 ms), so you can watch it physically flying between buildings on the sphere surface.

### Range

Delivery drones operate within the **same cell and adjacent cells** on the same face. Each face is divided into a 4×4 grid of cells (16×16 tiles each). A drone can reach any building within this ~3 cell radius from its bay.

> [!tip] Placement Strategy
> Place your Drone Bay near your Containment Vaults for shortest flight paths. The drone handles the last-mile delivery to construction sites anywhere in the surrounding cells.

### Fuel

Delivery drones consume fuel from the same pool as your camera drone's Auto-Refuel system:

- The drone has a **3-slot reserve fuel tank** and one active fuel slot
- It burns fuel at the same rate as the camera drone (0.2 seconds per tick while flying)
- It automatically draws fuel from the bay's Auto-Refuel buffer when its tank has room
- **If the drone runs out of fuel**, it drops any carried items on the ground and returns to the bay

| Fuel Type | Duration |
|---|---|
| Entity Biofuel | 60 seconds |
| Catalysed Ichor Fuel | 90 seconds |
| Refined Entity Fuel | 150 seconds |
| Unstable Mixed Fuel | 30 seconds |
| Stable Mixed Fuel | 480 seconds |

> [!warning] Keep the Bay Fueled
> Make sure your Drone Bay has Auto-Refuel installed and a steady supply of fuel routed in via Conduit. Without fuel, the delivery drone will sit idle.

### Delivery Cargo Upgrade (Clearance 4)

At Clearance 4, you can install **Delivery Cargo** on the same Drone Bay to double the delivery drone's carrying capacity from 2 to **4 items per trip**. This significantly speeds up construction for buildings that require many materials.

### Status Panel

When you click a Drone Bay with an active delivery drone, the tile info panel shows:

- **Status**: Idle, Picking up, Delivering, or Returning
- **Fuel**: Current fuel type and remaining seconds, plus reserve count
- **Cargo**: Items currently being carried
- **Capacity**: Current cargo limit (2 or 4)

---

**Previous:** [[Reaching Clearance 1]] | **Next:** [[Claiming Territory]]
