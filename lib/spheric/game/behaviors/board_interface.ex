defmodule Spheric.Game.Behaviors.BoardInterface do
  @moduledoc """
  Board Interface building behavior.

  Triple-input building for the Tier 8 endgame recipe.
  Produces board_resonator from dimensional_core + supercomputer + astral_lens.
  """

  @default_rate 50

  @recipes %{
    {:dimensional_core, :supercomputer, :astral_lens} => :board_resonator
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

  defp recipe_output(a, b, c), do: Map.get(@recipes, {a, b, c}, a)

  def recipes, do: @recipes
end
