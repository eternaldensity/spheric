defmodule Spheric.Game.Behaviors.AdvancedSmelter do
  @moduledoc """
  Advanced Smelter building behavior.

  Handles all standard smelter recipes plus advanced recipes like
  uranium processing. Faster base rate than standard smelter.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 8,
    recipes: [
      %{inputs: [iron_ore: 1], output: {:iron_ingot, 1}},
      %{inputs: [copper_ore: 1], output: {:copper_ingot, 1}},
      %{inputs: [titanium_ore: 1], output: {:titanium_ingot, 1}},
      %{inputs: [raw_quartz: 1], output: {:quartz_crystal, 1}},
      %{inputs: [raw_uranium: 4], output: {:enriched_uranium, 1}}
    ]
end
