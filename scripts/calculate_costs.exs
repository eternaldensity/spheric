# scripts/calculate_costs.exs
#
# Calculates the total raw-resource cost of constructing endgame items/buildings.
# Recursively resolves every intermediate recipe down to raw ores + creature_essence.
#
# Usage:
#   mix run scripts/calculate_costs.exs
#   mix run scripts/calculate_costs.exs --item board_resonator
#   mix run scripts/calculate_costs.exs --building board_interface
#   mix run scripts/calculate_costs.exs --tier 7           # all buildings in tier 7+
#   mix run scripts/calculate_costs.exs --all              # every item & building
#   mix run scripts/calculate_costs.exs --research         # case file delivery costs
#   mix run scripts/calculate_costs.exs --everything       # buildings + research combined
#   mix run scripts/calculate_costs.exs --supply           # supply vs demand analysis

# ── Recipe database ──────────────────────────────────────────────────────────
#
# Format: output_atom => {[{input, qty}, ...], output_qty}
# "To make output_qty of output, you need input_qty of each input."

recipe_lookup = %{
  # Smelter (all 1:1)
  iron_ingot: {[iron_ore: 1], 1},
  copper_ingot: {[copper_ore: 1], 1},
  titanium_ingot: {[titanium_ore: 1], 1},
  quartz_crystal: {[raw_quartz: 1], 1},

  # Refinery
  polycarbonate: {[crude_oil: 2], 1},
  sulfur_compound: {[raw_sulfur: 1], 1},
  refined_fuel: {[biofuel: 3], 2},

  # Nuclear refinery
  enriched_uranium: {[raw_uranium: 4], 1},

  # Assembler
  wire: {[copper_ingot: 1, copper_ingot: 1], 3},
  plate: {[iron_ingot: 1, iron_ingot: 1], 2},
  circuit: {[wire: 6, quartz_crystal: 1], 1},
  frame: {[plate: 2, titanium_ingot: 4], 1},
  motor: {[iron_ingot: 4, wire: 8], 1},
  cable: {[wire: 5, polycarbonate: 3], 2},
  reinforced_plate: {[plate: 2, iron_ingot: 4], 2},
  heat_sink: {[copper_ingot: 4, sulfur_compound: 1], 1},

  # Advanced assembler
  heavy_frame: {[frame: 2, reinforced_plate: 6], 1},
  advanced_circuit: {[circuit: 4, cable: 6], 1},
  plastic_sheet: {[polycarbonate: 10, sulfur_compound: 15], 5},

  # Fabrication plant
  computer: {[advanced_circuit: 3, advanced_circuit: 3, plastic_sheet: 4], 1},
  motor_housing: {[heavy_frame: 4, motor: 1, heat_sink: 2], 1},
  composite: {[reinforced_plate: 3, plastic_sheet: 2, titanium_ingot: 1], 1},

  # Particle collider
  supercomputer: {[computer: 10, advanced_circuit: 20], 1},
  advanced_composite: {[composite: 1, quartz_crystal: 2], 1},
  nuclear_cell: {[enriched_uranium: 1, advanced_composite: 3], 1},

  # Paranatural synthesizer
  containment_module: {[supercomputer: 1, advanced_composite: 1, creature_essence: 1], 1},
  dimensional_core: {[nuclear_cell: 1, containment_module: 1, creature_essence: 1], 1},
  astral_lens: {[quartz_crystal: 1, quartz_crystal: 1, creature_essence: 1], 1},

  # Board interface
  board_resonator: {[dimensional_core: 4, supercomputer: 2, astral_lens: 6], 1}
}

# Raw materials (no recipe to make them — they are mined or gathered)
raw_materials = MapSet.new([
  :iron_ore, :copper_ore, :raw_quartz, :titanium_ore,
  :crude_oil, :raw_sulfur, :raw_uranium,
  :creature_essence, :biofuel
])

# ── Recursive cost resolver ─────────────────────────────────────────────────

