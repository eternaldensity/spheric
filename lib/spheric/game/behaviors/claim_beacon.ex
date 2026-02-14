defmodule Spheric.Game.Behaviors.ClaimBeacon do
  @moduledoc """
  Claim Beacon building behavior.

  Establishes player territory within a radius of 8 tiles.
  Only the territory owner can build within claimed tiles.
  The beacon itself is passive — no tick processing needed.

  State:
  - radius: integer — the territory radius (default 8)
  - active: boolean — whether the territory claim is active
  """

  @doc "Returns the initial state for a newly placed claim beacon."
  def initial_state do
    %{radius: 8, active: true}
  end
end
