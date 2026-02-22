defmodule Spheric.Game.Behaviors.FabricationPlant do
  @moduledoc """
  Fabrication Plant building behavior.

  Triple-input assembler for Tier 5 recipes. Accepts three different
  inputs and combines them into advanced components.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 20,
    recipes: [
      %{inputs: [advanced_circuit: 2, advanced_circuit: 1, plastic_sheet: 1], output: {:computer, 1}},
      %{inputs: [heavy_frame: 1, motor: 1, heat_sink: 1], output: {:motor_housing, 1}},
      %{inputs: [reinforced_plate: 1, plastic_sheet: 1, titanium_ingot: 1], output: {:composite, 1}}
    ]
end
