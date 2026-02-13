defmodule Spheric.Game.Schema.World do
  use Ecto.Schema
  import Ecto.Changeset

  schema "worlds" do
    field :name, :string, default: "default"
    field :seed, :integer
    field :subdivisions, :integer, default: 16

    has_many :buildings, Spheric.Game.Schema.Building
    has_many :tile_resources, Spheric.Game.Schema.TileResource

    timestamps(type: :utc_datetime)
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [:name, :seed, :subdivisions])
    |> validate_required([:name, :seed])
    |> unique_constraint(:name)
  end
end
