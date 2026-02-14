defmodule Spheric.Game.Behaviors.Crossover do
  @moduledoc """
  Crossover conveyor — two perpendicular streams pass through without merging.

  Items entering horizontally (directions 0/2) use the `horizontal` slot.
  Items entering vertically (directions 1/3) use the `vertical` slot.
  Each slot pushes its item out the opposite side (passthrough).
  """

  def initial_state do
    %{horizontal: nil, vertical: nil, h_dir: nil, v_dir: nil}
  end
end
