defmodule Spheric.Game.Behaviors.ParanaturalSynthesizer do
  @moduledoc """
  Paranatural Synthesizer building behavior.

  Triple-input building for Tier 7 paranatural recipes. Requires
  an assigned creature to function -- the building will not process
  without a creature assigned.
  """

  alias Spheric.Game.Creatures

  @default_rate 30

  @recipes %{
    {:supercomputer, :advanced_composite, :creature_essence} => :containment_module,
    {:nuclear_cell, :containment_module, :creature_essence} => :dimensional_core,
    {:quartz_crystal, :quartz_crystal, :creature_essence} => :astral_lens
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

  def tick(key, building) do
    state = building.state

    # Requires an assigned creature to function
    unless Creatures.has_assigned_creature?(key) do
      building
    else
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
