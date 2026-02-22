defmodule Spheric.Game.Behaviors.EssenceExtractor do
  @moduledoc """
  Essence Extractor building behavior.

  Requires an assigned captured creature to function. Produces
  creature_essence periodically. The creature is NOT consumed.
  Output-boosted creatures produce faster.
  """

  alias Spheric.Game.Creatures

  @default_rate 30

  def initial_state do
    %{output_buffer: nil, progress: 0, rate: @default_rate, powered: true}
  end

  def tick(key, building) do
    state = building.state

    cond do
      state.output_buffer != nil ->
        building

      not Creatures.has_assigned_creature?(key) ->
        # No creature assigned, can't extract
        building

      state.progress + 1 >= state.rate ->
        %{building | state: %{state | output_buffer: :creature_essence, progress: 0}}

      true ->
        %{building | state: %{state | progress: state.progress + 1}}
    end
  end
end
