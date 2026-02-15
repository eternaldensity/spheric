defmodule Spheric.Game.Behaviors.NuclearRefinery do
  @moduledoc """
  Nuclear Refinery building behavior.

  Single-input refinery for nuclear materials. Handles uranium
  enrichment and other nuclear processing recipes.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 20,
    inputs: 1,
    recipes: %{
      raw_uranium: :enriched_uranium
    }
end
