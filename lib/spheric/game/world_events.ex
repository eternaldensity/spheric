defmodule Spheric.Game.WorldEvents do
  @moduledoc """
  World Events system.

  Periodic server-triggered events that affect the entire sphere:
  - Hiss Surge: temporary spike in corruption spread rate and entity spawns
  - Meteor Shower: random resource deposits appear on empty tiles
  - Resonance Cascade: all altered items pulse, granting temporary double effects
  - Entity Migration: creatures relocate en masse to new biome-appropriate tiles

  Events are tracked in an ETS table with active event state and cooldowns.
  """

  alias Spheric.Game.{WorldStore, Creatures, Hiss}

  require Logger

  @events_table :spheric_world_events

  # Event check interval (ticks)
  @check_interval 100
  # Minimum world age before events start
  @events_start_tick 1000
  # Minimum ticks between events
  @event_cooldown 500
  # Event duration in ticks
  @event_duration 150

  @event_types [:hiss_surge, :meteor_shower, :resonance_cascade, :entity_migration]

  @resource_types [:iron, :copper, :quartz, :titanium, :oil, :sulfur]

  # --- Public API ---

  def init do
    unless :ets.whereis(@events_table) != :undefined do
      :ets.new(@events_table, [:named_table, :set, :public, read_concurrency: true])
    end

    # Initialize state if not present
    case :ets.lookup(@events_table, :state) do
      [] ->
        :ets.insert(@events_table, {:state, %{
          active_event: nil,
          event_start_tick: 0,
          last_event_tick: 0,
          event_history: []
        }})
      _ -> :ok
    end

    :ok
  end

  @doc "Get the current world event state."
  def state do
    case :ets.whereis(@events_table) do
      :undefined -> %{active_event: nil, event_start_tick: 0, last_event_tick: 0, event_history: []}
      _ ->
        case :ets.lookup(@events_table, :state) do
          [{:state, s}] -> s
          [] -> %{active_event: nil, event_start_tick: 0, last_event_tick: 0, event_history: []}
        end
    end
  end

  @doc "Get the currently active event, or nil."
  def active_event do
    state().active_event
  end

  @doc "Check if a specific event type is currently active."
  def active?(event_type) do
    state().active_event == event_type
  end

  @doc "Get event history (most recent first)."
  def history do
    state().event_history
  end

  @doc "Event type display info."
  def event_info(:hiss_surge), do: %{
    name: "Hiss Surge",
    description: "Corruption spread accelerated. Hiss entities appearing at alarming rates.",
    color: 0xFF2222
  }
  def event_info(:meteor_shower), do: %{
    name: "Meteor Shower",
    description: "Extraplanar material deposits detected across the sphere surface.",
    color: 0xFFAA44
  }
  def event_info(:resonance_cascade), do: %{
    name: "Resonance Cascade",
    description: "All Altered Items are resonating. Doubled effect potency.",
    color: 0xAA44FF
  }
  def event_info(:entity_migration), do: %{
    name: "Entity Migration",
    description: "Altered entities are relocating. New capture opportunities emerge.",
    color: 0x44AAFF
  }
  def event_info(_), do: %{name: "Unknown", description: "", color: 0x888888}

  @doc """
  Process world events for the current tick.
  Returns `{event_started, event_ended, event_effects}` where:
  - event_started: `{event_type, info}` or nil
  - event_ended: `event_type` or nil
  - event_effects: list of effects applied this tick
  """
  def process_tick(tick, seed) do
    if tick < @events_start_tick or rem(tick, @check_interval) != 0 do
      {nil, nil, []}
    else
      current = state()

      cond do
        # Active event: check if it should end
        current.active_event != nil ->
          if tick - current.event_start_tick >= @event_duration do
            end_event(tick, current)
          else
            # Apply ongoing effects
            effects = apply_event_effects(tick, seed, current.active_event)
            {nil, nil, effects}
          end

        # No active event: check if we should start one
        tick - current.last_event_tick >= @event_cooldown ->
          maybe_start_event(tick, seed, current)

        true ->
          {nil, nil, []}
      end
    end
  end

  @doc "Put state directly (for persistence)."
  def put_state(s) do
    :ets.insert(@events_table, {:state, s})
  end

  @doc "Clear all event state."
  def clear do
    if :ets.whereis(@events_table) != :undefined do
      :ets.delete_all_objects(@events_table)
    end
  end

  # --- Internal ---

  defp maybe_start_event(tick, seed, current) do
    rng = :rand.seed_s(:exsss, {seed, tick, tick * 17})
    {roll, rng} = :rand.uniform_s(rng)

    # 40% chance of event per check
    if roll < 0.4 do
      {idx, _rng} = random_int(rng, length(@event_types))
      event_type = Enum.at(@event_types, idx)

      new_state = %{current |
        active_event: event_type,
        event_start_tick: tick,
        event_history: [{event_type, tick} | Enum.take(current.event_history, 19)]
      }
      :ets.insert(@events_table, {:state, new_state})

      Logger.info("World Event started: #{event_type} at tick #{tick}")

      # Apply immediate effects
      effects = apply_start_effects(tick, seed, event_type)
      {{event_type, event_info(event_type)}, nil, effects}
    else
      {nil, nil, []}
    end
  end

  defp end_event(tick, current) do
    event_type = current.active_event

    new_state = %{current |
      active_event: nil,
      event_start_tick: 0,
      last_event_tick: tick
    }
    :ets.insert(@events_table, {:state, new_state})

    Logger.info("World Event ended: #{event_type} at tick #{tick}")
    {nil, event_type, []}
  end

  defp apply_start_effects(tick, seed, :meteor_shower) do
    # Drop 5-15 random resource deposits on empty tiles
    rng = :rand.seed_s(:exsss, {seed, tick, tick * 19})
    n = Application.get_env(:spheric, :subdivisions, 64)
    {count, rng} = random_int(rng, 11)
    count = count + 5

    {deposits, _rng} =
      Enum.reduce(1..count, {[], rng}, fn _i, {acc, rng} ->
        {face_id, rng} = random_int(rng, 30)
        {row, rng} = random_int(rng, n)
        {col, rng} = random_int(rng, n)
        key = {face_id, row, col}

        tile = WorldStore.get_tile(key)

        if tile && tile.resource == nil && !WorldStore.has_building?(key) do
          {res_idx, rng} = random_int(rng, length(@resource_types))
          resource = Enum.at(@resource_types, res_idx)
          {amount_roll, rng} = random_int(rng, 500)
          amount = amount_roll + 100

          WorldStore.put_tile(key, %{tile | resource: {resource, amount}})
          {[{key, resource, amount} | acc], rng}
        else
          {acc, rng}
        end
      end)

    Enum.map(deposits, fn {key, resource, amount} ->
      {:meteor_deposit, key, resource, amount}
    end)
  end

  defp apply_start_effects(tick, seed, :entity_migration) do
    # Move all wild creatures to new random valid positions
    creatures = Creatures.all_wild_creatures()
    rng = :rand.seed_s(:exsss, {seed, tick, tick * 23})
    n = Application.get_env(:spheric, :subdivisions, 64)

    {moves, _rng} =
      Enum.reduce(creatures, {[], rng}, fn {id, creature}, {acc, rng} ->
        type_info = Creatures.creature_type(creature.type)
        valid_biomes = type_info.biomes

        # Try to find a valid tile
        {face_id, rng} = random_int(rng, 30)
        {row, rng} = random_int(rng, n)
        {col, rng} = random_int(rng, n)
        key = {face_id, row, col}

        tile = WorldStore.get_tile(key)

        if tile && tile.terrain in valid_biomes && !WorldStore.has_building?(key) do
          updated = %{creature | face: face_id, row: row, col: col}
          Creatures.put_wild_creature(id, updated)
          {[{id, updated} | acc], rng}
        else
          {acc, rng}
        end
      end)

    Enum.map(moves, fn {id, creature} ->
      {:creature_migrated, id, creature}
    end)
  end

  defp apply_start_effects(_tick, _seed, _event_type), do: []

  defp apply_event_effects(tick, seed, :hiss_surge) do
    # During hiss surge: extra corruption seeding every check
    if rem(tick, 25) == 0 do
      extra = Hiss.maybe_seed_corruption(tick, seed + 999)
      Enum.map(extra, fn {key, data} -> {:extra_corruption, key, data} end)
    else
      []
    end
  end

  defp apply_event_effects(_tick, _seed, _event_type), do: []

  defp random_int(rng, max) do
    {roll, rng} = :rand.uniform_s(rng)
    {trunc(roll * max) |> min(max - 1), rng}
  end
end
