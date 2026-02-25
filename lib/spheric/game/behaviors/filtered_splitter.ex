defmodule Spheric.Game.Behaviors.FilteredSplitter do
  @moduledoc """
  Filtered splitter building behavior.

  Routes items by type: items matching `filter_item` go left,
  everything else goes right. When no filter is set, alternates
  like a regular splitter.

  Upgrades:
    - Mirror mode: swaps left/right outputs
    - Dual filter: adds a right-side filter; non-matching goes forward

  Output directions relative to orientation `d`:
    - Left (matching):  (d + 3) rem 4
    - Right (non-matching): (d + 1) rem 4
    - Forward (dual filter non-matching): d
  Input: rear (d + 2) rem 4
  """

  @upgrade_costs %{
    mirror_mode: %{circuit: 1, plate: 1},
    dual_filter: %{circuit: 3, frame: 2}
  }

  @doc "Returns the initial state for a newly placed filtered splitter."
  def initial_state do
    %{item: nil, filter_item: nil, next_output: :left, mirrored: false, dual_filter: false, filter_item_right: nil}
  end

  @doc "Returns the upgrade cost for the given upgrade type."
  def upgrade_cost(upgrade), do: Map.get(@upgrade_costs, upgrade, %{})

  @doc "Returns the two output directions for the given orientation."
  def output_directions(orientation) do
    left = rem(orientation + 3, 4)
    right = rem(orientation + 1, 4)
    {left, right}
  end

  @doc "Returns all three output directions for the given orientation (dual filter mode)."
  def all_output_directions(orientation) do
    left = rem(orientation + 3, 4)
    right = rem(orientation + 1, 4)
    forward = orientation
    {left, right, forward}
  end
end
