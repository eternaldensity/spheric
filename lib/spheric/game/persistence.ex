defmodule Spheric.Game.Persistence do
  @moduledoc """
  Persistence layer: save/load world state between ETS and PostgreSQL.

  ETS remains the hot-path runtime store. This module handles:
  - Loading a saved world from the database into ETS on startup
  - Saving dirty ETS state to the database periodically
  - Managing world metadata (seed, name, subdivisions)
  """

  import Ecto.Query

  alias Spheric.Repo
  alias Spheric.Game.Schema.{World, Building, TileResource, Player}
  alias Spheric.Game.{WorldStore, WorldGen}

  require Logger

  @doc """
  Upsert a player record (id -> name, color mapping).
  Called on every connected mount to keep the mapping current.
  """
  def upsert_player(player_id, name, color) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      Player,
      [%{player_id: player_id, name: name, color: color, inserted_at: now, updated_at: now}],
      on_conflict: {:replace, [:name, :color, :updated_at]},
      conflict_target: [:player_id]
    )

    :ok
  end

  @doc "Look up a player's name by their player_id. Returns the name or nil."
  def get_player_name(nil), do: nil

  def get_player_name(player_id) do
    Player
    |> where([p], p.player_id == ^player_id)
    |> select([p], p.name)
    |> Repo.one()
  end

  @doc """
  Load a world by name. If found, regenerates terrain from seed,
  then overlays saved resource modifications and buildings into ETS.

  Returns `{:ok, world}` if a saved world was loaded, or `:none` if not found.
  """
  def load_world(name \\ "default") do
    case Repo.get_by(World, name: name) do
      nil ->
        :none

      world ->
        Logger.info("Loading saved world '#{name}' (seed=#{world.seed})")

        # Regenerate terrain from seed (fills ETS with pristine generated state)
        WorldGen.generate(seed: world.seed, subdivisions: world.subdivisions)

        # Overlay saved resource modifications
        load_tile_resources(world.id)

        # Load all saved buildings
        load_buildings(world.id)

        {:ok, world}
    end
  end

  @doc """
  Save all dirty state to the database.

  - `dirty_tiles` — list of `{face_id, row, col}` tile keys with modified resources
  - `dirty_buildings` — list of `{face_id, row, col}` building keys to upsert
  - `removed_buildings` — list of `{face_id, row, col}` building keys to delete
  """
  def save_dirty(world_id, dirty_tiles, dirty_buildings, removed_buildings) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    save_tile_resources(world_id, dirty_tiles, now)
    save_buildings(world_id, dirty_buildings, now)
    delete_buildings(world_id, removed_buildings)

    :ok
  end

  @doc """
  Find or create a world record by name.
  """
  def ensure_world(name \\ "default", seed, subdivisions) do
    case Repo.get_by(World, name: name) do
      nil ->
        %World{}
        |> World.changeset(%{name: name, seed: seed, subdivisions: subdivisions})
        |> Repo.insert!()

      world ->
        world
    end
  end

  # --- Loading ---

  defp load_tile_resources(world_id) do
    TileResource
    |> where([tr], tr.world_id == ^world_id)
    |> Repo.all()
    |> Enum.each(fn tr ->
      key = {tr.face_id, tr.row, tr.col}
      tile = WorldStore.get_tile(key)

      if tile do
        resource =
          if tr.resource_type && tr.amount && tr.amount > 0 do
            {String.to_atom(tr.resource_type), tr.amount}
          else
            nil
          end

        WorldStore.put_tile(key, %{tile | resource: resource})
      end
    end)

    # Clear dirty markers created by put_tile during load
    WorldStore.drain_dirty()
  end

  defp load_buildings(world_id) do
    Building
    |> where([b], b.world_id == ^world_id)
    |> Repo.all()
    |> Enum.each(fn b ->
      key = {b.face_id, b.row, b.col}
      type = String.to_atom(b.type)
      state = atomize_state_keys(b.state)

      building_data = %{
        type: type,
        orientation: b.orientation,
        state: state,
        owner_id: b.owner_id
      }

      WorldStore.put_building(key, building_data)
    end)

    # Clear dirty markers created by put_building during load
    WorldStore.drain_dirty()
  end

  # Convert string-keyed JSONB map to atom-keyed map, also converting
  # known atom values back from strings (item types like "iron_ore").
  defp atomize_state_keys(state) when is_map(state) do
    Map.new(state, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      val = atomize_state_value(key, v)
      {key, val}
    end)
  end

  defp atomize_state_keys(other), do: other

  @atom_fields [:item, :output_buffer, :input_buffer, :input_a, :input_b, :last_submitted]

  defp atomize_state_value(key, value) when key in @atom_fields and is_binary(value) do
    String.to_atom(value)
  end

  defp atomize_state_value(_key, value), do: value

  # --- Saving ---

  defp save_tile_resources(_world_id, [], _now), do: :ok

  defp save_tile_resources(world_id, dirty_tile_keys, now) do
    entries =
      Enum.flat_map(dirty_tile_keys, fn {face_id, row, col} = key ->
        tile = WorldStore.get_tile(key)

        if tile do
          {resource_type, amount} =
            case tile.resource do
              {type, amt} -> {Atom.to_string(type), amt}
              nil -> {nil, nil}
            end

          [
            %{
              world_id: world_id,
              face_id: face_id,
              row: row,
              col: col,
              resource_type: resource_type,
              amount: amount,
              inserted_at: now,
              updated_at: now
            }
          ]
        else
          []
        end
      end)

    if entries != [] do
      entries
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(TileResource, chunk,
          on_conflict: {:replace, [:resource_type, :amount, :updated_at]},
          conflict_target: [:world_id, :face_id, :row, :col]
        )
      end)
    end
  end

  defp save_buildings(_world_id, [], _now), do: :ok

  defp save_buildings(world_id, dirty_building_keys, now) do
    entries =
      Enum.flat_map(dirty_building_keys, fn {face_id, row, col} = key ->
        building = WorldStore.get_building(key)

        if building do
          serialized_state = serialize_state(building.state)

          [
            %{
              world_id: world_id,
              face_id: face_id,
              row: row,
              col: col,
              type: Atom.to_string(building.type),
              orientation: building.orientation,
              state: serialized_state,
              owner_id: building[:owner_id],
              inserted_at: now,
              updated_at: now
            }
          ]
        else
          []
        end
      end)

    if entries != [] do
      entries
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(Building, chunk,
          on_conflict: {:replace, [:type, :orientation, :state, :owner_id, :updated_at]},
          conflict_target: [:world_id, :face_id, :row, :col]
        )
      end)
    end
  end

  defp delete_buildings(_world_id, []), do: :ok

  defp delete_buildings(world_id, removed_keys) do
    Enum.each(removed_keys, fn {face_id, row, col} ->
      Building
      |> where(
        [b],
        b.world_id == ^world_id and b.face_id == ^face_id and b.row == ^row and b.col == ^col
      )
      |> Repo.delete_all()
    end)
  end

  defp serialize_state(state) when is_map(state) do
    Map.new(state, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      val = if is_atom(v) and not is_nil(v), do: Atom.to_string(v), else: v
      {key, val}
    end)
  end
end
