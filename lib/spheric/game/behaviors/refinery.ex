defmodule Spheric.Game.Behaviors.Refinery do
  @moduledoc """
  Refinery building behavior.

  Processes raw materials into refined products over several ticks.
  Follows the same single-input pattern as Smelter but handles
  different recipe types (liquids and compounds).
  """

  use Spheric.Game.Behaviors.Production,
    rate: 12,
    recipes: [
      %{inputs: [crude_oil: 2], output: {:polycarbonate, 1}},
      %{inputs: [raw_sulfur: 1], output: {:sulfur_compound, 1}},
      %{inputs: [biofuel: 3], output: {:refined_fuel, 2}}
    ]
end
