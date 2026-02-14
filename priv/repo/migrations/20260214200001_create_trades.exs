defmodule Spheric.Repo.Migrations.CreateTrades do
  use Ecto.Migration

  def change do
    create table(:trades) do
      add :world_id, references(:worlds), null: false
      add :offerer_id, :string, null: false
      add :accepter_id, :string
      add :status, :string, null: false, default: "open"
      add :offered_items, :map, null: false, default: %{}
      add :requested_items, :map, null: false, default: %{}
      add :offered_filled, :map, null: false, default: %{}
      add :requested_filled, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:trades, [:world_id, :status])
    create index(:trades, [:world_id, :offerer_id])
  end
end
