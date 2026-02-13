defmodule SphericWeb.Presence do
  @moduledoc """
  Tracks online players and their camera positions using Phoenix.Presence.

  Players are tracked on the "game:presence" topic. Each player's metadata
  includes their display name, color, and current camera position.
  """

  use Phoenix.Presence,
    otp_app: :spheric,
    pubsub_server: Spheric.PubSub

  @player_names ~w(Atlas Cosmo Nova Orbit Quasar Pulsar Vega Lyra Polaris
    Zenith Helix Nimbus Astro Flux Vertex Prism Cipher Nexus Echo Spark)

  @player_colors ~w(#ff6b6b #ffa94d #ffd43b #69db7c #38d9a9 #4dabf7
    #748ffc #da77f2 #f783ac #e599f7 #63e6be #74c0fc)

  @doc "Generate a random player name."
  def random_name do
    Enum.random(@player_names)
  end

  @doc "Generate a random player color hex string."
  def random_color do
    Enum.random(@player_colors)
  end
end