defmodule CostCalculator do
  @moduledoc false

  @doc """
  Resolve the raw material cost to produce `qty` of `item`.

  recipe_lookup format: %{output_atom => {[{input, input_qty}, ...], output_qty}}
  To make `qty` of item: need ceil(qty / output_qty) batches, each batch
  consuming input_qty of each input.
  """
  def resolve(item, qty, recipe_lookup, raw_materials, cache \\ %{}) do
    if MapSet.member?(raw_materials, item) do
      {%{item => qty}, cache}
    else
      case Map.get(recipe_lookup, item) do
        nil ->
          # Unknown item, treat as raw
          {%{item => qty}, cache}

        {inputs, out_qty} ->
          case Map.get(cache, item) do
            nil ->
              # Resolve cost for 1 batch (produces out_qty of this item)
              {batch_cost, cache} =
                Enum.reduce(inputs, {%{}, cache}, fn {input_item, input_qty}, {acc, cache} ->
                  {sub_cost, cache} = resolve(input_item, input_qty, recipe_lookup, raw_materials, cache)
                  {merge_costs(acc, sub_cost), cache}
                end)

              # Cache stores cost per batch (which produces out_qty items)
              cache = Map.put(cache, item, {batch_cost, out_qty})
              batches = ceil(qty / out_qty)
              {scale_costs(batch_cost, batches), cache}

            {batch_cost, cached_out_qty} ->
              batches = ceil(qty / cached_out_qty)
              {scale_costs(batch_cost, batches), cache}
          end
      end
    end
  end

  def merge_costs(a, b) do
    Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)
  end

  def scale_costs(costs, factor) do
    Map.new(costs, fn {k, v} -> {k, v * factor} end)
  end

  # Resolve a bill of materials (map of item => qty) into raw costs
  def resolve_bom(bom, recipe_lookup, raw_materials) do
    Enum.reduce(bom, %{}, fn {item, qty}, acc ->
      {cost, _cache} = resolve(item, qty, recipe_lookup, raw_materials)
      merge_costs(acc, cost)
    end)
  end
end

# ── Display names ────────────────────────────────────────────────────────────

display_names = %{
  iron_ore: "Iron Ore",
  copper_ore: "Copper Ore",
  raw_quartz: "Raw Quartz",
  titanium_ore: "Titanium Ore",
  crude_oil: "Crude Oil",
  raw_sulfur: "Raw Sulfur",
  raw_uranium: "Raw Uranium",
  creature_essence: "Creature Essence",
  biofuel: "Biofuel",
  iron_ingot: "Iron Ingot",
  copper_ingot: "Copper Ingot",
  titanium_ingot: "Titanium Ingot",
  quartz_crystal: "Quartz Crystal",
  polycarbonate: "Polycarbonate",
  sulfur_compound: "Sulfur Compound",
  enriched_uranium: "Enriched Uranium",
  wire: "Wire",
  plate: "Plate",
  circuit: "Circuit",
  frame: "Frame",
  motor: "Motor",
  cable: "Cable",
  reinforced_plate: "Reinforced Plate",
  heat_sink: "Heat Sink",
  heavy_frame: "Heavy Frame",
  advanced_circuit: "Advanced Circuit",
  plastic_sheet: "Plastic Sheet",
  computer: "Computer",
  motor_housing: "Motor Housing",
  composite: "Composite",
  supercomputer: "Supercomputer",
  advanced_composite: "Advanced Composite",
  nuclear_cell: "Nuclear Cell",
  containment_module: "Containment Module",
  dimensional_core: "Dimensional Core",
  astral_lens: "Astral Lens",
  board_resonator: "Board Resonator",
  refined_fuel: "Refined Fuel"
}

name = fn item ->
  Map.get(display_names, item, item |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize())
end

# ── Building construction costs ──────────────────────────────────────────────

