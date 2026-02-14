defmodule Spheric.Game.Territory do
  @moduledoc """
  Territory system for multiplayer zone control.

  Players establish territory by placing Claim Beacons, which claim all tiles
  within a radius of 8. Only the territory owner can build within claimed tiles.
  Unclaimed tiles remain free for anyone.

  Territory state is stored in ETS for fast runtime lookups and persisted to DB.
  """

  import Ecto.Query

  alias Spheric.Repo
  alias Spheric.Game.Schema.Territory, as: TerritorySchema

  require Logger

  @territory_table :spheric_territories
  @default_radius 8

  # --- Initialization ---

  def init do
    unless :ets.whereis(@territory_table) != :undefined do
      :ets.new(@territory_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Clear all territory data from ETS."
  def clear do
    if :ets.whereis(@territory_table) != :undefined, do: :ets.delete_all_objects(@territory_table)
    :ok
  end

  # --- Public API ---

  @doc "Returns the default territory radius for claim beacons."
  def default_radius, do: @default_radius

  @doc """
  Claim territory centered at the given key with a radius.
  The claim beacon building at key establishes the territory center.

  Returns :ok or {:error, reason}.
  """
  def claim(world_id, owner_id, {face, row, col} = _center_key) do
    territory = %{
      owner_id: owner_id,
      center_face: face,
      center_row: row,
      center_col: col,
      radius: @default_radius,
      world_id: world_id
    }

    # Check for overlapping territories
    case find_overlap(face, row, col, @default_radius) do
      nil ->
        # Store in ETS
        :ets.insert(@territory_table, {{face, row, col}, territory})
        # Mark dirty for persistence
        mark_dirty()
        :ok

      existing ->
        if existing.owner_id == owner_id do
          {:error, :already_claimed}
        else
          {:error, :territory_overlap}
        end
    end
  end

  @doc """
  Release territory centered at the given key.
  Called when a claim beacon is removed.
  """
  def release({face, row, col} = _center_key) do
    :ets.delete(@territory_table, {face, row, col})
    mark_dirty()
    :ok
  end

  @doc """
  Check if a tile is within any player's territory.
  Returns the territory map if claimed, or nil if unclaimed.
  """
  def territory_at({face, row, col}) do
    all_territories()
    |> Enum.find(fn {_center, territory} ->
      territory.center_face == face &&
        in_radius?(row, col, territory.center_row, territory.center_col, territory.radius)
    end)
    |> case do
      nil -> nil
      {_center, territory} -> territory
    end
  end

  @doc """
  Check if a player can build at a tile.
  Returns true if the tile is unclaimed or owned by the player.
  """
  def can_build?(player_id, tile_key) do
    case territory_at(tile_key) do
      nil -> true
      %{owner_id: ^player_id} -> true
      _other -> false
    end
  end

  @doc """
  Get all territories owned by a player.
  """
  def player_territories(player_id) do
    all_territories()
    |> Enum.filter(fn {_center, t} -> t.owner_id == player_id end)
    |> Enum.map(fn {_center, t} -> t end)
  end

  @doc """
  Get all territories as a list of {center_key, territory} tuples.
  """
  def all_territories do
    case :ets.whereis(@territory_table) do
      :undefined -> []
      _ -> :ets.tab2list(@territory_table)
    end
  end

  @doc """
  Get territories visible on a given face.
  """
  def territories_on_face(face_id) do
    all_territories()
    |> Enum.filter(fn {_center, t} -> t.center_face == face_id end)
    |> Enum.map(fn {_center, t} ->
      %{
        owner_id: t.owner_id,
        center_face: t.center_face,
        center_row: t.center_row,
        center_col: t.center_col,
        radius: t.radius
      }
    end)
  end

  @doc "Store a territory directly in ETS (used during loading)."
  def put_territory(center_key, territory) do
    :ets.insert(@territory_table, {center_key, territory})
  end

  # --- Persistence ---

  @doc "Save all territories to the database."
  def save_territories(world_id, now) do
    TerritorySchema
    |> where([t], t.world_id == ^world_id)
    |> Repo.delete_all()

    entries =
      all_territories()
      |> Enum.map(fn {_center, t} ->
        %{
          world_id: world_id,
          owner_id: t.owner_id,
          center_face: t.center_face,
          center_row: t.center_row,
          center_col: t.center_col,
          radius: t[:radius] || @default_radius,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [] do
      entries
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(TerritorySchema, chunk)
      end)
    end
  end

  @doc "Load all territories from the database into ETS."
  def load_territories(world_id) do
    TerritorySchema
    |> where([t], t.world_id == ^world_id)
    |> Repo.all()
    |> Enum.each(fn t ->
      center_key = {t.center_face, t.center_row, t.center_col}

      territory = %{
        owner_id: t.owner_id,
        center_face: t.center_face,
        center_row: t.center_row,
        center_col: t.center_col,
        radius: t.radius,
        world_id: t.world_id
      }

      put_territory(center_key, territory)
    end)
  end

  # --- Internal ---

  defp in_radius?(row, col, center_row, center_col, radius) do
    abs(row - center_row) <= radius and abs(col - center_col) <= radius
  end

  defp find_overlap(face, row, col, radius) do
    all_territories()
    |> Enum.find_value(fn {_center, territory} ->
      if territory.center_face == face do
        # Two territories overlap if the distance between centers is less than
        # the sum of their radii (using Chebyshev distance on the grid)
        dr = abs(territory.center_row - row)
        dc = abs(territory.center_col - col)

        if dr < territory.radius + radius and dc < territory.radius + radius do
          territory
        end
      end
    end)
  end

  defp mark_dirty do
    # Use a simple flag that persistence checks
    case :ets.whereis(:spheric_dirty) do
      :undefined -> :ok
      _ -> :ets.insert(:spheric_dirty, {{:territory, :all}, true})
    end
  end
end
