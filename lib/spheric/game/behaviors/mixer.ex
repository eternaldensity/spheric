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
      %{inputs: [crude_oil: 1, titanium_ingot: 1], output: {:catalysed_fuel, 1}},
      %{inputs: [catalysed_fuel: 8, refined_fuel: 8], output: {:unstable_fuel, 16}},
      %{inputs: [unstable_fuel: 5, sulfur_compound: 1], output: {:stable_fuel, 2}},
      %{inputs: [water: 10, titanium_dust: 2], output: {:thermal_slurry, 10}}
    ]
end
