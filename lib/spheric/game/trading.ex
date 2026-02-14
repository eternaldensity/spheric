defmodule Spheric.Game.Trading do
  @moduledoc """
  Trading system for async item exchange between players.

  Players create trade offers via Trade Terminals, specifying items they offer
  and items they want in return. Other players can accept and fulfill trades
  by feeding items into their own Trade Terminals.

  Trade lifecycle:
  1. Offerer creates trade (status: "open") with offered/requested item counts
  2. Another player accepts the trade (status: "accepted")
  3. Both players feed items into their Trade Terminals
  4. When both sides are fully filled, trade completes (status: "completed")
     and items become available for pickup at each terminal
  """

  import Ecto.Query

  alias Spheric.Repo
  alias Spheric.Game.Schema.Trade

  require Logger

  @trades_table :spheric_trades

  # --- Initialization ---

  def init do
    unless :ets.whereis(@trades_table) != :undefined do
      :ets.new(@trades_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  # --- Public API ---

  @doc """
  Create a new trade offer.

  offered_items and requested_items are maps of item_type_string => count.
  e.g. %{"iron_ingot" => 10, "copper_ingot" => 5}
  """
  def create_trade(world_id, offerer_id, offered_items, requested_items)
      when map_size(offered_items) > 0 and map_size(requested_items) > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    trade_id = System.unique_integer([:positive, :monotonic])

    trade = %{
      id: trade_id,
      world_id: world_id,
      offerer_id: offerer_id,
      accepter_id: nil,
      status: "open",
      offered_items: offered_items,
      requested_items: requested_items,
      offered_filled: %{},
      requested_filled: %{},
      created_at: now
    }

    :ets.insert(@trades_table, {trade_id, trade})
    save_trade_to_db(trade)

    {:ok, trade}
  end

  def create_trade(_world_id, _offerer_id, _offered, _requested) do
    {:error, :empty_trade}
  end

  @doc """
  Accept a trade offer. The accepter commits to providing the requested items.
  """
  def accept_trade(trade_id, accepter_id) do
    case get_trade(trade_id) do
      nil ->
        {:error, :not_found}

      trade ->
        cond do
          trade.status != "open" ->
            {:error, :not_open}

          trade.offerer_id == accepter_id ->
            {:error, :cannot_accept_own}

          true ->
            updated = %{trade | status: "accepted", accepter_id: accepter_id}
            :ets.insert(@trades_table, {trade_id, updated})
            update_trade_in_db(updated)
            {:ok, updated}
        end
    end
  end

  @doc """
  Submit an item to a trade from a trade terminal.

  The side parameter is :offerer or :accepter, indicating who is submitting.
  Returns {:ok, updated_trade} or {:completed, trade} if both sides are full,
  or {:error, reason}.
  """
  def submit_item(trade_id, player_id, item_type) do
    case get_trade(trade_id) do
      nil ->
        {:error, :not_found}

      trade ->
        cond do
          trade.status not in ["accepted"] ->
            {:error, :not_accepted}

          player_id == trade.offerer_id ->
            submit_to_side(trade, :offered, item_type)

          player_id == trade.accepter_id ->
            submit_to_side(trade, :requested, item_type)

          true ->
            {:error, :not_participant}
        end
    end
  end

  @doc "Cancel a trade. Only the offerer can cancel open/accepted trades."
  def cancel_trade(trade_id, player_id) do
    case get_trade(trade_id) do
      nil ->
        {:error, :not_found}

      trade ->
        if trade.offerer_id == player_id and trade.status in ["open", "accepted"] do
          updated = %{trade | status: "cancelled"}
          :ets.insert(@trades_table, {trade_id, updated})
          update_trade_in_db(updated)
          {:ok, updated}
        else
          {:error, :cannot_cancel}
        end
    end
  end

  @doc "Get a single trade by ID."
  def get_trade(trade_id) do
    case :ets.lookup(@trades_table, trade_id) do
      [{^trade_id, trade}] -> trade
      [] -> nil
    end
  end

  @doc "Get all open trades for a world."
  def open_trades(world_id) do
    all_trades()
    |> Enum.filter(fn {_id, t} -> t.world_id == world_id and t.status == "open" end)
    |> Enum.map(fn {_id, t} -> t end)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  end

  @doc "Get all trades involving a player (as offerer or accepter)."
  def player_trades(world_id, player_id) do
    all_trades()
    |> Enum.filter(fn {_id, t} ->
      t.world_id == world_id and
        (t.offerer_id == player_id or t.accepter_id == player_id)
    end)
    |> Enum.map(fn {_id, t} -> t end)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  end

  @doc "Get all trades (ETS)."
  def all_trades do
    case :ets.whereis(@trades_table) do
      :undefined -> []
      _ -> :ets.tab2list(@trades_table)
    end
  end

  # --- Persistence ---

  @doc "Save all trades to database."
  def save_trades(world_id, now) do
    Trade
    |> where([t], t.world_id == ^world_id)
    |> Repo.delete_all()

    entries =
      all_trades()
      |> Enum.filter(fn {_id, t} -> t.world_id == world_id end)
      |> Enum.map(fn {_id, t} ->
        %{
          world_id: world_id,
          offerer_id: t.offerer_id,
          accepter_id: t.accepter_id,
          status: t.status,
          offered_items: t.offered_items,
          requested_items: t.requested_items,
          offered_filled: t.offered_filled,
          requested_filled: t.requested_filled,
          inserted_at: t[:created_at] || now,
          updated_at: now
        }
      end)

    if entries != [] do
      entries
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(Trade, chunk)
      end)
    end
  end

  @doc "Load all trades from database into ETS."
  def load_trades(world_id) do
    Trade
    |> where([t], t.world_id == ^world_id)
    |> Repo.all()
    |> Enum.each(fn t ->
      trade = %{
        id: t.id,
        world_id: t.world_id,
        offerer_id: t.offerer_id,
        accepter_id: t.accepter_id,
        status: t.status,
        offered_items: t.offered_items,
        requested_items: t.requested_items,
        offered_filled: t.offered_filled,
        requested_filled: t.requested_filled,
        created_at: t.inserted_at
      }

      :ets.insert(@trades_table, {t.id, trade})
    end)
  end

  # --- Internal ---

  defp submit_to_side(trade, side, item_type) do
    item_str = if is_atom(item_type), do: Atom.to_string(item_type), else: item_type

    {required_items, filled_key} =
      case side do
        :offered -> {trade.offered_items, :offered_filled}
        :requested -> {trade.requested_items, :requested_filled}
      end

    required = Map.get(required_items, item_str, 0)
    current_filled = Map.get(Map.get(trade, filled_key), item_str, 0)

    if required == 0 do
      {:error, :item_not_needed}
    else
      if current_filled >= required do
        {:error, :already_filled}
      else
        new_count = current_filled + 1
        new_filled = Map.put(Map.get(trade, filled_key), item_str, new_count)
        updated = Map.put(trade, filled_key, new_filled)

        :ets.insert(@trades_table, {trade.id, updated})

        if trade_complete?(updated) do
          completed = %{updated | status: "completed"}
          :ets.insert(@trades_table, {trade.id, completed})
          update_trade_in_db(completed)
          {:completed, completed}
        else
          update_trade_in_db(updated)
          {:ok, updated}
        end
      end
    end
  end

  defp trade_complete?(trade) do
    offered_full? =
      Enum.all?(trade.offered_items, fn {item, required} ->
        Map.get(trade.offered_filled, item, 0) >= required
      end)

    requested_full? =
      Enum.all?(trade.requested_items, fn {item, required} ->
        Map.get(trade.requested_filled, item, 0) >= required
      end)

    offered_full? and requested_full?
  end

  defp save_trade_to_db(trade) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(Trade, [
      %{
        world_id: trade.world_id,
        offerer_id: trade.offerer_id,
        accepter_id: trade.accepter_id,
        status: trade.status,
        offered_items: trade.offered_items,
        requested_items: trade.requested_items,
        offered_filled: trade.offered_filled,
        requested_filled: trade.requested_filled,
        inserted_at: trade[:created_at] || now,
        updated_at: now
      }
    ])
  end

  defp update_trade_in_db(trade) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Find by matching world/offerer/items since ETS IDs differ from DB IDs
    Trade
    |> where([t], t.world_id == ^trade.world_id and t.offerer_id == ^trade.offerer_id)
    |> where([t], t.offered_items == ^trade.offered_items)
    |> limit(1)
    |> Repo.update_all(
      set: [
        status: trade.status,
        accepter_id: trade.accepter_id,
        offered_filled: trade.offered_filled,
        requested_filled: trade.requested_filled,
        updated_at: now
      ]
    )
  end
end
