defmodule Spheric.Game.Behaviors.NuclearRefinery do
  @moduledoc """
  Nuclear Refinery building behavior.

  Single-input refinery for nuclear materials. Handles uranium
  enrichment and other nuclear processing recipes.
  """

  @default_rate 20

  @recipes %{
    raw_uranium: :enriched_uranium
  }

  def initial_state do
    %{input_buffer: nil, output_buffer: nil, progress: 0, rate: @default_rate}
  end

  def tick(_key, building) do
    state = building.state

    cond do
      state.input_buffer != nil and state.output_buffer == nil ->
        if state.progress + 1 >= state.rate do
          output = Map.get(@recipes, state.input_buffer, state.input_buffer)
          %{building | state: %{state | input_buffer: nil, output_buffer: output, progress: 0}}
        else
          %{building | state: %{state | progress: state.progress + 1}}
        end

      true ->
        building
    end
  end

  def recipes, do: @recipes
end
