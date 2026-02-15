defmodule Spheric.Game.Behaviors.Smelter do
  @moduledoc """
  Smelter building behavior.

  Accepts ore in its input buffer, processes it over several ticks,
  then places the resulting ingot in the output buffer.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 10,
    inputs: 1,
    recipes: %{
      iron_ore: :iron_ingot,
      copper_ore: :copper_ingot,
      titanium_ore: :titanium_ingot,
      raw_quartz: :quartz_crystal
    }
end
