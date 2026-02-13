defmodule Spheric.Game.Behaviors.Conveyor do
  @moduledoc """
  Conveyor building behavior.

  Conveyors are passive -- their movement is handled entirely in the
  push-resolution phase of TickProcessor. This module provides the
  initial state definition.
  """

  @doc "Returns the initial state for a newly placed conveyor."
  def initial_state do
    %{item: nil}
  end
end
