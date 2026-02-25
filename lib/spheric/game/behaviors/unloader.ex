defmodule Spheric.Game.Behaviors.Unloader do
  @moduledoc """
  Unloader (Extraction Arm) building behavior.

  Takes items from a linked source tile (machine output, belt, or
  ground) and puts them into a linked storage container. Both source
  and destination must be within Manhattan distance 2 on the same face.

  State:
    - source: {face, row, col} | nil  -- where to grab items from
    - destination: {face, row, col} | nil  -- storage to fill
    - stack_upgrade: boolean  -- bulk transfer (multiple items/tick)
    - last_transferred: atom | nil  -- last item moved (for status)
    - powered: boolean  -- requires power to operate
  """

  def initial_state do
    %{
      source: nil,
      destination: nil,
      stack_upgrade: false,
      last_transferred: nil,
      powered: true
    }
  end
end
