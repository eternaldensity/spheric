defmodule Spheric.Game.Behaviors.OverflowGate do
  @moduledoc """
  Overflow gate building behavior.

  Items enter from the rear. Primary output is forward (orientation direction)
  — items pass through freely. When forward is full/blocked, items overflow
  to the left side instead. If both are full, the item is held.

  Output directions relative to orientation `d`:
    - Primary (forward):  d
    - Overflow (left):    (d + 3) rem 4
  Input: rear (d + 2) rem 4
  """

  @doc "Returns the initial state for a newly placed overflow gate."
  def initial_state do
    %{item: nil}
  end

  @doc "Returns the overflow output direction for the given orientation."
  def overflow_direction(orientation) do
    rem(orientation + 3, 4)
  end
end