building_costs = %{
  conveyor: %{iron_ingot: 1},
  miner: %{iron_ingot: 2, copper_ingot: 1},
  smelter: %{iron_ingot: 3},
  submission_terminal: %{iron_ingot: 2, copper_ingot: 2},
  conveyor_mk2: %{iron_ingot: 2, copper_ingot: 1},
  splitter: %{iron_ingot: 3, copper_ingot: 2},
  merger: %{iron_ingot: 3, copper_ingot: 2},
  claim_beacon: %{iron_ingot: 5, copper_ingot: 3},
  trade_terminal: %{iron_ingot: 5, wire: 3},
  storage_container: %{iron_ingot: 5, plate: 2},
  crossover: %{iron_ingot: 4, copper_ingot: 2},
  assembler: %{iron_ingot: 8, copper_ingot: 5, wire: 3},
  refinery: %{iron_ingot: 10, plate: 3, wire: 3},
  conveyor_mk3: %{iron_ingot: 3, wire: 2},
  balancer: %{iron_ingot: 5, circuit: 1},
  underground_conduit: %{iron_ingot: 8, copper_ingot: 5},
  containment_trap: %{frame: 2, circuit: 2, wire: 5},
  purification_beacon: %{frame: 3, circuit: 3, quartz_crystal: 5},
  defense_turret: %{frame: 3, plate: 5, circuit: 2},
  shadow_panel: %{frame: 2, quartz_crystal: 3, wire: 2},
  lamp: %{copper_ingot: 3, wire: 2, circuit: 1},
  bio_generator: %{frame: 3, motor: 2, cable: 3},
  substation: %{cable: 5, copper_ingot: 10, plate: 3},
  transfer_station: %{cable: 10, frame: 2, circuit: 3},
  advanced_smelter: %{heavy_frame: 1, circuit: 5, heat_sink: 3},
  advanced_assembler: %{heavy_frame: 2, advanced_circuit: 3, motor: 2},
  fabrication_plant: %{heavy_frame: 3, advanced_circuit: 5, motor: 3, cable: 5},
  essence_extractor: %{frame: 3, circuit: 5, quartz_crystal: 10},
  particle_collider: %{computer: 3, heavy_frame: 5, advanced_circuit: 5, motor_housing: 1},
  nuclear_refinery: %{composite: 5, computer: 2, heavy_frame: 3},
  dimensional_stabilizer: %{supercomputer: 2, advanced_composite: 5, containment_module: 1},
  paranatural_synthesizer: %{supercomputer: 3, advanced_composite: 3, nuclear_cell: 1},
  astral_projection_chamber: %{supercomputer: 2, containment_module: 2, astral_lens: 1},
  board_interface: %{dimensional_core: 2, supercomputer: 5, astral_lens: 3, advanced_composite: 10}
}

building_tiers = %{
  conveyor: 0, conveyor_mk2: 1, conveyor_mk3: 2,
  miner: 0, smelter: 0, submission_terminal: 0, gathering_post: 0,
  splitter: 1, merger: 1, claim_beacon: 1, trade_terminal: 1,
  storage_container: 1, crossover: 1,
  assembler: 2, refinery: 2, balancer: 2, underground_conduit: 2,
  containment_trap: 3, purification_beacon: 3, defense_turret: 3,
  shadow_panel: 3, lamp: 3,
  bio_generator: 4, substation: 4, transfer_station: 4, advanced_smelter: 4,
  advanced_assembler: 5, fabrication_plant: 5, essence_extractor: 5,
  particle_collider: 6, nuclear_refinery: 6,
  dimensional_stabilizer: 7, paranatural_synthesizer: 7, astral_projection_chamber: 7,
  board_interface: 8
}

building_names = %{
  conveyor: "Conveyor", conveyor_mk2: "Conveyor Mk2", conveyor_mk3: "Conveyor Mk3",
  miner: "Miner", smelter: "Smelter", submission_terminal: "Submission Terminal",
  gathering_post: "Gathering Post",
  splitter: "Splitter", merger: "Merger", claim_beacon: "Claim Beacon",
  trade_terminal: "Trade Terminal", storage_container: "Storage Container",
  crossover: "Crossover",
  assembler: "Assembler", refinery: "Refinery", balancer: "Balancer",
  underground_conduit: "Underground Conduit",
  containment_trap: "Containment Trap", purification_beacon: "Purification Beacon",
  defense_turret: "Defense Turret", shadow_panel: "Shadow Panel", lamp: "Lamp",
  bio_generator: "Bio Generator", substation: "Substation",
  transfer_station: "Transfer Station", advanced_smelter: "Advanced Smelter",
  advanced_assembler: "Advanced Assembler", fabrication_plant: "Fabrication Plant",
  essence_extractor: "Essence Extractor",
  particle_collider: "Particle Collider", nuclear_refinery: "Nuclear Refinery",
  dimensional_stabilizer: "Dimensional Stabilizer",
  paranatural_synthesizer: "Paranatural Synthesizer",
  astral_projection_chamber: "Astral Projection Chamber",
  board_interface: "Board Interface"
}

# ── Research case file costs ─────────────────────────────────────────────────

