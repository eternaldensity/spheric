defmodule Spheric.Game.Schema.HissEntity do
  use Ecto.Schema

  schema "hiss_entities" do
    field :world_id, :integer
    field :entity_id, :string
    field :face_id, :integer
    field :row, :integer
    field :col, :integer
    field :health, :integer, default: 100
    field :spawned_at, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
