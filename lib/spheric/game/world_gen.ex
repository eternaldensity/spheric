defmodule Spheric.Game.WorldGen do
  @moduledoc """
  Procedural terrain generation for the spherical world.

  Uses seeded RNG for reproducibility. Terrain biomes are assigned per cell
  (4x4 cells per face) based on cell center latitude (Y component).
  Resource deposits (iron, copper, quartz, titanium, oil, sulfur) are placed
  randomly with configurable density and biome-weighted distribution.

  Generates all 122,880 tiles (30 faces x 64x64 grid) on startup.
  """

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT
  alias Spheric.Game.{WorldStore, AlteredItems}

  @default_seed 42
  @default_subdivisions 64
  @cells_per_axis 4
  @resource_amount_range 100..500

  # Vein clustering parameters
  # How many vein centers to seed per face (average)
  @veins_per_face 12
  # Vein radius in tile units — tiles within this radius have high spawn chance
  @vein_radius 6.0
  # Probability at vein center (falls off with distance)
  @vein_center_prob 0.65
  # Background chance for tiles far from any vein (sparse lone deposits)
  @vein_background_prob 0.008

  # ── Public accessors for supply analysis scripts ──

  @doc "Returns the resource amount range for deposits."
  def resource_amount_range, do: @resource_amount_range

  @doc "Returns the default subdivisions per face axis."
  def subdivisions, do: @default_subdivisions

  @doc "Returns biome density multipliers as a map."
  def biome_density_multipliers do
    %{volcanic: 1.0, desert: 0.9, grassland: 0.75, forest: 0.6, tundra: 0.5}
  end

  @doc "Returns biome resource weights as a map of biome => [{resource, weight}]."
  def biome_resource_weights do
    %{
      volcanic: resource_weights(:volcanic),
      desert: resource_weights(:desert),
      grassland: resource_weights(:grassland),
      forest: resource_weights(:forest),
      tundra: resource_weights(:tundra)
    }
  end

  @doc """
  Generate terrain for all tiles and insert into ETS.

  Options:
  - `:seed` — RNG seed (default: #{@default_seed})
  - `:subdivisions` — grid size per face (default: #{@default_subdivisions})
  """
  def generate(opts \\ []) do
    seed = Keyword.get(opts, :seed, @default_seed)

    subdivisions =
      Keyword.get(
        opts,
        :subdivisions,
        Application.get_env(:spheric, :subdivisions, @default_subdivisions)
      )

    tiles_per_cell = div(subdivisions, @cells_per_axis)

    # Precompute face edge vectors for cell center computation
    verts = RT.vertices()

    # Seed the RNG and get the state
    rng = :rand.seed_s(:exsss, {seed, seed * 7, seed * 13})

    {tiles, rng} =
      Enum.reduce(0..29, {[], rng}, fn face_id, {acc, rng} ->
        # Precompute biomes for each of the 4x4 cells on this face
        cell_biomes = compute_cell_biomes(face_id, verts)

        # Seed vein centers for this face
        {veins, rng} = seed_veins(rng, cell_biomes, subdivisions)

        {face_tiles, rng} =
          Enum.reduce(0..(subdivisions - 1), {[], rng}, fn row, {acc, rng} ->
            {row_tiles, rng} =
              Enum.reduce(0..(subdivisions - 1), {[], rng}, fn col, {acc, rng} ->
                cell_row = div(row, tiles_per_cell)
                cell_col = div(col, tiles_per_cell)
                biome = Map.get(cell_biomes, {cell_row, cell_col})

                {resource, rng} = maybe_place_resource_clustered(rng, biome, row, col, veins)
                tile = {{face_id, row, col}, %{terrain: biome, resource: resource}}
                {[tile | acc], rng}
              end)

            {row_tiles ++ acc, rng}
          end)

        {face_tiles ++ acc, rng}
      end)

    WorldStore.put_tiles(tiles)

    # Place Altered Items (~0.1% of tiles)
    {altered_count, _rng} = AlteredItems.generate(rng, subdivisions)

    require Logger
    Logger.info("World gen: #{length(tiles)} tiles, #{altered_count} altered items")

    length(tiles)
  end

  # Compute biome for each of the 4x4 cells on a face,
  # based on the cell center's position on the sphere.
  defp compute_cell_biomes(face_id, verts) do
    [ai, bi, _ci, di] = Enum.at(RT.faces(), face_id)
    {ax, ay, az} = Enum.at(verts, ai)
    {bx, by, bz} = Enum.at(verts, bi)
    {dx, dy, dz} = Enum.at(verts, di)

    # e1 = v1 - v0 (col axis), e2 = v3 - v0 (row axis)
    e1 = {bx - ax, by - ay, bz - az}
    e2 = {dx - ax, dy - ay, dz - az}

    for cr <- 0..(@cells_per_axis - 1),
        cc <- 0..(@cells_per_axis - 1),
        into: %{} do
      # Cell center in parametric space
      u = (cc + 0.5) / @cells_per_axis
      v = (cr + 0.5) / @cells_per_axis

      x = ax + u * elem(e1, 0) + v * elem(e2, 0)
      y = ay + u * elem(e1, 1) + v * elem(e2, 1)
      z = az + u * elem(e1, 2) + v * elem(e2, 2)

      center = RT.normalize({x, y, z})
      {{cr, cc}, biome_for_center(center)}
    end
  end

  @doc "Determine biome based on face center's Y coordinate (latitude proxy)."
  def biome_for_center({_x, y, _z}) do
    # Normalize Y to the range of the rhombic triacontahedron vertices
    # Y values range roughly from -C2 to +C2 (~1.309)
    lat = y / 1.309

    cond do
      lat > 0.6 -> :tundra
      lat > 0.2 -> :forest
      lat > -0.2 -> :grassland
      lat > -0.6 -> :desert
      true -> :volcanic
    end
  end

  # Seed vein centers across the face. Each vein has a position (row, col),
  # resource type, and radius. Veins cluster resources into natural deposits.
  defp seed_veins(rng, cell_biomes, subdivisions) do
    # Scale vein count with face size, apply biome density multipliers
    base_count = @veins_per_face
    tiles_per_cell = div(subdivisions, @cells_per_axis)

    {veins, rng} =
      Enum.reduce(1..base_count, {[], rng}, fn _i, {veins, rng} ->
        # Random position on the face
        {row_f, rng} = :rand.uniform_s(rng)
        {col_f, rng} = :rand.uniform_s(rng)
        vein_row = row_f * subdivisions
        vein_col = col_f * subdivisions

        # Determine biome at this vein center
        cell_row = min(div(trunc(vein_row), tiles_per_cell), @cells_per_axis - 1)
        cell_col = min(div(trunc(vein_col), tiles_per_cell), @cells_per_axis - 1)
        biome = Map.get(cell_biomes, {cell_row, cell_col})

        # Biome density affects whether this vein spawns at all
        density_mult = biome_density_multiplier(biome)
        {spawn_roll, rng} = :rand.uniform_s(rng)

        if spawn_roll < density_mult do
          # Pick a resource type weighted by biome
          {resource_type, rng} = pick_resource_type(rng, biome)

          # Vary radius slightly per vein
          {radius_roll, rng} = :rand.uniform_s(rng)
          radius = @vein_radius * (0.6 + radius_roll * 0.8)

          vein = %{row: vein_row, col: vein_col, type: resource_type, radius: radius}
          {[vein | veins], rng}
        else
          {veins, rng}
        end
      end)

    {veins, rng}
  end

  defp biome_density_multiplier(:volcanic), do: 1.0
  defp biome_density_multiplier(:desert), do: 0.9
  defp biome_density_multiplier(:grassland), do: 0.75
  defp biome_density_multiplier(:forest), do: 0.6
  defp biome_density_multiplier(:tundra), do: 0.5

  # Place resources based on proximity to vein centers.
  # Close to a vein = high chance of that vein's resource type.
  # Far from all veins = very small background chance.
  defp maybe_place_resource_clustered(rng, biome, row, col, veins) do
    {roll, rng} = :rand.uniform_s(rng)

    # Find the closest vein and compute spawn probability
    case closest_vein(row, col, veins) do
      {vein, dist} when dist < vein.radius ->
        # Quadratic falloff: probability decreases with distance squared
        t = dist / vein.radius
        prob = @vein_center_prob * (1.0 - t * t)

        if roll < prob do
          {amount, rng} = random_amount(rng)
          {{vein.type, amount}, rng}
        else
          {nil, rng}
        end

      _ ->
        # Far from any vein — small background chance with biome-weighted type
        if roll < @vein_background_prob do
          {resource_type, rng} = pick_resource_type(rng, biome)
          {amount, rng} = random_amount(rng)
          {{resource_type, amount}, rng}
        else
          {nil, rng}
        end
    end
  end

  defp closest_vein(_row, _col, []), do: nil

  defp closest_vein(row, col, veins) do
    Enum.min_by(veins, fn vein ->
      dr = row - vein.row
      dc = col - vein.col
      dr * dr + dc * dc
    end)
    |> then(fn vein ->
      dr = row - vein.row
      dc = col - vein.col
      {vein, :math.sqrt(dr * dr + dc * dc)}
    end)
  end


  defp pick_resource_type(rng, biome) do
    {roll, rng} = :rand.uniform_s(rng)
    weights = resource_weights(biome)
    type = pick_weighted(roll, weights)
    {type, rng}
  end

  # Biome-specific resource distribution weights (must sum to 1.0)
  defp resource_weights(:volcanic),
    do: [
      {:iron, 0.23},
      {:copper, 0.10},
      {:titanium, 0.23},
      {:sulfur, 0.18},
      {:oil, 0.09},
      {:quartz, 0.10},
      {:uranium, 0.07}
    ]

  defp resource_weights(:desert),
    do: [
      {:iron, 0.25},
      {:copper, 0.15},
      {:oil, 0.25},
      {:sulfur, 0.15},
      {:titanium, 0.10},
      {:quartz, 0.10}
    ]

  defp resource_weights(:grassland),
    do: [
      {:iron, 0.25},
      {:copper, 0.25},
      {:quartz, 0.15},
      {:titanium, 0.10},
      {:oil, 0.15},
      {:sulfur, 0.10}
    ]

  defp resource_weights(:forest),
    do: [
      {:copper, 0.25},
      {:quartz, 0.25},
      {:iron, 0.15},
      {:titanium, 0.10},
      {:oil, 0.10},
      {:sulfur, 0.15}
    ]

  defp resource_weights(:tundra),
    do: [
      {:quartz, 0.28},
      {:copper, 0.26},
      {:iron, 0.12},
      {:titanium, 0.13},
      {:oil, 0.06},
      {:sulfur, 0.8},
      {:ice, 0.07}
    ]

  defp pick_weighted(_roll, [{type, _weight}]), do: type

  defp pick_weighted(roll, [{type, weight} | rest]) do
    if roll < weight, do: type, else: pick_weighted(roll - weight, rest)
  end

  defp random_amount(rng) do
    {roll, rng} = :rand.uniform_s(rng)
    min = Enum.min(@resource_amount_range)
    max = Enum.max(@resource_amount_range)
    amount = min + round(roll * (max - min))
    {amount, rng}
  end
end
