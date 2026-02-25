defmodule Mix.Tasks.RecipeThroughput do
  @moduledoc """
  Analyzes each recipe and determines the minimum conduit tier needed
  to keep the machine fed without idle time.

  Usage:
      mix recipe_throughput
  """
  use Mix.Task

  alias Spheric.Game.{Behaviors, Lore}

  @shortdoc "Analyze conduit tier requirements for each recipe"

  # Per-tier conduit throughput (items per tick):
  #   Mk-I:   pushes every 3 ticks = 0.333 items/tick = 1.67 items/sec
  #   Mk-II:  pushes every 2 ticks = 0.500 items/tick = 2.50 items/sec
  #   Mk-III: pushes every 1 tick  = 1.000 items/tick = 5.00 items/sec
  @mk1_rate 1 / 3
  @mk2_rate 1 / 2
  @mk3_rate 1 / 1

  @buildings [
    {:smelter, Behaviors.Smelter, 10, :single},
    {:refinery, Behaviors.Refinery, 12, :single},
    {:advanced_smelter, Behaviors.AdvancedSmelter, 8, :single},
    {:nuclear_refinery, Behaviors.NuclearRefinery, 20, :single},
    {:assembler, Behaviors.Assembler, 15, :dual},
    {:advanced_assembler, Behaviors.AdvancedAssembler, 12, :dual},
    {:particle_collider, Behaviors.ParticleCollider, 25, :dual},
    {:fabrication_plant, Behaviors.FabricationPlant, 20, :triple},
    {:paranatural_synthesizer, Behaviors.ParanaturalSynthesizer, 30, :triple},
    {:board_interface, Behaviors.BoardInterface, 50, :triple}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info(header())

    for {building_type, module, rate, slot_type} <- @buildings do
      recipes = module.recipes()

      for %{inputs: inputs, output: {out_item, out_qty}} <- recipes do
        total_input_items = Enum.reduce(inputs, 0, fn {_item, qty}, acc -> acc + qty end)

        # Full cycle time = rate ticks (processing) + max(out_qty - 1, 0) drain ticks
        # Inputs can arrive during processing and drain, so the full cycle is the
        # available window for delivering items.
        cycle_ticks = rate + max(out_qty - 1, 0)
        demand_rate = total_input_items / cycle_ticks

        conduit_tier = recommend_tier(demand_rate)

        # Calculate idle time percentage if using basic Mk-I conduit
        # Mk-I delivers 1 item every 3 ticks, so delivery time = total_input_items * 3
        delivery_ticks_mk1 = total_input_items * 3
        idle_ticks = max(delivery_ticks_mk1 - cycle_ticks, 0)

        idle_pct =
          if cycle_ticks > 0,
            do: idle_ticks / (cycle_ticks + idle_ticks) * 100,
            else: 0.0

        input_str =
          inputs
          |> Enum.map(fn {item, qty} ->
            "#{qty}x #{Lore.display_name(item)}"
          end)
          |> Enum.join(" + ")

        output_str = "#{out_qty}x #{Lore.display_name(out_item)}"
        building_name = Lore.display_name(building_type)

        status =
          cond do
            demand_rate <= @mk1_rate -> "OK (Mk-I)"
            demand_rate <= @mk2_rate -> "OK (Mk-II+)"
            demand_rate <= @mk3_rate -> "OK (Mk-III)"
            true -> "BOTTLENECK"
          end

        Mix.shell().info("""
        #{building_name} (#{rate} ticks, #{slot_type})
          Recipe: #{input_str} -> #{output_str}
          Cycle: #{cycle_ticks} ticks (#{rate} process + #{max(out_qty - 1, 0)} drain)
          Total inputs needed: #{total_input_items} items
          Demand rate: #{Float.round(demand_rate, 3)} items/tick
          Min conduit: #{status}#{if idle_pct > 0, do: " | #{Float.round(idle_pct, 1)}% idle with Mk-I", else: ""}
          Recommendation: #{conduit_tier}
        """)
      end
    end

    Mix.shell().info(summary())
  end

  defp recommend_tier(demand_rate) do
    cond do
      # Mk-I sustains 0.333 items/tick — sufficient for low-demand recipes
      demand_rate <= @mk1_rate ->
        "Conduit Mk-I is sufficient"

      # Mk-II sustains 0.5 items/tick
      demand_rate <= @mk2_rate ->
        "Conduit Mk-II recommended"

      # Mk-III sustains 1.0 items/tick
      demand_rate <= @mk3_rate ->
        "Conduit Mk-III recommended"

      # Genuinely need parallel belts via merger even with Mk-III
      true ->
        belts = Float.ceil(demand_rate / @mk3_rate) |> trunc()
        "Merger with #{belts} Mk-III input belts needed"
    end
  end

  defp header do
    """
    ============================================================
    RECIPE THROUGHPUT ANALYSIS
    ============================================================
    Tick rate: 200ms | Per-tier conduit throughput:
      - Conduit Mk-I:   1 item / 3 ticks = 0.333/tick (1.67/sec)
      - Conduit Mk-II:  1 item / 2 ticks = 0.500/tick (2.50/sec)
      - Conduit Mk-III: 1 item / 1 tick  = 1.000/tick (5.00/sec)

    Machines accept inputs into slots WHILE processing.
    Items enter from REAR direction (single belt) unless merged.
    ============================================================
    """
  end

  defp summary do
    """
    ============================================================
    LEGEND
    ============================================================
    OK (Mk-I)    = Mk-I conduit keeps the machine fully fed
    OK (Mk-II+)  = Mk-II or higher needed for full throughput
    OK (Mk-III)  = Mk-III needed for full throughput
    BOTTLENECK   = Even Mk-III cannot deliver inputs fast enough;
                   use a Merger with parallel Mk-III belts

    Cycle = processing ticks + output drain ticks
    Demand rate = total input items / cycle ticks
    ============================================================
    """
  end
end
