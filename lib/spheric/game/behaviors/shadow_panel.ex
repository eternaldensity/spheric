defmodule Spheric.Game.Behaviors.ShadowPanel do
  @moduledoc """
  Shadow Panel building behavior.

  Passive generator that produces power when its face is in shadow
  (sun on the far side of the sphere). Disabled if a powered lamp
  is within radius 3.
  """

  alias Spheric.Game.ShiftCycle

  @lamp_suppress_radius 3

  def initial_state do
    %{power_output: 0, rate: 1}
  end

  def tick({face, _row, _col} = key, building) do
    producing = ShiftCycle.dark?(face) and not lamp_nearby?(key)
    new_output = if producing, do: 1, else: 0

    if new_output != building.state.power_output do
      %{building | state: %{building.state | power_output: new_output}}
    else
      building
    end
  end

  @doc "Check if the shadow panel is currently producing power."
  def producing_power?(state), do: state.power_output > 0

  @doc "Radius within which a powered lamp suppresses this panel."
  def lamp_suppress_radius, do: @lamp_suppress_radius

  # Check if any powered lamp building exists within suppress radius
  defp lamp_nearby?({face, row, col}) do
    alias Spheric.Game.{WorldStore, Power}

    for r <- (row - @lamp_suppress_radius)..(row + @lamp_suppress_radius),
        c <- (col - @lamp_suppress_radius)..(col + @lamp_suppress_radius),
        r >= 0 and c >= 0 and r < 64 and c < 64,
        {r, c} != {row, col} do
      key = {face, r, c}
      building = WorldStore.get_building(key)
      building != nil and building.type == :lamp and Power.powered?(key)
    end
    |> Enum.any?()
  end
end
