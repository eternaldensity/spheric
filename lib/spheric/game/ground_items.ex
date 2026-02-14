defmodule Spheric.Game.GroundItems do
  @moduledoc """
  Ground items system.

  Manages items that exist on tiles without buildings. Used for:
  - Construction site delivery (items within radius 3 feed into sites)
  - Building deconstruction refunds
  - Overflow from conveyors with no downstream
  """

  @table :spheric_ground_items

  def init do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Get all ground items at a tile."
  def get(key) do
    case :ets.whereis(@table) do
      :undefined -> %{}

      _ ->
        case :ets.lookup(@table, key) do
          [{^key, items}] -> items
          [] -> %{}
        end
    end
  end

  @doc "Add items to a tile. Items is a map of %{atom => count}."
  def add(key, item_type, count \\ 1) do
    current = get(key)
    new_count = Map.get(current, item_type, 0) + count
    updated = Map.put(current, item_type, new_count)
    :ets.insert(@table, {key, updated})
    :ok
  end

  @doc "Remove one item of a type from a tile. Returns :ok or :empty."
  def take(key, item_type) do
    current = get(key)

    case Map.get(current, item_type, 0) do
      0 ->
        :empty

      1 ->
        updated = Map.delete(current, item_type)

        if updated == %{} do
          :ets.delete(@table, key)
        else
          :ets.insert(@table, {key, updated})
        end

        :ok

      n ->
        updated = Map.put(current, item_type, n - 1)
        :ets.insert(@table, {key, updated})
        :ok
    end
  end

  @doc "Get all ground items within a radius of a tile (same face only)."
  def items_near({face, row, col}, radius) do
    all_on_face(face)
    |> Enum.filter(fn {{f, r, c}, _items} ->
      f == face and abs(r - row) <= radius and abs(c - col) <= radius
    end)
  end

  @doc "Get all ground items on a face."
  def all_on_face(face_id) do
    case :ets.whereis(@table) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(@table)
        |> Enum.filter(fn {{f, _r, _c}, _items} -> f == face_id end)
    end
  end

  @doc "Get all ground items."
  def all do
    case :ets.whereis(@table) do
      :undefined -> []
      _ -> :ets.tab2list(@table)
    end
  end

  @doc "Get ground items grouped by face for broadcasting."
  def items_by_face do
    all()
    |> Enum.group_by(fn {{face, _r, _c}, _items} -> face end, fn {{face, row, col}, items} ->
      %{face: face, row: row, col: col, items: items}
    end)
  end

  @doc "Bulk insert ground items (from persistence)."
  def put_all(entries) do
    Enum.each(entries, fn {key, items} ->
      :ets.insert(@table, {key, items})
    end)

    :ok
  end

  @doc "Clear all ground items."
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end
  end
end
