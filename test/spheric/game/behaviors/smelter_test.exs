defmodule Spheric.Game.Behaviors.SmelterTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Behaviors.Smelter

  @key {0, 5, 5}

  test "initial_state has correct structure" do
    state = Smelter.initial_state()
    assert state.input_buffer == nil
    assert state.output_buffer == nil
    assert state.progress == 0
    assert state.rate == 10
  end

  test "idle when no input" do
    building = %{type: :smelter, orientation: 0, state: Smelter.initial_state()}

    updated = Smelter.tick(@key, building)
    assert updated.state == Smelter.initial_state()
  end

  test "increments progress when has input and output is clear" do
    state = %{input_buffer: :iron_ore, output_buffer: nil, progress: 0, rate: 10}
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    assert updated.state.progress == 1
    assert updated.state.input_buffer == :iron_ore
    assert updated.state.output_buffer == nil
  end

  test "produces ingot when progress reaches rate" do
    state = %{input_buffer: :iron_ore, output_buffer: nil, progress: 9, rate: 10}
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    assert updated.state.input_buffer == nil
    assert updated.state.output_buffer == :iron_ingot
    assert updated.state.progress == 0
  end

  test "produces copper ingot from copper ore" do
    state = %{input_buffer: :copper_ore, output_buffer: nil, progress: 9, rate: 10}
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    assert updated.state.output_buffer == :copper_ingot
  end

  test "stalls when output buffer is full" do
    state = %{input_buffer: :iron_ore, output_buffer: :iron_ingot, progress: 0, rate: 10}
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    # Should not advance progress
    assert updated.state.progress == 0
    assert updated.state.output_buffer == :iron_ingot
  end

  test "full smelting cycle over multiple ticks" do
    state = %{input_buffer: :iron_ore, output_buffer: nil, progress: 0, rate: 10}
    building = %{type: :smelter, orientation: 0, state: state}

    # Tick 9 times (progress 0->9)
    building =
      Enum.reduce(1..9, building, fn _, b ->
        Smelter.tick(@key, b)
      end)

    assert building.state.progress == 9
    assert building.state.input_buffer == :iron_ore
    assert building.state.output_buffer == nil

    # 10th tick should complete smelting
    building = Smelter.tick(@key, building)
    assert building.state.input_buffer == nil
    assert building.state.output_buffer == :iron_ingot
    assert building.state.progress == 0
  end

  test "recipes returns expected mappings" do
    recipes = Smelter.recipes()
    assert Map.get(recipes, :iron_ore) == :iron_ingot
    assert Map.get(recipes, :copper_ore) == :copper_ingot
  end
end
