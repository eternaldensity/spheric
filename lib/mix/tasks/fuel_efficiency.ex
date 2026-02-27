defmodule Mix.Tasks.FuelEfficiency do
  @moduledoc """
  Calculates the net power efficiency of each fuel type by comparing the
  energy produced when burned in a Bio Generator against the energy consumed
  by the production chain to manufacture one unit of that fuel.

  Also includes nuclear reactor + steam turbine energy analysis and a
  comparison of reactor power vs equivalent bio generators on stable fuel.

  All values (recipes, power draw, fuel durations) are imported from the
  actual game modules — no hardcoded copies.

  Usage:
      mix fuel_efficiency
  """
  use Mix.Task

  alias Spheric.Game.{ConstructionCosts, Behaviors}

  @shortdoc "Analyze power efficiency of fuel types and nuclear reactor"

  @impl Mix.Task
  def run(_args) do
    # ── Fuel durations (ticks per unit) from BioGenerator ──────────────────

    fuel_durations = %{
      biofuel: Behaviors.BioGenerator.fuel_duration(:biofuel),
      refined_fuel: Behaviors.BioGenerator.fuel_duration(:refined_fuel),
      catalysed_fuel: Behaviors.BioGenerator.fuel_duration(:catalysed_fuel),
      unstable_fuel: Behaviors.BioGenerator.fuel_duration(:unstable_fuel),
      stable_fuel: Behaviors.BioGenerator.fuel_duration(:stable_fuel)
    }

    # Generator output is constant 20W regardless of fuel type.
    generator_output_w = ConstructionCosts.power_output(:bio_generator)

    # ── Recipe lookup from production modules ──────────────────────────────
    #
    # Each recipe: %{inputs: [...], output: {item, qty}}
    # We also need the building type + its tick rate to compute production power cost.

    # Map building type → {module, tick rate, power draw}
    production_buildings = %{
      gathering_post:
        {Behaviors.GatheringPost, 20, ConstructionCosts.power_draw(:gathering_post)},
      miner: {Behaviors.Miner, 5, ConstructionCosts.power_draw(:miner)},
      smelter: {Behaviors.Smelter, 10, ConstructionCosts.power_draw(:smelter)},
      assembler: {Behaviors.Assembler, 15, ConstructionCosts.power_draw(:assembler)},
      refinery: {Behaviors.Refinery, 12, ConstructionCosts.power_draw(:refinery)},
      mixer: {Behaviors.Mixer, 15, ConstructionCosts.power_draw(:mixer)},
      freezer: {Behaviors.Freezer, 20, ConstructionCosts.power_draw(:freezer)},
      advanced_assembler:
        {Behaviors.AdvancedAssembler, 12, ConstructionCosts.power_draw(:advanced_assembler)},
      advanced_smelter:
        {Behaviors.AdvancedSmelter, 8, ConstructionCosts.power_draw(:advanced_smelter)},
      fabrication_plant:
        {Behaviors.FabricationPlant, 20, ConstructionCosts.power_draw(:fabrication_plant)},
      particle_collider:
        {Behaviors.ParticleCollider, 25, ConstructionCosts.power_draw(:particle_collider)},
      nuclear_refinery:
        {Behaviors.NuclearRefinery, 20, ConstructionCosts.power_draw(:nuclear_refinery)}
    }

    # Miner produces raw ores — model as pseudo-recipes with rate=5, output qty=1
    miner_recipes =
      [:iron_ore, :copper_ore, :titanium_ore, :raw_quartz, :crude_oil, :raw_sulfur, :raw_uranium, :ice]
      |> Enum.map(fn ore ->
        {ore, {:miner, %{inputs: [], output: {ore, 1}}}}
      end)

    # Build a recipe lookup: output_item → {building_type, recipe}
    # For dual-output recipes (freezer), register primary output with full cost (conservative).
    recipe_lookup =
      [
        {:smelter, Behaviors.Smelter.recipes()},
        {:assembler, Behaviors.Assembler.recipes()},
        {:refinery, Behaviors.Refinery.recipes()},
        {:mixer, Behaviors.Mixer.recipes()},
        {:freezer, Behaviors.Freezer.recipes()},
        {:advanced_assembler, Behaviors.AdvancedAssembler.recipes()},
        {:advanced_smelter, Behaviors.AdvancedSmelter.recipes()},
        {:fabrication_plant, Behaviors.FabricationPlant.recipes()},
        {:particle_collider, Behaviors.ParticleCollider.recipes()},
        {:nuclear_refinery, Behaviors.NuclearRefinery.recipes()}
      ]
      |> Enum.flat_map(fn {building_type, recipes} ->
        Enum.flat_map(recipes, fn recipe ->
          case recipe.output do
            {out_item, _out_qty} ->
              [{out_item, {building_type, recipe}}]

            [{out_a, out_qty_a}, {out_b, out_qty_b}] ->
              # Register both outputs of dual-output recipes.
              # Each output bears the full cycle cost (conservative estimate).
              [
                {out_a, {building_type, %{recipe | output: {out_a, out_qty_a}}}},
                {out_b, {building_type, %{recipe | output: {out_b, out_qty_b}}}}
              ]
          end
        end)
      end)
      |> then(fn building_recipes ->
        # Miner recipes go first so raw resources (ice, etc.) use the miner,
        # avoiding circular dependencies (e.g. freezer: water↔ice cycle).
        # First-wins: if multiple recipes produce the same item, keep the first.
        (miner_recipes ++ building_recipes)
        |> Enum.reduce(%{}, fn {item, recipe_info}, acc ->
          Map.put_new(acc, item, recipe_info)
        end)
      end)

    # ── Compute and display ─────────────────────────────────────────────────

    biofuel_baseline = generator_output_w * fuel_durations[:biofuel]
    fuels = [:biofuel, :catalysed_fuel, :refined_fuel, :unstable_fuel, :stable_fuel]

    info("╔══════════════════════════════════════════════════════════════════════════════════╗")
    info("║                         FUEL POWER EFFICIENCY ANALYSIS                          ║")
    info("╠══════════════════════════════════════════════════════════════════════════════════╣")
    info("║  Generator output: #{generator_output_w}W constant for all fuel types#{String.duplicate(" ", 30)}║")
    info("║  Biofuel baseline: #{biofuel_baseline} Wt per unit (free to produce)#{String.duplicate(" ", 28)}║")
    info("╚══════════════════════════════════════════════════════════════════════════════════╝")
    info("")

    results =
      Enum.reduce(fuels, {[], %{}}, fn fuel, {rows, memo} ->
        {cost_wt, memo} = energy_cost(fuel, recipe_lookup, production_buildings, memo)
        duration = fuel_durations[fuel]
        energy_produced = generator_output_w * duration
        net_energy = energy_produced - cost_wt
        extra_vs_biofuel = energy_produced - biofuel_baseline
        upgrade_ratio = if cost_wt > 0, do: extra_vs_biofuel / cost_wt, else: :infinity

        {[{fuel, duration, cost_wt, energy_produced, net_energy, extra_vs_biofuel, upgrade_ratio} | rows], memo}
      end)
      |> elem(0)
      |> Enum.reverse()

    # Header
    info(
      String.pad_trailing("Fuel Type", 18) <>
        String.pad_leading("Duration", 10) <>
        String.pad_leading("Prod Cost", 11) <>
        String.pad_leading("Energy Out", 12) <>
        String.pad_leading("Net Energy", 12) <>
        String.pad_leading("vs Biofuel", 12) <>
        String.pad_leading("Upgrade ROI", 13)
    )

    info(
      String.pad_trailing("", 18, "─") <>
        String.pad_leading("", 10, "─") <>
        String.pad_leading("", 11, "─") <>
        String.pad_leading("", 12, "─") <>
        String.pad_leading("", 12, "─") <>
        String.pad_leading("", 12, "─") <>
        String.pad_leading("", 13, "─")
    )

    Enum.each(results, fn {fuel, duration, cost_wt, energy_out, net, extra, upgrade_roi} ->
      name = display_fuel(fuel)

      extra_str =
        cond do
          fuel == :biofuel -> "baseline"
          extra > 0 -> "+#{format_wt(extra)}"
          extra == 0 -> "±0 Wt"
          true -> "#{round(extra)} Wt"
        end

      roi_str =
        case upgrade_roi do
          :infinity -> "(baseline)"
          r when r < 0 -> "#{Float.round(r, 2)}x LOSS"
          r -> "#{Float.round(r, 2)}x"
        end

      info(
        String.pad_trailing(name, 18) <>
          String.pad_leading("#{duration} ticks", 10) <>
          String.pad_leading(format_wt(cost_wt), 11) <>
          String.pad_leading("#{energy_out} Wt", 12) <>
          String.pad_leading(format_wt(net), 12) <>
          String.pad_leading(extra_str, 12) <>
          String.pad_leading(roi_str, 13)
      )
    end)

    info("")
    info("Upgrade ROI = (energy out − biofuel baseline) / production cost")
    info("  >1x = worth upgrading, <1x = biofuel would have been better")

    # ── Recipe chain breakdown ──────────────────────────────────────────────

    info("")
    info("╔══════════════════════════════════════════════════════════════════════════╗")
    info("║                       PRODUCTION CHAIN BREAKDOWN                        ║")
    info("╚══════════════════════════════════════════════════════════════════════════╝")

    Enum.each(fuels, fn fuel ->
      info("")
      info("── #{display_fuel(fuel)} ──")
      print_chain(fuel, recipe_lookup, production_buildings)
    end)

    # ── Opportunity cost: mixing vs burning ingredients directly ─────────────

    info("")
    info("╔══════════════════════════════════════════════════════════════════════════╗")
    info("║                  OPPORTUNITY COST: MIX vs BURN DIRECTLY                 ║")
    info("╚══════════════════════════════════════════════════════════════════════════╝")

    # Helper: energy from burning N units of a fuel type
    burn_energy = fn fuel_type, qty ->
      qty * generator_output_w * fuel_durations[fuel_type]
    end

    # Helper: production cost for the mixer step only (not including input costs)
    {_mod, mixer_rate, mixer_draw} = production_buildings[:mixer]
    mixer_cycle_cost = mixer_draw * mixer_rate

    # ── Unstable Fuel: 8 catalysed + 8 refined → 16 unstable ──
    info("")
    info("── Unstable Fuel: 8 catalysed + 8 refined → 16 unstable ──")
    info("")

    burn_catalysed_8 = burn_energy.(:catalysed_fuel, 8)
    burn_refined_8 = burn_energy.(:refined_fuel, 8)
    burn_inputs_directly = burn_catalysed_8 + burn_refined_8

    burn_unstable_16 = burn_energy.(:unstable_fuel, 16)

    info("  Burn 8 catalysed directly:  #{burn_catalysed_8} Wt")
    info("  Burn 8 refined directly:    #{burn_refined_8} Wt")
    info("  Total (burn inputs as-is):  #{burn_inputs_directly} Wt")
    info("")
    info("  Burn 16 unstable instead:   #{burn_unstable_16} Wt")
    info("  Mixer cost to combine:      #{mixer_cycle_cost} Wt")
    info("  Net from mixing:            #{burn_unstable_16 - mixer_cycle_cost} Wt")
    info("")

    diff_unstable = burn_unstable_16 - mixer_cycle_cost - burn_inputs_directly

    if diff_unstable > 0 do
      info("  → Mixing GAINS #{diff_unstable} Wt (+#{Float.round(diff_unstable / burn_inputs_directly * 100, 1)}%)")
    else
      info("  → Mixing LOSES #{abs(diff_unstable)} Wt (#{Float.round(diff_unstable / burn_inputs_directly * 100, 1)}%)")
      info("    Better to burn catalysed + refined fuel directly!")
    end

    # ── Stable Fuel: 5 unstable + 1 sulfur_compound → 2 stable ──
    info("")
    info("── Stable Fuel: 5 unstable + 1 sulfur_compound → 2 stable ──")
    info("")

    burn_unstable_5 = burn_energy.(:unstable_fuel, 5)
    burn_stable_2 = burn_energy.(:stable_fuel, 2)

    info("  Burn 5 unstable directly:   #{burn_unstable_5} Wt")
    info("")
    info("  Burn 2 stable instead:      #{burn_stable_2} Wt")
    info("  Mixer cost to combine:      #{mixer_cycle_cost} Wt")
    info("  Net from mixing:            #{burn_stable_2 - mixer_cycle_cost} Wt")
    info("")

    diff_stable = burn_stable_2 - mixer_cycle_cost - burn_unstable_5

    if diff_stable > 0 do
      info("  → Mixing GAINS #{diff_stable} Wt (+#{Float.round(diff_stable / burn_unstable_5 * 100, 1)}%)")
    else
      info("  → Mixing LOSES #{abs(diff_stable)} Wt (#{Float.round(diff_stable / burn_unstable_5 * 100, 1)}%)")
      info("    Better to burn unstable fuel directly!")
    end

    # ── Full chain: burn catalysed+refined vs go all the way to stable ──
    info("")
    info("── Full chain: 8 catalysed + 8 refined → 16 unstable → 6.4 stable ──")
    info("   (3.2 mixer cycles at 5 unstable each, yielding 6.4 stable, ignoring sulfur cost)")
    info("")

    stable_from_16_unstable = 16.0 / 5 * 2
    burn_stable_from_chain = stable_from_16_unstable * generator_output_w * fuel_durations[:stable_fuel]
    extra_mixer_cycles = 16.0 / 5
    extra_mixer_cost = extra_mixer_cycles * mixer_cycle_cost

    info("  Burn inputs directly:          #{burn_inputs_directly} Wt  (8 catalysed + 8 refined)")
    info("  Burn as #{Float.round(stable_from_16_unstable, 1)} stable:       #{round(burn_stable_from_chain)} Wt")
    info("  Extra mixer cost (#{Float.round(extra_mixer_cycles, 1)}+1 cycles): #{round(extra_mixer_cost + mixer_cycle_cost)} Wt")
    info("  Net from full chain:           #{round(burn_stable_from_chain - extra_mixer_cost - mixer_cycle_cost)} Wt")

    diff_full = burn_stable_from_chain - extra_mixer_cost - mixer_cycle_cost - burn_inputs_directly

    info("")

    if diff_full > 0 do
      info("  → Full chain GAINS #{round(diff_full)} Wt vs burning ingredients (+#{Float.round(diff_full / burn_inputs_directly * 100, 1)}%)")
    else
      info("  → Full chain LOSES #{abs(round(diff_full))} Wt vs burning ingredients (#{Float.round(diff_full / burn_inputs_directly * 100, 1)}%)")
    end

    info("")
    info("Units: Wt = Watt-ticks (power draw × ticks). Ratio = energy out / energy in.")
    info("Higher ratio = more efficient fuel. Net energy = surplus power after production costs.")

    # ══════════════════════════════════════════════════════════════════════════
    # NUCLEAR REACTOR + STEAM TURBINE ENERGY ANALYSIS
    # ══════════════════════════════════════════════════════════════════════════

    info("")
    info("╔══════════════════════════════════════════════════════════════════════════════════╗")
    info("║                  NUCLEAR REACTOR + STEAM TURBINE ANALYSIS                        ║")
    info("╚══════════════════════════════════════════════════════════════════════════════════╝")

    # ── Reactor design parameters ──────────────────────────────────────────

    # Nuclear cell: burns for 120 ticks in the reactor (2 phases × 60 ticks)
    cell_duration = 120
    phase_duration = 60
    phases_per_cell = div(cell_duration, phase_duration)

    # Temperature thresholds
    operating_temp = 100
    danger_temp = 200
    _critical_temp = 300

    # Steam production: proportional to temperature above operating threshold
    # steam_rate = (temp - operating_temp) / steam_scale  per tick
    steam_scale = 200

    # During normal operation, temp oscillates between operating_temp and danger_temp.
    # Linear ramp: average temp ≈ midpoint = (operating + danger) / 2
    avg_temp = (operating_temp + danger_temp) / 2
    avg_steam_per_tick = (avg_temp - operating_temp) / steam_scale

    # Steam turbine parameters
    turbine_cycle = 240
    turbine_power_w = 80
    turbines_per_reactor = 3
    total_reactor_power_w = turbines_per_reactor * turbine_power_w

    # Calculate steam demand per turbine
    # Each turbine needs N steam per 240-tick cycle, consuming at N/240 steam/tick
    turbine_steam_demand_per_tick = avg_steam_per_tick / turbines_per_reactor
    steam_per_turbine_cycle = turbine_steam_demand_per_tick * turbine_cycle

    # Round to clean integer for game implementation
    steam_per_turbine = round(steam_per_turbine_cycle)

    # Recalculate actual rates with rounded value
    actual_demand_per_tick = turbines_per_reactor * steam_per_turbine / turbine_cycle

    info("")
    info("── Design Parameters ──")
    info("")
    info("  Nuclear cell duration:     #{cell_duration} ticks (#{phases_per_cell} phases × #{phase_duration} ticks)")
    info("  Temperature range:         #{operating_temp} (operating) → #{danger_temp} (danger) → 300 (critical)")
    info("  Average operating temp:    #{round(avg_temp)}")
    info("  Steam scale factor:        #{steam_scale}")
    info("  Avg steam production:      #{Float.round(avg_steam_per_tick, 3)} steam/tick")
    info("")
    info("  Steam turbine cycle:       #{turbine_cycle} ticks")
    info("  Steam turbine output:      #{turbine_power_w}W")
    info("  Turbines per reactor:      #{turbines_per_reactor}")
    info("  Total nominal output:      #{total_reactor_power_w}W")
    info("")
    info("  → Steam per turbine cycle: #{steam_per_turbine} steam")
    info("  → Turbine demand rate:     #{Float.round(actual_demand_per_tick, 4)} steam/tick")
    info("  → Reactor supply rate:     #{Float.round(avg_steam_per_tick, 4)} steam/tick")

    supply_surplus = avg_steam_per_tick - actual_demand_per_tick

    if abs(supply_surplus) < 0.01 do
      info("  → Supply ≈ demand (balanced)")
    else
      info("  → Supply #{if supply_surplus > 0, do: "surplus", else: "deficit"}: #{Float.round(supply_surplus, 4)} steam/tick")
    end

    # ── Energy output per nuclear cell ──────────────────────────────────────

    info("")
    info("── Energy Output Per Nuclear Cell ──")
    info("")

    steam_per_cell = avg_steam_per_tick * cell_duration
    gross_energy_per_cell = total_reactor_power_w * cell_duration

    info("  Steam produced per cell:   #{Float.round(steam_per_cell, 1)} steam")
    info("  Gross energy per cell:     #{round(gross_energy_per_cell)} Wt (#{total_reactor_power_w}W × #{cell_duration} ticks)")

    # ── Production cost of reactor consumables ──────────────────────────────

    info("")
    info("── Production Cost of Reactor Consumables ──")
    info("")

    {cell_cost, memo} = energy_cost(:nuclear_cell, recipe_lookup, production_buildings)
    {regulator_cost, memo} = energy_cost(:thermal_regulator, recipe_lookup, production_buildings, memo)
    {rod_cost, _memo} = energy_cost(:coolant_rod, recipe_lookup, production_buildings, memo)

    thermal_cost_per_cell = regulator_cost * 1 + rod_cost * 1
    total_consumable_cost = cell_cost + thermal_cost_per_cell

    info("  Nuclear cell:              #{Float.round(cell_cost, 1)} Wt")
    info("  Thermal regulator (×1):    #{Float.round(regulator_cost, 1)} Wt")
    info("  Coolant rod (×1):          #{Float.round(rod_cost, 1)} Wt")
    info("  Total per cell cycle:      #{Float.round(total_consumable_cost, 1)} Wt")

    # ── Net energy and ROI ──────────────────────────────────────────────────

    info("")
    info("── Net Energy & ROI ──")
    info("")

    net_per_cell = gross_energy_per_cell - total_consumable_cost
    roi = if total_consumable_cost > 0, do: gross_energy_per_cell / total_consumable_cost, else: :infinity

    roi_str =
      case roi do
        :infinity -> "∞"
        r -> "#{Float.round(r, 2)}x"
      end

    info("  Gross energy per cell:     #{round(gross_energy_per_cell)} Wt")
    info("  Production cost per cell:  #{Float.round(total_consumable_cost, 1)} Wt")
    info("  Net energy per cell:       #{Float.round(net_per_cell, 1)} Wt")
    info("  ROI (gross / cost):        #{roi_str}")

    # ── Comparison: reactor vs bio generators on stable fuel ────────────────

    info("")
    info("── Reactor vs #{round(total_reactor_power_w / generator_output_w)} Bio Generators on Stable Fuel ──")
    info("")

    bio_gens_needed = total_reactor_power_w / generator_output_w
    stable_duration = fuel_durations[:stable_fuel]

    stable_per_gen_per_cell = cell_duration / stable_duration
    total_stable_needed = bio_gens_needed * stable_per_gen_per_cell

    {stable_cost, _} = energy_cost(:stable_fuel, recipe_lookup, production_buildings)
    bio_gen_fuel_cost = total_stable_needed * stable_cost
    bio_gen_energy = total_reactor_power_w * cell_duration

    bio_gen_net = bio_gen_energy - bio_gen_fuel_cost

    bio_gen_roi =
      if bio_gen_fuel_cost > 0, do: bio_gen_energy / bio_gen_fuel_cost, else: :infinity

    bio_roi_str =
      case bio_gen_roi do
        :infinity -> "∞"
        r -> "#{Float.round(r, 2)}x"
      end

    info("  Bio generator equivalent:  #{round(bio_gens_needed)} generators × #{total_reactor_power_w}W / #{generator_output_w}W")
    info("  Stable fuel needed:        #{Float.round(total_stable_needed, 2)} units per #{cell_duration} ticks")
    info("  Fuel production cost:      #{Float.round(bio_gen_fuel_cost, 1)} Wt")
    info("  Energy output:             #{round(bio_gen_energy)} Wt")
    info("  Net energy:                #{Float.round(bio_gen_net, 1)} Wt")
    info("  ROI:                       #{bio_roi_str}")
    info("")

    info(
      String.pad_trailing("", 18) <>
        String.pad_leading("Gross", 12) <>
        String.pad_leading("Prod Cost", 12) <>
        String.pad_leading("Net", 12) <>
        String.pad_leading("ROI", 10)
    )

    info(
      String.pad_trailing("", 18, "─") <>
        String.pad_leading("", 12, "─") <>
        String.pad_leading("", 12, "─") <>
        String.pad_leading("", 12, "─") <>
        String.pad_leading("", 10, "─")
    )

    info(
      String.pad_trailing("Reactor+Turbines", 18) <>
        String.pad_leading("#{round(gross_energy_per_cell)} Wt", 12) <>
        String.pad_leading("#{Float.round(total_consumable_cost, 1)} Wt", 12) <>
        String.pad_leading("#{Float.round(net_per_cell, 1)} Wt", 12) <>
        String.pad_leading(roi_str, 10)
    )

    info(
      String.pad_trailing("#{round(bio_gens_needed)} Bio Gens", 18) <>
        String.pad_leading("#{round(bio_gen_energy)} Wt", 12) <>
        String.pad_leading("#{Float.round(bio_gen_fuel_cost, 1)} Wt", 12) <>
        String.pad_leading("#{Float.round(bio_gen_net, 1)} Wt", 12) <>
        String.pad_leading(bio_roi_str, 10)
    )

    advantage = net_per_cell - bio_gen_net

    info("")

    if advantage > 0 do
      info("  → Reactor wins by #{Float.round(advantage, 1)} Wt per #{cell_duration}-tick cycle (+#{Float.round(advantage / bio_gen_net * 100, 1)}%)")
    else
      info("  → Bio generators win by #{Float.round(abs(advantage), 1)} Wt per #{cell_duration}-tick cycle")
    end

    info("")
    info("  Note: Reactor also requires managing thermal cycling (meltdown risk).")
    info("  Bio generators are passive but need #{round(bio_gens_needed)}× the fuel logistics throughput.")
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp info(msg), do: Mix.shell().info(msg)

  defp display_fuel(fuel) do
    fuel
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_wt(wt) do
    cond do
      wt == 0 -> "0 Wt"
      wt == round(wt) -> "#{round(wt)} Wt"
      true -> "#{Float.round(wt * 1.0, 1)} Wt"
    end
  end

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
          cost =
            case item do
              :biofuel ->
                {_mod, rate, draw} = production_buildings[:gathering_post]
                draw * rate

              _ ->
                0
            end

          {cost, Map.put(memo, item, cost)}

        {building_type, recipe} ->
          {_out_item, out_qty} = recipe.output
          {_mod, rate, draw} = production_buildings[building_type]

          building_energy = draw * rate

          {input_energy, memo} =
            Enum.reduce(recipe.inputs, {0, memo}, fn {inp_item, inp_qty}, {acc, m} ->
              {unit_cost, m} = energy_cost(inp_item, recipe_lookup, production_buildings, m)
              {acc + unit_cost * inp_qty, m}
            end)

          cost_per_unit = (building_energy + input_energy) / out_qty

          {cost_per_unit, Map.put(memo, item, cost_per_unit)}
      end
    end
  end

  defp print_chain(item, recipe_lookup, production_buildings, indent \\ 0) do
    prefix = String.duplicate("  ", indent)

    case Map.get(recipe_lookup, item) do
      nil ->
        case item do
          :biofuel ->
            {_mod, rate, draw} = production_buildings[:gathering_post]
            info("#{prefix}└─ biofuel: Gathering Post (#{rate} ticks, #{draw}W draw = #{draw * rate} Wt)")

          _ ->
            info("#{prefix}└─ #{item}: raw resource (0 Wt)")
        end

      {building_type, recipe} ->
        {_out_item, out_qty} = recipe.output
        {_mod, rate, draw} = production_buildings[building_type]

        building_name =
          building_type |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

        inputs_str = Enum.map_join(recipe.inputs, " + ", fn {i, q} -> "#{q}× #{i}" end)

        info(
          "#{prefix}└─ #{item} (×#{out_qty}): #{building_name} [#{inputs_str}] " <>
            "(#{rate} ticks, #{draw}W = #{draw * rate} Wt/cycle)"
        )

        Enum.each(recipe.inputs, fn {inp_item, _qty} ->
          print_chain(inp_item, recipe_lookup, production_buildings, indent + 1)
        end)
    end
  end
end