research_costs = %{
  "L1 Ferric Standardization" => %{iron_ingot: 50},
  "L1 Paraelectric Requisition" => %{copper_ingot: 30},
  "L2 Fabrication Protocol Alpha" => %{wire: 40, plate: 40},
  "L2 Astral Ore Refinement" => %{titanium_ingot: 30},
  "L3 Paranatural Engineering" => %{circuit: 30, frame: 20, polycarbonate: 20},
  "L4 Industrial Requisition" => %{motor: 20, cable: 20, heat_sink: 30},
  "L4 Organic Energy Mandate" => %{biofuel: 50, refined_fuel: 20},
  "L5 Heavy Industry Protocol" => %{heavy_frame: 15, advanced_circuit: 15},
  "L5 Entity Research Program" => %{creature_essence: 30, plastic_sheet: 10},
  "L6 Computational Threshold" => %{computer: 10, motor_housing: 10},
  "L6 Nuclear Clearance Protocol" => %{composite: 15, enriched_uranium: 5},
  "L7 Paranatural Convergence" => %{supercomputer: 5, advanced_composite: 5, nuclear_cell: 10},
  "L7 Entity Containment Mastery" => %{containment_module: 3, creature_essence: 5},
  "L8 Dimensional Mastery" => %{dimensional_core: 3, astral_lens: 3},
  "L8 Board Resonance Protocol" => %{board_resonator: 1}
}

# ── Output helpers ───────────────────────────────────────────────────────────

# Preferred display order for raw materials
raw_order = [
  :iron_ore, :copper_ore, :raw_quartz, :titanium_ore,
  :crude_oil, :raw_sulfur, :raw_uranium,
  :creature_essence, :biofuel
]

print_raw_costs = fn label, raw_costs ->
  IO.puts("  #{label}")
  total_ores = Enum.reduce(raw_costs, 0, fn {_k, v}, acc -> acc + v end)

  raw_order
  |> Enum.filter(&Map.has_key?(raw_costs, &1))
  |> Enum.each(fn item ->
    qty = Map.get(raw_costs, item)
    IO.puts("    #{String.pad_trailing(name.(item), 20)} #{qty}")
  end)

  # Any items not in raw_order (shouldn't happen, but just in case)
  raw_costs
  |> Enum.reject(fn {k, _v} -> k in raw_order end)
  |> Enum.sort_by(fn {_k, v} -> -v end)
  |> Enum.each(fn {item, qty} ->
    IO.puts("    #{String.pad_trailing(name.(item), 20)} #{qty}")
  end)

  IO.puts("    #{String.pad_trailing("── TOTAL ORES ──", 20)} #{total_ores}")
  IO.puts("")
end

print_item = fn item, qty ->
  raw = CostCalculator.resolve_bom(%{item => qty}, recipe_lookup, raw_materials)
  label = "#{name.(item)} x#{qty}"
  print_raw_costs.(label, raw)
end

print_building = fn building ->
  case Map.get(building_costs, building) do
    nil ->
      bname = Map.get(building_names, building, Atom.to_string(building))
      IO.puts("  #{bname}: FREE (no construction cost)")
      IO.puts("")

    cost_map ->
      bname = Map.get(building_names, building, Atom.to_string(building))
      tier = Map.get(building_tiers, building, "?")
      raw = CostCalculator.resolve_bom(cost_map, recipe_lookup, raw_materials)

      # Show direct costs first
      direct_parts =
        cost_map
        |> Enum.sort_by(fn {_k, v} -> -v end)
        |> Enum.map(fn {item, qty} -> "#{qty}x #{name.(item)}" end)
        |> Enum.join(", ")

      IO.puts("  [Tier #{tier}] #{bname}")
      IO.puts("    Direct: #{direct_parts}")
      IO.puts("    Raw ore breakdown:")

      total_ores = Enum.reduce(raw, 0, fn {_k, v}, acc -> acc + v end)

      raw_order
      |> Enum.filter(&Map.has_key?(raw, &1))
      |> Enum.each(fn item ->
        qty = Map.get(raw, item)
        IO.puts("      #{String.pad_trailing(name.(item), 20)} #{qty}")
      end)

      raw
      |> Enum.reject(fn {k, _v} -> k in raw_order end)
      |> Enum.sort_by(fn {_k, v} -> -v end)
      |> Enum.each(fn {item, qty} ->
        IO.puts("      #{String.pad_trailing(name.(item), 20)} #{qty}")
      end)

      IO.puts("      #{String.pad_trailing("── TOTAL ORES ──", 20)} #{total_ores}")
      IO.puts("")
  end
end

