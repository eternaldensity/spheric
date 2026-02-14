defmodule Spheric.Repo.Migrations.CreateCreatures do
  use Ecto.Migration

  def change do
    create table(:creatures) do
      add :world_id, references(:worlds, on_delete: :delete_all), null: false
      add :creature_id, :string, null: false
      add :creature_type, :string, null: false
      add :face_id, :integer, null: false
      add :row, :integer, null: false
      add :col, :integer, null: false
      add :owner_id, :string
      add :assigned_to_face, :integer
      add :assigned_to_row, :integer
      add :assigned_to_col, :integer
      add :spawned_at, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:creatures, [:world_id, :creature_id])
    create index(:creatures, [:world_id, :owner_id])
  end
end
