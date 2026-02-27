# scripts/fuel_efficiency.exs
#
# Calculates the net power efficiency of each fuel type by comparing the
# energy produced when burned in a Bio Generator against the energy consumed
# by the production chain to manufacture one unit of that fuel.
#
# All values (recipes, power draw, fuel durations) are imported from the
# actual game modules — no hardcoded copies.
#
# Usage:
#   mix run scripts/fuel_efficiency.exs

alias Spheric.Game.{ConstructionCosts, Behaviors}

# ── Fuel durations (ticks per unit) from BioGenerator ────────────────────────

fuel_durations = %{
  biofuel: Behaviors.BioGenerator.fuel_duration(:biofuel),
  refined_fuel: Behaviors.BioGenerator.fuel_duration(:refined_fuel),
  catalysed_fuel: Behaviors.BioGenerator.fuel_duration(:catalysed_fuel),
  unstable_fuel: Behaviors.BioGenerator.fuel_duration(:unstable_fuel),
  stable_fuel: Behaviors.BioGenerator.fuel_duration(:stable_fuel)
}

# Generator output is constant 20W regardless of fuel type.
generator_output_w = ConstructionCosts.power_output(:bio_generator)

# ── Recipe lookup from production modules ────────────────────────────────────
#
# Each recipe: %{inputs: [...], output: {item, qty}}
# We also need the building type + its tick rate to compute production power cost.

# Map building type → {module, tick rate, power draw}
production_buildings = %{
  gathering_post: {Behaviors.GatheringPost, 20, ConstructionCosts.power_draw(:gathering_post)},
  miner: {Behaviors.Miner, 5, ConstructionCosts.power_draw(:miner)},
  smelter: {Behaviors.Smelter, 10, ConstructionCosts.power_draw(:smelter)},
  refinery: {Behaviors.Refinery, 12, ConstructionCosts.power_draw(:refinery)},
  mixer: {Behaviors.Mixer, 15, ConstructionCosts.power_draw(:mixer)}
}

# Miner produces raw ores — model as pseudo-recipes with rate=5, output qty=1
miner_recipes =
  [:iron_ore, :copper_ore, :titanium_ore, :raw_quartz, :crude_oil, :raw_sulfur, :raw_uranium, :ice]
  |> Enum.map(fn ore ->
    {ore, {:miner, %{inputs: [], output: {ore, 1}}}}
  end)

# Build a recipe lookup: output_item → {building_type, recipe}
recipe_lookup =
  [
    {:smelter, Behaviors.Smelter.recipes()},
    {:refinery, Behaviors.Refinery.recipes()},
    {:mixer, Behaviors.Mixer.recipes()}
  ]
  |> Enum.flat_map(fn {building_type, recipes} ->
    Enum.map(recipes, fn recipe ->
      {out_item, _out_qty} = recipe.output
      {out_item, {building_type, recipe}}
    end)
  end)
  |> Kernel.++(miner_recipes)
  |> Map.new()

# ── Recursive energy cost calculator ────────────────────────────────────────
#
# For each fuel type, walk the recipe tree and sum up the total Watt-ticks
# consumed by production buildings to produce one unit.
#
# Energy cost of one unit = (building_power_draw × tick_rate) / output_qty
#                         + sum of (energy cost of each input × input_qty) / output_qty

defmodule FuelCalc do
  @doc """
  Recursively compute the total energy cost (in Watt-ticks) to produce one
  unit of `item`, given the recipe lookup and building info maps.
  """
  def energy_cost(item, recipe_lookup, production_buildings, memo \\ %{})

  def energy_cost(item, recipe_lookup, production_buildings, memo) do
    if Map.has_key?(memo, item) do
      {memo[item], memo}
    else
      case Map.get(recipe_lookup, item) do
        nil ->
          # Raw resource or biofuel (from gathering post) — check if it has
          # a dedicated building with power draw
          cost =
            case item do
              :biofuel ->
                {_mod, rate, draw} = production_buildings[:gathering_post]
                # Gathering post produces 1 biofuel per cycle
                draw * rate

              _ ->
                # Raw ores, creature drops — no power cost to acquire
                0
            end

          {cost, Map.put(memo, item, cost)}

        {building_type, recipe} ->
          {_out_item, out_qty} = recipe.output
          {_mod, rate, draw} = production_buildings[building_type]

          # Energy to run this building for one recipe cycle
          building_energy = draw * rate

          # Recursively compute energy cost of all inputs
          {input_energy, memo} =
            Enum.reduce(recipe.inputs, {0, memo}, fn {inp_item, inp_qty}, {acc, m} ->
              {unit_cost, m} = energy_cost(inp_item, recipe_lookup, production_buildings, m)
              {acc + unit_cost * inp_qty, m}
            end)

          # Total energy per output unit
          cost_per_unit = (building_energy + input_energy) / out_qty

          {cost_per_unit, Map.put(memo, item, cost_per_unit)}
      end
    end
  end
end

# ── Compute and display ─────────────────────────────────────────────────────

biofuel_baseline = generator_output_w * fuel_durations[:biofuel]

IO.puts("╔══════════════════════════════════════════════════════════════════════════════════╗")
IO.puts("║                         FUEL POWER EFFICIENCY ANALYSIS                          ║")
IO.puts("╠══════════════════════════════════════════════════════════════════════════════════╣")
IO.puts("║  Generator output: #{generator_output_w}W constant for all fuel types#{String.duplicate(" ", 30)}║")
IO.puts("║  Biofuel baseline: #{biofuel_baseline} Wt per unit (free to produce)#{String.duplicate(" ", 28)}║")
IO.puts("╚══════════════════════════════════════════════════════════════════════════════════╝")
IO.puts("")

