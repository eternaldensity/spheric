defmodule Spheric.Game.Behaviors.Production do
  @moduledoc """
  Shared production behavior for buildings that process items.

  Provides `initial_state/0`, `tick/2`, `recipes/0`, `try_accept_item/2`,
  and `full?/1`.

  ## Options

    * `:recipes` — list of recipe maps (required). Each recipe is:
        `%{inputs: [item: qty, ...], output: {item, qty}}`
      Input slot count is derived from the max number of distinct inputs.
    * `:rate` — default processing rate in ticks (required)
    * `:requires_creature` — whether tick requires an assigned creature (default: false)

  ## Recipe format examples

      # Single-input: 1 iron_ore → 1 iron_ingot
      %{inputs: [iron_ore: 1], output: {:iron_ingot, 1}}

      # Single-input: 2 crude_oil → 1 polycarbonate
      %{inputs: [crude_oil: 2], output: {:polycarbonate, 1}}

      # Dual-input: 1 copper_ingot + 1 copper_ingot → 3 wire
      %{inputs: [copper_ingot: 1, copper_ingot: 1], output: {:wire, 3}}

      # Dual-input: 2 iron_ingot + 1 wire → 1 motor
      %{inputs: [iron_ingot: 2, wire: 1], output: {:motor, 1}}

      # Triple-input: 2 adv_circuit + 1 adv_circuit + 1 plastic_sheet → 1 computer
      %{inputs: [advanced_circuit: 2, advanced_circuit: 1, plastic_sheet: 1], output: {:computer, 1}}

  ## State shape

  All production buildings get these additional fields:
    - `input_count` (single) or `input_a_count`, `input_b_count`, `input_c_count` (multi)
    - `output_remaining` — items left to emit after the current output_buffer
    - `output_type` — the item atom being emitted (persists during drain phase)
  """

  defmacro __using__(opts) do
    # Evaluate the recipe list at compile time (it's a literal in the use opts)
    {recipes, _bindings} = Code.eval_quoted(Keyword.fetch!(opts, :recipes), [], __CALLER__)
    rate = Keyword.fetch!(opts, :rate)
    requires_creature = Keyword.get(opts, :requires_creature, false)

    # Derive slot count from the max number of inputs across all recipes
    inputs = derive_input_count(recipes)

    # Normalize recipes into internal lookup structures at compile time
    {routing_map, qty_map} = build_recipe_maps(recipes, inputs)

    common =
      quote do
        @recipes unquote(Macro.escape(recipes))
        @recipe_routing unquote(Macro.escape(routing_map))
        @recipe_quantities unquote(Macro.escape(qty_map))
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

  # Derive the number of input slots from recipes
  defp derive_input_count(recipes) do
    recipes
    |> Enum.map(fn %{inputs: inputs} -> length(inputs) end)
    |> Enum.max()
  end

  # Build two compile-time maps:
  # 1. routing_map: maps input type tuple => output atom (for slot routing and recipe lookup)
  # 2. qty_map: maps input type tuple => {[in_qty_per_slot], out_qty}
  defp build_recipe_maps(recipes, inputs) do
    Enum.reduce(recipes, {%{}, %{}}, fn %{inputs: input_list, output: {out_item, out_qty}},
                                        {routing, quantities} ->
      input_types =
        case inputs do
          1 ->
            [{type, _qty}] = input_list
            type

          2 ->
            [{t1, _q1}, {t2, _q2}] = input_list
            {t1, t2}

          3 ->
            [{t1, _q1}, {t2, _q2}, {t3, _q3}] = input_list
            {t1, t2, t3}
        end

      input_qtys = Enum.map(input_list, fn {_type, qty} -> qty end)

      routing = Map.put(routing, input_types, out_item)
      quantities = Map.put(quantities, input_types, {input_qtys, out_qty})
      {routing, quantities}
    end)
  end

  # ── Single-input buildings ──────────────────────────────────────────────────

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
        %{
          input_buffer: nil,
          input_count: 0,
          output_buffer: nil,
          output_remaining: 0,
          output_type: nil,
          progress: 0,
          rate: @default_rate,
          powered: true
        }
      end

      def tick(key, building) do
        _ = key
        unquote(tick_fn)
      end

      def try_accept_item(state, item_type) do
        case Map.get(@recipe_quantities, item_type) do
          nil ->
            # Not a valid input for any recipe
            nil

          {[required_qty], _out_qty} ->
            current_count = state[:input_count] || 0

            cond do
              state.input_buffer == nil ->
                %{state | input_buffer: item_type, input_count: 1}

              state.input_buffer == item_type and current_count < required_qty ->
                %{state | input_count: current_count + 1}

              true ->
                nil
            end
        end
      end

      def full?(state) do
        if state.input_buffer == nil do
          false
        else
          current_count = state[:input_count] || 0

          case Map.get(@recipe_quantities, state.input_buffer) do
            {[required_qty], _} -> current_count >= required_qty
            nil -> true
          end
        end
      end
    end
  end

  defp gen_single_tick do
    quote do
      state = building.state
      remaining = state[:output_remaining] || 0

      cond do
        # Phase 1: Drain — emit remaining output items one at a time
        remaining > 0 and state.output_buffer == nil ->
          %{
            building
            | state: %{
                state
                | output_buffer: state[:output_type],
                  output_remaining: remaining - 1
              }
          }

        # Phase 2: Process — inputs satisfied, no pending output
        state.input_buffer != nil and state.output_buffer == nil and remaining == 0 ->
          current_count = state[:input_count] || 1

          case Map.get(@recipe_quantities, state.input_buffer) do
            {[required_qty], out_qty} when current_count >= required_qty ->
              if state.progress + 1 >= state.rate do
                output = Map.get(@recipe_routing, state.input_buffer, state.input_buffer)

                %{
                  building
                  | state: %{
                      state
                      | input_buffer: nil,
                        input_count: 0,
                        output_buffer: output,
                        output_remaining: out_qty - 1,
                        output_type: output,
                        progress: 0
                    }
                }
              else
                %{building | state: %{state | progress: state.progress + 1}}
              end

            _ ->
              # Input count not yet satisfied, or unknown recipe — idle
              building
          end

        # Phase 3: Idle
        true ->
          building
      end
    end
  end

  # ── Dual-input buildings ────────────────────────────────────────────────────

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
        %{
          input_a: nil,
          input_a_count: 0,
          input_b: nil,
          input_b_count: 0,
          output_buffer: nil,
          output_remaining: 0,
          output_type: nil,
          progress: 0,
          rate: @default_rate,
          powered: true
        }
      end

      def tick(key, building) do
        _ = key
        unquote(tick_fn)
      end

      def try_accept_item(state, item_type) do
        a_count = state[:input_a_count] || 0
        b_count = state[:input_b_count] || 0

        cond do
          # Slot A empty — check if item can go there
          state.input_a == nil and can_go_in_slot_a?(item_type, state.input_b) ->
            %{state | input_a: item_type, input_a_count: 1}

          # Slot A occupied with same type, check if it needs more
          state.input_a == item_type and slot_a_needs_more?(state.input_a, state.input_b, a_count) ->
            %{state | input_a_count: a_count + 1}

          # Slot B empty — check if item can go there
          state.input_b == nil and can_go_in_slot_b?(state.input_a, item_type) ->
            %{state | input_b: item_type, input_b_count: 1}

          # Slot B occupied with same type, check if it needs more
          state.input_b == item_type and slot_b_needs_more?(state.input_a, state.input_b, b_count) ->
            %{state | input_b_count: b_count + 1}

          true ->
            nil
        end
      end

      defp can_go_in_slot_a?(item, current_b) do
        Enum.any?(@recipe_routing, fn {{a, b}, _} ->
          a == item and (current_b == nil or b == current_b)
        end)
      end

      defp can_go_in_slot_b?(current_a, item) do
        Enum.any?(@recipe_routing, fn {{a, b}, _} ->
          b == item and (current_a == nil or a == current_a)
        end)
      end

      defp slot_a_needs_more?(a_type, b_type, current_count) do
        Enum.any?(@recipe_quantities, fn {{a, b}, {[qa, _qb], _out}} ->
          a == a_type and (b_type == nil or b == b_type) and current_count < qa
        end)
      end

      defp slot_b_needs_more?(a_type, b_type, current_count) do
        Enum.any?(@recipe_quantities, fn {{a, b}, {[_qa, qb], _out}} ->
          b == b_type and (a_type == nil or a == a_type) and current_count < qb
        end)
      end

      defp recipe_output(a, b), do: Map.get(@recipe_routing, {a, b}, a)

      defp slots_ready?(state) do
        a = state.input_a
        b = state.input_b
        a_count = state[:input_a_count] || 0
        b_count = state[:input_b_count] || 0

        if a != nil and b != nil do
          case Map.get(@recipe_quantities, {a, b}) do
            {[qa, qb], _out} -> a_count >= qa and b_count >= qb
            nil -> false
          end
        else
          false
        end
      end

      def full?(state) do
        a = state.input_a
        b = state.input_b
        a_count = state[:input_a_count] || 0
        b_count = state[:input_b_count] || 0

        if a == nil or b == nil do
          false
        else
          case Map.get(@recipe_quantities, {a, b}) do
            {[qa, qb], _} -> a_count >= qa and b_count >= qb
            nil -> true
          end
        end
      end
    end
  end

  defp gen_dual_tick do
    quote do
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
            {_qtys, out_qty} = Map.get(@recipe_quantities, {state.input_a, state.input_b})
            output = recipe_output(state.input_a, state.input_b)

            %{
              building
              | state: %{
                  state
                  | input_a: nil,
                    input_a_count: 0,
                    input_b: nil,
                    input_b_count: 0,
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
  end

  # ── Triple-input buildings ──────────────────────────────────────────────────

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

      def tick(key, building) do
        _ = key
        unquote(tick_fn)
      end

      def try_accept_item(state, item_type) do
        a_count = state[:input_a_count] || 0
        b_count = state[:input_b_count] || 0
        c_count = state[:input_c_count] || 0

        cond do
          # Slot A empty
          state.input_a == nil and
              can_go_in_slot_a?(item_type, state.input_b, state.input_c) ->
            %{state | input_a: item_type, input_a_count: 1}

          # Slot A needs more
          state.input_a == item_type and
              slot_a_needs_more?(state.input_a, state.input_b, state.input_c, a_count) ->
            %{state | input_a_count: a_count + 1}

          # Slot B empty
          state.input_b == nil and
              can_go_in_slot_b?(state.input_a, item_type, state.input_c) ->
            %{state | input_b: item_type, input_b_count: 1}

          # Slot B needs more
          state.input_b == item_type and
              slot_b_needs_more?(state.input_a, state.input_b, state.input_c, b_count) ->
            %{state | input_b_count: b_count + 1}

          # Slot C empty
          state.input_c == nil and
              can_go_in_slot_c?(state.input_a, state.input_b, item_type) ->
            %{state | input_c: item_type, input_c_count: 1}

          # Slot C needs more
          state.input_c == item_type and
              slot_c_needs_more?(state.input_a, state.input_b, state.input_c, c_count) ->
            %{state | input_c_count: c_count + 1}

          true ->
            nil
        end
      end

      defp can_go_in_slot_a?(item, current_b, current_c) do
        Enum.any?(@recipe_routing, fn {{a, b, c}, _} ->
          a == item and (current_b == nil or b == current_b) and
            (current_c == nil or c == current_c)
        end)
      end

      defp can_go_in_slot_b?(current_a, item, current_c) do
        Enum.any?(@recipe_routing, fn {{a, b, c}, _} ->
          b == item and (current_a == nil or a == current_a) and
            (current_c == nil or c == current_c)
        end)
      end

      defp can_go_in_slot_c?(current_a, current_b, item) do
        Enum.any?(@recipe_routing, fn {{a, b, c}, _} ->
          c == item and (current_a == nil or a == current_a) and
            (current_b == nil or b == current_b)
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

      defp recipe_output(a, b, c), do: Map.get(@recipe_routing, {a, b, c}, a)

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
    end
  end

  defp gen_triple_tick do
    quote do
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
