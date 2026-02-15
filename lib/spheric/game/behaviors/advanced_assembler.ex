defmodule Spheric.Game.Behaviors.AdvancedAssembler do
  @moduledoc """
  Advanced Assembler building behavior.

  Dual-input assembler for Tier 4 recipes. Faster than standard assembler.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 12,
    inputs: 2,
    recipes: %{
      {:frame, :reinforced_plate} => :heavy_frame,
      {:circuit, :cable} => :advanced_circuit,
      {:polycarbonate, :sulfur_compound} => :plastic_sheet
    }
end
