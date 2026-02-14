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
    Research
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

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    seed = Keyword.get(opts, :seed, @default_seed)
    subdivisions = Application.get_env(:spheric, :subdivisions, 64)

    Logger.info("WorldServer starting (seed=#{seed}, subdivisions=#{subdivisions})")

    WorldStore.init()
    Research.init()

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

      true ->
        building = %{
          type: type,
          orientation: orientation,
          state: Buildings.initial_state(type),
          owner_id: owner[:id]
        }

        WorldStore.put_building(key, building)

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

          true ->
            building = %{
              type: type,
              orientation: orientation,
              state: Buildings.initial_state(type),
              owner_id: owner[:id]
            }

            WorldStore.put_building(key, building)

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
  def handle_call(:tick_count, _from, state) do
    {:reply, state.tick, state}
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
