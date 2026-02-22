defmodule Spheric.Game.Behaviors.ParanaturalSynthesizer do
  @moduledoc """
  Paranatural Synthesizer building behavior.

  Triple-input building for Tier 7 paranatural recipes. Requires
  an assigned creature to function -- the building will not process
  without a creature assigned.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 30,
    requires_creature: true,
    recipes: [
      %{inputs: [supercomputer: 1, advanced_composite: 1, creature_essence: 1], output: {:containment_module, 1}},
      %{inputs: [nuclear_cell: 1, containment_module: 1, creature_essence: 1], output: {:dimensional_core, 1}},
      %{inputs: [quartz_crystal: 1, quartz_crystal: 1, creature_essence: 1], output: {:astral_lens, 1}}
    ]
end
