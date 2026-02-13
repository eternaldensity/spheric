defmodule Spheric.Game.Schema.Building do
  use Ecto.Schema
  import Ecto.Changeset

  schema "buildings" do
    field :face_id, :integer
    field :row, :integer
    field :col, :integer
    field :type, :string
    field :orientation, :integer, default: 0
    field :state, :map, default: %{}

    belongs_to :world, Spheric.Game.Schema.World

    timestamps(type: :utc_datetime)
  end

  def changeset(building, attrs) do
    building
    |> cast(attrs, [:world_id, :face_id, :row, :col, :type, :orientation, :state])
    |> validate_required([:world_id, :face_id, :row, :col, :type, :orientation])
    |> unique_constraint([:world_id, :face_id, :row, :col])
  end
end
