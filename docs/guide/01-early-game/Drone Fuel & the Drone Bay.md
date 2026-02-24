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
- **[[Your Starter Kit#Gathering Post|Gathering Posts]]** produce Entity Biofuel as a byproduct and output it onto [[The Conveyor Network|Conduits]]
- Eject biofuel from a building's output buffer onto the ground, then fly low to pick it up
- Route biofuel off your production line to a convenient pickup spot

> [!tip] Fuel Depot
> Early on, build a short Conduit spur off your Gathering Post that dumps biofuel onto an open tile. Fly there when you need to refuel.

## The Drone Bay (Clearance 1)

At **Clearance 1**, you unlock the **Drone Bay** — a personal upgrade station for your camera drone.

**Construction Cost:** 15 Ferric Standard, 10 Paraelectric Bar

Click a Drone Bay to open its upgrade panel. The bay offers three permanent upgrades:

### Upgrades

| Upgrade | Resource Cost | Effect |
|---|---|---|
| **Auto-Refuel** | 5 Ferric Standard, 3 Paraelectric Bar, 2 Conductive Filament | Bay accepts biofuel into a buffer and auto-refuels your drone when you fly nearby |
| **Expanded Tank** | 4 Conductive Filament, 3 Structural Plate, 2 Resonance Circuit | Increases tank capacity from 5 to **10 slots** |
| **Drone Spotlight** | 4 Ferric Standard, 3 Conductive Filament, 2 Paraelectric Bar | Toggleable light (press **L**); burns fuel at **2x speed** while on |

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

---

**Previous:** [[Reaching Clearance 1]] | **Next:** [[Claiming Territory]]
