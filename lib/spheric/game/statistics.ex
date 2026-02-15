defmodule Spheric.Game.Statistics do
  @moduledoc """
  Production statistics tracking.

  Tracks per-building throughput (items produced/consumed) over time.
  Uses ETS for fast, lockless reads from LiveView processes.
  """

  @table :spheric_statistics

  def init do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Record an item produced by a building."
  def record_production(building_key, item_type) do
    ensure_init()
    counter_key = {:produced, building_key, item_type}

    try do
      :ets.update_counter(@table, counter_key, {2, 1})
    catch
      :error, :badarg ->
        :ets.insert(@table, {counter_key, 1})
    end
  end

  @doc "Record an item consumed by a building."
  def record_consumption(building_key, item_type) do
    ensure_init()
    counter_key = {:consumed, building_key, item_type}

    try do
      :ets.update_counter(@table, counter_key, {2, 1})
    catch
      :error, :badarg ->
        :ets.insert(@table, {counter_key, 1})
    end
  end

  @doc "Record an item transported through a building."
  def record_throughput(building_key, item_type) do
    ensure_init()
    counter_key = {:throughput, building_key, item_type}

    try do
      :ets.update_counter(@table, counter_key, {2, 1})
    catch
      :error, :badarg ->
        :ets.insert(@table, {counter_key, 1})
    end
  end

  @doc """
  Get statistics for a specific building.
  Returns %{produced: %{item => count}, consumed: %{item => count}, throughput: %{item => count}}.
  """
  def building_stats(building_key) do
    ensure_init()

    produced =
      :ets.match_object(@table, {{:produced, building_key, :_}, :_})
      |> Map.new(fn {{:produced, _key, item}, count} -> {item, count} end)

    consumed =
      :ets.match_object(@table, {{:consumed, building_key, :_}, :_})
      |> Map.new(fn {{:consumed, _key, item}, count} -> {item, count} end)

    throughput =
      :ets.match_object(@table, {{:throughput, building_key, :_}, :_})
      |> Map.new(fn {{:throughput, _key, item}, count} -> {item, count} end)

    %{produced: produced, consumed: consumed, throughput: throughput}
  end

  @doc """
  Get global production summary for a player's buildings.
  Returns a list of %{key, type, produced, consumed, throughput}.
  """
  def player_summary(player_id) do
    ensure_init()
    alias Spheric.Game.WorldStore

    # Find all buildings owned by the player and query stats per-building
    for face_id <- 0..29,
        {key, building} <- WorldStore.get_face_buildings(face_id),
        building.owner_id == player_id do
      stats = building_stats(key)

      total =
        (stats.produced |> Map.values() |> Enum.sum()) +
          (stats.consumed |> Map.values() |> Enum.sum()) +
          (stats.throughput |> Map.values() |> Enum.sum())

      if total > 0 do
        Map.merge(stats, %{key: key, type: building.type})
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn s ->
      -(Map.values(s.produced) |> Enum.sum()) -
        (Map.values(s.consumed) |> Enum.sum()) -
        (Map.values(s.throughput) |> Enum.sum())
    end)
  end

  @doc "Clear all statistics."
  def reset do
    ensure_init()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_init do
    if :ets.whereis(@table) == :undefined, do: init()
  end
end
