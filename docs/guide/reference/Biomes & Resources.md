# Biomes & Resources

## Biomes

The sphere's surface is divided into five biome types based on latitude.

| Biome | Bureau Designation | Latitude | Creatures Found |
|---|---|---|---|
| Grassland | Threshold Plain | Mid-latitudes | Copper Beetle, Spore Cloud, Resonance Moth, Ferric Sentinel |
| Desert | Arid Expanse | Low-latitudes | Ember Wisp, Static Mote, Flux Serpent, Phase Wisp |
| Tundra | Permafrost Zone | High-latitudes | Frost Shard, Quartz Drone, Resonance Moth, Phase Wisp |
| Forest | Overgrowth Sector | Mid-latitudes | Shadow Tendril, Quartz Drone, Spore Cloud, Resonance Moth |
| Volcanic | Astral Rift | Extreme zones | Ember Wisp, Void Fragment, Flux Serpent, Ferric Sentinel |

See [[Creature Reference]] for full creature details.

## The Shift Cycle

Each biome may have production modifiers during different shift phases:

| Phase | Duration |
|---|---|
| Dawn Shift | 1200 ticks (~4 min) |
| Zenith Shift | 1200 ticks |
| Dusk Shift | 1200 ticks |
| Nadir Shift | 1200 ticks |

Full day cycle: **4800 ticks** (~16 minutes).

## Seasons & Solar Position

The sun's position is computed using realistic solar astronomy:

- **Solar Declination** varies over a **30-day year** due to the sphere's 23.4° axial tilt. The sun's path shifts between the northern and southern hemispheres, creating seasons.
- **Solar Hour Angle** drives the daily east-west rotation of the sun.
- **Solar Elevation** at any point on the sphere depends on both its latitude and the current declination: `sin(elevation) = sin(lat) × sin(decl) + cos(lat) × cos(decl) × cos(hour_angle)`

Lighting is calculated **per cell** (each face is divided into a 4x4 grid of cells), giving 480 distinct illumination zones across the sphere. This means the shadow/light boundary cuts smoothly across faces rather than toggling entire faces at once.

**Seasonal effects on gameplay:**
- **Polar biomes** (Tundra, Volcanic) experience the strongest seasonal variation — extended light or darkness depending on the time of year
- **Equatorial biomes** (Grassland, Desert) stay relatively stable year-round
- **Shadow Panels** near the poles produce power for longer during winter and shorter during summer

## Resources

Roughly **8% of tiles** contain resource deposits. Each deposit holds **100–500 units**.

| Resource | Bureau Name (Raw) | Bureau Name (Processed) | Processing Building |
|---|---|---|---|
| Iron | Ferric Compound (Raw) | Ferric Standard | [[Mining & Smelting\|Smelter]] |
| Copper | Paraelectric Ore (Raw) | Paraelectric Bar | Smelter |
| Quartz | Resonance Crystal (Raw) | Refined Resonance Crystal | Smelter |
| Titanium | Astral Ore (Raw) | Astral Ingot | Smelter |
| Oil | Black Rock Ichor (Crude) | Stabilized Polymer | [[The Refinery\|Refinery]] |
| Sulfur | Threshold Dust (Raw) | Threshold Compound | Refinery |
| Uranium | Threshold Radiant (Raw) | Enriched Radiant | [[Advanced Production\|Adv. Smelter]] / [[High-Tech Manufacturing\|Nuclear Refinery]] |

## Resource Availability by Clearance

| Clearance | New Resources Available |
|---|---|
| 0 | Iron, Copper |
| 2 | Quartz, Titanium, Oil, Sulfur |
| 4+ | Uranium |

---

**Back to:** [[Home]]
