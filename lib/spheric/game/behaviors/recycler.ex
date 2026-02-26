defmodule Spheric.Game.Behaviors.Recycler do
  @moduledoc """
  Recycler building behavior.

  Accepts any 10 items (mixed types allowed), then produces 1 random raw
  resource weighted by the biome the recycler sits on. Requires power.

  Rate: 30 ticks (slow, heavy process).

  Output weights per biome match the world generation resource distribution,
  producing ore/raw forms: iron_ore, copper_ore, raw_quartz, titanium_ore,
  crude_oil, raw_sulfur, raw_uranium, ice (tundra only).
  """

  alias Spheric.Game.{WorldStore, WorldGen}

  @rate 30
  @input_required 10

  # Map raw resource atoms from WorldGen to the ore/raw item atoms that
  # miners produce and that players actually handle as items.
  @resource_to_ore %{
    iron: :iron_ore,
    copper: :copper_ore,
    quartz: :raw_quartz,
    titanium: :titanium_ore,
    oil: :crude_oil,
    sulfur: :raw_sulfur,
    uranium: :raw_uranium,
    ice: :ice
  }

  # Derived at compile time from WorldGen.biome_resource_weights/0
  @biome_outputs WorldGen.biome_resource_weights()
                 |> Map.new(fn {biome, weights} ->
                   {biome,
                    Enum.map(weights, fn {resource, weight} ->
                      {Map.fetch!(@resource_to_ore, resource), weight}
                    end)}
                 end)

  def initial_state do
    %{
      input_count: 0,
      output_buffer: nil,
      progress: 0,
      rate: @rate,
      powered: true
    }
  end

  def recipes do
    [%{inputs: [any: @input_required], output: {:random_resource, 1}}]
  end

  @doc "Tick the recycler. Accepts any items up to 10, then processes."
  def tick(key, building) do
    state = building.state

    cond do
      # Phase 1: Drain — output waiting to be pushed
      state.output_buffer != nil ->
        building

      # Phase 2: Process — enough items collected, no pending output
      state.input_count >= @input_required and state.output_buffer == nil ->
        if state.progress + 1 >= state.rate do
          output_item = pick_biome_output(key)

          %{building | state: %{state | input_count: 0, output_buffer: output_item, progress: 0}}
        else
          %{building | state: %{state | progress: state.progress + 1}}
        end

      # Phase 3: Idle — waiting for more items
      true ->
        building
    end
  end

  @doc "Accept any item. Returns updated state or nil if full."
  def try_accept_item(state, _item_type) do
    if state.input_count < @input_required do
      %{state | input_count: state.input_count + 1}
    else
      nil
    end
  end

  @doc "Returns true if input is full (10 items collected)."
  def full?(state) do
    state.input_count >= @input_required
  end

  @doc "Returns the required input count."
  def input_required, do: @input_required

  # Pick a random output item based on the biome at the building's tile
  defp pick_biome_output(key) do
    biome =
      case WorldStore.get_tile(key) do
        %{terrain: terrain} when is_atom(terrain) -> terrain
        _ -> :grassland
      end

    weights = Map.get(@biome_outputs, biome, @biome_outputs.grassland)
    roll = :rand.uniform()
    pick_weighted(roll, weights)
  end

  defp pick_weighted(_roll, [{type, _weight}]), do: type

  defp pick_weighted(roll, [{type, weight} | rest]) do
    if roll < weight, do: type, else: pick_weighted(roll - weight, rest)
  end
end