# ── World supply estimation ──────────────────────────────────────────────────
#
# Based on world_gen.ex parameters:
#   30 faces x 64x64 = 122,880 tiles
#   4x4 cells per face = 16 cells per face = 480 cells total
#   Biome assigned per cell based on cell center latitude (Y coordinate)
#   Resource density per biome, resource weights per biome
#   Each deposit: 100-500 ore (average 300)
#
# Biome latitude bands (based on Y/1.309):
#   tundra:    lat > 0.6   (polar caps)
#   forest:    0.2 < lat <= 0.6
#   grassland: -0.2 < lat <= 0.2 (equatorial)
#   desert:    -0.6 < lat <= -0.2
#   volcanic:  lat <= -0.6 (south polar)
#
# The actual biome distribution depends on geometry. We estimate by
# computing expected tile counts from the latitude distribution of the
# 30-face rhombic triacontahedron's cells.

# Approximate biome tile distribution (from actual world gen with seed=42):
# These are estimated proportions based on the geometry.
# Each biome's cell count depends on how many of the 480 cells fall in each
# latitude band. We use rough proportions from the sphere geometry:
#   ~15% tundra, ~25% forest, ~30% grassland, ~20% desert, ~10% volcanic
biome_tile_fractions = %{
  tundra: 0.15,
  forest: 0.25,
  grassland: 0.30,
  desert: 0.20,
  volcanic: 0.10
}

total_tiles = 122_880
base_density = 0.08
avg_deposit = 300  # average of 100..500

biome_density_multipliers = %{
  volcanic: 1.5,
  desert: 1.2,
  grassland: 1.0,
  forest: 0.8,
  tundra: 0.6
}

biome_resource_weights = %{
  volcanic: %{iron: 0.27, copper: 0.10, titanium: 0.23, sulfur: 0.18, oil: 0.05, quartz: 0.10, uranium: 0.07},
  desert: %{iron: 0.25, copper: 0.15, oil: 0.25, sulfur: 0.15, titanium: 0.10, quartz: 0.10},
  grassland: %{iron: 0.25, copper: 0.25, quartz: 0.15, titanium: 0.10, oil: 0.15, sulfur: 0.10},
  forest: %{copper: 0.25, quartz: 0.25, iron: 0.15, titanium: 0.10, oil: 0.10, sulfur: 0.15},
  tundra: %{quartz: 0.28, copper: 0.24, iron: 0.15, titanium: 0.13, oil: 0.05, sulfur: 0.10, uranium: 0.05}
}

# Map resource types to raw ore names used in recipes
resource_to_ore = %{
  iron: :iron_ore,
  copper: :copper_ore,
  quartz: :raw_quartz,
  titanium: :titanium_ore,
  oil: :crude_oil,
  sulfur: :raw_sulfur,
  uranium: :raw_uranium
}

# Calculate expected total ore supply across the entire world
world_supply =
  biome_tile_fractions
  |> Enum.reduce(%{}, fn {biome, tile_fraction}, acc ->
    tiles_in_biome = total_tiles * tile_fraction
    density = base_density * Map.get(biome_density_multipliers, biome, 1.0)
    deposits_in_biome = tiles_in_biome * density
    weights = Map.get(biome_resource_weights, biome, %{})

    Enum.reduce(weights, acc, fn {resource, weight}, acc ->
      ore = Map.get(resource_to_ore, resource)
      amount = deposits_in_biome * weight * avg_deposit
      Map.update(acc, ore, amount, &(&1 + amount))
    end)
  end)
  |> Map.new(fn {k, v} -> {k, round(v)} end)

# ── Parse CLI args and run ───────────────────────────────────────────────────

args = System.argv()

