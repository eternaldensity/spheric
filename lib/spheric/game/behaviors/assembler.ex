defmodule Spheric.Game.Behaviors.Assembler do
  @moduledoc """
  Assembler building behavior.

  Accepts two different input items (input_a and input_b) and combines
  them into a component over several ticks. Each recipe defines which
  item type goes into which slot.

  Input direction: rear (opposite of orientation), same as Splitter.
  Items are routed to whichever input slot (a or b) matches the recipe.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 15,
    inputs: 2,
    recipes: %{
      {:copper_ingot, :copper_ingot} => :wire,
      {:iron_ingot, :iron_ingot} => :plate,
      {:wire, :quartz_crystal} => :circuit,
      {:plate, :titanium_ingot} => :frame,
      {:iron_ingot, :wire} => :motor,
      {:wire, :polycarbonate} => :cable,
      {:plate, :iron_ingot} => :reinforced_plate,
      {:copper_ingot, :sulfur_compound} => :heat_sink
    }
end
