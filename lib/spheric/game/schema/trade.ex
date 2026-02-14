defmodule Spheric.Game.Schema.Trade do
  use Ecto.Schema
  import Ecto.Changeset

  schema "trades" do
    field :offerer_id, :string
    field :accepter_id, :string
    field :status, :string, default: "open"
    field :offered_items, :map, default: %{}
    field :requested_items, :map, default: %{}
    field :offered_filled, :map, default: %{}
    field :requested_filled, :map, default: %{}

    belongs_to :world, Spheric.Game.Schema.World

    timestamps(type: :utc_datetime)
  end

  def changeset(trade, attrs) do
    trade
    |> cast(attrs, [
      :world_id,
      :offerer_id,
      :accepter_id,
      :status,
      :offered_items,
      :requested_items,
      :offered_filled,
      :requested_filled
    ])
    |> validate_required([:world_id, :offerer_id, :status, :offered_items, :requested_items])
    |> validate_inclusion(:status, ["open", "accepted", "completed", "cancelled"])
  end
end
