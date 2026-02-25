defmodule Spheric.Game.Behaviors.OverflowGate do
  @moduledoc """
  Overflow gate building behavior.

  Items enter from the rear. Primary output is forward (orientation direction)
  — items pass through freely. When forward is full/blocked, items overflow
  to the left side instead (or right when mirrored). If both are full, the item is held.

  Output directions relative to orientation `d`:
    - Primary (forward):  d
    - Overflow (left):    (d + 3) rem 4
    - Overflow mirrored:  (d + 1) rem 4
  Input: rear (d + 2) rem 4
  """

  @upgrade_costs %{
    mirror_mode: %{circuit: 1, plate: 1}
  }

  @doc "Returns the initial state for a newly placed overflow gate."
  def initial_state do
    %{item: nil, mirrored: false, upgrade_progress: nil}
  end

  @doc "Returns available upgrades as `{upgrade_atom, state_field}` tuples."
  def upgrades, do: [{:mirror_mode, :mirrored}]

  @doc "Returns the upgrade cost for the given upgrade type."
  def upgrade_cost(upgrade), do: Map.get(@upgrade_costs, upgrade, %{})

  @doc "Returns the overflow output direction for the given orientation."
  def overflow_direction(orientation) do
    rem(orientation + 3, 4)
  end
end
