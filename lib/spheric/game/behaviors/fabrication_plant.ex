defmodule Spheric.Game.Behaviors.FabricationPlant do
  @moduledoc """
  Fabrication Plant building behavior.

  Triple-input assembler for Tier 5 recipes. Accepts three different
  inputs and combines them into advanced components.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 20,
    recipes: [
      %{inputs: [advanced_circuit: 3, advanced_circuit: 3, plastic_sheet: 4], output: {:computer, 1}},
      %{inputs: [heavy_frame: 5, motor: 1, heat_sink: 2], output: {:motor_housing, 1}},
      %{inputs: [reinforced_plate: 6, plastic_sheet: 2, titanium_ingot: 1], output: {:composite, 1}},
      %{inputs: [ice: 1, plastic_sheet: 1, coolant_cube: 1], output: {:coolant_rod, 1}},
      %{inputs: [water: 1, plastic_sheet: 1, heat_sink: 1], output: {:thermal_regulator, 1}}
    ]
end
