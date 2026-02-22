defmodule Spheric.Game.Behaviors.Assembler do
  @moduledoc """
  Assembler building behavior.

  Accepts two different input items (input_a and input_b) and combines
  them into a component over several ticks. Each recipe defines which
  item type goes into which slot and how many of each are needed.

  Input direction: rear (opposite of orientation), same as Splitter.
  Items are routed to whichever input slot (a or b) matches the recipe.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 15,
    recipes: [
      %{inputs: [copper_ingot: 1, copper_ingot: 1], output: {:wire, 3}},
      %{inputs: [iron_ingot: 1, iron_ingot: 1], output: {:plate, 2}},
      %{inputs: [wire: 1, quartz_crystal: 1], output: {:circuit, 1}},
      %{inputs: [plate: 1, titanium_ingot: 1], output: {:frame, 1}},
      %{inputs: [iron_ingot: 2, wire: 1], output: {:motor, 1}},
      %{inputs: [wire: 1, polycarbonate: 1], output: {:cable, 1}},
      %{inputs: [plate: 2, iron_ingot: 1], output: {:reinforced_plate, 1}},
      %{inputs: [copper_ingot: 1, sulfur_compound: 1], output: {:heat_sink, 1}}
    ]
end
