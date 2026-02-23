defmodule Spheric.Repo.Migrations.AddDroneUpgradesToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :drone_upgrades, :map, default: %{}
    end
  end
end
