defmodule Spheric.Game.Behaviors.Splitter do
  @moduledoc """
  Splitter building behavior.

  Accepts items from the rear (opposite of orientation) and alternates
  pushing them to the left and right output directions.

  Output directions relative to orientation `d`:
    - Left:  (d + 3) rem 4
    - Right: (d + 1) rem 4
  """

  @doc "Returns the initial state for a newly placed splitter."
  def initial_state do
    %{item: nil, next_output: :left}
  end

  @doc "Returns the two output directions for a splitter with the given orientation."
  def output_directions(orientation) do
    left = rem(orientation + 3, 4)
    right = rem(orientation + 1, 4)
    {left, right}
  end
end
