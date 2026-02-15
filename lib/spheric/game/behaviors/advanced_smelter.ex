defmodule Spheric.Game.Behaviors.AdvancedSmelter do
  @moduledoc """
  Advanced Smelter building behavior.

  Handles all standard smelter recipes plus advanced recipes like
  uranium processing. Faster base rate than standard smelter.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 8,
    inputs: 1,
    recipes: %{
      iron_ore: :iron_ingot,
      copper_ore: :copper_ingot,
      titanium_ore: :titanium_ingot,
      raw_quartz: :quartz_crystal,
      raw_uranium: :enriched_uranium
    }
end
