defmodule Spheric.Game.Schema.Corruption do
  use Ecto.Schema

  schema "corruption" do
    field :world_id, :integer
    field :face_id, :integer
    field :row, :integer
    field :col, :integer
    field :intensity, :integer, default: 1
    field :seeded_at, :integer, default: 0
    field :building_damage_ticks, :integer, default: 0

    timestamps()
  end
end
