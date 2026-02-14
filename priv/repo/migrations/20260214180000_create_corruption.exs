defmodule Spheric.Repo.Migrations.CreateCorruption do
  use Ecto.Migration

  def change do
    create table(:corruption) do
      add :world_id, references(:worlds, on_delete: :delete_all), null: false
      add :face_id, :integer, null: false
      add :row, :integer, null: false
      add :col, :integer, null: false
      add :intensity, :integer, null: false, default: 1
      add :seeded_at, :integer, null: false, default: 0
      add :building_damage_ticks, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:corruption, [:world_id, :face_id, :row, :col])

    create table(:hiss_entities) do
      add :world_id, references(:worlds, on_delete: :delete_all), null: false
      add :entity_id, :string, null: false
      add :face_id, :integer, null: false
      add :row, :integer, null: false
      add :col, :integer, null: false
      add :health, :integer, null: false, default: 100
      add :spawned_at, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:hiss_entities, [:world_id, :entity_id])
  end
end
