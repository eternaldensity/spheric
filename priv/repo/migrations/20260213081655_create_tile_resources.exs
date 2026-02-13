defmodule Spheric.Repo.Migrations.CreateTileResources do
  use Ecto.Migration

  def change do
    create table(:tile_resources) do
      add :world_id, references(:worlds, on_delete: :delete_all), null: false
      add :face_id, :integer, null: false
      add :row, :integer, null: false
      add :col, :integer, null: false
      add :resource_type, :string
      add :amount, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tile_resources, [:world_id, :face_id, :row, :col])
    create index(:tile_resources, [:world_id])
  end
end
