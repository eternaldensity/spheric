defmodule Spheric.Game.Behaviors.Balancer do
  @moduledoc """
  Balancer building behavior.

  A smart splitter that routes items to the less-full downstream building.
  Accepts items from the rear and outputs to left or right based on
  downstream availability. Falls back to alternating if both sides
  are equally available.

  Output directions relative to orientation `d`:
    - Left:  (d + 3) rem 4
    - Right: (d + 1) rem 4
  """

  @doc "Returns the initial state for a newly placed balancer."
  def initial_state do
    %{item: nil, last_output: :left}
  end

  @doc "Returns the two output directions for a balancer with the given orientation."
  def output_directions(orientation) do
    left = rem(orientation + 3, 4)
    right = rem(orientation + 1, 4)
    {left, right}
  end
end
