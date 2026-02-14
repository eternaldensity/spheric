defmodule Spheric.Game.Behaviors.DefenseTurret do
  @moduledoc """
  Defense Turret behavior.

  Auto-attacks Hiss entities within radius 3. When a Hiss entity is killed,
  drops `hiss_residue` into the turret's output buffer (research material).

  Combat logic is processed by the Hiss module. The turret behavior
  manages the output buffer for hiss_residue drops.

  State:
  - output_buffer: nil or :hiss_residue
  - kills: total kills counter
  - rate: not used for production, but kept for consistency
  """

  @doc "Initial state for a newly placed defense turret."
  def initial_state do
    %{
      output_buffer: nil,
      kills: 0,
      rate: 1
    }
  end
end
