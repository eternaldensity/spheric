defmodule Spheric.Game.Behaviors.BoardInterface do
  @moduledoc """
  Board Interface building behavior.

  Triple-input building for the Tier 8 endgame recipe.
  Produces board_resonator from dimensional_core + supercomputer + astral_lens.
  """

  @default_rate 50

  @recipes [
    %{inputs: [dimensional_core: 1, supercomputer: 1, astral_lens: 1], output: {:board_resonator, 1}}
  ]

  # Routing map: {slot_a_type, slot_b_type, slot_c_type} => output_atom
  @recipe_routing %{
    {:dimensional_core, :supercomputer, :astral_lens} => :board_resonator
  }

  # Quantity map: {slot_a_type, slot_b_type, slot_c_type} => {[qa, qb, qc], out_qty}
  @recipe_quantities %{
    {:dimensional_core, :supercomputer, :astral_lens} => {[1, 1, 1], 1}
  }

  def initial_state do
    %{
      input_a: nil,
      input_a_count: 0,
      input_b: nil,
      input_b_count: 0,
      input_c: nil,
      input_c_count: 0,
      output_buffer: nil,
      output_remaining: 0,
      output_type: nil,
      progress: 0,
      rate: @default_rate,
      powered: true
    }
  end

  def tick(_key, building) do
    state = building.state
    remaining = state[:output_remaining] || 0

    cond do
      # Phase 1: Drain
      remaining > 0 and state.output_buffer == nil ->
        %{
          building
          | state: %{
              state
              | output_buffer: state[:output_type],
                output_remaining: remaining - 1
            }
        }

      # Phase 2: Process
      slots_ready?(state) and state.output_buffer == nil and remaining == 0 ->
        if state.progress + 1 >= state.rate do
          {_qtys, out_qty} =
            Map.get(@recipe_quantities, {state.input_a, state.input_b, state.input_c})

          output = recipe_output(state.input_a, state.input_b, state.input_c)

          %{
            building
            | state: %{
                state
                | input_a: nil,
                  input_a_count: 0,
                  input_b: nil,
                  input_b_count: 0,
                  input_c: nil,
                  input_c_count: 0,
                  output_buffer: output,
                  output_remaining: out_qty - 1,
                  output_type: output,
                  progress: 0
              }
          }
        else
          %{building | state: %{state | progress: state.progress + 1}}
        end

      # Phase 3: Idle
      true ->
        building
    end
  end

  def try_accept_item(state, item_type) do
    a_count = state[:input_a_count] || 0
    b_count = state[:input_b_count] || 0
    c_count = state[:input_c_count] || 0

    cond do
      state.input_a == nil and can_go_in_slot_a?(item_type, state.input_b, state.input_c) ->
        %{state | input_a: item_type, input_a_count: 1}

      state.input_a == item_type and
          slot_a_needs_more?(state.input_a, state.input_b, state.input_c, a_count) ->
        %{state | input_a_count: a_count + 1}

      state.input_b == nil and can_go_in_slot_b?(state.input_a, item_type, state.input_c) ->
        %{state | input_b: item_type, input_b_count: 1}

      state.input_b == item_type and
          slot_b_needs_more?(state.input_a, state.input_b, state.input_c, b_count) ->
        %{state | input_b_count: b_count + 1}

      state.input_c == nil and can_go_in_slot_c?(state.input_a, state.input_b, item_type) ->
        %{state | input_c: item_type, input_c_count: 1}

      state.input_c == item_type and
          slot_c_needs_more?(state.input_a, state.input_b, state.input_c, c_count) ->
        %{state | input_c_count: c_count + 1}

      true ->
        nil
    end
  end

  def full?(state) do
    a = state.input_a
    b = state.input_b
    c = state.input_c
    a_count = state[:input_a_count] || 0
    b_count = state[:input_b_count] || 0
    c_count = state[:input_c_count] || 0

    if a == nil or b == nil or c == nil do
      false
    else
      case Map.get(@recipe_quantities, {a, b, c}) do
        {[qa, qb, qc], _} -> a_count >= qa and b_count >= qb and c_count >= qc
        nil -> true
      end
    end
  end

  defp can_go_in_slot_a?(item, current_b, current_c) do
    Enum.any?(@recipe_routing, fn {{a, b, c}, _} ->
      a == item and (current_b == nil or b == current_b) and (current_c == nil or c == current_c)
    end)
  end

  defp can_go_in_slot_b?(current_a, item, current_c) do
    Enum.any?(@recipe_routing, fn {{a, b, c}, _} ->
      b == item and (current_a == nil or a == current_a) and (current_c == nil or c == current_c)
    end)
  end

  defp can_go_in_slot_c?(current_a, current_b, item) do
    Enum.any?(@recipe_routing, fn {{a, b, c}, _} ->
      c == item and (current_a == nil or a == current_a) and (current_b == nil or b == current_b)
    end)
  end

  defp slot_a_needs_more?(a_type, b_type, c_type, current_count) do
    Enum.any?(@recipe_quantities, fn {{a, b, c}, {[qa, _qb, _qc], _out}} ->
      a == a_type and (b_type == nil or b == b_type) and
        (c_type == nil or c == c_type) and current_count < qa
    end)
  end

  defp slot_b_needs_more?(a_type, b_type, c_type, current_count) do
    Enum.any?(@recipe_quantities, fn {{a, b, c}, {[_qa, qb, _qc], _out}} ->
      b == b_type and (a_type == nil or a == a_type) and
        (c_type == nil or c == c_type) and current_count < qb
    end)
  end

  defp slot_c_needs_more?(a_type, b_type, c_type, current_count) do
    Enum.any?(@recipe_quantities, fn {{a, b, c}, {[_qa, _qb, qc], _out}} ->
      c == c_type and (a_type == nil or a == a_type) and
        (b_type == nil or b == b_type) and current_count < qc
    end)
  end

  defp slots_ready?(state) do
    a = state.input_a
    b = state.input_b
    c = state.input_c
    a_count = state[:input_a_count] || 0
    b_count = state[:input_b_count] || 0
    c_count = state[:input_c_count] || 0

    if a != nil and b != nil and c != nil do
      case Map.get(@recipe_quantities, {a, b, c}) do
        {[qa, qb, qc], _out} -> a_count >= qa and b_count >= qb and c_count >= qc
        nil -> false
      end
    else
      false
    end
  end

  defp recipe_output(a, b, c), do: Map.get(@recipe_routing, {a, b, c}, a)

  def recipes, do: @recipes
end
