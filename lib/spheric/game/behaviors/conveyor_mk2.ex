defmodule Spheric.Game.Behaviors.ConveyorMk2 do
  @moduledoc """
  Conveyor Mk2 building behavior.

  A faster conveyor with a 2-item internal buffer. Items entering push
  the buffer forward, enabling higher throughput than standard conveyors.
  Movement is handled by the push-resolution phase of TickProcessor,
  but the 2-slot buffer allows accepting a new item while still holding one.
  """

  @doc "Returns the initial state for a newly placed Mk2 conveyor."
  def initial_state do
    %{item: nil, buffer: nil}
  end
end
