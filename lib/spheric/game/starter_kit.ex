defmodule Spheric.Game.StarterKit do
  @moduledoc """
  Starter kit system.

  New players receive a limited number of free buildings to bootstrap
  their economy. After the starter kit is exhausted, buildings cost resources.
  """

  @table :spheric_starter_kits

  @default_kit %{
    conveyor: 8,
    miner: 2,
    smelter: 2,
    submission_terminal: 1,
    gathering_post: 1
  }

  def init do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Get the remaining starter kit for a player."
  def get_remaining(player_id) do
    case :ets.whereis(@table) do
      :undefined ->
        @default_kit

      _ ->
        case :ets.lookup(@table, player_id) do
          [{^player_id, kit}] -> kit
          [] -> @default_kit
        end
    end
  end

  @doc """
  Try to consume a free building from the starter kit.
  Returns :ok if consumed (building is free), or :not_available.
  """
  def consume(player_id, building_type) do
    remaining = get_remaining(player_id)

    case Map.get(remaining, building_type, 0) do
      0 ->
        :not_available

      count ->
        new_remaining = Map.put(remaining, building_type, count - 1)
        :ets.insert(@table, {player_id, new_remaining})
        :ok
    end
  end

  @doc "Check if a player has free buildings of this type remaining."
  def has_free?(player_id, building_type) do
    Map.get(get_remaining(player_id), building_type, 0) > 0
  end

  @doc "Restore a free building to a player's starter kit (on decommission)."
  def restore(player_id, building_type) do
    remaining = get_remaining(player_id)
    count = Map.get(remaining, building_type, 0)
    new_remaining = Map.put(remaining, building_type, count + 1)
    :ets.insert(@table, {player_id, new_remaining})
    :ok
  end

  @doc "Put starter kit directly (for persistence)."
  def put_kit(player_id, kit) do
    :ets.insert(@table, {player_id, kit})
  end

  @doc "Get all kits (for persistence)."
  def all_kits do
    case :ets.whereis(@table) do
      :undefined -> []
      _ -> :ets.tab2list(@table)
    end
  end

  @doc "Clear all kits."
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end
  end

  @doc "Get all kits (for persistence)."
  def all do
    all_kits()
  end

  @doc "Bulk insert kits (from persistence)."
  def put_all(entries) do
    Enum.each(entries, fn {player_id, kit} ->
      :ets.insert(@table, {player_id, kit})
    end)

    :ok
  end

  @doc "Returns the default kit contents."
  def default_kit, do: @default_kit
end