fuels = [:biofuel, :catalysed_fuel, :refined_fuel, :unstable_fuel, :stable_fuel]

results =
  Enum.reduce(fuels, {[], %{}}, fn fuel, {rows, memo} ->
    {cost_wt, memo} = FuelCalc.energy_cost(fuel, recipe_lookup, production_buildings, memo)
    duration = fuel_durations[fuel]

    # Energy produced = generator output × burn duration (Watt-ticks)
    energy_produced = generator_output_w * duration

    # Net energy = produced - cost to manufacture
    net_energy = energy_produced - cost_wt

    # Compare against biofuel: extra energy gained vs energy spent upgrading
    extra_vs_biofuel = energy_produced - biofuel_baseline
    upgrade_ratio = if cost_wt > 0, do: extra_vs_biofuel / cost_wt, else: :infinity

    {[{fuel, duration, cost_wt, energy_produced, net_energy, extra_vs_biofuel, upgrade_ratio} | rows], memo}
  end)
  |> elem(0)
  |> Enum.reverse()

# Header
IO.puts(
  String.pad_trailing("Fuel Type", 18) <>
    String.pad_leading("Duration", 10) <>
    String.pad_leading("Prod Cost", 11) <>
    String.pad_leading("Energy Out", 12) <>
    String.pad_leading("Net Energy", 12) <>
    String.pad_leading("vs Biofuel", 12) <>
    String.pad_leading("Upgrade ROI", 13)
)

IO.puts(
  String.pad_trailing("", 18, "─") <>
    String.pad_leading("", 10, "─") <>
    String.pad_leading("", 11, "─") <>
    String.pad_leading("", 12, "─") <>
    String.pad_leading("", 12, "─") <>
    String.pad_leading("", 12, "─") <>
    String.pad_leading("", 13, "─")
)

format_wt = fn wt ->
  cond do
    wt == 0 -> "0 Wt"
    wt == round(wt) -> "#{round(wt)} Wt"
    true -> "#{Float.round(wt * 1.0, 1)} Wt"
  end
end

Enum.each(results, fn {fuel, duration, cost_wt, energy_out, net, extra, upgrade_roi} ->
  name =
    fuel
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")

  extra_str =
    cond do
      fuel == :biofuel -> "baseline"
      extra > 0 -> "+#{format_wt.(extra)}"
      extra == 0 -> "±0 Wt"
      true -> "#{round(extra)} Wt"
    end

  roi_str =
    case upgrade_roi do
      :infinity -> "(baseline)"
      r when r < 0 -> "#{Float.round(r, 2)}x LOSS"
      r -> "#{Float.round(r, 2)}x"
    end

  IO.puts(
    String.pad_trailing(name, 18) <>
      String.pad_leading("#{duration} ticks", 10) <>
      String.pad_leading(format_wt.(cost_wt), 11) <>
      String.pad_leading("#{energy_out} Wt", 12) <>
      String.pad_leading(format_wt.(net), 12) <>
      String.pad_leading(extra_str, 12) <>
      String.pad_leading(roi_str, 13)
  )
end)

IO.puts("")
IO.puts("Upgrade ROI = (energy out − biofuel baseline) / production cost")
IO.puts("  >1x = worth upgrading, <1x = biofuel would have been better")

# ── Recipe chain breakdown ──────────────────────────────────────────────────

IO.puts("")
IO.puts("╔══════════════════════════════════════════════════════════════════════════╗")
IO.puts("║                       PRODUCTION CHAIN BREAKDOWN                        ║")
IO.puts("╚══════════════════════════════════════════════════════════════════════════╝")

defmodule FuelChain do
  @doc "Print the recipe chain for a fuel type with indentation."
  def print_chain(item, recipe_lookup, production_buildings, indent \\ 0) do
    prefix = String.duplicate("  ", indent)

    case Map.get(recipe_lookup, item) do
      nil ->
        case item do
          :biofuel ->
            {_mod, rate, draw} = production_buildings[:gathering_post]
            IO.puts("#{prefix}└─ biofuel: Gathering Post (#{rate} ticks, #{draw}W draw = #{draw * rate} Wt)")

          _ ->
            IO.puts("#{prefix}└─ #{item}: raw resource (0 Wt)")
        end

      {building_type, recipe} ->
        {_out_item, out_qty} = recipe.output
        {_mod, rate, draw} = production_buildings[building_type]
        building_name = building_type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
        inputs_str = Enum.map_join(recipe.inputs, " + ", fn {i, q} -> "#{q}× #{i}" end)

        IO.puts(
          "#{prefix}└─ #{item} (×#{out_qty}): #{building_name} [#{inputs_str}] " <>
            "(#{rate} ticks, #{draw}W = #{draw * rate} Wt/cycle)"
        )

        Enum.each(recipe.inputs, fn {inp_item, _qty} ->
          print_chain(inp_item, recipe_lookup, production_buildings, indent + 1)
        end)
    end
  end
end

Enum.each(fuels, fn fuel ->
  name =
    fuel
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")

  IO.puts("")
  IO.puts("── #{name} ──")
  FuelChain.print_chain(fuel, recipe_lookup, production_buildings)
end)

IO.puts("")
IO.puts("Units: Wt = Watt-ticks (power draw × ticks). Ratio = energy out / energy in.")
IO.puts("Higher ratio = more efficient fuel. Net energy = surplus power after production costs.")
