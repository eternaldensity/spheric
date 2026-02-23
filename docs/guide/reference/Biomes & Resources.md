# Biomes & Resources

## Biomes

The sphere's surface is divided into five biome types based on latitude.

| Bureau Designation | Common Name | Latitude | Creatures Found |
|---|---|---|---|
| Threshold Plain | Grassland | Mid-latitudes | Copper Beetle, Spore Cloud, Resonance Moth, Ferric Sentinel |
| Arid Expanse | Desert | Low-latitudes | Ember Wisp, Static Mote, Flux Serpent, Phase Wisp |
| Permafrost Zone | Tundra | High-latitudes | Frost Shard, Quartz Drone, Resonance Moth, Phase Wisp |
| Overgrowth Sector | Forest | Mid-latitudes | Shadow Tendril, Quartz Drone, Spore Cloud, Resonance Moth |
| Astral Rift | Volcanic | Extreme zones | Ember Wisp, Void Fragment, Flux Serpent, Ferric Sentinel |

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
- **Polar biomes** (Permafrost Zone, Astral Rift) experience the strongest seasonal variation — extended light or darkness depending on the time of year
- **Equatorial biomes** (Threshold Plain, Arid Expanse) stay relatively stable year-round
- **Shadow Panels** near the poles produce power for longer during winter and shorter during summer

## Resources

Resources appear in **ore veins** — clusters of the same resource type that form natural deposits across the sphere's surface. Each deposit tile holds **100–500 units**.

Rather than being scattered randomly, ore veins radiate outward from a central point with the densest concentration at the core and thinning toward the edges. Resource-rich biomes (Astral Rift, Arid Expanse) produce more and larger veins, while sparse biomes (Permafrost Zone, Overgrowth Sector) have fewer. Occasional lone deposits can appear outside veins, but the bulk of resources are found in clusters.

> [!tip] Vein Scouting
> When you find a resource tile, check the surrounding area — there's likely a whole vein nearby. Plan your Extractor layouts around the densest part of the cluster for maximum yield.

| Bureau Name (Raw) | Common Name | Bureau Name (Processed) | Processing Building |
|---|---|---|---|
| Ferric Compound (Raw) | Iron | Ferric Standard | [[Extraction & Processing\|Processor]] |
| Paraelectric Ore (Raw) | Copper | Paraelectric Bar | Processor |
| Resonance Crystal (Raw) | Quartz | Refined Resonance Crystal | Processor |
| Astral Ore (Raw) | Titanium | Astral Ingot | Processor |
| Black Rock Ichor (Crude) | Oil | Stabilized Polymer | [[The Distiller\|Distiller]] |
| Threshold Dust (Raw) | Sulfur | Threshold Compound | Distiller |
| Threshold Radiant (Raw) | Uranium | Enriched Radiant | [[Advanced Production\|Adv. Processor]] / [[High-Tech Manufacturing\|Nuclear Distiller]] |

## Resource Availability by Clearance

| Clearance | New Resources Available |
|---|---|
| 0 | Ferric Compound, Paraelectric Ore |
| 2 | Resonance Crystal, Astral Ore, Black Rock Ichor, Threshold Dust |
| 4+ | Threshold Radiant |

---

**Back to:** [[Home]]
