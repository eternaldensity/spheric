defmodule Spheric.Game.WorldGenTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.{WorldStore, WorldGen}

  # WorldServer already ran WorldGen.generate at startup, so the ETS tables
  # contain the default world data. These tests verify the generated state
  # and test WorldGen functions directly.

  describe "generated world (from startup)" do
    test "7,680 tiles exist (30 faces x 16x16)" do
      assert WorldStore.tile_count() >= 7_680
    end

    test "every tile has a valid terrain type" do
      for face_id <- 0..29, row <- 0..15, col <- 0..15 do
        tile = WorldStore.get_tile({face_id, row, col})
        assert tile != nil, "Missing tile at {#{face_id}, #{row}, #{col}}"
        assert tile.terrain in [:grassland, :desert, :tundra, :forest, :volcanic]
      end
    end

    test "resources are nil or {type, amount}" do
      for face_id <- 0..29, row <- 0..15, col <- 0..15 do
        tile = WorldStore.get_tile({face_id, row, col})

        case tile.resource do
          nil -> :ok
          {type, amount} ->
            assert type in [:iron, :copper]
            assert is_integer(amount)
            assert amount >= 100 and amount <= 500
        end
      end
    end

    test "some tiles have resources" do
      resource_count =
        Enum.count(0..29, fn face_id ->
          Enum.any?(0..15, fn row ->
            Enum.any?(0..15, fn col ->
              tile = WorldStore.get_tile({face_id, row, col})
              tile.resource != nil
            end)
          end)
        end)

      assert resource_count > 0, "Expected some faces to have resource tiles"
    end
  end

  describe "generate/1 determinism" do
    test "same seed produces identical results" do
      WorldGen.generate(seed: 123, subdivisions: 4)
      tiles1 = for f <- 0..29, r <- 0..3, c <- 0..3, do: WorldStore.get_tile({f, r, c})

      # Regenerate with same seed
      WorldGen.generate(seed: 123, subdivisions: 4)
      tiles2 = for f <- 0..29, r <- 0..3, c <- 0..3, do: WorldStore.get_tile({f, r, c})

      assert tiles1 == tiles2

      # Restore default world
      WorldGen.generate(seed: 42, subdivisions: 16)
    end

    test "different seeds produce different results" do
      WorldGen.generate(seed: 1, subdivisions: 4)
      tiles1 = for f <- 0..29, r <- 0..3, c <- 0..3, do: WorldStore.get_tile({f, r, c})

      WorldGen.generate(seed: 999, subdivisions: 4)
      tiles2 = for f <- 0..29, r <- 0..3, c <- 0..3, do: WorldStore.get_tile({f, r, c})

      refute tiles1 == tiles2

      # Restore default world
      WorldGen.generate(seed: 42, subdivisions: 16)
    end
  end

  describe "biome_for_center/1" do
    test "high Y is tundra" do
      assert WorldGen.biome_for_center({0.0, 1.0, 0.0}) == :tundra
    end

    test "mid-high Y is forest" do
      assert WorldGen.biome_for_center({0.0, 0.5, 0.0}) == :forest
    end

    test "near-zero Y is grassland" do
      assert WorldGen.biome_for_center({0.5, 0.0, 0.5}) == :grassland
    end

    test "mid-low Y is desert" do
      assert WorldGen.biome_for_center({0.0, -0.5, 0.0}) == :desert
    end

    test "low Y is volcanic" do
      assert WorldGen.biome_for_center({0.0, -1.0, 0.0}) == :volcanic
    end
  end
end
