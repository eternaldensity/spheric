defmodule Spheric.Game.Behaviors.Miner do
  @moduledoc """
  Miner building behavior.

  Each tick, increments progress counter. When progress reaches rate,
  extracts one ore from the tile resource deposit and places it in
  the output buffer. Stalls if the output buffer is full or the
  resource is depleted.
  """

  alias Spheric.Game.WorldStore

  @default_rate 5

  @doc "Returns the initial state for a newly placed miner."
  def initial_state do
    %{output_buffer: nil, progress: 0, rate: @default_rate, powered: true}
  end

  @doc """
  Process one tick for a miner. Returns updated building map.

  Extracts resources directly from ETS tile data when ready.
  """
  def tick(key, building) do
    state = building.state

    cond do
      state.output_buffer != nil ->
        building

      state.progress + 1 < state.rate ->
        %{building | state: %{state | progress: state.progress + 1}}

      true ->
        case extract_resource(key) do
          {:ok, item_type} ->
            %{building | state: %{state | output_buffer: item_type, progress: 0}}

          :depleted ->
            building
        end
    end
  end

  defp extract_resource(key) do
    tile = WorldStore.get_tile(key)

    case tile do
      %{resource: {type, amount}} when amount > 0 ->
        new_resource = if amount <= 1, do: nil, else: {type, amount - 1}
        WorldStore.put_tile(key, %{tile | resource: new_resource})
        {:ok, resource_to_item(type)}

      _ ->
        :depleted
    end
  end

  defp resource_to_item(:iron), do: :iron_ore
  defp resource_to_item(:copper), do: :copper_ore
  defp resource_to_item(:quartz), do: :raw_quartz
  defp resource_to_item(:titanium), do: :titanium_ore
  defp resource_to_item(:oil), do: :crude_oil
  defp resource_to_item(:sulfur), do: :raw_sulfur
  defp resource_to_item(:uranium), do: :raw_uranium
end
