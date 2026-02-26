defmodule Spheric.Game.Behaviors.ShadowPanel do
  @moduledoc """
  Shadow Panel building behavior.

  Passive generator that produces power when its cell is in shadow
  (sun on the far side of the sphere). Uses per-cell illumination
  for 16× finer shadow boundaries than per-face. Disabled if a
  powered lamp is within radius 3.
  """

  alias Spheric.Game.ShiftCycle

  @lamp_suppress_radius 3
  # Max scan radius accounts for area-boosted lamps (base 3 * max ~2.8x = ~9)
  @lamp_scan_radius 9
  @max_output 10
  # Full output below this illumination, ramps to 0 at @cutoff
  @dark_threshold 0.15
  @cutoff 0.50

  def initial_state do
    %{power_output: 0, rate: 1}
  end

  def tick({face, row, col} = key, building) do
    new_output =
      if lamp_nearby?(key) do
        0
      else
        illumination = ShiftCycle.tile_illumination(face, row, col)
        output_for_illumination(illumination)
      end

    if new_output != building.state.power_output do
      %{building | state: %{building.state | power_output: new_output}}
    else
      building
    end
  end

  @doc "Compute wattage output for a given illumination level (0.0–1.0)."
  def output_for_illumination(illumination) when illumination < @dark_threshold, do: @max_output

  def output_for_illumination(illumination) when illumination >= @cutoff, do: 0

  def output_for_illumination(illumination) do
    # Linear ramp: 10W at threshold, 0W at cutoff
    t = (illumination - @dark_threshold) / (@cutoff - @dark_threshold)
    round(@max_output * (1.0 - t))
  end

  @doc "Check if the shadow panel is currently producing power."
  def producing_power?(state), do: state.power_output > 0

  @doc "Radius within which a powered lamp suppresses this panel."
  def lamp_suppress_radius, do: @lamp_suppress_radius

  # Check if any powered lamp building exists within its effective suppress radius.
  # Scans a wider area to account for area-boosted lamps, then checks per-lamp distance.
  defp lamp_nearby?({face, row, col}) do
    alias Spheric.Game.{WorldStore, Power}
    alias Spheric.Game.Behaviors.Lamp

    Enum.any?(
      for r <- (row - @lamp_scan_radius)..(row + @lamp_scan_radius),
          c <- (col - @lamp_scan_radius)..(col + @lamp_scan_radius),
          r >= 0 and c >= 0 and r < 64 and c < 64,
          {r, c} != {row, col} do
        lamp_key = {face, r, c}
        building = WorldStore.get_building(lamp_key)

        if building != nil and building.type == :lamp and Power.powered?(lamp_key) do
          eff_radius = Lamp.effective_radius(lamp_key, building[:owner_id])
          abs(r - row) <= eff_radius and abs(c - col) <= eff_radius
        else
          false
        end
      end
    )
  end
end
