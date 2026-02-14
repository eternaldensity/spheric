defmodule Spheric.Game.Behaviors.ConveyorMk3 do
  @moduledoc """
  Conveyor Mk3 building behavior.

  The fastest conveyor with a 3-item internal buffer. Items entering push
  the buffer forward, enabling maximum throughput. The 3-slot buffer
  allows continuous item flow without gaps.
  """

  @doc "Returns the initial state for a newly placed Mk3 conveyor."
  def initial_state do
    %{item: nil, buffer1: nil, buffer2: nil}
  end
end
