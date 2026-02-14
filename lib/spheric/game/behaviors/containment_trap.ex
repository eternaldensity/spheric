defmodule Spheric.Game.Behaviors.ContainmentTrap do
  @moduledoc """
  Containment Trap behavior.

  Captures wild creatures within a radius of 3 tiles over time.
  The trap doesn't produce or consume items — it passively captures
  nearby wild creatures and adds them to the owner's roster.

  State:
  - `capturing` — ID of the creature currently being captured (or nil)
  - `capture_progress` — ticks spent capturing the current target (0..15)
  """

  @doc "Returns the initial state for a new containment trap."
  def initial_state do
    %{
      capturing: nil,
      capture_progress: 0
    }
  end
end
