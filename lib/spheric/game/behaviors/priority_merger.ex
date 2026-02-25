defmodule Spheric.Game.Behaviors.PriorityMerger do
  @moduledoc """
  Priority merger building behavior.

  Accepts items from two side inputs with priority. The LEFT input
  always takes priority — the right input is only accepted when no
  item is pending from the left side. When mirrored, right has priority.

  Input directions relative to orientation `d`:
    - Priority (left):  (d + 3) rem 4
    - Secondary (right): (d + 1) rem 4
  Output: orientation direction `d`
  """

  @upgrade_costs %{
    mirror_mode: %{circuit: 1, plate: 1}
  }

  @doc "Returns the initial state for a newly placed priority merger."
  def initial_state do
    %{item: nil, mirrored: false}
  end

  @doc "Returns the upgrade cost for the given upgrade type."
  def upgrade_cost(upgrade), do: Map.get(@upgrade_costs, upgrade, %{})
end
