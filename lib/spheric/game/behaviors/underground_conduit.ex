defmodule Spheric.Game.Behaviors.UndergroundConduit do
  @moduledoc """
  Underground Conduit building behavior.

  A linked pair of conduits that teleport items between two points.
  Items enter from the rear and appear at the linked conduit's output.

  Linking is done by selecting one conduit and then clicking another
  to pair them. Each conduit stores its partner's key.
  """

  @doc "Returns the initial state for a newly placed underground conduit."
  def initial_state do
    %{item: nil, linked_to: nil}
  end
end