cond do
  "--supply" in args ->
    IO.puts("=" |> String.duplicate(70))
    IO.puts("  WORLD RESOURCE SUPPLY vs DEMAND ANALYSIS")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    # Full progression demand (1x every building + all research)
    all_building_bom =
      Enum.reduce(building_costs, %{}, fn {_b, cost}, acc ->
        case cost do
          nil -> acc
          cm -> CostCalculator.merge_costs(acc, cm)
        end
      end)

    all_research_bom =
      Enum.reduce(research_costs, %{}, fn {_l, bom}, acc ->
        CostCalculator.merge_costs(acc, bom)
      end)

    building_demand = CostCalculator.resolve_bom(all_building_bom, recipe_lookup, raw_materials)
    research_demand = CostCalculator.resolve_bom(all_research_bom, recipe_lookup, raw_materials)
    total_demand = CostCalculator.merge_costs(building_demand, research_demand)

    IO.puts("── Estimated World Supply (#{total_tiles} tiles) ──")
    IO.puts("")
    IO.puts("  Biome distribution: tundra 15%, forest 25%, grassland 30%, desert 20%, volcanic 10%")
    IO.puts("  Resource density: #{base_density} base (x0.6 tundra .. x1.5 volcanic)")
    IO.puts("  Deposit size: 100-500 ore (avg #{avg_deposit})")
    IO.puts("")

    total_supply = Enum.reduce(world_supply, 0, fn {_k, v}, acc -> acc + v end)
    total_deposits = round(total_supply / avg_deposit)

    IO.puts("  Total deposits: ~#{total_deposits}")
    IO.puts("  Total ore:      ~#{total_supply}")
    IO.puts("")

    IO.puts(String.pad_trailing("  Resource", 24) <>
            String.pad_leading("Supply", 10) <>
            String.pad_leading("Demand", 10) <>
            String.pad_leading("Ratio", 10) <>
            String.pad_leading("% Used", 10))
    IO.puts("  " <> String.duplicate("-", 62))

    raw_order
    |> Enum.filter(fn ore -> Map.has_key?(world_supply, ore) end)
    |> Enum.each(fn ore ->
      supply = Map.get(world_supply, ore, 0)
      demand = Map.get(total_demand, ore, 0)

      {ratio_str, pct_str} =
        if demand == 0 do
          {"∞", "0.0%"}
        else
          ratio = supply / demand
          pct = demand / supply * 100
          {"#{Float.round(ratio, 1)}x", "#{Float.round(pct, 2)}%"}
        end

      IO.puts(
        String.pad_trailing("  #{name.(ore)}", 24) <>
        String.pad_leading("#{supply}", 10) <>
        String.pad_leading("#{demand}", 10) <>
        String.pad_leading(ratio_str, 10) <>
        String.pad_leading(pct_str, 10)
      )
    end)

    # Non-minable resources (creature_essence, biofuel)
    IO.puts("")
    IO.puts("  Non-minable resources needed:")
    [:creature_essence, :biofuel]
    |> Enum.filter(&Map.has_key?(total_demand, &1))
    |> Enum.each(fn item ->
      demand = Map.get(total_demand, item, 0)
      IO.puts("    #{String.pad_trailing(name.(item), 20)} #{demand} (from creatures/gathering)")
    end)

    IO.puts("")
    IO.puts("-" |> String.duplicate(70))
    IO.puts("  CONTEXT: Demand assumes building 1x of EVERY building + ALL research.")
    IO.puts("  A real player builds many conveyors, miners, smelters, etc.")
    IO.puts("")

    # Estimate a "realistic" factory: multiples of production buildings
    realistic = %{
      # Logistics (many conveyors, some splitters/mergers)
      conveyor: 80, conveyor_mk2: 40, conveyor_mk3: 20,
      crossover: 5, underground_conduit: 5,
      splitter: 10, merger: 10, balancer: 5,
      # Production chain
      miner: 15, smelter: 10, assembler: 6, refinery: 4,
      advanced_smelter: 3, advanced_assembler: 3,
      fabrication_plant: 2, particle_collider: 2, nuclear_refinery: 1,
      # Endgame
      paranatural_synthesizer: 1, dimensional_stabilizer: 1,
      astral_projection_chamber: 1, board_interface: 1,
      # Support
      submission_terminal: 2, gathering_post: 4,
      storage_container: 10, claim_beacon: 2, trade_terminal: 1,
      # Defense & power
      containment_trap: 5, purification_beacon: 3, defense_turret: 6,
      shadow_panel: 4, lamp: 6,
      bio_generator: 3, substation: 3, transfer_station: 2,
      essence_extractor: 2
    }

    realistic_bom =
      Enum.reduce(realistic, %{}, fn {building, count}, acc ->
        case Map.get(building_costs, building) do
          nil -> acc
          cost_map ->
            scaled = Map.new(cost_map, fn {k, v} -> {k, v * count} end)
            CostCalculator.merge_costs(acc, scaled)
        end
      end)

    realistic_building_demand = CostCalculator.resolve_bom(realistic_bom, recipe_lookup, raw_materials)
    realistic_total = CostCalculator.merge_costs(realistic_building_demand, research_demand)

    IO.puts("── Realistic Single-Player Estimate ──")
    IO.puts("  (#{Enum.reduce(realistic, 0, fn {_, c}, a -> a + c end)} buildings + all research)")
    IO.puts("")

    IO.puts(String.pad_trailing("  Resource", 24) <>
            String.pad_leading("Supply", 10) <>
            String.pad_leading("Demand", 10) <>
            String.pad_leading("Ratio", 10) <>
            String.pad_leading("% Used", 10))
    IO.puts("  " <> String.duplicate("-", 62))

    raw_order
    |> Enum.filter(fn ore -> Map.has_key?(world_supply, ore) end)
    |> Enum.each(fn ore ->
      supply = Map.get(world_supply, ore, 0)
      demand = Map.get(realistic_total, ore, 0)

      {ratio_str, pct_str} =
        if demand == 0 do
          {"∞", "0.0%"}
        else
          ratio = supply / demand
          pct = demand / supply * 100
          {"#{Float.round(ratio, 1)}x", "#{Float.round(pct, 2)}%"}
        end

      IO.puts(
        String.pad_trailing("  #{name.(ore)}", 24) <>
        String.pad_leading("#{supply}", 10) <>
        String.pad_leading("#{demand}", 10) <>
        String.pad_leading(ratio_str, 10) <>
        String.pad_leading(pct_str, 10)
      )
    end)

    total_realistic_demand = Enum.reduce(realistic_total, 0, fn {_k, v}, acc -> acc + v end)
    IO.puts("")
    IO.puts("  Total ores needed: #{total_realistic_demand}")
    IO.puts("  Total world supply: ~#{total_supply}")
    IO.puts("  Overall ratio: #{Float.round(total_supply / total_realistic_demand, 1)}x")
    IO.puts("")

    # How many full playthroughs the world can support
    max_players =
      raw_order
      |> Enum.filter(fn ore -> Map.has_key?(world_supply, ore) end)
      |> Enum.map(fn ore ->
        supply = Map.get(world_supply, ore, 0)
        demand = Map.get(realistic_total, ore, 0)
        if demand > 0, do: supply / demand, else: 99999
      end)
      |> Enum.min()

    IO.puts("  Bottleneck resource limits world to ~#{Float.round(max_players, 1)} concurrent full playthroughs")
    IO.puts("  (before territory contention for that resource)")

  "--all" in args ->
    IO.puts("=" |> String.duplicate(70))
    IO.puts("  TOTAL RAW COST OF ALL ITEMS")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    all_items = Map.keys(recipe_lookup) |> Enum.sort()

    Enum.each(all_items, fn item ->
      print_item.(item, 1)
    end)

    IO.puts("=" |> String.duplicate(70))
    IO.puts("  TOTAL RAW COST OF ALL BUILDINGS")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    building_costs
    |> Enum.sort_by(fn {b, _} -> Map.get(building_tiers, b, 0) end)
    |> Enum.each(fn {building, _} -> print_building.(building) end)

  "--research" in args ->
    IO.puts("=" |> String.duplicate(70))
    IO.puts("  RESEARCH (CASE FILE) RAW ORE COSTS")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    grand_total =
      research_costs
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {label, bom}, grand ->
        raw = CostCalculator.resolve_bom(bom, recipe_lookup, raw_materials)
        print_raw_costs.(label, raw)
        CostCalculator.merge_costs(grand, raw)
      end)

    IO.puts("-" |> String.duplicate(70))
    print_raw_costs.("GRAND TOTAL (all research)", grand_total)

  "--everything" in args ->
    IO.puts("=" |> String.duplicate(70))
    IO.puts("  COMPLETE PROGRESSION: BUILDINGS + RESEARCH RAW ORE COSTS")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    # Combine all building costs + all research costs
    all_bom =
      Enum.reduce(building_costs, %{}, fn {_building, cost_map}, acc ->
        case cost_map do
          nil -> acc
          cm -> CostCalculator.merge_costs(acc, cm)
        end
      end)

    all_research_bom =
      Enum.reduce(research_costs, %{}, fn {_label, bom}, acc ->
        CostCalculator.merge_costs(acc, bom)
      end)

    IO.puts("── Buildings (1 of each) ──")
    IO.puts("")
    building_raw = CostCalculator.resolve_bom(all_bom, recipe_lookup, raw_materials)
    print_raw_costs.("All buildings combined", building_raw)

    IO.puts("── Research (all case files) ──")
    IO.puts("")
    research_raw = CostCalculator.resolve_bom(all_research_bom, recipe_lookup, raw_materials)
    print_raw_costs.("All research combined", research_raw)

    IO.puts("-" |> String.duplicate(70))
    combined = CostCalculator.merge_costs(building_raw, research_raw)
    print_raw_costs.("GRAND TOTAL (buildings + research)", combined)

  true ->
    # Check for specific flags
    item_flag = Enum.find_index(args, &(&1 == "--item"))
    building_flag = Enum.find_index(args, &(&1 == "--building"))
    tier_flag = Enum.find_index(args, &(&1 == "--tier"))

    cond do
      item_flag != nil ->
        item_name = Enum.at(args, item_flag + 1) |> String.to_atom()
        IO.puts("=" |> String.duplicate(70))
        IO.puts("  RAW COST: #{name.(item_name)}")
        IO.puts("=" |> String.duplicate(70))
        IO.puts("")
        print_item.(item_name, 1)

      building_flag != nil ->
        building_name = Enum.at(args, building_flag + 1) |> String.to_atom()
        IO.puts("=" |> String.duplicate(70))
        IO.puts("  RAW COST: Building #{Map.get(building_names, building_name, building_name)}")
        IO.puts("=" |> String.duplicate(70))
        IO.puts("")
        print_building.(building_name)

      tier_flag != nil ->
        min_tier = Enum.at(args, tier_flag + 1) |> String.to_integer()
        IO.puts("=" |> String.duplicate(70))
        IO.puts("  RAW COSTS: TIER #{min_tier}+ BUILDINGS")
        IO.puts("=" |> String.duplicate(70))
        IO.puts("")

        building_costs
        |> Enum.filter(fn {b, _} -> Map.get(building_tiers, b, 0) >= min_tier end)
        |> Enum.sort_by(fn {b, _} -> Map.get(building_tiers, b, 0) end)
        |> Enum.each(fn {building, _} -> print_building.(building) end)

      true ->
        # Default: show endgame items (Tier 7-8 buildings + endgame items)
        IO.puts("=" |> String.duplicate(70))
        IO.puts("  ENDGAME RAW ORE COSTS (Tier 7-8)")
        IO.puts("=" |> String.duplicate(70))
        IO.puts("")

        IO.puts("── Endgame Items ──")
        IO.puts("")

        endgame_items = [
          :containment_module, :dimensional_core, :astral_lens, :board_resonator,
          :supercomputer, :advanced_composite, :nuclear_cell
        ]

        Enum.each(endgame_items, fn item -> print_item.(item, 1) end)

        IO.puts("── Endgame Buildings ──")
        IO.puts("")

        endgame_buildings = [
          :dimensional_stabilizer, :paranatural_synthesizer,
          :astral_projection_chamber, :board_interface
        ]

        Enum.each(endgame_buildings, fn b -> print_building.(b) end)

        # Grand total for 1x of each T7-8 building
        IO.puts("-" |> String.duplicate(70))
        IO.puts("  GRAND TOTAL: 1x of each Tier 7-8 building")

        grand =
          endgame_buildings
          |> Enum.map(&Map.get(building_costs, &1, %{}))
          |> Enum.reduce(%{}, &CostCalculator.merge_costs/2)
          |> then(&CostCalculator.resolve_bom(&1, recipe_lookup, raw_materials))

        print_raw_costs.("Combined", grand)

        # Also show research costs to unlock T7-8
        IO.puts("-" |> String.duplicate(70))
        IO.puts("  RESEARCH COST: Unlock Tier 7 + 8 case files")

        t78_research =
          research_costs
          |> Enum.filter(fn {label, _} -> String.starts_with?(label, "L7") or String.starts_with?(label, "L8") end)
          |> Enum.reduce(%{}, fn {_label, bom}, acc -> CostCalculator.merge_costs(acc, bom) end)
          |> then(&CostCalculator.resolve_bom(&1, recipe_lookup, raw_materials))

        print_raw_costs.("T7+T8 research", t78_research)

        IO.puts("-" |> String.duplicate(70))
        combined = CostCalculator.merge_costs(grand, t78_research)
        print_raw_costs.("GRAND TOTAL (buildings + research for T7-8)", combined)
    end
end
