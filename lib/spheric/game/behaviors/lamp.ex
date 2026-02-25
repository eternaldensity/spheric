defmodule Spheric.Game.Behaviors.Lamp do
  @moduledoc """
  Lamp building behavior.

  Passive power consumer that illuminates nearby tiles when powered.
  Its presence within radius 3 of a shadow panel suppresses that panel's
  power generation. Area creature boost increases the effective radius.
  """

  alias Spheric.Game.Creatures

  @radius 3

  def initial_state do
    %{radius: @radius}
  end

  def radius, do: @radius

  @doc "Returns the effective radius for a lamp, including area creature boost."
  def effective_radius(key, owner_id) do
    area = Creatures.area_value(key, owner_id)
    round(@radius * (1.0 + area))
  end
end
