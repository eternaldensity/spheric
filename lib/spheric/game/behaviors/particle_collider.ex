defmodule Spheric.Game.Behaviors.ParticleCollider do
  @moduledoc """
  Particle Collider building behavior.

  Dual-input processing for Tier 6 high-tech recipes.
  """

  use Spheric.Game.Behaviors.Production,
    rate: 25,
    inputs: 2,
    recipes: %{
      {:computer, :advanced_circuit} => :supercomputer,
      {:composite, :quartz_crystal} => :advanced_composite,
      {:enriched_uranium, :advanced_composite} => :nuclear_cell
    }
end
