defmodule Spheric.Game.ShiftCycle do
  @moduledoc """
  Shift Cycle — sphere rotation phases affecting biome productivity and lighting.

  The sphere cycles through 4 phases, each lasting a fixed number of ticks.
  Each phase boosts or penalizes certain biomes' productivity:

  - Dawn:    tundra +20%, volcanic -10%
  - Zenith:  desert +20%, forest -10%
  - Dusk:    forest +20%, desert -10%
  - Nadir:   volcanic +20%, tundra -10%

  Grassland is always neutral. The cycle affects miner extraction rates
  and is reflected in scene lighting on the client.
  """

  @cycle_table :spheric_shift_cycle

  # Each phase lasts this many ticks (200ms per tick = ~2 min per phase)
  @phase_duration 600

  @phases [:dawn, :zenith, :dusk, :nadir]

  @phase_modifiers %{
    dawn: %{tundra: 0.20, volcanic: -0.10, grassland: 0.0, desert: 0.0, forest: 0.0},
    zenith: %{desert: 0.20, forest: -0.10, grassland: 0.0, tundra: 0.0, volcanic: 0.0},
    dusk: %{forest: 0.20, desert: -0.10, grassland: 0.0, tundra: 0.0, volcanic: 0.0},
    nadir: %{volcanic: 0.20, tundra: -0.10, grassland: 0.0, desert: 0.0, forest: 0.0}
  }

  @phase_lighting %{
    dawn: %{ambient: 0x2A3344, directional: 0xFFCC88, intensity: 0.5, bg: 0x080812},
    zenith: %{ambient: 0x667788, directional: 0xFFFFDD, intensity: 1.0, bg: 0x121222},
    dusk: %{ambient: 0x332233, directional: 0xFF8866, intensity: 0.4, bg: 0x06040C},
    nadir: %{ambient: 0x111118, directional: 0x334466, intensity: 0.15, bg: 0x020204}
  }

  @dark_phases [:nadir, :dusk]

  # --- Public API ---

  def init do
    unless :ets.whereis(@cycle_table) != :undefined do
      :ets.new(@cycle_table, [:named_table, :set, :public, read_concurrency: true])
    end

    case :ets.lookup(@cycle_table, :state) do
      [] ->
        :ets.insert(@cycle_table, {:state, %{
          current_phase: :dawn,
          phase_tick: 0
        }})
      _ -> :ok
    end

    :ok
  end

  @doc "Get the current shift cycle state."
  def state do
    case :ets.whereis(@cycle_table) do
      :undefined -> nil
      _ ->
        case :ets.lookup(@cycle_table, :state) do
          [{:state, s}] -> s
          [] -> nil
        end
    end
  end

  @doc "Get the current phase."
  def current_phase do
    case state() do
      nil -> :dawn
      s -> s.current_phase
    end
  end

  @doc "Get the list of all phases."
  def phases, do: @phases

  @doc "Get the phase duration in ticks."
  def phase_duration, do: @phase_duration

  @doc "Get biome modifiers for the current phase."
  def current_modifiers do
    Map.get(@phase_modifiers, current_phase(), %{})
  end

  @doc "Get the biome modifier for a specific biome in the current phase."
  def biome_modifier(biome) do
    case state() do
      nil -> 0.0
      _ ->
        mods = current_modifiers()
        Map.get(mods, biome, 0.0)
    end
  end

  @doc "Get lighting settings for the current phase."
  def current_lighting do
    Map.get(@phase_lighting, current_phase(), Map.get(@phase_lighting, :dawn))
  end

  @doc "Returns true during dark phases (dusk, nadir) when shadow panels can generate."
  def dark?, do: current_phase() in @dark_phases

  @doc """
  Apply the shift cycle modifier to a building's tick rate.
  Returns the modified rate (lower = faster).
  """
  def apply_rate_modifier(base_rate, biome) do
    mod = biome_modifier(biome)

    if mod != 0.0 do
      # Positive modifier = faster (reduce rate), negative = slower (increase rate)
      max(1, round(base_rate * (1.0 - mod)))
    else
      base_rate
    end
  end

  @doc """
  Process the shift cycle for the current tick.
  Returns `{:phase_changed, new_phase, lighting}` or `:no_change`.
  """
  def process_tick(tick) do
    if rem(tick, 10) != 0 do
      :no_change
    else
      current = state()

      if current == nil do
        :no_change
      else
        new_phase_tick = current.phase_tick + 10

        if new_phase_tick >= @phase_duration do
          # Advance to next phase
          phase_idx = Enum.find_index(@phases, &(&1 == current.current_phase))
          next_idx = rem(phase_idx + 1, length(@phases))
          next_phase = Enum.at(@phases, next_idx)

          new_state = %{current | current_phase: next_phase, phase_tick: 0}
          :ets.insert(@cycle_table, {:state, new_state})

          lighting = Map.get(@phase_lighting, next_phase)
          modifiers = Map.get(@phase_modifiers, next_phase)
          {:phase_changed, next_phase, lighting, modifiers}
        else
          :ets.insert(@cycle_table, {:state, %{current | phase_tick: new_phase_tick}})
          :no_change
        end
      end
    end
  end

  @doc "Put state directly (for persistence)."
  def put_state(s) do
    :ets.insert(@cycle_table, {:state, s})
  end

  @doc "Clear all state."
  def clear do
    if :ets.whereis(@cycle_table) != :undefined do
      :ets.delete_all_objects(@cycle_table)
    end
  end

  @doc "Get the progress through the current phase as a percentage (0-100)."
  def phase_progress do
    case state() do
      nil -> 0
      current -> trunc(current.phase_tick / @phase_duration * 100)
    end
  end

  @doc "Get display info for a phase."
  def phase_info(:dawn), do: %{name: "Dawn Shift", description: "Tundra operations enhanced"}
  def phase_info(:zenith), do: %{name: "Zenith Shift", description: "Desert operations enhanced"}
  def phase_info(:dusk), do: %{name: "Dusk Shift", description: "Forest operations enhanced"}
  def phase_info(:nadir), do: %{name: "Nadir Shift", description: "Volcanic operations enhanced"}
  def phase_info(_), do: %{name: "Unknown", description: ""}
end
