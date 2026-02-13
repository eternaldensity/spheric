defmodule Spheric.Game.Behaviors.MinerTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.Behaviors.Miner
  alias Spheric.Game.WorldStore

  @resource_key {0, 0, 0}

  setup do
    # Ensure a resource tile exists for testing
    WorldStore.put_tile(@resource_key, %{terrain: :volcanic, resource: {:iron, 100}})

    on_exit(fn ->
      WorldStore.put_tile(@resource_key, %{terrain: :volcanic, resource: {:iron, 100}})
    end)

    :ok
  end

  test "initial_state has correct structure" do
    state = Miner.initial_state()
    assert state.output_buffer == nil
    assert state.progress == 0
    assert state.rate == 5
  end

  test "increments progress each tick when not at rate" do
    building = %{type: :miner, orientation: 0, state: Miner.initial_state()}

    updated = Miner.tick(@resource_key, building)
    assert updated.state.progress == 1
    assert updated.state.output_buffer == nil
  end

  test "extracts ore when progress reaches rate" do
    building = %{type: :miner, orientation: 0, state: %{output_buffer: nil, progress: 4, rate: 5}}

    updated = Miner.tick(@resource_key, building)
    assert updated.state.output_buffer == :iron_ore
    assert updated.state.progress == 0
  end

  test "stalls when output buffer is full" do
    building = %{
      type: :miner,
      orientation: 0,
      state: %{output_buffer: :iron_ore, progress: 0, rate: 5}
    }

    updated = Miner.tick(@resource_key, building)
    assert updated.state.output_buffer == :iron_ore
    assert updated.state.progress == 0
  end

  test "decrements tile resource amount on extraction" do
    WorldStore.put_tile(@resource_key, %{terrain: :volcanic, resource: {:iron, 5}})
    building = %{type: :miner, orientation: 0, state: %{output_buffer: nil, progress: 4, rate: 5}}

    Miner.tick(@resource_key, building)

    tile = WorldStore.get_tile(@resource_key)
    assert tile.resource == {:iron, 4}
  end

  test "handles resource depletion (amount reaches 0)" do
    WorldStore.put_tile(@resource_key, %{terrain: :volcanic, resource: {:iron, 1}})
    building = %{type: :miner, orientation: 0, state: %{output_buffer: nil, progress: 4, rate: 5}}

    updated = Miner.tick(@resource_key, building)
    assert updated.state.output_buffer == :iron_ore

    tile = WorldStore.get_tile(@resource_key)
    assert tile.resource == nil
  end

  test "stalls when resource is nil (depleted)" do
    WorldStore.put_tile(@resource_key, %{terrain: :volcanic, resource: nil})
    building = %{type: :miner, orientation: 0, state: %{output_buffer: nil, progress: 4, rate: 5}}

    updated = Miner.tick(@resource_key, building)
    # Should not crash, just return unchanged
    assert updated.state.output_buffer == nil
  end

  test "extracts copper ore from copper resource" do
    WorldStore.put_tile(@resource_key, %{terrain: :forest, resource: {:copper, 50}})
    building = %{type: :miner, orientation: 0, state: %{output_buffer: nil, progress: 4, rate: 5}}

    updated = Miner.tick(@resource_key, building)
    assert updated.state.output_buffer == :copper_ore
  end

  test "full extraction cycle over multiple ticks" do
    building = %{type: :miner, orientation: 0, state: Miner.initial_state()}

    # Tick 4 times (progress 0->4)
    building =
      Enum.reduce(1..4, building, fn _, b ->
        Miner.tick(@resource_key, b)
      end)

    assert building.state.progress == 4
    assert building.state.output_buffer == nil

    # 5th tick should extract
    building = Miner.tick(@resource_key, building)
    assert building.state.progress == 0
    assert building.state.output_buffer == :iron_ore
  end
end
