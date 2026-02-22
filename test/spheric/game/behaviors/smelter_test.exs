defmodule Spheric.Game.Behaviors.SmelterTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Behaviors.Smelter

  @key {0, 5, 5}

  # Helper to build a full smelter state with all required fields
  defp smelter_state(overrides) do
    Map.merge(Smelter.initial_state(), overrides)
  end

  test "initial_state has correct structure" do
    state = Smelter.initial_state()
    assert state.input_buffer == nil
    assert state.output_buffer == nil
    assert state.progress == 0
    assert state.rate == 10
    assert state.input_count == 0
    assert state.output_remaining == 0
    assert state.output_type == nil
  end

  test "idle when no input" do
    building = %{type: :smelter, orientation: 0, state: Smelter.initial_state()}

    updated = Smelter.tick(@key, building)
    assert updated.state == Smelter.initial_state()
  end

  test "increments progress when has input and output is clear" do
    state = smelter_state(%{input_buffer: :iron_ore, input_count: 1})
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    assert updated.state.progress == 1
    assert updated.state.input_buffer == :iron_ore
    assert updated.state.output_buffer == nil
  end

  test "produces ingot when progress reaches rate" do
    state = smelter_state(%{input_buffer: :iron_ore, input_count: 1, progress: 9})
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    assert updated.state.input_buffer == nil
    assert updated.state.output_buffer == :iron_ingot
    assert updated.state.progress == 0
  end

  test "produces copper ingot from copper ore" do
    state = smelter_state(%{input_buffer: :copper_ore, input_count: 1, progress: 9})
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    assert updated.state.output_buffer == :copper_ingot
  end

  test "stalls when output buffer is full" do
    state = smelter_state(%{input_buffer: :iron_ore, input_count: 1, output_buffer: :iron_ingot, output_type: :iron_ingot})
    building = %{type: :smelter, orientation: 0, state: state}

    updated = Smelter.tick(@key, building)
    # Should not advance progress
    assert updated.state.progress == 0
    assert updated.state.output_buffer == :iron_ingot
  end

  test "full smelting cycle over multiple ticks" do
    state = smelter_state(%{input_buffer: :iron_ore, input_count: 1})
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

  test "recipes returns expected list format" do
    recipes = Smelter.recipes()
    assert is_list(recipes)

    iron_recipe = Enum.find(recipes, fn r -> r.output == {:iron_ingot, 1} end)
    assert iron_recipe != nil
    assert iron_recipe.inputs == [iron_ore: 1]

    copper_recipe = Enum.find(recipes, fn r -> r.output == {:copper_ingot, 1} end)
    assert copper_recipe != nil
    assert copper_recipe.inputs == [copper_ore: 1]
  end
end
