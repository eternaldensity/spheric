defmodule Spheric.Game.Behaviors.NuclearRefinery do
  @moduledoc """
  Nuclear Refinery building behavior.

  Single-input refinery for nuclear materials. Handles uranium
  enrichment and other nuclear processing recipes.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 20,
    recipes: [
      %{inputs: [raw_uranium: 1], output: {:enriched_uranium, 1}}
    ]
end
