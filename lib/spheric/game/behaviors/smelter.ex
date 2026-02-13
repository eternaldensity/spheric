defmodule Spheric.Game.Behaviors.Smelter do
  @moduledoc """
  Smelter building behavior.

  Accepts ore in its input buffer, processes it over several ticks,
  then places the resulting ingot in the output buffer.
  """

  @default_rate 10

  @recipes %{
    iron_ore: :iron_ingot,
    copper_ore: :copper_ingot
  }

  @doc "Returns the initial state for a newly placed smelter."
  def initial_state do
    %{input_buffer: nil, output_buffer: nil, progress: 0, rate: @default_rate}
  end

  @doc "Process one tick for a smelter. Returns updated building map."
  def tick(_key, building) do
    state = building.state

    cond do
      # Has input and output is clear -> processing
      state.input_buffer != nil and state.output_buffer == nil ->
        if state.progress + 1 >= state.rate do
          output = Map.get(@recipes, state.input_buffer, state.input_buffer)
          %{building | state: %{state | input_buffer: nil, output_buffer: output, progress: 0}}
        else
          %{building | state: %{state | progress: state.progress + 1}}
        end

      # No input or output full -> idle
      true ->
        building
    end
  end

  @doc "Returns the smelting recipe map."
  def recipes, do: @recipes
end
