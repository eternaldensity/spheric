defmodule Spheric.Game.Behaviors.Refinery do
  @moduledoc """
  Refinery building behavior.

  Processes raw materials into refined products over several ticks.
  Follows the same single-input pattern as Smelter but handles
  different recipe types (liquids and compounds).
  """

  use Spheric.Game.Behaviors.Production,
    rate: 12,
    inputs: 1,
    recipes: %{
      crude_oil: :polycarbonate,
      raw_sulfur: :sulfur_compound,
      biofuel: :refined_fuel
    }
end
