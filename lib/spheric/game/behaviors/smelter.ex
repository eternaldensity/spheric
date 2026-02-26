defmodule Spheric.Game.Behaviors.Smelter do
  @moduledoc """
  Smelter building behavior.

  Accepts ore in its input buffer, processes it over several ticks,
  then places the resulting ingot in the output buffer.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 10,
    recipes: [
      %{inputs: [iron_ore: 1], output: {:iron_ingot, 1}},
      %{inputs: [copper_ore: 1], output: {:copper_ingot, 1}},
      %{inputs: [titanium_ore: 1], output: {:titanium_ingot, 1}},
      %{inputs: [raw_quartz: 2], output: {:quartz_crystal, 1}},
      %{inputs: [ice: 1], output: {:water, 1}}
    ]
end
