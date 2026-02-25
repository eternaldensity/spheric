defmodule Spheric.Game.Behaviors.Loader do
  @moduledoc """
  Loader (Insertion Arm) building behavior.

  Takes items from a linked storage container and puts them into a
  destination tile (machine input, belt, or ground). Both source and
  destination must be within Manhattan distance 2 on the same face.

  State:
    - source: {face, row, col} | nil  -- storage to pull from
    - destination: {face, row, col} | nil  -- where to insert items
    - stack_upgrade: boolean  -- bulk transfer (multiple items/tick)
    - last_transferred: atom | nil  -- last item moved (for status)
    - powered: boolean  -- requires power to operate
  """

  @upgrade_costs %{
    stack_upgrade: %{motor: 1, cable: 2, circuit: 1, whispering_ingot: 1}
  }

  def initial_state do
    %{
      source: nil,
      destination: nil,
      stack_upgrade: false,
      last_transferred: nil,
      powered: true
    }
  end

  @doc "Returns the resource cost map for a given upgrade."
  def upgrade_cost(upgrade), do: Map.get(@upgrade_costs, upgrade, %{})
end
