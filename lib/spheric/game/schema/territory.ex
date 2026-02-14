defmodule Spheric.Game.Schema.Territory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "territories" do
    field :owner_id, :string
    field :center_face, :integer
    field :center_row, :integer
    field :center_col, :integer
    field :radius, :integer, default: 8

    belongs_to :world, Spheric.Game.Schema.World

    timestamps(type: :utc_datetime)
  end

  def changeset(territory, attrs) do
    territory
    |> cast(attrs, [:world_id, :owner_id, :center_face, :center_row, :center_col, :radius])
    |> validate_required([:world_id, :owner_id, :center_face, :center_row, :center_col])
    |> unique_constraint([:world_id, :center_face, :center_row, :center_col])
  end
end
