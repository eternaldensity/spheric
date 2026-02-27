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

# ── Opportunity cost: mixing vs burning ingredients directly ─────────────────
#
# Unstable fuel uses catalysed + refined fuel as inputs.
# Stable fuel uses unstable fuel (+ sulfur_compound) as input.
# Is it worth mixing, or better to burn the ingredients as-is?

IO.puts("")
IO.puts("╔══════════════════════════════════════════════════════════════════════════╗")
IO.puts("║                  OPPORTUNITY COST: MIX vs BURN DIRECTLY                 ║")
IO.puts("╚══════════════════════════════════════════════════════════════════════════╝")

# Helper: energy from burning N units of a fuel type
burn_energy = fn fuel_type, qty ->
  qty * generator_output_w * fuel_durations[fuel_type]
end

# Helper: production cost for the mixer step only (not including input costs)
mixer_info = production_buildings[:mixer]
{_mod, mixer_rate, mixer_draw} = mixer_info
mixer_cycle_cost = mixer_draw * mixer_rate

# ── Unstable Fuel: 8 catalysed + 8 refined → 16 unstable ──
IO.puts("")
IO.puts("── Unstable Fuel: 8 catalysed + 8 refined → 16 unstable ──")
IO.puts("")

burn_catalysed_8 = burn_energy.(:catalysed_fuel, 8)
burn_refined_8 = burn_energy.(:refined_fuel, 8)
burn_inputs_directly = burn_catalysed_8 + burn_refined_8

burn_unstable_16 = burn_energy.(:unstable_fuel, 16)

IO.puts("  Burn 8 catalysed directly:  #{burn_catalysed_8} Wt")
IO.puts("  Burn 8 refined directly:    #{burn_refined_8} Wt")
IO.puts("  Total (burn inputs as-is):  #{burn_inputs_directly} Wt")
IO.puts("")
IO.puts("  Burn 16 unstable instead:   #{burn_unstable_16} Wt")
IO.puts("  Mixer cost to combine:      #{mixer_cycle_cost} Wt")
IO.puts("  Net from mixing:            #{burn_unstable_16 - mixer_cycle_cost} Wt")
IO.puts("")

diff_unstable = burn_unstable_16 - mixer_cycle_cost - burn_inputs_directly

if diff_unstable > 0 do
  IO.puts("  → Mixing GAINS #{diff_unstable} Wt (+#{Float.round(diff_unstable / burn_inputs_directly * 100, 1)}%)")
else
  IO.puts("  → Mixing LOSES #{abs(diff_unstable)} Wt (#{Float.round(diff_unstable / burn_inputs_directly * 100, 1)}%)")
  IO.puts("    Better to burn catalysed + refined fuel directly!")
end

# ── Stable Fuel: 5 unstable + 1 sulfur_compound → 2 stable ──
# Compare: burn 5 unstable directly vs burn 2 stable
# (sulfur_compound has no fuel value, so it's "free" in opportunity terms)
IO.puts("")
IO.puts("── Stable Fuel: 5 unstable + 1 sulfur_compound → 2 stable ──")
IO.puts("")

burn_unstable_5 = burn_energy.(:unstable_fuel, 5)
burn_stable_2 = burn_energy.(:stable_fuel, 2)

IO.puts("  Burn 5 unstable directly:   #{burn_unstable_5} Wt")
IO.puts("")
IO.puts("  Burn 2 stable instead:      #{burn_stable_2} Wt")
IO.puts("  Mixer cost to combine:      #{mixer_cycle_cost} Wt")
IO.puts("  Net from mixing:            #{burn_stable_2 - mixer_cycle_cost} Wt")
IO.puts("")

diff_stable = burn_stable_2 - mixer_cycle_cost - burn_unstable_5

if diff_stable > 0 do
  IO.puts("  → Mixing GAINS #{diff_stable} Wt (+#{Float.round(diff_stable / burn_unstable_5 * 100, 1)}%)")
else
  IO.puts("  → Mixing LOSES #{abs(diff_stable)} Wt (#{Float.round(diff_stable / burn_unstable_5 * 100, 1)}%)")
  IO.puts("    Better to burn unstable fuel directly!")
end

# ── Full chain: what if you burned the original catalysed+refined instead of going all the way to stable?
IO.puts("")
IO.puts("── Full chain: 8 catalysed + 8 refined → 16 unstable → 6.4 stable ──")
IO.puts("   (3.2 mixer cycles at 5 unstable each, yielding 6.4 stable, ignoring sulfur cost)")
IO.puts("")

# 16 unstable → 16/5 = 3.2 mixer cycles → 6.4 stable
stable_from_16_unstable = 16.0 / 5 * 2
burn_stable_from_chain = stable_from_16_unstable * generator_output_w * fuel_durations[:stable_fuel]
extra_mixer_cycles = 16.0 / 5
extra_mixer_cost = extra_mixer_cycles * mixer_cycle_cost

IO.puts("  Burn inputs directly:          #{burn_inputs_directly} Wt  (8 catalysed + 8 refined)")
IO.puts("  Burn as #{Float.round(stable_from_16_unstable, 1)} stable:       #{round(burn_stable_from_chain)} Wt")
IO.puts("  Extra mixer cost (#{Float.round(extra_mixer_cycles, 1)}+1 cycles): #{round(extra_mixer_cost + mixer_cycle_cost)} Wt")
IO.puts("  Net from full chain:           #{round(burn_stable_from_chain - extra_mixer_cost - mixer_cycle_cost)} Wt")

diff_full = burn_stable_from_chain - extra_mixer_cost - mixer_cycle_cost - burn_inputs_directly

IO.puts("")

if diff_full > 0 do
  IO.puts("  → Full chain GAINS #{round(diff_full)} Wt vs burning ingredients (+#{Float.round(diff_full / burn_inputs_directly * 100, 1)}%)")
else
  IO.puts("  → Full chain LOSES #{abs(round(diff_full))} Wt vs burning ingredients (#{Float.round(diff_full / burn_inputs_directly * 100, 1)}%)")
end

IO.puts("")
IO.puts("Units: Wt = Watt-ticks (power draw × ticks). Ratio = energy out / energy in.")
IO.puts("Higher ratio = more efficient fuel. Net energy = surplus power after production costs.")
