defmodule Spheric.Game.Behaviors.TransferStation do
  @moduledoc """
  Transfer Station building behavior.

  Passive building for long-range power distribution.
  Only connects to substations and other transfer stations.
  """

  @radius 8

  def initial_state do
    %{radius: @radius, active: true}
  end

  def radius, do: @radius
end
