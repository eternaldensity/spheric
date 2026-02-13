defmodule Spheric.Repo.Migrations.CreateBuildings do
  use Ecto.Migration

  def change do
    create table(:buildings) do
      add :world_id, references(:worlds, on_delete: :delete_all), null: false
      add :face_id, :integer, null: false
      add :row, :integer, null: false
      add :col, :integer, null: false
      add :type, :string, null: false
      add :orientation, :integer, null: false, default: 0
      add :state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:buildings, [:world_id, :face_id, :row, :col])
    create index(:buildings, [:world_id])
  end
end
