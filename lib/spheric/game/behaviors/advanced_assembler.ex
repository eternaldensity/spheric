defmodule Spheric.Game.Behaviors.AdvancedAssembler do
  @moduledoc """
  Advanced Assembler building behavior.

  Dual-input assembler for Tier 4 recipes. Faster than standard assembler.
  """

  @default_rate 12

  @recipes %{
    {:frame, :reinforced_plate} => :heavy_frame,
    {:circuit, :cable} => :advanced_circuit,
    {:polycarbonate, :sulfur_compound} => :plastic_sheet
  }

  def initial_state do
    %{input_a: nil, input_b: nil, output_buffer: nil, progress: 0, rate: @default_rate}
  end

  def tick(_key, building) do
    state = building.state

    cond do
      state.input_a != nil and state.input_b != nil and state.output_buffer == nil ->
        if state.progress + 1 >= state.rate do
          output = recipe_output(state.input_a, state.input_b)

          %{
            building
            | state: %{
                state
                | input_a: nil,
                  input_b: nil,
                  output_buffer: output,
                  progress: 0
              }
          }
        else
          %{building | state: %{state | progress: state.progress + 1}}
        end

      true ->
        building
    end
  end

  def try_accept_item(state, item_type) do
    cond do
      state.input_a == nil and can_go_in_slot_a?(item_type, state.input_b) ->
        %{state | input_a: item_type}

      state.input_b == nil and can_go_in_slot_b?(state.input_a, item_type) ->
        %{state | input_b: item_type}

      true ->
        nil
    end
  end

  defp can_go_in_slot_a?(item, current_b) do
    Enum.any?(@recipes, fn {{a, b}, _output} ->
      a == item and (current_b == nil or b == current_b)
    end)
  end

  defp can_go_in_slot_b?(current_a, item) do
    Enum.any?(@recipes, fn {{a, b}, _output} ->
      b == item and (current_a == nil or a == current_a)
    end)
  end

  defp recipe_output(input_a, input_b) do
    Map.get(@recipes, {input_a, input_b}, input_a)
  end

  def recipes, do: @recipes
end
