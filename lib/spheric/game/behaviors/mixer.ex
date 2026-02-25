defmodule Spheric.Game.Behaviors.Mixer do
  @moduledoc """
  Mixer building behavior.

  A dual-input processing building for combining two different materials.
  Higher tier than the Refinery, handles mixed-ingredient recipes that
  require two distinct input types.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 15,
    recipes: [
      %{inputs: [crude_oil: 1, titanium_ingot: 1], output: {:catalysed_fuel, 1}}
    ]
end
