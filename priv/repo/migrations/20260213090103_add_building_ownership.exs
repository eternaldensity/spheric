defmodule Spheric.Repo.Migrations.AddBuildingOwnership do
  use Ecto.Migration

  def change do
    alter table(:buildings) do
      add :owner_id, :string
    end

    create table(:players) do
      add :player_id, :string, null: false
      add :name, :string, null: false
      add :color, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:players, [:player_id])
  end
end
