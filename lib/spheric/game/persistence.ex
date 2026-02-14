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
  alias Spheric.Game.Schema.{World, Building, TileResource, Player, Creature, Corruption, HissEntity}
  alias Spheric.Game.{WorldStore, WorldGen, Creatures, Hiss}

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

        # Load all saved creatures
        load_creatures(world.id)

        # Load corruption state
        load_corruption(world.id)

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
    save_creatures(world_id, now)
    save_corruption(world_id, now)

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

  @atom_fields [
    :item,
    :output_buffer,
    :input_buffer,
    :input_a,
    :input_b,
    :last_submitted,
    :altered_effect
  ]

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

  defp load_creatures(world_id) do
    Creature
    |> where([c], c.world_id == ^world_id)
    |> Repo.all()
    |> Enum.each(fn c ->
      type = String.to_atom(c.creature_type)

      if c.owner_id do
        # Captured creature — add to player roster
        assigned_to =
          if c.assigned_to_face do
            {c.assigned_to_face, c.assigned_to_row, c.assigned_to_col}
          else
            nil
          end

        captured = %{
          id: c.creature_id,
          type: type,
          assigned_to: assigned_to,
          captured_at: c.spawned_at
        }

        roster = Creatures.get_player_roster(c.owner_id)
        Creatures.put_player_roster(c.owner_id, [captured | roster])
      else
        # Wild creature — add to wild creatures table
        creature = %{
          type: type,
          face: c.face_id,
          row: c.row,
          col: c.col,
          spawned_at: c.spawned_at
        }

        Creatures.put_wild_creature(c.creature_id, creature)
      end
    end)
  end

  defp save_creatures(world_id, now) do
    # Delete all existing creature records for this world and rewrite
    Creature
    |> where([c], c.world_id == ^world_id)
    |> Repo.delete_all()

    entries = []

    # Save wild creatures
    wild_entries =
      Creatures.all_wild_creatures()
      |> Enum.map(fn {id, c} ->
        %{
          world_id: world_id,
          creature_id: id,
          creature_type: Atom.to_string(c.type),
          face_id: c.face,
          row: c.row,
          col: c.col,
          owner_id: nil,
          assigned_to_face: nil,
          assigned_to_row: nil,
          assigned_to_col: nil,
          spawned_at: c[:spawned_at] || 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    # Save captured creatures (from all player rosters)
    captured_entries =
      case :ets.whereis(:spheric_player_creatures) do
        :undefined ->
          []

        _ ->
          :ets.tab2list(:spheric_player_creatures)
          |> Enum.flat_map(fn {player_id, roster} ->
            Enum.map(roster, fn c ->
              {a_face, a_row, a_col} =
                case c.assigned_to do
                  {f, r, co} -> {f, r, co}
                  _ -> {nil, nil, nil}
                end

              %{
                world_id: world_id,
                creature_id: c.id,
                creature_type: Atom.to_string(c.type),
                face_id: 0,
                row: 0,
                col: 0,
                owner_id: player_id,
                assigned_to_face: a_face,
                assigned_to_row: a_row,
                assigned_to_col: a_col,
                spawned_at: c[:captured_at] || 0,
                inserted_at: now,
                updated_at: now
              }
            end)
          end)
      end

    all_entries = entries ++ wild_entries ++ captured_entries

    if all_entries != [] do
      all_entries
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(Creature, chunk)
      end)
    end
  end

  defp load_corruption(world_id) do
    Corruption
    |> where([c], c.world_id == ^world_id)
    |> Repo.all()
    |> Enum.each(fn c ->
      key = {c.face_id, c.row, c.col}

      data = %{
        intensity: c.intensity,
        seeded_at: c.seeded_at,
        building_damage_ticks: c.building_damage_ticks
      }

      Hiss.put_corruption(key, data)
    end)

    HissEntity
    |> where([h], h.world_id == ^world_id)
    |> Repo.all()
    |> Enum.each(fn h ->
      entity = %{
        face: h.face_id,
        row: h.row,
        col: h.col,
        health: h.health,
        spawned_at: h.spawned_at
      }

      Hiss.put_hiss_entity(h.entity_id, entity)
    end)
  end

  defp save_corruption(world_id, now) do
    # Delete and rewrite all corruption
    Corruption
    |> where([c], c.world_id == ^world_id)
    |> Repo.delete_all()

    corruption_entries =
      Hiss.all_corrupted()
      |> Enum.map(fn {{face_id, row, col}, data} ->
        %{
          world_id: world_id,
          face_id: face_id,
          row: row,
          col: col,
          intensity: data.intensity,
          seeded_at: data[:seeded_at] || 0,
          building_damage_ticks: data[:building_damage_ticks] || 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    if corruption_entries != [] do
      corruption_entries
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(Corruption, chunk)
      end)
    end

    # Delete and rewrite all Hiss entities
    HissEntity
    |> where([h], h.world_id == ^world_id)
    |> Repo.delete_all()

    hiss_entries =
      Hiss.all_hiss_entities()
      |> Enum.map(fn {id, e} ->
        %{
          world_id: world_id,
          entity_id: id,
          face_id: e.face,
          row: e.row,
          col: e.col,
          health: e.health,
          spawned_at: e[:spawned_at] || 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    if hiss_entries != [] do
      hiss_entries
      |> Enum.chunk_every(500)
      |> Enum.each(fn chunk ->
        Repo.insert_all(HissEntity, chunk)
      end)
    end
  end

  defp serialize_state(state) when is_map(state) do
    Map.new(state, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      val = if is_atom(v) and not is_nil(v), do: Atom.to_string(v), else: v
      {key, val}
    end)
  end
end
