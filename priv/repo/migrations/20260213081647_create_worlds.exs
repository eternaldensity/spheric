defmodule Spheric.Repo.Migrations.CreateWorlds do
  use Ecto.Migration

  def change do
    create table(:worlds) do
      add :name, :string, null: false, default: "default"
      add :seed, :integer, null: false
      add :subdivisions, :integer, null: false, default: 16

      timestamps(type: :utc_datetime)
    end

    create unique_index(:worlds, [:name])
  end
end
