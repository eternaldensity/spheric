defmodule Spheric.Game.Behaviors.ParticleCollider do
  @moduledoc """
  Particle Collider building behavior.

  Dual-input processing for Tier 6 high-tech recipes.
  """

  @default_rate 25

  @recipes %{
    {:computer, :advanced_circuit} => :supercomputer,
    {:composite, :quartz_crystal} => :advanced_composite,
    {:enriched_uranium, :advanced_composite} => :nuclear_cell
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
    Enum.any?(@recipes, fn {{a, b}, _} ->
      a == item and (current_b == nil or b == current_b)
    end)
  end

  defp can_go_in_slot_b?(current_a, item) do
    Enum.any?(@recipes, fn {{a, b}, _} ->
      b == item and (current_a == nil or a == current_a)
    end)
  end

  defp recipe_output(a, b), do: Map.get(@recipes, {a, b}, a)

  def recipes, do: @recipes
end
