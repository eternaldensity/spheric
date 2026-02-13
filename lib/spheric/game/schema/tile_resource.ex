defmodule Spheric.Game.Schema.TileResource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tile_resources" do
    field :face_id, :integer
    field :row, :integer
    field :col, :integer
    field :resource_type, :string
    field :amount, :integer

    belongs_to :world, Spheric.Game.Schema.World

    timestamps(type: :utc_datetime)
  end

  def changeset(tile_resource, attrs) do
    tile_resource
    |> cast(attrs, [:world_id, :face_id, :row, :col, :resource_type, :amount])
    |> validate_required([:world_id, :face_id, :row, :col])
    |> unique_constraint([:world_id, :face_id, :row, :col])
  end
end
