defmodule Spheric.Game.Behaviors.Lamp do
  @moduledoc """
  Lamp building behavior.

  Passive power consumer that illuminates nearby tiles when powered.
  Its presence within radius 3 of a shadow panel suppresses that panel's
  power generation.
  """

  @radius 3

  def initial_state do
    %{radius: @radius}
  end

  def radius, do: @radius
end
