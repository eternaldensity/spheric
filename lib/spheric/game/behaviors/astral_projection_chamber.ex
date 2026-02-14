defmodule Spheric.Game.Behaviors.AstralProjectionChamber do
  @moduledoc """
  Astral Projection Chamber — teleport camera anywhere on sphere.

  When a player owns this building, they can click on it to enter
  "astral projection" mode, which allows them to freely move their
  camera to any point on the sphere without physically moving.

  This is a passive building with no tick behavior.
  """

  def initial_state do
    %{
      active: false,
      last_used: nil
    }
  end
end
