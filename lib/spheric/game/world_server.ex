defmodule Spheric.Game.WorldServer do
  @moduledoc """
  GenServer managing the game world state.

  Owns the ETS tables (via WorldStore), runs the tick loop, and serializes
  all write operations (building placement/removal). Read operations go
  directly to ETS without bottlenecking through the GenServer.

  Broadcasts changes to per-face PubSub topics: `"world:face:{face_id}"`.
  """

  use GenServer

  alias Spheric.Game.{WorldStore, WorldGen, Buildings, TickProcessor}

  require Logger

  @tick_interval_ms 200
  @default_seed 42

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Place a building at the given tile. Returns :ok or {:error, reason}."
  def place_building({_face_id, _row, _col} = key, type, orientation \\ 0) do
    GenServer.call(__MODULE__, {:place_building, key, type, orientation})
  end

  @doc "Remove a building at the given tile. Returns :ok or {:error, :no_building}."
  def remove_building({_face_id, _row, _col} = key) do
    GenServer.call(__MODULE__, {:remove_building, key})
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
    seed = Keyword.get(opts, :seed, @default_seed)
    subdivisions = Application.get_env(:spheric, :subdivisions, 16)

    Logger.info("WorldServer starting (seed=#{seed}, subdivisions=#{subdivisions})")

    WorldStore.init()

    tile_count = WorldGen.generate(seed: seed, subdivisions: subdivisions)
    Logger.info("WorldGen complete: #{tile_count} tiles generated")

    schedule_tick()

    {:ok, %{tick: 0, seed: seed}}
  end

  @impl true
  def handle_call({:place_building, key, type, orientation}, _from, state) do
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

      true ->
        building = %{type: type, orientation: orientation, state: Buildings.initial_state(type)}
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
  def handle_call({:remove_building, key}, _from, state) do
    {face_id, _row, _col} = key

    if WorldStore.has_building?(key) do
      WorldStore.remove_building(key)

      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:building_removed, key}
      )

      {:reply, :ok, state}
    else
      {:reply, {:error, :no_building}, state}
    end
  end

  @impl true
  def handle_call(:tick_count, _from, state) do
    {:reply, state.tick, state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_tick = state.tick + 1

    {_tick, items_by_face} = TickProcessor.process_tick(new_tick)

    for {face_id, items} <- items_by_face do
      Phoenix.PubSub.broadcast(
        Spheric.PubSub,
        "world:face:#{face_id}",
        {:tick_update, new_tick, face_id, items}
      )
    end

    schedule_tick()
    {:noreply, %{state | tick: new_tick}}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_ms)
  end
end
