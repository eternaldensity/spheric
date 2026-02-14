defmodule Spheric.Game.ShiftCycle do
  @moduledoc """
  Shift Cycle — sun-driven day/night cycle on the sphere.

  A directional "sun" rotates around the sphere. Half the planet is
  illuminated and half is in shadow at any time. Each face's light level
  is the dot product of its outward normal with the sun direction.

  The cycle is divided into 4 named phases (dawn, zenith, dusk, nadir)
  for biome productivity modifiers. Phase transitions still broadcast
  to clients for UI updates.
  """

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT

  @cycle_table :spheric_shift_cycle

  # Full rotation = 4 phases × 600 ticks = 2400 ticks (~8 min)
  @phase_duration 600
  @full_cycle @phase_duration * 4

  @phases [:dawn, :zenith, :dusk, :nadir]

  @phase_modifiers %{
    dawn: %{tundra: 0.20, volcanic: -0.10, grassland: 0.0, desert: 0.0, forest: 0.0},
    zenith: %{desert: 0.20, forest: -0.10, grassland: 0.0, tundra: 0.0, volcanic: 0.0},
    dusk: %{forest: 0.20, desert: -0.10, grassland: 0.0, tundra: 0.0, volcanic: 0.0},
    nadir: %{volcanic: 0.20, tundra: -0.10, grassland: 0.0, desert: 0.0, forest: 0.0}
  }

  # Lighting palette per phase — ambient/bg set the mood, directional tints the sun
  @phase_lighting %{
    dawn: %{ambient: 0x2A3344, directional: 0xFFCC88, intensity: 0.7, bg: 0x080812},
    zenith: %{ambient: 0x667788, directional: 0xFFFFDD, intensity: 1.0, bg: 0x121222},
    dusk: %{ambient: 0x332233, directional: 0xFF8866, intensity: 0.6, bg: 0x06040C},
    nadir: %{ambient: 0x111118, directional: 0x334466, intensity: 0.3, bg: 0x020204}
  }

  # Threshold: faces with illumination below this are "dark"
  @dark_threshold 0.15

  # Precompute normalized face normals at compile time
  @face_normals (
    for i <- 0..29 do
      RT.normalize(RT.face_center(i))
    end
    |> List.to_tuple()
  )

  # --- Public API ---

  def init do
    unless :ets.whereis(@cycle_table) != :undefined do
      :ets.new(@cycle_table, [:named_table, :set, :public, read_concurrency: true])
    end

    case :ets.lookup(@cycle_table, :state) do
      [] ->
        :ets.insert(@cycle_table, {:state, %{
          sun_angle: 0.0,
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

  @doc "Get the current sun direction as {x, y, z}."
  def sun_direction do
    case state() do
      nil -> {1.0, 0.0, 0.0}
      s -> angle_to_direction(s.sun_angle)
    end
  end

  @doc "Get the illumination level for a face (0.0 = full shadow, 1.0 = full sun)."
  def face_illumination(face_id) when face_id >= 0 and face_id <= 29 do
    {sx, sy, sz} = sun_direction()
    {nx, ny, nz} = elem(@face_normals, face_id)
    max(0.0, sx * nx + sy * ny + sz * nz)
  end

  @doc "Returns true when the given face is in darkness (illumination below threshold)."
  def dark?(face_id) when face_id >= 0 and face_id <= 29 do
    face_illumination(face_id) < @dark_threshold
  end

  @doc "Returns the outward normal for a face."
  def face_normal(face_id) when face_id >= 0 and face_id <= 29 do
    elem(@face_normals, face_id)
  end

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
  Returns `{:phase_changed, new_phase, lighting, modifiers}` or
  `{:sun_moved, sun_dir}` or `:no_change`.
  """
  def process_tick(tick) do
    if rem(tick, 10) != 0 do
      :no_change
    else
      current = state()

      if current == nil do
        :no_change
      else
        # Advance sun angle
        angle_step = 2 * :math.pi() * 10 / @full_cycle
        new_angle = fmod(current.sun_angle + angle_step, 2 * :math.pi())
        new_phase = phase_for_angle(new_angle)
        new_phase_tick = if new_phase == current.current_phase, do: current.phase_tick + 10, else: 0

        new_state = %{current |
          sun_angle: new_angle,
          current_phase: new_phase,
          phase_tick: new_phase_tick
        }
        :ets.insert(@cycle_table, {:state, new_state})

        sun_dir = angle_to_direction(new_angle)

        if new_phase != current.current_phase do
          lighting = Map.get(@phase_lighting, new_phase)
          modifiers = Map.get(@phase_modifiers, new_phase)
          {:phase_changed, new_phase, lighting, modifiers, sun_dir}
        else
          {:sun_moved, sun_dir}
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

  # --- Private helpers ---

  # Sun rotates in the XZ plane (Y is the polar axis of the sphere)
  defp angle_to_direction(angle) do
    {:math.cos(angle), 0.0, :math.sin(angle)}
  end

  # Map angle quadrant to phase name
  defp phase_for_angle(angle) do
    quarter = :math.pi() / 2

    cond do
      angle < quarter -> :dawn
      angle < 2 * quarter -> :zenith
      angle < 3 * quarter -> :dusk
      true -> :nadir
    end
  end

  # Float modulo (Elixir's rem/2 is integer-only)
  defp fmod(a, b) do
    a - Float.floor(a / b) * b
  end
end
