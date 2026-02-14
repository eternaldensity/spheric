defmodule Spheric.Game.Schema.Creature do
  use Ecto.Schema
  import Ecto.Changeset

  schema "creatures" do
    field :creature_id, :string
    field :creature_type, :string
    field :face_id, :integer
    field :row, :integer
    field :col, :integer
    field :owner_id, :string
    field :assigned_to_face, :integer
    field :assigned_to_row, :integer
    field :assigned_to_col, :integer
    field :spawned_at, :integer, default: 0

    belongs_to :world, Spheric.Game.Schema.World

    timestamps(type: :utc_datetime)
  end

  def changeset(creature, attrs) do
    creature
    |> cast(attrs, [
      :world_id,
      :creature_id,
      :creature_type,
      :face_id,
      :row,
      :col,
      :owner_id,
      :assigned_to_face,
      :assigned_to_row,
      :assigned_to_col,
      :spawned_at
    ])
    |> validate_required([:world_id, :creature_id, :creature_type, :face_id, :row, :col])
    |> unique_constraint([:world_id, :creature_id])
  end
end
