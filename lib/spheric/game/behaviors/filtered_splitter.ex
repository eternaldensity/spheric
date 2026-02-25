defmodule Spheric.Game.Behaviors.FilteredSplitter do
  @moduledoc """
  Filtered splitter building behavior.

  Routes items by type: items matching `filter_item` go left,
  everything else goes right. When no filter is set, alternates
  like a regular splitter.

  Output directions relative to orientation `d`:
    - Left (matching):  (d + 3) rem 4
    - Right (non-matching): (d + 1) rem 4
  Input: rear (d + 2) rem 4
  """

  @doc "Returns the initial state for a newly placed filtered splitter."
  def initial_state do
    %{item: nil, filter_item: nil, next_output: :left}
  end

  @doc "Returns the two output directions for the given orientation."
  def output_directions(orientation) do
    left = rem(orientation + 3, 4)
    right = rem(orientation + 1, 4)
    {left, right}
  end
end
