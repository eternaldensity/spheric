defmodule Spheric.Game.SaveServer do
  @moduledoc """
  Background persistence process.

  Periodically flushes dirty ETS state to PostgreSQL. Runs on a configurable
  interval (default 30 seconds). Separate from WorldServer to avoid blocking
  the 200ms tick loop.
  """

  use GenServer

  alias Spheric.Game.{Persistence, WorldStore}

  require Logger

  @default_save_interval_ms 30_000

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Trigger an immediate save. Used by WorldServer on shutdown."
  def save_now do
    GenServer.call(__MODULE__, :save_now, 15_000)
  end

  @doc "Set the world_id to save against. Called once by WorldServer after init."
  def set_world(world_id) do
    GenServer.cast(__MODULE__, {:set_world, world_id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    interval =
      Application.get_env(:spheric, __MODULE__, [])
      |> Keyword.get(:save_interval, @default_save_interval_ms)

    {:ok, %{world_id: nil, save_interval: interval}}
  end

  @impl true
  def handle_cast({:set_world, world_id}, state) do
    schedule_save(state.save_interval)
    {:noreply, %{state | world_id: world_id}}
  end

  @impl true
  def handle_call(:save_now, _from, state) do
    result = do_save(state)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:periodic_save, state) do
    do_save(state)
    schedule_save(state.save_interval)
    {:noreply, state}
  end

  defp schedule_save(interval) do
    Process.send_after(self(), :periodic_save, interval)
  end

  defp do_save(%{world_id: nil}) do
    Logger.debug("SaveServer: no world_id set, skipping save")
    :ok
  end

  defp do_save(%{world_id: world_id}) do
    {dirty_tiles, dirty_buildings, removed_buildings} = WorldStore.drain_dirty()

    if dirty_tiles == [] and dirty_buildings == [] and removed_buildings == [] do
      Logger.debug("SaveServer: nothing dirty, skipping save")
      :ok
    else
      Logger.info(
        "SaveServer: saving #{length(dirty_tiles)} tiles, " <>
          "#{length(dirty_buildings)} buildings, " <>
          "#{length(removed_buildings)} removed"
      )

      Persistence.save_dirty(world_id, dirty_tiles, dirty_buildings, removed_buildings)
    end
  end
end
