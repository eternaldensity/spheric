defmodule Spheric.Game.Schema.ResearchProgress do
  use Ecto.Schema
  import Ecto.Changeset

  schema "research_progress" do
    field :player_id, :string
    field :case_file_id, :string
    field :submissions, :map, default: %{}
    field :completed, :boolean, default: false

    belongs_to :world, Spheric.Game.Schema.World

    timestamps(type: :utc_datetime)
  end

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:world_id, :player_id, :case_file_id, :submissions, :completed])
    |> validate_required([:world_id, :player_id, :case_file_id])
    |> unique_constraint([:world_id, :player_id, :case_file_id])
  end
end
