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

  # All conveyors deliver 1 item per tick via push resolution.
  # The difference is buffer depth (burst capacity), not sustained rate.
  # Sustained throughput for all tiers: 1 item/tick = 5 items/sec.
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

        # The machine takes `rate` ticks to process once inputs are satisfied.
        # After processing, it also takes `out_qty - 1` drain ticks (1 output/tick)
        # plus the processing tick itself. But drain happens in parallel with
        # the next input acceptance (output_buffer blocks new processing, not input).
        #
        # Full cycle time = rate ticks (processing) + max(out_qty - 1, 0) drain ticks
        # But inputs can be loaded DURING drain, so effective input window = full cycle.
        #
        # Actually: inputs can arrive any time while output_buffer is being drained
        # AND during processing. The machine accepts items whenever its input slots
        # have capacity. So the full cycle is:
        #   cycle_ticks = rate + (out_qty - 1)
        # And we need `total_input_items` delivered within `cycle_ticks`.
        #
        # A single conduit delivers 1 item/tick on the same input line.
        # Multi-input buildings accept from REAR direction only (single input belt).
        # So all items share one conduit unless the player uses a merger.

        cycle_ticks = rate + max(out_qty - 1, 0)
        demand_rate = total_input_items / cycle_ticks

        # For multi-input recipes where both slots need DIFFERENT item types,
        # items must alternate on the belt (or use a merger from 2 belts).
        # With a merger: each input line needs to supply its share.
        # Without a merger: single belt must interleave all types.

        # Single conduit throughput: 1 item/tick
        # Can it keep up? demand_rate <= 1.0 means yes
        conduit_tier = recommend_tier(total_input_items, cycle_ticks)

        # Calculate idle time percentage if using basic conduit
        # Time to deliver all inputs on 1 belt: total_input_items ticks
        # If total_input_items > cycle_ticks, machine waits
        idle_ticks = max(total_input_items - cycle_ticks, 0)
        idle_pct = if cycle_ticks > 0, do: idle_ticks / (cycle_ticks + idle_ticks) * 100, else: 0.0

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
            demand_rate <= 1.0 -> "OK"
            demand_rate <= 1.0 and total_input_items > 1 -> "OK (burst)"
            true -> "BOTTLENECK"
          end

        Mix.shell().info("""
        #{building_name} (#{rate} ticks, #{slot_type})
          Recipe: #{input_str} -> #{output_str}
          Cycle: #{cycle_ticks} ticks (#{rate} process + #{max(out_qty - 1, 0)} drain)
          Total inputs needed: #{total_input_items} items
          Demand rate: #{Float.round(demand_rate, 3)} items/tick
          Single conduit: #{status}#{if idle_pct > 0, do: " | #{Float.round(idle_pct, 1)}% idle with 1 belt", else: ""}
          Recommendation: #{conduit_tier}
        """)
      end
    end

    Mix.shell().info(summary())
  end

  defp recommend_tier(total_input_items, cycle_ticks) do
    cond do
      # Single belt can sustain the recipe with no waiting
      total_input_items <= cycle_ticks ->
        "Conduit (basic) is sufficient"

      # Need slight burst capacity - Mk2 buffer helps absorb
      total_input_items <= cycle_ticks + 1 ->
        "Conduit Mk-II recommended (buffer absorbs 1-item burst)"

      # Need more burst capacity
      total_input_items <= cycle_ticks + 2 ->
        "Conduit Mk-III recommended (buffer absorbs 2-item burst)"

      # Genuinely need parallel belts via merger
      true ->
        belts = Float.ceil(total_input_items / cycle_ticks) |> trunc()
        "Merger with #{belts} input belts needed"
    end
  end

  defp header do
    """
    ============================================================
    RECIPE THROUGHPUT ANALYSIS
    ============================================================
    Tick rate: 200ms | Conduit throughput: 1 item/tick (all tiers)
    Conduit tiers differ in BUFFER size (burst capacity):
      - Conduit:      1 slot  (no buffer)
      - Conduit Mk-II:  2 slots (1 buffer)
      - Conduit Mk-III: 3 slots (2 buffers)

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
    OK         = Single basic conduit keeps the machine fully fed
    BOTTLENECK = Single conduit cannot deliver inputs fast enough;
                 machine will idle between cycles waiting for items

    Cycle = processing ticks + output drain ticks
    Demand rate = total input items / cycle ticks
    If demand rate > 1.0, a single belt cannot sustain the recipe.
    ============================================================
    """
  end
end
