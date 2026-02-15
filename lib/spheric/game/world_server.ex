defmodule Spheric.Game.WorldServer do
  @moduledoc """
  GenServer managing the game world state.

  Owns the ETS tables (via WorldStore), runs the tick loop, and serializes
  all write operations (building placement/removal). Read operations go
  directly to ETS without bottlenecking through the GenServer.

  Broadcasts changes to per-face PubSub topics: `"world:face:{face_id}"`.
  """

  use GenServer

  alias Spheric.Game.{
    WorldStore,
    WorldGen,
    Buildings,
    TickProcessor,
    Persistence,
    SaveServer,
    Research,
    Creatures,
    AlteredItems,
    Hiss,
    Territory,
    Trading,
    Statistics,
    WorldEvents,
    TheBoard,
    BoardContact,
    ShiftCycle,
    ConstructionCosts,
    GroundItems,
    StarterKit,
    Power
  }

  require Logger

  @tick_interval_ms 200
  @default_seed 42

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Place a building at the given tile. Returns :ok or {:error, reason}."
  def place_building({_face_id, _row, _col} = key, type, orientation \\ 0, owner \\ %{}) do
    GenServer.call(__MODULE__, {:place_building, key, type, orientation, owner})
  end

  @doc "Place multiple buildings atomically. Returns list of {key, :ok | {:error, reason}}."
  def place_buildings(placements) when is_list(placements) do
    GenServer.call(__MODULE__, {:place_buildings, placements})
  end

  @doc "Remove a building at the given tile. Returns :ok or {:error, :no_building}."
  def remove_building({_face_id, _row, _col} = key, player_id \\ nil) do
    GenServer.call(__MODULE__, {:remove_building, key, player_id})
  end

  @doc "Remove multiple buildings. Returns list of {key, :ok | {:error, reason}}."
  def remove_buildings(keys, player_id \\ nil) when is_list(keys) do
    GenServer.call(__MODULE__, {:remove_buildings, keys, player_id})
  end

  @doc """
  Read tile state directly from ETS (no GenServer call).
  Returns tile data map or nil.
  """
  def get_tile(key), do: WorldStore.get_tile(key)

  @doc """
  Read building state directly from ETS (no GenServer call).
  Returns building data map or nil.
  """
  def get_building(key), do: WorldStore.get_building(key)

  @doc "Get a snapshot of all tiles and buildings for a face. Direct ETS reads."
  def get_face_snapshot(face_id) do
    %{
      tiles: WorldStore.get_face_tiles(face_id),
      buildings: WorldStore.get_face_buildings(face_id)
    }
  end

  @doc "Returns the current tick count."
  def tick_count do
    GenServer.call(__MODULE__, :tick_count)
  end

  @doc "Reset the world with a new seed. Clears all state and regenerates terrain."
  def reset_world(new_seed) do
    GenServer.call(__MODULE__, {:reset_world, new_seed}, 60_000)
  end

  @doc "Get current world info for admin display."
  def world_info do
    GenServer.call(__MODULE__, :world_info)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    seed = Keyword.get(opts, :seed, @default_seed)
    subdivisions = Application.get_env(:spheric, :subdivisions, 64)

    Logger.info("WorldServer starting (seed=#{seed}, subdivisions=#{subdivisions})")

    WorldStore.init()
    Research.init()
    Creatures.init()
    AlteredItems.init()
    Spheric.Game.ObjectsOfPower.init()
    Hiss.init()
    Territory.init()
    Trading.init()
    Statistics.init()
    WorldEvents.init()
    TheBoard.init()
    BoardContact.init()
    ShiftCycle.init()
    GroundItems.init()
    StarterKit.init()
    Power.init()

    # Try to load an existing world from the database
    {world_id, actual_seed} =
      case Persistence.load_world("default") do
        {:ok, world} ->
          Logger.info("Loaded saved world (id=#{world.id}, seed=#{world.seed})")
          {world.id, world.seed}

        :none ->
          Logger.info("No saved world found, generating fresh")
          tile_count = WorldGen.generate(seed: seed, subdivisions: subdivisions)
          Logger.info("WorldGen complete: #{tile_count} tiles generated")

          world = Persistence.ensure_world("default", seed, subdivisions)
          {world.id, seed}
      end

    # Tell SaveServer which world we're persisting
    SaveServer.set_world(world_id)

    schedule_tick()

    {:ok, %{tick: 0, seed: actual_seed, world_id: world_id, prev_item_faces: MapSet.new()}}
  end

  @impl true
  def handle_call({:place_building, key, type, orientation, owner}, _from, state) do
    {face_id, _row, _col} = key
    tile = WorldStore.get_tile(key)

    cond do
      tile == nil ->
        {:reply, {:error, :invalid_tile}, state}

      not Buildings.valid_type?(type) ->
        {:reply, {:error, :invalid_building_type}, state}

      WorldStore.has_building?(key) ->
        {:reply, {:error, :tile_occupied}, state}

      not Buildings.can_place_on?(type, tile) ->
        {:reply, {:error, :invalid_placement}, state}

      not Research.can_place?(owner[:id], type) ->
        {:reply, {:error, :not_unlocked}, state}

      Hiss.blocks_placement?(key) and type not in [:purification_beacon, :defense_turret, :dimensional_stabilizer] ->
        {:reply, {:error, :corrupted_tile}, state}

      not Territory.can_build?(owner[:id], key) ->
        {:reply, {:error, :territory_blocked}, state}

      true ->
        initial_state = Buildings.initial_state(type)

        # Apply altered item effect if tile has one
        state_with_altered =
          case AlteredItems.get(key) do
            nil -> initial_state
            altered -> Map.put(initial_state, :altered_effect, altered.id)
          end

        # Check starter kit — free placement if available
        {state_with_construction, _used_starter} =
          if owner[:id] && StarterKit.has_free?(owner[:id], type) do
            StarterKit.consume(owner[:id], type)
            {state_with_altered, true}
          else
            # Apply construction costs
            case ConstructionCosts.initial_construction(type) do
              nil ->
                {state_with_altered, false}

              construction ->
                # Gathering post is always free
                if type == :gathering_post do
                  {state_with_altered, false}
                else
                  {Map.put(state_with_altered, :construction, construction), false}
                end
            end
          end

        building = %{
          type: type,
          orientation: orientation,
          state: state_with_construction,
          owner_id: owner[:id]
        }

        WorldStore.put_building(key, building)

        # If this is a claim beacon, establish territory
        if type == :claim_beacon do
          Territory.claim(state.world_id, owner[:id], key)
          broadcast_territory_update(key)
        end

        Phoenix.PubSub.broadcast(
          Spheric.PubSub,
          "world:face:#{face_id}",
          {:building_placed, key, building}
        )

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:place_buildings, placements}, _from, state) do
    results =
      Enum.map(placements, fn {key, type, orientation, owner} ->
        {face_id, _row, _col} = key
        tile = WorldStore.get_tile(key)

        cond do
          tile == nil ->
            {key, {:error, :invalid_tile}}

          not Buildings.valid_type?(type) ->
            {key, {:error, :invalid_building_type}}

          WorldStore.has_building?(key) ->
            {key, {:error, :tile_occupied}}

          not Buildings.can_place_on?(type, tile) ->
            {key, {:error, :invalid_placement}}

          not Research.can_place?(owner[:id], type) ->
            {key, {:error, :not_unlocked}}

          Hiss.blocks_placement?(key) and type not in [:purification_beacon, :defense_turret, :dimensional_stabilizer] ->
            {key, {:error, :corrupted_tile}}

          not Territory.can_build?(owner[:id], key) ->
            {key, {:error, :territory_blocked}}

          true ->
            initial_state = Buildings.initial_state(type)

            state_with_altered =
              case AlteredItems.get(key) do
                nil -> initial_state
                altered -> Map.put(initial_state, :altered_effect, altered.id)
              end

            {state_with_construction, _used_starter} =
              if owner[:id] && StarterKit.has_free?(owner[:id], type) do
                StarterKit.consume(owner[:id], type)
                {state_with_altered, true}
              else
                case ConstructionCosts.initial_construction(type) do
                  nil ->
                    {state_with_altered, false}

                  construction ->
                    if type == :gathering_post do
                      {state_with_altered, false}
                    else
                      {Map.put(state_with_altered, :construction, construction), false}
                    end
                end
              end

            building = %{
              type: type,
              orientation: orientation,
              state: state_with_construction,
              owner_id: owner[:id]
            }

            WorldStore.put_building(key, building)

            if type == :claim_beacon do
              Territory.claim(state.world_id, owner[:id], key)
              broadcast_territory_update(key)
            end

            Phoenix.PubSub.broadcast(
              Spheric.PubSub,
              "world:face:#{face_id}",
              {:building_placed, key, building}
            )

            {key, :ok}
        end
      end)

    {:reply, results, state}
  end

  @impl true
  def handle_call({:remove_building, key, player_id}, _from, state) do
    {face_id, _row, _col} = key
    building = WorldStore.get_building(key)

    cond do
      building == nil ->
        {:reply, {:error, :no_building}, state}

      building.owner_id != nil and player_id != nil and building.owner_id != player_id ->
        {:reply, {:error, :not_owner}, state}

      true ->
        # Release territory if this is a claim beacon
        if building.type == :claim_beacon do
          Territory.release(key)
          broadcast_territory_update(key)
        end

        WorldStore.remove_building(key)

        Phoenix.PubSub.broadcast(
          Spheric.PubSub,
          "world:face:#{face_id}",
          {:building_removed, key}
        )

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:remove_buildings, keys, player_id}, _from, state) do
    results =
      Enum.map(keys, fn key ->
        {face_id, _row, _col} = key
        building = WorldStore.get_building(key)

        cond do
          building == nil ->
            {key, {:error, :no_building}}

          building.owner_id != nil and player_id != nil and building.owner_id != player_id ->
            {key, {:error, :not_owner}}

          true ->
            if building.type == :claim_beacon do
              Territory.release(key)
              broadcast_territory_update(key)
            end

            WorldStore.remove_building(key)

            Phoenix.PubSub.broadcast(
              Spheric.PubSub,
              "world:face:#{face_id}",
              {:building_removed, key}
            )

            {key, :ok}
        end
      end)

    {:reply, results, state}
  end

  @impl true
  def handle_call(:tick_count, _from, state) do
    {:reply, state.tick, state}
  end

  @impl true
  def handle_call(:world_info, _from, state) do
    info = %{
      world_id: state.world_id,
      seed: state.seed,
      tick: state.tick,
      tile_count: WorldStore.tile_count(),
      building_count: WorldStore.building_count(),
      subdivisions: Application.get_env(:spheric, :subdivisions, 64)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:reset_world, new_seed}, _from, state) do
    Logger.info("WorldServer: resetting world with new seed #{new_seed}")
    subdivisions = Application.get_env(:spheric, :subdivisions, 64)

    # 1. Delete all DB records for current world
    Persistence.delete_world(state.world_id)

    # 2. Clear all ETS tables
    WorldStore.clear()
    Research.clear()
    Creatures.clear_all()
    AlteredItems.clear()
    Spheric.Game.ObjectsOfPower.clear()
    Hiss.clear_all()
    Territory.clear()
    Trading.clear()
    Statistics.reset()
    WorldEvents.clear()
    TheBoard.clear()
    BoardContact.clear()
    ShiftCycle.clear()
    GroundItems.clear()
    StarterKit.clear()
    Power.clear()

    # 3. Re-initialize subsystems
    Research.init()
    Creatures.init()
    AlteredItems.init()
    Spheric.Game.ObjectsOfPower.init()
    Hiss.init()
    Territory.init()
    Trading.init()
    Statistics.init()
    WorldEvents.init()
    TheBoard.init()
    BoardContact.init()
    ShiftCycle.init()
    GroundItems.init()
    StarterKit.init()
    Power.init()

    # 4. Generate new terrain
    tile_count = WorldGen.generate(seed: new_seed, subdivisions: subdivisions)
    Logger.info("WorldServer reset: #{tile_count} tiles generated with seed #{new_seed}")

    # 5. Create new world DB record
    world = Persistence.ensure_world("default", new_seed, subdivisions)

    # 6. Update SaveServer with new world_id
    SaveServer.set_world(world.id)

    # 7. Broadcast world reset to all connected clients
    Phoenix.PubSub.broadcast(Spheric.PubSub, "world:admin", :world_reset)

    # 8. Reset state
    new_state = %{
      tick: 0,
      seed: new_seed,
      world_id: world.id,
      prev_item_faces: MapSet.new()
    }

    schedule_tick()
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_tick = state.tick + 1

    {_tick, items_by_face, submissions} = TickProcessor.process_tick(new_tick)

    current_item_faces = items_by_face |> Map.keys() |> MapSet.new()

    # Broadcast item updates for faces that have items
    for {face_id, items} <- items_by_face do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:tick_update, new_tick, face_id, items}
      )
    end

    # Broadcast empty updates for faces that had items last tick but don't now,
    # so clients clear stale item data
    for face_id <- MapSet.difference(state.prev_item_faces, current_item_faces) do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:tick_update, new_tick, face_id, []}
      )
    end

    # Process research submissions from submission terminals
    process_submissions(submissions, state.world_id)

    # Creature spawning
    spawned = Creatures.maybe_spawn(new_tick, state.seed)
    broadcast_creature_spawns(spawned)

    # Creature movement
    moved = Creatures.move_creatures(new_tick)
    broadcast_creature_moves(moved)

    # Containment trap processing
    captures = Creatures.process_traps(new_tick)
    broadcast_creature_captures(captures)

    # Broadcast full creature state every 5 ticks for sync
    if rem(new_tick, 5) == 0 do
      broadcast_creature_sync()
    end

    # --- Hiss Corruption Processing ---

    # Seed new corruption zones
    new_corruption = Hiss.maybe_seed_corruption(new_tick, state.seed)
    broadcast_corruption_updates(new_corruption)

    # Spread existing corruption
    spread_updates = Hiss.spread_corruption(new_tick)
    broadcast_corruption_updates(spread_updates)

    # Process purification beacons (clear corruption)
    purified = Hiss.process_purification(new_tick)
    broadcast_corruption_cleared(purified)

    # Building damage from corruption
    damage_results = Hiss.process_building_damage(new_tick)
    broadcast_building_damage(damage_results)

    # Spawn Hiss entities
    spawned_hiss = Hiss.maybe_spawn_hiss_entities(new_tick, state.seed)
    broadcast_hiss_spawns(spawned_hiss)

    # Move Hiss entities
    moved_hiss = Hiss.move_hiss_entities(new_tick)
    broadcast_hiss_moves(moved_hiss)

    # Combat: turrets and creatures vs Hiss entities
    {kills, drops} = Hiss.process_combat(new_tick)
    broadcast_hiss_kills(kills)
    process_hiss_drops(drops)

    # Broadcast full corruption sync every 10 ticks
    if rem(new_tick, 10) == 0 do
      broadcast_corruption_sync()
      broadcast_hiss_sync()
    end

    # --- Phase 8: Endgame Systems ---

    # World Events processing
    {event_started, event_ended, _effects} = WorldEvents.process_tick(new_tick, state.seed)
    broadcast_world_event(event_started, event_ended)

    # Shift Cycle processing
    shift_result = ShiftCycle.process_tick(new_tick)
    broadcast_shift_cycle(shift_result)

    # Creature evolution
    evolved = Creatures.process_evolution(new_tick)
    broadcast_creature_evolutions(evolved)

    schedule_tick()
    {:noreply, %{state | tick: new_tick, prev_item_faces: current_item_faces}}
  end

  defp process_submissions([], _world_id), do: :ok

  defp process_submissions(submissions, world_id) do
    for {_key, player_id, item} <- submissions, player_id != nil do
      case Research.submit_item(world_id, player_id, item) do
        {:completed, case_file_id} ->
          Logger.info("Case file completed: #{case_file_id} by #{player_id}")

          Phoenix.PubSub.broadcast(
            Spheric.PubSub,
            "research:#{player_id}",
            {:case_file_completed, case_file_id}
          )

        {:ok, _submissions} ->
          Phoenix.PubSub.broadcast(
            Spheric.PubSub,
            "research:#{player_id}",
            {:research_progress, item}
          )

        :no_match ->
          :ok
      end
    end
  end

  defp broadcast_creature_spawns([]), do: :ok

  defp broadcast_creature_spawns(spawned) do
    for {id, creature} <- spawned do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{creature.face}",
        {:creature_spawned, id, creature}
      )
    end
  end

  defp broadcast_creature_moves([]), do: :ok

  defp broadcast_creature_moves(moved) do
    for {id, creature} <- moved do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{creature.face}",
        {:creature_moved, id, creature}
      )
    end
  end

  defp broadcast_creature_captures([]), do: :ok

  defp broadcast_creature_captures(captures) do
    for {trap_key, creature_id, creature} <- captures do
      {face_id, _row, _col} = trap_key

      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:creature_captured, creature_id, creature, trap_key}
      )
    end
  end

  defp broadcast_creature_sync do
    creatures_by_face = Creatures.creatures_by_face()

    for {face_id, creatures} <- creatures_by_face do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:creature_sync, face_id, creatures}
      )
    end
  end

  # --- Hiss Corruption Broadcast Helpers ---

  defp broadcast_corruption_updates([]), do: :ok

  defp broadcast_corruption_updates(updates) do
    by_face =
      Enum.group_by(updates, fn {{face, _r, _c}, _data} -> face end)

    for {face_id, face_updates} <- by_face do
      tiles =
        Enum.map(face_updates, fn {{face, row, col}, data} ->
          %{face: face, row: row, col: col, intensity: data.intensity}
        end)

      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:corruption_update, face_id, tiles}
      )
    end
  end

  defp broadcast_corruption_cleared([]), do: :ok

  defp broadcast_corruption_cleared(purified_keys) do
    by_face = Enum.group_by(purified_keys, fn {face, _r, _c} -> face end)

    for {face_id, keys} <- by_face do
      tiles = Enum.map(keys, fn {face, row, col} -> %{face: face, row: row, col: col} end)

      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:corruption_cleared, face_id, tiles}
      )
    end
  end

  defp broadcast_building_damage([]), do: :ok

  defp broadcast_building_damage(results) do
    for {key, action} <- results do
      {face_id, _row, _col} = key

      if action == :destroyed do
        Phoenix.PubSub.broadcast(
          Spheric.PubSub,
          "world:face:#{face_id}",
          {:building_removed, key}
        )
      end

      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:building_damage, key, action}
      )
    end
  end

  defp broadcast_hiss_spawns([]), do: :ok

  defp broadcast_hiss_spawns(spawned) do
    for {id, entity} <- spawned do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{entity.face}",
        {:hiss_spawned, id, entity}
      )
    end
  end

  defp broadcast_hiss_moves([]), do: :ok

  defp broadcast_hiss_moves(moved) do
    for {id, entity} <- moved do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{entity.face}",
        {:hiss_moved, id, entity}
      )
    end
  end

  defp broadcast_hiss_kills([]), do: :ok

  defp broadcast_hiss_kills(kills) do
    for {hiss_id, killer} <- kills do
      # Broadcast on all faces since we don't track the entity's face after deletion
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:0",
        {:hiss_killed, hiss_id, killer}
      )
    end
  end

  defp process_hiss_drops([]), do: :ok

  defp process_hiss_drops(drops) do
    # Place hiss_residue into turret output buffers
    for {turret_key, item} <- drops do
      building = WorldStore.get_building(turret_key)

      if building && building.state[:output_buffer] == nil do
        new_state = %{
          building.state
          | output_buffer: item,
            kills: (building.state[:kills] || 0) + 1
        }

        WorldStore.put_building(turret_key, %{building | state: new_state})
      end
    end
  end

  defp broadcast_corruption_sync do
    by_face = Hiss.corrupted_by_face()

    for {face_id, tiles} <- by_face do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:corruption_sync, face_id, tiles}
      )
    end
  end

  defp broadcast_hiss_sync do
    by_face = Hiss.hiss_entities_by_face()

    for {face_id, entities} <- by_face do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:hiss_sync, face_id, entities}
      )
    end
  end

  defp broadcast_territory_update({face_id, _row, _col}) do
    territories = Territory.territories_on_face(face_id)

    Phoenix.PubSub.broadcast(
      Spheric.PubSub,
      "world:face:#{face_id}",
      {:territory_update, face_id, territories}
    )
  end

  # --- Phase 8 Broadcast Helpers ---

  defp broadcast_world_event(nil, nil), do: :ok

  defp broadcast_world_event(event_started, event_ended) do
    if event_started do
      {event_type, info} = event_started

      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:events",
        {:world_event_started, event_type, info}
      )
    end

    if event_ended do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:events",
        {:world_event_ended, event_ended}
      )
    end
  end

  defp broadcast_shift_cycle(:no_change), do: :ok

  defp broadcast_shift_cycle({:phase_changed, phase, lighting, modifiers, sun_dir}) do
    Phoenix.PubSub.broadcast(
      Spheric.PubSub,
      "world:events",
      {:shift_cycle_changed, phase, lighting, modifiers, sun_dir}
    )
  end

  defp broadcast_shift_cycle({:sun_moved, sun_dir}) do
    Phoenix.PubSub.broadcast(
      Spheric.PubSub,
      "world:events",
      {:sun_moved, sun_dir}
    )
  end

  defp broadcast_creature_evolutions([]), do: :ok

  defp broadcast_creature_evolutions(evolved) do
    for {player_id, creature_id, creature_type} <- evolved do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "research:#{player_id}",
        {:creature_evolved, creature_id, creature_type}
      )
    end
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("WorldServer terminating (reason=#{inspect(reason)}), triggering final save")

    try do
      SaveServer.save_now()
    rescue
      e -> Logger.error("Final save failed: #{inspect(e)}")
    end

    :ok
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_ms)
  end
end
