defmodule Spheric.Game.Behaviors.ParanaturalSynthesizer do
  @moduledoc """
  Paranatural Synthesizer building behavior.

  Triple-input building for Tier 7 paranatural recipes. Requires
  an assigned creature to function -- the building will not process
  without a creature assigned.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 30,
    inputs: 3,
    requires_creature: true,
    recipes: %{
      {:supercomputer, :advanced_composite, :creature_essence} => :containment_module,
      {:nuclear_cell, :containment_module, :creature_essence} => :dimensional_core,
      {:quartz_crystal, :quartz_crystal, :creature_essence} => :astral_lens
    }
end
