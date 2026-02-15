defmodule Spheric.Game.Behaviors.FabricationPlant do
  @moduledoc """
  Fabrication Plant building behavior.

  Triple-input assembler for Tier 5 recipes. Accepts three different
  inputs and combines them into advanced components.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 20,
    inputs: 3,
    recipes: %{
      {:advanced_circuit, :advanced_circuit, :plastic_sheet} => :computer,
      {:heavy_frame, :motor, :heat_sink} => :motor_housing,
      {:reinforced_plate, :plastic_sheet, :titanium_ingot} => :composite
    }
end
