defmodule Spheric.Game.Behaviors.Assembler do
  @moduledoc """
  Assembler building behavior.

  Accepts two different input items (input_a and input_b) and combines
  them into a component over several ticks. Each recipe defines which
  item type goes into which slot.

  Input direction: rear (opposite of orientation), same as Splitter.
  Items are routed to whichever input slot (a or b) matches the recipe.
  """

  @default_rate 15

  @recipes %{
    {:copper_ingot, :copper_ingot} => :wire,
    {:iron_ingot, :iron_ingot} => :plate,
    {:wire, :raw_quartz} => :circuit,
    {:plate, :titanium_ingot} => :frame
  }

  @doc "Returns the initial state for a newly placed assembler."
  def initial_state do
    %{input_a: nil, input_b: nil, output_buffer: nil, progress: 0, rate: @default_rate}
  end

  @doc "Process one tick for an assembler. Returns updated building map."
  def tick(_key, building) do
    state = building.state

    cond do
      # Both inputs present and output clear -> processing
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

      # Missing inputs or output full -> idle
      true ->
        building
    end
  end

  @doc "Try to accept an item into the appropriate input slot. Returns updated state or nil."
  def try_accept_item(state, item_type) do
    # Find which recipe slot this item belongs to
    cond do
      # Slot A is empty and item can go in slot A for some recipe
      state.input_a == nil and can_go_in_slot_a?(item_type, state.input_b) ->
        %{state | input_a: item_type}

      # Slot B is empty and item can go in slot B for some recipe
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

  @doc "Returns the assembler recipe map."
  def recipes, do: @recipes
end
