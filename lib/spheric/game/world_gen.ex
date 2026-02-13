defmodule Spheric.Game.WorldGen do
  @moduledoc """
  Procedural terrain generation for the spherical world.

  Uses seeded RNG for reproducibility. Terrain biomes are assigned based on
  face center latitude (Y component). Resource deposits (iron, copper) are
  placed randomly with configurable density.

  Generates all 7,680 tiles (30 faces x 16x16 grid) on startup.
  """

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT
  alias Spheric.Game.WorldStore

  @default_seed 42
  @default_subdivisions 16
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
    subdivisions = Keyword.get(opts, :subdivisions, Application.get_env(:spheric, :subdivisions, @default_subdivisions))

    face_centers = RT.face_centers()

    # Seed the RNG and get the state
    rng = :rand.seed_s(:exsss, {seed, seed * 7, seed * 13})

    {tiles, _rng} =
      Enum.reduce(0..29, {[], rng}, fn face_id, {acc, rng} ->
        center = Enum.at(face_centers, face_id)
        biome = biome_for_center(center)

        {face_tiles, rng} =
          Enum.reduce(0..(subdivisions - 1), {[], rng}, fn row, {acc, rng} ->
            {row_tiles, rng} =
              Enum.reduce(0..(subdivisions - 1), {[], rng}, fn col, {acc, rng} ->
                {resource, rng} = maybe_place_resource(rng, biome)
                tile = {{face_id, row, col}, %{terrain: biome, resource: resource}}
                {[tile | acc], rng}
              end)

            {row_tiles ++ acc, rng}
          end)

        {face_tiles ++ acc, rng}
      end)

    WorldStore.put_tiles(tiles)
    length(tiles)
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

    # Volcanic/desert biomes favor iron, forest/tundra favor copper
    iron_weight =
      case biome do
        :volcanic -> 0.7
        :desert -> 0.6
        :grassland -> 0.5
        :forest -> 0.4
        :tundra -> 0.3
      end

    type = if roll < iron_weight, do: :iron, else: :copper
    {type, rng}
  end

  defp random_amount(rng) do
    {roll, rng} = :rand.uniform_s(rng)
    min = Enum.min(@resource_amount_range)
    max = Enum.max(@resource_amount_range)
    amount = min + round(roll * (max - min))
    {amount, rng}
  end
end
