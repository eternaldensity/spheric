defmodule Spheric.Game.Behaviors.ParticleCollider do
  @moduledoc """
  Particle Collider building behavior.

  Dual-input processing for Tier 6 high-tech recipes.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 25,
    recipes: [
      %{inputs: [computer: 10, advanced_circuit: 20], output: {:supercomputer, 1}},
      %{inputs: [composite: 1, quartz_crystal: 2], output: {:advanced_composite, 1}},
      %{inputs: [enriched_uranium: 10, advanced_composite: 3], output: {:nuclear_cell, 1}}
    ]
end
