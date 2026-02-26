defmodule Spheric.Game.Behaviors.Freezer do
  @moduledoc """
  Freezer building behavior.

  A dual-input cryogenic processing building that produces two output types
  per recipe cycle. Takes ice and thermal slurry, outputs water and coolant cubes.
  Coolant cubes are used in nuclear reactor recipes.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 20,
    recipes: [
      %{inputs: [ice: 5, thermal_slurry: 3], output: [{:water, 5}, {:coolant_cube, 1}]}
    ]
end
