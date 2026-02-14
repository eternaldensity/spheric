defmodule Spheric.Repo.Migrations.CreateTerritory do
  use Ecto.Migration

  def change do
    create table(:territories) do
      add :world_id, references(:worlds), null: false
      add :owner_id, :string, null: false
      add :center_face, :integer, null: false
      add :center_row, :integer, null: false
      add :center_col, :integer, null: false
      add :radius, :integer, null: false, default: 8

      timestamps(type: :utc_datetime)
    end

    create unique_index(:territories, [:world_id, :center_face, :center_row, :center_col])
    create index(:territories, [:world_id, :owner_id])
  end
end
