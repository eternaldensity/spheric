defmodule Spheric.Game.Behaviors.Substation do
  @moduledoc """
  Substation building behavior.

  Passive building that distributes power within a short radius.
  Connects to generators, machines, and other substations.
  """

  @radius 4

  def initial_state do
    %{radius: @radius, active: true}
  end

  def radius, do: @radius
end
