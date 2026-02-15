defmodule Spheric.Game.Behaviors.Production do
  @moduledoc """
  Shared production behavior for buildings that process items.

  Provides `initial_state/0`, `tick/2`, `recipes/0`, and for multi-input
  buildings `try_accept_item/2`.

  ## Options

    * `:recipes` — recipe map (required). Key format depends on input count:
      - 1 input: `%{atom => atom}`
      - 2 inputs: `%{{atom, atom} => atom}`
      - 3 inputs: `%{{atom, atom, atom} => atom}`
    * `:rate` — default processing rate in ticks (required)
    * `:inputs` — number of input slots: 1, 2, or 3 (default: 1)
    * `:requires_creature` — whether tick requires an assigned creature (default: false)
  """

  defmacro __using__(opts) do
    recipes = Keyword.fetch!(opts, :recipes)
    rate = Keyword.fetch!(opts, :rate)
    inputs = Keyword.get(opts, :inputs, 1)
    requires_creature = Keyword.get(opts, :requires_creature, false)

    common =
      quote do
        @recipes unquote(recipes)
        @default_rate unquote(rate)

        def recipes, do: @recipes
      end

    body =
      case inputs do
        1 -> gen_single_input(requires_creature)
        2 -> gen_dual_input(requires_creature)
        3 -> gen_triple_input(requires_creature)
      end

    quote do
      unquote(common)
      unquote(body)
    end
  end

  defp gen_single_input(requires_creature) do
    tick_body = gen_single_tick()

    tick_fn =
      if requires_creature do
        wrap_creature_check(tick_body)
      else
        tick_body
      end

    quote do
      def initial_state do
        %{input_buffer: nil, output_buffer: nil, progress: 0, rate: @default_rate}
      end

      def tick(key, building) do
        _ = key
        unquote(tick_fn)
      end
    end
  end

  defp gen_single_tick do
    quote do
      state = building.state

      cond do
        state.input_buffer != nil and state.output_buffer == nil ->
          if state.progress + 1 >= state.rate do
            output = Map.get(@recipes, state.input_buffer, state.input_buffer)

            %{
              building
              | state: %{state | input_buffer: nil, output_buffer: output, progress: 0}
            }
          else
            %{building | state: %{state | progress: state.progress + 1}}
          end

        true ->
          building
      end
    end
  end

  defp gen_dual_input(requires_creature) do
    tick_body = gen_dual_tick()

    tick_fn =
      if requires_creature do
        wrap_creature_check(tick_body)
      else
        tick_body
      end

    quote do
      def initial_state do
        %{input_a: nil, input_b: nil, output_buffer: nil, progress: 0, rate: @default_rate}
      end

      def tick(key, building) do
        _ = key
        unquote(tick_fn)
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
    end
  end

  defp gen_dual_tick do
    quote do
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
  end

  defp gen_triple_tick do
    quote do
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
  end

  defp gen_triple_input(requires_creature) do
    tick_body = gen_triple_tick()

    tick_fn =
      if requires_creature do
        wrap_creature_check(tick_body)
      else
        tick_body
      end

    quote do
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
        _ = key
        unquote(tick_fn)
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
          a == item and (current_b == nil or b == current_b) and
            (current_c == nil or c == current_c)
        end)
      end

      defp can_go_in_slot_b?(current_a, item, current_c) do
        Enum.any?(@recipes, fn {{a, b, c}, _} ->
          b == item and (current_a == nil or a == current_a) and
            (current_c == nil or c == current_c)
        end)
      end

      defp can_go_in_slot_c?(current_a, current_b, item) do
        Enum.any?(@recipes, fn {{a, b, c}, _} ->
          c == item and (current_a == nil or a == current_a) and
            (current_b == nil or b == current_b)
        end)
      end

      defp recipe_output(a, b, c), do: Map.get(@recipes, {a, b, c}, a)
    end
  end

  defp wrap_creature_check(tick_body) do
    quote do
      if Spheric.Game.Creatures.has_assigned_creature?(key) do
        unquote(tick_body)
      else
        building
      end
    end
  end
end
