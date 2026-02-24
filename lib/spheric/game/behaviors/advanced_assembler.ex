defmodule Spheric.Game.Behaviors.AdvancedAssembler do
  @moduledoc """
  Advanced Assembler building behavior.

  Dual-input assembler for Tier 4 recipes. Faster than standard assembler.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 12,
    recipes: [
      %{inputs: [frame: 2, reinforced_plate: 6], output: {:heavy_frame, 1}},
      %{inputs: [circuit: 4, cable: 6], output: {:advanced_circuit, 2}},
      %{inputs: [polycarbonate: 10, sulfur_compound: 15], output: {:plastic_sheet, 5}}
    ]
end
