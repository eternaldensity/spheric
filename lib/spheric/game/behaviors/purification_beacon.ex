defmodule Spheric.Game.Behaviors.PurificationBeacon do
  @moduledoc """
  Purification Beacon behavior.

  Creates a corruption-immune zone (radius 5) and slowly pushes back
  corruption within its range. Passive building — purification logic
  is handled by the Hiss module during the corruption phase.

  State:
  - active: always true once placed
  - radius: 5 (the immune zone radius)
  """

  @doc "Initial state for a newly placed purification beacon."
  def initial_state do
    %{
      active: true,
      radius: 5
    }
  end
end
