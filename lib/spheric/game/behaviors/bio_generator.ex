defmodule Spheric.Game.Behaviors.BioGenerator do
  @moduledoc """
  Bio Generator building behavior.

  Consumes fuel items (biofuel, refined_fuel, catalysed_fuel, unstable_fuel or stable_fuel) and generates power.
  Power is distributed via the power network (substations/transfer stations).
  """

  @biofuel_duration 50
  @catalysed_fuel_duration 75
  @refined_fuel_duration 100
  @unstable_fuel_duration 20
  @stable_fuel_duration 325

  def initial_state do
    %{
      input_buffer: nil,
      fuel_type: nil,
      fuel_remaining: 0,
      power_output: 0,
      rate: 1,
      powered: true
    }
  end

  def tick(_key, building) do
    state = building.state

    cond do
      # Currently burning fuel
      state.fuel_remaining > 0 ->
        new_remaining = state.fuel_remaining - 1

        if new_remaining <= 0 do
          %{building | state: %{state | fuel_remaining: 0, fuel_type: nil, power_output: 0}}
        else
          building
        end

      # No fuel burning, but have fuel in input buffer
      state.input_buffer != nil ->
        base_duration = fuel_duration(state.input_buffer)

        # Object of Power: Power Surge gives +25% fuel duration
        duration =
          if building[:owner_id] &&
               Spheric.Game.ObjectsOfPower.player_has?(building.owner_id, :power_surge) do
            round(base_duration * 1.25)
          else
            base_duration
          end

        %{
          building
          | state: %{
              state
              | input_buffer: nil,
                fuel_type: state.input_buffer,
                fuel_remaining: duration,
                power_output: 1
            }
        }

      # No fuel at all
      true ->
        building
    end
  end

  @doc "Check if the generator is currently producing power."
  def producing_power?(state), do: state.fuel_remaining > 0

  @doc "Returns accepted fuel types."
  def fuel_types, do: [:biofuel, :catalysed_fuel, :refined_fuel, :unstable_fuel, :stable_fuel]

  @doc "Check if an item is valid fuel."
  def valid_fuel?(item), do: item in [:biofuel, :catalysed_fuel, :refined_fuel, :unstable_fuel, :stable_fuel]

  @doc "Returns the fuel duration for a given fuel type."
  def fuel_duration(:biofuel), do: @biofuel_duration
  def fuel_duration(:catalysed_fuel), do: @catalysed_fuel_duration
  def fuel_duration(:refined_fuel), do: @refined_fuel_duration
  def fuel_duration(:unstable_fuel), do: @unstable_fuel_duration
  def fuel_duration(:stable_fuel), do: @stable_fuel_duration
  def fuel_duration(_), do: 0
end
