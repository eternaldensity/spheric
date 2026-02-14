defmodule Spheric.Repo.Migrations.CreateResearchProgress do
  use Ecto.Migration

  def change do
    create table(:research_progress) do
      add :world_id, references(:worlds, on_delete: :delete_all), null: false
      add :player_id, :string, null: false
      add :case_file_id, :string, null: false
      add :submissions, :map, default: %{}, null: false
      add :completed, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:research_progress, [:world_id, :player_id, :case_file_id])
    create index(:research_progress, [:world_id, :player_id])
  end
end
