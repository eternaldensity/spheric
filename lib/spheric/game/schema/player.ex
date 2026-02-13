defmodule Spheric.Game.Schema.Player do
  use Ecto.Schema
  import Ecto.Changeset

  schema "players" do
    field :player_id, :string
    field :name, :string
    field :color, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:player_id, :name, :color])
    |> validate_required([:player_id, :name, :color])
    |> unique_constraint(:player_id)
  end
end
