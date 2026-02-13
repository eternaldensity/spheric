defmodule Spheric.Game.Behaviors.Merger do
  @moduledoc """
  Merger building behavior.

  Accepts items from two side inputs and pushes them out in the
  orientation direction. Acts like a conveyor with two valid input sides.

  Input directions relative to orientation `d`:
    - Left input:  (d + 3) rem 4
    - Right input: (d + 1) rem 4
  Output: orientation direction `d`
  """

  @doc "Returns the initial state for a newly placed merger."
  def initial_state do
    %{item: nil}
  end
end
