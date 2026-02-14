defmodule Spheric.Game.Behaviors.DimensionalStabilizer do
  @moduledoc """
  Dimensional Stabilizer — endgame building with huge corruption immunity radius.

  Passive building that creates a corruption-immune zone with radius 15
  (compared to Purification Beacon's radius 5). Does not actively push back
  corruption, but prevents new corruption from seeding or spreading within its zone.
  """

  @radius 15

  def initial_state do
    %{
      radius: @radius,
      power_level: 100
    }
  end

  @doc "Get the immunity radius."
  def radius, do: @radius
end
