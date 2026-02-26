# scripts/calculate_costs.exs
#
# Calculates the total raw-resource cost of constructing endgame items/buildings.
# Recursively resolves every intermediate recipe down to raw ores + creature_essence.
#
# All recipe, building cost, research, and display name data is loaded from the
# actual game modules — no hardcoded copies.
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

alias Spheric.Game.{Behaviors, ConstructionCosts, Research, Lore, WorldGen}

# ── Build recipe lookup from game behavior modules ─────────────────────────
#
# Format: output_atom => {[{input, qty}, ...], output_qty}
# Aggregates recipes from every production building.

recipe_modules = [
  Behaviors.Smelter,
  Behaviors.Refinery,
  Behaviors.NuclearRefinery,
  Behaviors.Assembler,
  Behaviors.Mixer,
  Behaviors.Freezer,
  Behaviors.AdvancedAssembler,
  Behaviors.AdvancedSmelter,
  Behaviors.FabricationPlant,
  Behaviors.ParticleCollider,
  Behaviors.ParanaturalSynthesizer,
  Behaviors.BoardInterface
]

recipe_lookup =
  recipe_modules
  |> Enum.flat_map(& &1.recipes())
  |> Enum.reduce(%{}, fn recipe, acc ->
    # Later recipes (higher-tier buildings) override earlier ones for the same output
    case recipe.output do
      {out_item, out_qty} ->
        Map.put(acc, out_item, {recipe.inputs, out_qty})

      [{out_a, out_qty_a}, {out_b, out_qty_b}] ->
        # Dual-output recipe: register both outputs with the same inputs
        acc
        |> Map.put(out_a, {recipe.inputs, out_qty_a})
        |> Map.put(out_b, {recipe.inputs, out_qty_b})
    end
  end)

# Raw materials (no recipe to make them — they are mined or gathered)
raw_materials = MapSet.new([
  :iron_ore, :copper_ore, :raw_quartz, :titanium_ore,
  :crude_oil, :raw_sulfur, :raw_uranium,
  :creature_essence, :biofuel, :hiss_residue
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

# ── Display names (from game Lore module) ──────────────────────────────────

name = fn item -> Lore.display_name(item) end

# ── Building data (from game ConstructionCosts module) ─────────────────────

building_costs = ConstructionCosts.all_costs()
building_tiers = ConstructionCosts.all_tiers()

building_names =
  Map.new(Map.keys(building_costs) ++ Map.keys(building_tiers), fn b ->
    {b, Lore.display_name(b)}
  end)

# ── Research case file costs (from game Research module) ───────────────────

research_costs =
  Research.case_files()
  |> Map.new(fn cf -> {"L#{cf.clearance} #{cf.name}", cf.requirements} end)

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

# ── World supply estimation (from WorldGen module) ──────────────────────────
#
# All parameters pulled from WorldGen: biome weights, density multipliers,
# deposit size range, subdivisions, etc.
#
# Biome tile fractions are estimated from the rhombic triacontahedron geometry:
#   ~15% tundra, ~25% forest, ~30% grassland, ~20% desert, ~10% volcanic
# (actual distribution depends on latitude bands of the 30 faces' 4x4 cells)

biome_tile_fractions = %{
  tundra: 0.15,
  forest: 0.25,
  grassland: 0.30,
  desert: 0.20,
  volcanic: 0.10
}

subdivisions = WorldGen.subdivisions()
total_tiles = 30 * subdivisions * subdivisions
amount_range = WorldGen.resource_amount_range()
avg_deposit = div(Enum.min(amount_range) + Enum.max(amount_range), 2)

biome_density_multipliers = WorldGen.biome_density_multipliers()

# WorldGen returns [{resource, weight}] lists; convert to maps for easier lookup
biome_resource_weights =
  WorldGen.biome_resource_weights()
  |> Map.new(fn {biome, weight_list} -> {biome, Map.new(weight_list)} end)

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

# Estimate base density from vein parameters (approximate effective deposit rate)
base_density = 0.08

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
    density_range = biome_density_multipliers |> Map.values() |> Enum.sort()
    IO.puts("  Resource density: #{base_density} base (x#{List.first(density_range)} .. x#{List.last(density_range)})")
    IO.puts("  Deposit size: #{Enum.min(amount_range)}..#{Enum.max(amount_range)} ore (avg #{avg_deposit})")
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
      advanced_smelter: 3, advanced_assembler: 3, freezer: 1,
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
