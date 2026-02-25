defmodule Spheric.Game.ResonanceCascadeTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.{Behaviors, TickProcessor, WorldStore, WorldEvents, Creatures}

  # Tile keys on face 15 (unlikely to conflict with other tests)
  @smelter_key {15, 10, 10}
  @miner_key {15, 10, 11}
  @conveyor1_key {15, 10, 12}
  @conveyor2_key {15, 10, 13}
  @conveyor3_key {15, 10, 14}
  @trap_key {15, 20, 20}

  @all_keys [
    @smelter_key, @miner_key, @conveyor1_key, @conveyor2_key,
    @conveyor3_key, @trap_key
  ]

  setup do
    WorldEvents.init()
    WorldEvents.clear()
    WorldEvents.init()
    Creatures.init()
    Creatures.clear_all()

    Enum.each(@all_keys, &WorldStore.remove_building/1)

    # Neutral terrain so ShiftCycle doesn't affect rates
    Enum.each(@all_keys, fn key ->
      WorldStore.put_tile(key, %{terrain: :grassland, resource: nil})
    end)

    WorldStore.put_tile(@miner_key, %{terrain: :grassland, resource: {:iron, 1000}})

    on_exit(fn ->
      WorldEvents.clear()
      WorldEvents.init()
      Enum.each(@all_keys, &WorldStore.remove_building/1)
    end)

    :ok
  end

  defp activate_resonance_cascade do
    WorldEvents.put_state(%{
      active_event: :resonance_cascade,
      event_start_tick: 0,
      last_event_tick: 0,
      event_history: [{:resonance_cascade, 0}]
    })
  end

  defp deactivate_resonance_cascade do
    WorldEvents.put_state(%{
      active_event: nil,
      event_start_tick: 0,
      last_event_tick: 0,
      event_history: []
    })
  end

  describe "overclock during resonance cascade" do
    test "overclock halves rate normally (2x speed)" do
      WorldStore.put_building(@miner_key, %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 10, altered_effect: :overclock, powered: true}
      })

      deactivate_resonance_cascade()

      # With overclock (2x speed), effective rate = 10/2 = 5
      for i <- 1..4, do: TickProcessor.process_tick(i)
      building = WorldStore.get_building(@miner_key)
      assert building.state.output_buffer == nil

      TickProcessor.process_tick(5)
      building = WorldStore.get_building(@miner_key)
      assert building.state.output_buffer == :iron_ore
    end

    test "overclock quadruples speed during resonance cascade (4x)" do
      WorldStore.put_building(@miner_key, %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 12, altered_effect: :overclock, powered: true}
      })

      activate_resonance_cascade()

      # With cascade overclock (4x speed), effective rate = 12/4 = 3
      for i <- 1..2, do: TickProcessor.process_tick(i)
      building = WorldStore.get_building(@miner_key)
      assert building.state.output_buffer == nil

      TickProcessor.process_tick(3)
      building = WorldStore.get_building(@miner_key)
      assert building.state.output_buffer == :iron_ore
    end
  end

  describe "purified_smelting during resonance cascade" do
    test "purified_smelting doubles output normally (2x)" do
      deactivate_resonance_cascade()

      smelter_state =
        Map.merge(Behaviors.Smelter.initial_state(), %{
          input_buffer: :iron_ore,
          input_count: 1,
          altered_effect: :purified_smelting
        })

      WorldStore.put_building(@smelter_key, %{
        type: :smelter,
        orientation: 0,
        state: smelter_state
      })

      # Tick enough times for the smelter to finish (rate = 10)
      for i <- 1..10, do: TickProcessor.process_tick(i)

      smelter = WorldStore.get_building(@smelter_key)
      assert smelter.state.output_buffer == :iron_ingot
      # 2x output: original 1, so output_remaining = (0+1)*2 - 1 = 1
      assert smelter.state.output_remaining == 1
    end

    test "purified_smelting quadruples output during resonance cascade (4x)" do
      activate_resonance_cascade()

      smelter_state =
        Map.merge(Behaviors.Smelter.initial_state(), %{
          input_buffer: :iron_ore,
          input_count: 1,
          altered_effect: :purified_smelting
        })

      WorldStore.put_building(@smelter_key, %{
        type: :smelter,
        orientation: 0,
        state: smelter_state
      })

      # Tick enough times for the smelter to finish (rate = 10)
      for i <- 1..10, do: TickProcessor.process_tick(i)

      smelter = WorldStore.get_building(@smelter_key)
      assert smelter.state.output_buffer == :iron_ingot
      # 4x output: original 1, so output_remaining = (0+1)*4 - 1 = 3
      assert smelter.state.output_remaining == 3
    end
  end

  describe "teleport_output during resonance cascade" do
    # Teleport only applies to buildings that use resolve_output_dest (smelter, assembler, etc.)
    # not miners (which push directly via TileNeighbors.neighbor).

    test "smelter with teleport_output skips 1 tile normally" do
      deactivate_resonance_cascade()

      # Smelter at col 10, orientation 0 (pushes to col+1)
      # Conveyors at col 11, 12, 13
      # Teleport should skip col 11 and land at col 12
      smelter_state =
        Map.merge(Behaviors.Smelter.initial_state(), %{
          output_buffer: :iron_ingot,
          altered_effect: :teleport_output
        })

      WorldStore.put_building(@smelter_key, %{
        type: :smelter,
        orientation: 2,
        state: smelter_state
      })

      # Direction 2 = col - 1, so smelter at {15,10,10} pushes to {15,10,9}, {15,10,8}, {15,10,7}
      # Let's use direction 0 (col+1) instead. Smelter at @smelter_key {15,10,10}, orientation 0
      # pushes toward col 11 (@miner_key), 12, 13
      # But @miner_key has a miner. Let me use a different layout.

      # Actually let me just re-place things cleanly:
      WorldStore.remove_building(@smelter_key)
      WorldStore.remove_building(@miner_key)

      # Smelter at {15, 10, 10}, orientation 0 pushes to col+1 = {15, 10, 11}
      smelter_state =
        Map.merge(Behaviors.Smelter.initial_state(), %{
          output_buffer: :iron_ingot,
          altered_effect: :teleport_output
        })

      WorldStore.put_building(@smelter_key, %{
        type: :smelter,
        orientation: 0,
        state: smelter_state
      })

      # {15, 10, 11} = skip target, {15, 10, 12} = destination
      WorldStore.put_building(@miner_key, %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil, speed: 1, progress: 0, powered: true}
      })

      WorldStore.put_building(@conveyor1_key, %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil, speed: 1, progress: 0, powered: true}
      })

      WorldStore.put_building(@conveyor2_key, %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil, speed: 1, progress: 0, powered: true}
      })

      TickProcessor.process_tick(1)

      skip = WorldStore.get_building(@miner_key)     # {15,10,11} — skipped
      dest = WorldStore.get_building(@conveyor1_key)  # {15,10,12} — destination
      far = WorldStore.get_building(@conveyor2_key)   # {15,10,13} — too far

      assert skip.state.item == nil
      assert dest.state.item == :iron_ingot
      assert far.state.item == nil
    end

    test "smelter with teleport_output skips 2 tiles during resonance cascade" do
      activate_resonance_cascade()

      WorldStore.remove_building(@smelter_key)
      WorldStore.remove_building(@miner_key)

      smelter_state =
        Map.merge(Behaviors.Smelter.initial_state(), %{
          output_buffer: :iron_ingot,
          altered_effect: :teleport_output
        })

      WorldStore.put_building(@smelter_key, %{
        type: :smelter,
        orientation: 0,
        state: smelter_state
      })

      # {15,10,11} = skip1, {15,10,12} = skip2, {15,10,13} = destination
      WorldStore.put_building(@miner_key, %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil, speed: 1, progress: 0, powered: true}
      })

      WorldStore.put_building(@conveyor1_key, %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil, speed: 1, progress: 0, powered: true}
      })

      WorldStore.put_building(@conveyor2_key, %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil, speed: 1, progress: 0, powered: true}
      })

      TickProcessor.process_tick(1)

      skip1 = WorldStore.get_building(@miner_key)     # {15,10,11} — skipped
      skip2 = WorldStore.get_building(@conveyor1_key)  # {15,10,12} — skipped
      dest = WorldStore.get_building(@conveyor2_key)   # {15,10,13} — destination

      assert skip1.state.item == nil
      assert skip2.state.item == nil
      assert dest.state.item == :iron_ingot
    end
  end

  describe "trap_radius during resonance cascade" do
    test "trap captures creature at extended range during resonance cascade" do
      # Normal trap_radius with altered: @capture_radius * 3 = 3 * 3 = 9
      # Cascade trap_radius: @capture_radius * 6 = 3 * 6 = 18
      activate_resonance_cascade()

      WorldStore.put_tile(@trap_key, %{terrain: :grassland, resource: nil})

      WorldStore.put_building(@trap_key, %{
        type: :containment_trap,
        orientation: 0,
        state: %{
          altered_effect: :trap_radius,
          powered: true,
          capture_progress: 0,
          capturing: nil
        },
        owner_id: "player:cascade_test"
      })

      # Place a wild creature at distance 12 (outside normal 9, inside cascade 18)
      Creatures.put_wild_creature("cascade_creature", %{
        type: :quartz_drone,
        face: 15,
        row: 20,
        col: 32,
        hp: 100
      })

      # Call process_traps to check if creature is in range
      Creatures.process_traps(1)

      trap = WorldStore.get_building(@trap_key)

      # With cascade, radius is 18, so creature at distance 12 should be detected
      assert trap.state.capture_progress > 0
      assert trap.state.capturing == "cascade_creature"

      # Clean up
      WorldStore.remove_building(@trap_key)
    end

    test "trap does NOT capture creature at extended range without resonance cascade" do
      deactivate_resonance_cascade()

      WorldStore.put_tile(@trap_key, %{terrain: :grassland, resource: nil})

      WorldStore.put_building(@trap_key, %{
        type: :containment_trap,
        orientation: 0,
        state: %{
          altered_effect: :trap_radius,
          powered: true,
          capture_progress: 0,
          capturing: nil
        },
        owner_id: "player:cascade_test2"
      })

      # Place a wild creature at distance 12 (outside normal 9)
      Creatures.put_wild_creature("cascade_creature2", %{
        type: :quartz_drone,
        face: 15,
        row: 20,
        col: 32,
        hp: 100
      })

      Creatures.process_traps(1)

      trap = WorldStore.get_building(@trap_key)

      # Without cascade, radius is 9, creature at distance 12 should NOT be detected
      assert trap.state.capture_progress == 0
      assert trap.state.capturing == nil

      # Clean up
      WorldStore.remove_building(@trap_key)
    end
  end
end
