defmodule Spheric.Game.Behaviors.AdvancedAssembler do
  @moduledoc """
  Advanced Assembler building behavior.

  Dual-input assembler for Tier 4 recipes. Faster than standard assembler.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 12,
    recipes: [
      %{inputs: [frame: 1, reinforced_plate: 1], output: {:heavy_frame, 1}},
      %{inputs: [circuit: 2, cable: 1], output: {:advanced_circuit, 1}},
      %{inputs: [polycarbonate: 1, sulfur_compound: 1], output: {:plastic_sheet, 1}}
    ]
end
