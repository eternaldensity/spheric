defmodule Spheric.Game.Behaviors.FabricationPlant do
  @moduledoc """
  Fabrication Plant building behavior.

  Triple-input assembler for Tier 5 recipes. Accepts three different
  inputs and combines them into advanced components.
  """

  @default_rate 20

  @recipes %{
    {:advanced_circuit, :advanced_circuit, :plastic_sheet} => :computer,
    {:heavy_frame, :motor, :heat_sink} => :motor_housing,
    {:reinforced_plate, :plastic_sheet, :titanium_ingot} => :composite
  }

  def initial_state do
    %{
      input_a: nil,
      input_b: nil,
      input_c: nil,
      output_buffer: nil,
      progress: 0,
      rate: @default_rate
    }
  end

  def tick(_key, building) do
    state = building.state

    cond do
      state.input_a != nil and state.input_b != nil and state.input_c != nil and
          state.output_buffer == nil ->
        if state.progress + 1 >= state.rate do
          output = recipe_output(state.input_a, state.input_b, state.input_c)

          %{
            building
            | state: %{
                state
                | input_a: nil,
                  input_b: nil,
                  input_c: nil,
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
      state.input_a == nil and can_go_in_slot_a?(item_type, state.input_b, state.input_c) ->
        %{state | input_a: item_type}

      state.input_b == nil and can_go_in_slot_b?(state.input_a, item_type, state.input_c) ->
        %{state | input_b: item_type}

      state.input_c == nil and can_go_in_slot_c?(state.input_a, state.input_b, item_type) ->
        %{state | input_c: item_type}

      true ->
        nil
    end
  end

  defp can_go_in_slot_a?(item, current_b, current_c) do
    Enum.any?(@recipes, fn {{a, b, c}, _} ->
      a == item and (current_b == nil or b == current_b) and (current_c == nil or c == current_c)
    end)
  end

  defp can_go_in_slot_b?(current_a, item, current_c) do
    Enum.any?(@recipes, fn {{a, b, c}, _} ->
      b == item and (current_a == nil or a == current_a) and (current_c == nil or c == current_c)
    end)
  end

  defp can_go_in_slot_c?(current_a, current_b, item) do
    Enum.any?(@recipes, fn {{a, b, c}, _} ->
      c == item and (current_a == nil or a == current_a) and (current_b == nil or b == current_b)
    end)
  end

  defp recipe_output(a, b, c) do
    Map.get(@recipes, {a, b, c}, a)
  end

  def recipes, do: @recipes
end
