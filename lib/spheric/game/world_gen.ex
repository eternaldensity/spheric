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
  @resource_density 0.08
  @resource_amount_range 100..500

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

        {face_tiles, rng} =
          Enum.reduce(0..(subdivisions - 1), {[], rng}, fn row, {acc, rng} ->
            {row_tiles, rng} =
              Enum.reduce(0..(subdivisions - 1), {[], rng}, fn col, {acc, rng} ->
                cell_row = div(row, tiles_per_cell)
                cell_col = div(col, tiles_per_cell)
                biome = Map.get(cell_biomes, {cell_row, cell_col})

                {resource, rng} = maybe_place_resource(rng, biome)
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

  defp maybe_place_resource(rng, biome) do
    {roll, rng} = :rand.uniform_s(rng)

    density = resource_density_for_biome(biome)

    if roll < density do
      {resource_type, rng} = pick_resource_type(rng, biome)
      {amount, rng} = random_amount(rng)
      {{resource_type, amount}, rng}
    else
      {nil, rng}
    end
  end

  defp resource_density_for_biome(:volcanic), do: @resource_density * 1.5
  defp resource_density_for_biome(:desert), do: @resource_density * 1.2
  defp resource_density_for_biome(:grassland), do: @resource_density
  defp resource_density_for_biome(:forest), do: @resource_density * 0.8
  defp resource_density_for_biome(:tundra), do: @resource_density * 0.6

  defp pick_resource_type(rng, biome) do
    {roll, rng} = :rand.uniform_s(rng)
    weights = resource_weights(biome)
    type = pick_weighted(roll, weights)
    {type, rng}
  end

  # Biome-specific resource distribution weights (must sum to 1.0)
  defp resource_weights(:volcanic),
    do: [
      {:iron, 0.30},
      {:copper, 0.10},
      {:titanium, 0.25},
      {:sulfur, 0.20},
      {:oil, 0.05},
      {:quartz, 0.10}
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
      {:quartz, 0.30},
      {:copper, 0.25},
      {:iron, 0.15},
      {:titanium, 0.15},
      {:oil, 0.05},
      {:sulfur, 0.10}
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
