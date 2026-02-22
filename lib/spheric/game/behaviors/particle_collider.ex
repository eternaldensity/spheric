defmodule Spheric.Game.Behaviors.ParticleCollider do
  @moduledoc """
  Particle Collider building behavior.

  Dual-input processing for Tier 6 high-tech recipes.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 25,
    recipes: [
      %{inputs: [computer: 1, advanced_circuit: 2], output: {:supercomputer, 1}},
      %{inputs: [composite: 1, quartz_crystal: 1], output: {:advanced_composite, 1}},
      %{inputs: [enriched_uranium: 1, advanced_composite: 1], output: {:nuclear_cell, 1}}
    ]
end
