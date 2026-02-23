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

  alias Spheric.Game.Schema.{
    World,
    Building,
    TileResource,
    Player,
    Creature,
    Corruption,
    HissEntity,
    ResearchProgress
  }

  alias Spheric.Game.Schema.Territory, as: TerritorySchema
  alias Spheric.Game.Schema.Trade

  alias Spheric.Game.{WorldStore, WorldGen, Creatures, Hiss, Territory, Trading, WorldEvents, BoardContact, ShiftCycle, GroundItems, StarterKit}

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

  @doc "Apply a drone upgrade for a player. Persists to DB."
  def apply_drone_upgrade(player_id, upgrade) do
    case Repo.get_by(Player, player_id: player_id) do
      nil ->
        :error

      player ->
        current = player.drone_upgrades || %{}
        updated = Map.put(current, Atom.to_string(upgrade), true)

        player
        |> Player.changeset(%{drone_upgrades: updated})
        |> Repo.update()
    end
  end

  @doc "Get a player's drone upgrades map. Returns %{} if not found."
  def get_drone_upgrades(player_id) do
    case Repo.get_by(Player, player_id: player_id) do
      nil -> %{}
      player -> player.drone_upgrades || %{}
    end
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

        # Load territory claims
        Territory.load_territories(world.id)

        # Load active trades
        Trading.load_trades(world.id)

        # Load Phase 8 state
        load_phase8_state(world.id)

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

    save_step("tile_resources", fn -> save_tile_resources(world_id, dirty_tiles, now) end)
    save_step("buildings", fn -> save_buildings(world_id, dirty_buildings, now) end)
    save_step("delete_buildings", fn -> delete_buildings(world_id, removed_buildings) end)
    save_step("creatures", fn -> save_creatures(world_id, now) end)
    save_step("corruption", fn -> save_corruption(world_id, now) end)
    save_step("territories", fn -> Territory.save_territories(world_id, now) end)
    save_step("trades", fn -> Trading.save_trades(world_id, now) end)
    save_step("phase8_state", fn -> save_phase8_state(world_id) end)

    :ok
  end

  defp save_step(label, fun) do
    fun.()
  rescue
    e ->
      Logger.error("SaveServer: failed to save #{label}: #{Exception.message(e)}")
      :error
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

  @doc """
  Delete all persisted data for a world. Used during world reset.
  """
  def delete_world(world_id) do
    Repo.delete_all(from b in Building, where: b.world_id == ^world_id)
    Repo.delete_all(from tr in TileResource, where: tr.world_id == ^world_id)
    Repo.delete_all(from c in Creature, where: c.world_id == ^world_id)
    Repo.delete_all(from c in Corruption, where: c.world_id == ^world_id)
    Repo.delete_all(from h in HissEntity, where: h.world_id == ^world_id)
    Repo.delete_all(from t in TerritorySchema, where: t.world_id == ^world_id)
    Repo.delete_all(from t in Trade, where: t.world_id == ^world_id)
    Repo.delete_all(from r in ResearchProgress, where: r.world_id == ^world_id)

    # Delete Phase 8 state file
    path = phase8_state_path(world_id)
    File.rm(path)

    # Delete the world record itself
    Repo.delete_all(from w in World, where: w.id == ^world_id)

    Logger.info("Deleted all DB data for world #{world_id}")
    :ok
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
    :input_c,
    :last_submitted,
    :altered_effect,
    :fuel,
    :fuel_type,
    :item_type,
    :output_type
  ]

  defp atomize_state_value(key, value) when key in @atom_fields and is_binary(value) do
    String.to_atom(value)
  end

  # Nested construction state needs recursive atomization
  defp atomize_state_value(:construction, value) when is_map(value) do
    construction = atomize_state_keys(value)

    # Atomize the keys in required/delivered maps
    construction =
      if is_map(construction[:required]) do
        Map.put(construction, :required, atomize_item_map(construction.required))
      else
        construction
      end

    if is_map(construction[:delivered]) do
      Map.put(construction, :delivered, atomize_item_map(construction.delivered))
    else
      construction
    end
  end

  defp atomize_state_value(_key, value), do: value

  defp atomize_item_map(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, v}
    end)
  end

  defp atomize_item_map(other), do: other

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

    all_entries = wild_entries ++ captured_entries

    # Use a transaction so delete+rewrite is atomic — no data loss on failure
    Repo.transaction(fn ->
      Creature
      |> where([c], c.world_id == ^world_id)
      |> Repo.delete_all()

      if all_entries != [] do
        all_entries
        |> Enum.chunk_every(500)
        |> Enum.each(fn chunk ->
          Repo.insert_all(Creature, chunk)
        end)
      end
    end)
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

    # Use a transaction so delete+rewrite is atomic — no data loss on failure
    Repo.transaction(fn ->
      Corruption
      |> where([c], c.world_id == ^world_id)
      |> Repo.delete_all()

      if corruption_entries != [] do
        corruption_entries
        |> Enum.chunk_every(500)
        |> Enum.each(fn chunk ->
          Repo.insert_all(Corruption, chunk)
        end)
      end

      HissEntity
      |> where([h], h.world_id == ^world_id)
      |> Repo.delete_all()

      if hiss_entries != [] do
        hiss_entries
        |> Enum.chunk_every(500)
        |> Enum.each(fn chunk ->
          Repo.insert_all(HissEntity, chunk)
        end)
      end
    end)
  end

  # Phase 8: Save world events, board contact, and shift cycle state to a file
  # alongside the database. These are lightweight state that doesn't need
  # a full DB schema — persisted as Erlang terms.
  defp save_phase8_state(world_id) do
    state = %{
      world_events: WorldEvents.state(),
      board_contact: BoardContact.state(),
      shift_cycle: ShiftCycle.state(),
      ground_items: GroundItems.all(),
      starter_kits: StarterKit.all()
    }

    path = phase8_state_path(world_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(state))
  rescue
    e -> Logger.warning("Failed to save Phase 8 state: #{inspect(e)}")
  end

  @doc "Load Phase 8 state from file (called during world load)."
  def load_phase8_state(world_id) do
    path = phase8_state_path(world_id)

    case File.read(path) do
      {:ok, data} ->
        state = :erlang.binary_to_term(data)
        if state[:world_events], do: WorldEvents.put_state(state.world_events)
        if state[:board_contact], do: BoardContact.put_state(state.board_contact)
        if state[:shift_cycle], do: ShiftCycle.put_state(state.shift_cycle)
        if state[:ground_items], do: GroundItems.put_all(state.ground_items)
        if state[:starter_kits], do: StarterKit.put_all(state.starter_kits)
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp phase8_state_path(world_id) do
    data_dir = Application.get_env(:spheric, :data_dir, "priv/data")
    Path.join([data_dir, "phase8_#{world_id}.bin"])
  end

  defp serialize_state(state) when is_map(state) do
    Map.new(state, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k

      val =
        cond do
          is_map(v) -> serialize_state(v)
          is_atom(v) and not is_nil(v) and not is_boolean(v) -> Atom.to_string(v)
          true -> v
        end

      {key, val}
    end)
  end
end
