defmodule Spheric.Game.ShiftCycle do
  @moduledoc """
  Shift Cycle — sun-driven day/night cycle on the sphere.

  A directional "sun" rotates around the sphere with realistic solar
  positioning based on longitude, latitude, and day of year. The sun's
  elevation varies by latitude and season using proper solar astronomy:

  - **Solar Declination**: The sun's angle above/below the equator,
    varying with day of year due to axial tilt (±23.44°).
  - **Solar Hour Angle**: Driven by the sun_angle (daily rotation).
  - **Solar Elevation**: `sin(elev) = sin(lat)*sin(decl) + cos(lat)*cos(decl)*cos(hour_angle)`

  Each face's light level is the dot product of its outward normal with
  the 3D sun direction vector. The cycle is divided into 4 named phases
  (dawn, zenith, dusk, nadir) for biome productivity modifiers.
  """

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT
  import Bitwise

  @cycle_table :spheric_shift_cycle

  # Full rotation = 4 phases × 1200 ticks = 4800 ticks (~16 min)
  @phase_duration 1200
  @full_cycle @phase_duration * 4

  # Seasonal cycle: 30 game-days = 1 year (each day = 1 full sun rotation)
  @year_length 30

  # Axial tilt in radians (~23.44° like Earth)
  @axial_tilt 23.44 * :math.pi() / 180.0

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

  # 4×4 cells per face
  @cells_per_axis 4

  # Precompute normalized face normals at compile time
  @face_normals (
    for i <- 0..29 do
      RT.normalize(RT.face_center(i))
    end
    |> List.to_tuple()
  )

  # Precompute normalized cell center normals at compile time.
  # Indexed as a tuple of 30 faces, each a tuple of 16 cells (row-major 4×4).
  # Cell center = origin + e1*(cellCol+0.5)/4 + e2*(cellRow+0.5)/4, normalized.
  @cell_normals (
    verts = RT.vertices()
    faces = RT.faces()

    for face_verts <- faces do
      [ai, bi, _ci, di] = face_verts
      {ax, ay, az} = Enum.at(verts, ai)
      {bx, by, bz} = Enum.at(verts, bi)
      {dx, dy, dz} = Enum.at(verts, di)

      # e1 = B - A (col axis), e2 = D - A (row axis)
      e1 = {bx - ax, by - ay, bz - az}
      e2 = {dx - ax, dy - ay, dz - az}

      for cell_row <- 0..3, cell_col <- 0..3 do
        u = (cell_col + 0.5) / 4
        v = (cell_row + 0.5) / 4
        {e1x, e1y, e1z} = e1
        {e2x, e2y, e2z} = e2
        px = ax + e1x * u + e2x * v
        py = ay + e1y * u + e2y * v
        pz = az + e1z * u + e2z * v
        RT.normalize({px, py, pz})
      end
      |> List.to_tuple()
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
          phase_tick: 0,
          day_of_year: 0
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

  @doc """
  Compute camera-local lighting based on how much the camera faces the sun.

  Returns `%{phase, ambient, directional, intensity, bg}` interpolated
  between the zenith (full sun) and nadir (full shadow) palettes.
  """
  def lighting_for_camera({cx, cy, cz}) do
    {sx, sy, sz} = sun_direction()

    # Normalize camera direction
    len = :math.sqrt(cx * cx + cy * cy + cz * cz)

    if len < 0.001 do
      current_lighting() |> Map.put(:phase, current_phase())
    else
      nx = cx / len
      ny = cy / len
      nz = cz / len

      # dot ∈ [-1, 1]: +1 = looking straight at sun, -1 = looking away
      dot = sx * nx + sy * ny + sz * nz
      # Remap to 0..1 where 1 = full sun, 0 = full shadow
      t = (dot + 1.0) / 2.0

      zenith = @phase_lighting[:zenith]
      nadir = @phase_lighting[:nadir]
      dawn = @phase_lighting[:dawn]
      dusk = @phase_lighting[:dusk]

      # Pick phase name from illumination level
      phase =
        cond do
          t > 0.75 -> :zenith
          t > 0.45 -> :dawn
          t > 0.25 -> :dusk
          true -> :nadir
        end

      # Interpolate ambient/bg between the two nearest palettes
      {low, high, local_t} =
        cond do
          t > 0.5 -> {dawn, zenith, (t - 0.5) * 2.0}
          true -> {nadir, dusk, t * 2.0}
        end

      %{
        phase: phase,
        ambient: lerp_color(low.ambient, high.ambient, local_t),
        directional: lerp_color(low.directional, high.directional, t),
        intensity: low.intensity + (high.intensity - low.intensity) * t,
        bg: lerp_color(low.bg, high.bg, local_t)
      }
    end
  end

  @doc "Get the current sun direction as {x, y, z}."
  def sun_direction do
    case state() do
      nil -> {1.0, 0.0, 0.0}
      s -> sun_direction_from(s.sun_angle, Map.get(s, :day_of_year, 0))
    end
  end

  @doc "Get the current day of year (0-based)."
  def day_of_year do
    case state() do
      nil -> 0
      s -> Map.get(s, :day_of_year, 0)
    end
  end

  @doc "Get the year length in game-days."
  def year_length, do: @year_length

  @doc "Get the current solar declination in radians."
  def solar_declination do
    solar_declination_for_day(day_of_year())
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

  @doc """
  Get the illumination level for a specific cell within a face.
  Cell coordinates are derived from tile row/col: cell_row = div(row, 16), cell_col = div(col, 16).
  Returns 0.0 (full shadow) to 1.0 (full sun).
  """
  def cell_illumination(face_id, cell_row, cell_col)
      when face_id >= 0 and face_id <= 29
      and cell_row >= 0 and cell_row <= 3
      and cell_col >= 0 and cell_col <= 3 do
    {sx, sy, sz} = sun_direction()
    {nx, ny, nz} = elem(@cell_normals, face_id) |> elem(cell_row * @cells_per_axis + cell_col)
    max(0.0, sx * nx + sy * ny + sz * nz)
  end

  @doc """
  Get the illumination level for a tile, using its cell's normal.
  Tiles are 64×64 per face, cells are 4×4 (16 tiles per cell).
  """
  def tile_illumination(face_id, row, col)
      when face_id >= 0 and face_id <= 29 do
    cell_illumination(face_id, div(row, 16), div(col, 16))
  end

  @doc "Returns true when a cell is in darkness."
  def cell_dark?(face_id, cell_row, cell_col) do
    cell_illumination(face_id, cell_row, cell_col) < @dark_threshold
  end

  @doc "Returns true when a tile's cell is in darkness."
  def tile_dark?(face_id, row, col) do
    tile_illumination(face_id, row, col) < @dark_threshold
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
        # Advance sun angle (hour angle)
        angle_step = 2 * :math.pi() * 10 / @full_cycle
        old_angle = current.sun_angle
        new_angle = fmod(old_angle + angle_step, 2 * :math.pi())

        # Advance day_of_year when the sun completes a full rotation
        day = Map.get(current, :day_of_year, 0)
        new_day = if new_angle < old_angle, do: rem(day + 1, @year_length), else: day

        new_phase = phase_for_angle(new_angle)
        new_phase_tick = if new_phase == current.current_phase, do: current.phase_tick + 10, else: 0

        new_state = %{current |
          sun_angle: new_angle,
          current_phase: new_phase,
          phase_tick: new_phase_tick
        }
        new_state = Map.put(new_state, :day_of_year, new_day)
        :ets.insert(@cycle_table, {:state, new_state})

        sun_dir = sun_direction_from(new_angle, new_day)

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
    # Migrate old state that lacks sun_angle or day_of_year
    s = if Map.has_key?(s, :sun_angle), do: s, else: Map.put(s, :sun_angle, 0.0)
    s = if Map.has_key?(s, :day_of_year), do: s, else: Map.put(s, :day_of_year, 0)
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

  # Solar declination: the sun's angle above/below the equator for a given day.
  # Varies sinusoidally over the year between -@axial_tilt and +@axial_tilt.
  # Day 0 = spring equinox (declination 0), day year/4 = summer solstice (max tilt).
  defp solar_declination_for_day(day) do
    @axial_tilt * :math.sin(2 * :math.pi() * day / @year_length)
  end

  # Compute 3D sun direction from hour angle and day of year.
  # The sun rotates in the XZ plane (hour angle) but is tilted above/below
  # the equatorial plane by the solar declination (Y axis = polar axis).
  #
  # This gives us a unit vector pointing from the sphere center toward the sun:
  #   x = cos(declination) * cos(hour_angle)
  #   y = sin(declination)
  #   z = cos(declination) * sin(hour_angle)
  defp sun_direction_from(hour_angle, day) do
    decl = solar_declination_for_day(day)
    cos_decl = :math.cos(decl)
    sin_decl = :math.sin(decl)
    {:math.cos(hour_angle) * cos_decl, sin_decl, :math.sin(hour_angle) * cos_decl}
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

  # Linear interpolation between two 0xRRGGBB hex colors
  defp lerp_color(c1, c2, t) do
    t = max(0.0, min(1.0, t))
    r1 = Bitwise.bsr(c1, 16) |> Bitwise.band(0xFF)
    g1 = Bitwise.bsr(c1, 8) |> Bitwise.band(0xFF)
    b1 = Bitwise.band(c1, 0xFF)
    r2 = Bitwise.bsr(c2, 16) |> Bitwise.band(0xFF)
    g2 = Bitwise.bsr(c2, 8) |> Bitwise.band(0xFF)
    b2 = Bitwise.band(c2, 0xFF)
    r = round(r1 + (r2 - r1) * t)
    g = round(g1 + (g2 - g1) * t)
    b = round(b1 + (b2 - b1) * t)
    Bitwise.bsl(r, 16) + Bitwise.bsl(g, 8) + b
  end
end
