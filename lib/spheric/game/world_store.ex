defmodule Spheric.Game.WorldStore do
  @moduledoc """
  ETS-backed storage for world tile and building state.

  Two tables:
  - `:spheric_tiles` — keyed by `{face_id, row, col}`, stores terrain and resource data
  - `:spheric_buildings` — keyed by `{face_id, row, col}`, stores building type and state

  Tables have public read access for fast lookups. All writes go through WorldServer
  to serialize mutations.
  """

  @tiles_table :spheric_tiles
  @buildings_table :spheric_buildings
  @dirty_table :spheric_dirty

  @type tile_key :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type terrain :: :grassland | :desert | :tundra | :forest | :volcanic
  @type resource_type :: :iron | :copper
  @type tile_data :: %{terrain: terrain(), resource: nil | {resource_type(), non_neg_integer()}}
  @type building_data :: %{
          type: atom(),
          orientation: 0..3,
          state: map()
        }

  @doc """
  Creates the ETS tables. Called once during WorldServer init.
  Safe to call multiple times — skips creation if tables already exist.
  """
  def init do
    unless :ets.whereis(@tiles_table) != :undefined do
      :ets.new(@tiles_table, [:named_table, :set, :public, read_concurrency: true])
    end

    unless :ets.whereis(@buildings_table) != :undefined do
      :ets.new(@buildings_table, [:named_table, :set, :public, read_concurrency: true])
    end

    unless :ets.whereis(@dirty_table) != :undefined do
      :ets.new(@dirty_table, [:named_table, :set, :public])
    end

    :ok
  end

  # --- Tiles ---

  @doc "Insert or update a tile. Marks the tile as dirty for persistence."
  def put_tile(key, data) do
    :ets.insert(@tiles_table, {key, data})
    :ets.insert(@dirty_table, {{:tile, key}, true})
    :ok
  end

  @doc "Batch insert tiles."
  def put_tiles(entries) do
    :ets.insert(@tiles_table, entries)
    :ok
  end

  @doc "Get a single tile by `{face_id, row, col}`."
  def get_tile(key) do
    case :ets.lookup(@tiles_table, key) do
      [{^key, data}] -> data
      [] -> nil
    end
  end

  @doc "Get all tiles for a given face."
  def get_face_tiles(face_id) do
    :ets.match_object(@tiles_table, {{face_id, :_, :_}, :_})
  end

  @doc "Returns the total number of tiles."
  def tile_count do
    :ets.info(@tiles_table, :size)
  end

  # --- Buildings ---

  @doc "Place a building at the given tile key. Marks the building as dirty for persistence."
  def put_building(key, data) do
    :ets.insert(@buildings_table, {key, data})
    :ets.insert(@dirty_table, {{:building, key}, true})
    :ets.delete(@dirty_table, {:building_removed, key})
    :ok
  end

  @doc "Remove a building at the given tile key. Marks the building as removed for persistence."
  def remove_building(key) do
    :ets.delete(@buildings_table, key)
    :ets.insert(@dirty_table, {{:building_removed, key}, true})
    :ets.delete(@dirty_table, {:building, key})
    :ok
  end

  @doc "Get a building at the given tile key."
  def get_building(key) do
    case :ets.lookup(@buildings_table, key) do
      [{^key, data}] -> data
      [] -> nil
    end
  end

  @doc "Get all buildings for a given face."
  def get_face_buildings(face_id) do
    :ets.match_object(@buildings_table, {{face_id, :_, :_}, :_})
  end

  @doc "Returns the total number of buildings."
  def building_count do
    :ets.info(@buildings_table, :size)
  end

  @doc "Check if a building exists at the given tile."
  def has_building?(key) do
    :ets.member(@buildings_table, key)
  end

  # --- Dirty Tracking ---

  @doc """
  Drain all dirty markers. Returns `{tile_keys, building_keys, removed_building_keys}`.
  After this call, the dirty table is empty.
  """
  def drain_dirty do
    all = :ets.tab2list(@dirty_table)
    :ets.delete_all_objects(@dirty_table)

    Enum.reduce(all, {[], [], []}, fn
      {{:tile, key}, _}, {t, b, r} -> {[key | t], b, r}
      {{:building, key}, _}, {t, b, r} -> {t, [key | b], r}
      {{:building_removed, key}, _}, {t, b, r} -> {t, b, [key | r]}
    end)
  end

  @doc "Returns the count of dirty entries."
  def dirty_count do
    :ets.info(@dirty_table, :size)
  end

  @doc "Clear all tile, building, and dirty data from ETS tables."
  def clear do
    if :ets.whereis(@tiles_table) != :undefined, do: :ets.delete_all_objects(@tiles_table)
    if :ets.whereis(@buildings_table) != :undefined, do: :ets.delete_all_objects(@buildings_table)
    if :ets.whereis(@dirty_table) != :undefined, do: :ets.delete_all_objects(@dirty_table)
    :ok
  end
end
