defmodule Spheric.Game.Behaviors.Refinery do
  @moduledoc """
  Refinery building behavior.

  Processes raw materials into refined products over several ticks.
  Follows the same single-input pattern as Smelter but handles
  different recipe types (liquids and compounds).
  """

  @default_rate 12

  @recipes %{
    crude_oil: :polycarbonate,
    raw_sulfur: :sulfur_compound
  }

  @doc "Returns the initial state for a newly placed refinery."
  def initial_state do
    %{input_buffer: nil, output_buffer: nil, progress: 0, rate: @default_rate}
  end

  @doc "Process one tick for a refinery. Returns updated building map."
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

  @doc "Returns the refinery recipe map."
  def recipes, do: @recipes
end
